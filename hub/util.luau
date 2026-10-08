--!nonstrict
--[[
  The small shared vocabulary.

  `isString` and `isNumber` were written out three times before this existed —
  twice in pipeline.luau, once in config.luau — and every copy was already
  identical, which is the duplication that drifts the first time one of them
  learns something. `isNumber` is the one that has: it rejects NaN, because a NaN
  that compares false to every threshold would read as a nominal metric.

  `NO_VALUE` is here for the same reason in the other direction: the collector
  publishes it for a card that has never answered, and the panel draws it where a
  card has no text yet. One glyph, two layers, and the view is not the place the
  collector should be asking for it.
]]

local M = {}

function M.isString(v)
  return type(v) == "string"
end

--- A NaN never equals itself, so `v == v` is the cheapest test there is for one.
--- JSON decodes `NaN` in some hosts and a payload can carry it; a number that
--- fails every comparison is worse than a missing value.
function M.isNumber(v)
  return type(v) == "number" and v == v
end

--- "There is no reading here." Never a zero and never an empty string: a value
--- that did not arrive has to stay visibly missing, or the panel starts
--- inventing facts (docs/06-failure-modes.md). The pipeline's own placeholder
--- for a reading that made no sense is a different string on purpose — see
--- Pipeline.NO_READING_TEXT.
M.NO_VALUE = "—"

return M
