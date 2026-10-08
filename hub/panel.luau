--!nonstrict
--[[
  The panel: presentation only.

  It subscribes to noctalia.state and builds a ui.* tree. It does not fetch, it
  does not parse, and it does not know that a reading came from an HTTP endpoint
  or a shell command — a card is a block with a value and a state, and that is the
  whole of what this file is allowed to assume.

  The visual framework — card blocks with radius/fill/border/hover, the font
  scale, the header menu and the tab strip — is ported from github-kanban
  (shangshui0302/github-kanban), retuned to the semantic-colour and density rules
  of docs/04-visual-language.md. The config keys that drive it live in
  `layout:` (D24); nothing here invents a colour outside the palette.

  Layout, colour and density follow docs/02-layout.md and
  docs/04-visual-language.md. What is deliberately not here yet, and why, is at
  the bottom of this file.
]]

local STATE_CONFIG = "hub.config"
local STATE_CARDS = "hub.cards"
local STATE_SUMMARY = "hub.summary"
local STATE_FATAL = "hub.fatal"

--- Seeded from state in onOpen, kept current by the watches below.
local doc = nil
local cards = {}
local summary = nil
local fatal = ""
local clock = ""

--- The landing tab, and the only tab that holds no zone. It is stored as the
--- empty string because a domain id is never empty, so a zone the author happens
--- to call `overview` keeps its own tab instead of colliding with this one.
--- Overview is the custom dashboard and is deliberately blank in this build.
local OVERVIEW = ""
local activeTab = OVERVIEW

--- The card block under the pointer, by key. Hover is a render-time decision, so
--- it lives with the other view state and never crosses to the collector.
local hovered = nil

--- Buttons ask the collector to act through the same channel refresh uses: the
--- panel is a subscriber and never launches a process itself
--- (docs/05-architecture.md). The sequence number makes a second click a
--- distinct write, so the watcher fires even when the target is unchanged.
local actionSeq = 0

local function dispatchAction(action, target)
  actionSeq = actionSeq + 1
  noctalia.state.set("hub.cmd", { action = action, target = target, seq = actionSeq })
end

-- ── visual language (docs/04-visual-language.md) ─────────────────────────────

--- Colour is semantic only: four signal roles. No free-form colour exists in the
--- config and none is invented here (D5). A card block's fill and border are
--- palette roles with alpha, never literal colours.
local STATE_COLOR = {
  ok = "primary",
  warn = "secondary",
  down = "error",
  stale = "on_surface_variant",
  pending = "on_surface_variant",
}

local STATE_GLYPH = {
  ok = "circle-filled",
  warn = "alert-circle",
  down = "alert-triangle",
  stale = "circle-dashed",
  pending = "circle",
}

--- A card without a glyph gets one from its kind, so a column of unadorned cards
--- still reads as instruments rather than as a word list.
local KIND_GLYPH = {
  status = "activity",
  metric = "chart-line",
  release = "tag",
  link = "external-link",
  console = "file-text",
  list = "list",
}

local SECONDARY = "on_surface_variant"
local DIMMED = "on_surface_variant/0.6"

--- A label that shares a row with a glyph.
---
--- The host anchors an icon font at the ink top and a text label at the text
--- baseline. In a row that centres its children, the two therefore sit on
--- different vertical centres: the icon's ink is high in its box, the text's ink is
--- low in its box, and the pair reads as crooked even though both are "centred".
--- `pictographic` centres the label's ink instead of aligning its baseline, which
--- is the alignment a glyph expects.
---
--- Only where a glyph is actually in the row. On a label that stands alone the same
--- setting centres the x-height rather than the line, and a column of plain text
--- starts to drift.
local function glyphLabel(props)
  props.baseline = "pictographic"
  return ui.label(props)
end

--- Density is a layout decision. A 4K screen with few zones needs the taller row
--- more than it needs a bigger number. `compact` is the instrument-panel default;
--- `standard` and `comfortable` trade scrolling for legibility.
local DENSITY = {
  compact = { valueSize = 11, zoneGap = 12, zonePadding = 8, rowGap = 4, cardPadH = 8, cardPadV = 5 },
  standard = { valueSize = 12, zoneGap = 14, zonePadding = 11, rowGap = 5, cardPadH = 10, cardPadV = 7 },
  comfortable = { valueSize = 13, zoneGap = 16, zonePadding = 14, rowGap = 6, cardPadH = 12, cardPadV = 9 },
}

local function layoutConf()
  if doc ~= nil and type(doc.layout) == "table" then
    return doc.layout
  end
  return {}
end

--- `font_scale` is applied to every text size at render time. Keeping it a
--- multiplier over the density base — rather than a second set of literal sizes —
--- is what stops the two from disagreeing (D24).
local function fontSize(size)
  local scale = tonumber(layoutConf().fontScale) or 100
  scale = math.max(80, math.min(130, scale))
  return math.floor(size * scale / 100 + 0.5)
end

local function style()
  return DENSITY[layoutConf().density] or DENSITY.compact
end

local function cardRadius()
  local value = tonumber(layoutConf().cardRadius)
  if value ~= nil then return value end
  return 9
end

local function cardSpacing()
  local value = tonumber(layoutConf().cardSpacing)
  if value ~= nil then return value end
  return 8
end

--- A card's fill is one of three theme states, never a colour. `tinted` and
--- `solid` are palette roles with alpha, resolved live against the active theme.
local function cardFill()
  local mode = layoutConf().cardBackground or "tinted"
  if mode == "transparent" then return "transparent" end
  if mode == "solid" then return "surface/0.68" end
  return "surface_variant/0.38"
end

--- The hover highlight. One step brighter than `tinted`, still a palette role, so
--- the theme keeps control of the actual colour (docs/04 §1).
local function hoverFill()
  return "surface_variant/0.62"
end

--- border, borderWidth. A hovered card claims the accent border only when the
--- config asked for a border response; the state colour stays on the value and
--- the status glyph, so a warning is never mistaken for a hover (D5, D24).
local function cardBorder(active)
  local mode = layoutConf().cardBorder or "subtle"
  local hover = layoutConf().hoverEffect or "background"
  if mode == "none" then return "outline/0", 0 end
  if active and hover == "border" then return "primary", 1 end
  if mode == "accent" then return "primary", 1 end
  return "outline/0.6", 1
end

local function clockPattern()
  if doc ~= nil and doc.layout ~= nil and type(doc.layout.clock) == "string" then
    return doc.layout.clock
  end
  return "%H:%M:%S"
end

-- ── rows ─────────────────────────────────────────────────────────────────────

--- "from 14:02 · 3 attempts" — the line that makes a frozen reading honest. The
--- value stays on screen; this says how old it is and how many tries have failed
--- since (docs/06-failure-modes.md).
local function ageLine(record)
  if record.lastGoodAtMs == nil then
    return nil
  end

  local parts = {
    "from " .. noctalia.formatTime("%H:%M:%S", math.floor(record.lastGoodAtMs / 1000)),
  }
  if record.attempts > 0 then
    parts[#parts + 1] = tostring(record.attempts) .. " attempts"
  end

  return table.concat(parts, " · ")
end

--- The reason a card is not ok, as one line for the state marker's tooltip. A
--- config problem outranks a fetch problem: it is the reason the fetch may never
--- succeed. A stale card with no error shows its age instead, so the dimmed dot
--- explains itself too.
---
--- A card with no record has no `configError` — a card that failed validation
--- never got one. Its errors live on the card itself, which is the only place they
--- can be read from, so this is where a card with no `id` still reports itself.
local function cardProblem(card, record)
  if record ~= nil then
    if record.configError ~= nil then
      return record.configError
    end
    if record.error ~= nil then
      return record.error
    end
    if record.state == "stale" then
      return ageLine(record)
    end
  end

  if #(card.errors or {}) > 0 then
    return card.errors[1].message
  end

  return nil
end

--- The second line under a card: what the thing is. A failure no longer takes
--- this line — it lives in the state marker's tooltip instead (D25), so a red
--- card still says what it measures while the reason waits one hover away on the
--- dot that is already coloured for it.
---
--- The age stays here when there is no description to show, because a frozen
--- reading with no age reads as a live one (docs/06-failure-modes.md).
local function cardSecondLine(card, record, size)
  if type(card.description) == "string" and card.description ~= "" then
    return ui.label({ text = card.description, fontSize = size, color = SECONDARY, maxLines = 2 })
  end

  if record.state == "stale" or record.attempts > 0 then
    local text = ageLine(record)
    if text ~= nil then
      return ui.label({ text = text, fontSize = size, color = DIMMED, maxLines = 1 })
    end
  end

  return nil
end

--- The update badge: a card's second reading, drawn before the state dot. It is
--- silent when there is nothing to say — no pending updates, or the check has not
--- answered yet — a warn-coloured count when there are, and a dim red glyph when
--- the check itself could not run (D27). "No updates" and "could not ask" are
--- different facts, and the panel must not draw them the same.
---
--- The count is the button that installs them: one target, so it is a button and
--- not a card-wide click (D26). The reason a failed check gives sits on the
--- glyph's tooltip, the same place a failed reading explains itself.
local function updatesBadge(card, record, size)
  local updates = record.updates
  if updates == nil then
    return nil
  end

  if updates.state == "warn" then
    local onUpgrade = nil
    if card.updates ~= nil and card.updates.run ~= nil then
      onUpgrade = function()
        dispatchAction("run", card.updates.run)
      end
    end
    return ui.button({
      text = updates.text,
      variant = "secondary",
      controlSize = "sm",
      tooltip = noctalia.tr("panel.updates"),
      onClick = onUpgrade,
    })
  end

  if updates.state == "down" then
    return ui.row({ tooltip = updates.error or noctalia.tr("panel.updates_failed"), align = "center" }, {
      ui.glyph({ name = "alert-triangle", size = size, color = "error/0.7" }),
    })
  end

  return nil
end

--- One card, drawn as the activity block of github-kanban (D25): a badge on the
--- left, a two-line column in the middle, and the reading plus its state marker on
--- the right.
---
---     ┌──┐  Title                  34%  ●  ⇱  ⌨
---     └──┘  Description
---
--- The badge is kanban's avatar slot: hub has no images, so it fills it with the
--- card's glyph on a tinted rounded square, which is exactly what kanban does for
--- the rows that have no avatar.
---
--- The second line is the description. A failure does not take its place: the
--- reason lives on the state marker's tooltip, so a red card still says what it
--- measures (docs/06-failure-modes.md). The reading stays on the trailing edge — a
--- column of numbers has to read as a scale — and the action buttons follow it.
---
--- `sizes` is the density table, not a font size: a card needs both a font size
--- and padding, and passing two numbers around invites swapping them. `index` is
--- only there to name a card that has no id — a card missing one is already a
--- config error, but it still has to draw without colliding with another card
--- missing one.
local function renderCard(card, record, sizes, index)
  local size = fontSize(sizes.valueSize)
  -- A card the collector has no record for: it failed validation before it could
  -- be given one. The shape has to be complete, because every field below is read
  -- unconditionally.
  record = record or { state = "pending", text = "", attempts = 0, rowCount = 0 }

  local key = "card:" .. (card.id or ("unnamed-" .. tostring(index)))
  local active = hovered == key
  local border, borderWidth = cardBorder(active)

  local state = record.state or "pending"
  local stateColor = STATE_COLOR[state] or SECONDARY
  local value = (record.text ~= nil and record.text ~= "") and record.text or "—"

  local badge = size + 17
  local leading = ui.column({
    width = badge,
    height = badge,
    radius = math.max(4, math.floor(badge / 4)),
    fill = "primary/0.12",
    align = "center",
    justify = "center",
  }, {
    ui.glyph({
      name = card.glyph or KIND_GLYPH[card.kind] or "activity",
      size = size + 5,
      color = "primary",
    }),
  })

  local lines = {
    ui.label({
      text = card.title or card.id or "—",
      fontWeight = "bold",
      fontSize = size + 2,
      color = "on_surface",
      maxLines = 2,
    }),
  }
  local second = cardSecondLine(card, record, size)
  if second ~= nil then
    lines[#lines + 1] = second
  end

  -- The reading and its state marker, then the card's buttons. Each button has
  -- its own target, so two of them is not the ambiguity the old one-action rule
  -- guarded against — a click on one cannot mean the other (D15, D26). Only
  -- `link` and `run` are drawn; `panel`, `deep_link` and `control` are still
  -- schema, not buttons.
  local marker = ui.glyph({ name = STATE_GLYPH[state] or STATE_GLYPH.pending, size = size, color = stateColor })
  local problem = cardProblem(card, record)
  if problem ~= nil then
    -- `ui.box` is a leaf — it takes no children — so the dot that must keep its
    -- own colour is wrapped in a row, which does take a tooltip (docs/05 UI
    -- primitives).
    marker = ui.row({ tooltip = problem, align = "center" }, { marker })
  end

  -- A status card says everything with its dot: the value column is not drawn for
  -- `kind: status` (D27). The dot's colour and its tooltip carry the state, and a
  -- word beside it was the same fact twice.
  local trailing = {}
  if card.kind ~= "status" then
    trailing[#trailing + 1] = ui.label({
      text = value,
      fontSize = size - 1,
      textAlign = "end",
      color = stateColor,
      maxLines = 1,
    })
  end

  -- The update count sits between the reading and the dot: it is a second reading
  -- about the same host, and it belongs on the reading side of the card (D27).
  local badge = updatesBadge(card, record, size)
  if badge ~= nil then
    trailing[#trailing + 1] = badge
  end

  trailing[#trailing + 1] = marker

  if card.actions ~= nil then
    if card.actions.link ~= nil then
      trailing[#trailing + 1] = ui.button({
        glyph = "external-link",
        variant = "ghost",
        controlSize = "sm",
        tooltip = noctalia.tr("panel.action_link"),
        onClick = function()
          dispatchAction("link", card.actions.link)
        end,
      })
    end
    if card.actions.run ~= nil then
      trailing[#trailing + 1] = ui.button({
        glyph = "terminal-2",
        variant = "ghost",
        controlSize = "sm",
        tooltip = noctalia.tr("panel.action_terminal"),
        onClick = function()
          dispatchAction("run", card.actions.run)
        end,
      })
    end
  end

  local children = {
    leading,
    ui.column({ flexGrow = 1, gap = 3 }, lines),
  }
  for _, node in ipairs(trailing) do
    children[#children + 1] = node
  end

  return ui.row({
    key = key,
    gap = sizes.cardPadH,
    paddingH = sizes.cardPadH,
    paddingV = sizes.cardPadV,
    radius = cardRadius(),
    fill = active and hoverFill() or cardFill(),
    border = border,
    borderWidth = borderWidth,
    align = "center",
    onHover = function(value)
      local nextHovered = value == "true" and key or nil
      if nextHovered ~= hovered then
        hovered = nextHovered
        render()
      end
    end,
  }, children)
end

-- ── zones ────────────────────────────────────────────────────────────────────

--- Problems in this zone, for the header count. Only real problems: a `pending`
--- card is an absence of one, and counting it would make every freshly loaded
--- panel look broken. Each card counts at most once.
local function zoneProblemCount(domain)
  local problems = 0
  for _, card in ipairs(domain.cards) do
    if card.hidden ~= true then
      local record = cards[card.id]
      local problem = false
      if record ~= nil and (record.state == "down" or record.state == "warn" or record.state == "stale") then
        problem = true
      end
      if #(card.errors or {}) > 0 then
        problem = true
      end
      if problem then
        problems = problems + 1
      end
    end
  end
  return problems
end

local function renderZoneHeader(glyph, title, problems, size)
  local children = {
    ui.glyph({ name = glyph or "layout-columns", size = size + 1, color = DIMMED }),
    glyphLabel({
      text = string.upper(title or ""),
      fontSize = size,
      fontWeight = "semibold",
      color = DIMMED,
      maxLines = 1,
    }),
  }

  if problems > 0 then
    children[#children + 1] = glyphLabel({
      text = tostring(problems),
      fontSize = size,
      fontWeight = "semibold",
      color = "error",
      maxLines = 1,
    })
  end

  children[#children + 1] = ui.separator({ thickness = 1, color = DIMMED })

  return ui.row({ gap = 6, align = "center" }, children)
end

local function renderZone(domain, sizes, rowGap, zonePadding)
  local size = fontSize(sizes.valueSize)
  local children = { renderZoneHeader(domain.glyph, domain.title or domain.id, zoneProblemCount(domain), size) }

  local visible = 0
  for index, card in ipairs(domain.cards) do
    if card.hidden ~= true then
      visible = visible + 1
      children[#children + 1] = ui.spacer({ height = cardSpacing() })
      children[#children + 1] = renderCard(card, cards[card.id], sizes, index)
    end
  end

  -- A domain's own errors are not repeated here: they are in `doc.errors`, and
  -- the config block above renders every one with its path. A card's errors do not
  -- appear in that list twice — they render under the card, from `card.errors`.
  --
  -- An empty domain is a hint, not an empty box. docs/02 asks for a ready-made
  -- template here; offering one needs a click target, and actions are not built
  -- yet, so this is the honest half of it.
  if visible == 0 then
    children[#children + 1] = ui.spacer({ height = rowGap })
    children[#children + 1] = ui.label({
      text = noctalia.tr("zone.empty"),
      fontSize = size - 1,
      color = DIMMED,
      maxLines = 1,
    })
  end

  return ui.column({
    key = "zone:" .. (domain.id or "?"),
    gap = 0,
    padding = zonePadding,
  }, children)
end

--- Document-level problems belong to no card and no zone, so they get their own
--- block above the content: an unknown secret, an unsupported version, a config
--- warning. Silent config problems are how a panel starts lying (docs/04 §6).
local function renderConfigErrors(sizes, zonePadding)
  if #(doc.errors or {}) == 0 then
    return nil
  end

  local size = fontSize(sizes.valueSize)
  local children = {
    renderZoneHeader("file-alert", noctalia.tr("zone.config"), #(doc.errors), size),
  }
  for _, err in ipairs(doc.errors) do
    children[#children + 1] = ui.spacer({ height = 4 })
    children[#children + 1] = ui.label({
      text = err.path .. " — " .. err.message,
      fontSize = size - 1,
      color = "error",
      maxLines = 2,
    })
  end

  return ui.column({ gap = 0, padding = zonePadding }, children)
end

-- ── header (docs/02-layout.md) ───────────────────────────────────────────────

--- "✓ 24 cards · 2 errors", permanently visible. A panel reporting whether it
--- can be trusted is part of trusting it, not debug output (docs/04 §6).
local function renderStatusLine(size)
  if summary == nil then
    return ui.label({ text = noctalia.tr("header.loading"), fontSize = size - 1, color = DIMMED, maxLines = 1 })
  end

  local broken = summary.errors > 0
  local text = noctalia.tr("header.cards", { n = summary.total })
  if broken then
    text = text .. " · " .. noctalia.tr("header.errors", { n = summary.errors })
  end

  return ui.row({ gap = 4, align = "center" }, {
    ui.glyph({ name = broken and "alert-triangle" or "circle-check", size = size + 1, color = broken and "error" or "primary" }),
    glyphLabel({ text = text, fontSize = size - 1, color = broken and "error" or SECONDARY, maxLines = 1 }),
  })
end

--- The zone names moved out of the header line and into this strip: one button
--- per domain, plus `overview`, which is the custom dashboard and holds no zone.
--- Selected buttons take the primary variant, the rest are ghost — the same tab
--- vocabulary as github-kanban's dashboard strip.
local function renderTabs(size)
  local children = {}

  local function tab(id, title, glyph)
    local active = activeTab == id
    children[#children + 1] = ui.button({
      text = string.upper(title),
      glyph = glyph,
      controlSize = "sm",
      variant = active and "primary" or "ghost",
      selected = active,
      onClick = function()
        activeTab = id
        hovered = nil
        render()
      end,
    })
  end

  tab(OVERVIEW, noctalia.tr("panel.tab_overview"), "layout-dashboard")
  for _, domain in ipairs(doc.domains or {}) do
    -- The pinned footer is background, not a destination: it is always visible
    -- and needs no tab.
    if domain.pin ~= "bottom" then
      tab(domain.id or "?", domain.title or domain.id or "?", domain.glyph)
    end
  end

  return ui.row({ gap = 3, align = "center" }, children)
end

--- The active tab can outlive the domain it named — a config edit removes or
--- renames a zone. Falling back to `overview` is the honest recovery: the panel
--- keeps showing its landing tab instead of an empty body under a dead name.
local function ensureTab()
  if activeTab == OVERVIEW then
    return
  end
  for _, domain in ipairs(doc.domains or {}) do
    if domain.id == activeTab then
      return
    end
  end
  activeTab = OVERVIEW
end

local function renderHeader(size, zonePadding)
  local left = {
    ui.glyph({ name = "gauge", size = size + 3, color = "primary" }),
    glyphLabel({
      text = string.upper(noctalia.tr("panel.name")),
      fontSize = size + 2,
      fontWeight = "bold",
      color = "primary",
      maxLines = 1,
    }),
    ui.spacer({ width = zonePadding }),
    renderStatusLine(size),
  }

  -- Refresh and close are buttons now, not text hints: the header menu of
  -- github-kanban. Refresh still goes through `hub.cmd` because starting a poll
  -- belongs on the collector's side of the boundary (docs/05-architecture.md).
  local right = {
    ui.glyph({ name = "clock", size = size, color = DIMMED }),
    glyphLabel({ text = clock, fontSize = size - 1, color = SECONDARY, maxLines = 1 }),
    ui.spacer({ width = zonePadding }),
    ui.button({
      glyph = "refresh",
      variant = "ghost",
      controlSize = "sm",
      tooltip = noctalia.tr("panel.refresh"),
      onClick = function()
        noctalia.state.set("hub.cmd", "refresh")
      end,
    }),
    ui.button({
      glyph = "close",
      variant = "ghost",
      controlSize = "sm",
      tooltip = noctalia.tr("panel.close"),
      onClick = function()
        panel.close()
      end,
    }),
  }

  return ui.column({ gap = 0, paddingH = zonePadding, paddingV = zonePadding }, {
    ui.row({ justify = "space_between", align = "center", gap = zonePadding }, {
      ui.row({ gap = 4, align = "center" }, left),
      ui.row({ gap = 4, align = "center" }, right),
    }),
    ui.spacer({ height = 6 }),
    renderTabs(size),
  })
end

--- The one case where the panel does not render zones at all: a config that could
--- not be read leaves nothing to draw, and an empty instrument panel would look
--- exactly like "everything is fine" (docs/06-failure-modes.md).
local function renderFatal(size, zonePadding)
  return ui.column({ gap = size, padding = zonePadding * 2, justify = "center" }, {
    ui.glyph({ name = "file-alert", size = 28, color = "error" }),
    ui.label({
      text = noctalia.tr("fatal.title"),
      fontSize = size + 3,
      fontWeight = "bold",
      color = "error",
    }),
    ui.label({ text = fatal, fontSize = size, color = SECONDARY, maxLines = 6 }),
  })
end

local function renderLoading(size, zonePadding)
  return ui.column({ gap = size, padding = zonePadding * 2, justify = "center", align = "center" }, {
    ui.label({ text = noctalia.tr("header.loading"), fontSize = size + 1, color = DIMMED }),
  })
end

-- ── render ───────────────────────────────────────────────────────────────────

function render()
  local sizes = style()
  local zonePadding = sizes.zonePadding
  local size = fontSize(sizes.valueSize)

  if doc == nil then
    panel.render(renderLoading(size, zonePadding))
    return
  end

  if fatal ~= "" then
    panel.render(renderFatal(size, zonePadding))
    return
  end

  ensureTab()

  local scrolling = {}
  local footer = nil

  local configErrors = renderConfigErrors(sizes, zonePadding)
  if configErrors ~= nil then
    scrolling[#scrolling + 1] = configErrors
  end

  for _, domain in ipairs(doc.domains or {}) do
    -- `pin: bottom` takes a zone out of the scrolling flow: it is background, and
    -- it must not push content around as its numbers change (D6). It is the one
    -- zone that draws on every tab, `overview` included.
    if domain.pin == "bottom" then
      footer = renderZone(domain, sizes, sizes.rowGap, zonePadding)
    elseif activeTab == domain.id then
      scrolling[#scrolling + 1] = renderZone(domain, sizes, sizes.rowGap, zonePadding)
    end
  end

  -- `overview` is the custom dashboard and is blank in this build, so it is the
  -- one tab where an empty body is the intended state and not a missing config.
  -- The config-errors block above still draws there: a broken config must never
  -- hide behind a blank tab (docs/06-failure-modes.md).
  if #(scrolling) == 0 and activeTab ~= OVERVIEW then
    scrolling[1] = ui.column({ gap = sizes.rowGap, padding = zonePadding }, {
      ui.label({ text = noctalia.tr("zone.no_domains"), fontSize = size, color = DIMMED, maxLines = 2 }),
    })
  end

  local main = {
    renderHeader(size, zonePadding),
    ui.separator({ thickness = 1, color = DIMMED }),
    -- Keyed by tab, the way k8s-status does it: when a tab's body changes from
    -- empty to full, an unkeyed scroll keeps the previous (empty) layout and the
    -- new zone never appears until the panel is reopened. A fresh key on every
    -- switch forces the relayout. The inner column stretches to the viewport, so a
    -- short zone fills the panel, and grows past it — the scroll then takes over.
    ui.scroll({
      key = "hub:scroll:" .. activeTab,
      flexGrow = 1,
      gap = sizes.zoneGap,
      align = "stretch",
    }, {
      ui.column({
        key = "hub:items:" .. activeTab,
        flexGrow = 1,
        justify = "start",
        align = "stretch",
        gap = sizes.zoneGap,
      }, scrolling),
    }),
  }

  if footer ~= nil then
    main[#main + 1] = ui.separator({ thickness = 1, color = DIMMED })
    main[#main + 1] = footer
  end

  panel.render(ui.column({ key = "hub:panel", gap = 0 }, main))
end

-- ── entry ────────────────────────────────────────────────────────────────────

local function seed()
  doc = noctalia.state.get(STATE_CONFIG)
  cards = noctalia.state.get(STATE_CARDS) or {}
  summary = noctalia.state.get(STATE_SUMMARY)
  fatal = noctalia.state.get(STATE_FATAL) or ""
end

function onOpen(_context)
  seed()
  hovered = nil

  -- The clock is the only thing on screen that must not wait for data.
  panel.setWantsSecondTicks(true)
  clock = noctalia.formatTime(clockPattern())

  render()
end

function update()
  -- Second tick: redraw for the clock. Nothing else moves on its own, which is
  -- the restraint docs/04 asks for.
  clock = noctalia.formatTime(clockPattern())
  render()
end

function onKey(chord, pressed)
  if not pressed then
    return
  end

  if chord == "escape" then
    panel.close()
    return
  end

  if chord == "r" then
    -- A refresh is a request to the collector, not work done here: starting a
    -- process belongs behind the same boundary as polling, not in the view
    -- (docs/05-architecture.md).
    noctalia.state.set("hub.cmd", "refresh")
  end
end

noctalia.state.watch(STATE_CARDS, function(value)
  cards = value or {}
  render()
end)

noctalia.state.watch(STATE_CONFIG, function(value)
  doc = value
  render()
end)

noctalia.state.watch(STATE_SUMMARY, function(value)
  summary = value
  render()
end)

noctalia.state.watch(STATE_FATAL, function(value)
  fatal = value or ""
  render()
end)

seed()

-- ── not in this build ────────────────────────────────────────────────────────
--
-- Each of these is a build-order item, not a missing idea. Saying where it goes
-- is more useful than leaving it to be rediscovered.
--
--   link_template / deep_link / panel / control  step 6, partial. `link` and
--     `run` are drawn as trailing buttons and executed; the other four are
--     validated and carried but not drawn. The buttons are pointer targets, so
--     `capture_keys` still lists only "escape" and "r" — capturing a key the
--     panel cannot honour takes it away from every other surface.
--   search ("/"), the "?" overlay, Return  land with step 6, when there is
--     something for them to act on.
--   sparklines (`graph:`)                   step 4. A graph with no history yet
--     draws an empty box, which reads as a broken instrument.
--   list expansion on Enter                 step 8. A list is the collapsed count
--     for now, which is the whole of it while there is nothing to expand.
--   console rows                            needs a stream source, step 3.
--   traversal down → warn → stale → ok      needs a selection model. Tabs and
--     rows render in YAML order, which is reading order for a human (D8 is about
--     Tab order, not about what is drawn).
--   the slow pulse on `down`                step 4, on panel.setNeedsFrameTick.
--   tabular figures                         docs/04 asks for fixed-width digits and
--     plugin_api 32 exposes no tabular-figure control: fontFamily needs a font
--     loaded through noctalia.loadFont, which is a vendored-asset decision (D21)
--     rather than a rendering detail. Values are right-aligned in the meantime.
--   the ready-made template in an empty zone  needs a click target, so it lands
--     with actions in step 6.
