import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { SourceVideoUploader } from "@/components/source-video-uploader";
import { SiteHeader } from "@/components/site-header";
import { VerifyLanguagePanel } from "@/components/verify-language-panel";
import { VerifyTranscriptReview, type TranscriptReview } from "@/components/verify-transcript-review";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";

export const instant = false;

export default async function StoryStagePage({ params }: { params: Promise<{ storyId: string; stage: string }> }) {
  const { storyId, stage } = await params;
  if (stage !== "tell" && stage !== "verify") redirect(`/story/${storyId}/tell`);
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
