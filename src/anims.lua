-- Battle animations for the newer moves: data/anims.lua (tools/build_anims.py), based off RHH's
-- pokeemerald-expansion (https://github.com/rh-hideout/pokeemerald-expansion/). Its animation
-- scripts, as the rows the engine's animation player runs, built only from pieces the Gen 3 carts
-- already have.
--
-- One wrap of Anim.scriptForMove (src.core.game3.battle.anim) answers every new move: its own
-- script, resolved against the running cart the first time it is asked for, or else the cart
-- animation it borrows (`looks` here, else data/moves.lua's `look`). The engine's battle_anims
-- registry is not used: it takes one fixed `seq` per move at load, with no per-cart resolution,
-- no pack labels and no "borrow move X". Resolution:
--   * a sprite template takes the cart's own tag, palette, callback and size (from the cart's
--     scripts that use it), and the script starts by loading those graphics, as the cart's do
--   * a sound effect is the cart's number for its name ("SE_M_BARRIER"; "SE:" in task arguments)
--   * a graphics tag in a task argument is the cart's tag id ("TAG:MOON")
--   * a task must be one the engine implements; a call/goto target is stored in the pack's labels
--     under "national_dex_gen3:" + its name
-- If any piece is missing on this cart, that move keeps its `look` animation. A move without a
-- script of its own may name a closer cart animation in `looks` (picked by comparing expansion's
-- scripts), which replaces data/moves.lua's `look`.
local MoveAnims = {}

local PREFIX = "national_dex_gen3:"
local SPRITES_START = 10000

-- opts: { data (data/anims.lua), moves (src/moves.lua's registered rows), require, log }
function MoveAnims.install(opts)
  local require, log, data = opts.require, opts.log, opts.data or {}
  local okA, Anim = pcall(require, "src.core.game3.battle.anim")
  local okT, AnimTasks = pcall(require, "src.core.game3.battle.anim_tasks")
  if not (okA and okT and type(Anim) == "table" and type(Anim.scriptForMove) == "function") then
    if log then log:warn("new move animations are off: the engine's animation player was not found") end
    return false
  end
  if Anim.__nationalDexAnims then return true end
  Anim.__nationalDexAnims = true

  local idOf, lookOf = {}, {}
  for _, r in ipairs(opts.moves or {}) do
    if r.index and r.id and ((data.moves and data.moves[r.id]) or (data.looks and data.looks[r.id]) or r.look) then
      idOf[tonumber(r.index)] = r.id
      lookOf[r.id] = (data.looks and data.looks[r.id]) or r.look
    end
  end

  local scriptForMove = Anim.scriptForMove
  local cache, index = {}, nil
  local missing = {}

  -- what the cart's own scripts say about each template and tag
  local function indexPack(pack)
    local templates, tagIdx = {}, {}
    local function scan(rows)
      if type(rows) ~= "table" then return end
      for _, r in ipairs(rows) do
        if type(r) == "table" then
          if r.op == "createsprite" and r.template and not templates[r.template] then templates[r.template] = r end
          if r.op == "loadspritegfx" and r.tag and r.tag_idx then tagIdx[r.tag] = r.tag_idx end
        end
      end
    end
    for _, k in ipairs({ "moves", "general", "special", "status", "labels" }) do
      for _, rows in pairs(pack[k] or {}) do scan(rows) end
    end
    -- the running cart's sound numbers; the engine's selected table if the version is not a Gen 3 one
    local songs = {}
    local okS, SE = pcall(require, "src.core.game3.se_ids")
    local okV, GVer = pcall(require, "src.core.GameVersion")
    if okS and type(SE) == "table" then
      local okF, t = false, nil
      if okV and SE.forVersion then okF, t = pcall(SE.forVersion, GVer.current) end
      if okF and type(t) == "table" then
        songs = t
      else
        for k, v in pairs(SE) do
          if type(k) == "string" and k:find("^SE_") and type(v) == "number" then songs[k] = v end
        end
      end
    end
    return { pack = pack, templates = templates, tagIdx = tagIdx, songs = songs }
  end

  local function hasTask(name)
    AnimTasks.init()
    local key = tostring(name):gsub("^g", "")
    return AnimTasks.REGISTRY[name] or AnimTasks.REGISTRY[key] or AnimTasks.REGISTRY["AnimTask_" .. key]
  end

  -- one label's rows for this cart, or nil + what is missing
  local function resolveRows(rows, idx, tags)
    local out = {}
    local function arg(v)
      if type(v) ~= "string" then return v end
      local kind, name = v:match("^(%u+):(.+)$")
      if kind == "SE" and idx.songs[name] then return idx.songs[name] end
      if kind == "TAG" and idx.tagIdx[name] then return SPRITES_START + idx.tagIdx[name] end
      error(v, 0)
    end
    for _, r in ipairs(rows) do
      local row = {}
      for k, v in pairs(r) do row[k] = v end
      if row.args then
        local args = {}
        for i, v in ipairs(row.args) do args[i] = arg(v) end
        row.args = args
      end
      if row.se then row.se = idx.songs[row.se] or error(row.se, 0) end
      for _, k in ipairs({ "label", "label1", "label2" }) do
        if row[k] then row[k] = PREFIX .. row[k] end
      end
      if row.op == "createsprite" then
        local t = idx.templates[row.template] or error(row.template, 0)
        row.tag, row.palTag, row.callback, row.noGfx, row.w, row.h = t.tag, t.palTag, t.callback, t.noGfx, t.w, t.h
        if row.tag then tags[row.tag] = true end
        if row.palTag then tags[row.palTag] = true end
      elseif (row.op == "createvisualtask" or row.op == "createsoundtask") and not hasTask(row.task) then
        error(row.task, 0)
      end
      out[#out + 1] = row
    end
    return out
  end

  local function resolve(id)
    local pack = Anim._pack
    if type(pack) ~= "table" then return nil end
    if not index or index.pack ~= pack then index, cache = indexPack(pack), {} end
    if cache[id] ~= nil then return cache[id] or nil end
    local entry = data.moves[id]
    local labels, tags, todo = {}, {}, { entry }
    local ok, err = pcall(function()
      while #todo > 0 do
        local name = table.remove(todo)
        if not labels[name] then
          local rows = data.labels and data.labels[name] or error(name, 0)
          labels[name] = resolveRows(rows, index, tags)
          for _, r in ipairs(rows) do
            for _, k in ipairs({ "label", "label1", "label2" }) do
              if r[k] then todo[#todo + 1] = r[k] end
            end
          end
        end
      end
    end)
    if not ok then
      cache[id] = false
      missing[#missing + 1] = id .. " (" .. tostring(err) .. ")"
      return nil
    end
    -- load the graphics first, as the cart's own scripts do
    local load = {}
    local sorted = {}
    for tag in pairs(tags) do sorted[#sorted + 1] = tag end
    table.sort(sorted)
    for _, tag in ipairs(sorted) do
      if index.tagIdx[tag] then load[#load + 1] = { op = "loadspritegfx", tag = tag, tag_idx = index.tagIdx[tag] } end
    end
    local script = load
    for _, r in ipairs(labels[entry]) do script[#script + 1] = r end
    pack.labels = pack.labels or {}
    for name, rows in pairs(labels) do pack.labels[PREFIX .. name] = (name == entry) and script or rows end
    cache[id] = script
    return script
  end

  Anim.scriptForMove = function(moveId, ...)
    local num = tonumber(moveId)
    if not num and type(moveId) == "string" then
      local okM, Moves = pcall(require, "src.core.game3.battle.moves")
      num = okM and Moves.numForName and Moves.numForName(moveId) or nil
    end
    local id = num and idOf[num]
    if id then
      local look = lookOf[id]
      local fallback = scriptForMove(look or moveId, ...)  -- also loads the pack
      if data.moves[id] then
        local okR, script = pcall(resolve, id)
        if okR and script then return script end
      end
      return fallback
    end
    return scriptForMove(moveId, ...)
  end
  MoveAnims._resolve = resolve
  MoveAnims._missing = missing

  if log then
    local n = 0
    for _ in pairs(idOf) do n = n + 1 end
    local own = 0
    for _ in pairs(data.moves or {}) do own = own + 1 end
    log:info("new move animations: %d from %s, %d closer cart ones", own, tostring(data.source), n - own)
  end
  return true
end

return MoveAnims
