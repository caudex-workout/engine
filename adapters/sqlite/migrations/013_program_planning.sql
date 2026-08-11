CREATE TABLE program_definitions (
  host_scope_key TEXT NOT NULL,
  definition_id TEXT NOT NULL,
  definition_version TEXT NOT NULL,
  configuration_fingerprint TEXT NOT NULL,
  definition_json TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, definition_id, definition_version)
);

CREATE TABLE program_instances (
  host_scope_key TEXT NOT NULL,
  instance_id TEXT NOT NULL,
  definition_id TEXT NOT NULL,
  definition_version TEXT NOT NULL,
  configuration_fingerprint TEXT NOT NULL,
  planning_revision INTEGER,
  instance_json TEXT NOT NULL,
  planning_state_json TEXT,
  PRIMARY KEY (host_scope_key, instance_id),
  FOREIGN KEY (host_scope_key, definition_id, definition_version)
    REFERENCES program_definitions (host_scope_key, definition_id, definition_version)
);

CREATE INDEX program_instances_by_definition
ON program_instances (host_scope_key, definition_id, definition_version, instance_id);

CREATE TABLE program_occurrences (
  host_scope_key TEXT NOT NULL,
  instance_id TEXT NOT NULL,
  occurrence_id TEXT NOT NULL,
  before_revision INTEGER NOT NULL,
  after_revision INTEGER NOT NULL,
  occurrence_json TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, instance_id, occurrence_id),
  FOREIGN KEY (host_scope_key, instance_id)
    REFERENCES program_instances (host_scope_key, instance_id)
);

CREATE INDEX program_occurrences_by_instance_revision
ON program_occurrences (host_scope_key, instance_id, after_revision, occurrence_id);
