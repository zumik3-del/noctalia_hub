# 03 — Config

## Why YAML

Comments, anchors for repeated cards, readability under hand-editing. The cost is a
converter: the manifest declares `dependencies = ["yq"]`, and the service converts
YAML→JSON **once** at load, caching the result and reconverting only when mtime changes
([D2](07-decisions.md)). An anchor must be **defined before it is referenced**, so a
templates block sits above `domains`.

## Location

```
~/.config/noctalia/hub/
├── hub.yaml              # main config — source of truth
├── hub.secrets.yaml      # tokens, mode 0600
└── README.md
```

`hub.yaml` is user-owned and committed to git; the plugin only ever reads it.

## The pipeline

One path for every card, regardless of source:

```
fetch  →  extract  →  map  →  format
```

- `fetch` — obtain raw data
- `extract` — collapse the payload into one value (or many, for `list`)
- `map` — translate that value into a semantic state (`ok` / `warn` / `down`)
- `format` — render the value as text

A single `source` block serves all of them; `kind` affects rendering only. This removes
per-source branches and stops the schema drifting into six mutually incompatible ways to
extract a value ([D4](07-decisions.md)).

## Full schema

```yaml
version: 1

layout:
  density: compact          # compact | standard | comfortable
  show_header: true
  stale_badge: true
  font_scale: 100           # 80..130, % applied to every text size
  card_radius: 9            # 0..24 px
  card_spacing: 8           # 0..32 px
  card_border: subtle       # none | subtle | accent
  card_background: tinted   # transparent | tinted | solid
  hover_effect: background  # none | background | border

defaults:
  interval_sec: 60
  timeout_ms: 8000
  stale_after_sec: 300
  graph_points: 48

domains:
  - id: infra
    title: Infrastructure
    glyph: server
    interval_sec: 30        # overrides defaults for this zone
    cards:
      - id: dynacat
        title: Dynacat
        glyph: cat
        kind: status
        link: https://dynacat.home.lan
        source:
          type: http
          url: https://dynacat.home.lan/health
          ok_when: "status == 200"

      - id: proxmox-nodes
        title: Proxmox
        glyph: hexagon
        kind: metric
        source:
          type: http
          url: https://pve.home.lan:8006/api2/json/cluster/resources
          auth: { token: "${proxmox_token}" }
          # /cluster/resources returns nodes AND guests. The label says nodes, so
          # count nodes — a bare `length` counts every VM and LXC too.
          extract: ".data | map(select(.type == \"node\")) | length"
        format: "{n} nodes"
        thresholds: { warn: 6, critical: 8 }
        graph: true
```

## Layout fields

| Field | Default | Description |
|---|---|---|
| `density` | `compact` | `compact` / `standard` / `comfortable` — base row height, padding, type size |
| `font_scale` | `100` | `80`–`130`. Multiplier applied to every text size |
| `card_radius` | `9` | `0`–`24` px corner rounding of a card block |
| `card_spacing` | `8` | `0`–`32` px gap between cards in a zone |
| `card_border` | `subtle` | `none` / `subtle` / `accent` |
| `card_background` | `tinted` | `transparent` / `tinted` / `solid`; always a theme role |
| `hover_effect` | `background` | `none` / `background` / `border` — one response, never two |
| `show_header` | `true` | Accepted and validated, **not yet honoured** (the header always draws) |
| `stale_badge` | `true` | Accepted and validated, **not yet honoured** (the age line always draws) |

None of these names a colour: shape and density are config, colour is the palette
([04](04-visual-language.md) §1).

## Card fields

### Identity and kind

| Field | Required | Description |
|---|---|---|
| `id` | yes | Stable key; state and interval are tracked per id |
| `title` | yes | Name shown in the instrument row |
| `glyph` | no | Tabler glyph; falls back to a default per `kind` |
| `kind` | yes | `status` \| `metric` \| `release` \| `link` \| `console` \| `list` |
| `span` | no | `1` or `2` — cells the card occupies (validated, not drawn) |
| `description` | no | One line of prose |
| `hidden` | no | `true` keeps the card in the config without rendering it |

The six kinds are a **closed set** ([D22](07-decisions.md)). `graph` is a presentation
field on any card, not a kind; a plain string reading is `status`.

#### description

The card's **second line**. A failure does not take it: the reason a card is not ok — a
source error, a config error, or the age of a stale reading — is shown on the **state
marker's tooltip** ([D25](07-decisions.md), [06](06-failure-modes.md)).

### Data

| Field | Description |
|---|---|
| `source.type` | `http` \| `command` \| `stream` \| `rss` \| `static` |
| `source.ok_when` | Predicate over the parsed response; false ⇒ `down` |
| `source.extract` | jq expression collapsing the payload into a value (or many) |
| `source.parse` | `json` \| `stdout` \| `stderr` — how command output is read |
| `map` | Extracted value ⇒ state, e.g. `{ 0: ok, 1: down }` |
| `interval_sec` | Poll period; inherited from the zone, which inherits `defaults` |
| `timeout_ms` | Timeout; defaults to 8000 (there is no zone-level override) |
| `stale_after_sec` | Age at which the card dims; inherited from the zone, default 300 |
| `retries` | Retry count on failure (validated, not yet acted on) |

**A value the `map` does not list is `down`, with the value shown.** A `map` is an
exhaustive statement about what the values mean, so an unexpected one is the service
having changed shape under the config — worth a red dot and the value that caused it.

`ok_when` and `map` answer different questions. `ok_when` is a predicate over the
**parsed response**, evaluated at fetch time (its bare identifiers are the response's
top-level fields, so `ok_when: "status == 'running'"` matches `{"status": "running"}`).
`map` runs later, on the **extracted value**, and translates it into a state. A card
carrying both is legal, and `map` wins — a value the author named explicitly is the more
specific instruction.

**`map` keys accept numbers unquoted.** `0: ok` and `"0": ok` are the same key; JSON
cannot tell them apart on the way back in. A card whose value is a string is matched on
that string.

### Presentation

| Field | Description |
|---|---|
| `thresholds` | `{ warn: N, critical: N }` — where colour turns amber, then red |
| `format` | Substitution template, e.g. `"{n} nodes"` |
| `unit` | Suffix: `"%"`, `"ms"`, `"MB"` |
| `graph` | `true` / a point count / `false` |
| `mini_cards` | The card's own second row of facts (see below) |

`format` placeholders are plain field names: `{n}` for the extracted value, plus any key
of a mapping value and, on a `list` card, the count. `{n.status}` does not substitute
and stays in the output as written — a template that quietly rendered half of itself is
worse than one that looks broken. A placeholder with nothing to put in it stays visible:
`"{n} nodes"` with no value renders as `{n} nodes`, not ` nodes`. `format`, `unit` and
`row_format` must be non-empty strings; a wrong type is a config error, not a field
dropped in silence.

`thresholds` must have `warn` below `critical`.

**`kind: status` draws only its dot** ([D27](07-decisions.md)): the value column is not
rendered, and `format` / `unit` have no effect. Metric, release, link, console and list
cards still show their reading.

#### mini_cards

A card's own second row of facts: small tinted tiles on the trailing edge, left of the
update badge. A tile is **static** (`{ label, value, unit?, link? }`) or **dynamic**
(`{ label, source, unit?, thresholds?, interval_sec?, link? }`).

A dynamic tile carries a full `source` — the same block a card carries — and the
collector fetches it on its own interval (3600 by default) and colours it by the
thresholds. Before the first fetch it shows `—`; a failed fetch keeps the last good value
with the reason on the tooltip. A tile speaks in colour **only when something is wrong**:
`warn` and `down` take the state colour, everything else — including the `ok` a
threshold produces — is neutral. A tile's `label` is drawn upper-case.

A tile carrying `link` is a button: clicking it opens the URL the same way a card's own
link button does ([D26](07-decisions.md)). See [D30](07-decisions.md).

### updates — a second reading on the card

One extra reading about the host: how many OS packages are waiting. It draws as a badge
before the state dot, silent when there is nothing to say. A count is a button: pressing
it runs the install command in a terminal. A check that could not run is a dim red glyph
whose tooltip carries the reason. The badge never changes the card's own dot and is not
counted in the header's error total ([D28](07-decisions.md)).

```yaml
- id: pihole
  title: Pi-hole
  kind: status
  description: DNS filtering and ad blocking
  source:
    type: command
    argv: ["curl", "-k", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "3", "https://dns.home.lan/admin/"]
  updates:
    source:
      type: command
      argv: ["ssh", "proxmox", "pct exec 100 -- sh -c 'apt-get update -qq >/dev/null || exit 1; apt-get -s -q upgrade | grep -c ^Inst || true'"]
    interval_sec: 3600
    run: "ssh -t proxmox 'pct exec 100 -- sh -c \"apt-get update && apt-get -y upgrade\"'"
```

| Field | Required | Description |
|---|---|---|
| `source` | yes | A source that prints the count as a number; `command` in this build |
| `run` | no | The install command the count button runs; without it the count is read-only |
| `interval_sec` | no | Poll period; default `3600` — a package check is not asked at the card's cadence |
| `timeout_ms` | no | Timeout; default `defaults.timeout_ms` |
| `format` | no | Template for the badge text; `{n}` is the count |

**The check prints a number, and anything else is `down`.** stdout is text, read as a
number; a non-number is a failure with the bytes quoted, never a zero the badge would
draw as "all clear". `0` is `ok` and draws nothing; `1`+ is `warn` and draws the button.

**The distribution is the config author's, not the plugin's.** Debian is `apt-get`,
Alpine is `apk`; there is no `family:` field ([D17](07-decisions.md)). The two canonical
checks:

```yaml
# Debian / Ubuntu
argv: ["ssh", "proxmox", "pct exec 100 -- sh -c 'apt-get update -qq >/dev/null || exit 1; apt-get -s -q upgrade | grep -c ^Inst || true'"]
# Alpine
argv: ["ssh", "proxmox", "pct exec 116 -- sh -c 'apk update -q >/dev/null 2>&1 || exit 1; apk version -l \"<\" | grep -c \"<\" || true'"]
```

Three details are load-bearing: **`sh -c`, not `sh -lc`** (a login shell's MOTD lands in
stdout, where the count cannot tell it from an answer); **`|| true` after `grep -c`** (it
exits `1` on a zero count, which would read as a failed check); **Alpine counts `<`
markers, not lines** (`apk version -l '<'` prints a header, so `wc -l` is off by one). A
bare host answers the same way without the `pct` hop.

## Actions

An action is a **button on the card's trailing edge**, not a hit area over the whole
card, so a card may carry more than one ([D26](07-decisions.md)).

| Field | Drawn as | Effect |
|---|---|---|
| `link` | link button | Open a URL in the browser |
| `run` | terminal button | Run a shell command in the user's terminal |
| `link_template` | — | Open a URL built from extracted fields (not drawn yet) |
| `deep_link` | — | Open a URL built from the source's `query` plus extracted fields (not drawn yet) |
| `panel` | — | Open another Noctalia panel (not drawn yet) |
| `control` | — | Write to a remote system — deferred ([D15](07-decisions.md)) |

Only `link` and `run` are drawn in this build; the other four are validated and carried,
and become buttons when their step lands. `control` is the one action that changes
something and must not share a card with another.

`link` opens the browser and nothing else. `run` opens a **separate terminal window**
(`runInTerminal`) — it does not embed one — and is a plain string passed through
untouched, with **no interpolation** of source values (an HTTP-derived hostname is not
your own typing; a command line built from it is an injection hole,
[D12](07-decisions.md)). On a shell without `runInTerminal` it falls back to `runAsync`.

### panel — open another Noctalia surface

```yaml
- id: go-calendar
  title: Calendar
  glyph: calendar
  kind: link
  source: { type: static, value: "—" }
  panel: "control-center calendar"
```

That runs `noctalia msg panel-open control-center calendar`. **Use `panel-open`, not
`noctalia.togglePanel`** — toggling inverts, which is right for a bar widget opening its
*own* panel and wrong for a card opening someone else's ([D20](07-decisions.md)).

Panels are built-ins (`launcher`, `control-center`, `clipboard`, `polkit`, `session`,
`tray-drawer`, `wallpaper`) or another plugin's `author/plugin:panel`. There is no
standalone `calendar` or `weather` panel — both are control-center sections reached
through the context argument (`"control-center calendar"`). The **id is validated** at
load time (a typo is reported on the card); the **context is not** — a bad context exits
`0` and does nothing ([06](06-failure-modes.md)).

### control — a flag, not a kind

A card that can write does not become a different kind. `kind` keeps its single meaning;
what the card *does* is an orthogonal axis, like `thresholds`:

```yaml
- id: pocketbase
  title: Pocketbase
  glyph: server
  kind: status
  source: { type: http, url: "…/lxc/104/status/current", extract: ".status" }
  map: { running: ok, stopped: warn }
  control:
    type: http
    url: "…/lxc/104/status/reboot"
    method: POST
    expect: '"code == 0"'
  confirm:
    target: "pocketbase @ pve.home.lan"
    effect: "LXC restart"
```

The row renders exactly as without `control:` — only what Enter does changes. This is
what keeps the control honest: the card shows the state of the thing you are about to
change. `confirm` is required whenever `control` is present, and names the target.
`control` and `run` are not interchangeable: `run` executes a local string the author
typed, `control` writes to a system the panel does not own. Controls belong in a
`Controls` zone.

### deep_link — the metric and its target are one fact

Writing the criterion twice is how a config rots, and the two copies are rarely the same
string (xyOps takes `tags:_error` on its API and `result=error` in its UI). `deep_link`
removes the duplication by exposing the source's own `query`:

```yaml
- id: xyops-failed
  title: xyOps failed
  glyph: alert-circle
  kind: metric
  source:
    type: http
    url: https://ops.home.lan/api/app/search_jobs/v1
    headers: ["X-API-Key: ${xyops_key}"]
    query: "tags:_error date:>=today"
    limit: 1                      # fetch one row, read the count from list.length
    extract: ".list.length"
  thresholds: { warn: 1, critical: 5 }
  deep_link: "https://ops.home.lan/#Search?result=error&date=today"
```

Placeholders: `{query}` (the source's `query`, percent-encoded by the plugin), `{url}`,
and `{n}` / any extracted field. `{query}` is optional — a `deep_link` with no
placeholder is legal, because the UI's vocabulary is usually not the API's, and that
mapping is the user's knowledge. A `link_template` requires a placeholder by definition;
a `deep_link` requires none.

`limit: 1` with the count read from the response metadata is the difference between one
number and a page of records — when a REST API returns a total alongside its rows, ask
for the rows you need and take the total from the metadata field.

**UI URLs are an application's private business.** xyOps documents its REST API and not
its `#Page?args` scheme — that was read out of source. A stale `deep_link` shows an
ordinary page, never an error. Treat it as a convenience, never the only path to a
number ([D14](07-decisions.md)).

### No embedded terminal

```lua
runAsync:  (cmdOrArgv, onResult?, timeoutMs?) -> boolean
runStream: (cmd, onLine) -> boolean
runInTerminal: (cmd: string) -> boolean
```

`CommandResult` is `{ exitCode, stdout, stderr, timedOut, stdoutTruncated,
stderrTruncated }`. There is no stdin handle, no resize, no raw mode — a real terminal
emulator needs a PTY, and `plugin_api` 32 exposes none. So there is no
`kind: terminal`; adding one needs a host-side PTY API that does not exist. What exists
is the console card.

### kind: console

A long-lived process whose output streams into the card — a read-only tail with a ring
buffer of the last `lines` entries.

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

`runStream` is one-way — stdout lines in, nothing back out. A console card holds a
process open, so it should declare a longer `stale_after_sec` than a polling card, and
closing the panel must tear the stream down.

### kind: list

A reading with more than one value in it — a top-N, a set of names, a roster.

```yaml
- id: pihole-top
  title: top blocked
  kind: list
  max_items: 8
  source:
    type: command
    argv: ["ssh", "pve.home.lan", "pct exec 100 -- sqlite3 /etc/pihole/pihole-FTL.db 'SELECT domain FROM queries GROUP BY domain ORDER BY COUNT(*) DESC LIMIT 8'"]
    extract_lines: domain          # field per row
```

The pipeline is unchanged; `extract` may now yield **several** values instead of one,
and `map` / `format` run once per row ([D16](07-decisions.md)).

| Field | Description |
|---|---|
| `max_items` | Rows shown; default 10 |
| `row_format` | Per-row template, e.g. `"{feed}  {title}"` |
| `source.extract_lines` | Field name or index to take from each row |
| `source.split` | Delimiter splitting a text row into indexed fields; `whitespace` collapses runs |
| `source.parse` | `json` when the command emits JSON, so `extract` can index it |

A row is a mapping whatever produced it: JSON keys, `title` / `link` / `pubDate` /
`feed` from `rss`, or one field from command text. When a tool emits fixed text columns,
`split:` turns each line into an indexed row (`{0}`, `{1}`, … in `row_format`, or one
index via `extract_lines`) — the alternative to an `awk`/`sed` pipeline inside a shell
string ([D23](07-decisions.md)).

A list card is collapsed to a count by default and expands on Enter — the top 8 blocked
domains is worth reading, all 400,000 is not. **Colour comes from the fetch, not the
contents**: a list has no thresholds, so it goes red when the command fails, never
because a row looks alarming. `format` is the collapsed label, not the row.

## Domain fields

| Field | Description |
|---|---|
| `id` | Stable key |
| `title` | Header text |
| `glyph` | Header glyph |
| `interval_sec` | Overrides `defaults.interval_sec` for this zone |
| `stale_after_sec` | Overrides the default for this zone |
| `pin` | `bottom` fixes the zone to the footer, outside the scrolling flow; at most one zone may pin |
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

`headers` / `auth` are where the whole-value secret rule bites: substitution does not
reach inside a string, so `"Bearer ${api_token}"` would go out literally — a schema
decision for the build that draws the card. **This build implements `static` and
`command` only; `http` is validated and reported as not built.**

### command

**Implemented in this build** alongside `static`. A non-zero exit is `down`, and the
tool's own text — stderr first, then stdout — goes in the card; exit codes are never
mapped to states ([06](06-failure-modes.md)). On success the reading is stdout, or the
decoded JSON when `parse: json` is set.

```yaml
source: { type: command, argv: ["systemctl", "is-active", "nginx"] }
# or a shell string:
source: { type: command, cmd: "docker ps --format '{{.Status}}' | head -1" }
```

`cmd` does not interpolate source values — same rule as `run`
([D12](07-decisions.md)). `parse` has three values: `json` (read stdout as JSON),
`stderr` (read the other stream — a fair number of tools report what you want there),
and `stdout` (the default). **A count arrives as text**: where a card or tile carries
`thresholds`, a numeric string is read as a number; a string the config did not ask to
compare is left as it came, so a word or a version still renders.

#### Reaching something inside a container

There is no `type: proxmox`; the hop composes from `command` + `ssh` + `pct exec`:

```yaml
source:
  type: command
  argv: ["ssh", "pve.home.lan", "pct exec 100 -- pihole -q --list"]
```

Everything after the host is **one argv element**, passed as a single string to `ssh`
and re-parsed once on the far side — no local shell, so nothing for a local quote to
break ([D17](07-decisions.md)). `pct exec` gives no login shell, so PATH may be minimal;
use absolute paths or a leading `PATH=`. Its exit code does not distinguish "container
stopped" from "command failed" — both are `down` with the text in the card.

`parse: json` puts a JSON-emitting command's shape where it is fetched, instead of
working around it with a `jq` pipeline inside a shell string whose quoting is already
fragile ([D17](07-decisions.md)).

#### Brackets in `extract` are load-bearing

`extract` is jq syntax, and jq's precedence will quietly produce a wrong answer rather
than an error:

```jq
[.. | .host? // empty | flatten]     # WRONG — yields []
[(.. | .host? // empty)] | flatten    # right
```

`//` binds more loosely than `|`, so the first parses as `.. | (.host? // (empty |
flatten))` — the `flatten` ends up inside the `empty` branch and never runs. No error,
and the empty list looks exactly like "there are no hosts".

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

#### feeds — many feeds, one card

```yaml
- id: infra-releases
  title: Infra
  kind: list
  max_items: 6
  row_format: "{feed}  {title}"
  source:
    type: rss
    feeds:
      pi-hole: https://github.com/pi-hole/pi-hole/releases.atom
      caddy: https://github.com/caddyserver/caddy/releases.atom
```

The keys are the labels and become the `{feed}` placeholder — which is why `feeds` is a
mapping and not a list: a version with no repository attached is not information.
**Merged feeds are always sorted newest-first**; there is no `sort` field because there
is no coherent alternative ([D19](07-decisions.md)). Row fields are `title`, `link`,
`pubDate`, `feed`, plus whatever `extract` yields.

### static

```yaml
source: { type: static, value: "—" }
```

## YAML anchors for repeated cards

Anchors are a plain YAML feature, not part of the schema ([D11](07-decisions.md)).
Define the shared body once, above `domains`:

```yaml
x-templates:
  lxc: &lxc
    kind: status
    source:
      type: http
      url: https://pve.home.lan:8006/api2/json/nodes/pve/status
      ok_when: "status == 'running'"

domains:
  - id: infra
    title: Infrastructure
    cards:
      - <<: *lxc
        id: pocketbase
        title: Pocketbase
```

The anchor must be defined before it is referenced, and an unknown top-level key is
ignored after expansion — so `x-templates` never reaches the data model.

## Deliberately absent

**`row` / `column` positioning** — order in the YAML is the order. **Free-form
`color`** — colour is semantic only ([D5](07-decisions.md)). **`priority`** —
`span: 1|2` covers it. **Inline secrets** — only `${name}` references.

## Secrets

```yaml
# hub.secrets.yaml — mode 0600, never committed
proxmox_token: "eyJhbGciOi..."
```

Referenced from `hub.yaml` as `${proxmox_token}`. **Quote the substitution** — inside a
flow mapping an unquoted value starting with `$` contains `{`, which YAML reads as the
start of a nested mapping:

```yaml
auth: { token: ${proxmox_token} }     # parse error
auth: { token: "${proxmox_token}" }   # correct
```

**Only a whole value is substituted.** `token: "${name}"` becomes the secret;
`"Bearer ${name}"` does not — because `run:` is a shell string whose own `${VAR}` and
`$(cmd)` belong to that shell, and a heuristic that guessed wrong would either leak a
token or eat a shell variable the user meant to keep ([D12](07-decisions.md)). An
unknown name is reported against the path it was found at, and the literal `${ghost}` is
left in place rather than blanked.

## Hot reload

The service polls the config mtime. On change it re-reads, rebuilds the zone tree, and
preserves scroll position and selection; a reload indicator flashes in the header.
`hub.secrets.yaml` is re-read on each reload, so rotating a token needs no restart.
