CREATE TABLE IF NOT EXISTS knowledge_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    workspace_id UUID NOT NULL
        REFERENCES ai_workspaces(id)
        ON DELETE CASCADE,

    source_id UUID
        REFERENCES knowledge_sources(id)
        ON DELETE CASCADE,

    document_type TEXT,
    title TEXT,

    original_file_name TEXT,
    mime_type TEXT,

    storage_path TEXT,

    content_hash TEXT,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_knowledge_documents_workspace
ON knowledge_documents(workspace_id);

CREATE INDEX IF NOT EXISTS idx_knowledge_documents_source
ON knowledge_documents(source_id);
