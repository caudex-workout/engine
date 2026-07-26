CREATE TABLE tracking_workout_sets (
  host_scope_key TEXT NOT NULL,
  athlete_id TEXT NOT NULL,
  workout_id TEXT NOT NULL,
  membership_id TEXT NOT NULL,
  set_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  target_metrics_json TEXT NOT NULL,
  actual_metrics_json TEXT NOT NULL,
  status TEXT NOT NULL,
  recorded_at TEXT,
  ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
  PRIMARY KEY (host_scope_key, athlete_id, workout_id, membership_id, set_id),
  UNIQUE (host_scope_key, athlete_id, workout_id, membership_id, ordinal),
  FOREIGN KEY (host_scope_key, athlete_id, workout_id, membership_id)
    REFERENCES tracking_workout_exercises
      (host_scope_key, athlete_id, workout_id, membership_id)
    ON DELETE CASCADE
);

CREATE TABLE tracking_set_command_receipts (
  host_scope_key TEXT NOT NULL,
  athlete_id TEXT NOT NULL,
  command_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  workout_id TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, athlete_id, command_id)
);
