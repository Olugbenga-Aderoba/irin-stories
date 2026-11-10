# Irin Stories

## Purpose and brand

Irin Stories is a creator-controlled AI storytelling studio that helps African storytellers transform authentic stories told in their own languages into culturally faithful, multilingual, publication-ready digital stories.

**Brand:** Irin Stories  
**Tagline:** African voices, across every border.

**Core principle:** AI proposes. The storyteller decides.

In this project, “verified” describes completion of the required approval, privacy, covenant, and provenance checks. It is not a judgment about whether a storyteller or story is truthful.

## Core workflow

**Tell -> Verify -> Craft -> Translate -> Protect -> Publish**

## Hackathon MVP

The prototype supports:

- One authenticated storyteller.
- One private 5 to 15-minute Yoruba source video.
- Yoruba speech transcribed into Yoruba.
- Storyteller correction and approval of the Yoruba transcript.
- An explainable 90 to 150-second Story Cut.
- Storyteller-controlled clip selection, rejection, and ordering.
- Cultural-expression review.
- Storyteller-approved English subtitles.
- Sensitive-information review.
- A versioned Story Covenant.
- A verified multilingual publication that satisfies the approval and provenance requirements in this file.
- Storyteller-controlled withdrawal after publication.

For the hackathon MVP, Yoruba is the only supported and demonstrated original language; English subtitles are the approved translation output, and English is the only functional share language. “Multilingual publication” refers to this Yoruba-to-English workflow; other languages are not supported in the MVP.

The product UX does not require the storyteller to choose an original language before recording or uploading. The system proposes an automatically detected original language, but that proposal is never authoritative by itself: the storyteller must confirm or correct it before transcription. Only a confirmed Yoruba original can proceed to transcription in this MVP. The storyteller chooses a share language through a selector designed for future expansion; English is the only available option, and other languages must not be presented as currently supported.

## Product invariants

These rules must never be bypassed:

1. `NO_AI_OUTPUT_IS_PUBLISHABLE_WITHOUT_HUMAN_APPROVAL`
2. `CRAFT_REQUIRES_APPROVED_SOURCE`
3. `TRANSLATION_REQUIRES_APPROVED_STORY_CUT`
4. `SOURCE_CHANGE_INVALIDATES_DEPENDENTS`
5. `PRIVACY_REVIEW_REQUIRED_FOR_PUBLICATION`
6. `ACTIVE_COVENANT_REQUIRED_FOR_PUBLICATION`
7. `WITHDRAWN_PUBLICATION_MUST_NOT_SERVE_MEDIA`
8. `EVERY_PUBLISHED_CLIP_MUST_TRACE_TO_APPROVED_SOURCE_TIMESTAMPS`
9. `EVERY_TRANSLATION_MUST_TRACE_TO_AN_APPROVED_SOURCE_VERSION`

Enforce these invariants in server-side workflow logic and preserve the evidence needed to audit approvals, state transitions, and source-to-derivative provenance. Do not weaken an invariant to make implementation or tests easier.

## Content and safety rules

- Never infer whether a storyteller is truthful.
- Never create a truth, credibility, or emotional-authenticity score.
- Never create synthetic reconstructions presented as real events.
- Never clone the storyteller's voice.
- Never automatically remove sensitive information.
- AI may recommend privacy actions, but the storyteller decides.
- The storyteller must approve editorial cuts, cultural meaning, translations, privacy decisions, and final publication.
- Original source media must be private by default.
- Background music, supplied photographs, and contextual material require storyteller approval.
- Published stories must disclose AI-assisted editing and translation.
- AI-generated editorial suggestions must never silently alter the storyteller's meaning.

## Technical direction

Use the following technologies and controls for future implementation work:

- Next.js App Router.
- TypeScript strict mode.
- Supabase PostgreSQL, Supabase Auth, and private Supabase Storage.
- Zod validation for external data and AI-generated structured data.
- Server-side workflow enforcement.
- Supabase Row Level Security (RLS).
- Versioned story artefacts.
- Auditable approvals and state transitions.
- Vitest for critical business logic.
- Playwright for end-to-end workflow testing.

Secrets and privileged credentials must remain server-side.

## Out of scope for the hackathon

Do not add:

- Multiple source languages.
- Blockchain.
- Payments.
- A creator marketplace.
- A social-media feed.
- Advanced video filters.
- Synthetic B-roll.
- AI avatars.
- Voice cloning.
- Hospital integrations.
- Government integrations.
- Native mobile applications.

## Development rules for future Codex tasks

For every future implementation task:

1. Read `AGENTS.md` first.
2. Inspect the existing repository before changing code.
3. Implement one bounded feature or vertical slice at a time.
4. Do not broaden scope without explicit instruction.
5. Do not weaken product invariants to make tests pass.
6. Validate external and AI-generated structured data.
7. Add automated tests for critical behaviour.
8. Run lint, typecheck, and relevant tests after changes.
9. Explain important database migrations and security changes.
10. Preserve traceability between source media and derived artefacts.
11. Report files changed, tests added, commands run, and known limitations.
12. Stop after completing the requested task.

## Codex build evidence

For future development work, maintain a record in `docs/codex-build-log.md` containing, where applicable:

- Task requested.
- Codex prompt or task summary.
- Files changed.
- Tests created.
- Test failures encountered.
- Diagnosis.
- Final fix.
- Human review decision.
- Known limitations.

Do not create the build log as part of the initial `AGENTS.md` setup task. Create or update it for future development work when applicable.

<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
