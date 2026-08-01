ALTER TABLE catalog ADD COLUMN revision INTEGER NOT NULL DEFAULT 1
  CHECK (revision > 0);
ALTER TABLE catalog ADD COLUMN updated_at TEXT NOT NULL
  DEFAULT '1970-01-01T00:00:00Z';

CREATE TABLE catalog_command_receipts (
  host_scope_key TEXT NOT NULL,
  command_id TEXT NOT NULL,
  exercise_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, command_id)
);

CREATE TABLE catalog_search_terms (
  host_scope_key TEXT NOT NULL,
  exercise_id TEXT NOT NULL,
  term TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, exercise_id, term),
  FOREIGN KEY (host_scope_key, exercise_id)
    REFERENCES catalog (host_scope_key, exercise_id) ON DELETE CASCADE
);

CREATE INDEX catalog_search_by_term
ON catalog_search_terms (host_scope_key, term, exercise_id);

INSERT OR IGNORE INTO catalog_search_terms (host_scope_key, exercise_id, term)
SELECT host_scope_key, exercise_id, lower(exercise_id) FROM catalog;

INSERT OR IGNORE INTO catalog_search_terms (host_scope_key, exercise_id, term)
SELECT host_scope_key, exercise_id, lower(json_extract(payload, '$.name'))
FROM catalog WHERE json_extract(payload, '$.name') IS NOT NULL;

INSERT OR IGNORE INTO catalog_search_terms (host_scope_key, exercise_id, term)
SELECT catalog.host_scope_key, catalog.exercise_id, lower(alias.value)
FROM catalog, json_each(catalog.payload, '$.aliases') AS alias;
