-- Standalone: luajit mods/national_dex_gen3/tests/editor_sprite_box_test.lua (from the
-- gen1recomp root; needs tools/save-editor).
--
-- The save editor fits a species' picture into a small slot. A sprite mod's picture keeps
-- the game's true size, so a small creature sits in a mostly empty canvas and came out a
-- speck: MonEditor.drawSprite now fits the creature itself (its opaque pixels), not the
-- whole canvas. The canvas here reports 64x64 and holds 256x256 pixels, as a DPI-scaled
-- one does.
package.path = "./?.lua;./?/init.lua;./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua;"
  .. package.path
local ok = pcall(require, "MonEditor")
if not ok then print("skipped: the save editor is not in this checkout") os.exit(0) end

local T = require("tests.modkit")
love = love or require("tests.love_stub")
local draws = {}
love.graphics.draw = function(...) draws[#draws + 1] = { ... } end
love.graphics.setColor = function() end
local ME = require("MonEditor")

local function canvas(x0, y0, x1, y1)
  return {
    getDimensions = function() return 64, 64 end,
    newImageData = function()
      return {
        getDimensions = function() return 256, 256 end,
        getPixel = function(_, px, py)
          return 1, 1, 1, (px >= x0 and px <= x1 and py >= y0 and py <= y1) and 1 or 0
        end,
      }
    end,
  }
end

local function draw(img, size)
  draws = {}
  ME.sprite = function() return img end
  ME.drawSprite({}, { scale = 1 }, "X", 10, 20, size)
  local d = draws[1]
  return d, d[5]
end

-- a tall creature fills the slot's height and is centred across it
local d, scale = draw(canvas(100, 120, 139, 255), 36)
local left, right = d[2] + (100 / 4) * scale, d[2] + (140 / 4) * scale
local top, bottom = d[3] + (120 / 4) * scale, d[3] + (256 / 4) * scale
T.check(math.abs(top - 20) < 0.01 and math.abs(bottom - 56) < 0.01, "a tall creature fills the slot's height")
T.check(math.abs((left + right) / 2 - 28) < 0.01, "and is centred in it")
T.check(left >= 10 and right <= 46, "inside the slot")

-- a small creature is scaled UP to the slot, not left a speck in the corner of its canvas
local _, small = draw(canvas(120, 200, 135, 215), 36)       -- 16x16 px = 4x4 shown
T.check(small > 8, "a small creature is enlarged to fill the slot (scale " .. small .. ")")

-- an empty picture, or one that cannot be read back, is drawn whole as before
local empty = canvas(1000, 1000, 1001, 1001)
local de, se = draw(empty, 36)
T.check(math.abs(se - 36 / 64) < 1e-9, "an empty canvas falls back to fitting the whole picture")
local image = { getDimensions = function() return 64, 64 end }  -- no newImageData
local dp, sp = draw(image, 36)
T.check(math.abs(sp - 36 / 64) < 1e-9 and dp[2] == 10, "a plain Image is fitted whole")

T.finish("national_dex_gen3 editor sprite box")
