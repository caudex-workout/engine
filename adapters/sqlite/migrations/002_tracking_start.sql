CREATE TABLE tracking_workouts (
  host_scope_key TEXT NOT NULL,
  athlete_id TEXT NOT NULL,
  workout_id TEXT NOT NULL,
  revision INTEGER NOT NULL,
  status TEXT NOT NULL,
  started_at TEXT NOT NULL,
  completed_at TEXT,
  PRIMARY KEY (host_scope_key, athlete_id, workout_id)
);

CREATE INDEX tracking_workouts_by_scope_status
ON tracking_workouts (host_scope_key, athlete_id, status, workout_id);

CREATE TABLE tracking_command_receipts (
  host_scope_key TEXT NOT NULL,
  athlete_id TEXT NOT NULL,
  command_id TEXT NOT NULL,
  command_kind TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  workout_id TEXT NOT NULL,
  started_at TEXT NOT NULL,
  result_revision INTEGER NOT NULL,
  result_status TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, athlete_id, command_id)
);
