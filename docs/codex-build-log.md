# Codex Build Log

## Foundation application shell — 2026-11-08

### Task

Implement only the Irin Stories Foundation visual shell and static workflow placeholders. Do not implement authentication, persistence, media processing, or real workflow integrations.

### Summary

Replaced the generic Next.js starter page with a warm, responsive Irin Stories landing page and a static demo workspace for Tell, Verify, Craft, Translate, Protect, and Publish. Added a reusable accessible workflow progress/navigation component. All story details, progress, decisions, privacy findings, Covenant terms, publication statuses, and QR artwork are placeholders; controls are disabled and clearly marked as non-functional.

### Files changed

- `package.json`
- `package-lock.json`
- `vitest.config.mts`
- `src/app/globals.css`
- `src/app/layout.tsx`
- `src/app/page.tsx`
- `src/app/story/demo/[stage]/page.tsx`
- `src/components/brand-mark.tsx`
- `src/components/home-page.tsx`
- `src/components/home-page.test.tsx`
- `src/components/site-header.tsx`
- `src/components/stage-placeholders.tsx`
- `src/components/stage-placeholders.test.tsx`
- `src/components/story-workspace.tsx`
- `src/components/workflow-progress.tsx`
- `src/components/workflow-progress.test.tsx`
- `src/lib/workflow.ts`
- `src/lib/workflow.test.ts`
- `src/test/setup.ts`
- `docs/codex-build-log.md`

### Tests added

- Workflow ordering, stage IDs, route mapping, and static route parameters.
- Workflow progress completed/current/future states, accessible current-step marking, and navigable stage links.
- Landing page brand/message/CTA/principle rendering.
- Static placeholder rendering, disabled controls, source and translation examples, privacy choices, and illustrative publication states.

### Failures encountered and fixes

1. Installing the latest Vitest initially failed with `ERESOLVE`: Vitest 5.1.0 required newer `@types/node` than the scaffold’s existing `^20`. Used Vitest `^4` instead and retained the existing Node type dependency.
2. The first Vitest run could not resolve the `@/` alias. Added the alias to `vitest.config.mts`; the `.mts` config also avoids the native-loader warning for a CommonJS-interpreted `.ts` config.
3. The next test run had one static-render assertion with mismatched capitalization. Corrected the expected text; the suite then passed.

### Final validation results

- `npm run lint` — passed.
- `npm run typecheck` — passed.
- `npm test` — passed: 4 test files, 10 tests.
- `npm run build` — passed; the home page and six demo stage routes were generated.

### Known limitations

- This is a static visual prototype. There is no authentication, database, storage, OpenAI API, transcription, FFmpeg, upload, generated Story Cut, translation workflow, privacy detection, persisted Covenant, publication, or withdrawal integration.
- Demo progress and all example approvals/permissions/publication statuses are illustrative only and are not saved. Buttons are disabled. The QR artwork is not scannable.
- The Yoruba cultural-expression card is an example and requires storyteller review; it is not an approved translation or cultural interpretation.
- Vitest covers unit and server-rendered static behavior. No Playwright end-to-end suite was added for this shell task.
- npm reported 8 moderate audit findings after installing Vitest. No unrelated dependency upgrades or audit fixes were applied.

### Human review decision

Accepted by human review before the Foundation commit.

## Hosted Supabase development project link — 2026-11-09

### Task

Verify the local repository link to the existing hosted `irin-stories-dev` project using read-only project and migration inspection. Do not create or apply migrations or change hosted resources.

### Summary

Confirmed that the local Supabase CLI is authenticated and this repository is linked to `irin-stories-dev` (`hhuqadqruwhctjgtlvcp`, region `eu-west-3`). The project listing reported `linked: true` and `ACTIVE_HEALTHY`. Read-only remote migration inspection returned an empty migration list; there is no local `supabase/migrations` directory. No hosted schema or other resources were modified.

### Tooling and link verification

- Project-local Supabase CLI: `3.0.0`.
- Authentication: existing local Supabase CLI authentication; no credentials were displayed or recorded.
- The ignored `supabase/.temp/project-ref` matches the hosted project reference.
- Machine-local files present under ignored `supabase/.temp`: `cli-latest`, `gotrue-version`, `linked-project.json`, `pooler-url`, `postgres-version`, `project-ref`, `rest-version`, `storage-migration`, and `storage-version`.
- `supabase/.gitignore` excludes `.temp`; the root `.gitignore` excludes `.env` and `.env.*` files.

### Files changed

- `docs/codex-build-log.md` — this verification entry. No application code, Supabase configuration, or migration files changed.

### Commands run

- `npx supabase --version` — `3.0.0` (verified from the project-local CLI setup).
- `npx supabase projects list --output json` — initial PowerShell extraction did not select the nested project result.
- `npx supabase projects list` — confirmed the single matching project, its name, reference, region, healthy status, and `linked: true`.
- `npx supabase migration list --remote` — read-only result: `migrations: []`. The CLI labeled its target environment `production` while identifying the project as `irin-stories-dev`.
- `git status --short --branch` — clean before this build-log update.
- `git check-ignore -v supabase/.temp/project-ref supabase/.temp/cli-latest .env .env.local .env.production` — confirmed local metadata and environment files are ignored.
- `npm run lint`, `npm run typecheck`, `npm test`, `npm run build`.
- `git diff --check` and `git status` (final results recorded after this entry).

### Failures encountered and fixes

The first PowerShell extraction attempt did not select the nested project object in the CLI JSON response. Re-ran the read-only project listing and confirmed the expected project and `linked: true`. No CLI linking, migration-inspection, or repository validation failures occurred.

### Final validation results

- `npm run lint` — passed.
- `npm run typecheck` — passed.
- `npm test` — passed: 5 test files, 13 tests.
- `npm run build` — passed; Next.js generated the landing page and demo workflow routes.
- `git diff --check` — passed after this entry was added (Git reported the existing LF-to-CRLF working-copy notice).
- Remote migration state — empty; no Irin Stories migrations need applying.
- Hosted database schema, tables, policies, storage buckets, and authentication settings — unchanged by this task.

### Known limitations

- This task verified an existing CLI link and inspected migration history only. It did not implement or configure application authentication, database schema, storage, or any product workflow integration.

### Human review decision

Pending.

## Supabase local tooling initialisation — 2026-11-09

### Task

Initialise project-local Supabase CLI tooling and safe, version-controlled local configuration only. Do not create schema, migrations, authentication UI, storage buckets, or hosted-project links.

### Summary

Added the official npm-based Supabase CLI as a project development dependency and initialized the repository with `supabase/config.toml`. The generated `supabase/.gitignore` excludes `.temp` metadata. The project-local CLI reports version `3.0.0`. No login, project link, local stack start, migration, database, or hosted-project command was run.

### Packages changed

- Added `supabase@^3.0.0` to `devDependencies`; `package-lock.json` resolves `supabase@3.0.0`.
- npm added 8 packages and reported 8 moderate audit findings. No audit fixes or unrelated dependency upgrades were applied.

### Files created

- `supabase/config.toml` — generated local Supabase configuration.
- `supabase/.gitignore` — ignores local CLI metadata and local dotenv files.
- `supabase/.temp/cli-latest` — machine-local CLI metadata, ignored by `supabase/.gitignore` and not for source control.

### Commands run

- `node --version` — `v26.13.0`.
- `npm --version` — `11.20.0`.
- `npm install --save-dev supabase` — initial registry access was denied by the sandbox; retry with approved registry access succeeded.
- `npx supabase --version` — `3.0.0`; telemetry was disabled for a non-elevated verification after the sandbox blocked the CLI's machine-local telemetry write.
- `npx supabase init` — succeeded and created local configuration only.
- `npm ls supabase --depth=0` — confirmed project-local `supabase@3.0.0`.
- `git check-ignore -v .env .env.local .env.production supabase/.temp/cli-latest` — environment files and CLI temporary metadata are ignored.
- `npm run lint`, `npm run typecheck`, `npm test`, `npm run build`, `git diff --check`, and `git status`.

### Failures encountered and fixes

1. The initial npm install could not access `registry.npmjs.org` (`EACCES`). Retried the same approved project-local npm installation with registry access; it succeeded.
2. The first CLI invocations could not create or write `C:\Users\USER\.supabase` because the sandbox restricts writes outside the workspace. The local version check and init were run with the required local-tooling permission. A later version check succeeded without escalation after disabling CLI telemetry for that process.
3. No lint, typecheck, test, build, or diff-check failures occurred.

### Final validation results

- `npx supabase --version` — passed, `3.0.0`.
- `npm run lint` — passed.
- `npm run typecheck` — passed.
- `npm test` — passed: 5 test files, 13 tests.
- `npm run build` — passed; landing page and demo workflow routes generated.
- `git diff --check` — passed (Git emitted LF-to-CRLF working-copy notices).
- Supabase schema scan — no migration or SQL files, table DDL, or schema DDL were created.
- No hosted Supabase resources were modified.

### Known limitations

- This task installs local tooling and initializes configuration only. Supabase services were not started, and no schema, migration, bucket, authentication UI, or application integration exists yet.
- A future local stack run needs a Docker-compatible container runtime. Local initialization and migration authoring do not require hosted credentials.
- A future hosted-project link requires a human to authenticate the CLI with `npx supabase login` and supply the intended development project's project reference. No credentials or project reference were requested or stored for this task.

### Human review decision

Pending.

## Foundation UX refinement — 2026-11-08

### Task

Refine the static Foundation demo language and title UX. Keep all detection, language choices, and title suggestions illustrative and non-functional; do not add integrations or persistence.

### Summary

Replaced the demo story title with “My Story” and centralized the demo language metadata in a typed model. The workspace now labels the original language as an unconfirmed Yoruba detection example and shows English in a disabled, English-only “Share my story in” dropdown. Tell demonstrates automatic detection and storyteller confirmation with disabled example actions. Craft shows a clearly labeled future AI working-title suggestion that was not generated and requires storyteller approval. Other language labels now derive from the shared metadata.

### Files changed

- `src/app/globals.css`
- `src/components/home-page.tsx`
- `src/components/home-page.test.tsx`
- `src/components/stage-placeholders.tsx`
- `src/components/stage-placeholders.test.tsx`
- `src/components/story-workspace.tsx`
- `src/components/story-workspace.test.tsx`
- `src/lib/workflow.ts`
- `src/lib/workflow.test.ts`
- `docs/codex-build-log.md`

### Tests changed

- Added assertions for the “My Story” title and absence of the former demo title in rendered views.
- Added checks for original-language wording, demo-only automatic detection, the Yoruba example, storyteller confirmation copy, and disabled conceptual actions.
- Added a workspace rendering test for the English-only selected share language and absence of unsupported language options.
- Added checks that the Craft title is an ungenerated example suggestion requiring storyteller approval.
- The suite passes with 5 test files and 13 tests.

### Failures encountered and fixes

No lint, typecheck, test, or build failures occurred during this refinement. No packages were installed or changed.

### Final validation results

- `npm run lint` — passed.
- `npm run typecheck` — passed.
- `npm test` — passed: 5 test files, 13 tests.
- `npm run build` — passed; the landing page and demo workflow routes were generated.
- `git diff --check` — passed (Git emitted only existing LF-to-CRLF working-copy notices).

### Known limitations

- Automatic language detection is not implemented. Yoruba is shown only as a demonstration/test-language example, and the storyteller confirmation controls are disabled.
- English is the only target language represented as available in the MVP; the selector is disabled and no language selection is saved.
- The Craft working-title idea is static sample text, not an AI-generated proposal. All title choices remain with the storyteller.
- No Supabase, authentication, AI APIs, media processing, or persistence was added.

### Human review decision

Accepted by human review before the Foundation commit.

## First local database migration — 2026-11-09

### Task

Design the minimum robust PostgreSQL foundation for the Irin Stories MVP, create one local Supabase migration and document the data model. The migration must not be applied to the hosted project.

### Summary

Added a versioned relational model for story ownership, private source-media metadata, proposed and confirmed original language, Yoruba transcript segments, explainable timestamped Story Cut segments, cultural review, English subtitle lineage, privacy findings and storyteller decisions, versioned Covenant permissions, exact-hash approvals, immutable publication snapshots, separate publication access state, and append-only audit events. Added dependency-aware current-approval checks, owner-scoped RLS on all public base tables, and a public-safe publication directory view. Language proposals and confirmations are server-written so confirmed changes can invalidate dependent approvals, stale a live publication, and return the workflow to language confirmation in the same transaction.

### Files changed

- `supabase/migrations/20261109090000_irin_stories_mvp_foundation.sql`
- `docs/data-model.md`
- `docs/codex-build-log.md`

### Tests added

- No automated application tests were added. Static SQL structure/security checks and the existing application test suite were run.

### Commands run

- `npx supabase --version` — `3.0.0`.
- `npx supabase db lint --local --schema public --fail-on error` — targeted only the local stack at `127.0.0.1:54322`; it could not connect because the local database runtime is not running.
- Static SQL review — balanced lexical structure; 22 public tables, all 22 included in the RLS setup; all requested workflow states present; no `DROP`, unrestricted `USING (true)`/`WITH CHECK (true)`, credential pattern, or authenticated insert path for language reviews; only the public-safe directory is granted to `anon`.
- `npm run lint` — passed.
- `npm run typecheck` — passed.
- `npm test` — passed: 5 files, 13 tests.
- `npm run build` — passed.
- `git diff --check` — passed.
- `git status` — captured after validation.

### Failures encountered and fixes

1. The first Supabase CLI lint invocation was blocked while the CLI attempted to write telemetry under the user profile. Reran with CLI telemetry disabled for that command; the CLI then confirmed it was targeting only the local stack and reported connection refused because PostgreSQL was not running.
2. No PostgreSQL parser/runtime (`psql`, Docker, `pg_format`, or `sqlfluff`) is available in this environment, so server-side SQL parsing could not be completed. The migration received static lexical, relationship, RLS, privilege, lineage, and destructive-statement review instead. No hosted or local database was changed.
3. Review tightened dependency-aware approval checks, made language confirmation server-only, and made newly sealed artefact versions reset workflow state to the affected review stage.

### Final validation results

- `npm run lint` — passed.
- `npm run typecheck` — passed.
- `npm test` — passed: 5 files, 13 tests.
- `npm run build` — passed.
- Static SQL/security review — passed; PostgreSQL execution-level validation remains unavailable until a local database runtime is provided.
- Hosted Supabase project — migration was not applied; no hosted database resources were modified.

### Known limitations

- The migration has not been applied or parsed by a running PostgreSQL server. It should receive a local Supabase database lint and migration rehearsal before any separately authorized remote push.
- Storage buckets and object policies, workflow APIs, Auth UI, language detection, transcription, translation generation, media processing, and publication serving are not implemented.
- Application-side canonical content hashing and transactional workflow orchestration remain required; the database checks supplied hashes and exact version bindings but does not calculate SHA-256 for artefact content.

### Human review decision

Pending.

## Critical database architecture review - 2026-11-09

### Task

Review and refine the local Irin Stories foundation migration for multi-story ownership, table complexity, duration/language flexibility, PostgreSQL immutability, approval integrity, Supabase RLS, public-read security, and future Storage readiness. Do not apply the migration.

### Changes

- Revised the foundation migration from 22 to 20 tables. Removed the timestamp-derivable cut/transcript junction and merged rendered-media lineage into `media_assets` while retaining exact source, transcript, cut, translation, and snapshot references.
- Confirmed one Auth user can own many stories; no unique owner constraint or one-story RLS assumption remains.
- Replaced hard 5-15-minute and 90-150-second database rules with positive duration, increasing timestamp, and source/cut timeline bounds. Kept Yoruba-to-English scope in workflow guards while language columns remain extensible.
- Replaced the owner-privileged public directory view with a narrow `SECURITY DEFINER` publication RPC using an empty fixed `search_path`, explicit current-publication and Covenant checks, full snapshot validation, and allowlisted public fields.
- Tightened privacy edit decisions to reference a later approved version with matching source/transcript lineage. Added per-story row locking for version allocation and ordered privacy reviews by their numeric artifact version.
- Added `docs/database-review.md` with the risk/decision log, table justification, RLS access and mutability matrices, deferred work, and execution-validation requirements. Rewrote `docs/data-model.md` to match the revised schema and storage/public-read model.

### Files changed

- `supabase/migrations/20261109090000_irin_stories_mvp_foundation.sql`
- `docs/data-model.md`
- `docs/database-review.md`
- `docs/codex-build-log.md`

No application code changed.

### Validation

- Static SQL review: 20 tables; all 20 RLS-enabled/covered (19 owner-scoped child tables plus explicit `stories` policy); all security-definer functions have `SET search_path = ''`; no `DROP`; no unrestricted private policy; no anonymous base-table grant; only the public lookup RPC is executable by `anon`; no one-story owner uniqueness; no hard hackathon duration ranges; required workflow states present; UUID IDs and 32-byte SHA-256 checks retained; delimiter scan balanced; no obvious credential material found.
- `npm run lint`  -  passed.
- `npm run typecheck`  -  passed.
- `npm test`  -  passed: 5 files, 13 tests.
- `npm run build`  -  passed.
- `git diff --check`  -  passed.

### Failures encountered and fixes

The review identified the one-story-per-user restriction, permanent duration ranges, unsafe view-owner semantics, redundant tables, and an unbound privacy edit decision. These were corrected in the local migration and reflected in the documentation. No application validation failed.

### Remaining validation and limitations

No PostgreSQL parser/runtime (`psql`, Docker, `pg_format`, or `sqlfluff`) is available. Static delimiter and schema-policy checks are not a substitute for executing PostgreSQL DDL. A Docker-compatible local Supabase runtime is required for the next execution-validation stage; that stage must remain local and separately authorized. The migration was **not applied locally or to the hosted Supabase project**.

`docs/implementation-plan.md` still contains the Foundation wording "A second story is rejected" and "Enforce one MVP story per storyteller." The architecture now supports multiple stories; the suggested minimal plan edit is to describe one seeded demo story while allowing multiple owned stories. The plan file was not modified in this review.


## Implementation plan ownership wording correction - 2026-11-09

Clarified in `docs/implementation-plan.md` that one storyteller and one story describe the hackathon demonstration only. An authenticated account may own multiple stories; each has independent Tell-to-Publish workflow and per-story ownership/RLS, and the database must not block a second story. Updated the Foundation outcome/acceptance criteria and proposed `stories` model accordingly. No application code, SQL migration, package files, or Supabase resources changed.

## Local Supabase migration validation - 2026-11-10

### Task

Resume local-only PostgreSQL execution validation for the existing foundation migration. Do not modify the hosted `irin-stories-dev` project.

### Result

`npx supabase db reset --local` completed successfully against `127.0.0.1:54322` and applied `20261109090000_irin_stories_mvp_foundation.sql`. No SQL correction was made. Catalog inspection found 20 public tables, 10 enums, 73 foreign keys, 68 checks, 53 indexes, 41 functions, and 25 policies; all 20 public tables enabled RLS. A rollback-only RLS check passed multiple-story creation, owner isolation, forged-owner rejection, and anonymous denial across 12 private tables. Unresolved privacy approval and final-media gates rejected the synthetic case as expected.

Docker Desktop then returned HTTP 500 from its `desktop-linux` engine during a synthetic publication validation, and its status changed to `stopping`. The transaction returned no completion result. The public RPC/withdrawal/provenance fixture, cross-story test results, second clean reset, and local full-service startup could not be confirmed. An attempted Docker Desktop restart did not recover the engine; its Windows service remained stopped and could not be opened by the current session.

### Validation

- `npm run lint` - passed.
- `npm run typecheck` - passed.
- `npm test` - passed: 5 files, 13 tests.
- `npm run build` - passed.
- `git diff --check` - passed before documentation updates; rerun after this entry.

### Configuration and limitations

`supabase/config.toml` remains at `health_timeout = "10m"` as requested for the first successful local validation. The local reset reported that the configured `supabase/seed.sql` path has no matching file; this did not block migration application. No credentials, tokens, passwords, or connection strings with credentials are recorded. No change was applied to the hosted project.

## Local database test continuation — 2026-11-10

### Task and result

Continue only the outstanding LOCAL PostgreSQL tests. A clean reset/replay was confirmed by direct query to `127.0.0.1:54322`: 20 public tables, all 20 RLS-enabled. The reset CLI output terminated after schema initialization without a final success line; Docker API health inspection was inaccessible. The local database remained reachable through `supabase db query`.

The targeted lineage, approval, valid-publication, anonymous RPC, and withdrawal/retention runtime fixtures were not completed and remain unverified. The migration declaration lists the public RPC fields, but that was not represented as successful invocation evidence. `health_timeout = "10m"` was retained because it helped the initial successful local startup and did not cause the Docker API inspection issue.

### Files updated

- `docs/local-database-test-report.md`
- `docs/database-review.md`
- `docs/data-model.md`
- `docs/codex-build-log.md`

### Application validation

- `npm run lint` — passed.
- `npm run typecheck` — passed.
- `npm test` — passed, 5 files / 13 tests.
- `npm run build` — passed.
- `git diff --check` — passed before final documentation edits; rerun after edits.

No CLI upgrade, hosted operation, commit, or schema edit was performed. Human review decision: pending. Remaining limitations: local runtime cases listed above are not proven.

## Outstanding local DB fixture attempt — 2026-11-10

Read `AGENTS.md`, the local database test report, data model, and foundation migration. The local database was reachable and empty after the prior clean replay. This follow-up did not complete the transaction fixture needed to validate cross-story constraint rejection, exact-target and cross-owner approval rejection, valid publication/RPC fields, and post-withdrawal provenance retention. These cases remain unverified; no triggers were disabled and no publication was synthesized outside the guarded workflow. No local database-changing SQL or hosted operation was run.

Documentation updated: `docs/local-database-test-report.md`, `docs/database-review.md`, `docs/data-model.md`, and this log. Human review decision pending.

## Foundation database integration harness — 2026-11-10

### Task

Create a repeatable synthetic local integration harness and execute the remaining lineage, approval, publication/RPC, withdrawal, and provenance scenarios. Do not change the foundation migration unless a runtime test proves a defect.

### Files changed

- `supabase/tests/irin_stories_foundation_test.sql`
- `docs/local-database-test-report.md`
- `docs/database-review.md`
- `docs/data-model.md`
- `docs/codex-build-log.md`

### Results

The harness ran twice on LOCAL `127.0.0.1:54322`; all 16 scenario checks passed; the additional predicate diagnostic also matched expected published state. It exercises two cross-story lineage rejections; multiple-target, cross-owner, malformed-hash, and cross-story approval rejections; a fully guarded publication path; anonymous RPC invocation and exact field allowlisting; owner withdrawal; and retained snapshot, seven approvals, Covenant, ten Covenant permission rows, seven typed provenance rows, and 17 audit events. Both executions use deterministic synthetic IDs and roll back through an intentional final sentinel exception. A follow-up query confirmed no synthetic users/stories persisted.

The CLI returns exit status 1 for the sentinel rollback, while its error payload contains the full matrix with `passed: true` for each check. No production migration SQL was modified; no schema defect was found. No hosted Supabase operation was run. Human review decision: pending.

Application validation after the final harness/docs edits: `npm run lint`, `npm run typecheck`, `npm test` (5 files / 13 tests), `npm run build`, and `git diff --check` all passed.

## Apply validated foundation to hosted development database — 2026-11-10

### Task and source

Apply only the committed and locally validated foundation migration to the linked development project. Source commit: `c90ce12d9c6d11aebff096dd81b2fbf32b7189c3` (`feat: add validated Irin Stories database foundation`). Project verified by authenticated Supabase CLI listing: `irin-stories-dev`, reference `hhuqadqruwhctjgtlvcp`. The working tree was clean before starting.

### Migration result

Remote migration history was inspected first and showed `20261109090000` pending. The standard explicit remote command applied only `20261109090000_irin_stories_mvp_foundation.sql`, with Vault updates skipped. The command completed successfully and reported that one migration was applied with no seeds or roles. A subsequent read-only migration-history query showed local and remote version `20261109090000` exactly once.

### Remote read-only verification

- Public tables: 20.
- Tables with RLS enabled: 20/20.
- Public policies: 25; owner-scoped `SELECT` policies and the expected owner insert/update, approval, privacy-decision, and publication-withdrawal policies were listed.
- Functions in `public` and `irin_private`: 41.
- `public.get_published_story(uuid)`: present and executable by `anon`.
- Anonymous direct privileges over public base tables: 0.
- Rows across all 20 Irin Stories tables: 0. No synthetic, sample, or storyteller records were created.

No seed data, remote test harness, Auth setting, Storage bucket, or application code was changed.

### Local application validation

- `npm run lint` — passed.
- `npm run typecheck` — passed.
- `npm test` — passed: 5 files, 13 tests.
- `npm run build` — passed.
- `git diff --check` — passed after this log update.

### Warnings and limitations

The CLI labels the linked target environment as `production` in command output, while the authenticated project listing confirmed the exact project name `irin-stories-dev` and reference above; the requested reference was used explicitly. An initial `db push` without `--remote` correctly selected LOCAL, reported no migrations, and made no hosted change. The successful push explicitly used `--remote=hhuqadqruwhctjgtlvcp --skip-vault`. The CLI noted that a newer version is available; no upgrade was performed. No credentials, access tokens, passwords, service-role keys, JWT secrets, or private connection strings are recorded here.

No commit was created for this build-log update.

## Authentication and private source-media foundation — 2026-11-10

### Task

Implement Supabase Auth session handling, protected storyteller workspace, multiple-story creation, and private Tell-stage source upload only. Do not implement language detection, transcription, or downstream workflow stages. Keep `irin-stories-dev` untouched.

### Changes

- Added `@supabase/ssr` and `@supabase/supabase-js` clients, cookie-backed SSR session refresh in `src/proxy.ts`, Auth callback/sign-in/sign-out, protected workspace, and `auth.uid()`-owned `create_story()` RPC.
- Replaced the public demo CTA and Tell route with owner-scoped stories and Tell upload UI. Language detection is explicitly pending; English remains the only share choice.
- Added resumable TUS upload with byte progress/retries; MP4/MOV/WebM validation; 500 MiB max; duration guidance only; streaming SHA-256; private playback by one-hour signed URL; atomic source metadata/artifact registration and audit event.
- Added migration `20261110090000_private_source_storage.sql`, rollback-only Storage policy integration harness, Vitest unit tests, and local-only Playwright tests.
- Updated local `supabase/config.toml` to 500 MiB Storage maximum, eight-character password minimum, and local Auth callback redirects.

### Database execution and hosted safety

Attempted only `supabase migration up --local`. CLI confirmed `Target: local stack (127.0.0.1:54322)` then failed with `DbConnectError: failed to connect to postgres: ... Connection terminated unexpectedly`. The new migration and SQL Storage test therefore remain unexecuted. No workaround or schema mutation was attempted. No remote migration, remote SQL, hosted Auth or Storage setting, or hosted project operation was performed. The foundation migration was not changed. No service-role key or other secret was added.

### Validation

- `npm run lint` — passed.
- `npm run typecheck` — passed after correcting Supabase `getClaims()` result access.
- `npm test` — passed, 6 files / 16 tests.
- `npm run build` — passed after removing incompatible `force-dynamic` route config and using Cache Components' request-time route behavior.
- `git diff --check` — passed after documentation edits.
- `npm run test:e2e -- --list` — passed; Playwright discovered two local-only cases. The browser flows were not executed.
- Playwright browser suite — added, not run because the local Supabase Auth/Storage endpoint is unavailable.

Known limitations: uploaded duration and SHA-256 are client-reported, not independently probed; files whose duration cannot be read are blocked because the existing schema requires a positive duration; one-hour signed source playback URLs are bearer URLs until expiry; local policies/RPC and hosted settings have not been executed/verified. `npm install` reported seven moderate audit findings; no dependency audit/fix was requested or run. Human review decision pending. No commit was created.

## Local Auth + private Tell validation — 2026-11-10

### Task and scope

Validate the existing Auth/private-source implementation using only synthetic local accounts and media. No language detection, transcription, hosted migration, Auth, Storage, or database operation was performed against `irin-stories-dev`.

### Local migration

Confirmed the foundation migration and the private-source migration were present locally. The first local application of `20261110090000_private_source_storage.sql` failed with PostgreSQL `syntax error at end of input (SQLSTATE 42601)` in `register_source_media()`'s MIME/extension `CASE` predicate. Replaced that expression with an equivalent explicit boolean predicate. With the user-visible confirmation `TARGET = LOCAL; DATABASE = 127.0.0.1:54322`, ran one local reset/replay; both foundation and private-source migrations reapplied successfully. No hosted target was used.

### Runtime tests and diagnosis

- The original SQL harness attempted direct `INSERT`/`DELETE` on `storage.objects`; PostgreSQL rejected it with `Direct deletion from storage tables is not allowed. Use the Storage API instead.` Reworked it as a read-only RLS/provenance verifier and added `supabase/tests/private_source_storage_api_test.mjs` for actual Auth and Storage API calls.
- The API runner reached local Auth, and synthetic `example.invalid` accounts appeared in local `auth.users`, but signup requests timed out. `create_story()` then returned an upstream timeout. The runner stopped before object upload; no Storage/RLS scenario is marked passed.
- Local PostgreSQL remained healthy on direct container read-only checks. Local Kong/PostgREST requests timed out. A local API gateway restart and local start attempts did not restore Storage; CLI repeatedly reported `storage-api` unhealthy because `127.0.0.1:5000` refused connections, and removed partial containers while preserving volumes. No SQL test ran after this failure.
- Code review: the Tell route verifies the session server-side, loads the story and media row under owner RLS, and signs only the object key loaded from that database row. The signed URL lifetime is 3600 seconds. Runtime owner/anonymous/expiry/public-object denial was not proven.
- Static limit comparison: client max, `supabase/config.toml`, bucket limit, and registration guard all resolve to 500 MiB / 524,288,000 bytes. TUS uses 6 MiB chunks and the bucket cap remains in force; an oversized TUS request was not executed.
- Playwright ran in installed Microsoft Edge: anonymous `/workspace` redirect passed; sign-up/story/Tell failed with `Failed to fetch` because local API services were unavailable. The flow did not reach story creation or video selection. The first Chromium attempt could not launch because the managed browser binary was absent.

### Application checks

- `npm run lint` — passed.
- `npm run typecheck` — passed.
- `npm test` — passed, 6 files / 16 tests.
- `npm run build` — passed.
- `npm run e2e` — 1 passed, 1 failed in Edge; no Auth/Tell creation or upload-ready pass.
- `git diff --check` — passed after documentation edits (Git emitted only expected LF/CRLF working-copy warnings).

### Files changed and remaining risks

Changed the private-source migration syntax, SQL/API integration harness, Playwright config and Auth/Tell test, npm e2e script, and `docs/auth-private-storage.md` plus this log. The API harness has not passed end-to-end. RLS/Storage authorization, signed-URL expiry, public URL denial, 500 MiB TUS rejection, and valid-file browser selection remain runtime-unverified. The public bucket flag and server-side signing flow were reviewed in code only. No commit was created; human review pending.

## Resumed local Auth + private Tell validation — 2026-11-10

### Local target and migrations

Read `AGENTS.md` and `docs/auth-private-storage.md` first. User-confirmed local services remained healthy, so they were not restarted. A read-only local history query confirmed foundation `20261109090000` and private-source `20261110090000` are both recorded. Every synthetic Auth, story, Storage, and API test used only `127.0.0.1:54321` and `127.0.0.1:54322`.

### Executed integration results

- The API/Auth/Storage harness passed 18/18: A authenticated and created two stories; B read zero A stories; invalid `text/plain` Storage upload was rejected (415); A uploaded/registered media and could read it; B and anonymous could not read it (404); B could not upload to A's path (403) or register under A's story (SQLSTATE `22023`); forged insert and owner change were blocked (SQLSTATE `42501`); a formatted public URL returned HTTP 400; A's temporary signed URL returned HTTP 200 with a 3600-second JWT lifetime; B/anonymous could not sign A's object (404); TUS above 500 MiB was rejected (413).
- The SQL verifier passed 7/7: two A stories and A object metadata visible to A; A story/object metadata invisible to B; object metadata invisible to anon; `private-source` has `public=false`; source audit provenance exists.
- Playwright in installed Microsoft Edge passed 2/2: anonymous redirect and full synthetic Auth/Tell flow, including A/B signup/sign-in, workspace, two stories, Tell routes, cross-owner story isolation, invalid file type rejection, and generated WebM reaching upload-ready state. The browser-generated WebM was not uploaded; actual Storage upload/registration was exercised by the API harness.

### Corrections during validation

Kept the earlier proven migration syntax fix. Replaced unsupported direct `storage.objects` DML with Storage API writes, qualified the SQL verifier's ambiguous `object_key` column, removed an authenticated-client `getBucket()` check that requires admin rights, and tested privacy by public retrieval plus SQL `public=false`. The API harness now checks the signed token's exact 3600-second lifetime, MIME rejection, and TUS 413. Playwright uses Edge via `PLAYWRIGHT_CHANNEL`, waits for route transitions, scopes the uploader alert selector, and base64-transfers the generated WebM between browser and Node.

Next dev emitted a non-fatal Cache Components diagnostic mentioning `Date.now()` during route prerendering; the Tell route rendered and both Playwright tests passed. This diagnostic is recorded as a remaining development warning. No hosted operation, commit, language detection, or transcription was performed.

### Application validation

- `npm run lint` — passed.
- `npm run typecheck` — passed.
- `npm test` — passed, 6 files / 16 tests.
- `npm run e2e` — passed, 2 tests / 0 failures in Microsoft Edge against LOCAL Supabase.
- `npm run build` — passed.
- `git diff --check` — passed after this log update; Git emitted only LF/CRLF working-copy warnings.

## Auth/Tell Playwright startup diagnosis — 2026-11-10

### Diagnosis and startup change

- The previously reported Next `ECONNRESET` / `Error: aborted` was absent during the initial targeted repeats (1/1, then 3/3). During this later commit-validation E2E run, Next logged `Error: aborted` with `code: ECONNRESET` while the Auth/Tell test was running; the browser test still passed. The reset is reproducible as a server log event, but its triggering request remains unidentified and it has not reproduced as a failed assertion.
- During a production `next start` experiment, Auth `/signup` and `/token` returned HTTP 504 after about 10 seconds (`context deadline exceeded`). Similar intermittent Auth timeouts also occurred during a later dev-server run, so the evidence does not attribute them to production mode. PostgreSQL logged cancellation of the corresponding client request, with no lock wait in the read-only activity check. The Auth health probe still returned 200. Restarted only the LOCAL Auth container; subsequent attempts included both successful requests and an intermittent timeout, so the restart does not establish a root cause. No database, migration, Storage, or hosted service was changed.
- Playwright now starts a fresh Next dev server on the configured local origin `127.0.0.1:3000`, with `reuseExistingServer: false` and a 120-second startup timeout. Port 3000 matches the local Auth `site_url` and allow-list. The server logs confirmed startup, and Playwright shut it down after each run. This removes the previous possibility of silently reusing a stale Next process. Production-server startup was reverted after its Auth timeouts; the evidence does not show that production mode caused them.
- The Auth/Tell assertions were not weakened. No application, Auth/Storage client, test assertion, or migration code changed.

### Executed results

- Targeted Auth/Tell test: 3/3 sequential passes with the final local-origin configuration.
- Full E2E suite: 2/2 passes, then 2/2 passes, then 2/2 passes during the full validation sequence; all runs used synthetic users and LOCAL Supabase.
- `npm run lint` — passed.
- `npm run typecheck` — passed.
- `npm test` — passed, 6 files / 16 tests.
- `npm run build` — passed.
- `git diff --check` — passed after this entry was added.

Next dev continues to emit a non-fatal Cache Components diagnostic for `Date.now()` in the Tell route during prerendering. It did not fail the final test. The local Auth endpoint separately showed intermittent HTTP 504 request timeouts during investigation, then succeeded for the final repeated tests. Source duration and checksum are still client-reported and require later server/media verification. No hosted project operation or commit occurred.

## Hosted private-source Tell infrastructure deployment — 2026-11-10

### Preflight and migration

- Started from clean Git HEAD `647ee007bf40cacf534a7449be131269be280102` (`feat: add authenticated private Tell workflow`). Supabase CLI authentication was confirmed by the project listing; both linked metadata and CLI identified `irin-stories-dev`, ref `hhuqadqruwhctjgtlvcp`.
- Before deployment, remote history showed foundation `20261109090000` applied once and private-source `20261110090000` pending. The standard linked migration workflow applied only `20261110090000_private_source_storage.sql` from the committed Auth/Tell milestone. A CLI consent guard initially returned `HostedMutationConsentRequiredError` and reported that nothing changed; the explicitly authorized retry with `--yes` succeeded. No reset, fixture, seed, Auth setting, or unrelated Storage configuration change was run.
- Post-deployment history reports each migration exactly once. No synthetic users, stories, source media, or other test records were created remotely.

### Read-only remote verification

- The `private-source` bucket exists with `public = false`, `file_size_limit = 524288000` bytes (500 MiB), and MIME types `video/mp4`, `video/quicktime`, and `video/webm`.
- Storage policies present: `anonymous cannot access source bucket` (restrictive deny for this bucket); `storytellers upload source media to their stories`; `storytellers read their private source media`; and `storytellers remove only unregistered source uploads`. The authenticated upload/read/delete predicates bind `owner_id` and the first object-key folder to `auth.uid()` and verify the folder's story belongs to that user. No unrestricted anonymous object policy was found.
- `public.register_source_media(uuid,uuid,text,text,text,bigint,bigint,bytea)` exists as `SECURITY DEFINER`; execute is granted to `authenticated` and not `anon`.
- The public database foundation remains 20 tables with RLS enabled on all 20. Verification used a read-only transaction; it created no rows.

### Application configuration and validation

- Eventual Next.js environment variable names: `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`. No values are recorded here.
- Configure the hosted Auth Site URL to the deployed application origin. Add the exact callback `https://<deployed-app-host>/auth/callback` to the Auth redirect allow-list (and any explicitly supported preview origin callbacks). The application constructs the callback from `window.location.origin`. No hosted Auth settings were changed in this task.
- `npm run lint` — passed; `npm run typecheck` — passed; `npm test` — passed, 6 files / 16 tests; `npm run build` — passed; `git diff --check` — recorded after this entry.
- `npm run e2e` used LOCAL Supabase only and returned 1 passed / 1 failed. The anonymous redirect passed; Auth/Tell timed out while remaining on `/sign-in`. LOCAL Auth logs show `/signup` HTTP 504 after 18,244 ms and `/token` HTTP 504 after 10,067 ms (`request_timeout`); Auth and Storage health probes returned HTTP 200 and local PostgreSQL was reachable. The hosted database was not used as fallback.

### Remaining risks and limits

The local Auth timeout prevents this deployment run's E2E suite from passing; the migration itself and remote read-only checks succeeded. Hosted Auth redirect configuration and application runtime variables remain to be configured separately. The bucket cap is 500 MiB, but the hosted project's global Storage upload limit must also permit that size before 500 MiB uploads can work. Source duration and checksum are still client-reported and require later server/media verification. The Next dev Cache Components `Date.now()` diagnostic remains known from local development. No Verify workflow was started, no secret was recorded, and no commit was created for this deployment report.

## OpenAI language identification for Verify A — 2026-11-10

### Provider and audio flow

- Implemented `OpenAILanguageDetectionProvider` behind the existing replaceable `LanguageDetectionProvider` interface. It uses the official OpenAI Node SDK with `gpt-transcribe` and JSON response format; it consumes only the detected language code list and safe request ID, discards the response transcript, and never writes or displays transcript text. OpenAI does not return a usable language confidence in this response, so normalized `confidence` is `null`. OpenAI `yo` is normalized to ISO 639-3 `yor` with an ISO language catalog.
- The normalized strict Zod proposal includes provider/model, language code/name, null confidence, detection time, source artifact ID, verified source SHA-256, and nullable request ID. Only this proposal metadata is persisted. Provider failures record an allowlisted category, not raw response/error content.
- With explicit storyteller consent, the server revalidates session, owner, current source artifact, READY verification, and server source hash; it extracts a maximum 90-second mono 16 kHz WAV excerpt from the private video, enforces OpenAI's 25 MiB limit, and deletes temporary audio/video on completion or failure. A speech-activity heuristic rejects silence/steady tones before provider calls; this is not a definitive speech detector. Empty or ambiguous detected-language output is retryable and creates no proposal.
- Local credential location: ignored project-root `.env.local`, as `OPENAI_API_KEY=...`; also keep the server-only `SUPABASE_SERVICE_ROLE_KEY` there for trusted database RPCs. Do not paste either value into chat or commit the file. The key-presence check found no `OPENAI_API_KEY` in process environment or `.env.local`; no live OpenAI request was made.

### Migrations and executed tests

- New migration `20261112090000_language_provider_provenance.sql` adds a nullable safe provider request ID and a failure-audit event/function. It replaces the service-role-only proposal RPC signature to persist the request ID. The existing Verify A migration was preserved. Both Verify migrations are applied to LOCAL PostgreSQL at `127.0.0.1:54322`; neither was applied remotely.
- The first local apply of migration 120 exposed a SQL quote defect at `owner's` (SQLSTATE `42601`). The migration transaction rolled back completely; a read-only catalog check confirmed no partial column, enum, or function change. Escaping the apostrophe fixed it; the local reapply succeeded.
- The rollback-only SQL harness emitted 19 passing assertions: provider failure category audit, request ID persistence without transcript, actual blocked `TRANSCRIBING` update (SQLSTATE `P0001`: `Transcribing requires server-verified media and explicit current Yoruba confirmation by the story owner.`), proposal-only ineligibility, ownership/anonymous/cross-story blocks, owner confirmation, unsupported correction, source replacement invalidation, and retained provenance. Synthetic fixtures rolled back.
- Mocked provider tests passed: Yoruba normalization; confidence remains null; malformed, empty, and ambiguous outputs reject; absent key returns retryable `provider_not_configured`; provider timeout is retryable; and empty/oversized samples are rejected before the provider boundary. Media tests reject a steady synthetic tone and confirm the temporary sample is removed on provider failure. No synthetic speech is represented as Yoruba.
- `npm run lint` — passed; `npm run typecheck` — passed; `npm test` — passed, 8 files / 24 tests; `npm run build` — passed.
- `npm run e2e` against LOCAL Supabase — 1 passed / 2 failed. Anonymous workspace redirect passed. Existing Auth/Tell failed to reach workspace, and Verify's synthetic account creation returned HTTP 504. Auth logs show local duplicate-identity lookup timeouts; failures occurred before story/media creation. The local Auth service was not restarted. No live OpenAI request occurred.
- `git diff --check` — passed after the final documentation edits.

### Remaining risks

The credential is absent and the user has not asked for a live OpenAI call, so real language accuracy, provider request ID behavior, and human confirmation in browser remain unverified. Local Auth 504s block authenticated E2E coverage. The VAD-like check is heuristic and needs real speech evaluation; the selected native FFmpeg build is old and requires replacement before production. OpenAI may internally produce transcript content, which this implementation discards; the sample is still sent externally only after explicit storyteller consent. No hosted database/Auth/Storage change or commit was made.

## Verify A: server media verification and language decision — 2026-11-10

### Scope and implementation

- Added migration `20261111090000_verify_source_language.sql` and `supabase/tests/verify_language_test.sql`. The migration was applied only to the disposable local database at `127.0.0.1:54322`; hosted project `irin-stories-dev` was not modified.
- Added an authenticated Verify stage, owner-authorized server-side private media retrieval, FFprobe metadata and server SHA-256, bounded FFmpeg audio decode/sample extraction, stored metadata discrepancies, append-only source-version verification and language decision records, owner-bound confirmation, and a database `TRANSCRIBING` guard. No transcription was implemented or invoked.
- The strict Zod language-result contract and provider interface are in place. Provider selection/credentials were not supplied (user said they would name another provider); therefore the UI and API explicitly report language detection unavailable, send no audio, and do not fabricate a language or confidence. The trusted local SQL fixture proposal is only a database behavior test, not a real detector result.
- Removed the incompatible `ffmpeg-static` package. Externalized the native FFmpeg/FFprobe packages from Next bundling and removed explicit `runtime` route settings incompatible with this repository's Cache Components configuration; Route Handlers use the Node default. The media test's bounded timeout is 20 seconds because native probing exceeded Vitest's 5-second default during concurrent checks.

### Actual local test results

- Local SQL/RLS integration harness: 16 assertions passed; the transaction rolled back its synthetic fixture data. It verified proposal-only ineligibility, valid owner confirmation, unsupported correction recorded but not eligible, other-user and anonymous blocks, cross-story blocks, client-write block, verified-current-source preconditions, source-replacement invalidation, and historical row retention.
- Media probe unit test: generated harmless synthetic color/tone WebM (not speech) was probed, decoded, and reduced to a bounded audio sample.
- Unit suite: `npm test` passed, 8 files / 22 tests.
- `npm run lint` passed; `npm run typecheck` passed.
- `npm run build` initially failed because explicit `runtime = "nodejs"` is incompatible with `cacheComponents` and Turbopack could not bundle the FFmpeg installer. After removing those route settings and externalizing the native packages, the production build passed.
- Full `npm run e2e` against LOCAL Supabase: 1 passed / 2 failed. Anonymous workspace redirect passed. Auth/Tell failed at local sign-in after signup recovery; Verify failed when the local Auth admin API returned HTTP 504 creating a synthetic account. Local Auth logs show database identity lookups timing out (`context deadline exceeded`); PostgreSQL was reachable with zero lock waits. Both failed attempts occurred before story/media creation. A read-only check found zero `source_media_verifications` and `source_language_reviews` rows. No service restart was performed.
- `git diff --check` passed after the final documentation edits (only Git's normal LF/CRLF working-copy notices were emitted).

### Limitations and risks

Real language detection, actual proposal UI review, confirmation/correction through browser, and end-to-end media verification remain unvalidated because provider choice is pending and local Auth returned 504. The current local probe test uses a tone, not Yoruba speech; audio decoding does not establish speech presence or intelligibility. Only an initial audio excerpt is prepared for future detection. The selected Windows FFmpeg installer binary is an old build and must be replaced with a maintained, verified native build before production use. Deployment disk/runtime limits for a 500 MiB temporary download remain unverified. No hosted changes or commit were made.

## Tell prerender clock and upload status

- The development log identified a synchronous clock read on the story stage route. The authenticated render path reaches Supabase Auth's `__loadSession()` expiry check, which compares `expires_at` with `Date.now()`. The route now awaits Next.js `connection()` before creating the client, following the installed Cache Components migration guide. The expiry calculation and clock source are unchanged.
- Tell uses the registered source state to show that the private video is ready and point the storyteller to Verify. The empty state keeps its existing wording.
- Lint, typecheck, the production build, and all 24 unit tests passed. The first test run encountered a full system drive. Clearing the generated production cache allowed the rerun to pass. An authenticated browser replay was not run.

## Home prerender clock

- Home's `AuthAwareHome` now awaits `connection()` before loading the Supabase session. The existing `Suspense` fallback remains the prerendered shell. Supabase Auth's `__loadSession()` still uses `Date.now()` to check session expiry at request time.
- Lint, typecheck, all 24 unit tests, and the production build passed. The media probe test timed out during the concurrent checks and passed on an isolated rerun.
- Anonymous requests to `/` and `/sign-in` on the running local development server returned HTTP 200 with no new current-time diagnostic. A separate synthetic session run could not start alongside the existing server, so signed-in development replay remains unverified.

## Verify A failure diagnostics

- The previous live 503 retained only `provider_error`. The detection route now logs the first failing stage and allowlisted metadata under a correlation ID. The browser gets the corresponding safe message, retryability, stage, category, and support reference. The existing database audit keeps its coarse categories.
- Provider HTTP errors, SDK timeouts and network failures, malformed responses, inconclusive results, and proposal write failures have distinct categories. SDK logging is disabled. Temporary video and audio directories are removed before any proposal write. A cleanup error cannot replace an earlier processing failure.
- Mocked route tests exercise these mappings, error redaction, temporary file removal, and the confirmation gate. An initial test run exposed a mock call history shared across cases. Clearing that history fixed the assertion. All 46 tests passed on rerun. The live request was not retried.

## Verify A diagnostic persistence by support reference — 2026-11-11

- Task: persist sanitized Verify A failure details and make them retrievable using the support reference, without changing detection logic or making a provider request.
- Added service-role-only `verify_language_detection_diagnostics` storage and an owner-authenticated lookup endpoint. Failure responses remain fixed safe browser fields; no secret, transcript, media, path, URL, or raw response data is stored.
- Updated mocked route coverage for the durable diagnostic insert and redaction; documented the persistence and lookup method in `docs/verify-language.md`.
- Files changed: migration, diagnostic route and tests, Verify A docs, this build log.
- Tests: added sanitized persistence assertions and support-reference lookup coverage, alongside provider status/category, transport classification, response validation, proposal persistence failure, proposal absence on failures, false transcription eligibility, cleanup, and secret/transcript redaction checks.
- Commands: `npm run lint` passed; `npm run typecheck` passed; `npm test` passed (9 files / 47 tests before the final lookup assertion, followed by a focused rerun); `npm run build` passed; `git diff --check` passed. No live OpenAI request or commit.
- Known limitation: the new migration must be applied to the local database before the runtime persistence is available; hosted database was not changed.

## Local diagnostics migration validation — 2026-11-11

- Applied only 20261113090000_verify_language_diagnostics.sql and its history entry atomically through supabase_db_irin-stories, confirmed mapped to local port 54322 and healthy. History count is exactly one.
- Verified table existence, RLS, fourteen approved columns, and denied SELECT/INSERT privileges for anon/authenticated. Service-role insertion and retrieval passed using synthetic rollback-only rows.
- Forbidden-data enforcement FAILED: unrestricted category text accepted a synthetic transcript sentinel. The test rolled back. No real secret or private content was used. The schema was not changed to conceal this finding.
- Added anonymous, cross-owner and unknown-reference 404 handler tests. These and the existing owner lookup test mock database/session boundaries; they do not establish live authenticated HTTP behavior.
- No Supabase restart, remote migration, live OpenAI request, or commit. Human review of the missing database content constraints remains pending.
## Local diagnostic hardening — 2026-11-11

Task: harden only local Verify diagnostic persistence. Files changed: follow-up migration; diagnostic helpers and POST write path; route test assertions; new sanitizer tests, database-backed lookup tests and SQL rejection matrix; verify-language.md, data-model.md and this log. Human review is pending.

Validation: lint, typecheck, production build and git diff --check passed; npm test passed 60 tests with four opt-in database cases skipped, and the four opt-in cases passed separately. Initial database lookup exceeded Vitest's five-second timeout during Docker startup and passed with a 30-second test budget. Initial replay bootstrap failed on copied platform ownership, then missing platform primary keys; copying schema without ownership and restoring required platform keys resolved both before successful replay. No product invariant was changed.

Follow-up migration 20261114090000_harden_verify_language_diagnostics.sql preserves applied history. Both diagnostic migrations are local-only. The fourteen columns are: correlation_id UUID primary key; story_id nullable UUID foreign key; attempted_at non-null timestamptz; stage/category non-null allowlisted text; retryable non-null boolean; provider/model nullable allowlisted text; provider_http_status nullable smallint (100–599); provider_error_type/code nullable exact allowlisted text (maximum 64); provider_request_id nullable req_ plus 32 hexadecimal digits; transport nullable timeout/network; database_code nullable five uppercase alphanumeric SQLSTATE characters. Null story IDs are allowed only at ownership_check. Diagnostics cascade on story deletion, replacing SET NULL to prevent invalid orphans.

Strict Zod validation precedes inserts. Unknown provider types/codes become null; PGRST codes become null because they are not SQLSTATEs. Browser failure fields are unchanged. No generic payload, JSON, message, transcript, audio, path or URL column exists.

The local SQL matrix rejected 92 forbidden insertions: paragraphs, key-like sentinels, bearer text, URLs, Windows/Unix paths, signed URLs, oversized identifiers and JSON across all nine text fields, invalid HTTP statuses/SQLSTATEs, and missing resolved story IDs. Service insertion/read and RLS/grants passed. Tests roll back. The existing Verify SQL harness reported 19 passing assertions and deliberately raised its results exception for rollback.

Four real-database GET handler cases passed: owner 200; cross-owner, anonymous and unknown reference 404. Session identity and database-client adapters are injected; full browser-cookie/HTTP authentication is not claimed. Run diagnostics-local.test.ts with VERIFY_DIAGNOSTICS_DB_TEST=1 and --testTimeout=30000 --hookTimeout=30000. Fixtures are removed.

All six application migrations replayed in an isolated local database over empty auth/storage platform definitions with required primary keys. The rejection matrix passed there; the scratch database was removed. No reset of the existing local database was needed.

Limits: constraints cannot prevent covert encoding into valid UUIDs, hexadecimal request IDs or SQLSTATE-shaped identifiers, or a privileged administrator changing constraints. Database outages can still prevent durable writes. No hosted changes, live OpenAI requests or commits occurred.

## HTTP 200 language cardinality diagnostics — 2026-11-11

Task: review gpt-transcribe response normalization and distinguish zero/one/multiple detected languages without a model, migration or transcription change. Official API documentation and installed SDK agree with the existing languages object-array parser; no structural mismatch found.

Changed language.ts (safe cardinality error metadata), detect-language route (safe log labels only), detection-route.test.ts, new language-sdk-response.test.ts, verify-language.md and this log. The new SDK tests mock global fetch; route tests mock the provider. No private payload is retained or inspected. Confidence remains null. Persisted diagnostic/browser contracts and the single-language requirement remain unchanged.

Limitation: labels are log-only because no schema change is permitted. Historical empty versus multiple results remain unknown. Human review pending. No live request, migration, model change or commit.

Validation: npm run lint, npm run typecheck, npm test (67 passed; four opt-in local-database tests skipped), npm run build and git diff --check passed. No test failures encountered in this task.

## Verify B Yoruba source transcription — 2026-11-11

Task: implement the minimum owner-authorized Yoruba source transcription path after explicit current-source language confirmation, with timestamped segments, immutable transcript versions, storyteller edits, and exact-hash approval. No Craft, English translation, hosted migration, live provider test, or commit was performed.

Added migration 20261116090000_verify_yoruba_transcription.sql to link transcript versions to either a confirmed AI review or storyteller language decision and to record owner approval against the sealed artifact SHA-256. The server route rechecks owner, latest READY verification, current source, eligibility, and source digest; downloads only the private source; extracts full-source 16 kHz mono FLAC; requests gpt-transcribe verbose segments; and writes through service-role-only functions. Transcript edits create a new artifact version and preserve `initial_proposal`; approvals and edits are separately audited.

Tests added for response timestamp/language validation, hash provenance, Verify transcript UI, and rollback SQL integration cases. The `supabase migration up` command explicitly targeted local 127.0.0.1:54322 but reported that the PostgreSQL connection terminated unexpectedly although Docker health and `pg_isready` succeeded. The reviewed migration was then applied transactionally through the explicitly named local PostgreSQL container; local history records 20261116090000 once, and 20261109090000 through 20261116090000 each appear once. The rollback-only SQL harness reported 23 passing assertions; its final `VERIFY_LANGUAGE_RESULTS` exception and nonzero psql status are intentional to roll back synthetic fixtures. Lint, typecheck, unit/component tests (75 passed, four database opt-in cases skipped), production build, and git diff --check passed. One existing FFmpeg media-probe test exceeded its 30-second timeout at 34 seconds on this machine; its per-test budget was increased to 60 seconds and the full suite then passed. Remaining limits: OpenAI transcription was not called in automated tests, and full hosted runtime, deployment-size limits and end-to-end browser behavior remain unverified. No hosted migration/write command was run.
## Human-authoritative language fallback — 2026-11-11

Task: add separate owner-authorized language selection and confirmation after `no_reliable_language`, retaining failed detection provenance and preventing selection-only transcription eligibility.

Completed the fallback with a pending selection row and a separate confirmation RPC. Selection has null confirmation fields; the confirmation trigger derives the owner and server timestamp, and eligibility checks current-source READY verification plus confirmed Yoruba. The source invalidation trigger runs when a SOURCE_MEDIA artifact is sealed, after it becomes the current version. Diagnostics remain intact and a source-linked unreliable-detection audit event records the correlation ID. No fake AI proposal is created.

The disposable LOCAL database was clean-reset and replayed after the migration changes. Local history shows migrations 20261109090000 through 20261115090000 once each. The rollback-only Verify SQL harness reported all assertions passed, including fallback owner selection, pending fields, eligibility, owner/anonymous rejection, source replacement, audit history and no fake proposal. Focused fallback UI tests passed 3/3. Lint, typecheck, all application tests (70 passed, 4 skipped), build and diff check passed. The focused Playwright attempt was blocked because the configured Chromium executable is not installed; no browser binaries were installed. No hosted target was accessed; no commit or transcription work occurred.

## Minimum Craft Story Cut workflow — 2026-11-11

Task: implement a bounded Craft path from the exact approved Yoruba transcript. Added local-only migration `20261117090000_story_cut_workflow.sql` with exact `transcript_segment_id` lineage and append-only exact-hash owner approvals. Separate server operations create a proposed version, persist storyteller remove/reorder changes as new sealed versions, and explicitly approve the latest version. Source and transcript gates require a current READY source and matching approved transcript hash; approval history stays attached to old versions when dependencies change. The Craft page shows the private video and approved transcript beside ordered Story Cut segments and duration; 90–150 seconds is guidance. No Translate, remote migration, or commit.

Focused mocked-provider unit and component coverage and database assertions were added. The server uses `OPENAI_STORY_CUT_MODEL` (default `gpt-4o-mini`) to select existing approved transcript-segment IDs and provide short role/rationale metadata; the server discards any text/timestamps the provider did not derive from the transcript, and no test performs a live request. Migration 20261117090000 was applied transactionally to the local database; the rollback-only SQL test exposed an ambiguous output-column reference in the approval RPC, fixed by local-only follow-up migration 20261117100000. Local history contains each migration from 20261109090000 through 20261117100000 once. The updated Verify SQL harness passed its Story Cut exact-segment/hash approval assertion and source-replacement invalidation assertion (the harness reports JSON in an intentional final exception to roll back synthetic fixtures). Lint, typecheck, unit/component tests (78 passed, 4 skipped), production build, and diff check passed. No remote migration, live model request during tests, or commit occurred.

## Yoruba-to-English Translate workflow — 2026-11-11

Task: add the minimum server-side Translate stage from the current approved Yoruba Story Cut. Migration 20261118090000 adds immutable exact-hash translation approvals, original AI-English storage, and owner/service-role policies; current-source/approved-cut checks use Story Cut provenance rather than a fabricated legacy approval. The API requires explicit processing consent before sending only approved cut-segment Yoruba text to OpenAI, validates one ordered result per exact cut segment, derives all timestamps and IDs server-side, and persists versioned AI proposals or storyteller edits. Translation UI shows Yoruba and English together, discloses AI assistance, permits editing as a new immutable version, and has a separate explicit approval action.

Migrations 20261118090000 and 20261118100000 were applied only to local Supabase at 127.0.0.1:54322; local history contains versions 20261109090000 through 20261118100000 once each. Rollback-only database assertions passed for exact Cut/transcript/source timestamp lineage, versioned edits preserving AI-original English, hash-bound owner approval, cross-owner/anonymous restrictions, audit events, and invalidation after Story Cut/source replacement. Focused mocked-provider and component tests passed. Full validation passed: lint, typecheck, tests (82 passed, 4 skipped), production build, and `git diff --check`. No Protect, remote migration, live OpenAI test call, or commit.

## Protect privacy and Story Covenant workflow — 2026-11-11

Task: add the minimum Protect stage from the approved English translation. New migration `20261119090000_protect_privacy_covenant.sql` stores AI-only findings anchored to exact translation segments, keeps storyteller decisions append-only, and binds each versioned Covenant to exact privacy-review, translation, Story Cut, and source versions. A separate owner-approved hash record activates a Covenant. Publication eligibility is a server/database readiness gate and requires a current approved translation and cut, explicit decisions for all current findings, exact latest Covenant approval, and allowed public viewing. Reuse permissions are explicit and default denied; voice cloning is blocked. No Publish or remote migration was implemented.

The Protect UI requests explicit consent before sending approved English segments to OpenAI, shows findings and safer alternatives, and exposes KEEP/GENERALISE/ANONYMISE/REMOVE as storyteller actions. Non-KEEP decisions retain the existing requirement for a later approved edit with matching source lineage, followed by a new privacy review. Provider and component tests use mocked data; the rollback-only local SQL harness covers exact finding lineage, owner decision/audit, explicit Covenant denials and approval, readiness eligibility, and source replacement invalidation.

Migration `20261119090000` was applied only to local Supabase at `127.0.0.1:54322`; local history contains migrations `20261109090000` through `20261119090000` exactly once. Every Protect assertion in the rollback harness passed; its final `VERIFY_LANGUAGE_RESULTS` exception is the expected rollback sentinel. `npm run lint`, `npm run typecheck`, `npm test` (85 passed, 4 skipped), `npm run build`, and `git diff --check` passed. No live OpenAI request, hosted migration, Publish implementation, or commit occurred. Limitation: the workflow reports readiness only; a later Publish implementation must recheck every source/version/permission dependency at transaction time.

## Publish and Withdrawal workflow — 2026-11-11

Task: implement the minimum real Publish and Withdrawal workflow from approved current versions. Local migrations `20261120090000_publication_and_withdrawal.sql` and `20261120100000_publication_uses_custom_cut_approval.sql` add exact source-verification/component hashes and connect Publish validation to the current custom Verify/Craft/Translate/Protect approvals. Cultural-review and rendered-media references are nullable for this bounded metadata-only publication; raw source video is never served. Snapshot creation, final storyteller approval, Publish, and Withdrawal are distinct owner-authorized server actions. The existing public RPC keeps its seven-field allowlist, and the public page reads only that RPC. Withdrawal changes serving state while retaining immutable provenance and approvals.

Focused component and rollback-only database tests cover blocked eligibility, separate final approval and Publish, exact snapshot/hash lineage, the public field allowlist, cross-owner access, immutable snapshot, withdrawal revocation and retained history. Local history was verified through `20261120100000`, with migrations `20261120090000` and `20261120100000` each present once. `npm run lint`, `npm run typecheck`, `npm test` (87 passed, 4 skipped), `npm run build`, and `git diff --check` passed. No remote migration, Publish media rendering, or commit.

### Hosted development deployment — 2026-11-11

Authenticated Supabase CLI preflight verified the linked target as `irin-stories-dev` (`hhuqadqruwhctjgtlvcp`). Remote history initially contained only `20261109090000` and `20261110090000`; the 13 pending migrations `20261111090000` through `20261120100000` were applied in order with `supabase migration up`. No migration failed, no synthetic test harness or seed ran remotely, and no Auth/Storage configuration was changed. Read-only post-deployment checks found all 15 expected migrations exactly once; all 20 foundation tables have RLS; `private-source` has `public=false`; Verify, Craft, Translate, Protect, and Publish schema objects exist; and `get_published_story(uuid)` returns only `public_id`, `title`, `original_language_code`, `share_language_code`, `ai_editing_disclosed`, `ai_translation_disclosed`, and `published_at`, executable by `anon` and `authenticated` only. Remote story and media asset counts are both zero. Local lint, typecheck, tests (87 passed, 4 skipped), production build, and `git diff --check` passed. The local-stack ledger refresh attempt during deployment returned `DbConnectError: Connection terminated unexpectedly`; pre-deployment local history through `20261120100000` had been verified previously and the local database was not modified by this deployment task.
