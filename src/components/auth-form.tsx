"use client";

import { useState, type FormEvent } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabase/client";

export function AuthForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const next = searchParams.get("next");
  const destination = next?.startsWith("/") && !next.startsWith("//") ? next : "/workspace";
  const [mode, setMode] = useState<"sign-in" | "sign-up">("sign-in");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setNotice(null);
    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") ?? "").trim();
    const password = String(form.get("password") ?? "");
    const supabase = createSupabaseBrowserClient();
    const result = mode === "sign-in"
      ? await supabase.auth.signInWithPassword({ email, password })
      : await supabase.auth.signUp({ email, password, options: { emailRedirectTo: `${window.location.origin}/auth/callback` } });

    setBusy(false);
    if (result.error) {
      setError(result.error.message);
      return;
    }
    if (mode === "sign-up" && !result.data.session) {
      setNotice("Check your email to confirm your account, then sign in.");
      return;
    }
    router.replace(destination);
    router.refresh();
  }

  return (
    <section className="auth-card" aria-labelledby="auth-title">
      <p className="eyebrow">YOUR PRIVATE STORY SPACE</p>
      <h1 id="auth-title">{mode === "sign-in" ? "Welcome back." : "Create your storyteller account."}</h1>
      <p>Sign in securely with Irin Stories. Your account is managed by Supabase Auth.</p>
      <form className="auth-form" onSubmit={submit}>
        <label>Email address<input autoComplete="email" name="email" required type="email" /></label>
        <label>Password<input autoComplete={mode === "sign-in" ? "current-password" : "new-password"} minLength={8} name="password" required type="password" /></label>
        {error && <p className="form-error" role="alert">{error}</p>}
        {notice && <p className="form-success" role="status">{notice}</p>}
        <button className="button button--primary" disabled={busy} type="submit">
          {busy ? "Please wait…" : mode === "sign-in" ? "Sign in" : "Create account"}
        </button>
      </form>
      <p className="auth-switch">
        {mode === "sign-in" ? "New to Irin Stories?" : "Already have an account?"}{" "}
        <button type="button" onClick={() => { setMode(mode === "sign-in" ? "sign-up" : "sign-in"); setError(null); setNotice(null); }}>
          {mode === "sign-in" ? "Create an account" : "Sign in"}
        </button>
      </p>
      <Link className="auth-home-link" href="/">Return home</Link>
    </section>
  );
}
