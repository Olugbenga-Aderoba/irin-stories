import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { spawn } from "node:child_process";
import { createRequire } from "node:module";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { z } from "zod";

const requireFromHere = createRequire(import.meta.url);

const ffprobe = z.object({
  streams: z.array(z.object({
    codec_type: z.string().optional(),
    codec_name: z.string().optional(),
    width: z.number().int().positive().optional(),
    height: z.number().int().positive().optional(),
    duration: z.string().optional(),
  }).passthrough()),
  format: z.object({
    format_name: z.string().min(1),
    duration: z.string().optional(),
  }).passthrough(),
});

export type ProbedMedia = {
  container: string;
  formatNames: string;
  durationMs: number;
  hasVideo: boolean;
  hasAudio: boolean;
  audioCodec: string | null;
  videoCodec: string | null;
  width: number | null;
  height: number | null;
};

export class MediaProbeError extends Error {
  constructor(message: string, readonly retryable = false) {
    super(message);
    this.name = "MediaProbeError";
  }
}

export class SpeechActivityError extends MediaProbeError {}

function getFfprobePath() {
  const configured = process.env.FFPROBE_PATH;
  if (configured) return configured;
  const ffprobe = requireFromHere("ffprobe-static") as { path?: string };
  if (!ffprobe.path) throw new MediaProbeError("FFprobe is unavailable on this server. Please retry later.", true);
  return ffprobe.path;
}

function getFfmpegPath() {
  if (process.env.FFMPEG_PATH) return process.env.FFMPEG_PATH;
  const ffmpeg = requireFromHere("@ffmpeg-installer/ffmpeg") as { path?: string };
  if (!ffmpeg.path) throw new MediaProbeError("FFmpeg is unavailable on this server. Please retry later.", true);
  return ffmpeg.path;
}

async function runFfmpeg(args: string[], timeoutMs: number, limitBytes = 256_000) {
  const binary = getFfmpegPath();
  await new Promise<void>((resolve, reject) => {
    const child = spawn(binary, args, { windowsHide: true, stdio: ["ignore", "ignore", "pipe"] });
    let stderr = "";
    const timeout = setTimeout(() => child.kill(), timeoutMs);
    child.stderr.setEncoding("utf8").on("data", (part: string) => {
      stderr += part;
      if (stderr.length > limitBytes) child.kill();
    });
    child.once("error", () => {
      clearTimeout(timeout);
      reject(new MediaProbeError("FFmpeg could not start on this server. Please retry later.", true));
    });
    child.once("close", (code) => {
      clearTimeout(timeout);
      if (code !== 0) reject(new MediaProbeError("FFmpeg could not decode the source audio. Please choose another video or retry."));
      else resolve();
    });
  });
}

export async function validateAudioTrack(path: string) {
  await runFfmpeg([
    "-nostdin", "-hide_banner", "-v", "error", "-i", path,
    "-map", "0:a:0", "-vn", "-f", "null", "-",
  ], 15 * 60_000);
}

export async function extractAudioForLanguageDetection(videoPath: string, audioPath: string) {
  await runFfmpeg([
    "-nostdin", "-hide_banner", "-v", "error", "-i", videoPath,
    "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "16000", "-t", "90",
    "-c:a", "pcm_s16le", "-f", "wav", audioPath,
  ], 3 * 60_000);
  const info = await stat(audioPath);
  if (info.size <= 44) {
    throw new MediaProbeError("No usable audio samples were found. Please choose another video.");
  }
}

export async function extractAudioForTranscription(videoPath: string, audioPath: string) {
  await runFfmpeg([
    "-nostdin", "-hide_banner", "-v", "error", "-i", videoPath,
    "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "16000", "-c:a", "flac", "-compression_level", "5", "-f", "flac", audioPath,
  ], 15 * 60_000);
  const info = await stat(audioPath);
  if (info.size <= 42) throw new MediaProbeError("No usable audio samples were found. Please choose another video.");
  if (info.size > 25 * 1024 * 1024) throw new MediaProbeError("The prepared audio exceeds the provider file-size limit.");
}

export async function validateSpeechActivity(audioPath: string) {
  const bytes = await readFile(audioPath);
  if (bytes.toString("ascii", 0, 4) !== "RIFF" || bytes.toString("ascii", 8, 12) !== "WAVE") {
    throw new MediaProbeError("The prepared audio sample is not a valid WAV file.");
  }

  let channels = 0;
  let sampleRate = 0;
  let bitsPerSample = 0;
  let dataOffset = -1;
  let dataSize = 0;
  for (let offset = 12; offset + 8 <= bytes.length;) {
    const id = bytes.toString("ascii", offset, offset + 4);
    const size = bytes.readUInt32LE(offset + 4);
    if (offset + 8 + size > bytes.length) break;
    if (id === "fmt " && size >= 16) {
      const audioFormat = bytes.readUInt16LE(offset + 8);
      channels = bytes.readUInt16LE(offset + 10);
      sampleRate = bytes.readUInt32LE(offset + 12);
      bitsPerSample = bytes.readUInt16LE(offset + 22);
      if (audioFormat !== 1) throw new MediaProbeError("Speech activity requires normalized PCM audio.");
    }
    if (id === "data") {
      dataOffset = offset + 8;
      dataSize = size;
      break;
    }
    offset += 8 + size + (size % 2);
  }
  if (channels !== 1 || sampleRate !== 16_000 || bitsPerSample !== 16 || dataOffset < 0) {
    throw new MediaProbeError("The prepared audio sample format could not be verified.");
  }

  const frameSamples = 320; // 20 ms at 16 kHz
  const totalSamples = Math.floor(dataSize / 2);
  const energy: number[] = [];
  const zeroCrossingRates: number[] = [];
  for (let start = 0; start + frameSamples <= totalSamples; start += frameSamples) {
    let sumSquares = 0;
    let crossings = 0;
    let previous = bytes.readInt16LE(dataOffset + start * 2);
    for (let index = 0; index < frameSamples; index++) {
      const sample = bytes.readInt16LE(dataOffset + (start + index) * 2);
      sumSquares += sample * sample;
      if ((sample < 0) !== (previous < 0)) crossings++;
      previous = sample;
    }
    const rms = Math.sqrt(sumSquares / frameSamples);
    if (rms >= 400) {
      energy.push(rms);
      zeroCrossingRates.push(crossings / frameSamples);
    }
  }
  if (energy.length < 15) {
    throw new SpeechActivityError("Speech activity could not be established in this sample. Choose a clearer recording and retry.", true);
  }

  const averageEnergy = energy.reduce((sum, value) => sum + value, 0) / energy.length;
  const energyVariation = Math.sqrt(energy.reduce((sum, value) => sum + (value - averageEnergy) ** 2, 0) / energy.length) / averageEnergy;
  const zcrRange = Math.max(...zeroCrossingRates) - Math.min(...zeroCrossingRates);
  if (energyVariation < 0.08 && zcrRange < 0.015) {
    throw new SpeechActivityError("The sample has no speech-like variation; silence or a steady tone cannot be used for language identification.", true);
  }
}

export class TemporaryMediaCleanupError extends Error {}

export async function withTemporaryMediaDirectory<T>(prefix: string, consume: (directory: string) => Promise<T>): Promise<T> {
  const directory = await mkdtemp(join(tmpdir(), prefix));
  let completed = false;
  try {
    const result = await consume(directory);
    completed = true;
    return result;
  } finally {
    try {
      await rm(directory, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 });
    } catch {
      // A removal failure must not replace the original processing failure.
      if (completed) throw new TemporaryMediaCleanupError();
    }
  }
}

export async function withTemporaryAudioSample<T>(
  videoPath: string,
  consumeSample: (audioPath: string) => Promise<T>,
  beforeSpeechValidation?: () => void,
): Promise<T> {
  return withTemporaryMediaDirectory("irin-audio-sample-", async (directory) => {
    const audioPath = join(directory, "speech-sample.wav");
    await extractAudioForLanguageDetection(videoPath, audioPath);
    const size = (await stat(audioPath)).size;
    if (size > 25 * 1024 * 1024) {
      throw new MediaProbeError("The prepared speech sample exceeds the provider file-size limit.");
    }
    beforeSpeechValidation?.();
    await validateSpeechActivity(audioPath);
    return consumeSample(audioPath);
  });
}

export async function sha256File(path: string): Promise<string> {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest("hex");
}

export async function probeMediaFile(path: string): Promise<ProbedMedia> {
  const binary = getFfprobePath();
  const result = await new Promise<string>((resolve, reject) => {
    const child = spawn(binary, [
      "-v", "error", "-show_entries",
      "format=format_name,duration:stream=codec_type,codec_name,width,height,duration",
      "-of", "json", path,
    ], { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    const timeout = setTimeout(() => child.kill(), 30_000);
    child.stdout.setEncoding("utf8").on("data", (part: string) => {
      stdout += part;
      if (stdout.length > 256_000) child.kill();
    });
    child.stderr.setEncoding("utf8").on("data", (part: string) => {
      stderr += part;
      if (stderr.length > 16_000) child.kill();
    });
    child.once("error", () => {
      clearTimeout(timeout);
      reject(new MediaProbeError("FFprobe could not start. Please retry after the media worker is available."));
    });
    child.once("close", (code) => {
      clearTimeout(timeout);
      if (code !== 0) reject(new MediaProbeError(stderr.trim()
        ? "FFprobe could not read this source video. Please choose another video or retry."
        : "FFprobe could not read this source video. Please retry."));
      else resolve(stdout);
    });
  });

  let parsed: z.infer<typeof ffprobe>;
  try {
    parsed = ffprobe.parse(JSON.parse(result));
  } catch {
    throw new MediaProbeError("FFprobe returned incomplete media metadata. Please retry or choose another video.");
  }

  const video = parsed.streams.find((stream) => stream.codec_type === "video");
  const audio = parsed.streams.find((stream) => stream.codec_type === "audio");
  const seconds = Number(parsed.format.duration) || Math.max(
    0,
    ...parsed.streams.map((stream) => Number(stream.duration) || 0),
  );
  if (!Number.isFinite(seconds) || seconds <= 0) {
    throw new MediaProbeError("The source duration could not be verified. Please retry or choose another video.");
  }

  return {
    container: parsed.format.format_name.split(",")[0],
    formatNames: parsed.format.format_name,
    durationMs: Math.round(seconds * 1000),
    hasVideo: Boolean(video),
    hasAudio: Boolean(audio),
    audioCodec: audio?.codec_name ?? null,
    videoCodec: video?.codec_name ?? null,
    width: video?.width ?? null,
    height: video?.height ?? null,
  };
}

export async function fileByteSize(path: string) {
  return (await stat(path)).size;
}
