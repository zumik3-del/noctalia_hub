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

  What the bar shares with this file — the four signal roles, the glyph baseline
  and the card wrapper — is in visual.luau. What this file keeps for itself is the
  header, the tab strip, the fatal/loading screens and render(); the card rows
  are rows.luau and the zones are zones.luau, each taking a `view` built here per
  render rather than holding state of their own.

  Layout, colour and density follow docs/02-layout.md and
  docs/04-visual-language.md. What is deliberately not here yet, and why, is at
  the bottom of this file.
]]

local Config = require("./config.luau")
local Zones = require("./zones.luau")
local Visual = require("./visual.luau")

--- Both requires are for constants, not for behaviour: Config.DEFAULT_LAYOUT is
--- where a field's absent value is decided, and the view is not a second opinion
--- on that. config.luau's IO half is never reached from here — the panel reads
--- the document the collector published, like everything else (docs/05).

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

--- The card block under the pointer is held by visual.luau with the rest of the
--- hover machinery: it is a render-time decision and both card shapes share it.

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
---
--- The roles, the glyph helpers and the card wrapper live in visual.luau, shared
--- with the bar: one address for what a state looks like. What stays here is
--- everything that depends on `doc.layout`, because the layout is config and the
--- config is state.

local SECONDARY = "on_surface_variant"
local DIMMED = "on_surface_variant/0.6"

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
---
--- No clamp: config.luau already rejects a `font_scale` outside 80..130 as a
--- config error, because pinning a typo to 130 hides the typo. Clamping here as
--- well would draw the corrected value and show nothing in the config-errors
--- block, which is the one place the author looks. The `or` only covers a
--- document with no layout at all — see service.luau's fatal path.
local function fontSize(size)
  local scale = tonumber(layoutConf().fontScale) or Config.DEFAULT_LAYOUT.fontScale
  return math.floor(size * scale / 100 + 0.5)
end

local function style()
  return DENSITY[layoutConf().density] or DENSITY.compact
end

--- Every default below comes from Config.DEFAULT_LAYOUT rather than being
--- repeated here. The layer that validates hub.yaml owns what a field is worth
--- when it is absent; a second copy in the view is the same number waiting to
--- drift, and it drifts silently — the panel keeps drawing while the schema
--- documents something else.
local function cardRadius()
  return tonumber(layoutConf().cardRadius) or Config.DEFAULT_LAYOUT.cardRadius
end

local function cardSpacing()
  return tonumber(layoutConf().cardSpacing) or Config.DEFAULT_LAYOUT.cardSpacing
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
  return Config.DEFAULT_LAYOUT.clock
end

-- ── header (docs/02-layout.md) ───────────────────────────────────────────────

--- "✓ 24 cards · 2 errors", permanently visible. A panel reporting whether it
--- can be trusted is part of trusting it, not debug output (docs/04 §6).
local function renderStatusLine(size)
  if summary == nil then
    return ui.label({ text = noctalia.tr("header.loading"), fontSize = size - 1, color = DIMMED, maxLines = 1 })
  end

  local broken = summary.errors > 0
  local warned = (summary.warn or 0) > 0

  local children = {
    ui.glyph({ name = broken and "alert-triangle" or "circle-check", size = size + 1, color = broken and "error" or "primary" }),
    Visual.glyphLabel({ text = noctalia.tr("header.cards", { n = summary.total }), fontSize = size - 1, color = broken and "error" or SECONDARY, maxLines = 1 }),
  }

  -- Warnings ride their own label so the count can be yellow without dragging
  -- the card total with it: "10 warn" is the same fact the badges state one by
  -- one, gathered on the header line (D28). Errors, when they exist, follow in
  -- red — a real failure is not the same attention as a pending package.
  if warned then
    children[#children + 1] = Visual.glyphLabel({ text = "· " .. noctalia.tr("header.warn", { n = summary.warn }), fontSize = size - 1, color = Visual.STATE_ROLES.warn.color, maxLines = 1 })
  end

  if broken then
    children[#children + 1] = Visual.glyphLabel({ text = "· " .. noctalia.tr("header.errors", { n = summary.errors }), fontSize = size - 1, color = "error", maxLines = 1 })
  end

  return ui.row({ gap = 4, align = "center" }, children)
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
        Visual.clearHover()
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
    Visual.glyphLabel({
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
    Visual.glyphLabel({ text = clock, fontSize = size - 1, color = SECONDARY, maxLines = 1 }),
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

--- What the row and zone renderers get from this file. Built per render rather
--- than stored: `doc` and `cards` are replaced by their watches, and a view that
--- held yesterday's tables would draw yesterday's readings. Handing over the
--- layout helpers as functions is the same idea at a smaller scale — `doc.layout`
--- is read once here, at the moment of drawing.
local function view()
  return {
    sizes = style(),
    document = doc,
    records = cards,
    size = fontSize,
    radius = cardRadius,
    spacing = cardSpacing,
    fill = cardFill,
    hoverFill = hoverFill,
    border = cardBorder,
    secondary = SECONDARY,
    dimmed = DIMMED,
    dispatch = dispatchAction,
  }
end

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

  local v = view()
  local scrolling = {}
  local footer = nil

  local configErrors = Zones.renderConfigErrors(v)
  if configErrors ~= nil then
    scrolling[#scrolling + 1] = configErrors
  end

  for index, domain in ipairs(doc.domains or {}) do
    -- `pin: bottom` takes a zone out of the scrolling flow: it is background, and
    -- it must not push content around as its numbers change (D6). It is the one
    -- zone that draws on every tab, `overview` included.
    if domain.pin == "bottom" then
      footer = Zones.renderZone(v, domain, index)
    elseif activeTab == domain.id then
      scrolling[#scrolling + 1] = Zones.renderZone(v, domain, index)
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

  -- `flexGrow` on the root is what makes the body scrollable: without it the
  -- column sizes to its content, so `ui.scroll` inside gets an unbounded height
  -- and has nothing to scroll against.
  panel.render(ui.column({ key = "hub:panel", flexGrow = 1, gap = 0 }, main))
end

-- ── entry ────────────────────────────────────────────────────────────────────

--- visual.luau owns the hover state but cannot call back into another entry —
--- there is no shared Lua memory between the plugin's files — so the panel hands
--- it the one function it needs: how to redraw when the pointer moves.
Visual.setRedraw(render)

local function seed()
  doc = noctalia.state.get(STATE_CONFIG)
  cards = noctalia.state.get(STATE_CARDS) or {}
  summary = noctalia.state.get(STATE_SUMMARY)
  fatal = noctalia.state.get(STATE_FATAL) or ""
end

function onOpen(_context)
  seed()
  Visual.clearHover()

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
--   span: 1|2                                  step 7, with the layout. A card
--     that is twice as wide is a column decision, and the panel has no grid to
--     put one in. It is validated, so a `span: 3` is still a config error rather
--     than a silently dropped field.
--   retries: N                                unbuilt. The interval is fixed and
--     a failed fetch is `down` with its reason in the tooltip (docs/06); a
--     retry inside the interval would be a second opinion about a reading the
--     panel has already made honest. It is validated, so a typo is still a typo.
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
