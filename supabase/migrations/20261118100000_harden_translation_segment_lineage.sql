-- Keep segment source/cut/transcript lineage bound to its translation version
-- even when the optional cultural-review reference is NULL.
ALTER TABLE public.translation_versions
  ADD CONSTRAINT translation_versions_media_transcript_cut_unique
  UNIQUE (story_id,artifact_version_id,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id);
ALTER TABLE public.translation_segments
  ADD CONSTRAINT translation_segments_version_lineage_fk
  FOREIGN KEY (story_id,translation_artifact_id,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id)
  REFERENCES public.translation_versions(story_id,artifact_version_id,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id)
  ON DELETE RESTRICT;
