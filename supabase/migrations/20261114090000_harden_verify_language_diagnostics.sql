-- Preserve applied history; fail atomically if existing records violate the contract.
ALTER TABLE public.verify_language_detection_diagnostics
  ALTER COLUMN provider_http_status TYPE smallint,
  ADD CONSTRAINT diagnostics_story_resolution CHECK (story_id IS NOT NULL OR stage = 'ownership_check'),
  ADD CONSTRAINT diagnostics_category CHECK (category IN ('provider_not_configured', 'provider_authentication_failed', 'provider_permission_denied', 'provider_model_unavailable', 'provider_payload_too_large', 'provider_quota_or_rate_limit', 'provider_temporarily_unavailable', 'provider_timeout', 'provider_network_failure', 'no_reliable_language', 'provider_response_invalid', 'proposal_persistence_failed', 'media_processing_failed', 'unknown_detection_failure')),
  ADD CONSTRAINT diagnostics_provider CHECK (provider IS NULL OR provider = 'openai'),
  ADD CONSTRAINT diagnostics_model CHECK (model IS NULL OR model = 'gpt-transcribe'),
  ADD CONSTRAINT diagnostics_http CHECK (provider_http_status IS NULL OR provider_http_status BETWEEN 100 AND 599),
  ADD CONSTRAINT diagnostics_error_type CHECK (provider_error_type IS NULL OR (length(provider_error_type) <= 64 AND provider_error_type IN ('invalid_request_error', 'authentication_error', 'permission_error', 'rate_limit_error', 'insufficient_quota', 'server_error', 'api_error', 'timeout', 'connection_error'))),
  ADD CONSTRAINT diagnostics_error_code CHECK (provider_error_code IS NULL OR (length(provider_error_code) <= 64 AND provider_error_code IN ('invalid_api_key', 'invalid_request_error', 'permission_denied', 'model_not_found', 'request_too_large', 'payload_too_large', 'rate_limit_exceeded', 'insufficient_quota', 'billing_hard_limit_reached', 'server_error', 'service_unavailable'))),
  ADD CONSTRAINT diagnostics_request_id CHECK (provider_request_id IS NULL OR (length(provider_request_id) = 36 AND provider_request_id ~* '^req_[a-f0-9]{32}$')),
  ADD CONSTRAINT diagnostics_sqlstate CHECK (database_code IS NULL OR (length(database_code) = 5 AND database_code ~ '^[A-Z0-9]{5}$'));

-- Remove linked diagnostics on story deletion rather than creating invalid orphan records.
ALTER TABLE public.verify_language_detection_diagnostics
  DROP CONSTRAINT verify_language_detection_diagnostics_story_id_fkey,
  ADD CONSTRAINT verify_language_detection_diagnostics_story_id_fkey
    FOREIGN KEY (story_id) REFERENCES public.stories(id) ON DELETE CASCADE;
