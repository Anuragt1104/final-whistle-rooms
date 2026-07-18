CREATE TABLE IF NOT EXISTS duel_states (
  id text PRIMARY KEY,
  invite_code text UNIQUE NOT NULL,
  version integer NOT NULL,
  state jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS duel_events (
  duel_id text NOT NULL REFERENCES duel_states(id) ON DELETE CASCADE,
  version integer NOT NULL,
  event jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (duel_id, version)
);

CREATE TABLE IF NOT EXISTS duel_actions (
  duel_id text NOT NULL REFERENCES duel_states(id) ON DELETE CASCADE,
  actor_id text NOT NULL,
  action_id text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (duel_id, actor_id, action_id)
);

CREATE TABLE IF NOT EXISTS duel_reward_grants (
  duel_id text NOT NULL REFERENCES duel_states(id) ON DELETE CASCADE,
  fan_id text NOT NULL,
  result text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (duel_id, fan_id)
);

CREATE TABLE IF NOT EXISTS fan_devices (
  token text PRIMARY KEY,
  fan_id text NOT NULL,
  platform text NOT NULL,
  fixture_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
  registered_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS fan_devices_fan_id_idx ON fan_devices(fan_id);
