import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { COVENANT_PERMISSION_KEYS, canonicalProtectHash, type CovenantPermissions } from "@/lib/protect/privacy";

const permissionsSchema = z.object(Object.fromEntries(COVENANT_PERMISSION_KEYS.map((key) => [key, z.boolean()])) as Record<typeof COVENANT_PERMISSION_KEYS[number], z.ZodBoolean>).strict().refine((value) => !value.VOICE_CLONING, "Voice cloning cannot be allowed.");
const requestSchema = z.discriminatedUnion("intent", [z.object({ intent: z.literal("create"), permissions: permissionsSchema }).strict(), z.object({ intent: z.literal("approve"), covenantId: z.string().uuid() }).strict()]);
export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string }> }) {
  const origin = request.headers.get("origin"); if (origin && origin !== new URL(request.url).origin) return NextResponse.json({ error: "Request origin was not accepted." }, { status: 403 });
  const { storyId } = await context.params; if (!z.string().uuid().safeParse(storyId).success) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const body = requestSchema.safeParse(await request.json().catch(() => null)); if (!body.success) return NextResponse.json({ error: "All Covenant permissions and an explicit action are required." }, { status: 400 });
  const supabase = await createSupabaseServerClient(); const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in to manage this Story Covenant." }, { status: 401 });
  const { data: story } = await supabase.from("stories").select("owner_id").eq("id", storyId).maybeSingle(); if (!story || story.owner_id !== user.id) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const admin = createSupabaseAdminClient();
  if (body.data.intent === "approve") {
    const { data, error } = await admin.rpc("approve_story_covenant", { p_story: storyId, p_actor: user.id, p_artifact: body.data.covenantId });
    if (error || !data) return NextResponse.json({ error: "Only the current complete Story Covenant can be approved." }, { status: 409 });
    const { data: eligible } = await admin.rpc("protection_publication_eligible", { p_story: storyId });
    return NextResponse.json({ state: "approved", publicationEligible: Boolean(eligible) }, { headers: { "Cache-Control": "no-store" } });
  }
  const permissions = body.data.permissions as CovenantPermissions;
  const { data: translation } = await supabase.from("translation_versions").select("artifact_version_id,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id").order("created_at", { ascending: false }).limit(1).maybeSingle();
  const { data: review } = await supabase.from("privacy_review_versions").select("artifact_version_id,translation_artifact_id").order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (!translation || !review || translation.artifact_version_id !== review.translation_artifact_id) return NextResponse.json({ error: "Complete privacy review for the current approved translation first." }, { status: 409 });
  const hash = canonicalProtectHash("covenant", { source: translation.source_media_artifact_id, transcript: translation.transcript_artifact_id, cut: translation.story_cut_artifact_id, translation: translation.artifact_version_id, privacyReview: review.artifact_version_id }, permissions);
  const { data, error } = await admin.rpc("create_story_covenant", { p_story: storyId, p_actor: user.id, p_permissions: permissions, p_hash: `\\x${hash.toString("hex")}` });
  if (error || !data) return NextResponse.json({ error: "Covenant could not be created. Confirm every privacy finding first." }, { status: 409 });
  return NextResponse.json({ covenantArtifactId: data, state: "draft" }, { headers: { "Cache-Control": "no-store" } });
}
