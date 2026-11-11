import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string; translationId: string }> }) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) return NextResponse.json({ error: "Request origin was not accepted." }, { status: 403 });
  const { storyId, translationId } = await context.params;
  if (![storyId, translationId].every((id) => z.string().uuid().safeParse(id).success)) return NextResponse.json({ error: "Translation not found." }, { status: 404 });
  if (!z.object({ intent: z.literal("approve_english_translation") }).strict().safeParse(await request.json().catch(() => null)).success) return NextResponse.json({ error: "Explicit translation approval is required." }, { status: 400 });
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in to approve this translation." }, { status: 401 });
  const { data: story } = await supabase.from("stories").select("id,owner_id").eq("id", storyId).maybeSingle();
  if (!story || story.owner_id !== user.id) return NextResponse.json({ error: "Translation not found." }, { status: 404 });
  const admin = createSupabaseAdminClient();
  const { data, error } = await admin.rpc("approve_english_translation", { p_story_id: storyId, p_actor_id: user.id, p_translation_id: translationId }).single();
  if (error || !data) return NextResponse.json({ error: "Only the latest translation of the current approved Story Cut can be approved." }, { status: 409 });
  return NextResponse.json({ state: "approved", translationArtifactId: translationId }, { headers: { "Cache-Control": "no-store" } });
}
