import { Suspense } from "react";
import { AuthForm } from "@/components/auth-form";

export default function SignInPage() {
  return <main className="auth-page"><Suspense fallback={<p>Loading sign in…</p>}><AuthForm /></Suspense></main>;
}
