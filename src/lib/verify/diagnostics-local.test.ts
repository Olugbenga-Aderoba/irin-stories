
import { execFileSync } from "node:child_process";
import { NextRequest } from "next/server";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

const state = vi.hoisted(() => ({ user: null as string | null }));
const owner = "71000000-0000-4000-8000-000000000001";
const other = "71000000-0000-4000-8000-000000000002";
const story = "71000000-0000-4000-8000-000000000003";
const reference = "71000000-0000-4000-8000-000000000004";
function sql(query: string) {
  return execFileSync("docker", ["exec", "-i", "supabase_db_irin-stories", "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"], { input: query, encoding: "utf8" }).trim();
}
function uuid(value: string) {
  if (!/^[a-f0-9-]{36}$/.test(value)) throw new Error("Invalid fixture UUID");
  return value;
}
vi.mock("@/lib/supabase/admin", () => ({
  createSupabaseAdminClient: () => ({
    from: () => ({ select: () => ({ eq: (_column: string, id: string) => ({
      maybeSingle: async () => {
        const data = sql("SET ROLE service_role; SELECT row_to_json(d) FROM public.verify_language_detection_diagnostics d WHERE correlation_id='" + uuid(id) + "';");
        return { data: data ? JSON.parse(data) : null, error: null };
      },
    }) }) }),
  }),
}));
vi.mock("@/lib/supabase/server", () => ({
  createSupabaseServerClient: async () => ({
    auth: { getUser: async () => ({ data: { user: state.user ? { id: state.user } : null } }) },
    from: () => {
      const filters: Record<string, string> = {};
      return {
        select() { return this; },
        eq(column: string, value: string) { filters[column] = uuid(value); return this; },
        async maybeSingle() {
          const data = sql("BEGIN; SET LOCAL ROLE authenticated; SET LOCAL request.jwt.claim.sub='" + uuid(state.user!) + "'; SELECT row_to_json(s) FROM (SELECT id FROM public.stories WHERE id='" + filters.id + "' AND owner_id='" + filters.owner_id + "') s; ROLLBACK;");
          return { data: data ? JSON.parse(data) : null, error: null };
        },
      };
    },
  }),
}));
import { GET } from "@/app/api/verify-diagnostics/[correlationId]/route";

describe.skipIf(process.env.VERIFY_DIAGNOSTICS_DB_TEST !== "1")("local database diagnostic lookup", () => {
  beforeAll(() => {
    sql("BEGIN; INSERT INTO auth.users(id,aud,role,email) VALUES ('" + owner + "','authenticated','authenticated','diagnostic-owner@example.invalid'),('" + other + "','authenticated','authenticated','diagnostic-other@example.invalid'); INSERT INTO public.stories(id,owner_id,title) VALUES ('" + story + "','" + owner + "','Synthetic diagnostic test'); SET LOCAL ROLE service_role; INSERT INTO public.verify_language_detection_diagnostics(correlation_id,story_id,attempted_at,stage,category,retryable,provider,model) VALUES ('" + reference + "','" + story + "',now(),'provider_request','provider_timeout',true,'openai','gpt-transcribe'); COMMIT;");
  });
  afterAll(() => {
    sql("BEGIN; DELETE FROM public.stories WHERE id='" + story + "'; DELETE FROM auth.users WHERE id IN ('" + owner + "','" + other + "'); COMMIT;");
  });
  it.each([
    [owner, reference, 200],
    [other, reference, 404],
    [null, reference, 404],
    [owner, "71000000-0000-4000-8000-000000000099", 404],
  ])("lookup user %s reference %s returns %s", async (user, id, status) => {
    state.user = user;
    const response = await GET(new NextRequest("http://localhost/api/verify-diagnostics/" + id), { params: Promise.resolve({ correlationId: id }) });
    expect(response.status).toBe(status);
    const body = await response.json();
    if (status === 200) expect(body).toMatchObject({ correlation_id: reference, story_id: story, category: "provider_timeout" });
    else expect(body).toEqual({ error: "Not found." });
  });
});
