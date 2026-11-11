"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export type TranslationReviewSegment = {
  id: string; cut_segment_id: string; transcript_segment_id: string; cue_start_ms: number; cue_end_ms: number;
  source_start_ms: number; source_end_ms: number; english_text: string; initial_proposal: string | null; yoruba_text: string;
};

function time(ms: number) {
  const total = Math.floor(ms / 1000);
  return `${Math.floor(total / 60).toString().padStart(2, "0")}:${(total % 60).toString().padStart(2, "0")}`;
}

export function TranslationReview(props: { storyId: string; cutApproved: boolean; translation: null | { artifactId: string; approved: boolean; segments: TranslationReviewSegment[] } }) {
  const router = useRouter();
  const [drafts, setDrafts] = useState(props.translation?.segments.map((segment) => segment.english_text) ?? []);
  const [consent, setConsent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const hasEdits = props.translation?.segments.some((segment, index) => drafts[index] !== segment.english_text) ?? false;

  async function post(url: string, body: unknown, success: string) {
    setBusy(true); setError(""); setMessage("");
    try {
      const response = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), cache: "no-store" });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(typeof data.error === "string" ? data.error : "The translation could not be saved.");
      setMessage(success); router.refresh();
    } catch (cause) { setError(cause instanceof Error ? cause.message : "The translation could not be saved."); }
    finally { setBusy(false); }
  }

  return <section className="tell-panel" aria-labelledby="translation-heading">
    <span className="field-label">TRANSLATE · YORUBA TO ENGLISH</span>
    <h2 id="translation-heading">English translation</h2>
    {!props.cutApproved ? <p>Approve the current Story Cut before creating its English translation.</p> : <>
      <p role="note">English translation is AI-assisted. Review and approve every segment before it can proceed.</p>
      {!props.translation && <>
        <label className="upload-help"><input type="checkbox" checked={consent} onChange={(event) => setConsent(event.target.checked)} /> I agree to send the approved Story Cut’s Yoruba transcript segments to OpenAI for an English translation proposal.</label>
        <button className="button button--primary" type="button" disabled={busy || !consent} onClick={() => void post(`/api/stories/${props.storyId}/translations`, { intent: "create_proposal", processingConsent: true }, "English translation proposal created.")}>{busy ? "Translating…" : "Create English translation proposal"}</button>
      </>}
      {props.translation && <>
        <div className="translation-columns" aria-label="Yoruba and English translation segments">
          <h3>Yoruba · approved Story Cut</h3><h3>English · AI-assisted proposal</h3>
          {props.translation.segments.map((segment, index) => <div className="translation-row" key={segment.id}>
            <div><p className="upload-help">Source video {time(segment.source_start_ms)}–{time(segment.source_end_ms)} · Story Cut {time(segment.cue_start_ms)}–{time(segment.cue_end_ms)}</p><p>{segment.yoruba_text}</p></div>
            <div><label className="sr-only" htmlFor={`english-translation-${index + 1}`}>English segment {index + 1}</label><textarea id={`english-translation-${index + 1}`} maxLength={10_000} value={drafts[index] ?? ""} onChange={(event) => setDrafts((previous) => previous.map((text, i) => i === index ? event.target.value : text))} />
              <details><summary>View AI-original English</summary><p>{segment.initial_proposal ?? segment.english_text}</p></details></div>
          </div>)}
        </div>
        {props.translation.approved && <p role="status">Approved by storyteller for this exact English translation version and hash.</p>}
        <button className="button button--quiet" type="button" disabled={busy || !hasEdits} onClick={() => void post(`/api/stories/${props.storyId}/translations`, { intent: "save_edits", segments: props.translation?.segments.map((segment, index) => ({ translationSegmentId: segment.id, englishText: drafts[index] ?? "" })) }, "Your English corrections were saved as a new version.")}>Save corrections as new version</button>
        {!props.translation.approved && <button className="button button--primary" type="button" disabled={busy || hasEdits} onClick={() => void post(`/api/stories/${props.storyId}/translations/${props.translation?.artifactId}/approve`, { intent: "approve_english_translation" }, "English translation approved for this exact version.")}>Approve English Translation</button>}
      </>}
    </>}
    {error && <p className="form-error" role="alert">{error}</p>}{message && <p role="status">{message}</p>}
  </section>;
}
