# 01 — Vision

## Problem

One screen showing everything you would otherwise think about separately: whether
infrastructure is alive, which services are down, what shipped recently, what state
the repositories are in, and a jump to any of them.

The panel opens full-screen and reads as a separate space rather than another
window floating above the desktop.

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

- full-screen panel with zones grouped by domain
- card kinds: status, metric, release, link, graph, text
- source types: HTTP, command, line stream, RSS, static value
- compact bar summary widget
- hotkey to open the panel

**Out:**

- executing remote commands from the panel (only local `command` sources)
- write access to sources — the panel reads; control belongs to dedicated plugins like `opnsense`
- aggregating several hosts into one "cluster" — sources are addressed by URL, grouping is visual only
- mobile layout — the panel targets a desktop monitor

## Done criteria

1. The panel opens on a hotkey and renders every zone from the config without errors.
2. A card with an unreachable source shows staleness rather than a false alarm.
3. An error in one card does not break the others.
4. Editing `hub.yaml` takes effect without restarting the shell.
5. Overall status is visible in the header: `✓ 24 cards · 2 errors`.