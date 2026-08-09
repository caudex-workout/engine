CREATE TABLE tracking_exercise_command_receipts (
  host_scope_key TEXT NOT NULL,
  athlete_id TEXT NOT NULL,
  command_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  workout_id TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, athlete_id, command_id)
);
