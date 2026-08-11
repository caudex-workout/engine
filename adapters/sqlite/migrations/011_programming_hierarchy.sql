CREATE TABLE accepted_program_recommendations (
  host_scope_key TEXT NOT NULL,
  accepted_recommendation_id TEXT NOT NULL,
  accepted_at TEXT NOT NULL,
  result_json TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, accepted_recommendation_id)
);

CREATE INDEX accepted_program_recommendations_by_scope
ON accepted_program_recommendations (host_scope_key, accepted_recommendation_id);

CREATE TABLE progression_state (
  host_scope_key TEXT NOT NULL,
  state_id TEXT NOT NULL,
  progression_id TEXT NOT NULL,
  progression_version TEXT NOT NULL,
  state_json TEXT NOT NULL,
  revision TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, state_id)
);

CREATE TABLE program_state (
  host_scope_key TEXT NOT NULL,
  program_id TEXT NOT NULL,
  strategy_id TEXT NOT NULL,
  strategy_version TEXT NOT NULL,
  state_json TEXT NOT NULL,
  revision TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, program_id)
);
