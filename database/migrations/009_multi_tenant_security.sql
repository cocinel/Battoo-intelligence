-- Battoo Intelligence
-- Migration 009: multi-tenant Row Level Security
--
-- Security model:
--   auth.uid() identifies the authenticated user.
--   ai_workspace_members links users to workspaces.
--   Knowledge data is visible only when the current user is a member
--   of the row's workspace.
--
-- This migration assumes Supabase Auth and a workspace membership table
-- named ai_workspace_members with columns: workspace_id, user_id.

-- Helper: determine whether the authenticated user belongs to a workspace.
CREATE OR REPLACE FUNCTION is_workspace_member(p_workspace_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM ai_workspace_members wm
        WHERE wm.workspace_id = p_workspace_id
          AND wm.user_id = auth.uid()
    );
$$;

REVOKE ALL ON FUNCTION is_workspace_member(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION is_workspace_member(UUID) TO authenticated;

-- Enable RLS on all tenant-scoped knowledge tables.
ALTER TABLE knowledge_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge_embeddings ENABLE ROW LEVEL SECURITY;

-- Policies are deliberately recreated so this migration is safe to re-run.
DROP POLICY IF EXISTS knowledge_sources_workspace_isolation ON knowledge_sources;
CREATE POLICY knowledge_sources_workspace_isolation
ON knowledge_sources
FOR ALL
TO authenticated
USING (is_workspace_member(workspace_id))
WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS knowledge_documents_workspace_isolation ON knowledge_documents;
CREATE POLICY knowledge_documents_workspace_isolation
ON knowledge_documents
FOR ALL
TO authenticated
USING (is_workspace_member(workspace_id))
WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS knowledge_chunks_workspace_isolation ON knowledge_chunks;
CREATE POLICY knowledge_chunks_workspace_isolation
ON knowledge_chunks
FOR ALL
TO authenticated
USING (is_workspace_member(workspace_id))
WITH CHECK (is_workspace_member(workspace_id));

DROP POLICY IF EXISTS knowledge_embeddings_workspace_isolation ON knowledge_embeddings;
CREATE POLICY knowledge_embeddings_workspace_isolation
ON knowledge_embeddings
FOR ALL
TO authenticated
USING (is_workspace_member(workspace_id))
WITH CHECK (is_workspace_member(workspace_id));

-- Secure the vector search function itself.
-- The function keeps workspace_id as an explicit parameter and verifies
-- membership before returning any vector matches.
CREATE OR REPLACE FUNCTION match_knowledge_embeddings(
    p_workspace_id UUID,
    p_query_embedding vector(1536),
    p_match_count INTEGER DEFAULT 10,
    p_min_similarity DOUBLE PRECISION DEFAULT 0.0
)
RETURNS TABLE (
    embedding_id UUID,
    workspace_id UUID,
    chunk_id UUID,
    embedding_model TEXT,
    similarity DOUBLE PRECISION
)
LANGUAGE SQL
STABLE
SECURITY INVOKER
AS $$
    SELECT
        ke.id AS embedding_id,
        ke.workspace_id,
        ke.chunk_id,
        ke.embedding_model,
        1 - (ke.embedding::vector(1536) <=> p_query_embedding)
            AS similarity
    FROM knowledge_embeddings ke
    WHERE ke.workspace_id = p_workspace_id
      AND is_workspace_member(p_workspace_id)
      AND ke.embedding IS NOT NULL
      AND ke.embedding_dimensions = 1536
      AND 1 - (ke.embedding::vector(1536) <=> p_query_embedding)
            >= p_min_similarity
    ORDER BY ke.embedding::vector(1536) <=> p_query_embedding
    LIMIT LEAST(GREATEST(p_match_count, 1), 100);
$$;

REVOKE ALL ON FUNCTION match_knowledge_embeddings(UUID, vector(1536), INTEGER, DOUBLE PRECISION) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION match_knowledge_embeddings(UUID, vector(1536), INTEGER, DOUBLE PRECISION) TO authenticated;
