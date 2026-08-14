-- Battoo Intelligence
-- Migration 013: hybrid RAG search
--
-- Combines lexical search (PostgreSQL full-text search), semantic vector
-- search over knowledge chunks, and semantic vector search over AI memory.
-- All retrieval remains workspace-scoped.

-- Lexical search support for knowledge chunks.
ALTER TABLE knowledge_chunks
ADD COLUMN IF NOT EXISTS search_vector TSVECTOR
GENERATED ALWAYS AS (
    to_tsvector('simple', COALESCE(content, ''))
) STORED;

CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_search_vector
ON knowledge_chunks USING GIN(search_vector);

-- Hybrid retrieval function.
-- Scores are normalized to [0,1] and combined using configurable weights.
CREATE OR REPLACE FUNCTION hybrid_knowledge_search(
    p_workspace_id UUID,
    p_query_text TEXT,
    p_query_embedding vector(1536),
    p_match_count INTEGER DEFAULT 10,
    p_min_score DOUBLE PRECISION DEFAULT 0.0,
    p_vector_weight DOUBLE PRECISION DEFAULT 0.70,
    p_text_weight DOUBLE PRECISION DEFAULT 0.30
)
RETURNS TABLE (
    chunk_id UUID,
    workspace_id UUID,
    content TEXT,
    vector_score DOUBLE PRECISION,
    text_score DOUBLE PRECISION,
    hybrid_score DOUBLE PRECISION
)
LANGUAGE SQL
STABLE
SECURITY INVOKER
AS $$
    WITH params AS (
        SELECT
            LEAST(GREATEST(p_vector_weight, 0.0), 1.0) AS vw,
            LEAST(GREATEST(p_text_weight, 0.0), 1.0) AS tw
    ),
    vector_results AS (
        SELECT
            ke.chunk_id,
            ke.workspace_id,
            1 - (ke.embedding::vector(1536) <=> p_query_embedding)
                AS vector_score
        FROM knowledge_embeddings ke
        WHERE ke.workspace_id = p_workspace_id
          AND is_workspace_member(p_workspace_id)
          AND ke.embedding IS NOT NULL
          AND ke.embedding_dimensions = 1536
        ORDER BY ke.embedding::vector(1536) <=> p_query_embedding
        LIMIT 100
    ),
    text_results AS (
        SELECT
            kc.id AS chunk_id,
            kc.workspace_id,
            ts_rank_cd(
                kc.search_vector,
                websearch_to_tsquery('simple', p_query_text)
            )::DOUBLE PRECISION AS raw_text_score
        FROM knowledge_chunks kc
        WHERE kc.workspace_id = p_workspace_id
          AND is_workspace_member(p_workspace_id)
          AND kc.search_vector @@ websearch_to_tsquery('simple', p_query_text)
        ORDER BY raw_text_score DESC
        LIMIT 100
    ),
    text_normalized AS (
        SELECT
            tr.chunk_id,
            tr.workspace_id,
            CASE
                WHEN MAX(tr.raw_text_score) OVER () > 0
                THEN tr.raw_text_score / MAX(tr.raw_text_score) OVER ()
                ELSE 0
            END AS text_score
        FROM text_results tr
    ),
    combined AS (
        SELECT
            COALESCE(v.chunk_id, t.chunk_id) AS chunk_id,
            COALESCE(v.workspace_id, t.workspace_id) AS workspace_id,
            COALESCE(v.vector_score, 0.0) AS vector_score,
            COALESCE(t.text_score, 0.0) AS text_score,
            (
                COALESCE(v.vector_score, 0.0) * p.vw +
                COALESCE(t.text_score, 0.0) * p.tw
            ) / NULLIF(p.vw + p.tw, 0.0) AS hybrid_score
        FROM vector_results v
        FULL OUTER JOIN text_normalized t
            ON t.chunk_id = v.chunk_id
        CROSS JOIN params p
    )
    SELECT
        c.chunk_id,
        c.workspace_id,
        kc.content,
        c.vector_score,
        c.text_score,
        c.hybrid_score
    FROM combined c
    INNER JOIN knowledge_chunks kc
        ON kc.id = c.chunk_id
       AND kc.workspace_id = c.workspace_id
    WHERE c.hybrid_score >= p_min_score
    ORDER BY c.hybrid_score DESC
    LIMIT LEAST(GREATEST(p_match_count, 1), 100);
$$;

REVOKE ALL ON FUNCTION hybrid_knowledge_search(UUID, TEXT, vector(1536), INTEGER, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hybrid_knowledge_search(UUID, TEXT, vector(1536), INTEGER, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;

-- Hybrid memory retrieval: semantic memory is combined with optional lexical
-- matching against memory content. Expired memories are excluded.
CREATE OR REPLACE FUNCTION hybrid_memory_search(
    p_workspace_id UUID,
    p_query_text TEXT,
    p_query_embedding vector(1536),
    p_match_count INTEGER DEFAULT 10,
    p_min_score DOUBLE PRECISION DEFAULT 0.0,
    p_vector_weight DOUBLE PRECISION DEFAULT 0.75,
    p_text_weight DOUBLE PRECISION DEFAULT 0.25,
    p_memory_type TEXT DEFAULT NULL
)
RETURNS TABLE (
    memory_id UUID,
    workspace_id UUID,
    memory_type TEXT,
    content TEXT,
    vector_score DOUBLE PRECISION,
    text_score DOUBLE PRECISION,
    hybrid_score DOUBLE PRECISION,
    metadata JSONB
)
LANGUAGE SQL
STABLE
SECURITY INVOKER
AS $$
    WITH params AS (
        SELECT
            LEAST(GREATEST(p_vector_weight, 0.0), 1.0) AS vw,
            LEAST(GREATEST(p_text_weight, 0.0), 1.0) AS tw
    ),
    vector_results AS (
        SELECT
            me.memory_id,
            me.workspace_id,
            1 - (me.embedding <=> p_query_embedding) AS vector_score
        FROM ai_memory_embeddings me
        INNER JOIN ai_memory_entries m
            ON m.id = me.memory_id
           AND m.workspace_id = me.workspace_id
        WHERE me.workspace_id = p_workspace_id
          AND is_workspace_member(p_workspace_id)
          AND (p_memory_type IS NULL OR m.memory_type = p_memory_type)
          AND (m.expires_at IS NULL OR m.expires_at > NOW())
        ORDER BY me.embedding <=> p_query_embedding
        LIMIT 100
    ),
    text_results AS (
        SELECT
            m.id AS memory_id,
            m.workspace_id,
            ts_rank_cd(
                to_tsvector('simple', COALESCE(m.content, '')),
                websearch_to_tsquery('simple', p_query_text)
            )::DOUBLE PRECISION AS raw_text_score
        FROM ai_memory_entries m
        WHERE m.workspace_id = p_workspace_id
          AND is_workspace_member(p_workspace_id)
          AND (p_memory_type IS NULL OR m.memory_type = p_memory_type)
          AND (m.expires_at IS NULL OR m.expires_at > NOW())
          AND to_tsvector('simple', COALESCE(m.content, ''))
              @@ websearch_to_tsquery('simple', p_query_text)
        ORDER BY raw_text_score DESC
        LIMIT 100
    ),
    text_normalized AS (
        SELECT
            tr.memory_id,
            tr.workspace_id,
            CASE
                WHEN MAX(tr.raw_text_score) OVER () > 0
                THEN tr.raw_text_score / MAX(tr.raw_text_score) OVER ()
                ELSE 0
            END AS text_score
        FROM text_results tr
    ),
    combined AS (
        SELECT
            COALESCE(v.memory_id, t.memory_id) AS memory_id,
            COALESCE(v.workspace_id, t.workspace_id) AS workspace_id,
            COALESCE(v.vector_score, 0.0) AS vector_score,
            COALESCE(t.text_score, 0.0) AS text_score,
            (
                COALESCE(v.vector_score, 0.0) * p.vw +
                COALESCE(t.text_score, 0.0) * p.tw
            ) / NULLIF(p.vw + p.tw, 0.0) AS hybrid_score
        FROM vector_results v
        FULL OUTER JOIN text_normalized t
            ON t.memory_id = v.memory_id
        CROSS JOIN params p
    )
    SELECT
        c.memory_id,
        c.workspace_id,
        m.memory_type,
        m.content,
        c.vector_score,
        c.text_score,
        c.hybrid_score,
        m.metadata
    FROM combined c
    INNER JOIN ai_memory_entries m
        ON m.id = c.memory_id
       AND m.workspace_id = c.workspace_id
    WHERE c.hybrid_score >= p_min_score
      AND (m.expires_at IS NULL OR m.expires_at > NOW())
    ORDER BY c.hybrid_score DESC
    LIMIT LEAST(GREATEST(p_match_count, 1), 100);
$$;

REVOKE ALL ON FUNCTION hybrid_memory_search(UUID, TEXT, vector(1536), INTEGER, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hybrid_memory_search(UUID, TEXT, vector(1536), INTEGER, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, TEXT) TO authenticated;
