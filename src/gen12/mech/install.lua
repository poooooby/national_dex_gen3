-- Registering the newer moves that run on the mechanics layer (src/gen12/mech/core.lua): every row
-- of data/gen12/moves.lua with no cart effect on this game (`gen1` / `gen2`) whose `mech` has a
-- mechanic becomes a real move here, on a move_effects record of its own ("NDX_M_<move>"), built
-- by this game's adapter (src/gen12/battle/red.lua / gold.lua). A row with no mechanic yet, and
-- the doubles-only moves, keep their stand-ins (src/gen12/moves.lua's resolver).
--
-- Registered before the species, so the learnsets name these moves. Each borrows the battle
-- animation of its `look` (a cart move; Red also takes that move's sound, kept on the record).

local Install = {}

Install.PREFIX = "NDX_M_"

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

-- opts: { mod, generation, rows (data/gen12/moves.lua), core (Core.new), adapter (Red / Gold),
-- types (src/gen12/types.lua), state (src/gen12/moves.lua's: byNumber gets these moves), require,
-- log }. Returns { registered, failed, looks = { id = look }, missing = { id } (no mechanic yet) }.
function Install.register(opts)
  local mod, gen, Types, core, Adapter = opts.mod, opts.generation, opts.types, opts.core, opts.adapter
  local key = "gen" .. gen
  local maxMove = gen == 1 and 165 or 251
  local content = mod.content
  local moves, effects, anims = content.moves, content.move_effects, content.battle_anims
  local deps = { require = opts.require, core = core, types = Types }
  local goldScripts, goldAdded = nil, {}
  if gen == 2 and anims then
    local ok, base = pcall(anims.get, anims, "moves")
    goldScripts = ok and type(base) == "table" and base or nil
  end
  local okE, Effects = false, nil
  if gen == 2 then okE, Effects = pcall(opts.require, "src.battle.gen2.Effects") end

  local result = { registered = 0, failed = 0, looks = {}, missing = {}, specs = {} }
  local firstError
  for _, row in ipairs(opts.rows or {}) do
    if row.n > maxMove and not row[key] and row.mech and not row.mech.doubles
        and not opts.state.byNumber[row.n] and moves:get(row.id) == nil then
      local spec = core:specFor(row)
      if not spec then
        result.missing[#result.missing + 1] = row.id
      else
        local look = row.look and row.look[key]
        local ok, err = pcall(function()
          local hit = spec.kind == "hit"
          local rec = { id = row.id, name = row.name, type = Types.cartId(row.type),
            power = hit and math.max(1, row.power or 0) or 0,
            accuracy = (row.accuracy or 0) > 0 and row.accuracy or 100, pp = row.pp }
          if (row.priority or 0) ~= 0 then rec.priority = row.priority end
          local effectId = Install.PREFIX .. row.id
          effects:register(effectId, Adapter.record(spec, deps))
          rec.effect = effectId
          if gen == 2 and (row.highCrit or spec.highCrit) then
            opts.state.highCrit[#opts.state.highCrit + 1] = row.id
          end
          if spec.charge then
            if gen == 1 then
              rec.chargeText = spec.charge.text
              if spec.charge.vanish then rec.semiInvulnerable = true end
            elseif okE and type(Effects.CHARGE) == "table" then
              Effects.CHARGE[effectId] = { text = spec.charge.text, vanish = spec.charge.vanish or nil }
            end
          end
          if gen == 1 then
            if row.highCrit or spec.highCrit then rec.highCrit = true end
            local like = look and moves:get(look)
            if like and like.anim then rec.anim = copy(like.anim) end
          else
            rec.index, rec.effectChance = row.n, 0
            if row.desc then rec.description = row.desc end
            -- past Gold's own Protect and Fly / Dig checks: what only touches the user, and what
            -- breaks through (Feint)
            if ((spec.kind == "status" and spec.selfOnly) or spec.ignoresProtect) and okE
                and type(Effects.NO_CHECKHIT) == "table" then
              Effects.NO_CHECKHIT[effectId] = true
            end
          end
          local okR, errR = pcall(moves.register, moves, row.id, rec)
          if not okR and gen == 2 then
            rec.index = nil
            okR, errR = pcall(moves.register, moves, row.id, rec)
          end
          if not okR then error(errR, 0) end
          if look then
            if gen == 1 and anims then
              local okA, seq = pcall(anims.get, anims, look)
              if okA and seq then pcall(anims.register, anims, row.id, copy(seq)) end
            elseif goldScripts and goldScripts[look] then
              goldAdded[row.id] = goldScripts[look]
            end
          end
        end)
        if ok then
          opts.state.byNumber[row.n] = row.id
          result.registered = result.registered + 1
          result.looks[row.id] = look
          result.specs[row.id] = spec
        else
          result.failed = result.failed + 1
          firstError = firstError or (row.id .. ": " .. tostring(err))
        end
      end
    end
  end
  if next(goldAdded) then pcall(anims.patch, anims, "moves", goldAdded) end
  core.liveSpecs = result.specs
  if firstError and opts.log then
    opts.log:warn("%d new move mechanics failed (first: %s); those moves use stand-ins", result.failed,
      firstError)
  end
  return result
end

return Install
