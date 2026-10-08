--!nonstrict
--[[
  The visual language (docs/04-visual-language.md), in one address.

  Both surfaces draw from here: the panel and the bar. The four signal roles used
  to be written out twice — STATE_COLOR/STATE_GLYPH in the panel, SIGNAL in the
  widget — and the copies had already drifted, the widget missing `pending` the
  panel had added for a card it had no record for. A role is one fact (a colour
  and a glyph), so it gets one table.

  What is deliberately not here: anything that reads `doc.layout`. Fill, radius
  and border come from the config, and the config arrives as state a surface
  subscribes to. A module that took them as arguments would be one more place to
  keep in step with config.luau's defaults (which is exactly the drift D10 and
  D24 exist to prevent), so visual.luau holds the roles, the two glyph helpers and
  the card wrapper, and its caller hands it the geometry it resolved.
]]

local M = {}

--- Colour is semantic only: four signal roles plus `pending`, which is the
--- absence of a reading rather than a state of its own (D5). No free-form colour
--- exists in the config and none is invented here.
M.STATE_ROLES = {
  ok = { color = "primary", glyph = "circle-filled" },
  warn = { color = "secondary", glyph = "alert-circle" },
  down = { color = "error", glyph = "alert-triangle" },
  stale = { color = "on_surface_variant", glyph = "circle-dashed" },
  pending = { color = "on_surface_variant", glyph = "circle" },
}

--- A card without a glyph gets one from its kind, so a column of unadorned cards
--- still reads as instruments rather than as a word list.
M.KIND_GLYPH = {
  status = "activity",
  metric = "chart-line",
  release = "tag",
  link = "external-link",
  console = "file-text",
  list = "list",
}

-- ── hover ────────────────────────────────────────────────────────────────────

--- The card under the pointer, by key. Hover is a render-time decision, so it
--- lives in the view layer and never crosses to the collector.
local hovered = nil
local requestRedraw = nil

--- How the caller redraws. Modules cannot call into each other — there is no
--- shared Lua memory between the plugin's entries — so the surface registers its
--- render() once and visual.luau calls that instead of guessing.
function M.setRedraw(fn)
  requestRedraw = fn
end

--- Called when the pointer's answer stops mattering: switching tabs, closing the
--- panel. A stale key would highlight a row that is no longer under the pointer.
function M.clearHover()
  hovered = nil
end

function M.isHovered(key)
  return hovered == key
end

local function hoverTo(value, key)
  local nextHovered = value == "true" and key or nil
  if nextHovered ~= hovered then
    hovered = nextHovered
    if requestRedraw ~= nil then
      requestRedraw()
    end
  end
end

-- ── rows ─────────────────────────────────────────────────────────────────────

--- The row every card is drawn in: the github-kanban activity block, with its
--- badge, two lines, reading and buttons (D25). What differs between a reading
--- card and a `kind: link` bookmark is what goes inside; the wrapper, the hover
--- response and the click target were the same code twice, so they live here.
---
--- `props`:
---   key                    the row's identity, unique per position
---   children               the row's contents
---   gap, paddingH, paddingV, radius
---                          geometry, resolved by the caller from `doc.layout`
---   fill, border, borderWidth
---                          the theme state, also from the caller
---   onClick                optional. A row with no target has none, and a
---                          bookmark with no `link:` is exactly that.
function M.cardShell(props)
  return ui.row({
    key = props.key,
    gap = props.gap,
    paddingH = props.paddingH,
    paddingV = props.paddingV,
    radius = props.radius,
    fill = props.fill,
    border = props.border,
    borderWidth = props.borderWidth,
    align = "center",
    onClick = props.onClick,
    onHover = function(value)
      hoverTo(value, props.key)
    end,
  }, props.children)
end

--- A label that shares a row with a glyph.
---
--- The host anchors an icon font at the ink top and a text label at the text
--- baseline. In a row that centres its children, the two therefore sit on
--- different vertical centres: the icon's ink is high in its box, the text's ink
--- is low in its box, and the pair reads as crooked even though both are
--- "centred". `pictographic` centres the label's ink instead of aligning its
--- baseline, which is the alignment a glyph expects.
---
--- Only where a glyph is actually in the row. On a label that stands alone the
--- same setting centres the x-height rather than the line, and a column of plain
--- text starts to drift.
---
--- The props are copied rather than set in place: a function that mutates its
--- argument is fine while every caller passes a literal, and a trap the first
--- time one caller reuses a table it also reads from.
function M.glyphLabel(props)
  local out = {}
  for key, value in pairs(props) do
    out[key] = value
  end
  out.baseline = "pictographic"
  return ui.label(out)
end

return M
