"use client";

import { createBrowserClient } from "@supabase/ssr";
import { getSupabasePublicEnv } from "./env";

export function createSupabaseBrowserClient() {
  const { url, key } = getSupabasePublicEnv();
  return createBrowserClient(url, key);
}
