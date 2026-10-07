# 07 — Decisions

Decision log. Format: what was decided, why, what was rejected.

---

## D1. Full-screen panel

**Decision.** `width = "fill"`, `height = "fill"`, `placement = "floating"`,
`keyboard_focus = "exclusive"`, `persistent = true`.

**Why.** The panel is opened to look, not to work in. Full screen separates it from
the desktop — the feel of a separate space rather than another window. `persistent`
keeps state between openings.

**Rejected.** `attached` to the bar — pins it to one monitor and loses meaning on
multi-monitor setups.

---

## D2. YAML, not JSON

**Decision.** `hub.yaml` plus conversion to JSON via `yq` at load time, cached in
`pluginDataDir()`.

**Why.** Comments, anchors for repeated cards, readability under hand-editing.
Across thirty LXC entries `<<: *lxc` saves more lines than the converter costs.

**Cost.** A dependency on `yq`. Repaid: conversion runs once per file change, not
per render.

**Rejected.** JSON — unreadable under hand-editing, no comments. A native Luau YAML
parser exists, but that is another dependency and another chunk of code to solve a
format problem `yq` handles in one line.

---

## D3. The config file is the source of truth

**Decision.** Everything in `hub.yaml`. `plugin.toml` carries only what the host
needs (widget instance settings, poll frequency).

**Why.** The config has to live in git: reviewable as a diff, revertible,
shareable between machines. Plugin settings live in Noctalia's `settings.toml` and
never reach git.

**Rejected.** Everything in manifest `[[setting]]` — unreadable with twenty cards,
and entering URLs through a GUI field is awkward.

---

## D4. One pipeline: fetch → extract → map → format

**Decision.** A single `source` block, one chain, `kind` affecting rendering only.

**Why.** Without this the schema diverges: `http_field`, `jq`, `regex`, `gsub` —
six mutually incompatible ways to pull one value out. A shared chain keeps one
semantics and lets a new source type plug into `fetch` without changing the schema.

**Rejected.** Separate fields per source type — inflates the schema and makes
"how do I extract a value" impossible to answer in one sentence.

---

## D5. Colour is semantic only

**Decision.** `ok` / `warn` / `down` / `stale`, mapped to Noctalia palette roles.
No free-form colour in the schema.

**Why.** An instrument panel holds together because colour means state. One red card
must read as an emergency, always. Free colour breaks that.

**Rejected.** Per-card `accent` — visually meaningless inside an eight-role palette.

---

## D6. Zones flow with their content

**Decision.** A zone takes its size from its content; the panel scrolls as a whole.

**Why.** Fixed columns break when one zone has four cards and another twelve. An
empty column three screens tall reads as a bug.

**Rejected.** A rigid grid — tidy with uniform data, broken with real data. Layout
B (rail plus focus) requires navigation, which is worse for a five-second glance.

---

## D7. Values survive source failure

**Decision.** On `down`, show the last good reading plus its age — not zero, not
"no data".

**Why.** A false alarm is worse than no alarm. Zero in monitoring is a lie: it looks
like the truth.

**Rejected.** Zeroing the value — the panel lies. Hiding the card — context is lost,
and you cannot see what exactly broke.

---

## D8. Traversal follows priority, not YAML order

**Decision.** Tab moves through cards in the order `down → warn → stale → ok`.

**Why.** YAML order is reading order for a human, not order of importance. Someone
paging through instruments should not step over normal readings to reach a failure.

**Rejected.** YAML order — it matches the visuals but not the attention model: a
failure at the end of the list comes last rather than first.

---

## D9. The GUI editor is deferred

**Decision.** Editing `hub.yaml` happens through the file only. No drag-and-drop
layout, no forms, no write-back.

**Why.** The value is in the data and its status, not in CRUD. A panel editor
(`dragSource`/`dropZone`, forms, writing back to YAML) is a large independent piece
of work, and the file covers the same need.

**When.** Once the schema has settled. Otherwise it gets rebuilt for every schema
change.

**Scope note.** This decision is about editing *the config file*, and it is
unaffected by the panel acting on the world — see [D12](#d12-the-panel-acts-but-only-by-delegating)
for `run:` and [D15](#d15-controls-live-in-their-own-zone-and-are-a-later-version)
for `control:`. The panel gained the ability to open a terminal and, later, to
write to remote systems without ever touching `hub.yaml`. An earlier wording of
this decision said "read-only panel", which stopped being true at D12 and is now
deliberately not what this says.

---

## D10. Thresholds are mandatory for numeric metrics

**Decision.** A card with `kind: metric` and no `thresholds` is treated as an
invalid config: the value renders in a neutral colour with a hint.

**Why.** Without thresholds a green metric means nothing. Is "38% memory" nominal or
an emergency? An instrument panel without thresholds is a list of numbers.

**Rejected.** Silently rendering `primary` — creates a false sense of normal.

---

## D11. Anchors are plain YAML, not a schema feature

**Decision.** Card repetition uses YAML anchors and merge keys. No template concept
in the data model, no `x-templates` block treated as configuration.

**Why.** It is a pure authoring convenience. The plugin only ever sees the expanded
result, so a card written with `<<: *lxc` is indistinguishable from one written out
in full. Inventing a template layer would mean a second merging implementation, a
second error surface, and no capability that YAML does not already provide.

**Consequence.** An unknown top-level key such as `x-templates` must be ignored after
expansion rather than treated as an error.

---

## D12. The panel acts, but only by delegating

**Decision.** A card may declare `run:`, which hands a shell command to the user's
terminal via `noctalia.runInTerminal`. `link` and `run` are mutually exclusive and
both together is a validation error. `run` is a literal string with no
interpolation.

**Why.** The panel was going to be read-only, and it turns out the most natural
click on a "Dynacat" card is not "open the URL" but "let me ssh in". Nineteen
community plugins already do this — `tailnet` runs `ssh` on click, `tailscale`
pings from a panel row, `nvim-projects` opens `cd <dir> && nvim .`. It is an
established pattern, not an invention.

Not a conflict with D9: an action is not configuration editing. The panel still
does not write to `hub.yaml`.

**Rejected.**

- *Embedding a terminal.* `plugin_api` 32 exposes no PTY. `runAsync` returns a
  finished `CommandResult`; `runStream` pushes stdout lines in with no path back
  out. No stdin, no resize, no raw mode. A real terminal emulator needs a
  host-side PTY API that does not exist — this is a missing capability, not a
  shortage of effort.
- *`run` as an argv list.* `runInTerminal` takes one string. Building argv and
  joining it back into a string is more code for no gain.
- *Interpolating source values into `run`.* A hostname discovered from an HTTP
  response is not something the user typed. Building a shell command line from it
  is an injection hole, and the escaping rules for it deserve their own decision
  rather than riding along on a free-text field.

**Consequence.** `run` is trusted input by construction — the config lives in the
user's home directory and is hand-edited — so it is passed to the shell verbatim
with no quoting. `${secret}` substitution is likewise deliberately unavailable in
`run`.

---

## D13. Console cards are read-only tails

**Decision.** `kind: console` renders the last N lines of a `stream` source. No
input field, no keystrokes.

**Why.** It is the closest thing to a terminal inside the panel that the API
actually permits, and it covers the real use: watching a log while deciding
whether something is broken. Someone who needs to type is better served by
`run:` and a real terminal window, which does not exist.

**Rejected.** An input line under the output. It would need a stdin handle the API
does not expose, so it would be a textbox that pretends to be a prompt and does
nothing.

**Consequence.** A console card holds a process open, so it needs a longer
`stale_after_sec` than a polling card, and closing the panel must tear the stream
down rather than leak readers.

---

## D14. The metric and its click target are one fact

**Decision.** `deep_link:` builds a card's click target from the source's own
`query` plus extracted fields. The plugin percent-encodes `{query}`.

**Why.** A card that counts failures should link to those failures. Writing the
criterion twice is how a config rots, and the two copies are rarely the same
string — xyOps takes `tags:_error` on its API and `result=error` in its UI. That
mapping is the target application's internal knowledge, and it changes without
warning.

**Rejected.**

- *Hand-writing both.* Two strings, one fact, no enforcement. Silently wrong.
- *A per-integration adapter.* xyOps would become a special case in the schema, and
  the next system with the same shape would become another one. The mechanism is
  generic; the knowledge stays in the user's config where they can see it.
- *Leaving encoding to the user.* `tags:_error date:>=today` contains a space and
  a `>`. Anyone who has to percent-encode a query stops writing queries.

**Consequence.** Deep links point into other applications' UIs, which are their
private business. xyOps documents its REST API thoroughly and its `#Page?args`
scheme not at all — the scheme was read out of source. A `deep_link` that stops
resolving shows an ordinary page rather than an error, so a stale one is invisible
until you notice you landed somewhere unexpected. Treat `deep_link` as a
convenience, never as the only path to a number.

---

## D15. Controls are a flag, in their own zone, and a later version

**Decision.** A card may declare a `control:` block that writes to a remote system.
Controls are grouped in a dedicated `Controls` zone, arm-confirm is mandatory, the
write result becomes the card value, and every action is logged. `control` is a
**flag, not a card kind** — `kind` keeps its single meaning, "how to draw the
reading". Deferred until after hot reload and the card editor.

**Why.** The instrument-panel metaphor was never only gauges, and the panel was
going to be read-only, which turns out to be the wrong instinct: the natural click
on a "Dynacat" card is not "open the URL" but "let me ssh in". Nothing about
reading forbids acting.

Not a conflict with D9. An action is not configuration editing; the panel still
does not write to `hub.yaml`.

**A separate zone, not buttons on indicator rows.** A real cockpit puts switches
on a switch panel rather than beside every gauge, and there is a practical reason
too: you do not mis-hit a switch because you were reading a number. Mixing them
turns the panel into a form and puts a reboot button next to a memory readout.

**Arm-confirm names the target**, not "are you sure". The panel is opened for a
five-second glance, so a mis-click is a realistic threat model, not a theoretical
one.

**The write result is the new reading.** The same feedback loop as everything else
in the panel: the response of the write becomes the card's value.

**Rejected.**

- *`kind: action`.* A separate card kind. It would give `kind` two meanings — "how
  to draw a reading" and "what this card is for" — which is the exact collapse D4
  avoided when it made `kind` affect rendering only. Every future kind would then
  have to be sorted into one bucket or the other. It also costs a new rendering
  mode for no gain, and it loses the thing that makes a control honest: a button
  labelled "restart plex" does not tell you whether plex is running right now,
  which is exactly what you need to know before pressing it. The separation the
  separate kind was meant to provide is already provided by the `Controls` zone.
- *`control` and `run` as one field.* Both "run a command", but `run` executes a
  local string the config author typed, and `control` writes to a system the panel
  does not own. Different risk, different confirmation rules, different secrets.

- *Confirmation via a host dialog.* There is none. `plugin_api` 32 has no
  `confirm`, no modal — the only host-provided dialog is `openColorPicker`, which
  exists because it is a built-in picker, not something a plugin composes. The
  two-step has to be built inside the panel.

**Consequence.** Two things this decision breaks, on purpose:

- **D7 does not apply to controls.** Values surviving failure is right for
  readings, and wrong for actions. A failed write must not leave a card looking
  nominal. This is a deliberate, narrow exception.
- **"Read-only first" stops being true.** D9's editor deferral still stands, but
  the framing does not survive, so it becomes an explicit per-version decision
  rather than a quiet drift.

Control lifecycle is a second state axis, orthogonal to `ok`/`warn`/`down`/`stale`:
`idle → armed → in-flight → ok` / `failed`. An action log ring buffer goes in the
footer, so "who restarted pve at 3am" has an answer.

**`control` joins the action mutual-exclusion set.** A card carries at most one of
`link`, `link_template`, `deep_link`, `run`, `control`. This is what stops a card
from being both a navigation target and a write target.

---

## Open questions

**Default interval.** 60s is reasonable for services, excessive for releases.
Should `kind: release` ignore `interval_sec` and poll every 15 minutes instead?
Leaning yes: releases get their own timer.

**Behaviour at high card counts.** Beyond roughly 80 cards a render budget and
possibly virtualisation will be needed. The actual limit is unknown.

**Desktop widget.** A separate `desktop_widget.luau` showing the same summary as the
bar indicator. Useful only if the bar widget is not enough — an open question.