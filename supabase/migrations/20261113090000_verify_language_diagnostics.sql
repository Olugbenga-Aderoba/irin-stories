CREATE TABLE public.verify_language_detection_diagnostics (
  correlation_id uuid PRIMARY KEY,
  story_id uuid REFERENCES public.stories(id) ON DELETE SET NULL,
  attempted_at timestamptz NOT NULL,
  stage text NOT NULL,
  category text NOT NULL,
  retryable boolean NOT NULL,
  provider text,
  model text,
  provider_http_status integer,
  provider_error_type text,
  provider_error_code text,
  provider_request_id text,
  transport text,
  database_code text,
  CONSTRAINT verify_language_diagnostics_stage_check CHECK (stage IN (
    'ownership_check','source_lookup','source_download','hash_verification','audio_extraction',
    'speech_validation','provider_request','provider_response_validation','proposal_persistence','cleanup'
  )),
  CONSTRAINT verify_language_diagnostics_transport_check CHECK (transport IS NULL OR transport IN ('timeout','network'))
);

ALTER TABLE public.verify_language_detection_diagnostics ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.verify_language_detection_diagnostics FROM PUBLIC, anon, authenticated;
GRANT INSERT, SELECT ON public.verify_language_detection_diagnostics TO service_role;

CREATE INDEX verify_language_diagnostics_story_id_idx
  ON public.verify_language_detection_diagnostics (story_id, attempted_at DESC);
