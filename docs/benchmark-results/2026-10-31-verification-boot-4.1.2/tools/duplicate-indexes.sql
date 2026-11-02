-- Duplicate indexes in the public schema: same table, same definition apart from the name.
-- Keeps one per group: the named idx_* index from schema.sql if present, else the
-- alphabetically first name. Primary keys and unique indexes are never dropped.
WITH idx AS (
  SELECT c.relname AS index_name,
         t.relname AS table_name,
         regexp_replace(pg_get_indexdef(i.indexrelid), 'INDEX \S+ ON', 'INDEX ON') AS normdef,
         i.indisprimary OR i.indisunique AS protected
  FROM pg_index i
  JOIN pg_class c ON c.oid = i.indexrelid
  JOIN pg_class t ON t.oid = i.indrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
),
ranked AS (
  SELECT *, row_number() OVER (PARTITION BY normdef
                               ORDER BY protected DESC, (index_name LIKE 'idx\_%') DESC, index_name) AS rn
  FROM idx
)
SELECT table_name, count(*) FILTER (WHERE rn > 1 AND NOT protected) AS would_drop,
       count(*) FILTER (WHERE rn = 1) AS would_keep
FROM ranked GROUP BY table_name ORDER BY table_name;
