# UDAO Contrast Audit — Phase 01

**Scope:** every color that renders TEXT or an interactive glyph, in both
themes, against its actual background. Method: first-principles WCAG 2.1
relative-luminance computation (script reproduced at the bottom — no
black-box tool; every ratio below was computed from the exact sRGB hex).

**Targets (WCAG 2.1):** normal text ≥ 4.5:1 · large text (≥18pt or
≥14pt bold) ≥ 3:1 · UI components / graphical objects ≥ 3:1.

Verdict: **PASS — every text pair ≥ 4.5:1 in both modes.** The one
sub-4.5 color (`flameVivid` on light) is decorative-only by rule (§2).

---

## 1. Dark theme

Backgrounds in play: scaffold `inkBg #0B0C10`, cards `inkSurface
#14161D`, raised surfaces (incl. the roast-card gradient) up to
`inkSurfaceHigh #1E2230`. Each row below reports the **worst case**
(the lightest background that pairing can sit on):

| Role | Foreground | Worst-case bg | Ratio | Target | Verdict |
|---|---|---|---|---|---|
| Body text | onSurface `#F2F4F8` | `#14161D` | **16.41** | 4.5 | PASS |
| Secondary text | onVariant `#A9B1C2` | `#14161D` | **8.39** | 4.5 | PASS |
| Primary accent text | flame `#FF5A3C` | `#1E2230` | **5.11** | 4.5 | PASS |
| Lime accent text | lime `#C9F24B` | `#1E2230` | **12.28** | 4.5 | PASS |
| Gold accent text | gold `#FFC94D` | `#1E2230` | **10.34** | 4.5 | PASS |
| Sky accent text | sky `#5AC8FA` | `#1E2230` | **8.35** | 4.5 | PASS |
| Violet accent text | violet `#A78BFA` | `#1E2230` | **5.82** | 4.5 | PASS |
| Success text | success `#4ADE80` | `#1E2230` | **9.08** | 4.5 | PASS |
| Error text | error `#FF6B6B` | `#1E2230` | **5.70** | 4.5 | PASS |
| Button label | onPrimary ink `#1A0C07` | on flame `#FF5A3C` | **6.17** | 4.5 | PASS |
| Lime button label | ink | on lime | **14.81** | 4.5 | PASS |
| Error button label | onError `#2A0D0D` | on error `#FF6B6B` | **6.51** | 4.5 | PASS |

(On the darker scaffold `#0B0C10` every ratio is higher still — e.g.
flame 6.31, onSurface 17.75.)

## 2. Light theme

Backgrounds in play: scaffold `paperBg #F7F5F0`, cards `paperSurface
#FFFFFF`. Worst case for dark-on-light text is the WHITE card; for the
scaffold it's `paperBg`. The bright flame `#FF5A3C` is **2.84:1 on
paper / 3.10:1 on white — below the 4.5 text target**, so it is NEVER
text in light mode. Light mode swaps each accent to a deepened
"text-safe" twin (see `udao_colors.dart`):

| Role | Foreground | Worst-case ratio | (on paper / on white) | Target | Verdict |
|---|---|---|---|---|---|
| Body text | onSurface `#14161D` | **16.58** | 16.58 / 18.07 | 4.5 | PASS |
| Secondary text | onVariant `#5A6172` | **5.69** | 5.69 / 6.20 | 4.5 | PASS |
| Primary accent text | flameDeep `#C93A12` | **4.70** | 4.70 / 5.13 | 4.5 | PASS |
| Lime accent text | limeDeep `#5F7A0A` | **4.51** | 4.51 / 4.91 | 4.5 | PASS |
| Gold accent text | goldDeep `#8A6A00` | **4.65** | 4.65 / 5.07 | 4.5 | PASS |
| Sky accent text | skyDeep `#0A6DA3` | **5.17** | 5.17 / 5.63 | 4.5 | PASS |
| Violet accent text | violetDeep `#5B3FC4` | **6.53** | 6.53 / 7.11 | 4.5 | PASS |
| Success text | successDeep `#15803D` | **4.60** | 4.60 / 5.02 | 4.5 | PASS |
| Error text | errorDeep `#B3261E` | **6.00** | 6.00 / 6.54 | 4.5 | PASS |
| Flame button label | white | **5.13** | on flameDeep | 4.5 | PASS |
| Lime button label | white | **4.91** | on limeDeep | 4.5 | PASS |
| Decorative flame | flameVivid `#FF5A3C` | 2.84 | 2.84 / 3.10 | n/a | Decor-only |

### The flameVivid rule

`flameVivid` (always-bright flame `#FF5A3C`) exists so brand artwork —
the logo mark, the streak flame, the onboarding hero — glows with the
SAME personality in light mode instead of going muddy brown. It may
color **decorative marks only**: it must never style text, icon glyphs
that carry meaning, or component boundaries users must perceive. The
grep gate for Phase 01+ reviews is: `flameVivid` references must sit
inside decorative SVG/Image tint sites, not `TextStyle`/`Icon` colors
in lists, rows or forms.

## 3. Non-text / UI-component contrast (≥ 3:1, both modes)

| Element | Pair | Ratio | Verdict |
|---|---|---|---|
| Card border (dark) | `inkOutline #323648` | 1.77 → decorative | Border reinforced by surface tint step |
| Card border (light) | `#DCD8CD` on paper | ~1.2 → decorative | Same |
| Skeleton fill | low contrast BY DESIGN | — | Content placeholder, aria-hidden via Semantics on parents |
| SpendBar fill | lime / flame on skeleton track | ≥ 3.0 both modes | PASS |
| Nav active tint | flame 14% over surface | paired with flame label ≥ 4.5 | PASS |
| Severity stamp border/text | flame on roast card | 5.11 / 4.70+ | PASS |

Card borders are intentionally soft (aesthetics of ink on paper); state
is never conveyed by border alone — every interactive card also shifts
background and label color, and every actionable control carries a
4.5:1+ label.

## 4. Large-text usage

`displayLarge/Medium/Small` (Syne 800, 48/40/28) and
`headlineMedium` (SG 700, 24) qualify as large text (≥ 18.66px bold).
Those styles may additionally use the accent colors listed above — all
of which already clear 4.5:1, i.e. they clear the 3:1 large-text bar
with more than 50% headroom.

## 5. Verification script (reproduce any ratio)

```python
def lum(hex_s):
    c = [int(hex_s[i:i+2], 16)/255 for i in (0, 2, 4)]
    c = [x/12.92 if x <= 0.04045 else ((x+0.055)/1.055)**2.4 for x in c]
    return 0.2126*c[0] + 0.7152*c[1] + 0.0722*c[2]

def ratio(f, b):
    lf, lb = lum(f[1:]), lum(b[1:])
    hi, lo = max(lf, lb), min(lf, lb)
    return (hi + 0.05) / (lo + 0.05)
```

Re-runnable live: swap the hexes for the current `UdaoColors` values
and assert `ratio(fg, bg) >= 4.5` in the Phase-01 test suite
(`test/core/theme/contrast_test.dart` does exactly this).

## 6. Regressions to watch

- Adding a new accent: add BOTH a text-safe light twin and a dark
  value, with a `contrast_test.dart` row, before first use.
- Delta chips use `tone.withValues(alpha: 0.16)` BACKGROUNDS with the
  FULL-tone label — never the washed tint as text color.
- `MediaQuery.withClampedTextScaling(1.3)` on MoneyDisplay/RoastCard
  keeps clamped scaling from pushing text past its container's edge —
  it does not affect contrast, but is part of the same accessibility
  pass.
