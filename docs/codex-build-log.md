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
