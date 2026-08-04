ALTER TABLE tracking_workouts ADD COLUMN origin TEXT NOT NULL DEFAULT 'manual'
  CHECK (origin IN ('manual', 'template', 'recommendation'));
ALTER TABLE tracking_workouts ADD COLUMN provenance_json TEXT;
ALTER TABLE tracking_workouts ADD COLUMN prescription_json TEXT NOT NULL DEFAULT '[]';

CREATE TABLE workout_templates (
  host_scope_key TEXT NOT NULL,
  template_id TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 0),
  payload_json TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, template_id)
);

CREATE TABLE workflow_recovery (
  host_scope_key TEXT NOT NULL,
  workflow_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'completed')),
  idempotency_key TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, workflow_id),
  UNIQUE (host_scope_key, idempotency_key)
);
