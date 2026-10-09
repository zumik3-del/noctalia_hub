# 07 — Decisions

Decision log. Format: what was decided, why, what was rejected.

---

## D1. Full-screen panel, without `persistent`

**Decision.** `width = "fill"`, `height = "fill"`, `placement = "floating"`,
`dismiss_on_outside_click = false`, `keyboard_focus = "exclusive"`. **Not**
`persistent = true`.

**Why.** The panel is opened to look, not to work in. Full screen separates it from
the desktop — the feel of a separate space rather than another window.

**`persistent` is not a preference, it is unavailable.** Noctalia rejects it
together with exclusive keyboard focus, and this design needs the focus:

```
$ noctalia plugins lint hub/
  error  panel entry 'panel': persistent = true is incompatible with keyboard_focus = "exclusive"
```

It also requires `placement = "floating"` and `dismiss_on_outside_click = false`,
and `keyboard_focus = "none"` requires `dismiss_on_outside_click = false` too. The
choice is therefore between `persistent` and exclusive focus, and the keyboard
wins: `return`, `/`, `r` and `1`…`9` are the whole navigation model (see
[02](02-layout.md)), and `capture_keys` only delivers to an entry holding focus.

**What is given up.** Panel state does not survive a close. That costs scroll
position and the current selection between openings — for a live monitoring panel
this is close to free, because everything on it is rebuilt from `noctalia.state`
anyway and a stale scroll position would be wrong more often than helpful.

**Rejected.**

- *`attached` to the bar* — pins it to one monitor and loses meaning on
  multi-monitor setups.
- *`persistent` with `keyboard_focus = "on_demand"`* — the one combination that
  keeps both. Rejected because on-demand focus means keys are captured only while
  the panel holds focus, and the keyboard model stops being reliable exactly where
  it matters: inside the search field.

**Superseded in part.** D24 moved the panel to `placement = "attached"` beside the
widget, and D25 set the size to github-kanban's 860x620 and turned on
`dismiss_on_outside_click`. The `persistent`-versus-exclusive-focus reasoning above
still holds — the panel is not persistent, and exclusive focus is still why. The
full-screen, `"fill"` and floating clauses no longer describe the panel.

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

**One exception: the footer.** A zone may declare `pin: bottom`, which takes it out
of the flow and fixes it to the panel footer. The system readout and the action log
live there: they are background, always visible, and must not push content around as
their numbers change. At most one zone may pin, so the footer stays a fixed strip
rather than a second column of zones.

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
terminal via `noctalia.runInTerminal`. `run` is a literal string with no
interpolation. (`link` and `run` were once mutually exclusive; D26 makes both
trailing buttons, so they may share a card.)

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
  labelled "restart pocketbase" does not tell you whether pocketbase is running right now,
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
`link`, `link_template`, `deep_link`, `panel`, `run`, `control`. This is what stops
a card from being both a navigation target and a write target.

**Superseded in part.** D26 makes actions trailing *buttons*, so two navigational
actions on one card are no longer ambiguous and are allowed. The mutual exclusion
now scopes to `control` alone: it is the one action that changes something and must
not share a card with another.

---

## D16. Lists are a rendering kind

**Decision.** `kind: list` renders an array of values. A list card is collapsed to a
count and expands on Enter.

**Why.** Some real readings are inherently plural: the top eight blocked domains,
the hostnames Caddy routes, the branches someone is waiting on. Collapsing each of
those into a single number is not a summary, it is information loss — there is no
one number for "which domains is my network asking for".

**Why it is a kind and not a flag.** D15's argument applies with more force here.
`list` genuinely changes how the value is *drawn* — many rows instead of one — which
is exactly what `kind` means and all it means. A `list:` flag on a `metric` card
would have `kind` describing two things at once.

**Colour comes from the fetch, not the contents.** A list has no thresholds. There
is no defensible `warn` level for "here are some domain names" — a list of 400,000
blocked domains is not a warning, it is a Tuesday. `ok` / `warn` / `down` / `stale`
describe whether the list could be *read*. Anything else invents a judgement the
panel has no basis for, and D5 already commits to colour meaning one thing only.

**One exception, and it is not about the contents.** A list that was non-empty and
is now empty goes `warn`, because that is a fact about the fetch, not about the
data. An empty result from a source that has just started returning rows is fine;
one that follows six rows is a broken card, and without this rule it looks
identical to a healthy card reporting nothing.

**Collapsed by default.** The panel is a glance, and the list is the answer to the
follow-up question. Expanding must be deliberate or every glance costs a scroll.
`max_items` bounds what the expand reveals, so "top 8" stays top 8 rather than
becoming an unbounded scroll target inside a fullscreen panel.

**Rejected.** A `list:` block instead of a kind — same fault as D15, `kind` stops
meaning one thing. A `limit:`/`offset:` block for paging — the panel is not a table
and paging invites the reader to treat it as one. Per-row colour or thresholds —
invented semantics.

**Consequence.** `extract` may now yield several values where it previously yielded
one, so the pipeline's contract widens from "one value" to "one or many", with
`map` and `format` applied per value. `format` on a list card is the *collapsed*
label, not a row template. A list card that fails to fetch follows D7 and keeps its
last good rows plus an age.

---

## D17. Remote containers compose; they do not get a source type

**Decision.** A service inside a Proxmox LXC is read with `type: command` and an
`argv` that runs `ssh <node> "pct exec <vmid> -- <command>"`. There is no
`type: proxmox`, and no `parse: json` beyond what `command` needs for its own
output.

**Why.** The hop is already expressible, and a dedicated type would add schema
surface to buy nothing. Worse, the obvious shape — `proxmox:` with a `vmid` field
and a nested command — is a wrapper the plugin would have to keep in step with
`command` forever, so every fix to command handling would need applying twice.

**`argv` rather than `cmd`, and this matters.** With `argv`, everything after the
host is a **single string argument**:

```yaml
argv: ["ssh", "pve.home.lan", "pct exec 100 -- pihole -q --list"]
```

`ssh` forwards that one argument to the remote shell verbatim, which parses it once.
With `cmd`, the same command needs a local shell, which then has to survive being
wrapped in quotes that the remote shell re-interprets — three layers of quoting to
get one command through. `argv` removes a layer rather than documenting around it.
This is the same reasoning as D12's no-interpolation rule: the fewer parsers a
string crosses, the fewer ways it can be silently wrong.

**`parse: json` is part of this, not a separate feature.** Reaching a JSON-emitting
command is common enough (`caddy adapt`, `sqlite3 -json`, `docker inspect`) that it
needs to be a declaration rather than a `jq` pipeline buried in a shell string.
Once declared, the same `extract` works as it does for `http` — the pipeline does
not know or care which source type produced the bytes.

**Rejected.**

- *`type: proxmox`.* A wrapper with no behaviour of its own; see above.
- *A `proxmox:` block alongside `source:`.* Same wrapper, worse ergonomics — it puts
  the transport in the card instead of the source, and D4 already fixed the layer
  that fetches.
- *`${var}` for the VMID.* No such need. Each card targets a different container,
  so there is no repeated string to factor out, and YAML anchors cannot build one
  from parts anyway — they merge mappings, they do not concatenate strings.
- *Reaching the container's HTTP API directly.* Possible where the service listens
  on a routable address, and preferable when it works. `pct exec` is the fallback
  for services bound to localhost inside the container, which is the common case
  for exactly the services worth watching.

**Consequence.** `pct exec` gives no login shell, so PATH is minimal and
`PATH=`-prefixing or absolute paths may be required. Its exit code does not
distinguish "container stopped" from "command failed", so cards must let a failed
fetch become `down` with the text in the card rather than trying to decode the
exit status.

---

## D18. A description is a second line on the selected card only

**Decision.** `description:` holds one line of prose. It renders on the selected
card and on expanded list rows, and nowhere else.

**Why.** Eighteen monitored services, each with a line explaining what it is.
Showing all eighteen at once doubles the zone's height, and a zone taller than the
screen is the failure this project exists to avoid. But the description earns its
place the moment you focus one card, which is exactly what selection means.

**Rejected.**

- *Always on.* It is not a rendering detail, it is a layout decision taken per card
  that belongs to the zone. Sixteen cards in a zone either fit or do not, and the
  author cannot know which without trying.
- *A tooltip.* The panel is keyboard-first and there is no hover; a description you
  only see by pointing at it is a description nobody reads.
- *Folding it into `title`.* `Proxmox — Web interface for Proxmox VE` is a title
  nobody can scan, because the part you scan by is buried mid-string.

**Consequence.** A zone that wants descriptions always visible has no switch for it,
and that is deliberate: a domain-level `show_descriptions` was considered and
rejected (see the resolved questions below). A zone that feels it needs one has too
many cards in it; the fix is to split the zone, not to add a toggle.

**Superseded in part.** D25 makes the description the second line of *every* card.
The rejection of a `show_descriptions` switch stands on its own: there is no switch
because the line is not optional, it is the card's own.

---

## D19. Many feeds merge into one card, sorted by date

**Decision.** An `rss` source takes either a single `url` or a `feeds` mapping of
label to URL. Merged feeds are always sorted newest-first. No `sort` field.

**Why.** Sixteen watched repositories on sixteen rows is a list, not a panel. The
useful question is "what shipped recently", and that needs all sixteen in one
place. Feeds are a mapping rather than a list because the label is load-bearing: a
version with no repository attached is not information.

**Rejected.**

- *One card per feed.* Technically simplest and it is what the first draft of the
  schema already implied. It also produces sixteen rows to answer one question.
- *A `sort` field.* There is no wrong answer to offer. Two timelines cannot be
  concatenated, so newest-first is the only coherent merge; a knob here would only
  allow configurations that are wrong.
- *Keeping feed order.* That is not a merge, it is a rotation through whichever
  repository happens to be listed first.

**Consequence.** One dead feed inside a merge must not fail the card — the other
five still have fresh entries, and a panel that goes red because one repository
renamed its feed is a panel that gets ignored. Partial merges are the failure mode
to design against; see `docs/06-failure-modes.md`.

---

## D20. The panel invokes other panels; it never mounts them

**Decision.** A card may declare `panel: "<id> [context]"`, which runs
`noctalia msg panel-open` directly through `runAsync` and opens no terminal
window. Panel ids are validated at load time against the shell's own registry.
Mounting another plugin's surface inside the panel is out of reach entirely.

**Why a separate field when `run` already does this.** `run: "noctalia msg
panel-open control-center calendar"` works. It also flashes a terminal window open
to display the word `ok`, because `run`'s whole contract is that the user asked to
watch a command run. A command that returns instantly and prints nothing anyone
reads is not delegation, it is a regression wearing delegation's clothes. The two
actions share a mechanism and must not share a cost model.

**`panel-open`, not `togglePanel`.** The Lua API only offers `togglePanel`, which
inverts — two presses and the panel closes. Every community plugin that opens
panels programmatically moved to `panel-open`, and `cider` documents the swap in
its README. Idempotence is the whole reason the CLI command exists.

**Panels cannot be embedded, and this is not an effort question.** There is no
WebView, no iframe and no HTML in `plugin_api` 32 — the panel is a declarative
`ui.*` tree and a plugin's panel is its own surface. Noctalia's calendar and
weather are reachable only as control-center sections; their data is held in
memory, fetched from CalDAV or Google, with nothing in `state.toml` but discovery
metadata. There is no file to read and no surface to mount. That data boundary is
absolute. The *rendering* of those widgets is a different matter, and open source
makes it portable — see [D21](#d21-the-look-is-portable-the-data-is-not).

**There is no generic way to read another plugin's data.** `noctalia.state` is a
shared key-value store — that is how a plugin's `service.luau` talks to its own
`panel.luau` — so a hub *could* read a key another plugin chose to publish. But
there is no discovery, no schema and no negotiation: it works only for a plugin
that published a key the hub already knows by name. That is a private convention,
not an API.

**What does work for cross-plugin communication** is
`noctalia msg plugin <author/plugin:entry> <target> <event> [payload]`, which
dispatches an event to a plugin entry. It is one-way and opt-in: the receiving
entry must implement an `onIpc` callback, and the shell distinguishes "no entry
matched", "entry not ready" and "entry has no `onIpc`". Recorded rather than
exposed in the schema — a card cannot send an event and get a result back, so it
would be an action with no observable outcome.

**Rejected.**

- *A `plugin:` block with `entry`, `event` and `payload`.* An action with no
  return path. The panel could tell the user it dispatched something and have no
  idea whether anything happened, which is the "rejected write" failure mode from
  D15 with none of the confirmation that makes it survivable.
- *Mounting a panel's contents.* No API exists. Recording it as out of scope
  stops the question being reopened every time someone asks for an embed.
- *Reading another plugin's state keys as a data source.* It works until the other
  plugin renames a key, and nothing detects that. A card that silently shows stale
  data because a neighbour changed its internals is worse than no card.

**Consequence.** Panel ids are **checkable**: the shell validates and, on failure,
lists every panel that exists. A typo becomes a config error on the offending card
rather than a click that does nothing. Contexts are **not** checkable — an invalid
section exits `0` and prints `ok`. The panel id is the plugin's problem; the
context is the config author's.

---

## D21. The look is portable, the data is not

**Decision.** A card may be rendered by code ported from the shell's own widget
source. The port is frozen at a known version, attributed, and its version is shown
in the panel. Vendored code may *present*; it may never *fetch*.

**The shell is open source.** `noctalia-dev/noctalia`, MIT, active — commits the
same day this was checked. An earlier note in this repo said the calendar and
weather had "no source". That was wrong, or true only of the local machine.

**Why the look is portable.** `src/shell/bar/widgets/weather_widget.cpp` is 219
lines. Its entire rendering is:

```cpp
void WeatherWidget::create() {
  auto area = ui::inputArea({});
  area->addChild(ui::glyph({ .glyph = "weather-cloud",
      .glyphSize = Style::baseGlyphSize * m_contentScale,
      .color = widgetIconColorOr(colorSpecFromRole(ColorRole::OnSurface)) }));
  area->addChild(ui::label({ .fontSize = Style::fontSizeBody * fontScale(),
      .fontWeight = labelFontWeight(), .maxLines = 1 }));
  setRoot(std::move(area));
}
```

Twenty-five lines. No shader, no custom painting, no WebView. The shell's widgets
and plugin widgets build the same kind of node tree through the same vocabulary —
shared `ui/builders.h`, `ui/palette.h`, `ui/style.h`, and one reconciler in
`src/ui/ui_tree_reconciler.cpp`. `ColorRole::OnSurface` is what
`noctalia.getColor(role)` hands a plugin.

The look is not secret rendering. It is a layout plus a palette. That is why
copying it is cheap.

**Three costs, measured rather than assumed.**

1. *Layout is manual in C++, reconciled in Luau.* `doLayout` measures and positions
   by hand: `measure(renderer)`, `setPosition(std::round(...))`, with a
   vertical/horizontal branch. A plugin's tree is laid out by the reconciler. The
   same geometry expressed through `ui.box` converges towards the shell's look; it
   does not reproduce it exactly. For a cockpit panel that is arguably correct — a
   widget that matches its own dashboard beats one that matches a widget somewhere
   else.
2. *The service pointer is unreachable.* `WeatherWidget` holds a `WeatherService*`,
   Noctalia's own fetch. A plugin cannot obtain it and must not try. Weather data
   is public JSON — one `http` source. The vendored code may present; it may not
   fetch.
3. *Per-widget colour overrides are missing.* `widgetIconColorOr()` and
   `widgetForegroundOr()` read the bar's per-widget user overrides.
   `noctalia.getColor(role)` gives the theme roles, not that layer. A card inherits
   the palette and not "this particular bar widget was set to accent". Small, and
   it is the difference between *beautiful* and *identical*.

**No upstream link, deliberately.** Once ported the renderer is frozen.
`lunar-calendar` vendors 36 kB of generated data from a pinned upstream with a
regeneration script and a `DO NOT EDIT BY HAND` header; `jalali_calendar` bundles
a font and ships its `LICENSE`. Same discipline. MIT permits it and the obligation
is one thing: keep the notice.

**Rejected.**

- *Vendoring the C++.* A plugin is Luau. Porting is the only option; pretending
  otherwise produces a build nobody can run.
- *Reading `WeatherService` from a plugin.* Not exposed, not discoverable, and the
  data is public anyway.
- *Tracking upstream.* Explicitly declined. The cost is that shell design changes
  do not propagate — which is the point.

**Consequence.** A vendored renderer's version is **visible in the panel**. This is
the first component whose appearance comes from outside the config, so the panel
is no longer fully described by `hub.yaml`. Freezing the port makes that honest:
the version in the footer is what the panel was drawn by, and a month later "the
panel changed" and "the panel broke" stay distinguishable.

It does not breach the no-markup boundary — Luau is not markup, and the config still
describes only data. What the port adds is a component whose output the config
author cannot read.

---

## D22. The kind set is closed at six

**Decision.** `kind` is exactly `status`, `metric`, `release`, `link`, `console`,
`list`. `graph` is a presentation field on any card, not a kind. A plain text
reading is `status`.

**Why.** An earlier draft listed eight kinds, adding `graph` and `text`. `graph`
was already a field (`graph: true` / a point count / `false`) and appeared as both,
which is the duplication D4 exists to prevent: a card that draws a sparkline is a
`metric` with `graph:` set, not a different kind of thing. `text` had no rendering
of its own — a static string, a URL and an IP all render as a labelled value, which
is `status`. Six is the number of genuinely distinct drawings.

**Why a closed set matters.** Every later decision leans on `kind` meaning one
thing. D15 kept `control` a flag rather than a kind for exactly this reason; D16
argued `list` *is* a kind because it changes the drawing. A closed set of six makes
"does this need a new kind?" answerable: only if it draws differently.

**Rejected.** Keeping eight and documenting `graph` twice. Folding `console` or
`list` into flags — they change the drawing, which is what a kind is.

---

## D23. `split:` turns a text line into fields

**Decision.** A `list` card's source may declare `split: <delimiter>`, which splits
each text row into indexed fields before `row_format` / `extract_lines` run.
`whitespace` is a reserved delimiter that collapses runs. Fields are indexed from
`0`.

**Why.** `kind: list` could take one field per row from JSON, but a tool that emits
fixed text columns — `df -P`, `pct list`, most `-o` output — could not be read at
all. The only way there was `awk` or `sed` inside a shell string, which is the
quoting this project refuses everywhere else (D12, D17). `split:` closes that
without a shell.

**Why `whitespace` is a value and not a second field.** Whitespace-separated columns
are the common case, and splitting on a single space leaves empty fields wherever
columns are aligned. One reserved word covers it; a `collapse:` flag whose only
legal value is `true` is a field that should not exist.

**Rejected.** A regex split — a second language in the schema for a case that has
not appeared. Doing it inside `extract` — `extract` is jq and runs on JSON; a text
row has not been parsed yet, so there is nothing for jq to index.

**Consequence.** The panel registry (`03-config.md`, D20) still cannot be a card.
Its line needs three transformations — strip the prefix, strip the trailing `)`,
split on `, ` — and `split:` provides only the last. A prefix/suffix strip for one
card is the wrong trade, so the gap is two operations wide instead of three, and it
is recorded rather than worked around with `sed`.

---

## D24. The panel framework is ported from github-kanban

**Decision.** The panel's card blocks, header menu, tab strip, font scale and
density come from github-kanban (`shangshui0302/github-kanban`). The shape knobs
live in `hub.yaml` under `layout:` — `font_scale`, `card_radius`, `card_spacing`,
`card_border`, `card_background`, `hover_effect`, plus a third density value
`standard` — and the panel moves to `placement = "attached"` with
`open_near_click = true`.

**Why.** github-kanban is a shipped, working Noctalia panel built on the same
`ui.*` reconciler. Its framework — rounded tinted card blocks, a header with
icon, title, status line, clock and refresh/close buttons, a tab strip, and a
panel that slides out beside the widget that opened it — is the instrument-panel
look this project is chasing, already paid for. Re-deriving the same paddings and
radii would only reproduce the same numbers with more code.

**Why the knobs go in `hub.yaml`, not the manifest.** The config is the product.
A second settings surface in `plugin.toml` would split one visual decision across
two files, and the manifest's `[[setting]]` entries belong to the *bar widget*,
not the panel. Shape is config; colour stays the palette (D5).

**Why `ALL` is the first tab.** docs/02 chose layout A (every zone visible) over
layout C (tabs holding one view). Porting kanban's tab strip wholesale would
reverse that. Keeping `ALL` as the default tab preserves the at-a-glance panel
and makes the other tabs an added shortcut rather than a replacement. A pinned
`pin: bottom` zone is background (D6), so it keeps the footer position and gets
no tab.

**Rejected.** Copying kanban's free-form colour settings
(`heatmap_custom_level_*`) — colour is semantic only (D5, docs/04 §1). Copying
its `appearance_*` keys into the manifest — see above. A hover effect that
changes a reading — hover is presentation only.

**Consequence.** Hover is wired on every card but no card has an `onClick` yet,
so it is presentation without an action until step 6. `show_header` and
`stale_badge` remain accepted, validated and unhonoured; porting the framework
did not change that.

**Superseded in part.** D25 replaces the first tab: it is `overview`, a blank
dashboard, not `ALL` with every zone stacked.

---

## D25. The card is github-kanban's activity row; `overview` is the landing tab

**Decision.** Every card draws as github-kanban's activity row: a glyph badge on
the left, a two-line column (title, then description), and the reading with its
state marker on the trailing edge. A card with no `description` is one line tall.
The first tab is `overview`, reserved for the custom dashboard and deliberately
blank in this build; each other tab shows exactly one zone. The panel is 860x620,
github-kanban's size.

**Why.** The activity row is the reading shape: a thing, what it is, and its
current value, in the order a person reads them. The old single line
(`[glyph] title ……… value ●`) put the title and the value on one baseline and had
nowhere for a description, so D18's description needed a selection state that does
not exist yet. The two-line block gives it a home without a selection model.

**Why `overview` and not `ALL`.** The first tab strip kept `ALL` as the default so
the at-a-glance panel survived (D24). The author wants a landing tab to grow a
custom dashboard on, so `overview` takes that slot and stays blank until it does.
The one-zone-per-domain tabs are unchanged; only the aggregate default is gone.

**Why the failure moved off the card.** An error briefly took the second line's
place here. It does not any more: the reason a card is not ok lives on the **state
marker's tooltip**, and the description keeps its line. A failure that replaces what
the card measures produces a card you cannot read while it is broken — the one
moment you most want to know what it is — and a column of them makes the panel jump
as services flap. The dot is already the element coloured for the state, so the
explanation sitting behind a hover on it is one gesture from the colour that asked
the question (docs/06-failure-modes.md).

**Rejected.** Always-on descriptions *with* a `show_descriptions` switch — the
switch was and remains rejected (D18); the line is the card's own now, so there is
nothing to toggle. Naming the landing tab in `hub.yaml` — it is built in, and the
panel stores it under the empty string so a zone the author calls `overview`
cannot collide with it. Copying kanban's avatar *images* — hub has no images, so
the badge is the glyph on a tinted square, which is kanban's own no-avatar
fallback.

**Consequence.** D18's "selected card only" is reversed: the description is always
the second line, so a zone of eighteen described cards is eighteen two-line
blocks. That is affordable now because a tab holds one zone, not the whole panel.
Selection, when it lands, has no description left to reveal and can use the row for
something else.

---

## D26. Actions are buttons; the one-action rule is retired

**Decision.** An action renders as a button on the card's trailing edge, not as a hit
area over the whole card. `link` and `run` may sit on one card, because each button
has its own target. The "at most one action per card" rule (D15) no longer applies to
the navigational actions; `control` stays out of the button set until its own step
lands.

**Why.** The one-action rule existed to stop a card having an ambiguous click target.
If the whole card is one hit area, two actions make the click a coin toss — that is
the fault D15 refused. A button removes the ambiguity by construction: there is no
shared hit area, so "a link and a terminal on the Pi-hole card" is not a card that
does two things on one click, it is a card with two clearly separated controls, the
same shape as the header's refresh and close buttons.

**Why `link` and `run` are the first two.** They are the pair a real service card
wants: one to open the thing, one to get into the machine behind it (`ssh` plus
`pct exec`, D17). The Pi-hole card is exactly that pair, and it forced the rule.

**Rejected.**

- *Keeping the rule and folding the actions into a menu.* A menu hides the target
  behind a click and a list, which is worse for a five-second glance than two icons.
- *A separate `terminal:` field.* `run:` already carries the command; a second field
  would restate it and split one concept across two names.
- *Drawing `link_template`, `deep_link` and `panel` as buttons now.* They are carried
  and validated, but each needs its own interpolation or target resolution. They
  become buttons when their step does, not before.

**Consequence.** The mutual exclusion D15 described is now scoped to `control`
alone. The schema's action fields are unchanged; only the rule about how many may
coexist changed, and the buttons are drawn by the panel while execution stays on the
collector's side of the boundary ([D12](#d12-the-panel-acts-but-only-by-delegating)).

---

## D27. `kind: status` draws only its dot

**Decision.** A `status` card renders no value column. The state marker's colour is
the whole reading; `format` and `unit` have no effect on a `status` card. Metric,
release, link, console and list cards are unchanged.

**Why.** On a status card the value was always a restatement of the dot —
`running`, `online`, `degraded` — and the dot is the faster read. Two encodings of
one fact is density spent on nothing, and this panel is read at a glance. Removing
it also gives the trailing edge back to the things that are not the card's state:
the update badge and the action buttons.

**What the value was carrying, and where it goes.** A status card's text still
exists in state, and a failure still explains itself on the dot's tooltip
([D25](#d25-the-card-is-github-kanbans-activity-row-overview-is-the-landing-tab)).
A `map`-driven `warn` with no error message is the one case that loses its word; the
description is where that belongs, not a second spelling of the same colour.

**Rejected.**

- *A per-card `show_value: false` flag.* It would make the common case a config edit
  and leave two ways to say "just the dot". The rule is the same on every status
  card, so it belongs in the renderer, not in each file.
- *Keeping the value and hiding it only when `ok`.* Then a card changes height as it
  changes state, and the nominal case — the one you glance at — still carries the
  word. The point was to stop drawing it at all.

---

## D28. OS updates are a card's second reading

**Decision.** A card may carry an `updates` block: a source that prints the number
of pending OS packages, a `run` string that installs them, and an optional interval
that defaults to one hour. The count draws as a warn-coloured badge immediately left
of the state dot. Zero draws nothing; a failed check draws a dim red glyph with its
reason on the tooltip. The count is the button.

**Why this shape.** The update count is not the card's state — Pi-hole can be up
with updates pending, and a broken `ssh` for the count is not a broken Pi-hole — so
it is a second reading with its own state, not a threshold on the card's dot and not
a separate card. A separate card would lose the "on the same host" relation the row
already carries; a threshold on the dot would make one colour mean two things.

**Why zero draws nothing.** A badge that says `0` is a permanent reassurance nobody
reads, and it competes with the badge that says `43`. Silence is the correct
rendering of "nothing to do"; the check's failure is the one case that must not be
silent, so it gets a glyph.

**Why the distribution is in the config.** Debian is `apt-get`, Alpine is `apk`, and
the two need different commands. A `family:` field would be the plugin choosing a
command from a distribution name, which is the integration wrapper D17 refuses for
Proxmox: a thing the plugin must keep in step with every distribution that appears.
The check is an ordinary `command` source and the install is an ordinary `run`
string, written out. [hub.example.yaml](../config/hub.example.yaml) carries both a
Debian and an Alpine card.

**Why an hour.** A package check is the one reading in the panel that may reach the
network and write the package lists — the Debian check runs `apt-get update`. It is
not asked on the card's 60-second cadence; `interval_sec` defaults to `3600` and a
card may override it.

**Rejected.**

- *A generic `badge:` second reading.* The more general field is the more general
  problem: it needs its own thresholds and its own rendering rules for every kind,
  and a reason to exist beyond this one. `updates` says exactly one thing, and the
  mechanism it reuses (`fetch` then `evaluate`) is already the general one.
- *Counting updates in the header's error total.* The trust line is about cards that
  failed. An update badge is a fact about the host, not a fault in the panel's
  reading of it, and folding it in would make `2 errors` mean two different things.
- *Trusting a `0` from a failed `grep -c`.* `grep -c` exits `1` on a zero count and a
  non-zero exit is `down`, so the check ends in `|| true`; and output that is not a
  number is `down` with the bytes quoted, never a zero the badge would draw as "all
  clear".

---

## D29. One view layer, and no module holds state

**Decision.** `hub/visual.luau` holds what both surfaces draw — the four signal
roles plus `pending`, the glyph baseline alignment, the kind fallback glyphs, the
card wrapper — and `hub/rows.luau` / `hub/zones.luau` hold the card and the zone.
None of the three reads `noctalia.state` or the filesystem. Each takes a `view`
built by the panel on every render: the density table, the layout helpers, the
records table, the dispatcher. `hub/util.luau` holds the two type predicates the
layers share, and the one placeholder glyph the collector publishes and the panel
draws.

**Why this shape.** The signal roles were written out twice — `STATE_COLOR` and
`STATE_GLYPH` in the panel, `SIGNAL` in the bar — and the copies had already
drifted, the bar missing `pending` that the panel had added for a card it had no
record for. A role is one fact (a colour and a glyph), so it gets one address. The
same argument moved `glyphLabel`, the card wrapper and its hover closure, the
three-way walk over domains→cards→records, and the `isString` / `isNumber`
definitions.

**Why the modules take a `view` instead of holding one.** The panel's `doc` and
`cards` are replaced by their watches. A module holding its own copy would hold the
table from before the last watch fired and draw a reading the collector had already
moved past — which is the failure D7 exists to prevent, arriving through a file
that looks like it is only presentation. Handing the layout helpers over as
functions is the same rule at a smaller scale: `doc.layout` is read once, at the
moment of drawing.

**Why hover state lives in visual.luau.** It is a render-time decision shared by
both card shapes, and it needs a redraw when it changes. Modules cannot call into
one another — the plugin's entries share no Lua memory, and only `noctalia.state`
crosses that boundary — so the panel registers its `render()` with
`Visual.setRedraw` and visual.luau calls that. The alternative, a hover flag passed
down and back up through every row, is the shared state by another name.

**Defaults live where the schema is validated.** `Config.DEFAULT_LAYOUT` and
`Config.DEFAULT_MAX_ITEMS` are exported and read by the panel and the pipeline. A
default written in the view as well as in the schema is the same number waiting to
drift, and it drifts silently: the panel keeps drawing while the documentation
describes something else. The collector's fatal path publishes its fallback
document *with* `layout`, for the same reason.

**Rejected.**

- *A context module the panel sets once.* `View.layout = doc.layout` at load time
  is the state this decision refuses: it goes stale the moment a watch fires.
- *Modules reading `noctalia.state` directly.* It would put a second subscription
  in every render file, and the layer rules in
  [05-architecture](05-architecture.md) — the collector publishes, the view
  subscribes — are what make a stale reading impossible to hide behind.
- *Naming every literal in one file.* The numbers are named where they are used,
  next to what they do. One table of magic numbers is a table nobody reads.

---

## Resolved questions

Earlier revisions carried these as open. Each is decided here; the reasoning is kept
because the reasoning is the useful part.

**Release polling is explicit, never per-kind.** `kind: release` does not get its
own timer. A kind affects rendering only (D4), and a per-kind interval would put a
polling rule inside a rendering concept — the exact collapse D4 refuses. The example
sets `interval_sec: 900` on the Releases domain, which is the mechanism: one
explicit knob at the domain, visible in the config.

**No card cap; virtualisation waits for a measurement.** Zones already flow and the
panel already scrolls as a whole (D6), so card count is a performance question, not
a layout one. v1 renders every card. A config above roughly 100 cards gets a
load-time *warning* — not an error — suggesting more zones, and virtualisation lands
only if a measured render budget says it must. No number is enforced before there is
a measurement to justify it.

**No desktop widget.** The bar summary plus a hotkey is the entry point; a desktop
surface would duplicate the summary and add a second render path to keep in step.
`desktop_widget.luau` is dropped from the layer list. If the bar widget proves
insufficient this reopens, with a reason rather than by default.

**No `show_descriptions`.** There was never a flag, and there is none now (D18).
The description is the second line of every card (D25); a domain-level switch
would make it optional, which is a toggle over a layout the zone already controls
by how many cards it holds. A zone with more descriptions than it wants to show is
a zone to split, not a switch to add.

**`split:` is added for text rows.** See D23. The panel-registry card still stays
out — it needs a prefix and a suffix strip as well as a split, and two more
transformations to support one card is the wrong trade. The general text/CSV case is
closed.

**No events to other plugins.** `noctalia msg plugin ...` stays unexposed. There is
no use case that is not better served by the panel reading the same data directly,
and a one-way send with no return path is the "rejected write" failure mode D15
refused for controls, without the confirmation that makes a control survivable.

**A vendored renderer is a zone-level component, not a kind.** `kind:` stays closed
at six (D22). A ported widget draws a *zone*, declared on the domain, and its
version shows in the panel (D21). It never becomes a seventh card kind, because that
would make `kind` mean "which code draws this" as well as "how the reading is
drawn" — and those are only the same thing by accident.

---

## D30. A card's second row of facts is a field, not a kind

**Decision.** A card may carry `mini_cards`: a list of tiles, each either static
(`{ label, value }`) or dynamic (`{ label, source, thresholds?, interval_sec? }`),
drawn as a row of small tinted tiles on the trailing edge, left of the update
badge. It is a field on the card, not a new `kind` — the card is still a `metric`,
still fetches, still draws its reading; the tiles are a second row of facts about
the same host, and a new kind would have meant a new fetch, a new extract and a
new state for what is a render of the config.

**Why left of the update badge.** The card's trailing edge is where its facts live:
the reading, the update count, the state dot, then the actions. The tiles are
readings, so they sit with the readings, between the main value and the update
badge — a click on a tile is not a click on an action, and the two must not share
a target (D15, D26). A full-width row under the whole card would need the card
wrapper to become a column, which changes the shape of every card to add a
feature only some have.

**Why the card's own pipeline.** A dynamic mini-card reuses the card's
`source → fetch → evaluate` chain unchanged: `readSource` validates it,
`Pipeline.fetch` and `Pipeline.evaluate` run it, and `thresholds` colour it and
`unit` suffixes it the way they do a card's reading — no second extractor, no
second state machine. It gets its own interval (3600 by default) and its own
record nested in the card's, the way `updates` is (D27). No staleness: a mini-card
has no `stale_after_sec`, so it is either fresh or `down`, and a failed fetch
keeps the last good value with the reason on the tooltip (D7).

**Rejected.**

- *A new `kind: mini`.* A kind is "how to draw the reading" (D4); these tiles
  have no reading. They would need their own fetch and state for a render of
  config.
- *Reusing `format` for the tiles.* `format` is the reading's template; the tiles
  are a different fact with their own labels.