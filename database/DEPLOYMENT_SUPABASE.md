# Battoo Intelligence — procédure de déploiement Supabase 001 → 014

## Audit réalisé

Les migrations 001 à 014 sont présentes dans `database/migrations/` et leurs dépendances principales sont cohérentes pour un déploiement séquentiel.

`pgvector` est déjà installé dans le projet Supabase cible.

## Ordre obligatoire

1. `001_extensions.sql`
2. `002_workspaces.sql`
3. `003_knowledge_sources.sql`
4. `004_knowledge_documents.sql`
5. `005_knowledge_chunks.sql`
6. `006_knowledge_embeddings.sql`
7. `007_indexes.sql`
8. `008_search_functions.sql`
9. `009_multi_tenant_security.sql`
10. `010_audit.sql`
11. `011_ai_memory.sql`
12. `012_memory_embeddings.sql`
13. `013_hybrid_search.sql`
14. `014_rag_context.sql`

Ne pas exécuter les tests 013/014 avant les migrations correspondantes.

## Dépendances

- 001 : extension `vector`.
- 002 : `ai_workspaces`.
- 003 : `knowledge_sources` → dépend de 002.
- 004 : `knowledge_documents` → dépend de 002/003.
- 005 : `knowledge_chunks` → dépend de 002/004.
- 006 : `knowledge_embeddings` → dépend de 002/005.
- 007 : index HNSW knowledge → dépend de 006.
- 008 : `match_knowledge_embeddings` → dépend de 006.
- 009 : `ai_workspace_members`, `is_workspace_member` et RLS → dépend de 002–006.
- 010 : audit → dépend de 009.
- 011 : mémoire IA → dépend de 009.
- 012 : embeddings mémoire → dépend de 011.
- 013 : recherche hybride knowledge + memory → dépend de 005/006/009/011/012.
- 014 : RAG context → dépend de 002/003/004/005/009/011/013.

## Point important sur `ai_workspaces`

`002_workspaces.sql` définit :

```sql
external_workspace_id UUID NOT NULL
```

et ne définit pas de colonne `slug`.

Toute donnée de test doit donc utiliser par exemple :

```sql
INSERT INTO ai_workspaces (external_workspace_id, name)
VALUES ('11111111-1111-1111-1111-111111111111', 'Test Workspace');
```

## Déploiement dans Supabase

Dans **Supabase → SQL Editor → New query** :

1. Ouvrir `001_extensions.sql` depuis GitHub, copier le contenu et exécuter.
2. Répéter exactement dans l'ordre 002 → 014.
3. En cas d'erreur, arrêter le déploiement et corriger avant de poursuivre.
4. Ne pas sauter une migration.

## Vérification après 014

### Tables

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
```

### Fonctions

```sql
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'is_workspace_member',
    'match_knowledge_embeddings',
    'save_ai_memory',
    'get_ai_memory',
    'save_ai_memory_embedding',
    'match_ai_memory_embeddings',
    'hybrid_knowledge_search',
    'hybrid_memory_search',
    'build_rag_context',
    'save_rag_context',
    'format_rag_context'
  )
ORDER BY routine_name;
```

### Index

```sql
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND (
    indexname LIKE '%knowledge%'
    OR indexname LIKE '%memory%'
    OR indexname LIKE '%rag%'
  )
ORDER BY indexname;
```

## Sécurité à traiter avant production

`009_multi_tenant_security.sql` protège les tables membres, knowledge et les recherches, mais ne crée pas actuellement de politique RLS sur `ai_workspaces` lui-même.

Avant production, il faut traiter l'accès à `ai_workspaces` avec une politique ou des fonctions contrôlées. Exemple minimal pour la lecture :

```sql
ALTER TABLE ai_workspaces ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ai_workspaces_member_select ON ai_workspaces;

CREATE POLICY ai_workspaces_member_select
ON ai_workspaces
FOR SELECT
TO authenticated
USING (is_workspace_member(id));
```

La création, modification et suppression des workspaces doivent ensuite être contrôlées par des fonctions/politiques owner/admin adaptées au modèle Battoo.

## Validation finale

Après déploiement :

1. exécuter `013_hybrid_search_validation.sql` ;
2. vérifier les RLS avec deux vraies sessions `authenticated` ;
3. créer puis exécuter `014_rag_context_validation.sql` ;
4. vérifier `build_rag_context`, `save_rag_context` et `format_rag_context` ;
5. lancer `EXPLAIN (ANALYZE, BUFFERS)` sur les recherches ;
6. seulement après validation, commencer la migration 015.

## Gate de production

`014` n'est considéré comme validé que lorsque :

- les migrations 001–014 sont appliquées sans erreur ;
- les tables et fonctions attendues existent ;
- les index vectoriels/textuels existent ;
- la recherche hybride passe ses tests ;
- le RAG retourne knowledge + memory sans mélange de tenants ;
- User A ne peut pas lire Workspace B ;
- User B ne peut pas lire Workspace A ;
- l'accès à `ai_workspaces` est correctement protégé ;
- les performances sont vérifiées.
