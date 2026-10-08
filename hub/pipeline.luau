--!nonstrict
--[[
  fetch -> extract -> map -> format.

  One chain for every card, whatever the source is (D4). `kind` appears exactly
  once in this file: a `list` card widens its extract to many rows in evaluate(),
  which is about the shape of the value rather than the source that produced it.

    Pipeline.fetch(card, done)     IO.  done(raw, err)
    Pipeline.evaluate(card, raw)   pure. Returns a reading, never raises.

  Documentation: docs/03-config.md.  Rationale: docs/07-decisions.md.
]]

local Config = require("./config.luau")
local Util = require("./util.luau")

local M = {}

local isNumber = Util.isNumber

-- ── value → text ─────────────────────────────────────────────────────────────

--- JSON gives back doubles, and Lua prints a whole double as "3.0" in some
--- hosts and "3" in others. A map key or a rendered metric must not depend on
--- which host rendered it, so whole numbers are formatted explicitly.
---
--- The bound is the same idea as `max_items`: a double is exact as an integer up
--- to 2^53, and past that `string.format("%d")` is guessing.
local WHOLE_NUMBER_LIMIT = 1e15

local function numberText(v)
  if v == math.floor(v) and math.abs(v) < WHOLE_NUMBER_LIMIT then
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
    local limit = card.maxItems or Config.DEFAULT_MAX_ITEMS
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

local isString = Util.isString

local function trim(text)
  return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- `command` is the source that carries a reading from anything the shell can
--- reach: a local binary, or `ssh` plus `pct exec` into a container (D17). It
--- is one branch here, and nothing downstream of it knows which produced the
--- bytes — `map`, `thresholds` and `format` run exactly as they do for `static`.
---
--- A non-zero exit is `down` and stderr is the reason, never a code→state table:
--- `pct exec` exits non-zero for a stopped container and for a failed command,
--- so a mapping would render two different faults as the same dot (D17).
local function fetchCommand(card, source, done)
  local raw = source.raw
  local runnable = nil
  if type(raw.argv) == "table" and #raw.argv > 0 then
    runnable = raw.argv
  elseif isString(raw.cmd) and raw.cmd ~= "" then
    runnable = raw.cmd
  else
    done(nil, "command source has neither 'argv' nor 'cmd'")
    return
  end

  local accepted = noctalia.runAsync(runnable, function(result)
    result = result or {}
    if result.timedOut then
      done(nil, "timed out after " .. tostring(card.timeoutMs) .. " ms")
      return
    end
    if (result.exitCode or 0) ~= 0 then
      -- stderr is the usual place a tool explains itself, but not every tool
      -- uses it: `dig` prints "connection timed out" on stdout and exits 9. The
      -- card should carry whichever stream spoke, and only name the code when
      -- neither did.
      local message = result.stderr
      if message == nil or trim(message) == "" then
        message = result.stdout
      end
      if message == nil or trim(message) == "" then
        message = "exit code " .. tostring(result.exitCode)
      end
      done(nil, trim(message))
      return
    end

    -- `parse` decides the stream and the shape where the bytes were produced:
    -- `json` decodes stdout, `stderr` reads the other stream, `stdout` is the
    -- default. This is the alternative to a `jq` pipeline buried in a shell
    -- string whose quoting is already fragile (D17).
    local out = result.stdout or ""
    if raw.parse == "stderr" then
      out = result.stderr or ""
    end

    if raw.parse == "json" then
      local value, err = noctalia.json.decode(out)
      if value == nil then
        done(nil, "command output is not JSON: " .. tostring(err))
        return
      end
      done(value, nil)
      return
    end

    done(trim(out), nil)
  end, card.timeoutMs)

  if not accepted then
    done(nil, "command could not be started")
  end
end

--- Only `static` and `command` fetch in this build. The other three are
--- recognised by config.luau so a typo is still reported as a typo; here they
--- produce an honest "not built yet" rather than an empty reading, because a
--- card that silently shows nothing is the failure mode this panel exists to
--- avoid.
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

  if source.type == "command" then
    fetchCommand(card, source, done)
    return
  end

  done(nil, "source type " .. source.type .. " is not implemented in this build")
end

return M
