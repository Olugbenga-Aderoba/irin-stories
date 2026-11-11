# Authentication and private source uploads

## Authentication

The application uses Supabase Auth email/password accounts; it does not manage passwords itself. The browser and server use `@supabase/ssr` with cookie-backed sessions. `src/proxy.ts` refreshes the session and redirects unauthenticated requests under `/workspace` and `/story/*` to sign-in. Protected server pages call `auth.getUser()` again before loading owner-scoped rows. Sign-in and sign-out use Supabase Auth.

For local web development, set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` (the local URL is `http://127.0.0.1:54321`). The publishable/anon key is not a secret; access is controlled by authenticated sessions and RLS. Verify A adds server-only environment variables `SUPABASE_SERVICE_ROLE_KEY` for trusted probe persistence and `OPENAI_API_KEY` for language identification. Store them only in the ignored project-root `.env.local` file for local development or in the server host's secret environment configuration. Never use `NEXT_PUBLIC_` names, import these credentials into client code, or expose them in responses/logs. The Auth provider redirect allowlist must include the application's `/auth/callback` URL when email confirmation is enabled.

Authenticated storytellers see `/workspace`, can create multiple stories titled “My Story”, and are sent to `/story/{story_id}/tell`. Story ownership is assigned by `public.create_story()` from `auth.uid()`; callers cannot supply an owner ID. Legacy demo URLs redirect to the authenticated workspace.

## Private source bucket

Migration `20261110090000_private_source_storage.sql` creates the private `private-source` bucket, limited to MP4, MOV, and WebM MIME types and 500 MiB per object. It adds a metadata filename field and two narrow functions:

- `create_story()` derives owner identity from `auth.uid()`.
- `register_source_media(...)` validates owner/story/path binding and uploaded-object ownership, then creates and seals the source artefact, media metadata, workflow transition, and audit event atomically.

The object key is `{owner_id}/{story_id}/{media_id}/{sanitized_filename}`. Storage INSERT, SELECT, and failed-upload cleanup policies bind the owner and story path. Registered media rows are append-only, and there is no delete policy for registered objects. Anonymous and public access have no matching policy. The bucket is never public.

The Tell interface supports one resumable TUS source upload per story with byte progress and retry delays. It validates extension/MIME and the 500 MiB bound before upload; 5–15 minutes is display guidance only. The current database requires a positive duration, so upload is blocked if the browser cannot read video duration. SHA-256 is calculated from the file stream in the browser to avoid reading a 500 MiB file into one memory buffer. Both duration and checksum are client-reported metadata and are not independently probed in this slice. No language detection, transcription, FFmpeg, or downstream story processing is started.

Private playback uses an owner-authorized, one-hour signed URL generated server-side from the private bucket. The signed URL is temporary bearer access and must not be logged or persisted. A future playback proxy can provide shorter, request-by-request authorization if tighter revocation is needed.

## Local validation record — 2026-11-10

The migration was applied to the disposable local database only. PostgreSQL initially rejected its MIME/extension `CASE` predicate with `syntax error at end of input (SQLSTATE 42601)`. The predicate was changed to equivalent boolean logic, then both migrations were replayed locally. Current local history contains `20261109090000` and `20261110090000`; no migration was applied remotely.

The initial SQL harness attempted direct writes to `storage.objects`, which Storage rejects. It is now a read-only RLS/provenance verifier, paired with `supabase/tests/private_source_storage_api_test.mjs` for actual Auth and Storage API operations. A later test query exposed an ambiguous `object_key` reference; the verifier now qualifies that column. The SQL verifier passed all seven checks: A reads two owned stories and object metadata, B and anonymous see no A stories/object metadata, the bucket is private, and the source audit event exists.

The API harness passed all 18 checks with synthetic users and harmless content:

- A authenticated and created two stories; B read zero A stories.
- Storage rejected a `text/plain` upload with HTTP 415. A uploaded and registered WebM source media; A could read it, while B and anonymous received HTTP 404.
- B's upload into A's path was rejected with HTTP 403. B's registration attempt was rejected with SQLSTATE `22023`. Forged insert and owner change were rejected with SQLSTATE `42501`.
- A generated a public object URL, but retrieval returned HTTP 400. The SQL verifier confirmed `private-source.public = false`.
- A signed playback URL returned HTTP 200. Its token lifetime was exactly 3600 seconds. B and anonymous could not create signed URLs (HTTP 404).
- A TUS create request for 524,288,001 bytes was rejected with HTTP 413.

The Tell route was reviewed: it authenticates server-side, loads the story and source-media row through owner-scoped RLS, and signs only the database-loaded object key for 3600 seconds. The URL is bearer access until expiry and is not logged or persisted. Client byte validation and database/bucket limits align at 500 MiB / 524,288,000 bytes; unit tests cover unsupported types and oversize input. The browser flow selected an actual generated synthetic WebM and reached the upload-ready state; it did not upload that browser-generated file. The API harness separately completed an actual local Storage upload and registration.

Playwright ran in installed Microsoft Edge: 2 passed, 0 failed. It verified the anonymous workspace redirect; signup/sign-in and workspace access; two story creations and Tell routes; cross-owner story denial; invalid file-type rejection; and valid synthetic WebM upload-ready state. The direct create-story redirect assertion passed for both stories. Next dev emitted a non-fatal Cache Components diagnostic mentioning `Date.now()` during prerendering, although the Tell route rendered and the browser tests passed; this remains a development warning to review separately.

The first local startup attempts failed and an earlier API attempt timed out before Storage was available. The user later confirmed the required services healthy; no restart was needed for the passing runs. No real storyteller media or real personal data was used. No hosted database, Auth, or Storage operation was performed.
