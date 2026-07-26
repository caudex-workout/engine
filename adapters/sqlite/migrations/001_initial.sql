CREATE TABLE catalog (
  host_scope_key TEXT NOT NULL,
  exercise_id TEXT NOT NULL,
  payload TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, exercise_id)
);

CREATE TABLE history (
  host_scope_key TEXT NOT NULL,
  completed_at TEXT NOT NULL,
  workout_id TEXT NOT NULL,
  payload TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, completed_at, workout_id)
);

CREATE INDEX history_by_scope_completed
ON history (host_scope_key, completed_at, workout_id);

CREATE TABLE methodology_state (
  host_scope_key TEXT NOT NULL,
  methodology_id TEXT NOT NULL,
  methodology_version TEXT NOT NULL,
  state_schema_version INTEGER NOT NULL,
  state_json TEXT NOT NULL,
  revision INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, methodology_id)
);
