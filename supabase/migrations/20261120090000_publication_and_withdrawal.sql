-- Publish and withdrawal from exact currently approved source-language, cut, translation and Protect versions.
ALTER TABLE public.publication_snapshots
  ALTER COLUMN cultural_review_artifact_id DROP NOT NULL,
  ALTER COLUMN rendered_media_artifact_id DROP NOT NULL;

CREATE TABLE public.publication_snapshot_hashes (
 story_id uuid NOT NULL,
 publication_snapshot_id uuid NOT NULL,
 source_verification_id uuid NOT NULL,
 source_sha256 bytea NOT NULL CHECK(octet_length(source_sha256)=32),
 transcript_sha256 bytea NOT NULL CHECK(octet_length(transcript_sha256)=32),
 story_cut_sha256 bytea NOT NULL CHECK(octet_length(story_cut_sha256)=32),
 translation_sha256 bytea NOT NULL CHECK(octet_length(translation_sha256)=32),
 privacy_review_sha256 bytea NOT NULL CHECK(octet_length(privacy_review_sha256)=32),
 covenant_sha256 bytea NOT NULL CHECK(octet_length(covenant_sha256)=32),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(story_id,publication_snapshot_id),
 FOREIGN KEY(story_id,publication_snapshot_id) REFERENCES public.publication_snapshots(story_id,id) ON DELETE RESTRICT,
 FOREIGN KEY(source_verification_id) REFERENCES public.source_media_verifications(id) ON DELETE RESTRICT
);
ALTER TABLE public.publication_snapshot_hashes ENABLE ROW LEVEL SECURITY;
CREATE POLICY publication_snapshot_hashes_owner_read ON public.publication_snapshot_hashes FOR SELECT TO authenticated USING (irin_private.user_owns_story(story_id));
REVOKE ALL ON public.publication_snapshot_hashes FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.publication_snapshot_hashes TO authenticated;
GRANT INSERT,SELECT ON public.publication_snapshot_hashes TO service_role;
CREATE TRIGGER publication_snapshot_hashes_immutable BEFORE UPDATE OR DELETE ON public.publication_snapshot_hashes FOR EACH ROW EXECUTE FUNCTION irin_private.reject_row_mutation();

CREATE FUNCTION irin_private.publication_snapshot_hashes_valid(p_snapshot uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $f$
 SELECT EXISTS(
  SELECT 1 FROM public.publication_snapshots s
  JOIN public.publication_snapshot_hashes h ON h.story_id=s.story_id AND h.publication_snapshot_id=s.id
  JOIN public.source_media_verifications v ON v.story_id=h.story_id AND v.id=h.source_verification_id AND v.source_media_artifact_id=s.source_media_artifact_id AND v.status='READY'
  JOIN public.artifact_versions sa ON sa.story_id=s.story_id AND sa.id=s.source_media_artifact_id
  JOIN public.artifact_versions ta ON ta.story_id=s.story_id AND ta.id=s.transcript_artifact_id
  JOIN public.artifact_versions ca ON ca.story_id=s.story_id AND ca.id=s.story_cut_artifact_id
  JOIN public.artifact_versions ea ON ea.story_id=s.story_id AND ea.id=s.translation_artifact_id
  JOIN public.artifact_versions pa ON pa.story_id=s.story_id AND pa.id=s.privacy_review_artifact_id
  JOIN public.artifact_versions coa ON coa.story_id=s.story_id AND coa.id=s.covenant_artifact_id
  WHERE s.id=p_snapshot
   AND h.source_sha256=v.server_content_sha256 AND h.transcript_sha256=ta.content_sha256 AND h.story_cut_sha256=ca.content_sha256
   AND h.translation_sha256=ea.content_sha256 AND h.privacy_review_sha256=pa.content_sha256 AND h.covenant_sha256=coa.content_sha256
   AND v.verification_number=(SELECT max(x.verification_number) FROM public.source_media_verifications x WHERE x.story_id=v.story_id AND x.source_media_artifact_id=v.source_media_artifact_id)
   AND s.manifest_sha256=extensions.digest(convert_to(jsonb_build_object(
    'story_id',s.story_id,'snapshot_version',s.snapshot_version,'title',s.title,'original_language_code',s.original_language_code,'share_language_code',s.share_language_code,
    'source_media_artifact_id',s.source_media_artifact_id,'source_sha256',encode(h.source_sha256,'hex'),
    'transcript_artifact_id',s.transcript_artifact_id,'transcript_sha256',encode(h.transcript_sha256,'hex'),
    'story_cut_artifact_id',s.story_cut_artifact_id,'story_cut_sha256',encode(h.story_cut_sha256,'hex'),
    'translation_artifact_id',s.translation_artifact_id,'translation_sha256',encode(h.translation_sha256,'hex'),
    'privacy_review_artifact_id',s.privacy_review_artifact_id,'privacy_review_sha256',encode(h.privacy_review_sha256,'hex'),
    'covenant_artifact_id',s.covenant_artifact_id,'covenant_sha256',encode(h.covenant_sha256,'hex'),
    'ai_editing_disclosed',s.ai_editing_disclosed,'ai_translation_disclosed',s.ai_translation_disclosed
   )::text,'UTF8'),'sha256')
 );
$f$;
REVOKE ALL ON FUNCTION irin_private.publication_snapshot_hashes_valid(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION irin_private.publication_snapshot_hashes_valid(uuid) TO service_role;

CREATE OR REPLACE FUNCTION irin_private.validate_publication_snapshot(p_snapshot_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE s public.publication_snapshots%ROWTYPE; v_owner uuid; verification_id uuid; source_hash bytea; transcript_hash bytea; cut_hash bytea; translation_hash bytea; privacy_hash bytea; covenant_hash bytea; latest_review uuid; latest_covenant uuid; manifest jsonb;
BEGIN
 SELECT * INTO s FROM public.publication_snapshots WHERE id=p_snapshot_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Publication snapshot does not exist.'; END IF;
 SELECT owner_id INTO v_owner FROM public.stories WHERE id=s.story_id;
 IF s.created_by IS DISTINCT FROM v_owner OR s.original_language_code<>'yor' OR s.share_language_code<>'eng' OR NOT s.ai_editing_disclosed OR NOT s.ai_translation_disclosed THEN RAISE EXCEPTION 'Publication must be owner-created, Yoruba-to-English, and disclose AI assistance.'; END IF;
 SELECT id,server_content_sha256 INTO verification_id,source_hash FROM public.source_media_verifications v
 WHERE v.story_id=s.story_id AND v.source_media_artifact_id=s.source_media_artifact_id AND v.status='READY'
 ORDER BY v.verification_number DESC LIMIT 1;
 IF s.source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(s.story_id) OR verification_id IS NULL
   OR NOT EXISTS(SELECT 1 FROM public.media_assets m JOIN public.artifact_versions a ON a.story_id=m.story_id AND a.id=m.artifact_version_id WHERE m.story_id=s.story_id AND m.artifact_version_id=s.source_media_artifact_id AND m.role='SOURCE' AND a.kind='SOURCE_MEDIA' AND a.sealed_at IS NOT NULL) THEN RAISE EXCEPTION 'Current source must remain server-verified and private.'; END IF;
 IF NOT irin_private.current_transcript_is_approved(s.story_id,s.transcript_artifact_id,s.source_media_artifact_id)
   OR NOT EXISTS(SELECT 1 FROM public.transcript_versions t JOIN public.artifact_versions a ON a.story_id=t.story_id AND a.id=t.artifact_version_id WHERE t.story_id=s.story_id AND t.artifact_version_id=s.transcript_artifact_id AND t.source_media_artifact_id=s.source_media_artifact_id AND t.language_code='yor' AND a.sealed_at IS NOT NULL) THEN RAISE EXCEPTION 'Current Yoruba Source approval is required.'; END IF;
 IF NOT irin_private.current_story_cut_is_approved(s.story_id,s.story_cut_artifact_id,s.source_media_artifact_id,s.transcript_artifact_id)
   OR EXISTS(SELECT 1 FROM public.story_cut_segments cs WHERE cs.story_id=s.story_id AND cs.cut_artifact_id=s.story_cut_artifact_id AND cs.decision<>'KEEP') THEN RAISE EXCEPTION 'Current approved Story Cut is required.'; END IF;
 IF NOT irin_private.current_english_translation_is_approved(s.story_id,s.translation_artifact_id)
   OR NOT EXISTS(SELECT 1 FROM public.translation_versions t WHERE t.story_id=s.story_id AND t.artifact_version_id=s.translation_artifact_id AND t.source_media_artifact_id=s.source_media_artifact_id AND t.transcript_artifact_id=s.transcript_artifact_id AND t.story_cut_artifact_id=s.story_cut_artifact_id AND t.source_language_code='yor' AND t.target_language_code='eng') THEN RAISE EXCEPTION 'Current approved English translation is required.'; END IF;
 SELECT r.artifact_version_id INTO latest_review FROM public.privacy_review_versions r JOIN public.artifact_versions a ON a.story_id=r.story_id AND a.id=r.artifact_version_id WHERE r.story_id=s.story_id AND r.artifact_version_id=s.privacy_review_artifact_id AND r.story_cut_artifact_id=s.story_cut_artifact_id AND r.translation_artifact_id=s.translation_artifact_id ORDER BY a.version_number DESC LIMIT 1;
 IF latest_review IS NULL OR NOT public.protection_publication_eligible(s.story_id) THEN RAISE EXCEPTION 'Current completed privacy review, all storyteller decisions, and approved public-viewing Covenant are required.'; END IF;
 IF s.cultural_review_artifact_id IS NOT NULL OR s.rendered_media_artifact_id IS NOT NULL THEN RAISE EXCEPTION 'This metadata-only Publish MVP does not serve cultural-review or rendered-media artefacts.'; END IF;
 IF EXISTS(SELECT 1 FROM public.publication_snapshot_hashes WHERE story_id=s.story_id AND publication_snapshot_id=s.id) THEN
  IF NOT irin_private.publication_snapshot_hashes_valid(s.id) THEN RAISE EXCEPTION 'Publication snapshot component hashes no longer match their exact versions.'; END IF;
 ELSE
  SELECT content_sha256 INTO source_hash FROM public.artifact_versions WHERE story_id=s.story_id AND id=s.source_media_artifact_id;
  SELECT content_sha256 INTO transcript_hash FROM public.artifact_versions WHERE story_id=s.story_id AND id=s.transcript_artifact_id;
  SELECT content_sha256 INTO cut_hash FROM public.artifact_versions WHERE story_id=s.story_id AND id=s.story_cut_artifact_id;
  SELECT content_sha256 INTO translation_hash FROM public.artifact_versions WHERE story_id=s.story_id AND id=s.translation_artifact_id;
  SELECT content_sha256 INTO privacy_hash FROM public.artifact_versions WHERE story_id=s.story_id AND id=s.privacy_review_artifact_id;
  SELECT content_sha256 INTO covenant_hash FROM public.artifact_versions WHERE story_id=s.story_id AND id=s.covenant_artifact_id;
  IF source_hash IS NULL OR transcript_hash IS NULL OR cut_hash IS NULL OR translation_hash IS NULL OR privacy_hash IS NULL OR covenant_hash IS NULL THEN RAISE EXCEPTION 'Every publication version must have a sealed content hash.'; END IF;
 END IF;
END;$f$;

CREATE OR REPLACE FUNCTION irin_private.publication_snapshot_is_valid(p_snapshot_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $f$
BEGIN PERFORM irin_private.validate_publication_snapshot(p_snapshot_id); RETURN true; EXCEPTION WHEN OTHERS THEN RETURN false; END;$f$;

CREATE FUNCTION public.publication_is_eligible(p_story uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $f$
 SELECT EXISTS(
  SELECT 1 FROM public.stories s
  JOIN public.media_assets m ON m.story_id=s.id AND m.artifact_version_id=irin_private.latest_source_media_id(s.id) AND m.role='SOURCE'
  JOIN public.source_media_verifications v ON v.story_id=s.id AND v.source_media_artifact_id=m.artifact_version_id AND v.status='READY'
  JOIN public.transcript_versions t ON t.story_id=s.id AND t.source_media_artifact_id=m.artifact_version_id AND t.language_code='yor'
  JOIN public.story_cut_versions c ON c.story_id=s.id AND c.source_media_artifact_id=m.artifact_version_id AND c.transcript_artifact_id=t.artifact_version_id
  JOIN public.translation_versions e ON e.story_id=s.id AND e.source_media_artifact_id=m.artifact_version_id AND e.transcript_artifact_id=t.artifact_version_id AND e.story_cut_artifact_id=c.artifact_version_id
  WHERE s.id=p_story AND v.verification_number=(SELECT max(v2.verification_number) FROM public.source_media_verifications v2 WHERE v2.story_id=s.id AND v2.source_media_artifact_id=m.artifact_version_id)
   AND irin_private.current_transcript_is_approved(s.id,t.artifact_version_id,m.artifact_version_id)
   AND irin_private.current_story_cut_is_approved(s.id,c.artifact_version_id,m.artifact_version_id,t.artifact_version_id)
   AND irin_private.current_english_translation_is_approved(s.id,e.artifact_version_id)
   AND public.protection_publication_eligible(s.id));
$f$;

CREATE FUNCTION public.create_publication_snapshot(p_story uuid,p_actor uuid)
RETURNS TABLE(snapshot_id uuid,public_id uuid,manifest_sha256 text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE own uuid; src uuid; tr uuid; cut uuid; trans uuid; review uuid; cov uuid; verify_id uuid; src_hash bytea; tr_hash bytea; cut_hash bytea; trans_hash bytea; review_hash bytea; cov_hash bytea; ver integer; title_value text; manifest jsonb; created_snapshot uuid; public_value uuid; current_state public.story_workflow_state;
BEGIN
 SELECT owner_id,title,workflow_state INTO own,title_value,current_state FROM public.stories WHERE id=p_story FOR UPDATE;
 IF own IS NULL OR own<>p_actor THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
 IF current_state='PUBLISHED' THEN RAISE EXCEPTION 'Withdraw or stale the current publication before preparing another snapshot.'; END IF;
 src:=irin_private.latest_source_media_id(p_story);
 SELECT t.artifact_version_id INTO tr FROM public.transcript_versions t WHERE t.story_id=p_story AND t.source_media_artifact_id=src AND t.language_code='yor' AND irin_private.current_transcript_is_approved(p_story,t.artifact_version_id,src) ORDER BY t.created_at DESC LIMIT 1;
 SELECT c.artifact_version_id INTO cut FROM public.story_cut_versions c WHERE c.story_id=p_story AND c.source_media_artifact_id=src AND c.transcript_artifact_id=tr AND irin_private.current_story_cut_is_approved(p_story,c.artifact_version_id,src,tr) ORDER BY c.created_at DESC LIMIT 1;
 SELECT t.artifact_version_id INTO trans FROM public.translation_versions t WHERE t.story_id=p_story AND t.source_media_artifact_id=src AND t.transcript_artifact_id=tr AND t.story_cut_artifact_id=cut AND irin_private.current_english_translation_is_approved(p_story,t.artifact_version_id) ORDER BY t.created_at DESC LIMIT 1;
 SELECT r.artifact_version_id INTO review FROM public.privacy_review_versions r WHERE r.story_id=p_story AND r.translation_artifact_id=trans AND r.story_cut_artifact_id=cut ORDER BY r.created_at DESC LIMIT 1;
 SELECT c.covenant_artifact_id INTO cov FROM public.story_covenant_versions c JOIN public.covenant_approvals a ON a.story_id=c.story_id AND a.covenant_artifact_id=c.covenant_artifact_id JOIN public.artifact_versions av ON av.story_id=a.story_id AND av.id=a.covenant_artifact_id AND av.content_sha256=a.approved_content_sha256 WHERE c.story_id=p_story AND c.privacy_review_artifact_id=review AND c.translation_artifact_id=trans ORDER BY av.version_number DESC LIMIT 1;
 SELECT id,server_content_sha256 INTO verify_id,src_hash FROM public.source_media_verifications v WHERE v.story_id=p_story AND v.source_media_artifact_id=src AND v.status='READY' ORDER BY verification_number DESC LIMIT 1;
 SELECT content_sha256 INTO tr_hash FROM public.artifact_versions WHERE story_id=p_story AND id=tr AND sealed_at IS NOT NULL;
 SELECT content_sha256 INTO cut_hash FROM public.artifact_versions WHERE story_id=p_story AND id=cut AND sealed_at IS NOT NULL;
 SELECT content_sha256 INTO trans_hash FROM public.artifact_versions WHERE story_id=p_story AND id=trans AND sealed_at IS NOT NULL;
 SELECT content_sha256 INTO review_hash FROM public.artifact_versions WHERE story_id=p_story AND id=review AND sealed_at IS NOT NULL;
 SELECT content_sha256 INTO cov_hash FROM public.artifact_versions WHERE story_id=p_story AND id=cov AND sealed_at IS NOT NULL;
 IF src IS NULL OR tr IS NULL OR cut IS NULL OR trans IS NULL OR review IS NULL OR cov IS NULL OR verify_id IS NULL OR NOT public.protection_publication_eligible(p_story) THEN RAISE EXCEPTION 'The current source, cut, translation, privacy decisions, and public-viewing Covenant must all be approved.'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.covenant_permissions p WHERE p.story_id=p_story AND p.covenant_artifact_id=cov AND p.permission='PUBLIC_VIEWING' AND p.allowed) THEN RAISE EXCEPTION 'Public viewing must be explicitly allowed by the active Covenant.'; END IF;
 UPDATE public.stories SET workflow_state='PUBLICATION_REVIEW' WHERE id=p_story AND workflow_state<>'PUBLICATION_REVIEW';
 SELECT coalesce(max(snapshot_version),0)+1 INTO ver FROM public.publication_snapshots WHERE story_id=p_story;
 manifest:=jsonb_build_object('story_id',p_story,'snapshot_version',ver,'title',title_value,'original_language_code','yor','share_language_code','eng','source_media_artifact_id',src,'source_sha256',encode(src_hash,'hex'),'transcript_artifact_id',tr,'transcript_sha256',encode(tr_hash,'hex'),'story_cut_artifact_id',cut,'story_cut_sha256',encode(cut_hash,'hex'),'translation_artifact_id',trans,'translation_sha256',encode(trans_hash,'hex'),'privacy_review_artifact_id',review,'privacy_review_sha256',encode(review_hash,'hex'),'covenant_artifact_id',cov,'covenant_sha256',encode(cov_hash,'hex'),'ai_editing_disclosed',true,'ai_translation_disclosed',true);
 INSERT INTO public.publication_snapshots(story_id,snapshot_version,title,original_language_code,share_language_code,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id,cultural_review_artifact_id,translation_artifact_id,privacy_review_artifact_id,covenant_artifact_id,rendered_media_artifact_id,ai_editing_disclosed,ai_translation_disclosed,manifest_sha256,created_by)
 VALUES(p_story,ver,title_value,'yor','eng',src,tr,cut,NULL,trans,review,cov,NULL,true,true,extensions.digest(convert_to(manifest::text,'UTF8'),'sha256'),own) RETURNING id,publication_snapshots.public_id INTO created_snapshot,public_value;
 INSERT INTO public.publication_snapshot_hashes(story_id,publication_snapshot_id,source_verification_id,source_sha256,transcript_sha256,story_cut_sha256,translation_sha256,privacy_review_sha256,covenant_sha256) VALUES(p_story,created_snapshot,verify_id,src_hash,tr_hash,cut_hash,trans_hash,review_hash,cov_hash);
 INSERT INTO public.publication_access(story_id,publication_snapshot_id,access_state) VALUES(p_story,created_snapshot,'DRAFT');
 PERFORM irin_private.validate_publication_snapshot(created_snapshot);
 snapshot_id:=created_snapshot; public_id:=public_value; manifest_sha256:=encode(extensions.digest(convert_to(manifest::text,'UTF8'),'sha256'),'hex'); RETURN NEXT;
END;$f$;

CREATE FUNCTION public.approve_publication_snapshot(p_story uuid,p_actor uuid,p_snapshot uuid)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE own uuid; hash_value bytea; approved timestamptz;
BEGIN
 SELECT owner_id INTO own FROM public.stories WHERE id=p_story FOR UPDATE;
 IF own IS NULL OR own<>p_actor THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
 PERFORM irin_private.validate_publication_snapshot(p_snapshot);
 IF NOT irin_private.publication_snapshot_hashes_valid(p_snapshot) OR NOT EXISTS(SELECT 1 FROM public.publication_snapshots WHERE story_id=p_story AND id=p_snapshot) THEN RAISE EXCEPTION 'Exact current publication snapshot is required.'; END IF;
 SELECT manifest_sha256 INTO hash_value FROM public.publication_snapshots WHERE story_id=p_story AND id=p_snapshot;
 INSERT INTO public.approvals(story_id,publication_snapshot_id,decision,approved_content_sha256,approver_id) VALUES(p_story,p_snapshot,'APPROVE',hash_value,own) RETURNING decided_at INTO approved;
 RETURN approved;
END;$f$;

CREATE FUNCTION public.publish_story_snapshot(p_story uuid,p_actor uuid,p_snapshot uuid)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE own uuid; published timestamptz;
BEGIN
 SELECT owner_id INTO own FROM public.stories WHERE id=p_story FOR UPDATE;
 IF own IS NULL OR own<>p_actor THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
 PERFORM irin_private.validate_publication_snapshot(p_snapshot);
 IF NOT irin_private.publication_snapshot_hashes_valid(p_snapshot) OR NOT EXISTS(SELECT 1 FROM public.approvals a JOIN public.publication_snapshots s ON s.story_id=a.story_id AND s.id=a.publication_snapshot_id WHERE a.story_id=p_story AND a.publication_snapshot_id=p_snapshot AND a.decision='APPROVE' AND a.approved_content_sha256=s.manifest_sha256 AND a.approver_id=own) THEN RAISE EXCEPTION 'A separate final storyteller approval of this exact snapshot is required.'; END IF;
 UPDATE public.publication_access SET access_state='PUBLISHED',published_by=own WHERE story_id=p_story AND publication_snapshot_id=p_snapshot AND access_state='DRAFT' RETURNING publication_access.published_at INTO published;
 IF published IS NULL THEN RAISE EXCEPTION 'Only a draft approved snapshot may be published.'; END IF;
 RETURN published;
END;$f$;

CREATE FUNCTION public.withdraw_story_publication(p_story uuid,p_actor uuid,p_snapshot uuid)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE own uuid; withdrawn timestamptz;
BEGIN
 SELECT owner_id INTO own FROM public.stories WHERE id=p_story FOR UPDATE;
 IF own IS NULL OR own<>p_actor THEN RAISE EXCEPTION 'Story owner required.' USING ERRCODE='42501'; END IF;
 UPDATE public.publication_access SET access_state='WITHDRAWN',withdrawn_by=own WHERE story_id=p_story AND publication_snapshot_id=p_snapshot AND access_state='PUBLISHED' RETURNING publication_access.withdrawn_at INTO withdrawn;
 IF withdrawn IS NULL THEN RAISE EXCEPTION 'Only an active publication can be withdrawn.'; END IF;
 RETURN withdrawn;
END;$f$;

CREATE OR REPLACE FUNCTION public.get_published_story(p_public_id uuid)
RETURNS TABLE(public_id uuid,title text,original_language_code text,share_language_code text,ai_editing_disclosed boolean,ai_translation_disclosed boolean,published_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $f$
 SELECT s.public_id,s.title,s.original_language_code,s.share_language_code,s.ai_editing_disclosed,s.ai_translation_disclosed,a.published_at
 FROM public.publication_snapshots s JOIN public.publication_access a ON a.story_id=s.story_id AND a.publication_snapshot_id=s.id
 JOIN public.stories st ON st.id=s.story_id
 JOIN public.approvals ap ON ap.story_id=s.story_id AND ap.publication_snapshot_id=s.id AND ap.decision='APPROVE' AND ap.approved_content_sha256=s.manifest_sha256
 WHERE s.public_id=p_public_id AND a.access_state='PUBLISHED' AND st.workflow_state='PUBLISHED'
 AND s.snapshot_version=(SELECT max(x.snapshot_version) FROM public.publication_snapshots x WHERE x.story_id=s.story_id)
 AND irin_private.publication_snapshot_hashes_valid(s.id) AND irin_private.publication_snapshot_is_valid(s.id);
$f$;

REVOKE ALL ON FUNCTION public.create_publication_snapshot(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_publication_snapshot(uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.approve_publication_snapshot(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.approve_publication_snapshot(uuid,uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.publish_story_snapshot(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.publish_story_snapshot(uuid,uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.withdraw_story_publication(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.withdraw_story_publication(uuid,uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.get_published_story(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_published_story(uuid) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.publication_is_eligible(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.publication_is_eligible(uuid) TO service_role;
