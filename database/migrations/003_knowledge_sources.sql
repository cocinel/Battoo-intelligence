CREATE TABLE IF NOT EXISTS knowledge_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    workspace_id UUID NOT NULL
        REFERENCES ai_workspaces(id)
        ON DELETE CASCADE,

    source_type TEXT NOT NULL,
    source_name TEXT NOT NULL,

    external_id TEXT,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_knowledge_sources_workspace
ON knowledge_sources(workspace_id);

CREATE INDEX IF NOT EXISTS idx_knowledge_sources_type
ON knowledge_sources(workspace_id, source_type);
