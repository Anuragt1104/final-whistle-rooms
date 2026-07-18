# ADR-0010 — Authoritative Stadium Duel + Moment Arena

## Status

Accepted (World Cup hackathon cutover).

## Decision

- Authenticate Duel / device routes with Ed25519 nonce + short-lived bearer session derived from the on-device Solana identity. Never trust client `fanId`.
- One `DuelEngine` facade with `StadiumRules` / `ArenaRules` / House commitments / actor projections.
- Persist Duel rows (+ economy/FC/Pass/devices) in Postgres with row locks, `version` for SSE ids, and exactly-once reward grants. Keep a single Railway replica because live rooms remain in-memory.
- House plays a fixed roster band with SHA-256 ordered-hand commitment; Friend turns use 60s + 15s grace and deterministic timeout auto-play.
- Flutter holds resolution privately in a presentation controller until cinematic reveal; `resolving` is UI-only.

## Consequences

Legacy unauthenticated create/play paths remain as safe adapters into the old in-memory helper for older clients; new Flutter builds use the command service exclusively.
