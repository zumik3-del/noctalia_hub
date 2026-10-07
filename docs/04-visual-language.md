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

## 3. Density, not air

Small type, thin separators, minimal padding. A space station is cramped, not airy.

Switchable density:

| | `compact` | `comfortable` |
|---|---|---|
| Row height | 22 | 30 |
| Value size | 11 | 13 |
| Zone padding | 8 | 14 |
| For | 1080p, many cards | 4K, few cards |

Default is `compact`. At 4K with many zones `comfortable` reads noticeably
better, which is why the switch has to exist.

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