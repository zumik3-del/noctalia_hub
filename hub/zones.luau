--!nonstrict
--[[
  The zone, and the config-errors block above it.

  A zone is a header and its cards; the block is document-level problems that
  belong to no card. Both share `renderZoneHeader`, which is the other reason
  they are in one file: the block is a zone whose glyph is a file alert and whose
  body is the error list, and the two were drawing that header twice.

  Like rows.luau, nothing here reads state or the filesystem — everything a zone
  needs arrives in `view` (see rows.luau for the fields it carries), plus the
  runtime records the zone counts problems in.
]]

local Rows = require("./rows.luau")
local Visual = require("./visual.luau")

local M = {}

--- The gap between one config error and the next. A list of problems reads as a
--- list, not as one paragraph, and this is the whole of its leading.
local ERROR_ROW_GAP = 4

--- Problems in this zone, for the header count. Only real problems: a `pending`
--- card is an absence of one, and counting it would make every freshly loaded
--- panel look broken. Each card counts at most once.
local function zoneProblemCount(domain, records)
  local problems = 0
  for _, card in ipairs(domain.cards) do
    if card.hidden ~= true then
      local record = records[card.id]
      local problem = false
      if record ~= nil then
        if record.state == "down" or record.state == "warn" or record.state == "stale" then
          problem = true
        end
        -- A failed update check is a reading that could not be made, so it is a
        -- fault in the card and it counts like one — the dim red badge is the
        -- only trace of it otherwise, and a zone header that says "0" over a
        -- broken badge is a lie the panel can see from the outside.
        --
        -- A *pending* update is deliberately not here. It is a fact about the
        -- host rather than a fault in the card, and it already shows as the
        -- badge on the card and the warn count in the header (D27, D28); a zone
        -- with one pending package is not a zone with a problem.
        if record.updates ~= nil and record.updates.state == "down" then
          problem = true
        end
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

local function renderZoneHeader(view, glyph, title, problems, size)
  local children = {
    ui.glyph({ name = glyph or "layout-columns", size = size + 1, color = view.dimmed }),
    Visual.glyphLabel({
      text = string.upper(title or ""),
      fontSize = size,
      fontWeight = "semibold",
      color = view.dimmed,
      maxLines = 1,
    }),
  }

  if problems > 0 then
    children[#children + 1] = Visual.glyphLabel({
      text = tostring(problems),
      fontSize = size,
      fontWeight = "semibold",
      color = "error",
      maxLines = 1,
    })
  end

  children[#children + 1] = ui.separator({ thickness = 1, color = view.dimmed })

  return ui.row({ gap = 6, align = "center" }, children)
end

--- `index` is the zone's position in the document, and it keys the zone. Keyed by
--- position for the same reason a card is: a duplicated domain id is a config
--- error, and two zones under one key would draw the first twice instead of
--- reporting it.
function M.renderZone(view, domain, index)
  local sizes = view.sizes
  local size = view.size(sizes.valueSize)
  local rowGap = sizes.rowGap
  local zonePadding = sizes.zonePadding
  local children = { renderZoneHeader(view, domain.glyph, domain.title or domain.id, zoneProblemCount(domain, view.records), size) }

  local visible = 0
  for cardIndex, card in ipairs(domain.cards) do
    if card.hidden ~= true then
      visible = visible + 1
      children[#children + 1] = ui.spacer({ height = view.spacing() })
      children[#children + 1] = Rows.renderCard(view, card, view.records[card.id], cardIndex)
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
      color = view.dimmed,
      maxLines = 1,
    })
  end

  return ui.column({
    key = "zone:" .. tostring(index),
    gap = 0,
    padding = zonePadding,
  }, children)
end

--- Document-level problems belong to no card and no zone, so they get their own
--- block above the content: an unknown secret, an unsupported version, a config
--- warning. Silent config problems are how a panel starts lying (docs/04 §6).
function M.renderConfigErrors(view)
  local errors = view.document and view.document.errors or {}
  if #errors == 0 then
    return nil
  end

  local sizes = view.sizes
  local size = view.size(sizes.valueSize)
  local children = {
    renderZoneHeader(view, "file-alert", noctalia.tr("zone.config"), #errors, size),
  }
  for _, err in ipairs(errors) do
    children[#children + 1] = ui.spacer({ height = ERROR_ROW_GAP })
    children[#children + 1] = ui.label({
      text = err.path .. " — " .. err.message,
      fontSize = size - 1,
      color = "error",
      maxLines = 2,
    })
  end

  return ui.column({ gap = 0, padding = sizes.zonePadding }, children)
end

return M
