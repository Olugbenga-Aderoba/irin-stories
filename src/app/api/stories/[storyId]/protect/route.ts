import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { canonicalProtectHash, type PrivacyFindingInput } from "@/lib/protect/privacy";
import { openAIPrivacyReview, PRIVACY_MODEL } from "@/lib/protect/openai-provider";

const schema = z.discriminatedUnion("intent", [
  z.object({ intent: z.literal("review"), processingConsent: z.literal(true) }).strict(),
  z.object({ intent: z.literal("decide"), reviewId: z.string().uuid(), findingId: z.string().uuid(), decision: z.enum(["KEEP", "GENERALISE", "ANONYMISE", "REMOVE"]) }).strict(),
]);
const cleanHash = (value: unknown) => typeof value === "string" ? value.replace(/^\\x/i, "").toLowerCase() : "";

export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string }> }) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) return NextResponse.json({ error: "Request origin was not accepted." }, { status: 403 });
  const { storyId } = await context.params;
  if (!z.string().uuid().safeParse(storyId).success) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const body = schema.safeParse(await request.json().catch(() => null));
  if (!body.success) return NextResponse.json({ error: "Explicit privacy review consent or a valid storyteller decision is required." }, { status: 400 });
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in to review privacy for this story." }, { status: 401 });
  const { data: story } = await supabase.from("stories").select("id,owner_id").eq("id", storyId).maybeSingle();
  if (!story || story.owner_id !== user.id) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const admin = createSupabaseAdminClient();
  if (body.data.intent === "decide") {
    const { data, error } = await admin.rpc("record_privacy_decision", { p_story: storyId, p_actor: user.id, p_review: body.data.reviewId, p_finding: body.data.findingId, p_decision: body.data.decision });
    if (error || !data) return NextResponse.json({ error: "Decision could not be recorded. Non-KEEP choices require a later approved edit with matching source lineage." }, { status: 409 });
    return NextResponse.json({ decisionId: data, decision: body.data.decision }, { headers: { "Cache-Control": "no-store" } });
  }
  const { data: translation } = await supabase.from("translation_versions").select("artifact_version_id,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id")
    .eq("story_id", storyId).order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (!translation) return NextResponse.json({ error: "An approved English translation is required first." }, { status: 409 });
  const [{ data: approval }, { data: artifact }, { data: rows }, { data: cutRows }] = await Promise.all([
    supabase.from("translation_approvals").select("approved_content_sha256").eq("story_id", storyId).eq("translation_artifact_id", translation.artifact_version_id).maybeSingle(),
    supabase.from("artifact_versions").select("content_sha256,sealed_at").eq("story_id", storyId).eq("id", translation.artifact_version_id).maybeSingle(),
    supabase.from("translation_segments").select("id,cut_segment_id,english_text,segment_number").eq("story_id", storyId).eq("translation_artifact_id", translation.artifact_version_id).order("segment_number"),
    supabase.from("story_cut_segments").select("id,source_start_ms,source_end_ms").eq("story_id", storyId).eq("cut_artifact_id", translation.story_cut_artifact_id),
  ]);
  if (!artifact?.sealed_at || !cleanHash(approval?.approved_content_sha256) || cleanHash(approval?.approved_content_sha256) !== cleanHash(artifact.content_sha256) || !rows?.length) return NextResponse.json({ error: "The current English translation must be explicitly approved first." }, { status: 409 });
  const cutById = new Map((cutRows ?? []).map((row) => [row.id, row]));
  const segments = rows.map((row) => { const cut = cutById.get(row.cut_segment_id); return { translationSegmentId: row.id, text: row.english_text, startMs: cut?.source_start_ms ?? 0, endMs: cut?.source_end_ms ?? 0 }; });
  if (segments.some((segment) => segment.endMs <= segment.startMs)) return NextResponse.json({ error: "Translation source lineage could not be verified." }, { status: 409 });
  let findings: PrivacyFindingInput[];
  try { findings = await openAIPrivacyReview(segments); } catch { return NextResponse.json({ error: "AI privacy review is unavailable. Please retry." }, { status: 503 }); }
  const hash = canonicalProtectHash("privacy-review", { source: translation.source_media_artifact_id, transcript: translation.transcript_artifact_id, cut: translation.story_cut_artifact_id, translation: translation.artifact_version_id }, findings);
  const { data, error } = await admin.rpc("persist_privacy_review", { p_story: storyId, p_actor: user.id, p_translation: translation.artifact_version_id, p_model: PRIVACY_MODEL, p_findings: findings, p_hash: `\\x${hash.toString("hex")}` });
  if (error || !data) return NextResponse.json({ error: "Privacy findings could not be saved. Refresh and retry." }, { status: 409 });
  return NextResponse.json({ reviewArtifactId: data, findings, proposalSource: "AI" }, { headers: { "Cache-Control": "no-store" } });
}
