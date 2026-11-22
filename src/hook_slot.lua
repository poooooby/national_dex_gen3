-- A hook wrapped only while it has work to do. The engine's call into a wrapped hook makes garbage
-- on every call, whatever the wrap itself does (its argument packs and the chain's links; on Gen 3
-- the record views too: about 1 KB a frame a hook on Red / Gold, 3.5 KB on Emerald, measured by
-- tests/drivers/garbage_probe.lua). A hook that runs every frame (input.step, render.hud) is held
-- while it is needed and let go after, and nothing is called for it in between.
--
--   local s = Slot.new(mod, "render.hud", fn, priority)
--   s:on()    wraps it (once; again after off)
--   s:off()   unwraps it. From inside fn only once its next() has returned: the engine walks the
--             chain by position, so a link taken away before that would skip the one after it.
-- An engine whose wrap hands back no remover keeps the hook for good (as a plain wrap would).
local Slot = {}
Slot.__index = Slot

function Slot.new(mod, name, fn, priority)
  return setmetatable({ mod = mod, name = name, fn = fn, priority = priority, remove = nil }, Slot)
end

function Slot:on()
  if self.remove ~= nil then return true end
  local hooks = self.mod and self.mod.hooks
  if not (hooks and hooks.wrap) then return false end
  local ok, remove = pcall(hooks.wrap, hooks, self.name, self.fn, self.priority)
  if not ok then error(remove, 0) end
  self.remove = type(remove) == "function" and remove or false
  return true
end

function Slot:off()
  local remove = self.remove
  if not remove then return end   -- (nil: not wrapped; false: held for good)
  self.remove = nil
  pcall(remove)
end

function Slot:held() return self.remove ~= nil end

return Slot
