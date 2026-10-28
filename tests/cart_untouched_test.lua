-- Standalone: luajit mods/national_dex_gen3/tests/cart_untouched_test.lua [game]
-- (from the gen1recomp root; game defaults to firered and must be imported).
--
-- The cart's own species keep the data the ROM has: after this mod loads (registration, the
-- registry re-apply, game.ready), P.stats, P.speciesMeta and P.abilities of every cart species
-- equal the imported ROM tables exactly, extra keys included - the rule Event Distributions
-- applies before it hands out a gift ("Modified species data: delivery blocked."). Whatever this
-- mod changes for a cart species (Safari flee rates, Fairy typing, real abilities) must live
-- outside these tables.
package.path = "./?.lua;./?/init.lua;" .. package.path

local GAME = arg[1] or "firered"
local T = require("tests.modkit")
local H = dofile((arg[0]:gsub("\\", "/"):match("^(.*)/") or ".") .. "/_gen3.lua")

local root = GAME .. "/data/generated/gba/pokemon/"
local probe = io.open(root .. "stats.lua", "rb")
if not probe then print("skipped: " .. GAME .. " is not imported") os.exit(0) end
probe:close()

H.useCart(GAME)
local data = H.gen3Data(GAME)
local ItemsData = require("src.core.game3.items_data")
if ItemsData.ensureLoaded then ItemsData.ensureLoaded() end
data.gen3Items = ItemsData
local run = T.sdk.loadMods({ "mods/national_dex_gen3" }, { data = data, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
pcall(require("src.mods.Gen3Compat").applyMerged, { mods = run.loader, data = data })
run.loader.events:emit("game.ready", {})

local P = require("src.core.game3.pokemon")
local function rom(name) return dofile(root .. name .. ".lua") end
local stats, meta, abilities = rom("stats"), rom("meta"), rom("abilities")

-- Event Distributions' comparison: same type, same values, no key missing on either side
local function diff(a, b, path, out)
  if type(a) ~= type(b) then out[#out + 1] = path return end
  if type(a) ~= "table" then
    if a ~= b then out[#out + 1] = path end
    return
  end
  for k, v in pairs(a) do diff(v, b[k], path .. "." .. tostring(k), out) end
  for k in pairs(b) do if a[k] == nil then out[#out + 1] = path .. "." .. tostring(k) end end
end

local checked, changed, first = 0, 0, nil
for slot = 1, 411 do
  if stats[slot] then
    checked = checked + 1
    local out = {}
    diff(P.stats(slot), stats[slot], "stats", out)
    diff(P.speciesMeta(slot), meta[slot], "meta", out)
    diff(P.abilities(slot), abilities[slot], "abilities", out)
    if #out > 0 then
      changed = changed + 1
      first = first or (tostring(P.name and P.name(slot) or slot) .. ": " .. out[1])
    end
  end
end
T.check(checked > 380, GAME .. ": " .. checked .. " cart species compared")
T.eq(changed, 0, GAME .. ": no cart species' stats, meta or abilities differ from the ROM ("
  .. tostring(first) .. ")")

run.release()
T.finish("national_dex_gen3 cart untouched (" .. GAME .. ")")
