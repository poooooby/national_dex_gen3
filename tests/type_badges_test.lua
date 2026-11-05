-- Standalone: luajit mods/national_dex_gen3/tests/type_badges_test.lua [game] (from the gen1recomp
-- root; needs that cart imported, FireRed by default).
--
-- The type badges beside the battle's HP boxes (src/type_badges.lua): drawn after the engine's own
-- Healthbox.draw, beside the box it placed (right of a foe's, left of the player's), following the
-- slide-in, not drawn for a hidden box or with the option off, one per current type.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")
local GAME = arg[1] or "firered"

local data = H.gen3Data(GAME)
-- the box pictures are read through the dataset cache, as a game reads them
do
  local CacheBlob = require("src.import.CacheBlob")
  require("src.core.game3.dataset").cache = function()
    return {
      read = function(_, rel)
        local f = io.open(GAME .. "/" .. rel, "rb")
        if not f then return nil end
        local bytes = f:read("*a")
        f:close()
        return CacheBlob.decode(rel, bytes)
      end,
      exists = function() return false end,
    }
  end
end
require("src.core.GameVersion").set(GAME)

-- the engine's Healthbox.draw needs a window; this stand-in places the boxes as it does (the box's top
-- left from its centre, the slide-in ox, a hidden box skipped) and hands them to BattleChrome
local Healthbox = require("src.core.game3.battle.healthbox")
local Chrome = require("src.ui.game3.battle_chrome")
local hidden = {}
-- (headless, the engine's doubles box would try to inflate its picture without zlib)
Chrome.drawDoublesBox = function() end
Healthbox.draw = function(side, battler, opts)
  if not battler then return end
  local ox = opts and opts.ox or 0
  if type(side) == "number" then
    local c = Healthbox.CENTERS[true][side]
    return Chrome.drawDoublesBox(side % 2 == 0, c.x - 32 + ox, c.y - 16)
  end
  if hidden[side] then return end
  local c = side == "player" and Healthbox.PLAYER_CENTER or Healthbox.ENEMY_CENTER
  if side == "player" then Chrome.drawPlayerBox(c.x - 32 + ox, c.y - 16) else Chrome.drawEnemyBox(c.x - 32 + ox, c.y - 16) end
end

local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})

local state = Healthbox.__ndxBadges
T.check(type(state) == "table" and type(state.drawBadge) == "function", "the badges are installed on the HP boxes")
local drawn = {}
state.drawBadge = function(t, x, y) drawn[#drawn + 1] = { t = t, x = x, y = y } end
local function draw(side, battler, opts)
  drawn = {}
  Healthbox.draw(side, battler, opts)
  return drawn
end

local W, F, N, FAIRY = 11, 2, 0, 18
local foe = draw("enemy", { type1 = F, type2 = N })
T.eq(#foe, 2, "a Flying / Normal foe has two badges")
T.check(foe[1] and foe[1].t == F and foe[2].t == N, "Flying first, Normal behind it")
local ex = Healthbox.ENEMY_CENTER.x - 32
T.check(foe[1] and foe[1].x > ex + 60, ("the foe's badges sit right of its box (x %s, box at %d)"):format(foe[1] and foe[1].x, ex))
T.check(foe[1] and foe[2].x > foe[1].x and foe[2].y > foe[1].y, "the second one down and to the right")
T.check(foe[1] and foe[1].y + 12 <= 66, "within the foe box's rows (above WoobleView's split at 66)")

local mine = draw("player", { type1 = W, type2 = W })
T.eq(#mine, 1, "a Water / Water Pokemon (or one soaked) has one badge")
local px = Healthbox.PLAYER_CENTER.x - 32
T.check(mine[1] and mine[1].x + 12 <= px + 16, ("the player's badge sits left of its box (x %s, box at %d)"):format(mine[1] and mine[1].x, px))
T.check(mine[1] and mine[1].y >= 66, "within the player box's rows (below the split)")
-- the same clear gap on both sides, from each box's frame (a foe's ends at x 92, the player's starts at 9)
local Edges = dofile("mods/national_dex_gen3/src/type_badges.lua").EDGES
local foeGap = foe[1].x - (ex + Edges.enemy.right + 1)
local myGap = (px + Edges.player.left) - (mine[1].x + 12)
T.check(foeGap == 2 and myGap == 2, ("both sides keep 2 px from their box (foe %d, player %d)"):format(foeGap, myGap))
print(("%s: foe badge at %d,%d; player badge at %d,%d"):format(GAME, foe[1].x, foe[1].y, mine[1].x, mine[1].y))

local slid = draw("enemy", { type1 = F }, { ox = -40 })
T.eq(slid[1] and slid[1].x, foe[1].x - 40, "a box sliding in brings its badge along")
hidden.enemy = true
T.eq(#draw("enemy", { type1 = F }), 0, "a hidden box shows no badges")
hidden.enemy = nil

local three = draw("enemy", { type1 = 12, type2 = 3, __ndxType3 = 6 })
T.eq(#three, 3, "Forest's Curse adds a third badge")
T.eq(three[3] and three[3].t, 6, "and it is Bug")
T.eq(draw("enemy", { type1 = FAIRY })[1].t, FAIRY, "a Fairy badge is drawn")
local mystery = draw("enemy", { type1 = 9, type2 = 10 })
T.check(#mystery == 1 and mystery[1].t == 10, "the ??? type is left out beside another")
T.eq(#draw("enemy", { type1 = "WATER" }), 1, "a type given by name resolves")

-- doubles: one per box, foes right, the player's left
for id = 0, 3 do
  local b = draw(id, { type1 = W })
  local c = Healthbox.CENTERS[true][id]
  local ok = b[1] and (id % 2 == 1 and b[1].x > c.x or id % 2 == 0 and b[1].x < c.x - 32)
  T.check(ok, ("doubles box %d's badge is on its outer side (x %s, centre %d)"):format(id, b[1] and b[1].x, c.x))
end

-- the option
run.loader.modOptions.national_dex_gen3 = { type_badges = false }
local okGet, value = pcall(function() return run.loader.modOptions.national_dex_gen3.type_badges end)
T.check(okGet and value == false, "the option is set")
local saved = state.enabled
state.enabled = function() return false end
T.eq(#draw("enemy", { type1 = F }), 0, "Type Badges off: none")
state.enabled = saved

-- every type has art
local Badges = dofile("mods/national_dex_gen3/src/type_badges.lua")
local missing = {}
for t = 0, 18 do
  local g = Badges.GLYPHS[t]
  if not (Badges.COLORS[t] and g and #g == 8) then missing[#missing + 1] = t end
  for _, row in ipairs(g or {}) do if #row ~= 8 then missing[#missing + 1] = t end end
end
T.eq(#missing, 0, "every type has a colour and an 8 x 8 symbol (" .. table.concat(missing, ", ") .. ")")
-- each symbol centred in its badge: as much space left as right, above as below
local offCentre = {}
for t = 0, 18 do
  local g = Badges.GLYPHS[t] or {}
  local x0, x1, y0, y1 = 9, -1, 9, -1
  for y, row in ipairs(g) do
    for x = 1, #row do
      if row:sub(x, x) == "#" then
        x0, x1, y0, y1 = math.min(x0, x), math.max(x1, x), math.min(y0, y), math.max(y1, y)
      end
    end
  end
  if x0 - 1 ~= 8 - x1 or y0 - 1 ~= 8 - y1 then offCentre[#offCentre + 1] = t end
end
T.eq(#offCentre, 0, "every symbol is centred (" .. table.concat(offCentre, ", ") .. ")")
local schema = run.loader.optionSchemas.national_dex_gen3
local opt
for _, o in ipairs(schema or {}) do if o.key == "type_badges" then opt = o end end
T.check(opt and opt.default == true and #opt.label <= 14, "a Type Badges option, on by default")

run.release()
T.finish("national_dex_gen3 type badges (" .. GAME .. ")")
