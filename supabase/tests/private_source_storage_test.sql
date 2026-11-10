-- Read-only RLS verification for fixtures created through the local Auth and
-- Storage APIs by private_source_storage_api_test.mjs. This file performs no
-- direct DML against storage.objects (Storage owns that table's write path).
DO $test$
DECLARE
  run_id text;
  a uuid;
  b uuid;
  a1 uuid;
  a2 uuid;
  media_id uuid;
  object_key text;
  actual_count integer;
  passed boolean;
  matrix jsonb := '[]'::jsonb;
BEGIN
  SELECT substring(email FROM '^codex-storage-a-([0-9a-f-]+)@example\.invalid$'), id
    INTO run_id, a
  FROM auth.users
  WHERE email ~ '^codex-storage-a-[0-9a-f-]+@example\.invalid$'
  ORDER BY created_at DESC LIMIT 1;
  IF run_id IS NULL THEN RAISE EXCEPTION 'Run private_source_storage_api_test.mjs first.'; END IF;

  SELECT id INTO b FROM auth.users WHERE email = 'codex-storage-b-' || run_id || '@example.invalid';
  SELECT id INTO a1 FROM public.stories WHERE owner_id=a AND title='Synthetic Storage A1 ' || run_id ORDER BY created_at LIMIT 1;
  SELECT id INTO a2 FROM public.stories WHERE owner_id=a AND title='Synthetic Storage A2 ' || run_id ORDER BY created_at LIMIT 1;
  SELECT media.artifact_version_id, media.object_key INTO media_id, object_key
  FROM public.media_assets AS media
  WHERE media.story_id=a1 AND media.original_filename='synthetic-' || run_id || '.webm';
  IF b IS NULL OR a1 IS NULL OR a2 IS NULL OR media_id IS NULL THEN
    RAISE EXCEPTION 'API fixture incomplete for run %.', run_id;
  END IF;

  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub',a::text,'role','authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*)::integer INTO actual_count FROM public.stories WHERE id IN (a1,a2);
  matrix := matrix || jsonb_build_array(jsonb_build_object('test','A reads two owned stories','expected',2,'actual',actual_count,'passed',actual_count=2));
  SELECT count(*)::integer INTO actual_count FROM storage.objects WHERE bucket_id='private-source' AND name=object_key;
  matrix := matrix || jsonb_build_array(jsonb_build_object('test','A reads own object metadata','expected',1,'actual',actual_count,'passed',actual_count=1));

  PERFORM set_config('request.jwt.claim.sub', b::text, true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub',b::text,'role','authenticated')::text, true);
  SELECT count(*)::integer INTO actual_count FROM public.stories WHERE id IN (a1,a2);
  matrix := matrix || jsonb_build_array(jsonb_build_object('test','B cannot read A stories','expected',0,'actual',actual_count,'passed',actual_count=0));
  SELECT count(*)::integer INTO actual_count FROM storage.objects WHERE bucket_id='private-source' AND name=object_key;
  matrix := matrix || jsonb_build_array(jsonb_build_object('test','B cannot read A object metadata','expected',0,'actual',actual_count,'passed',actual_count=0));

  PERFORM set_config('role', 'anon', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SELECT count(*)::integer INTO actual_count FROM storage.objects WHERE bucket_id='private-source' AND name=object_key;
  matrix := matrix || jsonb_build_array(jsonb_build_object('test','anonymous cannot read object metadata','expected',0,'actual',actual_count,'passed',actual_count=0));

  PERFORM set_config('role', 'postgres', true);
  SELECT NOT public INTO passed FROM storage.buckets WHERE id='private-source';
  matrix := matrix || jsonb_build_array(jsonb_build_object('test','source bucket is private','expected',true,'actual',passed,'passed',coalesce(passed,false)));
  SELECT count(*)::integer INTO actual_count FROM public.audit_events WHERE story_id=a1 AND artifact_version_id=media_id;
  matrix := matrix || jsonb_build_array(jsonb_build_object('test','source audit provenance retained','expected',1,'actual',actual_count,'passed',actual_count>=1));

  RAISE EXCEPTION 'IRIN_SOURCE_STORAGE_TEST_RESULTS:%', matrix::text;
END;
$test$;
