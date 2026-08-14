-- Battoo Intelligence
-- Migration 008: vector similarity search functions

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
      AND ke.embedding IS NOT NULL
      AND ke.embedding_dimensions = 1536
      AND 1 - (ke.embedding::vector(1536) <=> p_query_embedding)
            >= p_min_similarity
    ORDER BY ke.embedding::vector(1536) <=> p_query_embedding
    LIMIT LEAST(GREATEST(p_match_count, 1), 100);
$$;
