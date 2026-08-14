-- Battoo Intelligence
-- Migration 011: AI memory
--
-- Persistent memory is separated into three layers:
-- 1. conversation memory: facts/context extracted from interactions
-- 2. workspace memory: durable business context and preferences
-- 3. user memory: user-specific preferences within a workspace
--
-- All memory is workspace-scoped and protected by the existing RLS model.

CREATE TABLE IF NOT EXISTS ai_memory_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    workspace_id UUID NOT NULL
        REFERENCES ai_workspaces(id)
        ON DELETE CASCADE,

    user_id UUID
        REFERENCES auth.users(id)
        ON DELETE SET NULL,

    memory_type TEXT NOT NULL
        CHECK (memory_type IN ('conversation', 'workspace', 'user', 'business_context')),

    memory_key TEXT,
    content TEXT NOT NULL,

    importance SMALLINT NOT NULL DEFAULT 5
        CHECK (importance BETWEEN 1 AND 10),

    confidence NUMERIC(4,3) NOT NULL DEFAULT 1.000
        CHECK (confidence >= 0 AND confidence <= 1),

    source TEXT,
    source_reference UUID,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_memory_workspace_type
ON ai_memory_entries(workspace_id, memory_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_memory_workspace_key
ON ai_memory_entries(workspace_id, memory_key);

CREATE INDEX IF NOT EXISTS idx_ai_memory_user
ON ai_memory_entries(workspace_id, user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_memory_active
ON ai_memory_entries(workspace_id, expires_at);

CREATE INDEX IF NOT EXISTS idx_ai_memory_metadata
ON ai_memory_entries USING GIN(metadata);

ALTER TABLE ai_memory_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_memory_workspace_isolation ON ai_memory_entries;
CREATE POLICY ai_memory_workspace_isolation
ON ai_memory_entries
FOR ALL
TO authenticated
USING (is_workspace_member(workspace_id))
WITH CHECK (is_workspace_member(workspace_id));

-- Controlled memory writer. The authenticated user is derived from auth.uid().
CREATE OR REPLACE FUNCTION save_ai_memory(
    p_workspace_id UUID,
    p_memory_type TEXT,
    p_content TEXT,
    p_memory_key TEXT DEFAULT NULL,
    p_importance SMALLINT DEFAULT 5,
    p_confidence NUMERIC DEFAULT 1.000,
    p_source TEXT DEFAULT NULL,
    p_source_reference UUID DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb,
    p_expires_at TIMESTAMPTZ DEFAULT NULL
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

    INSERT INTO ai_memory_entries (
        workspace_id,
        user_id,
        memory_type,
        memory_key,
        content,
        importance,
        confidence,
        source,
        source_reference,
        metadata,
        expires_at
    )
    VALUES (
        p_workspace_id,
        auth.uid(),
        p_memory_type,
        p_memory_key,
        p_content,
        p_importance,
        p_confidence,
        p_source,
        p_source_reference,
        COALESCE(p_metadata, '{}'::jsonb),
        p_expires_at
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION save_ai_memory(UUID, TEXT, TEXT, TEXT, SMALLINT, NUMERIC, TEXT, UUID, JSONB, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION save_ai_memory(UUID, TEXT, TEXT, TEXT, SMALLINT, NUMERIC, TEXT, UUID, JSONB, TIMESTAMPTZ) TO authenticated;

-- Read relevant memory for a workspace, excluding expired entries.
CREATE OR REPLACE FUNCTION get_ai_memory(
    p_workspace_id UUID,
    p_memory_type TEXT DEFAULT NULL,
    p_memory_key TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    workspace_id UUID,
    user_id UUID,
    memory_type TEXT,
    memory_key TEXT,
    content TEXT,
    importance SMALLINT,
    confidence NUMERIC,
    source TEXT,
    metadata JSONB,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE SQL
STABLE
SECURITY INVOKER
AS $$
    SELECT
        m.id,
        m.workspace_id,
        m.user_id,
        m.memory_type,
        m.memory_key,
        m.content,
        m.importance,
        m.confidence,
        m.source,
        m.metadata,
        m.expires_at,
        m.created_at,
        m.updated_at
    FROM ai_memory_entries m
    WHERE m.workspace_id = p_workspace_id
      AND is_workspace_member(p_workspace_id)
      AND (p_memory_type IS NULL OR m.memory_type = p_memory_type)
      AND (p_memory_key IS NULL OR m.memory_key = p_memory_key)
      AND (m.expires_at IS NULL OR m.expires_at > NOW())
    ORDER BY m.importance DESC, m.updated_at DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 100);
$$;

REVOKE ALL ON FUNCTION get_ai_memory(UUID, TEXT, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_ai_memory(UUID, TEXT, TEXT, INTEGER) TO authenticated;

-- Keep updated_at current when a memory entry is modified.
CREATE OR REPLACE FUNCTION update_ai_memory_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ai_memory_updated_at ON ai_memory_entries;
CREATE TRIGGER trg_ai_memory_updated_at
BEFORE UPDATE ON ai_memory_entries
FOR EACH ROW
EXECUTE FUNCTION update_ai_memory_timestamp();
