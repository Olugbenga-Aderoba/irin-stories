# Verify A: source media and original language

## Storyteller-selected fallback

When the latest detection attempt for the current verified source is `no_reliable_language`, the owner may select Yoruba directly. Selection creates a `storyteller_language_decisions` row with origin `storyteller_selected`, state `selected`, and server-derived source, owner, and selection timestamp. The selection operation does not set confirmation fields and never makes the language authoritative. A separate confirmation request transitions the pending row to `confirmed`; only that current-source, owner-confirmed Yoruba decision can satisfy future transcription eligibility. A source replacement makes the row inapplicable because eligibility always joins the latest source ID.

This is distinct from an AI proposal confirmed by the storyteller and from an AI proposal corrected by the storyteller. No OpenAI proposal is created for a failed detection. The failure diagnostic remains in `verify_language_detection_diagnostics`, and the corresponding source-linked failure audit remains intact. Unsupported language values can be retained in the human decision model but do not qualify for MVP transcription.

## Scope and status

Verify A adds server-side inspection of the registered private source video and an append-only, source-version-linked place for a language proposal and the storyteller's confirmation or correction. It does not transcribe, generate a transcript, begin `TRANSCRIBING`, or implement later workflow stages. Yoruba remains the only source language eligible for future transcription; English remains the functional share language.

Migrations `20261111090000_verify_source_language.sql` and `20261112090000_language_provider_provenance.sql` are applied to the disposable LOCAL database only. They have not been applied to the hosted development project. No hosted database, Auth, or Storage operations were performed.

## Media verification

The authenticated route derives the user from the Supabase server session, checks the story owner, and loads the current SOURCE media row through owner-scoped RLS. It does not accept an object key or owner ID from the browser. The route creates a five-minute signed URL for the database-loaded key, downloads to a bounded temporary file, and removes that file in `finally`. The service-role client is isolated in a `server-only` module and is used only to persist the trusted probe result through a narrowly granted RPC; it is not imported into client components.

FFprobe records container and format names, duration, video/audio stream presence, audio/video codecs, dimensions, probe version, and a server-calculated SHA-256. FFmpeg verifies audio decoding and extracts a bounded mono 16 kHz WAV excerpt for a future language detector. Decode success means the stream is usable by the media pipeline; it does not establish that speech is present or intelligible. Mismatches between server-derived and registered client metadata are retained as evidence and shown to the storyteller. They do not silently replace reported values. READY requires a video stream and a decodable audio stream with a codec. A missing or unusable audio stream is REJECTED. The server enforces a 500 MiB read cap; source duration 5–15 minutes remains guidance.

## Language proposal and decision

`LanguageDetectionProvider` isolates provider-specific behavior. `OpenAILanguageDetectionProvider` uses the server-side OpenAI SDK and the [`gpt-transcribe` file transcription endpoint](https://developers.openai.com/api/docs/guides/speech-to-text) in JSON mode. It reads only the returned `languages` field and request ID; generated transcript text is ignored and never returned, persisted, or logged. OpenAI's documented response can contain an empty language list if it cannot reliably detect a language; that is treated as a retryable `no_reliable_language` result, not a default. The API does not expose a defensible language confidence value, so normalized confidence is always null. OpenAI codes are normalized through an ISO 639 catalog into the app's ISO 639-3 format (for example, `yo` becomes `yor`).

Before sending audio, the authenticated storyteller must check the explicit consent control. The server independently validates consent, identity, story ownership, current source artifact, READY verification, and the authoritative server content hash. It retrieves the private video using a short-lived owner-authorized signed URL, checks the downloaded hash against server verification, extracts at most the first 90 seconds to mono 16 kHz WAV, enforces the 25 MiB provider limit, and removes both temporary video and audio files in `finally`/scoped cleanup. No public audio URL is created. A local speech-activity heuristic rejects silence and steady tones before any provider call; it is a conservative precheck, not proof of human speech. If the model cannot reliably identify exactly one language, the operation fails retryably without creating a proposal.

The normalized Zod result contains provider `openai`, model `gpt-transcribe`, proposed ISO language code/name, null confidence, detection timestamp, exact source media artifact ID and verified SHA-256, and nullable provider request ID. Only those normalized fields and safe provider metadata are persisted. The request ID is retained in `source_language_reviews.provider_request_id`. Provider failures write only an allowlisted category to an immutable audit event; raw error bodies and provider transcription text are never stored.

The route returns a retryable `provider_not_configured` failure and creates no proposal when `OPENAI_API_KEY` is missing. The local SQL test uses synthetic proposals to exercise database behavior.

When configured, the intended result is an immutable `PROPOSED` row referencing the exact source artifact and provider/model metadata. The owner can confirm the proposal or correct it. The database derives the confirmer using `auth.uid()` and stores a separate append-only decision row referencing the proposal and same source version. A correction to a language other than Yoruba is recorded honestly but is not eligible for transcription. An unsupported language is not represented as supported.

### Detection failure diagnostics

The server writes a fixed-field sanitized record to `verify_language_detection_diagnostics`, keyed by the browser support reference (`correlation_id`). This table is service-role-only and is separate from the existing coarse audit RPC. Authenticated story owners retrieve it with `GET /api/verify-diagnostics/{correlationId}`; the handler verifies the caller owns the linked story and returns 404 to anonymous or non-owner callers. The record retains attempt timestamp, first failing stage, safe category, retryability, provider/model, provider status, allowlisted error type/code, validated request ID, timeout/network classification, and safe database error code. Browser failure responses continue to expose only the fixed safe category/message, retryability, stage, and support reference. The record never stores credentials, access tokens, transcript text, response bodies, audio, private paths, signed URLs, or raw database errors.

Stages are `ownership_check`, `source_lookup`, `source_download`, `hash_verification`, `audio_extraction`, `speech_validation`, `provider_request`, `provider_response_validation`, `proposal_persistence`, and `cleanup`. Temporary video and WAV cleanup runs on success and failure, before proposal persistence. Cleanup retries transient file removal errors and preserves an earlier processing error if removal also fails.

| Category | HTTP | Retryable |
| --- | --- | --- |
| `provider_not_configured` | 503 | Yes |
| `provider_authentication_failed`, `provider_permission_denied`, `provider_model_unavailable` | 502 | No |
| `provider_payload_too_large` | 422 | No |
| `provider_quota_or_rate_limit`, `provider_temporarily_unavailable`, `provider_network_failure` | 503 | Yes |
| `provider_timeout` | 504 | Yes |
| `no_reliable_language` | 422 | Yes |
| `provider_response_invalid` | 502 | Yes |
| `proposal_persistence_failed` | 500 | Yes |
| `media_processing_failed` | 422 by default. Source-specific guards can return 409, 413, or 502. | Depends on the failure |
| `unknown_detection_failure` | 500 by default. Request and ownership guards retain their 400, 401, 403, or 404 status. | Depends on the failure |

The diagnostic event uses fixed fields. It excludes credentials, access tokens, transcript text, media bytes, private paths, signed URLs, and raw provider or database responses.

## Server-side workflow gate and provenance

The database exposes owner-bound eligibility only when the current source is the latest READY verified version and its latest explicit storyteller decision confirms Yoruba. A separate trigger blocks a story transition to `TRANSCRIBING` unless that exact condition is true. This task does not implement or invoke the transition. Replacing the source changes the current source identity, so prior verification/decision evidence remains historical but no longer grants eligibility. Detection and decision rows are append-only.

## Local test evidence

`supabase/tests/verify_language_test.sql` was executed against LOCAL PostgreSQL at `127.0.0.1:54322`; it emitted 19 passing scenario assertions and rolled back all fixtures. It exercises safe provider failure auditing, request-ID retention without transcript, an actual blocked attempt to set `TRANSCRIBING` (SQLSTATE `P0001`, `Transcribing requires server-verified media and explicit current Yoruba confirmation by the story owner.`), proposal-only ineligibility, owner confirmation, unsupported correction, other-user/anonymous blocking, cross-story blocking, client probe-write blocking, verified-source preconditions, source replacement invalidation, and retained history. `src/lib/verify/media-probe.test.ts` exercises metadata probing, audio decoding, temporary excerpt creation and removal with generated synthetic color/tone WebM only; it is not Yoruba speech. Mocked provider tests cover Yoruba normalization, null confidence, malformed/ambiguous result, missing credential, timeout, and the provider size cap.

The browser test did not pass because local Supabase Auth returned HTTP 504 for `/admin/users`; Auth logs show it timed out while querying duplicate identities. PostgreSQL remained reachable with zero lock waits, and no source-media verification or language-review rows were left by the failed attempts. In the full E2E run, anonymous redirect passed and the two authenticated tests failed before source-media creation. No live OpenAI request was made. The Auth service was not restarted.

## Limitations and risks

- A previous live language detection attempt returned 503. Its coarse audit entry cannot identify the first failing stage. The diagnostic tests use mocked provider and database boundaries.
- Local Supabase Auth returned reproducible 504 timeouts; browser validation of the verification route remains blocked.
- The speech-activity check is heuristic, not proof of speech presence or intelligibility; it can reject quiet/steady speech or admit some non-speech audio. A reliable language result is required before a proposal is saved, but an OpenAI false positive remains possible and must be corrected by the storyteller.
- Only the first bounded excerpt is prepared for a future detector; language variation later in a long recording may be missed.
- FFmpeg/FFprobe binaries are third-party native dependencies; the installed Windows FFmpeg build is old and should be replaced with a maintained, verified build before production deployment.
- Server-side 500 MiB temporary disk capacity, request duration, and deployment runtime limits need validation in the eventual hosting environment.
- Do not apply either Verify A migration remotely without a separate deployment authorization and review.
## Local diagnostic hardening — 2026-11-11

Follow-up migration 20261114090000_harden_verify_language_diagnostics.sql preserves applied history. Both diagnostic migrations are local-only. The fourteen columns are: correlation_id UUID primary key; story_id nullable UUID foreign key; attempted_at non-null timestamptz; stage/category non-null allowlisted text; retryable non-null boolean; provider/model nullable allowlisted text; provider_http_status nullable smallint (100–599); provider_error_type/code nullable exact allowlisted text (maximum 64); provider_request_id nullable req_ plus 32 hexadecimal digits; transport nullable timeout/network; database_code nullable five uppercase alphanumeric SQLSTATE characters. Null story IDs are allowed only at ownership_check. Diagnostics cascade on story deletion, replacing SET NULL to prevent invalid orphans.

Strict Zod validation precedes inserts. Unknown provider types/codes become null; PGRST codes become null because they are not SQLSTATEs. Browser failure fields are unchanged. No generic payload, JSON, message, transcript, audio, path or URL column exists.

The local SQL matrix rejected 92 forbidden insertions: paragraphs, key-like sentinels, bearer text, URLs, Windows/Unix paths, signed URLs, oversized identifiers and JSON across all nine text fields, invalid HTTP statuses/SQLSTATEs, and missing resolved story IDs. Service insertion/read and RLS/grants passed. Tests roll back. The existing Verify SQL harness reported 19 passing assertions and deliberately raised its results exception for rollback.

Four real-database GET handler cases passed: owner 200; cross-owner, anonymous and unknown reference 404. Session identity and database-client adapters are injected; full browser-cookie/HTTP authentication is not claimed. Run diagnostics-local.test.ts with VERIFY_DIAGNOSTICS_DB_TEST=1 and --testTimeout=30000 --hookTimeout=30000. Fixtures are removed.

All six application migrations replayed in an isolated local database over empty auth/storage platform definitions with required primary keys. The rejection matrix passed there; the scratch database was removed. No reset of the existing local database was needed.

Limits: constraints cannot prevent covert encoding into valid UUIDs, hexadecimal request IDs or SQLSTATE-shaped identifiers, or a privileged administrator changing constraints. Database outages can still prevent durable writes. No hosted changes, live OpenAI requests or commits occurred.

## HTTP 200 language-response normalization review

Official contract reviewed against the installed OpenAI Node SDK 7.55.0 (resources/audio/transcriptions.d.ts, Transcription and TranscriptionLanguage) and https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create plus https://developers.openai.com/api/docs/guides/speech-to-text. The JSON response contains text and optional languages: [{ code: string }]. An empty array means no reliably detected language. The adapter already reads result.data.languages and expects this object-array shape; no mismatch was found. Request language hints are distinct from response detected-language objects. No language confidence is documented; proposal confidence remains null.

Future safe server logs distinguish zero_languages, one_language and multiple_languages. A well-formed zero/multiple list still fails as no_reliable_language, creates no proposal and grants no transcription eligibility. Missing/malformed languages fails as provider_response_invalid without inventing a cardinality. Exactly one recognized code is normalized through the existing catalog (yo -> yor / Yoruba); no default or inference from transcript text is used.

The failure event includes only the cardinality label, never candidate languages. A successful normalized response emits verify_language_response_classified with correlation ID and one_language. These labels are LOG-ONLY: the existing database allowlist has no matching column/value and migrations were explicitly excluded from this task. Persisted diagnostic and browser response shapes remain unchanged. The earlier HTTP 200 incident cannot retrospectively be resolved into zero versus multiple languages from its retained diagnostic.
