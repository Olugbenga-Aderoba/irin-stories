# Local database execution test report

**Date:** 2026-11-10
**Scope:** Disposable local Supabase/PostgreSQL only. The hosted `irin-stories-dev` project was not targeted for database operations.

## Runtime and target

- Docker Engine/Desktop: 29.9.2 / Docker Desktop 4.98.0.
- Docker Compose: 5.6.1.
- Supabase CLI: 3.0.0.
- Local PostgreSQL endpoint: `127.0.0.1:54322` (no credentials recorded).
- Docker context: `desktop-linux`.
- Configured database health timeout: `10m` (retained for initial local validation as requested).
- The official PostgreSQL image `public.ecr.aws/supabase/postgres:17.11.0.018` was already cached and reused.

## Migration execution

`npx supabase db reset --local` reported `Target: local stack (127.0.0.1:54322)`, recreated the disposable local database, and completed with `Finished supabase db reset`. It applied `20261109090000_irin_stories_mvp_foundation.sql` successfully. No SQL correction was made.

The command reported `no files matched pattern: supabase/seed.sql`; the configured seed path is absent, but this did not prevent migration success. The reset also downloaded a missing local Storage API image. Other Supabase services were reported stopped by `supabase status`; only the local database container was confirmed healthy before the reset.

There were no PostgreSQL errors during migration execution. Two early synthetic fixture attempts had test-order/input errors, not migration errors:

- An authenticated test insert explicitly supplied `stories.id`; the intended grant permits only `owner_id` and `title`. The corrected RLS test omitted `id`, using its database default.
- A publication fixture attempted privacy approval before resolving its finding. PostgreSQL correctly rejected it with `Privacy approval requires the current cut and translation and a storyteller decision for every finding.` The fixture was reordered to test the denial first and then resolve the finding.

The later publication fixture was interrupted when Docker Desktop returned HTTP 500 for the local engine/container API. No completion output was received for that transaction.

## Final catalog inspection after migration

| Object | Count/result |
|---|---:|
| Public tables | 20 |
| Enums | 10 |
| Foreign keys | 73 |
| Check constraints | 68 |
| Indexes | 53 |
| Functions (`public` and `irin_private`) | 41 |
| Public-table RLS enabled | 20 of 20 |
| Public RLS policies | 25 |
| Direct table grants to `anon` | None |
| Public RPC executable by `anon` and `authenticated` | `get_published_story(uuid)` only |

The catalog query initially used a nonexistent `information_schema.tables.row_security` column and failed. It was corrected to use `pg_class.relrowsecurity`; this was a verifier-query correction, not a database change.

## RLS and integrity matrix

| Case | Result | Evidence |
|---|---|---|
| A1: A creates Story 1 | PASS | Authenticated insert succeeded. |
| A2: A creates Story 2 | PASS | Authenticated insert succeeded; A saw 2 owned rows. |
| B1: B reads A's story | PASS | Result count was 0. |
| B2: B updates A's story | PASS | Update count was 0. |
| ANON1: private stories | PASS | Direct read denied. |
| ANON2: source-media metadata | PASS | Direct read denied. |
| ANON3: transcripts | PASS | Direct read denied. |
| ANON4: Story Cuts | PASS | Direct read denied. |
| ANON5: translations | PASS | Direct read denied. |
| ANON6: privacy findings | PASS | Direct read denied. |
| ANON7: Covenants | PASS | Direct read denied. |
| ANON8: audit records | PASS | Direct read denied. |
| Additional anonymous private-table checks | PASS | All 12 checked private tables raised insufficient privilege. |
| OWN1: forged owner ID on insert | PASS | RLS rejected the insert. |
| Story ownership update | PASS | Authenticated role lacks the owner-ID update grant; ownership is also guarded by a trigger. |
| Positive media duration | UNVERIFIED | Planned negative fixture was not completed. Schema catalog includes checks; runtime behavior still needs a complete local test. |
| Segment end after start | UNVERIFIED | Planned negative fixture was not completed. |
| Transcript source timestamp preservation | PARTIAL | Migration metadata confirms source media and start/end timestamp columns; runtime fixture was interrupted. |
| LINEAGE1: cross-story transcript/Story Cut | UNVERIFIED | Synthetic transaction returned no completion result. Composite FKs are present in the catalog. |
| LINEAGE2: cross-story translation | UNVERIFIED | Synthetic transaction returned no completion result. Composite FKs are present in the catalog. |
| APPROVAL1: approval has exactly one target | UNVERIFIED | The exact-target check exists; runtime negative fixture did not complete. |
| APPROVAL2: B approves A's artefact | UNVERIFIED | Owner-approval trigger exists; runtime negative fixture did not complete. |
| Historical approved-version immutability | UNVERIFIED | Seal guard exists; runtime mutation fixture did not complete. |
| Publication snapshot immutability | UNVERIFIED | Immutable-row trigger exists; runtime mutation fixture did not complete. |

## Privacy, Covenant, public RPC, and withdrawal

| Case | Result | Evidence |
|---|---|---|
| Unresolved privacy finding blocks approval | PASS | PostgreSQL rejected approval with the exact error recorded above. |
| Unresolved privacy review blocks final-media registration | PASS | PostgreSQL returned `Final media requires the current completed privacy review.` |
| Missing public-view Covenant blocks final-media registration | PASS | PostgreSQL returned `Final media requires an active Covenant that explicitly permits public viewing.` |
| Missing public-view Covenant prevents discovery | UNVERIFIED | RPC-level test was part of the interrupted transaction. |
| Missing publication approval prevents RPC discovery | UNVERIFIED | RPC-level test was part of the interrupted transaction. |
| Fully valid publication returned by narrow public RPC | UNVERIFIED | The complete publication transaction did not finish. |
| Public RPC field allowlist | PARTIAL | Catalog confirms its six declared return fields and its only public function grant; a successful anonymous invocation was not captured. |
| Withdrawal removes public visibility | UNVERIFIED | The withdrawal test did not complete. |
| Private snapshot, provenance, and audit retained after withdrawal | UNVERIFIED | The retention checks did not complete. |

## Repeatability and application validation

The initial `db reset --local` recreated the empty local database and applied the migration once. A second clean reset/reapply was not completed, so repeatability is **unverified**.

- `npm run lint` - passed.
- `npm run typecheck` - passed.
- `npm test` - passed (5 files, 13 tests).
- `npm run build` - passed.
- `git diff --check` - passed before this report was written; rerun after documentation edits.

## Docker recovery interruption and remaining risks

After the successful reset, Docker Desktop's `desktop-linux` engine returned HTTP 500 for container API requests and its own status reported `stopping`. A direct local Supabase CLI query reported `Connection terminated unexpectedly`. The Docker Desktop CLI restart hung; launching Docker Desktop again left it in the same state, and the service could not be opened by the current session. The full local service stack was therefore not confirmed healthy.

No hosted SQL, remote reset, migration push, Auth change, Storage change, or seed operation was run. No secrets, tokens, passwords, or credential-bearing connection strings are included here. Remaining work is to recover Docker Desktop, confirm the local endpoint, finish the unverified integrity/publication/withdrawal matrix, repeat a clean local reset, and rerun the final catalog checks. No commit was created.

## Continuation — 2026-11-10

### Clean local reset and replay

The requested clean reset was retried against **LOCAL `127.0.0.1:54322` only**. The CLI output reached `Initialising schema...` and then ended without its usual final success line; an immediate direct local catalog query confirmed the migration had replayed, with **20 public tables and RLS enabled on all 20**. A preceding reset attempt ended before schema initialization and left 0 public tables; it was retried. Docker status inspection remained unavailable due to access denied on the Docker API, but `supabase db query` reached the local database. No remote command was issued.

### Remaining runtime cases

Cross-story transcript/Story Cut and translation lineage rejection; approval exact-target and cross-owner rejection; a valid synthetic publication; anonymous RPC invocation and actual returned row fields; withdrawal visibility and retained provenance remain **unverified** in this continuation. The migration declares `get_published_story` as returning `public_id`, `title`, `original_language_code`, `share_language_code`, `ai_editing_disclosed`, `ai_translation_disclosed`, and `published_at`; that is source evidence only, not a successful RPC result. No publication or withdrawal fixture was created. The clean reset removed prior disposable test fixtures; no private retained records are claimed.

The larger transaction fixtures were not completed; no pass is inferred from composite constraints or the function declaration.

### Application checks and timeout setting

- `npm run lint` — passed.
- `npm run typecheck` — passed.
- `npm test` — passed, 5 files / 13 tests.
- `npm run build` — passed.
- `git diff --check` — passed before this continuation was documented; rerun after documentation edits.

`health_timeout = "10m"` is retained. It supported the previously successful local startup and did not cause the Docker API inspection issue. No CLI upgrade was run. No hosted SQL, `db push`, linked reset, remote migration, hosted Auth, or hosted Storage operation was run. No commit was created.

## Requested remaining tests — 2026-11-10 follow-up

The local database answered read-only queries at `127.0.0.1:54322` and currently has no synthetic Auth users or stories. This run did not create a publication fixture. The four requested runtime cases (cross-story lineage, approval integrity, valid publication/RPC, and withdrawal/retained provenance) therefore remain **not run**, not passed. No integrity trigger or RLS policy was disabled to manufacture test success. The migration's candidate enforcement points are composite lineage FKs, `approvals_exactly_one_target`, and `irin_private.guard_approval()` (`Approval must be made by the owning storyteller.`); these source definitions are not runtime rejection evidence. The RPC's declared field list is documented above, but no fields were returned by a valid publication call.

No LOCAL database-changing SQL was run in this follow-up. Application validation is rerun and recorded below.

## Repeatable foundation integration harness — 2026-11-10

This section supersedes the earlier continuation notes that described these scenarios as unverified; the earlier notes preserve the chronology before the harness was created.

Created and executed `supabase/tests/irin_stories_foundation_test.sql` twice against LOCAL `127.0.0.1:54322`. The migration presence/catalog check returned one foundation migration, 20 public tables, and RLS enabled on 20/20. Each run used fixed synthetic UUIDs and content, switched roles for the B approval attempt and anonymous RPC, and wrapped all fixture work in one PostgreSQL `DO` statement. Because `supabase db query` prepares one statement per invocation, the harness emits the matrix in a final `IRIN_STORIES_TEST_RESULTS` sentinel exception. That intentional exception rolls the whole statement back; both executions therefore have CLI exit status 1 despite every scenario reporting `passed: true`. A follow-up local query confirmed zero synthetic users/stories persisted.

| Test | Expected | Actual | Result / evidence |
|---|---|---|---|
| A1 -> A2 Story Cut lineage | BLOCKED | BLOCKED | PASS, SQLSTATE `P0001`: `Craft requires the latest storyteller-approved transcript of the current source.` |
| A1 -> A2 translation lineage | BLOCKED | BLOCKED | PASS, SQLSTATE `P0001`: `Translation requires the current source and approved source transcript.` |
| Multiple-target approval | BLOCKED | BLOCKED | PASS, SQLSTATE `23514`, check `approvals_exactly_one_target`. |
| Cross-owner approval as authenticated B | BLOCKED | BLOCKED | PASS, SQLSTATE `P0001`: `Approval must be made by the owning storyteller.` |
| Malformed approval hash | BLOCKED | BLOCKED | PASS, SQLSTATE `P0001`: `Approval must bind to the exact hash of a sealed artefact version.` The guard rejects the wrong-length value before the table hash-length check. |
| Cross-story approval target | BLOCKED | BLOCKED | PASS, SQLSTATE `P0001`: `Approval must bind to the exact hash of a sealed artefact version.` |
| Valid publication created | ALLOWED | ALLOWED | PASS; all source, approval, privacy, Covenant, final-media, and snapshot guards completed. |
| Anonymous RPC returns publication | YES | 1 row | PASS; actual row was the synthetic publication. |
| Public RPC field allowlist | Seven public fields only | Exact seven-key match | PASS; keys: `public_id`, `title`, `original_language_code`, `share_language_code`, `ai_editing_disclosed`, `ai_translation_disclosed`, `published_at`. No private ID, storage path, transcript, finding, audit, or Covenant field was returned. |
| Withdrawn publication returned publicly | NO | 0 rows | PASS after authenticated owner A withdrew access. |
| Snapshot retained | YES | 1 | PASS. |
| Approvals retained | YES | 7 | PASS. |
| Covenant history retained | YES | 1 Covenant artifact | PASS. |
| Source/transcript/cut/translation provenance retained | YES | 7 typed lineage rows | PASS; source media, transcript/version segment, cut/version segment, translation/version segment. |
| Covenant permissions retained | YES | 10 rows | PASS; every explicit permission row remains. |
| Audit history retained | YES | 17 events | PASS, including publication and withdrawal events. |

No production migration SQL was changed. No database defect was demonstrated. No hosted command or project was used. The harness itself is intentionally single-use-transaction/rollback and can be rerun; it does not persist fixtures. Its final sentinel is an expected test mechanism, not a scenario failure.

## Auth and private source Storage follow-up — 2026-11-10

Added migration `20261110090000_private_source_storage.sql` and synthetic rollback-only policy harness `supabase/tests/private_source_storage_test.sql`. The migration defines the private 500 MiB `private-source` bucket, owner/story-bound Storage INSERT/SELECT, cleanup-only deletion for unregistered objects, `create_story()` (owner from `auth.uid()`), and `register_source_media(...)` (atomic artefact/media metadata sealing and audit trigger). The migration was not applied locally or hosted during this run.

Local replay was attempted with `npx supabase migration up --local`; the CLI confirmed `Target: local stack (127.0.0.1:54322)` and then returned `DbConnectError: failed to connect to postgres: failed to connect to host=127.0.0.1 user=postgres database=postgres: Connection terminated unexpectedly`. Therefore Storage policy SQL, Auth functions, and Storage API behavior remain unexecuted. No hosted target was selected. The application unit suite passed (6 files, 16 tests); lint, typecheck, and build passed. The Playwright suite was added but not run because the disposable local Auth/Storage stack is unavailable.

No database or hosted Auth/Storage change was made. The migration needs local SQL execution and Storage HTTP/API authorization coverage before hosted deployment. The bucket config raises the local global Storage limit to 500 MiB and sets local password minimum to eight characters; hosted Auth redirect allowlists and hosted global Storage limits remain unchanged and will require separate review/configuration before deployment.

## Protect local verification — 2026-11-11

Migration `20261119090000_protect_privacy_covenant.sql` was applied only to the local Supabase PostgreSQL container for `127.0.0.1:54322` and recorded once in `supabase_migrations.schema_migrations`. The rollback-only `supabase/tests/verify_language_test.sql` harness was extended with synthetic approved translation and Protect data. Its Protect assertions passed: an AI finding stored `proposal_source=AI`, model label, exact translation-segment reference and safer alternative; Storyteller B was rejected; owner KEEP created an audit event; all ten Covenant permission rows were explicit with nine denied including all reuse permissions; exact-hash Covenant approval succeeded; the readiness gate became true; and replacing the source made Protect eligibility false while historical records remained. The harness ends with its intentional `VERIFY_LANGUAGE_RESULTS` exception to roll back the synthetic fixture. No hosted migration or data was touched.
