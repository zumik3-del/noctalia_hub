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

local STATE_SUMMARY = "hub.summary"

local summary = nil

--- Same four signal roles as the panel. The bar has no per-widget colour override
--- layer, so a widget draws from the palette and nothing else (D21).
local SIGNAL = {
  ok = { glyph = "circle-filled", color = "primary" },
  warn = { glyph = "alert-circle", color = "secondary" },
  down = { glyph = "alert-triangle", color = "error" },
  stale = { glyph = "circle-dashed", color = "on_surface_variant" },
}

--- Order is attention order, not alphabetical: the failure is the number you came
--- for, so it is read first (D8).
local SIGNALS = { "down", "warn", "stale", "ok" }

local isVertical = false

local Tooltip = { shown = false }

local function hideTooltip()
  -- Clearing a tooltip that is not there crashes the plugin, so the widget
  -- remembers whether it ever showed one.
  if Tooltip.shown then
    barWidget.clearTooltip()
    Tooltip.shown = false
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
  Tooltip.shown = true
end

--- Nothing to report: one dot, and that is the entire widget. This holds in both
--- modes — a row of green numbers on a bar is decoration, and the bar's job is
--- to say whether anything needs looking at and otherwise get out of the way.
local function renderNominal(glyph)
  return ui.glyph({ name = glyph, size = 14, color = "primary" })
end

--- One glyph for the worst state in the panel. This is the vertical-bar and
--- compact rendering: the answer to "is anything wrong", without the shape of it.
local function renderWorst(worst)
  local signal = SIGNAL[worst]
  return ui.glyph({ name = signal.glyph, size = 14, color = signal.color })
end

local function renderCounts(glyph)
  local children = { ui.glyph({ name = glyph, size = 14, color = "secondary" }) }

  for _, state in ipairs(SIGNALS) do
    local count = summary[state]
    if count ~= nil and count > 0 then
      local signal = SIGNAL[state]
      children[#children + 1] = ui.label({
        text = " " .. tostring(count),
        fontSize = 12,
        color = signal.color,
        fontWeight = "medium",
        maxLines = 1,
      })
      children[#children + 1] = ui.glyph({ name = signal.glyph, size = 8, color = signal.color })
    end
  end

  return ui.row({ gap = 2, align = "center" }, children)
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
    barWidget.render(ui.glyph({ name = glyph, size = 14, color = "on_surface_variant" }))
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
