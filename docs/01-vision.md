# 01 — Vision

## Problem

One screen showing everything you would otherwise think about separately: whether
infrastructure is alive, which services are down, what shipped recently, what state
the repositories are in, and a jump to any of them.

The panel opens beside the bar widget and reads as an instrument cluster rather
than another window floating above the desktop.

## Why not just a set of plugins

The pieces already exist in `community-plugins` (~230 of them):

| Plugin | What it covers |
|---|---|
| `dunarand/bookmarks` | user-defined link list with drag-and-drop |
| `systempulse`, `system-monitor` | system metrics |
| `rss-feeds` | recent entries from feeds |
| `github-activity`, `github-prs`, `github-notifications` | GitHub |
| `k8s-status`, `systemd`, `mini-docker`, `opnsense` | infrastructure monitoring |
| `web-launcher`, `cmd-runner`, `custom-shortcut` | running commands and links |

The problem is not missing features, it is that they live in different panels. To
find out what broke you have to open four separate places. Stitching them onto one
panel with shared configuration is the actual value.

## Key decision: the config file is the interface

The plugin ships no settings editor in the first version. Everything is described
in `hub.yaml`, which lives in git and is edited with a normal text editor.

Reasons:

- the config is reviewable as a diff, revertible through git, shareable between machines
- YAML with comments and anchors reads better than a GUI form
- one schema serves every source, not just the ones the author thought of

A GUI editor remains possible later (see [07-decisions](07-decisions.md)).

## Scope

**In:**

- panel beside the bar widget, with zones grouped by domain and one tab per zone
- card kinds: status, metric, release, link, console, list
- source types: HTTP, command, stream, RSS, static value
- click actions: `link`, `link_template`, `deep_link`, `panel`, `run`
- compact bar summary widget
- hotkey to open the panel

**Later, in a named version** — recorded so it is not a surprise when it lands:

- `control:` cards that write to remote systems, in their own `Controls` zone with
  mandatory arm-confirm and an action log ([D15](07-decisions.md))
- a GUI card editor writing back to `hub.yaml` ([D9](07-decisions.md))

**Out:**

- write access to *read* sources. A card reads or has a `control:`; it never both
  implicitly, and a control is never a side effect of polling
- aggregating several hosts into one "cluster" — sources are addressed by URL, grouping is visual only
- mobile layout — the panel targets a desktop monitor
- depending on an application's UI URL scheme for anything load-bearing —
  `deep_link` is a convenience ([D14](07-decisions.md))
- **embedding another plugin's surface.** There is no WebView, no iframe and no
  HTML in `plugin_api` 32, so mounting a panel inside a panel is not a design
  choice — it is absent. The panel can *open* other panels ([D20](07-decisions.md));
  it cannot contain them.
- **reading another plugin's data.** `noctalia.state` is shared, so a known key is
  readable, but there is no discovery and no schema. A private convention is not
  an API.
- **rendering anything the config did not describe.** A dashboard that accepts HTML
  or a template language in its config becomes an app, and an app needs escaping, a
  sandbox and a second security model. The config describes *data*; the panel
  decides what data looks like. No `template:`, no inline HTML, no markdown in a
  card body.

That last one has a concrete cost worth stating plainly, because it was measured
against a real dashboard rather than imagined. Dynacat renders PocketBase video
summaries through a Go HTML template with thumbnails, durations, and a modal that
renders markdown on click. The panel can read that same endpoint and show the
title, the duration and the link. It cannot show the thumbnail or the summary
formatting, and it never will without becoming an app. A card is a labelled
reading, not a document.

The boundary is about the **config**, not about code. Vendoring a renderer from
the shell's own open-source widgets is allowed ([D21](07-decisions.md)) precisely
because the config never describes it — the port is plugin code, frozen and
versioned visibly. What is forbidden is the config carrying markup.

## Done criteria

1. The panel opens on a hotkey and renders every zone from the config without errors.
2. A card with an unreachable source shows staleness rather than a false alarm.
3. An error in one card does not break the others.
4. Editing `hub.yaml` takes effect without restarting the shell.
5. Overall status is visible in the header: `✓ 24 cards · 2 errors`.