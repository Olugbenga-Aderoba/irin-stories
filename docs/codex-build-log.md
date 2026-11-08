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
