# 05 — Architecture

## Three layers

```
hub/
├── plugin.toml          # manifest: plugin_api 32, dependencies, settings
├── service.luau         # background: collect data → noctalia.state
├── panel.luau           # panel, pure subscriber
├── widget.luau          # compact bar summary
├── config.luau          # load and validate hub.yaml
├── pipeline.luau        # fetch → extract → map → format
├── .luaurc              # languageMode = nonstrict, matching the entry files
└── translations/en.json
```

There is no `sources/` directory. Each source type is a branch inside
`Pipeline.fetch`, and the schema's promise is that a new type plugs into `fetch`
without touching `extract`, `map` or `format` ([D4](07-decisions.md)). A directory
of source modules would only invite the extraction fields to drift per type, which
is the failure D4 exists to prevent.

`.luaurc` is the same file the official plugin repository ships: `nonstrict`
matches the `--!nonstrict` directive every entry file starts with, which is the
right fit for dynamically-typed scripts — full autocomplete and real typo
diagnostics, without strict-mode noise about absent optional values. Point
luau-lsp at the official `noctalia.d.luau` for the API surface.

### service.luau — data only

Does not touch the UI at all. Polls sources, lays results out in
`noctalia.state`, survives its own errors.

```lua
function update()
    -- ticks at noctalia.setUpdateInterval()
end
```

Results are published into plugin state:

```lua
noctalia.state.set("cards", { ... })
noctalia.state.set("configError", { line = 42, message = "unknown source type 'htp'" })
```

The panel subscribes via `noctalia.state.watch()` and redraws itself. There is no
shared Lua memory between entry points — state is the only channel.

Key calls:

```lua
noctalia.http({ url = ..., headers = { ... } }, function(res) ... end)
noctalia.runAsync(argv, function(res) ... end, timeoutMs)
noctalia.runStream(cmd, function(line) ... end)
noctalia.json.decode(str)
noctalia.getConfig(key)
noctalia.state.set("hub.cards", { ... })
```

The service writes four state keys and nothing else. Every one is namespaced
`hub.`, because `noctalia.state` is a single flat store shared by all plugins:

| Key | Contents |
|---|---|
| `hub.config` | the validated model, zones and all |
| `hub.cards` | `cardId -> runtime record`, the readings |
| `hub.summary` | per-state counts, for the header line and the bar widget |
| `hub.fatal` | why the config could not be read, `""` when it could |
| `hub.cmd` | panel → collector requests: `refresh`, and the card action buttons |

A runtime record is `{ state, text, fields, rows, rowCount, error, configError,
lastGoodAtMs, attempts, nextDueAtMs, updates }`. `error` is a problem with the
source; `configError` is a problem with the card itself, which is already true before
the first poll and does not clear when the source recovers. `updates` is the card's
second reading when it has one — its own `{ state, text, error, lastGoodAtMs,
attempts, nextDueAtMs }`, nested so it travels with the card ([D28](07-decisions.md)).

**A publish that changes nothing is a publish that costs a tree rebuild.** Both
subscribers redraw on every write, so the collector compares a signature of
everything drawn and skips the write when it matches. Ages are deliberately absent
from that signature: the panel derives them from `noctalia.nowMs()` at render time,
so the clock ticks without the collector writing once a second.

### panel.luau — presentation only

```lua
noctalia.state.watch("cards", render)
panel.render(tree)
```

Builds a `ui.*` tree: zones in `ui.column`, rows in `ui.row`. It does not know where
the data came from — it only renders what is in state.

### widget.luau — the summary

One row in the bar, not a list of icons:

```
● 5  ▲ 2  ↓ 1
```

Counts of ok, warn, down and available updates. When everything is nominal this
collapses to a single green dot. Clicking opens the panel:

```lua
function onClick()
    noctalia.togglePanel("zumik3-del/hub:panel")
end
```

## Noctalia API surface

| Call | Purpose |
|---|---|
| `noctalia.http(req, cb)` | HTTP sources |
| `noctalia.runAsync(argv, cb, timeout)` | Commands, file reads, YAML conversion |
| `noctalia.runStream(cmd, onLine)` | Feeds, `journalctl -f`, console cards |
| `noctalia.runInTerminal(cmd)` | `run:` actions — hands off to a terminal window |
| `noctalia.commandExists(name)` | Hiding actions whose binary is absent |
| `noctalia.state.set/get/watch` | service → UI channel |
| `noctalia.setUpdateInterval(ms)` | Service tick |
| `noctalia.getColor(role)` | Theme tokens |
| `noctalia.json.encode/decode` | Serialisation |
| `noctalia.readFile/fileInfo` | Config, mtime polling |
| `noctalia.pluginDataDir()` | Converted-JSON cache, history |
| `noctalia.tr(key, subst)` | i18n |
| `noctalia.notify` / `noctalia.notifyError` | Alerts |
| `noctalia.togglePanel(id)` | Opening **this** plugin's own panel, from the bar widget |
| `ui.*` | Declarative tree |

Opening *another* panel goes through the shell, not the API:

| Command | Purpose |
|---|---|
| `noctalia msg panel-open <id> [context]` | `panel:` actions — idempotent |
| `noctalia msg panel-close <id>` | Closing on panel teardown |
| `noctalia msg plugins list` | Discovering installed plugins |
| `noctalia msg settings-open-plugin <id>` | Another plugin's settings |

`noctalia.togglePanel` is used for exactly one thing: the bar widget toggling this
plugin's *own* panel, where inverting is correct. For **any other** panel a card
uses `panel-open`, because inverting is wrong there — pressing a card twice must
bring the panel forward, not dismiss it. Every community plugin that opens another
plugin's panel made the same swap — see [D20](07-decisions.md).

Types: `noctalia.d.luau` from the official plugins repository.

### What is not in the API

Worth listing, because each one closes off a design that looks attractive until
you check:

| Missing | Consequence |
|---|---|
| PTY / stdin handle | No embedded terminal. `runInTerminal` delegates to a real window |
| Write path into `runStream` | Console cards are read-only tails |
| Process resize, raw mode | Nothing to feed a `vim` inside the panel |
| WebView / iframe / HTML | No embedding — not of a URL, not of another plugin's panel |
| `openPanel`, panel registry query | `togglePanel` only inverts; the shell has the rest |
| Cross-plugin data read | `state` is shared but has no discovery and no schema |
| Service pointers (`WeatherService*` and friends) | Shell services are C++ objects; a plugin cannot hold one |
| Per-widget colour overrides | `getColor(role)` gives theme roles, not the bar's per-widget layer |
| Manual layout (`measure` + `setPosition`) | Plugin trees are laid out by the reconciler; geometry converges, not matches |

These are closed, not deferred. The first four are why the API table above is the
whole surface. The panel-registry and cross-plugin rows are recorded in
[D20](07-decisions.md); the service-pointer, per-widget-colour and manual-layout
rows in [D21](07-decisions.md).

### The shell source is a reference, not a dependency

`noctalia-dev/noctalia` is public and MIT-licensed. Two directories are worth
knowing about, for opposite reasons:

| Path | Use |
|---|---|
| `src/shell/bar/widgets/` | **Look reference.** `weather_widget.cpp` is 219 lines of declarative node-tree construction with no custom painting. Read it as a spec for layout and palette |
| `src/system/`, `src/calendar/` | **Not portable.** Service objects and data fetches. A plugin cannot hold a `WeatherService*`, and does not need to — the data is public JSON |

The shell's widgets and plugin widgets render through the same reconciler
(`src/ui/ui_tree_reconciler.cpp`) and share `ui/builders.h`, `ui/palette.h` and
`ui/style.h`. That shared vocabulary is why a port is cheap. See
[D21](07-decisions.md).

`runInTerminal` is guarded by a feature check, following `tailscale` in
`community-plugins`:

```lua
if type(noctalia.runInTerminal) == "function" then
    noctalia.runInTerminal(cmd)
else
    noctalia.runAsync(cmd)
end
```

Actions go through the service, not straight from the panel: the panel is a pure
subscriber, and launching a process is a side effect that belongs behind the same
boundary as polling.

## UI primitives

Used by the panel: `column`, `row`, `scroll`, `box`, `label`, `glyph`, `image`,
`separator`, `spacer`, `progress`, `button`, `graph`.

Available but deliberately unused: `markdown` (the no-markup boundary,
[01](01-vision.md)); `input` / `select` / `toggle` / `slider` (the panel is
read-only in v1, and `select` is not even allowed in a persistent panel);
`dragSource` / `dropZone` (the deferred editor, [D9](07-decisions.md)).

Properties that matter for this layout:

- `ui.graph` — sparklines, values `0..1`, a second series via `values2`
- `ui.scroll` — panels only; skipped with a warning in the bar
- `ui.select` — not allowed inside a persistent panel
- `ui.box` is a **leaf** — it takes no children; a tooltip on a node that has
  content goes on the `row`/`column` that wraps it, which take one too
- `dragSource` / `dropZone` — edit mode, `plugin_api` 5+
- `key` on a node gives it stable identity across renders, which preserves search
  input text and hover state

## Manifest

```toml
id = "zumik3-del/hub"
name = "Hub"
version = "0.1.0"
plugin_api = 32
author = "zumik3-del"
license = "MIT"
icon = "gauge"
description = "Instrument panel: service status, metrics, releases and links from one YAML file."
tags = ["bar", "panel", "service", "indicator", "utility", "system"]
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

`placement = "attached"` with `open_near_click = true` is the github-kanban panel
behaviour ([D24](07-decisions.md)): the panel slides out beside the bar widget
that opened it, and `position = "auto"` lets the host choose the side from the
click. `dismiss_on_outside_click = true` makes it a popover; `esc` still closes it.

`width` and `height` take a number of pixels or the word `"fill"` — nothing
between. There is no percentage and no `"half"`. 860x620 is github-kanban's panel
size, taken as-is once the panel became a popover beside the widget rather than a
measured screen half; a different size means editing both numbers. `"fill"` is the
only relative form, and it means the whole screen.

`position` takes `auto`, `center`, `center_left`, `center_right`, `top_left`,
`top_right`, `bottom_left`, `bottom_right` — **with underscores**. `auto` is the
attached-panel default: the host picks the side from the click. The settings
schema spells
the same positions with dashes (`settings.plugins.panels.position` takes
`center-left`), and the two spellings are not interchangeable: the manifest wants
the underscore form. `position = "center-left"` parses, lints clean, and is
silently ignored — the panel opens centred, which is the default anyway, so
nothing looks wrong until someone asks for a side and does not get one.

There is no `persistent = true`, because Noctalia rejects it alongside exclusive
keyboard focus — see [D1](07-decisions.md).

The plugin directory is named `hub/`, after the second segment of `id`. Noctalia
resolves a plugin at `<source>/<segment>/` and reads its manifest from
`<source>/<segment>/plugin.toml`, so the directory is not free. A mismatch is
reported as `parse error: File could not be opened for reading` — a TOML error
that names no file, and which arrives *after* the catalog row listed the plugin
without complaint.

The bar widget's id in `settings.json` is `plugin:<plugin-id>:<widget-entry-id>`,
so `plugin:zumik3-del/hub:summary`. The plugin does not add its own widget to the
bar; a card that is absent from the bar is a user layout decision, not a plugin
bug, and a plugin that wrote `settings.json` would fight the bar's own editor.

### Host rules that the type definitions do not state

None of these are in `noctalia.d.luau`. All four were found by loading the plugin
into a running shell, and three of them pass `noctalia plugins lint` and an
offline harness unchanged.

| Rule | What it costs to get it wrong |
|---|---|
| `require` must be relative **and** end in `.luau` | `call to 'chunk' failed: require path must be relative and end in .luau` — no module named |
| A glyph name must exist in the host's font | Nothing. `ui.glyph` draws empty, the card keeps its title, and the only trace is one log line per redraw |
| `setText` / `setGlyph` / `setImage` are inert while a `render()` tree is active | A ticking clock cannot be patched into one label; the tree is rebuilt per tick |
| A bar widget cannot host `ui` controls | `ui.input`, `ui.select` and `ui.scroll` are skipped in the bar, silently |
| A manifest `position` is spelled with underscores | `position = "center-left"` is accepted, lints clean, and ignored — the panel opens centred |

The glyph vocabulary is
`/usr/share/noctalia/assets/fonts/noctalia-tabler.ttf` — 5941 names, a Tabler
subset that moves with the shell. The plugin does not carry a copy and does not
validate glyph names at load time: a baked list would be wrong after every host
update, and the API has no way to ask whether a name exists. The check belongs
next to the host, so it is `grep 'missing glyph' ~/.cache/noctalia/noctalia.log`
rather than code.

The third row is why `panel.setWantsSecondTicks(true)` costs a full rebuild every
second instead of one label update. That is the price of a declarative tree, and
it is the right trade at fourteen cards: the alternative is mixing the imperative
and declarative models inside one panel.



`capture_keys` lists only what the panel answers today. Capturing a key the panel
cannot honour takes it away from every other surface, so `return`, `/` and `?` are
added with the features behind them rather than reserved up front.

Manifest rules worth knowing, all enforced by `noctalia plugins lint`:

| Rule | Message |
|---|---|
| `persistent = true` needs `dismiss_on_outside_click = false` | rejected |
| `persistent = true` is incompatible with `keyboard_focus = "exclusive"` | rejected |
| `width`/`height` `"fill"` needs `placement = "floating"` | rejected |
| `capture_keys` needs `keyboard_focus` `on_demand` or `exclusive` | rejected |
| a declared setting that no entry reads | warning |

That last one is why `widget.luau` reads both `glyph` and `compact`: lint reports a
setting declared and never read, which is how a settings key that does nothing gets
shipped.

## Build order

1. **Skeleton** — `plugin.toml`, static zone list from the config, `widget.luau`.
   Goal: `noctalia plugins lint` passes and the panel opens. **Done.** `lint` is
   clean, `hub.skeleton.yaml` validates with zero errors, and the renderer covers
   all six kinds and all five states. What landed with it: `config.luau` split into
   an IO half and a pure half, `map` and `thresholds` in `map`-position, per-card
   staleness, the two-channel error model, and `r` as a refresh request.
2. **One source** — Proxmox via `noctalia.http`, with the full
   `fetch → extract → map → format` chain working. This is where `extract` and
   `ok_when` become real: both are jq over a payload, and neither has an
   implementation yet.
3. **Remaining source types** — `http`, `rss`, `stream`. **`command` and `static`
   are done**: `command` carries the first real card (an HTTPS reachability
   check through `curl`), because it needs no jq and reaches the LAN the panel is
   about. `extract` and `ok_when` land with `http`, not before.
4. **Thresholds, staleness, sparklines.**
5. **Hot reload.**
6. **Actions** — `link` and `run:` are drawn as trailing buttons and executed
   ([D26](07-decisions.md)); `link_template`, `deep_link` and `panel` are
   validated and carried but not drawn. The `updates` badge reuses `run` for its
   install button ([D28](07-decisions.md)).
7. **Console cards** — `stream` with a ring buffer, torn down on panel close.
8. **List cards** — `extract` widening to many, collapsed-to-count then expand.
9. **Card editor** — `dragSource`/`dropZone`, writing back to `hub.yaml`.
10. **Controls** — `control:` writes, `Controls` zone, arm-confirm, action log.

Steps 1–2 yield a working panel with one live source. Each source type after that is
an independent increment.

Actions come before the editor on purpose: the panel stops being a read-only
display one increment earlier, and that is a better time to find out whether the
click surface is comfortable than after the drag-and-drop layout work lands.

List cards are cheap — a poll like any other card, with rendering that changes only
when the card is selected — so they ride along with wherever the pipeline already
handles the source.

Controls come last and are not on the critical path at all. They are the only
feature in the project that can break something, so they are built once the layout
and the click surface have settled. See [D15](07-decisions.md).

Remote containers are not on this list either, because they are not a feature. A
service in an LXC is `command` plus `ssh` plus `pct exec` in one argv element, and
`parse: json` covers the JSON-emitting ones. No new plumbing — see
[D17](07-decisions.md).

## Verification

```bash
noctalia plugins lint hub/          # manifest vs code: settings, entries, panel rules
noctalia msg plugins list              # is the plugin installed and enabled
```

`lint` cross-checks declared settings against plugin code and enforces the panel
rules in the manifest table above. It exits 1 on an error-level problem, so it
belongs in a pre-commit hook.

Runtime verification is manual: editing `hub.yaml` must take effect without
restarting the shell. It does — the collector stats the config on its own tick,
because the host has no file-watch API and `state.watch` fires on a state write,
not on an edit.

`lint` is not enough, and it is worth being blunt about why. It reads the manifest
and greps the code; it never loads a module, never resolves a `require` and never
asks the host to draw anything. Four defects got past it and past an offline
harness that stubs `noctalia`: a `for` over an array used as an iterator, an
`isArray` where `isTable` was meant, a discarded return value that left secrets
unsubstituted, and a `require` path the host rejects. All four were caught in one
session against a running shell. Anything the host enforces at load time is
outside `lint`'s reach by construction, so the log is part of the test surface:

```bash
# the repo is loadable as a plugin source; a path source reads the working tree
# directly, so edits hot-reload and nothing is copied
noctalia msg plugins source add hub path "$PWD"
noctalia msg plugins enable zumik3-del/hub
noctalia msg panel-open zumik3-del/hub:panel

grep -E 'missing glyph|\[ERR\] \[luau\]|\[plugins\]' ~/.cache/noctalia/noctalia.log
```

`~/.cache/noctalia/noctalia.log` runs at DEBUG and is the only place the host
speaks. The load sequence of a healthy plugin is three lines —

```
[INF] [plugins] loaded plugin 'zumik3-del/hub' (3 entries) from …/hub
[INF] [plugin-service] started service 'zumik3-del/hub:collector'
```

— and after that, silence. Silence is the expected steady state: the collector
publishes only when a signature changes, so a healthy panel produces no log
traffic at all. A `path` source is also what makes the loop bearable: the watcher
the host installs on each entry re-runs the service on save, with no restart.


## What the skeleton does not render yet

The renderer is complete for all six kinds, and the pipeline is complete for
`static` sources. What is missing is the list at the bottom of `panel.luau`, which
records each gap against the build-order step that closes it. Three of them are
worth stating here, because they are API limits rather than unfinished work:

- **No flex wrap.** `plugin_api` 32 has no wrapping flex container, so zones stack
  vertically and the panel scrolls. [02](02-layout.md)'s side-by-side sketch is a
  picture of the idea, not of the layout.
- **No tabular figures.** `fontFamily` is the only typography control, and it needs
  a font loaded through `noctalia.loadFont` — a vendored asset, which is a [D21](07-decisions.md)
  decision rather than a rendering detail. Values are right-aligned instead.
- **No per-widget colour layer.** `barWidget.setColor` reads theme roles, not the
  bar's per-instance user overrides ([D21](07-decisions.md)), so the bar summary
  draws from the palette and nothing else.