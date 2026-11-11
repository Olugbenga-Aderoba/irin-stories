-- Synthetic rollback-only local RLS/integration verifier for Verify A.
-- Requires the committed foundation/Storage migrations plus Verify A migrations.
-- Run only against the disposable local database at 127.0.0.1:54322.
DO $verify_test$
DECLARE
  a constant uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa01';
  b constant uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb01';
  s1 constant uuid := '11111111-1111-4111-8111-111111111101';
  s2 constant uuid := '22222222-2222-4222-8222-222222222202';
  src1 constant uuid := '10000000-0000-4000-8000-000000000101';
  src2 constant uuid := '20000000-0000-4000-8000-000000000202';
  src1_replacement constant uuid := '10000000-0000-4000-8000-000000000303';
  s3 constant uuid := '33333333-3333-4333-8333-333333333303';
  src3 constant uuid := '30000000-0000-4000-8000-000000000303';
  src3_replacement constant uuid := '30000000-0000-4000-8000-000000000304';
  fallback_decision uuid;
  transcript_id uuid;
  edited_transcript_id uuid;
  approval_result record;
  proposal1 uuid;
  proposal2 uuid;
  result_row record;
  expected_hash bytea := decode(repeat('cd', 32), 'hex');
  result jsonb := '[]'::jsonb;
  code text;
  error_message text;
  value boolean;
  rows_visible integer;

BEGIN
  INSERT INTO auth.users (id, aud, role, email, created_at, updated_at)
  VALUES (a,'authenticated','authenticated','verify-a@example.invalid',now(),now()),
         (b,'authenticated','authenticated','verify-b@example.invalid',now(),now());
  INSERT INTO public.stories(id,owner_id,title) VALUES
    (s1,a,'Synthetic Verify A1'),(s2,a,'Synthetic Verify A2');

  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by)
  VALUES (src1,s1,'SOURCE_MEDIA',1,a),(src2,s2,'SOURCE_MEDIA',1,a);
  INSERT INTO public.media_assets(
    story_id,artifact_version_id,role,bucket_id,object_key,content_sha256,mime_type,
    byte_size,duration_ms,original_filename
  ) VALUES
    (s1,src1,'SOURCE','private-source','synthetic/a1/source.webm',expected_hash,'video/webm',1024,60000,'synthetic-a1.webm'),
    (s2,src2,'SOURCE','private-source','synthetic/a2/source.webm',expected_hash,'video/webm',1024,60000,'synthetic-a2.webm');
  UPDATE public.artifact_versions SET content_sha256=expected_hash,sealed_at=clock_timestamp()
  WHERE id IN (src1,src2);
  UPDATE public.stories SET workflow_state='MEDIA_READY' WHERE id IN (s1,s2);

  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('role','service_role',true);
  PERFORM public.record_source_media_verification(
    s1,src1,'READY','webm','matroska,webm',60000,true,true,'opus','vp8',64,64,
    expected_hash,'[]'::jsonb,'ffprobe','synthetic-test',a
  );
  PERFORM public.record_source_media_verification(
    s2,src2,'READY','webm','matroska,webm',60000,true,true,'opus','vp8',64,64,
    expected_hash,'[]'::jsonb,'ffprobe','synthetic-test',a
  );
  proposal1 := public.create_source_language_proposal(s1,src1,'yor','Yoruba',NULL,'synthetic-test-provider','test-model','req_synthetic_1');
  proposal2 := public.create_source_language_proposal(s2,src2,'yor','Yoruba',NULL,'synthetic-test-provider','test-model','req_synthetic_2');
  PERFORM public.record_language_detection_failure(s1,src1,'provider_timeout',a);
  SELECT count(*) INTO rows_visible FROM public.audit_events
  WHERE story_id=s1 AND event_type='LANGUAGE_DETECTION_FAILED'
    AND metadata->>'error_category'='provider_timeout';
  result := result || jsonb_build_array(jsonb_build_object('test','provider failure records only safe category','expected',1,'actual',rows_visible,'passed',rows_visible=1));
  IF rows_visible <> 1 THEN RAISE EXCEPTION 'Safe provider failure category was not audited.'; END IF;
  BEGIN
    UPDATE public.stories SET workflow_state='TRANSCRIBING' WHERE id=s1;
    code := 'unexpected success';
    error_message := '';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE, error_message = MESSAGE_TEXT;
  END;
  result := result || jsonb_build_array(jsonb_build_object('test','server workflow gate blocks transcription before storyteller confirmation','expected','BLOCKED','actual',code,'message',error_message,'passed',code='P0001' AND error_message LIKE 'Transcribing requires server-verified media%'));
  IF code <> 'P0001' OR error_message NOT LIKE 'Transcribing requires server-verified media%' THEN
    RAISE EXCEPTION 'The server transcription gate did not block this unconfirmed source.';
  END IF;

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  PERFORM set_config('role','authenticated',true);
  value := public.is_transcription_eligible(s1);
  result := result || jsonb_build_array(jsonb_build_object('test','proposal alone is not transcription eligible','expected',false,'actual',value,'passed',value=false));
  IF value THEN RAISE EXCEPTION 'Proposal alone became transcription eligible.'; END IF;
  SELECT count(*) INTO rows_visible
  FROM public.source_language_reviews
  WHERE id=proposal1 AND provider_request_id='req_synthetic_1';
  result := result || jsonb_build_array(jsonb_build_object('test','safe provider request ID retained without transcript','expected',1,'actual',rows_visible,'passed',rows_visible=1));
  IF rows_visible <> 1 THEN RAISE EXCEPTION 'Provider request ID was not retained.'; END IF;

  PERFORM set_config('request.jwt.claim.sub',b::text,true);
  BEGIN
    PERFORM * FROM public.confirm_source_language(s1,src1,proposal1,'yor','Yoruba');
    code := 'unexpected success';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE;
  END;
  result := result || jsonb_build_array(jsonb_build_object('test','Storyteller B cannot confirm A language','expected','BLOCKED','actual',code,'passed',code='42501'));
  IF code <> '42501' THEN RAISE EXCEPTION 'Cross-owner confirmation was not rejected as expected.'; END IF;

  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  BEGIN
    PERFORM * FROM public.confirm_source_language(s1,src2,proposal2,'yor','Yoruba');
    code := 'unexpected success';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE;
  END;
  result := result || jsonb_build_array(jsonb_build_object('test','A cannot confirm media attached to another story','expected','BLOCKED','actual',code,'passed',code='42501'));
  IF code <> '42501' THEN RAISE EXCEPTION 'Cross-story confirmation was not rejected as expected.'; END IF;

  BEGIN
    PERFORM * FROM public.confirm_source_language(s1,src1,proposal1,'yor','Yoruba');
    code := 'unexpected success';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE;
  END;
  result := result || jsonb_build_array(jsonb_build_object('test','owner confirms current Yoruba proposal','expected','ALLOWED','actual',code,'passed',code='unexpected success'));
  IF code <> 'unexpected success' THEN RAISE EXCEPTION 'Owner confirmation unexpectedly failed with %.',code; END IF;
  value := public.is_transcription_eligible(s1);
  result := result || jsonb_build_array(jsonb_build_object('test','supported owner confirmation enables eligibility','expected',true,'actual',value,'passed',value));
  IF NOT value THEN RAISE EXCEPTION 'Supported owner confirmation did not enable eligibility.'; END IF;

  PERFORM set_config('request.jwt.claim.sub',b::text,true);
  BEGIN
    PERFORM public.create_source_language_proposal(s1,src1,'yor','Yoruba',NULL,'synthetic-test-provider','test-model','req_cross_owner');
    code := 'unexpected success';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE;
  END;
  result := result || jsonb_build_array(jsonb_build_object('test','Storyteller B cannot request detection for A media','expected','BLOCKED','actual',code,'passed',code='42501'));
  IF code <> '42501' THEN RAISE EXCEPTION 'Cross-owner detection attempt was not denied.'; END IF;
  SELECT count(*) INTO rows_visible FROM public.source_language_reviews WHERE story_id=s1;
  result := result || jsonb_build_array(jsonb_build_object('test','other storyteller cannot read A language history','expected',0,'actual',rows_visible,'passed',rows_visible=0));
  IF rows_visible <> 0 THEN RAISE EXCEPTION 'RLS exposed A language history to B.'; END IF;
  PERFORM set_config('request.jwt.claim.role','anon',true);
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('role','anon',true);
  BEGIN
    PERFORM public.create_source_language_proposal(s1,src1,'yor','Yoruba',NULL,'synthetic-test-provider','test-model','req_anonymous');
    code := 'unexpected success';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE;
  END;
  result := result || jsonb_build_array(jsonb_build_object('test','anonymous cannot request language detection','expected','BLOCKED','actual',code,'passed',code='42501'));
  IF code <> '42501' THEN RAISE EXCEPTION 'Anonymous detection request was not denied.'; END IF;
  BEGIN
    PERFORM * FROM public.confirm_source_language(s1,src1,proposal1,'yor','Yoruba');
    code := 'unexpected success';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE;
  END;
  result := result || jsonb_build_array(jsonb_build_object('test','anonymous cannot confirm language','expected','BLOCKED','actual',code,'passed',code='42501'));
  IF code <> '42501' THEN RAISE EXCEPTION 'Anonymous confirmation was not denied as expected.'; END IF;

  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('role','service_role',true);
  BEGIN
    PERFORM public.create_source_language_proposal(s1,src2,'yor','Yoruba',NULL,'synthetic-test-provider','test-model','req_wrong_story');
    code := 'unexpected success';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE;
  END;
  result := result || jsonb_build_array(jsonb_build_object('test','detection cannot use a source from another story','expected','BLOCKED','actual',code,'passed',code='42501'));
  IF code <> '42501' THEN RAISE EXCEPTION 'Cross-story proposal was not rejected as expected.'; END IF;

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  PERFORM set_config('role','authenticated',true);
  BEGIN
    PERFORM public.record_source_media_verification(
      s1,src1,'READY','webm','matroska,webm',60000,true,true,'opus','vp8',64,64,
      expected_hash,'[]'::jsonb,'ffprobe','synthetic-test',a
    );
    code := 'unexpected success';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE;
  END;
  result := result || jsonb_build_array(jsonb_build_object('test','client cannot forge server probe metadata','expected','BLOCKED','actual',code,'passed',code='42501'));
  IF code <> '42501' THEN RAISE EXCEPTION 'Client media verification write was not denied.'; END IF;
  SELECT * INTO result_row FROM public.confirm_source_language(s2,src2,proposal2,'eng','English');
  result := result || jsonb_build_array(jsonb_build_object('test','unsupported correction is retained as corrected','expected','CORRECTED','actual',result_row.review_status,'passed',result_row.review_status='CORRECTED'));
  IF result_row.review_status <> 'CORRECTED' THEN RAISE EXCEPTION 'Unsupported correction was not retained as corrected.'; END IF;
  value := public.is_transcription_eligible(s2);
  result := result || jsonb_build_array(jsonb_build_object('test','unsupported correction remains ineligible','expected',false,'actual',value,'passed',NOT value));
  IF value THEN RAISE EXCEPTION 'Unsupported corrected language became transcription eligible.'; END IF;

  -- Human fallback: failed detection remains without a proposal; select and confirm are separate.
  PERFORM set_config('request.jwt.claim.role','postgres',true);
  PERFORM set_config('role','postgres',true);
  INSERT INTO public.stories(id,owner_id,title) VALUES(s3,a,'Synthetic storyteller fallback');
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by) VALUES(src3,s3,'SOURCE_MEDIA',1,a);
  INSERT INTO public.media_assets(story_id,artifact_version_id,role,bucket_id,object_key,content_sha256,mime_type,byte_size,duration_ms,original_filename)
    VALUES(s3,src3,'SOURCE','private-source','synthetic/fallback/source.webm',expected_hash,'video/webm',1024,60000,'fallback.webm');
  UPDATE public.artifact_versions SET content_sha256=expected_hash,sealed_at=clock_timestamp() WHERE id=src3;
  PERFORM set_config('request.jwt.claim.role','service_role',true); PERFORM set_config('role','service_role',true);
  PERFORM public.record_source_media_verification(s3,src3,'READY','webm','matroska,webm',60000,true,true,'opus','vp8',64,64,expected_hash,'[]'::jsonb,'ffprobe','synthetic-test',a);
  INSERT INTO public.verify_language_detection_diagnostics(correlation_id,story_id,attempted_at,stage,category,retryable,provider,model)
    VALUES('30000000-0000-4000-8000-000000000305',s3,clock_timestamp(),'provider_response_validation','no_reliable_language',true,'openai','gpt-transcribe');
  SELECT count(*) INTO rows_visible FROM public.source_language_reviews WHERE story_id=s3;
  IF rows_visible<>0 THEN RAISE EXCEPTION 'Failed detection fabricated an AI proposal.'; END IF;
  PERFORM set_config('request.jwt.claim.role','authenticated',true); PERFORM set_config('request.jwt.claim.sub',a::text,true); PERFORM set_config('role','authenticated',true);
  fallback_decision:=public.select_storyteller_language(s3,'yor','Yoruba');
  SELECT count(*) INTO rows_visible FROM public.storyteller_language_decisions WHERE id=fallback_decision AND state='selected' AND confirmed_by IS NULL AND confirmed_at IS NULL AND decision_origin='storyteller_selected' AND selected_language_code='yor';
  IF rows_visible<>1 OR public.is_transcription_eligible(s3) THEN RAISE EXCEPTION 'Selection became confirmed or eligible before explicit confirmation.'; END IF;
  PERFORM set_config('request.jwt.claim.sub',b::text,true);
  BEGIN PERFORM * FROM public.confirm_storyteller_language(s3,fallback_decision); code:='unexpected success'; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
  IF code<>'42501' THEN RAISE EXCEPTION 'Cross-owner confirmation was not blocked.'; END IF;
  PERFORM set_config('request.jwt.claim.role','anon',true); PERFORM set_config('request.jwt.claim.sub','',true); PERFORM set_config('role','anon',true);
  BEGIN PERFORM public.select_storyteller_language(s3,'yor','Yoruba'); code:='unexpected success'; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
  IF code<>'42501' THEN RAISE EXCEPTION 'Anonymous selection was not blocked.'; END IF;
  PERFORM set_config('request.jwt.claim.role','authenticated',true); PERFORM set_config('request.jwt.claim.sub',a::text,true); PERFORM set_config('role','authenticated',true);
  BEGIN PERFORM * FROM public.confirm_storyteller_language(s3,fallback_decision);
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS error_message=MESSAGE_TEXT; RAISE EXCEPTION 'fallback owner confirmation failed: %',error_message; END;
  SELECT count(*) INTO rows_visible FROM public.storyteller_language_decisions WHERE id=fallback_decision AND state='confirmed' AND confirmed_by=a AND confirmed_at IS NOT NULL;
  IF rows_visible<>1 OR NOT public.is_transcription_eligible(s3) THEN RAISE EXCEPTION 'Explicit confirmation did not enable eligibility.'; END IF;
  SELECT count(*) INTO rows_visible FROM public.audit_events WHERE story_id=s3 AND event_type IN ('STORYTELLER_LANGUAGE_SELECTED','STORYTELLER_LANGUAGE_CONFIRMED');
  IF rows_visible<>2 THEN RAISE EXCEPTION 'Separate selection and confirmation audit events are missing.'; END IF;
  PERFORM set_config('request.jwt.claim.role','service_role',true); PERFORM set_config('role','service_role',true);
  BEGIN
    transcript_id:=public.persist_yoruba_transcript(s3,b,src3,'[{"startSeconds":0,"endSeconds":1.2,"text":"AI original Yoruba"}]'::jsonb,expected_hash,'ai_transcription',NULL);
    RAISE EXCEPTION 'Cross-owner transcript persistence was unexpectedly allowed.';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
  transcript_id:=public.persist_yoruba_transcript(s3,a,src3,'[{"startSeconds":0,"endSeconds":1.2,"text":"AI original Yoruba"}]'::jsonb,expected_hash,'ai_transcription',NULL);
  SELECT * INTO result_row FROM public.transcript_versions WHERE story_id=s3 AND artifact_version_id=transcript_id;
  IF result_row.language_decision_id<>fallback_decision OR result_row.language_review_id IS NOT NULL THEN RAISE EXCEPTION 'Fallback transcript provenance was not linked to the storyteller decision.'; END IF;
  PERFORM set_config('request.jwt.claim.role','authenticated',true); PERFORM set_config('request.jwt.claim.sub',b::text,true); PERFORM set_config('role','authenticated',true);
  SELECT count(*) INTO rows_visible FROM public.transcript_versions WHERE story_id=s3;
  IF rows_visible<>0 OR has_function_privilege('authenticated','public.persist_yoruba_transcript(uuid,uuid,uuid,jsonb,bytea,text,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Storyteller B could access or forge transcript edits.'; END IF;
  PERFORM set_config('request.jwt.claim.role','service_role',true); PERFORM set_config('role','service_role',true);
  SELECT count(*) INTO rows_visible FROM public.transcript_segments WHERE story_id=s3 AND transcript_artifact_id=transcript_id AND initial_proposal='AI original Yoruba' AND text_yoruba='AI original Yoruba' AND source_start_ms=0 AND source_end_ms=1200;
  IF rows_visible<>1 THEN RAISE EXCEPTION 'Timestamped AI-original transcript segment was not stored.'; END IF;
  SELECT * INTO approval_result FROM public.approve_yoruba_transcript(s3,a,transcript_id);
  IF approval_result.transcript_artifact_id<>transcript_id OR approval_result.approved_content_sha256<>encode(expected_hash,'hex') OR approval_result.approved_at IS NULL THEN RAISE EXCEPTION 'Transcript approval did not bind the sealed version hash.'; END IF;
  BEGIN
    PERFORM * FROM public.approve_yoruba_transcript(s3,b,transcript_id);
    RAISE EXCEPTION 'Cross-owner transcript approval was unexpectedly allowed.';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
  edited_transcript_id:=public.persist_yoruba_transcript(s3,a,src3,'[{"segmentNumber":1,"text":"Storyteller correction"}]'::jsonb,decode(repeat('ef',32),'hex'),'storyteller_edit',transcript_id);
  SELECT count(*) INTO rows_visible FROM public.transcript_segments WHERE story_id=s3 AND transcript_artifact_id=edited_transcript_id AND initial_proposal='AI original Yoruba' AND text_yoruba='Storyteller correction';
  IF rows_visible<>1 THEN RAISE EXCEPTION 'Storyteller edit overwrote or lost the AI-original transcript.'; END IF;
  SELECT count(*) INTO rows_visible FROM public.transcript_segments WHERE story_id=s3 AND transcript_artifact_id=transcript_id AND initial_proposal='AI original Yoruba' AND text_yoruba='AI original Yoruba';
  IF rows_visible<>1 THEN RAISE EXCEPTION 'Editing modified the approved historical transcript.'; END IF;
  SELECT count(*) INTO rows_visible FROM public.transcript_approvals WHERE story_id=s3 AND transcript_artifact_id=transcript_id AND approved_content_sha256=expected_hash AND approved_by=a;
  IF rows_visible<>1 THEN RAISE EXCEPTION 'Exact historical approval was not retained.'; END IF;
  SELECT count(*) INTO rows_visible FROM public.audit_events WHERE story_id=s3 AND event_type IN ('TRANSCRIPT_EDITED','TRANSCRIPT_APPROVED');
  IF rows_visible<>2 THEN RAISE EXCEPTION 'Transcript edit and approval audit events are missing.'; END IF;
  IF has_function_privilege('anon','public.persist_yoruba_transcript(uuid,uuid,uuid,jsonb,bytea,text,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.approve_yoruba_transcript(uuid,uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Anonymous transcript persistence or approval permission exists.'; END IF;
  result:=result||jsonb_build_array(jsonb_build_object('test','fallback transcript versioning preserves AI original, edit history and exact-hash owner approval','passed',true));
  PERFORM set_config('request.jwt.claim.role','authenticated',true); PERFORM set_config('request.jwt.claim.sub',a::text,true); PERFORM set_config('role','authenticated',true);
  PERFORM set_config('request.jwt.claim.role','postgres',true); PERFORM set_config('role','postgres',true);
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by) VALUES(src3_replacement,s3,'SOURCE_MEDIA',2,a);
  INSERT INTO public.media_assets(story_id,artifact_version_id,role,bucket_id,object_key,content_sha256,mime_type,byte_size,duration_ms,original_filename)
    VALUES(s3,src3_replacement,'SOURCE','private-source','synthetic/fallback/replacement.webm',expected_hash,'video/webm',1024,60000,'replacement.webm');
  UPDATE public.artifact_versions SET content_sha256=expected_hash,sealed_at=clock_timestamp() WHERE id=src3_replacement;
  PERFORM set_config('request.jwt.claim.role','authenticated',true); PERFORM set_config('request.jwt.claim.sub',a::text,true); PERFORM set_config('role','authenticated',true);
  IF public.is_transcription_eligible(s3) THEN RAISE EXCEPTION 'Source replacement preserved eligibility.'; END IF;
  PERFORM set_config('request.jwt.claim.role','service_role',true); PERFORM set_config('role','service_role',true);
  SELECT count(*) INTO rows_visible FROM public.transcript_approvals WHERE story_id=s3 AND transcript_artifact_id=transcript_id AND approved_by=a;
  IF rows_visible<>1 THEN RAISE EXCEPTION 'Replacing the source deleted historical transcript approval.'; END IF;
  BEGIN PERFORM * FROM public.approve_yoruba_transcript(s3,a,edited_transcript_id); code:='unexpected success'; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE; END;
  IF code<>'42501' THEN RAISE EXCEPTION 'Source replacement did not invalidate transcript approval applicability.'; END IF;
  PERFORM set_config('request.jwt.claim.role','authenticated',true); PERFORM set_config('request.jwt.claim.sub',a::text,true); PERFORM set_config('role','authenticated',true);
  SELECT count(*) INTO rows_visible FROM public.source_language_reviews WHERE story_id=s3 AND detected_language_code='yor';
  IF rows_visible<>0 THEN RAISE EXCEPTION 'Fallback created a fake AI proposal.'; END IF;
  result:=result||jsonb_build_array(jsonb_build_object('test','no-reliable failure creates no AI proposal','passed',rows_visible=0));
  SELECT count(*) INTO rows_visible FROM public.storyteller_language_decisions WHERE id=fallback_decision AND state='invalidated' AND decision_origin='storyteller_selected' AND confirmed_by=a AND confirmed_at IS NOT NULL;
  result:=result||jsonb_build_array(jsonb_build_object('test','owner selects then separately confirms Yoruba and source replacement invalidates applicability','passed',rows_visible=1 AND NOT public.is_transcription_eligible(s3)));
  SELECT count(*) INTO rows_visible FROM public.audit_events WHERE story_id=s3 AND event_type IN ('LANGUAGE_DETECTION_UNRELIABLE','STORYTELLER_LANGUAGE_SELECTED','STORYTELLER_LANGUAGE_CONFIRMED','LANGUAGE_DECISION_INVALIDATED_BY_SOURCE_REPLACEMENT');
  result:=result||jsonb_build_array(jsonb_build_object('test','failed detection selection confirmation and source invalidation are audited','passed',rows_visible=4));

  PERFORM set_config('request.jwt.claim.role','postgres',true);
  PERFORM set_config('role','postgres',true);
  INSERT INTO public.artifact_versions(id,story_id,kind,version_number,created_by)
  VALUES(src1_replacement,s1,'SOURCE_MEDIA',2,a);
  INSERT INTO public.media_assets(
    story_id,artifact_version_id,role,bucket_id,object_key,content_sha256,mime_type,
    byte_size,duration_ms,original_filename
  ) VALUES(s1,src1_replacement,'SOURCE','private-source','synthetic/a1/replacement.webm',expected_hash,'video/webm',1024,60000,'synthetic-replacement.webm');
  UPDATE public.artifact_versions SET content_sha256=expected_hash,sealed_at=clock_timestamp()
  WHERE id=src1_replacement;
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('role','service_role',true);
  BEGIN
    PERFORM public.create_source_language_proposal(s1,src1_replacement,'yor','Yoruba',NULL,'synthetic-test-provider','test-model','req_unverified');
    code := 'unexpected success';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE;
  END;
  result := result || jsonb_build_array(jsonb_build_object('test','detection requires a registered usable-media verification','expected','BLOCKED','actual',code,'passed',code='42501'));
  IF code <> '42501' THEN RAISE EXCEPTION 'Unverified source was allowed to run language detection.'; END IF;
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  PERFORM set_config('role','authenticated',true);
  value := public.is_transcription_eligible(s1);
  result := result || jsonb_build_array(jsonb_build_object('test','source replacement invalidates old confirmation','expected',false,'actual',value,'passed',NOT value));
  IF value THEN RAISE EXCEPTION 'Source replacement preserved prior eligibility.'; END IF;
  SELECT count(*) INTO rows_visible FROM public.source_language_reviews WHERE story_id=s1;
  result := result || jsonb_build_array(jsonb_build_object('test','prior language provenance remains','expected',2,'actual',rows_visible,'passed',rows_visible=2));
  IF rows_visible <> 2 THEN RAISE EXCEPTION 'Prior language provenance was not retained.'; END IF;

  RAISE EXCEPTION 'VERIFY_LANGUAGE_RESULTS:%',result::text;
END;
$verify_test$;
