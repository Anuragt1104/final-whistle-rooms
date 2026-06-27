# Final Whistle Rooms — Submission Pack

**Track:** Consumer & Fan Experiences · **Data:** TxLINE on Solana

---

## 1. Core idea (one paragraph)

Final Whistle Rooms is a mobile-first, **verified private live watch-room** for
World Cup fan groups. A host creates a room for a match, shares a code, and the
group joins on their phones. The room reacts in real time to verified TxLINE
data through three layers — a **plain-English match pulse** (goals, cards,
corners, and odds swings translated for mainstream fans), a **room game loop**
(*Tournament Draft* + live *Next Swing* predictions, points and streaks only),
and an **AI room recap**. Every event the room reacts to is hashed into a Merkle
root that can be anchored on Solana — trust as a fan feature. Instead of asking
fans to juggle a scores app, a group chat, a predictor and a pundit feed, it
folds them into one room that watches together.

---

## 2. Demo video script (≤ 5 minutes)

> Recorded against **simulation/replay mode** so the full flow is reliable and
> reproducible — no live match required (per the judging note). Architecture is
> identical on live TxLINE data.

1. **The problem (0:00–0:35).** "Everyone watches the World Cup on their phone,
   but split across five apps and a group chat." Show the home screen — World
   Cup fixtures, "Verified by TxLINE on Solana."
2. **Create a room (0:35–1:15).** Pick a live match → name the room → both game
   modes on → "Continue with Solana" (note: an on-device identity is created
   instantly, no wallet/funds). Land in the room; show the invite code.
3. **The room fills up (1:15–1:45).** Open a second device/tab, join by code,
   draft the opposite side. Two fans, one room.
4. **Kick off — the live pulse (1:45–2:45).** Host starts the match. Narrate the
   **pulse cards** as they fire ("Goal — win chance swung 48 points", "chaos
   watch"), the **momentum meter**, and the **win-chance bar** moving with the
   market. This is the "market translator" in action.
5. **Play Next Swing (2:45–3:30).** Answer a live prompt ("What happens first — a
   goal or a card?"), show it **lock and settle automatically**, points + streak
   land, leaderboard reorders live.
6. **Half-time recap (3:30–4:00).** Show the AI recap summarizing the *room*, not
   just the match.
7. **Verify it (4:00–4:35).** Tap **Verified** → Merkle root, a live inclusion
   proof (✓ verified), and the optional on-chain anchor. Explain it maps to
   TxLINE's `stat-validation` / `odds-validation` endpoints.
8. **Full-time + the pitch (4:35–5:00).** Final recap, room winner. Close on the
   business model.

---

## 3. Application access (for judges)

- **No wallet, no credentials, no live match needed.** Open the deployed link,
  create or join a room, press **Start match**, and the full experience plays
  out on deterministic replay data.
- Local: `pnpm install && pnpm dev`.
- A functional API is also testable directly, e.g.
  `GET /api/fixtures`, `POST /api/rooms`, `POST /api/rooms/{id}/start`,
  `GET /api/rooms/{id}/stream` (SSE), `GET /api/rooms/{id}/proof`.

---

## 4. Specific TxLINE endpoints used

- `POST /auth/guest/start` — guest session JWT
- `POST /api/token/activate` — signed activation → API token (live mode)
- `GET /api/fixtures/snapshot` — tournament schedule / lobby
- `GET /api/scores/snapshot/{fixtureId}` — room hydrate (score)
- `GET /api/odds/snapshot/{fixtureId}` — room hydrate (odds)
- `GET /api/scores/stream` — live scores (SSE)
- `GET /api/odds/stream` — live odds (SSE)
- `GET /api/scores/historical/{fixtureId}` — replay mode
- `GET /api/scores/stat-validation` — score-stat Merkle proof
- `GET /api/odds/validation` — odds-update Merkle proof
- `GET /api/fixtures/validation` — fixture Merkle proof

Soccer primitives consumed: **total goals, yellow cards, red cards, corners**
(and first/second-half splits), **game phase**, and the **consensus 1X2 odds**
(de-margined implied % via the `Pct` field).

---

## 5. Business & monetization path

- **Freemium (consumer):** free = public rooms + one private room + core live
  features. Paid = multiple private rooms, creator customization, richer recaps,
  and **season-long leaderboards** across competitions.
- **Creators & communities:** branded rooms and sponsor overlays — a live
  "second screen" a creator owns.
- **B2B white-label:** sports bars, media brands, supporters' clubs, and betting
  operators (as an engagement/retention surface) license rooms.
- **Why it covers data cost after the hackathon:** the hackathon data licence is
  temporary, so sponsorships, premium rooms, and white-label deals fund the
  post-hackathon TxLINE subscription. The architecture already assumes a
  commercial licensing step (the `LiveSource` adapter is the only swap).

---

## 6. Our experience with the TxLINE API (feedback)

**What we liked most**

- **One normalized schema** across fixtures / scores / odds made it genuinely
  fast to model the whole app behind a single `TxLineSource` interface.
- The **named soccer score structure** (`scoreSoccer.ParticipantN.{Total,H1,H2}`
  with `Goals/YellowCards/RedCards/Corners`) is clean and self-describing — far
  nicer to read than a flat numeric stat table.
- **SSE streams** (`/api/scores/stream`, `/api/odds/stream`) with a
  `timestamp:index` id and `Last-Event-ID` resume are exactly the right shape
  for a real-time consumer app.
- The **three-level Merkle proof** model (batch → per-fixture → per-stat) is a
  standout differentiator — it let us build "trust as a fan feature" with very
  little extra work.
- The **free, rate-limit-free World Cup tier** with on-chain verification meant
  data cost never constrained the build.

**Where we hit friction**

- **Two-header auth is under-documented in prose.** The World Cup page reads as
  if one `Authorization: Bearer <apiToken>` header is enough, but the OpenAPI
  spec (and working code) require **both** `Authorization: Bearer <JWT>` *and*
  `X-Api-Token: <apiToken>`. We lost time before trusting the spec. A one-line
  fix in the prose would help.
- **Numeric soccer encodings aren't published.** Game-phase codes
  (`SoccerFixtureStatus` is title-only: `NS/H1/HT/H2/…`) and the numeric
  stat-key table for `stat-validation` aren't in the spec or the `tx-on-chain`
  README (which only lists US Football/Basketball). We had to rely on the named
  structure for display and treat numeric `statKey`s as derive-at-runtime. A
  published soccer stat-key + phase-code table would unblock proof tooling.
- **`fixtureId` is `int64` in paths but `int32` in the `Scores` body** — a real
  spec inconsistency we had to code around defensively.
- **Runtime host vs docs host.** The `servers` block points at
  `txline.txodds.com`, but the prose says to call `oracle.txodds.com` at
  runtime. Making the runtime host the canonical `servers` entry would remove a
  surprise.
- **Activation returns the token as raw `text/plain`** (not JSON), and all error
  bodies are `text/plain` — easy to mis-handle if you assume JSON everywhere.
- **`/api/scores/historical` only works for fixtures 6h–2wk old**, which is a
  narrow window for building a reliable replay demo around a *current*
  tournament — part of why we built a deterministic replay engine as well.

Net: a genuinely strong data layer; most friction was documentation/clarity, not
capability.
