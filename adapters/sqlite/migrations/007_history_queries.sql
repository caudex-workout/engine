CREATE INDEX tracking_completed_history
ON tracking_workouts (host_scope_key, athlete_id, status, completed_at, workout_id);

CREATE TABLE tracking_correction_receipts (
  host_scope_key TEXT NOT NULL,
  athlete_id TEXT NOT NULL,
  command_id TEXT NOT NULL,
  workout_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, athlete_id, command_id)
);
