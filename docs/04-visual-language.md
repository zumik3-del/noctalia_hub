# 04 — Visual language

What separates an instrument panel from an ordinary dashboard.

## 1. Colour is semantic only

Three or four signal colours drawn from the active Noctalia palette, nothing else.

| State | Palette role | When |
|---|---|---|
| `ok` | `primary` | nominal, fresh data |
| `warn` | `secondary` | attention: degraded, updates available, threshold crossed |
| `down` | `error` | failure, source unreachable, release overdue |
| `stale` | `on_surface_variant` | data older than `stale_after_sec` |
| secondary text | `on_surface_variant` | labels, units, timestamps |

No decorative gradients, no brand colours. That is what makes it read as
instruments rather than as a landing page.

Roles come from `noctalia.getColor(role)`, so the panel follows the Noctalia theme
automatically.

## 2. Tabular numerals

Fixed-width figures for **every** metric: percentages, sizes, durations, versions.
Titles stay in the regular face.

Two reasons:

- instrument-panel feel
- numeric columns stop shifting on refresh, so the eye does not relearn every 30 seconds

Numbers are right-aligned: a column has to read as a scale.

**The right-alignment ships; the fixed-width figures do not, and cannot yet.**
`plugin_api` 32 exposes no tabular-figure control. The only typography lever is
`fontFamily`, and it needs a font file registered through `noctalia.loadFont` —
which is a vendored asset carrying an attribution and a visible version, so it is a
[D21](07-decisions.md) decision rather than a rendering detail. Loading a font to
fix a glyph width is the wrong trade to make inside an instrument panel build;
until someone decides it deliberately, values are right-aligned and the digits are
the shell's.

## 3. Density, not air

Small type, thin separators, minimal padding. A space station is cramped, not airy.

Switchable density:

| | `compact` | `standard` | `comfortable` |
|---|---|---|---|
| Value size | 11 | 12 | 13 |
| Zone padding | 8 | 11 | 14 |
| For | 1080p, many cards | default balance | 4K, few cards |

Default is `compact`. At 4K with many zones `comfortable` reads noticeably
better, which is why the switch has to exist. `font_scale` in `layout:`
multiplies every size on top of the chosen density, so a high-DPI screen can
scale type without also loosening the spacing.

## 4. Restrained motion

Only a problem indicator pulses — a slow red breath, roughly 2s period.
Everything else is static.

Sparklines refresh only as fast as the data actually changes.

Rationale: constant motion is fatiguing, and in an instrument panel the priority is
not to distract. Attention should arrive at the problem, not compete with blinking
decoration.

## 5. Focus hierarchy

Reading order follows importance:

1. `down` — failure
2. `warn` — attention
3. `stale` — data cannot be trusted
4. `ok` — nominal, background

Tabbing through the panel follows that order, not YAML order. Someone paging
through instruments should not have to step over normal readings to reach a failure.

## 6. The status line is always visible

`✓ 24 cards · 2 errors` in the header. Not decoration: the panel reports whether it
can be trusted. If a source is quietly returning garbage, that must be visible
immediately.

## 7. Card blocks and the header menu

The card-block framework comes from github-kanban ([D24](07-decisions.md)): each
card is a rounded block with a tinted fill, an optional border, and a lighter
fill while the pointer is over it. The `layout:` keys pick the **shape** —
`card_radius`, `card_spacing`, `card_border`, `card_background`, `hover_effect` —
and the palette picks the **colour**. A lighter hover fill is a palette role with
alpha, not a literal colour, so the theme still owns the result. Hover is
presentation only: it never changes a reading or a state.

Inside the block the layout is github-kanban's activity row ([D25](07-decisions.md)):

```
┌──┐  Gateway                              2  ●
└──┘  Keenetic, gateway and routing
```

A glyph badge leads, a two-line column carries the title and the description, and
the reading plus its state marker sit on the trailing edge. The title is
`on_surface` bold, the description `on_surface_variant`, and only the value and
the marker carry a signal colour (§1–2): the block never recolours the title to
match the state.

A `kind: status` card reads as the dot alone: the colour is the whole message and a
word beside it was the same fact twice ([D27](07-decisions.md)). The `2` above is
the card's **update badge** — the host's pending OS packages, in the attention
colour, and the button that installs them. It is absent when there is nothing to
say, so no host without updates carries a permanent zero.

The header is a menu, also from github-kanban:

```
⌂ HUB   ✓ 14 cards            ◷ 10:14  ⟳  ✕
OVERVIEW   SERVICES   RELEASES   LINKS
```

- left: name and the always-visible trust line (`✓ 24 cards · 2 errors`, §6)
- right: clock, a refresh button and a close button
- below it, `OVERVIEW` plus one tab per zone

`OVERVIEW` is the landing tab and is reserved for the custom dashboard — blank in
this build. Each other tab shows one zone. A pinned `pin: bottom` zone is
background and gets no tab; it stays in the footer.

## Rejected

**A spinner per card.** Visual noise. One skeleton on first render, then data or an
honest "no data".

**Auto-resizing panels.** Constant reflow as card counts change is irritating. Size
is declared in the manifest.

**Custom fonts and icons fetched over the network.** `noctalia.appIconPath` and
`loadFont` exist, but the network is not needed for this.

**Gradient panel backgrounds.** The panel is a backdrop for data. Any patterned
background reduces small-text legibility.

## Theme tokens

Roles are resolved at runtime, never hard-coded:

```lua
local function colorFor(state)
    if state == "down"  then return noctalia.getColor("error") end
    if state == "warn"  then return noctalia.getColor("secondary") end
    if state == "stale" then return noctalia.getColor("on_surface_variant") end
    return noctalia.getColor("primary")
end
```

The alternative `"primary/0.6"` syntax (role with alpha) resolves live against the
palette. Used for de-emphasised elements: zone headers, secondary labels, dividers.