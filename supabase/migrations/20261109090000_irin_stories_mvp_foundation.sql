-- Irin Stories MVP database foundation.
-- This migration is local source control only until a separately approved push.
-- All media metadata and workflow artefacts are private by default.

CREATE SCHEMA IF NOT EXISTS irin_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA irin_private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA irin_private TO authenticated, service_role;

CREATE TYPE public.story_workflow_state AS ENUM (
  'DRAFT',
  'MEDIA_READY',
  'LANGUAGE_CONFIRMATION',
  'TRANSCRIBING',
  'SOURCE_REVIEW',
  'SOURCE_APPROVED',
  'CRAFTING',
  'CRAFT_REVIEW',
  'CRAFT_APPROVED',
  'TRANSLATING',
  'TRANSLATION_REVIEW',
  'TRANSLATION_APPROVED',
  'PRIVACY_REVIEW',
  'COVENANT_REVIEW',
  'PUBLICATION_REVIEW',
  'PUBLISHED',
  'WITHDRAWN'
);

CREATE TYPE public.story_artifact_kind AS ENUM (
  'SOURCE_MEDIA',
  'TRANSCRIPT',
  'STORY_CUT',
  'CULTURAL_REVIEW',
  'TRANSLATION',
  'PRIVACY_REVIEW',
  'COVENANT',
  'RENDERED_MEDIA'
);

CREATE TYPE public.media_asset_role AS ENUM ('SOURCE', 'FINAL_PUBLICATION');
CREATE TYPE public.story_cut_decision AS ENUM ('PROPOSED', 'KEEP', 'REMOVE');
CREATE TYPE public.privacy_decision AS ENUM ('KEEP', 'GENERALISE', 'ANONYMISE', 'REMOVE');
CREATE TYPE public.approval_decision AS ENUM ('APPROVE', 'REJECT');
CREATE TYPE public.publication_access_state AS ENUM ('DRAFT', 'PUBLISHED', 'STALE', 'WITHDRAWN');
CREATE TYPE public.audit_actor_kind AS ENUM ('STORYTELLER', 'SYSTEM');

CREATE TYPE public.covenant_permission AS ENUM (
  'PUBLIC_VIEWING',
  'EDUCATIONAL_USE',
  'ACADEMIC_RESEARCH',
  'DOCUMENTARY_REUSE',
  'COMMERCIAL_REUSE',
  'AI_MODEL_TRAINING',
  'VOICE_CLONING',
  'POLITICAL_USE',
  'CHILD_IDENTITY_DISCLOSURE',
  'THIRD_PARTY_EDITING'
);

CREATE TYPE public.audit_event_type AS ENUM (
  'STORY_CREATED',
  'WORKFLOW_STATE_CHANGED',
  'MEDIA_REGISTERED',
  'LANGUAGE_CONFIRMED',
  'LANGUAGE_CORRECTED',
  'TRANSCRIPT_VERSION_CREATED',
  'SOURCE_APPROVED',
  'STORY_CUT_VERSION_CREATED',
  'STORY_CUT_APPROVED',
  'CULTURAL_REVIEW_CREATED',
  'CULTURAL_REVIEW_APPROVED',
  'TRANSLATION_CREATED',
  'TRANSLATION_APPROVED',
  'PRIVACY_REVIEW_CREATED',
  'PRIVACY_REVIEW_APPROVED',
  'PRIVACY_DECISION_MADE',
  'COVENANT_CREATED',
  'COVENANT_APPROVED',
  'PUBLICATION_APPROVED',
  'PUBLICATION_PUBLISHED',
  'PUBLICATION_STALE',
  'PUBLICATION_WITHDRAWN',
  'ARTIFACT_REJECTED'
);

CREATE TABLE public.stories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  title text NOT NULL DEFAULT 'My Story',
  workflow_state public.story_workflow_state NOT NULL DEFAULT 'DRAFT',
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT stories_title_nonempty CHECK (length(btrim(title)) BETWEEN 1 AND 160)
);

COMMENT ON TABLE public.stories IS
  'Private MVP story root. Supabase Auth user ID is the owner; no profile table is required.';

CREATE TABLE public.artifact_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  kind public.story_artifact_kind NOT NULL,
  version_number integer NOT NULL CHECK (version_number > 0),
  content_sha256 bytea,
  sealed_at timestamptz,
  created_by uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT artifact_versions_story_id_unique UNIQUE (story_id, id),
  CONSTRAINT artifact_versions_story_kind_version_unique UNIQUE (story_id, kind, version_number),
  CONSTRAINT artifact_versions_hash_seal_pair CHECK (
    (content_sha256 IS NULL AND sealed_at IS NULL)
    OR (octet_length(content_sha256) = 32 AND sealed_at IS NOT NULL)
  )
);

COMMENT ON TABLE public.artifact_versions IS
  'Shared immutable version registry. A row is assembled in one transaction, then sealed once with its canonical SHA-256 digest.';

CREATE TABLE public.media_assets (
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  artifact_version_id uuid NOT NULL,
  role public.media_asset_role NOT NULL,
  bucket_id text NOT NULL CHECK (length(btrim(bucket_id)) > 0),
  object_key text NOT NULL CHECK (
    length(btrim(object_key)) > 0
    AND position('://' IN object_key) = 0
  ),
  content_sha256 bytea NOT NULL CHECK (octet_length(content_sha256) = 32),
  mime_type text NOT NULL CHECK (length(btrim(mime_type)) BETWEEN 1 AND 160),
  byte_size bigint NOT NULL CHECK (byte_size > 0),
  duration_ms bigint NOT NULL CHECK (duration_ms > 0),
  story_cut_artifact_id uuid,
  translation_artifact_id uuid,
  frame_rate_num integer,
  frame_rate_den integer,
  video_timebase_num integer,
  video_timebase_den integer,
  video_start_pts bigint,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT media_assets_artifact_unique UNIQUE (story_id, artifact_version_id),
  CONSTRAINT media_assets_publication_lineage_unique UNIQUE (
    story_id, artifact_version_id, story_cut_artifact_id, translation_artifact_id
  ),
  CONSTRAINT media_assets_object_key_unique UNIQUE (bucket_id, object_key),
  CONSTRAINT media_assets_role_lineage CHECK (
    (role = 'SOURCE' AND story_cut_artifact_id IS NULL AND translation_artifact_id IS NULL)
    OR (role = 'FINAL_PUBLICATION' AND story_cut_artifact_id IS NOT NULL AND translation_artifact_id IS NOT NULL)
  ),
  CONSTRAINT media_assets_artifact_fk FOREIGN KEY (story_id, artifact_version_id)
    REFERENCES public.artifact_versions (story_id, id) ON DELETE RESTRICT,
  CONSTRAINT media_assets_frame_rate_pair CHECK (
    (frame_rate_num IS NULL AND frame_rate_den IS NULL)
    OR (frame_rate_num IS NOT NULL AND frame_rate_den IS NOT NULL AND frame_rate_num > 0 AND frame_rate_den > 0)
  ),
  CONSTRAINT media_assets_timebase_pair CHECK (
    (video_timebase_num IS NULL AND video_timebase_den IS NULL)
    OR (video_timebase_num IS NOT NULL AND video_timebase_den IS NOT NULL AND video_timebase_num > 0 AND video_timebase_den > 0)
  )
);

COMMENT ON TABLE public.media_assets IS
  'Private storage metadata for original and final media. Bucket privacy and object authorization are enforced separately by future Storage policies.';

CREATE TABLE public.source_language_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  source_media_artifact_id uuid NOT NULL,
  review_number integer NOT NULL CHECK (review_number > 0),
  detected_language_code text CHECK (detected_language_code ~ '^[a-z]{3}(-[A-Za-z0-9]{2,8})*$'),
  detection_confidence numeric(5, 4) CHECK (detection_confidence BETWEEN 0 AND 1),
  detector_name text CHECK (detector_name IS NULL OR length(btrim(detector_name)) <= 160),
  confirmed_language_code text CHECK (confirmed_language_code ~ '^[a-z]{3}(-[A-Za-z0-9]{2,8})*$'),
  confirmed_by uuid REFERENCES auth.users (id) ON DELETE RESTRICT,
  confirmed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT language_review_source_fk FOREIGN KEY (story_id, source_media_artifact_id)
    REFERENCES public.media_assets (story_id, artifact_version_id) ON DELETE RESTRICT,
  CONSTRAINT language_review_identity_unique UNIQUE (story_id, id, source_media_artifact_id),
  CONSTRAINT language_review_number_unique UNIQUE (story_id, source_media_artifact_id, review_number),
  CONSTRAINT language_review_confidence_requires_proposal CHECK (
    detected_language_code IS NOT NULL OR detection_confidence IS NULL
  ),
  CONSTRAINT language_review_confirmation_pair CHECK (
    (confirmed_language_code IS NULL AND confirmed_by IS NULL AND confirmed_at IS NULL)
    OR (confirmed_language_code IS NOT NULL AND confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL)
  )
);

COMMENT ON TABLE public.source_language_reviews IS
  'Append-only language proposal and storyteller confirmation. A proposal never authorizes transcription by itself.';

CREATE TABLE public.transcript_versions (
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  artifact_version_id uuid NOT NULL,
  source_media_artifact_id uuid NOT NULL,
  language_review_id uuid NOT NULL,
  language_code text NOT NULL DEFAULT 'yor'
    CHECK (language_code ~ '^[a-z]{3}(-[A-Za-z0-9]{2,8})*$'),
  provider_name text CHECK (provider_name IS NULL OR length(btrim(provider_name)) <= 120),
  model_name text CHECK (model_name IS NULL OR length(btrim(model_name)) <= 160),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT transcript_versions_artifact_unique UNIQUE (story_id, artifact_version_id),
  CONSTRAINT transcript_versions_lineage_unique UNIQUE (story_id, artifact_version_id, source_media_artifact_id),
  CONSTRAINT transcript_versions_artifact_fk FOREIGN KEY (story_id, artifact_version_id)
    REFERENCES public.artifact_versions (story_id, id) ON DELETE RESTRICT,
  CONSTRAINT transcript_versions_source_fk FOREIGN KEY (story_id, source_media_artifact_id)
    REFERENCES public.media_assets (story_id, artifact_version_id) ON DELETE RESTRICT,
  CONSTRAINT transcript_versions_language_review_fk FOREIGN KEY (story_id, language_review_id, source_media_artifact_id)
    REFERENCES public.source_language_reviews (story_id, id, source_media_artifact_id) ON DELETE RESTRICT
);

CREATE TABLE public.transcript_segments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  transcript_artifact_id uuid NOT NULL,
  source_media_artifact_id uuid NOT NULL,
  segment_number integer NOT NULL CHECK (segment_number > 0),
  source_start_ms bigint NOT NULL CHECK (source_start_ms >= 0),
  source_end_ms bigint NOT NULL CHECK (source_end_ms > source_start_ms),
  source_start_pts bigint,
  source_end_pts bigint,
  initial_proposal text,
  text_yoruba text NOT NULL CHECK (length(btrim(text_yoruba)) > 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT transcript_segments_version_unique UNIQUE (story_id, transcript_artifact_id, segment_number),
  CONSTRAINT transcript_segments_identity_unique UNIQUE (story_id, id, transcript_artifact_id),
  CONSTRAINT transcript_segments_source_identity_unique UNIQUE (
    story_id, id, transcript_artifact_id, source_media_artifact_id
  ),
  CONSTRAINT transcript_segments_lineage_fk FOREIGN KEY (story_id, transcript_artifact_id, source_media_artifact_id)
    REFERENCES public.transcript_versions (story_id, artifact_version_id, source_media_artifact_id) ON DELETE RESTRICT,
  CONSTRAINT transcript_segments_media_fk FOREIGN KEY (story_id, source_media_artifact_id)
    REFERENCES public.media_assets (story_id, artifact_version_id) ON DELETE RESTRICT,
  CONSTRAINT transcript_segments_pts_pair CHECK (
    (source_start_pts IS NULL AND source_end_pts IS NULL)
    OR (source_start_pts IS NOT NULL AND source_end_pts IS NOT NULL AND source_end_pts > source_start_pts)
  )
);

CREATE TABLE public.story_cut_versions (
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  artifact_version_id uuid NOT NULL,
  source_media_artifact_id uuid NOT NULL,
  transcript_artifact_id uuid NOT NULL,
  estimated_duration_ms bigint NOT NULL CHECK (estimated_duration_ms > 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT story_cut_versions_artifact_unique UNIQUE (story_id, artifact_version_id),
  CONSTRAINT story_cut_versions_lineage_unique UNIQUE (story_id, artifact_version_id, source_media_artifact_id, transcript_artifact_id),
  CONSTRAINT story_cut_versions_artifact_fk FOREIGN KEY (story_id, artifact_version_id)
    REFERENCES public.artifact_versions (story_id, id) ON DELETE RESTRICT,
  CONSTRAINT story_cut_versions_source_transcript_fk FOREIGN KEY (story_id, transcript_artifact_id, source_media_artifact_id)
    REFERENCES public.transcript_versions (story_id, artifact_version_id, source_media_artifact_id) ON DELETE RESTRICT
);

CREATE TABLE public.story_cut_segments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  cut_artifact_id uuid NOT NULL,
  source_media_artifact_id uuid NOT NULL,
  transcript_artifact_id uuid NOT NULL,
  segment_number integer NOT NULL CHECK (segment_number > 0),
  source_start_ms bigint NOT NULL CHECK (source_start_ms >= 0),
  source_end_ms bigint NOT NULL CHECK (source_end_ms > source_start_ms),
  source_start_pts bigint,
  source_end_pts bigint,
  output_start_ms bigint NOT NULL CHECK (output_start_ms >= 0),
  output_end_ms bigint NOT NULL CHECK (output_end_ms > output_start_ms),
  narrative_role text NOT NULL CHECK (length(btrim(narrative_role)) BETWEEN 1 AND 120),
  selection_rationale text NOT NULL CHECK (length(btrim(selection_rationale)) > 0),
  decision public.story_cut_decision NOT NULL DEFAULT 'PROPOSED',
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT story_cut_segments_order_unique UNIQUE (story_id, cut_artifact_id, segment_number),
  CONSTRAINT story_cut_segments_identity_unique UNIQUE (story_id, id, cut_artifact_id, transcript_artifact_id),
  CONSTRAINT story_cut_segments_source_identity_unique UNIQUE (
    story_id, id, cut_artifact_id, transcript_artifact_id, source_media_artifact_id
  ),
  CONSTRAINT story_cut_segments_cut_identity_unique UNIQUE (story_id, id, cut_artifact_id),
  CONSTRAINT story_cut_segments_lineage_fk FOREIGN KEY (story_id, cut_artifact_id, source_media_artifact_id, transcript_artifact_id)
    REFERENCES public.story_cut_versions (story_id, artifact_version_id, source_media_artifact_id, transcript_artifact_id) ON DELETE RESTRICT,
  CONSTRAINT story_cut_segments_pts_pair CHECK (
    (source_start_pts IS NULL AND source_end_pts IS NULL)
    OR (source_start_pts IS NOT NULL AND source_end_pts IS NOT NULL AND source_end_pts > source_start_pts)
  )
);

CREATE TABLE public.cultural_review_versions (
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  artifact_version_id uuid NOT NULL,
  story_cut_artifact_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT cultural_review_versions_artifact_unique UNIQUE (story_id, artifact_version_id),
  CONSTRAINT cultural_review_versions_lineage_unique UNIQUE (story_id, artifact_version_id, story_cut_artifact_id),
  CONSTRAINT cultural_review_versions_artifact_fk FOREIGN KEY (story_id, artifact_version_id)
    REFERENCES public.artifact_versions (story_id, id) ON DELETE RESTRICT,
  CONSTRAINT cultural_review_versions_cut_fk FOREIGN KEY (story_id, story_cut_artifact_id)
    REFERENCES public.story_cut_versions (story_id, artifact_version_id) ON DELETE RESTRICT
);

CREATE TABLE public.cultural_annotations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  cultural_review_artifact_id uuid NOT NULL,
  story_cut_artifact_id uuid NOT NULL,
  cut_segment_id uuid NOT NULL,
  yoruba_expression text NOT NULL CHECK (length(btrim(yoruba_expression)) > 0),
  literal_meaning text,
  contextual_meaning text,
  storyteller_interpretation text NOT NULL CHECK (length(btrim(storyteller_interpretation)) > 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT cultural_annotations_review_fk FOREIGN KEY (story_id, cultural_review_artifact_id, story_cut_artifact_id)
    REFERENCES public.cultural_review_versions (story_id, artifact_version_id, story_cut_artifact_id) ON DELETE RESTRICT,
  CONSTRAINT cultural_annotations_cut_segment_fk FOREIGN KEY (story_id, cut_segment_id, story_cut_artifact_id)
    REFERENCES public.story_cut_segments (story_id, id, cut_artifact_id) ON DELETE RESTRICT
);

CREATE TABLE public.translation_versions (
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  artifact_version_id uuid NOT NULL,
  source_media_artifact_id uuid NOT NULL,
  transcript_artifact_id uuid NOT NULL,
  story_cut_artifact_id uuid NOT NULL,
  cultural_review_artifact_id uuid NOT NULL,
  source_language_code text NOT NULL DEFAULT 'yor'
    CHECK (source_language_code ~ '^[a-z]{3}(-[A-Za-z0-9]{2,8})*$'),
  target_language_code text NOT NULL DEFAULT 'eng'
    CHECK (target_language_code ~ '^[a-z]{3}(-[A-Za-z0-9]{2,8})*$'),
  provider_name text CHECK (provider_name IS NULL OR length(btrim(provider_name)) <= 120),
  model_name text CHECK (model_name IS NULL OR length(btrim(model_name)) <= 160),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT translation_versions_artifact_unique UNIQUE (story_id, artifact_version_id),
  CONSTRAINT translation_versions_lineage_unique UNIQUE (story_id, artifact_version_id, source_media_artifact_id, transcript_artifact_id, story_cut_artifact_id, cultural_review_artifact_id),
  CONSTRAINT translation_versions_cut_identity_unique UNIQUE (story_id, artifact_version_id, story_cut_artifact_id),
  CONSTRAINT translation_versions_artifact_fk FOREIGN KEY (story_id, artifact_version_id)
    REFERENCES public.artifact_versions (story_id, id) ON DELETE RESTRICT,
  CONSTRAINT translation_versions_cut_fk FOREIGN KEY (story_id, story_cut_artifact_id, source_media_artifact_id, transcript_artifact_id)
    REFERENCES public.story_cut_versions (story_id, artifact_version_id, source_media_artifact_id, transcript_artifact_id) ON DELETE RESTRICT,
  CONSTRAINT translation_versions_cultural_fk FOREIGN KEY (story_id, cultural_review_artifact_id, story_cut_artifact_id)
    REFERENCES public.cultural_review_versions (story_id, artifact_version_id, story_cut_artifact_id) ON DELETE RESTRICT
);

ALTER TABLE public.media_assets
  ADD CONSTRAINT media_assets_cut_fk FOREIGN KEY (story_id, story_cut_artifact_id)
    REFERENCES public.story_cut_versions (story_id, artifact_version_id) ON DELETE RESTRICT,
  ADD CONSTRAINT media_assets_translation_fk FOREIGN KEY (story_id, translation_artifact_id, story_cut_artifact_id)
    REFERENCES public.translation_versions (story_id, artifact_version_id, story_cut_artifact_id) ON DELETE RESTRICT;

CREATE TABLE public.translation_segments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  translation_artifact_id uuid NOT NULL,
  source_media_artifact_id uuid NOT NULL,
  transcript_artifact_id uuid NOT NULL,
  story_cut_artifact_id uuid NOT NULL,
  cultural_review_artifact_id uuid NOT NULL,
  cut_segment_id uuid NOT NULL,
  transcript_segment_id uuid NOT NULL,
  segment_number integer NOT NULL CHECK (segment_number > 0),
  cue_start_ms bigint NOT NULL CHECK (cue_start_ms >= 0),
  cue_end_ms bigint NOT NULL CHECK (cue_end_ms > cue_start_ms),
  english_text text NOT NULL CHECK (length(btrim(english_text)) > 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT translation_segments_order_unique UNIQUE (story_id, translation_artifact_id, segment_number),
  CONSTRAINT translation_segments_lineage_fk FOREIGN KEY (
    story_id, translation_artifact_id, source_media_artifact_id, transcript_artifact_id,
    story_cut_artifact_id, cultural_review_artifact_id
  ) REFERENCES public.translation_versions (
    story_id, artifact_version_id, source_media_artifact_id, transcript_artifact_id,
    story_cut_artifact_id, cultural_review_artifact_id
  ) ON DELETE RESTRICT,
  CONSTRAINT translation_segments_cut_source_fk FOREIGN KEY (
    story_id, cut_segment_id, story_cut_artifact_id, transcript_artifact_id, source_media_artifact_id
  ) REFERENCES public.story_cut_segments (
    story_id, id, cut_artifact_id, transcript_artifact_id, source_media_artifact_id
  ) ON DELETE RESTRICT,
  CONSTRAINT translation_segments_transcript_source_fk FOREIGN KEY (
    story_id, transcript_segment_id, transcript_artifact_id, source_media_artifact_id
  ) REFERENCES public.transcript_segments (
    story_id, id, transcript_artifact_id, source_media_artifact_id
  ) ON DELETE RESTRICT,
  CONSTRAINT translation_segments_identity_unique UNIQUE (story_id, id, translation_artifact_id)
);

CREATE TABLE public.privacy_review_versions (
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  artifact_version_id uuid NOT NULL,
  story_cut_artifact_id uuid NOT NULL,
  translation_artifact_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT privacy_review_versions_artifact_unique UNIQUE (story_id, artifact_version_id),
  CONSTRAINT privacy_review_versions_lineage_unique UNIQUE (story_id, artifact_version_id, story_cut_artifact_id, translation_artifact_id),
  CONSTRAINT privacy_review_versions_artifact_fk FOREIGN KEY (story_id, artifact_version_id)
    REFERENCES public.artifact_versions (story_id, id) ON DELETE RESTRICT,
  CONSTRAINT privacy_review_versions_translation_fk FOREIGN KEY (story_id, translation_artifact_id, story_cut_artifact_id)
    REFERENCES public.translation_versions (story_id, artifact_version_id, story_cut_artifact_id) ON DELETE RESTRICT
);

CREATE TABLE public.privacy_findings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  privacy_review_artifact_id uuid NOT NULL,
  proposal_source text NOT NULL DEFAULT 'AI' CHECK (proposal_source IN ('AI', 'HUMAN')),
  proposal_model text CHECK (proposal_model IS NULL OR length(btrim(proposal_model)) <= 160),
  risk_category text NOT NULL CHECK (length(btrim(risk_category)) BETWEEN 1 AND 80),
  proposal_summary text NOT NULL CHECK (length(btrim(proposal_summary)) > 0),
  suggested_safer_alternative text,
  source_media_artifact_id uuid,
  source_start_ms bigint,
  source_end_ms bigint,
  transcript_artifact_id uuid,
  transcript_segment_id uuid,
  story_cut_artifact_id uuid,
  cut_segment_id uuid,
  translation_artifact_id uuid,
  translation_segment_id uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT privacy_findings_story_id_unique UNIQUE (story_id, id),
  CONSTRAINT privacy_findings_review_fk FOREIGN KEY (story_id, privacy_review_artifact_id)
    REFERENCES public.privacy_review_versions (story_id, artifact_version_id) ON DELETE RESTRICT,
  CONSTRAINT privacy_findings_source_fk FOREIGN KEY (story_id, source_media_artifact_id)
    REFERENCES public.media_assets (story_id, artifact_version_id) ON DELETE RESTRICT,
  CONSTRAINT privacy_findings_transcript_fk FOREIGN KEY (story_id, transcript_segment_id, transcript_artifact_id)
    REFERENCES public.transcript_segments (story_id, id, transcript_artifact_id) ON DELETE RESTRICT,
  CONSTRAINT privacy_findings_cut_fk FOREIGN KEY (story_id, cut_segment_id, story_cut_artifact_id)
    REFERENCES public.story_cut_segments (story_id, id, cut_artifact_id) ON DELETE RESTRICT,
  CONSTRAINT privacy_findings_translation_fk FOREIGN KEY (story_id, translation_segment_id, translation_artifact_id)
    REFERENCES public.translation_segments (story_id, id, translation_artifact_id) ON DELETE RESTRICT,
  CONSTRAINT privacy_findings_one_anchor CHECK (
    num_nonnulls(source_media_artifact_id, transcript_segment_id, cut_segment_id, translation_segment_id) = 1
  ),
  CONSTRAINT privacy_findings_source_time_pair CHECK (
    (source_media_artifact_id IS NULL AND source_start_ms IS NULL AND source_end_ms IS NULL)
    OR (
      source_media_artifact_id IS NOT NULL AND source_start_ms IS NOT NULL AND source_end_ms IS NOT NULL
      AND source_start_ms >= 0 AND source_end_ms > source_start_ms
    )
  ),
  CONSTRAINT privacy_findings_anchor_version_pair CHECK (
    (transcript_segment_id IS NULL) = (transcript_artifact_id IS NULL)
    AND (cut_segment_id IS NULL) = (story_cut_artifact_id IS NULL)
    AND (translation_segment_id IS NULL) = (translation_artifact_id IS NULL)
  )
);

COMMENT ON TABLE public.privacy_findings IS
  'Private potential-risk proposals only. No automated decision is stored here; storyteller decisions are separate append-only rows.';

CREATE TABLE public.privacy_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  privacy_finding_id uuid NOT NULL,
  decision public.privacy_decision NOT NULL,
  resolution_artifact_version_id uuid,
  storyteller_note text,
  decided_by uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT privacy_decisions_finding_unique UNIQUE (story_id, privacy_finding_id),
  CONSTRAINT privacy_decisions_resolution_pair CHECK (
    (decision = 'KEEP' AND resolution_artifact_version_id IS NULL)
    OR (decision <> 'KEEP' AND resolution_artifact_version_id IS NOT NULL)
  ),
  CONSTRAINT privacy_decisions_finding_fk FOREIGN KEY (story_id, privacy_finding_id)
    REFERENCES public.privacy_findings (story_id, id) ON DELETE RESTRICT,
  CONSTRAINT privacy_decisions_resolution_fk FOREIGN KEY (story_id, resolution_artifact_version_id)
    REFERENCES public.artifact_versions (story_id, id) ON DELETE RESTRICT
);

CREATE TABLE public.covenant_permissions (
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  covenant_artifact_id uuid NOT NULL,
  permission public.covenant_permission NOT NULL,
  allowed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT covenant_permissions_pk PRIMARY KEY (story_id, covenant_artifact_id, permission),
  CONSTRAINT covenant_voice_cloning_forbidden CHECK (permission <> 'VOICE_CLONING' OR NOT allowed),
  CONSTRAINT covenant_permissions_artifact_fk FOREIGN KEY (story_id, covenant_artifact_id)
    REFERENCES public.artifact_versions (story_id, id) ON DELETE RESTRICT
);

COMMENT ON TABLE public.covenant_permissions IS
  'Explicit terms for each Covenant version. Every permission defaults to denied; publication requires explicit public-viewing permission.';

CREATE TABLE public.publication_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  snapshot_version integer NOT NULL CHECK (snapshot_version > 0),
  public_id uuid NOT NULL DEFAULT gen_random_uuid(),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 160),
  original_language_code text NOT NULL DEFAULT 'yor'
    CHECK (original_language_code ~ '^[a-z]{3}(-[A-Za-z0-9]{2,8})*$'),
  share_language_code text NOT NULL DEFAULT 'eng'
    CHECK (share_language_code ~ '^[a-z]{3}(-[A-Za-z0-9]{2,8})*$'),
  source_media_artifact_id uuid NOT NULL,
  transcript_artifact_id uuid NOT NULL,
  story_cut_artifact_id uuid NOT NULL,
  cultural_review_artifact_id uuid NOT NULL,
  translation_artifact_id uuid NOT NULL,
  privacy_review_artifact_id uuid NOT NULL,
  covenant_artifact_id uuid NOT NULL,
  rendered_media_artifact_id uuid NOT NULL,
  ai_editing_disclosed boolean NOT NULL CHECK (ai_editing_disclosed),
  ai_translation_disclosed boolean NOT NULL CHECK (ai_translation_disclosed),
  manifest_sha256 bytea NOT NULL CHECK (octet_length(manifest_sha256) = 32),
  created_by uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT publication_snapshots_story_version_unique UNIQUE (story_id, snapshot_version),
  CONSTRAINT publication_snapshots_public_id_unique UNIQUE (public_id),
  CONSTRAINT publication_snapshots_story_id_unique UNIQUE (story_id, id),
  CONSTRAINT publication_snapshots_source_fk FOREIGN KEY (story_id, source_media_artifact_id)
    REFERENCES public.media_assets (story_id, artifact_version_id) ON DELETE RESTRICT,
  CONSTRAINT publication_snapshots_transcript_fk FOREIGN KEY (story_id, transcript_artifact_id, source_media_artifact_id)
    REFERENCES public.transcript_versions (story_id, artifact_version_id, source_media_artifact_id) ON DELETE RESTRICT,
  CONSTRAINT publication_snapshots_cut_fk FOREIGN KEY (story_id, story_cut_artifact_id, source_media_artifact_id, transcript_artifact_id)
    REFERENCES public.story_cut_versions (story_id, artifact_version_id, source_media_artifact_id, transcript_artifact_id) ON DELETE RESTRICT,
  CONSTRAINT publication_snapshots_cultural_fk FOREIGN KEY (story_id, cultural_review_artifact_id, story_cut_artifact_id)
    REFERENCES public.cultural_review_versions (story_id, artifact_version_id, story_cut_artifact_id) ON DELETE RESTRICT,
  CONSTRAINT publication_snapshots_translation_fk FOREIGN KEY (
    story_id, translation_artifact_id, source_media_artifact_id, transcript_artifact_id,
    story_cut_artifact_id, cultural_review_artifact_id
  ) REFERENCES public.translation_versions (
    story_id, artifact_version_id, source_media_artifact_id, transcript_artifact_id,
    story_cut_artifact_id, cultural_review_artifact_id
  ) ON DELETE RESTRICT,
  CONSTRAINT publication_snapshots_privacy_fk FOREIGN KEY (story_id, privacy_review_artifact_id, story_cut_artifact_id, translation_artifact_id)
    REFERENCES public.privacy_review_versions (story_id, artifact_version_id, story_cut_artifact_id, translation_artifact_id) ON DELETE RESTRICT,
  CONSTRAINT publication_snapshots_covenant_fk FOREIGN KEY (story_id, covenant_artifact_id)
    REFERENCES public.artifact_versions (story_id, id) ON DELETE RESTRICT,
  CONSTRAINT publication_snapshots_render_fk FOREIGN KEY (
    story_id, rendered_media_artifact_id, story_cut_artifact_id, translation_artifact_id
  ) REFERENCES public.media_assets (
    story_id, artifact_version_id, story_cut_artifact_id, translation_artifact_id
  ) ON DELETE RESTRICT
);

COMMENT ON TABLE public.publication_snapshots IS
  'Immutable typed manifest of one exact, approved publication package. Serving state is held separately.';

CREATE TABLE public.approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  artifact_version_id uuid,
  publication_snapshot_id uuid,
  decision public.approval_decision NOT NULL,
  approved_content_sha256 bytea NOT NULL CHECK (octet_length(approved_content_sha256) = 32),
  approver_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  review_note text,
  decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT approvals_exactly_one_target CHECK (num_nonnulls(artifact_version_id, publication_snapshot_id) = 1),
  CONSTRAINT approvals_artifact_fk FOREIGN KEY (story_id, artifact_version_id)
    REFERENCES public.artifact_versions (story_id, id) ON DELETE RESTRICT,
  CONSTRAINT approvals_publication_fk FOREIGN KEY (story_id, publication_snapshot_id)
    REFERENCES public.publication_snapshots (story_id, id) ON DELETE RESTRICT,
  CONSTRAINT approvals_artifact_once UNIQUE (artifact_version_id),
  CONSTRAINT approvals_publication_once UNIQUE (publication_snapshot_id)
);

COMMENT ON TABLE public.approvals IS
  'Append-only human decision bound to one sealed artefact or immutable publication manifest hash.';

CREATE TABLE public.publication_access (
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  publication_snapshot_id uuid PRIMARY KEY,
  access_state public.publication_access_state NOT NULL DEFAULT 'DRAFT',
  published_at timestamptz,
  published_by uuid REFERENCES auth.users (id) ON DELETE RESTRICT,
  stale_at timestamptz,
  withdrawn_at timestamptz,
  withdrawn_by uuid REFERENCES auth.users (id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT publication_access_snapshot_fk FOREIGN KEY (story_id, publication_snapshot_id)
    REFERENCES public.publication_snapshots (story_id, id) ON DELETE RESTRICT,
  CONSTRAINT publication_access_state_timestamps CHECK (
    (access_state = 'DRAFT' AND published_at IS NULL AND published_by IS NULL AND stale_at IS NULL AND withdrawn_at IS NULL AND withdrawn_by IS NULL)
    OR (access_state = 'PUBLISHED' AND published_at IS NOT NULL AND published_by IS NOT NULL AND stale_at IS NULL AND withdrawn_at IS NULL AND withdrawn_by IS NULL)
    OR (access_state = 'STALE' AND published_at IS NOT NULL AND published_by IS NOT NULL AND stale_at IS NOT NULL AND withdrawn_at IS NULL AND withdrawn_by IS NULL)
    OR (access_state = 'WITHDRAWN' AND published_at IS NOT NULL AND published_by IS NOT NULL AND stale_at IS NULL AND withdrawn_at IS NOT NULL AND withdrawn_by IS NOT NULL)
  )
);

CREATE TABLE public.audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  actor_kind public.audit_actor_kind NOT NULL,
  actor_id uuid REFERENCES auth.users (id) ON DELETE RESTRICT,
  event_type public.audit_event_type NOT NULL,
  artifact_version_id uuid,
  publication_snapshot_id uuid,
  previous_workflow_state public.story_workflow_state,
  next_workflow_state public.story_workflow_state,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT audit_events_actor_pair CHECK (
    (actor_kind = 'SYSTEM' AND actor_id IS NULL)
    OR (actor_kind = 'STORYTELLER' AND actor_id IS NOT NULL)
  ),
  CONSTRAINT audit_events_one_artifact_target CHECK (
    artifact_version_id IS NULL OR publication_snapshot_id IS NULL
  ),
  CONSTRAINT audit_events_artifact_fk FOREIGN KEY (story_id, artifact_version_id)
    REFERENCES public.artifact_versions (story_id, id) ON DELETE RESTRICT,
  CONSTRAINT audit_events_publication_fk FOREIGN KEY (story_id, publication_snapshot_id)
    REFERENCES public.publication_snapshots (story_id, id) ON DELETE RESTRICT
);

-- Foreign keys that reference publication snapshots are added above through the later render table.
-- All foreign keys are RESTRICT so provenance cannot be cascaded away.

CREATE OR REPLACE FUNCTION irin_private.user_owns_story(p_story_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.stories AS owned_story
    WHERE owned_story.id = p_story_id
      AND owned_story.owner_id = auth.uid()
  );
$function$;

CREATE OR REPLACE FUNCTION irin_private.reject_row_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION 'This versioned or audit row is append-only.';
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.require_unsealed_artifact()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_artifact_id uuid;
  v_kind public.story_artifact_kind;
BEGIN
  v_artifact_id := (to_jsonb(NEW) ->> TG_ARGV[0])::uuid;

  SELECT artifact.kind INTO v_kind
  FROM public.artifact_versions AS artifact
  WHERE artifact.id = v_artifact_id
    AND artifact.story_id = NEW.story_id
    AND artifact.sealed_at IS NULL;

  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'Artefact child rows may only be added before the artefact is sealed.';
  END IF;

  IF TG_NARGS > 1 AND v_kind::text IS DISTINCT FROM TG_ARGV[1] THEN
    RAISE EXCEPTION 'Child row does not match its declared artefact kind.';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.assert_artifact_complete(
  p_story_id uuid,
  p_artifact_id uuid,
  p_kind public.story_artifact_kind
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  CASE p_kind
    WHEN 'SOURCE_MEDIA' THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.media_assets AS media
        WHERE media.story_id = p_story_id
          AND media.artifact_version_id = p_artifact_id
          AND media.role = 'SOURCE'
      ) THEN
        RAISE EXCEPTION 'A source-media artefact requires source media metadata.';
      END IF;
    WHEN 'TRANSCRIPT' THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.transcript_versions AS transcript
        WHERE transcript.story_id = p_story_id AND transcript.artifact_version_id = p_artifact_id
      ) OR NOT EXISTS (
        SELECT 1 FROM public.transcript_segments AS segment
        WHERE segment.story_id = p_story_id AND segment.transcript_artifact_id = p_artifact_id
      ) THEN
        RAISE EXCEPTION 'A transcript artefact requires version metadata and at least one timestamped segment.';
      END IF;
    WHEN 'STORY_CUT' THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.story_cut_versions AS cut
        WHERE cut.story_id = p_story_id AND cut.artifact_version_id = p_artifact_id
      ) OR NOT EXISTS (
        SELECT 1 FROM public.story_cut_segments AS segment
        WHERE segment.story_id = p_story_id AND segment.cut_artifact_id = p_artifact_id
      ) THEN
        RAISE EXCEPTION 'A Story Cut artefact requires version metadata and at least one source-mapped segment.';
      END IF;
    WHEN 'CULTURAL_REVIEW' THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.cultural_review_versions AS review
        WHERE review.story_id = p_story_id AND review.artifact_version_id = p_artifact_id
      ) THEN
        RAISE EXCEPTION 'A cultural-review artefact requires version metadata.';
      END IF;
    WHEN 'TRANSLATION' THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.translation_versions AS translation
        WHERE translation.story_id = p_story_id AND translation.artifact_version_id = p_artifact_id
      ) OR NOT EXISTS (
        SELECT 1 FROM public.translation_segments AS segment
        WHERE segment.story_id = p_story_id AND segment.translation_artifact_id = p_artifact_id
      ) THEN
        RAISE EXCEPTION 'A translation artefact requires version metadata and at least one subtitle segment.';
      END IF;
    WHEN 'PRIVACY_REVIEW' THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.privacy_review_versions AS review
        WHERE review.story_id = p_story_id AND review.artifact_version_id = p_artifact_id
      ) THEN
        RAISE EXCEPTION 'A privacy-review artefact requires version metadata.';
      END IF;
    WHEN 'COVENANT' THEN
      IF (
        SELECT count(*) FROM public.covenant_permissions AS permission
        WHERE permission.story_id = p_story_id AND permission.covenant_artifact_id = p_artifact_id
      ) <> 10 THEN
        RAISE EXCEPTION 'A Covenant must record every defined permission explicitly.';
      END IF;
    WHEN 'RENDERED_MEDIA' THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.media_assets AS media
        WHERE media.story_id = p_story_id
          AND media.artifact_version_id = p_artifact_id
          AND media.role = 'FINAL_PUBLICATION'
          AND media.story_cut_artifact_id IS NOT NULL
          AND media.translation_artifact_id IS NOT NULL
      ) THEN
        RAISE EXCEPTION 'A rendered-media artefact requires final publication media metadata.';
      END IF;
  END CASE;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_artifact_version()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Artefact versions cannot be deleted.';
  END IF;

  IF OLD.sealed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Sealed artefact versions are immutable.';
  END IF;

  IF NEW.sealed_at IS NULL OR NEW.content_sha256 IS NULL OR octet_length(NEW.content_sha256) <> 32 THEN
    RAISE EXCEPTION 'The only permitted artefact update is a one-time seal with a SHA-256 digest.';
  END IF;

  IF ROW(NEW.id, NEW.story_id, NEW.kind, NEW.version_number, NEW.created_by, NEW.created_at)
     IS DISTINCT FROM
     ROW(OLD.id, OLD.story_id, OLD.kind, OLD.version_number, OLD.created_by, OLD.created_at) THEN
    RAISE EXCEPTION 'Artefact identity and provenance cannot change while sealing.';
  END IF;

  PERFORM irin_private.assert_artifact_complete(NEW.story_id, NEW.id, NEW.kind);
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.artifact_is_latest(
  p_story_id uuid,
  p_artifact_id uuid,
  p_kind public.story_artifact_kind
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.artifact_versions AS target
    WHERE target.story_id = p_story_id
      AND target.id = p_artifact_id
      AND target.kind = p_kind
      AND target.sealed_at IS NOT NULL
      AND target.version_number = (
        SELECT max(candidate.version_number)
        FROM public.artifact_versions AS candidate
        WHERE candidate.story_id = p_story_id AND candidate.kind = p_kind
      )
  );
$function$;

CREATE OR REPLACE FUNCTION irin_private.artifact_is_approved(
  p_story_id uuid,
  p_artifact_id uuid,
  p_kind public.story_artifact_kind
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.artifact_versions AS artifact
    JOIN public.approvals AS approval
      ON approval.story_id = artifact.story_id
     AND approval.artifact_version_id = artifact.id
     AND approval.decision = 'APPROVE'
     AND approval.approved_content_sha256 = artifact.content_sha256
    WHERE artifact.story_id = p_story_id
      AND artifact.id = p_artifact_id
      AND artifact.kind = p_kind
      AND artifact.sealed_at IS NOT NULL
  );
$function$;

CREATE OR REPLACE FUNCTION irin_private.latest_source_media_id(p_story_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT artifact.id
  FROM public.artifact_versions AS artifact
  JOIN public.media_assets AS media
    ON media.story_id = artifact.story_id
   AND media.artifact_version_id = artifact.id
   AND media.role = 'SOURCE'
  WHERE artifact.story_id = p_story_id
    AND artifact.kind = 'SOURCE_MEDIA'
    AND artifact.sealed_at IS NOT NULL
  ORDER BY artifact.version_number DESC
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION irin_private.artifact_is_latest_approved(
  p_story_id uuid,
  p_artifact_id uuid,
  p_kind public.story_artifact_kind
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT irin_private.artifact_is_latest(p_story_id, p_artifact_id, p_kind)
     AND irin_private.artifact_is_approved(p_story_id, p_artifact_id, p_kind)
     AND CASE p_kind
       WHEN 'SOURCE_MEDIA' THEN
         p_artifact_id = irin_private.latest_source_media_id(p_story_id)
       WHEN 'TRANSCRIPT' THEN EXISTS (
         SELECT 1
         FROM public.transcript_versions AS transcript
         JOIN public.source_language_reviews AS language_review
           ON language_review.story_id = transcript.story_id
          AND language_review.id = transcript.language_review_id
          AND language_review.source_media_artifact_id = transcript.source_media_artifact_id
         WHERE transcript.story_id = p_story_id
           AND transcript.artifact_version_id = p_artifact_id
           AND transcript.source_media_artifact_id = irin_private.latest_source_media_id(p_story_id)
           AND language_review.confirmed_language_code = 'yor'
           AND language_review.confirmed_by = (SELECT story.owner_id FROM public.stories AS story WHERE story.id = p_story_id)
           AND language_review.review_number = (
             SELECT max(candidate.review_number)
             FROM public.source_language_reviews AS candidate
             WHERE candidate.story_id = transcript.story_id
               AND candidate.source_media_artifact_id = transcript.source_media_artifact_id
               AND candidate.confirmed_language_code IS NOT NULL
           )
       )
       WHEN 'STORY_CUT' THEN EXISTS (
         SELECT 1
         FROM public.story_cut_versions AS cut
         WHERE cut.story_id = p_story_id
           AND cut.artifact_version_id = p_artifact_id
           AND cut.source_media_artifact_id = irin_private.latest_source_media_id(p_story_id)
           AND irin_private.artifact_is_latest_approved(
             p_story_id, cut.transcript_artifact_id, 'TRANSCRIPT'
           )
       )
       WHEN 'CULTURAL_REVIEW' THEN EXISTS (
         SELECT 1
         FROM public.cultural_review_versions AS review
         WHERE review.story_id = p_story_id
           AND review.artifact_version_id = p_artifact_id
           AND irin_private.artifact_is_latest_approved(
             p_story_id, review.story_cut_artifact_id, 'STORY_CUT'
           )
       )
       WHEN 'TRANSLATION' THEN EXISTS (
         SELECT 1
         FROM public.translation_versions AS translation
         WHERE translation.story_id = p_story_id
           AND translation.artifact_version_id = p_artifact_id
           AND translation.source_media_artifact_id = irin_private.latest_source_media_id(p_story_id)
           AND irin_private.artifact_is_latest_approved(
             p_story_id, translation.transcript_artifact_id, 'TRANSCRIPT'
           )
           AND irin_private.artifact_is_latest_approved(
             p_story_id, translation.story_cut_artifact_id, 'STORY_CUT'
           )
           AND irin_private.artifact_is_latest_approved(
             p_story_id, translation.cultural_review_artifact_id, 'CULTURAL_REVIEW'
           )
       )
       WHEN 'PRIVACY_REVIEW' THEN EXISTS (
         SELECT 1
         FROM public.privacy_review_versions AS review
         WHERE review.story_id = p_story_id
           AND review.artifact_version_id = p_artifact_id
           AND irin_private.artifact_is_latest_approved(
             p_story_id, review.story_cut_artifact_id, 'STORY_CUT'
           )
           AND irin_private.artifact_is_latest_approved(
             p_story_id, review.translation_artifact_id, 'TRANSLATION'
           )
       )
       ELSE true
     END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.active_covenant_id(p_story_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT artifact.id
  FROM public.artifact_versions AS artifact
  JOIN public.approvals AS approval
    ON approval.story_id = artifact.story_id
   AND approval.artifact_version_id = artifact.id
   AND approval.decision = 'APPROVE'
   AND approval.approved_content_sha256 = artifact.content_sha256
  WHERE artifact.story_id = p_story_id
    AND artifact.kind = 'COVENANT'
    AND artifact.sealed_at IS NOT NULL
  ORDER BY artifact.version_number DESC
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_artifact_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_owner_id uuid;
  v_next_version integer;
BEGIN
  SELECT story.owner_id INTO v_owner_id
  FROM public.stories AS story
  WHERE story.id = NEW.story_id
  FOR UPDATE;

  IF v_owner_id IS NULL OR NEW.created_by IS DISTINCT FROM v_owner_id THEN
    RAISE EXCEPTION 'Artefact creator must be the owning storyteller.';
  END IF;

  SELECT coalesce(max(artifact.version_number), 0) + 1 INTO v_next_version
  FROM public.artifact_versions AS artifact
  WHERE artifact.story_id = NEW.story_id AND artifact.kind = NEW.kind;

  IF NEW.version_number <> v_next_version THEN
    RAISE EXCEPTION 'Artefact versions must increase by one within each story and artefact kind.';
  END IF;

  IF NEW.content_sha256 IS NOT NULL OR NEW.sealed_at IS NOT NULL THEN
    RAISE EXCEPTION 'New artefacts must be assembled before they are sealed.';
  END IF;

  NEW.created_at := clock_timestamp();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.emit_audit_event(
  p_story_id uuid,
  p_actor_id uuid,
  p_event_type public.audit_event_type,
  p_artifact_version_id uuid,
  p_publication_snapshot_id uuid,
  p_metadata jsonb,
  p_previous_state public.story_workflow_state,
  p_next_state public.story_workflow_state
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  INSERT INTO public.audit_events (
    story_id, actor_kind, actor_id, event_type, artifact_version_id,
    publication_snapshot_id, previous_workflow_state, next_workflow_state, metadata
  ) VALUES (
    p_story_id,
    CASE WHEN p_actor_id IS NULL THEN 'SYSTEM'::public.audit_actor_kind
         ELSE 'STORYTELLER'::public.audit_actor_kind END,
    p_actor_id,
    p_event_type,
    p_artifact_version_id,
    p_publication_snapshot_id,
    p_previous_state,
    p_next_state,
    coalesce(p_metadata, '{}'::jsonb)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.after_story_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM irin_private.emit_audit_event(
      NEW.id, NEW.owner_id, 'STORY_CREATED', NULL, NULL, '{}'::jsonb, NULL, NEW.workflow_state
    );
  ELSIF NEW.workflow_state IS DISTINCT FROM OLD.workflow_state THEN
    PERFORM irin_private.emit_audit_event(
      NEW.id, auth.uid(), 'WORKFLOW_STATE_CHANGED', NULL, NULL,
      '{}'::jsonb, OLD.workflow_state, NEW.workflow_state
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.after_language_review_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.confirmed_language_code IS NOT NULL THEN
    PERFORM irin_private.emit_audit_event(
      NEW.story_id,
      NEW.confirmed_by,
      CASE WHEN NEW.detected_language_code IS NULL OR NEW.confirmed_language_code = NEW.detected_language_code
        THEN 'LANGUAGE_CONFIRMED'::public.audit_event_type
        ELSE 'LANGUAGE_CORRECTED'::public.audit_event_type
      END,
      NEW.source_media_artifact_id,
      NULL,
      jsonb_build_object(
        'detected_language_code', NEW.detected_language_code,
        'confirmed_language_code', NEW.confirmed_language_code
      ),
      NULL,
      NULL
    );

    IF NEW.review_number > 1 THEN
      UPDATE public.publication_access AS access
      SET access_state = 'STALE'
      WHERE access.story_id = NEW.story_id
        AND access.access_state = 'PUBLISHED';

      UPDATE public.stories AS story
      SET workflow_state = 'LANGUAGE_CONFIRMATION'
      WHERE story.id = NEW.story_id
        AND story.workflow_state NOT IN ('DRAFT', 'LANGUAGE_CONFIRMATION', 'WITHDRAWN');
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION irin_private.after_language_review_insert() IS
  'A new storyteller-confirmed language decision invalidates downstream approvals, stales active publication access, and returns the workflow to language confirmation; an unconfirmed AI proposal does not replace the confirmed choice.';

















CREATE OR REPLACE FUNCTION irin_private.after_approval_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_kind public.story_artifact_kind;
  v_event public.audit_event_type;
BEGIN
  IF NEW.publication_snapshot_id IS NOT NULL THEN
    v_event := CASE WHEN NEW.decision = 'APPROVE'
      THEN 'PUBLICATION_APPROVED'::public.audit_event_type
      ELSE 'ARTIFACT_REJECTED'::public.audit_event_type
    END;
    PERFORM irin_private.emit_audit_event(
      NEW.story_id, NEW.approver_id, v_event, NULL,
      NEW.publication_snapshot_id,
      jsonb_build_object('decision', NEW.decision), NULL, NULL
    );
    RETURN NEW;
  END IF;

  IF NEW.decision = 'REJECT' THEN
    v_event := 'ARTIFACT_REJECTED';
  ELSE
    SELECT artifact.kind INTO v_kind
    FROM public.artifact_versions AS artifact
    WHERE artifact.story_id = NEW.story_id AND artifact.id = NEW.artifact_version_id;
    v_event := CASE v_kind
      WHEN 'TRANSCRIPT' THEN 'SOURCE_APPROVED'::public.audit_event_type
      WHEN 'STORY_CUT' THEN 'STORY_CUT_APPROVED'::public.audit_event_type
      WHEN 'CULTURAL_REVIEW' THEN 'CULTURAL_REVIEW_APPROVED'::public.audit_event_type
      WHEN 'TRANSLATION' THEN 'TRANSLATION_APPROVED'::public.audit_event_type
      WHEN 'PRIVACY_REVIEW' THEN 'PRIVACY_REVIEW_APPROVED'::public.audit_event_type
      WHEN 'COVENANT' THEN 'COVENANT_APPROVED'::public.audit_event_type
      ELSE 'ARTIFACT_REJECTED'::public.audit_event_type
    END;
  END IF;

  PERFORM irin_private.emit_audit_event(
    NEW.story_id, NEW.approver_id, v_event, NEW.artifact_version_id, NULL,
    jsonb_build_object('decision', NEW.decision), NULL, NULL
  );
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.after_privacy_decision_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  PERFORM irin_private.emit_audit_event(
    NEW.story_id,
    NEW.decided_by,
    'PRIVACY_DECISION_MADE',
    (SELECT finding.privacy_review_artifact_id
     FROM public.privacy_findings AS finding
     WHERE finding.story_id = NEW.story_id AND finding.id = NEW.privacy_finding_id),
    NULL,
    jsonb_build_object('finding_id', NEW.privacy_finding_id, 'decision', NEW.decision),
    NULL,
    NULL
  );
  RETURN NEW;
END;
$function$;



CREATE OR REPLACE FUNCTION irin_private.guard_source_language_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_owner_id uuid;
  v_latest_source_id uuid;
  v_next_review_number integer;
BEGIN
  SELECT story.owner_id INTO v_owner_id
  FROM public.stories AS story
  WHERE story.id = NEW.story_id
  FOR UPDATE;

  v_latest_source_id := irin_private.latest_source_media_id(NEW.story_id);
  IF v_owner_id IS NULL OR NEW.source_media_artifact_id IS DISTINCT FROM v_latest_source_id THEN
    RAISE EXCEPTION 'Language review must reference the current source owned by this story.';
  END IF;

  SELECT coalesce(max(review.review_number), 0) + 1 INTO v_next_review_number
  FROM public.source_language_reviews AS review
  WHERE review.story_id = NEW.story_id
    AND review.source_media_artifact_id = NEW.source_media_artifact_id;

  IF NEW.review_number <> v_next_review_number THEN
    RAISE EXCEPTION 'Language review numbers must increase by one for each source version.';
  END IF;

  IF NEW.confirmed_language_code IS NULL THEN
    IF NEW.confirmed_by IS NOT NULL OR NEW.confirmed_at IS NOT NULL THEN
      RAISE EXCEPTION 'An unconfirmed language proposal cannot contain confirmation identity or time.';
    END IF;
  ELSE
    IF NEW.confirmed_language_code IS DISTINCT FROM 'yor' THEN
      RAISE EXCEPTION 'The MVP currently supports Yoruba as its only confirmed original language.';
    END IF;
    IF NEW.confirmed_by IS DISTINCT FROM v_owner_id THEN
      RAISE EXCEPTION 'Only the story owner may confirm or correct the original language.';
    END IF;
    NEW.confirmed_at := clock_timestamp();
  END IF;

  NEW.created_at := clock_timestamp();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_media_asset()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_kind public.story_artifact_kind;
BEGIN
  SELECT artifact.kind INTO v_kind
  FROM public.artifact_versions AS artifact
  WHERE artifact.story_id = NEW.story_id AND artifact.id = NEW.artifact_version_id;

  IF (NEW.role = 'SOURCE' AND v_kind <> 'SOURCE_MEDIA')
     OR (NEW.role = 'FINAL_PUBLICATION' AND v_kind <> 'RENDERED_MEDIA') THEN
    RAISE EXCEPTION 'Media role must match the typed artefact kind.';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_transcript_version()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_confirmed_language text;
  v_review_source_id uuid;
BEGIN
  SELECT review.confirmed_language_code, review.source_media_artifact_id
    INTO v_confirmed_language, v_review_source_id
  FROM public.source_language_reviews AS review
  WHERE review.story_id = NEW.story_id AND review.id = NEW.language_review_id;

  IF v_confirmed_language IS DISTINCT FROM 'yor'
     OR NEW.language_code IS DISTINCT FROM 'yor'
     OR v_review_source_id IS DISTINCT FROM NEW.source_media_artifact_id
     OR NEW.source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(NEW.story_id) THEN
    RAISE EXCEPTION 'Transcription requires the current source and its exact storyteller-confirmed Yoruba language review.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.source_language_reviews AS review
    WHERE review.story_id = NEW.story_id
      AND review.source_media_artifact_id = NEW.source_media_artifact_id
      AND review.id = NEW.language_review_id
      AND review.review_number = (
        SELECT max(candidate.review_number)
        FROM public.source_language_reviews AS candidate
        WHERE candidate.story_id = NEW.story_id
          AND candidate.source_media_artifact_id = NEW.source_media_artifact_id
          AND candidate.confirmed_language_code IS NOT NULL
      )
  ) THEN
    RAISE EXCEPTION 'Transcription must use the latest storyteller language confirmation.';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_transcript_segment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_duration_ms bigint;
  v_timebase_num integer;
  v_timebase_den integer;
BEGIN
  SELECT media.duration_ms, media.video_timebase_num, media.video_timebase_den
    INTO v_duration_ms, v_timebase_num, v_timebase_den
  FROM public.media_assets AS media
  WHERE media.story_id = NEW.story_id
    AND media.artifact_version_id = NEW.source_media_artifact_id;

  IF NEW.source_end_ms > v_duration_ms THEN
    RAISE EXCEPTION 'Transcript timestamps must fall within the referenced source media.';
  END IF;

  IF NEW.source_start_pts IS NOT NULL AND v_timebase_num IS NULL THEN
    RAISE EXCEPTION 'Source PTS values require the source media timebase.';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_story_cut_version()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(NEW.story_id)
     OR NOT irin_private.artifact_is_latest_approved(NEW.story_id, NEW.transcript_artifact_id, 'TRANSCRIPT') THEN
    RAISE EXCEPTION 'Craft requires the latest storyteller-approved transcript of the current source.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.transcript_versions AS transcript
    WHERE transcript.story_id = NEW.story_id
      AND transcript.artifact_version_id = NEW.transcript_artifact_id
      AND transcript.source_media_artifact_id = NEW.source_media_artifact_id
  ) THEN
    RAISE EXCEPTION 'Story Cut source and transcript lineage do not match.';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_story_cut_segment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_source_duration_ms bigint;
  v_cut_duration_ms bigint;
  v_timebase_num integer;
BEGIN
  SELECT media.duration_ms, media.video_timebase_num
    INTO v_source_duration_ms, v_timebase_num
  FROM public.media_assets AS media
  WHERE media.story_id = NEW.story_id
    AND media.artifact_version_id = NEW.source_media_artifact_id;

  SELECT cut.estimated_duration_ms INTO v_cut_duration_ms
  FROM public.story_cut_versions AS cut
  WHERE cut.story_id = NEW.story_id AND cut.artifact_version_id = NEW.cut_artifact_id;

  IF NEW.source_end_ms > v_source_duration_ms OR NEW.output_end_ms > v_cut_duration_ms THEN
    RAISE EXCEPTION 'Story Cut source or output timestamps exceed their referenced media timeline.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.transcript_segments AS transcript_segment
    WHERE transcript_segment.story_id = NEW.story_id
      AND transcript_segment.transcript_artifact_id = NEW.transcript_artifact_id
      AND transcript_segment.source_media_artifact_id = NEW.source_media_artifact_id
      AND transcript_segment.source_start_ms < NEW.source_end_ms
      AND transcript_segment.source_end_ms > NEW.source_start_ms
  ) THEN
    RAISE EXCEPTION 'Every Story Cut segment must overlap a segment from its exact approved transcript and source.';
  END IF;

  IF NEW.source_start_pts IS NOT NULL AND v_timebase_num IS NULL THEN
    RAISE EXCEPTION 'Story Cut PTS values require the source media timebase.';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_cultural_review_version()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT irin_private.artifact_is_latest_approved(NEW.story_id, NEW.story_cut_artifact_id, 'STORY_CUT') THEN
    RAISE EXCEPTION 'Cultural review requires the latest approved Story Cut.';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_translation_version()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.source_language_code IS DISTINCT FROM 'yor'
     OR NEW.target_language_code IS DISTINCT FROM 'eng' THEN
    RAISE EXCEPTION 'The MVP currently supports Yoruba source stories and English sharing only.';
  END IF;

  IF NEW.source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(NEW.story_id)
     OR NOT irin_private.artifact_is_latest_approved(NEW.story_id, NEW.transcript_artifact_id, 'TRANSCRIPT') THEN
    RAISE EXCEPTION 'Translation requires the current source and approved source transcript.';
  END IF;

  IF NOT irin_private.artifact_is_latest_approved(NEW.story_id, NEW.story_cut_artifact_id, 'STORY_CUT')
     OR NOT irin_private.artifact_is_latest_approved(NEW.story_id, NEW.cultural_review_artifact_id, 'CULTURAL_REVIEW') THEN
    RAISE EXCEPTION 'Translation requires the approved Story Cut and cultural review.';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_translation_segment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_cut_duration_ms bigint;
  v_segment_start_ms bigint;
  v_segment_end_ms bigint;
  v_source_start_ms bigint;
  v_source_end_ms bigint;
BEGIN
  SELECT cut.estimated_duration_ms INTO v_cut_duration_ms
  FROM public.story_cut_versions AS cut
  WHERE cut.story_id = NEW.story_id AND cut.artifact_version_id = NEW.story_cut_artifact_id;

  SELECT cut_segment.output_start_ms, cut_segment.output_end_ms,
         cut_segment.source_start_ms, cut_segment.source_end_ms
    INTO v_segment_start_ms, v_segment_end_ms, v_source_start_ms, v_source_end_ms
  FROM public.story_cut_segments AS cut_segment
  WHERE cut_segment.story_id = NEW.story_id
    AND cut_segment.id = NEW.cut_segment_id
    AND cut_segment.cut_artifact_id = NEW.story_cut_artifact_id;

  IF NEW.cue_end_ms > v_cut_duration_ms
     OR NEW.cue_start_ms < v_segment_start_ms
     OR NEW.cue_end_ms > v_segment_end_ms
     OR NOT EXISTS (
       SELECT 1 FROM public.transcript_segments AS transcript_segment
       WHERE transcript_segment.story_id = NEW.story_id
         AND transcript_segment.id = NEW.transcript_segment_id
         AND transcript_segment.transcript_artifact_id = NEW.transcript_artifact_id
         AND transcript_segment.source_media_artifact_id = NEW.source_media_artifact_id
         AND transcript_segment.source_start_ms < v_source_end_ms
         AND transcript_segment.source_end_ms > v_source_start_ms
     ) THEN
    RAISE EXCEPTION 'Subtitle cues must fit within their exact Story Cut segment timeline.';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_privacy_review_version()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT irin_private.artifact_is_latest_approved(NEW.story_id, NEW.translation_artifact_id, 'TRANSLATION')
     OR NOT irin_private.artifact_is_latest_approved(NEW.story_id, NEW.story_cut_artifact_id, 'STORY_CUT') THEN
    RAISE EXCEPTION 'Privacy review requires the latest approved cut and translation.';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_privacy_finding()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_review_cut_id uuid;
  v_review_translation_id uuid;
  v_review_source_id uuid;
  v_review_transcript_id uuid;
  v_source_duration_ms bigint;
BEGIN
  SELECT review.story_cut_artifact_id, review.translation_artifact_id,
         cut.source_media_artifact_id, cut.transcript_artifact_id
    INTO v_review_cut_id, v_review_translation_id, v_review_source_id, v_review_transcript_id
  FROM public.privacy_review_versions AS review
  JOIN public.story_cut_versions AS cut
    ON cut.story_id = review.story_id
   AND cut.artifact_version_id = review.story_cut_artifact_id
  WHERE review.story_id = NEW.story_id
    AND review.artifact_version_id = NEW.privacy_review_artifact_id;

  IF v_review_cut_id IS NULL THEN
    RAISE EXCEPTION 'Privacy finding requires an existing privacy-review version.';
  END IF;

  IF NEW.source_media_artifact_id IS NOT NULL THEN
    SELECT media.duration_ms INTO v_source_duration_ms
    FROM public.media_assets AS media
    WHERE media.story_id = NEW.story_id
      AND media.artifact_version_id = NEW.source_media_artifact_id;
    IF NEW.source_media_artifact_id <> v_review_source_id
       OR NEW.source_end_ms > v_source_duration_ms THEN
      RAISE EXCEPTION 'Source-timestamp privacy finding must anchor within the review source.';
    END IF;
  ELSIF NEW.transcript_segment_id IS NOT NULL THEN
    IF NEW.transcript_artifact_id IS DISTINCT FROM v_review_transcript_id THEN
      RAISE EXCEPTION 'Transcript privacy finding must use the review source transcript.';
    END IF;
  ELSIF NEW.cut_segment_id IS NOT NULL THEN
    IF NEW.story_cut_artifact_id IS DISTINCT FROM v_review_cut_id THEN
      RAISE EXCEPTION 'Story Cut privacy finding must use the review cut.';
    END IF;
  ELSIF NEW.translation_segment_id IS NOT NULL THEN
    IF NEW.translation_artifact_id IS DISTINCT FROM v_review_translation_id THEN
      RAISE EXCEPTION 'Translation privacy finding must use the review translation.';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_privacy_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_owner_id uuid;
  v_finding_created_at timestamptz;
  v_review_source_media_id uuid;
  v_review_transcript_id uuid;
  v_resolution_kind public.story_artifact_kind;
  v_resolution_created_at timestamptz;
  v_resolution_source_media_id uuid;
  v_resolution_transcript_id uuid;
BEGIN
  SELECT story.owner_id INTO v_owner_id
  FROM public.stories AS story
  WHERE story.id = NEW.story_id;

  IF v_owner_id IS NULL OR NEW.decided_by IS DISTINCT FROM v_owner_id THEN
    RAISE EXCEPTION 'Only the storyteller may resolve a privacy finding.';
  END IF;

  SELECT finding.created_at, cut.source_media_artifact_id, cut.transcript_artifact_id
    INTO v_finding_created_at, v_review_source_media_id, v_review_transcript_id
  FROM public.privacy_findings AS finding
  JOIN public.privacy_review_versions AS review
    ON review.story_id = finding.story_id
   AND review.artifact_version_id = finding.privacy_review_artifact_id
  JOIN public.story_cut_versions AS cut
    ON cut.story_id = review.story_id
   AND cut.artifact_version_id = review.story_cut_artifact_id
  WHERE finding.story_id = NEW.story_id AND finding.id = NEW.privacy_finding_id;

  IF v_finding_created_at IS NULL THEN
    RAISE EXCEPTION 'Privacy decision must reference an existing finding.';
  END IF;

  IF NEW.decision <> 'KEEP' THEN
    SELECT artifact.kind, artifact.created_at
      INTO v_resolution_kind, v_resolution_created_at
    FROM public.artifact_versions AS artifact
    WHERE artifact.story_id = NEW.story_id
      AND artifact.id = NEW.resolution_artifact_version_id
      AND artifact.sealed_at IS NOT NULL;

    IF v_resolution_kind = 'STORY_CUT' THEN
      SELECT cut.source_media_artifact_id, cut.transcript_artifact_id
        INTO v_resolution_source_media_id, v_resolution_transcript_id
      FROM public.story_cut_versions AS cut
      WHERE cut.story_id = NEW.story_id
        AND cut.artifact_version_id = NEW.resolution_artifact_version_id;
    ELSIF v_resolution_kind = 'TRANSLATION' THEN
      SELECT translation.source_media_artifact_id, translation.transcript_artifact_id
        INTO v_resolution_source_media_id, v_resolution_transcript_id
      FROM public.translation_versions AS translation
      WHERE translation.story_id = NEW.story_id
        AND translation.artifact_version_id = NEW.resolution_artifact_version_id;
    END IF;

    IF v_resolution_kind IS NULL
       OR v_resolution_kind NOT IN ('STORY_CUT', 'TRANSLATION')
       OR v_resolution_created_at IS NULL
       OR v_resolution_created_at <= v_finding_created_at
       OR v_resolution_source_media_id IS DISTINCT FROM v_review_source_media_id
       OR v_resolution_transcript_id IS DISTINCT FROM v_review_transcript_id
       OR NOT coalesce(irin_private.artifact_is_latest_approved(
         NEW.story_id, NEW.resolution_artifact_version_id, v_resolution_kind
       ), false) THEN
      RAISE EXCEPTION 'Generalise, Anonymise, or Remove must reference a later approved edit version with the finding source lineage.';
    END IF;
  END IF;

  NEW.decided_at := clock_timestamp();
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_covenant_permission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.artifact_versions AS artifact
    WHERE artifact.story_id = NEW.story_id
      AND artifact.id = NEW.covenant_artifact_id
      AND artifact.kind = 'COVENANT'
      AND artifact.sealed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Covenant permissions must be assembled before their Covenant version is sealed.';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_covenant_approval(
  p_story_id uuid,
  p_artifact_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_permission_count integer;
BEGIN
  SELECT count(*) INTO v_permission_count
  FROM public.covenant_permissions AS permission
  WHERE permission.story_id = p_story_id
    AND permission.covenant_artifact_id = p_artifact_id;

  IF v_permission_count <> 10 THEN
    RAISE EXCEPTION 'Covenant approval requires all ten explicit permission decisions.';
  END IF;

  IF NOT irin_private.artifact_is_latest(p_story_id, p_artifact_id, 'COVENANT') THEN
    RAISE EXCEPTION 'Only the latest Covenant version may be activated.';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_owner_id uuid;
  v_artifact_kind public.story_artifact_kind;
  v_artifact_hash bytea;
  v_is_sealed boolean;
  v_source_id uuid;
  v_language_review_id uuid;
  v_transcript_id uuid;
  v_cut_id uuid;
  v_cultural_id uuid;
  v_translation_id uuid;
  v_privacy_id uuid;
  v_media_id uuid;
  v_estimated_duration_ms bigint;
BEGIN
  SELECT story.owner_id INTO v_owner_id
  FROM public.stories AS story WHERE story.id = NEW.story_id;

  IF v_owner_id IS NULL OR NEW.approver_id IS DISTINCT FROM v_owner_id THEN
    RAISE EXCEPTION 'Approval must be made by the owning storyteller.';
  END IF;

  IF NEW.artifact_version_id IS NOT NULL THEN
    SELECT artifact.kind, artifact.content_sha256, artifact.sealed_at IS NOT NULL
      INTO v_artifact_kind, v_artifact_hash, v_is_sealed
    FROM public.artifact_versions AS artifact
    WHERE artifact.story_id = NEW.story_id AND artifact.id = NEW.artifact_version_id;

    IF v_artifact_kind IS NULL OR NOT v_is_sealed
       OR NEW.approved_content_sha256 IS DISTINCT FROM v_artifact_hash THEN
      RAISE EXCEPTION 'Approval must bind to the exact hash of a sealed artefact version.';
    END IF;

    IF NEW.decision = 'REJECT' THEN
      RETURN NEW;
    END IF;

    CASE v_artifact_kind
      WHEN 'TRANSCRIPT' THEN
        SELECT transcript.source_media_artifact_id, transcript.language_review_id
          INTO v_source_id, v_language_review_id
        FROM public.transcript_versions AS transcript
        WHERE transcript.story_id = NEW.story_id
          AND transcript.artifact_version_id = NEW.artifact_version_id;
        IF NOT irin_private.artifact_is_latest(NEW.story_id, NEW.artifact_version_id, 'TRANSCRIPT')
           OR v_source_id IS DISTINCT FROM irin_private.latest_source_media_id(NEW.story_id)
           OR NOT EXISTS (
             SELECT 1 FROM public.source_language_reviews AS review
             JOIN public.transcript_versions AS transcript
               ON transcript.story_id = review.story_id
              AND transcript.language_review_id = review.id
              AND transcript.source_media_artifact_id = review.source_media_artifact_id
             WHERE transcript.story_id = NEW.story_id
               AND transcript.artifact_version_id = NEW.artifact_version_id
               AND review.id = v_language_review_id
               AND review.confirmed_language_code = 'yor'
               AND review.confirmed_by = v_owner_id
               AND review.review_number = (
                 SELECT max(candidate.review_number)
                 FROM public.source_language_reviews AS candidate
                 WHERE candidate.story_id = review.story_id
                   AND candidate.source_media_artifact_id = review.source_media_artifact_id
                   AND candidate.confirmed_language_code IS NOT NULL
               )
           ) THEN
          RAISE EXCEPTION 'Source approval must target the latest transcript and storyteller-confirmed Yoruba review of the current source.';
        END IF;
      WHEN 'STORY_CUT' THEN
        SELECT cut.source_media_artifact_id, cut.transcript_artifact_id, cut.estimated_duration_ms
          INTO v_source_id, v_transcript_id, v_estimated_duration_ms
        FROM public.story_cut_versions AS cut
        WHERE cut.story_id = NEW.story_id AND cut.artifact_version_id = NEW.artifact_version_id;
        IF NOT irin_private.artifact_is_latest(NEW.story_id, NEW.artifact_version_id, 'STORY_CUT')
           OR v_source_id IS DISTINCT FROM irin_private.latest_source_media_id(NEW.story_id)
           OR NOT irin_private.artifact_is_latest_approved(NEW.story_id, v_transcript_id, 'TRANSCRIPT')
           OR NOT EXISTS (
             SELECT 1 FROM public.transcript_versions AS transcript
             WHERE transcript.story_id = NEW.story_id
               AND transcript.artifact_version_id = v_transcript_id
               AND transcript.source_media_artifact_id = v_source_id
           )
           OR EXISTS (
             SELECT 1 FROM public.story_cut_segments AS segment
             WHERE segment.story_id = NEW.story_id
               AND segment.cut_artifact_id = NEW.artifact_version_id
               AND segment.decision <> 'KEEP'
           )
           OR NOT EXISTS (
             SELECT 1 FROM public.story_cut_segments AS segment
             WHERE segment.story_id = NEW.story_id
               AND segment.cut_artifact_id = NEW.artifact_version_id
           ) THEN
          RAISE EXCEPTION 'Story Cut approval requires the current approved source and only kept clips with transcript lineage.';
        END IF;
      WHEN 'CULTURAL_REVIEW' THEN
        SELECT review.story_cut_artifact_id INTO v_cut_id
        FROM public.cultural_review_versions AS review
        WHERE review.story_id = NEW.story_id
          AND review.artifact_version_id = NEW.artifact_version_id;
        IF NOT irin_private.artifact_is_latest(NEW.story_id, NEW.artifact_version_id, 'CULTURAL_REVIEW')
           OR NOT irin_private.artifact_is_latest_approved(NEW.story_id, v_cut_id, 'STORY_CUT') THEN
          RAISE EXCEPTION 'Cultural approval must reference the latest approved Story Cut.';
        END IF;
      WHEN 'TRANSLATION' THEN
        SELECT translation.source_media_artifact_id, translation.transcript_artifact_id,
               translation.story_cut_artifact_id, translation.cultural_review_artifact_id
          INTO v_source_id, v_transcript_id, v_cut_id, v_cultural_id
        FROM public.translation_versions AS translation
        WHERE translation.story_id = NEW.story_id
          AND translation.artifact_version_id = NEW.artifact_version_id;
        IF NOT irin_private.artifact_is_latest(NEW.story_id, NEW.artifact_version_id, 'TRANSLATION')
           OR v_source_id IS DISTINCT FROM irin_private.latest_source_media_id(NEW.story_id)
           OR NOT irin_private.artifact_is_latest_approved(NEW.story_id, v_transcript_id, 'TRANSCRIPT')
           OR NOT irin_private.artifact_is_latest_approved(NEW.story_id, v_cut_id, 'STORY_CUT')
           OR NOT irin_private.artifact_is_latest_approved(NEW.story_id, v_cultural_id, 'CULTURAL_REVIEW') THEN
          RAISE EXCEPTION 'Translation approval requires the current approved source, cut, and cultural review.';
        END IF;
      WHEN 'PRIVACY_REVIEW' THEN
        SELECT review.story_cut_artifact_id, review.translation_artifact_id
          INTO v_cut_id, v_translation_id
        FROM public.privacy_review_versions AS review
        WHERE review.story_id = NEW.story_id
          AND review.artifact_version_id = NEW.artifact_version_id;
        IF NOT irin_private.artifact_is_latest(NEW.story_id, NEW.artifact_version_id, 'PRIVACY_REVIEW')
           OR NOT irin_private.artifact_is_latest_approved(NEW.story_id, v_cut_id, 'STORY_CUT')
           OR NOT irin_private.artifact_is_latest_approved(NEW.story_id, v_translation_id, 'TRANSLATION')
           OR EXISTS (
             SELECT 1 FROM public.privacy_findings AS finding
             LEFT JOIN public.privacy_decisions AS decision
               ON decision.story_id = finding.story_id
              AND decision.privacy_finding_id = finding.id
             WHERE finding.story_id = NEW.story_id
               AND finding.privacy_review_artifact_id = NEW.artifact_version_id
               AND decision.id IS NULL
           ) THEN
          RAISE EXCEPTION 'Privacy approval requires the current cut and translation and a storyteller decision for every finding.';
        END IF;
      WHEN 'COVENANT' THEN
        PERFORM irin_private.guard_covenant_approval(NEW.story_id, NEW.artifact_version_id);
      WHEN 'SOURCE_MEDIA' THEN
        RAISE EXCEPTION 'Source media is approved as part of its exact Yoruba transcript/source package.';
      WHEN 'RENDERED_MEDIA' THEN
        RAISE EXCEPTION 'Rendered media is approved as part of its immutable publication snapshot.';
    END CASE;
  ELSE
    IF NEW.publication_snapshot_id IS NULL THEN
      RAISE EXCEPTION 'Approval target is missing.';
    END IF;

    IF NEW.decision = 'APPROVE' THEN
      IF NEW.approved_content_sha256 IS DISTINCT FROM (
        SELECT snapshot.manifest_sha256
        FROM public.publication_snapshots AS snapshot
        WHERE snapshot.story_id = NEW.story_id
          AND snapshot.id = NEW.publication_snapshot_id
      ) THEN
        RAISE EXCEPTION 'Publication approval must bind to the exact immutable manifest hash.';
      END IF;
      PERFORM irin_private.validate_publication_snapshot(NEW.publication_snapshot_id);
    ELSIF NOT EXISTS (
      SELECT 1 FROM public.publication_snapshots AS snapshot
      WHERE snapshot.story_id = NEW.story_id
        AND snapshot.id = NEW.publication_snapshot_id
        AND snapshot.manifest_sha256 = NEW.approved_content_sha256
    ) THEN
      RAISE EXCEPTION 'Publication rejection must identify the exact immutable manifest hash.';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- SECURITY: Every snapshot is revalidated in the database at creation, approval, and activation; the caller cannot bypass publication gates with a crafted client request.
CREATE OR REPLACE FUNCTION irin_private.validate_publication_snapshot(p_snapshot_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_snapshot public.publication_snapshots%ROWTYPE;
  v_owner_id uuid;
  v_cut_duration_ms bigint;
  v_permission_count integer;
BEGIN
  SELECT snapshot.* INTO v_snapshot
  FROM public.publication_snapshots AS snapshot
  WHERE snapshot.id = p_snapshot_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Publication snapshot does not exist.';
  END IF;

  SELECT story.owner_id INTO v_owner_id
  FROM public.stories AS story WHERE story.id = v_snapshot.story_id;

  IF v_snapshot.created_by IS DISTINCT FROM v_owner_id
     OR v_snapshot.original_language_code <> 'yor'
     OR v_snapshot.share_language_code <> 'eng'
     OR NOT v_snapshot.ai_editing_disclosed
     OR NOT v_snapshot.ai_translation_disclosed THEN
    RAISE EXCEPTION 'Publication snapshot must be owner-created, Yoruba-to-English, and disclose AI-assisted editing and translation.';
  END IF;

  IF v_snapshot.source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(v_snapshot.story_id)
     OR NOT EXISTS (
       SELECT 1 FROM public.artifact_versions AS artifact
       JOIN public.media_assets AS media
         ON media.story_id = artifact.story_id
        AND media.artifact_version_id = artifact.id
       WHERE artifact.story_id = v_snapshot.story_id
         AND artifact.id = v_snapshot.source_media_artifact_id
         AND artifact.kind = 'SOURCE_MEDIA'
         AND artifact.sealed_at IS NOT NULL
         AND media.role = 'SOURCE'
     ) THEN
    RAISE EXCEPTION 'Publication must reference the current private original source media version.';
  END IF;

  IF NOT irin_private.artifact_is_latest_approved(v_snapshot.story_id, v_snapshot.transcript_artifact_id, 'TRANSCRIPT')
     OR NOT EXISTS (
       SELECT 1 FROM public.transcript_versions AS transcript
       WHERE transcript.story_id = v_snapshot.story_id
         AND transcript.artifact_version_id = v_snapshot.transcript_artifact_id
         AND transcript.source_media_artifact_id = v_snapshot.source_media_artifact_id
         AND transcript.language_code = 'yor'
     ) THEN
    RAISE EXCEPTION 'Publication must reference the approved Yoruba transcript of the exact current source version.';
  END IF;

  IF NOT irin_private.artifact_is_latest_approved(v_snapshot.story_id, v_snapshot.story_cut_artifact_id, 'STORY_CUT')
     OR NOT EXISTS (
       SELECT 1 FROM public.story_cut_versions AS cut
       WHERE cut.story_id = v_snapshot.story_id
         AND cut.artifact_version_id = v_snapshot.story_cut_artifact_id
         AND cut.source_media_artifact_id = v_snapshot.source_media_artifact_id
         AND cut.transcript_artifact_id = v_snapshot.transcript_artifact_id
     )
     OR EXISTS (
       SELECT 1 FROM public.story_cut_segments AS segment
       WHERE segment.story_id = v_snapshot.story_id
         AND segment.cut_artifact_id = v_snapshot.story_cut_artifact_id
         AND segment.decision <> 'KEEP'
     ) THEN
    RAISE EXCEPTION 'Publication must reference the approved Story Cut derived from the approved source package.';
  END IF;

  SELECT cut.estimated_duration_ms INTO v_cut_duration_ms
  FROM public.story_cut_versions AS cut
  WHERE cut.story_id = v_snapshot.story_id
    AND cut.artifact_version_id = v_snapshot.story_cut_artifact_id;

  IF NOT irin_private.artifact_is_latest_approved(v_snapshot.story_id, v_snapshot.cultural_review_artifact_id, 'CULTURAL_REVIEW')
     OR NOT EXISTS (
       SELECT 1 FROM public.cultural_review_versions AS review
       WHERE review.story_id = v_snapshot.story_id
         AND review.artifact_version_id = v_snapshot.cultural_review_artifact_id
         AND review.story_cut_artifact_id = v_snapshot.story_cut_artifact_id
     ) THEN
    RAISE EXCEPTION 'Publication requires the approved cultural review for this exact Story Cut.';
  END IF;

  IF NOT irin_private.artifact_is_latest_approved(v_snapshot.story_id, v_snapshot.translation_artifact_id, 'TRANSLATION')
     OR NOT EXISTS (
       SELECT 1 FROM public.translation_versions AS translation
       WHERE translation.story_id = v_snapshot.story_id
         AND translation.artifact_version_id = v_snapshot.translation_artifact_id
         AND translation.source_media_artifact_id = v_snapshot.source_media_artifact_id
         AND translation.transcript_artifact_id = v_snapshot.transcript_artifact_id
         AND translation.story_cut_artifact_id = v_snapshot.story_cut_artifact_id
         AND translation.cultural_review_artifact_id = v_snapshot.cultural_review_artifact_id
         AND translation.source_language_code = 'yor'
         AND translation.target_language_code = 'eng'
     )
     OR NOT EXISTS (
       SELECT 1 FROM public.translation_segments AS segment
       WHERE segment.story_id = v_snapshot.story_id
         AND segment.translation_artifact_id = v_snapshot.translation_artifact_id
         AND segment.cue_end_ms <= v_cut_duration_ms
     ) THEN
    RAISE EXCEPTION 'Publication requires the approved English translation tied to the exact approved Yoruba source and Story Cut versions.';
  END IF;

  IF NOT irin_private.artifact_is_latest_approved(v_snapshot.story_id, v_snapshot.privacy_review_artifact_id, 'PRIVACY_REVIEW')
     OR NOT EXISTS (
       SELECT 1 FROM public.privacy_review_versions AS review
       WHERE review.story_id = v_snapshot.story_id
         AND review.artifact_version_id = v_snapshot.privacy_review_artifact_id
         AND review.story_cut_artifact_id = v_snapshot.story_cut_artifact_id
         AND review.translation_artifact_id = v_snapshot.translation_artifact_id
     )
     OR EXISTS (
       SELECT 1 FROM public.privacy_findings AS finding
       LEFT JOIN public.privacy_decisions AS decision
         ON decision.story_id = finding.story_id
        AND decision.privacy_finding_id = finding.id
       WHERE finding.story_id = v_snapshot.story_id
         AND finding.privacy_review_artifact_id = v_snapshot.privacy_review_artifact_id
         AND decision.id IS NULL
     ) THEN
    RAISE EXCEPTION 'Publication requires an approved privacy review with every finding resolved by the storyteller.';
  END IF;

  IF irin_private.active_covenant_id(v_snapshot.story_id) IS DISTINCT FROM v_snapshot.covenant_artifact_id
     OR NOT EXISTS (
       SELECT 1 FROM public.covenant_permissions AS permission
       WHERE permission.story_id = v_snapshot.story_id
         AND permission.covenant_artifact_id = v_snapshot.covenant_artifact_id
         AND permission.permission = 'PUBLIC_VIEWING'
         AND permission.allowed
     ) THEN
    RAISE EXCEPTION 'Publication requires the active approved Covenant with explicit public-viewing permission.';
  END IF;

  SELECT count(*) INTO v_permission_count
  FROM public.covenant_permissions AS permission
  WHERE permission.story_id = v_snapshot.story_id
    AND permission.covenant_artifact_id = v_snapshot.covenant_artifact_id;

  IF v_permission_count <> 10 THEN
    RAISE EXCEPTION 'Publication requires all ten explicit Covenant permissions.';
  END IF;

  IF NOT irin_private.artifact_is_latest(v_snapshot.story_id, v_snapshot.rendered_media_artifact_id, 'RENDERED_MEDIA')
     OR NOT EXISTS (
       SELECT 1 FROM public.media_assets AS media
       WHERE media.story_id = v_snapshot.story_id
         AND media.artifact_version_id = v_snapshot.rendered_media_artifact_id
         AND media.story_cut_artifact_id = v_snapshot.story_cut_artifact_id
         AND media.translation_artifact_id = v_snapshot.translation_artifact_id
         AND media.role = 'FINAL_PUBLICATION'
     ) THEN
    RAISE EXCEPTION 'Publication must reference the latest final-render metadata for its exact approved cut and translation.';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.publication_snapshot_is_valid(p_snapshot_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  PERFORM irin_private.validate_publication_snapshot(p_snapshot_id);
  RETURN true;
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$function$;

-- Public reads go through a narrow RPC. SECURITY DEFINER is required because
-- anonymous callers receive no grants on private base tables. The explicit predicates
-- require current publication state, exact publication approval and active Covenant.
CREATE OR REPLACE FUNCTION public.get_published_story(p_public_id uuid)
RETURNS TABLE (
  public_id uuid,
  title text,
  original_language_code text,
  share_language_code text,
  ai_editing_disclosed boolean,
  ai_translation_disclosed boolean,
  published_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT snapshot.public_id,
         snapshot.title,
         snapshot.original_language_code,
         snapshot.share_language_code,
         snapshot.ai_editing_disclosed,
         snapshot.ai_translation_disclosed,
         access.published_at
  FROM public.publication_snapshots AS snapshot
  JOIN public.publication_access AS access
    ON access.story_id = snapshot.story_id
   AND access.publication_snapshot_id = snapshot.id
  JOIN public.stories AS story ON story.id = snapshot.story_id
  JOIN public.approvals AS approval
    ON approval.story_id = snapshot.story_id
   AND approval.publication_snapshot_id = snapshot.id
   AND approval.decision = 'APPROVE'
   AND approval.approved_content_sha256 = snapshot.manifest_sha256
  WHERE snapshot.public_id = p_public_id
    AND access.access_state = 'PUBLISHED'
    AND story.workflow_state = 'PUBLISHED'
    AND snapshot.snapshot_version = (
      SELECT max(latest.snapshot_version)
      FROM public.publication_snapshots AS latest
      WHERE latest.story_id = snapshot.story_id
    )
    AND irin_private.active_covenant_id(snapshot.story_id) = snapshot.covenant_artifact_id
    AND EXISTS (
      SELECT 1 FROM public.covenant_permissions AS permission
      WHERE permission.story_id = snapshot.story_id
        AND permission.covenant_artifact_id = snapshot.covenant_artifact_id
        AND permission.permission = 'PUBLIC_VIEWING'
        AND permission.allowed
    )
    AND irin_private.publication_snapshot_is_valid(snapshot.id);
$function$;

COMMENT ON FUNCTION public.get_published_story(uuid) IS
  'Minimal public lookup for explicitly published records. It returns no private artefact IDs, storage keys, or owner IDs.';

-- SECURITY: SECURITY DEFINER avoids recursive RLS evaluation on stories; the function has a fixed empty search path and exposes only the caller's ownership boolean.
CREATE OR REPLACE FUNCTION irin_private.guard_publication_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Publication snapshots are immutable and cannot be deleted.';
  END IF;

  PERFORM 1 FROM public.stories AS story
  WHERE story.id = NEW.story_id
  FOR UPDATE;

  IF NEW.snapshot_version <> coalesce((
    SELECT max(snapshot.snapshot_version)
    FROM public.publication_snapshots AS snapshot
    WHERE snapshot.story_id = NEW.story_id
  ), 0) + 1 THEN
    RAISE EXCEPTION 'Publication snapshot versions must increase by one.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.stories AS story
    WHERE story.id = NEW.story_id AND story.owner_id = NEW.created_by
  ) THEN
    RAISE EXCEPTION 'Publication snapshot creator must be the story owner.';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.validate_publication_snapshot_after_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  PERFORM irin_private.validate_publication_snapshot(NEW.id);
  RETURN NEW;
END;
$function$;

-- SECURITY: Only explicit public snapshots can enter PUBLISHED. Withdrawal and staleness are one-way access transitions; the snapshot itself remains unchanged.
CREATE OR REPLACE FUNCTION irin_private.guard_publication_access()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_owner_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Publication access history cannot be deleted.';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.access_state <> 'DRAFT'
       OR NEW.published_at IS NOT NULL
       OR NEW.published_by IS NOT NULL
       OR NEW.stale_at IS NOT NULL
       OR NEW.withdrawn_at IS NOT NULL
       OR NEW.withdrawn_by IS NOT NULL THEN
      RAISE EXCEPTION 'A publication access record must begin in DRAFT.';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.story_id IS DISTINCT FROM OLD.story_id
     OR NEW.publication_snapshot_id IS DISTINCT FROM OLD.publication_snapshot_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Publication access identity is immutable.';
  END IF;

  IF NEW.access_state = OLD.access_state THEN
    RAISE EXCEPTION 'Publication access changes must use a valid state transition.';
  END IF;

  IF OLD.access_state = 'DRAFT' AND NEW.access_state = 'PUBLISHED' THEN
    IF auth.uid() IS NOT NULL THEN
      RAISE EXCEPTION 'Publication activation is a server-side workflow transition.';
    END IF;
    SELECT story.owner_id INTO v_owner_id
    FROM public.stories AS story WHERE story.id = NEW.story_id;
    IF NEW.published_by IS DISTINCT FROM v_owner_id THEN
      RAISE EXCEPTION 'Publication activation must record the owning storyteller.';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.stories AS story
      WHERE story.id = NEW.story_id AND story.workflow_state = 'PUBLICATION_REVIEW'
    ) OR NOT EXISTS (
      SELECT 1 FROM public.approvals AS approval
      JOIN public.publication_snapshots AS snapshot
        ON snapshot.story_id = approval.story_id
       AND snapshot.id = approval.publication_snapshot_id
      WHERE approval.story_id = NEW.story_id
        AND approval.publication_snapshot_id = NEW.publication_snapshot_id
        AND approval.decision = 'APPROVE'
        AND approval.approved_content_sha256 = snapshot.manifest_sha256
    ) THEN
      RAISE EXCEPTION 'Publishing requires publication-review state and approval of the exact snapshot.';
    END IF;
    PERFORM irin_private.validate_publication_snapshot(NEW.publication_snapshot_id);
    NEW.published_at := clock_timestamp();
    NEW.published_by := v_owner_id;
    NEW.stale_at := NULL;
    NEW.withdrawn_at := NULL;
    NEW.withdrawn_by := NULL;
  ELSIF OLD.access_state = 'PUBLISHED' AND NEW.access_state = 'STALE' THEN
    IF auth.uid() IS NOT NULL THEN
      RAISE EXCEPTION 'Staling a publication is an internal source or artefact transition.';
    END IF;
    NEW.published_at := OLD.published_at;
    NEW.published_by := OLD.published_by;
    NEW.stale_at := clock_timestamp();
    NEW.withdrawn_at := NULL;
    NEW.withdrawn_by := NULL;
  ELSIF OLD.access_state = 'PUBLISHED' AND NEW.access_state = 'WITHDRAWN' THEN
    SELECT story.owner_id INTO v_owner_id
    FROM public.stories AS story WHERE story.id = NEW.story_id;
    IF auth.uid() IS NOT NULL AND auth.uid() IS DISTINCT FROM v_owner_id THEN
      RAISE EXCEPTION 'Only the storyteller may withdraw a publication.';
    END IF;
    IF auth.uid() IS NOT NULL THEN
      NEW.withdrawn_by := auth.uid();
    ELSIF NEW.withdrawn_by IS DISTINCT FROM v_owner_id THEN
      RAISE EXCEPTION 'Internal withdrawal must record the owning storyteller as actor.';
    END IF;
    NEW.published_at := OLD.published_at;
    NEW.published_by := OLD.published_by;
    NEW.stale_at := NULL;
    NEW.withdrawn_at := clock_timestamp();
  ELSE
    RAISE EXCEPTION 'Invalid publication access transition: % -> %.', OLD.access_state, NEW.access_state;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.after_publication_access_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_event public.audit_event_type;
BEGIN
  IF NEW.access_state = 'PUBLISHED' AND OLD.access_state IS DISTINCT FROM 'PUBLISHED' THEN
    UPDATE public.publication_access AS prior_access
    SET access_state = 'STALE'
    WHERE prior_access.story_id = NEW.story_id
      AND prior_access.publication_snapshot_id <> NEW.publication_snapshot_id
      AND prior_access.access_state = 'PUBLISHED';

    UPDATE public.stories AS story
    SET workflow_state = 'PUBLISHED'
    WHERE story.id = NEW.story_id
      AND story.workflow_state = 'PUBLICATION_REVIEW';

    v_event := 'PUBLICATION_PUBLISHED';
  ELSIF NEW.access_state = 'WITHDRAWN' AND OLD.access_state IS DISTINCT FROM 'WITHDRAWN' THEN
    UPDATE public.stories AS story
    SET workflow_state = 'WITHDRAWN'
    WHERE story.id = NEW.story_id
      AND story.workflow_state = 'PUBLISHED';

    v_event := 'PUBLICATION_WITHDRAWN';
  ELSIF NEW.access_state = 'STALE' AND OLD.access_state IS DISTINCT FROM 'STALE' THEN
    v_event := 'PUBLICATION_STALE';
  ELSE
    RETURN NEW;
  END IF;

  PERFORM irin_private.emit_audit_event(
    NEW.story_id,
    CASE
      WHEN v_event = 'PUBLICATION_WITHDRAWN' THEN NEW.withdrawn_by
      WHEN v_event = 'PUBLICATION_PUBLISHED' THEN NEW.published_by
      WHEN v_event = 'PUBLICATION_STALE' THEN NULL
      ELSE auth.uid()
    END,
    v_event,
    NULL,
    NEW.publication_snapshot_id,
    '{}'::jsonb,
    NULL,
    NULL
  );

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.after_artifact_sealed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_event public.audit_event_type;
  v_rework_state public.story_workflow_state;
BEGIN
  v_event := CASE NEW.kind
    WHEN 'SOURCE_MEDIA' THEN 'MEDIA_REGISTERED'::public.audit_event_type
    WHEN 'TRANSCRIPT' THEN 'TRANSCRIPT_VERSION_CREATED'::public.audit_event_type
    WHEN 'STORY_CUT' THEN 'STORY_CUT_VERSION_CREATED'::public.audit_event_type
    WHEN 'CULTURAL_REVIEW' THEN 'CULTURAL_REVIEW_CREATED'::public.audit_event_type
    WHEN 'TRANSLATION' THEN 'TRANSLATION_CREATED'::public.audit_event_type
    WHEN 'PRIVACY_REVIEW' THEN 'PRIVACY_REVIEW_CREATED'::public.audit_event_type
    WHEN 'COVENANT' THEN 'COVENANT_CREATED'::public.audit_event_type
    ELSE NULL
  END;

  IF v_event IS NOT NULL THEN
    PERFORM irin_private.emit_audit_event(
      NEW.story_id, NEW.created_by, v_event, NEW.id, NULL, '{}'::jsonb, NULL, NULL
    );
  END IF;

  UPDATE public.publication_access AS access
  SET access_state = 'STALE'
  WHERE access.story_id = NEW.story_id
    AND access.access_state = 'PUBLISHED';

  v_rework_state := CASE NEW.kind
    WHEN 'SOURCE_MEDIA' THEN 'MEDIA_READY'::public.story_workflow_state
    WHEN 'TRANSCRIPT' THEN 'SOURCE_REVIEW'::public.story_workflow_state
    WHEN 'STORY_CUT' THEN 'CRAFT_REVIEW'::public.story_workflow_state
    WHEN 'CULTURAL_REVIEW' THEN 'CRAFT_REVIEW'::public.story_workflow_state
    WHEN 'TRANSLATION' THEN 'TRANSLATION_REVIEW'::public.story_workflow_state
    WHEN 'PRIVACY_REVIEW' THEN 'PRIVACY_REVIEW'::public.story_workflow_state
    WHEN 'COVENANT' THEN 'COVENANT_REVIEW'::public.story_workflow_state
    WHEN 'RENDERED_MEDIA' THEN 'PUBLICATION_REVIEW'::public.story_workflow_state
  END;

  -- Every newly sealed version returns the workflow to its affected review stage,
  -- even before the first publication. Old exact approvals remain historical,
  -- while dependency-aware approval checks make stale descendants unusable.
  UPDATE public.stories AS story
  SET workflow_state = v_rework_state
  WHERE story.id = NEW.story_id
    AND story.workflow_state IS DISTINCT FROM v_rework_state;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_final_publication_media()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_privacy_review_id uuid;
  v_covenant_id uuid;
BEGIN
  IF NOT irin_private.artifact_is_latest_approved(NEW.story_id, NEW.story_cut_artifact_id, 'STORY_CUT')
     OR NOT irin_private.artifact_is_latest_approved(NEW.story_id, NEW.translation_artifact_id, 'TRANSLATION') THEN
    RAISE EXCEPTION 'Final media requires the exact current approved Story Cut and translation.';
  END IF;

  SELECT review.artifact_version_id INTO v_privacy_review_id
  FROM public.privacy_review_versions AS review
  JOIN public.artifact_versions AS artifact
    ON artifact.story_id = review.story_id
   AND artifact.id = review.artifact_version_id
  WHERE review.story_id = NEW.story_id
    AND review.story_cut_artifact_id = NEW.story_cut_artifact_id
    AND review.translation_artifact_id = NEW.translation_artifact_id
  ORDER BY artifact.version_number DESC
  LIMIT 1;

  IF v_privacy_review_id IS NULL
     OR NOT irin_private.artifact_is_latest_approved(NEW.story_id, v_privacy_review_id, 'PRIVACY_REVIEW')
     OR EXISTS (
       SELECT 1 FROM public.privacy_findings AS finding
       LEFT JOIN public.privacy_decisions AS decision
         ON decision.story_id = finding.story_id
        AND decision.privacy_finding_id = finding.id
       WHERE finding.story_id = NEW.story_id
         AND finding.privacy_review_artifact_id = v_privacy_review_id
         AND decision.id IS NULL
     ) THEN
    RAISE EXCEPTION 'Final media requires the current completed privacy review.';
  END IF;

  v_covenant_id := irin_private.active_covenant_id(NEW.story_id);
  IF v_covenant_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.covenant_permissions AS permission
    WHERE permission.story_id = NEW.story_id
      AND permission.covenant_artifact_id = v_covenant_id
      AND permission.permission = 'PUBLIC_VIEWING'
      AND permission.allowed
  ) THEN
    RAISE EXCEPTION 'Final media requires an active Covenant that explicitly permits public viewing.';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION irin_private.guard_story_state_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_latest_source uuid;
  v_latest_transcript uuid;
  v_latest_cut uuid;
  v_latest_translation uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.workflow_state <> 'DRAFT' THEN
      RAISE EXCEPTION 'A new story must begin in DRAFT.';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.owner_id IS DISTINCT FROM OLD.owner_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Story identity and ownership are immutable.';
  END IF;
  NEW.updated_at := clock_timestamp();

  IF NEW.workflow_state = OLD.workflow_state THEN
    RETURN NEW;
  END IF;

  IF NOT (
    (OLD.workflow_state = 'DRAFT' AND NEW.workflow_state = 'MEDIA_READY')
    OR (OLD.workflow_state = 'MEDIA_READY' AND NEW.workflow_state = 'LANGUAGE_CONFIRMATION')
    OR (OLD.workflow_state = 'LANGUAGE_CONFIRMATION' AND NEW.workflow_state = 'TRANSCRIBING')
    OR (OLD.workflow_state = 'TRANSCRIBING' AND NEW.workflow_state = 'SOURCE_REVIEW')
    OR (OLD.workflow_state = 'SOURCE_REVIEW' AND NEW.workflow_state IN ('TRANSCRIBING', 'SOURCE_APPROVED'))
    OR (OLD.workflow_state = 'SOURCE_APPROVED' AND NEW.workflow_state = 'CRAFTING')
    OR (OLD.workflow_state = 'CRAFTING' AND NEW.workflow_state = 'CRAFT_REVIEW')
    OR (OLD.workflow_state = 'CRAFT_REVIEW' AND NEW.workflow_state IN ('CRAFTING', 'CRAFT_APPROVED'))
    OR (OLD.workflow_state = 'CRAFT_APPROVED' AND NEW.workflow_state = 'TRANSLATING')
    OR (OLD.workflow_state = 'TRANSLATING' AND NEW.workflow_state = 'TRANSLATION_REVIEW')
    OR (OLD.workflow_state = 'TRANSLATION_REVIEW' AND NEW.workflow_state IN ('TRANSLATING', 'TRANSLATION_APPROVED'))
    OR (OLD.workflow_state = 'TRANSLATION_APPROVED' AND NEW.workflow_state = 'PRIVACY_REVIEW')
    OR (OLD.workflow_state = 'PRIVACY_REVIEW' AND NEW.workflow_state = 'COVENANT_REVIEW')
    OR (OLD.workflow_state = 'COVENANT_REVIEW' AND NEW.workflow_state = 'PUBLICATION_REVIEW')
    OR (OLD.workflow_state = 'PUBLICATION_REVIEW' AND NEW.workflow_state = 'PUBLISHED')
    OR (OLD.workflow_state = 'PUBLISHED' AND NEW.workflow_state = 'WITHDRAWN')
    OR (OLD.workflow_state = 'WITHDRAWN' AND NEW.workflow_state = 'PUBLICATION_REVIEW')
    OR (
      OLD.workflow_state = 'WITHDRAWN'
      AND NEW.workflow_state IN (
        'MEDIA_READY', 'LANGUAGE_CONFIRMATION', 'SOURCE_REVIEW', 'CRAFTING', 'CRAFT_REVIEW',
        'TRANSLATING', 'TRANSLATION_REVIEW', 'PRIVACY_REVIEW', 'COVENANT_REVIEW', 'PUBLICATION_REVIEW'
      )
    )
    OR (
      OLD.workflow_state NOT IN ('DRAFT', 'WITHDRAWN')
      AND NEW.workflow_state IN (
        'MEDIA_READY', 'LANGUAGE_CONFIRMATION', 'SOURCE_REVIEW', 'CRAFTING', 'CRAFT_REVIEW',
        'TRANSLATING', 'TRANSLATION_REVIEW', 'PRIVACY_REVIEW',
        'COVENANT_REVIEW', 'PUBLICATION_REVIEW'
      )
    )
  ) THEN
    RAISE EXCEPTION 'Invalid workflow transition: % -> %.', OLD.workflow_state, NEW.workflow_state;
  END IF;

  IF NEW.workflow_state = 'TRANSCRIBING' THEN
    v_latest_source := irin_private.latest_source_media_id(NEW.id);
    IF v_latest_source IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.source_language_reviews AS language_review
      WHERE language_review.story_id = NEW.id
        AND language_review.source_media_artifact_id = v_latest_source
        AND language_review.review_number = (
          SELECT max(candidate.review_number)
          FROM public.source_language_reviews AS candidate
          WHERE candidate.story_id = NEW.id
            AND candidate.source_media_artifact_id = v_latest_source
            AND candidate.confirmed_language_code IS NOT NULL
        )
        AND language_review.confirmed_language_code = 'yor'
        AND language_review.confirmed_by = NEW.owner_id
        AND language_review.confirmed_at IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'Transcription requires storyteller-confirmed Yoruba for the current source.';
    END IF;
  END IF;

  IF NEW.workflow_state = 'SOURCE_APPROVED' THEN
    SELECT transcript.artifact_version_id INTO v_latest_transcript
    FROM public.transcript_versions AS transcript
    JOIN public.artifact_versions AS artifact
      ON artifact.story_id = transcript.story_id
     AND artifact.id = transcript.artifact_version_id
    WHERE transcript.story_id = NEW.id
      AND transcript.source_media_artifact_id = irin_private.latest_source_media_id(NEW.id)
    ORDER BY artifact.version_number DESC
    LIMIT 1;
    IF v_latest_transcript IS NULL
       OR NOT irin_private.artifact_is_latest_approved(NEW.id, v_latest_transcript, 'TRANSCRIPT') THEN
      RAISE EXCEPTION 'SOURCE_APPROVED requires approval of the current source transcript version.';
    END IF;
  END IF;

  IF NEW.workflow_state = 'CRAFT_APPROVED' THEN
    SELECT cut.artifact_version_id INTO v_latest_cut
    FROM public.story_cut_versions AS cut
    JOIN public.artifact_versions AS artifact
      ON artifact.story_id = cut.story_id AND artifact.id = cut.artifact_version_id
    WHERE cut.story_id = NEW.id
    ORDER BY artifact.version_number DESC
    LIMIT 1;
    IF v_latest_cut IS NULL
       OR NOT irin_private.artifact_is_latest_approved(NEW.id, v_latest_cut, 'STORY_CUT')
       OR NOT EXISTS (
         SELECT 1 FROM public.cultural_review_versions AS review
         WHERE review.story_id = NEW.id
           AND review.story_cut_artifact_id = v_latest_cut
           AND irin_private.artifact_is_latest_approved(NEW.id, review.artifact_version_id, 'CULTURAL_REVIEW')
       ) THEN
      RAISE EXCEPTION 'CRAFT_APPROVED requires current approved Story Cut and cultural-review versions.';
    END IF;
  END IF;

  IF NEW.workflow_state = 'TRANSLATION_APPROVED' THEN
    SELECT translation.artifact_version_id INTO v_latest_translation
    FROM public.translation_versions AS translation
    JOIN public.artifact_versions AS artifact
      ON artifact.story_id = translation.story_id AND artifact.id = translation.artifact_version_id
    WHERE translation.story_id = NEW.id
    ORDER BY artifact.version_number DESC
    LIMIT 1;
    IF v_latest_translation IS NULL
       OR NOT irin_private.artifact_is_latest_approved(NEW.id, v_latest_translation, 'TRANSLATION') THEN
      RAISE EXCEPTION 'TRANSLATION_APPROVED requires approval of the current English translation version.';
    END IF;
  END IF;

  IF NEW.workflow_state = 'COVENANT_REVIEW' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.privacy_review_versions AS review
      WHERE review.story_id = NEW.id
        AND irin_private.artifact_is_latest_approved(NEW.id, review.artifact_version_id, 'PRIVACY_REVIEW')
        AND NOT EXISTS (
          SELECT 1 FROM public.privacy_findings AS finding
          LEFT JOIN public.privacy_decisions AS decision
            ON decision.story_id = finding.story_id
           AND decision.privacy_finding_id = finding.id
          WHERE finding.story_id = review.story_id
            AND finding.privacy_review_artifact_id = review.artifact_version_id
            AND decision.id IS NULL
        )
    ) THEN
      RAISE EXCEPTION 'COVENANT_REVIEW requires an approved current privacy review with every finding resolved.';
    END IF;
  END IF;

  IF NEW.workflow_state = 'PUBLISHED' AND NOT EXISTS (
    SELECT 1
    FROM public.publication_snapshots AS snapshot
    JOIN public.publication_access AS access
      ON access.story_id = snapshot.story_id
     AND access.publication_snapshot_id = snapshot.id
     AND access.access_state = 'PUBLISHED'
    JOIN public.approvals AS approval
      ON approval.story_id = snapshot.story_id
     AND approval.publication_snapshot_id = snapshot.id
     AND approval.decision = 'APPROVE'
     AND approval.approved_content_sha256 = snapshot.manifest_sha256
    WHERE snapshot.story_id = NEW.id
      AND snapshot.snapshot_version = (
        SELECT max(candidate.snapshot_version)
        FROM public.publication_snapshots AS candidate
        WHERE candidate.story_id = NEW.id
      )
  ) THEN
    RAISE EXCEPTION 'PUBLISHED requires the latest immutable snapshot, its exact approval, and an active access record.';
  END IF;

  IF NEW.workflow_state = 'WITHDRAWN' AND EXISTS (
    SELECT 1 FROM public.publication_access AS access
    WHERE access.story_id = NEW.id AND access.access_state = 'PUBLISHED'
  ) THEN
    RAISE EXCEPTION 'WITHDRAWN requires public access to be revoked first.';
  END IF;

  RETURN NEW;
END;
$function$;

-- Row versions are created with all child rows in one transaction, then sealed once.
-- Sealed content and all historical decision records reject UPDATE and DELETE.
CREATE TRIGGER story_cut_versions_unsealed_guard
  BEFORE INSERT ON public.story_cut_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.require_unsealed_artifact('artifact_version_id', 'STORY_CUT');

CREATE TRIGGER media_assets_unsealed_guard
  BEFORE INSERT ON public.media_assets
  FOR EACH ROW EXECUTE FUNCTION irin_private.require_unsealed_artifact('artifact_version_id');
CREATE TRIGGER media_assets_kind_guard
  BEFORE INSERT ON public.media_assets
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_media_asset();
CREATE TRIGGER media_assets_immutable
  BEFORE UPDATE OR DELETE ON public.media_assets
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE TRIGGER source_language_reviews_insert_guard
  BEFORE INSERT ON public.source_language_reviews
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_source_language_review();
CREATE TRIGGER source_language_reviews_immutable
  BEFORE UPDATE OR DELETE ON public.source_language_reviews
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();
CREATE TRIGGER source_language_reviews_audit
  AFTER INSERT ON public.source_language_reviews
  FOR EACH ROW EXECUTE FUNCTION irin_private.after_language_review_insert();

CREATE TRIGGER artifact_versions_insert_guard
  BEFORE INSERT ON public.artifact_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_artifact_insert();
CREATE TRIGGER artifact_versions_seal_guard
  BEFORE UPDATE OR DELETE ON public.artifact_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_artifact_version();
CREATE TRIGGER artifact_versions_after_seal
  AFTER UPDATE OF sealed_at ON public.artifact_versions
  FOR EACH ROW WHEN (OLD.sealed_at IS NULL AND NEW.sealed_at IS NOT NULL)
  EXECUTE FUNCTION irin_private.after_artifact_sealed();

CREATE TRIGGER transcript_versions_unsealed_guard
  BEFORE INSERT ON public.transcript_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.require_unsealed_artifact('artifact_version_id', 'TRANSCRIPT');
CREATE TRIGGER transcript_versions_language_guard
  BEFORE INSERT ON public.transcript_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_transcript_version();
CREATE TRIGGER transcript_versions_immutable
  BEFORE UPDATE OR DELETE ON public.transcript_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();
CREATE TRIGGER transcript_segments_unsealed_guard
  BEFORE INSERT ON public.transcript_segments
  FOR EACH ROW EXECUTE FUNCTION irin_private.require_unsealed_artifact('transcript_artifact_id', 'TRANSCRIPT');
CREATE TRIGGER transcript_segments_timestamp_guard
  BEFORE INSERT ON public.transcript_segments
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_transcript_segment();
CREATE TRIGGER transcript_segments_immutable
  BEFORE UPDATE OR DELETE ON public.transcript_segments
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE TRIGGER story_cut_versions_source_gate
  BEFORE INSERT ON public.story_cut_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_story_cut_version();
CREATE TRIGGER story_cut_versions_immutable
  BEFORE UPDATE OR DELETE ON public.story_cut_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();
CREATE TRIGGER story_cut_segments_unsealed_guard
  BEFORE INSERT ON public.story_cut_segments
  FOR EACH ROW EXECUTE FUNCTION irin_private.require_unsealed_artifact('cut_artifact_id', 'STORY_CUT');
CREATE TRIGGER story_cut_segments_timestamp_guard
  BEFORE INSERT ON public.story_cut_segments
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_story_cut_segment();
CREATE TRIGGER story_cut_segments_immutable
  BEFORE UPDATE OR DELETE ON public.story_cut_segments
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE TRIGGER cultural_review_versions_unsealed_guard
  BEFORE INSERT ON public.cultural_review_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.require_unsealed_artifact('artifact_version_id', 'CULTURAL_REVIEW');
CREATE TRIGGER cultural_review_versions_cut_gate
  BEFORE INSERT ON public.cultural_review_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_cultural_review_version();
CREATE TRIGGER cultural_review_versions_immutable
  BEFORE UPDATE OR DELETE ON public.cultural_review_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();
CREATE TRIGGER cultural_annotations_unsealed_guard
  BEFORE INSERT ON public.cultural_annotations
  FOR EACH ROW EXECUTE FUNCTION irin_private.require_unsealed_artifact('cultural_review_artifact_id', 'CULTURAL_REVIEW');
CREATE TRIGGER cultural_annotations_immutable
  BEFORE UPDATE OR DELETE ON public.cultural_annotations
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE TRIGGER translation_versions_unsealed_guard
  BEFORE INSERT ON public.translation_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.require_unsealed_artifact('artifact_version_id', 'TRANSLATION');
CREATE TRIGGER translation_versions_approval_gate
  BEFORE INSERT ON public.translation_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_translation_version();
CREATE TRIGGER translation_versions_immutable
  BEFORE UPDATE OR DELETE ON public.translation_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();
CREATE TRIGGER translation_segments_unsealed_guard
  BEFORE INSERT ON public.translation_segments
  FOR EACH ROW EXECUTE FUNCTION irin_private.require_unsealed_artifact('translation_artifact_id', 'TRANSLATION');
CREATE TRIGGER translation_segments_timeline_guard
  BEFORE INSERT ON public.translation_segments
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_translation_segment();
CREATE TRIGGER translation_segments_immutable
  BEFORE UPDATE OR DELETE ON public.translation_segments
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE TRIGGER privacy_review_versions_unsealed_guard
  BEFORE INSERT ON public.privacy_review_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.require_unsealed_artifact('artifact_version_id', 'PRIVACY_REVIEW');
CREATE TRIGGER privacy_review_versions_approval_gate
  BEFORE INSERT ON public.privacy_review_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_privacy_review_version();
CREATE TRIGGER privacy_review_versions_immutable
  BEFORE UPDATE OR DELETE ON public.privacy_review_versions
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();
CREATE TRIGGER privacy_findings_unsealed_guard
  BEFORE INSERT ON public.privacy_findings
  FOR EACH ROW EXECUTE FUNCTION irin_private.require_unsealed_artifact('privacy_review_artifact_id', 'PRIVACY_REVIEW');
CREATE TRIGGER privacy_findings_anchor_guard
  BEFORE INSERT ON public.privacy_findings
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_privacy_finding();
CREATE TRIGGER privacy_findings_immutable
  BEFORE UPDATE OR DELETE ON public.privacy_findings
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();
CREATE TRIGGER privacy_decisions_insert_guard
  BEFORE INSERT ON public.privacy_decisions
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_privacy_decision();
CREATE TRIGGER privacy_decisions_immutable
  BEFORE UPDATE OR DELETE ON public.privacy_decisions
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();
CREATE TRIGGER privacy_decisions_audit
  AFTER INSERT ON public.privacy_decisions
  FOR EACH ROW EXECUTE FUNCTION irin_private.after_privacy_decision_insert();

CREATE TRIGGER covenant_permissions_unsealed_guard
  BEFORE INSERT ON public.covenant_permissions
  FOR EACH ROW EXECUTE FUNCTION irin_private.require_unsealed_artifact('covenant_artifact_id', 'COVENANT');
CREATE TRIGGER covenant_permissions_kind_guard
  BEFORE INSERT ON public.covenant_permissions
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_covenant_permission();
CREATE TRIGGER covenant_permissions_immutable
  BEFORE UPDATE OR DELETE ON public.covenant_permissions
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE TRIGGER media_assets_final_unsealed_guard
  BEFORE INSERT ON public.media_assets
  FOR EACH ROW WHEN (NEW.role = 'FINAL_PUBLICATION')
  EXECUTE FUNCTION irin_private.require_unsealed_artifact('artifact_version_id', 'RENDERED_MEDIA');
CREATE TRIGGER media_assets_final_approval_gate
  BEFORE INSERT ON public.media_assets
  FOR EACH ROW WHEN (NEW.role = 'FINAL_PUBLICATION')
  EXECUTE FUNCTION irin_private.guard_final_publication_media();
CREATE TRIGGER approvals_insert_guard
  BEFORE INSERT ON public.approvals
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_approval();
CREATE TRIGGER approvals_immutable
  BEFORE UPDATE OR DELETE ON public.approvals
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();
CREATE TRIGGER approvals_audit
  AFTER INSERT ON public.approvals
  FOR EACH ROW EXECUTE FUNCTION irin_private.after_approval_insert();

CREATE TRIGGER publication_snapshots_insert_guard
  BEFORE INSERT ON public.publication_snapshots
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_publication_snapshot();
CREATE TRIGGER publication_snapshots_validate
  AFTER INSERT ON public.publication_snapshots
  FOR EACH ROW EXECUTE FUNCTION irin_private.validate_publication_snapshot_after_insert();
CREATE TRIGGER publication_snapshots_immutable
  BEFORE UPDATE OR DELETE ON public.publication_snapshots
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE TRIGGER publication_access_state_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.publication_access
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_publication_access();
CREATE TRIGGER publication_access_audit_and_state
  AFTER UPDATE OF access_state ON public.publication_access
  FOR EACH ROW EXECUTE FUNCTION irin_private.after_publication_access_change();

CREATE TRIGGER audit_events_immutable
  BEFORE UPDATE OR DELETE ON public.audit_events
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE INDEX approvals_story_target_idx ON public.approvals (story_id, artifact_version_id, publication_snapshot_id);
CREATE INDEX cultural_annotations_story_idx ON public.cultural_annotations (story_id, cultural_review_artifact_id);
CREATE INDEX privacy_findings_review_idx ON public.privacy_findings (story_id, privacy_review_artifact_id);
CREATE INDEX publication_access_story_state_idx ON public.publication_access (story_id, access_state);
CREATE INDEX audit_events_story_created_idx ON public.audit_events (story_id, created_at DESC);

-- Every owner-scoped base table is private to the owning Supabase Auth user.
DO $rls$
DECLARE
  v_table text;
  v_owner_tables text[] := ARRAY[
    'artifact_versions', 'media_assets', 'source_language_reviews',
    'transcript_versions', 'transcript_segments', 'story_cut_versions',
    'story_cut_segments',
    'cultural_review_versions', 'cultural_annotations', 'translation_versions',
    'translation_segments', 'privacy_review_versions', 'privacy_findings',
    'privacy_decisions', 'covenant_permissions', 'approvals',
    'publication_snapshots', 'publication_access', 'audit_events'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_owner_tables LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', v_table);
    EXECUTE format(
      'CREATE POLICY owner_select ON public.%I FOR SELECT TO authenticated USING (irin_private.user_owns_story(story_id))',
      v_table
    );
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated, service_role', v_table);
    EXECUTE format('GRANT SELECT ON TABLE public.%I TO authenticated', v_table);
    IF v_table <> 'audit_events' THEN
      EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', v_table);
    ELSE
      EXECUTE 'GRANT SELECT ON TABLE public.audit_events TO service_role';
    END IF;
  END LOOP;
END;
$rls$;

ALTER TABLE public.stories ENABLE ROW LEVEL SECURITY;
CREATE POLICY story_owner_select ON public.stories
  FOR SELECT TO authenticated USING (owner_id = auth.uid());
CREATE POLICY story_owner_insert ON public.stories
  FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid() AND workflow_state = 'DRAFT');
CREATE POLICY story_owner_update_title ON public.stories
  FOR UPDATE TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
REVOKE ALL ON TABLE public.stories FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.stories TO authenticated;
GRANT INSERT (owner_id, title) ON TABLE public.stories TO authenticated;
GRANT UPDATE (title) ON TABLE public.stories TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.stories TO service_role;

CREATE POLICY privacy_decision_owner_insert ON public.privacy_decisions
  FOR INSERT TO authenticated
  WITH CHECK (irin_private.user_owns_story(story_id) AND decided_by = auth.uid());
GRANT INSERT (story_id, privacy_finding_id, decision, resolution_artifact_version_id, storyteller_note, decided_by)
  ON TABLE public.privacy_decisions TO authenticated;

CREATE POLICY approval_owner_insert ON public.approvals
  FOR INSERT TO authenticated
  WITH CHECK (irin_private.user_owns_story(story_id) AND approver_id = auth.uid());
GRANT INSERT (
  story_id, artifact_version_id, publication_snapshot_id, decision,
  approved_content_sha256, approver_id, review_note
) ON TABLE public.approvals TO authenticated;

REVOKE ALL ON FUNCTION public.get_published_story(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_published_story(uuid) TO anon, authenticated;

CREATE POLICY publication_access_owner_update ON public.publication_access
  FOR UPDATE TO authenticated
  USING (irin_private.user_owns_story(story_id) AND access_state = 'PUBLISHED')
  WITH CHECK (irin_private.user_owns_story(story_id) AND access_state = 'WITHDRAWN');
GRANT UPDATE (access_state) ON TABLE public.publication_access TO authenticated;

REVOKE ALL ON TYPE public.story_workflow_state FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TYPE public.story_artifact_kind FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TYPE public.media_asset_role FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TYPE public.story_cut_decision FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TYPE public.privacy_decision FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TYPE public.approval_decision FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TYPE public.publication_access_state FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TYPE public.audit_actor_kind FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TYPE public.covenant_permission FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TYPE public.audit_event_type FROM PUBLIC, anon, authenticated;
GRANT USAGE ON TYPE
  public.story_workflow_state,
  public.story_artifact_kind,
  public.media_asset_role,
  public.story_cut_decision,
  public.privacy_decision,
  public.approval_decision,
  public.publication_access_state,
  public.audit_actor_kind,
  public.covenant_permission,
  public.audit_event_type
TO authenticated, service_role;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA irin_private FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION irin_private.user_owns_story(uuid) TO authenticated, service_role;






