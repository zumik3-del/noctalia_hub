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

### What actually renders

**Zones stack vertically, one per row, and the panel scrolls.** `plugin_api` 32 has
no wrapping flex container — `ui.column` and `ui.row` lay out and there is no
`flexWrap`, so a masonry flow is not expressible. The sketches above are the idea;
the shipped layout is one column of zones.

The rule they were making survives intact, because it was never really about
columns: **a zone is exactly as tall as its cards, and no zone is stretched to match
another.** That is what the vertical stack already gives. What is lost is density —
twelve zones means twelve full-width blocks and more scrolling than the sketches
imply.

Zone headers stay aligned left, values stay right-aligned within a zone, and the
instrument-panel character comes from the type scale, the rules and the signal
colours rather than from the arrangement.

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

System metrics (CPU / MEM / DISK) compact, with inline sparklines. A separate
`system` domain, declared with `pin: bottom`, so it sits outside the scrolling flow
— it is background, not content.

## Keyboard

| Key | Action |
|---|---|
| `esc` | close panel |
| `?` | shortcut overlay |
| `/` | search across all cards |
| `r` | force refresh |
| `1`…`9` | jump to domain |

`capture_keys` in the manifest lists only `esc` and `r` today. The other rows are
the design, not the build: a key is captured when there is something behind it, so
that the panel never swallows a keystroke it will ignore. `esc` closes the panel
directly; `r` sets `hub.cmd` to `refresh` and the collector does the work, because
the panel is a subscriber and starting a poll belongs on the other side of that
boundary.

## Rejected alternatives

**B "central console"** — domain rail on the left, one large scene in the centre.
Reads better but requires navigation to read. For a panel you open for five seconds
to check whether everything is alive, that is worse.

**C "sector"** — tabs holding a single large grid where a cell's importance drives
its size. Interesting, but importance-driven sizing makes the layout unstable: the
panel jumps on every new incident.

**Fixed columns** — see above.