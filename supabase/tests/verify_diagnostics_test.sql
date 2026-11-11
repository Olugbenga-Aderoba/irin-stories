
-- Local-only, rollback-only synthetic contract matrix.
BEGIN;
DO $test$
DECLARE
  field text;
  sample text;
  rejected integer := 0;
  base_count bigint;
  id uuid := '70000000-0000-4000-8000-000000000001';
BEGIN
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.verify_language_detection_diagnostics'::regclass) THEN
    RAISE EXCEPTION 'RLS missing';
  END IF;
  IF has_table_privilege('anon','public.verify_language_detection_diagnostics','SELECT')
     OR has_table_privilege('authenticated','public.verify_language_detection_diagnostics','SELECT')
     OR has_table_privilege('anon','public.verify_language_detection_diagnostics','INSERT')
     OR has_table_privilege('authenticated','public.verify_language_detection_diagnostics','INSERT') THEN
    RAISE EXCEPTION 'Client table access granted';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
    AND table_name='verify_language_detection_diagnostics' AND column_name <> ALL(ARRAY[
      'correlation_id','story_id','attempted_at','stage','category','retryable','provider','model',
      'provider_http_status','provider_error_type','provider_error_code','provider_request_id','transport','database_code'])) THEN
    RAISE EXCEPTION 'Unexpected payload column';
  END IF;
  SELECT count(*) INTO base_count FROM public.source_language_reviews;
  SET LOCAL ROLE service_role;
  INSERT INTO public.verify_language_detection_diagnostics VALUES
    (id,NULL,now(),'ownership_check','provider_network_failure',true,'openai','gpt-transcribe',
     503,'connection_error',NULL,'req_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','network','42501');
  IF NOT EXISTS (SELECT 1 FROM public.verify_language_detection_diagnostics WHERE correlation_id=id) THEN
    RAISE EXCEPTION 'Service-role roundtrip failed';
  END IF;
  FOREACH field IN ARRAY ARRAY['stage','category','provider','model','provider_error_type','provider_error_code','provider_request_id','transport','database_code'] LOOP
    FOREACH sample IN ARRAY ARRAY[
      'This is a synthetic transcript paragraph with private details.',
      'sk-proj-syntheticKey123','Bearer synthetic-token','https://example.invalid',
      E'C:\\private\\source.wav','/private/source.wav','https://example.invalid/audio?token=synthetic',
      repeat('a',129),'{"raw":"synthetic response"}'
    ] LOOP
      BEGIN
        EXECUTE format('INSERT INTO public.verify_language_detection_diagnostics(correlation_id,attempted_at,stage,category,retryable,%I) VALUES (gen_random_uuid(),now(),%L,%L,true,%L)',
          field,'ownership_check','provider_network_failure',sample);
        -- stage/category already appear in the baseline: use a typed composite below instead.
        RAISE EXCEPTION 'Unexpected accepted value';
      EXCEPTION WHEN duplicate_column THEN
        BEGIN
          EXECUTE format('INSERT INTO public.verify_language_detection_diagnostics(correlation_id,attempted_at,stage,category,retryable) VALUES (gen_random_uuid(),now(),%L,%L,true)',
            CASE WHEN field='stage' THEN sample ELSE 'ownership_check' END,
            CASE WHEN field='category' THEN sample ELSE 'provider_network_failure' END);
          RAISE EXCEPTION 'Unexpected accepted value';
        EXCEPTION WHEN check_violation THEN rejected := rejected + 1;
        END;
      WHEN check_violation THEN rejected := rejected + 1;
      END;
    END LOOP;
  END LOOP;
  FOREACH sample IN ARRAY ARRAY['99','600','-1','40000','bad'] LOOP
    BEGIN
      EXECUTE format('INSERT INTO public.verify_language_detection_diagnostics(correlation_id,attempted_at,stage,category,retryable,provider_http_status) VALUES (gen_random_uuid(),now(),%L,%L,true,%L)','ownership_check','unknown_detection_failure',sample);
      RAISE EXCEPTION 'Invalid status accepted';
    EXCEPTION WHEN check_violation OR numeric_value_out_of_range OR invalid_text_representation THEN rejected := rejected+1;
    END;
  END LOOP;
  FOREACH sample IN ARRAY ARRAY['p0001','1234','123456','PGRST301','42 01'] LOOP
    BEGIN
      INSERT INTO public.verify_language_detection_diagnostics(correlation_id,attempted_at,stage,category,retryable,database_code)
        VALUES(gen_random_uuid(),now(),'ownership_check','unknown_detection_failure',true,sample);
      RAISE EXCEPTION 'Invalid SQLSTATE accepted';
    EXCEPTION WHEN check_violation THEN rejected := rejected+1;
    END;
  END LOOP;
  BEGIN
    INSERT INTO public.verify_language_detection_diagnostics(correlation_id,attempted_at,stage,category,retryable)
      VALUES(gen_random_uuid(),now(),'source_lookup','unknown_detection_failure',true);
    RAISE EXCEPTION 'Unresolved story allowed after ownership';
  EXCEPTION WHEN check_violation THEN rejected := rejected+1;
  END;
  IF (SELECT count(*) FROM public.source_language_reviews) <> base_count THEN RAISE EXCEPTION 'Proposal fabricated'; END IF;
  RAISE NOTICE 'PASS: % forbidden insertions rejected; valid service insert, RLS grants, exact columns, no fabricated proposal', rejected;
END;
$test$;
ROLLBACK;
