import { createHash } from "node:crypto";
import { z } from "zod";

export const proposalSegmentSchema = z.object({
  transcriptSegmentId: z.string().uuid(),
  narrativeRole: z.string().trim().min(1).max(120),
  selectionRationale: z.string().trim().min(1).max(1000),
}).strict();

export type StoryCutSegmentInput = z.infer<typeof proposalSegmentSchema> & {
  sourceStartMs: number;
  sourceEndMs: number;
};

export function canonicalStoryCutHash(sourceMediaArtifactId: string, transcriptArtifactId: string, segments: readonly StoryCutSegmentInput[]) {
  const canonical = JSON.stringify({
    sourceMediaArtifactId,
    transcriptArtifactId,
    segments: segments.map((segment, index) => ({
      transcriptSegmentId: segment.transcriptSegmentId,
      segmentNumber: index + 1,
      sourceStartMs: segment.sourceStartMs,
      sourceEndMs: segment.sourceEndMs,
      narrativeRole: segment.narrativeRole,
      selectionRationale: segment.selectionRationale,
    })),
  });
  return createHash("sha256").update(canonical, "utf8").digest();
}

// Kept behind an injectable provider boundary so tests never call a live model.
export type StoryCutProposalProvider = (segments: readonly { id: string; startMs: number; endMs: number; text: string }[]) => Promise<Array<Pick<StoryCutSegmentInput, "transcriptSegmentId" | "narrativeRole" | "selectionRationale">>>;

export function outputTiming(segments: readonly Pick<StoryCutSegmentInput, "sourceStartMs" | "sourceEndMs">[]) {
  let cursor = 0;
  return segments.map((segment) => {
    const duration = segment.sourceEndMs - segment.sourceStartMs;
    const result = { outputStartMs: cursor, outputEndMs: cursor + duration };
    cursor += duration;
    return result;
  });
}
