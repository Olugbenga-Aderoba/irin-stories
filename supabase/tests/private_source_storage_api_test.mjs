import { randomBytes, randomUUID, createHash } from "node:crypto";
import { createClient } from "@supabase/supabase-js";

const url = process.env.LOCAL_SUPABASE_URL;
const anonKey = process.env.LOCAL_SUPABASE_ANON_KEY;
if (!url || !anonKey || !["127.0.0.1", "localhost"].includes(new URL(url).hostname)) {
  throw new Error("Set LOCAL_SUPABASE_URL and LOCAL_SUPABASE_ANON_KEY for the local stack only.");
}

const runId = randomUUID();
const results = [];
function record(name, expected, passed, details = "") {
  results.push({ test: name, expected, actual: passed ? "PASS" : "FAIL", details });
}
function check(name, expected, passed, details = "") {
  record(name, expected, passed, details);
  if (!passed) throw new Error(`${name} failed${details ? `: ${details}` : ""}`);
}
function client() {
  return createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
}
function must(data, error, label) {
  if (error) throw new Error(`${label}: ${error.message} (${error.code ?? "no SQLSTATE"})`);
  return data;
}
const A = client();
const B = client();
const anonymous = client();
const passwordA = `Synthetic-${randomBytes(18).toString("hex")}a1`;
const passwordB = `Synthetic-${randomBytes(18).toString("hex")}b2`;
const emailA = `codex-storage-a-${runId}@example.invalid`;
const emailB = `codex-storage-b-${runId}@example.invalid`;

// Run bcrypt-backed local sign-ups sequentially so a small disposable Auth
// container is not needlessly CPU-starved by concurrent password hashing.
async function signUpWithLocalRetry(who, email, password, label) {
  const created = await who.auth.signUp({ email, password });
  if (!created.error && created.data.session) return created;
  // A local Auth instance can persist the user but time out while returning
  // the initial response under cold-start CPU load. Verify through a fresh
  // password sign-in; keep the original signup timeout visible in results.
  const signedIn = await who.auth.signInWithPassword({ email, password });
  if (signedIn.error || !signedIn.data.session) {
    throw new Error(`${label} signup: ${created.error?.message ?? "confirmation required"}; sign-in retry: ${signedIn.error?.message ?? "no session"}`);
  }
  record(`${label} signup response`, "200 session", false, `${created.error?.message ?? "no session"}; account recovered by password sign-in`);
  return signedIn;
}
const signA = await signUpWithLocalRetry(A, emailA, passwordA, "A");
const signB = await signUpWithLocalRetry(B, emailB, passwordB, "B");
const userA = must(signA.data.user, signA.error, "Synthetic A Auth");
const userB = must(signB.data.user, signB.error, "Synthetic B Auth");
if (!signA.data.session || !signB.data.session) throw new Error("Local email confirmation must be disabled for disposable synthetic accounts.");
record("synthetic local Auth accounts signed in", "A and B", true);

async function createStory(who, title) {
  const { data, error } = await who.rpc("create_story");
  const storyId = must(data, error, "create_story");
  const { error: titleError } = await who.from("stories").update({ title }).eq("id", storyId);
  if (titleError) throw new Error(`Synthetic story title: ${titleError.message} (${titleError.code})`);
  return storyId;
}
const storyA1 = await createStory(A, `Synthetic Storage A1 ${runId}`);
const storyA2 = await createStory(A, `Synthetic Storage A2 ${runId}`);
record("A creates two stories", "2 owner-scoped stories", true);
const hiddenStory = await B.from("stories").select("id").in("id", [storyA1, storyA2]);
check("B cannot read A stories", "0 rows", !hiddenStory.error && hiddenStory.data.length === 0, hiddenStory.error?.code ?? "RLS returned no rows");

const invalidMimeKey = `${userA.id}/${storyA1}/${randomUUID()}/synthetic-invalid-mime.webm`;
const invalidMimeUpload = await A.storage.from("private-source").upload(invalidMimeKey, Buffer.from("synthetic"), {
  contentType: "text/plain", upsert: false,
});
check("Storage rejects invalid MIME type", "BLOCKED", Boolean(invalidMimeUpload.error),
  invalidMimeUpload.error?.statusCode ?? invalidMimeUpload.error?.message);

const artifactId = randomUUID();
const filename = `synthetic-${runId}.webm`;
const objectKey = `${userA.id}/${storyA1}/${artifactId}/${filename}`;
const bytes = Buffer.from([0x1a, 0x45, 0xdf, 0xa3, ...randomBytes(64)]);
const digest = createHash("sha256").update(bytes).digest("hex");
const uploaded = await A.storage.from("private-source").upload(objectKey, bytes, { contentType: "video/webm", upsert: false });
must(uploaded.data, uploaded.error, "A Storage upload");
const registered = await A.rpc("register_source_media", {
  p_story_id: storyA1,
  p_artifact_id: artifactId,
  p_object_key: objectKey,
  p_original_filename: filename,
  p_mime_type: "video/webm",
  p_byte_size: bytes.byteLength,
  p_duration_ms: 60_000,
  p_content_sha256: `\\x${digest}`,
});
must(registered.data, registered.error, "A register source media");
record("A uploads and registers source media", "ALLOWED", true);

const ownerDownload = await A.storage.from("private-source").download(objectKey);
check("A can read own source object", "ALLOWED", !ownerDownload.error && Boolean(ownerDownload.data));
const otherDownload = await B.storage.from("private-source").download(objectKey);
check("B cannot read A source object", "BLOCKED", Boolean(otherDownload.error), otherDownload.error?.statusCode ?? otherDownload.error?.message);
const anonDownload = await anonymous.storage.from("private-source").download(objectKey);
check("anonymous cannot read A source object", "BLOCKED", Boolean(anonDownload.error), anonDownload.error?.statusCode ?? anonDownload.error?.message);

const crossUpload = await B.storage.from("private-source").upload(objectKey, bytes, { contentType: "video/webm", upsert: false });
check("B cannot upload to A object path", "BLOCKED", Boolean(crossUpload.error), crossUpload.error?.statusCode ?? crossUpload.error?.message);
const crossRegister = await B.rpc("register_source_media", {
  p_story_id: storyA1, p_artifact_id: randomUUID(), p_object_key: objectKey,
  p_original_filename: filename, p_mime_type: "video/webm", p_byte_size: bytes.byteLength,
  p_duration_ms: 60_000, p_content_sha256: `\\x${digest}`,
});
check("B cannot register media under A story/path", "BLOCKED", Boolean(crossRegister.error), `${crossRegister.error?.code ?? "HTTP"}: ${crossRegister.error?.message ?? "unexpected success"}`);

const forgedStory = await A.from("stories").insert({ owner_id: userB.id, title: "Synthetic forged owner" }).select("id").maybeSingle();
check("client cannot forge owner_id", "BLOCKED", Boolean(forgedStory.error) || !forgedStory.data, `${forgedStory.error?.code ?? "no row"}: ${forgedStory.error?.message ?? ""}`);
const ownerChange = await A.from("stories").update({ owner_id: userB.id }).eq("id", storyA1).select("id");
const unchangedOwner = await A.from("stories").select("owner_id").eq("id", storyA1).single();
check("client cannot change story owner", "BLOCKED", (Boolean(ownerChange.error) || ownerChange.data?.length === 0) && unchangedOwner.data?.owner_id === userA.id,
  `${ownerChange.error?.code ?? "no rows changed"}; owner remains authenticated A`);

const publicObjectUrl = A.storage.from("private-source").getPublicUrl(objectKey).data.publicUrl;
const publicResponse = await fetch(publicObjectUrl);
check("public object URL is not accessible", "non-2xx", !publicResponse.ok, `HTTP ${publicResponse.status}`);

const aSigned = await A.storage.from("private-source").createSignedUrl(objectKey, 3600);
must(aSigned.data, aSigned.error, "A signed playback URL");
const signedToken = new URL(aSigned.data.signedUrl).searchParams.get("token");
let tokenClaims = null;
try { tokenClaims = signedToken ? JSON.parse(Buffer.from(signedToken.split(".")[1], "base64url").toString("utf8")) : null; } catch { /* assertion below reports invalid token */ }
check("signed playback URL expires after 3600 seconds", "exp - iat = 3600", tokenClaims?.exp - tokenClaims?.iat === 3600,
  `JWT lifetime ${tokenClaims?.exp - tokenClaims?.iat ?? "unavailable"} seconds`);
const signedResponse = await fetch(aSigned.data.signedUrl);
check("A receives authorized private playback", "HTTP 2xx", signedResponse.ok, `HTTP ${signedResponse.status}`);
const bSigned = await B.storage.from("private-source").createSignedUrl(objectKey, 60);
check("B cannot obtain playback URL for A object", "BLOCKED", Boolean(bSigned.error), bSigned.error?.statusCode ?? bSigned.error?.message);
const anonSigned = await anonymous.storage.from("private-source").createSignedUrl(objectKey, 60);
check("anonymous cannot obtain playback URL", "BLOCKED", Boolean(anonSigned.error), anonSigned.error?.statusCode ?? anonSigned.error?.message);

const overLimit = await fetch(`${url}/storage/v1/upload/resumable`, {
  method: "POST",
  headers: {
    authorization: `Bearer ${signA.data.session.access_token}`,
    apikey: anonKey,
    "tus-resumable": "1.0.0",
    "upload-length": "524288001",
    "upload-metadata": [
      ["bucketName", "private-source"], ["objectName", `${userA.id}/${storyA2}/${randomUUID()}/oversize.webm`],
      ["contentType", "video/webm"], ["cacheControl", "0"],
    ].map(([k, v]) => `${k} ${Buffer.from(v).toString("base64")}`).join(","),
  },
});
if (overLimit.ok && overLimit.headers.get("location")) {
  await fetch(overLimit.headers.get("location"), { method: "DELETE", headers: { authorization: `Bearer ${signA.data.session.access_token}`, "tus-resumable": "1.0.0" } });
}
check("TUS cannot initialize upload above 500 MiB", "rejected", !overLimit.ok, `HTTP ${overLimit.status}`);

const matrix = results.map(({ test, expected, actual, details }) => ({ test, expected, actual, ...(details ? { details } : {}) }));
console.log(JSON.stringify({ runId, matrix }, null, 2));
