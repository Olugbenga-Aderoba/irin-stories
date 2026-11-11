import { createHash } from "node:crypto";
import { createWriteStream } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { NextResponse, type NextRequest } from "next/server";
import { Readable, Transform } from "node:stream";
import { pipeline } from "node:stream/promises";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { extractAudioForTranscription } from "@/lib/verify/media-probe";
import { canonicalTranscriptHash } from "@/lib/verify/transcript-contract";
import { transcribeYoruba } from "@/lib/verify/transcription";

export const maxDuration = 900;
const requestSchema = z.object({ intent: z.literal("transcribe"), processingConsent: z.literal(true) }).strict();
const MAX_SOURCE_BYTES = 524_288_000;

export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string }> }) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) return NextResponse.json({ error: "Request origin was not accepted." }, { status: 403 });
  const { storyId } = await context.params;
  if (!z.string().uuid().safeParse(storyId).success) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const body = requestSchema.safeParse(await request.json().catch(() => null));
  if (!body.success) return NextResponse.json({ error: "Explicitly consent to Yoruba transcription to continue." }, { status: 400 });

  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in to transcribe this source." }, { status: 401 });
  const { data: story } = await supabase.from("stories").select("id,owner_id").eq("id", storyId).maybeSingle();
  if (!story || story.owner_id !== user.id) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const { data: source } = await supabase.from("media_assets")
    .select("artifact_version_id,object_key,bucket_id,role")
    .eq("story_id", storyId).eq("role", "SOURCE").order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (!source || source.bucket_id !== "private-source") return NextResponse.json({ error: "A current private source is required." }, { status: 409 });
  const [{ data: verification }, { data: eligible }] = await Promise.all([
    supabase.from("source_media_verifications").select("status,server_content_sha256,verification_number")
      .eq("story_id", storyId).eq("source_media_artifact_id", source.artifact_version_id)
      .order("verification_number", { ascending: false }).limit(1).maybeSingle(),
    supabase.rpc("is_transcription_eligible", { p_story_id: storyId }),
  ]);
  const verifiedHash = typeof verification?.server_content_sha256 === "string"
    ? verification.server_content_sha256.replace(/^\\x/i, "").toLowerCase() : "";
  if (!verification || verification.status !== "READY" || !/^[a-f0-9]{64}$/.test(verifiedHash) || eligible !== true) {
    return NextResponse.json({ error: "Verify the current source and explicitly confirm Yoruba before transcription." }, { status: 409 });
  }
  if (!process.env.OPENAI_API_KEY) return NextResponse.json({ error: "Yoruba transcription is temporarily unavailable." }, { status: 503 });
  const { data: signed, error: signError } = await supabase.storage.from("private-source").createSignedUrl(source.object_key, 300);
  if (signError || !signed) return NextResponse.json({ error: "The private source could not be retrieved. Please retry." }, { status: 503 });

  let directory: string | undefined;
  try {
    directory = await mkdtemp(join(tmpdir(), "irin-transcribe-"));
    const videoPath = join(directory, "source-video");
    const response = await fetch(signed.signedUrl, { cache: "no-store", signal: AbortSignal.timeout(15 * 60_000) });
    if (!response.ok || !response.body) return NextResponse.json({ error: "The private source could not be downloaded. Please retry." }, { status: 503 });
    const declaredLength = Number(response.headers.get("content-length"));
    if (Number.isFinite(declaredLength) && declaredLength > MAX_SOURCE_BYTES) return NextResponse.json({ error: "The source exceeds the media-processing limit." }, { status: 413 });
    const digest = createHash("sha256");
    let bytes = 0;
    const limiter = new Transform({ transform(chunk: Buffer, _encoding, callback) {
      bytes += chunk.byteLength;
      if (bytes > MAX_SOURCE_BYTES) return callback(new Error("source limit exceeded"));
      digest.update(chunk); callback(null, chunk);
    } });
    await pipeline(Readable.fromWeb(response.body as unknown as Parameters<typeof Readable.fromWeb>[0]), limiter, createWriteStream(videoPath, { flags: "wx" }));
    if (digest.digest("hex") !== verifiedHash) return NextResponse.json({ error: "The source no longer matches its verified version. Verify it again." }, { status: 409 });
    const audioPath = join(directory, "yoruba-source.flac");
    await extractAudioForTranscription(videoPath, audioPath);
    const segments = await transcribeYoruba(audioPath);
    const hashSegments = segments.map((segment) => ({
      startMs: Math.round(segment.startSeconds * 1000), endMs: Math.round(segment.endSeconds * 1000), initialProposal: segment.text, text: segment.text,
    }));
    const contentHash = canonicalTranscriptHash(source.artifact_version_id, hashSegments).toString("hex");
    const admin = createSupabaseAdminClient();
    const { data: transcriptArtifactId, error } = await admin.rpc("persist_yoruba_transcript", {
      p_story_id: storyId, p_actor_id: user.id, p_source_media_artifact_id: source.artifact_version_id,
      p_segments: segments, p_content_sha256: `\\x${contentHash}`, p_action: "ai_transcription", p_parent_transcript_artifact_id: null,
    });
    if (error || !transcriptArtifactId) return NextResponse.json({ error: "The transcript could not be saved. Please retry." }, { status: 503 });
    return NextResponse.json({ transcriptArtifactId, segmentCount: segments.length, languageCode: "yor" }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return NextResponse.json({ error: "Yoruba transcription could not be completed. Please retry." }, { status: 503 });
  } finally {
    if (directory) await rm(directory, { recursive: true, force: true }).catch(() => undefined);
  }
}
