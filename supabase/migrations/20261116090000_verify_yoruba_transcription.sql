-- Verify B: versioned Yoruba transcript persistence and explicit approval.
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'TRANSCRIPT_EDITED';
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'TRANSCRIPT_APPROVED';

ALTER TABLE public.storyteller_language_decisions
  ADD CONSTRAINT storyteller_language_decision_identity_unique UNIQUE (story_id,id,source_media_artifact_id);

ALTER TABLE public.transcript_versions
  ALTER COLUMN language_review_id DROP NOT NULL,
  ADD COLUMN language_decision_id uuid;
ALTER TABLE public.transcript_versions
  ADD CONSTRAINT transcript_language_evidence_check CHECK (num_nonnulls(language_review_id,language_decision_id)=1),
  ADD CONSTRAINT transcript_language_decision_fk FOREIGN KEY (story_id,language_decision_id,source_media_artifact_id)
    REFERENCES public.storyteller_language_decisions(story_id,id,source_media_artifact_id) ON DELETE RESTRICT;

CREATE FUNCTION irin_private.current_yoruba_transcription_eligible(p_story_id uuid,p_owner_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.stories s
    JOIN public.storyteller_language_decisions d ON d.story_id=s.id
      AND d.source_media_artifact_id=irin_private.latest_source_media_id(s.id)
      AND d.state='confirmed' AND d.selected_language_code='yor' AND d.confirmed_by=s.owner_id
    JOIN public.source_media_verifications v ON v.story_id=s.id AND v.source_media_artifact_id=d.source_media_artifact_id AND v.status='READY'
      AND v.verification_number=(SELECT max(x.verification_number) FROM public.source_media_verifications x WHERE x.story_id=v.story_id AND x.source_media_artifact_id=v.source_media_artifact_id)
    WHERE s.id=p_story_id AND s.owner_id=p_owner_id
  ) OR EXISTS (
    SELECT 1 FROM public.stories s
    JOIN public.source_language_reviews r ON r.story_id=s.id AND r.source_media_artifact_id=irin_private.latest_source_media_id(s.id)
      AND r.review_status IN ('CONFIRMED','CORRECTED') AND r.confirmed_language_code='yor' AND r.confirmed_by=s.owner_id
      AND r.review_number=(SELECT max(x.review_number) FROM public.source_language_reviews x WHERE x.story_id=r.story_id AND x.source_media_artifact_id=r.source_media_artifact_id AND x.review_status IN ('CONFIRMED','CORRECTED'))
    JOIN public.source_media_verifications v ON v.story_id=s.id AND v.source_media_artifact_id=r.source_media_artifact_id AND v.status='READY'
      AND v.verification_number=(SELECT max(x.verification_number) FROM public.source_media_verifications x WHERE x.story_id=v.story_id AND x.source_media_artifact_id=v.source_media_artifact_id)
    WHERE s.id=p_story_id AND s.owner_id=p_owner_id
  );
$function$;
REVOKE ALL ON FUNCTION irin_private.current_yoruba_transcription_eligible(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION irin_private.current_yoruba_transcription_eligible(uuid,uuid) TO service_role;

CREATE TABLE public.transcript_approvals (
  story_id uuid NOT NULL REFERENCES public.stories(id) ON DELETE RESTRICT,
  transcript_artifact_id uuid NOT NULL,
  approved_content_sha256 bytea NOT NULL CHECK (octet_length(approved_content_sha256)=32),
  approved_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (story_id,transcript_artifact_id),
  FOREIGN KEY (story_id,transcript_artifact_id) REFERENCES public.transcript_versions(story_id,artifact_version_id) ON DELETE RESTRICT
);
ALTER TABLE public.transcript_approvals ENABLE ROW LEVEL SECURITY;
CREATE POLICY transcript_approval_owner_read ON public.transcript_approvals
  FOR SELECT TO authenticated USING (irin_private.user_owns_story(story_id));
REVOKE ALL ON public.transcript_approvals FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.transcript_approvals TO authenticated;
GRANT INSERT,SELECT ON public.transcript_approvals TO service_role;
CREATE TRIGGER transcript_approvals_immutable BEFORE UPDATE OR DELETE ON public.transcript_approvals
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE OR REPLACE FUNCTION irin_private.guard_transcript_version()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_ok boolean:=false;
BEGIN
  IF NEW.language_code IS DISTINCT FROM 'yor' OR NEW.source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(NEW.story_id)
     OR NOT irin_private.current_yoruba_transcription_eligible(NEW.story_id,(SELECT owner_id FROM public.stories WHERE id=NEW.story_id)) THEN
    RAISE EXCEPTION 'Transcription requires current server-verified Yoruba explicitly confirmed by the owner.';
  END IF;
  IF NEW.language_decision_id IS NOT NULL THEN
    SELECT d.state='confirmed' AND d.decision_origin IN ('storyteller_selected','storyteller_corrected')
      AND d.selected_language_code='yor' AND d.confirmed_by=s.owner_id AND d.source_media_artifact_id=NEW.source_media_artifact_id
      INTO v_ok
    FROM public.stories s JOIN public.storyteller_language_decisions d ON d.story_id=s.id
    WHERE s.id=NEW.story_id AND d.id=NEW.language_decision_id;
  ELSE
    SELECT r.confirmed_language_code='yor' AND r.confirmed_by=s.owner_id AND r.source_media_artifact_id=NEW.source_media_artifact_id
      AND r.review_status IN ('CONFIRMED','CORRECTED') AND r.review_number=(
        SELECT max(x.review_number) FROM public.source_language_reviews x WHERE x.story_id=r.story_id
        AND x.source_media_artifact_id=r.source_media_artifact_id AND x.review_status IN ('CONFIRMED','CORRECTED'))
      INTO v_ok
    FROM public.stories s JOIN public.source_language_reviews r ON r.story_id=s.id
    WHERE s.id=NEW.story_id AND r.id=NEW.language_review_id;
  END IF;
  IF NOT coalesce(v_ok,false) THEN RAISE EXCEPTION 'Transcript language provenance is not current and owner-confirmed.'; END IF;
  RETURN NEW;
END; $function$;

CREATE FUNCTION public.persist_yoruba_transcript(
  p_story_id uuid,p_actor_id uuid,p_source_media_artifact_id uuid,p_segments jsonb,p_content_sha256 bytea,
  p_action text,p_parent_transcript_artifact_id uuid DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_owner uuid; v_artifact uuid; v_version integer; v_review uuid; v_decision uuid; v_source_duration bigint;
  v_count integer; v_segment jsonb; v_start bigint; v_end bigint; v_text text; v_initial text; v_no integer:=0;
BEGIN
  SELECT owner_id INTO v_owner FROM public.stories WHERE id=p_story_id FOR UPDATE;
  IF v_owner IS NULL OR v_owner IS DISTINCT FROM p_actor_id THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
  IF p_source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(p_story_id)
    OR NOT irin_private.current_yoruba_transcription_eligible(p_story_id,p_actor_id) THEN RAISE EXCEPTION 'Current verified Yoruba confirmation required.' USING ERRCODE='42501'; END IF;
  SELECT m.duration_ms INTO v_source_duration FROM public.media_assets m
  WHERE m.story_id=p_story_id AND m.artifact_version_id=p_source_media_artifact_id AND m.role='SOURCE';
  IF p_action='ai_transcription' THEN
    IF p_parent_transcript_artifact_id IS NOT NULL OR jsonb_typeof(p_segments)<>'array' OR jsonb_array_length(p_segments)=0 THEN
      RAISE EXCEPTION 'Invalid AI transcript payload.';
    END IF;
  ELSIF p_action='storyteller_edit' THEN
    IF p_parent_transcript_artifact_id IS NULL OR jsonb_typeof(p_segments)<>'array' OR jsonb_array_length(p_segments)=0 THEN RAISE EXCEPTION 'Invalid transcript edit.'; END IF;
    SELECT tv.language_review_id,tv.language_decision_id INTO v_review,v_decision FROM public.transcript_versions tv
      JOIN public.artifact_versions av ON av.story_id=tv.story_id AND av.id=tv.artifact_version_id
    WHERE tv.story_id=p_story_id AND tv.artifact_version_id=p_parent_transcript_artifact_id
      AND tv.source_media_artifact_id=p_source_media_artifact_id AND av.kind='TRANSCRIPT' AND av.sealed_at IS NOT NULL
      AND av.version_number=(SELECT max(x.version_number) FROM public.artifact_versions x WHERE x.story_id=p_story_id AND x.kind='TRANSCRIPT');
    IF NOT FOUND THEN RAISE EXCEPTION 'Only the current transcript version can be edited.' USING ERRCODE='42501'; END IF;
  ELSE RAISE EXCEPTION 'Unknown transcript action.'; END IF;

  IF p_action='ai_transcription' THEN
    SELECT d.id INTO v_decision FROM public.storyteller_language_decisions d WHERE d.story_id=p_story_id
      AND d.source_media_artifact_id=p_source_media_artifact_id AND d.state='confirmed' AND d.selected_language_code='yor'
      AND d.confirmed_by=v_owner ORDER BY d.created_at DESC LIMIT 1;
    IF v_decision IS NULL THEN
      SELECT r.id INTO v_review FROM public.source_language_reviews r WHERE r.story_id=p_story_id AND r.source_media_artifact_id=p_source_media_artifact_id
        AND r.confirmed_language_code='yor' AND r.confirmed_by=v_owner AND r.review_status IN ('CONFIRMED','CORRECTED')
      ORDER BY r.review_number DESC LIMIT 1;
    END IF;
  END IF;

  SELECT count(*) INTO v_count FROM jsonb_array_elements(p_segments);
  IF v_count NOT BETWEEN 1 AND 10000 OR octet_length(p_content_sha256)<>32 THEN RAISE EXCEPTION 'Transcript payload is outside supported bounds.'; END IF;
  INSERT INTO public.artifact_versions(story_id,kind,version_number,created_by)
    SELECT p_story_id,'TRANSCRIPT',coalesce(max(version_number),0)+1,v_owner FROM public.artifact_versions WHERE story_id=p_story_id AND kind='TRANSCRIPT'
    RETURNING id,version_number INTO v_artifact,v_version;
  INSERT INTO public.transcript_versions(story_id,artifact_version_id,source_media_artifact_id,language_review_id,language_decision_id,language_code,provider_name,model_name)
  VALUES(p_story_id,v_artifact,p_source_media_artifact_id,v_review,v_decision,'yor',CASE WHEN p_action='ai_transcription' THEN 'openai' ELSE NULL END,
    CASE WHEN p_action='ai_transcription' THEN 'gpt-transcribe' ELSE NULL END);

  IF p_action='storyteller_edit' THEN
    FOR v_segment IN SELECT value FROM jsonb_array_elements(p_segments) LOOP
      v_no:=v_no+1;
      IF (v_segment->>'segmentNumber')::integer<>v_no THEN RAISE EXCEPTION 'Edited transcript segments must preserve order.'; END IF;
      SELECT source_start_ms,source_end_ms,initial_proposal INTO v_start,v_end,v_initial FROM public.transcript_segments
       WHERE story_id=p_story_id AND transcript_artifact_id=p_parent_transcript_artifact_id AND segment_number=v_no;
      IF NOT FOUND THEN RAISE EXCEPTION 'Transcript segment lineage is incomplete.'; END IF;
      v_text:=btrim(v_segment->>'text'); IF v_text IS NULL OR length(v_text)=0 OR length(v_text)>10000 THEN RAISE EXCEPTION 'Transcript text is invalid.'; END IF;
      INSERT INTO public.transcript_segments(story_id,transcript_artifact_id,source_media_artifact_id,segment_number,source_start_ms,source_end_ms,initial_proposal,text_yoruba)
       VALUES(p_story_id,v_artifact,p_source_media_artifact_id,v_no,v_start,v_end,v_initial,v_text);
    END LOOP;
    IF v_no<>(SELECT count(*) FROM public.transcript_segments WHERE story_id=p_story_id AND transcript_artifact_id=p_parent_transcript_artifact_id) THEN RAISE EXCEPTION 'All transcript segments are required.'; END IF;
  ELSE
    FOR v_segment IN SELECT value FROM jsonb_array_elements(p_segments) LOOP
      v_no:=v_no+1; v_start:=round((v_segment->>'startSeconds')::numeric*1000); v_end:=round((v_segment->>'endSeconds')::numeric*1000);
      v_text:=btrim(v_segment->>'text');
      IF v_start<0 OR v_end<=v_start OR v_end>v_source_duration OR v_text IS NULL OR length(v_text)=0 OR length(v_text)>10000 THEN RAISE EXCEPTION 'AI transcript segment is invalid.'; END IF;
      INSERT INTO public.transcript_segments(story_id,transcript_artifact_id,source_media_artifact_id,segment_number,source_start_ms,source_end_ms,initial_proposal,text_yoruba)
       VALUES(p_story_id,v_artifact,p_source_media_artifact_id,v_no,v_start,v_end,v_text,v_text);
    END LOOP;
  END IF;
  UPDATE public.artifact_versions SET content_sha256=p_content_sha256,sealed_at=clock_timestamp() WHERE id=v_artifact AND story_id=p_story_id;
  IF p_action='storyteller_edit' THEN
    PERFORM irin_private.emit_audit_event(p_story_id,p_actor_id,'TRANSCRIPT_EDITED'::public.audit_event_type,
      v_artifact,NULL,jsonb_build_object('version',v_version,'source_media_artifact_id',p_source_media_artifact_id,
        'parent_transcript_artifact_id',p_parent_transcript_artifact_id,'segment_count',v_count),NULL,NULL);
  END IF;
  RETURN v_artifact;
END; $function$;

CREATE FUNCTION public.approve_yoruba_transcript(p_story_id uuid,p_actor_id uuid,p_transcript_artifact_id uuid)
RETURNS TABLE(transcript_artifact_id uuid,approved_at timestamptz,approved_content_sha256 text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_owner uuid; v_source uuid; v_hash bytea; v_at timestamptz;
BEGIN
  SELECT owner_id INTO v_owner FROM public.stories WHERE id=p_story_id FOR UPDATE;
  IF v_owner IS NULL OR v_owner IS DISTINCT FROM p_actor_id THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
  SELECT tv.source_media_artifact_id,av.content_sha256 INTO v_source,v_hash FROM public.transcript_versions tv
    JOIN public.artifact_versions av ON av.story_id=tv.story_id AND av.id=tv.artifact_version_id
  WHERE tv.story_id=p_story_id AND tv.artifact_version_id=p_transcript_artifact_id AND tv.language_code='yor'
    AND av.kind='TRANSCRIPT' AND av.sealed_at IS NOT NULL
    AND av.version_number=(SELECT max(x.version_number) FROM public.artifact_versions x WHERE x.story_id=p_story_id AND x.kind='TRANSCRIPT');
  IF NOT FOUND OR v_source IS DISTINCT FROM irin_private.latest_source_media_id(p_story_id) OR NOT irin_private.current_yoruba_transcription_eligible(p_story_id,p_actor_id) THEN
    RAISE EXCEPTION 'Only the current eligible Yoruba transcript may be approved.' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.transcript_approvals(story_id,transcript_artifact_id,approved_content_sha256,approved_by)
    VALUES(p_story_id,p_transcript_artifact_id,v_hash,p_actor_id) RETURNING transcript_approvals.approved_at INTO v_at;
  PERFORM irin_private.emit_audit_event(p_story_id,p_actor_id,'TRANSCRIPT_APPROVED'::public.audit_event_type,p_transcript_artifact_id,NULL,
    jsonb_build_object('source_media_artifact_id',v_source,'approved_content_sha256',encode(v_hash,'hex')),NULL,NULL);
  transcript_artifact_id:=p_transcript_artifact_id; approved_at:=v_at; approved_content_sha256:=encode(v_hash,'hex'); RETURN NEXT;
END; $function$;

REVOKE ALL ON FUNCTION public.persist_yoruba_transcript(uuid,uuid,uuid,jsonb,bytea,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.persist_yoruba_transcript(uuid,uuid,uuid,jsonb,bytea,text,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.approve_yoruba_transcript(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.approve_yoruba_transcript(uuid,uuid,uuid) TO service_role;
