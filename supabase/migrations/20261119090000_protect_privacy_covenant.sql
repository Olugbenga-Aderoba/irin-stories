-- Local Protect workflow: AI findings, owner decisions, and versioned Covenant.
CREATE TABLE public.covenant_approvals (
  story_id uuid NOT NULL REFERENCES public.stories(id) ON DELETE RESTRICT,
  covenant_artifact_id uuid NOT NULL,
  approved_content_sha256 bytea NOT NULL CHECK (octet_length(approved_content_sha256)=32),
  approved_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(story_id,covenant_artifact_id),
  FOREIGN KEY(story_id,covenant_artifact_id) REFERENCES public.artifact_versions(story_id,id) ON DELETE RESTRICT
);
ALTER TABLE public.covenant_approvals ENABLE ROW LEVEL SECURITY;
CREATE POLICY covenant_approval_owner_read ON public.covenant_approvals FOR SELECT TO authenticated USING (irin_private.user_owns_story(story_id));
REVOKE ALL ON public.covenant_approvals FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.covenant_approvals TO authenticated;
GRANT INSERT,SELECT ON public.covenant_approvals TO service_role;
CREATE TRIGGER covenant_approvals_immutable BEFORE UPDATE OR DELETE ON public.covenant_approvals FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE TABLE public.story_covenant_versions (
 story_id uuid NOT NULL REFERENCES public.stories(id) ON DELETE RESTRICT,
 covenant_artifact_id uuid NOT NULL,
 privacy_review_artifact_id uuid NOT NULL,
 translation_artifact_id uuid NOT NULL,
 story_cut_artifact_id uuid NOT NULL,
 source_media_artifact_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(story_id,covenant_artifact_id),
 FOREIGN KEY(story_id,covenant_artifact_id) REFERENCES public.artifact_versions(story_id,id) ON DELETE RESTRICT,
 FOREIGN KEY(story_id,privacy_review_artifact_id,story_cut_artifact_id,translation_artifact_id) REFERENCES public.privacy_review_versions(story_id,artifact_version_id,story_cut_artifact_id,translation_artifact_id) ON DELETE RESTRICT,
 FOREIGN KEY(story_id,translation_artifact_id) REFERENCES public.translation_versions(story_id,artifact_version_id) ON DELETE RESTRICT,
 FOREIGN KEY(story_id,story_cut_artifact_id) REFERENCES public.story_cut_versions(story_id,artifact_version_id) ON DELETE RESTRICT,
 FOREIGN KEY(story_id,source_media_artifact_id) REFERENCES public.media_assets(story_id,artifact_version_id) ON DELETE RESTRICT
);
ALTER TABLE public.story_covenant_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY story_covenant_version_owner_read ON public.story_covenant_versions FOR SELECT TO authenticated USING (irin_private.user_owns_story(story_id));
REVOKE ALL ON public.story_covenant_versions FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.story_covenant_versions TO authenticated;
GRANT INSERT,SELECT ON public.story_covenant_versions TO service_role;
CREATE TRIGGER story_covenant_versions_immutable BEFORE UPDATE OR DELETE ON public.story_covenant_versions FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE FUNCTION irin_private.current_english_translation_is_approved(p_story uuid,p_translation uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $f$
 SELECT EXISTS(SELECT 1 FROM public.translation_versions t
  JOIN public.artifact_versions a ON a.story_id=t.story_id AND a.id=t.artifact_version_id
  JOIN public.translation_approvals p ON p.story_id=t.story_id AND p.translation_artifact_id=t.artifact_version_id AND p.approved_content_sha256=a.content_sha256
  WHERE t.story_id=p_story AND t.artifact_version_id=p_translation AND t.source_language_code='yor' AND t.target_language_code='eng'
  AND t.source_media_artifact_id=irin_private.latest_source_media_id(p_story)
  AND irin_private.current_story_cut_is_approved(t.story_id,t.story_cut_artifact_id,t.source_media_artifact_id,t.transcript_artifact_id)
  AND a.kind='TRANSLATION' AND a.sealed_at IS NOT NULL
  AND a.version_number=(SELECT max(x.version_number) FROM public.artifact_versions x WHERE x.story_id=p_story AND x.kind='TRANSLATION')
  AND p.approved_by=(SELECT owner_id FROM public.stories WHERE id=p_story));
$f$;
REVOKE ALL ON FUNCTION irin_private.current_english_translation_is_approved(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION irin_private.guard_privacy_review_version()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE v_translation public.translation_versions%ROWTYPE;
BEGIN
 SELECT * INTO v_translation FROM public.translation_versions WHERE story_id=NEW.story_id AND artifact_version_id=NEW.translation_artifact_id;
 IF v_translation.story_cut_artifact_id IS DISTINCT FROM NEW.story_cut_artifact_id
    OR NOT irin_private.current_english_translation_is_approved(NEW.story_id,NEW.translation_artifact_id) THEN
  RAISE EXCEPTION 'Privacy review requires the exact current approved English translation and Story Cut.';
 END IF;
 RETURN NEW;
END;$f$;

CREATE OR REPLACE FUNCTION irin_private.guard_privacy_decision()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE v_owner uuid; v_finding timestamptz; v_source uuid; v_transcript uuid; v_kind public.story_artifact_kind; v_resolution_source uuid; v_resolution_transcript uuid; v_resolution_created timestamptz;
BEGIN
 SELECT owner_id INTO v_owner FROM public.stories WHERE id=NEW.story_id;
 IF v_owner IS NULL OR NEW.decided_by IS DISTINCT FROM v_owner THEN RAISE EXCEPTION 'Only the owning storyteller may decide privacy findings.'; END IF;
 SELECT f.created_at,c.source_media_artifact_id,c.transcript_artifact_id INTO v_finding,v_source,v_transcript
 FROM public.privacy_findings f JOIN public.privacy_review_versions r ON r.story_id=f.story_id AND r.artifact_version_id=f.privacy_review_artifact_id
 JOIN public.story_cut_versions c ON c.story_id=r.story_id AND c.artifact_version_id=r.story_cut_artifact_id
 WHERE f.story_id=NEW.story_id AND f.id=NEW.privacy_finding_id;
 IF v_finding IS NULL THEN RAISE EXCEPTION 'Privacy finding does not exist.'; END IF;
 IF NEW.decision<>'KEEP' THEN
  SELECT kind,created_at INTO v_kind,v_resolution_created FROM public.artifact_versions WHERE story_id=NEW.story_id AND id=NEW.resolution_artifact_version_id AND sealed_at IS NOT NULL;
  IF v_kind='TRANSLATION' THEN
   SELECT source_media_artifact_id,transcript_artifact_id INTO v_resolution_source,v_resolution_transcript FROM public.translation_versions WHERE story_id=NEW.story_id AND artifact_version_id=NEW.resolution_artifact_version_id;
   IF NOT irin_private.current_english_translation_is_approved(NEW.story_id,NEW.resolution_artifact_version_id) THEN RAISE EXCEPTION 'Privacy edits must cite a current owner-approved translation.'; END IF;
  ELSIF v_kind='STORY_CUT' THEN
   SELECT source_media_artifact_id,transcript_artifact_id INTO v_resolution_source,v_resolution_transcript FROM public.story_cut_versions WHERE story_id=NEW.story_id AND artifact_version_id=NEW.resolution_artifact_version_id;
   IF NOT irin_private.current_story_cut_is_approved(NEW.story_id,NEW.resolution_artifact_version_id,v_resolution_source,v_resolution_transcript) THEN RAISE EXCEPTION 'Privacy edits must cite a current owner-approved Story Cut.'; END IF;
  ELSE RAISE EXCEPTION 'A later approved edit is required for this privacy decision.'; END IF;
  IF v_resolution_source IS DISTINCT FROM v_source OR v_resolution_transcript IS DISTINCT FROM v_transcript OR v_resolution_created<=v_finding THEN RAISE EXCEPTION 'Privacy edit must be later and preserve the finding source lineage.'; END IF;
 END IF;
 NEW.decided_at:=clock_timestamp(); RETURN NEW;
END;$f$;

CREATE FUNCTION public.persist_privacy_review(p_story uuid,p_actor uuid,p_translation uuid,p_model text,p_findings jsonb,p_hash bytea)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE v_owner uuid; v_tv public.translation_versions%ROWTYPE; v_cut public.story_cut_versions%ROWTYPE; v_artifact uuid; v_version integer; v_item jsonb; v_seg public.translation_segments%ROWTYPE; v_cutseg public.story_cut_segments%ROWTYPE; v_count integer:=0;
BEGIN
 SELECT owner_id INTO v_owner FROM public.stories WHERE id=p_story FOR UPDATE;
 IF v_owner IS NULL OR v_owner<>p_actor THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_tv FROM public.translation_versions WHERE story_id=p_story AND artifact_version_id=p_translation;
 IF NOT irin_private.current_english_translation_is_approved(p_story,p_translation) OR jsonb_typeof(p_findings)<>'array' OR jsonb_array_length(p_findings)>200 OR octet_length(p_hash)<>32 OR length(btrim(p_model))=0 OR length(p_model)>160 THEN RAISE EXCEPTION 'Current approved translation and valid findings required.'; END IF;
 SELECT * INTO v_cut FROM public.story_cut_versions WHERE story_id=p_story AND artifact_version_id=v_tv.story_cut_artifact_id;
 SELECT coalesce(max(version_number),0)+1 INTO v_version FROM public.artifact_versions WHERE story_id=p_story AND kind='PRIVACY_REVIEW';
 INSERT INTO public.artifact_versions(story_id,kind,version_number,created_by) VALUES(p_story,'PRIVACY_REVIEW',v_version,v_owner) RETURNING id INTO v_artifact;
 INSERT INTO public.privacy_review_versions(story_id,artifact_version_id,story_cut_artifact_id,translation_artifact_id) VALUES(p_story,v_artifact,v_tv.story_cut_artifact_id,p_translation);
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_findings) LOOP
  SELECT * INTO v_seg FROM public.translation_segments WHERE story_id=p_story AND translation_artifact_id=p_translation AND id=(v_item->>'translationSegmentId')::uuid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Finding must reference an exact approved translation segment.'; END IF;
  SELECT * INTO v_cutseg FROM public.story_cut_segments WHERE story_id=p_story AND cut_artifact_id=v_tv.story_cut_artifact_id AND id=v_seg.cut_segment_id;
  INSERT INTO public.privacy_findings(story_id,privacy_review_artifact_id,proposal_source,proposal_model,risk_category,proposal_summary,suggested_safer_alternative,translation_artifact_id,translation_segment_id)
   VALUES(p_story,v_artifact,'AI',p_model,left(btrim(v_item->>'riskCategory'),80),btrim(v_item->>'affectedPassage'),nullif(btrim(v_item->>'suggestedSaferAlternative'),''),p_translation,v_seg.id);
  v_count:=v_count+1;
 END LOOP;
 UPDATE public.artifact_versions SET content_sha256=p_hash,sealed_at=clock_timestamp() WHERE story_id=p_story AND id=v_artifact;
 PERFORM irin_private.emit_audit_event(p_story,v_owner,'PRIVACY_REVIEW_CREATED',v_artifact,NULL,jsonb_build_object('translation_artifact_id',p_translation,'source_media_artifact_id',v_tv.source_media_artifact_id,'story_cut_artifact_id',v_tv.story_cut_artifact_id,'finding_count',v_count,'proposal_source','AI'),NULL,NULL);
 RETURN v_artifact;
END;$f$;

CREATE FUNCTION public.record_privacy_decision(p_story uuid,p_actor uuid,p_review uuid,p_finding uuid,p_decision public.privacy_decision)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE v_owner uuid; v_id uuid; v_resolution uuid; v_review_translation uuid; v_source uuid; v_transcript uuid;
BEGIN
 SELECT owner_id INTO v_owner FROM public.stories WHERE id=p_story FOR UPDATE;
 IF v_owner IS NULL OR v_owner<>p_actor THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
 SELECT r.translation_artifact_id,c.source_media_artifact_id,c.transcript_artifact_id INTO v_review_translation,v_source,v_transcript
 FROM public.privacy_findings f JOIN public.privacy_review_versions r ON r.story_id=f.story_id AND r.artifact_version_id=f.privacy_review_artifact_id
 JOIN public.story_cut_versions c ON c.story_id=r.story_id AND c.artifact_version_id=r.story_cut_artifact_id
 WHERE f.story_id=p_story AND f.id=p_finding AND r.artifact_version_id=p_review;
 IF v_review_translation IS NULL THEN RAISE EXCEPTION 'Finding is not part of the selected privacy review.'; END IF;
 IF p_decision='KEEP' THEN
  IF NOT irin_private.current_english_translation_is_approved(p_story,v_review_translation) THEN RAISE EXCEPTION 'KEEP applies only to the current approved translation.'; END IF;
 ELSE
  SELECT t.artifact_version_id INTO v_resolution FROM public.translation_versions t JOIN public.artifact_versions a ON a.story_id=t.story_id AND a.id=t.artifact_version_id
  WHERE t.story_id=p_story AND t.source_media_artifact_id=v_source AND t.transcript_artifact_id=v_transcript AND t.story_cut_artifact_id=(SELECT story_cut_artifact_id FROM public.privacy_review_versions WHERE story_id=p_story AND artifact_version_id=p_review)
   AND a.created_at>(SELECT created_at FROM public.privacy_findings WHERE story_id=p_story AND id=p_finding)
  ORDER BY a.version_number DESC LIMIT 1;
  IF v_resolution IS NULL OR NOT irin_private.current_english_translation_is_approved(p_story,v_resolution) THEN RAISE EXCEPTION 'A later approved edit with matching source lineage is required.'; END IF;
 END IF;
 INSERT INTO public.privacy_decisions(story_id,privacy_finding_id,decision,resolution_artifact_version_id,decided_by) VALUES(p_story,p_finding,p_decision,CASE WHEN p_decision='KEEP' THEN NULL ELSE v_resolution END,v_owner) RETURNING id INTO v_id;
 RETURN v_id;
END;$f$;

CREATE FUNCTION public.create_story_covenant(p_story uuid,p_actor uuid,p_permissions jsonb,p_hash bytea)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE v_owner uuid; v_review public.privacy_review_versions%ROWTYPE; v_artifact uuid; v_version integer; v_permission public.covenant_permission; v_allowed boolean;
BEGIN
 SELECT owner_id INTO v_owner FROM public.stories WHERE id=p_story FOR UPDATE;
 IF v_owner IS NULL OR v_owner<>p_actor THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
 SELECT r.* INTO v_review FROM public.privacy_review_versions r JOIN public.artifact_versions a ON a.story_id=r.story_id AND a.id=r.artifact_version_id WHERE r.story_id=p_story AND irin_private.current_english_translation_is_approved(r.story_id,r.translation_artifact_id) ORDER BY a.version_number DESC LIMIT 1;
 IF v_review.artifact_version_id IS NULL OR EXISTS(SELECT 1 FROM public.privacy_findings f WHERE f.story_id=p_story AND f.privacy_review_artifact_id=v_review.artifact_version_id AND NOT EXISTS(SELECT 1 FROM public.privacy_decisions d WHERE d.story_id=f.story_id AND d.privacy_finding_id=f.id)) THEN RAISE EXCEPTION 'Every finding in the current privacy review needs an explicit storyteller decision.'; END IF;
 IF jsonb_typeof(p_permissions)<>'object' OR (SELECT count(*) FROM jsonb_object_keys(p_permissions))<>10 OR octet_length(p_hash)<>32 THEN RAISE EXCEPTION 'All ten Covenant permissions are required.'; END IF;
 SELECT coalesce(max(version_number),0)+1 INTO v_version FROM public.artifact_versions WHERE story_id=p_story AND kind='COVENANT';
 INSERT INTO public.artifact_versions(story_id,kind,version_number,created_by) VALUES(p_story,'COVENANT',v_version,v_owner) RETURNING id INTO v_artifact;
 INSERT INTO public.story_covenant_versions(story_id,covenant_artifact_id,privacy_review_artifact_id,translation_artifact_id,story_cut_artifact_id,source_media_artifact_id)
 VALUES(p_story,v_artifact,v_review.artifact_version_id,v_review.translation_artifact_id,(SELECT story_cut_artifact_id FROM public.translation_versions WHERE story_id=p_story AND artifact_version_id=v_review.translation_artifact_id),(SELECT source_media_artifact_id FROM public.translation_versions WHERE story_id=p_story AND artifact_version_id=v_review.translation_artifact_id));
 FOR v_permission IN SELECT unnest(enum_range(NULL::public.covenant_permission)) LOOP
  IF NOT p_permissions ? v_permission::text OR jsonb_typeof(p_permissions->v_permission::text)<>'boolean' THEN RAISE EXCEPTION 'Every Covenant permission must be an explicit boolean.'; END IF;
  v_allowed:=(p_permissions->>v_permission::text)::boolean;
  IF v_permission='VOICE_CLONING' AND v_allowed THEN RAISE EXCEPTION 'Voice cloning cannot be permitted.'; END IF;
  INSERT INTO public.covenant_permissions(story_id,covenant_artifact_id,permission,allowed) VALUES(p_story,v_artifact,v_permission,v_allowed);
 END LOOP;
 UPDATE public.artifact_versions SET content_sha256=p_hash,sealed_at=clock_timestamp() WHERE story_id=p_story AND id=v_artifact;
 PERFORM irin_private.emit_audit_event(p_story,v_owner,'COVENANT_CREATED',v_artifact,NULL,jsonb_build_object('privacy_review_artifact_id',v_review.artifact_version_id,'translation_artifact_id',v_review.translation_artifact_id,'source_media_artifact_id',(SELECT source_media_artifact_id FROM public.translation_versions WHERE story_id=p_story AND artifact_version_id=v_review.translation_artifact_id)),NULL,NULL);
 RETURN v_artifact;
END;$f$;

CREATE FUNCTION public.approve_story_covenant(p_story uuid,p_actor uuid,p_artifact uuid)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE v_owner uuid; v_hash bytea; v_at timestamptz;
BEGIN
 SELECT owner_id INTO v_owner FROM public.stories WHERE id=p_story FOR UPDATE;
 IF v_owner IS NULL OR v_owner<>p_actor THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
 PERFORM irin_private.guard_covenant_approval(p_story,p_artifact);
 SELECT a.content_sha256 INTO v_hash FROM public.artifact_versions a WHERE a.story_id=p_story AND a.id=p_artifact AND a.kind='COVENANT' AND a.sealed_at IS NOT NULL;
 IF v_hash IS NULL OR EXISTS(SELECT 1 FROM public.privacy_review_versions r WHERE r.story_id=p_story AND irin_private.current_english_translation_is_approved(r.story_id,r.translation_artifact_id) AND EXISTS(SELECT 1 FROM public.privacy_findings f WHERE f.story_id=p_story AND f.privacy_review_artifact_id=r.artifact_version_id AND NOT EXISTS(SELECT 1 FROM public.privacy_decisions d WHERE d.story_id=f.story_id AND d.privacy_finding_id=f.id))) THEN RAISE EXCEPTION 'Current privacy findings must all be decided before Covenant approval.'; END IF;
 INSERT INTO public.covenant_approvals(story_id,covenant_artifact_id,approved_content_sha256,approved_by) VALUES(p_story,p_artifact,v_hash,v_owner) RETURNING approved_at INTO v_at;
 PERFORM irin_private.emit_audit_event(p_story,v_owner,'COVENANT_APPROVED',p_artifact,NULL,jsonb_build_object('approved_content_sha256',encode(v_hash,'hex')),NULL,NULL);
 RETURN v_at;
END;$f$;

CREATE FUNCTION public.protection_publication_eligible(p_story uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $f$
 SELECT EXISTS(SELECT 1 FROM public.privacy_review_versions r
  JOIN public.artifact_versions ra ON ra.story_id=r.story_id AND ra.id=r.artifact_version_id AND ra.sealed_at IS NOT NULL
  JOIN public.translation_versions t ON t.story_id=r.story_id AND t.artifact_version_id=r.translation_artifact_id
  JOIN public.artifact_versions ca ON ca.story_id=t.story_id AND ca.id=t.story_cut_artifact_id
  JOIN public.artifact_versions ta ON ta.story_id=t.story_id AND ta.id=t.artifact_version_id
  JOIN public.translation_approvals tap ON tap.story_id=t.story_id AND tap.translation_artifact_id=t.artifact_version_id AND tap.approved_content_sha256=ta.content_sha256
  JOIN public.covenant_approvals cap ON cap.story_id=r.story_id
  JOIN public.covenant_permissions cp ON cp.story_id=cap.story_id AND cp.covenant_artifact_id=cap.covenant_artifact_id AND cp.permission='PUBLIC_VIEWING' AND cp.allowed
  JOIN public.story_covenant_versions scv ON scv.story_id=cap.story_id AND scv.covenant_artifact_id=cap.covenant_artifact_id AND scv.privacy_review_artifact_id=r.artifact_version_id AND scv.translation_artifact_id=r.translation_artifact_id
  WHERE r.story_id=p_story AND irin_private.current_english_translation_is_approved(p_story,r.translation_artifact_id)
  AND r.artifact_version_id=(SELECT rr.artifact_version_id FROM public.privacy_review_versions rr JOIN public.artifact_versions av ON av.story_id=rr.story_id AND av.id=rr.artifact_version_id WHERE rr.story_id=p_story ORDER BY av.version_number DESC LIMIT 1)
  AND NOT EXISTS(SELECT 1 FROM public.privacy_findings f WHERE f.story_id=p_story AND f.privacy_review_artifact_id=r.artifact_version_id AND NOT EXISTS(SELECT 1 FROM public.privacy_decisions d WHERE d.story_id=f.story_id AND d.privacy_finding_id=f.id))
  AND irin_private.current_story_cut_is_approved(t.story_id,t.story_cut_artifact_id,t.source_media_artifact_id,t.transcript_artifact_id)
  AND cap.covenant_artifact_id=(SELECT v.id FROM public.artifact_versions v WHERE v.story_id=p_story AND v.kind='COVENANT' ORDER BY v.version_number DESC LIMIT 1)
  AND cap.approved_content_sha256=(SELECT content_sha256 FROM public.artifact_versions WHERE story_id=p_story AND id=cap.covenant_artifact_id)
  AND NOT EXISTS(SELECT 1 FROM public.covenant_permissions x WHERE x.story_id=p_story AND x.covenant_artifact_id=cap.covenant_artifact_id AND x.permission='VOICE_CLONING' AND x.allowed));
$f$;

REVOKE ALL ON FUNCTION public.persist_privacy_review(uuid,uuid,uuid,text,jsonb,bytea) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.persist_privacy_review(uuid,uuid,uuid,text,jsonb,bytea) TO service_role;
REVOKE ALL ON FUNCTION public.record_privacy_decision(uuid,uuid,uuid,uuid,public.privacy_decision) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_privacy_decision(uuid,uuid,uuid,uuid,public.privacy_decision) TO service_role;
REVOKE ALL ON FUNCTION public.create_story_covenant(uuid,uuid,jsonb,bytea) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_story_covenant(uuid,uuid,jsonb,bytea) TO service_role;
REVOKE ALL ON FUNCTION public.approve_story_covenant(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.approve_story_covenant(uuid,uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.protection_publication_eligible(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.protection_publication_eligible(uuid) TO service_role;
