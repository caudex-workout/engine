CREATE TABLE accepted_recommendations (
  host_scope_key TEXT NOT NULL,
  accepted_recommendation_id TEXT NOT NULL,
  accepted_at TEXT NOT NULL,
  result_json TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, accepted_recommendation_id)
);

CREATE INDEX accepted_recommendations_by_scope
ON accepted_recommendations (host_scope_key, accepted_recommendation_id);

CREATE TABLE portable_catalog_references (
  host_scope_key TEXT NOT NULL,
  exercise_id TEXT NOT NULL,
  catalog_id TEXT,
  catalog_version TEXT,
  PRIMARY KEY (host_scope_key, exercise_id)
);
