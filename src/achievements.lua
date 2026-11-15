-- WoobleDex's achievements in the Recomp Achievements mod (its provider API 1.x): completing the
-- National Dex, each generation, the starters, the Legendaries, the regional variants and more
-- (data/achievements.lua). Every one is a progress achievement counted from the Pokedex itself,
-- so a catch, an evolution, a hatch or a trade counts once the game marks the Pokemon caught, and
-- a save from before this existed is credited the first time it loads. Nothing of ours is saved:
-- the achievements mod keeps the records. Without that mod installed, nothing happens.
--
-- Shared by every game. The caller hands over a reader: `reader()` -> nil (no save yet) or
--   { caught(nat) -> bool, seen(nat) -> bool, formCaught(formId) -> bool }
-- (Gen 3: the session's Pokedex by species slot; Red / Gold: save.pokedex by species id).

local Achievements = {}

Achievements.NATIONAL_MAX = 1025
Achievements.UNIT = "POKEMON"

local function regionOf(form)
  if type(form) ~= "string" then return nil end
  for _, region in ipairs({ "ALOLA", "GALAR", "HISUI", "PALDEA" }) do
    if form == region or form:sub(1, #region + 1) == region .. "_" then return region end
  end
  return nil
end

-- data: data/achievements.lua. species: { { dex, legendary, mythical } } (the newer species: the
-- cart's 386 come from data.groups). forms: { { id, form, baseSpecies, baseDex } }.
-- Returns { { def = <registration>, nationals = { n, ... }, forms = { id, ... }, seen, goal } }.
function Achievements.build(data, species, forms)
  local groups = data.groups or {}
  local flagged = { legendary = {}, mythical = {} }
  for flag, set in pairs(flagged) do
    for _, n in ipairs(groups[flag] or {}) do set[n] = true end
  end
  for _, r in ipairs(species or {}) do
    local n = tonumber(r.dex)
    if n and n <= Achievements.NATIONAL_MAX then
      if r.legendary then flagged.legendary[n] = true end
      if r.mythical then flagged.mythical[n] = true end
    end
  end
  local baseDexOf = {}
  for _, f in ipairs(forms or {}) do
    if f.baseSpecies and f.baseDex then baseDexOf[f.baseSpecies] = tonumber(f.baseDex) end
  end

  local out = {}
  for _, e in ipairs(data.list or {}) do
    local nats, ids, seenN = {}, {}, {}
    local function add(n)
      n = tonumber(n)
      if n and n >= 1 and n <= Achievements.NATIONAL_MAX and not seenN[n] then
        seenN[n] = true
        nats[#nats + 1] = n
      end
    end
    if e.range then for n = e.range[1], e.range[2] do add(n) end end
    if type(e.dex) == "string" then for _, n in ipairs(groups[e.dex] or {}) do add(n) end end
    if type(e.dex) == "table" then for _, n in ipairs(e.dex) do add(n) end end
    if e.flag and flagged[e.flag] then
      local list = {}
      for n in pairs(flagged[e.flag]) do list[#list + 1] = n end
      table.sort(list)
      for _, n in ipairs(list) do add(n) end
    end
    if e.family then add(baseDexOf[e.family]) end
    for _, f in ipairs(forms or {}) do
      local take = false
      if e.forms == "all" then take = true
      elseif e.forms == "regional" then
        local region = regionOf(f.form)
        take = region ~= nil and (e.region == nil or e.region == region)
      end
      if e.family and f.baseSpecies == e.family then take = true end
      if take and f.id then ids[#ids + 1] = f.id end
    end
    local total = #nats + #ids
    if total > 0 then
      local goal = math.min(tonumber(e.goal) or total, total)
      out[#out + 1] = {
        def = { id = e.id, title = e.title, description = e.description, points = e.points,
          category = e.category, goal = goal, unit = Achievements.UNIT, hidden = false },
        nationals = nats, forms = ids, seen = e.seen == true, goal = goal,
      }
    end
  end
  return out
end

-- How many of `a`'s Pokemon the reader has. caughtN / seenN: memo tables for one refresh.
function Achievements.count(a, reader, memo)
  memo = memo or { caught = {}, seen = {}, form = {} }
  local function ask(cache, fn, key)
    local v = cache[key]
    if v == nil then
      local ok, yes = pcall(fn, key)
      v = ok and yes and true or false
      cache[key] = v
    end
    return v
  end
  local n = 0
  for _, nat in ipairs(a.nationals) do
    if a.seen then
      if ask(memo.seen, reader.seen, nat) then n = n + 1 end
    elseif ask(memo.caught, reader.caught, nat) then
      n = n + 1
    end
  end
  for _, id in ipairs(a.forms) do
    if ask(memo.form, reader.formCaught, id) then n = n + 1 end
  end
  return n
end

-- opts: { data, species, forms, reader = fn() -> reader | nil, log }. Returns the state, or nil
-- when the achievements mod is not installed (or speaks another major version).
function Achievements.install(mod, opts)
  local found = type(mod.find) == "function" and mod.find("recomp_achievements") or nil
  local ach = type(found) == "table" and found.exports or nil
  if type(ach) ~= "table" or type(ach.connect) ~= "function" then return nil end
  local major = tonumber(tostring(ach.apiVersion):match("^(%d+)"))
  if major ~= 1 then
    if opts.log then opts.log:info("achievements: Recomp Achievements API %s is not 1.x; skipped", tostring(ach.apiVersion)) end
    return nil
  end
  local okC, handle = pcall(ach.connect, mod)
  if not (okC and type(handle) == "table") then
    if opts.log then opts.log:warn("achievements: could not connect (%s)", tostring(handle)) end
    return nil
  end

  local list = Achievements.build(opts.data, opts.species, opts.forms)
  local state = { list = {}, last = {}, handle = handle }
  local failed, firstError = 0, nil
  for _, a in ipairs(list) do
    local ok, err, msg = handle:register(a.def)
    if ok or err == "duplicate_id" then
      state.list[#state.list + 1] = a
    else
      failed = failed + 1
      firstError = firstError or (a.def.id .. ": " .. tostring(msg or err))
    end
  end
  if failed > 0 and opts.log then
    opts.log:warn("achievements: %d could not be registered (first: %s)", failed, firstError)
  end

  -- progress for every achievement, written only where it changed since the last refresh
  function state.refresh()
    local okR, reader = pcall(opts.reader)
    if not (okR and type(reader) == "table") then return 0 end
    local memo, wrote = { caught = {}, seen = {}, form = {} }, 0
    for _, a in ipairs(state.list) do
      local id = a.def.id
      local n = Achievements.count(a, reader, memo)
      if state.last[id] ~= n then
        local ok, code = handle:setProgress(id, n)
        if ok or code == "already_unlocked" then
          state.last[id] = n
          wrote = wrote + 1
        elseif code == "no_save" then
          state.last = {}
          return wrote
        end
      end
    end
    return wrote
  end
  -- another save: everything is written again once it is attached
  function state.reset() state.last = {} end

  local function refresh() pcall(state.refresh) end
  local events = ach.events or {}
  if events.ready then
    mod.events:on(events.ready, function() state.reset(); refresh() end)
  end
  mod.events:on("save.loaded", function() state.reset(); refresh() end)
  for _, name in ipairs({ "pokemon.caught", "pokemon.evolved", "pokemon.received", "trade.completed",
      "battle.ended", "map.entered", "screen.popped" }) do
    mod.events:on(name, refresh)
  end
  if opts.log then opts.log:info("achievements: %d", #state.list) end
  return state
end

return Achievements
