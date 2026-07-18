-- Question Engine V2: immutable question specs, answers, rewards, replay tapes.

CREATE TABLE IF NOT EXISTS question_instances (
  id text PRIMARY KEY,
  fixture_id text NOT NULL,
  rule_id text NOT NULL,
  rule_version integer NOT NULL,
  lane text NOT NULL,
  status text NOT NULL,
  spec jsonb NOT NULL,
  winner_key text,
  engine_version text NOT NULL,
  opened_at timestamptz,
  settled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS question_instances_fixture_idx
  ON question_instances(fixture_id, created_at DESC);

CREATE TABLE IF NOT EXISTS question_answers (
  question_id text NOT NULL REFERENCES question_instances(id) ON DELETE CASCADE,
  fan_id text NOT NULL,
  option_key text NOT NULL,
  action_id text,
  room_id text,
  answered_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (question_id, fan_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS question_answers_action_idx
  ON question_answers(question_id, fan_id, action_id)
  WHERE action_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS question_reward_grants (
  question_id text NOT NULL REFERENCES question_instances(id) ON DELETE CASCADE,
  fan_id text NOT NULL,
  result text NOT NULL,
  moment_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (question_id, fan_id)
);

CREATE TABLE IF NOT EXISTS fixture_event_tapes (
  fixture_id text PRIMARY KEY,
  kickoff timestamptz,
  tape bytea NOT NULL,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  archived_at timestamptz NOT NULL DEFAULT now()
);
