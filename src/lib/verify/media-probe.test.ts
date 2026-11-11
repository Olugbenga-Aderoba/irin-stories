import { execFileSync } from "node:child_process";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import ffmpeg from "@ffmpeg-installer/ffmpeg";
import { extractAudioForLanguageDetection, probeMediaFile, validateAudioTrack, validateSpeechActivity, withTemporaryAudioSample } from "./media-probe";

const directories: string[] = [];

afterEach(async () => {
  await Promise.all(directories.splice(0).map((directory) => rm(directory, { recursive: true, force: true })));
});

describe("trusted source media probe", () => {
  it("derives video/audio metadata, decodes its audio, and extracts only a temporary audio sample", async () => {
    const directory = await mkdtemp(join(tmpdir(), "irin-verify-test-"));
    directories.push(directory);
    const videoPath = join(directory, "synthetic-tone.webm");
    const variableVideoPath = join(directory, "synthetic-variable-audio.webm");
    let temporaryAudioPath = "";
    // Harmless synthetic tone and color frames; no storyteller content or spoken words.
    execFileSync(ffmpeg.path, [
      "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
      "-f", "lavfi", "-i", "color=c=black:s=64x64:r=10",
      "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=16000",
      "-t", "2", "-c:v", "libvpx", "-deadline", "realtime", "-c:a", "libopus", videoPath,
    ], { stdio: "pipe", windowsHide: true });

    const probe = await probeMediaFile(videoPath);
    expect(probe).toMatchObject({ hasVideo: true, hasAudio: true, audioCodec: "opus", videoCodec: "vp8" });
    expect(probe.durationMs).toBeGreaterThan(0);
    expect(probe.width).toBe(64);
    expect(probe.height).toBe(64);
    await validateAudioTrack(videoPath);
    const toneSamplePath = join(directory, "tone-sample.wav");
    await extractAudioForLanguageDetection(videoPath, toneSamplePath);
    await expect(validateSpeechActivity(toneSamplePath)).rejects.toThrow(/silence or a steady tone/);
    execFileSync(ffmpeg.path, [
      "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
      "-f", "lavfi", "-i", "color=c=black:s=64x64:r=10",
      "-f", "lavfi", "-i", "anoisesrc=color=pink:amplitude=0.2:sample_rate=16000",
      "-t", "2", "-c:v", "libvpx", "-deadline", "realtime", "-c:a", "libopus", variableVideoPath,
    ], { stdio: "pipe", windowsHide: true });
    await expect(withTemporaryAudioSample(variableVideoPath, async (audioPath) => {
      temporaryAudioPath = audioPath;
      expect((await stat(audioPath)).size).toBeGreaterThan(44);
      throw new Error("mock provider failure after reading sample");
    })).rejects.toThrow("mock provider failure after reading sample");
    await expect(stat(temporaryAudioPath)).rejects.toMatchObject({ code: "ENOENT" });
  }, 60_000);
});
