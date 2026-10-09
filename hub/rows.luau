--!nonstrict
--[[
  The card rows.

  One card, two shapes: a reading (badge, two lines, value, state marker) and the
  `kind: link` bookmark. Both are the same row underneath — that wrapper is
  `Visual.cardShell` — so what lives here is what goes inside it.

  Nothing in this file reads state or the filesystem. Everything a row needs from
  the panel arrives in `view`, built once per render by the panel that owns it:

    sizes      the density table (docs/04): valueSize, cardPadH, cardPadV
    size(n)    a font size, already scaled by `font_scale`
    radius()   the card corner radius from `layout:`
    spacing()  the gap between cards from `layout:`
    fill(active) the card's fill for its background mode, and the hover
               response — `hover_effect` is a layout field, so the panel
               resolves it and this file never reads it
    border(active) -> colour, width
    secondary, dimmed
               the two text roles a row uses
    dispatch(action, target)
               how a button reaches the collector (docs/05-architecture.md)

  A module cannot hold `doc` or `cards` itself: the panel's watches replace those
  tables, and a module holding the old one would draw a reading the collector has
  already moved past. Handing over functions is what keeps that impossible.
]]

local Util = require("./util.luau")
local Visual = require("./visual.luau")

--- "There is no reading here." The collector publishes it for a card that has
--- never answered and the panel draws it where a card has no text yet, so the
--- glyph is the shared one in util.luau rather than a view decision.
local NO_VALUE = Util.NO_VALUE

--- The card's own numbers, in one block. Every one of them is relative to the
--- font size, so a density or a `font_scale` scales the whole shape; what they
--- fix is the *relationship* — how much bigger the badge is than the line it
--- sits beside, and how the two lines of type are ordered.
local BADGE_PADDING = 17         -- badge edge past the text size
local BADGE_GLYPH_OVERHANG = 5   -- the glyph inside the badge
local BADGE_MIN_RADIUS = 4       -- a badge at the smallest font still reads round
local BADGE_FILL = "primary/0.12" -- the tile behind the glyph: a palette role
local TITLE_STEP = 2             -- the title leads its line
local VALUE_STEP = 1             -- the value sits just under it
local TITLE_GAP = 3              -- between the title and its second line

--- The leading tile, and the one place the card's glyph is chosen. Both card
--- shapes draw it — a reading and a `kind: link` bookmark are the same row
--- underneath — so writing it out twice meant the tile's geometry had two copies
--- and the glyph's fallback chain had two, which had already diverged: the link
--- card reached for its own `"link"` while `Visual.KIND_GLYPH` held an
--- `external-link` for it. One expression, one tile.
local function leadingTile(size, card)
  local tile = size + BADGE_PADDING
  return ui.column({
    width = tile,
    height = tile,
    radius = math.max(BADGE_MIN_RADIUS, math.floor(tile / 4)),
    fill = BADGE_FILL,
    align = "center",
    justify = "center",
  }, {
    ui.glyph({
      name = card.glyph or Visual.KIND_GLYPH[card.kind] or "activity",
      size = size + BADGE_GLYPH_OVERHANG,
      color = "primary",
    }),
  })
end

--- How much text a line of a card may take. A title wraps to two because a
--- service can be called `Home Assistant`; everything else on the card is one
--- line by design — a value, a description and a reason are each one fact, and a
--- second line of any of them is a card asking for more room than the panel has.
local TITLE_MAX_LINES = 2
local ONE_LINE = 1

local M = {}

--- "from 14:02 · 3 attempts" — the line that makes a frozen reading honest. The
--- value stays on screen; this says how old it is and how many tries have failed
--- since (docs/06-failure-modes.md).
local function ageLine(record)
  if record.lastGoodAtMs == nil then
    return nil
  end

  local parts = {
    "from " .. noctalia.formatTime("%H:%M:%S", math.floor(record.lastGoodAtMs / 1000)),
  }
  if record.attempts > 0 then
    parts[#parts + 1] = tostring(record.attempts) .. " attempts"
  end

  return table.concat(parts, " · ")
end

--- The reason a card is not ok, as one line for the state marker's tooltip. A
--- config problem outranks a fetch problem: it is the reason the fetch may never
--- succeed. A stale card with no error shows its age instead, so the dimmed dot
--- explains itself too.
---
--- A card with no record has no `configError` — a card that failed validation
--- never got one. Its errors live on the card itself, which is the only place they
--- can be read from, so this is where a card with no `id` still reports itself.
local function cardProblem(card, record)
  if record ~= nil then
    if record.configError ~= nil then
      return record.configError
    end
    if record.error ~= nil then
      return record.error
    end
    if record.state == "stale" then
      return ageLine(record)
    end
  end

  if #(card.errors or {}) > 0 then
    return card.errors[1].message
  end

  return nil
end

--- The second line under a card: what the thing is. A failure no longer takes
--- this line — it lives in the state marker's tooltip instead (D25), so a red
--- card still says what it measures while the reason waits one hover away on the
--- dot that is already coloured for it.
---
--- The age stays here when there is no description to show, because a frozen
--- reading with no age reads as a live one (docs/06-failure-modes.md).
local function cardSecondLine(view, card, record, size)
  if type(card.description) == "string" and card.description ~= "" then
    return ui.label({ text = card.description, fontSize = size, color = view.secondary, maxLines = TITLE_MAX_LINES })
  end

  if record.state == "stale" or record.attempts > 0 then
    local text = ageLine(record)
    if text ~= nil then
      return ui.label({ text = text, fontSize = size, color = view.dimmed, maxLines = ONE_LINE })
    end
  end

  return nil
end

--- A card's own second row of facts: small tiles on the trailing edge, left of
--- the update badge, each a label over a value. A tile is static (`value`) or
--- dynamic (`source`), and one carrying a `link` is a button that opens it — the
--- tile answers the pointer and names its target (D30). Drawn only when the card
--- carries `mini_cards`; a card without them is the shape it always was.
local MINI_GAP = 4         -- between the tiles
local MINI_PAD_H = 6       -- a tile's side padding
local MINI_PAD_V = 3       -- a tile's top and bottom padding
local MINI_RADIUS = 6      -- a tile's corner rounding
local MINI_LABEL_STEP = 2  -- the label sits this far under the value's size
local MINI_FILL_HOVER = "primary/0.22" -- a clickable tile's fill under the pointer

local function miniCardsRow(view, card, record, size, cardIndex)
  local minis = card.miniCards
  if minis == nil or #minis == 0 then
    return nil
  end

  -- A tile is a fixed width so the row reads as cards rather than loose labels,
  -- and the text is centred in it: a label that hugs its own text has no room
  -- on either side to centre in.
  local tileW = size * 4 + 8

  local tiles = {}
  for i, mini in ipairs(minis) do
    local text, color, tooltip
    if mini.source ~= nil then
      -- A dynamic tile: the collector owns the reading, the panel only draws
      -- it. Before the first fetch the value is the shared placeholder, and a
      -- failed one keeps the last good value with the reason on the tooltip
      -- (D7, D30).
      local miniRecord = record ~= nil and record.minis ~= nil and record.minis[i] or nil
      if miniRecord ~= nil then
        text = (miniRecord.text ~= nil and miniRecord.text ~= "") and miniRecord.text or NO_VALUE
        tooltip = miniRecord.error
        -- A tile speaks in colour only when something is wrong: `warn` and
        -- `down` take the state colour, and everything else — including the `ok`
        -- a threshold produces — draws in the neutral column colour a static
        -- tile uses. A green number for "nothing failed" is noise, and without a
        -- threshold `ok` means even less.
        if miniRecord.state == "warn" or miniRecord.state == "down" then
          color = Visual.STATE_ROLES[miniRecord.state].color
        else
          color = view.secondary
        end
      else
        text = NO_VALUE
        color = view.secondary
      end
    else
      text = tostring(mini.value) .. (mini.unit or "")
      color = view.secondary
    end

    local valueLabel = ui.label({
      text = text,
      fontSize = size,
      textAlign = "center",
      fontWeight = "medium",
      color = color,
      maxLines = ONE_LINE,
    })
    if tooltip ~= nil then
      valueLabel = ui.row({ tooltip = tooltip, align = "center" }, { valueLabel })
    end

    -- A tile with a `link` is a button: it opens the URL through the same
    -- dispatch a card's own link button uses (D26), answers the pointer with a
    -- stronger fill so it reads as clickable, and names its target on the
    -- tooltip. A tile without one is the inert fact it always was. The key is
    -- the tile's own — the card shell keys hover by the card, and a tile inside
    -- it needs a distinct identity to light up on its own.
    local link = mini.link
    local miniKey = "mini:" .. tostring(cardIndex) .. ":" .. tostring(i)
    local active = link ~= nil and Visual.isHovered(miniKey)

    local tile = {
      key = miniKey,
      width = tileW,
      paddingH = MINI_PAD_H,
      paddingV = MINI_PAD_V,
      radius = MINI_RADIUS,
      fill = active and MINI_FILL_HOVER or BADGE_FILL,
      gap = 1,
    }
    if link ~= nil then
      tile.tooltip = link
      tile.onClick = function()
        view.dispatch("link", link)
      end
      tile.onHover = function(value)
        Visual.hover(value, miniKey)
      end
    end

    tiles[#tiles + 1] = ui.column(tile, {
      ui.label({
        -- Upper-cased like a zone title: the tile head is a column head, and the
        -- case of the config word is not something the author should manage.
        text = string.upper(mini.label),
        fontSize = size - MINI_LABEL_STEP,
        textAlign = "center",
        color = view.dimmed,
        maxLines = ONE_LINE,
      }),
      valueLabel,
    })
  end

  return ui.row({ gap = MINI_GAP, align = "start" }, tiles)
end

--- The update badge: a card's second reading, drawn before the state dot. It is
--- silent when there is nothing to say — no pending updates, or the check has not
--- answered yet — a warn-coloured count when there are, and a dim red glyph when
--- the check itself could not run (D27). "No updates" and "could not ask" are
--- different facts, and the panel must not draw them the same.
---
--- The count is the button that installs them: one target, so it is a button and
--- not a card-wide click (D26). The reason a failed check gives sits on the
--- glyph's tooltip, the same place a failed reading explains itself.
local function updatesBadge(view, card, record, size)
  local updates = record.updates
  if updates == nil then
    return nil
  end

  if updates.state == "warn" then
    local onUpgrade = nil
    if card.updates ~= nil and card.updates.run ~= nil then
      onUpgrade = function()
        view.dispatch("run", card.updates.run)
      end
    end
    return ui.button({
      text = "↑" .. updates.text,
      variant = "ghost",
      controlSize = "sm",
      tooltip = noctalia.tr("panel.updates"),
      onClick = onUpgrade,
    })
  end

  if updates.state == "down" then
    return ui.row({ tooltip = updates.error or noctalia.tr("panel.updates_failed"), align = "center" }, {
      ui.glyph({ name = "alert-triangle", size = size, color = "error/0.7" }),
    })
  end

  return nil
end

--- A `kind: link` card is a bookmark, not an instrument: one line, the glyph on
--- the left, the title beside it, and the description pushed to the trailing
--- edge. It draws no reading, no state dot and no buttons — the whole row is the
--- target, so a click opens `link:` in the browser (D26). This is the one kind
--- that takes no `source` and no collector record (config.luau).
local function renderLinkCard(view, card, index)
  local sizes = view.sizes
  local size = view.size(sizes.valueSize)
  -- Keyed by position, not by `card.id`: a duplicate id is a config error (and is
  -- reported as one), but two rows under one key make the second invisible on
  -- screen, which is the one place a config error must not be able to hide. A
  -- card with no id still has a position, so both problems draw.
  local key = "card:" .. tostring(index)
  local active = Visual.isHovered(key)
  local border, borderWidth = view.border(active)

  -- The title sits in the flexible column so the description, added after it,
  -- lands on the trailing edge instead of beside the title.
  local children = {
    leadingTile(size, card),
    ui.column({ flexGrow = 1 }, {
      ui.label({
        text = card.title or card.id or NO_VALUE,
        fontWeight = "bold",
        fontSize = size + TITLE_STEP,
        color = "on_surface",
        maxLines = ONE_LINE,
      }),
    }),
  }

  if type(card.description) == "string" and card.description ~= "" then
    children[#children + 1] = ui.label({
      text = card.description,
      fontSize = size,
      textAlign = "end",
      color = view.secondary,
      maxLines = ONE_LINE,
    })
  end

  local url = card.actions and card.actions.link or nil
  local onClick = nil
  if url ~= nil then
    onClick = function()
      view.dispatch("link", url)
    end
  end

  return Visual.cardShell({
    key = key,
    children = children,
    gap = sizes.cardPadH,
    paddingH = sizes.cardPadH,
    paddingV = sizes.cardPadV,
    radius = view.radius(),
    fill = view.fill(active),
    border = border,
    borderWidth = borderWidth,
    onClick = onClick,
  })
end

--- One card, drawn as the activity block of github-kanban (D25): a badge on the
--- left, a two-line column in the middle, and the reading plus its state marker on
--- the right.
---
---     ┌──┐  Title                  34%  ●  ⇱  ⌨
---     └──┘  Description
---
--- The badge is kanban's avatar slot: hub has no images, so it fills it with the
--- card's glyph on a tinted rounded square, which is exactly what kanban does for
--- the rows that have no avatar.
---
--- The second line is the description. A failure does not take its place: the
--- reason lives on the state marker's tooltip, so a red card still says what it
--- measures (docs/06-failure-modes.md). The reading stays on the trailing edge — a
--- column of numbers has to read as a scale — and the action buttons follow it.
---
--- `index` is the card's position in its zone, and it is what the row is keyed
--- by: a card missing its id is already a config error, but it still has to draw
--- without colliding with another card missing one.
function M.renderCard(view, card, record, index)
  -- A link is a row of its own shape, drawn before any reading is looked at.
  if card.kind == "link" then
    return renderLinkCard(view, card, index)
  end

  local sizes = view.sizes
  local size = view.size(sizes.valueSize)
  -- A card the collector has no record for: it failed validation before it could
  -- be given one. The shape has to be complete, because every field below is read
  -- unconditionally.
  record = record or { state = "pending", text = "", attempts = 0, rowCount = 0 }

  local key = "card:" .. tostring(index)
  local active = Visual.isHovered(key)
  local border, borderWidth = view.border(active)

  local state = record.state or "pending"
  local role = Visual.STATE_ROLES[state] or Visual.STATE_ROLES.pending
  local stateColor = role.color
  local value = (record.text ~= nil and record.text ~= "") and record.text or NO_VALUE

  local lines = {
    ui.label({
      text = card.title or card.id or NO_VALUE,
      fontWeight = "bold",
      fontSize = size + TITLE_STEP,
      color = "on_surface",
      maxLines = TITLE_MAX_LINES,
    }),
  }
  local second = cardSecondLine(view, card, record, size)
  if second ~= nil then
    lines[#lines + 1] = second
  end

  -- The reading and its state marker, then the card's buttons. Each button has
  -- its own target, so two of them is not the ambiguity the old one-action rule
  -- guarded against — a click on one cannot mean the other (D15, D26). Only
  -- `link` and `run` are drawn; `panel`, `deep_link` and `control` are still
  -- schema, not buttons.
  local marker = ui.glyph({ name = role.glyph, size = size, color = stateColor })
  local problem = cardProblem(card, record)
  if problem ~= nil then
    -- `ui.box` is a leaf — it takes no children — so the dot that must keep its
    -- own colour is wrapped in a row, which does take a tooltip (docs/05 UI
    -- primitives).
    marker = ui.row({ tooltip = problem, align = "center" }, { marker })
  end

  -- A status card says everything with its dot: the value column is not drawn for
  -- `kind: status` (D27). The dot's colour and its tooltip carry the state, and a
  -- word beside it was the same fact twice.
  local trailing = {}
  if card.kind ~= "status" then
    trailing[#trailing + 1] = ui.label({
      text = value,
      fontSize = size - VALUE_STEP,
      textAlign = "end",
      color = stateColor,
      maxLines = ONE_LINE,
    })
  end

  -- The mini cards sit between the reading and the update badge: a second row of
  -- facts about the same host, on the reading side of the card (D30).
  local minis = miniCardsRow(view, card, record, size, index)
  if minis ~= nil then
    trailing[#trailing + 1] = minis
  end

  -- The update count sits between the reading and the dot: it is a second reading
  -- about the same host, and it belongs on the reading side of the card (D27).
  -- Named for what it is, not `badge` — that word was already the tile's
  -- geometry, and one name for a number and a ui node is how the next reader
  -- breaks the arithmetic.
  local updatesNode = updatesBadge(view, card, record, size)
  if updatesNode ~= nil then
    trailing[#trailing + 1] = updatesNode
  end

  trailing[#trailing + 1] = marker

  if card.actions ~= nil then
    if card.actions.link ~= nil then
      trailing[#trailing + 1] = ui.button({
        glyph = "external-link",
        variant = "ghost",
        controlSize = "sm",
        tooltip = noctalia.tr("panel.action_link"),
        onClick = function()
          view.dispatch("link", card.actions.link)
        end,
      })
    end
    if card.actions.run ~= nil then
      trailing[#trailing + 1] = ui.button({
        glyph = "terminal-2",
        variant = "ghost",
        controlSize = "sm",
        tooltip = noctalia.tr("panel.action_terminal"),
        onClick = function()
          view.dispatch("run", card.actions.run)
        end,
      })
    end
  end

  local children = {
    leadingTile(size, card),
    ui.column({ flexGrow = 1, gap = TITLE_GAP }, lines),
  }
  for _, node in ipairs(trailing) do
    children[#children + 1] = node
  end

  return Visual.cardShell({
    key = key,
    children = children,
    gap = sizes.cardPadH,
    paddingH = sizes.cardPadH,
    paddingV = sizes.cardPadV,
    radius = view.radius(),
    fill = view.fill(active),
    border = border,
    borderWidth = borderWidth,
  })
end

return M
