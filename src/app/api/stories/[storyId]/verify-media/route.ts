import { createHash } from "node:crypto";
import { createWriteStream } from "node:fs";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Transform, Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { NextResponse, type NextRequest } from "next/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { probeMediaFile, validateAudioTrack, MediaProbeError } from "@/lib/verify/media-probe";

export const maxDuration = 900;

const MAX_SOURCE_BYTES = 524_288_000;

function mimeMatchesContainer(mimeType: string, formatNames: string) {
  const formats = formatNames.toLowerCase().split(",");
  if (mimeType === "video/mp4") return formats.includes("mp4") || formats.includes("mov");
  if (mimeType === "video/quicktime") return formats.includes("mov");
  if (mimeType === "video/webm") return formats.includes("matroska,webm") || formats.includes("webm");
  return false;
}

export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string }> }) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) {
    return NextResponse.json({ error: "Request origin was not accepted." }, { status: 403 });
  }

  const { storyId } = await context.params;
  if (!/^[0-9a-f-]{36}$/i.test(storyId)) {
    return NextResponse.json({ error: "Story not found." }, { status: 404 });
  }

  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in to verify this source." }, { status: 401 });

  const { data: story } = await supabase.from("stories").select("id,owner_id").eq("id", storyId).maybeSingle();
  if (!story || story.owner_id !== user.id) return NextResponse.json({ error: "Story not found." }, { status: 404 });

  const { data: media } = await supabase.from("media_assets")
    .select("artifact_version_id,object_key,bucket_id,mime_type,byte_size,duration_ms,content_sha256,original_filename")
    .eq("story_id", storyId)
    .eq("role", "SOURCE")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!media || media.bucket_id !== "private-source") {
    return NextResponse.json({ error: "No registered private source video is available." }, { status: 404 });
  }

  const { data: signed, error: signError } = await supabase.storage
    .from("private-source")
    .createSignedUrl(media.object_key, 300);
  if (signError || !signed) {
    return NextResponse.json({ error: "The owner-authorized source could not be retrieved. Please retry." }, { status: 503 });
  }

  let tempDirectory: string | undefined;
  try {
    const response = await fetch(signed.signedUrl, { cache: "no-store", signal: AbortSignal.timeout(15 * 60_000) });
    if (!response.ok || !response.body) {
      return NextResponse.json({ error: "The private source download failed. Please retry." }, { status: 503 });
    }
    const declaredLength = Number(response.headers.get("content-length"));
    if (Number.isFinite(declaredLength) && declaredLength > MAX_SOURCE_BYTES) {
      return NextResponse.json({ error: "The source exceeds the 500 MiB media-verification limit." }, { status: 413 });
    }

    tempDirectory = await mkdtemp(join(tmpdir(), "irin-verify-"));
    const localPath = join(tempDirectory, "source-video");
    const hash = createHash("sha256");
    let downloadedBytes = 0;
    const limiter = new Transform({
      transform(chunk: Buffer, _encoding, callback) {
        downloadedBytes += chunk.byteLength;
        if (downloadedBytes > MAX_SOURCE_BYTES) {
          callback(new Error("source exceeds maximum"));
          return;
        }
        hash.update(chunk);
        callback(null, chunk);
      },
    });
    try {
      await pipeline(
        Readable.fromWeb(response.body as unknown as Parameters<typeof Readable.fromWeb>[0]),
        limiter,
        createWriteStream(localPath, { flags: "wx" }),
      );
    } catch {
      return NextResponse.json({ error: "The private source could not be downloaded completely. Please retry." }, { status: 413 });
    }

    const [probe, measuredBytes] = await Promise.all([
      probeMediaFile(localPath),
      stat(localPath).then((file) => file.size),
    ]);
    const serverHash = hash.digest("hex");
    if (measuredBytes !== downloadedBytes || !serverHash) {
      return NextResponse.json({ error: "The source integrity check did not complete. Please retry." }, { status: 503 });
    }

    const reportedHash = typeof media.content_sha256 === "string"
      ? media.content_sha256.replace(/^\\x/i, "")
      : "";
    const mismatches: Array<{ field: string; reported: string; verified: string }> = [];
    if (Math.abs(probe.durationMs - media.duration_ms) > 1_000) {
      mismatches.push({ field: "duration_ms", reported: String(media.duration_ms), verified: String(probe.durationMs) });
    }
    if (measuredBytes !== media.byte_size) {
      mismatches.push({ field: "byte_size", reported: String(media.byte_size), verified: String(measuredBytes) });
    }
    if (!reportedHash || serverHash.toLowerCase() !== reportedHash.toLowerCase()) {
      mismatches.push({ field: "content_sha256", reported: "client digest differs", verified: "server digest differs" });
    }
    if (!mimeMatchesContainer(media.mime_type, probe.formatNames)) {
      mismatches.push({ field: "container", reported: media.mime_type, verified: probe.formatNames });
    }

    let audioDecodes = false;
    if (probe.hasAudio && probe.audioCodec) {
      try {
        await validateAudioTrack(localPath);
        audioDecodes = true;
      } catch (error) {
        if (error instanceof MediaProbeError && error.retryable) throw error;
      }
    }
    const usable = probe.hasVideo && probe.hasAudio && Boolean(probe.audioCodec) && audioDecodes;
    const status = usable ? "READY" : "REJECTED";
    const admin = createSupabaseAdminClient();
    const { data: verificationId, error: recordError } = await admin.rpc("record_source_media_verification", {
      p_story_id: storyId,
      p_source_media_artifact_id: media.artifact_version_id,
      p_status: status,
      p_actual_container: probe.container,
      p_actual_format_names: probe.formatNames,
      p_actual_duration_ms: probe.durationMs,
      p_has_video: probe.hasVideo,
      p_has_audio: probe.hasAudio,
      p_audio_codec: probe.audioCodec,
      p_video_codec: probe.videoCodec,
      p_video_width: probe.width,
      p_video_height: probe.height,
      p_server_content_sha256: `\\x${serverHash}`,
      p_client_metadata_mismatches: mismatches,
      p_probe_name: "ffprobe",
      p_probe_version: "4.0.2",
      p_requested_by: user.id,
    });
    if (recordError || !verificationId) {
      return NextResponse.json({ error: "Verified media metadata could not be saved. Please retry." }, { status: 503 });
    }

    return NextResponse.json({
      verificationId,
      sourceMediaArtifactId: media.artifact_version_id,
      status,
      actual: {
        container: probe.container,
        formatNames: probe.formatNames,
        durationMs: probe.durationMs,
        hasVideo: probe.hasVideo,
        hasAudio: probe.hasAudio,
        audioDecodes,
        audioCodec: probe.audioCodec,
        videoCodec: probe.videoCodec,
        width: probe.width,
        height: probe.height,
        byteSize: measuredBytes,
      },
      mismatches,
      message: usable
        ? "Source media has verified video and audio. Review any metadata differences before continuing."
        : "This source does not contain usable video and audio streams for the next stage. Choose another video.",
    }, { status: usable ? 200 : 422, headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    if (error instanceof Error && error.name === "MediaProbeError") {
      const retryable = error instanceof MediaProbeError && error.retryable;
      return NextResponse.json({ error: retryable
        ? "Media verification is temporarily unavailable. Your source remains private; please retry."
        : "The media could not be verified. Please choose another video." }, { status: retryable ? 503 : 422 });
    }
    return NextResponse.json({ error: "Media verification could not complete. Your source remains private; please retry." }, { status: 503 });
  } finally {
    if (tempDirectory) await rm(tempDirectory, { recursive: true, force: true });
  }
}
