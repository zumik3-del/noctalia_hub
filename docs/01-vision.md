# 01 — Vision

## Problem

One screen for what you would otherwise check in four places: whether infrastructure
is alive, which services are down, what shipped recently, what state the repositories
are in, and a jump to any of them. The panel opens beside the bar widget and reads as
an instrument cluster rather than another window floating over the desktop.

## Why not just a set of plugins

The pieces already exist (~230 community plugins: `bookmarks`, `systempulse`,
`rss-feeds`, `github-activity`, `k8s-status`, `web-launcher`, …). The problem is not
missing features — it is that they live in different panels. Finding out what broke
means opening four separate places. Stitching them onto one panel with shared
configuration is the actual value.

## Key decision: the config file is the interface

The plugin ships no settings editor in v1. Everything is described in `hub.yaml`,
which lives in git and is edited with a normal text editor: reviewable as a diff,
revertible, shareable, and one schema serves every source rather than the ones the
author thought of. A GUI editor remains possible later ([D9](07-decisions.md)).

## Scope

**In:** a panel beside the bar widget, zones grouped by domain with one tab each; card
kinds `status` / `metric` / `release` / `link` / `console` / `list`; sources `http` /
`command` / `stream` / `rss` / `static`; actions `link` / `link_template` /
`deep_link` / `panel` / `run`; a compact bar summary; a hotkey to open the panel.

**Later, in a named version:** `control:` cards that write to remote systems, in their
own `Controls` zone with mandatory arm-confirm and an action log
([D15](07-decisions.md)); a GUI card editor writing back to `hub.yaml`
([D9](07-decisions.md)).

**Out:**

- write access to *read* sources — a card reads or has a `control:`, never both
  implicitly, and a control is never a side effect of polling
- aggregating several hosts into one "cluster" — sources are addressed by URL,
  grouping is visual only
- mobile layout — the panel targets a desktop monitor
- depending on an application's UI URL scheme for anything load-bearing — `deep_link`
  is a convenience ([D14](07-decisions.md))
- **embedding another plugin's surface.** There is no WebView, iframe or HTML in
  `plugin_api` 32. The panel can *open* other panels ([D20](07-decisions.md)); it
  cannot contain them.
- **reading another plugin's data.** `noctalia.state` is shared, so a known key is
  readable, but there is no discovery and no schema — a private convention is not an
  API.
- **rendering anything the config did not describe.** No `template:`, no inline HTML,
  no markdown in a card body. The config describes *data*; the panel decides what it
  looks like. A dashboard that accepts markup becomes an app, and an app needs
  escaping, a sandbox and a second security model.

That last boundary is about the **config**, not the code: vendoring a renderer from
the shell's own open-source widgets is allowed ([D21](07-decisions.md)) precisely
because the config never describes it. What is forbidden is the config carrying
markup.

## Done criteria

1. The panel opens on a hotkey and renders every zone from the config without errors.
2. A card with an unreachable source shows staleness rather than a false alarm.
3. An error in one card does not break the others.
4. Editing `hub.yaml` takes effect without restarting the shell.
5. Overall status is visible in the header: `✓ 24 cards · 2 errors`.
