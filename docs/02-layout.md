# 02 — Layout

Chosen: **layout A, "instrument panel"** — zones grouped by domain.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ⌂ HUB        PROXMOX · GITHUB · RELEASES        ◷ 14:32:07 ⚙ esc ✕    │
├────────────────┬──────────────────────────┬──────────────────────────────┤
│ INFRASTRUCTURE │ RELEASES                  │ WATCHING                     │
│                │                          │                              │
│ ▸ dynacat    ● │  ▸ opencode    1.4.2  ↑  │  ▸ opencode      CI  ●●●○○   │
│ ▸ proxmox    ● │  ▸ noctalia   5.2.1  –   │  ▸ noctalia-plugins  ○○○●○   │
│ ▸ grafana    ○ │  ▸ kitty      0.36 ↑2   │  ▸ hub-repo        new PR    │
│ ▸ uptime   99%│                          │                              │
├────────────────┴──────────────────────────┴──────────────────────────────┤
│  CPU ▁▂▃▅▇▆▄▂  34%   MEM ▁▁▂▂▃▃▃▂▂  48%   DISK / ███████░░░  71%  ⏻    │
└──────────────────────────────────────────────────────────────────────────┘
```

## Zones flow, they do not sit in a rigid grid

An early revision of this concept assumed fixed columns. It breaks immediately: the
Releases zone holds twelve entries, Links holds four. An empty column three screens
tall reads as a bug.

Final rule: a zone takes its size from its content, and the panel scrolls as a
whole.

```
┌──────────────┐ ┌──────────────┐
│ INFRA        │ │ RELEASES     │   ← different heights, flow top to bottom
│ ▸ dynacat  ● │ │ 1.4.2  ↑     │
│ ▸ proxmox  ● │ │ 5.2.1  –     │
│ ▸ grafana  ○ │ │ 0.36   ↑2    │
└──────────────┘ └──────────────┘
┌──────────────┐ ┌──────────────┐
│ WATCHING     │ │ LINKS        │
└──────────────┘ └──────────────┘
```

The instrument-panel feel survives (groups with headers, aligned left edges) while
size mismatches stop being a problem.

## What a zone contains

**Header** — glyph, domain title, problem count for that domain. The header is the
only element present even when the domain is empty.

**Instrument rows** — one per card. Fixed row structure:

```
[glyph] title .................. value [status]
```

- glyph on the left for identification, scanned with a vertical glance
- value on the right for the thing you actually came to read
- status indicator at the end: a coloured dot or an arrow

Right-alignment of values is mandatory: a column of numbers has to read as a scale.

**Empty domain** is not an empty box but a quiet hint offering a ready-made template
(Proxmox / GitHub / RSS). Lowers the entry barrier and doubles as in-panel
documentation.

## Header

```
⌂ HUB        PROXMOX · GITHUB · RELEASES        ◷ 14:32:07 ⚙ esc ✕
```

- left: name and the list of active domains
- right: clock
- overall status: `✓ 24 cards · 2 errors` — always visible, so you know whether the panel can be trusted
- hotkey hints: `esc` closes, `?` opens the shortcut overlay

## Footer

System metrics (CPU / MEM / DISK / NET) compact, with inline sparklines. A separate
`system` domain, but always pinned to the bottom — it is background, not content.

## Keyboard

| Key | Action |
|---|---|
| `esc` | close panel |
| `?` | shortcut overlay |
| `/` | search across all cards |
| `r` | force refresh |
| `1`…`9` | jump to domain |

## Rejected alternatives

**B "central console"** — domain rail on the left, one large scene in the centre.
Reads better but requires navigation to read. For a panel you open for five seconds
to check whether everything is alive, that is worse.

**C "sector"** — tabs holding a single large grid where a cell's importance drives
its size. Interesting, but importance-driven sizing makes the layout unstable: the
panel jumps on every new incident.

**Fixed columns** — see above.