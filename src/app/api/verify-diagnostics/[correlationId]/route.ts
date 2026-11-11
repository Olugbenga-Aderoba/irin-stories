import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { createSupabaseAdminClient } from "@/lib/supabase/admin";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest, context: { params: Promise<{ correlationId: string }> }) {
  const { correlationId } = await context.params;
  if (!z.string().uuid().safeParse(correlationId).success) return NextResponse.json({ error: "Not found." }, { status: 404 });
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Not found." }, { status: 404 });
  const admin = createSupabaseAdminClient();
  const { data, error } = await admin.from("verify_language_detection_diagnostics")
    .select("correlation_id,story_id,attempted_at,stage,category,retryable,provider,model,provider_http_status,provider_error_type,provider_error_code,provider_request_id,transport,database_code")
    .eq("correlation_id", correlationId).maybeSingle();
  if (error || !data?.story_id) return NextResponse.json({ error: "Not found." }, { status: 404 });
  const { data: story } = await supabase.from("stories").select("id").eq("id", data.story_id).eq("owner_id", user.id).maybeSingle();
  if (!story) return NextResponse.json({ error: "Not found." }, { status: 404 });
  return NextResponse.json(data, { headers: { "Cache-Control": "no-store" } });
}
