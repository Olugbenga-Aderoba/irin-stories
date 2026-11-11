-- Separate human language selection from explicit confirmation.
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'LANGUAGE_SELECTED';
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'LANGUAGE_SELECTION_CHANGED';
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'LANGUAGE_UNSUPPORTED_CONFIRMED';
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'LANGUAGE_DECISION_INVALIDATED';
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'LANGUAGE_DETECTION_UNRELIABLE';
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'STORYTELLER_LANGUAGE_SELECTED';
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'STORYTELLER_LANGUAGE_SELECTION_CHANGED';
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'STORYTELLER_LANGUAGE_CONFIRMED';
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'UNSUPPORTED_LANGUAGE_CONFIRMED';
ALTER TYPE public.audit_event_type ADD VALUE IF NOT EXISTS 'LANGUAGE_DECISION_INVALIDATED_BY_SOURCE_REPLACEMENT';

CREATE TYPE public.language_decision_origin AS ENUM
  ('ai_proposal_confirmed', 'storyteller_selected', 'storyteller_corrected');
CREATE TYPE public.language_decision_state AS ENUM
  ('selected', 'confirmed', 'superseded', 'invalidated');

CREATE TABLE public.storyteller_language_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.stories(id) ON DELETE RESTRICT,
  source_media_artifact_id uuid NOT NULL,
  detection_correlation_id uuid REFERENCES public.verify_language_detection_diagnostics(correlation_id) ON DELETE RESTRICT,
  proposal_review_id uuid,
  decision_origin public.language_decision_origin NOT NULL,
  state public.language_decision_state NOT NULL,
  selected_language_code text NOT NULL CHECK (selected_language_code ~ '^[a-z]{3}(-[A-Za-z0-9]{2,8})*$'),
  selected_language_name text NOT NULL CHECK (length(btrim(selected_language_name)) BETWEEN 1 AND 120),
  selected_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  selected_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  confirmed_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  confirmed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT storyteller_language_source_fk FOREIGN KEY (story_id,source_media_artifact_id)
    REFERENCES public.media_assets(story_id,artifact_version_id) ON DELETE RESTRICT,
  CONSTRAINT storyteller_language_proposal_fk FOREIGN KEY (story_id,proposal_review_id,source_media_artifact_id)
    REFERENCES public.source_language_reviews(story_id,id,source_media_artifact_id) ON DELETE RESTRICT,
  CONSTRAINT storyteller_language_origin_shape CHECK (
    (decision_origin='storyteller_selected' AND proposal_review_id IS NULL AND detection_correlation_id IS NOT NULL)
    OR (decision_origin='storyteller_corrected' AND proposal_review_id IS NOT NULL)
    OR (decision_origin='ai_proposal_confirmed' AND proposal_review_id IS NOT NULL)
  ),
  CONSTRAINT storyteller_language_confirmation_shape CHECK (
    (state IN ('selected','superseded') AND confirmed_by IS NULL AND confirmed_at IS NULL)
    OR (state='confirmed' AND confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL)
    OR (state='invalidated' AND ((confirmed_by IS NULL AND confirmed_at IS NULL) OR (confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL)))
  ),
  CONSTRAINT storyteller_language_one_current UNIQUE(story_id,source_media_artifact_id,id)
);
CREATE INDEX storyteller_language_decisions_latest ON public.storyteller_language_decisions(story_id,source_media_artifact_id,created_at DESC);
CREATE UNIQUE INDEX storyteller_language_one_pending_selection ON public.storyteller_language_decisions(story_id,source_media_artifact_id) WHERE state='selected';
ALTER TABLE public.storyteller_language_decisions ENABLE ROW LEVEL SECURITY;
CREATE POLICY storyteller_language_owner_read ON public.storyteller_language_decisions
  FOR SELECT TO authenticated USING (irin_private.user_owns_story(story_id));
REVOKE ALL ON public.storyteller_language_decisions FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.storyteller_language_decisions TO authenticated;
GRANT SELECT,INSERT,UPDATE ON public.storyteller_language_decisions TO service_role;

CREATE FUNCTION irin_private.guard_storyteller_language_decision() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_owner uuid; v_current uuid;
BEGIN
  SELECT owner_id INTO v_owner FROM public.stories WHERE id=NEW.story_id;
  v_current := irin_private.latest_source_media_id(NEW.story_id);
  IF TG_OP='INSERT' THEN
    IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM v_owner OR NEW.selected_by IS DISTINCT FROM auth.uid()
      OR NEW.source_media_artifact_id IS DISTINCT FROM v_current OR NEW.state<>'selected'
      OR NEW.confirmed_by IS NOT NULL OR NEW.confirmed_at IS NOT NULL THEN
      RAISE EXCEPTION 'Language selection must be a pending selection by the current owner for the current source.' USING ERRCODE='42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.source_media_verifications v WHERE v.story_id=NEW.story_id AND v.source_media_artifact_id=v_current AND v.status='READY'
      AND v.verification_number=(SELECT max(x.verification_number) FROM public.source_media_verifications x WHERE x.story_id=v.story_id AND x.source_media_artifact_id=v.source_media_artifact_id)) THEN
      RAISE EXCEPTION 'Current source must be verified.' USING ERRCODE='42501';
    END IF;
  ELSE
    IF NEW.state='invalidated' AND OLD.state IN ('selected','confirmed') AND NEW.source_media_artifact_id IS DISTINCT FROM v_current
      AND NEW.id=OLD.id AND NEW.story_id=OLD.story_id AND NEW.selected_language_code=OLD.selected_language_code
      AND NEW.selected_language_name=OLD.selected_language_name AND NEW.selected_by=OLD.selected_by
      AND NEW.selected_at=OLD.selected_at AND NEW.decision_origin=OLD.decision_origin
      AND NEW.confirmed_by IS NOT DISTINCT FROM OLD.confirmed_by AND NEW.confirmed_at IS NOT DISTINCT FROM OLD.confirmed_at
      AND NEW.proposal_review_id IS NOT DISTINCT FROM OLD.proposal_review_id AND NEW.detection_correlation_id IS NOT DISTINCT FROM OLD.detection_correlation_id THEN
      RETURN NEW;
    END IF;
    IF OLD.state<>'selected' OR NEW.state NOT IN ('confirmed','superseded') OR NEW.id IS DISTINCT FROM OLD.id
      OR NEW.story_id IS DISTINCT FROM OLD.story_id OR OLD.source_media_artifact_id IS DISTINCT FROM v_current
      OR OLD.selected_by IS DISTINCT FROM v_owner OR auth.uid() IS DISTINCT FROM v_owner THEN
      RAISE EXCEPTION 'Only a pending current-source selection may be explicitly confirmed by its owner.' USING ERRCODE='42501', DETAIL=concat('old_state=',OLD.state,', new_state=',NEW.state,', actor=',auth.uid(),', owner=',v_owner,', source=',OLD.source_media_artifact_id,', current=',v_current,', selected_by=',OLD.selected_by);
    END IF;
    NEW.source_media_artifact_id:=OLD.source_media_artifact_id;
    NEW.selected_by:=OLD.selected_by;
    NEW.selected_at:=OLD.selected_at;
    NEW.decision_origin:=OLD.decision_origin;
    NEW.selected_language_code:=OLD.selected_language_code;
    NEW.selected_language_name:=OLD.selected_language_name;
    NEW.proposal_review_id:=OLD.proposal_review_id;
    NEW.detection_correlation_id:=OLD.detection_correlation_id;
    IF NEW.state='confirmed' THEN NEW.confirmed_by:=auth.uid(); NEW.confirmed_at:=clock_timestamp();
    ELSE NEW.confirmed_by:=NULL; NEW.confirmed_at:=NULL; END IF;
  END IF;
  RETURN NEW;
END; $function$;
CREATE TRIGGER storyteller_language_decision_guard BEFORE INSERT OR UPDATE ON public.storyteller_language_decisions
  FOR EACH ROW EXECUTE FUNCTION irin_private.guard_storyteller_language_decision();

CREATE FUNCTION irin_private.invalidate_language_decisions_on_source_replacement() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
BEGIN
 IF NEW.kind='SOURCE_MEDIA' AND NEW.sealed_at IS NOT NULL THEN
   UPDATE public.storyteller_language_decisions SET state='invalidated'
    WHERE story_id=NEW.story_id AND source_media_artifact_id<>NEW.id AND state IN ('selected','confirmed');
 END IF;
 RETURN NEW;
END; $function$;
CREATE TRIGGER source_replacement_invalidates_language_decisions AFTER UPDATE OF sealed_at ON public.artifact_versions
 FOR EACH ROW EXECUTE FUNCTION irin_private.invalidate_language_decisions_on_source_replacement();

CREATE FUNCTION irin_private.audit_language_decision_invalidation() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
BEGIN
 IF NEW.state='invalidated' AND OLD.state IS DISTINCT FROM NEW.state THEN
   PERFORM irin_private.emit_audit_event(NEW.story_id,auth.uid(),'LANGUAGE_DECISION_INVALIDATED_BY_SOURCE_REPLACEMENT'::public.audit_event_type,
     NEW.source_media_artifact_id,NULL,jsonb_build_object('decision_id',NEW.id),NULL,NULL);
 END IF;
 RETURN NEW;
END; $function$;
CREATE TRIGGER storyteller_language_decision_invalidation_audit AFTER UPDATE ON public.storyteller_language_decisions
 FOR EACH ROW EXECUTE FUNCTION irin_private.audit_language_decision_invalidation();

CREATE FUNCTION irin_private.audit_unreliable_language_detection() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_source uuid;
BEGIN
 IF NEW.category='no_reliable_language' AND NEW.story_id IS NOT NULL THEN
   v_source:=irin_private.latest_source_media_id(NEW.story_id);
   IF v_source IS NOT NULL THEN
     PERFORM irin_private.emit_audit_event(NEW.story_id,NULL,'LANGUAGE_DETECTION_UNRELIABLE'::public.audit_event_type,v_source,NULL,
       jsonb_build_object('correlation_id',NEW.correlation_id,'outcome','no_reliable_language'),NULL,NULL);
   END IF;
 END IF;
 RETURN NEW;
END; $function$;
CREATE TRIGGER language_detection_unreliable_audit AFTER INSERT ON public.verify_language_detection_diagnostics
 FOR EACH ROW EXECUTE FUNCTION irin_private.audit_unreliable_language_detection();

CREATE FUNCTION public.select_storyteller_language(p_story_id uuid,p_language_code text,p_language_name text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v_source uuid; v_id uuid; v_detection uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.stories WHERE id=p_story_id AND owner_id=auth.uid()) THEN RAISE EXCEPTION 'Owner authentication required.' USING ERRCODE='42501'; END IF;
 v_source:=irin_private.latest_source_media_id(p_story_id);
 SELECT d.correlation_id INTO v_detection FROM public.verify_language_detection_diagnostics d
 JOIN public.audit_events e ON e.story_id=d.story_id AND e.artifact_version_id=v_source
   AND e.event_type='LANGUAGE_DETECTION_UNRELIABLE' AND e.metadata->>'correlation_id'=d.correlation_id::text
 WHERE d.story_id=p_story_id AND d.category='no_reliable_language'
   AND NOT EXISTS (SELECT 1 FROM public.verify_language_detection_diagnostics newer WHERE newer.story_id=d.story_id AND newer.attempted_at>d.attempted_at)
   AND NOT EXISTS (SELECT 1 FROM public.source_language_reviews proposal WHERE proposal.story_id=d.story_id AND proposal.source_media_artifact_id=v_source AND proposal.detected_at>d.attempted_at)
 ORDER BY d.attempted_at DESC LIMIT 1;
 IF v_detection IS NULL THEN RAISE EXCEPTION 'A no_reliable_language outcome is required.' USING ERRCODE='22023'; END IF;
 IF p_language_code !~ '^[a-z]{3}(-[A-Za-z0-9]{2,8})*$' OR p_language_name IS NULL OR length(btrim(p_language_name)) NOT BETWEEN 1 AND 120 THEN RAISE EXCEPTION 'Invalid language.' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM public.storyteller_language_decisions WHERE story_id=p_story_id AND source_media_artifact_id=v_source AND state='selected') THEN
   UPDATE public.storyteller_language_decisions SET state='superseded' WHERE story_id=p_story_id AND source_media_artifact_id=v_source AND state='selected';
   PERFORM irin_private.emit_audit_event(p_story_id,auth.uid(),'STORYTELLER_LANGUAGE_SELECTION_CHANGED'::public.audit_event_type,v_source,NULL,'{}'::jsonb,NULL,NULL);
 END IF;
 INSERT INTO public.storyteller_language_decisions(story_id,source_media_artifact_id,detection_correlation_id,decision_origin,state,selected_language_code,selected_language_name,selected_by)
 VALUES(p_story_id,v_source,v_detection,'storyteller_selected','selected',lower(p_language_code),btrim(p_language_name),auth.uid()) RETURNING id INTO v_id;
 PERFORM irin_private.emit_audit_event(p_story_id,auth.uid(),'STORYTELLER_LANGUAGE_SELECTED'::public.audit_event_type,v_source,NULL,jsonb_build_object('decision_id',v_id,'origin','storyteller_selected','language_code',lower(p_language_code)),NULL,NULL);
 RETURN v_id;
END; $function$;

CREATE FUNCTION public.confirm_storyteller_language(p_story_id uuid,p_decision_id uuid)
RETURNS TABLE(decision_id uuid,state text,transcription_eligible boolean) LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $function$
DECLARE v public.storyteller_language_decisions%ROWTYPE;
BEGIN
 SELECT * INTO v FROM public.storyteller_language_decisions WHERE id=p_decision_id AND story_id=p_story_id FOR UPDATE;
 IF NOT FOUND OR v.state<>'selected' OR v.selected_by IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Current pending selection not found.' USING ERRCODE='42501'; END IF;
 UPDATE public.storyteller_language_decisions SET state='confirmed',confirmed_by=auth.uid(),confirmed_at=clock_timestamp() WHERE id=v.id;
 decision_id:=v.id; state:='confirmed';
 transcription_eligible:=lower(v.selected_language_code)='yor' AND public.is_transcription_eligible(p_story_id);
 PERFORM irin_private.emit_audit_event(p_story_id,auth.uid(),CASE WHEN lower(v.selected_language_code)='yor' THEN 'STORYTELLER_LANGUAGE_CONFIRMED'::public.audit_event_type ELSE 'UNSUPPORTED_LANGUAGE_CONFIRMED'::public.audit_event_type END,v.source_media_artifact_id,NULL,jsonb_build_object('decision_id',v.id,'origin',v.decision_origin,'language_code',v.selected_language_code,'transcription_eligible',transcription_eligible),NULL,NULL);
 RETURN NEXT;
END; $function$;
REVOKE ALL ON FUNCTION public.select_storyteller_language(uuid,text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.select_storyteller_language(uuid,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.confirm_storyteller_language(uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.confirm_storyteller_language(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.is_transcription_eligible(p_story_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 SELECT EXISTS(SELECT 1 FROM public.stories s JOIN public.storyteller_language_decisions d ON d.story_id=s.id
   AND d.source_media_artifact_id=irin_private.latest_source_media_id(s.id) AND d.state='confirmed'
   AND d.selected_language_code='yor' AND d.confirmed_by=s.owner_id
   JOIN public.source_media_verifications v ON v.story_id=s.id AND v.source_media_artifact_id=d.source_media_artifact_id AND v.status='READY'
   AND v.verification_number=(SELECT max(x.verification_number) FROM public.source_media_verifications x WHERE x.story_id=v.story_id AND x.source_media_artifact_id=v.source_media_artifact_id)
   WHERE s.id=p_story_id AND s.owner_id=auth.uid())
 OR EXISTS(SELECT 1 FROM public.stories s JOIN public.source_language_reviews r ON r.story_id=s.id
   AND r.source_media_artifact_id=irin_private.latest_source_media_id(s.id) AND r.review_status IN ('CONFIRMED','CORRECTED')
   AND r.confirmed_language_code='yor' AND r.confirmed_by=s.owner_id
   AND r.review_number=(SELECT max(x.review_number) FROM public.source_language_reviews x WHERE x.story_id=r.story_id AND x.source_media_artifact_id=r.source_media_artifact_id AND x.review_status IN ('CONFIRMED','CORRECTED'))
   JOIN public.source_media_verifications v ON v.story_id=s.id AND v.source_media_artifact_id=r.source_media_artifact_id AND v.status='READY'
   AND v.verification_number=(SELECT max(x.verification_number) FROM public.source_media_verifications x WHERE x.story_id=v.story_id AND x.source_media_artifact_id=v.source_media_artifact_id)
   WHERE s.id=p_story_id AND s.owner_id=auth.uid()); $function$;
REVOKE ALL ON FUNCTION public.is_transcription_eligible(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.is_transcription_eligible(uuid) TO authenticated;
