# MVP Implementation Plan — Moment Cards + Card Game

**Parent vision:** evolve Final Whistle Rooms into Moments + playable cards + Duels (demo-complete by ~19 Jul 2026).  
**Glossary:** [CONTEXT.md](../../CONTEXT.md) · **Decisions:** [docs/adr/](../adr/)  
**Primary seam:** Card Economy (ADR-0001)

## Goal

Ship a vertical product judges can demo in one sitting:

1. Live (or simulated) Fixture  
2. Mint a Moment (Market Rarity + Odds Sandwich + Verify)  
3. Micro-Play → Called It + better Pack  
4. Open Pack / Craft → Player Card with Lineage  
5. Trump Duel (friend code) + one Moment Arena  
6. Optional Party drop multiplier  

## Architecture

```
TxLineSource (sim|live) → Match Events
         ↓
PulseInterpreter → Pulse Cards (ephemeral feed; unchanged role)
         ↓
Party runtime (ex-Room) → calls Card Economy on significant ticks
         ↓
Card Economy  ←── Micro-Play results, Craft, Duel API
   mintFromEvent / openPack / craft / resolveDuel / inventoryOf
         ↓
Merkle (Moment leaves + Lineage leaves) → optional Solana anchor
         ↓
Web + Flutter clients (inventory, album, duel UI)
```

## Phases (tracer order)

Parent PRD: [#1](https://github.com/Anuragt1104/final-whistle-rooms/issues/1)

| Phase | Issue | Slice | Demo checkpoint |
|-------|------:|-------|-----------------|
| 0 | [#2](https://github.com/Anuragt1104/final-whistle-rooms/issues/2) | Card Economy skeleton + Fan inventory store | Unit tests on empty inventory |
| 1 | [#3](https://github.com/Anuragt1104/final-whistle-rooms/issues/3) | Mint Moment from Match Event + album API/UI | Goal → Moment appears |
| 2 | [#12](https://github.com/Anuragt1104/final-whistle-rooms/issues/12) | Market Rarity + Odds Sandwich on Moment | Stars + before/after % |
| 3 | [#13](https://github.com/Anuragt1104/final-whistle-rooms/issues/13) | Moment Proof (Merkle inclusion + verify UI) | Tap Verify |
| 4 | [#14](https://github.com/Anuragt1104/final-whistle-rooms/issues/14) | Micro-Play → Called It + Pack weight | Correct call stamps Moment |
| 5 | [#4](https://github.com/Anuragt1104/final-whistle-rooms/issues/4) | Pack → Player Card + Lineage leaf | Open pack after event |
| 6 | [#5](https://github.com/Anuragt1104/final-whistle-rooms/issues/5) | Craft Player from Moments | Burn set → Player |
| 7 | [#6](https://github.com/Anuragt1104/final-whistle-rooms/issues/6) | Trump Duel vs bot | Play axes, win Pack dust |
| 8 | [#7](https://github.com/Anuragt1104/final-whistle-rooms/issues/7) | Trump Duel friend PvP | Share duel code |
| 9 | [#8](https://github.com/Anuragt1104/final-whistle-rooms/issues/8) | Moment Arena (one seed Moment) | Claim seeded Moment |
| 10 | [#9](https://github.com/Anuragt1104/final-whistle-rooms/issues/9) | Skill Cards in Duels (thin set) | Play one Skill |
| 11 | [#10](https://github.com/Anuragt1104/final-whistle-rooms/issues/10) | Party drop multiplier | 2 fans, better packs |
| 12 | [#11](https://github.com/Anuragt1104/final-whistle-rooms/issues/11) | Likeness roster assets (fixed WC set) | Real faces on Players |

## Module responsibilities

| Module | Owns | Does not own |
|--------|------|--------------|
| Card Economy | Moments, Packs, Craft, Duels, inventory, Lineage requests | TxLINE HTTP, Pulse copy, Solana tx submit |
| Party runtime | Match loop, SSE, Micro-Play prompts, calling mint | Rarity math, duel rules |
| Pulse | Plain-English feed | Minting |
| Merkle util | Tree/proof primitives | When to mint leaves |
| Clients | Album, reveal, duel UX, share image later | Authoritative inventory |

## Persistence (MVP)

In-memory inventory keyed by Fan id (same constraint as current Party store). Acceptable for single-instance demo. Document restart = wipe. Post-MVP: Redis/Postgres.

## Testing at the seam

Prefer tests against Card Economy public behavior:

- Given event + odds + Fan context → Moment fields + leaf appended  
- Micro-Play correct → Called It + pack weight delta  
- Craft recipe → Player + Lineage  
- Trump resolve → winner + rewards  
- Arena score → higher claim wins  

Do not require Next route or Flutter for core rules.

## Out of MVP

Ranked ladder, marketplace/trading, cash stakes, deep Skill meta, voice, TxLINE oracle CPI validation (local Merkle is enough), full album sets UX polish, iOS-only polish beyond parity.

## Submission notes

- Keep product title **Final Whistle Rooms**  
- Demo on simulation mode (zero config)  
- Show Verify + one Duel + one Moment mint in video  
