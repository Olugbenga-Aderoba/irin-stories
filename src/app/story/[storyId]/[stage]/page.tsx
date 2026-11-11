import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { SourceVideoUploader } from "@/components/source-video-uploader";
import { SiteHeader } from "@/components/site-header";
import { VerifyLanguagePanel } from "@/components/verify-language-panel";
import { VerifyTranscriptReview, type TranscriptReview } from "@/components/verify-transcript-review";
import { StoryCutReview, type StoryCutItem } from "@/components/story-cut-review";
import { TranslationReview, type TranslationReviewSegment } from "@/components/translation-review";
import { ProtectReview } from "@/components/protect-review";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";

export const instant = false;

export default async function StoryStagePage({ params }: { params: Promise<{ storyId: string; stage: string }> }) {
  const { storyId, stage } = await params;
  if (stage !== "tell" && stage !== "verify" && stage !== "craft" && stage !== "translate" && stage !== "protect") redirect(`/story/${storyId}/tell`);
  if (!/^[0-9a-f-]{36}$/i.test(storyId)) notFound();

  // Run Supabase's session expiry clock reads at request time.
  await connection();
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect(`/sign-in?next=${encodeURIComponent(`/story/${storyId}/tell`)}`);

  const { data: story, error: storyError } = await supabase.from("stories")
    .select("id,title,workflow_state")
    .eq("id", storyId)
    .maybeSingle();
  if (storyError) throw new Error("The story could not be loaded.");
  if (!story) notFound();

  if (stage === "craft") {
    const { data: media, error: mediaError } = await supabase.from("media_assets")
      .select("artifact_version_id,object_key")
      .eq("story_id", story.id).eq("role", "SOURCE").order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (mediaError) throw new Error("Source media metadata could not be loaded.");
    let playbackUrl = "";
    let transcriptApproved = false;
    let transcriptSegments: { id: string; source_start_ms: number; source_end_ms: number; text_yoruba: string }[] = [];
    let cut: null | { artifactId: string; durationMs: number; approved: boolean; segments: StoryCutItem[] } = null;
    if (media) {
      const { data: signed } = await supabase.storage.from("private-source").createSignedUrl(media.object_key, 300);
      playbackUrl = signed?.signedUrl ?? "";
      const { data: transcript } = await supabase.from("transcript_versions").select("artifact_version_id,source_media_artifact_id,language_code")
        .eq("story_id", story.id).eq("source_media_artifact_id", media.artifact_version_id).order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (transcript?.language_code === "yor") {
        const [{ data: segments }, { data: approval }, { data: artifact }] = await Promise.all([
          supabase.from("transcript_segments").select("id,source_start_ms,source_end_ms,text_yoruba").eq("story_id", story.id).eq("transcript_artifact_id", transcript.artifact_version_id).order("segment_number", { ascending: true }),
          supabase.from("transcript_approvals").select("approved_content_sha256").eq("story_id", story.id).eq("transcript_artifact_id", transcript.artifact_version_id).maybeSingle(),
          supabase.from("artifact_versions").select("content_sha256,sealed_at").eq("story_id", story.id).eq("id", transcript.artifact_version_id).maybeSingle(),
        ]);
        transcriptSegments = segments ?? [];
        const cleanHash = (value: unknown) => typeof value === "string" ? value.replace(/^\\x/i, "").toLowerCase() : "";
        transcriptApproved = Boolean(artifact?.sealed_at && cleanHash(approval?.approved_content_sha256) && cleanHash(approval?.approved_content_sha256) === cleanHash(artifact.content_sha256));
        if (transcriptApproved) {
          const { data: latestCut } = await supabase.from("story_cut_versions").select("artifact_version_id,estimated_duration_ms")
            .eq("story_id", story.id).eq("source_media_artifact_id", media.artifact_version_id).eq("transcript_artifact_id", transcript.artifact_version_id).order("created_at", { ascending: false }).limit(1).maybeSingle();
          if (latestCut) {
            const [{ data: cutApproval }, { data: cutArtifact }] = await Promise.all([
              supabase.from("story_cut_approvals").select("approved_content_sha256").eq("story_id", story.id).eq("cut_artifact_id", latestCut.artifact_version_id).maybeSingle(),
              supabase.from("artifact_versions").select("content_sha256,sealed_at").eq("story_id", story.id).eq("id", latestCut.artifact_version_id).maybeSingle(),
            ]);
            const { data: joined } = await supabase.from("story_cut_segments").select("id,transcript_segment_id,transcript_artifact_id,source_start_ms,source_end_ms,output_start_ms,output_end_ms,narrative_role,selection_rationale")
              .eq("story_id", story.id).eq("cut_artifact_id", latestCut.artifact_version_id).order("segment_number", { ascending: true });
            const textById = new Map((segments ?? []).map((segment) => [segment.id, segment.text_yoruba]));
            const cleanHash = (value: unknown) => typeof value === "string" ? value.replace(/^\\x/i, "").toLowerCase() : "";
            cut = { artifactId: latestCut.artifact_version_id, durationMs: latestCut.estimated_duration_ms,
              approved: Boolean(cutArtifact?.sealed_at && cleanHash(cutApproval?.approved_content_sha256) && cleanHash(cutApproval?.approved_content_sha256) === cleanHash(cutArtifact.content_sha256)),
              segments: (joined ?? []).filter((segment) => segment.transcript_segment_id).map((segment) => ({ ...segment, text_yoruba: textById.get(segment.transcript_segment_id) ?? "" })) };
          }
        }
      }
    }
    return <div className="workspace-page"><SiteHeader variant="workspace" /><main className="real-story-workspace mx-auto w-full max-w-7xl px-5 sm:px-8">
      <header className="real-story-heading"><p className="eyebrow">CRAFT · STORY CUT</p><h1>{story.title}</h1><p>Shape moments from your approved Yoruba Source. Your edits are saved as new versions.</p></header>
      {!media || !playbackUrl ? <section className="tell-panel"><p>A current private source video is required.</p><a className="button button--primary" href={`/story/${story.id}/verify`}>Return to Verify</a></section>
        : <StoryCutReview key={cut?.artifactId ?? "new-cut"} storyId={story.id} sourceUrl={playbackUrl} transcriptApproved={transcriptApproved} transcriptSegments={transcriptSegments} cut={cut} />}
    </main></div>;
  }

  if (stage === "translate") {
    let cutApproved = false;
    let translation: null | { artifactId: string; approved: boolean; segments: TranslationReviewSegment[] } = null;
    const { data: media } = await supabase.from("media_assets").select("artifact_version_id").eq("story_id", story.id).eq("role", "SOURCE").order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (media) {
      const { data: transcript } = await supabase.from("transcript_versions").select("artifact_version_id,source_media_artifact_id,language_code").eq("story_id", story.id).eq("source_media_artifact_id", media.artifact_version_id).order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (transcript?.language_code === "yor") {
        const { data: cut } = await supabase.from("story_cut_versions").select("artifact_version_id")
          .eq("story_id", story.id).eq("source_media_artifact_id", media.artifact_version_id).eq("transcript_artifact_id", transcript.artifact_version_id).order("created_at", { ascending: false }).limit(1).maybeSingle();
        if (cut) {
          const [{ data: transcriptApproval }, { data: transcriptArtifact }, { data: cutApproval }, { data: cutArtifact }, { data: cutRows }] = await Promise.all([
            supabase.from("transcript_approvals").select("approved_content_sha256").eq("story_id", story.id).eq("transcript_artifact_id", transcript.artifact_version_id).maybeSingle(),
            supabase.from("artifact_versions").select("content_sha256,sealed_at").eq("story_id", story.id).eq("id", transcript.artifact_version_id).maybeSingle(),
            supabase.from("story_cut_approvals").select("approved_content_sha256").eq("story_id", story.id).eq("cut_artifact_id", cut.artifact_version_id).maybeSingle(),
            supabase.from("artifact_versions").select("content_sha256,sealed_at").eq("story_id", story.id).eq("id", cut.artifact_version_id).maybeSingle(),
            supabase.from("story_cut_segments").select("id,transcript_segment_id,source_start_ms,source_end_ms,output_start_ms,output_end_ms,segment_number")
              .eq("story_id", story.id).eq("cut_artifact_id", cut.artifact_version_id).order("segment_number", { ascending: true }),
          ]);
          const cleanHash = (value: unknown) => typeof value === "string" ? value.replace(/^\\x/i, "").toLowerCase() : "";
          cutApproved = Boolean(transcriptArtifact?.sealed_at && cleanHash(transcriptApproval?.approved_content_sha256) === cleanHash(transcriptArtifact.content_sha256)
            && cutArtifact?.sealed_at && cleanHash(cutApproval?.approved_content_sha256) === cleanHash(cutArtifact.content_sha256));
          if (cutApproved && cutRows?.length) {
            const transcriptIds = cutRows.map((row) => row.transcript_segment_id).filter((id): id is string => Boolean(id));
            const [{ data: translationRow }, { data: transcriptSegments }] = await Promise.all([
              supabase.from("translation_versions").select("artifact_version_id,source_language_code,target_language_code")
                .eq("story_id", story.id).eq("source_media_artifact_id", media.artifact_version_id).eq("transcript_artifact_id", transcript.artifact_version_id).eq("story_cut_artifact_id", cut.artifact_version_id).order("created_at", { ascending: false }).limit(1).maybeSingle(),
              supabase.from("transcript_segments").select("id,text_yoruba").eq("story_id", story.id).eq("transcript_artifact_id", transcript.artifact_version_id).in("id", transcriptIds),
            ]);
            if (translationRow?.source_language_code === "yor" && translationRow.target_language_code === "eng") {
              const [{ data: approval }, { data: artifact }, { data: translatedRows }] = await Promise.all([
                supabase.from("translation_approvals").select("approved_content_sha256").eq("story_id", story.id).eq("translation_artifact_id", translationRow.artifact_version_id).maybeSingle(),
                supabase.from("artifact_versions").select("content_sha256,sealed_at").eq("story_id", story.id).eq("id", translationRow.artifact_version_id).maybeSingle(),
                supabase.from("translation_segments").select("id,cut_segment_id,transcript_segment_id,cue_start_ms,cue_end_ms,english_text,initial_proposal,segment_number")
                  .eq("story_id", story.id).eq("translation_artifact_id", translationRow.artifact_version_id).order("segment_number", { ascending: true }),
              ]);
              const cutById = new Map(cutRows.map((row) => [row.id, row]));
              const transcriptText = new Map((transcriptSegments ?? []).map((row) => [row.id, row.text_yoruba]));
              translation = { artifactId: translationRow.artifact_version_id,
                approved: Boolean(artifact?.sealed_at && cleanHash(approval?.approved_content_sha256) && cleanHash(approval?.approved_content_sha256) === cleanHash(artifact.content_sha256)),
                segments: (translatedRows ?? []).flatMap((row) => {
                  const cutSegment = cutById.get(row.cut_segment_id);
                  const yoruba = transcriptText.get(row.transcript_segment_id);
                  return cutSegment && yoruba ? [{ ...row, source_start_ms: cutSegment.source_start_ms, source_end_ms: cutSegment.source_end_ms, yoruba_text: yoruba }] : [];
                }) };
            }
          }
        }
      }
    }
    return <div className="workspace-page"><SiteHeader variant="workspace" /><main className="real-story-workspace mx-auto w-full max-w-7xl px-5 sm:px-8">
      <header className="real-story-heading"><p className="eyebrow">TRANSLATE · YORUBA TO ENGLISH</p><h1>{story.title}</h1><p>Review an AI-assisted English translation of the exact approved Story Cut. Your Yoruba Source and Story Cut remain unchanged.</p></header>
      <TranslationReview key={translation?.artifactId ?? "new-translation"} storyId={story.id} cutApproved={cutApproved} translation={translation} />
    </main></div>;
  }

  if (stage === "protect") {
    const [{ data: translation }, { data: review }] = await Promise.all([
      supabase.from("translation_versions").select("artifact_version_id,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id").eq("story_id", story.id).order("created_at", { ascending: false }).limit(1).maybeSingle(),
      supabase.from("privacy_review_versions").select("artifact_version_id,translation_artifact_id").eq("story_id", story.id).order("created_at", { ascending: false }).limit(1).maybeSingle(),
    ]);
    let findings: Parameters<typeof ProtectReview>[0]["findings"] = [];
    if (review) {
      const [{ data: rows }, { data: segments }] = await Promise.all([
        supabase.from("privacy_findings").select("id,privacy_review_artifact_id,risk_category,proposal_summary,suggested_safer_alternative,translation_segment_id,translation_artifact_id").eq("story_id", story.id).eq("privacy_review_artifact_id", review.artifact_version_id),
        supabase.from("translation_segments").select("id,english_text").eq("story_id", story.id).eq("translation_artifact_id", review.translation_artifact_id),
      ]);
      const ids = (rows ?? []).map((row) => row.id);
      const { data: decisions } = ids.length
        ? await supabase.from("privacy_decisions").select("privacy_finding_id,decision").eq("story_id", story.id).in("privacy_finding_id", ids)
        : { data: [] as { privacy_finding_id: string; decision: string }[] };
      const text = new Map((segments ?? []).map((item) => [item.id, item.english_text])); const decisionByFinding = new Map((decisions ?? []).map((item) => [item.privacy_finding_id, item.decision]));
      findings = (rows ?? []).map((row) => ({ id: row.id, review_id: review.artifact_version_id, risk_category: row.risk_category, proposal_summary: row.proposal_summary, suggested_safer_alternative: row.suggested_safer_alternative, translation_segment_id: row.translation_segment_id ?? "", translation_artifact_id: row.translation_artifact_id ?? "", decision: decisionByFinding.get(row.id) ?? null, passage: row.proposal_summary || (row.translation_segment_id ? text.get(row.translation_segment_id) ?? "" : "") }));
    }
    const [{ data: covenant }, { data: eligible }] = await Promise.all([
      supabase.from("artifact_versions").select("id,content_sha256,sealed_at").eq("story_id", story.id).eq("kind", "COVENANT").order("version_number", { ascending: false }).limit(1).maybeSingle(),
      createSupabaseAdminClient().rpc("protection_publication_eligible", { p_story: story.id }),
    ]);
    let permissions: Parameters<typeof ProtectReview>[0]["permissions"] = []; let covenantApproved = false;
    if (covenant) {
      const [{ data: rows }, { data: approval }] = await Promise.all([
        supabase.from("covenant_permissions").select("permission,allowed").eq("story_id", story.id).eq("covenant_artifact_id", covenant.id),
        supabase.from("covenant_approvals").select("approved_content_sha256").eq("story_id", story.id).eq("covenant_artifact_id", covenant.id).maybeSingle(),
      ]);
      permissions = rows ?? [];
      const cleanHash = (value: unknown) => typeof value === "string" ? value.replace(/^\\x/i, "").toLowerCase() : "";
      covenantApproved = Boolean(covenant.sealed_at && approval && cleanHash(approval.approved_content_sha256) === cleanHash(covenant.content_sha256));
    }
    return <div className="workspace-page"><SiteHeader variant="workspace" /><main className="real-story-workspace mx-auto w-full max-w-7xl px-5 sm:px-8"><header className="real-story-heading"><p className="eyebrow">PROTECT · PRIVACY AND PERMISSIONS</p><h1>{story.title}</h1><p>Review potential privacy concerns in your approved English translation. AI proposes; you decide.</p></header><ProtectReview storyId={story.id} translationId={translation?.artifact_version_id ?? null} findings={findings} permissions={permissions} covenantId={covenant?.id ?? null} covenantApproved={covenantApproved} eligible={Boolean(eligible)} /></main></div>;
  }

  if (stage === "verify") {
    const { data: media, error: mediaError } = await supabase.from("media_assets")
      .select("artifact_version_id,object_key,bucket_id,original_filename,duration_ms")
      .eq("story_id", story.id)
      .eq("role", "SOURCE")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (mediaError) throw new Error("Source media metadata could not be loaded.");

    let verification = null;
    let latestReview = null;
    let transcriptionEligible = false;
    let humanDecision = null;
    let noReliableDetection = false;
    let playbackUrl = "";
    let transcript: TranscriptReview | null = null;
    if (media) {
      const [{ data: latestVerification }, { data: review }, { data: eligible }, { data: signed }, { data: decision }] = await Promise.all([
        supabase.from("source_media_verifications")
          .select("id,status,actual_container,actual_format_names,actual_duration_ms,has_video,has_audio,audio_codec,video_codec,video_width,video_height,client_metadata_mismatches")
          .eq("story_id", story.id)
          .eq("source_media_artifact_id", media.artifact_version_id)
          .order("verification_number", { ascending: false })
          .limit(1)
          .maybeSingle(),
        supabase.from("source_language_reviews")
          .select("id,review_status,detected_language_code,detected_language_name,detection_confidence,confirmed_language_code,confirmed_language_name")
          .eq("story_id", story.id)
          .eq("source_media_artifact_id", media.artifact_version_id)
          .order("review_number", { ascending: false })
          .limit(1)
          .maybeSingle(),
        supabase.rpc("is_transcription_eligible", { p_story_id: story.id }),
        supabase.storage.from("private-source").createSignedUrl(media.object_key, 300),
        supabase.from("storyteller_language_decisions").select("id,state,selected_language_code,selected_language_name,decision_origin").eq("story_id", story.id).eq("source_media_artifact_id", media.artifact_version_id).order("created_at", { ascending: false }).limit(1).maybeSingle(),
      ]);
      verification = latestVerification;
      latestReview = review;
      transcriptionEligible = Boolean(eligible);
      humanDecision = decision;
      const admin = createSupabaseAdminClient();
      const { data: diagnostic } = await admin.from("verify_language_detection_diagnostics").select("category,attempted_at").eq("story_id", story.id).order("attempted_at", { ascending: false }).limit(1).maybeSingle();
      noReliableDetection = diagnostic?.category === "no_reliable_language";
      playbackUrl = signed?.signedUrl ?? "";
      const { data: latestTranscript } = await supabase.from("transcript_versions")
        .select("artifact_version_id,source_media_artifact_id,language_code")
        .eq("story_id", story.id).eq("source_media_artifact_id", media.artifact_version_id)
        .order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (latestTranscript) {
        const [{ data: segments }, { data: approval }, { data: artifact }] = await Promise.all([
          supabase.from("transcript_segments").select("id,segment_number,source_start_ms,source_end_ms,initial_proposal,text_yoruba")
            .eq("story_id", story.id).eq("transcript_artifact_id", latestTranscript.artifact_version_id).order("segment_number", { ascending: true }),
          supabase.from("transcript_approvals").select("approved_content_sha256")
            .eq("story_id", story.id).eq("transcript_artifact_id", latestTranscript.artifact_version_id).maybeSingle(),
          supabase.from("artifact_versions").select("content_sha256,sealed_at")
            .eq("story_id", story.id).eq("id", latestTranscript.artifact_version_id).maybeSingle(),
        ]);
        const artifactHash = typeof artifact?.content_sha256 === "string" ? artifact.content_sha256.replace(/^\\x/i, "").toLowerCase() : "";
        const approvedHash = typeof approval?.approved_content_sha256 === "string" ? approval.approved_content_sha256.replace(/^\\x/i, "").toLowerCase() : "";
        if (segments && artifact?.sealed_at) transcript = {
          artifact_version_id: latestTranscript.artifact_version_id,
          source_media_artifact_id: latestTranscript.source_media_artifact_id,
          language_code: latestTranscript.language_code,
          approved: Boolean(approvedHash && artifactHash && approvedHash === artifactHash),
          segments,
        };
      }
    }

    return (
      <div className="workspace-page">
        <a className="skip-link" href="#verify-main">Skip to verification</a>
        <SiteHeader variant="workspace" />
        <main className="real-story-workspace mx-auto w-full max-w-7xl px-5 sm:px-8" id="verify-main">
          <header className="real-story-heading">
            <p className="eyebrow">VERIFY · SOURCE AND LANGUAGE</p>
            <h1>{story.title}</h1>
            <p>We check the actual video and audio first. A detected language remains a proposal until you decide.</p>
          </header>
          {!media || !playbackUrl
            ? <section className="tell-panel"><p>A private source video is required before verification.</p><a className="button button--primary" href={`/story/${story.id}/tell`}>Return to Tell</a></section>
            : <VerifyLanguagePanel
                storyId={story.id}
                sourceMediaArtifactId={media.artifact_version_id}
                filename={media.original_filename ?? "Private source video"}
                playbackUrl={playbackUrl}
                verification={verification}
                latestReview={latestReview}
                transcriptionEligible={transcriptionEligible}
                humanDecision={humanDecision}
                noReliableDetection={noReliableDetection}
                transcriptPanel={<VerifyTranscriptReview key={transcript?.artifact_version_id ?? media.artifact_version_id} storyId={story.id} sourceMediaArtifactId={media.artifact_version_id} transcriptionEligible={transcriptionEligible} transcript={transcript} />}
              />}
        </main>
      </div>
    );
  }

  const { data: media, error: mediaError } = await supabase.from("media_assets")
    .select("object_key,original_filename,duration_ms")
    .eq("story_id", story.id)
    .eq("role", "SOURCE")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (mediaError) throw new Error("Source media metadata could not be loaded.");

  let existing: { filename: string; durationMs: number; signedUrl: string } | null = null;
  if (media) {
    const { data: signed, error } = await supabase.storage.from("private-source").createSignedUrl(media.object_key, 60 * 60);
    if (!error && signed) existing = { filename: media.original_filename ?? "Private source video", durationMs: media.duration_ms, signedUrl: signed.signedUrl };
  }

  return (
    <div className="workspace-page">
      <a className="skip-link" href="#tell-main">Skip to story</a>
      <SiteHeader variant="workspace" />
      <main className="real-story-workspace mx-auto w-full max-w-7xl px-5 sm:px-8" id="tell-main">
        <header className="real-story-heading">
          <p className="eyebrow">TELL · PRIVATE STORY</p>
          <h1>{story.title}</h1>
          <p>Your source video stays private. Only you can access this story and its source media.</p>
        </header>
        <div className="tell-grid">
          <section className="tell-panel" aria-labelledby="source-video-heading">
            <span className="field-label">YOUR ORIGINAL</span>
            <h2 id="source-video-heading">Source video</h2>
            <SourceVideoUploader storyId={story.id} existing={existing} />
          </section>
          <aside className="tell-panel language-panel" aria-labelledby="language-heading">
            <span className="field-label">LANGUAGE PREFERENCES</span>
            <label id="language-heading">Original language</label>
            <p className="language-value">Detect automatically</p>
            <p className="upload-help">Continue to Verify to check the source media and request a language proposal after upload.</p>
            <label htmlFor="share-language">Share my story in</label>
            <select id="share-language" disabled value="eng"><option value="eng">English</option></select>
            <p className="upload-help">English is the only share language available in this MVP.</p>
          </aside>
        </div>
        <a className="button button--quiet" href={`/story/${story.id}/verify`}>Continue to Verify</a>
        <p className="tell-scope-note">Uploading does not start media verification, language detection, or transcription.</p>
      </main>
    </div>
  );
}
