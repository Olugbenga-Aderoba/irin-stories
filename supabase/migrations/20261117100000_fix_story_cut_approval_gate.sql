-- Qualify the segment lookup to avoid collision with approve_story_cut's output column.
CREATE OR REPLACE FUNCTION public.approve_story_cut(p_story_id uuid,p_actor_id uuid,p_cut_id uuid)
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
   OR NOT EXISTS(SELECT 1 FROM public.story_cut_segments cs WHERE cs.story_id=p_story_id AND cs.cut_artifact_id=p_cut_id) THEN
  RAISE EXCEPTION 'Only the latest Story Cut for the current approved source may be approved.' USING ERRCODE='42501';
 END IF;
 INSERT INTO public.story_cut_approvals(story_id,cut_artifact_id,approved_content_sha256,approved_by) VALUES(p_story_id,p_cut_id,v_hash,p_actor_id) RETURNING story_cut_approvals.approved_at INTO v_at;
 PERFORM irin_private.emit_audit_event(p_story_id,p_actor_id,'STORY_CUT_APPROVED',p_cut_id,NULL,jsonb_build_object('source_media_artifact_id',v_source,'transcript_artifact_id',v_transcript,'approved_content_sha256',encode(v_hash,'hex')),NULL,NULL);
 cut_artifact_id:=p_cut_id; approved_at:=v_at; approved_content_sha256:=encode(v_hash,'hex'); RETURN NEXT;
END; $function$;
