"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import type { ReactNode } from "react";

type Verification = {
  id: string;
  status: string;
  actual_container: string;
  actual_format_names: string;
  actual_duration_ms: number;
  has_video: boolean;
  has_audio: boolean;
  audio_codec: string | null;
  video_codec: string | null;
  video_width: number | null;
  video_height: number | null;
  client_metadata_mismatches: Array<{ field: string; reported: string; verified: string }>;
};

type LanguageReview = {
  id: string;
  review_status: "PROPOSED" | "CONFIRMED" | "CORRECTED";
  detected_language_code: string;
  detected_language_name: string;
  detection_confidence: number | null;
  confirmed_language_code: string | null;
  confirmed_language_name: string | null;
};

type Props = {
  storyId: string;
  sourceMediaArtifactId: string;
  filename: string;
  playbackUrl: string;
  verification: Verification | null;
  latestReview: LanguageReview | null;
  transcriptionEligible: boolean;
  humanDecision: { id: string; state: "selected" | "confirmed" | "superseded" | "invalidated"; selected_language_code: string; selected_language_name: string; decision_origin: string } | null;
  noReliableDetection: boolean;
  transcriptPanel?: ReactNode;
};

async function postJson(url: string, body?: unknown) {
  const response = await fetch(url, {
    method: "POST",
    headers: body ? { "Content-Type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
    cache: "no-store",
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = typeof payload.error === "string" ? payload.error : "The request could not complete. Please retry.";
    const reference = typeof payload.correlationId === "string" && /^[a-f0-9-]{36}$/i.test(payload.correlationId)
      ? ` Support reference ${payload.correlationId}.`
      : "";
    throw new Error(message + reference);
  }
  return payload;
}

export function VerifyLanguagePanel(props: Props) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [processingConsent, setProcessingConsent] = useState(false);
  const [showCorrection, setShowCorrection] = useState(false);
  const [languageName, setLanguageName] = useState("");
  const [languageCode, setLanguageCode] = useState("");

  async function run(url: string, body?: unknown) {
    setBusy(true); setError(null); setSuccess(null);
    try {
      const response = await postJson(url, body);
      if (response.status === "REJECTED") {
        setError(response.message || "This source is not ready. Choose another video.");
        router.refresh();
        return;
      }
      setSuccess(response.message || "Your decision was saved.");
      router.refresh();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "The request failed. Please retry.");
    } finally {
      setBusy(false);
    }
  }

  const review = props.latestReview;
  const proposalPending = review?.review_status === "PROPOSED";
  const decisionSaved = review && !proposalPending;
  const unsupported = decisionSaved && review.confirmed_language_code !== "yor";

  async function saveDecision(code: string, name: string) {
    await run(`/api/stories/${props.storyId}/confirm-language`, {
      sourceMediaArtifactId: props.sourceMediaArtifactId,
      proposalReviewId: review?.id,
      languageCode: code,
      displayName: name,
    });
    setShowCorrection(false);
  }

  return (
    <div className="stage-content-stack">
      <section className="tell-panel" aria-labelledby="verify-source-heading">
        <span className="field-label">PRIVATE SOURCE · SERVER VERIFICATION</span>
        <h2 id="verify-source-heading">{props.filename}</h2>
        <video className="verify-private-video" controls preload="metadata" src={props.playbackUrl} />
        <p className="upload-help">Playback is owner-authorized and temporary. The original video remains private.</p>
        {(!props.verification || props.verification.status === "REJECTED") && <button className="button button--primary" disabled={busy} onClick={() => void run(`/api/stories/${props.storyId}/verify-media`)} type="button">
          {busy ? "Verifying source…" : props.verification ? "Retry media verification" : "Verify source media"}
        </button>}
        {props.verification && <>
          <p className={props.verification.status === "READY" ? "upload-status" : "form-error"}>
            {props.verification.status === "READY" ? "Source verified" : "Source could not be verified"} · {props.verification.actual_container} · {Math.round(props.verification.actual_duration_ms / 1000)} seconds
          </p>
          <p className="upload-help">
            Video: {props.verification.video_codec ?? "none"}{props.verification.video_width && props.verification.video_height ? ` · ${props.verification.video_width}×${props.verification.video_height}` : ""} · Audio: {props.verification.audio_codec ?? "none"}
          </p>
          {props.verification.client_metadata_mismatches.length > 0 && <div role="status">
            <strong>Reported upload metadata differs from the server check.</strong>
            <ul>{props.verification.client_metadata_mismatches.map((item) => <li key={item.field}>{item.field}: uploaded value {item.reported}; verified value {item.verified}</li>)}</ul>
          </div>}
        </>}
      </section>

      {props.verification?.status === "READY" && <section className="tell-panel" aria-labelledby="original-language-heading">
        <span className="field-label">{props.noReliableDetection ? "YOUR LANGUAGE SELECTION" : "AI PROPOSAL · YOUR DECISION"}</span>
        <h2 id="original-language-heading">Original language</h2>
        {proposalPending && review && <>
          <p>Detected: <strong lang={review.detected_language_code}>{review.detected_language_name}</strong></p>
          {review.detection_confidence !== null && <p className="upload-help">Provider confidence: {Math.round(review.detection_confidence * 100)}%</p>}
          <h3>Is {review.detected_language_name} correct?</h3>
          <p>AI proposes. You decide. Confirming anything other than Yoruba records your choice, but transcription is not available for that language in this MVP.</p>
          <div className="language-confirmation-actions">
            <button className="button button--primary" disabled={busy} onClick={() => void saveDecision(review.detected_language_code, review.detected_language_name)} type="button">Yes, continue</button>
            <button className="button button--quiet" disabled={busy} onClick={() => { setShowCorrection(true); setLanguageName(""); setLanguageCode(""); }} type="button">Change language</button>
          </div>
        </>}
        {decisionSaved && review && <>
          <p>Confirmed by you: <strong lang={review.confirmed_language_code ?? undefined}>{review.confirmed_language_name}</strong></p>
          {unsupported
            ? <p role="status">{review.confirmed_language_name} is saved as your correction. Transcription is not available for this language in the MVP.</p>
            : <p role="status">Yoruba is confirmed for this source version. AI output has not been created or approved.</p>}
        </>}
        {props.noReliableDetection && !review && props.humanDecision?.state !== "confirmed" && <>
          <p>We couldn&apos;t identify the original language reliably. You can try detection again or tell Irin Stories what language you used.</p>
          <p><strong>Original language</strong></p><p>Yoruba</p>
          <p className="upload-help">Yoruba is the only original language currently supported for transcription in this MVP.</p>
          {(!props.humanDecision || props.humanDecision.state === "superseded" || props.humanDecision.state === "invalidated") && <button className="button button--primary" disabled={busy} onClick={async () => {
            setBusy(true); setError(null);
            try { await postJson(`/api/stories/${props.storyId}/select-language`, { languageCode: "yor", intent: "select" }); router.refresh(); }
            catch (cause) { setError(cause instanceof Error ? cause.message : "Selection failed."); }
            finally { setBusy(false); }
          }} type="button">Select Yoruba</button>}
          <label className="upload-help"><input checked={processingConsent} onChange={(event) => setProcessingConsent(event.target.checked)} type="checkbox" /> I agree to send this audio sample to OpenAI for original-language identification.</label>
          <button className="button button--quiet" disabled={busy || !processingConsent} onClick={() => void run(`/api/stories/${props.storyId}/detect-language`, { sourceMediaArtifactId: props.sourceMediaArtifactId, processingConsent })} type="button">Try detection again</button>
        </>}
        {props.humanDecision?.state === "selected" && <>
          <p>You selected {props.humanDecision.selected_language_name} as the original language.</p>
          <p>Please confirm that this is correct for the current source video.</p>
          <p role="status">Selected, awaiting confirmation</p><p>Transcription: Not yet eligible</p>
          <button className="button button--primary" disabled={busy} onClick={async () => {
            setBusy(true); setError(null);
            try { await postJson(`/api/stories/${props.storyId}/confirm-language`, { decisionId: props.humanDecision!.id, intent: "confirm" }); router.refresh(); }
            catch (cause) { setError(cause instanceof Error ? cause.message : "Confirmation failed."); }
            finally { setBusy(false); }
          }} type="button">Confirm Yoruba</button>
          <button className="button button--quiet" disabled={busy} onClick={async () => {
            setBusy(true); setError(null);
            try { await postJson(`/api/stories/${props.storyId}/select-language`, { languageCode: "yor", intent: "select" }); router.refresh(); }
            catch (cause) { setError(cause instanceof Error ? cause.message : "Selection change failed."); }
            finally { setBusy(false); }
          }} type="button">Change selection</button>
        </>}
        {props.humanDecision?.state === "confirmed" && props.humanDecision.decision_origin === "storyteller_selected" && <>
          <p>Original language: <strong>Yoruba</strong></p><p>Confirmed by storyteller</p>
          <p>Transcription: {props.transcriptionEligible ? "Eligible for the next Verify step" : "Not yet eligible; this language is not supported for transcription in this MVP."}</p>
        </>}
        {!review && !props.noReliableDetection && !props.humanDecision && <>
          <p>A language proposal sends up to 90 seconds of this verified source audio to OpenAI. The provider may generate transcript text internally; Irin Stories discards it and stores only detected language and safe request metadata.</p>
          <p className="upload-help">Yoruba is the only language supported for transcription in this MVP. A different proposal can be corrected and saved, but it cannot proceed to transcription.</p>
          <label className="upload-help"><input checked={processingConsent} onChange={(event) => setProcessingConsent(event.target.checked)} type="checkbox" /> I agree to send this audio sample to OpenAI for original-language identification.</label>
          <button className="button button--primary" disabled={busy || !processingConsent} onClick={() => void run(`/api/stories/${props.storyId}/detect-language`, {
            sourceMediaArtifactId: props.sourceMediaArtifactId,
            processingConsent,
          })} type="button">
            {busy ? "Detecting language…" : "Detect original language"}
          </button>
        </>}
        {showCorrection && review && <form className="language-correction-form" onSubmit={(event) => {
          event.preventDefault();
          void saveDecision(languageCode.trim().toLowerCase(), languageName.trim());
        }}>
          <label htmlFor="correction-name">Language name</label>
          <input id="correction-name" autoComplete="off" maxLength={120} onChange={(event) => setLanguageName(event.target.value)} required value={languageName} />
          <label htmlFor="correction-code">ISO 639-3 language code</label>
          <input id="correction-code" autoComplete="off" maxLength={3} minLength={3} pattern="[a-z]{3}" onChange={(event) => setLanguageCode(event.target.value.toLowerCase())} placeholder="e.g. yor" required value={languageCode} />
          <p className="upload-help">Only Yoruba (yor) is supported for transcription in this MVP. Other corrections are recorded without enabling transcription.</p>
          <div className="language-confirmation-actions">
            <button className="button button--primary" disabled={busy} type="submit">Save correction</button>
            <button className="button button--quiet" disabled={busy} onClick={() => setShowCorrection(false)} type="button">Cancel</button>
          </div>
        </form>}
        {props.transcriptionEligible && <p role="status">This exact source has a supported, storyteller-confirmed original language and is eligible for a future stage.</p>}
      </section>}
      {props.transcriptPanel}
      {error && <p className="form-error" role="alert">{error}</p>}
      {success && <p className="upload-status" role="status">{success}</p>}
    </div>
  );
}
