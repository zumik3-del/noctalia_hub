# 07 — Decisions

Decision log. Each entry: what was decided, why, what was rejected.

---

## D1. The panel is not `persistent`

**Decision.** `keyboard_focus = "exclusive"`, **not** `persistent = true`.

**Why.** Noctalia rejects `persistent` together with exclusive focus, and the design
needs the focus: `esc`, `r`, `/` and `1`…`9` are the navigation model, and
`capture_keys` only delivers to a focused entry. The choice is between `persistent` and
exclusive focus, and the keyboard wins. The cost is that panel state does not survive a
close — near free, since everything is rebuilt from `noctalia.state`.

**Rejected.** `persistent` with `keyboard_focus = "on_demand"` — the one combination
that keeps both, but keys are captured only while the panel holds focus, so the keyboard
model stops being reliable exactly where it matters: inside the search field. (D24/D25
later moved the panel to `attached`, 860x620; the focus reasoning stands.)

---

## D2. YAML, not JSON

**Decision.** `hub.yaml` plus conversion to JSON via `yq` at load time, cached in
`pluginDataDir()`.

**Why.** Comments, anchors for repeated cards, readability under hand-editing. Across
thirty LXC entries `<<: *lxc` saves more lines than the converter costs, and conversion
runs once per file change, not per render.

**Rejected.** JSON (unreadable, no comments); a native Luau YAML parser (another
dependency to solve a format problem `yq` handles in one line).

---

## D3. The config file is the source of truth

**Decision.** Everything in `hub.yaml`. `plugin.toml` carries only what the host needs
(widget instance settings, poll frequency).

**Why.** The config has to live in git: reviewable as a diff, revertible, shareable.
Plugin settings live in Noctalia's `settings.toml` and never reach git.

**Rejected.** Everything in manifest `[[setting]]` — unreadable with twenty cards.

---

## D4. One pipeline: fetch → extract → map → format

**Decision.** A single `source` block, one chain, `kind` affecting rendering only.

**Why.** Without it the schema diverges into six mutually incompatible ways to pull one
value out. A shared chain keeps one semantics and lets a new source type plug into
`fetch` without changing the schema.

**Rejected.** Separate fields per source type — "how do I extract a value" becomes
impossible to answer in one sentence.

---

## D5. Colour is semantic only

**Decision.** `ok` / `warn` / `down` / `stale`, mapped to Noctalia palette roles. No
free-form colour in the schema.

**Why.** An instrument panel holds together because colour means state. One red card
must read as an emergency, always.

**Rejected.** A per-card `accent` — visually meaningless inside an eight-role palette.

---

## D6. Zones flow with their content

**Decision.** A zone takes its size from its content; the panel scrolls as a whole.

**Why.** Fixed columns break when one zone has four cards and another twelve. An empty
column three screens tall reads as a bug.

**Rejected.** A rigid grid — tidy with uniform data, broken with real data. Layout B
(rail plus focus) requires navigation, worse for a five-second glance.

**Exception.** `pin: bottom` takes a zone out of the flow and fixes it to the footer. It
is background and must not push content around as its numbers change; at most one zone
may pin.

---

## D7. Values survive source failure

**Decision.** On `down`, show the last good reading plus its age — not zero, not "no
data".

**Why.** A false alarm is worse than no alarm. Zero in monitoring is a lie: it looks
like the truth.

**Rejected.** Zeroing the value (the panel lies); hiding the card (context is lost).

---

## D8. Traversal follows priority, not YAML order

**Decision.** Tab moves through cards `down → warn → stale → ok`.

**Why.** YAML order is reading order for a human, not order of importance. Someone paging
through instruments should not step over normal readings to reach a failure.

**Rejected.** YAML order — matches the visuals, not the attention model.

---

## D9. The GUI editor is deferred

**Decision.** Editing `hub.yaml` happens through the file only. No drag-and-drop layout,
no forms, no write-back.

**Why.** The value is in the data and its status, not in CRUD. A panel editor
(`dragSource`/`dropZone`, forms, YAML write-back) is a large independent piece of work,
and the file covers the same need. It lands once the schema has settled, or it gets
rebuilt for every schema change.

**Note.** This is about editing the config file, not about the panel acting on the world
— `run:` (D12) and `control:` (D15) never touch `hub.yaml`.

---

## D10. Thresholds are mandatory for numeric metrics

**Decision.** A card with `kind: metric` and no `thresholds` is an invalid config.

**Why.** Without thresholds a green metric means nothing — is "38% memory" nominal or an
emergency? An instrument panel without thresholds is a list of numbers.

**Rejected.** Silently rendering `primary` — a false sense of normal.

---

## D11. Anchors are plain YAML, not a schema feature

**Decision.** Card repetition uses YAML anchors and merge keys. No template concept in
the data model, no `x-templates` block treated as configuration.

**Why.** A pure authoring convenience: the plugin only sees the expanded result, so a
card written with `<<: *lxc` is indistinguishable from one written out in full. A
template layer would be a second merging implementation, a second error surface, and no
capability YAML does not already provide.

**Consequence.** An unknown top-level key (`x-templates`) must be ignored after
expansion rather than treated as an error.

---

## D12. The panel acts, but only by delegating

**Decision.** A card may declare `run:`, which hands a shell command to the user's
terminal via `noctalia.runInTerminal`. `run` is a literal string with no interpolation.

**Why.** The most natural click on a "Dynacat" card is not "open the URL" but "let me
ssh in" — an established pattern in nineteen community plugins. Not a conflict with D9:
an action is not configuration editing.

**Rejected.** Embedding a terminal (`plugin_api` 32 has no PTY — a missing capability,
not a shortage of effort); `run` as an argv list (`runInTerminal` takes one string);
interpolating source values into `run` (an HTTP-derived hostname is not your own typing;
building a command line from it is an injection hole).

---

## D13. Console cards are read-only tails

**Decision.** `kind: console` renders the last N lines of a `stream` source. No input
field, no keystrokes.

**Why.** It is the closest thing to a terminal the API permits, and it covers the real
use: watching a log while deciding whether something is broken. Someone who needs to type
is better served by `run:` and a real terminal window.

**Rejected.** An input line under the output — a textbox that pretends to be a prompt and
does nothing, needing a stdin handle the API does not expose.

**Consequence.** A console card holds a process open, so it needs a longer
`stale_after_sec`, and closing the panel must tear the stream down.

---

## D14. The metric and its click target are one fact

**Decision.** `deep_link:` builds a card's click target from the source's own `query`
plus extracted fields. The plugin percent-encodes `{query}`.

**Why.** A card that counts failures should link to those failures. Writing the criterion
twice is how a config rots, and the two copies are rarely the same string — xyOps takes
`tags:_error` on its API and `result=error` in its UI.

**Rejected.** Hand-writing both (two strings, one fact, silently wrong); a
per-integration adapter (the mechanism is generic, the knowledge stays in the user's
config); leaving encoding to the user (anyone who has to percent-encode a query stops
writing queries).

**Consequence.** UI URL schemes are an application's private business, and a stale
`deep_link` shows an ordinary page rather than an error. Treat it as a convenience, never
the only path to a number.

---

## D15. Controls are a flag, in their own zone, a later version

**Decision.** A card may declare a `control:` block that writes to a remote system.
Controls are grouped in a dedicated `Controls` zone, arm-confirm is mandatory, the write
result becomes the card value, and every action is logged. `control` is a **flag, not a
card kind**. Deferred until after hot reload and the card editor.

**Why.** Nothing about reading forbids acting, and the instrument-panel metaphor was
never only gauges. A separate zone (not buttons on indicator rows) keeps a reboot button
off a memory readout. Arm-confirm names the target, not "are you sure" — the panel is
opened for a five-second glance, so a mis-click is a realistic threat model. The write
result is the new reading, the same feedback loop as everything else.

**Rejected.** `kind: action` — it gives `kind` two meanings, the exact collapse D4
avoided, and it loses what makes a control honest: a button labelled "restart pocketbase"
does not tell you whether pocketbase is running. `control` and `run` as one field —
`run` executes a local string the author typed, `control` writes to a system the panel
does not own. A host dialog — `plugin_api` 32 has no modal, so the two-step is built
inside the panel.

**Consequences.** D7 does not apply to controls: a failed write must not leave a card
looking nominal. Control lifecycle is a second axis: `idle → armed → in-flight → ok` /
`failed`. `control` must not share a card with another action.

---

## D16. Lists are a rendering kind

**Decision.** `kind: list` renders an array of values, collapsed to a count and expanded
on Enter.

**Why.** Some real readings are inherently plural, and collapsing them into one number
is information loss. `list` genuinely changes how the value is *drawn*, which is exactly
what `kind` means — a `list:` flag on a `metric` card would have `kind` describing two
things.

**Colour comes from the fetch, not the contents.** A list has no thresholds: there is no
defensible `warn` for "here are some domain names". `ok` / `warn` / `down` / `stale`
describe whether the list could be *read*. One exception, about the fetch: a list that
was non-empty and is now empty goes `warn` ([06](06-failure-modes.md)).

**Rejected.** A `list:` block instead of a kind (same fault as D15); a
`limit:`/`offset:` paging block (the panel is not a table); per-row colour or thresholds
(invented semantics).

**Consequence.** `extract` may now yield several values, with `map` / `format` applied
per value. `format` on a list card is the *collapsed* label, not a row template.

---

## D17. Remote containers compose; they do not get a source type

**Decision.** A service inside an LXC is read with `type: command` and an `argv` that
runs `ssh <node> "pct exec <vmid> -- <command>"`. No `type: proxmox`.

**Why.** The hop is already expressible, and a dedicated type would be a wrapper the
plugin would have to keep in step with `command` forever. With `argv`, everything after
the host is a **single string argument** that the remote shell parses once; `cmd` would
need a local shell and three layers of quoting to get one command through. `parse: json`
is part of this, not a separate feature: reaching a JSON-emitting command is common
enough to be a declaration rather than a `jq` pipeline in a shell string.

**Rejected.** `type: proxmox` (a wrapper with no behaviour of its own); a `proxmox:`
block beside `source:` (worse ergonomics); `${var}` for the VMID (YAML anchors merge
mappings, they do not concatenate strings); reaching the container's HTTP API directly
(possible and preferable when it works — `pct exec` is the fallback for localhost-bound
services).

**Consequence.** `pct exec` gives no login shell, so PATH may be minimal; its exit code
does not distinguish "container stopped" from "command failed".

---

## D18. A description is a second line

**Decision.** `description:` holds one line of prose. (D25 later makes it the second line
of every card.)

**Why.** Eighteen monitored services, each with a line explaining what it is, doubles the
zone's height — the failure this project exists to avoid. But it earns its place the
moment you focus one card.

**Rejected.** A `show_descriptions` switch — the line is not optional, it is the card's
own; a zone with more descriptions than it wants is a zone to split. A tooltip — a
description you only see by pointing is one nobody reads. Folding it into `title` —
`Proxmox — Web interface for Proxmox VE` is a title nobody can scan.

---

## D19. Many feeds merge into one card, sorted by date

**Decision.** An `rss` source takes either a single `url` or a `feeds` mapping of label
to URL. Merged feeds are always sorted newest-first. No `sort` field.

**Why.** Sixteen watched repositories on sixteen rows is a list, not a panel; the useful
question is "what shipped recently", and that needs all sixteen in one place. Feeds are a
mapping because the label is load-bearing: a version with no repository attached is not
information.

**Rejected.** One card per feed (sixteen rows to answer one question); a `sort` field
(two timelines cannot be concatenated, so newest-first is the only coherent merge);
keeping feed order (a rotation through whichever repo is listed first, not a merge).

**Consequence.** A dead feed inside a merge must not fail the card
([06](06-failure-modes.md)).

---

## D20. The panel invokes other panels; it never mounts them

**Decision.** A card may declare `panel: "<id> [context]"`, which runs `noctalia msg
panel-open` directly through `runAsync` and opens no terminal window. Panel ids are
validated at load time. Mounting another plugin's surface is out of reach entirely.

**Why a separate field when `run` already does this.** `run: "noctalia msg panel-open
..."` works but flashes a terminal window to display the word `ok`. The two actions share
a mechanism and must not share a cost model.

**Why `panel-open`, not `togglePanel`.** `togglePanel` inverts — two presses close the
panel — which is right for a bar widget toggling its *own* panel and wrong for a card.
Idempotence is the whole reason the CLI command exists.

**Panels cannot be embedded.** No WebView, iframe or HTML in `plugin_api` 32, and the
calendar/weather data is held in memory with no file to read. **There is no generic way
to read another plugin's data**: `noctalia.state` is shared but has no discovery, schema
or negotiation. Cross-plugin events (`noctalia msg plugin …`) are one-way and opt-in, so
a card cannot send an event and get a result.

**Rejected.** A `plugin:` block with `entry`/`event`/`payload` (an action with no return
path); mounting a panel's contents (no API exists); reading another plugin's state keys
as a source (works until the other plugin renames a key, and nothing detects that).

**Consequence.** Panel ids are **checkable** — the shell validates and lists what exists.
Contexts are **not** — an invalid section exits `0` and prints `ok`.

---

## D21. The look is portable, the data is not

**Decision.** A card may be rendered by code ported from the shell's own widget source.
The port is frozen at a known version, attributed, and its version shown in the panel.
Vendored code may *present*; it may never *fetch*.

**Why.** The shell is open source (MIT), and a widget's look is a layout plus a palette —
no shader, no custom painting. The shell's widgets and plugin widgets build the same node
tree through the same vocabulary and one reconciler, so copying the look is cheap.

**Three costs.** Layout is manual in C++ and reconciled in Luau (the same geometry
converges, it does not match); the service pointer is unreachable (the data is public
JSON anyway); per-widget colour overrides are missing (`getColor(role)` gives theme
roles).

**Rejected.** Vendoring the C++ (a plugin is Luau); reading the service from a plugin
(not exposed, and the data is public); tracking upstream (declined — shell design changes
do not propagate, which is the point).

**Consequence.** The panel is no longer fully described by `hub.yaml`; the version in the
footer keeps "the panel changed" and "the panel broke" distinguishable. It does not
breach the no-markup boundary: Luau is not markup, and the config still describes only
data.

---

## D22. The kind set is closed at six

**Decision.** `kind` is exactly `status`, `metric`, `release`, `link`, `console`,
`list`. `graph` is a presentation field on any card, not a kind. A plain text reading is
`status`.

**Why.** An earlier draft listed eight, adding `graph` (already a field) and `text` (no
rendering of its own). Six is the number of genuinely distinct drawings, and a closed set
makes "does this need a new kind?" answerable: only if it draws differently.

**Rejected.** Keeping eight and documenting `graph` twice; folding `console` or `list`
into flags (they change the drawing, which is what a kind is).

---

## D23. `split:` turns a text line into fields

**Decision.** A `list` card's source may declare `split: <delimiter>`, which splits each
text row into indexed fields before `row_format` / `extract_lines` run. `whitespace` is a
reserved delimiter that collapses runs. Fields are indexed from `0`.

**Why.** `kind: list` could take one field per row from JSON, but a tool that emits fixed
text columns (`df -P`, `pct list`) could not be read at all — the only way was `awk` or
`sed` inside a shell string, the quoting this project refuses everywhere else.

**Why `whitespace` is a value and not a second field.** Whitespace-separated columns are
the common case, and splitting on a single space leaves empty fields wherever columns are
aligned. A `collapse:` flag whose only legal value is `true` should not exist.

**Rejected.** A regex split (a second language for a case that has not appeared); doing
it inside `extract` (jq runs on JSON; a text row has not been parsed yet).

---

## D24. The panel framework is ported from github-kanban

**Decision.** The card blocks, header menu, tab strip, font scale and density come from
github-kanban. The shape knobs live in `hub.yaml` under `layout:`, and the panel moves to
`placement = "attached"` with `open_near_click = true`.

**Why.** github-kanban is a shipped, working Noctalia panel built on the same `ui.*`
reconciler; its framework is the instrument-panel look this project chases, already paid
for. The knobs go in `hub.yaml` because the config is the product — a second settings
surface would split one visual decision across two files. Shape is config; colour stays
the palette (D5).

**Rejected.** Copying kanban's free-form colour settings (D5); copying its `appearance_*`
keys into the manifest; a hover effect that changes a reading.

---

## D25. The card is github-kanban's activity row; `overview` is the landing tab

**Decision.** Every card draws as github-kanban's activity row: a glyph badge on the
left, a two-line column (title, then description), and the reading with its state marker
on the trailing edge. A card with no `description` is one line tall. The first tab is
`overview`, reserved for the custom dashboard and blank in this build; each other tab
shows one zone. The panel is 860x620.

**Why.** The activity row is the reading shape — a thing, what it is, and its value, in
the order a person reads them. The old single line had nowhere for a description. The
author wants a landing tab to grow a custom dashboard on, so `overview` takes that slot.

**Why the failure moved off the card.** The reason a card is not ok lives on the **state
marker's tooltip**, and the description keeps its line. A failure that replaces what the
card measures produces a card you cannot read while it is broken — the one moment you
most want to know what it is.

**Rejected.** A `show_descriptions` switch (D18); naming the landing tab in `hub.yaml`
(it is built in, stored under the empty string so a zone called `overview` cannot
collide); copying kanban's avatar images (hub has no images — the badge is the glyph on a
tinted square, kanban's own no-avatar fallback).

---

## D26. Actions are buttons; the one-action rule is retired

**Decision.** An action renders as a button on the card's trailing edge, not as a hit
area over the whole card. `link` and `run` may sit on one card. The "at most one action"
rule (D15) no longer applies to the navigational actions; `control` stays out of the
button set until its step lands.

**Why.** The one-action rule existed to stop an ambiguous click target. A button removes
the ambiguity by construction: "a link and a terminal on the Pi-hole card" is a card with
two clearly separated controls, the same shape as the header's refresh and close buttons.

**Rejected.** Folding the actions into a menu (worse for a five-second glance than two
icons); a separate `terminal:` field (`run:` already carries the command); drawing
`link_template` / `deep_link` / `panel` as buttons now (each needs its own interpolation
or target resolution).

---

## D27. `kind: status` draws only its dot

**Decision.** A `status` card renders no value column; `format` and `unit` have no
effect. Metric, release, link, console and list cards are unchanged.

**Why.** On a status card the value was a restatement of the dot, and the dot is the
faster read. Removing it gives the trailing edge back to the update badge and the action
buttons. A failure still explains itself on the dot's tooltip.

**Rejected.** A per-card `show_value: false` flag (two ways to say "just the dot"); the
value hidden only when `ok` (the card changes height as it changes state).

---

## D28. OS updates are a card's second reading

**Decision.** A card may carry an `updates` block: a source printing the pending package
count, a `run` that installs them, an optional interval (default one hour). The count
draws as a warn-coloured badge left of the state dot. Zero draws nothing; a failed check
draws a dim red glyph with its reason on the tooltip. The count is the button.

**Why this shape.** The update count is not the card's state — Pi-hole can be up with
updates pending, and a broken `ssh` for the count is not a broken Pi-hole — so it is a
second reading with its own state, not a threshold on the dot and not a separate card.

**Why zero draws nothing.** A badge that says `0` is a permanent reassurance nobody
reads, and it competes with the badge that says `43`. The check's failure is the one case
that must not be silent, so it gets a glyph.

**Why the distribution is in the config.** Debian is `apt-get`, Alpine is `apk`, and the
two need different commands. A `family:` field would be the integration wrapper D17
refuses for Proxmox.

**Rejected.** A generic `badge:` second reading (the more general field is the more
general problem); counting updates in the header's error total (the trust line is about
failed cards); trusting a `0` from a failed `grep -c`.

---

## D29. One view layer, and no module holds state

**Decision.** `visual.luau` holds what both surfaces draw; `rows.luau` / `zones.luau`
hold the card and the zone. None of the three reads `noctalia.state` or the filesystem;
each takes a `view` built by the panel on every render. `util.luau` holds the shared type
predicates and the one placeholder glyph.

**Why this shape.** The signal roles were written out twice and had already drifted (the
bar missing `pending`). A role is one fact — a colour and a glyph — so it gets one
address. The same argument moved `glyphLabel`, the card wrapper and its hover closure,
and the `isString` / `isNumber` definitions.

**Why modules take a `view`.** The panel's `doc` and `cards` are replaced by their
watches; a module holding its own copy would draw a reading the collector had already
moved past.

**Why hover state lives in `visual.luau`.** It is a render-time decision shared by both
card shapes and needs a redraw; modules share no Lua memory, so the panel registers its
`render()` with `Visual.setRedraw`.

**Defaults live where the schema is validated.** `Config.DEFAULT_LAYOUT` and
`Config.DEFAULT_MAX_ITEMS` are exported and read by the panel and the pipeline — a
default written twice is the same number waiting to drift, and it drifts silently.

**Rejected.** A context module the panel sets once (goes stale the moment a watch fires);
modules reading `noctalia.state` directly (a second subscription in every render file);
naming every literal in one file (a table nobody reads).

---

## D30. A card's second row of facts is a field, not a kind

**Decision.** A card may carry `mini_cards`: a list of tiles, each static (`{ label,
value, link? }`) or dynamic (`{ label, source, thresholds?, interval_sec?, link? }`),
drawn on the trailing edge, left of the update badge.

**Why a field, not a kind.** The card is still a `metric`, still fetches, still draws its
reading; the tiles are a second row of facts about the same host, and a new kind would
have meant a new fetch, extract and state for what is a render of the config.

**Why left of the update badge.** The trailing edge is where the card's facts live. The
tiles are readings, so they sit with the readings; a click on a tile is not a click on an
action, and the two must not share a target.

**Why the card's own pipeline.** A dynamic tile reuses `source → fetch → evaluate`
unchanged, with `thresholds` and `unit` as on a card's reading. A tile draws in colour
only when something is wrong: `warn` / `down` take the state colour, `ok` is neutral
whether a threshold produced it or not — a green "0 failed" is noise. It gets its own
interval (3600 default) and its own record nested in the card's, the way `updates` is. No
staleness — either fresh or `down`, and a failed fetch keeps the last good value.

**Why a tile may carry a `link`.** A tile is a fact about a host, and the host is usually
one click away — the Proxmox UI, the failed-jobs search. A `link` makes the tile a button
that fires the same `link` action a card's own button does, so it opens the target
directly. It answers the pointer with a stronger fill, because a target that does not
answer the pointer reads as decoration. It is a plain URL, not a `deep_link` template: a
tile is one fact, and a URL that substitutes the reading is the card's job.

**Rejected.** A new `kind: mini` (a kind is "how to draw the reading", and these tiles
have no reading); reusing `format` for the tiles (a different fact with its own labels).

---

## Smaller decisions

- **Release polling is explicit, never per-kind.** `kind: release` gets no timer — a kind
  affects rendering only (D4); the example sets `interval_sec` on the Releases domain.
- **No card cap.** Zones flow and the panel scrolls (D6), so card count is a performance
  question; a config above roughly 100 cards gets a load-time *warning*, not an error.
- **No desktop widget.** The bar summary plus a hotkey is the entry point.
- **A vendored renderer draws a zone, not a kind.** `kind:` stays closed at six (D22).
- **No events to other plugins.** A one-way send with no return path is the "rejected
  write" failure mode (D15) without the confirmation that makes a control survivable.
