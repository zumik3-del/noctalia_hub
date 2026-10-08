--!nonstrict
--[[
  fetch -> extract -> map -> format.

  One chain for every card, whatever the source is (D4). `kind` never appears in
  this file: it decides how the panel draws a reading, not how the reading is
  obtained. The two places `kind` is read here are `list` (whose extract widens
  to many) and the metric/list split in evaluate(), and both are about the shape
  of the value rather than the source that produced it.

    Pipeline.fetch(card, done)     IO.  done(raw, err)
    Pipeline.evaluate(card, raw)   pure. Returns a reading, never raises.

  Documentation: docs/03-config.md.  Rationale: docs/07-decisions.md.
]]

local M = {}

--- Reading order for traversal and for the summary counts: a failure is worth
--- more attention than a nominal reading (D8). `pending` sits with `ok` — it is
--- not a problem, it is an absence of one.
M.RANK = { down = 1, warn = 2, stale = 3, ok = 4, pending = 5 }

-- ── value → text ─────────────────────────────────────────────────────────────

local function isNumber(v)
  return type(v) == "number" and v == v
end

--- JSON gives back doubles, and Lua prints a whole double as "3.0" in some
--- hosts and "3" in others. A map key or a rendered metric must not depend on
--- which host rendered it, so whole numbers are formatted explicitly.
local function numberText(v)
  if v == math.floor(v) and math.abs(v) < 1e15 then
    return string.format("%d", v)
  end
  return tostring(v)
end

local function typeName(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 then
      return "a list of " .. tostring(#v)
    end
    return "an empty list"
  end
  return "a " .. t
end

--- Never substitutes zero for something that is missing. A value that did not
--- arrive stays visible as a placeholder rather than becoming a plausible lie.
local function scalarText(v)
  local t = type(v)
  if t == "number" then
    return numberText(v)
  end
  if t == "boolean" then
    return tostring(v)
  end
  if t == "string" then
    return v
  end
  if t == "table" then
    return "<" .. tostring(#v) .. " items>"
  end
  return "???"
end

--- `{name}` substitution. An unknown placeholder is left in place on purpose:
--- `"{n} nodes"` with nothing to put in `n` should read as a broken format, not
--- as " nodes".
local function render(template, fields, unit)
  local text

  if type(template) == "string" then
    text = template:gsub("{(%w+)}", function(name)
      local value = fields[name]
      if value == nil then
        return "{" .. name .. "}"
      end
      return scalarText(value)
    end)
  else
    text = scalarText(fields.n)
  end

  if type(unit) == "string" and unit ~= "" then
    text = text .. unit
  end

  return text
end

--- The extracted value is addressable as `{n}`, and a mapping value additionally
--- exposes its own keys, so `extract: ".data"` can be formatted as `{n.code}`.
local function fieldsFor(value)
  local fields = {}
  if type(value) == "table" then
    for key, item in pairs(value) do
      fields[tostring(key)] = item
    end
  end
  fields.n = value
  return fields
end

-- ── map: value → state ───────────────────────────────────────────────────────

--- `map` answers "what does this value mean", `thresholds` answers "where does
--- this number turn". They answer different questions and a card carries at
--- most one; when both are present `map` wins, because a value the author has
--- named explicitly is the more specific instruction.
local function stateFor(card, value)
  if card.valueMap ~= nil then
    local state = card.valueMap[scalarText(value)]
    if state == nil then
      return nil, "value " .. string.format("%q", scalarText(value)) .. " is not in `map`"
    end
    return state
  end

  if card.thresholds ~= nil then
    if not isNumber(value) then
      return nil, "thresholds need a number, got " .. typeName(value)
    end
    if card.thresholds.critical ~= nil and value >= card.thresholds.critical then
      return "down"
    end
    if card.thresholds.warn ~= nil and value >= card.thresholds.warn then
      return "warn"
    end
    return "ok"
  end

  return "ok"
end

-- ── evaluate: raw → reading ──────────────────────────────────────────────────

--- Pure. A reading is `{ state, text, fields, rows, error }`:
---   state   pending | ok | warn | down
---   text    the value column, already formatted
---   rows    list cards only, bounded by max_items
---   error   a problem with the card itself, not with the world
local function evaluate(card, raw)
  local reading = { state = "pending", fields = {}, rows = nil, error = nil }

  if card.kind == "list" then
    if type(raw) ~= "table" then
      reading.error = "kind: list needs a source that yields rows; this one yielded " .. typeName(raw)
      return reading
    end

    local rows = {}
    local limit = card.maxItems or 10
    for i, row in ipairs(raw) do
      if i > limit then
        break
      end
      rows[#rows + 1] = row
    end

    -- `n` is the whole fetch, not the bounded view: "8 seen" when max_items is 6
    -- is a true statement about the source, and truncating it would make the
    -- count and the rows disagree.
    reading.rowCount = #raw
    reading.rows = rows
    reading.fields = { n = #raw }
    reading.text = render(card.format, reading.fields, nil)

    -- Colour comes from the fetch, not from the contents: there is no defensible
    -- `warn` for "here are some domain names" (D16). The one exception — a list
    -- that was non-empty and is now empty — needs the previous fetch, which lives
    -- in service.luau.
    reading.state = "ok"
    return reading
  end

  reading.fields = fieldsFor(raw)

  local state, reason = stateFor(card, raw)
  if state == nil then
    reading.state = "down"
    reading.error = reason
    reading.text = "???"
    return reading
  end

  reading.state = state
  reading.text = render(card.format, reading.fields, card.unit)
  return reading
end

M.evaluate = evaluate

--- Row templates share the value syntax. `row_format: "{feed}  {title}"` on a
--- merged feed, `"{5}  {4}"` on `df -P` output after `split: whitespace`.
function M.rowText(template, row)
  if type(row) ~= "table" then
    return scalarText(row)
  end
  return render(template, row, nil)
end

-- ── fetch ────────────────────────────────────────────────────────────────────

--- Only `static` fetches in this build. The other four are recognised by
--- config.luau so a typo is still reported as a typo; here they produce an
--- honest "not built yet" rather than an empty reading, because a card that
--- silently shows nothing is the failure mode this panel exists to avoid.
function M.fetch(card, done)
  local source = card.source

  if source == nil then
    done(nil, "card has no usable source")
    return
  end

  if source.type == "static" then
    done(source.raw.value, nil)
    return
  end

  done(nil, "source type " .. source.type .. " is not implemented in this build")
end

return M
