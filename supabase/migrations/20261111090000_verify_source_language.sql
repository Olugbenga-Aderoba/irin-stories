-- Verify A: trusted source-media probe and storyteller-controlled language review.
-- This migration is versioned; it does not alter or replace prior migrations.

ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'MEDIA_VERIFIED';

CREATE TABLE public.source_media_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.stories (id) ON DELETE RESTRICT,
  source_media_artifact_id uuid NOT NULL,
  verification_number integer NOT NULL CHECK (verification_number > 0),
  status text NOT NULL CHECK (status IN ('READY', 'REJECTED')),
  actual_container text NOT NULL CHECK (length(btrim(actual_container)) BETWEEN 1 AND 120),
  actual_format_names text NOT NULL CHECK (length(btrim(actual_format_names)) BETWEEN 1 AND 500),
  actual_duration_ms bigint NOT NULL CHECK (actual_duration_ms > 0),
  has_video boolean NOT NULL,
  has_audio boolean NOT NULL,
  audio_codec text,
  video_codec text,
  video_width integer CHECK (video_width IS NULL OR video_width > 0),
  video_height integer CHECK (video_height IS NULL OR video_height > 0),
  server_content_sha256 bytea NOT NULL CHECK (octet_length(server_content_sha256) = 32),
  client_metadata_mismatches jsonb NOT NULL DEFAULT '[]'::jsonb
    CHECK (jsonb_typeof(client_metadata_mismatches) = 'array'),
  probe_name text NOT NULL CHECK (length(btrim(probe_name)) BETWEEN 1 AND 120),
  probe_version text NOT NULL CHECK (length(btrim(probe_version)) BETWEEN 1 AND 120),
  requested_by uuid NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  verified_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT source_media_verifications_ready_usable CHECK (
    status <> 'READY' OR (has_video AND has_audio AND audio_codec IS NOT NULL)
  ),
  CONSTRAINT source_media_verifications_source_fk FOREIGN KEY (story_id, source_media_artifact_id)
    REFERENCES public.media_assets (story_id, artifact_version_id) ON DELETE RESTRICT,
  CONSTRAINT source_media_verifications_version_unique UNIQUE (story_id, source_media_artifact_id, verification_number),
  CONSTRAINT source_media_verifications_identity_unique UNIQUE (story_id, id, source_media_artifact_id)
);

COMMENT ON TABLE public.source_media_verifications IS
  'Append-only server-derived probe results for one exact private source-media version; client-reported values are retained separately for comparison.';

CREATE OR REPLACE FUNCTION irin_private.audit_source_media_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  PERFORM irin_private.emit_audit_event(
    NEW.story_id,
    NEW.requested_by,
    'MEDIA_VERIFIED'::public.audit_event_type,
    NEW.source_media_artifact_id,
    NULL,
    jsonb_build_object(
      'verification_id', NEW.id,
      'status', NEW.status,
      'client_metadata_mismatch_count', jsonb_array_length(NEW.client_metadata_mismatches)
    ),
    NULL,
    NULL
  );
  RETURN NEW;
END;
$function$;

CREATE TRIGGER source_media_verifications_audit
  AFTER INSERT ON public.source_media_verifications
  FOR EACH ROW EXECUTE FUNCTION irin_private.audit_source_media_verification();

ALTER TABLE public.source_language_reviews
  ADD COLUMN detected_language_name text,
  ADD COLUMN detector_model text,
  ADD COLUMN detected_at timestamptz,
  ADD COLUMN confirmed_language_name text,
  ADD COLUMN review_status text NOT NULL DEFAULT 'PROPOSED',
  ADD COLUMN proposal_review_id uuid;

UPDATE public.source_language_reviews
SET detected_language_name = CASE detected_language_code
      WHEN 'yor' THEN 'Yoruba'
      WHEN 'eng' THEN 'English'
      ELSE detected_language_code
    END,
    detected_at = created_at,
    confirmed_language_name = CASE confirmed_language_code
      WHEN 'yor' THEN 'Yoruba'
      WHEN 'eng' THEN 'English'
      ELSE confirmed_language_code
    END,
    review_status = CASE
      WHEN confirmed_language_code IS NULL THEN 'PROPOSED'
      WHEN confirmed_language_code = detected_language_code THEN 'CONFIRMED'
      ELSE 'CORRECTED'
    END;

ALTER TABLE public.source_language_reviews
  ADD CONSTRAINT source_language_reviews_status_valid CHECK (
    review_status IN ('PROPOSED', 'CONFIRMED', 'CORRECTED')
  ),
  ADD CONSTRAINT source_language_reviews_status_fields CHECK (
    (review_status = 'PROPOSED'
      AND detected_language_code IS NOT NULL
      AND detected_language_name IS NOT NULL
      AND detected_at IS NOT NULL
      AND confirmed_language_code IS NULL
      AND confirmed_language_name IS NULL
      AND confirmed_by IS NULL
      AND confirmed_at IS NULL
      AND proposal_review_id IS NULL)
    OR (review_status IN ('CONFIRMED', 'CORRECTED')
      AND detected_language_code IS NOT NULL
      AND detected_language_name IS NOT NULL
      AND detected_at IS NOT NULL
      AND confirmed_language_code IS NOT NULL
      AND confirmed_language_name IS NOT NULL
      AND confirmed_by IS NOT NULL
      AND confirmed_at IS NOT NULL
      AND proposal_review_id IS NOT NULL
      AND ((review_status = 'CONFIRMED' AND confirmed_language_code = detected_language_code)
        OR (review_status = 'CORRECTED' AND confirmed_language_code <> detected_language_code)))
  ) NOT VALID,
  ADD CONSTRAINT source_language_reviews_proposal_fk FOREIGN KEY (story_id, proposal_review_id, source_media_artifact_id)
    REFERENCES public.source_language_reviews (story_id, id, source_media_artifact_id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX source_language_reviews_one_decision_per_proposal
  ON public.source_language_reviews (story_id, proposal_review_id)
  WHERE review_status IN ('CONFIRMED', 'CORRECTED');

ALTER TABLE public.source_media_verifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY source_media_verifications_owner_select ON public.source_media_verifications
  FOR SELECT TO authenticated USING (irin_private.user_owns_story(story_id));
REVOKE ALL ON TABLE public.source_media_verifications FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.source_media_verifications TO authenticated, service_role;

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
  v_proposal public.source_language_reviews%ROWTYPE;
BEGIN
  SELECT story.owner_id INTO v_owner_id
  FROM public.stories AS story
  WHERE story.id = NEW.story_id
  FOR UPDATE;

  v_latest_source_id := irin_private.latest_source_media_id(NEW.story_id);
  IF v_owner_id IS NULL OR NEW.source_media_artifact_id IS DISTINCT FROM v_latest_source_id THEN
    RAISE EXCEPTION 'Language review must reference the current source owned by this story.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.source_media_verifications AS verification
    WHERE verification.story_id = NEW.story_id
      AND verification.source_media_artifact_id = NEW.source_media_artifact_id
      AND verification.status = 'READY'
      AND verification.verification_number = (
        SELECT max(candidate.verification_number)
        FROM public.source_media_verifications AS candidate
        WHERE candidate.story_id = verification.story_id
          AND candidate.source_media_artifact_id = verification.source_media_artifact_id
      )
  ) THEN
    RAISE EXCEPTION 'Language detection requires a usable server-verified current source.';
  END IF;

  SELECT coalesce(max(review.review_number), 0) + 1 INTO v_next_review_number
  FROM public.source_language_reviews AS review
  WHERE review.story_id = NEW.story_id
    AND review.source_media_artifact_id = NEW.source_media_artifact_id;

  IF NEW.review_number <> v_next_review_number THEN
    RAISE EXCEPTION 'Language review numbers must increase by one for each source version.';
  END IF;

  IF NEW.review_status = 'PROPOSED' THEN
    IF auth.role() <> 'service_role'
       OR NEW.detected_language_code IS NULL
       OR NEW.detected_language_name IS NULL
       OR NEW.detected_at IS NULL
       OR NEW.detector_name IS NULL THEN
      RAISE EXCEPTION 'A language proposal must be created by the trusted detection service.';
    END IF;
    IF NEW.confirmed_language_code IS NOT NULL
       OR NEW.confirmed_by IS NOT NULL
       OR NEW.confirmed_at IS NOT NULL
       OR NEW.proposal_review_id IS NOT NULL THEN
      RAISE EXCEPTION 'A detection proposal cannot contain storyteller confirmation.';
    END IF;
  ELSIF NEW.review_status IN ('CONFIRMED', 'CORRECTED') THEN
    IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM v_owner_id
       OR NEW.confirmed_by IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Only the owning storyteller may confirm or correct the original language.';
    END IF;

    SELECT proposal.* INTO v_proposal
    FROM public.source_language_reviews AS proposal
    WHERE proposal.story_id = NEW.story_id
      AND proposal.id = NEW.proposal_review_id
      AND proposal.source_media_artifact_id = NEW.source_media_artifact_id
      AND proposal.review_status = 'PROPOSED';

    IF NOT FOUND OR v_proposal.detected_language_code IS DISTINCT FROM NEW.detected_language_code
       OR v_proposal.detected_language_name IS DISTINCT FROM NEW.detected_language_name
       OR v_proposal.detector_name IS DISTINCT FROM NEW.detector_name
       OR v_proposal.detector_model IS DISTINCT FROM NEW.detector_model
       OR v_proposal.detected_at IS DISTINCT FROM NEW.detected_at THEN
      RAISE EXCEPTION 'Confirmation must reference the exact proposal for this source version.';
    END IF;

    IF NEW.review_status = 'CONFIRMED'
       AND NEW.confirmed_language_code IS DISTINCT FROM NEW.detected_language_code THEN
      RAISE EXCEPTION 'Confirmation must match the proposed language.';
    END IF;
    IF NEW.review_status = 'CORRECTED'
       AND NEW.confirmed_language_code IS NOT DISTINCT FROM NEW.detected_language_code THEN
      RAISE EXCEPTION 'A corrected language must differ from the proposal.';
    END IF;
    NEW.confirmed_at := clock_timestamp();
  ELSE
    RAISE EXCEPTION 'Unsupported language review status.';
  END IF;

  NEW.created_at := clock_timestamp();
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
  IF NEW.review_status = 'PROPOSED' THEN
    UPDATE public.stories AS story
    SET workflow_state = 'LANGUAGE_CONFIRMATION'
    WHERE story.id = NEW.story_id AND story.workflow_state = 'MEDIA_READY';
    RETURN NEW;
  END IF;

  PERFORM irin_private.emit_audit_event(
    NEW.story_id,
    NEW.confirmed_by,
    CASE WHEN NEW.review_status = 'CONFIRMED'
      THEN 'LANGUAGE_CONFIRMED'::public.audit_event_type
      ELSE 'LANGUAGE_CORRECTED'::public.audit_event_type
    END,
    NEW.source_media_artifact_id,
    NULL,
    jsonb_build_object(
      'proposal_review_id', NEW.proposal_review_id,
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
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_source_media_verification(
  p_story_id uuid,
  p_source_media_artifact_id uuid,
  p_status text,
  p_actual_container text,
  p_actual_format_names text,
  p_actual_duration_ms bigint,
  p_has_video boolean,
  p_has_audio boolean,
  p_audio_codec text,
  p_video_codec text,
  p_video_width integer,
  p_video_height integer,
  p_server_content_sha256 bytea,
  p_client_metadata_mismatches jsonb,
  p_probe_name text,
  p_probe_version text,
  p_requested_by uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_verification_id uuid := gen_random_uuid();
  v_owner_id uuid;
  v_verification_number integer;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Only the trusted media verification service may record probe results.'
      USING ERRCODE = '42501';
  END IF;

  SELECT story.owner_id INTO v_owner_id
  FROM public.stories AS story
  WHERE story.id = p_story_id;
  IF v_owner_id IS NULL OR v_owner_id <> p_requested_by THEN
    RAISE EXCEPTION 'Media verification requester must own the story.'
      USING ERRCODE = '42501';
  END IF;
  IF p_source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(p_story_id)
     OR NOT EXISTS (
       SELECT 1 FROM public.media_assets AS media
       WHERE media.story_id = p_story_id
         AND media.artifact_version_id = p_source_media_artifact_id
         AND media.role = 'SOURCE'
     ) THEN
    RAISE EXCEPTION 'Media verification must target the current registered source.'
      USING ERRCODE = '22023';
  END IF;
  IF p_status NOT IN ('READY', 'REJECTED')
     OR p_actual_duration_ms IS NULL OR p_actual_duration_ms <= 0
     OR p_server_content_sha256 IS NULL OR octet_length(p_server_content_sha256) <> 32
     OR jsonb_typeof(p_client_metadata_mismatches) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Server media probe result is malformed.'
      USING ERRCODE = '22023';
  END IF;
  IF p_status = 'READY' AND (NOT p_has_video OR NOT p_has_audio OR p_audio_codec IS NULL) THEN
    RAISE EXCEPTION 'Media without usable audio and a video stream cannot be marked ready.'
      USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(max(verification.verification_number), 0) + 1
    INTO v_verification_number
  FROM public.source_media_verifications AS verification
  WHERE verification.story_id = p_story_id
    AND verification.source_media_artifact_id = p_source_media_artifact_id;

  INSERT INTO public.source_media_verifications (
    id, story_id, source_media_artifact_id, verification_number, status,
    actual_container, actual_format_names, actual_duration_ms, has_video, has_audio,
    audio_codec, video_codec, video_width, video_height, server_content_sha256,
    client_metadata_mismatches, probe_name, probe_version, requested_by
  ) VALUES (
    v_verification_id, p_story_id, p_source_media_artifact_id, v_verification_number, p_status,
    p_actual_container, p_actual_format_names, p_actual_duration_ms, p_has_video, p_has_audio,
    p_audio_codec, p_video_codec, p_video_width, p_video_height, p_server_content_sha256,
    p_client_metadata_mismatches, p_probe_name, p_probe_version, p_requested_by
  );

  IF p_status = 'READY' THEN
    UPDATE public.stories AS story
    SET workflow_state = 'LANGUAGE_CONFIRMATION'
    WHERE story.id = p_story_id AND story.workflow_state = 'MEDIA_READY';
  END IF;

  RETURN v_verification_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_source_media_verification(uuid, uuid, text, text, text, bigint, boolean, boolean, text, text, integer, integer, bytea, jsonb, text, text, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_source_media_verification(uuid, uuid, text, text, text, bigint, boolean, boolean, text, text, integer, integer, bytea, jsonb, text, text, uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.create_source_language_proposal(
  p_story_id uuid,
  p_source_media_artifact_id uuid,
  p_detected_language_code text,
  p_detected_language_name text,
  p_detection_confidence numeric,
  p_detector_name text,
  p_detector_model text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_proposal_id uuid := gen_random_uuid();
  v_owner_id uuid;
  v_review_number integer;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Only the trusted language-detection service may create a proposal.'
      USING ERRCODE = '42501';
  END IF;
  SELECT story.owner_id INTO v_owner_id
  FROM public.stories AS story WHERE story.id = p_story_id;
  IF v_owner_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.source_media_verifications AS verification
    WHERE verification.story_id = p_story_id
      AND verification.source_media_artifact_id = p_source_media_artifact_id
      AND verification.status = 'READY'
      AND verification.verification_number = (
        SELECT max(candidate.verification_number)
        FROM public.source_media_verifications AS candidate
        WHERE candidate.story_id = verification.story_id
          AND candidate.source_media_artifact_id = verification.source_media_artifact_id
      )
  ) OR p_source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(p_story_id) THEN
    RAISE EXCEPTION 'Language detection requires an owner-authorized, verified current source.'
      USING ERRCODE = '42501';
  END IF;
  IF p_detected_language_code !~ '^[a-z]{3}(-[A-Za-z0-9]{2,8})*$'
     OR p_detected_language_name IS NULL OR length(btrim(p_detected_language_name)) NOT BETWEEN 1 AND 120
     OR p_detection_confidence IS NOT NULL AND p_detection_confidence NOT BETWEEN 0 AND 1
     OR p_detector_name IS NULL OR length(btrim(p_detector_name)) NOT BETWEEN 1 AND 120
     OR p_detector_model IS NULL OR length(btrim(p_detector_model)) NOT BETWEEN 1 AND 160 THEN
    RAISE EXCEPTION 'Language proposal does not satisfy the validated result contract.'
      USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(max(review.review_number), 0) + 1 INTO v_review_number
  FROM public.source_language_reviews AS review
  WHERE review.story_id = p_story_id AND review.source_media_artifact_id = p_source_media_artifact_id;

  INSERT INTO public.source_language_reviews (
    id, story_id, source_media_artifact_id, review_number, detected_language_code,
    detected_language_name, detection_confidence, detector_name, detector_model,
    detected_at, review_status
  ) VALUES (
    v_proposal_id, p_story_id, p_source_media_artifact_id, v_review_number,
    lower(p_detected_language_code), p_detected_language_name, p_detection_confidence,
    p_detector_name, p_detector_model, clock_timestamp(), 'PROPOSED'
  );
  RETURN v_proposal_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_source_language_proposal(uuid, uuid, text, text, numeric, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_source_language_proposal(uuid, uuid, text, text, numeric, text, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.confirm_source_language(
  p_story_id uuid,
  p_source_media_artifact_id uuid,
  p_proposal_review_id uuid,
  p_confirmed_language_code text,
  p_confirmed_language_name text
)
RETURNS TABLE (review_id uuid, review_status text, transcription_eligible boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_owner_id uuid;
  v_proposal public.source_language_reviews%ROWTYPE;
  v_review_number integer;
  v_new_status text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication is required to confirm the original language.'
      USING ERRCODE = '42501';
  END IF;
  SELECT story.owner_id INTO v_owner_id
  FROM public.stories AS story WHERE story.id = p_story_id FOR UPDATE;
  IF v_owner_id IS NULL OR v_owner_id IS DISTINCT FROM auth.uid()
     OR p_source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(p_story_id) THEN
    RAISE EXCEPTION 'Only the owner may confirm language for the current source in this story.'
      USING ERRCODE = '42501';
  END IF;
  SELECT proposal.* INTO v_proposal
  FROM public.source_language_reviews AS proposal
  WHERE proposal.story_id = p_story_id
    AND proposal.id = p_proposal_review_id
    AND proposal.source_media_artifact_id = p_source_media_artifact_id
    AND proposal.review_status = 'PROPOSED';
  IF NOT FOUND OR EXISTS (
    SELECT 1 FROM public.source_language_reviews AS decision
    WHERE decision.story_id = p_story_id
      AND decision.proposal_review_id = p_proposal_review_id
      AND decision.review_status IN ('CONFIRMED', 'CORRECTED')
  ) THEN
    RAISE EXCEPTION 'The exact language proposal is unavailable or already has a storyteller decision.'
      USING ERRCODE = '22023';
  END IF;
  IF p_confirmed_language_code !~ '^[a-z]{3}(-[A-Za-z0-9]{2,8})*$'
     OR p_confirmed_language_name IS NULL
     OR length(btrim(p_confirmed_language_name)) NOT BETWEEN 1 AND 120 THEN
    RAISE EXCEPTION 'The storyteller language choice is malformed.'
      USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(max(review.review_number), 0) + 1 INTO v_review_number
  FROM public.source_language_reviews AS review
  WHERE review.story_id = p_story_id AND review.source_media_artifact_id = p_source_media_artifact_id;
  v_new_status := CASE WHEN p_confirmed_language_code = v_proposal.detected_language_code
    THEN 'CONFIRMED' ELSE 'CORRECTED' END;

  INSERT INTO public.source_language_reviews (
    story_id, source_media_artifact_id, review_number, detected_language_code,
    detected_language_name, detection_confidence, detector_name, detector_model,
    detected_at, confirmed_language_code, confirmed_language_name, confirmed_by,
    confirmed_at, review_status, proposal_review_id
  ) VALUES (
    p_story_id, p_source_media_artifact_id, v_review_number, v_proposal.detected_language_code,
    v_proposal.detected_language_name, v_proposal.detection_confidence,
    v_proposal.detector_name, v_proposal.detector_model, v_proposal.detected_at,
    lower(p_confirmed_language_code), p_confirmed_language_name, auth.uid(),
    clock_timestamp(), v_new_status, v_proposal.id
  ) RETURNING id INTO review_id;

  review_status := v_new_status;
  transcription_eligible := lower(p_confirmed_language_code) = 'yor'
    AND public.is_transcription_eligible(p_story_id);
  RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION public.is_transcription_eligible(p_story_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.stories AS story
    JOIN public.media_assets AS source
      ON source.story_id = story.id
     AND source.artifact_version_id = irin_private.latest_source_media_id(story.id)
     AND source.role = 'SOURCE'
    JOIN public.source_media_verifications AS verification
      ON verification.story_id = story.id
     AND verification.source_media_artifact_id = source.artifact_version_id
     AND verification.status = 'READY'
     AND verification.verification_number = (
       SELECT max(candidate.verification_number)
       FROM public.source_media_verifications AS candidate
       WHERE candidate.story_id = verification.story_id
         AND candidate.source_media_artifact_id = verification.source_media_artifact_id
     )
    JOIN public.source_language_reviews AS review
      ON review.story_id = story.id
     AND review.source_media_artifact_id = source.artifact_version_id
     AND review.confirmed_language_code = 'yor'
     AND review.confirmed_by = story.owner_id
     AND review.review_status IN ('CONFIRMED', 'CORRECTED')
     AND review.review_number = (
       SELECT max(candidate.review_number)
       FROM public.source_language_reviews AS candidate
       WHERE candidate.story_id = story.id
         AND candidate.source_media_artifact_id = source.artifact_version_id
         AND candidate.review_status IN ('CONFIRMED', 'CORRECTED')
     )
    WHERE story.id = p_story_id AND story.owner_id = auth.uid()
  );
$function$;

REVOKE ALL ON FUNCTION public.confirm_source_language(uuid, uuid, uuid, text, text)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.confirm_source_language(uuid, uuid, uuid, text, text)
  TO authenticated;
REVOKE ALL ON FUNCTION public.is_transcription_eligible(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.is_transcription_eligible(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION irin_private.guard_transcription_eligibility()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.workflow_state = 'TRANSCRIBING'
     AND OLD.workflow_state IS DISTINCT FROM NEW.workflow_state
     AND NOT EXISTS (
       SELECT 1 FROM public.stories AS story
       WHERE story.id = NEW.id
         AND story.owner_id = NEW.owner_id
         AND irin_private.latest_source_media_id(NEW.id) IS NOT NULL
         AND EXISTS (
           SELECT 1 FROM public.source_media_verifications AS verification
           WHERE verification.story_id = NEW.id
             AND verification.source_media_artifact_id = irin_private.latest_source_media_id(NEW.id)
             AND verification.status = 'READY'
             AND verification.verification_number = (
               SELECT max(candidate.verification_number)
               FROM public.source_media_verifications AS candidate
               WHERE candidate.story_id = verification.story_id
                 AND candidate.source_media_artifact_id = verification.source_media_artifact_id
             )
         )
         AND EXISTS (
           SELECT 1 FROM public.source_language_reviews AS review
           WHERE review.story_id = NEW.id
             AND review.source_media_artifact_id = irin_private.latest_source_media_id(NEW.id)
             AND review.review_status IN ('CONFIRMED', 'CORRECTED')
             AND review.confirmed_language_code = 'yor'
             AND review.confirmed_by = NEW.owner_id
             AND review.review_number = (
               SELECT max(candidate.review_number)
               FROM public.source_language_reviews AS candidate
               WHERE candidate.story_id = NEW.id
                 AND candidate.source_media_artifact_id = review.source_media_artifact_id
                 AND candidate.review_status IN ('CONFIRMED', 'CORRECTED')
             )
         )
     ) THEN
    RAISE EXCEPTION 'Transcribing requires server-verified media and explicit current Yoruba confirmation by the story owner.';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER stories_transcription_eligibility_guard
  BEFORE UPDATE OF workflow_state ON public.stories
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_transcription_eligibility();

COMMENT ON FUNCTION public.is_transcription_eligible(uuid) IS
  'Returns true only for the caller-owned current server-verified source with the latest explicit storyteller-confirmed Yoruba language. It does not start transcription.';
