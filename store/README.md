# La Berceuse — App Store submission kit

Everything App Store Connect asks for, ready to paste/upload.

## Metadata (`metadata/`)
- `fr.md` — French listing (fr-CA, **primary** — development language is French)
- `en.md` — English listing
- `app-privacy-answers.md` — App Privacy questionnaire ("Data Not Collected"),
  HealthKit review notes, and suggested App Review notes
- `testflight.md` — beta description (FR/EN), what-to-test, export compliance

URLs are live: `la-berceuse.netlify.app` + `/support` `/aide` `/privacy`
`/confidentialite`.

## Screenshots (`screenshots/`)
Captured on iOS 27 simulators, dark mode, status bar staged at 22:47.

| Folder | Device | Size | Sets |
|---|---|---|---|
| `iphone-6.9/{fr,en}` | iPhone 17 Pro Max | 1320×2868 | 7 shots each |
| `ipad-13/{fr,en}` | iPad Pro 13" (M5) | 2064×2752 | 7 shots each |

Order to upload (same story in both languages):
1. `01-accueil` — Home with « Dors », last night's sleep, nightstand mode
2. `02-souffle` — breathing orb mid-hold (4-7-8)
3. `03-sons` — generative music + soundscape mixer
4. `04-brouillage` — cognitive shuffle mid-word
5. `05-repos` — NSDR / yoga-nidra list
6. `06-minuterie` — sleep-timer sheet
7. `07-nidra-lecture` — nidra player mid-line

## Regenerating screenshots
Simulators: `Otto-Shot-iPhone69` and `Otto-Shot-iPad13`. Build once for
`generic/platform=iOS Simulator`, install, then launch with the demo flags:
`-demoLang fr|en`, `-demoTab home|breath|sound|shuffle|nidra`, `-demoSleep`,
`-demoTimer`, `-demoRun`, `-demoMusic`, `-demoNidra`, plus `-demoNoHealth`
(skips the HealthKit prompt) and `-demoNoSpeech` (a stalled simulator TTS
voice can freeze the UI). Set `SIMCTL_CHILD_TZ` to an evening zone so the
home greeting matches the staged 22:47 status bar. **Mute the Mac first** —
`-demoRun`/`-demoMusic` play real audio.

## Submission reminders
- Build & upload via **Xcode Cloud** (App Store submits fail on this
  beta-macOS Mac — see `feedback_beta_macos_itms90111`).
- Version 1.0, build ≥ 5 (`CURRENT_PROJECT_VERSION` in `project.yml`).
- Age 4+, Free, Health & Fitness / Lifestyle.
- Answer the encryption question "none/exempt" — the app has no networking.
