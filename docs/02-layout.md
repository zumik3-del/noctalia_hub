# 02 — Layout

Chosen: **layout A, "instrument panel"** — zones grouped by domain.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ⌂ HUB        ✓ 24 cards · 2 errors         ◷ 14:32:07  ⟳  ✕          │
│ OVERVIEW   PROXMOX   GITHUB   RELEASES                                   │
├────────────────┬──────────────────────────┬──────────────────────────────┤
│ INFRASTRUCTURE │ RELEASES                  │ WATCHING                     │
│                │                          │                              │
│ ▸ dynacat    ● │  ▸ opencode    1.4.2  ↑  │  ▸ opencode      CI  ●●●○○   │
│ ▸ proxmox    ● │  ▸ noctalia   5.2.1  –   │  ▸ noctalia-plugins  ○○○●○   │
│ ▸ grafana    ○ │  ▸ kitty      0.36 ↑2   │  ▸ hub-repo        new PR    │
│ ▸ uptime   99%│                          │                              │
└────────────────┴──────────────────────────┴──────────────────────────────┘
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

**Instrument rows** — one per card, drawn as github-kanban's activity block
([D25](07-decisions.md)). Fixed structure:

```
┌──┐  Title                      value  ●
└──┘  Description
```

- badge on the left: the card's glyph on a tinted rounded square, for
  identification scanned with a vertical glance
- title on the first line, bold
- description on the second line, dimmed; an error or a stale reading takes that
  line's place rather than sitting under it, so a failure is never lost
- value and status dot on the trailing edge, for the thing you actually came to
  read

A card with no `description` is one line tall. Right-alignment of values is
mandatory: a column of numbers has to read as a scale.

**Empty domain** is not an empty box but a quiet hint offering a ready-made template
(Proxmox / GitHub / RSS). Lowers the entry barrier and doubles as in-panel
documentation.

## Header

```
⌂ HUB        ✓ 24 cards · 2 errors        ◷ 14:32:07  ⟳  ✕
OVERVIEW   PROXMOX   GITHUB   RELEASES
```

- left: name and the trust line, `✓ 24 cards · 2 errors` — always visible, so you
  know whether the panel can be trusted
- right: clock, a refresh button and a close button
- below: a tab strip, `OVERVIEW` plus one tab per zone

The zone list used to sit inline in the header (`PROXMOX · GITHUB · RELEASES`) and
became the tab strip when the github-kanban menu framework landed
([D24](07-decisions.md)). `OVERVIEW` is the default and is reserved for the custom
dashboard — deliberately blank in this build. Each other tab shows one zone. A
`pin: bottom` zone is background, so it keeps its place in the footer instead of
getting a tab. `esc` and `r` still work from the keyboard; `?` opens the shortcut
overlay once it exists.

## Footer

A zone may declare `pin: bottom` to sit outside the scrolling flow and stay
visible. It is background, not content, so its numbers never push the panel around
(D6), and at most one zone may pin. This build ships no pinned zone — the earlier
System footer was removed — but the mechanism is part of the schema
([03](03-config.md)).

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