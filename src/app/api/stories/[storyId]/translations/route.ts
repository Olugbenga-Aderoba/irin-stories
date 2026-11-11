import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { canonicalEnglishTranslationHash, englishTranslationSchema, type EnglishTranslationInput } from "@/lib/translate/contract";
import { openAIYorubaToEnglish, TRANSLATION_MODEL } from "@/lib/translate/openai-provider";

const requestSchema = z.discriminatedUnion("intent", [
  z.object({ intent: z.literal("create_proposal"), processingConsent: z.literal(true) }).strict(),
  z.object({ intent: z.literal("save_edits"), segments: z.array(z.object({ translationSegmentId: z.string().uuid(), englishText: z.string().trim().min(1).max(10_000) }).strict()).min(1).max(1000) }).strict(),
]);
const cleanHash = (value: unknown) => typeof value === "string" ? value.replace(/^\\x/i, "").toLowerCase() : "";

export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string }> }) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) return NextResponse.json({ error: "Request origin was not accepted." }, { status: 403 });
  const { storyId } = await context.params;
  if (!z.string().uuid().safeParse(storyId).success) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const body = requestSchema.safeParse(await request.json().catch(() => null));
  if (!body.success) return NextResponse.json({ error: "Explicit translation consent or valid English edits are required." }, { status: 400 });
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in to translate this Story Cut." }, { status: 401 });
  const { data: story } = await supabase.from("stories").select("id,owner_id").eq("id", storyId).maybeSingle();
  if (!story || story.owner_id !== user.id) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const { data: source } = await supabase.from("media_assets").select("artifact_version_id").eq("story_id", storyId).eq("role", "SOURCE").order("created_at", { ascending: false }).limit(1).maybeSingle();
  const { data: transcript } = await supabase.from("transcript_versions").select("artifact_version_id,source_media_artifact_id,language_code").eq("story_id", storyId).order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (!source || !transcript || transcript.source_media_artifact_id !== source.artifact_version_id || transcript.language_code !== "yor") return NextResponse.json({ error: "A current approved Yoruba Source is required." }, { status: 409 });
  const [{ data: transcriptApproval }, { data: transcriptArtifact }] = await Promise.all([
    supabase.from("transcript_approvals").select("approved_content_sha256").eq("story_id", storyId).eq("transcript_artifact_id", transcript.artifact_version_id).maybeSingle(),
    supabase.from("artifact_versions").select("content_sha256,sealed_at").eq("story_id", storyId).eq("id", transcript.artifact_version_id).maybeSingle(),
  ]);
  if (!transcriptArtifact?.sealed_at || !cleanHash(transcriptApproval?.approved_content_sha256) || cleanHash(transcriptApproval?.approved_content_sha256) !== cleanHash(transcriptArtifact.content_sha256)) return NextResponse.json({ error: "The current Yoruba Source transcript must be approved first." }, { status: 409 });
  const { data: cut } = await supabase.from("story_cut_versions").select("artifact_version_id,source_media_artifact_id,transcript_artifact_id")
    .eq("story_id", storyId).eq("source_media_artifact_id", source.artifact_version_id).eq("transcript_artifact_id", transcript.artifact_version_id).order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (!cut) return NextResponse.json({ error: "Create and approve a Story Cut before translation." }, { status: 409 });
  const [{ data: cutApproval }, { data: cutArtifact }, { data: cutSegments }] = await Promise.all([
    supabase.from("story_cut_approvals").select("approved_content_sha256").eq("story_id", storyId).eq("cut_artifact_id", cut.artifact_version_id).maybeSingle(),
    supabase.from("artifact_versions").select("content_sha256,sealed_at").eq("story_id", storyId).eq("id", cut.artifact_version_id).maybeSingle(),
    supabase.from("story_cut_segments").select("id,transcript_segment_id,source_start_ms,source_end_ms,output_start_ms,output_end_ms,segment_number")
      .eq("story_id", storyId).eq("cut_artifact_id", cut.artifact_version_id).order("segment_number", { ascending: true }),
  ]);
  if (!cutArtifact?.sealed_at || !cleanHash(cutApproval?.approved_content_sha256) || cleanHash(cutApproval?.approved_content_sha256) !== cleanHash(cutArtifact.content_sha256) || !cutSegments?.length || cutSegments.some((segment) => !segment.transcript_segment_id)) return NextResponse.json({ error: "The current Story Cut must be approved before translation." }, { status: 409 });
  const transcriptSegmentIds = cutSegments.map((segment) => segment.transcript_segment_id!);
  const { data: transcriptSegments } = await supabase.from("transcript_segments").select("id,text_yoruba").eq("story_id", storyId).eq("transcript_artifact_id", transcript.artifact_version_id).in("id", transcriptSegmentIds);
  const transcriptTextById = new Map((transcriptSegments ?? []).map((segment) => [segment.id, segment.text_yoruba]));
  if (cutSegments.some((segment) => !transcriptTextById.has(segment.transcript_segment_id!))) return NextResponse.json({ error: "Story Cut transcript lineage could not be verified." }, { status: 409 });

  let translationSegments: EnglishTranslationInput[];
  let parentTranslationId: string | null = null;
  let modelName: string | null = null;
  let action: "ai_proposal" | "storyteller_edit";
  let persistencePayload: Array<Record<string, string>>;
  if (body.data.intent === "create_proposal") {
    action = "ai_proposal";
    let translated;
    try {
      translated = await openAIYorubaToEnglish(cutSegments.map((segment) => ({
        cutSegmentId: segment.id, startMs: segment.source_start_ms, endMs: segment.source_end_ms,
        text: transcriptTextById.get(segment.transcript_segment_id!)!,
      })));
    } catch {
      return NextResponse.json({ error: "The English translation could not be generated. Please retry." }, { status: 503 });
    }
    modelName = TRANSLATION_MODEL;
    translationSegments = cutSegments.map((segment, index) => {
      const translation = translated[index];
      return { ...translation, transcriptSegmentId: segment.transcript_segment_id!, sourceStartMs: segment.source_start_ms, sourceEndMs: segment.source_end_ms,
        cueStartMs: segment.output_start_ms, cueEndMs: segment.output_end_ms, initialProposal: translation.englishText };
    });
    persistencePayload = translationSegments.map((segment) => ({ cutSegmentId: segment.cutSegmentId, englishText: segment.englishText }));
  } else {
    action = "storyteller_edit";
    const { data: parent } = await supabase.from("translation_versions").select("artifact_version_id")
      .eq("story_id", storyId).eq("source_media_artifact_id", source.artifact_version_id).eq("transcript_artifact_id", transcript.artifact_version_id).eq("story_cut_artifact_id", cut.artifact_version_id).order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (!parent) return NextResponse.json({ error: "Create an English proposal before editing it." }, { status: 409 });
    parentTranslationId = parent.artifact_version_id;
    const { data: stored } = await supabase.from("translation_segments").select("id,cut_segment_id,transcript_segment_id,cue_start_ms,cue_end_ms,english_text,initial_proposal")
      .eq("story_id", storyId).eq("translation_artifact_id", parentTranslationId).order("segment_number", { ascending: true });
    if (!stored?.length || stored.length !== body.data.segments.length || new Set(body.data.segments.map((item) => item.translationSegmentId)).size !== stored.length) return NextResponse.json({ error: "Translation segments changed. Refresh and try again." }, { status: 409 });
    const edits = new Map(body.data.segments.map((item) => [item.translationSegmentId, item.englishText]));
    if (stored.some((item) => !edits.has(item.id))) return NextResponse.json({ error: "Every translation segment must be retained." }, { status: 409 });
    const cutById = new Map(cutSegments.map((segment) => [segment.id, segment]));
    if (stored.some((item) => !cutById.has(item.cut_segment_id))) return NextResponse.json({ error: "Translation no longer matches the approved Story Cut." }, { status: 409 });
    translationSegments = stored.map((item) => {
      const sourceCut = cutById.get(item.cut_segment_id)!;
      return { cutSegmentId: item.cut_segment_id, transcriptSegmentId: item.transcript_segment_id, sourceStartMs: sourceCut.source_start_ms,
        sourceEndMs: sourceCut.source_end_ms, cueStartMs: item.cue_start_ms, cueEndMs: item.cue_end_ms,
        initialProposal: item.initial_proposal ?? item.english_text, englishText: edits.get(item.id)! };
    });
    persistencePayload = stored.map((item) => ({ translationSegmentId: item.id, englishText: edits.get(item.id)! }));
  }
  const validated = z.array(englishTranslationSchema.extend({ transcriptSegmentId: z.string().uuid(), sourceStartMs: z.number().int().nonnegative(), sourceEndMs: z.number().int().positive(), cueStartMs: z.number().int().nonnegative(), cueEndMs: z.number().int().positive(), initialProposal: z.string().min(1).max(10_000) }).strict()).min(1).max(1000).safeParse(translationSegments);
  if (!validated.success) return NextResponse.json({ error: "The English translation could not be validated." }, { status: 502 });
  const hash = canonicalEnglishTranslationHash(source.artifact_version_id, transcript.artifact_version_id, cut.artifact_version_id, validated.data);
  const admin = createSupabaseAdminClient();
  const { data: translationId, error } = await admin.rpc("persist_english_translation", {
    p_story_id: storyId, p_actor_id: user.id, p_source_id: source.artifact_version_id, p_transcript_id: transcript.artifact_version_id,
    p_cut_id: cut.artifact_version_id, p_segments: persistencePayload, p_hash: `\\x${hash.toString("hex")}`,
    p_action: action, p_parent_translation_id: parentTranslationId, p_model_name: modelName,
  });
  if (error || !translationId) return NextResponse.json({ error: "The English translation could not be saved. Refresh and try again." }, { status: 409 });
  return NextResponse.json({ translationArtifactId: translationId, state: "proposal" }, { headers: { "Cache-Control": "no-store" } });
}
