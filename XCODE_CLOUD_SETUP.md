# Xcode Cloud → TestFlight — one-time setup for La Berceuse

**Why Xcode Cloud:** this Mac runs a beta macOS, and Apple's validator rejects
uploads made from a beta OS with **ITMS-90111** — even with the GA SDK (the same
issue Carousel and Astheure hit). Xcode Cloud archives on Apple's **GA-macOS
runners**, which sidesteps it entirely. One push to `main` → a TestFlight build.

## Already done for you
- ✅ **Build 5** (rituels, Dors, chevet, réveils nocturnes, carnet, Siri, Live
  Activity, stereo engine) committed and pushed to
  `github.com/gautjac/la-berceuse` (`main`).
- ✅ The `.xcodeproj` and its **shared `LaBerceuse` scheme** are committed, so
  the runner needs no `xcodegen`. No external packages → **no `ci_scripts`.**
- ✅ `ITSAppUsesNonExemptEncryption = NO` in the app **and** widget plists —
  TestFlight builds go straight to testers with no export-compliance question.
- ✅ HealthKit usage strings (FR/EN) + entitlement, opaque 1024 icon,
  `NSSupportsLiveActivities`, background-audio mode — all validation-clean.
- ✅ A local Release **archive succeeds** (see README), so the cloud archive will.

## What you do in Xcode (≈5 min, needs your Apple ID)

1. Open **`LaBerceuse.xcodeproj`** in Xcode.
2. Menu **Integrate → Create Workflow…** → pick the **LaBerceuse** app.
3. **Grant access** when prompted: your Apple ID (Account Holder / Admin), and
   authorize Xcode Cloud for the GitHub repo `gautjac/la-berceuse`.
4. Configure the workflow:
   - **Name:** `TestFlight Release`
   - **Start Conditions:** Branch Changes → `main` (or **Manual** if you prefer
     to trigger builds yourself).
   - **Environment → Xcode:** the **Latest Release** Xcode. ⚠️ **Not** a beta —
     beta-built binaries are rejected too.
   - **Actions:** keep **Archive** (iOS), **Deployment Preparation** →
     **TestFlight & App Store**. Enable **"Automatically manage build number"**
     so every cloud build gets a fresh number (local is at 5; Xcode Cloud takes
     over from there).
   - **Post-Actions:** add **TestFlight Internal Testing** so you (and any
     internal testers) get each build on the phone automatically.
5. If App Store Connect doesn't have the app yet, Xcode Cloud **creates the app
   record and registers both bundle ids** (`app.atelier.laberceuse` + the
   `.widgets` extension) as part of the first archive — nothing to pre-create.
6. **Save.** The first build starts (~10–15 min) and lands in TestFlight.

## After the first cloud build
- App Store Connect → **La Berceuse** → **TestFlight** tab: the build appears
  under **iOS builds**; internal testers can install immediately.
- For external testers later: create a group, add the build, fill the short
  **beta review** notes (uses HealthKit — read sleep/heart rate, write mindful
  time; fully offline; no account needed) and submit for beta review.

## Notes
- Widget extension (Live Activity) ships inside the app — no separate record.
- Xcode Cloud free tier: 25 compute-hours/month — ample.
- Once this Mac is back on a released macOS, `_outillage/ship-ios.sh
  ~/Claude/apps/la-berceuse` is the faster local path (the ASC API key
  `H8L98GV62V` is already configured in `_outillage/config.env`).
