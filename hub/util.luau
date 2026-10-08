--!nonstrict
--[[
  The two type predicates every layer uses.

  They were written out three times — twice in pipeline.luau, once in config.luau
  — and every copy was already identical, which is the duplication that drifts the
  first time one of them learns something. `isNumber` is the one that has: it
  rejects NaN, because a NaN that compares false to every threshold would read as
  a nominal metric.
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

return M
