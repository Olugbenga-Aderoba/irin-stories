-- Minimum versioned Craft workflow. Historical Story Cuts without explicit
-- transcript-segment links remain readable but new versions require exact lineage.
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'STORY_CUT_EDITED';

ALTER TABLE public.story_cut_segments ADD COLUMN transcript_segment_id uuid;
ALTER TABLE public.story_cut_segments
  ADD CONSTRAINT story_cut_segments_transcript_segment_fk
  FOREIGN KEY (story_id, transcript_segment_id, transcript_artifact_id, source_media_artifact_id)
  REFERENCES public.transcript_segments(story_id, id, transcript_artifact_id, source_media_artifact_id) ON DELETE RESTRICT;

CREATE TABLE public.story_cut_approvals (
  story_id uuid NOT NULL REFERENCES public.stories(id) ON DELETE RESTRICT,
  cut_artifact_id uuid NOT NULL,
  approved_content_sha256 bytea NOT NULL CHECK (octet_length(approved_content_sha256)=32),
  approved_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (story_id,cut_artifact_id),
  FOREIGN KEY (story_id,cut_artifact_id) REFERENCES public.story_cut_versions(story_id,artifact_version_id) ON DELETE RESTRICT
);
ALTER TABLE public.story_cut_approvals ENABLE ROW LEVEL SECURITY;
CREATE POLICY story_cut_approval_owner_read ON public.story_cut_approvals FOR SELECT TO authenticated USING (irin_private.user_owns_story(story_id));
REVOKE ALL ON public.story_cut_approvals FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.story_cut_approvals TO authenticated;
GRANT INSERT,SELECT ON public.story_cut_approvals TO service_role;
CREATE TRIGGER story_cut_approvals_immutable BEFORE UPDATE OR DELETE ON public.story_cut_approvals
  FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE OR REPLACE FUNCTION irin_private.current_transcript_is_approved(p_story_id uuid,p_transcript_id uuid,p_source_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 SELECT EXISTS (
   SELECT 1 FROM public.transcript_versions tv
   JOIN public.artifact_versions av ON av.story_id=tv.story_id AND av.id=tv.artifact_version_id
   JOIN public.transcript_approvals ta ON ta.story_id=tv.story_id AND ta.transcript_artifact_id=tv.artifact_version_id
     AND ta.approved_content_sha256=av.content_sha256
   WHERE tv.story_id=p_story_id AND tv.artifact_version_id=p_transcript_id AND tv.source_media_artifact_id=p_source_id
     AND tv.language_code='yor' AND av.kind='TRANSCRIPT' AND av.sealed_at IS NOT NULL
     AND p_source_id=irin_private.latest_source_media_id(p_story_id)
     AND av.version_number=(SELECT max(v.version_number) FROM public.artifact_versions v WHERE v.story_id=p_story_id AND v.kind='TRANSCRIPT')
     AND EXISTS (SELECT 1 FROM public.source_media_verifications smv WHERE smv.story_id=p_story_id
       AND smv.source_media_artifact_id=p_source_id AND smv.status='READY'
       AND smv.verification_number=(SELECT max(x.verification_number) FROM public.source_media_verifications x WHERE x.story_id=p_story_id AND x.source_media_artifact_id=p_source_id))
 );
$function$;
REVOKE ALL ON FUNCTION irin_private.current_transcript_is_approved(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION irin_private.guard_story_cut_version()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
BEGIN
 IF NEW.source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(NEW.story_id)
   OR NOT irin_private.current_transcript_is_approved(NEW.story_id,NEW.transcript_artifact_id,NEW.source_media_artifact_id) THEN
   RAISE EXCEPTION 'Craft requires the latest approved Yoruba transcript of the current verified source.';
 END IF;
 RETURN NEW;
END; $function$;

CREATE OR REPLACE FUNCTION irin_private.guard_story_cut_segment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_source_duration bigint; v_cut_duration bigint; v_timebase_num integer; v_timebase_den integer; v_transcript_start bigint; v_transcript_end bigint;
BEGIN
 SELECT duration_ms,video_timebase_num,video_timebase_den INTO v_source_duration,v_timebase_num,v_timebase_den FROM public.media_assets
  WHERE story_id=NEW.story_id AND artifact_version_id=NEW.source_media_artifact_id;
 SELECT estimated_duration_ms INTO v_cut_duration FROM public.story_cut_versions WHERE story_id=NEW.story_id AND artifact_version_id=NEW.cut_artifact_id;
 SELECT source_start_ms,source_end_ms INTO v_transcript_start,v_transcript_end FROM public.transcript_segments
  WHERE story_id=NEW.story_id AND id=NEW.transcript_segment_id AND transcript_artifact_id=NEW.transcript_artifact_id AND source_media_artifact_id=NEW.source_media_artifact_id;
 IF v_transcript_start IS NULL OR NEW.source_start_ms<v_transcript_start OR NEW.source_end_ms>v_transcript_end THEN
   RAISE EXCEPTION 'Story Cut interval must remain inside its exact linked transcript segment.';
 END IF;
 IF NEW.source_end_ms>v_source_duration OR NEW.output_end_ms>v_cut_duration THEN RAISE EXCEPTION 'Story Cut timestamp exceeds its referenced timeline.'; END IF;
 IF NEW.source_start_pts IS NOT NULL AND v_timebase_num IS NULL THEN RAISE EXCEPTION 'Story Cut PTS requires the source media timebase.'; END IF;
 RETURN NEW;
END; $function$;

CREATE FUNCTION public.persist_story_cut(p_story_id uuid,p_actor_id uuid,p_source_id uuid,p_transcript_id uuid,p_segments jsonb,p_hash bytea,p_parent_cut_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_owner uuid; v_cut uuid; v_version integer; v_duration bigint:=0; v_row jsonb; v_seg public.transcript_segments%ROWTYPE; v_num integer:=0; v_start bigint; v_end bigint; v_len bigint; v_role text; v_reason text; v_parent uuid;
BEGIN
 SELECT owner_id INTO v_owner FROM public.stories WHERE id=p_story_id FOR UPDATE;
 IF v_owner IS NULL OR v_owner<>p_actor_id THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
 IF p_source_id IS DISTINCT FROM irin_private.latest_source_media_id(p_story_id) OR NOT irin_private.current_transcript_is_approved(p_story_id,p_transcript_id,p_source_id)
   OR jsonb_typeof(p_segments)<>'array' OR jsonb_array_length(p_segments)=0 OR jsonb_array_length(p_segments)>1000 OR octet_length(p_hash)<>32 THEN
   RAISE EXCEPTION 'Current approved transcript and source required.' USING ERRCODE='42501';
 END IF;
 IF p_parent_cut_id IS NOT NULL THEN
  SELECT artifact_version_id INTO v_parent FROM public.story_cut_versions sc JOIN public.artifact_versions av ON av.story_id=sc.story_id AND av.id=sc.artifact_version_id
   WHERE sc.story_id=p_story_id AND sc.artifact_version_id=p_parent_cut_id AND sc.source_media_artifact_id=p_source_id AND sc.transcript_artifact_id=p_transcript_id
     AND av.sealed_at IS NOT NULL AND av.version_number=(SELECT max(x.version_number) FROM public.artifact_versions x WHERE x.story_id=p_story_id AND x.kind='STORY_CUT');
  IF v_parent IS NULL THEN RAISE EXCEPTION 'Only the current Story Cut can be edited.' USING ERRCODE='42501'; END IF;
 END IF;
 FOR v_row IN SELECT value FROM jsonb_array_elements(p_segments) LOOP
  SELECT * INTO v_seg FROM public.transcript_segments WHERE story_id=p_story_id AND id=(v_row->>'transcriptSegmentId')::uuid
    AND transcript_artifact_id=p_transcript_id AND source_media_artifact_id=p_source_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Story Cut segment does not belong to the approved transcript.'; END IF;
  v_start:=coalesce((v_row->>'sourceStartMs')::bigint,v_seg.source_start_ms); v_end:=coalesce((v_row->>'sourceEndMs')::bigint,v_seg.source_end_ms);
  IF v_start<v_seg.source_start_ms OR v_end>v_seg.source_end_ms OR v_end<=v_start THEN RAISE EXCEPTION 'Invalid Story Cut source interval.'; END IF;
  v_len:=v_end-v_start; v_duration:=v_duration+v_len;
 END LOOP;
 SELECT coalesce(max(version_number),0)+1 INTO v_version FROM public.artifact_versions WHERE story_id=p_story_id AND kind='STORY_CUT';
 INSERT INTO public.artifact_versions(story_id,kind,version_number,created_by) VALUES(p_story_id,'STORY_CUT',v_version,v_owner) RETURNING id INTO v_cut;
 INSERT INTO public.story_cut_versions(story_id,artifact_version_id,source_media_artifact_id,transcript_artifact_id,estimated_duration_ms)
 VALUES(p_story_id,v_cut,p_source_id,p_transcript_id,v_duration);
 v_num:=0; v_duration:=0;
 FOR v_row IN SELECT value FROM jsonb_array_elements(p_segments) LOOP
  v_num:=v_num+1;
  SELECT * INTO v_seg FROM public.transcript_segments WHERE story_id=p_story_id AND id=(v_row->>'transcriptSegmentId')::uuid AND transcript_artifact_id=p_transcript_id;
  v_start:=coalesce((v_row->>'sourceStartMs')::bigint,v_seg.source_start_ms); v_end:=coalesce((v_row->>'sourceEndMs')::bigint,v_seg.source_end_ms); v_len:=v_end-v_start;
  v_role:=left(coalesce(nullif(btrim(v_row->>'narrativeRole'),''),'Story moment'),120);
  v_reason:=left(coalesce(nullif(btrim(v_row->>'selectionRationale'),''),'Included from the approved Yoruba source transcript.'),1000);
  INSERT INTO public.story_cut_segments(story_id,cut_artifact_id,source_media_artifact_id,transcript_artifact_id,transcript_segment_id,segment_number,source_start_ms,source_end_ms,output_start_ms,output_end_ms,narrative_role,selection_rationale,decision)
  VALUES(p_story_id,v_cut,p_source_id,p_transcript_id,v_seg.id,v_num,v_start,v_end,v_duration,v_duration+v_len,v_role,v_reason,'PROPOSED');
  v_duration:=v_duration+v_len;
 END LOOP;
 UPDATE public.artifact_versions SET content_sha256=p_hash,sealed_at=clock_timestamp() WHERE story_id=p_story_id AND id=v_cut;
 IF p_parent_cut_id IS NOT NULL THEN PERFORM irin_private.emit_audit_event(p_story_id,p_actor_id,'STORY_CUT_EDITED',v_cut,NULL,jsonb_build_object('parent_cut_artifact_id',p_parent_cut_id,'source_media_artifact_id',p_source_id,'transcript_artifact_id',p_transcript_id,'segment_count',v_num,'estimated_duration_ms',v_duration),NULL,NULL); END IF;
 RETURN v_cut;
END; $function$;

CREATE FUNCTION public.approve_story_cut(p_story_id uuid,p_actor_id uuid,p_cut_id uuid)
RETURNS TABLE(cut_artifact_id uuid,approved_at timestamptz,approved_content_sha256 text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_owner uuid; v_hash bytea; v_source uuid; v_transcript uuid; v_at timestamptz;
BEGIN
 SELECT owner_id INTO v_owner FROM public.stories WHERE id=p_story_id FOR UPDATE;
 IF v_owner IS NULL OR v_owner<>p_actor_id THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
 SELECT sc.source_media_artifact_id,sc.transcript_artifact_id,av.content_sha256 INTO v_source,v_transcript,v_hash
 FROM public.story_cut_versions sc JOIN public.artifact_versions av ON av.story_id=sc.story_id AND av.id=sc.artifact_version_id
 WHERE sc.story_id=p_story_id AND sc.artifact_version_id=p_cut_id AND av.kind='STORY_CUT' AND av.sealed_at IS NOT NULL
  AND av.version_number=(SELECT max(x.version_number) FROM public.artifact_versions x WHERE x.story_id=p_story_id AND x.kind='STORY_CUT');
 IF NOT FOUND OR v_source IS DISTINCT FROM irin_private.latest_source_media_id(p_story_id)
   OR NOT irin_private.current_transcript_is_approved(p_story_id,v_transcript,v_source)
   OR NOT EXISTS(SELECT 1 FROM public.story_cut_segments WHERE story_id=p_story_id AND cut_artifact_id=p_cut_id) THEN
  RAISE EXCEPTION 'Only the latest Story Cut for the current approved source may be approved.' USING ERRCODE='42501';
 END IF;
 INSERT INTO public.story_cut_approvals(story_id,cut_artifact_id,approved_content_sha256,approved_by) VALUES(p_story_id,p_cut_id,v_hash,p_actor_id) RETURNING story_cut_approvals.approved_at INTO v_at;
 PERFORM irin_private.emit_audit_event(p_story_id,p_actor_id,'STORY_CUT_APPROVED',p_cut_id,NULL,jsonb_build_object('source_media_artifact_id',v_source,'transcript_artifact_id',v_transcript,'approved_content_sha256',encode(v_hash,'hex')),NULL,NULL);
 cut_artifact_id:=p_cut_id; approved_at:=v_at; approved_content_sha256:=encode(v_hash,'hex'); RETURN NEXT;
END; $function$;

REVOKE ALL ON FUNCTION public.persist_story_cut(uuid,uuid,uuid,uuid,jsonb,bytea,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.persist_story_cut(uuid,uuid,uuid,uuid,jsonb,bytea,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.approve_story_cut(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.approve_story_cut(uuid,uuid,uuid) TO service_role;
