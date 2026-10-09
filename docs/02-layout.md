# 02 — Layout

Chosen: **layout A, "instrument panel"** — zones grouped by domain.

```
┌──────────────────────────────────────────────────────────────────┐
│ ⌂ HUB        ✓ 24 cards · 2 errors         ◷ 14:32:07  ⟳  ✕      │
│ OVERVIEW   PROXMOX   GITHUB   RELEASES                           │
├──────────────────────────────────────────────────────────────────┤
│ INFRASTRUCTURE                                                   │
│  ▸ dynacat   ●    ▸ proxmox   ●    ▸ grafana   ○    ▸ uptime 99% │
│ RELEASES                                                         │
│  ▸ opencode 1.4.2 ↑   ▸ noctalia 5.2.1 –   ▸ kitty 0.36 ↑2       │
└──────────────────────────────────────────────────────────────────┘
```

## Zones flow, they do not sit in a rigid grid

A zone takes its size from its content, and the panel scrolls as a whole. Fixed
columns break immediately: Releases holds twelve entries, Links four, and an empty
column three screens tall reads as a bug.

`plugin_api` 32 has no wrapping flex container — `ui.column` / `ui.row` lay out and
there is no `flexWrap` — so what actually ships is **one column of zones, the panel
scrolling**. The rule they were making survives: **a zone is exactly as tall as its
cards, and no zone is stretched to match another.** What is lost is density — twelve
zones means more scrolling than the sketches imply.

## What a zone contains

**Header** — glyph, domain title, problem count for that domain. The header is the
only element present even when the domain is empty.

**Instrument rows** — one per card, github-kanban's activity block
([D25](07-decisions.md)):

```
┌──┐  Title                    value  2  ●  ⇱  ⌨
└──┘  Description
```

- badge on the left: the card's glyph on a tinted rounded square, scanned with a
  vertical glance
- title (bold) on the first line, description (dimmed) on the second; a failure does
  not displace the description — its reason sits on the state marker's tooltip, so a
  red card still says what it measures ([D25](07-decisions.md))
- the reading and the state dot on the trailing edge; a `kind: status` card draws only
  its dot — the colour is the whole message ([D27](07-decisions.md))
- the update badge, when the host has pending OS packages — a warn-coloured count
  between the reading and the dot, and the button that installs them
  ([D28](07-decisions.md))
- action buttons after the dot: a link button opens `link:`, a terminal button runs
  `run:`. Each has its own target, so a card may carry both
  ([D26](07-decisions.md)); only those two are drawn in this build

A card with no `description` is one line tall. Values are right-aligned — a column of
numbers has to read as a scale.

**Empty domain** is not an empty box but a quiet hint offering a ready-made template
(Proxmox / GitHub / RSS) — in-panel documentation.

## Header

```
⌂ HUB        ✓ 24 cards · 2 errors        ◷ 14:32:07  ⟳  ✕
OVERVIEW   PROXMOX   GITHUB   RELEASES
```

- left: name and the trust line `✓ 24 cards · 2 errors`, always visible
- right: clock, refresh, close
- below: a tab strip, `OVERVIEW` plus one tab per zone

`OVERVIEW` is the default and is reserved for the custom dashboard — deliberately
blank in this build. Each other tab shows one zone. A `pin: bottom` zone is
background, so it keeps its footer place instead of getting a tab. `esc` and `r` work
from the keyboard.

## Footer

A zone may declare `pin: bottom` to sit outside the scrolling flow and stay visible.
It is background, not content, so its numbers never push the panel around
([D6](07-decisions.md)), and at most one zone may pin. This build ships no pinned
zone, but the mechanism is part of the schema ([03](03-config.md)).

## Keyboard

| Key | Action |
|---|---|
| `esc` | close panel |
| `r` | force refresh |
| `?` | shortcut overlay (planned) |
| `/` | search across all cards (planned) |
| `1`…`9` | jump to domain (planned) |

`capture_keys` lists only `esc` and `r` today: a key is captured when there is
something behind it, so the panel never swallows a keystroke it will ignore. `r` sets
`hub.cmd` to `refresh` and the collector does the work — the panel is a subscriber,
and starting a poll belongs on the other side of that boundary.

## Rejected alternatives

**B "central console"** (domain rail plus one large scene) reads better but requires
navigation — worse for a panel opened for five seconds. **C "sector"**
(importance-driven cell sizes) makes the layout unstable: it jumps on every incident.
**Fixed columns** — see above.
