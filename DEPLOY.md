# Deploy guide — backend, app, mainnet

The app already works **standalone** (local fixtures + on-device live matches),
so anyone can install the APK and start watching with zero setup. You only need
to deploy the **backend** to unlock **multiplayer rooms** (friends in the same
room over the internet) and **live TxLINE data**.

---

## 1. Deploy the backend (multiplayer)

The live-room engine keeps in-memory state and streams over SSE, so it must run
as **one persistent Node instance** — not serverless (no Vercel/Cloudflare
functions). Pick any:

### Option A — Render (easiest, free tier)
1. Push this repo to GitHub (done: `Anuragt1104/final-whistle-rooms`).
2. Go to https://render.com → **New + → Blueprint** → connect the repo.
   It reads [`render.yaml`](render.yaml) and builds the [`Dockerfile`](Dockerfile).
3. Deploy. You'll get a URL like `https://final-whistle-backend.onrender.com`.
   - Free tier sleeps on idle (~30s cold start). Upgrade to keep it warm.

### Option B — Railway / Fly.io / any Docker host
```bash
# Railway: railway up   (detects the Dockerfile)
# Fly.io:  fly launch && fly deploy
# Generic: docker build -t fwr-backend . && docker run -p 3000:3000 fwr-backend
```

### Option C — keep it on your Mac for testing
```bash
pnpm install && pnpm dev      # http://localhost:3000, reachable on your LAN IP
```

Verify any deploy: open `https://<your-url>/api/config` → returns JSON.

---

## 2. Point the app at your backend

Two ways:

- **In-app (no rebuild):** open the app → **You** tab → **Server** → paste your
  URL (e.g. `https://final-whistle-backend.onrender.com`). Persists on device.
- **Baked into the APK (for distribution):** rebuild with the URL compiled in:
  ```bash
  cd mobile
  flutter build apk --release --dart-define=API_BASE=https://final-whistle-backend.onrender.com
  # or an App Bundle for Play Store:
  flutter build appbundle --release --dart-define=API_BASE=https://final-whistle-backend.onrender.com
  ```
  Use **https** for a public backend (Android/iOS block plain http by default;
  the cleartext exception we ship is only for `localhost`/LAN dev).

---

## 3. Live TxLINE data (optional)

The deploy defaults to `TXLINE_MODE=simulation` (works with no credentials).
To serve **real** World Cup data, set on the backend:
- `TXLINE_MODE=live`
- `TXLINE_API_TOKEN=<token>` — obtained via the Solana wallet → guest JWT →
  signed activation flow (free World Cup tier; see [`docs/TXLINE_API.md`](docs/TXLINE_API.md)).

Everything above the data layer is identical; only this env flag changes.

---

## 4. Mainnet + real wallet

- **Identity today:** every user gets an on-device ed25519 Solana keypair
  ("Continue with Solana") — a real address, no funds needed. Power users can
  attach an external wallet **address** at login (display + leaderboard).
- **Mainnet display/anchor:** set on the backend
  `NEXT_PUBLIC_SOLANA_CLUSTER=mainnet-beta` and a mainnet RPC. The room proof
  Merkle root can be anchored on mainnet by setting `SOLANA_ANCHOR_SECRET_KEY`
  to a **funded** mainnet keypair (each anchor costs a small SOL fee).
- **Real wallet signing (Phantom/Solflare):** the next step is **Solana Mobile
  Wallet Adapter (MWA)** — deep-links to an installed wallet app to sign. It
  needs a wallet app on the device and can't be exercised on a bare emulator, so
  it's staged as a follow-up (the `cryptography` embedded wallet covers sign-in
  today). Package to add when ready: `solana_mobile_client` (Android) + an iOS
  deep-link flow.

> ⚠️ Anchoring on **mainnet-beta** spends real SOL. Keep the anchor key funded
> minimally and treat `SOLANA_ANCHOR_SECRET_KEY` as a secret (never in git).

---

## 5. Play Store

See [`mobile/PLAYSTORE.md`](mobile/PLAYSTORE.md) for the signed App Bundle build,
keystore setup, store-listing copy, and the submission checklist.
