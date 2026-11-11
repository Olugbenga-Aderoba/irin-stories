import { createHash, randomUUID } from "node:crypto";
import { createWriteStream } from "node:fs";
import { join } from "node:path";
import { Readable, Transform } from "node:stream";
import { pipeline } from "node:stream/promises";
import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  detectionFailures,
  diagnosticRecordSchema,
  safeDiagnosticErrorType,
  safeDiagnosticErrorCode,
  safeProviderRequestId,
  safeDatabaseCode,
  type DetectionFailureCategory,
  type DetectionStage,
} from "@/lib/verify/detection-diagnostics";
import { SpeechActivityError, TemporaryMediaCleanupError, withTemporaryAudioSample, withTemporaryMediaDirectory } from "@/lib/verify/media-probe";
import {
  createLanguageDetectionProvider,
  LANGUAGE_MODEL,
  LanguageDetectionProviderError,
  LanguageDetectionUnavailableError,
  normalizedLanguageProposalSchema,
} from "@/lib/verify/language";

const requestSchema = z.object({
  sourceMediaArtifactId: z.string().uuid(),
  processingConsent: z.literal(true),
}).strict();

const MAX_SOURCE_BYTES = 524_288_000;

function sourceHash(value: string) {
  const normalized = value.replace(/^\\x/i, "");
  return /^[a-f0-9]{64}$/i.test(normalized) ? normalized.toLowerCase() : null;
}

class RouteFailure extends Error {
  constructor(
    readonly category: DetectionFailureCategory,
    readonly status: number = detectionFailures[category][0],
    message: string = detectionFailures[category][2],
    readonly retryable: boolean = detectionFailures[category][1],
  ) {
    super(message);
  }
}

async function recordSafeFailure(storyId: string, sourceMediaId: string, category: string, userId: string) {
  try {
    const admin = createSupabaseAdminClient();
    await admin.rpc("record_language_detection_failure", {
      p_story_id: storyId,
      p_source_media_artifact_id: sourceMediaId,
      p_error_category: category,
      p_requested_by: userId,
    });
  } catch {
    // The structured server diagnostic is already recorded.
  }
}

async function persistDiagnostic(event: Record<string, unknown>) {
  try {
    const admin = createSupabaseAdminClient();
    await admin.from("verify_language_detection_diagnostics").insert(diagnosticRecordSchema.parse(event));
  } catch {
    // Never let diagnostic storage change the browser response or expose internals.
  }
}

export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string }> }) {
  const correlationId = randomUUID();
  const attemptedAt = new Date().toISOString();
  let stage: DetectionStage = "ownership_check";
  const currentStage = (): DetectionStage => stage;
  let auditTarget: { storyId: string; sourceMediaId: string; userId: string } | undefined;
  let diagnosticStoryId: string | null = null;
  let databaseCode: string | null = null;
  let proposalRequestId: string | null = null;

  try {
    const origin = request.headers.get("origin");
    if (origin && origin !== new URL(request.url).origin) {
      throw new RouteFailure("unknown_detection_failure", 403, "Request origin was not accepted.", false);
    }
    const { storyId } = await context.params;
    if (!z.string().uuid().safeParse(storyId).success) {
      throw new RouteFailure("unknown_detection_failure", 404, "Story not found.", false);
    }
    const body = requestSchema.safeParse(await request.json().catch(() => null));
    if (!body.success) {
      throw new RouteFailure("unknown_detection_failure", 400, "Explicitly consent to language identification and provide the current source version.", false);
    }

    const supabase = await createSupabaseServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new RouteFailure("unknown_detection_failure", 401, "Sign in to request language detection.", false);

    const { data: story, error: storyError } = await supabase.from("stories").select("id,owner_id").eq("id", storyId).maybeSingle();
    if (storyError) throw new RouteFailure("unknown_detection_failure");
    if (!story || story.owner_id !== user.id) {
      throw new RouteFailure("unknown_detection_failure", 404, "Story not found.", false);
    }

    diagnosticStoryId = storyId;
    stage = "source_lookup";
    const { data: sources, error: sourcesError } = await supabase.from("media_assets")
      .select("artifact_version_id,object_key,bucket_id,role")
      .eq("story_id", storyId)
      .eq("role", "SOURCE")
      .order("created_at", { ascending: false })
      .limit(1);
    if (sourcesError) throw new RouteFailure("unknown_detection_failure");
    const source = sources?.[0];
    if (!source || source.bucket_id !== "private-source" || source.artifact_version_id !== body.data.sourceMediaArtifactId) {
      throw new RouteFailure("unknown_detection_failure", 404, "The current registered source version was not found.", false);
    }

    const { data: verification, error: verificationError } = await supabase.from("source_media_verifications")
      .select("status,verification_number,server_content_sha256")
      .eq("story_id", storyId)
      .eq("source_media_artifact_id", source.artifact_version_id)
      .order("verification_number", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (verificationError) throw new RouteFailure("unknown_detection_failure");
    const verifiedHash = verification && sourceHash(verification.server_content_sha256);
    if (!verification || verification.status !== "READY" || !verifiedHash) {
      throw new RouteFailure("media_processing_failed", 409, "Verify the current source media before requesting language detection.", false);
    }

    auditTarget = { storyId, sourceMediaId: source.artifact_version_id, userId: user.id };
    stage = "provider_request";
    if (!process.env.OPENAI_API_KEY) throw new LanguageDetectionUnavailableError();

    stage = "source_download";
    const proposal = await withTemporaryMediaDirectory("irin-language-", async (directory) => {
      const { data: signed, error: signError } = await supabase.storage
        .from("private-source")
        .createSignedUrl(source.object_key, 300);
      if (signError || !signed) throw new RouteFailure("media_processing_failed", 502, "The private source could not be retrieved. Please retry.");

      const response = await fetch(signed.signedUrl, { cache: "no-store", signal: AbortSignal.timeout(15 * 60_000) });
      if (!response.ok || !response.body) {
        throw new RouteFailure("media_processing_failed", 502, "The private source could not be downloaded. Please retry.");
      }

      const videoPath = join(directory, "source-video");
      const digest = createHash("sha256");
      let downloadedBytes = 0;
      const tooLarge = () => new RouteFailure("media_processing_failed", 413, "The source exceeds the 500 MiB verification limit.", false);
      if (Number(response.headers.get("content-length")) > MAX_SOURCE_BYTES) throw tooLarge();

      const limiter = new Transform({
        transform(chunk: Buffer, _encoding, callback) {
          downloadedBytes += chunk.byteLength;
          if (downloadedBytes > MAX_SOURCE_BYTES) return callback(tooLarge());
          digest.update(chunk);
          callback(null, chunk);
        },
      });
      await pipeline(
        Readable.fromWeb(response.body as unknown as Parameters<typeof Readable.fromWeb>[0]),
        limiter,
        createWriteStream(videoPath, { flags: "wx" }),
      );

      stage = "hash_verification";
      if (digest.digest("hex") !== verifiedHash) {
        throw new RouteFailure("media_processing_failed", 409, "The current source no longer matches its verified content. Verify it again.", false);
      }

      stage = "audio_extraction";
      return withTemporaryAudioSample(videoPath, async (audioPath) => {
        stage = "provider_request";
        const provider = createLanguageDetectionProvider();
        const result = await provider.detectLanguage({
          audioPath,
          sourceMediaArtifactId: source.artifact_version_id,
          sourceMediaHash: verifiedHash,
        });
        stage = "provider_response_validation";
        const parsed = normalizedLanguageProposalSchema.safeParse(result);
        if (!parsed.success || parsed.data.sourceMediaId !== source.artifact_version_id || parsed.data.sourceMediaHash !== verifiedHash) {
          throw new LanguageDetectionProviderError("provider_response_invalid", "provider_response_validation");
        }
        return parsed.data;
      }, () => { stage = "speech_validation"; });
    });

    stage = "proposal_persistence";
    console.info("verify_language_response_classified", { correlationId, languageCountClassification: "one_language" });
    proposalRequestId = proposal.providerRequestId;
    const admin = createSupabaseAdminClient();
    const { data: proposalId, error: proposalError } = await admin.rpc("create_source_language_proposal", {
      p_story_id: storyId,
      p_source_media_artifact_id: proposal.sourceMediaId,
      p_detected_language_code: proposal.proposedLanguageCode,
      p_detected_language_name: proposal.proposedLanguageName,
      p_detection_confidence: proposal.confidence,
      p_detector_name: proposal.provider,
      p_detector_model: proposal.model,
      p_provider_request_id: proposal.providerRequestId,
    });
    if (proposalError || !proposalId) {
      databaseCode = safeDatabaseCode(proposalError?.code);
      throw new RouteFailure("proposal_persistence_failed");
    }
    return NextResponse.json({
      proposalId,
      reviewStatus: "PROPOSED",
      message: `Detected ${proposal.proposedLanguageName}. Please review the proposal and decide whether it is correct.`,
      proposedLanguageCode: proposal.proposedLanguageCode,
      proposedLanguageName: proposal.proposedLanguageName,
      confidence: null,
      detectedAt: proposal.detectedAt,
      sourceMediaId: proposal.sourceMediaId,
      provider: proposal.provider,
      model: proposal.model,
      providerRequestId: proposal.providerRequestId,
    }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    const providerError = error instanceof LanguageDetectionProviderError ? error : null;
    const failedStage = providerError?.stage ?? (error instanceof TemporaryMediaCleanupError ? "cleanup" : currentStage());
    const fallbackCategory = failedStage === "proposal_persistence" ? "proposal_persistence_failed"
      : error instanceof SpeechActivityError ? "no_reliable_language"
      : failedStage === "source_download" || failedStage === "audio_extraction" || failedStage === "speech_validation" || failedStage === "cleanup" ? "media_processing_failed"
      : "unknown_detection_failure";
    const failure = error instanceof RouteFailure ? error : new RouteFailure(
      providerError?.category ?? (error instanceof LanguageDetectionUnavailableError ? "provider_not_configured" : fallbackCategory),
    );
    const requestId = safeProviderRequestId(providerError?.metadata.requestId ?? proposalRequestId);
    const diagnostic = {
      correlationId, attemptedAt, stage: failedStage, category: failure.category, retryable: failure.retryable,
      storyId: diagnosticStoryId,
      provider: "openai", model: LANGUAGE_MODEL,
      providerHttpStatus: providerError?.metadata.httpStatus ?? null,
      providerErrorType: safeDiagnosticErrorType(providerError?.metadata.errorType),
      providerErrorCode: safeDiagnosticErrorCode(providerError?.metadata.errorCode),
      providerRequestId: requestId,
      transport: providerError?.metadata.transport ?? null,
      databaseCode,
      // Log only: the current database contract has no language-count column.
      languageCountClassification: z.enum(["zero_languages", "one_language", "multiple_languages"])
        .safeParse(providerError?.metadata.languageCountClassification).data ?? (proposalRequestId ? "one_language" : null),
    };
    console.warn("verify_language_detection_failed", diagnostic);
    await persistDiagnostic({
      correlation_id: correlationId, story_id: diagnosticStoryId,
      attempted_at: attemptedAt, stage: failedStage, category: failure.category,
      retryable: failure.retryable, provider: "openai", model: LANGUAGE_MODEL,
      provider_http_status: diagnostic.providerHttpStatus,
      provider_error_type: diagnostic.providerErrorType, provider_error_code: diagnostic.providerErrorCode,
      provider_request_id: requestId, transport: diagnostic.transport, database_code: databaseCode,
    });
    if (auditTarget) {
      // Keep the deployed RPC's existing allowlist while server logs retain the detailed category.
      const category = failure.category;
      const auditCategory = category === "provider_not_configured" || category === "provider_timeout" ? category
        : category === "no_reliable_language" && failedStage === "speech_validation" ? "speech_not_established"
        : category === "no_reliable_language" ? category : "provider_error";
      await recordSafeFailure(auditTarget.storyId, auditTarget.sourceMediaId, auditCategory, auditTarget.userId);
    }
    return NextResponse.json({
      category: failure.category, retryable: failure.retryable, stage: failedStage, error: failure.message, correlationId,
    }, { status: failure.status, headers: { "Cache-Control": "no-store" } });
  }
}
