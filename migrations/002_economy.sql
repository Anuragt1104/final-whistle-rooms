-- Durable card economy, FC balances, and World Cup Pass state.
-- Active Duels already snapshot combat values; this survives inventory wipes
-- and Railway restarts for ownership + soft-currency settlement.

CREATE TABLE IF NOT EXISTS fan_inventories (
  fan_id text PRIMARY KEY,
  inventory jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS moment_leaves (
  leaf_key text PRIMARY KEY,
  leaves jsonb NOT NULL DEFAULT '[]'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fan_wallets (
  fan_id text PRIMARY KEY,
  credits integer NOT NULL DEFAULT 250,
  earned integer NOT NULL DEFAULT 250,
  spent integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fan_passes (
  fan_id text PRIMARY KEY,
  state jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS platform_revenue (
  id text PRIMARY KEY,
  event jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
