import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const requestSchema = z.object({ intent: z.literal("approve_source") }).strict();
export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string; transcriptId: string }> }) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) return NextResponse.json({ error: "Request origin was not accepted." }, { status: 403 });
  const { storyId, transcriptId } = await context.params;
  if (![storyId, transcriptId].every((id) => z.string().uuid().safeParse(id).success)) return NextResponse.json({ error: "Transcript not found." }, { status: 404 });
  const body = requestSchema.safeParse(await request.json().catch(() => null));
  if (!body.success) return NextResponse.json({ error: "Explicit approval is required." }, { status: 400 });
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in to approve this transcript." }, { status: 401 });
  const { data: story } = await supabase.from("stories").select("id,owner_id").eq("id", storyId).maybeSingle();
  if (!story || story.owner_id !== user.id) return NextResponse.json({ error: "Transcript not found." }, { status: 404 });
  const admin = createSupabaseAdminClient();
  const { data, error } = await admin.rpc("approve_yoruba_transcript", {
    p_story_id: storyId, p_actor_id: user.id, p_transcript_artifact_id: transcriptId,
  }).single();
  if (error || !data) return NextResponse.json({ error: "Only the latest transcript for the current eligible source can be approved." }, { status: 409 });
  return NextResponse.json({ state: "approved", transcriptArtifactId: transcriptId }, { headers: { "Cache-Control": "no-store" } });
}
