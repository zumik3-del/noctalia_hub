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

**Decision.** The first version is a read-only panel. Editing happens through the
file only.

**Why.** The value is in the data and its status, not in CRUD. A panel editor
(`dragSource`/`dropZone`, forms, writing back to YAML) is a large independent piece
of work, and the file covers the same need.

**When.** Once the schema has settled. Otherwise it gets rebuilt for every schema
change.

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

## Open questions

**Default interval.** 60s is reasonable for services, excessive for releases.
Should `kind: release` ignore `interval_sec` and poll every 15 minutes instead?
Leaning yes: releases get their own timer.

**Behaviour at high card counts.** Beyond roughly 80 cards a render budget and
possibly virtualisation will be needed. The actual limit is unknown.

**Desktop widget.** A separate `desktop_widget.luau` showing the same summary as the
bar indicator. Useful only if the bar widget is not enough — an open question.