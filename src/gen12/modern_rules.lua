-- Modern Rules on Red / Blue / Yellow (option `modern_rules`, on by default): battles drop the
-- Gen 1 bugs and use today's critical hits.
--
--   * a ruleset of ours (`national_dex_gen3_modern`, hidden from the game's own Options list) is
--     registered at load: the engine's modern_clean switches (no 1/256 miss, no Focus Energy bug,
--     Hyper Beam always recharges, AI PP, the HP / Substitute / stat-cap bugs fixed) plus stages
--     kept on a critical hit, badge boosts applied once, and poison / burn / Leech Seed at the end
--     of the round. While the option is on, battle.started puts it on the battle (the save's own
--     ruleset choice is left as it is, and comes back when the option is off).
--   * critical hits: 1 in 24, 1 in 8 for a high-critical move, 1 in 2 with Focus Energy as well,
--     always at +3 stages; x1.5 damage, screens ignored (a battle.damage wrap rolls it, runs the
--     game's formula without its own critical hit and scales the result). The mechanics layer's
--     "noCrit" / "forceCrit" answers (Lucky Chant, Battle Armor, Scope Lens ...) still decide
--     first.

local ModernRules = {}

ModernRules.ID = "national_dex_gen3_modern"
ModernRules.RULESET = {
  name = "WoobleDex modern", hidden = true,
  statCapRollbackBug = false, oneIn256Miss = false, critUsesBaseSpeed = true, critIgnoresStages = false,
  randMin = 217, randMax = 255, focusEnergyBug = false, enemyUnlimitedPP = false,
  hyperBeamSkipRechargeOnKO = false, residualAfterMove = false, badgeBoostReapplyBug = false,
  zeroDamageMiss = false, statusPenaltyIsBaked = false, healHpLowByteBug = false,
  toxicFlagSurvivesCure = false, substituteZeroHpBug = false,
}
-- one in n, by stage (0, +1, +2, +3 and up)
ModernRules.CRIT_ODDS = { 24, 8, 2, 1 }

function ModernRules.critStage(battler, move)
  local stage = 0
  if move and move.highCrit then stage = stage + 1 end
  if battler and battler.focusEnergy then stage = stage + 2 end
  return stage
end

-- opts: { mod, require, option = fn(key) -> value, mech = fn() -> { core, adapter, deps } | nil }
function ModernRules.install(opts)
  local mod = opts.mod
  local function on()
    local ok, v = pcall(opts.option, "modern_rules")
    return not ok or v ~= false
  end
  if mod.content and mod.content.rulesets then
    local ok, err = pcall(function()
      if mod.content.rulesets:get(ModernRules.ID) == nil then
        mod.content.rulesets:register(ModernRules.ID, ModernRules.RULESET)
      end
    end)
    if not ok and mod.log then mod.log:warn("modern rules: no ruleset: %s", tostring(err)) end
  end

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle then return end
    local rulesets = battle.data and battle.data.rulesets
    local ours = rulesets and rulesets[ModernRules.ID]
    if on() and ours then
      battle.__ndxSavedRuleset = battle.__ndxSavedRuleset or battle.ruleset
      battle.ruleset = ours
    end
  end)

  mod.hooks:wrap("battle.damage", function(nextFn, c)
    if not (c and c.battle and c.move and on()) then return nextFn(c) end
    local o = c.opts
    if (c.move.power or 0) == 0 or (o and (o.forceCrit == false or o.typeless)) then return nextFn(c) end
    local crit = o and o.forceCrit == true or nil         -- an always-critical move
    local mech = crit == nil and opts.mech and opts.mech()
    local A = mech and mech.adapter and mech.adapter.adapter and mech.adapter.adapter(c.battle, mech.deps)
    local core = mech and mech.core
    if core and A then
      if core.hooks.noCrit and core:ask("noCrit", A, c.user, c.target) then crit = false
      elseif core.hooks.forceCrit and core:ask("forceCrit", A, c.user) then crit = true end
    end
    if crit == nil then
      local odds = ModernRules.CRIT_ODDS[math.min(4, ModernRules.critStage(c.user, c.move) + 1)]
      local rng = (o and o.rng) or c.rng or love.math.random
      crit = odds <= 1 or rng(1, odds) == 1
    end
    local copy = {}
    for k, v in pairs(o or {}) do copy[k] = v end
    copy.forceCrit = false
    if crit then copy.screens = false end
    c.opts = copy
    local dmg, info = nextFn(c)
    c.opts = o
    if crit and type(dmg) == "number" and dmg > 0 then
      dmg = math.max(1, math.floor(dmg * 3 / 2))
      if type(info) == "table" then info.crit = true end
    end
    return dmg, info
  end)
end

return ModernRules
