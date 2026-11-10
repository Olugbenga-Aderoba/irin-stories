# Irin Stories MVP data model

## Scope and identity

This local-only schema supports multiple stories per Supabase Auth user. `stories.owner_id` references `auth.users.id`, with no unique constraint on `owner_id`; one Auth user can own many stories. A child row carries `story_id` and reaches its owner through `stories`. A separate profile or password table is unnecessary for the MVP.

The migration creates no Storage buckets. It was applied to the disposable local Supabase database on 2026-11-10; it has not been applied to any hosted database. `media_assets` stores a `bucket_id` and private `object_key`, never a public URL. The functional MVP remains Yoruba source stories shared in English. Language columns use validated text codes so adding another supported language later does not require a structural schema change; workflow guards enforce Yoruba and English for this MVP.

## Entities and relationships

The migration has 20 tables. Their responsibility is split along ownership, version, cardinality, access-state, and audit boundaries:

- **Story root and shared version registry:** `stories` stores owner, title, and workflow state. `artifact_versions` gives typed story artefacts increasing per-kind version numbers, creator, SHA-256 digest, and a one-time seal timestamp.
- **Source and language confirmation:** `media_assets` stores source or final media metadata. `source_language_reviews` preserves each proposal and the storyteller's confirmation/correction. `transcript_versions` binds an exact language confirmation and source version; `transcript_segments` stores Yoruba text with source-media ID and bounded source timestamps.
- **Craft and cultural review:** `story_cut_versions` binds the approved source/transcript pair. `story_cut_segments` stores each source-video interval, output interval, narrative role, rationale, and decision. A trigger requires each interval to overlap a segment in the exact transcript version. The overlap is derived from timestamps, so a separate cut-to-transcript junction table is unnecessary. `cultural_review_versions` and `cultural_annotations` keep versioned cultural review and one-or-more storyteller explanations for expressions in specific cut segments.
- **Translation:** `translation_versions` binds Yoruba source, exact transcript, Story Cut, and cultural-review versions. `translation_segments` references both the exact transcript segment and exact cut segment. Composite foreign keys keep them on the same story, source media, transcript version, and Story Cut; a trigger checks that the source transcript interval overlaps the selected cut segment. Subtitles use the cut output timeline.
- **Privacy:** `privacy_review_versions` binds a review to the exact approved cut and translation. `privacy_findings` stores potential concerns and a source/timestamp, transcript, cut, or translation anchor. `privacy_decisions` is a separate storyteller-only, append-only choice. `KEEP` has no edit version; `GENERALISE`, `ANONYMISE`, and `REMOVE` must cite a later approved Story Cut or translation version with the same source-media/transcript ancestry as the finding. A new privacy review must approve the edited content before publication.
- **Permissions and approvals:** a Covenant is an `artifact_versions` row of kind `COVENANT`, with one `covenant_permissions` row for each of ten explicit permissions. Defaults deny; publication requires the active Covenant to explicitly allow `PUBLIC_VIEWING`. Voice cloning cannot be enabled. `approvals` bind a human decision and 32-byte SHA-256 digest to exactly one sealed artefact version or publication snapshot.
- **Publication and history:** `publication_snapshots` is the immutable typed manifest of exact source, transcript, cut, cultural review, translation, privacy review, Covenant, and final-media versions, including disclosure flags and a manifest hash. Final media metadata is a `media_assets` row with `role = FINAL_PUBLICATION` and exact cut/translation lineage; a wrapper table is not needed. `publication_access` holds mutable serving state outside the immutable snapshot. `audit_events` records append-only events without copying private text or storage paths.

## Relationship diagram

```mermaid
erDiagram
  AUTH_USERS ||--o{ STORIES : owns
  STORIES ||--o{ ARTIFACT_VERSIONS : versions
  ARTIFACT_VERSIONS ||--o| MEDIA_ASSETS : describes
  MEDIA_ASSETS ||--o{ SOURCE_LANGUAGE_REVIEWS : receives
  SOURCE_LANGUAGE_REVIEWS ||--o{ TRANSCRIPT_VERSIONS : confirms
  TRANSCRIPT_VERSIONS ||--o{ TRANSCRIPT_SEGMENTS : contains
  STORY_CUT_VERSIONS ||--o{ STORY_CUT_SEGMENTS : contains
  TRANSCRIPT_SEGMENTS ||--o{ STORY_CUT_SEGMENTS : timestamp_overlap
  CULTURAL_REVIEW_VERSIONS ||--o{ CULTURAL_ANNOTATIONS : explains
  STORY_CUT_SEGMENTS ||--o{ CULTURAL_ANNOTATIONS : anchors
  TRANSLATION_VERSIONS ||--o{ TRANSLATION_SEGMENTS : contains
  TRANSCRIPT_SEGMENTS ||--o{ TRANSLATION_SEGMENTS : source_text
  STORY_CUT_SEGMENTS ||--o{ TRANSLATION_SEGMENTS : output_timing
  PRIVACY_REVIEW_VERSIONS ||--o{ PRIVACY_FINDINGS : proposes
  PRIVACY_FINDINGS ||--o| PRIVACY_DECISIONS : resolved_by
  ARTIFACT_VERSIONS ||--o{ COVENANT_PERMISSIONS : defines
  ARTIFACT_VERSIONS ||--o{ APPROVALS : approved_as
  PUBLICATION_SNAPSHOTS ||--o{ APPROVALS : approved_as
  PUBLICATION_SNAPSHOTS ||--o| PUBLICATION_ACCESS : serves_through
  STORIES ||--o{ AUDIT_EVENTS : records
```

Composite foreign keys repeat `story_id` intentionally. They reject cross-story references and bind child rows to exact versions. The diagram abbreviates some specialized version relationships for readability.

## Workflow states and version invalidation

`story_workflow_state` is a PostgreSQL enum containing the requested finite state set: `DRAFT`, `MEDIA_READY`, `LANGUAGE_CONFIRMATION`, `TRANSCRIBING`, `SOURCE_REVIEW`, `SOURCE_APPROVED`, `CRAFTING`, `CRAFT_REVIEW`, `CRAFT_APPROVED`, `TRANSLATING`, `TRANSLATION_REVIEW`, `TRANSLATION_APPROVED`, `PRIVACY_REVIEW`, `COVENANT_REVIEW`, `PUBLICATION_REVIEW`, `PUBLISHED`, and `WITHDRAWN`. Unknown states fail at the database boundary; adding future states requires an explicit migration.

The main forward path is:

```text
DRAFT -> MEDIA_READY -> LANGUAGE_CONFIRMATION -> TRANSCRIBING -> SOURCE_REVIEW
-> SOURCE_APPROVED -> CRAFTING -> CRAFT_REVIEW -> CRAFT_APPROVED
-> TRANSLATING -> TRANSLATION_REVIEW -> TRANSLATION_APPROVED
-> PRIVACY_REVIEW -> COVENANT_REVIEW -> PUBLICATION_REVIEW -> PUBLISHED -> WITHDRAWN
```

Rework creates a new artefact version. Historical approvals stay attached to their old target and hash; `artifact_is_latest_approved` checks dependencies before treating an approval as current. Sealing a new version changes the workflow to its affected review stage and changes any active publication access to `STALE` in the same transaction. Per-story row locks serialize artefact, language-review, and publication-snapshot version allocation. Unique constraints still fail closed if a competing workflow bypasses the lock discipline.

`publication_access`, not the story workflow label alone, controls whether a publication may be served. A publication snapshot is immutable and its access record is a separate, constrained state machine.

## Language and duration rules

Language codes are text with a generic language-tag format check, not a PostgreSQL language enum and not hard-coded column equality checks. Proposals may record detected codes and optional confidence. Confirmation is append-only and requires the authenticated storyteller. Workflow triggers currently allow only confirmed `yor`, transcription in `yor`, and translation from `yor` to `eng`; publication snapshots are similarly validated as Yoruba-to-English. These are MVP workflow rules, not structural language-column restrictions.

Database duration checks are general integrity constraints: media and cut durations must be positive; segment end must exceed segment start; timestamps cannot exceed the referenced source media or cut timeline. The recommended hackathon UX guidance remains a 5-15-minute source video and a 90-150-second Story Cut/publication. The server and client should validate these demo ranges, but the database does not enforce them as permanent limits.

## Storage keys and private media

No Storage bucket is created by this migration. `media_assets.bucket_id` and `media_assets.object_key` store storage identifiers rather than public URLs; the object-key constraint rejects URL-shaped values. Suggested future paths are:

- source: `private-source/{owner_id}/{story_id}/{media_artifact_id}/source.ext`
- derived private media: `private-derived/{owner_id}/{story_id}/{artifact_id}/...`
- final publication media: `publications/{publication_public_id}/{snapshot_version}/...`

Use private buckets for source, intermediate, and final objects. Future Storage policies must verify owner/story/path binding for source and derived objects. Final-publication reads must resolve an explicitly active publication and check access on every request; withdrawal must block later reads. Avoid long-lived signed URLs and caches that outlive withdrawal. No database row in this migration stores a public URL.

## Approvals, privacy, and Covenant

`approvals` has two nullable target FKs, a database `CHECK (num_nonnulls(artifact_version_id, publication_snapshot_id) = 1)`, and a separate FK for each target. This bounded polymorphic form is safe here: exactly one target is mandatory, each target must exist in the same story, and unique constraints prevent duplicate decisions for a version/snapshot. The approval trigger requires the approver to equal the story owner, the artefact to be sealed, and the supplied 32-byte hash to match the exact version. Publication approvals bind to the immutable manifest hash. Approval rows cannot be updated or deleted.

AI may propose privacy findings, but cannot resolve them. A storyteller decision is required for each finding in the review being published. Non-KEEP decisions cite a later approved edit version; a subsequent privacy review must still approve the edited cut/translation. `REMOVE` applies to derived/public content and never deletes source media or provenance.

Covenant permissions are versioned and privacy-protective. All ten permissions must be present; absent values cannot silently become allowed. `VOICE_CLONING = true` is rejected. An active Covenant is the latest approved Covenant version. Publishing and public lookup both require explicit `PUBLIC_VIEWING = true` on the active Covenant.

## Publication, public reads, and withdrawal

`publication_snapshots` stores the exact approved source media, transcript, Story Cut, cultural review, English translation, privacy review, Covenant, and final rendered-media artefact. Composite FKs preserve lineage within one story; the manifest SHA-256 and snapshot rows are immutable. A trusted server must calculate the canonical digest and perform the approval and publish transitions transactionally; PostgreSQL checks digest length and equality but does not compute the canonical application hash.

There is no anonymous-readable view. `public.get_published_story(uuid)` is a narrow `SECURITY DEFINER` RPC because PostgreSQL views normally run with their owner's privileges and could bypass base-table RLS. The function has an empty fixed `search_path`, schema-qualifies every object, is executable only by `anon` and `authenticated`, and returns only public ID, title, language codes, AI disclosure flags, and publish time. It requires an exact approved manifest hash; `PUBLISHED` access and story state; the latest snapshot; the active Covenant with explicit public viewing; and successful full snapshot validation. It returns no owner ID, storage key, transcript, privacy finding, or Covenant field. Anonymous and authenticated clients have no base-table grant for private records.

Withdrawal changes only `publication_access` and story state. It removes the record from the public RPC and future media-serving checks, while snapshots, private media metadata, approvals, and audit events remain available to the owner and authorized server workflow. It cannot recall previously downloaded copies.

## Row Level Security and remaining work

RLS is enabled on all 20 tables. Private child tables scope authenticated `SELECT` through `irin_private.user_owns_story(story_id)`, a narrowly granted `SECURITY DEFINER` ownership helper that compares the story owner with `auth.uid()`. `stories` uses `owner_id = auth.uid()` directly. No authenticated insert accepts an unchecked owner ID. Authenticated storytellers can insert only their own privacy decisions and approvals; they can only change a published access row to withdrawn. Most artefact writes occur in trusted server workflows because authenticated clients have no write grants for those tables. `service_role` bypasses RLS and must remain server-side; triggers and constraints still enforce version, ownership, approval, and lineage rules. No base table grants access to `anon`.

Before implementation, add transaction-oriented server operations for sealing and approvals, enforce canonical hashing, and complete the remaining local RLS and publication tests listed in `docs/local-database-test-report.md`. Before any publication feature, add private Storage policies for each object class and test every public page/media/subtitle request after withdrawal. Further local execution validation remains required before any separately authorized remote migration push.

Local replay was subsequently confirmed by catalog query on 2026-11-10 (20 public tables; RLS enabled on all 20). Runtime verification of cross-story lineage, approval integrity, a full valid synthetic publication, actual RPC output, and withdrawal retention remains open; see `docs/local-database-test-report.md`.

The requested cross-story, approval-integrity, valid-publication/RPC, and withdrawal tests remain runtime-unverified. Current local DB has no synthetic users or stories. Do not treat the composite constraints, target check, trigger definitions, or RPC return declaration as proof of those behaviors; see `docs/local-database-test-report.md`.

## Local runtime integration evidence

The repeatable rollback-only synthetic harness at `supabase/tests/irin_stories_foundation_test.sql` executed twice against the local PostgreSQL database. It passed cross-story lineage and approval-integrity rejection cases, created and returned one complete publication through the anonymous RPC with exactly seven public fields, then verified withdrawal removed public visibility while private snapshot, approvals, Covenant, source lineage, and audit history remained. The full result matrix and database errors are in `docs/local-database-test-report.md`. No production migration change was needed.
