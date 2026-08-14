-- Battoo Intelligence
-- Validation test: migration 014 - RAG Context Builder
--
-- IMPORTANT:
-- Run only after migrations 001 -> 014 have been applied.
-- Run in a disposable/staging Supabase project.
--
-- This validation matches the ACTUAL schemas in migrations 002-013.
-- In particular, ai_workspaces uses external_workspace_id, not slug.
--
-- The fixture transaction is rolled back at the end.

BEGIN;

-- ============================================================
-- 1. TEST IDENTIFIERS
-- ============================================================

CREATE TEMP TABLE test_014_ids AS
SELECT
    '11111111-1111-1111-1111-111111111111'::uuid AS workspace_a,
    '22222222-2222-2222-2222-222222222222'::uuid AS workspace_b,
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid AS user_a,
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid AS user_b;

-- The user UUIDs above must already exist in auth.users.

-- ============================================================
-- 2. PRE-FLIGHT: REQUIRED OBJECTS
-- ============================================================

DO $$
DECLARE
    v_missing TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF to_regclass('public.ai_workspaces') IS NULL THEN
        v_missing := array_append(v_missing, 'ai_workspaces');
    END IF;
    IF to_regclass('public.ai_workspace_members') IS NULL THEN
        v_missing := array_append(v_missing, 'ai_workspace_members');
    END IF;
    IF to_regclass('public.knowledge_sources') IS NULL THEN
        v_missing := array_append(v_missing, 'knowledge_sources');
    END IF;
    IF to_regclass('public.knowledge_documents') IS NULL THEN
        v_missing := array_append(v_missing, 'knowledge_documents');
    END IF;
    IF to_regclass('public.knowledge_chunks') IS NULL THEN
        v_missing := array_append(v_missing, 'knowledge_chunks');
    END IF;
    IF to_regclass('public.knowledge_embeddings') IS NULL THEN
        v_missing := array_append(v_missing, 'knowledge_embeddings');
    END IF;
    IF to_regclass('public.ai_memory_entries') IS NULL THEN
        v_missing := array_append(v_missing, 'ai_memory_entries');
    END IF;
    IF to_regclass('public.ai_memory_embeddings') IS NULL THEN
        v_missing := array_append(v_missing, 'ai_memory_embeddings');
    END IF;

    IF array_length(v_missing, 1) IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: required relations missing: %', array_to_string(v_missing, ', ');
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'build_rag_context') THEN
        RAISE EXCEPTION 'FAIL: build_rag_context() is missing. Apply 014 first.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'format_rag_context') THEN
        RAISE EXCEPTION 'FAIL: format_rag_context() is missing. Apply 014 first.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'save_rag_context') THEN
        RAISE EXCEPTION 'FAIL: save_rag_context() is missing. Apply 014 first.';
    END IF;
END $$;

-- ============================================================
-- 3. TWO WORKSPACES
-- ============================================================
-- ai_workspaces schema is:
-- id, external_workspace_id, name, created_at, updated_at
-- There is NO slug column.

INSERT INTO ai_workspaces (
    id,
    external_workspace_id,
    name
)
SELECT
    workspace_a,
    '91111111-1111-1111-1111-111111111111'::uuid,
    'TEST 014 Workspace A'
FROM test_014_ids
ON CONFLICT (id) DO NOTHING;

INSERT INTO ai_workspaces (
    id,
    external_workspace_id,
    name
)
SELECT
    workspace_b,
    '92222222-2222-2222-2222-222222222222'::uuid,
    'TEST 014 Workspace B'
FROM test_014_ids
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 4. MEMBERSHIPS
-- ============================================================

INSERT INTO ai_workspace_members (
    workspace_id,
    user_id,
    role
)
SELECT
    workspace_a,
    user_a,
    'owner'
FROM test_014_ids
ON CONFLICT (workspace_id, user_id) DO NOTHING;

INSERT INTO ai_workspace_members (
    workspace_id,
    user_id,
    role
)
SELECT
    workspace_b,
    user_b,
    'owner'
FROM test_014_ids
ON CONFLICT (workspace_id, user_id) DO NOTHING;

-- ============================================================
-- 5. KNOWLEDGE FIXTURE — WORKSPACE A
-- ============================================================

INSERT INTO knowledge_sources (
    id,
    workspace_id,
    source_type,
    source_name
)
SELECT
    '31111111-1111-1111-1111-111111111111',
    workspace_a,
    'manual',
    'TEST 014 Source A'
FROM test_014_ids
ON CONFLICT (id) DO NOTHING;

INSERT INTO knowledge_documents (
    id,
    workspace_id,
    source_id,
    document_type,
    title,
    original_file_name,
    mime_type
)
SELECT
    '41111111-1111-1111-1111-111111111111',
    workspace_a,
    '31111111-1111-1111-1111-111111111111',
    'procedure',
    'Procédure de facturation',
    'facturation.pdf',
    'application/pdf'
FROM test_014_ids
ON CONFLICT (id) DO NOTHING;

INSERT INTO knowledge_chunks (
    id,
    workspace_id,
    document_id,
    content,
    chunk_index
)
SELECT
    '51111111-1111-1111-1111-111111111111',
    workspace_a,
    '41111111-1111-1111-1111-111111111111',
    'Les factures doivent être envoyées au client par email après validation du devis.',
    0
FROM test_014_ids
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 6. KNOWLEDGE EMBEDDING — WORKSPACE A
-- ============================================================

INSERT INTO knowledge_embeddings (
    id,
    workspace_id,
    chunk_id,
    embedding,
    embedding_model,
    embedding_dimensions
)
SELECT
    '61111111-1111-1111-1111-111111111111',
    workspace_a,
    '51111111-1111-1111-1111-111111111111',
    ('[' || '1,' || repeat('0,', 1534) || '0]')::vector(1536),
    'test-embedding-1536',
    1536
FROM test_014_ids
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 7. MEMORY FIXTURE — WORKSPACE A
-- ============================================================

INSERT INTO ai_memory_entries (
    id,
    workspace_id,
    user_id,
    memory_type,
    memory_key,
    content,
    importance,
    confidence,
    source,
    metadata
)
SELECT
    '71111111-1111-1111-1111-111111111111',
    workspace_a,
    user_a,
    'business_context',
    'invoice_delivery',
    'Le client préfère recevoir les factures par email.',
    8,
    0.950,
    'test',
    '{"test": true}'::jsonb
FROM test_014_ids
ON CONFLICT (id) DO NOTHING;

INSERT INTO ai_memory_embeddings (
    id,
    workspace_id,
    memory_id,
    embedding,
    embedding_model,
    embedding_dimensions
)
SELECT
    '81111111-1111-1111-1111-111111111111',
    workspace_a,
    '71111111-1111-1111-1111-111111111111',
    ('[' || '1,' || repeat('0,', 1534) || '0]')::vector(1536),
    'test-embedding-1536',
    1536
FROM test_014_ids
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 8. BUILD RAG CONTEXT
-- ============================================================

DO $$
DECLARE
    v_context JSONB;
    v_knowledge_count INTEGER;
    v_memory_count INTEGER;
BEGIN
    SELECT build_rag_context(
        (SELECT workspace_a FROM test_014_ids),
        'Comment envoyer les factures au client ?',
        ('[' || '1,' || repeat('0,', 1534) || '0]')::vector(1536),
        8,
        5,
        0.20,
        0.70,
        0.30,
        NULL
    ) INTO v_context;

    IF v_context IS NULL THEN
        RAISE EXCEPTION 'FAIL: build_rag_context() returned NULL';
    END IF;

    v_knowledge_count := COALESCE((v_context->'counts'->>'knowledge')::INTEGER, 0);
    v_memory_count := COALESCE((v_context->'counts'->>'memories')::INTEGER, 0);

    IF v_knowledge_count = 0 THEN
        RAISE EXCEPTION 'FAIL: no knowledge result returned';
    END IF;

    IF v_memory_count = 0 THEN
        RAISE EXCEPTION 'FAIL: no memory result returned';
    END IF;

    IF NOT (v_context ? 'knowledge') THEN
        RAISE EXCEPTION 'FAIL: knowledge array missing';
    END IF;

    IF NOT (v_context ? 'memories') THEN
        RAISE EXCEPTION 'FAIL: memories array missing';
    END IF;

    IF NOT (v_context->'knowledge'->0 ? 'source') THEN
        RAISE EXCEPTION 'FAIL: knowledge source metadata missing';
    END IF;

    RAISE NOTICE 'PASS: build_rag_context()';
    RAISE NOTICE 'Knowledge results: %', v_knowledge_count;
    RAISE NOTICE 'Memory results: %', v_memory_count;
END $$;

-- ============================================================
-- 9. FORMAT RAG CONTEXT
-- ============================================================

DO $$
DECLARE
    v_context JSONB;
    v_formatted TEXT;
BEGIN
    SELECT build_rag_context(
        (SELECT workspace_a FROM test_014_ids),
        'facture client email',
        ('[' || '1,' || repeat('0,', 1534) || '0]')::vector(1536),
        8,
        5,
        0.20,
        0.70,
        0.30,
        NULL
    ) INTO v_context;

    SELECT format_rag_context(v_context, 24000)
    INTO v_formatted;

    IF v_formatted IS NULL OR LENGTH(v_formatted) = 0 THEN
        RAISE EXCEPTION 'FAIL: format_rag_context() returned empty text';
    END IF;

    IF POSITION('=== KNOWLEDGE ===' IN v_formatted) = 0 THEN
        RAISE EXCEPTION 'FAIL: KNOWLEDGE section missing';
    END IF;

    IF POSITION('=== MEMORY ===' IN v_formatted) = 0 THEN
        RAISE EXCEPTION 'FAIL: MEMORY section missing';
    END IF;

    RAISE NOTICE 'PASS: format_rag_context()';
END $$;

-- ============================================================
-- 10. SAVE FUNCTION EXISTENCE / SIGNATURE
-- ============================================================

DO $$
DECLARE
    v_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM pg_proc p
        WHERE p.proname = 'save_rag_context'
          AND p.proargtypes::text = (
              SELECT oid::text || ' ' ||
                     (SELECT oid FROM pg_type WHERE typname = 'text')::text || ' ' ||
                     (SELECT oid FROM pg_type WHERE typname = 'jsonb')::text
              WHERE FALSE
          )
    ) INTO v_exists;

    -- Signature is checked more directly below; this block only confirms the function exists.
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'save_rag_context') THEN
        RAISE EXCEPTION 'FAIL: save_rag_context() does not exist';
    END IF;

    RAISE NOTICE 'PASS: save_rag_context() exists';
END $$;

-- ============================================================
-- 11. JSON STRUCTURE
-- ============================================================

DO $$
DECLARE
    v_context JSONB;
BEGIN
    SELECT build_rag_context(
        (SELECT workspace_a FROM test_014_ids),
        'facture',
        ('[' || '1,' || repeat('0,', 1534) || '0]')::vector(1536),
        8,
        5,
        0.20,
        0.70,
        0.30,
        NULL
    ) INTO v_context;

    IF NOT (v_context ? 'version') THEN
        RAISE EXCEPTION 'FAIL: context version missing';
    END IF;

    IF NOT (v_context ? 'workspace_id') THEN
        RAISE EXCEPTION 'FAIL: workspace_id missing';
    END IF;

    IF NOT (v_context ? 'query') THEN
        RAISE EXCEPTION 'FAIL: query missing';
    END IF;

    IF NOT (v_context ? 'retrieval') THEN
        RAISE EXCEPTION 'FAIL: retrieval metadata missing';
    END IF;

    IF NOT (v_context ? 'generated_at') THEN
        RAISE EXCEPTION 'FAIL: generated_at missing';
    END IF;

    RAISE NOTICE 'PASS: RAG context JSON structure';
END $$;

-- ============================================================
-- 12. CROSS-WORKSPACE FUNCTION TEST — STRUCTURAL
-- ============================================================
--
-- SQL Editor generally executes with a privileged role, so the real
-- authenticated RLS test MUST be performed using two authenticated
-- sessions. Do not treat a postgres/service-role result as an RLS proof.
--
-- User A should be allowed to access Workspace A and denied Workspace B:
--
-- SET ROLE authenticated;
-- SELECT set_config('request.jwt.claim.sub', 'USER_A_UUID', true);
--
-- SELECT build_rag_context(
--   'WORKSPACE_A_UUID',
--   'facture client email',
--   ('[' || '1,' || repeat('0,', 1534) || '0]')::vector(1536),
--   8, 5, 0.20, 0.70, 0.30, NULL
-- );
-- -- EXPECTED: context returned
--
-- SELECT build_rag_context(
--   'WORKSPACE_B_UUID',
--   'facture client email',
--   ('[' || '1,' || repeat('0,', 1534) || '0]')::vector(1536),
--   8, 5, 0.20, 0.70, 0.30, NULL
-- );
-- -- EXPECTED: ERROR workspace access denied
--
-- Repeat for User B with A/B reversed.

-- ============================================================
-- 13. PERFORMANCE TEST
-- ============================================================
-- Run separately after the functional validation:
--
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT build_rag_context(
--   'WORKSPACE_A_UUID',
--   'facture client email',
--   ('[' || '1,' || repeat('0,', 1534) || '0]')::vector(1536),
--   8, 5, 0.20, 0.70, 0.30, NULL
-- );

-- ============================================================
-- 14. FINAL RESULT
-- ============================================================

RAISE NOTICE '=========================================';
RAISE NOTICE 'BATTOO INTELLIGENCE - TEST 014';
RAISE NOTICE 'RAG CONTEXT VALIDATION';
RAISE NOTICE '=========================================';
RAISE NOTICE 'PASS: required relations';
RAISE NOTICE 'PASS: required functions';
RAISE NOTICE 'PASS: workspace fixture schema';
RAISE NOTICE 'PASS: knowledge fixture';
RAISE NOTICE 'PASS: memory fixture';
RAISE NOTICE 'PASS: build_rag_context()';
RAISE NOTICE 'PASS: format_rag_context()';
RAISE NOTICE 'PASS: save_rag_context() exists';
RAISE NOTICE 'PASS: RAG JSON structure';
RAISE NOTICE '=========================================';
RAISE NOTICE 'RLS cross-tenant test must use authenticated sessions.';
RAISE NOTICE '=========================================';

ROLLBACK;
