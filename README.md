# noctalia_hub

An instrument panel for [Noctalia](https://noctalia.dev) v5 — a control centre
showing links, service status, metrics and release feeds on the left half of the
monitor.

> **Status: skeleton.** The plugin exists and opens; only `source: static` fetches.
> `http`, `command`, `stream` and `rss` are validated and report themselves as
> unbuilt. The panel renders every zone, every card kind and every card state, so
> what is missing is transport, not layout. See
> [docs/05-architecture.md](docs/05-architecture.md) for the build order.

## Idea

The panel opens on the left half of the monitor and reads like a spacecraft
instrument panel: zones grouped by domain, one instrument per row, colour meaning
state rather than decoration.

Where existing plugins cover a single concern — `bookmarks` is a link list,
`systempulse` is metrics, `rss-feeds` is feeds — this puts all of it on one
panel, configured by one file.

## Documents

| File | Subject |
|---|---|
| [docs/01-vision.md](docs/01-vision.md) | Problem, differentiation, scope boundaries |
| [docs/02-layout.md](docs/02-layout.md) | Layout A "instrument panel", zone flow rules |
| [docs/03-config.md](docs/03-config.md) | `hub.yaml` schema, `fetch → extract → map → format` |
| [docs/04-visual-language.md](docs/04-visual-language.md) | Colour, typography, density, motion |
| [docs/05-architecture.md](docs/05-architecture.md) | Three layers, service/UI split, Noctalia API |
| [docs/06-failure-modes.md](docs/06-failure-modes.md) | Source degradation, config errors, staleness |
| [docs/07-decisions.md](docs/07-decisions.md) | Decision log with rationale |

## Configuration

Lives outside the plugin code, in git, edited with any text editor:

```
~/.config/noctalia/hub/
├── hub.yaml              # main config — source of truth
├── hub.secrets.yaml      # tokens, mode 0600
└── README.md
```

Example: [config/hub.example.yaml](config/hub.example.yaml),
secrets: [config/hub.secrets.example.yaml](config/hub.secrets.example.yaml).

YAML rather than JSON, for comments, anchors when cards repeat (a fleet of LXC
containers), and readability under hand-editing. Rationale in
[docs/03-config.md](docs/03-config.md).

## Repository layout

```
noctalia_hub/
├── README.md
├── AGENTS.md              # agent guidance (not committed)
├── docs/                  # project decision
├── config/                # example configs
└── hub/                   # the plugin (Luau, plugin_api 32)
    ├── plugin.toml        # manifest: entries, settings, dependencies
    ├── config.luau        # read and validate hub.yaml
    ├── pipeline.luau      # fetch → extract → map → format
    ├── service.luau       # collector: polls, publishes into noctalia.state
    ├── panel.luau         # panel, a pure subscriber
    ├── widget.luau        # compact bar summary
    └── translations/      # en.json
```

Three layers, one direction. `service.luau` talks to the world and publishes into
`noctalia.state`; `panel.luau` and `widget.luau` read that state and nothing else.
There is no shared Lua memory between entry points, so state is the whole channel.

## Running it

```bash
noctalia plugins lint hub/          # manifest vs code

cp config/hub.skeleton.yaml ~/.config/noctalia/hub/hub.yaml
```

`hub.skeleton.yaml` is the config this build renders end to end — every card uses
`source: { type: static }`, so it needs no network, no shell and no container.
`config/hub.example.yaml` is the real thing, with all five source types; on the
skeleton build each of its cards reports itself as unbuilt rather than showing
nothing.

Requires `yq` at runtime, for the one-time YAML→JSON conversion
([D2](docs/07-decisions.md)).

## Compatibility

Targets Noctalia **v5.2+** (native C++, Luau plugins, `plugin_api` 32). The QML
plugins of v4 do not run here, so code targets Luau with declarative UI via
`ui.*`.

## Licence

MIT