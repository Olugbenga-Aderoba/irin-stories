"use server";

import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function signOut() {
  const supabase = await createSupabaseServerClient();
  await supabase.auth.signOut();
  redirect("/");
}

export async function createStory() {
  const supabase = await createSupabaseServerClient();
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) redirect("/sign-in?next=/workspace");

  const { data: storyId, error } = await supabase.rpc("create_story");
  if (error || !storyId) throw new Error("Your story could not be created. Please try again.");
  redirect(`/story/${storyId}/tell`);
}
