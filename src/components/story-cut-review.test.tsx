import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh: vi.fn() }) }));

import { StoryCutReview } from "@/components/story-cut-review";

const transcriptSegment = { id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", source_start_ms: 1000, source_end_ms: 61000, text_yoruba: "Àlàyé ìtàn." };
const item = { id: "cut-segment", transcript_segment_id: transcriptSegment.id, source_start_ms: 1000, source_end_ms: 61000, output_start_ms: 0, output_end_ms: 60000, narrative_role: "Opening", selection_rationale: "Introduces the story." , text_yoruba: transcriptSegment.text_yoruba };

describe("Craft Story Cut review", () => {
  it("gates generation on approved Yoruba Source and shows the video, lineage timing and duration guidance", () => {
    const blocked = renderToStaticMarkup(<StoryCutReview storyId="story" sourceUrl="/private" transcriptApproved={false} transcriptSegments={[transcriptSegment]} cut={null} />);
    expect(blocked).toContain("Approve the current Yoruba Source transcript");
    expect(blocked).not.toContain("Create Story Cut proposal");
    const ready = renderToStaticMarkup(<StoryCutReview storyId="story" sourceUrl="/private" transcriptApproved transcriptSegments={[transcriptSegment]} cut={null} />);
    expect(ready).toContain("Current source video");
    expect(ready).toContain("Approved Yoruba transcript");
    expect(ready).toContain("90–150 second target");
    expect(ready).toContain("Create Story Cut proposal");
  });

  it("exposes remove/reorder controls and explicit approval bound to a version", () => {
    const markup = renderToStaticMarkup(<StoryCutReview storyId="story" sourceUrl="/private" transcriptApproved transcriptSegments={[transcriptSegment]} cut={{ artifactId: "cut-version", durationMs: 60000, approved: false, segments: [item] }} />);
    expect(markup).toContain("total duration 60 seconds");
    expect(markup).toContain("Move up");
    expect(markup).toContain("Move down");
    expect(markup).toContain("Remove");
    expect(markup).toContain("Save changes as new version");
    expect(markup).toContain("Approve Story Cut");
    const approved = renderToStaticMarkup(<StoryCutReview storyId="story" sourceUrl="/private" transcriptApproved transcriptSegments={[transcriptSegment]} cut={{ artifactId: "cut-version", durationMs: 60000, approved: true, segments: [item] }} />);
    expect(approved).toContain("exact Story Cut version and hash");
  });
});
