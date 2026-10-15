-- What the engine's battle animation player and the imported carts offer, for
-- tools/build_anims.py: one line per item, "<kind> <name>".
--   O <op>        an opcode the animation VM runs (src/core/game3/battle/anim_vm.lua)
--   K <task>      a visual or sound task it implements (AnimTasks.REGISTRY)
--   T <template>  a sprite template one of the imported carts' own scripts uses
--   G <tag>       a graphics tag an imported cart has
-- Run from the gen1recomp root: luajit mods/national_dex_gen3/tools/anim_known.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local CacheBlob = require("src.import.CacheBlob")

local out = {}
local function add(kind, name) out[kind .. " " .. tostring(name)] = true end

local f = assert(io.open("src/core/game3/battle/anim_vm.lua", "r"))
local src = f:read("*a")
f:close()
for name in src:gmatch("\nOPS%.([%w_]+)%s*=") do add("O", name) end
for name in src:gmatch("\nOPS%[\"([%w_]+)\"%]%s*=") do add("O", name) end

local AnimTasks = require("src.core.game3.battle.anim_tasks")
pcall(AnimTasks.init)
for name in pairs(AnimTasks.REGISTRY) do add("K", name) end

local REL = "data/generated/gba/pokemon/battle_anims/pack.lua"
for _, game in ipairs({ "firered", "leafgreen", "ruby", "sapphire", "emerald" }) do
  local fh = io.open(game .. "/" .. REL, "rb")
  if fh then
    local data = fh:read("*a")
    fh:close()
    local decoded = CacheBlob.decode(REL, data)
    local pack = type(decoded) == "string" and assert(loadstring(decoded))() or decoded
    local function scan(rows)
      if type(rows) ~= "table" then return end
      for _, r in ipairs(rows) do
        if type(r) == "table" and r.op == "createsprite" and r.template then add("T", r.template) end
      end
    end
    for _, k in ipairs({ "moves", "general", "special", "status", "labels" }) do
      for _, rows in pairs(pack[k] or {}) do scan(rows) end
    end
    for tag in pairs(pack.tags or {}) do add("G", tag) end
  end
end

local lines = {}
for k in pairs(out) do lines[#lines + 1] = k end
table.sort(lines)
io.write(table.concat(lines, "\n"), "\n")
