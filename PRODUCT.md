# PRODUCT.md — La Berceuse

## Register

**Product** (native iOS app UI) by default; the `landing/` folder is a **brand**
surface (marketing landing page) and is designed in the brand register.

## What it is

La Berceuse is a native iOS **sleep instrument** — a lullaby for the racing
mind. Wind-down rituals, breath pacing, a cognitive shuffle, living procedural
soundscapes, generative music (in the spirit of brain.fm/Endel, but fully
on-device), NSDR/yoga-nidra, a 3 a.m. rescue mode, a nightstand mode, and a
night journal correlating rituals with HealthKit sleep. **Entirely offline: no
account, no tracking, no network, no AI calls.** Sixth app in Jac's Atelier /
« La shop » family.

## Users & purpose

- People falling asleep (or awake at 3 a.m.) with a racing mind — in the dark,
  one-handed, phone dimmed, often with a partner asleep beside them.
- French-first (Québec), fully bilingual FR/EN.
- The job: *make tonight easier* — start the night in one tap, quiet the mind,
  let the sound fade itself out.
- Emotions the surfaces must evoke: **calm, intimacy, trust**. Never urgency,
  never gamification, never "engagement".

## Brand personality

**Calme, nocturne, artisanal.** A quiet night sky, a low warm moon; handcrafted
sound (every layer synthesized live, nothing looped) presented with restraint.
The voice is soft, second-person, French-first; short sentences; no exclamation
marks; no hype adjectives.

## Visual identity (from the app, `Sources/Util/Theme.swift`)

- Ground: true black `#000` / deep indigo `oklch(0.18 0.05 285)`-family
  (`indigo #171536`, `indigoDeep #0A0A1C`, `nightBlue #0F1229`).
- Ink: `moonlight #DBDBEB`, muted `mist #9EA3BD`, faint `mutedFar #666B85`.
- Accent (used sparingly, it IS the moon): `amber #F5C780`, `amberDeep #E69452`.
- Panels: `#121216` / lines `#2E2E42`.
- Type pairing: a quiet serif for display (New York in-app) + a rounded sans for
  UI (SF Rounded in-app). Web equivalents should keep the serif-display /
  rounded-body contrast.
- Motion: slow, breathing, reduced-motion safe. Nothing bounces.

## Anti-references

- SaaS landing slop: gradient text, hero metrics, identical feature-card grids,
  uppercase tracked eyebrows, purple gradients.
- Wellness-app clichés: lotus icons, gradient sunsets, stock photos of sleeping
  models, "Sleep better tonight!!" urgency.
- Cream/warm-editorial default (Jac's standing rule): warmth comes from the
  amber accent and the voice, never from a cream page background.
- Anything that looks bright: these surfaces are read at night, in the dark.

## Accessibility

- Body contrast ≥ 4.5:1 even on the dark ground; the landing is read at night.
- `prefers-reduced-motion` honored everywhere (the app is reduced-motion safe;
  the web surfaces must be too).
- FR and EN fully equivalent — no untranslated strings.
