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
    id: pocketbase
    title: Pocketbase
  - <<: *lxc
    id: jellyfin
    title: Jellyfin
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
  density: compact          # compact | standard | comfortable
  show_header: true
  clock: "%H:%M:%S"
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

  - id: system
    title: System
    glyph: cpu
    pin: bottom            # footer: background, outside the scrolling flow
    cards:
      - id: cpu
        title: CPU
        kind: metric
        source: { type: command, cmd: "top -bn1 | awk '/Cpu\\(s\\)/ {print 100 - $8}'" }
        format: "{n}%"
        thresholds: { warn: 80, critical: 95 }
        graph: 48
```

## Layout fields

| Field | Default | Description |
|---|---|---|
| `density` | `compact` | `compact`, `standard` or `comfortable`. Sets the base row height, padding and type size. |
| `clock` | `"%H:%M:%S"` | `strftime` pattern for the header clock, redrawn every second. |
| `font_scale` | `100` | `80`–`130`. Multiplier applied to every text size at render time. |
| `card_radius` | `9` | `0`–`24` px. Corner rounding of a card block. |
| `card_spacing` | `8` | `0`–`32` px. Gap between cards inside a zone. |
| `card_border` | `subtle` | `none`, `subtle` or `accent`. Border of a card block. |
| `card_background` | `tinted` | `transparent`, `tinted` or `solid`. Fill of a card block; always a theme role, never a colour. |
| `hover_effect` | `background` | `none`, `background` or `border`. Response while the pointer is over a card: `background` brightens the fill, `border` claims the accent border, `none` does not react. One response, never two. |
| `show_header` | `true` | Accepted and validated, **not yet honoured** in this build (the header always draws). |
| `stale_badge` | `true` | Accepted and validated, **not yet honoured** in this build (the age line always draws). |

`density`, `font_scale`, `card_radius`, `card_spacing`, `card_border`,
`card_background` and `hover_effect` are the card-block framework ported from
github-kanban ([D24](07-decisions.md)). None of them names a colour: shape and
density are config, colour is always the active Noctalia palette
([04](04-visual-language.md) §1).

## Card fields

### Identity and kind

| Field | Required | Description |
|---|---|---|
| `id` | yes | Stable key; state and interval are tracked per id |
| `title` | yes | Name shown in the instrument row |
| `glyph` | no | Tabler glyph; falls back to a default per `kind` |
| `kind` | yes | Rendering only: `status` \| `metric` \| `release` \| `link` \| `console` \| `list` |
| `span` | no | `1` or `2` — how many cells the card occupies in the flow |
| `description` | no | One line of prose; see below |
| `hidden` | no | `true` keeps the card in the config without rendering it |

The six kinds are a **closed set** ([D22](07-decisions.md)). `graph` is a
presentation field on any card, not a kind; a plain string reading is `status`.

#### description

A single line saying what the thing is, for when you cannot tell from the name.
`Router · Keenetic gateway` is ambiguous; `Gateway and routing` is not.

**It is the second line of its card.** The card is github-kanban's activity block
([D25](07-decisions.md)): title on the first line, description on the second, the
reading and its state marker on the trailing edge. A card with no description is
one line tall.

A failure does not take the second line. The reason a card is not ok — a source
error, a config error, or the age of a stale reading — is shown on the **state
marker's tooltip**: hover the coloured dot and the reason appears. The body stays
readable, so a red card still says what it measures
([D25](07-decisions.md), [06](06-failure-modes.md)). This reverses D18's "selected
card only": the description is the card's own second line now.

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
| `stale_after_sec` | Age at which the card dims; inherited from the zone, which defaults to 300 |
| `retries` | Retry count on failure |

`retries` is validated but not yet acted on. There is no retry loop to configure
until step 2 lands, and a setting that does nothing is worse than an absent one —
which is why the build records its own gaps rather than implying they work. Both
this and `span` are listed in the "not in this build" note at the bottom of
`panel.luau`, next to the features waiting on a build-order step.

**A value the `map` does not list is `down`, with the value shown.** Not `ok`
because the list was not consulted, and not `warn` because it might be fine. A
`map` is an exhaustive statement about what the values mean, so an unexpected one
is the service having changed shape under the config, and that is worth a red dot
and the value that caused it.

`ok_when` and `map` answer different questions, and both are needed. `ok_when` is a
predicate over the **parsed response**, evaluated at fetch time — its bare
identifiers are the response's top-level fields, so `ok_when: "status == 'running'"`
matches a body of `{"status": "running"}`. `map` runs later, on the **extracted
value**, and translates it into a state (`0: ok`, `1: down`). A card asking "did the
response say the right thing" uses `ok_when`; a card asking "what does this number
mean" uses `map`.

A card carrying both is legal, and `map` wins — a value the author has named
explicitly is the more specific instruction, and `ok_when` on the same card is
about the response rather than the reading.

**`map` keys accept numbers unquoted.** `0: ok` and `"0": ok` are the same key;
JSON cannot tell them apart on the way back in, so the config author should not have
to care. A card whose value is a string is matched on that string.

### Presentation

| Field | Description |
|---|---|
| `thresholds` | `{ warn: N, critical: N }` — where colour turns amber, then red |
| `format` | Substitution template, e.g. `"{n} nodes"` |
| `unit` | Suffix: `"%"`, `"ms"`, `"MB"` |
| `graph` | `true` / a point count / `false` |
| `mini_cards` | A list of `{ label, value, unit? }` (static) or `{ label, source, unit?, thresholds?, interval_sec? }` (dynamic) — the card's own second row of facts, drawn as small tiles on the trailing edge, left of the update badge |

`format` placeholders are plain field names: `{n}` for the extracted value, plus
any key of a mapping value and, on a `list` card, the count. `{n}`, `{0}` and
`{status}` substitute; `{n.status}` does not, and stays in the output as written —
a template that quietly rendered half of itself would be worse than one that looks
broken.

**A placeholder with nothing to put in it stays visible.** `"{n} nodes"` with no
extracted value renders as `{n} nodes`, not as ` nodes`. An empty string reads as
a service with zero nodes; the broken template reads as a broken template.

**`format`, `unit` and `row_format` must be non-empty strings.** A wrong type is a
config error, not a field dropped in silence: a `unit: 5` that vanished would leave
the panel looking correct while the suffix was simply missing, which is the failure
mode the config-errors block exists to prevent
([04](04-visual-language.md) §6).

A mini-card is either static or dynamic. A static one carries `value` and draws it
as-is. A dynamic one carries a full `source` — the same block a card carries — plus
an optional `unit` (a suffix such as `"%"`), `thresholds` and `interval_sec`: the
collector fetches it on its own interval (3600 by default) and colours the value by
the thresholds, the way it colours a card's reading. Before the first fetch the tile
shows the shared placeholder, and a failed fetch keeps the last good value with the
reason on the tooltip ([D30](07-decisions.md)).

**A tile speaks in colour only when something is wrong.** `warn` and `down` take
the state colour; everything else — including the `ok` a threshold produces —
draws in the neutral column colour a static tile uses. A green number for "nothing
failed" is noise, and without a threshold `ok` means even less. A tile's `label` is
drawn upper-case, like a zone title.

`thresholds` must have `warn` below `critical`, and the validator says so rather
than accepting a card whose amber is unreachable.

**`kind: status` draws only its dot.** The value column is not rendered for a
status card: the dot's colour carries the state, and a word beside it was the same
fact twice. `format` and `unit` have no effect on a `status` card
([D27](07-decisions.md)). Metric, release, link, console and list cards still show
their reading.

### updates — a second reading on the card

A card can carry one extra reading about the host it watches: how many OS packages
are waiting. It draws as a **badge before the state dot**, and it is silent when
there is nothing to say — no pending updates, or the check has not answered yet. A
count is a button: pressing it runs the install command in a terminal. A check that
could not run is a dim red glyph whose tooltip carries the reason, because "no
updates" and "could not ask" are different facts. The badge never changes the
card's own dot and is not counted in the header's error total
([D27](07-decisions.md)).

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
| `interval_sec` | no | Poll period; defaults to `3600` — a package check is not asked at the card's cadence |
| `timeout_ms` | no | Timeout; defaults to `defaults.timeout_ms` |
| `format` | no | Template for the badge text; `{n}` is the count |

**The check prints a number, and anything else is `down`.** stdout is text, so the
collector reads it as a number; a non-number becomes a failure with the bytes
quoted, never a zero the badge would draw as "all clear". A count of `0` is `ok` and
draws nothing; `1` or more is `warn` and draws the button.

**The distribution is the config author's, not the plugin's.** Debian is `apt-get`,
Alpine is `apk`, and there is no `family:` field: a plugin that guessed between them
would be an integration to keep in step with every distribution that appears
([D17](07-decisions.md), [D27](07-decisions.md)). The two canonical checks:

```yaml
# Debian / Ubuntu
argv: ["ssh", "proxmox", "pct exec 100 -- sh -c 'apt-get update -qq >/dev/null || exit 1; apt-get -s -q upgrade | grep -c ^Inst || true'"]

# Alpine
argv: ["ssh", "proxmox", "pct exec 116 -- sh -c 'apk update -q >/dev/null 2>&1 || exit 1; apk version -l \"<\" | grep -c \"<\" || true'"]
```

**A bare host answers too, without the `pct` hop.** The node's own packages are the
same check on the far side of `ssh` alone — `ssh proxmox sh -c '...'`, no `pct exec`
— and its install is `ssh -t proxmox 'apt-get update && apt-get -y upgrade'`.
Container or host is a property of the command, not of the schema, which is the
point of writing the command out.

Three things in those strings are load-bearing, and all three were verified against
live containers:

- **`sh -c`, not `sh -lc`.** A login shell sources the container's profile and an
  MOTD banner lands in stdout, where the count cannot tell it from an answer.
- **`|| true` after the `grep -c`.** `grep -c` exits `1` when it counts zero, and a
  non-zero exit is `down` — without it, "no updates" would render as a failed check.
- **Alpine counts `<` markers, not lines.** `apk version -l '<'` prints an
  `Installed: Available:` header, so `wc -l` is off by one; the marker lines are the
  only rows.

The Debian check runs `apt-get update` first, so it writes the package lists inside
the container once per interval. That is the price of a count that is about now
rather than about whenever the lists last moved; a card that would rather not touch
the container can drop that part and read whatever lists are already there.

## Actions

A card can do something. An action is a **button on the card's trailing edge**, not
a hit area over the whole card, so a card may carry more than one: `link` and `run`
sit side by side, each with its own target, and a click on one cannot mean the other
([D26](07-decisions.md)).

| Field | Drawn as | Effect |
|---|---|---|
| `link` | link button | Open a URL in the browser |
| `run` | terminal button | Run a shell command in the user's terminal |
| `link_template` | — | Open a URL built from extracted fields (not drawn yet) |
| `deep_link` | — | Open a URL built from the source's own query plus extracted fields (not drawn yet) |
| `panel` | — | Open another Noctalia panel (not drawn yet) |
| `control` | — | Write to a remote system — deferred ([D15](07-decisions.md)) |

Only `link` and `run` are drawn in this build; the other four are validated and
carried in the model and become buttons when their step lands. Each button has its
own target, so two of them is not the ambiguity the old one-action rule guarded
against — the rule that survives is scoped to `control`, which is the one action
that changes something and must not share a card with another.

`link` opens the browser and nothing else. `run` opens a terminal window, because
the user asked to watch a command run. The two share a mechanism — both are handed
to the collector, which runs them — and must not share a cost model. A window
flashing open to display `ok` is a regression wearing delegation's clothes
([D20](07-decisions.md)).

### panel — open another Noctalia surface

The shell already has panels: a launcher, a control center, a clipboard history, and
whatever your own plugins register. `panel` opens one of them.

```yaml
- id: go-calendar
  title: Calendar
  glyph: calendar
  kind: link
  source: { type: static, value: "—" }
  panel: "control-center calendar"
```

That is `noctalia msg panel-open control-center calendar`, run directly:

```lua
noctalia.runAsync({ "noctalia", "msg", "panel-open", "control-center", "calendar" })
```

**`panel` and `run` are different even though both end up in `runAsync`.** `run`
opens a terminal window, because the user asked to see a command run. `panel`
opens a panel and nothing else — the command returns immediately, prints nothing
anyone reads, and a terminal window flashing open to display `ok` is a bug, not
delegation.

**For another panel, use `panel-open`, not `togglePanel`.** The Lua API offers
`noctalia.togglePanel`, which inverts: press it twice and the panel closes. That is
correct for a bar widget toggling its *own* panel, and wrong for a card opening
someone else's — a card pressed twice should bring the panel forward, not dismiss
it. Every community plugin that opens another plugin's panel switched to
`panel-open` for this reason, and `cider` documents the swap outright.

Panels come in two spellings:

| Id | Example |
|---|---|
| Built-in | `launcher`, `control-center`, `clipboard`, `polkit`, `session`, `tray-drawer`, `wallpaper` |
| A plugin's panel | `author/plugin:panel` |

There is **no standalone `calendar` or `weather` panel**. Both are sections of the
control center, reached through the optional context argument:

```yaml
panel: "control-center calendar"
panel: "control-center weather"
panel: "launcher /downloads"
```

The context is what makes this useful, and it is also the one part the plugin
cannot check. A valid panel with a nonsense context exits `0` and prints `ok`,
doing nothing. Only the panel id is verifiable — see below. A config author owns
that argument.

#### Panel ids are checkable

Noctalia validates the id and, on failure, lists everything that exists:

```
$ noctalia msg panel-open nosuch/plugin:panel
error: unknown panel "nosuch/plugin:panel" (available: clipboard,
control-center, launcher, polkit, session, tray-drawer, wallpaper,
pozzoo/hassio:entity_manager, ...)
```

Two things follow. A panel id in `hub.yaml` is a **validation-time check**, not a
guess — a typo is reported on the offending card, alongside the other config
errors. And because the registry is enumerable, `parse: stderr` can read it.

That second one is a deliberate hack on a missing API, and it is documented as one
because there is no `listPanels` and parsing an error message is not a dependency a
card should take quietly:

```yaml
source:
  type: command
  argv: ["noctalia", "msg", "panel-open", "__probe__"]
  parse: stderr
```

**This one does not work yet, and the reason is a real schema gap.** The registry
arrives as a single line — `error: unknown panel "..." (available: a, b, c)` — and
turning it into a list of ids needs three transformations: strip the prefix, strip
the trailing `)`, split on `, `. `split:` now exists ([D23](07-decisions.md)), which
is the last of the three; the two strips remain, and a prefix/suffix strip for a
single card is still the wrong trade. It is left as a documented gap rather than
papered over with a `sed`, because a card that works only until the shell rewords
its error message is worse than no card.

### control — a flag, not a kind

A card that can write does not become a different kind of card. `kind` keeps its
single meaning, "how to draw the reading", exactly as [D4](07-decisions.md)
established. What the card *does* is an orthogonal axis, like `thresholds`:

```yaml
- id: pocketbase
  title: Pocketbase
  glyph: server
  kind: status                    # unchanged — this is still a status reading
  source:
    type: http
    url: https://pve.home.lan:8006/api2/json/nodes/pve/lxc/104/status/current
    auth: { token: "${proxmox_token}" }
    extract: ".status"
  map:
    running: ok
    stopped: warn
  control:
    type: http
    url: https://pve.home.lan:8006/api2/json/nodes/pve/lxc/104/status/reboot
    method: POST
    auth: { token: "${proxmox_token}" }
    expect: '"code == 0"'
  confirm:
    target: "pocketbase @ pve.home.lan"
    effect: "LXC restart"
```

The row renders exactly as it would without `control:` — glyph, title, value, state,
age. Only what Enter does changes. The renderer gains no new branch.

This is what keeps the control honest: the card shows the state of the thing you
are about to change. A button labelled "restart pocketbase" on its own does not tell you
whether pocketbase is currently running, which is exactly the information you need before
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
link: "https://ops.home.lan/#Search?result=error&date=today"   # for the click
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
    url: https://ops.home.lan/api/app/search_jobs/v1
    headers: ["X-API-Key: ${xyops_key}"]
    query: "tags:_error date:>=today"
    limit: 1
    extract: ".list.length"
  thresholds: { warn: 1, critical: 5 }
  deep_link: "https://ops.home.lan/#Search?result=error&date=today"
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

**`{query}` is optional, and a `deep_link` with no placeholder at all is legal.**
A deep link points into another application's own URL scheme, and that scheme's
vocabulary is usually not the source's: xyOps takes `tags:_error` on its API and
`result=error` in its UI. That mapping is xyOps-internal knowledge and it lives in
the user's config, where they can see it and update it. The validator requires a
placeholder in a `link_template` — which is built from extracted fields by
definition — and requires none in a `deep_link`.

What `{query}` actually buys is narrower than it looks, and worth being exact
about: it removes the *date* half of the duplication, not the *vocabulary* half.
On an application whose UI accepts the same query string its API does, it removes
all of it:

```yaml
deep_link: "https://ops.example.lan/#Search?q={query}"   # nothing left to keep in sync
```

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
    url: https://ops.home.lan/api/app/search_jobs/v1
    headers: ["X-API-Key: ${xyops_key}"]
    query: "tags:_error date:>=today"
    limit: 1                      # fetch one row, read the count from list.length
    extract: ".list.length"
  thresholds: { warn: 1, critical: 5 }
  deep_link: "https://ops.home.lan/#Search?result=error&date=today"
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
  title: pve.home.lan
  glyph: ssh
  kind: status
  run: "ssh root@pve.home.lan"
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
noctalia.runInTerminal("ssh root@pve.home.lan")
```

This opens a **separate terminal window**, it does not embed one. The panel stays
visible behind it.

`run` is a plain string, not an argv list, and it is passed through untouched. The
config is written by the user in their own home directory, so it is trusted input
and needs no quoting. Chaining and redirection work:

```yaml
run: "ssh root@pve.home.lan 'journalctl -u pveproxy -f -n 20'"
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

The pipeline is unchanged — `fetch → extract → map → format`. What changes is that
`extract` may now yield **several** values instead of one. Everything downstream
(`map`, `format`) runs once per row. See [D16](07-decisions.md).

| Field | Description |
|---|---|
| `max_items` | Rows shown; default 10 |
| `row_format` | Per-row template, e.g. `"{feed}  {title}"` |
| `description` | Second line, shown when the card is selected |
| `source.extract_lines` | Field name or index to take from each row |
| `source.split` | Delimiter splitting a text row into indexed fields; `whitespace` collapses runs |
| `source.parse` | `json` when the command emits JSON, so `extract` can index it |

A row is a mapping, whatever produced it: JSON keys from a `command` source,
`title` / `link` / `pubDate` / `feed` from `rss`, one field from `command` text.
`row_format` templates the row the same way `format` templates a single value.

When the tool emits fixed text columns rather than JSON, `split:` turns each line
into an indexed row — `{0}`, `{1}`, … in `row_format`, or one index via
`extract_lines`. `split: whitespace` collapses runs of spaces, which is what
column-oriented output such as `df -P` needs. This is the alternative to an `awk`
or `sed` pipeline inside a shell string, which is the quoting the schema refuses
everywhere else ([D23](07-decisions.md)).

A list card is collapsed to a count by default and expands on Enter. That is the
only card that changes shape when selected, and the reason is capacity: the top 8
blocked domains is worth reading, all 400,000 is not.

**Colour comes from the fetch, not from the contents.** A list has no thresholds —
there is no sensible `warn` for "here are some domain names". `ok` / `warn` /
`down` / `stale` describe whether the list could be read at all, so a `list` card
goes red when the command fails and never because a row looks alarming.

**`format` is the collapsed label**, not the row. When collapsed the card shows the
count; when expanded it shows the rows.

```yaml
- id: caddy-routes
  title: caddy routes
  kind: list
  max_items: 6
  format: "{n} sites"
```

## Domain fields

| Field | Description |
|---|---|
| `id` | Stable key |
| `title` | Header text |
| `glyph` | Header glyph |
| `interval_sec` | Overrides `defaults.interval_sec` for this zone |
| `stale_after_sec` | Overrides the default for this zone |
| `pin` | `bottom` fixes the zone to the panel footer, outside the scrolling flow; at most one zone may pin |
| `cards` | Ordered list; order is the visual order, there is no `row`/`column` |

## Source types

### http

```yaml
source:
  type: http
  url: https://api.example.com/status
  method: GET              # defaults to GET
  headers: ["Authorization: Bearer ${api_token}"]   # see the note below
  auth: { token: "${proxmox_token}" }
  body: ""
  follow_redirects: true
  allow_insecure_tls: false
  query: "scope=all&since=24h"   # appended to the URL, percent-encoded by the plugin
  limit: 1                       # ask the server for fewer rows
  select: ["id", "code"]         # request only these fields, where supported
  extract: ".data | length"
```

`headers` and `auth` are where the whole-value rule in §Secrets bites: the
substitution does not reach inside a string, so `"Bearer ${api_token}"` would go
out as those literal characters. The http build has to decide there — a way to
spell a prefix separately from the token, so the token stays one whole value —
and it is a schema decision for the build that draws the card, not one to guess
at now. This build implements `static` and `command` only; `http` is validated
and reported as not built.

`query` is a convenience for APIs that take query-string parameters. It is
URL-encoded for you, so write `&` and spaces normally. `extract` is applied to the
parsed response body.

**When an API returns a total alongside its rows, use it.** Most REST search
endpoints return both the page of records and the overall match count in a
metadata field. Request `limit: 1` and read the count from that field — a card
that wants one number should not transfer a page of records every thirty seconds
to compute it. xyOps, Proxmox and GitHub all do this.

A response is parsed as JSON before `extract` sees it. When a **command** already
emits JSON, declare that rather than wrapping it in `jq`:

```yaml
source:
  type: command
  argv: ["caddy", "adapt", "--config", "/etc/caddy/Caddyfile"]
  parse: json
  extract: "[(.. | .host? // empty)] | flatten"
```

`parse: json` puts the output shape where it is fetched, instead of working around
it with a `jq` pipeline inside a shell string whose quoting is already fragile. A
card that has to shell out to `jq` in order to be readable is a card whose author
will get the quoting wrong eventually.

It is the same `extract` as `http` — the parser is the only difference, which is
the point. See [D17](07-decisions.md).

`parse` has three values, not two: `json` reads stdout as JSON, `stderr` reads
stderr instead of stdout, and `stdout` is the default. The `stderr` case exists
because a fair number of tools report the thing you want on the error stream —
`noctalia msg panel-open` lists the available panels there, and `git` puts its
advice there. A card that has to merge stderr into stdout with `2>&1` in a shell
string is a card with quoting in it, which is what `argv` was supposed to avoid.

#### Brackets in `extract` are load-bearing

`extract` is jq syntax, and jq's precedence will quietly produce a wrong answer
rather than an error:

```jq
[.. | .host? // empty | flatten]     # WRONG — yields []
[(.. | .host? // empty)] | flatten    # right
```

`//` binds more loosely than `|`, so the first line parses as
`.. | (.host? // (empty | flatten))` — the `flatten` ends up inside the `empty`
branch and never runs on real data. There is no error, no warning, and the result
is an empty list, which for a `kind: list` card looks exactly like "there are no
hosts". Collected and verified against real `caddy adapt` output; the failure mode
is that a card shows nothing and looks healthy.

### command

**`command` is implemented in this build** alongside `static`; `http`, `stream` and
`rss` are still recognised-but-not-built. A non-zero exit is `down`, and the tool's
own text — stderr first, then stdout — goes in the card; exit codes are never mapped
to states ([06](06-failure-modes.md)). On success the reading is stdout, or the
decoded JSON when `parse: json` is set. `parse: stderr` reads the other stream for
the tools that report what you want there.

**A count arrives as text.** stdout is a string, so `"2"` is not a number to the
pipeline. Where a card or a tile carries `thresholds`, a numeric string is read as a
number; a string the config did not ask to compare is left as it came, so a word or
a version still renders.

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

`cmd` does not interpolate source values — same rule as `run`, see
[D12](07-decisions.md). A value that came from an HTTP response is not your own
typing.

#### Reaching something inside a container

A service in a Proxmox container is reached by sshing to the node and using
`pct exec`. There is no `type: proxmox`. The hop composes out of the parts that
already exist, and `argv` keeps the quoting honest:

```yaml
source:
  type: command
  argv: ["ssh", "pve.home.lan", "pct exec 100 -- pihole -q --list"]
```

Everything after the host is **one argv element**, so the remote command is passed
as a single string to `ssh` and re-parsed once on the far side. There is no local
shell, so there is nothing for a local quote to break. This is the whole reason to
prefer `argv` over `cmd` for anything that crosses a hop — see
[D17](07-decisions.md).

**`pct exec` has no login shell by default**, so it does not read `.bashrc` and
PATH may be minimal. Absolute paths, or a leading `PATH=`, matter here:

```yaml
argv: ["ssh", "pve.home.lan", "pct exec 100 -- /usr/bin/sqlite3 /etc/pihole/pihole-FTL.db 'SELECT ...'"]
```

Two traps specific to this hop:

- **`pct exec` returns a non-zero exit code when the container is stopped**, and the
  message goes to stderr. A card reading a stopped container shows `down` with the
  container's own error text, which is correct and useful.
- **`pct exec` on a running container still exits non-zero if the *command* fails**,
  and the two are indistinguishable unless you read stderr. Do not map exit codes
  to states; let a failed fetch become `down` and put the text in the card.

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

Sixteen repositories do not belong on sixteen rows of a panel that is supposed to
be read at a glance. `feeds` merges them into one card:

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
      forgejo: https://codeberg.org/forgejo/forgejo/releases.rss
```

The keys are the labels; they become the `{feed}` placeholder. That is the whole
reason `feeds` is a mapping and not a list — a release with no repository name
attached is not information, it is a version number.

**Merged feeds are always sorted newest-first.** There is no `sort` field because
there is no sensible alternative: two timelines cannot be concatenated, and a
merge that preserves feed order is not a merge, it is a rotation through
whichever repo happens to be listed first. A single `url` keeps the order the
feed returned.

Row fields are `title`, `link`, `pubDate` and `feed`, plus whatever `extract`
yields. Both GitHub and Forgejo put the version tag in `<title>`, so the same
`tag: title` works for either host — verified against both.

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
      url: https://pve.home.lan:8006/api2/json/nodes/pve/status
      auth: { token: "${proxmox_token}" }
      ok_when: "status == 'running'"

domains:
  - id: infra
    title: Infrastructure
    cards:
      - <<: *lxc
        id: pocketbase
        title: Pocketbase
      - <<: *lxc
        id: jellyfin
        title: Jellyfin
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

**Only a whole value is substituted.** `token: "${name}"` becomes the secret;
`"Bearer ${name}"` does not — the reference has to be the entire value. The
reason is `run:`, which is a shell string and whose own `${VAR}` and `$(cmd)`
belong to that shell, not to this file (see D12). A substitution that reached
inside strings would have to decide which `${...}` is the user's shell and which
is the panel's, and a heuristic that guesses wrong either leaks a token into a
command line or eats a shell variable the user meant to keep. So the boundary is
exact and it is this: write the reference alone, or use it where a literal
`${name}` in the output costs nothing.

An unknown name is reported against the path it was found at, and the literal is
left in place rather than blanked — a config that says `${ghost}` on screen is
telling the truth about a name `hub.secrets.yaml` does not have.

## Hot reload

The service polls the config mtime. On change it re-reads, rebuilds the zone tree,
and preserves scroll position and selection. A reload indicator flashes in the
header.

`hub.secrets.yaml` is re-read on each reload, so rotating a token does not require
restarting the shell.