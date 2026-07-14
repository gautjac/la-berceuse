# TestFlight — beta testing setup

App Store Connect → your app → **TestFlight** tab.

- **Internal testers** (up to 100, need an ASC role) — builds reach them in
  minutes, no Beta App Review.
- **External testers** (up to 10,000, by email or public link) — the first
  build of each version needs a quick Beta App Review. The fields below are
  what that review asks for.

---

## Test Information (External testing → "Test Details")

### Beta App Description  *(shown to testers)*

**Français**
```
La Berceuse est un instrument de sommeil — une berceuse pour l'esprit qui tourne. Souffle guidé, brouillage cognitif, sons vivants et musique générative composés sur l'appareil, repos profond (NSDR), rituels et bouton « Dors », minuterie qui fond tout vers le silence. Entièrement hors ligne.

Dans cette bêta, j'aimerais votre avis sur : est-ce que tout se fait facilement d'une main, dans le noir, l'écran tamisé ? Est-ce que les sons et la musique vous semblent vivants (jamais en boucle) ? Est-ce que la minuterie s'éteint vraiment en douceur ? Testez idéalement au coucher — et dites-moi tout ce qui accroche.

Aucun compte requis. La permission Santé est optionnelle : elle active le carnet de nuit et l'adaptation de la musique à votre cœur.
```

**English**
```
La Berceuse is a sleep instrument — a lullaby for the racing mind. Paced breathing, a cognitive shuffle, living soundscapes and generative music composed on-device, deep rest (NSDR), rituals and a one-tap "Dors" button, and a sleep timer that fades everything to silence. Entirely offline.

In this beta I'd love your read on: does everything work one-handed, in the dark, with the screen dimmed? Do the sounds and music feel alive (never looped)? Does the timer truly fade out gently? Ideally test it at bedtime — and tell me anything that snags.

No account needed. Health permission is optional: it enables the night journal and the music's heart-rate adaptation.
```

### Feedback Email
```
gautreau.jac@gmail.com
```

### What to Test  *(per-build notes — "What's New for testers")*
```
Build 5 — first TestFlight build.
• Start the night with « Dors » and let the timer fade everything out.
• Try each breath pattern; check the haptics feel gentle, not insistent.
• Leave the shuffle running — does it help you drift?
• Mix soundscapes with the generative music; save a favourite mix.
• If you wake at 3 a.m., open the app: you should get one big button.
• Check the Lock Screen countdown (Live Activity) while the timer runs.
```

## Notes
- **Beta App Review notes:** same as the App Review notes in
  `app-privacy-answers.md` (offline, optional HealthKit, background audio).
- **Sign-in required?** → No.
- **Export compliance:** uses only standard iOS encryption (HTTPS is not even
  used — no network). Answer "None of the algorithms mentioned" / exempt.
