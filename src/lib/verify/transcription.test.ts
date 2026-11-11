import { describe, expect, it } from "vitest";
import { canonicalTranscriptHash, normalizeYorubaTranscriptResponse, YorubaTranscriptionError } from "@/lib/verify/transcript-contract";

describe("Yoruba transcript provenance", () => {
  it("keeps provider segment timestamps and text without inventing a fallback", () => {
    expect(normalizeYorubaTranscriptResponse({
      language: "Yoruba",
      segments: [{ start: 0.2, end: 1.4, text: " Ẹ káàárọ̀ " }, { start: 1.5, end: 2.1, text: "àwọn ènìyàn." }],
    })).toEqual([
      { startSeconds: 0.2, endSeconds: 1.4, text: "Ẹ káàárọ̀" },
      { startSeconds: 1.5, endSeconds: 2.1, text: "àwọn ènìyàn." },
    ]);
  });

  it("rejects missing, malformed, or unordered timestamps", () => {
    expect(() => normalizeYorubaTranscriptResponse({ language: "Yoruba", text: "not a timestamped transcript" })).toThrow(YorubaTranscriptionError);
    expect(() => normalizeYorubaTranscriptResponse({ language: "Yoruba", segments: [{ start: 2, end: 1, text: "text" }] })).toThrow(YorubaTranscriptionError);
    expect(() => normalizeYorubaTranscriptResponse({ language: "Yoruba", segments: [{ start: 1, end: 2, text: "first" }, { start: 0, end: 3, text: "second" }] })).toThrow(YorubaTranscriptionError);
    expect(() => normalizeYorubaTranscriptResponse({ language: "English", segments: [{ start: 0, end: 1, text: "not Yoruba" }] })).toThrow(YorubaTranscriptionError);
  });

  it("binds both the immutable AI original and the current edit into the version hash", () => {
    const source = "22222222-2222-4222-8222-222222222222";
    const initial = [{ startMs: 0, endMs: 1200, initialProposal: "AI text", text: "AI text" }];
    const edited = [{ ...initial[0], text: "Storyteller text" }];
    expect(canonicalTranscriptHash(source, initial)).not.toEqual(canonicalTranscriptHash(source, edited));
  });
});
