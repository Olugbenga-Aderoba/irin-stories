import { notFound } from "next/navigation";
import { connection } from "next/server";
import { SiteHeader } from "@/components/site-header";
import { PublicStoryCard } from "@/components/publication-review";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { z } from "zod";

const publicStorySchema = z.object({
  public_id: z.string().uuid(),
  title: z.string(),
  original_language_code: z.string(),
  share_language_code: z.string(),
  ai_editing_disclosed: z.boolean(),
  ai_translation_disclosed: z.boolean(),
  published_at: z.string().datetime({ offset: true }),
});

export const instant = false;
export default async function PublishedStoryPage({ params }: { params: Promise<{ publicId: string }> }) {
  const { publicId } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(publicId)) notFound();
  await connection();
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.rpc("get_published_story", { p_public_id: publicId }).maybeSingle();
  const story = publicStorySchema.safeParse(data);
  if (error || !story.success) notFound();
  return <div className="workspace-page"><SiteHeader variant="workspace" /><main className="real-story-workspace mx-auto w-full max-w-3xl px-5 sm:px-8"><PublicStoryCard story={story.data} /><p>Only the owner-approved publication record is available on this page.</p></main></div>;
}
