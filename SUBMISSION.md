# Final Whistle — Submission Pack

**Track:** Consumer & Fan Experiences · **Data:** TxLINE on Solana

---

## 1. Core idea (one paragraph)

Final Whistle is **the fan-retention engine that turns every verified match
update into the next meaningful action**. TxLINE drives one causal loop:
**Watch → Call → Earn → Open → Craft → Duel → Return**. Fans enter an
auto-managed Official Match Hub in one tap, answer short points-only football
Calls, receive an event-linked Moment and Pack immediately when correct, craft
verified lineage into a Player Card, and use it in a server-authoritative
best-of-three Duel. Embedded Solana identity removes wallet friction; Merkle
lineage and optional Solana anchoring make event-to-reward causality
inspectable. Private Parties retain invite-code social play, while branded
Match Hubs are the primary commercial product for creators, clubs, media and
sports bars.

---

## 2. Demo video script (4:55 maximum)

The master timecoded script is [`docs/DEMO_SCRIPT.md`](docs/DEMO_SCRIPT.md).
It records fixture `18222446` as a visibly labelled **TxLINE historical
replay** on a physical Android phone plus a second Android identity. Guided
checkpoints are 7′, 9′, 68′, 71′, 108′, 111′ and full time; intermediate TxLINE
frames stream in order rather than being skipped. The device checklist,
correct-answer cue sheet and fallback shots are in
[`docs/PRESENTER_RUNBOOK.md`](docs/PRESENTER_RUNBOOK.md).

---

## 3. Application access (for judges)

- **No wallet extension, credentials, or live match needed.** Install the APK,
  tap **Experience a verified classic**, and follow the guided TxLINE replay.
- Local: `pnpm install && pnpm dev`.
- A functional API is also testable directly, e.g.
  `GET /api/fixtures`, `POST /api/fixtures/18222446/showcase`,
  `POST /api/rooms/{id}/replay`,
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
