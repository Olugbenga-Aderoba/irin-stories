import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createSupabaseServerClient } from "@/lib/supabase/server";

const confirmation = z.object({
  sourceMediaArtifactId: z.string().uuid(),
  proposalReviewId: z.string().uuid(),
  languageCode: z.string().regex(/^[a-z]{3}(?:-[A-Za-z0-9]{2,8})*$/),
  displayName: z.string().trim().min(1).max(120),
}).strict();
const selectedConfirmation = z.object({ decisionId: z.string().uuid(), intent: z.literal("confirm") }).strict();

export async function POST(request: NextRequest, context: { params: Promise<{ storyId: string }> }) {
  const origin = request.headers.get("origin");
  if (origin && origin !== new URL(request.url).origin) {
    return NextResponse.json({ error: "Request origin was not accepted." }, { status: 403 });
  }

  const { storyId } = await context.params;
  if (!z.string().uuid().safeParse(storyId).success) {
    return NextResponse.json({ error: "Story not found." }, { status: 404 });
  }

  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in to confirm the original language." }, { status: 401 });

  const { data: story } = await supabase.from("stories").select("id").eq("id", storyId).maybeSingle();
  if (!story) return NextResponse.json({ error: "Story not found." }, { status: 404 });

  let body: unknown;
  try { body = await request.json(); } catch { return NextResponse.json({ error: "Invalid confirmation request." }, { status: 400 }); }
  const selected = selectedConfirmation.safeParse(body);
  if (selected.success) {
    const { data, error } = await supabase.rpc("confirm_storyteller_language", { p_story_id: storyId, p_decision_id: selected.data.decisionId }).single();
    if (error || !data) return NextResponse.json({ error: error?.code === "42501" ? "This pending selection is not available for your current source." : "Your confirmation could not be saved." }, { status: error?.code === "42501" ? 403 : 409 });
    const result = data as unknown as { decision_id: string; state: string; transcription_eligible: boolean };
    return NextResponse.json({ decisionId: result.decision_id, state: result.state, transcriptionEligible: result.transcription_eligible }, { headers: { "Cache-Control": "no-store" } });
  }
  const parsed = confirmation.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: "Enter a language name and a valid three-letter language code." }, { status: 400 });

  const { data, error } = await supabase.rpc("confirm_source_language", {
    p_story_id: storyId,
    p_source_media_artifact_id: parsed.data.sourceMediaArtifactId,
    p_proposal_review_id: parsed.data.proposalReviewId,
    p_confirmed_language_code: parsed.data.languageCode,
    p_confirmed_language_name: parsed.data.displayName,
  }).single();

  if (error || !data) {
    const status = error?.code === "42501" ? 403 : error?.code === "22023" ? 409 : 503;
    return NextResponse.json({ error: status === 403
      ? "This language proposal does not belong to your current story source."
      : status === 409
        ? "The language proposal has changed. Refresh and review the current proposal."
        : "Your language decision could not be saved. Please retry." }, { status });
  }

  const result = data as unknown as { review_status: string; transcription_eligible: boolean };
  return NextResponse.json({
    reviewStatus: result.review_status,
    confirmedLanguageCode: parsed.data.languageCode,
    confirmedLanguageName: parsed.data.displayName,
    transcriptionEligible: result.transcription_eligible,
    supportedForMvp: parsed.data.languageCode === "yor",
  }, { headers: { "Cache-Control": "no-store" } });
}
