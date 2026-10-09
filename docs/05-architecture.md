# 05 — Architecture

## Three layers

```
hub/
├── plugin.toml          # manifest: plugin_api 32, dependencies, settings
├── service.luau         # background: collect data → noctalia.state
├── panel.luau           # panel, pure subscriber
├── widget.luau          # compact bar summary
├── visual.luau          # signal roles, glyph helpers, the card wrapper
├── rows.luau            # one card: the reading and the link bookmark
├── zones.luau           # a zone, and the config-errors block
├── util.luau            # the type predicates every layer uses
├── config.luau          # load and validate hub.yaml
├── pipeline.luau        # fetch → extract → map → format
├── .luaurc              # languageMode = nonstrict, matching the entry files
└── translations/en.json
```

There is no `sources/` directory. Each source type is a branch inside `Pipeline.fetch`,
and a new type plugs into `fetch` without touching `extract`, `map` or `format`
([D4](07-decisions.md)). A directory of source modules would only invite the extraction
fields to drift per type — the failure D4 exists to prevent.

### service.luau — data only

Does not touch the UI. Polls sources, lays results out in `noctalia.state`, survives
its own errors. It writes four state keys and nothing else, all namespaced `hub.` because
`noctalia.state` is a single flat store shared by all plugins:

| Key | Contents |
|---|---|
| `hub.config` | the validated model, zones and all |
| `hub.cards` | `cardId -> runtime record`, the readings |
| `hub.summary` | per-state counts, for the header line and the bar widget |
| `hub.fatal` | why the config could not be read, `""` when it could |

`hub.cmd` is the one channel the other way: the panel writes a request (`refresh`, or a
card's action) and the collector watches for it.

A runtime record is `{ state, text, fields, rows, rowCount, error, configError,
lastGoodAtMs, attempts, nextDueAtMs, updates, minis }`. `error` is a problem with the
source; `configError` is a problem with the card, already true before the first poll and
not cleared when the source recovers. `updates` and `minis` are nested second readings
that travel with the card ([D28](07-decisions.md), [D30](07-decisions.md)).

**A publish that changes nothing is a publish that costs a tree rebuild.** Both
subscribers redraw on every write, so the collector compares a signature of everything
drawn and skips the write when it matches. Ages are deliberately absent from that
signature — the panel derives them at render time, so ages update without a write per second
once a second.

### panel.luau — presentation only

Builds a `ui.*` tree: zones in `ui.column`, rows in `ui.row`. It does not know where the
data came from — it only renders what is in state. The rows and the zones live in
`rows.luau` and `zones.luau`; what stays here is the header, the tab strip, the fatal
and loading screens, and the `view` those are handed.

### visual.luau — what both surfaces draw

The five signal roles (`ok` / `warn` / `down` / `stale`, plus `pending` as the absence
of a reading), the glyph baseline alignment, the kind fallback glyphs, the card wrapper,
and the hover state. Both `panel.luau` and `widget.luau` read from here — the roles were
written out twice once and the copies had drifted, the bar missing `pending` the panel
had added. It holds no colour beyond the roles and reads nothing from the config: fill,
radius and border arrive as state. The hover state needs a redraw, and modules cannot
call into one another, so the panel registers its `render()` through
`Visual.setRedraw`.

### rows.luau / zones.luau — the card and the zone

A card is two shapes (a reading, and the `kind: link` bookmark) plus the update badge; a
zone is a header plus those cards, plus the config-errors block. Neither reads state:
both take a `view` built by the panel on every render. A module that held `doc` or
`cards` itself would hold the table from before the last watch fired and draw a reading
the collector had already moved past.

### util.luau

`isString` and `isNumber`, plus the one `NO_VALUE` placeholder the collector publishes
and the panel draws. `isNumber` rejects NaN, which JSON decodes in some hosts and which
compares false against every threshold.

### widget.luau — the summary

One row in the bar: `● 5  ▲ 2  ↓ 1` — counts of ok, warn, down and available updates,
collapsing to a single green dot when everything is nominal. Clicking opens the panel.

## Noctalia API surface

| Call | Purpose |
|---|---|
| `noctalia.http(req, cb)` | HTTP sources |
| `noctalia.runAsync(argv, cb, timeout)` | Commands, file reads, YAML conversion |
| `noctalia.runStream(cmd, onLine)` | Feeds, `journalctl -f`, console cards |
| `noctalia.runInTerminal(cmd)` | `run:` actions — a separate terminal window |
| `noctalia.commandExists(name)` | Hiding actions whose binary is absent |
| `noctalia.state.set/get/watch` | service → UI channel |
| `noctalia.setUpdateInterval(ms)` | Service tick |
| `noctalia.getColor(role)` | Theme tokens |
| `noctalia.json.encode/decode` | Serialisation |
| `noctalia.readFile/fileInfo` | Config, mtime polling |
| `noctalia.pluginDataDir()` | Converted-JSON cache |
| `noctalia.tr(key, subst)` | i18n |
| `noctalia.notify` / `notifyError` | Alerts |
| `noctalia.togglePanel(id)` | Opening **this** plugin's own panel, from the bar |
| `ui.*` | Declarative tree |

Opening *another* panel goes through the shell: `noctalia msg panel-open <id>
[context]` (idempotent), `panel-close`, `plugins list`, `settings-open-plugin`.
`noctalia.togglePanel` is used for exactly one thing — the bar widget toggling this
plugin's *own* panel, where inverting is correct. For **any other** panel a card uses
`panel-open`, because pressing a card twice must bring the panel forward, not dismiss it
([D20](07-decisions.md)).

### What is not in the API

| Missing | Consequence |
|---|---|
| PTY / stdin handle | No embedded terminal; `runInTerminal` delegates to a real window |
| Write path into `runStream` | Console cards are read-only tails |
| WebView / iframe / HTML | No embedding — not a URL, not another plugin's panel |
| Panel registry query | `togglePanel` only inverts; the shell has the rest |
| Cross-plugin data read | `state` is shared but has no discovery and no schema |
| Service pointers | Shell services are C++ objects a plugin cannot hold |
| Per-widget colour overrides | `getColor(role)` gives theme roles, not the bar's layer |
| Manual layout | Plugin trees are laid out by the reconciler; geometry converges, not matches |

These are closed, not deferred ([D20](07-decisions.md), [D21](07-decisions.md)).

## UI primitives

Used: `column`, `row`, `scroll`, `box`, `label`, `glyph`, `image`, `separator`,
`spacer`, `progress`, `button`, `graph`. Deliberately unused: `markdown` (the no-markup
boundary, [01](01-vision.md)); `input` / `select` / `toggle` / `slider` (read-only in
v1, and `select` is not allowed in a persistent panel); `dragSource` / `dropZone` (the
deferred editor, [D9](07-decisions.md)).

- `ui.graph` — sparklines, values `0..1`, a second series via `values2`
- `ui.scroll` — panels only; skipped with a warning in the bar
- `ui.box` is a **leaf** — a tooltip on a node with content goes on the `row`/`column`
  that wraps it, which take one too
- `key` gives a node stable identity across renders, preserving hover state

## Manifest

```toml
id = "zumik3-del/hub"
name = "Hub"
version = "0.1.0"
plugin_api = 32
dependencies = ["yq"]

[[widget]]
id = "summary"
entry = "widget.luau"
  [[widget.setting]]
  key = "glyph"
  type = "glyph"
  default = "gauge"
  [[widget.setting]]
  key = "compact"
  type = "bool"
  default = false

[[panel]]
id = "panel"
entry = "panel.luau"
width = 860
height = 620
placement = "attached"
position = "auto"
open_near_click = true
dismiss_on_outside_click = true
keyboard_focus = "exclusive"
capture_keys = ["escape", "r"]

[[service]]
id = "collector"
entry = "service.luau"
```

`placement = "attached"` with `open_near_click = true` is github-kanban's behaviour
([D24](07-decisions.md)): the panel slides out beside the widget, and `position =
"auto"` lets the host pick the side from the click. `width`/`height` take a pixel count
or `"fill"` — nothing between. `position` takes the underscore spellings
(`center_left`, `top_right`, …); the settings schema spells them with dashes, and
`"center-left"` parses, lints clean, and is silently ignored. There is no
`persistent = true` ([D1](07-decisions.md)).

The plugin directory is named after the id's second segment (`hub`): Noctalia resolves a
plugin at `<source>/<segment>/` and reads `plugin.toml` there, so the directory is not
free. A mismatch fails with `parse error: File could not be opened for reading`. The bar
widget's id in `settings.json` is `plugin:zumik3-del/hub:summary`.

### Host rules the type definitions do not state

| Rule | Cost of getting it wrong |
|---|---|
| `require` must be relative **and** end in `.luau` | `call to 'chunk' failed: require path must be relative and end in .luau` |
| A glyph name must exist in the host's font | Nothing draws; one log line per redraw |
| `setText` / `setGlyph` / `setImage` are inert while a `render()` tree is active | The tree is rebuilt per tick |
| A bar widget cannot host `ui` controls | `input` / `select` / `scroll` skipped silently |
| A manifest `position` is spelled with underscores | `"center-left"` is ignored; the panel opens centred |

The glyph vocabulary is the host's bundled Tabler subset, which moves with the shell.
The plugin does not carry a copy and does not validate names — check with
`grep 'missing glyph' ~/.cache/noctalia/noctalia.log`. The third row is why
`setWantsSecondTicks(true)` costs a full rebuild every second instead of one label
update: the price of a declarative tree.

Manifest rules enforced by `noctalia plugins lint`: `persistent = true` needs
`dismiss_on_outside_click = false` and is incompatible with `keyboard_focus =
"exclusive"`; `"fill"` needs `placement = "floating"`; `capture_keys` needs
`on_demand` or `exclusive` focus; a declared setting that no entry reads is a warning —
which is why `widget.luau` reads both `glyph` and `compact`.

## Build order

1. **Skeleton** — manifest, static zones, `widget.luau`. **Done.**
2. **One source** — Proxmox via `http`, with the full pipeline. Not built.
3. **Remaining sources** — `http`, `rss`, `stream`. **`command` and `static` are done.**
4. **Thresholds, staleness, sparklines.**
5. **Hot reload.**
6. **Actions** — `link` and `run` are drawn and executed; `link_template`, `deep_link`
   and `panel` are validated but not drawn.
7. **Console cards**, 8. **List cards**, 9. **Card editor**, 10. **Controls.**

Steps 1–2 yield a working panel with one live source; each source type after that is an
independent increment. Controls come last — they are the only feature that can break
something. Remote containers are not a feature: a service in an LXC is `command` + `ssh`
+ `pct exec` ([D17](07-decisions.md)).

## Verification

```bash
noctalia plugins lint hub/          # manifest vs code: settings, entries, panel rules
noctalia msg plugins list           # is the plugin installed and enabled
```

`lint` never loads a module, resolves a `require` or asks the host to draw anything, so
four defects got past it and past an offline harness — a `for` over an array used as an
iterator, an `isArray` where `isTable` was meant, a discarded return that left secrets
unsubstituted, and a rejected `require` path. All four were caught against a running
shell, so the log is part of the test surface:

```bash
# a path source reads the working tree, so edits hot-reload and nothing is copied
noctalia msg plugins source add hub path "$PWD"
noctalia msg plugins enable zumik3-del/hub
grep -E 'missing glyph|\[ERR\] \[luau\]' ~/.cache/noctalia/noctalia.log
```

A healthy plugin loads in three lines and then goes silent: the collector publishes only
when a signature changes, so silence is the expected steady state.

## What the skeleton does not render yet

The list at the bottom of `panel.luau` records each gap against the build-order step
that closes it. Three are API limits, not unfinished work:

- **No flex wrap** — zones stack vertically and the panel scrolls
  ([02](02-layout.md)).
- **No tabular figures** — values are right-aligned instead ([D21](07-decisions.md)).
- **No per-widget colour layer** — the bar summary draws from the palette only.
