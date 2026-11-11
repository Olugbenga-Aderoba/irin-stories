import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const requestSchema = z.discriminatedUnion("intent", [
  z.object({ intent: z.literal("prepare_snapshot") }).strict(),
  z.object({ intent: z.literal("approve_final"), snapshotId: z.string().uuid() }).strict(),
  z.object({ intent: z.literal("publish"), snapshotId: z.string().uuid() }).strict(),
  z.object({ intent: z.literal("withdraw"), snapshotId: z.string().uuid() }).strict(),
]);
const snapshotResultSchema = z.object({ snapshot_id: z.string().uuid(), public_id: z.string().uuid() });
const timestampResultSchema = z.string().datetime({ offset: true });

export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string }> }) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) return NextResponse.json({ error: "Request origin was not accepted." }, { status: 403 });
  const { storyId } = await context.params;
  if (!z.string().uuid().safeParse(storyId).success) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const body = requestSchema.safeParse(await request.json().catch(() => null));
  if (!body.success) return NextResponse.json({ error: "An explicit publication action is required." }, { status: 400 });
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in to manage publication." }, { status: 401 });
  const { data: story } = await supabase.from("stories").select("id,owner_id").eq("id", storyId).maybeSingle();
  if (!story || story.owner_id !== user.id) return NextResponse.json({ error: "Story not found." }, { status: 404 });
  const admin = createSupabaseAdminClient();
  if (body.data.intent === "prepare_snapshot") {
    const { data, error } = await admin.rpc("create_publication_snapshot", { p_story: storyId, p_actor: user.id }).single();
    const result = snapshotResultSchema.safeParse(data);
    if (error || !result.success) return NextResponse.json({ error: "Publication is not eligible yet. Complete current approvals, privacy decisions, and Covenant first." }, { status: 409 });
    return NextResponse.json({ snapshotId: result.data.snapshot_id, publicId: result.data.public_id, state: "DRAFT" }, { headers: { "Cache-Control": "no-store" } });
  }
  const { data, error } = body.data.intent === "approve_final"
    ? await admin.rpc("approve_publication_snapshot", { p_story: storyId, p_actor: user.id, p_snapshot: body.data.snapshotId })
    : body.data.intent === "publish"
      ? await admin.rpc("publish_story_snapshot", { p_story: storyId, p_actor: user.id, p_snapshot: body.data.snapshotId })
      : await admin.rpc("withdraw_story_publication", { p_story: storyId, p_actor: user.id, p_snapshot: body.data.snapshotId });
  const changedAt = timestampResultSchema.safeParse(data);
  if (error || !changedAt.success) return NextResponse.json({ error: body.data.intent === "withdraw" ? "Only an active publication can be withdrawn." : "This publication action could not be completed for the current approved versions." }, { status: 409 });
  return NextResponse.json({ state: body.data.intent === "approve_final" ? "APPROVED" : body.data.intent === "publish" ? "PUBLISHED" : "WITHDRAWN", changedAt: changedAt.data }, { headers: { "Cache-Control": "no-store" } });
}
