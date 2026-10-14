-- The FAIRY type icon on Ruby/Sapphire/Emerald's summary screen (src/types.lua adds the type).
--
-- Those summaries draw a type icon as frame N of the cart's move-type strip, from a local
-- function (Emerald's `drawTypeIcon`, Ruby/Sapphire's `typeIcon`). Frame 18 onwards are the
-- contest categories, drawn by the same function as `18 + category`, so a Fairy Pokemon or move
-- would show the COOL icon. A mod cannot wrap a local, so, as src/dex_patch.lua does for the
-- Pokedex, the engine file is read (CacheBlob.readFs), patched by exact text and run on the
-- LIVE module table:
--   * the contest call passes a flag saying it is a contest icon
--   * the icon function draws this mod's Fairy icon (assets/types/fairy_rse.png) for type 18
--     when that flag is not set
-- Any mismatch leaves the stock screen (a Fairy icon then shows as COOL), with a warning.
-- FireRed/LeafGreen draw through exported functions; src/types.lua handles those.

local TypeIcons = {}

local SCREENS = {
  rse = {
    path = "src/ui/game3/rse/summary_menu.lua",
    module = "src.ui.game3.rse.summary_menu",
    edits = {
      { "local RseSummary = {}", 'local RseSummary = require("src.ui.game3.rse.summary_menu")' },
      { "local function drawTypeIcon(m, typeId, x, y)\n  drawFrame(m.moveTypes, typeId, x, y)",
        "local function drawTypeIcon(m, typeId, x, y, contest)\n"
          .. "  if not contest and tonumber(typeId) == 18 and __nationalDexFairyIcon then return __nationalDexFairyIcon(x, y) end\n"
          .. "  drawFrame(m.moveTypes, typeId, x, y)" },
      { "drawTypeIcon(m, 18 + (cm and cm.category or 0), 85, 32 + (i - 1) * 16)",
        "drawTypeIcon(m, 18 + (cm and cm.category or 0), 85, 32 + (i - 1) * 16, true)" },
    },
  },
  rs = {
    path = "src/ui/game3/rs/summary_menu.lua",
    module = "src.ui.game3.rs.summary_menu",
    edits = {
      { "local S = {isMenu = true, open = false, PAGE = Policy.PAGE, MODE = Policy.MODE, policy = Policy}",
        'local S = require("src.ui.game3.rs.summary_menu"); S.isMenu, S.PAGE, S.MODE, S.policy = true, Policy.PAGE, Policy.MODE, Policy' },
      { "local function typeIcon(index, x, y)\n  index = tonumber(index) or require(\"src.core.game3.battle.types\").ID[index]",
        "local function typeIcon(index, x, y, contest)\n  index = tonumber(index) or require(\"src.core.game3.battle.types\").ID[index]\n"
          .. "  if not contest and index == 18 and __nationalDexFairyIcon then return __nationalDexFairyIcon(x, y) end" },
      { "typeIcon(contestPage and c.category + 18 or def.type, 87, y)",
        "typeIcon(contestPage and c.category + 18 or def.type, 87, y, contestPage)" },
    },
  },
}
TypeIcons.SCREENS = SCREENS

-- Plain-text replace, each edit exactly once. Returns the patched source or nil.
function TypeIcons.patch(source, which)
  local screen = SCREENS[which]
  if type(source) ~= "string" or not screen then return nil end
  local out = source:gsub("\r\n", "\n")
  for _, e in ipairs(screen.edits) do
    local i, j = out:find(e[1], 1, true)
    if not i or out:find(e[1], j + 1, true) then return nil end
    out = out:sub(1, i - 1) .. e[2] .. out:sub(j + 1)
  end
  return out
end

-- opts: { which = "rse"|"rs", read, load, require, log, env, icon = Image }
function TypeIcons.install(opts)
  local which, log = opts.which, opts.log
  local screen = SCREENS[which]
  local function fail(why)
    if log and log.warn then log:warn("the summary shows Fairy with the COOL icon (%s)", why) end
    return false, why
  end
  if not screen then return fail("no such screen") end
  local require = opts.require
  local okM, live = pcall(require, screen.module)
  if not (okM and type(live) == "table") then return fail("module unavailable") end
  if live.__nationalDexFairyIcons then return true end
  local okR, source = pcall(opts.read, screen.path)
  if not (okR and type(source) == "string") then return fail("engine source not readable") end
  local patched = TypeIcons.patch(source, which)
  if not patched then return fail("engine source is not the expected one") end
  local env = opts.env or _G
  local icon = opts.icon
  env.__nationalDexFairyIcon = function(x, y)
    if not (icon and love and love.graphics) then return end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(icon, x, y)
  end
  local chunk, err = (opts.load or load)(patched, "@" .. screen.path)
  if not chunk then return fail("compile: " .. tostring(err)) end
  local okC, result = pcall(chunk)
  if not (okC and result == live) then return fail("run: " .. tostring(result)) end
  live.__nationalDexFairyIcons = true
  if log and log.info then log:info("the summary draws a FAIRY type icon") end
  return true
end

return TypeIcons
