import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { canonicalStoryCutHash, proposalSegmentSchema, type StoryCutSegmentInput } from "@/lib/craft/story-cut";
import { openAIStoryCutProposal } from "@/lib/craft/proposal-provider";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const requestSchema = z.discriminatedUnion("intent", [
  z.object({ intent: z.literal("create_proposal") }).strict(),
  z.object({ intent: z.literal("save_order"), orderedSegmentIds: z.array(z.string().uuid()).min(1).max(1000) }).strict(),
]);

export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string }> }) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) return NextResponse.json({ error: "Request origin was not accepted." }, { status: 403 });
  const { storyId } = await context.params;
  if (!z.string().uuid().safeParse(storyId).success) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const body = requestSchema.safeParse(await request.json().catch(() => null));
  if (!body.success) return NextResponse.json({ error: "A valid Story Cut action is required." }, { status: 400 });
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in to shape this Story Cut." }, { status: 401 });
  const { data: story } = await supabase.from("stories").select("id,owner_id").eq("id", storyId).maybeSingle();
  if (!story || story.owner_id !== user.id) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const { data: media } = await supabase.from("media_assets").select("artifact_version_id").eq("story_id", storyId).eq("role", "SOURCE").order("created_at", { ascending: false }).limit(1).maybeSingle();
  const { data: transcript } = await supabase.from("transcript_versions").select("artifact_version_id,source_media_artifact_id,language_code").eq("story_id", storyId).order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (!media || !transcript || transcript.language_code !== "yor" || transcript.source_media_artifact_id !== media.artifact_version_id) return NextResponse.json({ error: "A current approved Yoruba source transcript is required." }, { status: 409 });
  const [{ data: approval }, { data: artifact }] = await Promise.all([
    supabase.from("transcript_approvals").select("approved_content_sha256").eq("story_id", storyId).eq("transcript_artifact_id", transcript.artifact_version_id).maybeSingle(),
    supabase.from("artifact_versions").select("content_sha256,sealed_at").eq("story_id", storyId).eq("id", transcript.artifact_version_id).maybeSingle(),
  ]);
  const cleanHash = (value: unknown) => typeof value === "string" ? value.replace(/^\\x/i, "").toLowerCase() : "";
  if (!approval || !artifact?.sealed_at || !cleanHash(approval.approved_content_sha256) || cleanHash(approval.approved_content_sha256) !== cleanHash(artifact.content_sha256)) return NextResponse.json({ error: "The current Yoruba Source must be approved before Craft." }, { status: 409 });

  let segments: StoryCutSegmentInput[];
  let parentCutId: string | null = null;
  if (body.data.intent === "create_proposal") {
    const { data: transcriptSegments } = await supabase.from("transcript_segments").select("id,source_start_ms,source_end_ms,text_yoruba").eq("story_id", storyId).eq("transcript_artifact_id", transcript.artifact_version_id).order("segment_number", { ascending: true });
    if (!transcriptSegments?.length) return NextResponse.json({ error: "No approved transcript segments are available." }, { status: 409 });
    let proposal;
    try {
      proposal = await openAIStoryCutProposal(transcriptSegments.map((item) => ({ id: item.id, startMs: item.source_start_ms, endMs: item.source_end_ms, text: item.text_yoruba })));
    } catch {
      return NextResponse.json({ error: "The Story Cut proposal could not be generated. Please retry." }, { status: 503 });
    }
    const byId = new Map(transcriptSegments.map((item, index) => [item.id, { item, index }]));
    const ordered = proposal.map((entry) => byId.get(entry.transcriptSegmentId));
    if (ordered.some((entry) => !entry) || ordered.some((entry, index) => index > 0 && entry!.index <= ordered[index - 1]!.index)) return NextResponse.json({ error: "The Story Cut proposal could not be validated. Please retry." }, { status: 502 });
    segments = proposal.map((entry) => {
      const item = byId.get(entry.transcriptSegmentId)!.item;
      return { ...entry, sourceStartMs: item.source_start_ms, sourceEndMs: item.source_end_ms };
    });
  } else {
    const { data: parent } = await supabase.from("story_cut_versions").select("artifact_version_id").eq("story_id", storyId).eq("source_media_artifact_id", media.artifact_version_id).eq("transcript_artifact_id", transcript.artifact_version_id).order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (!parent) return NextResponse.json({ error: "Create the first Story Cut proposal before editing it." }, { status: 409 });
    parentCutId = parent.artifact_version_id;
    const { data: oldSegments } = await supabase.from("story_cut_segments").select("transcript_segment_id,source_start_ms,source_end_ms,narrative_role,selection_rationale").eq("story_id", storyId).eq("cut_artifact_id", parentCutId);
    const byId = new Map((oldSegments ?? []).map((segment) => [segment.transcript_segment_id, segment]));
    if (new Set(body.data.orderedSegmentIds).size !== body.data.orderedSegmentIds.length || body.data.orderedSegmentIds.some((id) => !byId.has(id))) return NextResponse.json({ error: "Refresh the Story Cut before saving these changes." }, { status: 409 });
    segments = body.data.orderedSegmentIds.map((id) => {
      const item = byId.get(id)!;
      return { transcriptSegmentId: id, sourceStartMs: item.source_start_ms, sourceEndMs: item.source_end_ms, narrativeRole: item.narrative_role, selectionRationale: item.selection_rationale };
    });
  }
  const valid = z.array(proposalSegmentSchema.extend({ sourceStartMs: z.number().int().nonnegative(), sourceEndMs: z.number().int().positive() }).strict()).min(1).max(1000).safeParse(segments);
  if (!valid.success) return NextResponse.json({ error: "The Story Cut proposal was invalid." }, { status: 500 });
  const contentHash = canonicalStoryCutHash(media.artifact_version_id, transcript.artifact_version_id, valid.data);
  const admin = createSupabaseAdminClient();
  const { data: cutId, error } = await admin.rpc("persist_story_cut", {
    p_story_id: storyId, p_actor_id: user.id, p_source_id: media.artifact_version_id,
    p_transcript_id: transcript.artifact_version_id, p_segments: valid.data,
    p_hash: `\\x${contentHash.toString("hex")}`, p_parent_cut_id: parentCutId,
  });
  if (error || !cutId) return NextResponse.json({ error: "The Story Cut could not be saved. Refresh and try again." }, { status: 409 });
  return NextResponse.json({ cutArtifactId: cutId, state: "proposal" }, { headers: { "Cache-Control": "no-store" } });
}
