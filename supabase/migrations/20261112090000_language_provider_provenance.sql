-- Verify A provider metadata: retain safe request IDs and failure categories only.

ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'LANGUAGE_DETECTION_FAILED';

ALTER TABLE public.source_language_reviews
  ADD COLUMN provider_request_id text
  CONSTRAINT source_language_reviews_provider_request_id_length
  CHECK (provider_request_id IS NULL OR length(btrim(provider_request_id)) BETWEEN 1 AND 200);

DROP FUNCTION public.create_source_language_proposal(uuid, uuid, text, text, numeric, text, text);

CREATE FUNCTION public.create_source_language_proposal(
  p_story_id uuid,
  p_source_media_artifact_id uuid,
  p_detected_language_code text,
  p_detected_language_name text,
  p_detection_confidence numeric,
  p_detector_name text,
  p_detector_model text,
  p_provider_request_id text
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
     OR p_detector_model IS NULL OR length(btrim(p_detector_model)) NOT BETWEEN 1 AND 160
     OR p_provider_request_id IS NOT NULL AND length(btrim(p_provider_request_id)) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Language proposal does not satisfy the validated result contract.'
      USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(max(review.review_number), 0) + 1 INTO v_review_number
  FROM public.source_language_reviews AS review
  WHERE review.story_id = p_story_id AND review.source_media_artifact_id = p_source_media_artifact_id;

  INSERT INTO public.source_language_reviews (
    id, story_id, source_media_artifact_id, review_number, detected_language_code,
    detected_language_name, detection_confidence, detector_name, detector_model,
    detected_at, review_status, provider_request_id
  ) VALUES (
    v_proposal_id, p_story_id, p_source_media_artifact_id, v_review_number,
    lower(p_detected_language_code), p_detected_language_name, p_detection_confidence,
    p_detector_name, p_detector_model, clock_timestamp(), 'PROPOSED', p_provider_request_id
  );
  RETURN v_proposal_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_source_language_proposal(uuid, uuid, text, text, numeric, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_source_language_proposal(uuid, uuid, text, text, numeric, text, text, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.record_language_detection_failure(
  p_story_id uuid,
  p_source_media_artifact_id uuid,
  p_error_category text,
  p_requested_by uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_owner_id uuid;
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'Only the trusted language-detection service may record provider failure.'
      USING ERRCODE = '42501';
  END IF;
  SELECT story.owner_id INTO v_owner_id
  FROM public.stories AS story WHERE story.id = p_story_id;
  IF v_owner_id IS DISTINCT FROM p_requested_by
     OR p_source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(p_story_id) THEN
    RAISE EXCEPTION 'Language detection failure must reference the owner''s current source.'
      USING ERRCODE = '42501';
  END IF;
  IF p_error_category NOT IN (
    'provider_not_configured', 'provider_timeout', 'provider_error',
    'no_reliable_language', 'unsupported_provider_code', 'speech_not_established'
  ) THEN
    RAISE EXCEPTION 'Language provider failure category is not allowed.' USING ERRCODE = '22023';
  END IF;
  PERFORM irin_private.emit_audit_event(
    p_story_id, p_requested_by, 'LANGUAGE_DETECTION_FAILED'::public.audit_event_type,
    p_source_media_artifact_id, NULL,
    jsonb_build_object('error_category', p_error_category), NULL, NULL
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.record_language_detection_failure(uuid, uuid, text, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_language_detection_failure(uuid, uuid, text, uuid)
  TO service_role;
