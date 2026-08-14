-- Battoo Intelligence
-- Migration 002
-- Workspace isolation

CREATE TABLE IF NOT EXISTS ai_workspaces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    external_workspace_id UUID NOT NULL,
    name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_workspaces_external
ON ai_workspaces(external_workspace_id);
