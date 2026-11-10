-- Private source uploads for the authenticated Tell workflow.
-- This migration creates no public bucket and exposes no service key.

ALTER TABLE public.media_assets
  ADD COLUMN original_filename text;

ALTER TABLE public.media_assets
  ADD CONSTRAINT media_assets_original_filename_nonempty
  CHECK (original_filename IS NULL OR length(btrim(original_filename)) BETWEEN 1 AND 255);

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'private-source',
  'private-source',
  false,
  524288000,
  ARRAY['video/mp4', 'video/quicktime', 'video/webm']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY "anonymous cannot access source bucket"
ON storage.objects AS RESTRICTIVE FOR ALL TO anon
USING (bucket_id <> 'private-source')
WITH CHECK (bucket_id <> 'private-source');

CREATE POLICY "storytellers upload source media to their stories"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'private-source'
  AND owner_id = (SELECT auth.uid())::text
  AND cardinality(storage.foldername(name)) = 3
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND (storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'
  AND (storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'
  AND EXISTS (
    SELECT 1 FROM public.stories AS story
    WHERE story.id = ((storage.foldername(name))[2])::uuid
      AND story.owner_id = (SELECT auth.uid())
  )
  AND lower(storage.extension(name)) IN ('mp4', 'mov', 'webm')
);

CREATE POLICY "storytellers read their private source media"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'private-source'
  AND owner_id = (SELECT auth.uid())::text
  AND cardinality(storage.foldername(name)) = 3
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND EXISTS (
    SELECT 1 FROM public.stories AS story
    WHERE story.id = ((storage.foldername(name))[2])::uuid
      AND story.owner_id = (SELECT auth.uid())
  )
);

-- Deletion is available only for an unregistered upload whose metadata RPC failed.
-- Registered source artefacts and their immutable provenance are append-only.
CREATE POLICY "storytellers remove only unregistered source uploads"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'private-source'
  AND owner_id = (SELECT auth.uid())::text
  AND cardinality(storage.foldername(name)) = 3
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND EXISTS (
    SELECT 1 FROM public.stories AS story
    WHERE story.id = ((storage.foldername(name))[2])::uuid
      AND story.owner_id = (SELECT auth.uid())
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.media_assets AS media
    WHERE media.bucket_id = 'private-source'
      AND media.object_key = name
  )
);

CREATE OR REPLACE FUNCTION public.register_source_media(
  p_story_id uuid,
  p_artifact_id uuid,
  p_object_key text,
  p_original_filename text,
  p_mime_type text,
  p_byte_size bigint,
  p_duration_ms bigint,
  p_content_sha256 bytea
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_owner_id uuid := auth.uid();
  v_version integer;
BEGIN
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Authentication is required to register source media.'
      USING ERRCODE = '42501';
  END IF;

  IF p_story_id IS NULL
     OR p_artifact_id IS NULL
     OR p_object_key IS NULL
     OR cardinality(string_to_array(p_object_key, '/')) <> 4
     OR (string_to_array(p_object_key, '/'))[1] <> v_owner_id::text
     OR (string_to_array(p_object_key, '/'))[2] <> p_story_id::text
     OR (string_to_array(p_object_key, '/'))[3] <> p_artifact_id::text
     OR length(btrim((string_to_array(p_object_key, '/'))[4])) NOT BETWEEN 1 AND 255
     OR p_original_filename IS NULL
     OR length(btrim(p_original_filename)) NOT BETWEEN 1 AND 255
     OR p_mime_type IS NULL
     OR p_mime_type NOT IN ('video/mp4', 'video/quicktime', 'video/webm')
     OR NOT (
       (p_mime_type = 'video/mp4' AND lower(storage.extension(p_object_key)) = 'mp4')
       OR (p_mime_type = 'video/quicktime' AND lower(storage.extension(p_object_key)) = 'mov')
       OR (p_mime_type = 'video/webm' AND lower(storage.extension(p_object_key)) = 'webm')
     )
     OR p_byte_size IS NULL
     OR p_byte_size NOT BETWEEN 1 AND 524288000
     OR p_duration_ms IS NULL OR p_duration_ms <= 0
     OR p_content_sha256 IS NULL OR octet_length(p_content_sha256) <> 32 THEN
    RAISE EXCEPTION 'Source media metadata or owner/story object path is invalid.'
      USING ERRCODE = '22023';
  END IF;

  PERFORM 1 FROM public.stories AS story
  WHERE story.id = p_story_id AND story.owner_id = v_owner_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Story does not exist or is not owned by the authenticated storyteller.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM storage.objects AS object
    WHERE object.bucket_id = 'private-source'
      AND object.name = p_object_key
      AND object.owner_id = v_owner_id::text
  ) THEN
    RAISE EXCEPTION 'Uploaded private source object does not exist for this storyteller.'
      USING ERRCODE = '42501';
  END IF;

  SELECT coalesce(max(artifact.version_number), 0) + 1 INTO v_version
  FROM public.artifact_versions AS artifact
  WHERE artifact.story_id = p_story_id AND artifact.kind = 'SOURCE_MEDIA';

  INSERT INTO public.artifact_versions (
    id, story_id, kind, version_number, created_by
  ) VALUES (
    p_artifact_id, p_story_id, 'SOURCE_MEDIA', v_version, v_owner_id
  );

  INSERT INTO public.media_assets (
    story_id, artifact_version_id, role, bucket_id, object_key,
    original_filename, content_sha256, mime_type, byte_size, duration_ms
  ) VALUES (
    p_story_id, p_artifact_id, 'SOURCE', 'private-source', p_object_key,
    p_original_filename, p_content_sha256, p_mime_type, p_byte_size, p_duration_ms
  );

  UPDATE public.artifact_versions
  SET content_sha256 = p_content_sha256, sealed_at = clock_timestamp()
  WHERE story_id = p_story_id AND id = p_artifact_id;

  RETURN p_artifact_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.register_source_media(uuid, uuid, text, text, text, bigint, bigint, bytea)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_source_media(uuid, uuid, text, text, text, bigint, bigint, bytea)
  TO authenticated;

COMMENT ON FUNCTION public.register_source_media(uuid, uuid, text, text, text, bigint, bigint, bytea) IS
  'Registers an uploaded private source object after checking auth.uid(), owner/story/path binding, MIME, size, and metadata; creates and seals its SOURCE_MEDIA artefact and audit event atomically.';

CREATE OR REPLACE FUNCTION public.create_story()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_owner_id uuid := auth.uid();
  v_story_id uuid;
BEGIN
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'Authentication is required to create a story.'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.stories (owner_id, title)
  VALUES (v_owner_id, 'My Story')
  RETURNING id INTO v_story_id;

  RETURN v_story_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_story() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_story() TO authenticated;
COMMENT ON FUNCTION public.create_story() IS
  'Creates a My Story root owned only by auth.uid(); the caller cannot provide an owner ID.';
