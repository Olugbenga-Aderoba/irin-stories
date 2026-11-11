import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import OpenAI from "openai";
import { iso6393, iso6393To1 } from "iso-639-3";
import { z } from "zod";
import { detectionFailures, safeProviderRequestId, type DetectionFailureCategory, type DetectionStage } from "./detection-diagnostics";

export const LANGUAGE_MODEL = "gpt-transcribe" as const;
const OPENAI_MAX_FILE_BYTES = 25 * 1024 * 1024;

export const normalizedLanguageProposalSchema = z.object({
  provider: z.literal("openai"),
  model: z.literal(LANGUAGE_MODEL),
  proposedLanguageCode: z.string().regex(/^[a-z]{3}$/),
  proposedLanguageName: z.string().trim().min(1).max(120),
  confidence: z.number().min(0).max(1).nullable(),
  detectedAt: z.string().datetime(),
  sourceMediaId: z.string().uuid(),
  sourceMediaHash: z.string().regex(/^[a-f0-9]{64}$/i),
  providerRequestId: z.string().regex(/^req_[a-f0-9]{32}$/i).nullable(),
}).strict();

export type NormalizedLanguageProposal = z.infer<typeof normalizedLanguageProposalSchema>;

export type LanguageDetectionInput = Readonly<{
  audioPath: string;
  sourceMediaArtifactId: string;
  sourceMediaHash: string;
}>;

export interface LanguageDetectionProvider {
  detectLanguage(input: LanguageDetectionInput): Promise<NormalizedLanguageProposal>;
}

export type OpenAITranscriptionBoundary = (input: {
  audioPath: string;
  signal: AbortSignal;
  apiKey: string;
}) => Promise<{ languages: unknown; requestId: string | null; httpStatus?: number }>;

const transcriptionLanguageSchema = z.object({
  languages: z.array(z.object({ code: z.string().trim().min(2).max(8) })),
});

type ProviderErrorMetadata = {
  languageCountClassification?: "zero_languages" | "one_language" | "multiple_languages";
  httpStatus?: number;
  errorType?: string | null;
  errorCode?: string | null;
  requestId?: string | null;
  transport?: "timeout" | "network";
};

export class LanguageDetectionUnavailableError extends Error {
  constructor() {
    super(detectionFailures.provider_not_configured[2]);
    this.name = "LanguageDetectionUnavailableError";
  }
}

export class LanguageDetectionProviderError extends Error {
  readonly retryable: boolean;

  constructor(
    readonly category: DetectionFailureCategory,
    readonly stage: Extract<DetectionStage, "provider_request" | "provider_response_validation" | "audio_extraction">,
    readonly metadata: ProviderErrorMetadata = {},
  ) {
    super(detectionFailures[category][2]);
    this.name = "LanguageDetectionProviderError";
    this.retryable = detectionFailures[category][1];
  }
}

const providerHttpFailures: Partial<Record<number, DetectionFailureCategory>> = {
  401: "provider_authentication_failed",
  403: "provider_permission_denied",
  404: "provider_model_unavailable",
  413: "provider_payload_too_large",
  429: "provider_quota_or_rate_limit",
};
const providerErrorTypes = ["invalid_request_error", "authentication_error", "permission_error", "rate_limit_error", "insufficient_quota", "server_error", "api_error"];
const providerErrorCodes = ["invalid_api_key", "invalid_request_error", "permission_denied", "model_not_found", "request_too_large", "payload_too_large", "rate_limit_exceeded", "insufficient_quota", "billing_hard_limit_reached", "server_error", "service_unavailable"];

function classifyProviderError(error: unknown, signal: AbortSignal) {
  if (error instanceof OpenAI.APIConnectionTimeoutError || (error instanceof Error &&
    (error.name === "TimeoutError" || (signal.aborted && (error.name === "AbortError" || error instanceof OpenAI.APIUserAbortError))))) {
    return new LanguageDetectionProviderError("provider_timeout", "provider_request", { transport: "timeout", errorType: "timeout" });
  }
  if (error instanceof OpenAI.APIConnectionError || error instanceof OpenAI.APIUserAbortError) {
    return new LanguageDetectionProviderError("provider_network_failure", "provider_request", { transport: "network", errorType: "connection_error" });
  }
  if (error instanceof OpenAI.APIError) {
    const status = error.status;
    const httpStatus = typeof status === "number" && Number.isInteger(status) && status >= 400 && status <= 599 ? status : undefined;
    const category = httpStatus && httpStatus >= 500
      ? "provider_temporarily_unavailable"
      : (httpStatus && providerHttpFailures[httpStatus]) || "unknown_detection_failure";
    return new LanguageDetectionProviderError(category, "provider_request", {
      httpStatus,
      errorType: typeof error.type === "string" && providerErrorTypes.includes(error.type) ? error.type : "api_error",
      errorCode: typeof error.code === "string" && providerErrorCodes.includes(error.code) ? error.code : null,
      requestId: safeProviderRequestId(error.requestID),
    });
  }
  if (error instanceof SyntaxError) {
    return new LanguageDetectionProviderError("provider_response_invalid", "provider_response_validation");
  }
  return new LanguageDetectionProviderError("unknown_detection_failure", "provider_request");
}

function normalizeLanguageCode(code: string) {
  const normalized = code.trim().toLowerCase().split("-")[0];
  const language = iso6393.find((entry) => entry.iso6393 === normalized)
    ?? iso6393.find((entry) => iso6393To1[entry.iso6393] === normalized);
  return language && { code: language.iso6393, name: language.name };
}

const openAITranscriptionBoundary: OpenAITranscriptionBoundary = async (input) => {
  const client = new OpenAI({ apiKey: input.apiKey, timeout: 30_000, maxRetries: 0, logLevel: "off" });
  const result = await client.audio.transcriptions.create({
    file: createReadStream(input.audioPath),
    model: LANGUAGE_MODEL,
    response_format: "json",
  }, { signal: input.signal }).withResponse();

  // Only pass detected language codes onward. Never return or persist result.data.text.
  return { languages: result.data?.languages, requestId: result.request_id, httpStatus: result.response.status };
};

export class OpenAILanguageDetectionProvider implements LanguageDetectionProvider {
  constructor(
    private readonly transcribe: OpenAITranscriptionBoundary = openAITranscriptionBoundary,
    private readonly getApiKey: () => string | undefined = () => process.env.OPENAI_API_KEY,
  ) {}

  async detectLanguage(input: LanguageDetectionInput): Promise<NormalizedLanguageProposal> {
    const apiKey = this.getApiKey();
    if (!apiKey) throw new LanguageDetectionUnavailableError();

    const file = await stat(input.audioPath);
    if (file.size <= 44) {
      throw new LanguageDetectionProviderError("media_processing_failed", "audio_extraction");
    }
    if (file.size > OPENAI_MAX_FILE_BYTES) {
      throw new LanguageDetectionProviderError("provider_payload_too_large", "audio_extraction");
    }

    const signal = AbortSignal.timeout(30_000);
    let response: Awaited<ReturnType<OpenAITranscriptionBoundary>>;
    try {
      response = await this.transcribe({ audioPath: input.audioPath, signal, apiKey });
    } catch (error) {
      if (error instanceof LanguageDetectionUnavailableError) throw error;
      throw classifyProviderError(error, signal);
    }

    const requestId = safeProviderRequestId(response.requestId);
    const httpStatus = response.httpStatus;
    const metadata = { requestId, httpStatus: httpStatus && Number.isInteger(httpStatus) && httpStatus >= 200 && httpStatus < 300 ? httpStatus : undefined };
    const parsed = transcriptionLanguageSchema.safeParse({ languages: response.languages });
    if (!parsed.success) {
      throw new LanguageDetectionProviderError("provider_response_invalid", "provider_response_validation", metadata);
    }
    const languageCountClassification = parsed.data.languages.length === 0 ? "zero_languages"
      : parsed.data.languages.length === 1 ? "one_language" : "multiple_languages";
    const classifiedMetadata: ProviderErrorMetadata = { ...metadata, languageCountClassification };
    if (languageCountClassification !== "one_language") {
      throw new LanguageDetectionProviderError("no_reliable_language", "provider_response_validation", classifiedMetadata);
    }

    const language = normalizeLanguageCode(parsed.data.languages[0].code);
    const proposal = language && normalizedLanguageProposalSchema.safeParse({
      provider: "openai",
      model: LANGUAGE_MODEL,
      proposedLanguageCode: language.code,
      proposedLanguageName: language.name,
      confidence: null,
      detectedAt: new Date().toISOString(),
      sourceMediaId: input.sourceMediaArtifactId,
      sourceMediaHash: input.sourceMediaHash,
      providerRequestId: requestId,
    });
    if (!proposal || !proposal.success) {
      throw new LanguageDetectionProviderError("provider_response_invalid", "provider_response_validation", classifiedMetadata);
    }
    return proposal.data;
  }
}

export function createLanguageDetectionProvider(): LanguageDetectionProvider {
  return new OpenAILanguageDetectionProvider();
}

export function isTranscriptionEligible(input: {
  mediaVerified: boolean;
  currentSourceVersion: boolean;
  decisionStatus: "PROPOSED" | "CONFIRMED" | "CORRECTED" | null;
  confirmedLanguageCode: string | null;
  confirmerIsOwner: boolean;
}): boolean {
  return input.mediaVerified
    && input.currentSourceVersion
    && (input.decisionStatus === "CONFIRMED" || input.decisionStatus === "CORRECTED")
    && input.confirmedLanguageCode === "yor"
    && input.confirmerIsOwner;
}

export function isMvpSupportedLanguage(languageCode: string) {
  return languageCode === "yor";
}
