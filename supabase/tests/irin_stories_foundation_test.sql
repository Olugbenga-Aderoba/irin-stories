-- Irin Stories foundation integration harness; all identities/content are synthetic.
-- Run: npx supabase db query --local --file supabase/tests/irin_stories_foundation_test.sql
-- One DO statement; final sentinel exception rolls the whole statement back.
DO $fixture$
DECLARE
  a constant uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
  b constant uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1';
  s1 constant uuid := '11111111-1111-4111-8111-111111111111';
  s2 constant uuid := '22222222-2222-4222-8222-222222222222';
  src1 constant uuid := '10000000-0000-4000-8000-000000000001';
  tr1 constant uuid := '10000000-0000-4000-8000-000000000002';
  cut1 constant uuid := '10000000-0000-4000-8000-000000000003';
  cul1 constant uuid := '10000000-0000-4000-8000-000000000004';
  trans1 constant uuid := '10000000-0000-4000-8000-000000000005';
  priv1 constant uuid := '10000000-0000-4000-8000-000000000006';
  cov1 constant uuid := '10000000-0000-4000-8000-000000000007';
  rend1 constant uuid := '10000000-0000-4000-8000-000000000008';
  src2 constant uuid := '20000000-0000-4000-8000-000000000001';
  tr2 constant uuid := '20000000-0000-4000-8000-000000000002';
  cut2 constant uuid := '20000000-0000-4000-8000-000000000003';
  seg1 uuid := '30000000-0000-4000-8000-000000000001';
  cseg1 uuid := '30000000-0000-4000-8000-000000000002';
  snap uuid := '40000000-0000-4000-8000-000000000001';
  pub uuid := '40000000-0000-4000-8000-000000000002';
  err text;
  st text;
  hash bytea := decode(repeat('ab', 32), 'hex');
  test_results jsonb := '[]'::jsonb;
  rpc_rows jsonb;
  diagnostic jsonb;
  rpc_count integer;
  key_list text[];
  n integer;
BEGIN
  INSERT INTO auth.users (id, aud, role, email, created_at, updated_at)
  VALUES (a,'authenticated','authenticated','synthetic-a@example.invalid',now(),now()),
         (b,'authenticated','authenticated','synthetic-b@example.invalid',now(),now());
  INSERT INTO public.stories(id,owner_id,title) VALUES
    (s1,a,'Synthetic Story A1'),(s2,a,'Synthetic Story A2');

  -- A1 source and storyteller-confirmed Yoruba transcript.
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by) VALUES (src1,s1,'SOURCE_MEDIA',1,a);
  INSERT INTO public.media_assets(story_id,artifact_version_id,role,bucket_id,object_key,content_sha256,mime_type,byte_size,duration_ms)
  VALUES(s1,src1,'SOURCE','synthetic-private','synthetic/a1/source.mp4',hash,'video/mp4',1000000,600000);
  UPDATE public.artifact_versions SET content_sha256=hash,sealed_at=now() WHERE id=src1;
  UPDATE public.stories SET workflow_state='LANGUAGE_CONFIRMATION' WHERE id=s1;
  INSERT INTO public.source_language_reviews(id,story_id,source_media_artifact_id,review_number,detected_language_code,confirmed_language_code,confirmed_by,confirmed_at)
  VALUES('50000000-0000-4000-8000-000000000001',s1,src1,1,'yor','yor',a,now());
  UPDATE public.stories SET workflow_state='TRANSCRIBING' WHERE id=s1;
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by) VALUES (tr1,s1,'TRANSCRIPT',1,a);
  INSERT INTO public.transcript_versions(story_id,artifact_version_id,source_media_artifact_id,language_review_id,language_code)
  VALUES(s1,tr1,src1,'50000000-0000-4000-8000-000000000001','yor');
  INSERT INTO public.transcript_segments(id,story_id,transcript_artifact_id,source_media_artifact_id,segment_number,source_start_ms,source_end_ms,text_yoruba)
  VALUES(seg1,s1,tr1,src1,1,10000,30000,'Ìtàn àdánwò wa.');
  UPDATE public.artifact_versions SET content_sha256=hash,sealed_at=now() WHERE id=tr1;
  INSERT INTO public.approvals(story_id,artifact_version_id,decision,approved_content_sha256,approver_id)
  VALUES(s1,tr1,'APPROVE',hash,a);
  UPDATE public.stories SET workflow_state='SOURCE_APPROVED' WHERE id=s1;
  UPDATE public.stories SET workflow_state='CRAFTING' WHERE id=s1;

  -- A1 Story Cut and cultural review.
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by) VALUES (cut1,s1,'STORY_CUT',1,a);
  INSERT INTO public.story_cut_versions(story_id,artifact_version_id,source_media_artifact_id,transcript_artifact_id,estimated_duration_ms)
  VALUES(s1,cut1,src1,tr1,10000);
  INSERT INTO public.story_cut_segments(id,story_id,cut_artifact_id,source_media_artifact_id,transcript_artifact_id,segment_number,source_start_ms,source_end_ms,output_start_ms,output_end_ms,narrative_role,selection_rationale,decision)
  VALUES(cseg1,s1,cut1,src1,tr1,1,10000,30000,0,10000,'opening','Synthetic approved interval','KEEP');
  UPDATE public.artifact_versions SET content_sha256=hash,sealed_at=now() WHERE id=cut1;
  INSERT INTO public.approvals(story_id,artifact_version_id,decision,approved_content_sha256,approver_id)
  VALUES(s1,cut1,'APPROVE',hash,a);
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by) VALUES (cul1,s1,'CULTURAL_REVIEW',1,a);
  INSERT INTO public.cultural_review_versions(story_id,artifact_version_id,story_cut_artifact_id) VALUES(s1,cul1,cut1);
  UPDATE public.artifact_versions SET content_sha256=hash,sealed_at=now() WHERE id=cul1;
  INSERT INTO public.approvals(story_id,artifact_version_id,decision,approved_content_sha256,approver_id)
  VALUES(s1,cul1,'APPROVE',hash,a);
  UPDATE public.stories SET workflow_state='CRAFT_APPROVED' WHERE id=s1;
  UPDATE public.stories SET workflow_state='TRANSLATING' WHERE id=s1;

  -- A1 English translation and completed, empty-findings privacy review.
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by) VALUES (trans1,s1,'TRANSLATION',1,a);
  INSERT INTO public.translation_versions(story_id,artifact_version_id,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id,cultural_review_artifact_id)
  VALUES(s1,trans1,src1,tr1,cut1,cul1);
  INSERT INTO public.translation_segments(story_id,translation_artifact_id,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id,cultural_review_artifact_id,cut_segment_id,transcript_segment_id,segment_number,cue_start_ms,cue_end_ms,english_text)
  VALUES(s1,trans1,src1,tr1,cut1,cul1,cseg1,seg1,1,0,10000,'Our synthetic story.');
  UPDATE public.artifact_versions SET content_sha256=hash,sealed_at=now() WHERE id=trans1;
  INSERT INTO public.approvals(story_id,artifact_version_id,decision,approved_content_sha256,approver_id)
  VALUES(s1,trans1,'APPROVE',hash,a);
  UPDATE public.stories SET workflow_state='TRANSLATION_APPROVED' WHERE id=s1;
  UPDATE public.stories SET workflow_state='PRIVACY_REVIEW' WHERE id=s1;
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by) VALUES (priv1,s1,'PRIVACY_REVIEW',1,a);
  INSERT INTO public.privacy_review_versions(story_id,artifact_version_id,story_cut_artifact_id,translation_artifact_id)
  VALUES(s1,priv1,cut1,trans1);
  UPDATE public.artifact_versions SET content_sha256=hash,sealed_at=now() WHERE id=priv1;
  INSERT INTO public.approvals(story_id,artifact_version_id,decision,approved_content_sha256,approver_id)
  VALUES(s1,priv1,'APPROVE',hash,a);
  UPDATE public.stories SET workflow_state='COVENANT_REVIEW' WHERE id=s1;

  -- Covenant with all ten explicit permissions; only public viewing is allowed.
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by) VALUES (cov1,s1,'COVENANT',1,a);
  INSERT INTO public.covenant_permissions(story_id,covenant_artifact_id,permission,allowed)
  SELECT s1,cov1,p,(p='PUBLIC_VIEWING') FROM unnest(enum_range(NULL::public.covenant_permission)) AS p;
  UPDATE public.artifact_versions SET content_sha256=hash,sealed_at=now() WHERE id=cov1;
  INSERT INTO public.approvals(story_id,artifact_version_id,decision,approved_content_sha256,approver_id)
  VALUES(s1,cov1,'APPROVE',hash,a);
  UPDATE public.stories SET workflow_state='PUBLICATION_REVIEW' WHERE id=s1;

  -- Final-media metadata, immutable snapshot and exact snapshot approval.
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by) VALUES (rend1,s1,'RENDERED_MEDIA',1,a);
  INSERT INTO public.media_assets(story_id,artifact_version_id,role,bucket_id,object_key,content_sha256,mime_type,byte_size,duration_ms,story_cut_artifact_id,translation_artifact_id)
  VALUES(s1,rend1,'FINAL_PUBLICATION','synthetic-public','synthetic/publication/final.mp4',hash,'video/mp4',500000,10000,cut1,trans1);
  UPDATE public.artifact_versions SET content_sha256=hash,sealed_at=now() WHERE id=rend1;
  INSERT INTO public.publication_snapshots(id,story_id,snapshot_version,public_id,title,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id,cultural_review_artifact_id,translation_artifact_id,privacy_review_artifact_id,covenant_artifact_id,rendered_media_artifact_id,ai_editing_disclosed,ai_translation_disclosed,manifest_sha256,created_by)
  VALUES(snap,s1,1,pub,'Synthetic publication',src1,tr1,cut1,cul1,trans1,priv1,cov1,rend1,true,true,hash,a);
  INSERT INTO public.publication_access(story_id,publication_snapshot_id) VALUES(s1,snap);
  INSERT INTO public.approvals(story_id,publication_snapshot_id,decision,approved_content_sha256,approver_id)
  VALUES(s1,snap,'APPROVE',hash,a);
  UPDATE public.publication_access SET access_state='PUBLISHED',published_by=a WHERE publication_snapshot_id=snap;

  -- Synthetic A2 source. Its own current source differs from A1's source.
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by) VALUES (src2,s2,'SOURCE_MEDIA',1,a);
  INSERT INTO public.media_assets(story_id,artifact_version_id,role,bucket_id,object_key,content_sha256,mime_type,byte_size,duration_ms)
  VALUES(s2,src2,'SOURCE','synthetic-private','synthetic/a2/source.mp4',hash,'video/mp4',1000000,600000);
  UPDATE public.artifact_versions SET content_sha256=hash,sealed_at=now() WHERE id=src2;
  UPDATE public.stories SET workflow_state='LANGUAGE_CONFIRMATION' WHERE id=s2;
  INSERT INTO public.source_language_reviews(id,story_id,source_media_artifact_id,review_number,detected_language_code,confirmed_language_code,confirmed_by,confirmed_at)
  VALUES('50000000-0000-4000-8000-000000000002',s2,src2,1,'yor','yor',a,now());
  UPDATE public.stories SET workflow_state='TRANSCRIBING' WHERE id=s2;
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by) VALUES (tr2,s2,'TRANSCRIPT',1,a);
  INSERT INTO public.transcript_versions(story_id,artifact_version_id,source_media_artifact_id,language_review_id,language_code)
  VALUES(s2,tr2,src2,'50000000-0000-4000-8000-000000000002','yor');
  INSERT INTO public.transcript_segments(id,story_id,transcript_artifact_id,source_media_artifact_id,segment_number,source_start_ms,source_end_ms,text_yoruba)
  VALUES('30000000-0000-4000-8000-000000000003',s2,tr2,src2,1,10000,30000,'Ìtàn àdánwò kejì.');
  UPDATE public.artifact_versions SET content_sha256=hash,sealed_at=now() WHERE id=tr2;
  INSERT INTO public.approvals(story_id,artifact_version_id,decision,approved_content_sha256,approver_id)
  VALUES(s2,tr2,'APPROVE',hash,a);

  -- A1 transcript attached to an A2 cut must be rejected by the cut source gate.
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by) VALUES (cut2,s2,'STORY_CUT',1,a);
  BEGIN
    INSERT INTO public.story_cut_versions(story_id,artifact_version_id,source_media_artifact_id,transcript_artifact_id,estimated_duration_ms)
    VALUES(s2,cut2,src2,tr1,10000);
    test_results := test_results || jsonb_build_array(jsonb_build_object('test', 'A1 -> A2 Story Cut lineage', 'expected', 'BLOCKED', 'actual', 'ALLOWED', 'sqlstate', NULL, 'detail', 'cross-story transcript unexpectedly attached', 'passed', false));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS err = MESSAGE_TEXT, st = RETURNED_SQLSTATE;
    test_results := test_results || jsonb_build_array(jsonb_build_object('test', 'A1 -> A2 Story Cut lineage', 'expected', 'BLOCKED', 'actual', 'BLOCKED', 'sqlstate', st, 'detail', err, 'passed', true));
  END;
  -- The same cross-story source/transcript pair is rejected before translation assembly.
  BEGIN
    INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by)
    VALUES('20000000-0000-4000-8000-000000000004',s2,'TRANSLATION',1,a);
    INSERT INTO public.translation_versions(story_id,artifact_version_id,source_media_artifact_id,transcript_artifact_id,story_cut_artifact_id,cultural_review_artifact_id)
    VALUES(s2,'20000000-0000-4000-8000-000000000004',src1,tr1,cut1,cul1);
    test_results := test_results || jsonb_build_array(jsonb_build_object('test', 'A1 -> A2 translation lineage', 'expected', 'BLOCKED', 'actual', 'ALLOWED', 'sqlstate', NULL, 'detail', 'cross-story translation unexpectedly attached', 'passed', false));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS err = MESSAGE_TEXT, st = RETURNED_SQLSTATE;
    test_results := test_results || jsonb_build_array(jsonb_build_object('test', 'A1 -> A2 translation lineage', 'expected', 'BLOCKED', 'actual', 'BLOCKED', 'sqlstate', st, 'detail', err, 'passed', true));
  END;

  -- Invalid approval rows: check target cardinality, hash shape, owner, and story binding.
  BEGIN
    INSERT INTO public.approvals(story_id,artifact_version_id,publication_snapshot_id,decision,approved_content_sha256,approver_id)
    VALUES(s1,tr1,snap,'APPROVE',hash,a);
    test_results := test_results || jsonb_build_array(jsonb_build_object('test', 'multiple-target approval', 'expected', 'BLOCKED', 'actual', 'ALLOWED', 'sqlstate', NULL, 'detail', 'both target columns accepted', 'passed', false));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS err=MESSAGE_TEXT,st=RETURNED_SQLSTATE;
    test_results := test_results || jsonb_build_array(jsonb_build_object('test', 'multiple-target approval', 'expected', 'BLOCKED', 'actual', 'BLOCKED', 'sqlstate', st, 'detail', err, 'passed', true));
  END;
  BEGIN
    PERFORM set_config('request.jwt.claim.sub',b::text,true);
    PERFORM set_config('role','authenticated',true);
    INSERT INTO public.approvals(story_id,artifact_version_id,decision,approved_content_sha256,approver_id)
    VALUES(s1,tr1,'APPROVE',hash,b);
    PERFORM set_config('role','postgres',true);
    test_results := test_results || jsonb_build_array(jsonb_build_object('test', 'cross-owner approval', 'expected', 'BLOCKED', 'actual', 'ALLOWED', 'sqlstate', NULL, 'detail', 'non-owner approval policy unexpectedly allowed insert', 'passed', false));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS err=MESSAGE_TEXT,st=RETURNED_SQLSTATE;
    PERFORM set_config('role','postgres',true);
    test_results := test_results || jsonb_build_array(jsonb_build_object('test', 'cross-owner approval', 'expected', 'BLOCKED', 'actual', 'BLOCKED', 'sqlstate', st, 'detail', err, 'passed', true));
  END;
  BEGIN
    INSERT INTO public.approvals(story_id,artifact_version_id,decision,approved_content_sha256,approver_id)
    VALUES(s1,'10000000-0000-4000-8000-000000000005','APPROVE',decode('abcd','hex'),a);
    test_results := test_results || jsonb_build_array(jsonb_build_object('test', 'malformed approval hash', 'expected', 'BLOCKED', 'actual', 'ALLOWED', 'sqlstate', NULL, 'detail', 'short hash accepted', 'passed', false));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS err=MESSAGE_TEXT,st=RETURNED_SQLSTATE;
    test_results := test_results || jsonb_build_array(jsonb_build_object('test', 'malformed approval hash', 'expected', 'BLOCKED', 'actual', 'BLOCKED', 'sqlstate', st, 'detail', err, 'passed', true));
  END;
  BEGIN
    INSERT INTO public.approvals(story_id,artifact_version_id,decision,approved_content_sha256,approver_id)
    VALUES(s2,tr1,'APPROVE',hash,a);
    test_results := test_results || jsonb_build_array(jsonb_build_object('test', 'cross-story approval', 'expected', 'BLOCKED', 'actual', 'ALLOWED', 'sqlstate', NULL, 'detail', 'cross-story target accepted', 'passed', false));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS err=MESSAGE_TEXT,st=RETURNED_SQLSTATE;
    test_results := test_results || jsonb_build_array(jsonb_build_object('test', 'cross-story approval', 'expected', 'BLOCKED', 'actual', 'BLOCKED', 'sqlstate', st, 'detail', err, 'passed', true));
  END;

  test_results := test_results || jsonb_build_array(jsonb_build_object('test', 'valid publication created', 'expected', 'ALLOWED', 'actual', 'ALLOWED', 'sqlstate', NULL, 'detail', 'all migration guards passed', 'passed', true));
  -- Capture predicate state so an empty RPC result distinguishes fixture from schema issues.
  SELECT jsonb_build_object(
    'access_state',(SELECT access_state::text FROM public.publication_access WHERE publication_snapshot_id=snap),
    'story_state',(SELECT workflow_state::text FROM public.stories WHERE id=s1),
    'snapshot_approved',EXISTS(SELECT 1 FROM public.approvals WHERE story_id=s1 AND publication_snapshot_id=snap AND decision='APPROVE' AND approved_content_sha256=hash),
    'active_covenant',irin_private.active_covenant_id(s1),
    'snapshot_valid',irin_private.publication_snapshot_is_valid(snap)
  ) INTO diagnostic;
  test_results := test_results || jsonb_build_array(jsonb_build_object('test','publication predicates diagnostic','expected','all true/current','actual',diagnostic,'sqlstate',NULL,'detail','inspect only if RPC result is empty','passed',true));

  -- Public RPC as anon. Capture the actual row as JSON and verify exact allowlist.
  PERFORM set_config('role','anon',true);
  SELECT count(*), coalesce(jsonb_agg(to_jsonb(result_row)),'[]'::jsonb)
    INTO rpc_count,rpc_rows
  FROM public.get_published_story(pub) AS result_row;
  PERFORM set_config('role','postgres',true);
  SELECT array_agg(key ORDER BY key) INTO key_list
  FROM jsonb_object_keys(rpc_rows->0) AS keys(key);
  test_results := test_results || jsonb_build_array(jsonb_build_object(
    'test','public RPC returns publication','expected','one row','actual',rpc_count,'sqlstate',NULL,
    'detail',rpc_rows::text,'passed',rpc_count=1));
  test_results := test_results || jsonb_build_array(jsonb_build_object(
    'test','public RPC returns only allowlisted fields','expected',
    jsonb_build_array('ai_editing_disclosed','ai_translation_disclosed','original_language_code','public_id','published_at','share_language_code','title'),
    'actual',to_jsonb(key_list),'sqlstate',NULL,'detail','actual anon RPC row columns','passed',
    key_list = ARRAY['ai_editing_disclosed','ai_translation_disclosed','original_language_code','public_id','published_at','share_language_code','title']::text[]));

  -- Withdraw as owner A through the authenticated role and its row policy.
  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  PERFORM set_config('role','authenticated',true);
  UPDATE public.publication_access SET access_state='WITHDRAWN'
  WHERE publication_snapshot_id=snap;
  PERFORM set_config('role','postgres',true);
  PERFORM set_config('role','anon',true);
  SELECT count(*) INTO rpc_count FROM public.get_published_story(pub);
  PERFORM set_config('role','postgres',true);
  test_results := test_results || jsonb_build_array(jsonb_build_object(
    'test','withdrawn publication publicly returned','expected',0,'actual',rpc_count,'sqlstate',NULL,
    'detail','anon RPC count after owner withdrawal','passed',rpc_count=0));

  SELECT count(*) INTO n FROM public.publication_snapshots WHERE id=snap;
  test_results := test_results || jsonb_build_array(jsonb_build_object('test','snapshot retained after withdrawal','expected',1,'actual',n,'sqlstate',NULL,'detail','publication_snapshots','passed',n=1));
  SELECT count(*) INTO n FROM public.approvals WHERE story_id=s1;
  test_results := test_results || jsonb_build_array(jsonb_build_object('test','approvals retained','expected',7,'actual',n,'sqlstate',NULL,'detail','artefact and snapshot approvals','passed',n>=7));
  SELECT count(*) INTO n FROM public.artifact_versions WHERE story_id=s1 AND kind='COVENANT';
  test_results := test_results || jsonb_build_array(jsonb_build_object('test','Covenant history retained','expected',1,'actual',n,'sqlstate',NULL,'detail','Covenant artifact retained','passed',n=1));
  SELECT
    (SELECT count(*) FROM public.media_assets WHERE story_id=s1 AND artifact_version_id=src1 AND role='SOURCE') +
    (SELECT count(*) FROM public.transcript_versions WHERE story_id=s1 AND artifact_version_id=tr1 AND source_media_artifact_id=src1) +
    (SELECT count(*) FROM public.transcript_segments WHERE story_id=s1 AND transcript_artifact_id=tr1 AND source_media_artifact_id=src1) +
    (SELECT count(*) FROM public.story_cut_versions WHERE story_id=s1 AND artifact_version_id=cut1 AND source_media_artifact_id=src1 AND transcript_artifact_id=tr1) +
    (SELECT count(*) FROM public.story_cut_segments WHERE story_id=s1 AND cut_artifact_id=cut1 AND transcript_artifact_id=tr1 AND source_media_artifact_id=src1) +
    (SELECT count(*) FROM public.translation_versions WHERE story_id=s1 AND artifact_version_id=trans1 AND source_media_artifact_id=src1 AND transcript_artifact_id=tr1 AND story_cut_artifact_id=cut1) +
    (SELECT count(*) FROM public.translation_segments WHERE story_id=s1 AND translation_artifact_id=trans1 AND source_media_artifact_id=src1 AND transcript_artifact_id=tr1 AND story_cut_artifact_id=cut1)
  INTO n;
  test_results := test_results || jsonb_build_array(jsonb_build_object('test','source/translation provenance retained','expected',7,'actual',n,'sqlstate',NULL,'detail','typed source media, transcript, Story Cut and translation lineage rows','passed',n=7));
  SELECT count(*) INTO n FROM public.covenant_permissions WHERE story_id=s1 AND covenant_artifact_id=cov1;
  test_results := test_results || jsonb_build_array(jsonb_build_object('test','Covenant permissions retained','expected',10,'actual',n,'sqlstate',NULL,'detail','all explicit permission history rows','passed',n=10));
  SELECT count(*) INTO n FROM public.audit_events WHERE story_id=s1;
  test_results := test_results || jsonb_build_array(jsonb_build_object('test','audit history retained','expected','>0','actual',n,'sqlstate',NULL,'detail','append-only workflow events','passed',n>0));
  RAISE EXCEPTION 'IRIN_STORIES_TEST_RESULTS:%',test_results::text;

END;
$fixture$;
