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