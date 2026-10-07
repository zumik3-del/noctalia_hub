# 05 — Architecture

## Three layers

```
plugin/
├── plugin.toml          # manifest: plugin_api 32, dependencies, settings
├── service.luau         # background: collect data → noctalia.state
├── panel.luau           # full-screen panel, pure subscriber
├── widget.luau          # compact bar summary
├── desktop_widget.luau  # optional desktop surface
├── config.luau          # load and validate hub.yaml
├── pipeline.luau        # fetch → extract → map → format
├── sources/             # source type implementations
└── translations/en.json
```

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
```

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
| `noctalia.togglePanel(id)` | Opening the panel |
| `ui.*` | Declarative tree |

Types: `noctalia.d.luau` from the official plugins repository.

### What is not in the API

Worth listing, because each one closes off a design that looks attractive until
you check:

| Missing | Consequence |
|---|---|
| PTY / stdin handle | No embedded terminal. `runInTerminal` delegates to a real window |
| Write path into `runStream` | Console cards are read-only tails |
| Process resize, raw mode | Nothing to feed a `vim` inside the panel |

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

Used: `column`, `row`, `scroll`, `box`, `label`, `glyph`, `image`, `separator`,
`spacer`, `progress`, `button`, `graph`, `input`, `select`, `toggle`, `slider`,
`dragSource`, `dropZone`, `markdown`.

Properties that matter for this layout:

- `ui.graph` — sparklines, values `0..1`, a second series via `values2`
- `ui.scroll` — panels only; skipped with a warning in the bar
- `ui.select` — not allowed inside a persistent panel
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
description = "Full-screen instrument panel: service status, metrics, releases and links from one YAML file."
tags = ["bar", "panel", "service", "indicator", "utility", "system"]
dependencies = ["yq"]

[[widget]]
id = "summary"
entry = "widget.luau"

[[panel]]
id = "panel"
entry = "panel.luau"
width = "fill"
height = "fill"
placement = "floating"
position = "center"
persistent = true
keyboard_focus = "exclusive"
capture_keys = ["escape", "return", "r", "slash", "question"]
```

The full-screen panel is a supported case rather than a hack: v5 handles
`width`/`height` `"fill"`, `persistent`, `keyboard_focus` and `capture_keys`.

`return` is captured because it activates the focused card — otherwise `run:` and
`link:` would only be reachable with a mouse, and the panel is keyboard-first.

## Build order

1. **Skeleton** — `plugin.toml`, static zone list from the config, `widget.luau`.
   Goal: `noctalia plugins lint` passes and the panel opens.
2. **One source** — Proxmox via `noctalia.http`, with the full
   `fetch → extract → map → format` chain working.
3. **Remaining source types** — `command`, `rss`, `stream`, `static`.
4. **Thresholds, staleness, sparklines.**
5. **Hot reload.**
6. **Actions** — `link`, `link_template`, `run:` via `runInTerminal`.
7. **Console cards** — `stream` with a ring buffer, torn down on panel close.
8. **Card editor** — `dragSource`/`dropZone`, writing back to `hub.yaml`.

Steps 1–2 yield a working panel with one live source. Each source type after that is
an independent increment.

Actions come before the editor on purpose: the panel stops being a read-only
display one increment earlier, and that is a better time to find out whether the
click surface is comfortable than after the drag-and-drop layout work lands.

Writing to remote systems is not on this list. It is a separate capability with
its own confirmation and logging requirements — see D14.

## Verification

```bash
noctalia plugins lint plugin/
noctalia msg plugins list
```

`lint` cross-checks declared settings against plugin code. Runtime verification is
manual: editing `hub.yaml` must take effect without restarting the shell.