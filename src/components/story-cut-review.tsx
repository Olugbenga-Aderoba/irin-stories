"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export type StoryCutItem = { id: string; transcript_segment_id: string; source_start_ms: number; source_end_ms: number; output_start_ms: number; output_end_ms: number; narrative_role: string; selection_rationale: string; text_yoruba: string };

function time(ms: number) {
  const seconds = Math.floor(ms / 1000);
  return `${Math.floor(seconds / 60).toString().padStart(2, "0")}:${(seconds % 60).toString().padStart(2, "0")}`;
}

export function StoryCutReview(props: { storyId: string; sourceUrl: string; transcriptApproved: boolean; transcriptSegments: { id: string; source_start_ms: number; source_end_ms: number; text_yoruba: string }[]; cut: null | { artifactId: string; durationMs: number; approved: boolean; segments: StoryCutItem[] } }) {
  const router = useRouter();
  const [items, setItems] = useState(props.cut?.segments ?? []);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const duration = items.reduce((total, item) => total + item.source_end_ms - item.source_start_ms, 0);
  const hasChanges = Boolean(props.cut && (items.length !== props.cut.segments.length || items.some((item, index) => item.id !== props.cut?.segments[index]?.id)));

  async function post(url: string, body: unknown, success: string) {
    setBusy(true); setError(""); setMessage("");
    try {
      const response = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), cache: "no-store" });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(typeof data.error === "string" ? data.error : "The Story Cut could not be saved.");
      setMessage(success); router.refresh();
    } catch (cause) { setError(cause instanceof Error ? cause.message : "The Story Cut could not be saved."); }
    finally { setBusy(false); }
  }

  function move(index: number, offset: number) {
    setItems((current) => { const next = [...current]; const target = index + offset; if (target < 0 || target >= next.length) return current; [next[index], next[target]] = [next[target], next[index]]; return next; });
  }

  return <section className="tell-panel" aria-labelledby="story-cut-heading">
    <span className="field-label">CRAFT · STORY CUT</span>
    <h2 id="story-cut-heading">Shape your Story Cut</h2>
    {!props.transcriptApproved ? <p>Approve the current Yoruba Source transcript in Verify before creating a Story Cut.</p> : <>
      <div className="story-cut-grid">
        <div><h3>Current source video</h3><video controls preload="metadata" src={props.sourceUrl} aria-label="Current private source video" />
          <h3>Approved Yoruba transcript</h3>{props.transcriptSegments.map((segment) => <p key={segment.id}><span>{time(segment.source_start_ms)}–{time(segment.source_end_ms)} </span>{segment.text_yoruba}</p>)}</div>
        <div>
          <h3>Proposed Story Cut</h3>
          {!props.cut && <p>Create a first proposal from the approved transcript. The 90–150 second target is guidance; you control the final selection.</p>}
          {props.cut && <><p>Versioned proposal · total duration {Math.round(duration / 1000)} seconds</p>{items.map((item, index) => <article className="transcript-segment" key={item.id}>
            <p><strong>{index + 1}. {item.narrative_role}</strong> · {time(item.source_start_ms)}–{time(item.source_end_ms)}</p>
            <p>{item.text_yoruba}</p><p className="upload-help">{item.selection_rationale}</p>
            <div><button className="button button--quiet" type="button" disabled={busy || index === 0} onClick={() => move(index, -1)}>Move up</button> <button className="button button--quiet" type="button" disabled={busy || index === items.length - 1} onClick={() => move(index, 1)}>Move down</button> <button className="button button--quiet" type="button" disabled={busy || items.length <= 1} onClick={() => setItems((old) => old.filter((_, itemIndex) => itemIndex !== index))}>Remove</button></div>
          </article>)}
          {props.cut && <>
            <button className="button button--quiet" type="button" disabled={busy || !hasChanges} onClick={() => void post(`/api/stories/${props.storyId}/story-cuts`, { intent: "save_order", orderedSegmentIds: items.map((item) => item.transcript_segment_id) }, "Your changes are saved as a new Story Cut version.")}>Save changes as new version</button>
            {!props.cut.approved && <button className="button button--primary" type="button" disabled={busy || hasChanges} onClick={() => void post(`/api/stories/${props.storyId}/story-cuts/${props.cut?.artifactId}/approve`, { intent: "approve_story_cut" }, "Story Cut approved for this exact version.")}>Approve Story Cut</button>}
          </>}
          {props.cut?.approved && <><p role="status">Approved by storyteller for this exact Story Cut version and hash.</p><a className="button button--primary" href={`/story/${props.storyId}/translate`}>Continue to Translate</a></>}
          </>}
          {!props.cut && <button className="button button--primary" type="button" disabled={busy || !props.transcriptSegments.length} onClick={() => void post(`/api/stories/${props.storyId}/story-cuts`, { intent: "create_proposal" }, "Story Cut proposal created.")}>{busy ? "Creating…" : "Create Story Cut proposal"}</button>}
          {props.cut && !props.cut.approved && <p>Target duration: 90–150 seconds (guidance, not a requirement).</p>}
        </div>
      </div>
    </>}
    {error && <p className="form-error" role="alert">{error}</p>}{message && <p role="status">{message}</p>}
  </section>;
}
