# 03 — Config

## Format: why YAML

| | YAML | JSON |
|---|---|---|
| Comments | yes | no |
| Readability | no braces | noisy braces |
| Repetition | **anchors and aliases** | copy-paste |
| Multi-line commands | `\|` and `>` | `\n` |
| Key order | preserved | not guaranteed |
| Parsing in-plugin | needs a converter | native `noctalia.json.decode` |

Anchors are the deciding argument. With thirty identical LXC containers:

```yaml
cards:
  - <<: *lxc
    id: plex
    title: Plex
  - <<: *lxc
    id: sonarr
    title: Sonarr
```

The cost is a converter. That is handled by an existing mechanism: declare
`dependencies = ["yq"]` in the manifest, and the service converts YAML→JSON **once**
at load, caching the result and reconverting only when mtime changes. The runtime
price of YAML is zero.

Note the two YAML-level requirements that come with anchors:

- an anchor must be **defined before it is referenced**, so a templates block sits
  above `domains`, not below it
- a merge key (`<<:`) accepts explicit sibling keys alongside the merged ones

## Location

```
~/.config/noctalia/hub/
├── hub.yaml              # main config — source of truth
├── hub.secrets.yaml      # tokens, mode 0600
└── README.md
```

`hub.yaml` is user-owned and committed to git. The plugin only ever reads it.

## The data pipeline

The central decision of the schema: **one path for every card**, regardless of
source.

```
fetch  →  extract  →  map  →  format
```

A single `source` block for all of them. `kind` determines rendering, the renderer
is shared. This removes per-source branches ("for http", "for command") and stops
the schema drifting into six mutually incompatible ways to extract a value.

- `fetch` — obtain raw data
- `extract` — collapse the payload into one value
- `map` — translate that value into a semantic state (`ok` / `warn` / `down`)
- `format` — render the value as text

## Full schema

```yaml
version: 1

layout:
  density: compact          # compact | comfortable
  show_header: true
  clock: "%H:%M:%S"
  stale_badge: true

defaults:
  interval_sec: 60
  timeout_ms: 8000
  stale_after_sec: 300
  graph_points: 48

domains:
  - id: infra
    title: Infrastructure
    glyph: server
    refresh: 30             # overrides defaults for this zone

    cards:
      - id: dynacat
        title: Dynacat
        glyph: cat
        kind: status
        link: https://dynacat.lan
        source:
          type: http
          url: https://dynacat.lan/health
          ok_when: "status == 200"

      - id: proxmox-nodes
        title: Proxmox
        glyph: hexagon
        kind: metric
        source:
          type: http
          url: https://pve.lan:8006/api2/json/cluster/resources
          auth: { token: "${proxmox_token}" }
          extract: "length"
        format: "{n} nodes"
        thresholds: { warn: 6, critical: 8 }
        graph: true

  - id: releases
    title: Releases
    glyph: tag
    cards:
      - id: opencode
        title: OpenCode
        kind: release
        source:
          type: rss
          url: https://github.com/zumik3-del/opencode/releases.atom
          pick: first
        link_template: "https://github.com/zumik3-del/opencode/releases/tag/{tag}"

  - id: git
    title: Watching
    glyph: git-branch
    cards:
      - id: opencode-ci
        title: opencode
        kind: status
        source:
          type: command
          argv: ["gh", "run", "list", "--limit", "1",
                 "--json", "conclusion", "-q", ".[0].conclusion"]
        map:
          success: ok
          failure: down
          cancelled: warn
        stale_after_sec: 900
```

## Card fields

### Identity and kind

| Field | Required | Description |
|---|---|---|
| `id` | yes | Stable key; state and interval are tracked per id |
| `title` | yes | Name shown in the instrument row |
| `glyph` | no | Tabler glyph; falls back to a default per `kind` |
| `kind` | yes | Rendering only: `status` \| `metric` \| `release` \| `link` \| `graph` \| `text` \| `console` |
| `span` | no | `1` or `2` — how many cells the card occupies in the flow |
| `hidden` | no | `true` keeps the card in the config without rendering it |

### Data

| Field | Description |
|---|---|
| `source.type` | `http` \| `command` \| `stream` \| `rss` \| `static` |
| `interval_sec` | Poll period; inherited from `defaults` |
| `timeout_ms` | Timeout; defaults to 8000 |
| `stale_after_sec` | Age at which the card dims |
| `retries` | Retry count on failure |

### Presentation

| Field | Description |
|---|---|
| `thresholds` | `{ warn: N, critical: N }` — where colour turns amber, then red |
| `format` | Substitution template, e.g. `"{n} nodes"` |
| `unit` | Suffix: `"%"`, `"ms"`, `"MB"` |
| `graph` | `true` / a point count / `false` |

## Actions

A card can do something on click. **At most one action per card**, drawn from:

| Field | Kind | Effect |
|---|---|---|
| `link` | string | Open a URL |
| `link_template` | string | Open a URL built from extracted fields |
| `deep_link` | string | Open a URL built from the source's own query plus extracted fields |
| `run` | string | Run a shell command in the user's terminal |
| `control` | block | Write to a remote system |

The first four navigate or launch. `control` is the only one that changes
something, and it is the only one that takes a block rather than a string. See
[D15](07-decisions.md).

Two actions on one card is a validation error, not a silent precedence rule. A card
whose click target is ambiguous is a card nobody trusts. `control` is in this list
for exactly that reason — a card with both a `link` and a `control` would be a
card that does two different things on the same click.

### control — a flag, not a kind

A card that can write does not become a different kind of card. `kind` keeps its
single meaning, "how to draw the reading", exactly as [D4](07-decisions.md)
established. What the card *does* is an orthogonal axis, like `thresholds`:

```yaml
- id: plex
  title: Plex
  glyph: server
  kind: status                    # unchanged — this is still a status reading
  source:
    type: http
    url: https://pve.lan:8006/api2/json/nodes/pve/status/104/status
    auth: { token: "${proxmox_token}" }
    extract: ".status"
  map:
    running: ok
    stopped: warn
  control:
    type: http
    url: https://pve.lan:8006/api2/json/nodes/pve/status/104/status/reboot
    method: POST
    auth: { token: "${proxmox_token}" }
    expect: '"code == 0"'
  confirm:
    target: "plex @ pve.lan"
    effect: "LXC restart"
```

The row renders exactly as it would without `control:` — glyph, title, value, state,
age. Only what Enter does changes. The renderer gains no new branch.

This is what keeps the control honest: the card shows the state of the thing you
are about to change. A button labelled "restart plex" on its own does not tell you
whether plex is currently running, which is exactly the information you need before
pressing it.

`confirm` is required whenever `control` is present. `control` and `run` are not
interchangeable despite both "running a command": `run` executes a local string
that the config author typed, `control` writes to a system the panel does not own.
They carry different risk and get different confirmation rules.

Controls belong in a `Controls` zone. That is where the separation happens — not
in the card kind, which is what makes it possible for one card to be both the
reading and the thing you act on.

### deep_link — the metric and its target are one fact

When a card counts something, the click target should be *the same thing*. Writing
the query twice is how a config rots:

```yaml
# two strings that must stay in sync, expressing one fact
query: "tags:_error date:>=today"                    # for the count
link: "https://ops.lan/#Search?result=error&date=today"   # for the click
```

Worse, the two vocabularies are rarely the same strings. xyOps, for example,
takes `tags:_error` on its REST API and `result=error` in its UI — a mapping that
is xyOps-internal knowledge and quietly wrong the moment xyOps changes.

`deep_link` removes the duplication by exposing the source's own `query`:

```yaml
- id: xyops-failed
  title: xyOps failed
  glyph: alert-circle
  kind: metric
  source:
    type: http
    url: https://ops.lan/api/app/search_jobs/v1
    headers: ["X-API-Key: ${xyops_key}"]
    query: "tags:_error date:>=today"
    limit: 1
    extract: ".list.length"
  thresholds: { warn: 1, critical: 5 }
  deep_link: "https://ops.lan/#Search?result=error&date=today"
```

Placeholders available inside `deep_link`:

| Placeholder | Expands to |
|---|---|
| `{query}` | the source's `query`, percent-encoded |
| `{url}` | the source's `url` |
| `{n}` and any other extracted field | the extracted value |

**`{query}` is URL-encoded by the plugin.** A real query like
`tags:_error date:>=today` contains a space and a `>`, neither of which is legal
unencoded. Encoding is the plugin's job — a user who has to percent-encode a
query by hand stops writing queries.

This is deliberately generic, not an xyOps feature. Any REST source with a web UI
and a query language gets the same benefit; see
[an xyOps card](../config/hub.example.yaml) for a worked one.

### A worked example: counting failed jobs

The full round trip, because it is the shape most real cards want:

```yaml
- id: xyops-failed
  title: xyOps failed
  kind: metric
  source:
    type: http
    method: GET
    url: https://ops.lan/api/app/search_jobs/v1
    headers: ["X-API-Key: ${xyops_key}"]
    query: "tags:_error date:>=today"
    limit: 1                      # fetch one row, read the count from list.length
    extract: ".list.length"
  thresholds: { warn: 1, critical: 5 }
  deep_link: "https://ops.lan/#Search?result=error&date=today"
```

`limit: 1` with the count read from the response metadata is the difference
between one number and a page of job records. When a REST API returns a total
alongside the rows, ask for the rows you need and take the total from the header
field.

**A caveat about deep links in general.** UI URLs are an application's private
business. xyOps documents its REST API thoroughly and documents its `#Page?args`
URL scheme not at all — the scheme above was read out of its source. It works, and
it may change without notice. A `deep_link` that stops resolving shows an
ordinary page, never an error, so a stale one is invisible until you notice you
landed somewhere unexpected.


```yaml
- id: pve-ssh
  title: pve.lan
  glyph: ssh
  kind: status
  run: "ssh root@pve.lan"
  source:
    type: command
    argv: ["systemctl", "is-active", "pveproxy"]

- id: grafana-logs
  title: grafana journal
  kind: console
  source:
    type: stream
    cmd: "journalctl -u grafana -f -o cat --no-pager"
    lines: 12
```

### run — what it actually does

```lua
noctalia.runInTerminal("ssh root@pve.lan")
```

This opens a **separate terminal window**, it does not embed one. The panel stays
visible behind it.

`run` is a plain string, not an argv list, and it is passed through untouched. The
config is written by the user in their own home directory, so it is trusted input
and needs no quoting. Chaining and redirection work:

```yaml
run: "ssh root@pve.lan 'journalctl -u pveproxy -f -n 20'"
```

`run` **does not interpolate source values.** No `{host}`, no `${secret}`. A value
that came from an HTTP response is not your own typing, and a command line built
from it is an injection hole. If a card needs a discovered hostname in its
command, that is a separate decision with its own escaping rules, not a free-text
template.

On a shell without `runInTerminal` the action falls back to `runAsync` and the
header shows a warning that no terminal window will appear.

### No embedded terminal

Worth being explicit, because it is the obvious thing to want:

```lua
runAsync:  (cmdOrArgv, onResult?, timeoutMs?) -> boolean
runStream: (cmd, onLine) -> boolean
runInTerminal: (cmd: string) -> boolean
```

`CommandResult` is `{ exitCode, stdout, stderr, timedOut, stdoutTruncated,
stderrTruncated }`. There is no stdin handle, no resize, no raw mode, no way to
write a keystroke back into a running process. A real terminal emulator needs a
PTY, and `plugin_api` 32 exposes none.

So there is no `kind: terminal` that renders a shell inside the panel, and adding
one is not a matter of effort — it needs a host-side PTY API that does not exist.
What exists is the console card.

### kind: console

The closest thing to a terminal inside the panel: a long-lived process whose output
streams into the card.

```yaml
- id: nginx-tail
  title: nginx
  kind: console
  source:
    type: stream
    cmd: "journalctl -u nginx -f -o cat"
    pick: last
    lines: 12
```

`runStream` is one-way — stdout lines in, nothing back out. The card is a read-only
tail, with a ring buffer of the last `lines` entries. Precedent in
`community-plugins/processes`, which pipes a helper's output through
`noctalia.runStream` and re-reads its state through a temp file.

A console card holds a process open. It should therefore declare a longer
`stale_after_sec` than a polling card, and closing the panel should tear the stream
down rather than leave orphaned readers behind.

## Domain fields

| Field | Description |
|---|---|
| `id` | Stable key |
| `title` | Header text |
| `glyph` | Header glyph |
| `refresh` | Overrides `defaults.interval_sec` for this zone |
| `stale_after_sec` | Overrides the default for this zone |
| `cards` | Ordered list; order is the visual order, there is no `row`/`column` |

## Source types

### http

```yaml
source:
  type: http
  url: https://api.example.com/status
  method: GET              # defaults to GET
  headers: ["Authorization: Bearer ${api_token}"]
  auth: { token: "${proxmox_token}" }
  body: ""
  follow_redirects: true
  allow_insecure_tls: false
  query: "scope=all&since=24h"   # appended to the URL, percent-encoded by the plugin
  limit: 1                       # ask the server for fewer rows
  select: ["id", "code"]         # request only these fields, where supported
  extract: ".data | length"
```

`query` is a convenience for APIs that take query-string parameters. It is
URL-encoded for you, so write `&` and spaces normally. `extract` is applied to the
parsed response body.

**When an API returns a total alongside its rows, use it.** Most REST search
endpoints return both the page of records and the overall match count in a
metadata field. Request `limit: 1` and read the count from that field — a card
that wants one number should not transfer a page of records every thirty seconds
to compute it. xyOps, Proxmox and GitHub all do this.


### command

Executed directly, no shell:

```yaml
source:
  type: command
  argv: ["systemctl", "is-active", "nginx"]
```

Or as a shell string:

```yaml
source:
  type: command
  cmd: "docker ps --format '{{.Status}}' | head -1"
```

### stream

Long-lived, not restarted per tick — feeds and `journalctl -f`:

```yaml
source:
  type: stream
  cmd: "journalctl -u nginx -f -o cat"
  pick: last               # first | last
  lines: 12                # ring buffer size, for kind: console
```

### rss

```yaml
source:
  type: rss
  url: https://github.com/zumik3-del/opencode/releases.atom
  pick: first
  tag: title
```

### static

No source; for headers and hints:

```yaml
source:
  type: static
  value: "—"
```

## YAML anchors for repeated cards

Anchors are a plain YAML feature, not part of the schema — nothing new to
implement. Define the shared body once, above `domains`:

```yaml
x-templates:
  lxc: &lxc
    kind: status
    source:
      type: http
      url: https://pve.lan:8006/api2/json/nodes/pve/status
      auth: { token: "${proxmox_token}" }
      ok_when: "status == 'running'"

domains:
  - id: infra
    title: Infrastructure
    cards:
      - <<: *lxc
        id: plex
        title: Plex
      - <<: *lxc
        id: sonarr
        title: Sonarr
```

Two constraints:

- the anchor must be defined before it is referenced, so `x-templates` goes above
  `domains`
- a top-level key the schema does not know is ignored after expansion, so
  `x-templates` never reaches the data model

Because the anchor only expands to ordinary card fields, a card using one is
indistinguishable from a card written out in full. That is the point: repetition is
an authoring convenience, not a runtime concept.

## Deliberately absent

**`row` / `column` positioning.** Order in the YAML is the order. Hand-tuned
coordinates are a source of pain when editing, and drag-and-drop in the panel is
needed anyway.

**Free-form `color`.** Colour is semantic only: `ok` / `warn` / `down` / `stale`.
A free colour turns an instrument panel into a Christmas tree.

**`priority`.** `span: 1|2` covers it without a priority system.

**Inline secrets.** Only `${name}` references into `hub.secrets.yaml`.

## Secrets

```yaml
# hub.secrets.yaml — mode 0600, never committed
proxmox_token: "eyJhbGciOi..."
github_token: "ghp_..."
grafana_token: "glsa_..."
```

Referenced from `hub.yaml` as `${proxmox_token}`.

**Quote the substitution.** Inside a flow mapping an unquoted value starting with
`$` contains `{`, which YAML reads as the start of a nested mapping:

```yaml
auth: { token: ${proxmox_token} }     # parse error
auth: { token: "${proxmox_token}" }   # correct
```

The alternative — `${ENV_VAR}` read from the environment — needs a correctly
configured user unit for autostart and is fragile. The file is more dependable.

## Hot reload

The service polls the config mtime. On change it re-reads, rebuilds the zone tree,
and preserves scroll position and selection. A reload indicator flashes in the
header.

`hub.secrets.yaml` is re-read on each reload, so rotating a token does not require
restarting the shell.