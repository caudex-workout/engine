ALTER TABLE catalog ADD COLUMN archived INTEGER NOT NULL DEFAULT 0
  CHECK (archived IN (0, 1));

CREATE TABLE tracking_workout_exercises (
  host_scope_key TEXT NOT NULL,
  athlete_id TEXT NOT NULL,
  workout_id TEXT NOT NULL,
  membership_id TEXT NOT NULL,
  exercise_id TEXT NOT NULL,
  ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
  PRIMARY KEY (host_scope_key, athlete_id, workout_id, membership_id),
  UNIQUE (host_scope_key, athlete_id, workout_id, ordinal),
  FOREIGN KEY (host_scope_key, athlete_id, workout_id)
    REFERENCES tracking_workouts (host_scope_key, athlete_id, workout_id)
    ON DELETE CASCADE
);
