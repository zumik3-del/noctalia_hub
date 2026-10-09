# 04 — Visual language

What separates an instrument panel from an ordinary dashboard.

## 1. Colour is semantic only

| State | Palette role | When |
|---|---|---|
| `ok` | `primary` | nominal, fresh data |
| `warn` | `secondary` | degraded, updates available, threshold crossed |
| `down` | `error` | failure, source unreachable, release overdue |
| `stale` | `on_surface_variant` | data older than `stale_after_sec` |
| secondary text | `on_surface_variant` | labels, units, timestamps |

No decorative gradients, no brand colours. Roles come from `noctalia.getColor(role)`,
so the panel follows the Noctalia theme. The `"primary/0.6"` form (a role with alpha)
resolves live against the palette and is used for de-emphasised elements.

## 2. Tabular numerals

Fixed-width figures for every metric, right-aligned so a numeric column stops shifting
and reads as a scale. **The right-alignment ships; the fixed-width figures do not.**
`plugin_api` 32 exposes no tabular-figure control — the only lever is `fontFamily`,
which needs a font loaded through `noctalia.loadFont`, a vendored asset
([D21](07-decisions.md)). Loading a font to fix a glyph width is the wrong trade here;
until someone decides it deliberately, values are right-aligned and the digits are the
shell's.

## 3. Density, not air

| | `compact` | `standard` | `comfortable` |
|---|---|---|---|
| Value size | 11 | 12 | 13 |
| Zone padding | 8 | 11 | 14 |
| For | 1080p, many cards | default balance | 4K, few cards |

Default is `compact`. `font_scale` in `layout:` multiplies every size on top of the
chosen density, so a high-DPI screen can scale type without loosening the spacing.

## 4. Restrained motion

Only a problem indicator pulses — a slow red breath, roughly 2s. Everything else is
static, and sparklines refresh only as fast as the data changes. Constant motion is
fatiguing; attention should arrive at the problem, not compete with blinking
decoration.

## 5. Focus hierarchy

Reading order — and tab order — is `down → warn → stale → ok`, not YAML order
([D8](07-decisions.md)). Someone paging through instruments should not step over normal
readings to reach a failure.

## 6. The status line is always visible

`✓ 24 cards · 2 errors` in the header. Not decoration: the panel reports whether it can
be trusted. A source quietly returning garbage must be visible immediately.

## 7. Card blocks and the header menu

The card-block framework comes from github-kanban ([D24](07-decisions.md)): a rounded
block with a tinted fill, an optional border, and a lighter fill while the pointer is
over it. The `layout:` keys pick the **shape**; the palette picks the **colour**. Hover
is presentation only — it never changes a reading or a state.

Inside the block is github-kanban's activity row ([D25](07-decisions.md)):

```
┌──┐  Gateway                              2  ●
└──┘  Keenetic, gateway and routing
```

A glyph badge leads, a two-line column carries the title and the description, and the
reading plus its state marker sit on the trailing edge. The title is `on_surface` bold,
the description `on_surface_variant`, and only the value and the marker carry a signal
colour (§1–2) — the block never recolours the title. A `kind: status` card reads as the
dot alone ([D27](07-decisions.md)). The `2` is the update badge — the host's pending OS
packages, in the attention colour, absent when there is nothing to say
([D28](07-decisions.md)).

The header is a menu, also from github-kanban:

```
⌂ HUB   ✓ 14 cards            ◷ 10:14  ⟳  ✕
OVERVIEW   SERVICES   RELEASES   LINKS
```

Left: name and the trust line (§6). Right: refresh, close. Below: `OVERVIEW`
plus one tab per zone. `OVERVIEW` is the blank landing tab; a pinned `pin: bottom` zone
is background and gets no tab.

## Rejected

**A spinner per card** — visual noise; one skeleton on first render, then data or an
honest "no data". **Auto-resizing panels** — constant reflow is irritating; size is
declared in the manifest. **Network-fetched fonts and icons** — not needed. **Gradient
backgrounds** — reduce small-text legibility.
