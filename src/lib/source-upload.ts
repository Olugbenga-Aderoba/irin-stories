export const MAX_SOURCE_BYTES = 500 * 1024 * 1024;

const MIME_BY_EXTENSION: Record<string, string> = {
  mp4: "video/mp4",
  mov: "video/quicktime",
  webm: "video/webm",
};

export function getVideoMime(filename: string, browserMime: string) {
  const extension = filename.toLowerCase().split(".").pop() ?? "";
  const expected = MIME_BY_EXTENSION[extension];
  if (!expected || (browserMime && browserMime !== expected)) return null;
  return expected;
}

export function validateSourceVideo(file: Pick<File, "name" | "type" | "size">) {
  if (file.size <= 0) return "Choose a video file that is not empty.";
  if (file.size > MAX_SOURCE_BYTES) return "The maximum video size is 500 MB.";
  if (!getVideoMime(file.name, file.type)) return "Choose an MP4, MOV, or WebM video.";
  return null;
}

export function sanitizeFilename(filename: string) {
  const base = filename.split(/[\\/]/).pop()?.normalize("NFKC") ?? "source-video";
  const safe = base.replace(/[^\p{L}\p{N}._-]+/gu, "-").replace(/^-+|-+$/g, "").slice(0, 180);
  return safe || "source-video";
}

export function sourceObjectKey(ownerId: string, storyId: string, mediaId: string, filename: string) {
  return `${ownerId}/${storyId}/${mediaId}/${sanitizeFilename(filename)}`;
}

export function durationGuidance(durationMs: number) {
  return durationMs >= 5 * 60_000 && durationMs <= 15 * 60_000
    ? "Within the recommended 5–15 minute range."
    : "The recommended source duration is 5–15 minutes. This is guidance, not a limit.";
}
