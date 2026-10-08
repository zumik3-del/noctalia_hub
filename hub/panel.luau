--!nonstrict
--[[
  The panel: presentation only.

  It subscribes to noctalia.state and builds a ui.* tree. It does not fetch, it
  does not parse, and it does not know that a reading came from an HTTP endpoint
  or a shell command — a card is a row with a value and a state, and that is the
  whole of what this file is allowed to assume.

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

-- ── visual language (docs/04-visual-language.md) ─────────────────────────────

--- Colour is semantic only: four signal roles. No free-form colour exists in the
--- config and none is invented here (D5).
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
--- more than it needs a bigger number.
local DENSITY = {
  compact = { rowHeight = 22, valueSize = 11, zoneGap = 12, zonePadding = 8, rowGap = 4 },
  comfortable = { rowHeight = 30, valueSize = 13, zoneGap = 16, zonePadding = 14, rowGap = 6 },
}

local function style()
  if doc ~= nil and doc.layout ~= nil and DENSITY[doc.layout.density] ~= nil then
    return DENSITY[doc.layout.density]
  end
  return DENSITY.compact
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

--- The second line under a card, when there is something the value column cannot
--- say by itself. A config problem outranks a fetch problem: it is the reason the
--- fetch may never succeed at all.
---
--- A card with no record has no `configError` — a card that failed validation
--- never got one. Its errors live on the card itself, which is the only place they
--- can be read from, so this is where a card with no `id` still reports itself.
local function cardSecondLine(card, record, size)
  if record.configError ~= nil then
    return ui.label({ text = record.configError, fontSize = size - 1, color = "error", maxLines = 2 })
  end

  if #(card.errors or {}) > 0 then
    return ui.label({ text = card.errors[1].message, fontSize = size - 1, color = "error", maxLines = 2 })
  end

  if record.error ~= nil then
    return ui.label({
      text = record.error,
      fontSize = size - 1,
      color = STATE_COLOR[record.state] or SECONDARY,
      maxLines = 2,
    })
  end

  if record.state == "stale" or record.attempts > 0 then
    local text = ageLine(record)
    if text ~= nil then
      return ui.label({ text = text, fontSize = size - 1, color = DIMMED, maxLines = 1 })
    end
  end

  return nil
end

--- `sizes` is the density table, not a font size: a card needs both a font size
--- and a row height, and passing two numbers around invites swapping them.
--- `index` is only there to name a card that has no id — a card missing one is
--- already a config error, but it still has to draw without colliding with
--- another card missing one.
local function renderCard(card, record, sizes, index)
  local size = sizes.valueSize
  -- A card the collector has no record for: it failed validation before it could
  -- be given one. The shape has to be complete, because every field below is read
  -- unconditionally.
  record = record or { state = "pending", text = "", attempts = 0, rowCount = 0 }

  local children = {
    ui.glyph({
      name = card.glyph or KIND_GLYPH[card.kind] or "activity",
      size = size + 2,
      color = SECONDARY,
    }),
    glyphLabel({
      text = card.title or card.id or "—",
      fontSize = size,
      color = "on_surface",
      maxLines = 1,
    }),
    -- The value is pushed to the trailing edge: a column of numbers has to read
    -- as a scale, and a scale needs a shared edge (docs/02-layout.md).
    ui.spacer({ flexGrow = 1 }),
    glyphLabel({
      text = (record.text ~= nil and record.text ~= "") and record.text or "—",
      fontSize = size,
      fontWeight = "medium",
      textAlign = "end",
      color = STATE_COLOR[record.state] or SECONDARY,
      maxLines = 1,
    }),
    ui.glyph({
      name = STATE_GLYPH[record.state] or STATE_GLYPH.pending,
      size = size,
      color = STATE_COLOR[record.state] or SECONDARY,
    }),
  }

  local second = cardSecondLine(card, record, size)
  if second ~= nil then
    children[#children + 1] = ui.spacer({ height = 2 })
    children[#children + 1] = second
  end

  return ui.column({
    key = "card:" .. (card.id or ("unnamed-" .. tostring(index))),
    gap = 0,
    height = second ~= nil and nil or sizes.rowHeight,
    justify = "center",
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
  local size = sizes.valueSize
  local children = { renderZoneHeader(domain.glyph, domain.title or domain.id, zoneProblemCount(domain), size) }

  local visible = 0
  for index, card in ipairs(domain.cards) do
    if card.hidden ~= true then
      visible = visible + 1
      children[#children + 1] = ui.spacer({ height = rowGap })
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

  local size = sizes.valueSize
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

local function renderDomainTitles(size)
  local children = {}
  for _, domain in ipairs(doc.domains or {}) do
    if #children > 0 then
      children[#children + 1] = ui.label({ text = "·", fontSize = size - 1, color = DIMMED })
    end
    children[#children + 1] = ui.label({
      text = string.upper(domain.title or domain.id or ""),
      fontSize = size - 1,
      color = DIMMED,
      maxLines = 1,
    })
  end
  return ui.row({ gap = 4, align = "center" }, children)
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
  }
  if #(doc.domains or {}) > 0 then
    left[#left + 1] = ui.spacer({ width = zonePadding * 2 })
    left[#left + 1] = renderDomainTitles(size)
  end

  local right = {
    ui.glyph({ name = "clock", size = size, color = DIMMED }),
    glyphLabel({ text = clock, fontSize = size - 1, color = SECONDARY, maxLines = 1 }),
    ui.spacer({ width = zonePadding }),
    renderStatusLine(size),
    ui.spacer({ width = zonePadding }),
    glyphLabel({ text = noctalia.tr("panel.hint_close"), fontSize = size - 1, color = DIMMED, maxLines = 1 }),
  }

  return ui.column({ gap = 0, paddingH = zonePadding, paddingV = zonePadding }, {
    ui.row({ justify = "space_between", align = "center", gap = zonePadding }, {
      ui.row({ gap = 4, align = "center" }, left),
      ui.row({ gap = 4, align = "center" }, right),
    }),
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
  local size = style()
  local zonePadding = size.zonePadding

  if doc == nil then
    panel.render(renderLoading(size.valueSize, zonePadding))
    return
  end

  if fatal ~= "" then
    panel.render(renderFatal(size.valueSize, zonePadding))
    return
  end

  local scrolling = {}
  local footer = nil

  local configErrors = renderConfigErrors(size, zonePadding)
  if configErrors ~= nil then
    scrolling[#scrolling + 1] = configErrors
  end

  for _, domain in ipairs(doc.domains or {}) do
    -- `pin: bottom` takes a zone out of the scrolling flow: it is background, and
    -- it must not push content around as its numbers change (D6).
    if domain.pin == "bottom" then
      footer = renderZone(domain, size, size.rowGap, zonePadding)
    else
      scrolling[#scrolling + 1] = renderZone(domain, size, size.rowGap, zonePadding)
    end
  end

  if #(scrolling) == 0 then
    scrolling[1] = ui.column({ gap = size.rowGap, padding = zonePadding }, {
      ui.label({ text = noctalia.tr("zone.no_domains"), fontSize = size.valueSize, color = DIMMED, maxLines = 2 }),
    })
  end

  local main = {
    renderHeader(size.valueSize, zonePadding),
    ui.separator({ thickness = 1, color = DIMMED }),
    ui.scroll({ flexGrow = 1 }, {
      ui.column({ gap = size.zoneGap }, scrolling),
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
--   actions (link / panel / run / control)  step 6. No row has an onClick yet,
--     which is also why `capture_keys` lists only "escape" and "r": capturing a
--     key the panel cannot honour takes it away from every other surface.
--   search ("/"), the "?" overlay, Return  land with step 6, when there is
--     something for them to act on.
--   sparklines (`graph:`)                   step 4. A graph with no history yet
--     draws an empty box, which reads as a broken instrument.
--   list expansion on Enter                 step 8. A list is the collapsed count
--     for now, which is the whole of it while there is nothing to expand.
--   console rows                            needs a stream source, step 3.
--   traversal down → warn → stale → ok      needs a selection model. Zones and
--     rows render in YAML order, which is reading order for a human (D8 is about
--     Tab order, not about what is drawn).
--   the slow pulse on `down`                step 4, on panel.setNeedsFrameTick.
--   tabular figures                         docs/04 asks for fixed-width digits and
--     plugin_api 32 exposes no tabular-figure control: fontFamily needs a font
--     loaded through noctalia.loadFont, which is a vendored-asset decision (D21)
--     rather than a rendering detail. Values are right-aligned in the meantime.
--   the ready-made template in an empty zone  needs a click target, so it lands
--     with actions in step 6.
