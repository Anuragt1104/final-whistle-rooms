# ⚽ Final Whistle Rooms

**A verified, private live watch-room for World Cup fans — powered by TxLINE on Solana.**

> Most fans watch the World Cup with a phone in their hand, scattered across a
> scores app, a group chat, a predictor, and a pundit feed. Final Whistle Rooms
> compresses all of that into **one room your group watches together** — that
> reacts, in real time, to verified TxLINE match data.

A host spins up a room for a match, shares a 6-character code, and the group
joins on their phones. During the match the room runs three tightly-integrated
layers:

1. **Live match pulse** — goals, cards, corners and **odds swings** translated
   into plain-English "pulse cards", a momentum meter, and a friendly win-chance
   read of the market.
2. **A room game loop** — *Tournament Draft* (draft a side, earn points as they
   perform) and *Next Swing* (bite-sized, skill-based live predictions on the
   next goal, corner, or odds move). Points and streaks only — **no cash staking.**
3. **AI room recap** — at half-time and full-time, a short narrative of what
   happened in the *room*, not just the match ("Ana tops the room on 128 after
   calling the red-card swing").

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

Everything above the data layer is identical whether it runs on **simulated** or
**live** TxLINE data — the only difference is which `TxLineSource` the factory
returns (`lib/txline/source.ts`), chosen by `TXLINE_MODE`.

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

### Simulation / replay mode (default)

The brief calls replay *"not optional"*, and the judging note warns matches end
before review. So the default `SimulationSource` is a **deterministic, seeded**
match engine (`lib/txline/simulation.ts`) that emits feeds in the exact TxLINE
shape — same fixture id always plays out the same dramatic sequence. This means:

- **Judges need no wallet, no credentials, no live match** — open the link, join
  a room, watch the full experience immediately.
- The demo is reliable and reproducible.

Flip `TXLINE_MODE=live` and the same room engine consumes the real TxLINE SSE
streams (`lib/txline/live.ts`), synthesizing events by diffing score snapshots.

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

Open the app → **Create a room** → **Start match** → watch the pulse feed,
play Next Swing, climb the leaderboard, read the recap, tap **Verified** to
inspect the proof. Open the same room in a second tab (or share the code) to see
the multiplayer leaderboard update live.

For a faster demo loop, set the match pacing:

```bash
SIM_SECONDS_PER_MATCH_MINUTE=2 pnpm dev   # a 90' match in ~3 min
```

Everything runs with **zero configuration**. See [`.env.example`](.env.example)
for the optional live-TxLINE, on-chain-anchor, and Claude-recap settings.

---

## Mobile app (Flutter)

A native **iOS + Android** client lives in [`mobile/`](mobile/). It's a thin
Flutter front-end over this same backend — REST + the room **SSE** stream — so
the live pulse, Next Swing predictions, leaderboard, recaps, and Solana proof
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
  game/     nextswing.ts (live predictions) · scoring.ts (draft + streaks)
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
above. The deterministic simulation source keeps the deployed demo fully
functional with **no environment variables at all**.

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
