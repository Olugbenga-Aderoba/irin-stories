import { describe, expect, it } from "vitest";
import { durationGuidance, getVideoMime, MAX_SOURCE_BYTES, sanitizeFilename, sourceObjectKey, validateSourceVideo } from "@/lib/source-upload";

describe("private source upload validation", () => {
  it("accepts the three supported video formats only when MIME and extension agree", () => {
    expect(getVideoMime("story.mp4", "video/mp4")).toBe("video/mp4");
    expect(getVideoMime("story.mov", "video/quicktime")).toBe("video/quicktime");
    expect(getVideoMime("story.webm", "video/webm")).toBe("video/webm");
    expect(getVideoMime("story.mp4", "video/webm")).toBeNull();
    expect(getVideoMime("story.avi", "video/x-msvideo")).toBeNull();
  });

  it("enforces the 500 MB cap and treats duration as guidance", () => {
    expect(validateSourceVideo({ name: "source.mp4", type: "video/mp4", size: MAX_SOURCE_BYTES })).toBeNull();
    expect(validateSourceVideo({ name: "source.mp4", type: "video/mp4", size: MAX_SOURCE_BYTES + 1 })).toContain("500 MB");
    expect(durationGuidance(2 * 60_000)).toContain("guidance, not a limit");
    expect(durationGuidance(8 * 60_000)).toContain("recommended");
  });

  it("sanitizes filenames and binds object keys to owner, story, and media IDs", () => {
    expect(sanitizeFilename("../../My Story.mov")).toBe("My-Story.mov");
    expect(sourceObjectKey("owner", "story", "media", "my video.mp4")).toBe("owner/story/media/my-video.mp4");
  });
});
