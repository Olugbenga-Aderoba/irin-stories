import { describe, expect, it, vi } from "vitest";
import { canonicalStoryCutHash, type StoryCutProposalProvider } from "@/lib/craft/story-cut";

describe("Craft Story Cut provenance", () => {
  it("accepts a mocked proposal provider and binds order, transcript segments and timestamps in the digest", async () => {
    const mockedGeneration: StoryCutProposalProvider = vi.fn(async (segments: readonly { id: string; startMs: number; endMs: number; text: string }[]) => segments.map((segment) => ({
      transcriptSegmentId: segment.id, sourceStartMs: segment.startMs, sourceEndMs: segment.endMs,
      narrativeRole: "Opening", selectionRationale: "Mocked model proposal for this test.",
    })));
    const transcript = [
      { id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", startMs: 0, endMs: 1200, text: "First" },
      { id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", startMs: 2400, endMs: 4000, text: "Second" },
    ];
    const proposal = await mockedGeneration(transcript);
    expect(mockedGeneration).toHaveBeenCalledOnce();
    expect(proposal.map((segment) => segment.transcriptSegmentId)).toEqual(transcript.map((segment) => segment.id));
    const completeProposal = proposal.map((segment) => ({ ...segment, sourceStartMs: transcript.find((source) => source.id === segment.transcriptSegmentId)!.startMs, sourceEndMs: transcript.find((source) => source.id === segment.transcriptSegmentId)!.endMs }));
    const original = canonicalStoryCutHash("source", "transcript", completeProposal).toString("hex");
    const reordered = canonicalStoryCutHash("source", "transcript", [...completeProposal].reverse()).toString("hex");
    const changedLineage = canonicalStoryCutHash("source", "other-transcript", completeProposal).toString("hex");
    expect(original).not.toBe(reordered);
    expect(original).not.toBe(changedLineage);
  });
});
