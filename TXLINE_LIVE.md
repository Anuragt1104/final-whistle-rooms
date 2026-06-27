# Going live on real TxLINE World Cup data

The app runs great standalone (on-device engine). This guide flips it to the
**real TxLINE feed** — actual World Cup fixtures, live scores and odds — by
minting a TxLINE API token and running the backend in live mode.

> Must run on a machine with **internet** + a **Solana wallet**. (The token mint
> is an on-chain transaction; it can't run in a sandbox.)

Verified against `github.com/txodds/tx-on-chain` + the TxLINE World Cup docs:
program `9ExbZjAapQww1vfcisDmrngPinHTEfpjYRWMunJgcKaA`, mint
`Zhw9TVKp68a1QrftncMSd6ELXKDtpVMNuMGr1jNwdeL`, host `txline.txodds.com`,
free service levels **1** (60-second delay) and **12** (real-time), 0 TxL.

---

## 1. Install

```bash
pnpm install      # adds @coral-xyz/anchor + @solana/spl-token (used by the mint script)
```

## 2. Mint your TxLINE token

Pick a path:

### Mainnet — real live World Cup data (recommended)
Service level 12 = real-time, **free of TxL**, but the on-chain `subscribe` tx
needs a tiny bit of SOL (~0.02 SOL) for the network fee + token-account rent.

```bash
NETWORK=mainnet SERVICE_LEVEL=12 \
  WALLET_SECRET="$(cat ~/.config/solana/id.json)" \
  pnpm txline:activate
```
`WALLET_SECRET` accepts a Solana keypair-file path, a JSON byte array, or a
base58 secret key. Use service level `1` for the free 60-second-delayed tier.

### Devnet — fully free, self-funds (test data backend)
No wallet or SOL needed — it generates a keypair and airdrops devnet SOL. Note
the devnet backend is for testing and may not carry real live mainnet matches.

```bash
NETWORK=devnet pnpm txline:activate
```

The script performs the full **guest JWT → on-chain subscribe → signed
activation** flow, verifies a live fixtures/scores/odds fetch, and writes
`.env.local`:

```
TXLINE_MODE=live
TXLINE_BASE_URL=https://txline.txodds.com
TXLINE_API_TOKEN=txoracle_api_…
TXLINE_COMPETITION_ID=…        # discovered World Cup competition id
NEXT_PUBLIC_SOLANA_CLUSTER=mainnet-beta
```

## 3. Run the backend (now live)

```bash
pnpm dev          # or: pnpm build && pnpm start  (or deploy — see DEPLOY.md)
```

Check it's live: `curl localhost:3000/api/config` → `"mode":"live"`, and
`curl localhost:3000/api/fixtures` returns **real** World Cup fixtures.

## 4. Point the app at it

- In the app: **You → Server** → your backend URL (or deployed HTTPS URL).
- Or bake it into the build:
  `flutter build apk --release --dart-define=API_BASE=https://your-backend`

Now in the app, the home shows **real** live/upcoming World Cup matches, and
tapping a **LIVE** match hosts a room that **streams the real TxLINE feed** —
goals, cards, corners and odds swings update from the actual match. (Off-line or
without live mode, it falls back to the on-device engine.)

---

## How it flows in the code
- `scripts/txline-activate.mjs` — the one-shot mint (Anchor `subscribe` +
  activation), vendored IDL in `idl/txoracle.json`.
- `lib/txline/auth.ts` — guest JWT + the API token (both headers on every call).
- `lib/txline/live.ts` — maps TxLINE fixtures/scores/odds into the app schema;
  `openLiveMatchFeed` consumes the `/api/scores|odds/stream` SSE.
- `lib/store/rooms.ts` — when `TXLINE_MODE=live`, a started room is driven by the
  live feed (real score deltas → goal pulses, win-chance, settled predictions).

## Caveats
- The free hackathon tier is open **through 2026‑07‑19**; after that a paid
  TxLINE plan is required (the architecture only needs a different token).
- Real-time (level 12) is mainnet; delayed (level 1) streams sample ~every 60s.
- The on-chain program/pricing being live for your chosen cluster is assumed
  from the docs — if `subscribe` reverts, double-check `NETWORK`/`SERVICE_LEVEL`.
