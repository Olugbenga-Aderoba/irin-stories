import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  isMvpSupportedLanguage,
  isTranscriptionEligible,
  LanguageDetectionProviderError,
  LanguageDetectionUnavailableError,
  OpenAILanguageDetectionProvider,
  normalizedLanguageProposalSchema,
} from "./language";

const tempDirectories: string[] = [];
const uuid = "10000000-0000-4000-8000-000000000001";
const hash = "a".repeat(64);
const mockApiKey = "mock-only-not-a-credential";
const mockRequestId = "req_" + "a".repeat(32);

afterEach(async () => {
  await Promise.all(tempDirectories.splice(0).map((path) => rm(path, { recursive: true, force: true })));
});

async function audioFixture(size = 128) {
  const directory = await mkdtemp(join(tmpdir(), "irin-openai-mock-"));
  tempDirectories.push(directory);
  const audioPath = join(directory, "sample.wav");
  await writeFile(audioPath, Buffer.alloc(size, 1));
  return audioPath;
}

describe("Verify A OpenAI language proposal contract", () => {
  it("normalizes OpenAI Yoruba detection without retaining transcript text or confidence", async () => {
    const audioPath = await audioFixture();
    const provider = new OpenAILanguageDetectionProvider(async () => ({
      languages: [{ code: "yo" }],
      requestId: mockRequestId,
      text: "synthetic transcript that must not be returned or stored",
    }), () => mockApiKey);
    const result = await provider.detectLanguage({ audioPath, sourceMediaArtifactId: uuid, sourceMediaHash: hash });

    expect(result).toMatchObject({
      provider: "openai",
      model: "gpt-transcribe",
      proposedLanguageCode: "yor",
      proposedLanguageName: "Yoruba",
      confidence: null,
      sourceMediaId: uuid,
      sourceMediaHash: hash,
      providerRequestId: mockRequestId,
    });
    expect(result).not.toHaveProperty("text");
    expect(Object.keys(result).sort()).toEqual([
      "provider", "model", "proposedLanguageCode", "proposedLanguageName", "confidence",
      "detectedAt", "sourceMediaId", "sourceMediaHash", "providerRequestId",
    ].sort());
    expect(normalizedLanguageProposalSchema.safeParse(result).success).toBe(true);
  });

  it("never fabricates confidence when the provider omits it", async () => {
    const audioPath = await audioFixture();
    const provider = new OpenAILanguageDetectionProvider(async () => ({ languages: [{ code: "yo" }], requestId: null }), () => mockApiKey);
    await expect(provider.detectLanguage({ audioPath, sourceMediaArtifactId: uuid, sourceMediaHash: hash }))
      .resolves.toMatchObject({ confidence: null, providerRequestId: null });
  });

  it("rejects malformed or ambiguous provider language output", async () => {
    const audioPath = await audioFixture();
    for (const languages of [undefined, [], [{ code: "not-a-real-code" }], [{ code: "yo" }, { code: "en" }]]) {
      const provider = new OpenAILanguageDetectionProvider(async () => ({ languages, requestId: null }), () => mockApiKey);
      await expect(provider.detectLanguage({ audioPath, sourceMediaArtifactId: uuid, sourceMediaHash: hash }))
        .rejects.toBeInstanceOf(LanguageDetectionProviderError);
    }
    expect(() => normalizedLanguageProposalSchema.parse({ languageCode: "en", displayName: "English" })).toThrow();
  });

  it("fails as retryable and makes no provider call when OPENAI_API_KEY is absent", async () => {
    const previous = process.env.OPENAI_API_KEY;
    delete process.env.OPENAI_API_KEY;
    let called = false;
    const provider = new OpenAILanguageDetectionProvider(async () => {
      called = true;
      return { languages: [{ code: "yo" }], requestId: null };
    }, () => undefined);
    try {
      await expect(provider.detectLanguage({ audioPath: await audioFixture(), sourceMediaArtifactId: uuid, sourceMediaHash: hash }))
        .rejects.toBeInstanceOf(LanguageDetectionUnavailableError);
      expect(called).toBe(false);
    } finally {
      if (previous !== undefined) process.env.OPENAI_API_KEY = previous;
    }
  });

  it("maps provider timeout to an explicit retryable category", async () => {
    const audioPath = await audioFixture();
    const provider = new OpenAILanguageDetectionProvider(async () => { throw new DOMException("timeout", "TimeoutError"); }, () => mockApiKey);
    await expect(provider.detectLanguage({ audioPath, sourceMediaArtifactId: uuid, sourceMediaHash: hash }))
      .rejects.toMatchObject({ category: "provider_timeout", retryable: true });
  });

  it("rejects empty and over-limit audio before sending it", async () => {
    const empty = await audioFixture(44);
    const oversized = await audioFixture(25 * 1024 * 1024 + 1);
    let called = false;
    const provider = new OpenAILanguageDetectionProvider(async () => {
      called = true;
      return { languages: [{ code: "yo" }], requestId: null };
    }, () => mockApiKey);
    for (const audioPath of [empty, oversized]) {
      await expect(provider.detectLanguage({ audioPath, sourceMediaArtifactId: uuid, sourceMediaHash: hash }))
        .rejects.toBeInstanceOf(LanguageDetectionProviderError);
    }
    expect(called).toBe(false);
  });

  it("supports Yoruba only and requires owner confirmation of current verified media", () => {
    expect(isMvpSupportedLanguage("yor")).toBe(true);
    expect(isMvpSupportedLanguage("eng")).toBe(false);
    const confirmed = {
      mediaVerified: true,
      currentSourceVersion: true,
      decisionStatus: "CONFIRMED" as const,
      confirmedLanguageCode: "yor",
      confirmerIsOwner: true,
    };
    expect(isTranscriptionEligible(confirmed)).toBe(true);
    expect(isTranscriptionEligible({ ...confirmed, decisionStatus: "PROPOSED" })).toBe(false);
    expect(isTranscriptionEligible({ ...confirmed, currentSourceVersion: false })).toBe(false);
    expect(isTranscriptionEligible({ ...confirmed, mediaVerified: false })).toBe(false);
    expect(isTranscriptionEligible({ ...confirmed, confirmerIsOwner: false })).toBe(false);
    expect(isTranscriptionEligible({ ...confirmed, confirmedLanguageCode: "eng" })).toBe(false);
  });
});
