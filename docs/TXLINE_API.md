# TxLINE API — what Final Whistle Rooms uses

This is a condensed, build-focused reference for the TxLINE (TxODDS) football
data layer, verified against the OpenAPI spec (`docs.yaml` v1.5.2). The app
talks to TxLINE through a single `TxLineSource` interface
(`lib/txline/source.ts`) with two implementations:

- **`SimulationSource`** (`TXLINE_MODE=simulation`) — deterministic, seeded
  replay of TxLINE-shaped feeds for offline demos and CI. No credentials.
- **`LiveSource`** (`TXLINE_MODE=live`) — the real client below.

**Honest production vs historical:** the shipped Railway backend runs
`TXLINE_MODE=live` against real World Cup fixtures/scores/odds streams. Replay
/ historical endpoints power judge demos when a live match is unavailable —
they do **not** invent production match state. Stadium Duels and Moment Arena
use the fixed World Cup roster + immutable Moment lineage snapshots; they are
not powered by fake “Bot Striker” cards.

## Runtime host

`https://oracle.txodds.com` (mainnet) · `https://oracle-dev.txodds.com` (devnet).
The docs are served from `txline.txodds.com`, but live API calls go to the
oracle host.

## Auth — two credentials on every data call

```
Authorization: Bearer <session JWT>
X-Api-Token:   <long-lived API token>
```

Flow (Solana wallet → guest JWT → signed activation → API token):

1. `POST /auth/guest/start` (no auth, no body) → `{ "token": "<jwt>" }` (30-day).
2. On-chain Solana `subscribe` instruction. Free World Cup tier = service level
   **1** (60s delay) or **12** (real-time); the subscribe tx registers on-chain
   and charges **0 TxLINE**. Capture the confirmed `txSig`.
3. Build the binding message **`` `${txSig}:${leagues.join(',')}:${jwt}` ``**,
   Ed25519-detached sign with the wallet secret key, base64-encode → `walletSignature`.
4. `POST /api/token/activate` (`Authorization: Bearer <jwt>`, body
   `{ txSig, walletSignature, leagues? }`) → **raw `text/plain` token** (not JSON).
5. On `401`, the JWT expired — re-run step 1.

## Endpoints used

| Surface | Endpoint | Notes |
|---|---|---|
| Lobby | `GET /api/fixtures/snapshot?startEpochDay&competitionId` | tournament schedule |
| Room hydrate | `GET /api/scores/snapshot/{fixtureId}?asOf` | current score per action |
| Room hydrate | `GET /api/odds/snapshot/{fixtureId}?asOf` | latest odds per market line |
| Live transport | `GET /api/scores/stream?fixtureId` (SSE) | real-time scores |
| Live transport | `GET /api/odds/stream?fixtureId` (SSE) | real-time odds |
| Replay | `GET /api/scores/historical/{fixtureId}` | full sequence (fixtures 6h–2wk old) |
| Proof | `GET /api/scores/stat-validation?fixtureId&seq&statKey&statKey2` | Merkle proof of a stat |
| Proof | `GET /api/odds/validation?messageId&ts` | Merkle proof of an odds update |
| Proof | `GET /api/fixtures/validation?fixtureId&timestamp` | Merkle proof of a fixture |

## SSE framing

`Content-Type: text/event-stream`. Data messages carry `id: <ts>:<idx>` and
`data: { ...single record }`. Heartbeats use `event: heartbeat`. Resume after a
drop with the `Last-Event-ID` header. Times are Unix **milliseconds**.

## Soccer score shape

`Scores.scoreSoccer.{Participant1,Participant2}` is a `SoccerTotalScore` with
period keys `H1, HT, H2, ET1, ET2, PE, ETTotal, Total`, each a `SoccerScore`
with the four tracked stats: `Goals, YellowCards, RedCards, Corners`. We read
totals from `.Total` and period splits from `.H1` / `.H2`. Game phase comes from
`GameState` codes (`NS, H1, HT, H2, ET1, ET2, PE, F, …`).

> The numeric stat-key / phase-code tables are **not** published; the named
> structure above is authoritative for display. Numeric `statKey`s are only
> needed for `stat-validation` and are derived from the live `Scores.stats` map.

## Odds shape

`OddsPayload` is per market line: `SuperOddsType` (e.g. `"1X2"`), `GameState`,
`MarketPeriod`, `PriceNames` (e.g. `["1","X","2"]`), `Prices` (opaque scaled
ints), and **`Pct`** — the de-margined implied percentages we display. Movement
is computed by diffing successive payloads for the same `(SuperOddsType +
MarketParameters + MarketPeriod)` line.

## App surfaces that consume TxLINE proofs / odds sandwiches

| Surface | How TxLINE shows up |
|---|---|
| Live rooms | SSE scores + odds → pulse, Next Swing, Merkle room proof |
| Moment mint | Significant events + odds sandwich + optional `sourceEventId` |
| Moment proof | Local Merkle over Moment leaves; room roots can anchor on Solana |
| Moment Arena | Explicit seed Moment; lineage scoring uses kind / fixture / team / Called It |

Internal Duel API (authenticated Solana session, not TxLINE):
`POST /api/duels`, `POST /api/duels/join`, `POST /api/duels/:id/actions`,
`GET /api/duels/:id`, `GET /api/duels/:id/stream` (personalized SSE).
