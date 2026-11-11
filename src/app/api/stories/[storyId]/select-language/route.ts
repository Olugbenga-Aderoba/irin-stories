import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const bodySchema = z.object({ languageCode: z.literal("yor"), intent: z.literal("select") }).strict();
export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string }> }) {
  if (request.headers.get("origin") && request.headers.get("origin") !== new URL(request.url).origin) return NextResponse.json({ error: "Request origin was not accepted." }, { status: 403 });
  const { storyId } = await context.params;
  if (!z.string().uuid().safeParse(storyId).success) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: "Select a supported language explicitly." }, { status: 400 });
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in to select the original language." }, { status: 401 });
  const { data: story } = await supabase.from("stories").select("id").eq("id", storyId).maybeSingle();
  if (!story) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const { data, error } = await supabase.rpc("select_storyteller_language", { p_story_id: storyId, p_language_code: parsed.data.languageCode, p_language_name: "Yoruba" });
  if (error || !data) return NextResponse.json({ error: error?.code === "42501" ? "The current verified source or detection attempt could not be confirmed." : "Your selection could not be saved." }, { status: error?.code === "42501" ? 403 : 409 });
  return NextResponse.json({ decisionId: data, state: "selected", transcriptionEligible: false }, { headers: { "Cache-Control": "no-store" } });
}
