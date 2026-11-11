import { randomUUID } from "node:crypto";
import { expect, test } from "@playwright/test";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const isLocal = Boolean(supabaseUrl && ["127.0.0.1", "localhost"].includes(new URL(supabaseUrl).hostname));

test("owner verifies synthetic media and completes no-reliable-language fallback", async ({ page }) => {
  test.setTimeout(120_000);
  test.skip(!isLocal, "This test requires the disposable local Supabase stack.");

  const email = `verify-${randomUUID()}@example.invalid`;
  const password = `Synthetic-${randomUUID()}a1`;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceKey) throw new Error("The local E2E setup requires its local Supabase service key.");
  const createUser = await fetch(`${supabaseUrl}/auth/v1/admin/users`, {
    method: "POST",
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  if (!createUser.ok) throw new Error(`Local synthetic Auth fixture failed with HTTP ${createUser.status}.`);

  await page.goto("/sign-in");
  await page.getByLabel("Email address").fill(email);
  await page.getByLabel("Password").fill(password);
  await page.locator(".auth-form").getByRole("button", { name: "Sign in" }).click();
  await expect(page).toHaveURL(/\/workspace$/, { timeout: 30_000 });
  await page.getByRole("button", { name: /Start your story/ }).click();
  await expect(page).toHaveURL(/\/story\/[0-9a-f-]+\/tell$/);

  const syntheticWebm = await page.evaluate(async () => {
    const canvas = document.createElement("canvas");
    canvas.width = 64;
    canvas.height = 64;
    const context = canvas.getContext("2d");
    const videoStream = canvas.captureStream(12);
    const audioContext = new AudioContext();
    const oscillator = audioContext.createOscillator();
    const destination = audioContext.createMediaStreamDestination();
    oscillator.frequency.value = 440;
    oscillator.connect(destination);
    oscillator.start();
    const stream = new MediaStream([...videoStream.getVideoTracks(), ...destination.stream.getAudioTracks()]);
    const mimeType = MediaRecorder.isTypeSupported("video/webm;codecs=vp8,opus") ? "video/webm;codecs=vp8,opus" : "video/webm";
    const recorder = new MediaRecorder(stream, { mimeType });
    const chunks: BlobPart[] = [];
    recorder.ondataavailable = (event) => { if (event.data.size) chunks.push(event.data); };
    const stopped = new Promise<Blob>((resolve) => { recorder.onstop = () => resolve(new Blob(chunks, { type: "video/webm" })); });
    recorder.start();
    const frames = window.setInterval(() => {
      if (context) { context.fillStyle = "#386d5a"; context.fillRect(0, 0, 64, 64); }
    }, 80);
    await new Promise((resolve) => setTimeout(resolve, 2200));
    window.clearInterval(frames);
    recorder.stop();
    const blob = await stopped;
    oscillator.stop();
    stream.getTracks().forEach((track) => track.stop());
    await audioContext.close();
    const bytes = new Uint8Array(await blob.arrayBuffer());
    let binary = "";
    bytes.forEach((byte) => { binary += String.fromCharCode(byte); });
    return { base64: btoa(binary), mimeType: blob.type };
  });

  await page.locator('input[type="file"]').setInputFiles({
    name: "synthetic-verify.webm",
    mimeType: syntheticWebm.mimeType,
    buffer: Buffer.from(syntheticWebm.base64, "base64"),
  });
  await expect(page.getByRole("button", { name: "Upload privately" })).toBeEnabled({ timeout: 15_000 });
  await page.getByRole("button", { name: "Upload privately" }).click();
  await expect(page.getByText("Upload complete. Your source video is private to you.")).toBeVisible({ timeout: 60_000 });
  await page.getByRole("link", { name: "Continue to Verify" }).click();
  await expect(page).toHaveURL(/\/story\/[0-9a-f-]+\/verify$/);

  await page.getByRole("button", { name: "Verify source media" }).click();
  await expect(page.getByText(/Source verified/)).toBeVisible({ timeout: 60_000 });
  await expect(page.getByText(/Video: vp8/)).toBeVisible();
  await expect(page.getByText(/Audio: opus/)).toBeVisible();
  await expect(page.getByText(/Detect original language/)).toBeVisible();
  await expect(page.getByRole("button", { name: "Detect original language" })).toBeDisabled();
  await expect(page.getByText(/Yoruba is the only language supported for transcription/i)).toBeVisible();

  const storyId = page.url().match(/\/story\/([0-9a-f-]+)\/verify$/i)?.[1];
  if (!storyId) throw new Error("Synthetic story ID could not be read from the local workspace URL.");
  const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" };
  const sourceResponse = await fetch(`${supabaseUrl}/rest/v1/media_assets?select=artifact_version_id&story_id=eq.${storyId}&role=eq.SOURCE&order=created_at.desc&limit=1`, { headers });
  if (!sourceResponse.ok) throw new Error(`Local source fixture lookup failed with HTTP ${sourceResponse.status}.`);
  const [source] = await sourceResponse.json() as Array<{ artifact_version_id: string }>;
  if (!source) throw new Error("The verified synthetic source fixture is missing.");
  const diagnosticResponse = await fetch(`${supabaseUrl}/rest/v1/verify_language_detection_diagnostics`, {
    method: "POST", headers: { ...headers, Prefer: "return=minimal" },
    body: JSON.stringify({ correlation_id: randomUUID(), story_id: storyId, attempted_at: new Date().toISOString(), stage: "provider_response_validation", category: "no_reliable_language", retryable: true, provider: "openai", model: "gpt-transcribe", provider_http_status: 200 }),
  });
  if (!diagnosticResponse.ok) throw new Error(`Local no-reliable-language fixture failed with HTTP ${diagnosticResponse.status}.`);

  await page.reload();
  await expect(page.getByText(/We couldn't identify the original language reliably/)).toBeVisible();
  await expect(page.getByText("Detected: Yoruba")).toHaveCount(0);
  await page.getByRole("button", { name: "Select Yoruba" }).click();
  await expect(page.getByText("Selected, awaiting confirmation")).toBeVisible();
  await expect(page.getByText("Transcription: Not yet eligible")).toBeVisible();
  await expect(page.getByText("Detected: Yoruba")).toHaveCount(0);
  await page.getByRole("button", { name: "Confirm Yoruba" }).click();
  await expect(page.getByText("Confirmed by storyteller")).toBeVisible();
  await expect(page.getByText("Transcription: Eligible for the next Verify step")).toBeVisible();
  await expect(page.getByText("Detected: Yoruba")).toHaveCount(0);
});
