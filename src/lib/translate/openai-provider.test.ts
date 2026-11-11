import { describe, expect, it, vi } from "vitest";
vi.mock("server-only", () => ({}));

import { createYorubaToEnglishProvider } from "@/lib/translate/openai-provider";
import { canonicalEnglishTranslationHash } from "@/lib/translate/contract";

const source = [
  { cutSegmentId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", startMs: 1000, endMs: 2000, text: "Yoruba sentence one" },
  { cutSegmentId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", startMs: 4000, endMs: 7000, text: "Yoruba sentence two" },
];

describe("Yoruba to English translation provider", () => {
  it("accepts mocked, one-to-one English segments without contacting OpenAI", async () => {
    const completion = vi.fn(async () => ({ segments: source.map((segment, index) => ({ cutSegmentId: segment.cutSegmentId, englishText: `English ${index + 1}` })) }));
    const provider = createYorubaToEnglishProvider(completion);
    const translated = await provider(source);
    expect(completion).toHaveBeenCalledOnce();
    expect(translated.map((segment) => segment.englishText)).toEqual(["English 1", "English 2"]);
    const segments = translated.map((segment, index) => ({ ...segment, transcriptSegmentId: `transcript-${index}`, sourceStartMs: source[index].startMs,
      sourceEndMs: source[index].endMs, cueStartMs: index * 2000, cueEndMs: (index + 1) * 2000, initialProposal: segment.englishText }));
    const digest = canonicalEnglishTranslationHash("source", "transcript", "cut", segments).toString("hex");
    expect(digest).toHaveLength(64);
    expect(canonicalEnglishTranslationHash("source", "transcript", "other-cut", segments).toString("hex")).not.toBe(digest);
  });

  it("rejects fabricated IDs and missing segments from mocked provider output", async () => {
    const fabricated = createYorubaToEnglishProvider(async () => ({ segments: [{ cutSegmentId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc", englishText: "Wrong segment" }, { cutSegmentId: source[1].cutSegmentId, englishText: "Two" }] }));
    const missing = createYorubaToEnglishProvider(async () => ({ segments: [{ cutSegmentId: source[0].cutSegmentId, englishText: "One" }] }));
    await expect(fabricated(source)).rejects.toThrow("English translation could not be generated");
    await expect(missing(source)).rejects.toThrow("English translation could not be generated");
  });
});
