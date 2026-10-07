# noctalia_hub

An instrument panel for [Noctalia](https://noctalia.dev) v5 — a full-screen control
centre showing links, service status, metrics and release feeds.

> **Status: concept.** No plugin implementation yet. This repository holds the
> project decision: config schema, API surface, visual rules and layout.

## Idea

The panel opens full-screen and reads like a spacecraft instrument panel: zones
grouped by domain, one instrument per row, colour meaning state rather than
decoration. No scrolling to find a number you came to read.

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
└── plugin/                # future plugin code (Luau)
    └── plugin.toml
```

## Compatibility

Targets Noctalia **v5.2+** (native C++, Luau plugins, `plugin_api` 32). The QML
plugins of v4 do not run here, so code targets Luau with declarative UI via
`ui.*`.

## Licence

MIT