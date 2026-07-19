# Final Whistle

**The fan-retention engine that turns every verified match update into the next meaningful action.**

> **Live backend:** https://final-whistle-production.up.railway.app · health: [`/api/config`](https://final-whistle-production.up.railway.app/api/config)
> The Android APK ships pointing at this URL (works on any network). Serves real mainnet TxLINE World Cup data in live mode.

> Most fans watch the World Cup with a phone in their hand, scattered across a
> scores app, a group chat, a predictor, and a pundit feed. Final Whistle Rooms
> compresses all of that into **one room your group watches together** — that
> reacts, in real time, to verified TxLINE match data.

The complete loop is **Watch → Call → Earn → Open → Craft → Duel → Return**.
Every fixture has one auto-managed Official Match Hub; invite-only Private
Parties add friend chat and reactions. During a match the product runs three
tightly integrated layers:

1. **Live match pulse** — goals, cards, corners and **odds swings** translated
   into plain-English "pulse cards", a momentum meter, and a friendly win-chance
   read of the market.
2. **A room game loop** — *Team Draft* (draft a side, earn points as they
   perform) and *Live Calls* (bite-sized, skill-based predictions on the
   next goal, corner, or odds move). Points and streaks only — **no cash staking.**
3. **Playable lineage** — a correct Call earns one immediate Moment and one
   retry-safe Pack. Selected Moments craft deterministically into Player Cards
   used in best-of-three Stadium Duels.

Every event the room reacts to is hashed into a **Merkle tree**; the root is the
room's tamper-evident fingerprint of the verified TxLINE data it responded to,
and can be **anchored on Solana** — mirroring TxLINE's own proof model, surfaced
as a fan-facing trust feature.

---

## Why this, and why it's different

Existing fan products are each strong at *one* mode — information (FotMob,
SofaScore), public chat (OneFootball), or pre-match prediction (FIFA Predictor)
— but none combine **private social presence + a live game loop + verifiable
trust** in a single mobile-first surface. The white space is **structured
private rooms** (how people actually watch — WhatsApp groups, house parties,
office pools), reacting live, with verifiability as a consumer feature.

It is also deliberately **skill-based, points-only** — broader consumer appeal
and safer under the hackathon's gambling-law constraints than a sportsbook-style
UI.

---

## How TxLINE powers it

Production uses TxLINE as its sole football source. Explicit demo mode remains
for isolated development and tests, but it is never substituted when a live or
historical feed is unavailable.

### Endpoints used (mapped to product surfaces)

| Product surface | TxLINE endpoint |
| --- | --- |
| Lobby / match schedule | `GET /api/fixtures/snapshot` |
| Room hydrate (score) | `GET /api/scores/snapshot/{fixtureId}` |
| Room hydrate (odds) | `GET /api/odds/snapshot/{fixtureId}` |
| Live transport (scores) | `GET /api/scores/stream` (SSE) |
| Live transport (odds) | `GET /api/odds/stream` (SSE) |
| Replay mode | `GET /api/scores/historical/{fixtureId}` |
| Proof — score stat | `GET /api/scores/stat-validation` |
| Proof — odds update | `GET /api/odds/validation` |
| Proof — fixture | `GET /api/fixtures/validation` |
| Auth | `POST /auth/guest/start` → on-chain `subscribe` → `POST /api/token/activate` |

The **interpretation layer** (`lib/engine/pulse.ts`) is where the product becomes
original: it turns low-level score/odds deltas into room-native events (a goal +
an odds move over threshold becomes a "shock swing" card; two cards in five
minutes triggers "chaos watch"; three quick corners opens a corner challenge).

> Full schema notes (auth headers, PascalCase fields, soccer score structure,
> SSE framing) live in [`docs/TXLINE_API.md`](docs/TXLINE_API.md), verified
> against the OpenAPI spec `docs.yaml` v1.5.2.

### Verified historical replay

Judges tap **Experience a verified classic** to run Argentina–Switzerland
fixture `18222446` from TxLINE historical records. The replay stays visibly
labelled, uses the same match-intelligence and Question Engine path as live
data, streams every event frame in order, and pauses at guided recording beats.
Clock resets, provisional full time, extra time, corrections and stable source
event identities are normalized before any UI or reward observes them.

---

## Solana

- **Identity:** "Continue with Solana" creates a secure **on-device ed25519
  keypair** (a real Solana address) and signs a proof-of-identity message — no
  extension, no funds, no friction for mainstream fans (and nothing for judges
  to install). Power users can attach an external wallet address.
- **Proof anchor (optional):** the room's Merkle root is written to an SPL Memo
  transaction on devnet (`lib/solana/anchor.ts`). Proofs verify locally without
  it; set `SOLANA_ANCHOR_SECRET_KEY` to also timestamp on-chain.
- **TxLINE access:** live mode runs the documented Solana-wallet → guest JWT →
  signed activation → API-token flow server-side (`lib/txline/auth.ts`).

---

## Run it

```bash
pnpm install
pnpm dev            # http://localhost:3000
```

Open the app → **Experience a verified classic** → answer Live Calls → inspect
the immediate Called It Moment → open Packs → craft a primary Moment into a
Player Card → equip it in Arena. A second identity joins the private showcase
through its invite code.

For a faster demo loop, set the match pacing:

```bash
SIM_SECONDS_PER_MATCH_MINUTE=2 pnpm dev   # a 90' match in ~3 min
```

See [`.env.example`](.env.example) for TxLINE and optional Solana-anchor
configuration. Production fails closed rather than displaying simulated facts.

---

## Mobile app (Flutter)

A native **Android** client lives in [`mobile/`](mobile/). It's a Flutter
Flutter front-end over this same backend — REST + the room **SSE** stream — so
the live pulse, Live Calls, leaderboard, collectibles, Duels and Solana proof
all work natively on a phone. Verified running on an Android emulator against the
live backend.

```bash
cd mobile
flutter run                                     # Android emulator/device
flutter run --dart-define=API_BASE=http://10.0.2.2:3000   # point at local backend
```

iOS needs full Xcode + CocoaPods (one-time) — see
[`mobile/README.md`](mobile/README.md) for the complete Android **and** iOS
(simulator + physical iPhone) run instructions.

## Architecture

```
app/                    Next.js App Router — pages + API route handlers
  api/rooms/[id]/stream  SSE transport for live room state
components/              Mobile-first UI (TopBar, ScoreRail, PulseFeed, NextSwing…)
lib/
  txline/   types · simulation engine · live adapter · source factory · auth
  engine/   pulse.ts — interpretation layer (deltas → pulse cards, momentum)
  game/     question-engine.ts · nextswing.ts · scoring.ts
  showcase/ guided verified replay pacing + deterministic recording Calls
  store/    rooms.ts — in-memory room store + match engine + SSE broadcast
  recap/    generate.ts — local narrative generator (+ optional Claude)
  solana/   wallet.ts (embedded identity) · anchor.ts (devnet memo)
  util/     seeded RNG · Merkle tree · base58 · formatting
docs/TXLINE_API.md      condensed, build-focused TxLINE reference
```

**Stack:** Next.js 15 · React 19 · TypeScript · Tailwind CSS v4 · `@solana/web3.js`.

Room state is in-memory per process — ideal for a single-instance demo. A
production deployment would back the store with Redis/Postgres and move the
match runner to a worker; the `RoomRuntime` boundary is already isolated for it.

### Deploying

Because the live room runner holds in-memory state and pushes over SSE with a
per-process `setInterval`, deploy to a **single long-lived Node instance**
(`pnpm build && pnpm start`) — e.g. Render, Railway, Fly.io, or any VM /
container. **Avoid serverless/edge** (Vercel functions, Cloudflare Workers) for
this demo build: ephemeral invocations won't keep room state or hold the SSE
connection. Multi-instance scaling needs the Redis/Postgres + worker split noted
above. Keep the Railway deployment on one long-lived instance during a match or
recording; restarts intentionally clear the in-memory Hub and inventory state.

---

## How it maps to the judging criteria

- **Fan Accessibility & UX** — one mobile-first room, plain-English translations,
  instant zero-friction Solana sign-in, no wallet needed to test.
- **Real-Time Responsiveness** — SSE-driven pulse cards, momentum, live-moving
  win chance, and predictions that settle the moment the match changes.
- **Originality** — not a scores app or a sportsbook: a *private verified watch
  room* that turns match data into a shared game loop, with on-chain provenance.
- **Commercial path** — freemium private rooms + B2B white-label (sports bars,
  creators, supporters' clubs). See [`SUBMISSION.md`](SUBMISSION.md).
- **Completeness** — a functional end-to-end product: create → join → live match
  → predict → leaderboard → recap → verifiable proof.

See [`SUBMISSION.md`](SUBMISSION.md) for the demo-video script, business model,
and our TxLINE API feedback.

---

## Moment Cards + Stadium Duels

Product evolution toward Merkle-backed **Moments**, playable **Player/Skill** cards,
and between-match **Duels**. Domain language, decisions, and MVP plan:

| Doc | Purpose |
| --- | --- |
| [`CONTEXT.md`](CONTEXT.md) | Ubiquitous language |
| [`docs/adr/`](docs/adr/) | Architectural decisions |
| [`docs/plans/moment-cards-mvp.md`](docs/plans/moment-cards-mvp.md) | Implementation plan + GitHub tickets |
| [PRD #1](https://github.com/Anuragt1104/final-whistle-rooms/issues/1) | Spec + user stories |
