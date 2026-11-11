"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export type TranscriptSegment = {
  id: string;
  segment_number: number;
  source_start_ms: number;
  source_end_ms: number;
  initial_proposal: string | null;
  text_yoruba: string;
};
export type TranscriptReview = {
  artifact_version_id: string;
  source_media_artifact_id: string;
  language_code: string;
  approved: boolean;
  segments: TranscriptSegment[];
};

async function postJson(url: string, body: unknown) {
  const response = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), cache: "no-store" });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(typeof payload.error === "string" ? payload.error : "The request could not complete.");
  return payload as { transcriptArtifactId?: string };
}

function timestamp(value: number) {
  const totalSeconds = Math.floor(value / 1000);
  return `${Math.floor(totalSeconds / 60).toString().padStart(2, "0")}:${(totalSeconds % 60).toString().padStart(2, "0")}`;
}

export function VerifyTranscriptReview(props: {
  storyId: string;
  sourceMediaArtifactId: string;
  transcriptionEligible: boolean;
  transcript: TranscriptReview | null;
}) {
  const router = useRouter();
  const [consent, setConsent] = useState(false);
  const [drafts, setDrafts] = useState<string[]>(props.transcript?.segments.map((segment) => segment.text_yoruba) ?? []);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  async function act(url: string, body: unknown, message: string) {
    setBusy(true); setError(null); setSuccess(null);
    try { await postJson(url, body); setSuccess(message); router.refresh(); }
    catch (cause) { setError(cause instanceof Error ? cause.message : "The request could not complete."); }
    finally { setBusy(false); }
  }

  const transcript = props.transcript;
  const hasEdits = transcript?.segments.some((segment, index) => drafts[index] !== segment.text_yoruba) ?? false;
  return <section className="tell-panel" aria-labelledby="yoruba-transcript-heading">
    <span className="field-label">VERIFY B · YORUBA SOURCE TRANSCRIPT</span>
    <h2 id="yoruba-transcript-heading">Yoruba transcript</h2>
    {!transcript && !props.transcriptionEligible && <p>Transcription is available after the current verified source has an explicitly confirmed Yoruba language.</p>}
    {!transcript && props.transcriptionEligible && <>
      <p>AI will prepare a Yoruba transcript with timestamps. You can review and correct every segment before approval.</p>
      <label className="upload-help"><input checked={consent} onChange={(event) => setConsent(event.target.checked)} type="checkbox" /> I agree to send the current source audio to OpenAI to create a Yoruba transcript.</label>
      <button className="button button--primary" disabled={busy || !consent} onClick={() => void act(`/api/stories/${props.storyId}/transcribe`, { intent: "transcribe", processingConsent: true }, "Yoruba transcript created.")} type="button">{busy ? "Transcribing…" : "Create Yoruba transcript"}</button>
    </>}
    {transcript && <>
      <p>Transcript version for this source · language: Yoruba</p>
      {transcript.segments.map((segment, index) => <div className="transcript-segment" key={segment.id}>
        <label htmlFor={`transcript-segment-${index + 1}`}>
          <span>{timestamp(segment.source_start_ms)}–{timestamp(segment.source_end_ms)}</span>
          <span className="sr-only">Segment {index + 1}</span>
        </label>
        <textarea id={`transcript-segment-${index + 1}`} maxLength={10_000} onChange={(event) => setDrafts((previous) => previous.map((text, i) => i === index ? event.target.value : text))} value={drafts[index] ?? ""} />
      </div>)}
      <details className="transcript-original">
        <summary>View AI-original transcript</summary>
        {transcript.segments.map((segment, index) => <p key={segment.id}><span>{index + 1}. </span>{segment.initial_proposal ?? segment.text_yoruba}</p>)}
      </details>
      <button className="button button--quiet" disabled={busy || !hasEdits} onClick={() => void act(
        `/api/stories/${props.storyId}/transcripts/${transcript.artifact_version_id}/edit`,
        { segments: drafts.map((text, index) => ({ segmentNumber: index + 1, text })) },
        "Your corrections were saved as a new transcript version.",
      )} type="button">Save corrections as new version</button>
      {transcript.approved
        ? <p role="status">Approved by storyteller for this exact transcript version.</p>
        : <button className="button button--primary" disabled={busy} onClick={() => void act(
          `/api/stories/${props.storyId}/transcripts/${transcript.artifact_version_id}/approve`,
          { intent: "approve_source" },
          "Yoruba source transcript approved.",
        )} type="button">Approve Yoruba Source</button>}
    </>}
    {error && <p className="form-error" role="alert">{error}</p>}
    {success && <p role="status">{success}</p>}
  </section>;
}
