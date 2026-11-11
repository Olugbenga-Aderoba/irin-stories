"use client";

import { useState } from "react";

type PublicationState = "DRAFT" | "PUBLISHED" | "STALE" | "WITHDRAWN" | null;
export function PublicationReview({ storyId, eligible, snapshotId: initialSnapshotId, publicId: initialPublicId, state: initialState, approved: initialApproved }: { storyId: string; eligible: boolean; snapshotId: string | null; publicId: string | null; state: PublicationState; approved: boolean }) {
  const [snapshotId, setSnapshotId] = useState(initialSnapshotId); const [publicId, setPublicId] = useState(initialPublicId); const [state, setState] = useState(initialState); const [approved, setApproved] = useState(initialApproved); const [busy, setBusy] = useState(false); const [message, setMessage] = useState("");
  async function act(intent: "prepare_snapshot" | "approve_final" | "publish" | "withdraw") {
    setBusy(true); setMessage("");
    try {
      const response = await fetch(`/api/stories/${storyId}/publication`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ intent, ...(intent === "prepare_snapshot" ? {} : { snapshotId }) }) });
      const data = await response.json(); if (!response.ok) throw new Error(data.error ?? "Publication action failed.");
      if (intent === "prepare_snapshot") { setSnapshotId(data.snapshotId); setPublicId(data.publicId); setState("DRAFT"); setApproved(false); }
      if (intent === "approve_final") setApproved(true);
      if (intent === "publish") setState("PUBLISHED");
      if (intent === "withdraw") setState("WITHDRAWN");
    } catch (error) { setMessage(error instanceof Error ? error.message : "Publication action failed."); }
    finally { setBusy(false); }
  }
  return <section className="tell-panel publication-panel"><h2>Publication readiness</h2><p>Current approved source, Story Cut, English translation, resolved privacy review and public-viewing Covenant are required.</p><p><strong>Eligibility:</strong> {eligible ? "Eligible for final approval" : "Not yet eligible"}</p>
    {!snapshotId && <button className="button button--secondary" disabled={busy || !eligible} onClick={() => void act("prepare_snapshot")}>Prepare publication snapshot</button>}
    {snapshotId && state === "DRAFT" && !approved && <><p>Snapshot prepared. Review and give your explicit final approval to this exact version.</p><button className="button button--primary" disabled={busy} onClick={() => void act("approve_final")}>Approve this publication</button></>}
    {snapshotId && state === "DRAFT" && approved && <><p>Final storyteller approval recorded. Publication has not started.</p><button className="button button--primary" disabled={busy} onClick={() => void act("publish")}>Publish now</button></>}
    {state === "PUBLISHED" && <><p role="status">Published</p>{publicId && <p><a href={`/published/${publicId}`}>View public story</a></p>}<button className="button button--secondary" disabled={busy} onClick={() => void act("withdraw")}>Withdraw publication</button><p>Withdrawal stops future serving. Copies already downloaded by others cannot be recalled.</p></>}
    {state === "WITHDRAWN" && <p role="status">Withdrawn. Future public requests are blocked; the snapshot and approval history remain retained.</p>}
    {state === "STALE" && <p role="status">This publication is stale because a required version changed. Recheck the current Protect and approval steps.</p>}
    {message && <p role="alert">{message}</p>}
  </section>;
}

export function PublicStoryCard({ story }: { story: { public_id: string; title: string; original_language_code: string; share_language_code: string; ai_editing_disclosed: boolean; ai_translation_disclosed: boolean; published_at: string } }) {
  return <article className="public-story-card"><p className="eyebrow">IRIN STORIES · VERIFIED PUBLICATION</p><h1>{story.title}</h1><p>Original language: Yoruba</p><p>Share language: English</p>{story.ai_editing_disclosed && <p>AI-assisted editing disclosed</p>}{story.ai_translation_disclosed && <p>AI-assisted English translation disclosed</p>}<p>Published {new Date(story.published_at).toLocaleDateString()}</p></article>;
}
