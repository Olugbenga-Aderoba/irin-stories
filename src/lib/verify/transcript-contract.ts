import { createHash } from "node:crypto";
import { z } from "zod";

export type YorubaTranscriptSegment = Readonly<{ startSeconds: number; endSeconds: number; text: string }>;
export class YorubaTranscriptionError extends Error {
  constructor() {
    super("Yoruba transcription could not be completed. Please retry.");
    this.name = "YorubaTranscriptionError";
  }
}

const providerResponse = z.object({
  language: z.string().trim().min(1).max(64),
  segments: z.array(z.object({
    start: z.number().finite().nonnegative(),
    end: z.number().finite().positive(),
    text: z.string().trim().min(1).max(10_000),
  })).min(1).max(10_000),
});

export function normalizeYorubaTranscriptResponse(value: unknown): YorubaTranscriptSegment[] {
  const parsed = providerResponse.safeParse(value);
  if (!parsed.success || !["yo", "yor", "yoruba"].includes(parsed.data.language.toLowerCase())) throw new YorubaTranscriptionError();
  let previousStart = -1;
  return parsed.data.segments.map((segment) => {
    if (segment.end <= segment.start || segment.start < previousStart) throw new YorubaTranscriptionError();
    previousStart = segment.start;
    return { startSeconds: segment.start, endSeconds: segment.end, text: segment.text };
  });
}

export function canonicalTranscriptHash(sourceMediaArtifactId: string, segments: ReadonlyArray<{
  startMs: number;
  endMs: number;
  initialProposal: string;
  text: string;
}>) {
  const canonical = JSON.stringify({
    languageCode: "yor",
    sourceMediaArtifactId,
    segments: segments.map((segment) => ({
      startMs: segment.startMs,
      endMs: segment.endMs,
      initialProposal: segment.initialProposal,
      text: segment.text,
    })),
  });
  return createHash("sha256").update(canonical, "utf8").digest();
}
