import Link from "next/link";
import { redirect } from "next/navigation";
import { createStory, signOut } from "@/app/auth/actions";
import { SiteHeader } from "@/components/site-header";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export const instant = false;

export default async function WorkspacePage() {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/sign-in?next=/workspace");

  const { data: stories, error } = await supabase.from("stories")
    .select("id,title,workflow_state,created_at")
    .order("created_at", { ascending: false });
  if (error) throw new Error("Your stories could not be loaded.");

  return (
    <div className="workspace-page">
      <SiteHeader variant="workspace" />
      <main className="owner-workspace mx-auto w-full max-w-7xl px-5 sm:px-8">
        <div className="workspace-account-row">
          <div><p className="eyebrow">STORYTELLER WORKSPACE</p><h1>Your stories, held with care.</h1><p>Signed in as {user.email}</p></div>
          <form action={signOut}><button className="button button--quiet" type="submit">Sign out</button></form>
        </div>
        <section className="story-list-card" aria-labelledby="story-list-title">
          <div className="card-heading-row"><div><span className="field-label">PRIVATE WORKSPACE</span><h2 id="story-list-title">My stories</h2></div>
            <form action={createStory}><button className="button button--primary" type="submit">Start your story <span aria-hidden="true">↗</span></button></form>
          </div>
          {stories?.length ? <ul className="story-list">{stories.map((story) => (
            <li key={story.id}><Link href={`/story/${story.id}/tell`}><span><strong>{story.title}</strong><small>Created {new Date(story.created_at).toLocaleDateString()}</small></span><span className="story-state">{story.workflow_state.replaceAll("_", " ")}</span></Link></li>
          ))}</ul> : <p className="empty-stories">Your workspace is ready. Create a story when you are ready to begin.</p>}
        </section>
      </main>
    </div>
  );
}
