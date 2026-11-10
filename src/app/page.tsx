import { Suspense } from "react";
import { HomePage } from "@/components/home-page";
import { createSupabaseServerClient } from "@/lib/supabase/server";

async function AuthAwareHome() {
  let signedIn = false;
  try {
    const supabase = await createSupabaseServerClient();
    signedIn = Boolean((await supabase.auth.getUser()).data.user);
  } catch {
    // The marketing page stays viewable before Supabase environment setup.
  }
  return <HomePage signedIn={signedIn} />;
}

export default function Home() {
  return <Suspense fallback={<HomePage />}><AuthAwareHome /></Suspense>;
}
