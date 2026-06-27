# 📱 Final Whistle Rooms — Flutter mobile app

A native **iOS + Android** client for Final Whistle Rooms. It's a thin, polished
mobile front-end over the same Next.js backend (`../`): it calls the REST API and
subscribes to the room's **SSE** stream, so the live match pulse, Next Swing
predictions, leaderboard, recaps, and Solana proof all work natively on a phone.

Built with Flutter 3.38 / Dart 3.9. On-device **Solana identity** is a real
ed25519 keypair generated with the `cryptography` package (no wallet, no funds).

> Verified running on an Android emulator (API 34) against the live backend —
> Home + Room screens render with real data.

---

## 0) You need the backend running

The app talks to the Next.js backend in the parent folder. Start it first:

```bash
cd ..            # the consumerapp/ Next.js project
pnpm install && pnpm dev      # serves on http://localhost:3000
```

…or point the app at your **deployed** URL (recommended for a real device).

### Which URL does the app use?

The base URL is resolved in this order (`lib/api/api_client.dart`):

1. `--dart-define=API_BASE=<url>` if you pass it at build/run time
2. the in-app **Server URL** setting (gear icon, top-right) — persisted
3. a platform default:
   - **iOS simulator / desktop:** `http://localhost:3000`
   - **Android emulator:** `http://10.0.2.2:3000` (the emulator's alias for your Mac)
   - **Real phone:** set it yourself — your Mac's LAN IP (e.g. `http://192.168.1.34:3000`) on the same Wi-Fi, or your deployed `https://…` URL.

You can change it any time from the **⚙️ gear → Server URL** dialog.

---

## 1) Run on Android  ✅ (works on this machine today)

```bash
flutter emulators                       # list AVDs
flutter emulators --launch <id>         # e.g. alenka_api34
flutter run                             # builds, installs, launches
# or target the running backend explicitly:
flutter run --dart-define=API_BASE=http://10.0.2.2:3000
```

Physical Android phone: enable USB debugging, plug in, `flutter devices`, then
`flutter run -d <device>` with `--dart-define=API_BASE=http://<your-mac-ip>:3000`.

Cleartext HTTP to the local backend is already enabled in the manifest
(`usesCleartextTraffic="true"`, `INTERNET` permission).

---

## 2) Run on iOS  🍏 (needs full Xcode — one-time setup)

This Mac currently has only the **Command Line Tools**, so iOS can't build yet.
Here's the complete setup:

### a. Install full Xcode (required)

- Install **Xcode** from the App Store (large download), then:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

### b. Install CocoaPods (required for plugins)

```bash
sudo gem install cocoapods        # or: brew install cocoapods
```

### c. Confirm the toolchain

```bash
flutter doctor                    # the [✓] Xcode line should be green now
```

### d. Run on the iOS Simulator (easiest, no Apple account needed)

```bash
open -a Simulator                 # boot a simulated iPhone
cd mobile
flutter run                       # auto-runs `pod install`, builds, launches
```

On the simulator the default `http://localhost:3000` reaches the backend on your
Mac directly — no extra config. (ATS is pre-configured to allow localhost HTTP.)

### e. Run on a physical iPhone

1. Open the iOS project in Xcode once to set signing:
   ```bash
   open ios/Runner.xcworkspace
   ```
   Select the **Runner** target → **Signing & Capabilities** → pick your **Team**
   (a free Apple ID works for development). Xcode will set a unique bundle id.
2. Plug in the iPhone, trust the computer, and on the phone enable
   **Developer Mode** (Settings → Privacy & Security).
3. Run, pointing at your Mac's LAN IP (same Wi-Fi) or your deployed URL:
   ```bash
   flutter devices
   flutter run -d <iphone> --dart-define=API_BASE=http://<your-mac-ip>:3000
   ```
   First launch: on the iPhone, trust your developer certificate under
   **Settings → General → VPN & Device Management**.

> For a physical iPhone hitting a **plain-HTTP** LAN backend, either use a
> deployed **HTTPS** URL (cleanest), or add an ATS exception for that IP. The
> bundled ATS config already covers `localhost` and local networking for dev.

---

## 3) Release builds

```bash
flutter build apk --release          # Android APK
flutter build appbundle --release    # Android App Bundle (Play Store)
flutter build ipa --release          # iOS (needs Xcode + signing)
# bake in a production backend:
flutter build apk --release --dart-define=API_BASE=https://your-backend.example.com
```

---

## Project layout

```
lib/
  main.dart                 app entry, theme, base-URL init
  theme.dart                design tokens (mirrors the web app)
  api/
    models.dart             Dart mirrors of the backend RoomView JSON
    api_client.dart         REST client + configurable base URL
    sse_client.dart         SSE consumer (live room state, auto-reconnect)
  state/
    identity.dart           on-device ed25519 Solana identity
    local_store.dart        display name, membership, picks (SharedPreferences)
    room_controller.dart    per-room state + actions over SSE
  screens/                  home, create, room
  widgets/                  score rail, pulse feed, Next Swing, leaderboard,
                            chat, recap, proof sheet, headers
  util/base58.dart          base58 for Solana keys
```

Same product, same backend, native phone UX.
