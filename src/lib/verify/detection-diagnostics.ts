import { z } from "zod";

export const detectionFailures = {
  provider_not_configured: [503, true, "Language detection is unavailable. Ask support to check the API configuration."],
  provider_authentication_failed: [502, false, "Ask support to check the language detection API credentials."],
  provider_permission_denied: [502, false, "Ask support to check the language detection API permissions."],
  provider_model_unavailable: [502, false, "Ask support to check which language detection model is available."],
  provider_payload_too_large: [422, false, "The prepared audio sample is too large for language detection."],
  provider_quota_or_rate_limit: [503, true, "Language detection is temporarily limited. Retry later or ask support to check API quota and billing."],
  provider_temporarily_unavailable: [503, true, "The language detection provider is temporarily unavailable. Retry later."],
  provider_timeout: [504, true, "Language detection timed out. Please retry."],
  provider_network_failure: [503, true, "Language detection could not connect to the provider. Please retry."],
  no_reliable_language: [422, true, "A single language could not be identified reliably. Try a recording with clearer speech."],
  provider_response_invalid: [502, true, "The language detection provider returned an unexpected result. Please retry."],
  proposal_persistence_failed: [500, true, "The language proposal could not be saved. Please retry or contact support."],
  media_processing_failed: [422, true, "The private source could not be prepared for language detection. Please retry."],
  unknown_detection_failure: [500, true, "Language detection could not complete. Please retry or contact support."],
} as const;

export type DetectionFailureCategory = keyof typeof detectionFailures;
export type DetectionStage =
  | "ownership_check"
  | "source_lookup"
  | "source_download"
  | "hash_verification"
  | "audio_extraction"
  | "speech_validation"
  | "provider_request"
  | "provider_response_validation"
  | "proposal_persistence"
  | "cleanup";

export function safeProviderRequestId(value: unknown) {
  return typeof value === "string" && /^req_[a-f0-9]{32}$/i.test(value) ? value : null;
}

export function safeDatabaseCode(value: unknown) {
  return typeof value === "string" && /^[A-Z0-9]{5}$/.test(value) ? value : null;
}

export const diagnosticErrorTypes = ["invalid_request_error", "authentication_error", "permission_error", "rate_limit_error", "insufficient_quota", "server_error", "api_error", "timeout", "connection_error"] as const;
export const diagnosticErrorCodes = ["invalid_api_key", "invalid_request_error", "permission_denied", "model_not_found", "request_too_large", "payload_too_large", "rate_limit_exceeded", "insufficient_quota", "billing_hard_limit_reached", "server_error", "service_unavailable"] as const;

export const diagnosticRecordSchema = z.object({
  correlation_id: z.string().uuid(),
  story_id: z.string().uuid().nullable(),
  attempted_at: z.string().datetime(),
  stage: z.enum(["ownership_check", "source_lookup", "source_download", "hash_verification", "audio_extraction", "speech_validation", "provider_request", "provider_response_validation", "proposal_persistence", "cleanup"]),
  category: z.enum(Object.keys(detectionFailures) as [DetectionFailureCategory, ...DetectionFailureCategory[]]),
  retryable: z.boolean(),
  provider: z.literal("openai").nullable(),
  model: z.literal("gpt-transcribe").nullable(),
  provider_http_status: z.number().int().min(100).max(599).nullable(),
  provider_error_type: z.enum(diagnosticErrorTypes).nullable(),
  provider_error_code: z.enum(diagnosticErrorCodes).nullable(),
  provider_request_id: z.string().regex(/^req_[a-f0-9]{32}$/i).nullable(),
  transport: z.enum(["timeout", "network"]).nullable(),
  database_code: z.string().regex(/^[A-Z0-9]{5}$/).nullable(),
}).strict().refine((event) => event.story_id !== null || event.stage === "ownership_check");
export function safeDiagnosticErrorType(value: unknown) {
  const parsed = z.enum(diagnosticErrorTypes).safeParse(value);
  return parsed.success ? parsed.data : null;
}
export function safeDiagnosticErrorCode(value: unknown) {
  const parsed = z.enum(diagnosticErrorCodes).safeParse(value);
  return parsed.success ? parsed.data : null;
}
