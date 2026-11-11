-- Owner-reviewed English translation versions tied to an explicitly approved Story Cut.
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'TRANSLATION_EDITED';

ALTER TABLE public.translation_versions ALTER COLUMN cultural_review_artifact_id DROP NOT NULL;
ALTER TABLE public.translation_segments
  ALTER COLUMN cultural_review_artifact_id DROP NOT NULL,
  ADD COLUMN initial_proposal text,
  ADD CONSTRAINT translation_segments_cut_once UNIQUE (story_id,translation_artifact_id,cut_segment_id);

CREATE TABLE public.translation_approvals (
  story_id uuid NOT NULL REFERENCES public.stories(id) ON DELETE RESTRICT,
  translation_artifact_id uuid NOT NULL,
  approved_content_sha256 bytea NOT NULL CHECK (octet_length(approved_content_sha256)=32),
  approved_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (story_id,translation_artifact_id),
  FOREIGN KEY (story_id,translation_artifact_id) REFERENCES public.translation_versions(story_id,artifact_version_id) ON DELETE RESTRICT
);
ALTER TABLE public.translation_approvals ENABLE ROW LEVEL SECURITY;
CREATE POLICY translation_approval_owner_read ON public.translation_approvals
  FOR SELECT TO authenticated USING (irin_private.user_owns_story(story_id));
REVOKE ALL ON public.translation_approvals FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.translation_approvals TO authenticated;
GRANT INSERT,SELECT ON public.translation_approvals TO service_role;
CREATE TRIGGER translation_approvals_immutable BEFORE UPDATE OR DELETE ON public.translation_approvals
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE FUNCTION irin_private.current_story_cut_is_approved(p_story_id uuid,p_cut_id uuid,p_source_id uuid,p_transcript_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 SELECT EXISTS (
   SELECT 1 FROM public.story_cut_versions cv
   JOIN public.artifact_versions av ON av.story_id=cv.story_id AND av.id=cv.artifact_version_id
   JOIN public.story_cut_approvals ca ON ca.story_id=cv.story_id AND ca.cut_artifact_id=cv.artifact_version_id
     AND ca.approved_content_sha256=av.content_sha256
   WHERE cv.story_id=p_story_id AND cv.artifact_version_id=p_cut_id
     AND cv.source_media_artifact_id=p_source_id AND cv.transcript_artifact_id=p_transcript_id
     AND p_source_id=irin_private.latest_source_media_id(p_story_id)
     AND irin_private.current_transcript_is_approved(p_story_id,p_transcript_id,p_source_id)
     AND av.kind='STORY_CUT' AND av.sealed_at IS NOT NULL
     AND av.version_number=(SELECT max(v.version_number) FROM public.artifact_versions v WHERE v.story_id=p_story_id AND v.kind='STORY_CUT')
     AND ca.approved_by=(SELECT s.owner_id FROM public.stories s WHERE s.id=p_story_id)
 );
$function$;
REVOKE ALL ON FUNCTION irin_private.current_story_cut_is_approved(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION irin_private.guard_translation_version()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
BEGIN
 IF NEW.source_language_code IS DISTINCT FROM 'yor' OR NEW.target_language_code IS DISTINCT FROM 'eng'
   OR NEW.source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(NEW.story_id)
   OR NOT irin_private.current_transcript_is_approved(NEW.story_id,NEW.transcript_artifact_id,NEW.source_media_artifact_id)
   OR NOT irin_private.current_story_cut_is_approved(NEW.story_id,NEW.story_cut_artifact_id,NEW.source_media_artifact_id,NEW.transcript_artifact_id) THEN
  RAISE EXCEPTION 'English translation requires the current approved Yoruba transcript and Story Cut.';
 END IF;
 IF NEW.cultural_review_artifact_id IS NOT NULL THEN
  RAISE EXCEPTION 'This MVP translation workflow does not require or create a cultural-review artifact.';
 END IF;
 RETURN NEW;
END; $function$;

CREATE OR REPLACE FUNCTION irin_private.guard_translation_segment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_cut_duration bigint; v_cut_segment public.story_cut_segments%ROWTYPE; v_translation public.translation_versions%ROWTYPE;
BEGIN
 SELECT * INTO v_translation FROM public.translation_versions WHERE story_id=NEW.story_id AND artifact_version_id=NEW.translation_artifact_id;
 SELECT * INTO v_cut_segment FROM public.story_cut_segments WHERE story_id=NEW.story_id AND id=NEW.cut_segment_id
   AND cut_artifact_id=NEW.story_cut_artifact_id AND source_media_artifact_id=NEW.source_media_artifact_id
   AND transcript_artifact_id=NEW.transcript_artifact_id;
 SELECT estimated_duration_ms INTO v_cut_duration FROM public.story_cut_versions WHERE story_id=NEW.story_id AND artifact_version_id=NEW.story_cut_artifact_id;
 IF v_cut_segment.id IS NULL OR v_translation.artifact_version_id IS NULL
   OR NEW.transcript_segment_id IS DISTINCT FROM v_cut_segment.transcript_segment_id
   OR NEW.cue_start_ms IS DISTINCT FROM v_cut_segment.output_start_ms OR NEW.cue_end_ms IS DISTINCT FROM v_cut_segment.output_end_ms
   OR NEW.cultural_review_artifact_id IS NOT NULL OR NEW.cue_end_ms>v_cut_duration
   OR NOT EXISTS(SELECT 1 FROM public.transcript_segments ts WHERE ts.story_id=NEW.story_id AND ts.id=NEW.transcript_segment_id
     AND ts.transcript_artifact_id=NEW.transcript_artifact_id AND ts.source_media_artifact_id=NEW.source_media_artifact_id
     AND ts.source_start_ms<=v_cut_segment.source_start_ms AND ts.source_end_ms>=v_cut_segment.source_end_ms)
   OR length(btrim(NEW.english_text))=0 OR length(NEW.english_text)>10000 THEN
  RAISE EXCEPTION 'English subtitle must preserve its exact approved cut, transcript, and source timestamp lineage.';
 END IF;
 RETURN NEW;
END; $function$;

CREATE FUNCTION public.persist_english_translation(
 p_story_id uuid,p_actor_id uuid,p_source_id uuid,p_transcript_id uuid,p_cut_id uuid,
 p_segments jsonb,p_hash bytea,p_action text,p_parent_translation_id uuid DEFAULT NULL,p_model_name text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_owner uuid; v_artifact uuid; v_version integer; v_row jsonb; v_cut_segment public.story_cut_segments%ROWTYPE;
 v_parent_segment public.translation_segments%ROWTYPE; v_n integer:=0; v_count integer; v_english text; v_original text;
BEGIN
 SELECT owner_id INTO v_owner FROM public.stories WHERE id=p_story_id FOR UPDATE;
 IF v_owner IS NULL OR v_owner<>p_actor_id THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
 IF p_source_id IS DISTINCT FROM irin_private.latest_source_media_id(p_story_id)
   OR NOT irin_private.current_transcript_is_approved(p_story_id,p_transcript_id,p_source_id)
   OR NOT irin_private.current_story_cut_is_approved(p_story_id,p_cut_id,p_source_id,p_transcript_id)
   OR jsonb_typeof(p_segments)<>'array' OR jsonb_array_length(p_segments)=0 OR jsonb_array_length(p_segments)>1000 OR octet_length(p_hash)<>32 THEN
  RAISE EXCEPTION 'Current approved Story Cut required.' USING ERRCODE='42501';
 END IF;
 SELECT count(*) INTO v_count FROM public.story_cut_segments WHERE story_id=p_story_id AND cut_artifact_id=p_cut_id;
 IF p_action='ai_proposal' THEN
  IF p_parent_translation_id IS NOT NULL OR jsonb_array_length(p_segments)<>v_count OR p_model_name IS NULL THEN RAISE EXCEPTION 'Invalid translation proposal payload.'; END IF;
 ELSIF p_action='storyteller_edit' THEN
  IF p_parent_translation_id IS NULL OR p_model_name IS NOT NULL OR jsonb_array_length(p_segments)<>v_count THEN RAISE EXCEPTION 'Invalid translation edit payload.'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.translation_versions tv JOIN public.artifact_versions av ON av.story_id=tv.story_id AND av.id=tv.artifact_version_id
    WHERE tv.story_id=p_story_id AND tv.artifact_version_id=p_parent_translation_id AND tv.source_media_artifact_id=p_source_id
      AND tv.transcript_artifact_id=p_transcript_id AND tv.story_cut_artifact_id=p_cut_id AND av.kind='TRANSLATION' AND av.sealed_at IS NOT NULL
      AND av.version_number=(SELECT max(x.version_number) FROM public.artifact_versions x WHERE x.story_id=p_story_id AND x.kind='TRANSLATION')) THEN
   RAISE EXCEPTION 'Only the current translation version may be edited.' USING ERRCODE='42501';
  END IF;
 ELSE RAISE EXCEPTION 'Unknown translation action.'; END IF;

 SELECT coalesce(max(version_number),0)+1 INTO v_version FROM public.artifact_versions WHERE story_id=p_story_id AND kind='TRANSLATION';
 INSERT INTO public.artifact_versions(story_id,kind,version_number,created_by) VALUES(p_story_id,'TRANSLATION',v_version,v_owner) RETURNING id INTO v_artifact;
 INSERT INTO public.translation_versions(story_id,artifact_version_id,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id,cultural_review_artifact_id,source_language_code,target_language_code,provider_name,model_name)
 VALUES(p_story_id,v_artifact,p_source_id,p_transcript_id,p_cut_id,NULL,'yor','eng',CASE WHEN p_action='ai_proposal' THEN 'openai' ELSE NULL END,CASE WHEN p_action='ai_proposal' THEN p_model_name ELSE NULL END);

 FOR v_row IN SELECT value FROM jsonb_array_elements(p_segments) LOOP
  v_n:=v_n+1;
  IF p_action='ai_proposal' THEN
   SELECT * INTO v_cut_segment FROM public.story_cut_segments cs WHERE cs.story_id=p_story_id AND cs.cut_artifact_id=p_cut_id
     AND cs.id=(v_row->>'cutSegmentId')::uuid AND cs.segment_number=v_n;
   IF NOT FOUND THEN RAISE EXCEPTION 'AI translation must include each approved Story Cut segment in order.'; END IF;
   v_english:=btrim(v_row->>'englishText'); v_original:=v_english;
   INSERT INTO public.translation_segments(story_id,translation_artifact_id,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id,cultural_review_artifact_id,cut_segment_id,transcript_segment_id,segment_number,cue_start_ms,cue_end_ms,initial_proposal,english_text)
   VALUES(p_story_id,v_artifact,p_source_id,p_transcript_id,p_cut_id,NULL,v_cut_segment.id,v_cut_segment.transcript_segment_id,v_n,v_cut_segment.output_start_ms,v_cut_segment.output_end_ms,v_original,v_english);
  ELSE
   SELECT * INTO v_parent_segment FROM public.translation_segments ts WHERE ts.story_id=p_story_id AND ts.translation_artifact_id=p_parent_translation_id
     AND ts.id=(v_row->>'translationSegmentId')::uuid AND ts.segment_number=v_n;
   IF NOT FOUND THEN RAISE EXCEPTION 'Edited translation must retain every segment in order.'; END IF;
   v_english:=btrim(v_row->>'englishText');
   INSERT INTO public.translation_segments(story_id,translation_artifact_id,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id,cultural_review_artifact_id,cut_segment_id,transcript_segment_id,segment_number,cue_start_ms,cue_end_ms,initial_proposal,english_text)
   VALUES(p_story_id,v_artifact,p_source_id,p_transcript_id,p_cut_id,NULL,v_parent_segment.cut_segment_id,v_parent_segment.transcript_segment_id,v_n,v_parent_segment.cue_start_ms,v_parent_segment.cue_end_ms,v_parent_segment.initial_proposal,v_english);
  END IF;
 END LOOP;
 UPDATE public.artifact_versions SET content_sha256=p_hash,sealed_at=clock_timestamp() WHERE story_id=p_story_id AND id=v_artifact;
 IF p_action='storyteller_edit' THEN PERFORM irin_private.emit_audit_event(p_story_id,p_actor_id,'TRANSLATION_EDITED',v_artifact,NULL,
   jsonb_build_object('parent_translation_artifact_id',p_parent_translation_id,'source_media_artifact_id',p_source_id,'transcript_artifact_id',p_transcript_id,'story_cut_artifact_id',p_cut_id,'segment_count',v_count),NULL,NULL); END IF;
 RETURN v_artifact;
END; $function$;

CREATE FUNCTION public.approve_english_translation(p_story_id uuid,p_actor_id uuid,p_translation_id uuid)
RETURNS TABLE(translation_artifact_id uuid,approved_at timestamptz,approved_content_sha256 text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_owner uuid; v_hash bytea; v_source uuid; v_transcript uuid; v_cut uuid; v_at timestamptz;
BEGIN
 SELECT owner_id INTO v_owner FROM public.stories WHERE id=p_story_id FOR UPDATE;
 IF v_owner IS NULL OR v_owner<>p_actor_id THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
 SELECT tv.source_media_artifact_id,tv.transcript_artifact_id,tv.story_cut_artifact_id,av.content_sha256 INTO v_source,v_transcript,v_cut,v_hash
 FROM public.translation_versions tv JOIN public.artifact_versions av ON av.story_id=tv.story_id AND av.id=tv.artifact_version_id
 WHERE tv.story_id=p_story_id AND tv.artifact_version_id=p_translation_id AND tv.source_language_code='yor' AND tv.target_language_code='eng'
   AND av.kind='TRANSLATION' AND av.sealed_at IS NOT NULL
   AND av.version_number=(SELECT max(x.version_number) FROM public.artifact_versions x WHERE x.story_id=p_story_id AND x.kind='TRANSLATION');
 IF NOT FOUND OR v_source IS DISTINCT FROM irin_private.latest_source_media_id(p_story_id)
   OR NOT irin_private.current_transcript_is_approved(p_story_id,v_transcript,v_source)
   OR NOT irin_private.current_story_cut_is_approved(p_story_id,v_cut,v_source,v_transcript)
   OR NOT EXISTS(SELECT 1 FROM public.translation_segments ts WHERE ts.story_id=p_story_id AND ts.translation_artifact_id=p_translation_id) THEN
  RAISE EXCEPTION 'Only the latest English translation of the current approved Story Cut may be approved.' USING ERRCODE='42501';
 END IF;
 INSERT INTO public.translation_approvals(story_id,translation_artifact_id,approved_content_sha256,approved_by)
 VALUES(p_story_id,p_translation_id,v_hash,p_actor_id) RETURNING translation_approvals.approved_at INTO v_at;
 PERFORM irin_private.emit_audit_event(p_story_id,p_actor_id,'TRANSLATION_APPROVED',p_translation_id,NULL,
   jsonb_build_object('source_media_artifact_id',v_source,'transcript_artifact_id',v_transcript,'story_cut_artifact_id',v_cut,'approved_content_sha256',encode(v_hash,'hex')),NULL,NULL);
 translation_artifact_id:=p_translation_id; approved_at:=v_at; approved_content_sha256:=encode(v_hash,'hex'); RETURN NEXT;
END; $function$;

REVOKE ALL ON FUNCTION public.persist_english_translation(uuid,uuid,uuid,uuid,uuid,jsonb,bytea,text,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.persist_english_translation(uuid,uuid,uuid,uuid,uuid,jsonb,bytea,text,uuid,text) TO service_role;
REVOKE ALL ON FUNCTION public.approve_english_translation(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.approve_english_translation(uuid,uuid,uuid) TO service_role;
