import "server-only";

import { createClient } from "@supabase/supabase-js";
import { getSupabasePublicEnv } from "./env";

export function createSupabaseAdminClient() {
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceRoleKey) {
    throw new Error("Trusted server database operations are not configured.");
  }
  const { url } = getSupabasePublicEnv();
  return createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
}
