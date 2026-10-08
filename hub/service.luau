--!nonstrict
--[[
  The collector: the only entry that talks to the outside world.

  It loads hub.yaml, polls the cards on their own intervals, decides what state
  each reading is in, and publishes the result into noctalia.state. It never
  touches the UI — panel.luau and widget.luau are subscribers and know nothing
  about where a number came from.

  The rule that shapes this file: a failure never destroys a reading. A card that
  stops answering keeps its last good value and its age; it is never zeroed,
  hidden, or replaced with "no data" (D7). docs/06-failure-modes.md is the
  specification this implements.
]]

-- The extension is part of the path, not a detail: Noctalia's module loader
-- refuses a require that is not relative and does not end in .luau, and the
-- failure surfaces as "call to 'chunk' failed" with no mention of the module.
local Config = require("./config.luau")
local Pipeline = require("./pipeline.luau")

noctalia.setUpdateInterval(1000)

local STATE_CONFIG = "hub.config"
local STATE_CARDS = "hub.cards"
local STATE_SUMMARY = "hub.summary"
local STATE_FATAL = "hub.fatal"
local STATE_CMD = "hub.cmd"

--- doc         the validated model from config.luau, nil until it loads
--- cards       cardId -> runtime record
--- fatal       why the config could not be read at all; the panel shows this
---             instead of zones, because a config that cannot be read leaves
---             nothing honest to render (docs/06-failure-modes.md)
local doc = nil
local cards = {}
local fatal = ""

--- configStamp  mtime:size of the config files as of the start of the last read
--- loading      a read is in flight — yq is a subprocess, and a second one
---              queued behind a slow first would apply its answer out of order
local configStamp = nil
local loading = false

--- Defined below, called from tick: the change watch and the loader are mutually
--- dependent, and a forward declaration beats reordering code that reads better
--- in the order the collector actually runs.
local load

local function nowMs()
  return noctalia.nowMs()
end

-- ── runtime records ──────────────────────────────────────────────────────────

local function newUpdatesRecord(card)
  if card.updates == nil then
    return nil
  end
  return {
    state = "pending",
    text = "",
    error = nil,
    lastGoodAtMs = nil,
    attempts = 0,
    nextDueAtMs = 0,
  }
end

local function newRecord(card)
  return {
    id = card.id,
    state = "pending",
    text = "",
    fields = {},
    rows = nil,
    rowCount = 0,
    error = nil,
    -- A config problem is not a fetch problem: it is already true before the
    -- first poll and it does not clear itself when the source recovers.
    configError = nil,
    lastGoodAtMs = nil,
    attempts = 0,
    nextDueAtMs = 0,
    -- The second reading is nested so it travels with its card through
    -- adoptRecords and signature, and gets its own rhythm: a package check does
    -- not run on the service's cadence (D27).
    updates = newUpdatesRecord(card),
  }
end

--- Rebuilds the record table from the model, carrying the last good reading of
--- every card id that survived. This is what lets a config edit show a new tree
--- without flashing the whole panel back to "pending" — and it is also what
--- makes the empty-list rule in poll() survive a reload.
local function adoptRecords()
  local adopted = {}
  for _, domain in ipairs(doc.domains) do
    for _, card in ipairs(domain.cards) do
      if card.id ~= nil and card.id ~= "" then
        local record = newRecord(card)
        local previous = cards[card.id]
        if previous ~= nil then
          record.state = previous.state
          record.text = previous.text
          record.fields = previous.fields
          record.rows = previous.rows
          record.rowCount = previous.rowCount
          record.lastGoodAtMs = previous.lastGoodAtMs
          record.attempts = previous.attempts
          if record.updates ~= nil and previous.updates ~= nil then
            record.updates.state = previous.updates.state
            record.updates.text = previous.updates.text
            record.updates.lastGoodAtMs = previous.updates.lastGoodAtMs
            record.updates.attempts = previous.updates.attempts
          end
        end
        record.nextDueAtMs = 0 -- poll everything once on (re)load
        adopted[card.id] = record
      end
    end
  end
  cards = adopted
end

-- ── publishing ───────────────────────────────────────────────────────────────

--- The panel redraws whenever a watched key is written, so a write that changes
--- nothing is a wasted tree rebuild. The signature covers exactly what is drawn:
--- state, value, errors and the row count. Ages are deliberately absent — the
--- panel derives them from `nowMs()` at render time, so the clock keeps ticking
--- without the collector publishing once a second.
local function signature()
  local parts = { fatal }
  for id, record in pairs(cards) do
    local updates = record.updates
    parts[#parts + 1] = table.concat({
      id,
      record.state,
      record.text,
      record.error or "",
      record.configError or "",
      tostring(record.rowCount),
      tostring(record.attempts),
      updates and updates.state or "",
      updates and updates.text or "",
      updates and updates.error or "",
    }, "\1")
  end
  table.sort(parts)
  return table.concat(parts, "\2")
end

local function countStates()
  local counts = { ok = 0, warn = 0, down = 0, stale = 0, pending = 0, errors = 0, total = 0 }
  for _, record in pairs(cards) do
    counts.total = counts.total + 1
    local state = record.state
    local updatesWarn = record.updates ~= nil and record.updates.state == "warn"

    -- `warn` is a superset of the card's own state: a service whose reading is
    -- fine but whose host has pending OS updates sits on the same yellow line as
    -- a crossed threshold (D28). It is counted once, and a card already down or
    -- stale keeps its more severe count instead of also reading as warn.
    if state == "warn" or ((state == "ok" or state == "pending") and updatesWarn) then
      counts.warn = counts.warn + 1
    elseif counts[state] ~= nil then
      counts[state] = counts[state] + 1
    end

    if record.error ~= nil or record.configError ~= nil then
      counts.errors = counts.errors + 1
    end
  end
  return counts
end

local publishedSignature = nil

local function publish()
  local sig = signature()
  if sig == publishedSignature then
    return
  end
  publishedSignature = sig

  noctalia.state.set(STATE_FATAL, fatal)
  noctalia.state.set(STATE_CONFIG, doc or { domains = {}, errors = {} })
  noctalia.state.set(STATE_CARDS, cards)
  noctalia.state.set(STATE_SUMMARY, countStates())
end

-- ── polling ──────────────────────────────────────────────────────────────────

--- The host's `runAsync` refuses to start a command when too many are already
--- running, and answers with "command could not be started". A zone of a dozen
--- cards all due on the same tick is exactly that pile-up — every card is due at
--- once on load and again when its interval lands on the same second — so the
--- collector starts at most a few at a time and drains the rest as each
--- finishes. The cap is low on purpose: the run channel is shared with every
--- other plugin in the shell.
local MAX_INFLIGHT = 4
local inflight = 0
local queue = {}

--- Starts queued jobs while there is room. A job is `function(done)` and must
--- call `done` exactly once when its fetch settles, which is what frees the slot
--- and lets the next one start.
local pump
pump = function()
  while inflight < MAX_INFLIGHT do
    local job = table.remove(queue, 1)
    if job == nil then
      return
    end
    inflight = inflight + 1
    job(function()
      inflight = inflight - 1
      pump()
    end)
  end
end

local function enqueue(job)
  queue[#queue + 1] = job
  pump()
end

--- The fetch worked or it did not; either way the record keeps its last good
--- reading (D7). Split out of the runAsync callback so the scheduler is told the
--- job finished no matter which branch returned.
local function applyReading(card, record, raw, err)
  if err ~= nil then
    -- The reading survives: state and error change, text and age do not.
    record.attempts = record.attempts + 1
    record.error = err
    record.state = "down"
    if record.lastGoodAtMs == nil then
      record.text = "—"
    end
    return
  end

  local reading = Pipeline.evaluate(card, raw)
  record.attempts = 0

  if reading.error ~= nil then
    -- The fetch worked and the reading does not make sense. That is `down`
    -- with the reason attached, and it does not overwrite the last good value.
    record.error = reading.error
    record.state = "down"
    if record.lastGoodAtMs == nil then
      record.text = "???"
    end
    return
  end

  record.error = nil

  -- A list that was non-empty and is now empty is a broken fetch, not a fact
  -- about the world (D16). A list that has simply never had rows is fine.
  if card.kind == "list" and (reading.rowCount or 0) == 0 and (record.rowCount or 0) > 0 then
    record.state = "warn"
    record.error = "no rows — this source returned " .. tostring(record.rowCount) .. " a moment ago"
    record.lastGoodAtMs = nowMs()
    return
  end

  record.state = reading.state
  record.text = reading.text
  record.fields = reading.fields
  record.rows = reading.rows
  record.rowCount = reading.rowCount or 0
  record.lastGoodAtMs = nowMs()
end

local function poll(card, record, complete)
  Pipeline.fetch(card, function(raw, err)
    applyReading(card, record, raw, err)
    complete()
  end)
end

--- The updates reading reuses the pipeline rather than growing a parser: a
--- `command` source fetches, and `evaluate` with a `{ warn: 1 }` threshold turns
--- the count into a state and its text. The one thing the pipeline cannot do for
--- a `command` is read the count as a number — stdout is text — so a non-number
--- is `down` with the bytes quoted, never a zero the badge would draw as "all
--- clear".
local function applyUpdates(card, record, raw, err)
  local updates = record.updates
  local spec = card.updates

  if err ~= nil then
    updates.attempts = updates.attempts + 1
    updates.error = err
    updates.state = "down"
    return
  end

  local n = tonumber(type(raw) == "number" and raw or tostring(raw))
  if n == nil then
    updates.attempts = updates.attempts + 1
    updates.error = "update check did not return a number: " .. string.format("%q", tostring(raw))
    updates.state = "down"
    return
  end

  local reading = Pipeline.evaluate({ thresholds = { warn = 1 }, format = spec.format }, n)
  if reading.error ~= nil then
    updates.attempts = updates.attempts + 1
    updates.error = reading.error
    updates.state = "down"
    return
  end

  updates.attempts = 0
  updates.error = nil
  updates.state = reading.state
  updates.text = reading.text
  updates.lastGoodAtMs = nowMs()
end

local function pollUpdates(card, record, complete)
  local spec = card.updates
  Pipeline.fetch({ source = spec.source, timeoutMs = spec.timeoutMs }, function(raw, err)
    applyUpdates(card, record, raw, err)
    complete()
  end)
end

--- The degradation ladder from docs/06-failure-modes.md:
---   attempt fails    -> down,   previous value retained
---   stale_after_sec  -> stale,  previous value retained, dimmed
---   recovery         -> ok,     attempt counter reset
--- Staleness needs something to be stale about, so a card that has never
--- succeeded stays `down` rather than aging into a dimmer `down`.
local function applyAge(record, card, stamp)
  if record.lastGoodAtMs == nil then
    return
  end
  if (stamp - record.lastGoodAtMs) / 1000 > card.staleAfterSec then
    record.state = "stale"
  end
end

local function tickCard(card, record, stamp)
  -- `hidden` keeps a card in the config without rendering it. It does not stop
  -- the source: hiding a card is not a way to un-watch a service.
  if card.hidden == true then
    return
  end

  -- A `kind: link` card has no source to poll, and neither has a card whose
  -- source failed validation — `readSource` returns nil and the config error is
  -- already attached to the record. Polling either would ask the pipeline for a
  -- fetch it cannot make.
  if card.source == nil then
    return
  end

  if stamp >= record.nextDueAtMs then
    -- A fixed interval per card. The panel does not adapt the period to how
    -- quickly a source answers (docs/06-failure-modes.md).
    record.nextDueAtMs = stamp + card.intervalSec * 1000
    enqueue(function(done)
      poll(card, record, done)
    end)
  end

  if record.updates ~= nil and stamp >= record.updates.nextDueAtMs then
    record.updates.nextDueAtMs = stamp + card.updates.intervalSec * 1000
    enqueue(function(done)
      pollUpdates(card, record, done)
    end)
  end

  applyAge(record, card, stamp)
end

local function tick(stamp)
  -- The host has no file-watch API: state.watch is the only subscription there
  -- is, and it fires on a write, not on a file being edited. So the config is
  -- watched by stat'ing it on the tick that already runs — one stat per second
  -- against a file the plugin has to open anyway.
  --
  -- Returning rather than polling first: the cards in `doc` are the ones the file
  -- used to describe. Polling them before the reload lands spends a subprocess on
  -- a card the user may have just deleted, and a card added a moment ago stays
  -- pending for one more poll interval it may not have wanted.
  if Config.stamp() ~= configStamp then
    load()
    return
  end

  if doc ~= nil then
    for _, domain in ipairs(doc.domains) do
      for _, card in ipairs(domain.cards) do
        local record = cards[card.id]
        if record ~= nil then
          tickCard(card, record, stamp)
        end
      end
    end
  end

  publish()
end

-- ── entry ────────────────────────────────────────────────────────────────────

function update()
  tick(nowMs())
end

--- "r" in the panel asks for a refresh rather than causing one: the panel is a
--- subscriber, and starting work belongs on this side of the boundary. Making
--- every card due on the next tick is the whole of it — this does not bypass
--- `stale_after_sec`, it just does not wait for the next scheduled poll.
local function refreshSoon()
  if doc == nil then
    return
  end
  for _, domain in ipairs(doc.domains) do
    for _, card in ipairs(domain.cards) do
      local record = cards[card.id]
      if record ~= nil then
        record.nextDueAtMs = 0
        if record.updates ~= nil then
          record.updates.nextDueAtMs = 0
        end
      end
    end
  end
end

--- A card's trailing buttons ask the collector to act, the way refresh does:
--- the panel does not launch a process, it publishes a request and stays a
--- subscriber (docs/05-architecture.md). `link` opens the browser and nothing
--- else; `run` hands a literal string to a terminal window, which is the whole
--- difference between the two actions (D12, D20).
local function performAction(action, target)
  if action == "link" then
    noctalia.runAsync({ "xdg-open", target })
    return
  end

  if action == "run" then
    -- The feature check follows tailscale: a shell without `runInTerminal`
    -- still runs the command, it just does not show a window.
    if type(noctalia.runInTerminal) == "function" then
      noctalia.runInTerminal(target)
    else
      noctalia.runAsync(target)
    end
  end
end

noctalia.state.watch(STATE_CMD, function(command)
  if command == "refresh" then
    refreshSoon()
    return
  end

  if type(command) == "table" and type(command.action) == "string" then
    if type(command.target) == "string" and command.target ~= "" then
      performAction(command.action, command.target)
    end
  end
end)

--- An invalid config never stops the collector: the panel needs something to
--- render, and a config that cannot be read is itself something the panel
--- reports rather than hides.
load = function()
  if loading then
    -- Dropping the read rather than queueing it: a queued read answers a question
    -- about a file that has already moved on, and applies its result after a newer
    -- one. The stamp is left alone so the next tick notices the change is still
    -- unapplied and tries again — losing a reload is better than showing a config
    -- the user did not write.
    return
  end
  loading = true

  -- Taken before the read, not after: yq is a subprocess, so a file written while
  -- it runs would otherwise be stamped as already-applied and never re-read.
  local started = Config.stamp()

  Config.read(function(model, reason)
    loading = false
    configStamp = started
    fatal = reason or ""
    doc = model

    if model ~= nil then
      adoptRecords()
      -- Config errors are true before the first poll and stay true until the
      -- file changes, so they are attached once here instead of every poll.
      for _, domain in ipairs(model.domains) do
        for _, card in ipairs(domain.cards) do
          local record = cards[card.id]
          if record ~= nil and #card.errors > 0 then
            record.configError = card.errors[1].message
          end
        end
      end
    end

    publishedSignature = nil
    publish()

    -- One poll straight away rather than waiting out the first interval. The
    -- panel is opened to be looked at, and a second of "pending" on every open is
    -- a second where the panel says nothing about whether the world is fine.
    tick(nowMs())
  end)
end

load()
