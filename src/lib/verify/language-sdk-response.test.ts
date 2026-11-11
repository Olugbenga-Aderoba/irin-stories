
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Transcription } from "openai/resources/audio/transcriptions";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { OpenAILanguageDetectionProvider, isTranscriptionEligible } from "./language";

const sentinel = "synthetic transcript content must never leave the SDK response";
const requestId = "req_" + "b".repeat(32);
let directory: string;
let audioPath: string;
beforeEach(async () => {
  directory = await mkdtemp(join(tmpdir(), "irin-sdk-fixture-"));
  audioPath = join(directory, "fixture.wav");
  await writeFile(audioPath, Buffer.alloc(128));
});
afterEach(async () => {
  vi.unstubAllGlobals();
  await rm(directory, { recursive: true, force: true });
});
describe("installed SDK JSON response contract (mock fetch only)", () => {
  it.each([
    [[{ code: "yo" }], null, "one_language"],
    [[], "no_reliable_language", "zero_languages"],
    [[{ code: "yo" }, { code: "en" }], "no_reliable_language", "multiple_languages"],
    [undefined, "provider_response_invalid", undefined],
  ] as const)("normalizes documented language shape %#", async (languages, category, classification) => {
    const body: Transcription = { text: sentinel, ...(languages === undefined ? {} : { languages: [...languages] }) };
    const fetchMock = vi.fn(async () => new Response(JSON.stringify(body), {
      status: 200, headers: { "Content-Type": "application/json", "x-request-id": requestId },
    }));
    vi.stubGlobal("fetch", fetchMock);
    const provider = new OpenAILanguageDetectionProvider(undefined, () => "mock-api-key-not-real");
    const attempt = provider.detectLanguage({
      audioPath, sourceMediaArtifactId: "10000000-0000-4000-8000-000000000001", sourceMediaHash: "a".repeat(64),
    });
    if (category === null) {
      const proposal = await attempt;
      expect(proposal).toMatchObject({ proposedLanguageCode: "yor", proposedLanguageName: "Yoruba", confidence: null, providerRequestId: requestId });
      expect(JSON.stringify(proposal)).not.toContain(sentinel);
      expect(proposal).not.toHaveProperty("languages");
    } else {
      const error = await attempt.catch((value: unknown) => value);
      expect(error).toMatchObject({ category, stage: "provider_response_validation", metadata: { httpStatus: 200, requestId } });
      expect((error as { metadata: { languageCountClassification?: string } }).metadata.languageCountClassification).toBe(classification);
      expect(JSON.stringify(error)).not.toContain(sentinel);
      expect(error).not.toHaveProperty("metadata.languages");
    }
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(isTranscriptionEligible({ mediaVerified: true, currentSourceVersion: true, decisionStatus: null, confirmedLanguageCode: null, confirmerIsOwner: true })).toBe(false);
  });
});
