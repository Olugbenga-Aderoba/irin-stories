import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { canonicalTranscriptHash } from "@/lib/verify/transcript-contract";

const requestSchema = z.object({ segments: z.array(z.object({ segmentNumber: z.number().int().positive(), text: z.string().trim().min(1).max(10_000) }).strict()).min(1).max(10_000) }).strict();

export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string; transcriptId: string }> }) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) return NextResponse.json({ error: "Request origin was not accepted." }, { status: 403 });
  const { storyId, transcriptId } = await context.params;
  if (![storyId, transcriptId].every((id) => z.string().uuid().safeParse(id).success)) return NextResponse.json({ error: "Transcript not found." }, { status: 404 });
  const body = requestSchema.safeParse(await request.json().catch(() => null));
  if (!body.success) return NextResponse.json({ error: "Review every transcript segment before saving." }, { status: 400 });
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in to edit this transcript." }, { status: 401 });
  const { data: story } = await supabase.from("stories").select("id,owner_id").eq("id", storyId).maybeSingle();
  if (!story || story.owner_id !== user.id) return NextResponse.json({ error: "Transcript not found." }, { status: 404 });
  const { data: transcript } = await supabase.from("transcript_versions")
    .select("artifact_version_id,source_media_artifact_id,language_code")
    .eq("story_id", storyId).eq("artifact_version_id", transcriptId).maybeSingle();
  if (!transcript || transcript.language_code !== "yor") return NextResponse.json({ error: "Transcript not found." }, { status: 404 });
  const [{ data: sources }, { data: eligible }, { data: segments }] = await Promise.all([
    supabase.from("media_assets").select("artifact_version_id").eq("story_id", storyId).eq("role", "SOURCE").order("created_at", { ascending: false }).limit(1),
    supabase.rpc("is_transcription_eligible", { p_story_id: storyId }),
    supabase.from("transcript_segments").select("segment_number,source_start_ms,source_end_ms,initial_proposal,text_yoruba")
      .eq("story_id", storyId).eq("transcript_artifact_id", transcriptId).order("segment_number", { ascending: true }),
  ]);
  if (transcript.source_media_artifact_id !== sources?.[0]?.artifact_version_id || eligible !== true || !segments?.length || segments.length !== body.data.segments.length) {
    return NextResponse.json({ error: "Only the current eligible transcript can be edited." }, { status: 409 });
  }
  const edits = new Map(body.data.segments.map((segment) => [segment.segmentNumber, segment.text]));
  if (edits.size !== segments.length || segments.some((segment, index) => !edits.has(index + 1))) {
    return NextResponse.json({ error: "Transcript segments changed. Refresh and try again." }, { status: 409 });
  }
  const hashInput = segments.map((segment) => ({
    startMs: segment.source_start_ms, endMs: segment.source_end_ms, initialProposal: segment.initial_proposal ?? "", text: edits.get(segment.segment_number)!,
  }));
  const contentHash = canonicalTranscriptHash(transcript.source_media_artifact_id, hashInput).toString("hex");
  const admin = createSupabaseAdminClient();
  const { data: nextTranscriptId, error } = await admin.rpc("persist_yoruba_transcript", {
    p_story_id: storyId, p_actor_id: user.id, p_source_media_artifact_id: transcript.source_media_artifact_id,
    p_segments: body.data.segments, p_content_sha256: `\\x${contentHash}`, p_action: "storyteller_edit", p_parent_transcript_artifact_id: transcriptId,
  });
  if (error || !nextTranscriptId) return NextResponse.json({ error: "The corrected transcript could not be saved. Please retry." }, { status: 409 });
  return NextResponse.json({ transcriptArtifactId: nextTranscriptId, state: "draft" }, { headers: { "Cache-Control": "no-store" } });
}
