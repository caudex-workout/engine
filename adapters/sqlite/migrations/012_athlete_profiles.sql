CREATE TABLE athlete_profiles (
  host_scope_key TEXT NOT NULL,
  athlete_profile_id TEXT NOT NULL,
  profile_json TEXT NOT NULL,
  revision INTEGER NOT NULL,
  fingerprint TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (host_scope_key, athlete_profile_id)
);
