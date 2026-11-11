import { createHash } from "node:crypto";
import { EventEmitter } from "node:events";
import { access, rm, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { NextRequest } from "next/server";
import OpenAI from "openai";
import { afterEach, beforeEach, describe, expect, it, vi, type MockInstance } from "vitest";
import { POST } from "@/app/api/stories/[storyId]/detect-language/route";
import { GET } from "@/app/api/verify-diagnostics/[correlationId]/route";
import { isTranscriptionEligible } from "./language";
import { diagnosticRecordSchema } from "./detection-diagnostics";

const mocks = vi.hoisted(() => ({
  serverClient: vi.fn(), rpc: vi.fn(), transcribe: vi.fn(), spawn: vi.fn(), remove: vi.fn(), diagnosticInsert: vi.fn(), diagnosticLookup: vi.fn(),
}));
vi.mock("@/lib/supabase/server", () => ({ createSupabaseServerClient: mocks.serverClient }));
vi.mock("@/lib/supabase/admin", () => ({ createSupabaseAdminClient: () => ({
  rpc: mocks.rpc,
  from: () => ({ insert: mocks.diagnosticInsert, select: () => ({ eq: () => ({ maybeSingle: mocks.diagnosticLookup }) }) }),
}) }));
vi.mock("node:child_process", async (importOriginal) => ({
  ...await importOriginal<typeof import("node:child_process")>(), spawn: mocks.spawn,
}));
vi.mock("node:fs/promises", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:fs/promises")>();
  mocks.remove.mockImplementation(actual.rm);
  return { ...actual, rm: mocks.remove };
});
vi.mock("./language", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./language")>();
  return { ...actual, createLanguageDetectionProvider: () => new actual.OpenAILanguageDetectionProvider(mocks.transcribe) };
});

const storyId = "10000000-0000-4000-8000-000000000001";
const mediaId = "10000000-0000-4000-8000-000000000002";
const ownerId = "10000000-0000-4000-8000-000000000003";
const privateSource = "private-video-fixture";
const verifiedHash = createHash("sha256").update(privateSource).digest("hex");
const providerRequestId = "req_" + "a".repeat(32);
const fakeSecrets = ["mock-openai-secret", "mock-service-secret", "mock-access-token", "private transcript phrase", "private/source/path", "mock-signed-url-secret"];
const safeLanguage = { languages: [{ code: "yo" }], requestId: providerRequestId, httpStatus: 200, text: fakeSecrets[3] };
let samplePath: string | undefined;
let videoPath: string | undefined;
let warn: MockInstance<typeof console.warn>;

function wav(silent: boolean) {
  const samples = 320 * 20;
  const bytes = Buffer.alloc(44 + samples * 2);
  bytes.write("RIFF", 0);
  bytes.writeUInt32LE(bytes.length - 8, 4);
  bytes.write("WAVEfmt ", 8);
  bytes.writeUInt32LE(16, 16);
  bytes.writeUInt16LE(1, 20);
  bytes.writeUInt16LE(1, 22);
  bytes.writeUInt32LE(16000, 24);
  bytes.writeUInt32LE(32000, 28);
  bytes.writeUInt16LE(2, 32);
  bytes.writeUInt16LE(16, 34);
  bytes.write("data", 36);
  bytes.writeUInt32LE(samples * 2, 40);
  if (!silent) {
    for (let index = 0; index < samples; index++) {
      const amplitude = Math.floor(index / 320) % 2 ? 4000 : 1000;
      bytes.writeInt16LE(index % 16 < 8 ? amplitude : -amplitude, 44 + index * 2);
    }
  }
  return bytes;
}

function mockFfmpeg(result: "audio" | "silence" | "failure") {
  mocks.spawn.mockImplementation((_binary: string, args: string[]) => {
    const child = Object.assign(new EventEmitter(), {
      stderr: Object.assign(new EventEmitter(), { setEncoding: vi.fn().mockReturnThis() }),
      kill: vi.fn(),
    });
    samplePath = args.at(-1)!;
    videoPath = args[args.indexOf("-i") + 1];
    if (result === "failure") queueMicrotask(() => child.emit("close", 1));
    else void writeFile(samplePath, wav(result === "silence")).then(() => child.emit("close", 0), (error) => child.emit("error", error));
    return child;
  });
}

async function requestDetection() {
  return POST(new NextRequest("http://localhost/api/stories/" + storyId + "/detect-language", {
    method: "POST",
    body: JSON.stringify({ sourceMediaArtifactId: mediaId, processingConsent: true }),
  }), { params: Promise.resolve({ storyId }) });
}

async function assertRemoved() {
  expect(samplePath).toBeDefined();
  expect(videoPath).toBeDefined();
  for (const path of [samplePath!, videoPath!]) {
    await expect(access(dirname(path))).rejects.toMatchObject({ code: "ENOENT" });
  }
}

async function checkFailure(category: string, stage: string, status: number, retryable: boolean, persistenceAttempted = false, audited = true) {
  const response = await requestDetection();
  const body = await response.json();
  expect(response.status).toBe(status);
  expect(body).toEqual({ category, stage, retryable, error: expect.any(String), correlationId: expect.stringMatching(/^[a-f0-9-]{36}$/) });
  expect(warn).toHaveBeenCalledWith("verify_language_detection_failed", expect.objectContaining({
    category, stage, retryable, correlationId: body.correlationId, attemptedAt: expect.any(String),
    provider: "openai", model: "gpt-transcribe",
  }));
  const diagnostics = JSON.stringify({ browser: body, server: warn.mock.calls, writes: mocks.rpc.mock.calls });
  for (const secret of fakeSecrets) expect(diagnostics).not.toContain(secret);
  expect(mocks.diagnosticInsert).toHaveBeenCalledWith(expect.objectContaining({
    correlation_id: body.correlationId, category, stage, retryable,
  }));
  for (const secret of fakeSecrets) expect(JSON.stringify(mocks.diagnosticInsert.mock.calls)).not.toContain(secret);
  for (const [event] of mocks.diagnosticInsert.mock.calls) expect(diagnosticRecordSchema.safeParse(event).success).toBe(true);
  const writes = mocks.rpc.mock.calls.map(([name]) => name);
  expect(writes).toEqual(persistenceAttempted
    ? ["create_source_language_proposal", "record_language_detection_failure"]
    : audited ? ["record_language_detection_failure"] : []);
  expect(isTranscriptionEligible({
    mediaVerified: true, currentSourceVersion: true, decisionStatus: null, confirmedLanguageCode: null, confirmerIsOwner: true,
  })).toBe(false);
}

beforeEach(() => {
  vi.stubEnv("OPENAI_API_KEY", fakeSecrets[0]);
  vi.stubEnv("SUPABASE_SERVICE_ROLE_KEY", fakeSecrets[1]);
  vi.stubEnv("FFMPEG_PATH", "mock-ffmpeg");
  warn = vi.spyOn(console, "warn").mockImplementation(() => {});
  vi.spyOn(console, "info").mockImplementation(() => {});
  samplePath = undefined;
  videoPath = undefined;
  mocks.spawn.mockClear();
  mocks.remove.mockClear();
  mocks.rpc.mockReset().mockResolvedValue({ data: null, error: null });
  mocks.diagnosticInsert.mockReset().mockResolvedValue({ error: null });
  mocks.diagnosticLookup.mockReset().mockResolvedValue({ data: null, error: null });
  mocks.transcribe.mockReset().mockResolvedValue(safeLanguage);
  const tables: Record<string, unknown> = {
    stories: { owner_id: ownerId },
    media_assets: [{ artifact_version_id: mediaId, object_key: fakeSecrets[4], bucket_id: "private-source" }],
    source_media_verifications: { status: "READY", server_content_sha256: verifiedHash },
  };
  mocks.serverClient.mockResolvedValue({
    auth: { getUser: async () => ({ data: { user: { id: ownerId } } }) },
    from: (table: string) => {
      const result = { data: tables[table], error: null };
      return {
        select() { return this; },
        eq() { return this; },
        order() { return this; },
        limit() { return table === "media_assets" ? result : this; },
        maybeSingle: async () => result,
      };
    },
    storage: { from: () => ({ createSignedUrl: async () => ({
      data: { signedUrl: "https://example.invalid/" + fakeSecrets[5] }, error: null,
    }) }) },
  });
  vi.stubGlobal("fetch", vi.fn(async () => new Response(privateSource)));
  mockFfmpeg("audio");
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("Verify A failure diagnostics", () => {
  it.each(["anonymous", "cross-owner", "unknown"])("returns 404 for %s diagnostic lookup", async (scenario) => {
    const correlationId = "10000000-0000-4000-8000-000000000004";
    mocks.diagnosticLookup.mockResolvedValue({ data: scenario === "unknown" ? null : { correlation_id: correlationId, story_id: storyId }, error: null });
    mocks.serverClient.mockResolvedValue({
      auth: { getUser: async () => ({ data: { user: scenario === "anonymous" ? null : { id: ownerId } } }) },
      from: () => ({ select() { return this; }, eq() { return this; }, maybeSingle: async () => ({ data: null, error: null }) }),
    });
    const response = await GET(new NextRequest("http://localhost/api/verify-diagnostics/" + correlationId), { params: Promise.resolve({ correlationId }) });
    expect(response.status).toBe(404);
    expect(await response.json()).toEqual({ error: "Not found." });
    if (scenario === "anonymous") expect(mocks.diagnosticLookup).not.toHaveBeenCalled();
  });

  it("retrieves the sanitized event by support reference for its story owner", async () => {
    const event = {
      correlation_id: "10000000-0000-4000-8000-000000000004", story_id: storyId,
      attempted_at: new Date().toISOString(), stage: "provider_request", category: "provider_network_failure",
      retryable: true, provider: "openai", model: "gpt-transcribe", provider_http_status: null,
      provider_error_type: null, provider_error_code: null, provider_request_id: null, transport: "network", database_code: null,
    };
    mocks.diagnosticLookup.mockResolvedValue({ data: event, error: null });
    const response = await GET(new NextRequest("http://localhost/api/verify-diagnostics/" + event.correlation_id), {
      params: Promise.resolve({ correlationId: event.correlation_id }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(event);
  });

  it.each([
    [401, "invalid_api_key", "provider_authentication_failed", 502, false],
    [403, "permission_denied", "provider_permission_denied", 502, false],
    [404, "model_not_found", "provider_model_unavailable", 502, false],
    [413, "payload_too_large", "provider_payload_too_large", 422, false],
    [429, "insufficient_quota", "provider_quota_or_rate_limit", 503, true],
    [500, "server_error", "provider_temporarily_unavailable", 503, true],
  ] as const)("maps OpenAI HTTP %s and removes both temporary directories", async (providerStatus, code, category, status, retryable) => {
    mocks.transcribe.mockRejectedValue(OpenAI.APIError.generate(providerStatus, {
      error: { type: "invalid_request_error", code, message: fakeSecrets.join(" ") },
    }, undefined, new Headers({ "x-request-id": providerRequestId })));
    await checkFailure(category, "provider_request", status, retryable);
    expect(warn.mock.calls[0][1]).toMatchObject({
      providerHttpStatus: providerStatus, providerErrorCode: code,
      providerErrorType: "invalid_request_error", providerRequestId,
    });
    await assertRemoved();
  });

  it.each([
    [new OpenAI.APIConnectionTimeoutError({ message: fakeSecrets.join(" ") }), "provider_timeout", 504, "timeout"],
    [new OpenAI.APIConnectionError({ message: fakeSecrets.join(" ") }), "provider_network_failure", 503, "network"],
  ] as const)("maps SDK transport failure %# and removes temporary files", async (error, category, status, transport) => {
    mocks.transcribe.mockRejectedValue(error);
    await checkFailure(category, "provider_request", status, true);
    expect(warn.mock.calls[0][1]).toMatchObject({ transport, providerHttpStatus: null });
    await assertRemoved();
  });

  it("drops non-allowlisted provider type, code and request ID", async () => {
    mocks.transcribe.mockRejectedValue(OpenAI.APIError.generate(401, {
      error: { type: fakeSecrets[0], code: fakeSecrets[1], message: fakeSecrets[3] },
    }, undefined, new Headers({ "x-request-id": fakeSecrets[2] })));
    await checkFailure("provider_authentication_failed", "provider_request", 502, false);
    expect(warn.mock.calls[0][1]).toMatchObject({ providerErrorType: "api_error", providerErrorCode: null, providerRequestId: null });
    await assertRemoved();
  });

  it.each([
    [{ code: "yo" }, "provider_response_invalid", 502],
    [[], "no_reliable_language", 422],
  ] as const)("distinguishes malformed and inconclusive responses %#", async (languages, category, status) => {
    mocks.transcribe.mockResolvedValue({ ...safeLanguage, languages });
    await checkFailure(category, "provider_response_validation", status, true);
    expect(warn.mock.calls[0][1]).toMatchObject({ providerHttpStatus: 200, providerRequestId });
    await assertRemoved();
  });

  it.each([
    [[], "no_reliable_language", "zero_languages", 422],
    [[{ code: "yo" }, { code: "en" }], "no_reliable_language", "multiple_languages", 422],
    [undefined, "provider_response_invalid", null, 502],
  ] as const)("logs only language cardinality for response %#", async (languages, category, classification, status) => {
    mocks.transcribe.mockResolvedValue({ ...safeLanguage, languages });
    await checkFailure(category, "provider_response_validation", status, true);
    expect(warn.mock.calls[0][1]).toMatchObject({ languageCountClassification: classification });
    const persisted = mocks.diagnosticInsert.mock.calls[0][0];
    expect(persisted).not.toHaveProperty("languageCountClassification");
    expect(persisted).not.toHaveProperty("languages");
    expect(JSON.stringify({ logs: warn.mock.calls, persisted })).not.toContain(fakeSecrets[3]);
    await assertRemoved();
  });

  it("reports persistence failure with only a safe SQLSTATE after cleaning up", async () => {
    mocks.rpc.mockImplementation(async (name: string) => {
      if (name !== "create_source_language_proposal") return { data: null, error: null };
      await assertRemoved();
      return { data: null, error: { code: "42501", message: fakeSecrets.join(" ") } };
    });
    await checkFailure("proposal_persistence_failed", "proposal_persistence", 500, true, true);
    expect(warn.mock.calls[0][1]).toMatchObject({ databaseCode: "42501", providerRequestId });
    await assertRemoved();
  });

  it("persists safe diagnostic metadata across provider, validation, and proposal failures", async () => {
    mocks.transcribe.mockRejectedValue(OpenAI.APIError.generate(401, { error: { type: "invalid_request_error", code: "invalid_api_key", message: fakeSecrets.join(" ") } }, undefined, new Headers({ "x-request-id": providerRequestId })));
    await checkFailure("provider_authentication_failed", "provider_request", 502, false);
    expect(mocks.diagnosticInsert.mock.calls[0][0]).toMatchObject({ provider_http_status: 401, provider_error_code: "invalid_api_key", provider_request_id: providerRequestId });
    await assertRemoved();
  });

  it.each([
    ["failure", "audio_extraction", "media_processing_failed"],
    ["silence", "speech_validation", "no_reliable_language"],
  ] as const)("reports %s before sending audio to OpenAI", async (result, stage, category) => {
    mockFfmpeg(result);
    await checkFailure(category, stage, 422, true);
    expect(mocks.transcribe).not.toHaveBeenCalled();
    await assertRemoved();
  });

  it("reports missing configuration before downloading or creating media", async () => {
    vi.stubEnv("OPENAI_API_KEY", "");
    await checkFailure("provider_not_configured", "provider_request", 503, true);
    expect(fetch).not.toHaveBeenCalled();
    expect(mocks.spawn).not.toHaveBeenCalled();
    expect(mocks.transcribe).not.toHaveBeenCalled();
    expect(mocks.remove).not.toHaveBeenCalled();
  });

  it("reports failed ownership without reading media or writing an audit row", async () => {
    mocks.serverClient.mockResolvedValueOnce({
      auth: { getUser: async () => ({ data: { user: null } }) },
    });
    await checkFailure("unknown_detection_failure", "ownership_check", 401, false, false, false);
    expect(fetch).not.toHaveBeenCalled();
    expect(mocks.remove).not.toHaveBeenCalled();
  });

  it.each([
    [new Response(null, { status: 403 }), "source_download", 502, true],
    [new Response("wrong source bytes"), "hash_verification", 409, false],
  ] as const)("reports source preparation failure %# and removes the video directory", async (response, stage, status, retryable) => {
    vi.mocked(fetch).mockResolvedValueOnce(response);
    await checkFailure("media_processing_failed", stage, status, retryable);
    expect(mocks.transcribe).not.toHaveBeenCalled();
    expect(mocks.remove).toHaveBeenCalledTimes(1);
    await expect(access(mocks.remove.mock.calls[0][0])).rejects.toMatchObject({ code: "ENOENT" });
  });

  it("reports an unexpected provider-boundary failure and removes temporary files", async () => {
    mocks.transcribe.mockRejectedValue(new Error(fakeSecrets.join(" ")));
    await checkFailure("unknown_detection_failure", "provider_request", 500, true);
    await assertRemoved();
  });

  it.each([true, false])("reports cleanup only when it is the first failure (prior provider failure: %s)", async (priorFailure) => {
    const remove = mocks.remove.getMockImplementation()!;
    // Simulate a removal exception after deleting, so this test leaves no fixture behind.
    mocks.remove.mockImplementationOnce(async (...args: Parameters<typeof rm>) => {
      await remove(...args);
      throw new Error(fakeSecrets.join(" "));
    });
    if (priorFailure) mocks.transcribe.mockRejectedValue(new OpenAI.APIConnectionTimeoutError());
    await checkFailure(
      priorFailure ? "provider_timeout" : "media_processing_failed",
      priorFailure ? "provider_request" : "cleanup",
      priorFailure ? 504 : 422,
      true,
    );
    await assertRemoved();
  });

  it("persists a proposal only, strips transcript text and leaves eligibility false", async () => {
    mocks.rpc.mockResolvedValue({ data: "proposal-fixture", error: null });
    const response = await requestDetection();
    const body = await response.json();
    expect(response.status).toBe(200);
    expect(body).toMatchObject({ reviewStatus: "PROPOSED", proposedLanguageCode: "yor" });
    expect(console.info).toHaveBeenCalledWith("verify_language_response_classified", {
      correlationId: expect.any(String), languageCountClassification: "one_language",
    });
    expect(mocks.rpc.mock.calls).toEqual([["create_source_language_proposal", {
      p_story_id: storyId,
      p_source_media_artifact_id: mediaId,
      p_detected_language_code: "yor",
      p_detected_language_name: "Yoruba",
      p_detection_confidence: null,
      p_detector_name: "openai",
      p_detector_model: "gpt-transcribe",
      p_provider_request_id: providerRequestId,
    }]]);
    expect(JSON.stringify({ body, writes: mocks.rpc.mock.calls, logs: warn.mock.calls })).not.toContain(fakeSecrets[3]);
    expect(isTranscriptionEligible({
      mediaVerified: true, currentSourceVersion: true, decisionStatus: body.reviewStatus,
      confirmedLanguageCode: null, confirmerIsOwner: true,
    })).toBe(false);
    await assertRemoved();
  });
});
