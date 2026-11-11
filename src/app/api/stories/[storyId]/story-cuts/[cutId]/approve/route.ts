import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string; cutId: string }> }) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) return NextResponse.json({ error: "Request origin was not accepted." }, { status: 403 });
  const { storyId, cutId } = await context.params;
  if (![storyId, cutId].every((id) => z.string().uuid().safeParse(id).success)) return NextResponse.json({ error: "Story Cut not found." }, { status: 404 });
  const body = await request.json().catch(() => null);
  if (!z.object({ intent: z.literal("approve_story_cut") }).strict().safeParse(body).success) return NextResponse.json({ error: "Explicit Story Cut approval is required." }, { status: 400 });
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in to approve this Story Cut." }, { status: 401 });
  const { data: story } = await supabase.from("stories").select("id,owner_id").eq("id", storyId).maybeSingle();
  if (!story || story.owner_id !== user.id) return NextResponse.json({ error: "Story Cut not found." }, { status: 404 });
  const admin = createSupabaseAdminClient();
  const { data, error } = await admin.rpc("approve_story_cut", { p_story_id: storyId, p_actor_id: user.id, p_cut_id: cutId }).single();
  if (error || !data) return NextResponse.json({ error: "Only the latest Story Cut for the current approved source can be approved." }, { status: 409 });
  return NextResponse.json({ state: "approved", cutArtifactId: cutId }, { headers: { "Cache-Control": "no-store" } });
}
