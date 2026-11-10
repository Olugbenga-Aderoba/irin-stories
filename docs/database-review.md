# Irin Stories database architecture review

## Scope and decisions

This review covers the local proposed foundation migration only. It was not applied to PostgreSQL or Supabase; no remote project was queried or changed for this review.

The initial proposal contained 22 tables. The refined migration contains **20 tables**. Two structures were removed without removing required history or lineage:

1. `story_cut_segment_transcript_segments` was removed. Each cut segment already carries the exact story, source-media, transcript-version IDs, and source-video interval. A trigger requires that interval to overlap a segment in that exact transcript version. Translation segments separately reference the exact transcript segment and cut segment, with a trigger checking overlap. The junction relationship can therefore be derived from timestamps.
2. `rendered_media_versions` was merged into `media_assets`. Final publication metadata is a `media_assets` row with `role = FINAL_PUBLICATION` and exact cut/translation lineage. Composite FKs bind the snapshot directly to that row; the wrapper duplicated a link without adding history.

All remaining tables are required by the complete MVP invariants. Runtime implementation can be staged by workflow, but merging these records would conflate ownership, cardinality, lifecycle, privacy, or audit boundaries.

### Risks and decisions

- **Ownership:** no unique constraint or policy limits an owner to one story. `stories.owner_id -> auth.users.id` permits one Auth user to own many stories; children inherit ownership through `story_id`.
- **Durations:** database constraints require positive media/cut duration, `end > start`, and timestamp bounds within the source or cut timeline. Source 5-15 minutes and final 90-150 seconds remain application/UX guidance.
- **Languages:** language fields use validated text codes. Workflow guards enforce Yoruba confirmation/transcription and Yoruba-to-English translation for the MVP. Adding languages later does not require a structural migration.
- **Public reads:** the previous `published_story_directory` view was unsafe because ordinary PostgreSQL views run with view-owner privileges; `security_barrier` alone does not enforce base-table RLS. It was replaced with a narrow `public.get_published_story(uuid)` `SECURITY DEFINER` RPC. It has empty fixed `search_path`, schema-qualified objects, revoked default execution, explicit grants only to `anon` and `authenticated`, and returns only public ID/title/language codes/AI disclosure flags/publish time. It requires published access and story state, exact snapshot approval/hash, latest snapshot, active Covenant with public-view permission, and successful full snapshot validation. It exposes no owner ID, media key, transcript, finding, or Covenant field. Anonymous users have no base-table grant.
- **Approvals:** the two-target shape has `CHECK (num_nonnulls(artifact_version_id, publication_snapshot_id) = 1)` plus separate same-story FKs and unique constraints. This constrained polymorphic target is safe for these two known targets. Each decision binds the owner, timestamp, target, and 32-byte SHA-256 digest.
- **Privacy:** AI findings and storyteller decisions are separate append-only records. `KEEP` has no edit version. `GENERALISE`, `ANONYMISE`, and `REMOVE` cite a later approved cut or translation version; a new privacy review must approve edited output before publication.
- **Immutability:** revisions create new artefact versions. Sealed versions and child rows, approvals, Covenant permissions, privacy decisions/findings, and snapshots reject update/delete. Dependency-aware current-approval checks keep historical approvals auditable but make them unusable after an upstream version changes. `publication_access` is mutable only through guarded state transitions.
- **Concurrency:** per-story locks serialize artefact, language-review, and snapshot version allocation. Uniqueness constraints fail closed if locking is bypassed; transactional workflow and retry behavior still need execution tests.
- **Hashing:** PostgreSQL checks hash length and equality. The trusted server must calculate the canonical digest; this migration does not hash arbitrary row content.
- **Existing plan wording conflict:** `docs/implementation-plan.md` still says "A second story is rejected" and "Enforce one MVP story per storyteller." This review leaves that planning file unchanged. The smallest later correction is to say the demo starts with one story while an account may own many.

## Table justification matrix

"Required for MVP" means required in the complete MVP data model. Runtime use can wait until the named stage.

| Table | Purpose | Why separate | Timing | Ownership path | Version/lineage role |
|---|---|---|---|---|---|
| `stories` | Owner-scoped workflow root/title | Stable identity must outlive versions | Required now; Foundation | `owner_id -> auth.users.id` | Stable root; guarded workflow state |
| `artifact_versions` | Typed version, creator, hash, seal registry | Common version fields differ from typed child data | Required now; Foundation | `story_id -> stories.owner_id` | Per-kind increasing versions; one-time seal |
| `media_assets` | Source/final private object metadata | Object key, bytes, MIME, duration, and stream fields are media-specific | Tell/Publish | `story_id -> stories.owner_id` | Source or final-render version; final row binds exact cut/translation |
| `source_language_reviews` | Detection proposal and storyteller confirmation | Multiple proposals/corrections need independent timestamps | Tell | `story_id -> stories.owner_id` | Per-source review sequence; transcript references exact review |
| `transcript_versions` | Transcript metadata and source/language lineage | Version-level details differ from many timed text segments | Verify | `story_id -> stories.owner_id` | Typed version tied to source and confirmation |
| `transcript_segments` | Yoruba text and source timestamps | One transcript has many independently traceable intervals | Verify | `story_id -> stories.owner_id` | Immutable child of exact transcript/source |
| `story_cut_versions` | Cut-level source/transcript and duration | Version lineage differs from ordered clip records | Craft | `story_id -> stories.owner_id` | Typed version tied to approved source/transcript |
| `story_cut_segments` | Clip decision, rationale, source/output interval | Per-clip ordering and timestamps are repeatable records | Craft | `story_id -> stories.owner_id` | Immutable child, exact source interval; overlap derives transcript mapping |
| `cultural_review_versions` | Review bound to one cut | Review approval lifecycle differs from its annotations | Craft | `story_id -> stories.owner_id` | Typed version tied to exact cut |
| `cultural_annotations` | Expression meanings and storyteller interpretation | A review can contain many segment-specific expressions | Craft | `story_id -> stories.owner_id` | Immutable children of review and cut segment |
| `translation_versions` | Language pair and exact source/cut lineage | Version lineage differs from cue rows | Translate | `story_id -> stories.owner_id` | Typed Yoruba/English MVP version tied to transcript/cut/cultural review |
| `translation_segments` | English cue timing and text | One translation has many cues, each with exact source references | Translate | `story_id -> stories.owner_id` | Tied to exact transcript and cut segments |
| `privacy_review_versions` | Review identity for exact cut/translation | Re-review must not overwrite prior review | Protect | `story_id -> stories.owner_id` | Typed review version tied to exact output |
| `privacy_findings` | Potential concern, suggestion, source anchor | A review can have many findings with independent decisions | Protect | `story_id -> stories.owner_id` | Immutable proposal anchored to source/transcript/cut/translation |
| `privacy_decisions` | Storyteller decision/actor/time | Proposal and human resolution must remain distinct | Protect | `story_id -> stories.owner_id`; actor must own story | Append-only, one per finding; non-KEEP cites later approved edit |
| `covenant_permissions` | One explicit permission per Covenant | Ten auditable terms are clearer than opaque JSON | Protect/Publish | `story_id -> stories.owner_id` | Immutable children of Covenant artifact version |
| `publication_snapshots` | Immutable exact package manifest | Snapshot contents must not share mutable serving state | Publish | `story_id -> stories.owner_id` | Versioned manifest with exact IDs and hash |
| `approvals` | Human decision for one artefact or snapshot | Uniform audit record must remain separate from content | Before each advance | `story_id -> stories.owner_id`; approver must own story | Append-only target/version/hash/actor/time |
| `publication_access` | Publish/stale/withdraw serving state | Access changes while snapshot remains immutable | Publish/Withdraw | `story_id -> stories.owner_id` | Mutable guarded access state for one snapshot |
| `audit_events` | Important workflow and access events | Audit retention/access differs from business artefacts | Required now | `story_id -> stories.owner_id`; actor is Auth user/system | Append-only event record; avoid private prose/paths |

## RLS access matrix

Legend: `S` SELECT, `I` INSERT, `U` UPDATE, `D` DELETE; `-` no direct privilege. `U(title)` and `U(withdraw)` are column-limited. For service role, `U*/D*` means table grants exist but triggers reject mutation except one-time sealing or guarded access transitions. RLS does not constrain `service_role`; it must remain server-only. "Owner" is the user owning the parent story, never a client-supplied owner value.

| Table | Authenticated owner | Anonymous | `service_role` | Ownership check and write path |
|---|---|---|---|---|
| `stories` | S/I/U(title), no D | - | S/I/U*/D* | `owner_id = auth.uid()`; owner insert checks identity; state/owner guarded |
| `artifact_versions` | S only | - | S/I/U*/D* | Owner helper on `story_id`; trusted server creates and seals |
| `media_assets` | S only | - | S/I/U*/D* | Same story ownership; trusted server registers private metadata |
| `source_language_reviews` | S only | - | S/I/U*/D* | Same; trusted server records proposal/confirmed actor |
| `transcript_versions` | S only | - | S/I/U*/D* | Same; trusted server writes confirmed-language version |
| `transcript_segments` | S only | - | S/I/U*/D* | Same; server inserts bounded text segments before seal |
| `story_cut_versions` | S only | - | S/I/U*/D* | Same; server requires approved source package |
| `story_cut_segments` | S only | - | S/I/U*/D* | Same; server writes immutable timestamped clips |
| `cultural_review_versions` | S only | - | S/I/U*/D* | Same; server opens review for approved cut |
| `cultural_annotations` | S only | - | S/I/U*/D* | Same; server inserts annotations before seal |
| `translation_versions` | S only | - | S/I/U*/D* | Same; server enforces MVP language and lineage |
| `translation_segments` | S only | - | S/I/U*/D* | Same; server writes cues tied to exact source/cut segments |
| `privacy_review_versions` | S only | - | S/I/U*/D* | Same; server binds review to current approved output |
| `privacy_findings` | S only | - | S/I/U*/D* | Same; AI/server may propose; no automatic decision |
| `privacy_decisions` | S/I, no U/D | - | S/I/U*/D* | Owner helper; insert checks `decided_by = auth.uid()` and valid edit resolution |
| `covenant_permissions` | S only | - | S/I/U*/D* | Same; server writes explicit permissions before seal |
| `publication_snapshots` | S only | - | S/I/U*/D* | Same; server validates immutable exact manifest |
| `approvals` | S/I, no U/D | - | S/I/U*/D* | Owner helper; insert checks `approver_id = auth.uid()` and exact hash/target |
| `publication_access` | S/U(withdraw), no I/D | - | S/I/U*/D* | Owner helper; owner can only withdraw PUBLISHED access; server handles publish/stale |
| `audit_events` | S only | - | S only | Owner helper; trigger-owned append, no direct table writes |

All 20 tables enable RLS. The 19 child tables use `irin_private.user_owns_story(story_id)`; `stories` checks `owner_id = auth.uid()`. There is no unrestricted `USING (true)` private policy, no anonymous base-table access, no client path to change owner identity, and no direct authenticated write to versioned artefacts. The only public path is the narrow RPC. Server workflows must derive owner from the authenticated session and keep service credentials private.

## Mutable and immutable matrix

| Table(s) | Classification | Permitted behavior |
|---|---|---|
| `stories` | Mutable root | Owner may change title; workflow and `updated_at` are trigger-governed; owner ID/identity cannot change; no owner delete |
| `artifact_versions` | Draft then sealed | Created unsealed; one seal update with 32-byte digest; no mutation/deletion after seal |
| `media_assets`, `source_language_reviews` | Append-only | New source/final metadata or language review; no update/delete |
| `transcript_versions`, `transcript_segments`, `story_cut_versions`, `story_cut_segments`, `cultural_review_versions`, `cultural_annotations`, `translation_versions`, `translation_segments`, `privacy_review_versions`, `privacy_findings` | Immutable artefact content | Insert while parent is unsealed; edits create new version; no update/delete |
| `privacy_decisions` | Append-only human decision | One owner decision per finding; non-KEEP references an approved later edit |
| `covenant_permissions` | Immutable versioned terms | Insert before Covenant seal; changed terms require new Covenant version |
| `approvals` | Append-only decision | Exact target/hash/actor/time; corrected content needs a new version |
| `publication_snapshots` | Immutable snapshot | Insert once with exact lineage/hash; no update/delete |
| `publication_access` | Mutable serving state | Guarded DRAFT->PUBLISHED, PUBLISHED->STALE, or PUBLISHED->WITHDRAWN; identity fixed; no delete |
| `audit_events` | Append-only audit history | Trigger-generated; no update/delete |

## Deferred database features and remaining validation

No Auth setup, Storage buckets/policies, API workflow functions, worker queue, OpenAI integration, language detection, transcription, translation generation, FFmpeg processing, or canonical content-hash implementation is included. The future object-path strategy is `private-source/{owner_id}/{story_id}/{media_artifact_id}/...`, `private-derived/{owner_id}/{story_id}/{artifact_id}/...`, and `publications/{publication_public_id}/{snapshot_version}/...`; database records store object keys, never public URLs. Future policies must bind paths to owner/story IDs and check publication state for each final-media request.

The next execution-validation stage needs a Docker-compatible runtime for local Supabase/PostgreSQL. In a separately authorized local-only stage, run SQL lint and a migration rehearsal, then test as anon, owner A, owner B, and service role. Exercise version allocation, approval gates, stale publication, RPC field allowlisting, withdrawal, and direct mutation rejection. This review did not apply or parse the migration in a running database and did not use a hosted project.

Before that stage, resolve the `docs/implementation-plan.md` wording noted above so one-story demo scope is not mistaken for one-story-per-user architecture.

## Authentication and private source storage follow-up

Migration `20261110090000_private_source_storage.sql` creates a private 500 MiB source bucket with MP4/MOV/WebM restrictions, authenticated owner/story path policies, and no anonymous/public access policy. It adds an auth.uid()-derived `create_story()` function and a narrowly scoped source metadata registration function that creates/seals the artifact through existing guards and triggers. Client cleanup can delete only an unregistered failed upload; registered source metadata and objects are append-only. The original filename is stored as metadata, while the sanitized filename remains in the object key.

Application code uses Supabase SSR cookie sessions; both proxy and protected server pages validate the authenticated user. No service-role credential is introduced. Source playback currently returns a one-hour signed URL after the authenticated page has passed ownership checks. This is temporary bearer access, so tighter immediate revocation would require a streaming proxy. Upload size/MIME and path are checked at client, Storage bucket/policies, and metadata RPC boundaries; duration and hash are generated by the client and have not been independently verified by a media worker. The migration is not applied to the hosted project by this task.

The new migration and rollback-only Storage policy test were added to source control but could not be executed locally in this task: `supabase migration up --local` targeted `127.0.0.1:54322` and returned `DbConnectError: failed to connect to postgres: ... Connection terminated unexpectedly`. No schema was applied in response to this failure. Hosted behavior remains unverified.

## Local execution validation - 2026-11-10

The foundation migration was applied successfully once to the disposable local Supabase PostgreSQL target at `127.0.0.1:54322`. PostgreSQL reported 20 public tables, 10 enums, 73 foreign keys, 68 checks, 53 indexes, 41 functions across `public` and `irin_private`, and 25 policies; all 20 tables had RLS enabled. The public RPC was executable by `anon` and `authenticated`, and anonymous had no direct public-table grants.

Rollback-only synthetic RLS checks confirmed one authenticated owner can create two stories, a second owner sees zero rows and updates zero rows for the first owner's story, forged ownership inserts are rejected, owner-ID updates are unavailable to the client, and anonymous direct reads are denied for 12 private tables. An unresolved privacy finding was rejected at the privacy-approval guard, and final-media creation was rejected while privacy approval was unresolved. A later synthetic publication run was interrupted by Docker Desktop's Linux engine returning HTTP 500; the public RPC, cross-story lineage, approval-target, withdrawal, provenance-retention, and second clean-reset results remain unverified. See `docs/local-database-test-report.md` for command results and exact errors.

No SQL correction was needed: the migration itself completed successfully. `supabase/config.toml` still uses `health_timeout = "10m"` for this initial validation cycle. Docker Desktop subsequently entered a persistent stopping state, so the full local service stack and remaining database tests must be rerun after the local engine recovers. No hosted schema change was made.

### Local validation continuation — 2026-11-10

A subsequent clean local reset/replay was confirmed by direct catalog query: 20 public tables and 20/20 with RLS enabled. The CLI reset process did not emit its final completion line, although the database catalog showed the migration present. Docker health inspection was blocked by local Docker API access denial; direct `supabase db query` continued to connect to `127.0.0.1:54322`.

Cross-story lineage rejection, exact approval-target/cross-owner approval rejection, a valid publication, successful anonymous RPC result fields, and withdrawal/retention behavior remain unverified runtime cases. The RPC declaration allowlists `public_id`, `title`, `original_language_code`, `share_language_code`, `ai_editing_disclosed`, `ai_translation_disclosed`, and `published_at`, but no successful publication call was captured. Do not treat the declaration as runtime proof. The `10m` local health timeout remains in place because it supported the initial successful startup and did not cause the current Docker API inspection failure. No hosted project was targeted.

### Remaining requested runtime cases — 2026-11-10 follow-up

At that point the local database was reachable but empty and no guarded fixture had yet been executed. The subsequent `Foundation integration tests` section below records the completed runtime results and supersedes this interim status.

## Foundation integration tests — 2026-11-10

The repeatable synthetic harness `supabase/tests/irin_stories_foundation_test.sql` was executed twice on the local PostgreSQL endpoint. All 16 scenario checks plus one predicate diagnostic were emitted: cross-story Story Cut/translation lineage rejections, four approval-integrity rejections, a valid complete publication, anonymous RPC row and exact seven-column allowlist, withdrawal removal, and retained snapshot/approvals/Covenant/provenance/audit rows. Exact errors and SQLSTATEs are recorded in `docs/local-database-test-report.md`.

The Supabase CLI accepts one prepared statement per `db query --file` call. The harness uses one `DO` statement and raises a final results sentinel to roll back the synthetic fixture. Consequently the CLI reports exit status 1 by design, with the complete matrix in the error payload; every matrix row has `passed: true`. A separate query confirmed the synthetic Auth users and stories did not persist. No migration change was necessary or made; no schema defect was reproduced.

### Foundation integration tests — 2026-11-10

The final synthetic harness ran twice against the local database. All 16 scenario checks passed, with one additional predicate diagnostic. Cross-story cut and translation attempts were rejected by their guards; invalid approval cases were rejected by the exact-target check or approval guard; a complete publication passed all gates; anonymous RPC returned one row with exactly the seven public fields; owner withdrawal removed it from the RPC; and 7 provenance rows, 7 approvals, the snapshot, all 10 Covenant permissions, and 17 audit events remained. The harness rolled back each execution and a post-run query found no synthetic users or stories. The CLI's nonzero exit is the intentional sentinel exception used to force transactional rollback; results are embedded in that response. No migration change was needed.

Application validation after the final harness/docs edits: `npm run lint`, `npm run typecheck`, `npm test` (5 files / 13 tests), `npm run build`, and `git diff --check` all passed.

### Local startup timeout

`supabase/config.toml` keeps `health_timeout = "10m"` as a local-development reliability setting after the local database startup/replay experience. Revisit and optimize this value later when startup timings are better characterized. It is local CLI configuration, not hosted-project configuration.
