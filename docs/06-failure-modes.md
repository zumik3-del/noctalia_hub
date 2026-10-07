# 06 — Failure modes

The main risk in monitoring is not "the panel does not work", it is "the panel
lies". A false alarm is worse than no alarm: you start ignoring red, and then
nothing works any more.

## Card states

Exactly five, no more. Each is unambiguously determined.

| State | Condition | Rendering |
|---|---|---|
| `pending` | First sample has not arrived | Skeleton, no figures |
| `ok` | Data received, thresholds not crossed | Value, `primary` |
| `warn` | `warn` threshold crossed | Value, `secondary` |
| `down` | Source errored or `ok_when` was false | `—`, `error`, pulsing |
| `stale` | Data older than `stale_after_sec` | Value + timestamp, `on_surface_variant` |

## What a card shows while the API is down for three minutes

Not a flashing error, and not a zero. It shows:

```
▸ grafana        404        from 14:02 · 3 attempts
```

- the value as of the last success
- the age of that data
- the number of failed attempts

After `stale_after_sec` the card dims — but **the figure stays**. You can see that
the reading froze, not that the reading is zero.

When the source recovers the value updates and the attempt counter resets.

Separate `down` highlighting without clearing the value covers a different case:
the source answered, but answered with the wrong thing (`down` via `ok_when`). The
value is shown as-is and marked red, so it is visible that the instrument is broken
rather than the connection.

## Error hierarchy

```
invalid YAML ──────────────► panel does not render at all; reason shown
  └─ invalid structure ───► panel renders, offending zones empty
       └─ card error ─────► only that card: name + error text
            └─ source failure ► card in stale / down
```

A broken card **does not break the others**. This is a testable requirement: you
will eventually have one malformed card, and the whole panel must not disappear
because of it.

## Config errors point at a line

```
hub.yaml:42 — unknown source type "htp"
```

The line number saves an hour of debugging. The YAML parser provides it, so pass it
through.

Messages must be actionable — not `invalid value`, but
`unknown source type "htp" (expected: http, command, stream, rss, static)`.

## One dead feed inside a merge

A merged `feeds:` card survives a dead feed — the others still have entries, and
turning the whole card red because one repository renamed its feed trains the
operator to ignore red. But surviving is not the same as being honest, and the
card must say which feeds answered:

```
▸ Infra releases   6 of 7 feeds   ⚠ caddy: 404 Not Found
```

Three rules, and the third is the one that matters:

- **A dead feed does not fail the card.** It is annotated on the card.
- **The count is of feeds that answered**, not feeds declared. `6 of 7` means six
  returned something, and that number must never be the count of entries in the
  config.
- **All feeds dead is `down`, not an empty list.** That is the partial case's
  opposite, and it must land differently, or a merge of one broken feed and one
  quiet feed becomes indistinguishable from a healthy card.

A quiet feed — one that returned 200 and zero new items — counts as answered. That
is the correct answer, and it is the reason the badge says "feeds" rather than
"new entries".

## A panel action that silently does nothing

`panel-open` validates the panel id and refuses loudly. It does **not** validate
the context:

```
$ noctalia msg panel-open control-center nosuchsection
ok
```

Exit code `0`, no message, no panel section. Every other action in the panel has a
visible outcome — a link opens a browser, `run` opens a terminal, a failed
`control` turns the row red. A `panel:` with a bad context is the one that
reports success and delivers nothing.

So the split is deliberate and worth stating: **the panel id is the plugin's
responsibility and is checked at load; the context is the config author's, and
cannot be checked.** A card pointing at a section that no longer exists fails the
way a typo in a URL fails — silently, and only when someone presses it.

There is no fix inside the panel. The shell has no way to ask which contexts a
panel accepts. What the panel can do is refuse to invent a context that was never
declared, which is why the field is a plain string rather than an enum with
plausible-looking values to choose from.

## A list that is quietly empty

The nastiest failure in the panel, because nothing looks wrong.

```
▸ caddy routes   0 sites      ← ok, up to date, genuinely nothing
▸ caddy routes   0 sites      ← ok, the extract silently matched nothing
```

These are identical on screen. An `extract` with a precedence slip, a renamed JSON
field, or a service that changed its output format all produce the second one — a
card that is fetching fine, on schedule, with a green dot, showing nothing.

The rule this forces: **a list card that is empty but whose source previously
returned rows must not report `ok`.** It goes `warn` with "no rows" and keeps the
last good rows visible. The list existed a minute ago and now does not, and that
transition is the signal.

The general form: **a sudden drop to an empty result is a failure of the fetch, not
a fact about the world.** A service with zero hosts is possible; a service whose
host list went from six to zero without a deploy is a broken card.

## A failed action is not a stale reading

The rule above — keep the last good value, dim it, never zero it — is right for
readings and wrong for actions. A card that says "restart plex" and shows `200 ok`
from four minutes ago while the restart fails is lying, and it is lying about the
one thing you acted on.

A failed `control:` therefore surfaces immediately and independently of the card's
value:

```
▸ plex        200      from 14:02        ⚠ restart failed: 503
```

The value keeps its own staleness rules. The action gets its own, separate line,
and the row goes to `down` for the action's sake. This is a deliberate exception
to the rule above, scoped to actions only.

## A deep link that stopped resolving

The worst failure mode in the panel, because it is silent. A `deep_link` points
into another application's UI, and UI URL schemes are that application's private
business. xyOps documents its REST API thoroughly and its `#Page?args` scheme not
at all — the scheme was read out of its source.

When one breaks, the target application shows an ordinary page rather than an
error. Nothing in the panel can detect this, because from here the click worked.

The only defence is not relying on it: a `deep_link` must never be the only way to
reach a number the panel depends on. The card still shows the value; the link is
a shortcut.

## A value that failed to parse is shown as-is

Not replaced with zero, not hidden:

```
▸ proxmox-nodes   ???       ← extract returned garbage
```

Zero is the more dangerous option here: `0 nodes` reads as the truth.

## Many cards, one dead hop

Six cards reading six containers on one Proxmox node share a single point of
failure: the ssh. When the node is unreachable they all go `down` together, and the
panel shows six red rows instead of one.

That is honest but not useful, because the operator's next question is always
"which hop broke" — and the answer is not in the rows. So:

- **A failing fetch states the hop.** `pct exec 101 -- sqlite3 ...` failing on a
  dead node produces `ssh: connect to host pve.lan port 22: No route to host`, and
  that text goes in the card. The message names the cause.
- **Cards sharing a source are grouped in the zone**, so the failure reads as a
  block rather than scattered singles.

What the panel does **not** do is deduce a shared cause and collapse the rows. That
would be an inference, and an inferred "pve is down" badge on a card about Pi-hole
is a lie the moment the node is up and Pi-hole is not.

## Exit codes from a hop are not a state

`pct exec` exits non-zero both when the container is stopped and when the command
inside it failed. Same code, two very different situations, and the difference only
appears in stderr.

So a card must not map exit codes to `ok` / `warn` / `down`. A card that does gets
"container stopped" and "sqlite3 is not installed" rendered as the same green dot.
Instead: any non-zero exit is `down`, and stderr goes in the card verbatim. The
operator sees `sqlite3: command not found` instead of a green light, which is the
whole point of showing the text.

## One failed row must not blank the list

A `kind: list` card whose fetch fails keeps its last good rows and shows the age,
exactly like any other reading (D7). It does **not** collapse to an empty list —
an empty list is indistinguishable from "there genuinely are none of these things",
which is the most dangerous possible reading of a roster.

```
▸ top blocked   8 rows   from 14:02   ⚠ ssh: No route to host
```

## A command that needs PATH

`pct exec` gives no login shell, so `.bashrc` is not read and `PATH` may not
include `/usr/local/bin` or anything a package installed outside the default set.
A command that works perfectly over ssh and fails here is almost always this.

The failure looks like a missing binary, so the card goes `down` with
`sqlite3: not found` — a message that is literally true and practically wrong.
Two ways out, both acceptable:

- absolute paths in `argv`, which is the more honest config
- `PATH=/usr/local/bin:$PATH` prefixed inside the remote command, if the path is
  long enough to be unreadable inline

## Header status line

```
✓ 24 cards · 2 errors
```

Permanently visible. The panel reporting whether it can be trusted is part of
trusting the tool, not debug output.

## Timeouts

`timeout_ms` defaults to 8000. A source that misses it counts as `down` for that
attempt and must not block other cards — polling is parallel, and one hung source
must never slow the panel down.

## What the panel does not do

**Does not retry aggressively.** Monitoring a source that has been down for ten
minutes must not generate a flood of requests — that finishes off the service you
are trying to observe.

**Does not adapt the interval to the response.** A fixed `interval_sec` is
predictable; an adaptive one is not.

**Does not show a loading bar.** For a source that answers in a second, it is
visual noise.

## Degradation instead of failure

Order of events when a source is lost:

1. attempt fails → state `down`, previous value retained
2. `stale_after_sec` passes → state `stale`, previous value retained, dimmed
3. recovery → value updated, state `ok`, attempt counter reset

Never: zero the value, hide the card, or show "no data" without a reason.