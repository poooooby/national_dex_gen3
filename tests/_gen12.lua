-- Test helper for the Gen 1 / Gen 2 path (the "_" prefix keeps tests/tier_runner.lua from running it).
-- Builds a Red/Blue/Yellow or Gold/Silver/Crystal dataset headlessly from an imported cart under
-- <version>/data/generated, shaped the way the game hands it to mods:
--   Gen 1: every generated module under its own name, then Data.seedDefaults (as Data:load does);
--   Gen 2: the keys src/core/Game2.lua builds before mods load (pokemon, items, moves, type_chart,
--          gen2Pokedex, gen2Constants, ...).
-- H.load(version, extra) loads the mod (plus any extra mod paths) on that cart.
--
-- Suites run from the gen1recomp root: luajit mods/national_dex_gen3/tests/<name>_test.lua [version]

local H = {}

H.GENERATION = { red = 1, blue = 1, yellow = 1, gold = 2, silver = 2, crystal = 2 }
-- what a suite runs on when it is given no version: one cart of each layout
H.DEFAULT_VERSIONS = { "red", "yellow", "gold", "crystal" }

function H.modRoot()
  local script = ((arg and arg[0]) or ""):gsub("\\", "/")
  return script:match("^(.*)/tests/[^/]+$") or "mods/national_dex_gen3"
end

function H.module(name)
  local chunk = assert(loadfile(H.modRoot() .. "/" .. name))
  return chunk()
end

-- the versions a suite should run: the ones named on its command line, else the defaults
function H.versions()
  local out = {}
  for i = 1, #(arg or {}) do
    if H.GENERATION[arg[i]] then out[#out + 1] = arg[i] end
  end
  if #out == 0 then
    for _, v in ipairs(H.DEFAULT_VERSIONS) do out[#out + 1] = v end
  end
  return out
end

local function generated(version, name)
  local chunk = loadfile(version .. "/data/generated/" .. name .. ".lua")
  if not chunk then return nil end
  local ok, value = pcall(chunk)
  return ok and value or nil
end

local function listModules(version)
  local names = {}
  local pipe = io.popen('ls "' .. version .. '/data/generated"')
  for file in pipe:lines() do
    local name = file:match("^(.-)%.lua$")
    if name then names[#names + 1] = name end
  end
  pipe:close()
  return names
end

function H.gen1Data(version)
  local Data = require("src.core.Data")
  local data = {}
  for _, name in ipairs(listModules(version)) do data[name] = generated(version, name) end
  Data.seedDefaults(data, version)
  return data
end

local GEN2_KEYS = {
  pokemon = "pokemon", items = "items", moves = "moves", type_chart = "type_chart",
  audio = "audio", gen2Pokedex = "pokedex", gen2Constants = "constants",
  gen2Encounters = "encounters", gen2Maps = "maps", gen2Landmarks = "landmarks",
  gen2Marts = "marts", gen2Icons = "icons", gen2Trainers = "trainers",
  gen2BattleAnims = "battle_anims", gen2Text = "text",
}

function H.gen2Data(version)
  local data = {}
  for key, name in pairs(GEN2_KEYS) do data[key] = generated(version, name) end
  data.audio = data.audio or {}
  return data
end

function H.data(version)
  assert(H.GENERATION[version], "not a Gen 1/2 version: " .. tostring(version))
  require("src.core.GameVersion").set(version)
  if H.GENERATION[version] == 1 then return H.gen1Data(version) end
  return H.gen2Data(version)
end

-- Loads the mod on <version>; extra = more mod paths to load beside it (e.g. a stub national_dex).
-- Returns the sdk run (run.loader, run.data, run.mods, run.errors, run.release) and the mod's exports.
-- A battle simulator for the mechanics layer (src/gen12/mech/), the same calls on both games:
--   local sim = H.sim(version)            (loads the mod; sim.release() when done)
--   local w = sim.fresh({ mine = "SQUIRTLE", foe = "RATTATA", level = 40, roll = "low" | "high",
--     moves = { "TACKLE" } })
--   w.use("CLOSE_COMBAT")                 the player's mon uses it on the foe (w.use(id, "enemy"): back)
--   w.hp("enemy"), w.maxHp(side), w.stage(side, "spAtk"), w.status(side), w.types(side),
--   w.mon(side), w.battler(side), w.texts() (every line said so far), w.endTurn(), w.A (adapter)
-- "low" rolls make every accuracy and chance roll land; "high" ones make every chance fail.
function H.sim(version, extra)
  local run, api = H.load(version, extra)
  local gen = H.GENERATION[version]
  local data = run.data or (run.loader and run.loader.data)
  local mech = api and api._mech
  local sim = { gen = gen, run = run, data = data, mech = mech, version = version }
  function sim.release() run.release() end

  if gen == 1 then
    require("src.battle.TypeChart").load(data)
    pcall(require("src.render.Font").load, data)
    local Game = require("src.core.Game")
    Game.data = data
    Game.save = require("src.core.SaveData").newGame()
    local Pokemon = require("src.pokemon.Pokemon")
    local BattleState = require("src.battle.BattleState")
    function sim.fresh(o)
      o = o or {}
      Game.save.options.animations = false
      local mine = Pokemon.new(data, o.mine or "SQUIRTLE", o.level or 40)
      Game.save.party = { mine }
      for _, id in ipairs(o.party or {}) do Game.save.party[#Game.save.party + 1] = Pokemon.new(data, id, o.level or 40) end
      local tb = BattleState.newWild(Game, o.foe or "RATTATA", o.foeLevel or o.level or 40)
      tb.queue, tb.nextInsert = {}, 0
      if o.roll == "high" then tb.rng = function(_, b) return b end else tb.rng = function(a) return a end end
      local w = { battle = tb, gen = 1 }
      local function who(side) return side == "enemy" and tb.enemy or tb.player end
      function w.battler(side) return who(side) end
      function w.mon(side) return who(side).mon end
      function w.adapter() return mech and mech.adapter.adapter(tb, mech.deps) end
      w.A = w.adapter()
      function w.use(id, side)
        local user = who(side)
        local target = side == "enemy" and tb.player or tb.enemy
        return tb:performMove(user, target, { id = id, pp = 10 }, false)
      end
      function w.hp(side) return who(side).mon.hp end
      function w.maxHp(side) return who(side).mon.stats.hp end
      function w.stage(side, s) return w.A:stage(who(side), s) end
      function w.status(side) return w.A:status(who(side)) end
      function w.types(side) return w.A:types(who(side)) end
      function w.texts()
        local out = {}
        for _, item in ipairs(tb.queue) do if item.text then out[#out + 1] = item.text end end
        return out
      end
      function w.endTurn() tb:endOfTurn() end
      function w.nextTurn() tb.turnCount = (tb.turnCount or 0) + 1 end
      -- run the queued actions (Red swaps battlers and such from its queue)
      function w.flush()
        local i = 1
        while i <= #tb.queue do
          local item = tb.queue[i]
          if item.fn and not item.done then
            item.done = true
            tb.nextInsert = i
            item.fn()
          end
          i = i + 1
        end
      end
      if o.setup then o.setup(w) end
      return w
    end
    return sim
  end

  local Battle = require("src.battle.gen2.Battle")
  local Mon = require("src.battle.gen2.Mon")
  local ok0, text = pcall(require("tests.gen2_battle_text_fixture"))
  data.text = data.text or (ok0 and text) or nil
  require("src.mods.Runtime").emit("game.ready", { game = { data = data } })
  function sim.fresh(o)
    o = o or {}
    local player = Mon.new(data, o.mine or "TOTODILE", o.level or 40)
    local wild = Mon.new(data, o.foe or "RATTATA", o.foeLevel or o.level or 40)
    player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local random
    if o.roll == "high" then random = function(n) return (n or 1) - 1 end
    else
      -- low, but every fourth roll a little higher: Gold re-rolls some bytes until they are not
      -- zero (Tri Attack), which a constant could never satisfy
      local k = 0
      random = function(n)
        k = k + 1
        if (n or 1) <= 1 then return 0 end
        if k % 4 == 0 then return math.min(n - 1, 20) end
        return 1
      end
    end
    local party = { player }
    for _, id in ipairs(o.party or {}) do
      local m = Mon.new(data, id, o.level or 40)
      m.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
      party[#party + 1] = m
    end
    local b = Battle.new({ data = data, party = party, wild = wild,
      save = { player = { id = 7, badges = {}, kantoBadges = {} } }, random = random })
    local w = { battle = b, gen = 2 }
    local function who(side) return side == "enemy" and b.enemy or b.player end
    function w.battler(side) return who(side) end
    function w.mon(side) return who(side) end
    function w.adapter() return mech and mech.adapter.adapter(b, mech.deps) end
    w.A = w.adapter()
    function w.use(id, side)
      local user = who(side)
      local target = side == "enemy" and b.player or b.enemy
      return b:useMove(user, target, id)
    end
    function w.hp(side) return who(side).hp end
    function w.maxHp(side) return w.A:maxHp(who(side)) end
    function w.stage(side, s) return w.A:stage(who(side), s) end
    function w.status(side) return w.A:status(who(side)) end
    function w.types(side) return w.A:types(who(side)) end
    function w.texts()
      local out = {}
      for _, ev in ipairs(b.events or {}) do
        if ev.kind == "message" and ev.text then out[#out + 1] = ev.text end
      end
      return out
    end
    function w.endTurn()
      if b.betweenTurnEffects then b:betweenTurnEffects() end
      b:applyFieldResiduals()
    end
    function w.nextTurn() b.turn = (b.turn or 0) + 1 end
    function w.flush() end
    if o.setup then o.setup(w) end
    return w
  end
  return sim
end

function H.load(version, extra)
  local T = require("tests.modkit")
  local data = H.data(version)
  local paths = { H.modRoot() }
  for _, p in ipairs(extra or {}) do paths[#paths + 1] = p end
  local run = T.sdk.loadMods(paths, { data = data, generation = H.GENERATION[version] })
  return run, run.loader.exports.national_dex_gen3
end

return H
