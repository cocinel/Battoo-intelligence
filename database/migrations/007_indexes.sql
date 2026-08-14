-- Battoo Intelligence
-- Migration 007: vector search indexes
--
-- The embedding column is intentionally dimension-agnostic in migration 006.
-- This migration creates the first production vector index for the canonical
-- 1536-dimensional embedding space used by Battoo Intelligence.

-- Fast workspace filtering before vector similarity ranking.
CREATE INDEX IF NOT EXISTS idx_knowledge_embeddings_workspace_model
ON knowledge_embeddings(workspace_id, embedding_model);

-- HNSW cosine-similarity index for the canonical 1536-dimensional vectors.
-- The partial predicate prevents embeddings from another dimension/model from
-- entering this index and keeps the index compatible with pgvector.
CREATE INDEX IF NOT EXISTS idx_knowledge_embeddings_embedding_hnsw_cosine_1536
ON knowledge_embeddings
USING hnsw ((embedding::vector(1536)) vector_cosine_ops)
WHERE embedding IS NOT NULL
  AND embedding_dimensions = 1536;

-- Supporting index for model/dimension filtering during migrations and
-- re-embedding operations.
CREATE INDEX IF NOT EXISTS idx_knowledge_embeddings_model_dimensions
ON knowledge_embeddings(embedding_model, embedding_dimensions);
