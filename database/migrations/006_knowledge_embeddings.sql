CREATE TABLE IF NOT EXISTS knowledge_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    workspace_id UUID NOT NULL
        REFERENCES ai_workspaces(id)
        ON DELETE CASCADE,

    chunk_id UUID NOT NULL
        REFERENCES knowledge_chunks(id)
        ON DELETE CASCADE,

    embedding vector,

    embedding_model TEXT NOT NULL,

    embedding_dimensions INTEGER NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(chunk_id, embedding_model)
);

CREATE INDEX IF NOT EXISTS idx_knowledge_embeddings_workspace
ON knowledge_embeddings(workspace_id);
