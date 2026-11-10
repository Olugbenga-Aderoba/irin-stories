import { notFound, redirect } from "next/navigation";
import { SourceVideoUploader } from "@/components/source-video-uploader";
import { SiteHeader } from "@/components/site-header";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const instant = false;

export default async function StoryStagePage({ params }: { params: Promise<{ storyId: string; stage: string }> }) {
  const { storyId, stage } = await params;
  if (stage !== "tell") redirect(`/story/${storyId}/tell`);
  if (!/^[0-9a-f-]{36}$/i.test(storyId)) notFound();

  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect(`/sign-in?next=${encodeURIComponent(`/story/${storyId}/tell`)}`);

  const { data: story, error: storyError } = await supabase.from("stories")
    .select("id,title,workflow_state")
    .eq("id", storyId)
    .maybeSingle();
  if (storyError) throw new Error("The story could not be loaded.");
  if (!story) notFound();

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
            <p className="upload-help">Detection will be available after source media is present. No language has been detected yet.</p>
            <label htmlFor="share-language">Share my story in</label>
            <select id="share-language" disabled value="eng"><option value="eng">English</option></select>
            <p className="upload-help">English is the only share language available in this MVP.</p>
          </aside>
        </div>
        <p className="tell-scope-note">Language detection and transcription are not implemented yet. Your video upload does not start either process.</p>
      </main>
    </div>
  );
}
