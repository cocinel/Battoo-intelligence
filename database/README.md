# Battoo Intelligence — Database

This directory contains the database schema and migrations for Battoo Intelligence.

## Structure

- `migrations/` — versioned PostgreSQL schema migrations
- `functions/` — database functions for vector and hybrid search
- `seed/` — development-only seed data

The production database is PostgreSQL with `pgvector` enabled. GitHub stores the schema and migration history; it does not store production user data or embeddings.

## Migration order

1. `001_extensions.sql`
2. `002_workspaces.sql`
3. `003_knowledge_sources.sql`
4. `004_knowledge_documents.sql`
5. `005_knowledge_chunks.sql`
6. `006_knowledge_embeddings.sql`

Future migrations will add vector indexes, tenant security, AI conversations, insights, actions, and agents.
