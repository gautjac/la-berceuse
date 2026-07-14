# App Privacy questionnaire — recommended answers

App Store Connect → your app → **App Privacy**. This is the "nutrition label."

## Tracking
**Do you or your third-party partners use data for tracking?** → **No.**
The app has no analytics, no ads, no third-party SDKs, no IDFA, and no network
code at all.

## Data collection — recommended answer: **"Data Not Collected"**

"Collected" in Apple's sense means *transmitted off the device*. La Berceuse
transmits nothing — it has **no networking code whatsoever** — so **Data Not
Collected** is the accurate answer for the whole app. The honest reasoning per
data path:

| Data path | Where it goes | Why it's "not collected" |
|---|---|---|
| **HealthKit — sleep & heart rate (read)** | Read on-device for the night journal and to soften the generative music. Never stored outside the app's local store, never transmitted. | Nothing leaves the device. |
| **HealthKit — mindful/in-bed time (write)** | Ritual sessions are written *into* the user's own Health store, by their permission. | Writing to the user's Health store is not collection. |
| **Sound mixes, rituals, settings, journal** | SwiftData, local only. Deleted with the app. | Nothing leaves the device. |
| **Speech (shuffle & nidra voices)** | `AVSpeechSynthesizer`, on-device voices. | Nothing leaves the device. |
| **Siri « Bonne nuit »** | Handled by Apple's App Intents; the app only receives the request to open the ritual. | System service, no data collected by the app. |

## HealthKit review notes (App Review 5.1.3)
- HealthKit data is used **only** for the app's core features (night journal,
  music adaptation, logging rest time) — never for advertising or shared with
  anyone. This matches the required usage-string wording in `iOS/Info.plist`.
- The app **functions fully when Health permission is denied** — the journal
  and heart-rate adaptation simply stay quiet. Say so in the Review Notes to
  pre-empt a rejection.

## Privacy Policy URL
Required, and **live** (bilingual): `https://la-berceuse.netlify.app/privacy`
(FR: `https://la-berceuse.netlify.app/confidentialite`).
Paste it into App Privacy and each localization's metadata.

## Suggested App Review notes (paste into "Notes" in the version page)
```
La Berceuse is fully offline: no account, no server, no analytics, no network
code. HealthKit is optional — the app reads sleep and heart rate to show a
night journal and gently adapt the generative music, and writes wind-down
rituals as mindful/in-bed time. All processing is on-device; the app works
fully if Health access is denied. Audio continues in the background
(background-audio entitlement) because the app plays sleep sounds under the
locked screen; a sleep timer fades audio to silence and stops the engine.
```
