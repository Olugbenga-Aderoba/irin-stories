-- Verify CRAFT's versioned storyteller approval is authoritative for the exact Story Cut.
-- Its segment rows retain the legacy PROPOSED label, so publication must use the
-- exact current story_cut_approvals hash rather than that legacy per-row field.
CREATE OR REPLACE FUNCTION irin_private.validate_publication_snapshot(p_snapshot_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $f$
DECLARE s public.publication_snapshots%ROWTYPE; v_owner uuid; verification_id uuid; source_hash bytea; transcript_hash bytea; cut_hash bytea; translation_hash bytea; privacy_hash bytea; covenant_hash bytea; latest_review uuid;
BEGIN
 SELECT * INTO s FROM public.publication_snapshots WHERE id=p_snapshot_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Publication snapshot does not exist.'; END IF;
 SELECT owner_id INTO v_owner FROM public.stories WHERE id=s.story_id;
 IF s.created_by IS DISTINCT FROM v_owner OR s.original_language_code<>'yor' OR s.share_language_code<>'eng' OR NOT s.ai_editing_disclosed OR NOT s.ai_translation_disclosed THEN RAISE EXCEPTION 'Publication must be owner-created, Yoruba-to-English, and disclose AI assistance.'; END IF;
 SELECT id,server_content_sha256 INTO verification_id,source_hash FROM public.source_media_verifications v WHERE v.story_id=s.story_id AND v.source_media_artifact_id=s.source_media_artifact_id AND v.status='READY' ORDER BY v.verification_number DESC LIMIT 1;
 IF s.source_media_artifact_id IS DISTINCT FROM irin_private.latest_source_media_id(s.story_id) OR verification_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.media_assets m JOIN public.artifact_versions a ON a.story_id=m.story_id AND a.id=m.artifact_version_id WHERE m.story_id=s.story_id AND m.artifact_version_id=s.source_media_artifact_id AND m.role='SOURCE' AND a.kind='SOURCE_MEDIA' AND a.sealed_at IS NOT NULL) THEN RAISE EXCEPTION 'Current source must remain server-verified and private.'; END IF;
 IF NOT irin_private.current_transcript_is_approved(s.story_id,s.transcript_artifact_id,s.source_media_artifact_id) OR NOT EXISTS(SELECT 1 FROM public.transcript_versions t JOIN public.artifact_versions a ON a.story_id=t.story_id AND a.id=t.artifact_version_id WHERE t.story_id=s.story_id AND t.artifact_version_id=s.transcript_artifact_id AND t.source_media_artifact_id=s.source_media_artifact_id AND t.language_code='yor' AND a.sealed_at IS NOT NULL) THEN RAISE EXCEPTION 'Current Yoruba Source approval is required.'; END IF;
 IF NOT irin_private.current_story_cut_is_approved(s.story_id,s.story_cut_artifact_id,s.source_media_artifact_id,s.transcript_artifact_id) THEN RAISE EXCEPTION 'Current approved Story Cut is required.'; END IF;
 IF NOT irin_private.current_english_translation_is_approved(s.story_id,s.translation_artifact_id) OR NOT EXISTS(SELECT 1 FROM public.translation_versions t WHERE t.story_id=s.story_id AND t.artifact_version_id=s.translation_artifact_id AND t.source_media_artifact_id=s.source_media_artifact_id AND t.transcript_artifact_id=s.transcript_artifact_id AND t.story_cut_artifact_id=s.story_cut_artifact_id AND t.source_language_code='yor' AND t.target_language_code='eng') THEN RAISE EXCEPTION 'Current approved English translation is required.'; END IF;
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
