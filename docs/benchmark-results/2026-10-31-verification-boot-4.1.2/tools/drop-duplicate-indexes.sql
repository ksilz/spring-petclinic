-- Drops duplicate indexes in the public schema: same table, same definition apart from the name.
-- Same ranking as duplicate-indexes.sql: keeps one per group (the named idx_* index from schema.sql
-- if present, else the alphabetically first name). Primary keys and unique indexes are never dropped.
-- Each DROP INDEX runs in its own transaction (psql autocommit), so thousands of drops do not need
-- thousands of locks in one transaction. Run with: psql -v ON_ERROR_STOP=1 -f drop-duplicate-indexes.sql
WITH idx AS (
  SELECT c.relname AS index_name,
         regexp_replace(pg_get_indexdef(i.indexrelid), 'INDEX \S+ ON', 'INDEX ON') AS normdef,
         i.indisprimary OR i.indisunique AS protected
  FROM pg_index i
  JOIN pg_class c ON c.oid = i.indexrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
),
ranked AS (
  SELECT *, row_number() OVER (PARTITION BY normdef
                               ORDER BY protected DESC, (index_name LIKE 'idx\_%') DESC, index_name) AS rn
  FROM idx
)
SELECT format('DROP INDEX public.%I', index_name)
FROM ranked
WHERE rn > 1 AND NOT protected
ORDER BY index_name
\gexec
