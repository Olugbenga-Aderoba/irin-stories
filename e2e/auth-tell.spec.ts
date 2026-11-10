import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const isLocalSupabase = Boolean(supabaseUrl && ["127.0.0.1", "localhost"].includes(new URL(supabaseUrl).hostname));

async function signUpAndReachWorkspace(page: import("@playwright/test").Page, email: string, password: string) {
  await page.goto("/sign-in");
  await page.getByRole("button", { name: "Create an account" }).click();
  await expect(page.getByRole("heading", { name: "Create your storyteller account." })).toBeVisible();
  await page.getByLabel("Email address").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.locator(".auth-form").getByRole("button", { name: "Create account" }).click();

  try {
    await expect(page).toHaveURL(/\/workspace$/, { timeout: 15_000 });
  } catch {
    // Local auth may return a confirmed account without a browser session.
    // Exercise the normal sign-in path for that same synthetic account.
    await page.locator(".auth-switch").getByRole("button", { name: "Sign in" }).click();
    await expect(page.getByRole("heading", { name: "Welcome back." })).toBeVisible();
    await page.locator(".auth-form").getByRole("button", { name: "Sign in" }).click();
    await expect(page).toHaveURL(/\/workspace$/, { timeout: 15_000 });
  }
}

async function createStoryAndOpenTell(page: import("@playwright/test").Page) {
  await page.getByRole("button", { name: /Start your story/ }).click();
  const tellPath = /\/story\/[0-9a-f-]+\/tell$/;
  try {
    await expect(page).toHaveURL(tellPath, { timeout: 15_000 });
    return { directRouteWorked: true, path: new URL(page.url()).pathname };
  } catch {
    // Keep validating Tell independently if the server action creates a row
    // but fails to deliver its redirect. The failed direct route is asserted
    // at the end so this fallback cannot turn that defect into a pass.
    if (tellPath.test(new URL(page.url()).pathname)) {
      return { directRouteWorked: true, path: new URL(page.url()).pathname };
    }
    await page.reload();
    if (tellPath.test(new URL(page.url()).pathname)) {
      return { directRouteWorked: false, path: new URL(page.url()).pathname };
    }
    const firstStory = page.locator(".story-list a").first();
    await expect(firstStory).toBeVisible();
    await firstStory.click();
    await expect(page).toHaveURL(/\/story\/[0-9a-f-]+\/tell$/);
    return { directRouteWorked: false, path: new URL(page.url()).pathname };
  }
}

test("anonymous visitors are redirected from the storyteller workspace", async ({ page }) => {
  test.skip(!isLocalSupabase, "Set NEXT_PUBLIC_SUPABASE_URL to a disposable local Supabase stack.");
  await page.goto("/workspace");
  await expect(page).toHaveURL(/\/sign-in\?/);
  await expect(page.getByRole("heading", { name: "Welcome back." })).toBeVisible();
});

test("a synthetic storyteller signs up, creates multiple stories, and reaches Tell", async ({ page }) => {
  test.setTimeout(90_000);
  test.skip(!isLocalSupabase, "Set NEXT_PUBLIC_SUPABASE_URL to a disposable local Supabase stack.");
  const emailA = `codex-${randomUUID()}@example.invalid`;
  const passwordA = `Synthetic-${randomUUID()}a1`;
  await signUpAndReachWorkspace(page, emailA, passwordA);
  await expect(page.getByRole("heading", { name: "Your stories, held with care." })).toBeVisible();
  const firstStory = await createStoryAndOpenTell(page);
  const firstStoryPath = firstStory.path;
  await expect(page.getByRole("heading", { name: "My Story" })).toBeVisible();
  await expect(page.getByText("Detect automatically")).toBeVisible();
  await expect(page.getByText(/No language has been detected yet/)).toBeVisible();
  await expect(page.getByText(/MP4, MOV, or WebM/)).toBeVisible();

  const picker = page.locator('input[type="file"]');
  await picker.setInputFiles({ name: "synthetic-invalid.txt", mimeType: "text/plain", buffer: Buffer.from("synthetic") });
  await expect(page.locator(".source-upload-card p[role=alert]")).toContainText("Choose an MP4, MOV, or WebM video.");

  const webm = await page.evaluate(async () => {
    const canvas = document.createElement("canvas");
    canvas.width = 64;
    canvas.height = 64;
    const context = canvas.getContext("2d");
    const stream = canvas.captureStream(12);
    const recorder = new MediaRecorder(stream, { mimeType: "video/webm;codecs=vp8" });
    const chunks: BlobPart[] = [];
    recorder.ondataavailable = (event) => { if (event.data.size) chunks.push(event.data); };
    const stopped = new Promise<Blob>((resolve) => { recorder.onstop = () => resolve(new Blob(chunks, { type: "video/webm" })); });
    recorder.start();
    const frame = window.setInterval(() => {
      if (context) { context.fillStyle = `rgb(${Math.floor(Math.random() * 255)},40,90)`; context.fillRect(0, 0, 64, 64); }
    }, 80);
    await new Promise((resolve) => setTimeout(resolve, 1800));
    window.clearInterval(frame);
    recorder.stop();
    const blob = await stopped;
    stream.getTracks().forEach((track) => track.stop());
    const bytes = new Uint8Array(await blob.arrayBuffer());
    let binary = "";
    bytes.forEach((byte) => { binary += String.fromCharCode(byte); });
    return { base64: btoa(binary), type: blob.type };
  });
  await picker.setInputFiles({ name: "synthetic-test.webm", mimeType: webm.type, buffer: Buffer.from(webm.base64, "base64") });
  await expect(page.getByRole("button", { name: "Upload privately" })).toBeEnabled({ timeout: 15_000 });
  await expect(page.getByText(/synthetic-test\.webm/)).toBeVisible();

  await page.getByRole("link", { name: "My stories" }).click();
  const secondStory = await createStoryAndOpenTell(page);
  expect(secondStory.path).not.toBe(firstStoryPath);

  await page.getByRole("button", { name: "Sign out" }).click();
  const emailB = `codex-${randomUUID()}@example.invalid`;
  const passwordB = `Synthetic-${randomUUID()}b2`;
  await signUpAndReachWorkspace(page, emailB, passwordB);
  await page.goto(firstStoryPath);
  await expect(page.getByText("This page could not be found.")).toBeVisible();

  expect(firstStory.directRouteWorked && secondStory.directRouteWorked,
    "the Start your story action should redirect directly to Tell for each new story").toBe(true);
});
