# Presenter runbook — Argentina 3–1 Switzerland

## Freeze checklist

1. Deploy the single-instance Railway backend once. Do not deploy or restart it after the two presenter identities join.
2. Install the same production APK on the physical Android phone and the second Android device. Clear app data before the final rehearsal.
3. Set display names, use stable Wi-Fi, disable battery saver, and enable Do Not Disturb except for the notification shot.
4. Open the physical phone on Home. Keep the second device ready on invite-code entry.
5. Capture separate native-resolution shots. Use an external camera only for the six-second tilt shot.

## Endpoint smoke checks

```bash
curl -fsS https://final-whistle-production.up.railway.app/api/config
curl -fsS https://final-whistle-production.up.railway.app/api/fixtures
curl -fsS https://final-whistle-production.up.railway.app/api/fixtures/18222446/match-data
```

Confirm: live mode; historical replay, card economy and anchor configured; exactly 104 fixtures; ARG 3–1 SWI; 11/11 starters; Mac Allister 9′; Embolo red 71′; Álvarez 111′; Lautaro 120′.

## Guided checkpoint cue sheet

| Beat | Presenter action | Correct answer | Expected proof |
| --- | --- | --- | --- |
| 7′ | Tap **Next beat**, open Calls, answer. | Argentina | Prompt uses only the known 7′ state. |
| 9′ | Tap **Next beat**. | — | Mac Allister goal; one Moment + one Pack. |
| 68′ | Advance after the 66′ equalizer, answer. | Switzerland | “Which team receives the next card?” |
| 71′ | Tap **Next beat**. | — | Embolo red; second Moment + Pack. |
| 108′ | Advance, answer. | Argentina | “Who scores next before 115′?” |
| 111′ | Tap **Next beat**. | — | Álvarez goal; third Moment + Pack. |
| 120′ | Tap **Next beat**. | — | Lautaro goal and authoritative 3–1 result. |

Select the Álvarez Moment first in craft mode so it is the primary lineage source. Then select the other two Moments. A timed-out retry returns the same Player Card and never consumes twice.

## Fallback shots

- Catalog unavailable: use the captured verified Fixtures shot; never switch to demo fixtures.
- Second device cannot join: use its successful invite-code shot; do not imply it is currently connected.
- Proof endpoint slow: show the room inclusion result and state that the Solana transaction is optional.
- Pack animation stalls: cut to the retry-safe opened Pack and use **View Card**.
- Sensors unavailable: use drag parallax and the external physical-device tilt rehearsal shot.

## Recording guardrails

- Keep `REPLAY` and `TxLINE historical` visible in every match shot.
- Never show simulation controls, demo inventory, unlicensed match footage, copyrighted commentary, a fabricated sponsor, or future replay data.
- Check captions for TxLINE, Solana, Merkle, Julián Álvarez, Alexis Mac Allister and fixture `18222446`.
- Master on a 1920×1080 canvas and finish by 4:55.
