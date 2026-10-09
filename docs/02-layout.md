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
- right: refresh, close
- below: a tab strip, `OVERVIEW` plus one tab per zone

`OVERVIEW` is the default and is reserved for the custom dashboard — a fleet-wide
summary with a health bar and a problems list (see below). Each other tab shows one
zone. A `pin: bottom` zone is background, so it keeps its footer place instead of
getting a tab. `esc` and `r` work from the keyboard.

## Overview tab

The overview tab is a fleet-wide summary: a health bar showing how many cards
are ok, warn, down, or stale, followed by a problems list of every card that is
not ok, most severe first.

```
┌─────────────────────────────────────────────────┐
│  ✓ 24 cards · 2 errors              [↻] [✕]    │
├─────────────────────────────────────────────────┤
│  [OVERVIEW]  [INFRA]  [SERVICES]  [MEDIA]       │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐        │
│  │  18  │  │  3   │  │  2   │  │  1   │        │
│  │  ok  │  │ warn │  │ down │  │stale │        │
│  └──────┘  └──────┘  └──────┘  └──────┘        │
│                                                 │
│  ─────────────────────────────────────────────  │
│                                                 │
│  ⚠ pihole              42 updates pending       │
│  ⚠ proxmox             disk 85% full            │
│  ⚠ lxc-121             container stopped        │
│                                                 │
│  ✗ home-assistant      timeout after 8s         │
│  ✗ grafana             connection refused       │
│                                                 │
└─────────────────────────────────────────────────┘
```

The health bar is one row of four tiles, each showing a count and its label.
Colour is semantic: ok is primary, warn is warn, down is error, stale is dimmed.
A tile with 0 is still drawn — the absence of a problem is a fact the reader
wants to see, not a gap to skip.

The problems list shows every card that is not ok, sorted by severity:
down and errors first, then stale, then warn. A card whose own state is ok but
whose host has pending updates is warn (D28), so it belongs here.

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
