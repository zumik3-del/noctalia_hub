# 06 — Failure modes

The main risk in monitoring is not "the panel does not work", it is "the panel lies".
A false alarm is worse than no alarm: you start ignoring red, and then nothing works
any more.

## Card states

Exactly five, each unambiguously determined.

| State | Condition | Rendering |
|---|---|---|
| `pending` | First sample has not arrived | `—`, hollow dot |
| `ok` | Data received, thresholds not crossed | Value, `primary` |
| `warn` | `warn` threshold crossed, or a `map` value says so | Value, `secondary` |
| `down` | Source errored, `ok_when` was false, or the reading makes no sense | Value if there is one, `error`, pulsing |
| `stale` | Data older than `stale_after_sec` | Value + age, `on_surface_variant` |

A card has two error channels. `error` is a problem with the source and clears when the
source recovers; `configError` is a problem with the card (a bad field, a missing
secret) and is already true before the first poll, because it came from reading the
file. Whichever is speaking, the reason appears on the **state marker's tooltip**, not
in the card body — the description keeps its line, so a failing card still says what it
measures. The document-level block above the zones still lists every config error with
its path.

A `kind: status` card has no value column ([D27](07-decisions.md)). A card that has
**never** succeeded stays `down` rather than aging into a dimmer `down` — there is no
reading for the age to qualify.

## While the API is down for three minutes

Not a flashing error, and not a zero:

```
▸ grafana        404        from 14:02 · 3 attempts
```

The value as of the last success, its age, and the failed-attempt count. After
`stale_after_sec` the card dims, but **the figure stays** — you can see the reading
froze, not that it is zero. On recovery the value updates and the counter resets.
Separately, `down` via `ok_when` shows the value as-is in red, so it is visible that
the instrument is broken rather than the connection.

## Error hierarchy

```
converter unavailable ─► panel does not render; reason shown
  └─ invalid YAML ─────► panel does not render; reason shown
       └─ invalid structure ► panel renders; the error is a block above the zones
            └─ card error ─► only that card: title + the error under it
                 └─ source failure ► card in down / stale, value retained
```

A broken card **does not break the others**. "Converter unavailable" is separate from
"invalid YAML": `yq` is a declared dependency, and on a machine without it the file is
not wrong — it was never read. An empty-but-valid document is not fatal: `domains: []`
renders an empty panel with a hint. Only a config that cannot be read at all refuses to
render, because an empty instrument panel and a healthy one look alike.

## Config errors point at a path, not a line

`yq` does not report line numbers, so a semantic error carries the **document path**:

```
domains[2].cards[5].source.type — unknown source type "htp" (expected: http, command, stream, rss, static)
domains[0].cards[3].thresholds — warn must be below critical, got warn=90 critical=10
```

A parse failure carries the converter's own message (with a line); a missing secret
carries a path plus the file that should have held it. Messages are actionable —
`unknown source type "htp"`, not `invalid value`. A card that fails validation is not
dropped: it renders with its error next to the cards that are fine. The collector stats
`hub.yaml` on its own tick, so fixing the file clears the error without a restart.

## One dead feed inside a merge

A merged `feeds:` card survives a dead feed but must say which feeds answered:

```
▸ Infra releases   6 of 7 feeds   ⚠ caddy: 404 Not Found
```

- a dead feed does not fail the card — it is annotated
- the count is of feeds that **answered**, never of entries in the config
- **all feeds dead is `down`**, not an empty list — otherwise a merge of one broken
  feed and one quiet feed is indistinguishable from a healthy card

A quiet feed (200, zero new items) counts as answered — which is why the badge says
"feeds", not "new entries".

## A panel action that silently does nothing

`panel-open` validates the panel id and refuses loudly; it does **not** validate the
context (`panel-open control-center nosuchsection` exits `0`, prints `ok`, does
nothing). The panel id is the plugin's responsibility and is checked at load; the
context is the config author's and cannot be checked. A card pointing at a section that
no longer exists fails the way a typo in a URL fails — silently, and only when someone
presses it.

## A list that is quietly empty

The nastiest failure in the panel, because nothing looks wrong:

```
▸ caddy routes   0 sites      ← ok, up to date, genuinely nothing
▸ caddy routes   0 sites      ← ok, the extract silently matched nothing
```

Identical on screen. The rule: **a list card that is empty but whose source previously
returned rows must not report `ok`** — it goes `warn` with "no rows" and keeps the last
good rows visible. The general form: **a sudden drop to an empty result is a failure of
the fetch, not a fact about the world.**

## A failed action is not a stale reading

Keeping the last good value is right for readings and wrong for actions. A card that
says "restart pocketbase" and shows `200 ok` from four minutes ago while the restart
fails is lying about the one thing you acted on. A failed `control:` therefore surfaces
immediately and independently of the card's value:

```
▸ pocketbase        200      from 14:02        ⚠ restart failed: 503
```

The value keeps its own staleness rules; the action gets its own line and the row goes
`down` for the action's sake.

## A deep link that stopped resolving

Silent: a `deep_link` points into another application's UI, and when it breaks the app
shows an ordinary page rather than an error. Nothing in the panel can detect it. The
only defence is not relying on it — a `deep_link` must never be the only way to reach a
number the panel depends on.

## A value that failed to parse is shown as-is

```
▸ proxmox-nodes   ???       ← extract returned garbage
```

Not replaced with zero: `0 nodes` reads as the truth.

## An update check that could not run

The `updates` badge is silent at zero and a warn-coloured count otherwise; a check that
failed is a third fact — a dim red glyph whose tooltip carries the reason. The card's
own dot is untouched: a broken update check is not a broken Pi-hole. The badge is the
host's second reading, not the card's state, so it is not counted in the header's error
total. A non-zero exit, a timeout, or output that is not a number is `down` with the
tool's own text — never a zero the badge would draw as "no updates".

## Many cards, one dead hop

Six cards reading six containers on one Proxmox node share a single point of failure:
the ssh. When the node is unreachable they all go `down`, and the panel shows six red
rows. That is honest but not useful, so:

- **a failing fetch states the hop** — `ssh: connect to host pve.home.lan port 22: No
  route to host` goes in the card, naming the cause
- **cards sharing a source are grouped in the zone**, so the failure reads as a block

The panel does **not** deduce a shared cause and collapse the rows: an inferred "pve is
down" badge on a card about Pi-hole is a lie the moment the node is up and Pi-hole is
not.

## Exit codes from a hop are not a state

`pct exec` exits non-zero both when the container is stopped and when the command
inside it failed; the difference only appears in stderr. A card must not map exit codes
to states — any non-zero exit is `down` with stderr verbatim, so the operator sees
`sqlite3: command not found` instead of a green light.

## One failed row must not blank the list

A `kind: list` card whose fetch fails keeps its last good rows and shows the age,
exactly like any other reading ([D7](07-decisions.md)). It does **not** collapse to an
empty list, which is indistinguishable from "there genuinely are none of these things".

## A command that needs PATH

`pct exec` gives no login shell, so `.bashrc` is not read and `PATH` may not include
`/usr/local/bin`. A command that works perfectly over ssh and fails here is almost
always this. Two fixes: absolute paths in `argv`, or `PATH=/usr/local/bin:$PATH`
prefixed inside the remote command.

## Timeouts

`timeout_ms` defaults to 8000. A source that misses it counts as `down` for that
attempt and must not block other cards — polling is parallel, and one hung source must
never slow the panel down.

## What the panel does not do

**No aggressive retry** — a source down for ten minutes must not generate a flood of
requests. **No adaptive interval** — a fixed `interval_sec` is predictable. **No loading
bar** — visual noise for a source that answers in a second.

## Degradation instead of failure

1. attempt fails → `down`, previous value retained
2. `stale_after_sec` passes → `stale`, value retained, dimmed
3. recovery → value updated, `ok`, counter reset

Never: zero the value, hide the card, or show "no data" without a reason.
