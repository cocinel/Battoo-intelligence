-- Battoo Intelligence
-- Migration 010: audit trail
--
-- Central audit log for AI searches, knowledge access, generations,
-- errors and other security-relevant events.

CREATE TABLE IF NOT EXISTS ai_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    workspace_id UUID NOT NULL
        REFERENCES ai_workspaces(id)
        ON DELETE CASCADE,

    user_id UUID
        REFERENCES auth.users(id)
        ON DELETE SET NULL,

    action TEXT NOT NULL,

    resource_type TEXT,
    resource_id UUID,

    status TEXT NOT NULL DEFAULT 'success'
        CHECK (status IN ('success', 'failure', 'denied')),

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    error_code TEXT,
    error_message TEXT,

    request_id TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_audit_logs_workspace_created
ON ai_audit_logs(workspace_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_audit_logs_workspace_action
ON ai_audit_logs(workspace_id, action, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_audit_logs_user_created
ON ai_audit_logs(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_audit_logs_resource
ON ai_audit_logs(resource_type, resource_id);

CREATE INDEX IF NOT EXISTS idx_ai_audit_logs_request
ON ai_audit_logs(request_id);

-- Multi-tenant isolation for audit records.
ALTER TABLE ai_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_audit_logs_workspace_isolation ON ai_audit_logs;
CREATE POLICY ai_audit_logs_workspace_isolation
ON ai_audit_logs
FOR SELECT
TO authenticated
USING (is_workspace_member(workspace_id));

-- Audit events must be written through the controlled helper below.
-- Direct INSERT/UPDATE/DELETE access is not granted to authenticated users.
REVOKE ALL ON ai_audit_logs FROM PUBLIC;
REVOKE ALL ON ai_audit_logs FROM authenticated;

-- Controlled audit writer. The caller can only write an event for a workspace
-- where the authenticated user is a member. user_id is derived from auth.uid()
-- rather than trusted from client input.
CREATE OR REPLACE FUNCTION record_ai_audit_event(
    p_workspace_id UUID,
    p_action TEXT,
    p_status TEXT DEFAULT 'success',
    p_resource_type TEXT DEFAULT NULL,
    p_resource_id UUID DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb,
    p_error_code TEXT DEFAULT NULL,
    p_error_message TEXT DEFAULT NULL,
    p_request_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF NOT is_workspace_member(p_workspace_id) THEN
        RAISE EXCEPTION 'workspace access denied';
    END IF;

    INSERT INTO ai_audit_logs (
        workspace_id,
        user_id,
        action,
        resource_type,
        resource_id,
        status,
        metadata,
        error_code,
        error_message,
        request_id
    )
    VALUES (
        p_workspace_id,
        auth.uid(),
        p_action,
        p_resource_type,
        p_resource_id,
        p_status,
        COALESCE(p_metadata, '{}'::jsonb),
        p_error_code,
        p_error_message,
        p_request_id
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION record_ai_audit_event(UUID, TEXT, TEXT, TEXT, UUID, JSONB, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION record_ai_audit_event(UUID, TEXT, TEXT, TEXT, UUID, JSONB, TEXT, TEXT, TEXT) TO authenticated;
