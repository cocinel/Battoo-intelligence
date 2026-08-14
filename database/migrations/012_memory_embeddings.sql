-- Battoo Intelligence
-- Migration 012: vector embeddings for AI memory
--
-- Memory remains in ai_memory_entries. This table stores the vector
-- representation separately so memory lifecycle and embedding lifecycle
-- can evolve independently.

CREATE TABLE IF NOT EXISTS ai_memory_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    workspace_id UUID NOT NULL
        REFERENCES ai_workspaces(id)
        ON DELETE CASCADE,

    memory_id UUID NOT NULL
        REFERENCES ai_memory_entries(id)
        ON DELETE CASCADE,

    embedding vector(1536) NOT NULL,

    embedding_model TEXT NOT NULL,
    embedding_dimensions INTEGER NOT NULL DEFAULT 1536
        CHECK (embedding_dimensions = 1536),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT ai_memory_embeddings_memory_model_unique
        UNIQUE (memory_id, embedding_model)
);

CREATE INDEX IF NOT EXISTS idx_ai_memory_embeddings_workspace_model
ON ai_memory_embeddings(workspace_id, embedding_model);

CREATE INDEX IF NOT EXISTS idx_ai_memory_embeddings_memory
ON ai_memory_embeddings(memory_id);

CREATE INDEX IF NOT EXISTS idx_ai_memory_embeddings_hnsw_cosine
ON ai_memory_embeddings
USING hnsw (embedding vector_cosine_ops);

ALTER TABLE ai_memory_embeddings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_memory_embeddings_workspace_isolation
ON ai_memory_embeddings;

CREATE POLICY ai_memory_embeddings_workspace_isolation
ON ai_memory_embeddings
FOR ALL
TO authenticated
USING (is_workspace_member(workspace_id))
WITH CHECK (is_workspace_member(workspace_id));

-- Controlled writer: memory embeddings can only be attached to a memory
-- belonging to the same authorized workspace.
CREATE OR REPLACE FUNCTION save_ai_memory_embedding(
    p_workspace_id UUID,
    p_memory_id UUID,
    p_embedding vector(1536),
    p_embedding_model TEXT
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

    IF NOT EXISTS (
        SELECT 1
        FROM ai_memory_entries m
        WHERE m.id = p_memory_id
          AND m.workspace_id = p_workspace_id
    ) THEN
        RAISE EXCEPTION 'memory does not belong to workspace';
    END IF;

    INSERT INTO ai_memory_embeddings (
        workspace_id,
        memory_id,
        embedding,
        embedding_model,
        embedding_dimensions
    )
    VALUES (
        p_workspace_id,
        p_memory_id,
        p_embedding,
        p_embedding_model,
        1536
    )
    ON CONFLICT (memory_id, embedding_model)
    DO UPDATE SET
        embedding = EXCLUDED.embedding,
        embedding_dimensions = EXCLUDED.embedding_dimensions,
        updated_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION save_ai_memory_embedding(UUID, UUID, vector(1536), TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION save_ai_memory_embedding(UUID, UUID, vector(1536), TEXT) TO authenticated;

-- Semantic memory retrieval. Results are restricted to the requested
-- workspace and exclude expired memories.
CREATE OR REPLACE FUNCTION match_ai_memory_embeddings(
    p_workspace_id UUID,
    p_query_embedding vector(1536),
    p_match_count INTEGER DEFAULT 10,
    p_min_similarity DOUBLE PRECISION DEFAULT 0.0,
    p_memory_type TEXT DEFAULT NULL
)
RETURNS TABLE (
    embedding_id UUID,
    memory_id UUID,
    workspace_id UUID,
    memory_type TEXT,
    memory_key TEXT,
    content TEXT,
    importance SMALLINT,
    confidence NUMERIC,
    similarity DOUBLE PRECISION,
    metadata JSONB
)
LANGUAGE SQL
STABLE
SECURITY INVOKER
AS $$
    SELECT
        me.id AS embedding_id,
        m.id AS memory_id,
        m.workspace_id,
        m.memory_type,
        m.memory_key,
        m.content,
        m.importance,
        m.confidence,
        1 - (me.embedding <=> p_query_embedding) AS similarity,
        m.metadata
    FROM ai_memory_embeddings me
    INNER JOIN ai_memory_entries m
        ON m.id = me.memory_id
       AND m.workspace_id = me.workspace_id
    WHERE me.workspace_id = p_workspace_id
      AND is_workspace_member(p_workspace_id)
      AND (p_memory_type IS NULL OR m.memory_type = p_memory_type)
      AND (m.expires_at IS NULL OR m.expires_at > NOW())
      AND 1 - (me.embedding <=> p_query_embedding) >= p_min_similarity
    ORDER BY me.embedding <=> p_query_embedding
    LIMIT LEAST(GREATEST(p_match_count, 1), 100);
$$;

REVOKE ALL ON FUNCTION match_ai_memory_embeddings(UUID, vector(1536), INTEGER, DOUBLE PRECISION, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION match_ai_memory_embeddings(UUID, vector(1536), INTEGER, DOUBLE PRECISION, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION update_ai_memory_embedding_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ai_memory_embeddings_updated_at
ON ai_memory_embeddings;

CREATE TRIGGER trg_ai_memory_embeddings_updated_at
BEFORE UPDATE ON ai_memory_embeddings
FOR EACH ROW
EXECUTE FUNCTION update_ai_memory_embedding_timestamp();
