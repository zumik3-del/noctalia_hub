--!nonstrict
--[[
  The bar summary.

  One row in the bar, not a list of icons:

      ● 5   ▲ 2   ↓ 1

  Counts of ok, warn and down. Everything nominal collapses to one green dot,
  because a row of green numbers on a bar is decoration; the bar's job is to say
  whether anything needs looking at, and to get out of the way when nothing does.

  Clicking toggles this plugin's own panel — the one case where inverting is the
  correct behaviour (D20).
]]

local Visual = require("./visual.luau")

local STATE_SUMMARY = "hub.summary"

local summary = nil

--- Order is attention order, not alphabetical: the failure is the number you came
--- for, so it is read first (D8).
local SIGNALS = { "down", "warn", "stale", "ok" }

--- The bar's own type scale. Not scaled by `font_scale` and not taken from the
--- density table: the bar is host chrome, and a panel setting resizing a row of
--- the panel's own bar is the panel overreaching into someone else's layout.
--- Named for the same reason the panel's numbers are — five copies of `14` are
--- five places to change one decision.
local BAR_GLYPH_SIZE = 14      -- the summary dot, and the lead glyph of the counts
local BAR_COUNT_SIZE = 12      -- a count beside its glyph
local BAR_SIGNAL_GLYPH_SIZE = 8 -- the small state glyph after each count
local BAR_GAP = 2              -- between the parts of the counts row

local isVertical = false

local tooltipShown = false

local function hideTooltip()
  -- Clearing a tooltip that is not there crashes the plugin, so the widget
  -- remembers whether it ever showed one.
  if tooltipShown then
    barWidget.clearTooltip()
    tooltipShown = false
  end
end

local function showTooltip()
  if summary == nil then
    return
  end

  local rows = {
    { key = noctalia.tr("widget.tooltip_cards"), value = tostring(summary.total) },
  }
  if summary.errors > 0 then
    rows[#rows + 1] = { key = noctalia.tr("widget.tooltip_errors"), value = tostring(summary.errors) }
  end
  for _, state in ipairs(SIGNALS) do
    local count = summary[state]
    if count ~= nil and count > 0 then
      rows[#rows + 1] = { key = noctalia.tr("state." .. state), value = tostring(count) }
    end
  end

  barWidget.setTooltip(rows)
  tooltipShown = true
end

--- Nothing to report: one dot, and that is the entire widget. This holds in both
--- modes — a row of green numbers on a bar is decoration, and the bar's job is
--- to say whether anything needs looking at and otherwise get out of the way.
local function renderNominal(glyph)
  return ui.glyph({ name = glyph, size = BAR_GLYPH_SIZE, color = "primary" })
end

--- One glyph for the worst state in the panel. This is the vertical-bar and
--- compact rendering: the answer to "is anything wrong", without the shape of it.
local function renderWorst(worst)
  local role = Visual.STATE_ROLES[worst] or Visual.STATE_ROLES.ok
  return ui.glyph({ name = role.glyph, size = BAR_GLYPH_SIZE, color = role.color })
end

local function renderCounts(glyph)
  local children = { ui.glyph({ name = glyph, size = BAR_GLYPH_SIZE, color = "secondary" }) }

  -- Only what needs attention reaches the bar: a green count on a bar is
  -- decoration, and the tooltip still carries the whole breakdown. So `ok` is
  -- skipped here (and the whole row collapses to one dot when nothing is wrong,
  -- in render() below).
  for _, state in ipairs(SIGNALS) do
    local count = summary[state]
    if state ~= "ok" and count ~= nil and count > 0 then
      local role = Visual.STATE_ROLES[state]
      children[#children + 1] = Visual.glyphLabel({
        text = " " .. tostring(count),
        fontSize = BAR_COUNT_SIZE,
        color = role.color,
        fontWeight = "medium",
        maxLines = 1,
      })
      children[#children + 1] = ui.glyph({ name = role.glyph, size = BAR_SIGNAL_GLYPH_SIZE, color = role.color })
    end
  end

  return ui.row({ gap = BAR_GAP, align = "center" }, children)
end

--- The worst state present, in attention order. `stale` outranks `ok` but not
--- `warn`: data you cannot trust is worth noticing, a threshold you crossed is
--- worth more.
local function worstState()
  for _, state in ipairs(SIGNALS) do
    if (summary[state] or 0) > 0 then
      return state
    end
  end
  return "ok"
end

local function render()
  local glyph = noctalia.getConfig("glyph") or "gauge"
  local compact = noctalia.getConfig("compact") == true

  if summary == nil then
    hideTooltip()
    barWidget.render(ui.glyph({ name = glyph, size = BAR_GLYPH_SIZE, color = "on_surface_variant" }))
    return
  end

  local problems = (summary.down or 0) + (summary.warn or 0) + (summary.stale or 0) + (summary.errors or 0)

  if problems == 0 then
    hideTooltip()
    barWidget.render(renderNominal(glyph))
    return
  end

  showTooltip()

  -- A vertical bar has one line of height to spend and counts do not read in it,
  -- so the dot carries the state and the tooltip carries the numbers.
  if isVertical or compact then
    barWidget.render(renderWorst(worstState()))
    return
  end

  barWidget.render(renderCounts(glyph))
end

function update()
  isVertical = barWidget.isVertical()
  render()
end

noctalia.state.watch(STATE_SUMMARY, function(value)
  summary = value
  render()
end)

function onClick()
  -- This plugin's own panel from this plugin's own widget: toggling is what a
  -- second click should do. Opening anyone else's panel goes through
  -- `noctalia msg panel-open`, which is idempotent (D20).
  noctalia.togglePanel("zumik3-del/hub:panel")
end

summary = noctalia.state.get(STATE_SUMMARY)
