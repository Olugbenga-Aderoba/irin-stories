import { createHash } from "node:crypto";
import { z } from "zod";

export const englishTranslationSchema = z.object({
  cutSegmentId: z.string().uuid(),
  englishText: z.string().trim().min(1).max(10_000),
}).strict();

export type EnglishTranslationInput = z.infer<typeof englishTranslationSchema> & {
  transcriptSegmentId: string;
  sourceStartMs: number;
  sourceEndMs: number;
  cueStartMs: number;
  cueEndMs: number;
  initialProposal: string;
};

export function canonicalEnglishTranslationHash(sourceId: string, transcriptId: string, cutId: string, segments: readonly EnglishTranslationInput[]) {
  const canonical = JSON.stringify({
    sourceMediaArtifactId: sourceId,
    transcriptArtifactId: transcriptId,
    storyCutArtifactId: cutId,
    sourceLanguageCode: "yor",
    targetLanguageCode: "eng",
    segments: segments.map((segment, index) => ({
      segmentNumber: index + 1,
      cutSegmentId: segment.cutSegmentId,
      transcriptSegmentId: segment.transcriptSegmentId,
      sourceStartMs: segment.sourceStartMs,
      sourceEndMs: segment.sourceEndMs,
      cueStartMs: segment.cueStartMs,
      cueEndMs: segment.cueEndMs,
      initialProposal: segment.initialProposal,
      englishText: segment.englishText,
    })),
  });
  return createHash("sha256").update(canonical, "utf8").digest();
}

export type YorubaToEnglishProvider = (segments: readonly { cutSegmentId: string; startMs: number; endMs: number; text: string }[]) => Promise<Array<z.infer<typeof englishTranslationSchema>>>;
