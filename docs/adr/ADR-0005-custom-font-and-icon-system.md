# ADR-0005 — Custom font & icon system (no default fonts/icons)

- **Status:** Accepted (Phase 00)
- **Date:** 2026-10-27

## Context

The product brief is explicit: **no generic "AI-generated app" look**.
Default Roboto + Material icons is the uniform of template apps; UDAO's
brand ("Desi Maximalism × Fintech Precision") needs a distinct typographic
voice (display flair for roasts, tabular-feel numerals for money) and
original iconography for its signature concepts (roast flame, chindi
badge, ladder, slayer, verdict bell).

## Decision

1. **Fonts (all SIL OFL, vendored as static TTFs in assets/fonts):**
   - `Syne` 700/800 — display family (wordmark, roast headlines);
   - `SpaceGrotesk` 400/500/700 — headings and money numerals;
   - `Inter` 400–800 — body and UI text.
   No widget may rely on the platform/default family.
2. **Icons:**
   - 8 original brand SVG marks in `assets/icons/`, exposed through the
     `AppIcons` registry, drawn at 24×24 with 2px rounded strokes and
     `currentColor` (tint at render time);
   - `phosphor_flutter` for generic system glyphs (arrows, close,
     settings, …);
   - **Material `Icons` / `CupertinoIcons` are banned in `lib/`** —
     enforced by CI grep with word boundaries (`\b(Icons|CupertinoIcons)\.`)
     so `AppIcons` itself never trips it.
3. `uses-material-design: true` stays in pubspec because framework
   internals (text-selection toolbar) reference the icon font; our code
   never does.
4. Launcher/splash artwork ships as an adaptive-icon vector now
   (placeholder), replaced by the Phase 08 brand pass.

## Consequences

**Positive:** recognizable identity; roast surfaces look like a zine, not
a bank app; icon ban is mechanically enforced, not aspirational.

**Negative:** ~2.5 MB of vendored fonts; the AppIcons registry must be
maintained as marks are added; CI gate needs the word-boundary nuance
documented (done in ci.yml).

**Mitigations:** fonts are subset-able later if size pressure appears
(Phase 08 size budget: play AAB base ≤15 MB); Phase 01's design system
encapsulates families so a swap is one-token.
