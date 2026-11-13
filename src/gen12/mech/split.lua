-- Physical / special by the move itself (option move_split, off by default), as in today's games:
-- data/gen12/battle.lua `split` has every damaging move's modern class by id. The adapters ask
-- core.moveCategory first (A:category), and the damage hooks put the stats a move's class reads
-- where each game's formula looks for them: Red reads a move's own `category`, Gold picks by type,
-- so the stats are swapped for the call.

return function(core, opts)
  local split = (core.facts and core.facts.split) or {}
  local function on()
    if not opts.option then return false end
    local ok, v = pcall(opts.option, "move_split")
    return ok and v == true
  end
  -- "physical" / "special" by the move, or nil (by its type, the game's way)
  function core.moveCategory(m)
    if not (m and on()) then return nil end
    local c = split[m.id]
    if c == "p" then return "physical" elseif c == "s" then return "special" end
    return nil
  end
end
