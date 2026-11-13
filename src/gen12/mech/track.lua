-- What the newer moves need to know that neither game keeps, gathered from the battle events
-- (Core:listen) onto the battle's own tables:
--   A:field().turn, .chosen = { player, enemy }   the turn and the move each side chose
--     (Sucker Punch)
--   A:field().moved = { side = turn }             who has acted this turn (Payback, Bolt Beak)
--   A:vol(b).tookThisTurn, .lastTaken, .lastTakenKind, .tookFrom
--                                                 the damage it took this turn and from whom
--                                                 (Assurance, Revenge, Focus Punch, Metal Burst)
--   A:vol(b).acted, .used, .lastMove, .prevMove, .lastFailed
--                                                 its moves since it came in (Fake Out, Last
--                                                 Resort, Gigaton Hammer, Stomping Tantrum)
--   A:field().hits[mon]                           times each Pokemon was hit this battle (Rage Fist)
--   A:field().faints[side], .faintTurn[side]      faints on each side (Last Respects, Retaliate)
--   A:field().echo, .fusion                        Echoed Voice's chain, the last Fusion move

return function(core)
  local function hitsTable(f)
    local h = f.hits
    if not h then h = setmetatable({}, { __mode = "k" }); f.hits = h end
    return h
  end

  core:on("turnStarted", function(A, ev)
    local f = A:field()
    f.turn = ev.turn or A:turn()
    local pa, ea = ev.playerAction, ev.enemyAction
    f.chosen = { player = pa and (pa.id or pa.move) or nil, enemy = ea and (ea.id or ea.move) or nil }
    f.moved = {}
    local p, e = A:battlers()
    for _, b in ipairs({ p, e }) do
      if b then
        local v = A:vol(b)
        v.tookThisTurn, v.lastTaken, v.lastTakenKind, v.tookFrom = 0, nil, nil, nil
      end
    end
  end)

  core:on("moveUsed", function(A, ev)
    local u = ev.user
    if not u then return end
    local id = ev.moveId or (ev.move and ev.move.id)
    local f = A:field()
    f.moved = f.moved or {}
    f.moved[A:sideName(u)] = A:turn()
    if ev.isCalled then return end
    local v = A:vol(u)
    v.prevMove, v.lastMove = v.lastMove, id
    v.used = v.used or {}
    v.used[id] = true
    v.acted = (v.acted or 0) + 1
    -- a damaging move that dealt nothing failed (Stomping Tantrum); cleared by its damage
    v.lastFailed = v.pendingFail
    v.pendingFail = (ev.move and (ev.move.power or 0) > 0) or nil
    local turn = A:turn()
    if id == "ECHOED_VOICE" then
      local e = f.echo
      if e and e.turn == turn then
        -- used twice in one turn: same count
      elseif e and e.turn == turn - 1 then
        e.count, e.turn = math.min(5, e.count + 1), turn
      else
        f.echo = { count = 1, turn = turn }
      end
    end
    if id == "FUSION_FLARE" or id == "FUSION_BOLT" then
      f.fusionBefore = f.fusion
      f.fusion = { turn = turn, id = id }
    end
  end)

  core:on("damageDealt", function(A, ev)
    local t, u, n = ev.target, ev.user, tonumber(ev.damage) or 0
    if not t or n <= 0 then return end
    local v = A:vol(t)
    v.tookThisTurn = (v.tookThisTurn or 0) + n
    v.lastTaken = n
    v.lastTakenKind = ev.kind or (ev.move and A:category(ev.move)) or "physical"
    if u then
      v.tookFrom = A:sideName(u)
      A:vol(u).pendingFail = nil
    end
    local mon = A:mon(t)
    if mon then
      local h = hitsTable(A:field())
      h[mon] = (h[mon] or 0) + 1
    end
  end)

  core:on("fainted", function(A, ev)
    local b = ev.battler
    if not b then return end
    local f = A:field()
    local side = A:sideName(b)
    f.faints = f.faints or {}
    f.faints[side] = (f.faints[side] or 0) + 1
    f.faintTurn = f.faintTurn or {}
    f.faintTurn[side] = A:turn()
  end)

  -- helpers the mechanics read
  local Track = {}
  core.track = Track
  function Track.hits(A, b)
    local h = A:field().hits
    return (h and h[A:mon(b)]) or 0
  end
  function Track.faints(A, side)
    local f = A:field().faints
    return (f and f[side]) or 0
  end
  function Track.movedThisTurn(A, b)
    local m = A:field().moved
    return m and m[A:sideName(b)] == A:turn() or false
  end
  -- the battler's first action since it came in (counted by moveUsed, which runs before the
  -- move's effect)
  function Track.firstAction(A, b) return (A:vol(b).acted or 0) <= 1 end
end
