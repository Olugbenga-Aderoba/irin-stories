# Irin Stories Hackathon MVP Implementation Plan

## Purpose and fixed scope

This document defines the implementation sequence and release gates for the hackathon MVP. It is a plan only: it does not authorize application changes, package installation, database migrations, or external service integrations.

**Brand:** Irin Stories — African voices, across every border.  
**Core principle:** AI proposes. The storyteller decides.  
**Core workflow:** Tell -> Verify -> Craft -> Translate -> Protect -> Publish.

The MVP is limited to one authenticated storyteller, one story, one private 5 to 15-minute Yoruba source video, Yoruba transcription and approval, one explainable 90 to 150-second Story Cut, Yoruba cultural-expression review, English as the only target language, storyteller-approved English subtitles, sensitive-information review, one versioned Story Covenant, one active verified multilingual publication, and storyteller-controlled withdrawal. A source replacement is a new version in the same lineage, not a second source story.

Here, “multilingual publication” means the Yoruba source with storyteller-approved English subtitles; Yoruba is the only source language and English is the only target language.

Background music, supplied photographs, and contextual material are not required for the MVP; if any are introduced, they require explicit storyteller approval before use. Never create synthetic reconstructions presented as real events or clone the storyteller's voice. Never infer truthfulness or create truth, credibility, or emotional-authenticity scores.

For workflow purposes, the **approved source package** is the immutable source-video version together with the storyteller-approved Yoruba transcript version for that video. Craft requires approval of that exact package. “Verified publication” means that approvals, privacy decisions, covenant status, and provenance checks pass; it is not a judgment about truthfulness.

Every approval must bind to an immutable artifact version and content hash. Editing or replacing an artifact creates a new version; it must not silently carry forward an approval. A changed source video or approved Yoruba transcript invalidates dependent cuts, cultural reviews, translations, privacy resolutions that refer to those artifacts, and publication eligibility. If a currently published snapshot depends on a changed or superseded artifact (including the active Covenant), take it out of public serving before accepting the change; retain the immutable snapshot and history privately. A new snapshot must pass all gates before serving again.

The following `AGENTS.md` invariants are release gates throughout this plan:

1. `NO_AI_OUTPUT_IS_PUBLISHABLE_WITHOUT_HUMAN_APPROVAL`
2. `CRAFT_REQUIRES_APPROVED_SOURCE`
3. `TRANSLATION_REQUIRES_APPROVED_STORY_CUT`
4. `SOURCE_CHANGE_INVALIDATES_DEPENDENTS`
5. `PRIVACY_REVIEW_REQUIRED_FOR_PUBLICATION`
6. `ACTIVE_COVENANT_REQUIRED_FOR_PUBLICATION`
7. `WITHDRAWN_PUBLICATION_MUST_NOT_SERVE_MEDIA`
8. `EVERY_PUBLISHED_CLIP_MUST_TRACE_TO_APPROVED_SOURCE_TIMESTAMPS`
9. `EVERY_TRANSLATION_MUST_TRACE_TO_AN_APPROVED_SOURCE_VERSION`

## 0. Foundation

### 1. User outcome

The single storyteller can sign in, see a private empty workspace, and start one draft story. No media is processed or published in this stage.

### 2. User interface

- Sign-in, sign-out, and session-expired states.
- A private story workspace with an empty state and a “Start story” action.
- A small persistent workflow-status area that will show the current stage and outstanding approvals.
- The storyteller decides whether to create the draft. There is no public profile, feed, or discovery interface.

### 3. Application logic

- **Client:** render authenticated states, submit only user-editable story metadata, and display server-returned workflow state.
- **Server:** obtain identity from the authenticated session; create the story with that user as owner; authorize every read and write; validate all state changes server-side. Never trust a client-supplied owner ID, approval flag, artifact status, or publication state.
- Define typed workflow and artifact states before implementing stage transitions. Keep secrets and service-role credentials server-side.

### 4. Data requirements

- Store the Supabase Auth user ID as the story owner; a separate storyteller-profile table is unnecessary unless profile fields become required.
- Store a story ID, owner ID, creation time, and initial workflow state.
- No media or derived artifact exists yet. Subsequent artifact versions and approval records must be append-only or otherwise immutable.
- Record story creation and state transitions in the audit history without copying sensitive story content into logs.

### 5. Workflow states

- **Requires:** no story for the signed-in user.
- **Creates:** `TELL_READY` for a private draft.
- Creating a story invalidates no downstream approvals. An unauthenticated or non-owner request creates no state.

### 6. External services

- **Supabase:** eventually provides Auth, PostgreSQL, RLS, and a private Storage bucket. This stage establishes the server-side access pattern; migrations and service integration are future implementation work.
- **OpenAI APIs:** not required in Foundation.
- **FFmpeg:** not required in Foundation.

### 7. Security and privacy

- Require authentication for the workspace and owner authorization for every story operation.
- Apply RLS to all owner-scoped tables from their introduction. Default-deny private media access; do not create public buckets.
- Keep credentials server-side. Do not put tokens, story content, or private URLs in client logs or analytics.

### 8. AI responsibility

- AI proposes nothing in Foundation and cannot create or approve a story, grant access, or change workflow state.
- Before any later external AI processing, the storyteller must receive a clear disclosure and explicitly approve that processing.

### 9. Testing

- **Unit:** workflow-state transition and owner-ID validation helpers.
- **Integration:** authenticated story creation, RLS owner isolation, and rejection of unauthenticated or forged-owner writes.
- **Playwright:** sign in, create a draft, sign out, and confirm the private workspace cannot be opened unauthenticated.
- **Failure/adversarial:** expired session, forged owner ID, direct request for another user’s story, and attempted client-side state escalation.

### 10. Acceptance criteria

- One authenticated storyteller can create and reopen the single private MVP story; a second story is rejected. An unauthenticated user cannot access it.
- The server derives ownership from the session and RLS rejects cross-owner access.
- No media, AI calls, or publication are available in this state.

## 1. Tell

### 1. User outcome

The storyteller uploads one private Yoruba source video approximately 5 to 15 minutes long and sees that the source is safely received and ready for transcription.

### 2. User interface

- A source upload screen with supported-format/size guidance, progress, retry, and clear validation errors.
- A private source preview with duration and upload status.
- The storyteller confirms that the recording is Yoruba and chooses the source file. The client may preflight duration, but the server’s inspection is authoritative.

### 3. Application logic

- **Client:** upload to a narrowly scoped owner/story path with progress and interruption recovery. Do not expose a public object URL.
- **Server:** authorize upload; verify object ownership, media type, stream presence, actual duration, and integrity after upload. Mark invalid uploads rejected. Never overwrite source bytes in place; replacement creates a new source version and invalidates dependents.
- Agree the supported codecs and maximum file size before implementation; duration is bounded by the MVP. Do not treat browser-provided metadata as authoritative.

### 4. Data requirements

- Create a source-media artifact version with private storage key, owner/story IDs, checksum, byte size, MIME type, duration, stream metadata, and creation time.
- Preserve the source media as the original. Store frame rate/timebase and stream start metadata needed to map later edits to exact source timestamps.
- Keep rejected upload records or audit events, but do not retain unusable media longer than the defined cleanup policy.

### 5. Workflow states

- **Requires:** `TELL_READY` and an authenticated owner.
- **Creates:** `SOURCE_RECEIVED` after server validation; otherwise remain in `TELL_READY` with a rejection reason.
- A replacement source creates a new source version and marks transcript, cut, translation, privacy resolution, and publication descendants stale. If a publication is active, take it out of public serving before accepting the replacement. No approval follows the source automatically.

### 6. External services

- **Supabase:** Auth and RLS authorize upload; private Storage holds the original; PostgreSQL records metadata and status.
- **OpenAI APIs:** not used for upload or validation.
- **FFmpeg:** eventually use `ffprobe` (distributed with FFmpeg) in an isolated worker to inspect actual streams and duration. Do not run long media jobs inside a short web request.

### 7. Security and privacy

- Original media is private by default and owner-scoped in both database policy and Storage policy.
- Use short-lived, path-scoped upload authorization only for uploading; never make the source object public.
- Show where the source will be stored and, before transcription, disclose the separate external AI-processing step and obtain explicit approval.

### 8. AI responsibility

- AI has no role in accepting, rejecting, or changing the uploaded source.
- No tool may infer truthfulness, credibility, or emotional authenticity from the recording.
- Human approval of the corrected transcript is required before the source package is approved for Craft.

### 9. Testing

- **Unit:** duration boundaries, MIME/stream validation, checksum handling, and source-version creation.
- **Integration:** private upload/read policies, owner-scoped paths, metadata persistence, and failed-upload cleanup.
- **Playwright:** valid upload and preview; invalid duration/type is rejected with a useful message; interrupted upload can resume or restart safely.
- **Failure/adversarial:** spoofed MIME type, truncated file, unexpected streams, oversized file, cross-owner upload path, and in-place replacement attempt.

### 10. Acceptance criteria

- A valid 5 to 15-minute Yoruba source is stored privately and is visible only to its owner.
- Server-verified metadata and a stable source version are recorded.
- Invalid media cannot proceed to Verify, and replacing the source does not preserve downstream approvals.

## 2. Verify

### 1. User outcome

The storyteller reviews, corrects, and explicitly approves a Yoruba transcript for the exact uploaded source video.

### 2. User interface

- A transcript review screen pairing source playback/seek controls with timecoded Yoruba text.
- The storyteller can correct wording, adjust a segment boundary, save a draft, and approve the complete transcript version.
- Show that transcription is AI-generated and approval is still required. The approval action identifies the exact version being approved.

### 3. Application logic

- **Client:** edit transcript draft fields and display their source timestamps. No client action can mark a transcript approved.
- **Server:** require accepted external-processing consent before sending audio; extract audio; call the transcription provider; validate structured output with Zod; store the output as an unapproved draft. Corrections create a new immutable transcript version. Approval pins a content hash and exact source-video version.
- Treat the approved source package as source-video version plus approved Yoruba transcript version. Do not allow Craft from an unapproved or stale transcript.

### 4. Data requirements

- Store versioned transcript segments with Yoruba text and source start/end positions. Each segment references its transcript version and exact source-video version.
- Preserve original machine output, human corrections, timestamps, language, provider/model metadata, and the approval event. Avoid storing API secrets or unnecessary raw audio copies.
- If the source video changes, all transcript versions based on it become stale. A new transcript version needs a new approval.

### 5. Workflow states

- **Requires:** `SOURCE_RECEIVED`, owner approval for external processing, and a valid source asset.
- **Creates:** `TRANSCRIPT_DRAFT` while machine output or corrections are pending; `SOURCE_APPROVED` only after human approval of the exact transcript/source pair.
- Editing a transcript after approval creates a draft version and removes current approval eligibility. Replacing the video invalidates all transcripts for Craft. If an approved-source change affects an active publication, mark that publication non-serving before accepting the change.

### 6. External services

- **Supabase:** private source/audio storage, versioned transcript records, approval records, and RLS.
- **OpenAI APIs:** eventually provide Yoruba speech-to-text. Evaluate Yoruba accuracy and timestamp quality on consented, representative recordings before selecting a model; never assume API support implies adequate quality.
- **FFmpeg:** extract an audio track from the private source in an isolated worker. Send only the audio needed for transcription, not the full video, unless a documented need arises.

### 7. Security and privacy

- Require owner access for the transcript and source. Keep extracted audio private and delete temporary worker copies after processing according to a documented policy.
- Explain that audio is sent to an external AI service, what is returned, and the applicable retention controls before consent. Do not send media without that consent.
- RLS protects transcript versions and approvals. Provider calls and logs must not expose source content to unrelated users.

### 8. AI responsibility

- AI may propose Yoruba words and timecodes as a draft only.
- AI must never decide that the transcript is accurate, that the storyteller is truthful, or that cultural meaning is correct.
- The storyteller must be able to correct and approve the exact Yoruba transcript before Craft.

### 9. Testing

- **Unit:** Zod schema, timestamp bounds, transcript-version hashing, and approval eligibility.
- **Integration:** mocked transcription responses, consent gate, persistence of machine and corrected versions, and source-version linkage.
- **Playwright:** inspect, edit, save, and approve a transcript; confirm an edit after approval requires reapproval.
- **Failure/adversarial:** malformed provider response, missing/overlapping/out-of-range timestamps, provider timeout, duplicate callback, no processing consent, and stale transcript after source replacement.

### 10. Acceptance criteria

- Every transcript segment falls within the exact source media timeline and is linked to its video version.
- Craft is blocked until a human approves the exact corrected transcript/source pair.
- AI output remains visibly a draft until that approval; provider failure leaves the source private and retryable.

## 3. Craft

### 1. User outcome

The storyteller creates one explainable 90 to 150-second Story Cut, selects, rejects, and orders candidate clips, reviews Yoruba cultural expression, and approves the final cut.

### 2. User interface

- A timeline editor with source preview, candidate clips, exact source in/out points, resulting cut order, and total rendered duration.
- Each AI suggestion includes its source time range and a plain-language editorial reason. The storyteller can select, reject, trim, reorder, and preview clips.
- A Yoruba cultural-expression review panel anchors notes/questions to exact transcript or video time ranges. The storyteller supplies or confirms cultural meaning and approves the review and cut.

### 3. Application logic

- **Client:** edit a proposal and render a preview; display source and output timelines distinctly.
- **Server:** reject any craft request without the currently approved source package; validate clip boundaries against the source timebase, reject excluded/rejected segments from the final edit decision list, calculate total duration from selected clips, and create a new cut version for every changed selection/order.
- Render only the approved edit decision list. Preserve the mapping from every output interval to its exact source interval. Never silently change text, clip order, or meaning.

### 4. Data requirements

- Each Story Cut version references the exact approved video and transcript versions.
- Each segment stores source start/end in milliseconds and authoritative source presentation timestamps/timebase or equivalent frame boundaries; also store order and output-timeline start/end. Link to the transcript segment(s) used to explain the selection.
- Preserve suggested, selected, and rejected decisions and explanations in the draft history. The final cut contains only storyteller-selected segments.
- Store a versioned cultural review with anchored annotations, storyteller meaning/decision, approval, render checksum, and source map.

### 5. Workflow states

- **Requires:** `SOURCE_APPROVED` for the current video/transcript pair.
- **Creates:** `CUT_DRAFT`, then `CULTURAL_REVIEW_APPROVED` and `CUT_APPROVED` after the storyteller approves the exact cut and review.
- Any source, transcript, selected segment, trim, ordering, cultural-review, or rendered-content change creates a new version and invalidates the cut approval and downstream translation/privacy/publication eligibility.

### 6. External services

- **Supabase:** persist cut/review versions, approvals, private previews, and render metadata.
- **OpenAI APIs:** may propose timecoded editorial candidates and questions for cultural-expression review. Use structured output validated by Zod.
- **FFmpeg:** eventually render selected source ranges into the cut and generate previews. Use a worker and verify the rendered timeline against the stored source map; do not assume requested seek points equal actual frame boundaries.

### 7. Security and privacy

- Cut proposals, source previews, cultural notes, and renders remain private until publication.
- RLS checks owner access; workers accept only authorized artifact IDs and private storage keys issued server-side.
- Do not expose the original source through preview URLs with broad or long-lived access.

### 8. AI responsibility

- AI may propose clips and explain the signal or transcript passage that prompted a suggestion. It may flag a possible cultural question for the storyteller.
- AI must not decide which clips are selected, whether an expression is culturally correct, what the story means, or how the storyteller feels. Do not create truth, credibility, or emotional-authenticity scores.
- Human approval is required for cultural meaning and the final cut. Rejected clips must never appear in the final render.

### 9. Testing

- **Unit:** duration calculation, source/output time mapping, frame-boundary conversion, and edit-decision validation.
- **Integration:** craft blocked on unapproved source; render manifest contains only selected clips; output duration and source-map metadata match the approved version.
- **Playwright:** select, reject, trim, reorder, review cultural notes, preview, and approve a 90 to 150-second cut.
- **Failure/adversarial:** request craft from an unapproved/stale source, include a rejected segment, use out-of-range or inverted timestamps, exceed duration, tamper with order after approval, and simulate render mismatch/failure.

### 10. Acceptance criteria

- The approved cut is 90 to 150 seconds and its rendered intervals map to exact approved source-video timestamps.
- Every published clip can be traced from snapshot to cut segment to approved source video and transcript versions.
- No rejected segment is rendered; cultural review and cut approval bind to the same immutable version.

## 4. Translate

### 1. User outcome

The storyteller reviews, edits, and approves English subtitles for the approved Story Cut. English is the only target language in the MVP.

### 2. User interface

- A bilingual subtitle editor showing the Yoruba source passage, source video/cut context, proposed English subtitle, and subtitle timing on the cut timeline.
- The storyteller can edit text and timing, review the complete subtitle file in preview, and approve that exact version.
- Clearly mark machine translation as a draft. Do not offer additional target languages.

### 3. Application logic

- **Client:** edit subtitle draft text/timing and preview captions against the cut.
- **Server:** require the current approved Story Cut and its approved source package; call translation only from those versions; validate structure, cue timing, and references with Zod; reject orphaned or mismatched segments. Approval pins the subtitle artifact hash and all parent version IDs.
- Publish only captions whose source, transcript, cut, and translation versions are still current and approved.

### 4. Data requirements

- Store versioned English translation segments with cue start/end on the cut timeline.
- Every segment explicitly references the exact approved Yoruba transcript version, source-video version, source transcript segment, approved cut version, and cut segment from which it was derived.
- Preserve machine draft, human edits, approval, content hash, and provider/model metadata. A correction creates a new version.

### 5. Workflow states

- **Requires:** `CUT_APPROVED` and `CULTURAL_REVIEW_APPROVED` for the current approved source package.
- **Creates:** `TRANSLATION_DRAFT`, then `TRANSLATION_APPROVED` only after human approval of the exact English subtitle version.
- A source video, approved Yoruba transcript, Story Cut, or referenced cut-segment change invalidates dependent translation approval. A changed translation requires reapproval.

### 6. External services

- **Supabase:** store translation versions, segment references, approvals, and private caption previews.
- **OpenAI APIs:** eventually propose English translations from approved Yoruba transcript/cut context. Validate all structured responses; select a model only after Yoruba-to-English quality review.
- **FFmpeg:** not required to translate. Use a WebVTT sidecar for captions; final assembly/rendering is handled at Publish or when an approved privacy edit changes the cut.

### 7. Security and privacy

- Translation drafts and source text remain owner-only. Do not expose private Yoruba transcript text in public metadata or logs.
- Send only the approved source text/context necessary for translation, and only after external-processing consent. Protect API credentials server-side.
- RLS prevents access to another storyteller’s translation or source references.

### 8. AI responsibility

- AI may propose English subtitle text and timing based on the approved Yoruba source and cut.
- AI must not decide cultural meaning, silently rewrite the storyteller’s intent, or approve/publish a translation.
- The storyteller must review and approve every final translation version.

### 9. Testing

- **Unit:** segment schema, cue bounds/order, version-reference consistency, and invalidation rules.
- **Integration:** mocked translation response, exact parent-version persistence, stale-parent rejection, and approval hash checks.
- **Playwright:** edit and approve English subtitles; preview captions; confirm translation status changes if its source/cut changes.
- **Failure/adversarial:** malformed response, mismatched transcript/source IDs, cue outside cut, untranslated/empty segment handling, source change after approval, and attempted approval of a stale translation.

### 10. Acceptance criteria

- English is the sole target language and subtitles align to the approved cut timeline.
- Every subtitle segment traces to the exact approved Yoruba source/transcript version and approved cut segment.
- No stale, unapproved, or AI-only translation can be published.

## 5. Protect

### 1. User outcome

The storyteller reviews potential sensitive-information concerns, decides Keep, Generalise, Anonymise, or Remove for each finding, confirms any resulting edits, and accepts one version of the Story Covenant.

### 2. User interface

- A private finding queue with time/location, a minimally exposed excerpt, why it was flagged, and exactly four explicit decisions: **Keep**, **Generalise**, **Anonymise**, **Remove**.
- Show the effect of a decision on the cut and subtitles. The storyteller applies and reviews any edit; no action is preselected.
- A Story Covenant screen presents the version, processing/publication scope, AI-assisted editing/translation disclosure, rights/consent terms, and withdrawal explanation. The storyteller accepts the exact version.

### 3. Application logic

- **Client:** display findings and collect one human decision per finding; collect human edits separately from AI suggestions.
- **Server:** create a versioned privacy review; block readiness while any finding lacks a human decision or required resolution. “Keep” is an explicit decision to retain the referenced content. For Generalise/Anonymise/Remove, require the storyteller to make and approve the corresponding edit in a new cut/translation version; never apply the edit automatically.
- If a privacy edit changes the cut or subtitles, return to Craft or Translate as needed, create new versions, re-run relevant reviews, and invalidate old downstream approvals. Activate the exact Covenant version only after the storyteller accepts it.

### 4. Data requirements

- Store a versioned privacy review and findings anchored to source timestamps, transcript segments, cut segments, or subtitle segments; include the AI flag, minimal rationale/category, storyteller disposition, resolution artifact/version, and human resolver/approval.
- Do not duplicate raw sensitive content in audit logs. Keep original source private and immutable; removal means exclusion from the derived/public version, not erasure of provenance without a separately approved retention policy.
- Store the versioned Story Covenant text/structured terms, accepted-by user, accepted timestamp, content hash, and active/superseded status. At most one version is active for publication.

### 5. Workflow states

- **Requires:** current approved cut, cultural review, and translation.
- **Creates:** `PRIVACY_REVIEW_PENDING`; on complete human disposition and required approved edits, `PRIVACY_RESOLVED`. Covenant acceptance creates `COVENANT_ACTIVE` for that version.
- Any changed cut, subtitle, source, or relevant finding reopens privacy review and invalidates resolutions tied to prior content. A new Covenant version supersedes the prior active version and requires explicit acceptance.

### 6. External services

- **Supabase:** persist private findings, decisions, review versions, Covenant versions, approvals, and audit events.
- **OpenAI APIs:** may identify potential privacy concerns in approved transcript/cut/subtitle text and return timecoded flags. They do not decide disposition or modify any artifact.
- **FFmpeg:** not required for detection or decisions. It is required again only if a storyteller-approved video edit changes the rendered cut.

### 7. Security and privacy

- Findings may themselves contain sensitive details; owner-only RLS, minimal excerpts, private storage, and redacted logs are mandatory.
- Explain external processing and data handling. Do not send content for privacy analysis without consent.
- “Remove” from a public cut must not accidentally delete the private original or audit/provenance records. Access to all source material remains private.

### 8. AI responsibility

- AI may identify a potential concern and its location, with a concise reason. It must not assign a truth/credibility score, determine that publication is safe, select one of the four dispositions, or alter content.
- Only the storyteller decides Keep, Generalise, Anonymise, or Remove for each finding and approves each resulting edit and final review.
- Unresolved findings always block publication; the system never silently clears a finding.

### 9. Testing

- **Unit:** disposition enum, unresolved-finding gate, dependency invalidation, and Covenant activation rules.
- **Integration:** every finding must have a human decision; required edited versions and approvals must match; only one Covenant version can be active.
- **Playwright:** review each finding, exercise all four choices, edit where required, accept a Covenant version, and see readiness update.
- **Failure/adversarial:** omitted finding decision, stale privacy review after cut/translation edit, AI response attempting to choose a disposition, Covenant changed after acceptance, and publication attempt with an unresolved finding.

### 10. Acceptance criteria

- Every finding has an explicit storyteller decision; Generalise/Anonymise/Remove decisions are reflected in separately approved derived artifacts.
- No privacy action is automatic, and the private original plus audit history remain intact.
- A single exact Covenant version is active and accepted before publication readiness.

## 6. Publish

### 1. User outcome

The storyteller reviews a final preview and publishes one verified Yoruba-to-English story with approved subtitles, an AI-assisted editing/translation disclosure, and a stable public page.

### 2. User interface

- A private publication checklist and final preview naming the exact source, cut, translation, privacy review, and Covenant versions.
- The storyteller makes the final publish decision explicitly.
- A single public story page serves only the approved cut and English captions, shows the required disclosure, and offers no feed or marketplace features.

### 3. Application logic

- **Client:** show status from the server and submit a publish request; never construct the authoritative snapshot.
- **Server:** in one transaction, recheck ownership, exact current versions, required human approvals, cultural review, resolved privacy findings, active Covenant, and clip/source mappings. Create an immutable snapshot manifest with version IDs and hashes, then activate a publication pointer/event. Fail closed on any mismatch.
- Serve public media through a server-controlled route that checks publication state on every request/range request. Do not expose the private Storage object or use long-lived signed URLs/CDN caching that can outlive withdrawal.

### 4. Data requirements

- Create an immutable `publication_snapshot` referencing the exact source-video version, approved Yoruba transcript, cultural review, Story Cut, English translation, resolved privacy review, active Covenant, rendered media, subtitle file, disclosures, and content hashes.
- Store snapshot version, creation time, and manifest hash. Store mutable access state separately from the immutable snapshot, with append-only publish/withdraw audit events.
- A later content change creates a new snapshot; it never edits the published snapshot in place.

### 5. Workflow states

- **Requires:** current `CUT_APPROVED`, `CULTURAL_REVIEW_APPROVED`, `TRANSLATION_APPROVED`, `PRIVACY_RESOLVED`, and `COVENANT_ACTIVE`, all referencing compatible current versions.
- **Creates:** `PUBLISH_READY` after validation, then `PUBLISHED` only after the immutable snapshot and access record commit successfully.
- Any source or derived-content change makes the old snapshot non-serving and ineligible for publication; its contents remain immutable in private history. A republish requires a newly verified snapshot.

### 6. External services

- **Supabase:** transactional state/snapshot records, RLS, private media storage, and server-side publication access checks.
- **OpenAI APIs:** no new AI decision is required at Publish. All AI-assisted editing and translation already used must be disclosed.
- **FFmpeg:** eventually assemble the approved cut after privacy rework if needed, verify output against the approved edit decision list, and produce the private publication render. Serve captions as a referenced WebVTT file.

### 7. Security and privacy

- Original sources and all drafts remain in private storage. Public requests may access only the active published render and captions after a fresh state check.
- RLS protects owner data. Public route logic is server-side and narrowly allowlisted; no service-role secret reaches the browser.
- Disable cache/CDN storage for gated media responses. Support range requests only through the access-checking route. Record publication and access transitions without logging sensitive content.

### 8. AI responsibility

- No AI may publish, approve final editorial content, clear privacy findings, or accept the Covenant.
- Publication requires human approvals for transcript/source, cut, cultural review, translation, privacy choices, Covenant, and final publication.
- The public page must disclose AI-assisted editing and translation.

### 9. Testing

- **Unit:** publication eligibility predicate, manifest construction, immutable hash, and version-compatibility checks.
- **Integration:** transaction rollback on any failed prerequisite, snapshot immutability, private-object access control, and public route allowlist.
- **Playwright:** complete final checklist, publish once, open public page, verify English captions/disclosure, and confirm no source/draft URLs are exposed.
- **Failure/adversarial:** each missing approval, stale parent version, unresolved finding, inactive Covenant, rejected segment, forged snapshot reference, direct storage URL, duplicate publish request, and render hash mismatch.

### 10. Acceptance criteria

- The server refuses publication unless every required invariant passes against the same exact versions.
- The immutable snapshot contains the approved source, Story Cut, translation, resolved privacy review, and active Covenant, plus cultural review, render, captions, disclosure, and hashes.
- Public access returns only approved publication media, and the page discloses AI-assisted editing and translation.

## 7. Withdraw

### 1. User outcome

The storyteller can withdraw the public story while keeping private source media, approved versions, and audit/provenance history.

### 2. User interface

- An owner-only published-story control with a clear withdrawal confirmation and explanation of public-access effects.
- After confirmation, show `WITHDRAWN` and retain private access to the storyteller’s own history. Do not offer automatic deletion as part of withdrawal.

### 3. Application logic

- **Client:** request withdrawal and reflect server-confirmed status only.
- **Server:** atomically mark the publication inactive and append a withdrawal event before acknowledging success. Public page, media, and subtitle routes must deny new requests after that transaction. Abort active streams where the serving architecture permits; never create a new public URL to the withdrawn snapshot.
- Preserve immutable snapshot and provenance. Republish, if later requested and all gates pass, through a new verified snapshot.

### 4. Data requirements

- Record withdrawal actor, time, publication snapshot ID, and state transition in append-only audit history.
- Keep source media, transcript, cuts, translations, privacy decisions, Covenant, approvals, and snapshot privately available to the owner under existing retention policy.
- Do not mutate the snapshot contents or erase audit events as a side effect of withdrawal.

### 5. Workflow states

- **Requires:** `PUBLISHED` and an authenticated owner.
- **Creates:** `WITHDRAWN` after access revocation and audit write commit.
- No downstream approval is restored by withdrawal. Republishing requires a new publication snapshot and a fresh check of every prerequisite.

### 6. External services

- **Supabase:** update publication access state and append withdrawal event; private Storage retains source and provenance.
- **OpenAI APIs:** not required.
- **FFmpeg:** not required.

### 7. Security and privacy

- Withdrawal is owner-authorized and fail-closed. Check current state for every page, media-range, and subtitle request; do not cache a public response or rely on revoking a long-lived signed URL.
- Keep private owner access separate from public access. Restrict the withdrawal endpoint against CSRF/replay and audit the transition.
- A copy already downloaded by a viewer cannot be recalled. The application must stop serving new bytes after withdrawal and abort active streams as promptly as its architecture allows; disclose this limit to the storyteller.

### 8. AI responsibility

- AI has no role in deciding whether to withdraw or in reactivating a publication.
- The storyteller alone decides to withdraw. No AI process may republish or change the withdrawal state.

### 9. Testing

- **Unit:** allowed state transitions and owner authorization.
- **Integration:** withdrawal commits before route access, private artifacts remain accessible to their owner, and public state checks fail closed.
- **Playwright:** withdraw a published story, refresh the public page, request media and subtitles, and confirm the owner still sees private history.
- **Failure/adversarial:** non-owner withdrawal, stale cached page, direct old media URL, byte-range request after withdrawal, repeated withdrawal, concurrent publish/withdraw, and attempt to modify the snapshot.

### 10. Acceptance criteria

- After the withdrawal transaction commits, new public page, media, range, and caption requests are denied; active streams are stopped where supported.
- Private source, derivatives, approvals, snapshot, and audit history remain available only to the owner/authorized server processes.
- Any later publication requires a new snapshot and full validation. Previously downloaded external copies are documented as unretractable.

## 8. Adversarial testing and evaluation

### 1. User outcome

The storyteller receives a workflow that fails safely when state, ownership, provenance, privacy, Covenant, or publication data is missing or tampered with. This stage is a release gate, not a new product capability.

### 2. User interface

- No new production screen. Provide automated Playwright flows, seeded test fixtures, and a concise pass/fail release report.
- Test actors make normal storyteller decisions in UI tests; reviewers decide whether failures block release.

### 3. Application logic

- Exercise the same server transitions and media routes used by the product; do not test only client visibility.
- Seed state through test-only helpers. Keep adversarial test setup unavailable in production and verify each rejected action leaves no partial approval/publication state.

### 4. Data requirements

- Use synthetic accounts, source videos, transcripts, and personal-information examples. Never place real storyteller media in fixtures.
- Record test run, case ID, expected/actual result, and artifact IDs without copying sensitive fixture content into logs.
- Include immutable approved-version hashes and deliberate stale/tampered variants.

### 5. Workflow states

- **Requires:** isolated test environment with fixtures for each major state, including rejected, stale, unresolved, published, and withdrawn.
- **Creates:** a release-gate result (`PASS` or `BLOCKED`), not a product workflow state.
- Tests must prove source changes invalidate dependents; failed transitions create no downstream approval. Tampering with immutable artifacts or snapshots must fail.

### 6. External services

- **Supabase:** use a local or isolated test project with test-only Auth users, RLS, and private Storage policies.
- **OpenAI APIs:** stub deterministic outputs by default. Any later contract test uses non-sensitive fixtures and explicit test credentials; never use production media.
- **FFmpeg:** run a bounded isolated worker against synthetic fixtures and verify timestamp-to-output mapping. Do not use production media in evaluation.

### 7. Security and privacy

- Verify cross-user isolation through both database and Storage APIs; test that service credentials cannot escape server-only code.
- Ensure logs, errors, public HTML, and manifests do not expose source URLs, private transcript text, secrets, or unresolved sensitive details.
- Run all adversarial cases against the actual RLS and public media access paths, not mocks alone.

### 8. AI responsibility

- Use deterministic AI fixtures to confirm the server treats all AI results as drafts and never as approvals or privacy decisions.
- Do not evaluate truthfulness, credibility, emotion, or cultural authenticity as model metrics. Human reviewers evaluate whether the workflow preserves storyteller control.

### 9. Testing

- **Unit:** invariant/state-transition matrix, version ancestry checks, snapshot hash verification, and access-state predicate.
- **Integration:** RLS and private Storage policies; server route state checks; transaction rollback; OpenAI schema validation; FFmpeg source-map verification.
- **Playwright:** full Tell-to-Publish journey, subsequent withdrawal journey, and observable user recovery from provider/worker failures.
- **Required failure/adversarial cases:**
  1. Craft from an unapproved source.
  2. Publish a rejected video segment.
  3. Publish an outdated English translation after the Yoruba source changes.
  4. Publish with unresolved privacy findings.
  5. Publish without an active Story Covenant.
  6. Access another storyteller’s private media.
  7. Access withdrawn public media, including range and caption requests.
  8. Tamper with a publication snapshot or its referenced artifact/hash.
- Also test malformed AI data, out-of-range timestamps, duplicate jobs, request forgery, and concurrent state transitions.

### 10. Acceptance criteria

- All eight required adversarial cases fail safely in unit/integration coverage and relevant end-to-end flows.
- No test can publish without human approvals, exact provenance, resolved privacy, and an active Covenant.
- RLS/private Storage and withdrawal checks are exercised against an isolated Supabase environment; failures block release.
- Human review confirms the public output preserves storyteller decisions and required AI disclosure. No automated truth or authenticity evaluation is used.

## A. MVP architecture summary

- **Web application:** Next.js App Router with strict TypeScript. Use server components/actions or route handlers for trusted workflow transitions; keep browser code limited to presentation, upload progress, editing, and explicit human decisions.
- **Identity and records:** Supabase Auth plus PostgreSQL. Every owner-scoped row uses the authenticated user ID and RLS. Server-side workflow checks enforce the same invariants before writes.
- **Media:** private Supabase Storage for original, temporary audio, previews, final cut, and captions. Never expose originals through public object URLs.
- **Media worker:** isolated FFmpeg/ffprobe worker for metadata inspection, audio extraction, and cut rendering. It receives authorized job inputs, writes private outputs, and reports checksums and timestamp maps.
- **AI services:** server-side OpenAI API calls for Yoruba transcription, editorial suggestions, English subtitle proposals, and potential privacy flags. Validate structured outputs with Zod; store model output as draft artifacts. Obtain explicit processing consent before sending media/text.
- **Publication:** immutable, hash-verified snapshot with a separately mutable access state. A no-cache server route checks active state before serving only the approved render/captions. Withdrawal disables subsequent public access.
- No integrations or migrations are created by this plan.

## B. Proposed data-model summary

Use the smallest model that retains ownership, immutable versions, exact lineage, and auditable decisions. Supabase Auth is the storyteller identity; do not duplicate it in a `storytellers` table for the one-user MVP.

1. **`stories`** — owner ID, draft/workflow state, current source package IDs, publication pointer/access state, created/updated timestamps. Enforce one MVP story per storyteller.
2. **`artifact_versions`** — common immutable version registry: story ID, kind, version number, parent/source artifact IDs, status, creator, creation time, content hash. Use it for source, transcript, cultural review, Story Cut, translation, privacy review, Covenant, and rendered media versions.
3. **`media_assets`** — artifact ID, private bucket/key, checksum, MIME type, size, duration, stream/frame rate and timebase metadata.
4. **`transcript_segments`** — transcript artifact ID, source-media artifact ID, segment order, source start/end timestamp, Yoruba text.
5. **`story_cut_segments`** — Story Cut artifact ID, source-media/transcript references, exact source start/end (milliseconds plus authoritative PTS/timebase or frame boundaries), selected/rejected decision, order, output start/end.
6. **`cultural_annotations`** — cultural-review artifact ID, source/cut anchor, storyteller note/decision, and approval lineage.
7. **`translation_segments`** — translation artifact ID, approved source-media and transcript-version IDs, source transcript segment ID, approved cut/cut-segment IDs, cut-timeline cue bounds, English text.
8. **`privacy_findings`** — privacy-review artifact ID, anchored location, potential finding, human disposition (`KEEP`, `GENERALISE`, `ANONYMISE`, `REMOVE`), resolution artifact/version, resolver and time. Unresolved findings block Publish.
9. **`covenant_versions`** — artifact ID, terms/content hash, accepted user/time, and active/superseded state. Enforce at most one active version per story.
10. **`approvals`** — artifact version ID, decision, approver, approved content hash, timestamp, and optional reason. Approval is for a specific immutable artifact, never a mutable story-wide boolean.
11. **`publication_snapshots`** — immutable manifest/version/hash with typed references to the approved source video/transcript, cultural review, cut, translation, privacy review, active Covenant, rendered media, captions, and disclosure.
12. **`audit_events`** — append-only actor, action, state transition, artifact/snapshot IDs, timestamp, and request/job ID. Exclude secrets and unnecessary sensitive content.

The `stories` row holds the current publication snapshot pointer and mutable access state (`PUBLISHED`, `STALE`/non-serving, or `WITHDRAWN`); the snapshot itself remains immutable. Any referenced-artifact or active-Covenant change moves a serving snapshot to `STALE` before the change is accepted. `WITHDRAWN` records storyteller-directed withdrawal; both states deny public media. Child records reference `artifact_versions` with foreign keys. Enforce that all referenced artifacts belong to the same story and that source-version ancestry matches; use constraints/triggers or server transactions where ordinary foreign keys cannot express cross-row rules. Rejected cut proposals may remain in draft history but never enter a final render or publication snapshot.

## C. Workflow/state summary

`TELL_READY -> SOURCE_RECEIVED -> TRANSCRIPT_DRAFT -> SOURCE_APPROVED -> CUT_DRAFT -> CULTURAL_REVIEW_APPROVED + CUT_APPROVED -> TRANSLATION_DRAFT -> TRANSLATION_APPROVED -> PRIVACY_REVIEW_PENDING -> PRIVACY_RESOLVED + COVENANT_ACTIVE -> PUBLISH_READY -> PUBLISHED -> WITHDRAWN`

The state machine must also represent rejected/failed processing, stale artifacts, rework, and retry without implying approval. `SOURCE_APPROVED` is the approved video/transcript pair. Any source or parent-artifact change marks descendants stale; old approvals remain historical but cannot satisfy a current gate. If an active publication references a changed/superseded artifact, it becomes `STALE` and non-serving until a new snapshot passes every gate. `WITHDRAWN` is storyteller-directed and also denies public media; neither state erases the immutable snapshot or private provenance.

## D. Testing strategy

- Use Vitest for pure state transitions, Zod schemas, timestamp math, lineage checks, and publication eligibility.
- Use integration tests against isolated Supabase Auth/PostgreSQL/Storage to prove RLS, private object access, transactional state changes, and snapshot constraints.
- Use Playwright for each stage’s key human decision, the full end-to-end approval path, and withdrawal.
- Run lint, typecheck, and relevant tests for each implementation slice; a failing check blocks advancement to the next stage.
- Mock OpenAI responses and media jobs for deterministic tests; separately test worker outputs against synthetic video/audio fixtures.
- Treat the adversarial cases in Stage 8 as release blockers. Test server-side enforcement even when the UI hides an invalid action.
- Never use real storyteller media or sensitive text as test fixtures.

## E. Security strategy

- Authenticate with Supabase Auth; authorize every story/artifact by owner ID in server logic and RLS. Default deny.
- Keep the source and all drafts in private Storage. Validate owner/story/path binding on every upload and read.
- Keep service-role/OpenAI credentials server-side. Never return them or unrestricted storage locations to the browser.
- Require explicit consent before external AI processing; minimize transmitted data and temporary copies.
- Validate external/AI structured data with Zod and independently validate all referenced IDs, versions, timestamps, and state transitions on the server.
- Bind approvals to immutable artifact hashes. Keep audit events append-only and avoid sensitive content in logs.
- Publish only an immutable approved snapshot. Gate every public media/caption request on current publication status; disable CDN/browser caching and signed-URL paths that outlive withdrawal.
- Test RLS, Storage policies, withdrawal, and snapshot immutability using adversarial identities and requests.

## F. Recommended implementation order

1. **Foundation:** define schemas/state vocabulary, authenticated private workspace, RLS/access patterns, test harness, and consent/disclosure copy.
2. **Tell:** private upload, authoritative metadata validation, source versioning, and failure recovery.
3. **Verify:** consent-gated Yoruba ASR draft, transcript editor, exact-version approval.
4. **Craft:** source-time-preserving cut editor, explainable suggestions, cultural review, and render/map validation.
5. **Translate:** English subtitle draft/editor/approval with per-segment source lineage.
6. **Protect:** human disposition of every privacy finding, edit/review loop, and accepted Covenant version.
7. **Publish:** final gate, immutable snapshot, disclosure, gated public page/media.
8. **Withdraw:** owner-controlled access revocation while retaining private provenance.
9. **Adversarial testing and evaluation:** execute the full invariant/security matrix as the release gate; fix failures before demo.

Each stage is complete only when its acceptance criteria and automated tests pass. Do not start the next stage by bypassing a failed gate.

## G. Major technical risks and proposed mitigations

- **Yoruba transcription/translation quality:** language coverage, dialects, names, code-switching, and timing may be weak. Pilot on consented representative samples, keep all output editable, preserve uncertainty as draft, and require storyteller approval at each language boundary.
- **External processing privacy:** source audio/transcripts may contain sensitive material. Obtain explicit consent, disclose provider use, minimize payloads, use server-only credentials, define retention/deletion for temporary copies, and offer a no-send failure path.
- **Timestamp drift and media variability:** variable frame rate, stream offsets, codec handling, and FFmpeg seeking can misalign clips. Record source PTS/timebase/frame metadata, render in an isolated worker, and test source-to-output maps with fixtures and frame-level checks.
- **Long-running media jobs:** uploads, extraction, transcription, and rendering can exceed web request limits. Use bounded asynchronous jobs, idempotency keys, retries, job status, resource/time limits, and private temporary storage cleanup.
- **Stale approvals and lineage gaps:** edits can leave downstream versions apparently approved. Use immutable artifact versions, explicit parent references, content hashes, centralized server-side gate checks, and tests for every invalidation edge.
- **Withdrawal and copies:** already downloaded copies cannot be recalled; caches and long-lived URLs may continue serving. Avoid public buckets and long-lived signed URLs, proxy media through fresh access checks, disable caching, abort active streams where feasible, and communicate the irretrievable-copy limitation.
- **RLS/service-role bypass:** a privileged server key can bypass database policies. Isolate privileged operations in narrow server modules, perform explicit owner/state checks, never expose keys, and test access with multiple synthetic users.
- **MVP scope/time:** cultural review, privacy resolution, auditability, rendering, and publication security can expand quickly. Keep one source language, one target language, one storyteller, one cut, and one publication; defer all non-required experiences listed below.

## H. Features deferred until after the hackathon

- Multiple source languages beyond Yoruba, and target languages beyond English.
- Multiple storytellers/teams and production-scale account administration.
- Blockchain, payments, and creator marketplace.
- Social-media feed or discovery features.
- Advanced video filters or synthetic B-roll.
- AI avatars or voice cloning.
- Hospital or government integrations.
- Native mobile applications.
- Any workflow that treats AI output as approved, automatically resolves privacy findings, or scores truth, credibility, emotion, or authenticity.
