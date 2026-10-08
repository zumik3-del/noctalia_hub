--!nonstrict
--[[
  hub.yaml -> the data model.

  Two halves, deliberately apart:

    Config.read(onDone)            IO: resolve paths, convert YAML to JSON with
                                   yq, read secrets, then call build().
    Config.build(doc, secrets)     pure: validate and normalise. No IO at all.

  The split is what makes the schema testable. Everything that decides what a
  valid config is lives in build(); nothing in build() touches the filesystem or
  spawns anything. That is also the whole reason a card with one bad field does
  not take the panel down with it — see docs/06-failure-modes.md.

  Documentation: docs/03-config.md.  Rationale: docs/07-decisions.md.
]]

local M = {}

--- The config directory, per docs/03-config.md. Overridable with NOCTALIA_CONFIG_HOME.
M.dir = "~/.config/noctalia/hub"
M.hubFile = "hub.yaml"
M.secretsFile = "hub.secrets.yaml"

--- Closed sets. `kind` is closed at six (D22); the source types and the action
--- fields are the schema's other two closed sets (D15, D17).
M.KINDS = { "status", "metric", "release", "link", "console", "list" }
M.SOURCE_TYPES = { "http", "command", "stream", "rss", "static" }
M.ACTIONS = { "link", "link_template", "deep_link", "panel", "run", "control" }

local KINDSET = {}
for _, kind in ipairs(M.KINDS) do KINDSET[kind] = true end
local SOURCESET = {}
for _, sourceType in ipairs(M.SOURCE_TYPES) do SOURCESET[sourceType] = true end

--- Defaults for every optional field, per the schema tables in docs/03-config.md.
local DEFAULT_LAYOUT = {
  density = "compact",
  showHeader = true,
  clock = "%H:%M:%S",
  staleBadge = true,
  -- Card-block framework ported from github-kanban (D24). Density picks a base
  -- row height and padding; these four are the taste layer on top of it, kept in
  -- hub.yaml rather than the manifest because the config is the product.
  fontScale = 100,
  cardRadius = 9,
  cardSpacing = 8,
  cardBorder = "subtle",
  cardBackground = "tinted",
  hoverEffect = "background",
}

local DEFAULT_DEFAULTS = {
  intervalSec = 60,
  timeoutMs = 8000,
  staleAfterSec = 300,
  graphPoints = 48,
}

-- ── small helpers ────────────────────────────────────────────────────────────

local function isString(v)
  return type(v) == "string"
end

local function isNumber(v)
  return type(v) == "number" and v == v -- NaN never equals itself
end

local function isBool(v)
  return type(v) == "boolean"
end

--- "Is this a block of fields at all?" Everything in the schema that is written
--- `key: value` pairs rather than a list arrives as a table, and the error for
--- the other shape is "expected a mapping".
local function isTable(v)
  return type(v) == "table"
end

--- A JSON-decoded table is one of two things: an object keyed by strings, or an
--- array keyed by 1..n. Which one it is decides whether a field is a block or a
--- list, and "expected a mapping" about a list is the whole error message.
---
--- An empty table is ambiguous — it is what `cards: []` and `{}` both decode to —
--- so it counts as a list. Nothing in the schema depends on telling them apart.
local function isList(t)
  if type(t) ~= "table" then
    return false
  end
  local count = 0
  for k in pairs(t) do
    if type(k) ~= "number" then
      return false
    end
    count = count + 1
  end
  for i = 1, count do
    if t[i] == nil then
      return false
    end
  end
  return true
end

local function oneOf(list)
  return table.concat(list, ", ")
end

--- Every error carries the path it came from. Line numbers are not available
--- here — yq does not report them — so a path is what the panel can honestly
--- show. See docs/06-failure-modes.md.
local function newSink()
  local sink = {}
  sink.items = {}
  sink.add = function(path, message)
    sink.items[#sink.items + 1] = { path = path, message = message }
  end
  return sink
end

--- A sink whose errors land in the document list *and* in `owner.errors`.
---
--- Both are needed and they are not redundant. The document list is how the panel
--- reports "2 errors" and how a problem with no owner — a bad secret, an
--- unsupported version — gets shown at all. `owner.errors` is how a card renders
--- the problem under its own row instead of only in a block the reader has to go
--- looking for.
local function ownedSink(sink, owner)
  local owned = newSink()
  owned.add = function(path, message)
    sink.add(path, message)
    owner.errors[#owner.errors + 1] = { path = path, message = message }
  end
  return owned
end

-- ── secret substitution ──────────────────────────────────────────────────────

local SECRET_PATTERN = "^%${([%w_]+)}$"

--- Replaces `${name}` in every string. Walked before validation so that a card
--- whose title comes from a secret is validated as its real value; an unknown
--- name is reported against the path it was found at and the literal is left in
--- place, because a half-substituted config is not a config worth guessing at.
local function substitute(value, path, secrets, sink)
  if isString(value) then
    local name = value:match(SECRET_PATTERN)
    if name == nil then
      return value
    end
    local found = secrets[name]
    if found == nil then
      sink.add(path, "unknown secret \"${" .. name .. "}\" (" .. M.secretsFile .. " has no such key)")
      return value
    end
    if not isString(found) then
      sink.add(path, "secret \"" .. name .. "\" is not a string")
      return value
    end
    return found
  end

  if type(value) == "table" then
    local out = {}
    for k, v in pairs(value) do
      local childPath = type(k) == "number" and (path .. "[" .. k .. "]") or (path .. "." .. tostring(k))
      out[k] = substitute(v, childPath, secrets, sink)
    end
    return out
  end

  return value
end

-- ── layout / defaults ────────────────────────────────────────────────────────

local function readLayout(raw, sink)
  local layout = {}
  for k, v in pairs(DEFAULT_LAYOUT) do
    layout[k] = v
  end

  if raw == nil then
    return layout
  end
  if not isTable(raw) then
    sink.add("layout", "expected a mapping of layout options")
    return layout
  end

  local density = raw.density
  if density ~= nil then
    if density ~= "compact" and density ~= "standard" and density ~= "comfortable" then
      sink.add("layout.density", "expected \"compact\", \"standard\" or \"comfortable\", got " .. string.format("%q", tostring(density)))
    else
      layout.density = density
    end
  end

  for _, key in ipairs({ "show_header", "stale_badge" }) do
    local field = raw[key]
    if field ~= nil then
      local target = key == "show_header" and "showHeader" or "staleBadge"
      if not isBool(field) then
        sink.add("layout." .. key, "expected true or false")
      else
        layout[target] = field
      end
    end
  end

  local clock = raw.clock
  if clock ~= nil then
    if not isString(clock) or clock == "" then
      sink.add("layout.clock", "expected a non-empty time pattern, e.g. \"%H:%M:%S\"")
    else
      layout.clock = clock
    end
  end

  -- Appearance fields (D24). A number out of range is a config error rather than
  -- a clamp: silently pinning `font_scale: 500` to 130 hides a typo the author
  -- would want to see.
  local function readRange(field, path, target, minimum, maximum)
    if field == nil then
      return
    end
    if not isNumber(field) or field < minimum or field > maximum then
      sink.add(path, "expected a number between " .. tostring(minimum) .. " and " .. tostring(maximum) .. ", got " .. tostring(field))
    else
      layout[target] = field
    end
  end

  local function readChoice(field, path, target, allowed)
    if field == nil then
      return
    end
    for _, value in ipairs(allowed) do
      if field == value then
        layout[target] = field
        return
      end
    end
    sink.add(path, "expected one of: " .. oneOf(allowed) .. ", got " .. string.format("%q", tostring(field)))
  end

  readRange(raw.font_scale, "layout.font_scale", "fontScale", 80, 130)
  readRange(raw.card_radius, "layout.card_radius", "cardRadius", 0, 24)
  readRange(raw.card_spacing, "layout.card_spacing", "cardSpacing", 0, 32)
  readChoice(raw.card_border, "layout.card_border", "cardBorder", { "none", "subtle", "accent" })
  readChoice(raw.card_background, "layout.card_background", "cardBackground", { "transparent", "tinted", "solid" })
  readChoice(raw.hover_effect, "layout.hover_effect", "hoverEffect", { "none", "background", "border" })

  return layout
end

--- Reads one positive number, falling back to the default and reporting why.
local function readPositive(raw, path, sink, fallback)
  if raw == nil then
    return fallback
  end
  if not isNumber(raw) then
    sink.add(path, "expected a number")
    return fallback
  end
  if raw <= 0 then
    sink.add(path, "expected a positive number, got " .. tostring(raw))
    return fallback
  end
  return raw
end

local function readDefaults(raw, sink)
  local defaults = {}
  for k, v in pairs(DEFAULT_DEFAULTS) do
    defaults[k] = v
  end

  if raw == nil then
    return defaults
  end
  if not isTable(raw) then
    sink.add("defaults", "expected a mapping of poll defaults")
    return defaults
  end

  defaults.intervalSec = readPositive(raw.interval_sec, "defaults.interval_sec", sink, defaults.intervalSec)
  defaults.timeoutMs = readPositive(raw.timeout_ms, "defaults.timeout_ms", sink, defaults.timeoutMs)
  defaults.staleAfterSec = readPositive(raw.stale_after_sec, "defaults.stale_after_sec", sink, defaults.staleAfterSec)
  defaults.graphPoints = readPositive(raw.graph_points, "defaults.graph_points", sink, defaults.graphPoints)

  return defaults
end

-- ── source ───────────────────────────────────────────────────────────────────

--- `static` and `command` are implemented in this build; the rest are
--- recognised so that a typo is still reported as a typo, and so the pipeline
--- can say "not built yet" rather than "no such type". See
--- docs/05-architecture.md build order.
local BUILT_SOURCE_TYPES = { static = true, command = true }

local function readSource(raw, path, sink)
  if raw == nil then
    sink.add(path, "missing 'source' — every card needs one")
    return nil
  end
  if not isTable(raw) then
    sink.add(path, "expected a mapping of source options")
    return nil
  end

  local kind = raw.type
  if kind == nil then
    sink.add(path .. ".type", "missing 'type' (expected one of: " .. oneOf(M.SOURCE_TYPES) .. ")")
    return nil
  end
  if not SOURCESET[kind] then
    sink.add(path .. ".type", "unknown source type " .. string.format("%q", tostring(kind)) .. " (expected: " .. oneOf(M.SOURCE_TYPES) .. ")")
    return nil
  end

  -- Required per type. Checked here so the error names the missing field rather
  -- than surfacing later as an empty reading.
  local REQUIRED = {
    http = { "url" },
    command = {},       -- argv or cmd, one of which is required
    stream = { "cmd" },
    rss = {},           -- url or feeds
    static = { "value" },
  }
  for _, field in ipairs(REQUIRED[kind]) do
    if raw[field] == nil then
      sink.add(path, "source type " .. kind .. " requires '" .. field .. "'")
    end
  end
  if kind == "command" and raw.argv == nil and raw.cmd == nil then
    sink.add(path, "source type command requires 'argv' (preferred) or 'cmd'")
  end
  if kind == "rss" and raw.url == nil and raw.feeds == nil then
    sink.add(path, "source type rss requires 'url' or 'feeds'")
  end

  local parse = raw.parse
  if parse ~= nil and parse ~= "json" and parse ~= "stdout" and parse ~= "stderr" then
    sink.add(path .. ".parse", "expected \"json\", \"stdout\" or \"stderr\", got " .. string.format("%q", tostring(parse)))
  end

  local pick = raw.pick
  if pick ~= nil and pick ~= "first" and pick ~= "last" then
    sink.add(path .. ".pick", "expected \"first\" or \"last\", got " .. string.format("%q", tostring(pick)))
  end

  local split = raw.split
  if split ~= nil and not isString(split) and split ~= "whitespace" then
    sink.add(path .. ".split", "expected a delimiter string or the word \"whitespace\"")
  end

  return {
    type = kind,
    raw = raw,
    implemented = BUILT_SOURCE_TYPES[kind] == true,
  }
end

-- ── thresholds / map / actions ───────────────────────────────────────────────

local function readThresholds(raw, path, sink)
  if raw == nil then
    return nil
  end
  if not isTable(raw) then
    sink.add(path, "expected { warn: N, critical: N }")
    return nil
  end

  local out = {}
  for _, key in ipairs({ "warn", "critical" }) do
    local value = raw[key]
    if value ~= nil then
      if not isNumber(value) then
        sink.add(path .. "." .. key, "expected a number")
      else
        out[key] = value
      end
    end
  end

  if out.warn ~= nil and out.critical ~= nil and out.warn >= out.critical then
    sink.add(path, "warn must be below critical, got warn=" .. tostring(out.warn) .. " critical=" .. tostring(out.critical))
  end

  return out
end

--- `map` is value -> state. Keys are whatever the source yields, so they arrive
--- from JSON as strings; numbers are accepted and stringified here so a config
--- author can write `0: ok` without quoting.
local function readMap(raw, path, sink)
  if raw == nil then
    return nil
  end
  if not isTable(raw) then
    sink.add(path, "expected a mapping of value to state, e.g. { running: ok }")
    return nil
  end

  local out = {}
  for key, state in pairs(raw) do
    if isString(state) and (state == "ok" or state == "warn" or state == "down") then
      out[tostring(key)] = state
    else
      sink.add(path, "state for " .. string.format("%q", tostring(key)) .. " must be ok, warn or down, got " .. string.format("%q", tostring(state)))
    end
  end

  return out
end

--- Actions are buttons on the card's trailing edge, so two is no longer the
--- ambiguity the old one-action rule guarded against. `link` and `run` sit side
--- by side, each with its own target, and a click on one cannot mean the other —
--- a stronger separation than the single card-wide click the rule was written
--- for (D15, D26). `control` is still deferred and still needs a confirm.
local function readActions(card, path, sink)
  local actions = {}

  for _, field in ipairs(M.ACTIONS) do
    local value = card[field]
    if value ~= nil then
      if field == "control" then
        if not isTable(value) then
          sink.add(path .. ".control", "expected a mapping of control options")
        elseif card.confirm == nil then
          sink.add(path, "'control' requires 'confirm' — a control always names its target before it fires (D15)")
        end
        -- deferred to a later version; see docs/05-architecture.md
      elseif not isString(value) or value == "" then
        sink.add(path .. "." .. field, "expected a non-empty string")
      else
        actions[field] = value
      end
    end
  end

  if next(actions) == nil then
    return nil
  end
  return actions
end

-- ── card ─────────────────────────────────────────────────────────────────────

local function readCard(raw, path, seenIds, defaults, sink)
  local card = { errors = {} }
  local own = ownedSink(sink, card)
  local add = own.add

  if not isTable(raw) then
    add(path, "expected a card mapping")
    return card
  end

  -- identity
  local id = raw.id
  if not isString(id) or id == "" then
    add(path .. ".id", "missing 'id' — it is the key state and poll intervals are tracked by")
  elseif seenIds[id] then
    add(path .. ".id", "duplicate card id " .. string.format("%q", id) .. " — ids address runtime state and must be unique")
  else
    seenIds[id] = true
    card.id = id
  end

  if isString(raw.title) then
    card.title = raw.title
  else
    add(path .. ".title", "missing 'title'")
  end

  local kind = raw.kind
  if not isString(kind) then
    add(path .. ".kind", "missing 'kind' (one of: " .. oneOf(M.KINDS) .. ")")
  elseif not KINDSET[kind] then
    add(path .. ".kind", "unknown kind " .. string.format("%q", kind) .. " (expected: " .. oneOf(M.KINDS) .. ")")
  else
    card.kind = kind
  end

  if raw.glyph ~= nil then
    if isString(raw.glyph) then
      card.glyph = raw.glyph
    else
      add(path .. ".glyph", "expected a Tabler glyph name")
    end
  end

  if raw.span ~= nil then
    if raw.span ~= 1 and raw.span ~= 2 then
      add(path .. ".span", "expected 1 or 2, got " .. tostring(raw.span))
    else
      card.span = raw.span
    end
  end

  if raw.description ~= nil then
    if isString(raw.description) then
      card.description = raw.description
    else
      add(path .. ".description", "expected one line of prose")
    end
  end

  if raw.hidden ~= nil then
    if isBool(raw.hidden) then
      card.hidden = raw.hidden
    else
      add(path .. ".hidden", "expected true or false")
    end
  end

  -- data
  card.source = readSource(raw.source, path .. ".source", own)
  card.intervalSec = readPositive(raw.interval_sec, path .. ".interval_sec", own, defaults.intervalSec)
  card.timeoutMs = readPositive(raw.timeout_ms, path .. ".timeout_ms", own, defaults.timeoutMs)
  card.staleAfterSec = readPositive(raw.stale_after_sec, path .. ".stale_after_sec", own, defaults.staleAfterSec)

  if raw.retries ~= nil then
    if isNumber(raw.retries) and raw.retries >= 0 and raw.retries == math.floor(raw.retries) then
      card.retries = raw.retries
    else
      add(path .. ".retries", "expected a whole number of retries, got " .. tostring(raw.retries))
    end
  end

  -- presentation
  card.thresholds = readThresholds(raw.thresholds, path .. ".thresholds", own)
  card.valueMap = readMap(raw.map, path .. ".map", own)
  card.unit = isString(raw.unit) and raw.unit or nil
  card.maxItems = readPositive(raw.max_items, path .. ".max_items", own, 10)

  if isString(raw.format) then
    card.format = raw.format
  end
  if isString(raw.row_format) then
    card.rowFormat = raw.row_format
  end

  if raw.graph ~= nil then
    if isBool(raw.graph) then
      card.graph = raw.graph
    elseif isNumber(raw.graph) and raw.graph > 0 then
      card.graph = math.floor(raw.graph)
    else
      add(path .. ".graph", "expected true, false or a point count")
    end
  end

  -- A green metric with no thresholds means nothing: is 38% memory nominal or an
  -- emergency? D10 makes it a config error rather than a neutral colour.
  if card.kind == "metric" and card.thresholds == nil then
    add(path, "kind: metric needs 'thresholds' — without them a green number says nothing (D10)")
  end

  card.actions = readActions(raw, path, own)

  -- `link_template` is built from extracted fields by definition, so a template
  -- with no placeholder is a forgotten `{tag}`.
  --
  -- `deep_link` is deliberately not checked. A deep link points into another
  -- application's own URL scheme, and that scheme's vocabulary is not the
  -- source's: xyOps takes `tags:_error` on its API and `result=error` in its UI,
  -- and that mapping is the config author's knowledge, not something a placeholder
  -- can derive (D14). `{query}` is available and optional, not required.
  if card.actions ~= nil and card.actions.link_template ~= nil then
    if not card.actions.link_template:find("{", 1, true) then
      add(path .. ".link_template", "template has no {field} placeholder — expected e.g. {tag} or {n}")
    end
  end

  return card
end

-- ── domain ───────────────────────────────────────────────────────────────────

local function readDomain(raw, index, seenIds, cardIds, defaults, sink)
  local path = "domains[" .. index .. "]"
  local domain = { id = "", title = "", cards = {}, errors = {} }
  local own = ownedSink(sink, domain)
  local add = own.add

  if not isTable(raw) then
    add(path, "expected a domain mapping")
    return domain
  end

  local id = raw.id
  if not isString(id) or id == "" then
    add(path .. ".id", "missing 'id'")
  elseif seenIds[id] then
    add(path .. ".id", "duplicate domain id " .. string.format("%q", id))
  else
    seenIds[id] = true
    domain.id = id
  end

  if isString(raw.title) then
    domain.title = raw.title
  else
    add(path .. ".title", "missing 'title'")
  end

  domain.glyph = isString(raw.glyph) and raw.glyph or "layout-columns"
  domain.intervalSec = readPositive(raw.interval_sec, path .. ".interval_sec", own, defaults.intervalSec)
  domain.staleAfterSec = readPositive(raw.stale_after_sec, path .. ".stale_after_sec", own, defaults.staleAfterSec)

  -- A card inherits its zone's interval and staleness, not the global defaults.
  -- The domain's `interval_sec` is "the whole of release polling" (D4): a zone
  -- that declares 900 must make its cards poll every 900, or the field is a
  -- comment. `timeout_ms` has no domain-level field, so it stays the global one.
  local cardDefaults = {
    intervalSec = domain.intervalSec,
    staleAfterSec = domain.staleAfterSec,
    timeoutMs = defaults.timeoutMs,
    graphPoints = defaults.graphPoints,
  }

  if raw.pin ~= nil then
    if raw.pin ~= "bottom" then
      add(path .. ".pin", "expected \"bottom\" or nothing, got " .. string.format("%q", tostring(raw.pin)))
    else
      domain.pin = "bottom"
    end
  end

  local cards = raw.cards
  if cards == nil then
    add(path .. ".cards", "missing 'cards'")
  elseif not isList(cards) then
    add(path .. ".cards", "expected a list of cards")
  else
    for i, rawCard in ipairs(cards) do
      domain.cards[#domain.cards + 1] = readCard(rawCard, path .. ".cards[" .. i .. "]", cardIds, cardDefaults, sink)
    end
  end

  return domain
end

-- ── build ────────────────────────────────────────────────────────────────────

--- Pure: takes the two decoded YAML documents and returns the data model.
--- Never raises; every problem becomes an entry in `errors`, attached to the
--- domain or card that caused it so the panel can render everything else.
function M.build(doc, secrets)
  secrets = secrets or {}
  local sink = newSink()

  if not isTable(doc) then
    sink.add("<document>", "expected a mapping at the top level")
    return {
      version = 0,
      layout = DEFAULT_LAYOUT,
      defaults = DEFAULT_DEFAULTS,
      domains = {},
      errors = sink.items,
      fatal = true,
    }
  end

  local version = doc.version
  if version == nil then
    sink.add("version", "missing 'version' — this build understands version 1")
  elseif version ~= 1 then
    sink.add("version", "unsupported version " .. tostring(version) .. " — this build understands 1")
  end

  -- Substitution runs first so that everything below validates real values.
  -- Its own errors are document-level: a bad secret is a document-level problem
  -- even when it was found inside one card.
  --
  -- The walk builds new tables rather than mutating in place, so its result is
  -- what everything below reads — dropping it is how a config ends up shipping
  -- literal `${name}` strings into the panel.
  doc = substitute(doc, "<document>", secrets, sink)

  local layout = readLayout(doc.layout, sink)
  local defaults = readDefaults(doc.defaults, sink)

  local domains = {}
  local seenDomains = {}
  local seenCards = {}
  local pinned = 0

  local rawDomains = doc.domains
  if rawDomains == nil then
    sink.add("domains", "missing 'domains' — the panel is a list of zones")
  elseif not isList(rawDomains) then
    sink.add("domains", "expected a list of domains")
  else
    for i, rawDomain in ipairs(rawDomains) do
      local domain = readDomain(rawDomain, i, seenDomains, seenCards, defaults, sink)
      if domain.pin == "bottom" then
        pinned = pinned + 1
        if pinned > 1 then
          domain.errors[#domain.errors + 1] = {
            path = "domains[" .. i .. "].pin",
            message = "at most one domain may pin to the footer (D6)",
          }
          sink.add("domains[" .. i .. "].pin", "at most one domain may pin to the footer (D6)")
          domain.pin = nil
        end
      end
      domains[#domains + 1] = domain
    end
  end

  -- Resolved questions in docs/07-decisions.md: no cap is enforced before there
  -- is a measurement to justify one. This is a warning, not an error.
  local total = 0
  for _, domain in ipairs(domains) do
    total = total + #domain.cards
  end
  if total > 100 then
    sink.add("domains", "warning: " .. total .. " cards — consider more zones (no cap is enforced until there is a render measurement)")
  end

  return {
    version = 1,
    layout = layout,
    defaults = defaults,
    domains = domains,
    errors = sink.items,
  }
end

-- ── read (the IO half) ───────────────────────────────────────────────────────

local function hubPath()
  return noctalia.expandPath(M.dir .. "/" .. M.hubFile)
end

local function secretsPath()
  return noctalia.expandPath(M.dir .. "/" .. M.secretsFile)
end

--- A cheap fingerprint of the config files, for the collector's change watch.
---
--- Both files, not just hub.yaml: editing a secret leaves the document byte-for-
--- byte identical while changing what it says, and a watch that only saw the
--- document would keep serving the old token until something else happened to
--- move the file again.
---
--- A missing file gets its own marker rather than being skipped, so creating
--- hub.secrets.yaml after a config that needed none is still a change. It is also
--- what stops a config that does not exist from looking like an unchanged one:
--- `nil` twice compares equal, and a collector that treated "absent" as "steady"
--- would never notice the file arriving.
function M.stamp()
  local parts = {}
  for _, path in ipairs({ hubPath(), secretsPath() }) do
    local info = noctalia.fileInfo(path)
    if info == nil or info.isDir then
      parts[#parts + 1] = "-"
    else
      parts[#parts + 1] = tostring(info.mtime) .. ":" .. tostring(info.size)
    end
  end
  return table.concat(parts, "|")
end

--- yq converts YAML to JSON once per file change and the JSON is cached in the
--- plugin data dir, so the price of YAML is paid at load rather than per render
--- (D2). The cache is keyed on mtime and size, which is what makes a later hot
--- reload a stat() rather than a guess.
local function convertToJson(path, cachePath, done)
  local info = noctalia.fileInfo(path)
  if info == nil then
    done(nil, "cannot stat " .. path)
    return
  end

  if cachePath ~= nil and noctalia.fileExists(cachePath) then
    local cachedInfo = noctalia.fileInfo(cachePath)
    local cached = cachedInfo and noctalia.readFile(cachePath)
    if cached and cachedInfo.mtime > info.mtime and cachedInfo.size > 0 then
      done(cached, nil)
      return
    end
  end

  if not noctalia.commandExists("yq") then
    done(nil, "yq not found — hub.yaml is YAML and needs a converter (see docs/07-decisions.md, D2)")
    return
  end

  -- argv, not a shell string: the path is user data and must not be re-parsed.
  local accepted = noctalia.runAsync({ "yq", "-o=json", ".", path }, function(result)
    if result.timedOut then
      done(nil, "yq timed out on " .. path)
      return
    end
    if result.exitCode ~= 0 then
      local message = result.stderr
      if message == nil or message == "" then
        message = "exit code " .. tostring(result.exitCode)
      end
      done(nil, message)
      return
    end
    if cachePath ~= nil then
      noctalia.writeFile(cachePath, result.stdout)
    end
    done(result.stdout, nil)
  end, 10000)

  if not accepted then
    done(nil, "yq could not be started")
  end
end

local function decodeJson(text, path, done)
  local value, err = noctalia.json.decode(text)
  if value == nil then
    done(nil, path .. ": " .. tostring(err or "invalid JSON"))
    return
  end
  done(value, nil)
end

--- Loads hub.yaml and hub.secrets.yaml and hands the pair to build().
--- `onDone(model)` on success, `onDone(nil, reason)` when the config cannot be
--- read at all — the one case where the panel does not render (docs/06).
function M.read(onDone)
  local path = hubPath()

  if not noctalia.fileExists(path) then
    onDone(nil, "no config at " .. path .. "\ncopy config/hub.skeleton.yaml there to start")
    return
  end

  local dataDir = noctalia.pluginDataDir()
  local cacheDir = dataDir

  convertToJson(path, cacheDir and (cacheDir .. "/hub.json"), function(hubJson, err)
    if hubJson == nil then
      onDone(nil, tostring(err))
      return
    end
    decodeJson(hubJson, M.hubFile, function(doc, decodeErr)
      if doc == nil then
        onDone(nil, tostring(decodeErr))
        return
      end

      local secretPath = secretsPath()
      if not noctalia.fileExists(secretPath) then
        -- Secrets are optional: a config with no ${name} in it needs no file.
        onDone(M.build(doc, {}), nil)
        return
      end

      convertToJson(secretPath, cacheDir and (cacheDir .. "/hub.secrets.json"), function(secretsJson, secretsErr)
        if secretsJson == nil then
          onDone(nil, tostring(secretsErr))
          return
        end
        decodeJson(secretsJson, M.secretsFile, function(secrets, secretsDecodeErr)
          if secrets == nil then
            onDone(nil, tostring(secretsDecodeErr))
            return
          end
          onDone(M.build(doc, secrets), nil)
        end)
      end)
    end)
  end)
end

return M
