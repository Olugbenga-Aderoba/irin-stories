"use client";

import { useState, type ChangeEvent } from "react";
import * as tus from "tus-js-client";
import { sha256 } from "@noble/hashes/sha2.js";
import { bytesToHex } from "@noble/hashes/utils.js";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";
import { durationGuidance, getVideoMime, sanitizeFilename, sourceObjectKey, validateSourceVideo } from "@/lib/source-upload";

type Props = { storyId: string; existing?: { filename: string; durationMs: number; signedUrl: string } | null };

async function readDuration(file: File): Promise<number> {
  const url = URL.createObjectURL(file);
  try {
    return await new Promise((resolve, reject) => {
      const video = document.createElement("video");
      video.preload = "metadata";
      video.onloadedmetadata = () => {
        const duration = video.duration;
        video.src = "";
        if (!Number.isFinite(duration) || duration <= 0) reject(new Error("Video duration could not be read."));
        else resolve(Math.round(duration * 1000));
      };
      video.onerror = () => reject(new Error("This video could not be opened by your browser."));
      video.src = url;
    });
  } finally {
    URL.revokeObjectURL(url);
  }
}

async function hashFile(file: File) {
  const hasher = sha256.create();
  const reader = file.stream().getReader();
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    hasher.update(value);
  }
  return bytesToHex(hasher.digest());
}

function resumableEndpoint(projectUrl: string) {
  const url = new URL(projectUrl);
  if (url.hostname.endsWith(".supabase.co")) {
    url.hostname = `${url.hostname.replace(/\.supabase\.co$/, "")}.storage.supabase.co`;
  }
  return `${url.origin}/storage/v1/upload/resumable`;
}

export function SourceVideoUploader({ storyId, existing }: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [durationMs, setDurationMs] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState("Choose a video to begin.");
  const [progress, setProgress] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [mediaId, setMediaId] = useState<string | null>(null);

  async function selectFile(event: ChangeEvent<HTMLInputElement>) {
    const selected = event.target.files?.[0] ?? null;
    setFile(null); setDurationMs(null); setError(null); setProgress(null);
    if (!selected) return;
    const validation = validateSourceVideo(selected);
    if (validation) { setError(validation); return; }
    setFile(selected);
    setMediaId(crypto.randomUUID());
    setStatus("Reading video duration…");
    try {
      const duration = await readDuration(selected);
      setDurationMs(duration);
      setStatus(durationGuidance(duration));
    } catch (cause) {
      setFile(null);
      setError(cause instanceof Error ? cause.message : "Video metadata could not be read.");
      setStatus("Choose another video or try again.");
    }
  }

  async function upload() {
    if (!file || !durationMs) return;
    setBusy(true); setError(null); setProgress(null); setStatus("Calculating a source checksum…");
    const supabase = createSupabaseBrowserClient();
    const uploadId = mediaId ?? crypto.randomUUID();
    const filename = sanitizeFilename(file.name);
    const mime = getVideoMime(file.name, file.type);
    let uploadedObjectKey: string | null = null;
    let uploadCompleted = false;
    try {
      const [{ data: { user }, error: userError }, { data: { session }, error: sessionError }, digest] = await Promise.all([
        supabase.auth.getUser(), supabase.auth.getSession(), hashFile(file),
      ]);
      if (userError || sessionError || !user || !session) throw new Error("Your sign-in session expired. Sign in again and retry.");
      if (!mime) throw new Error("Choose an MP4, MOV, or WebM video.");
      const envUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
      if (!envUrl) throw new Error("Supabase is not configured.");
      const objectKey = sourceObjectKey(user.id, storyId, uploadId, filename);
      uploadedObjectKey = objectKey;
      setProgress(0);
      setStatus("Starting private upload…");

      await new Promise<void>((resolve, reject) => {
        const upload = new tus.Upload(file, {
          endpoint: resumableEndpoint(envUrl),
          retryDelays: [0, 3000, 5000, 10000, 20000],
          headers: { authorization: `Bearer ${session.access_token}`, "x-upsert": "false" },
          uploadDataDuringCreation: true,
          removeFingerprintOnSuccess: true,
          chunkSize: 6 * 1024 * 1024,
          metadata: { bucketName: "private-source", objectName: objectKey, contentType: mime, cacheControl: "0" },
          onError: reject,
          onProgress: (uploaded, total) => {
            setProgress(Math.floor(uploaded / total * 100));
            setStatus("Uploading privately…");
          },
          onSuccess: () => { uploadCompleted = true; resolve(); },
        });
        void upload.findPreviousUploads().then((previous) => {
          if (previous.length) upload.resumeFromPreviousUpload(previous[0]);
          upload.start();
        }).catch(reject);
      });

      setStatus("Recording private media metadata…");
      const { error: registerError } = await supabase.rpc("register_source_media", {
        p_story_id: storyId,
        p_artifact_id: uploadId,
        p_object_key: objectKey,
        p_original_filename: file.name.slice(0, 255),
        p_mime_type: mime,
        p_byte_size: file.size,
        p_duration_ms: durationMs,
        p_content_sha256: `\\x${digest}`,
      });
      if (registerError) throw new Error(registerError.message);
      setProgress(100);
      setStatus("Upload complete. Your source video is private to you.");
      window.location.reload();
    } catch (cause) {
      if (uploadCompleted && uploadedObjectKey) {
        const { data: registered } = await supabase.from("media_assets")
          .select("artifact_version_id")
          .eq("story_id", storyId)
          .eq("artifact_version_id", uploadId)
          .maybeSingle();
        if (registered) {
          window.location.reload();
          return;
        }
        await supabase.storage.from("private-source").remove([uploadedObjectKey]);
      }
      setError(cause instanceof Error ? cause.message : "Upload failed. Please retry.");
      setStatus("The upload was not completed. You can retry safely.");
      setProgress(null);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="source-upload-card">
      {existing && <div className="private-video-wrap"><video controls preload="metadata" src={existing.signedUrl} /><p>Private source · {existing.filename} · {Math.round(existing.durationMs / 60_000)} min</p></div>}
      {!existing && <>
        <label className="upload-picker">Choose source video
          <input accept="video/mp4,video/quicktime,video/webm,.mp4,.mov,.webm" disabled={busy} onChange={selectFile} type="file" />
        </label>
        <p className="upload-help">MP4, MOV, or WebM · max 500 MB · recommended 5–15 minutes. Duration guidance does not block upload.</p>
        {file && <p className="selected-file">{file.name} · {(file.size / (1024 * 1024)).toFixed(1)} MB{durationMs ? ` · ${(durationMs / 60_000).toFixed(1)} min` : ""}</p>}
        {file && <button className="button button--primary" disabled={busy || !durationMs} onClick={upload} type="button">{busy ? "Uploading…" : "Upload privately"}</button>}
      </>}
      {progress !== null && <div className="upload-progress" role="progressbar" aria-label="Upload progress" aria-valuemin={0} aria-valuemax={100} aria-valuenow={progress}><span style={{ width: `${progress}%` }} /></div>}
      <p aria-live="polite" className="upload-status">{existing
        ? "Your private source video is ready. Continue to Verify to check the media and detect its original language."
        : status}</p>
      {error && <p className="form-error" role="alert">{error}</p>}
    </div>
  );
}
