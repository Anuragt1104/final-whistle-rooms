# Publishing to Google Play

The app is structured so this is a checklist, not a rebuild. Package name:
**`com.alenkamedia.final_whistle`**.

> You need a **Google Play Developer account** (one-time **$25**). Everything
> below uses your account + a keystore you generate (a secret — never commit it;
> it's already gitignored).

---

## 1. Create your upload keystore (once)
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
Then create `mobile/android/key.properties` (gitignored) from the example:
```
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/Users/you/upload-keystore.jks
```
The Gradle config already picks this up automatically (`build.gradle.kts`):
with `key.properties` present, release builds are signed with your upload key;
without it, they fall back to the debug key (so dev builds keep working).

> Back up `upload-keystore.jks` + passwords somewhere safe. Lose it and you
> can't update the app (unless you enrolled in Play App Signing key reset).

---

## 2. Build the App Bundle (.aab — Play's required format)
Point it at your deployed backend (see ../DEPLOY.md):
```bash
cd mobile
flutter build appbundle --release \
  --dart-define=API_BASE=https://your-backend.onrender.com
# output: build/app/outputs/bundle/release/app-release.aab
```
Bump the version per release in `mobile/pubspec.yaml` (`version: 1.0.0+1` →
`1.0.1+2`; the `+N` is the Play versionCode and must increase).

---

## 3. Play Console submission checklist
1. https://play.google.com/console → **Create app** (name: *Final Whistle Rooms*).
2. **Internal testing** track first → upload the `.aab` → add testers → share the
   opt-in link. (Fastest way to get it on phones; review is minutes–hours.)
3. Fill the required listing (copy below), **Content rating** questionnaire,
   **Data safety** form, **Privacy policy** URL, target audience, ads = No.
4. Promote Internal → **Closed/Open testing** → **Production** when ready
   (production review can take a few days).

### Store listing copy (ready to paste)
- **App name:** Final Whistle Rooms
- **Short description (≤80):**
  `Watch the World Cup together — live rooms, predictions & verified match data.`
- **Full description:**
  ```
  Final Whistle Rooms turns every match into a place your group watches
  together. Open a private live room, react to every goal as it happens, and
  play Next Swing — quick, skill-based calls on the next goal, corner or odds
  swing. Build streaks, climb the terrace leaderboard, and get an instant
  full-time recap.

  • Live match pulse — goals, cards, corners and odds swings in plain English
  • Next Swing — bite-sized live predictions (points & streaks only, no staking)
  • Tournament Draft — back a side and earn as they perform
  • Verified on Solana — the data the room reacts to is provably real
  • Watch any match live, instantly — no account, no wait

  Skill-based and points-only. No real-money betting.
  ```
- **Category:** Sports · **Tags:** football, world cup, live scores, predictions

### Content rating / Data safety notes
- **No real-money gambling** — it's points/streaks only; state this clearly
  (Play scrutinizes anything betting-adjacent). The win-chance bar is an
  informational "live odds, in plain English" read, not a wagering market.
- **Data safety:** the app stores a display name + an on-device key locally;
  if a backend is configured it sends room messages/predictions to that server.
  No third-party ads/trackers are bundled.

### Assets you'll need to upload
- App icon 512×512 (replace the default Flutter launcher icons under
  `mobile/android/app/src/main/res/mipmap-*` — or use `flutter_launcher_icons`).
- Feature graphic 1024×500.
- ≥2 phone screenshots (use the in-app screens — Browse, Live room, Final
  Whistle).
- A privacy policy URL (host a simple page; a generator like
  app-privacy-policy-generator works).

---

## iOS / App Store (when you have a Mac with full Xcode)
- Apple Developer Program: **$99/year**. Build: `flutter build ipa --release
  --dart-define=API_BASE=https://your-backend...`, then upload via Xcode/
  Transporter to App Store Connect → TestFlight → review. Same listing copy.
