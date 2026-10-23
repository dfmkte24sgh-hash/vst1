
----------------------------------------------------------------------------
-- METAIS
----------------------------------------------------------------------------
local function genBrass(ctx, P)
  local out, rng = {}, ctx.rng
  local lo, hi = Vc.reg(P, 48, 79)
  local style = P.style
  local nv = 3 + floor(P.complexity * 1.9)
  local st = { pats = {} }
  local rot = 0

  local function block(chord, t, len, vel, topTarget, gate)
    local top = Vc.nearestChordTone(chord, topTarget or (hi - 3 - (rot % 3) * 2), lo + 7, hi)
    local v = Vc.closeBelow(chord, top, nv)
    for _, p in ipairs(v) do Vc.add(out, ctx, P, t, len, p, vel, { gate = gate or 0.8 }) end
    rot = rot + 1
  end

  if style == 3 then -- swells longos
    for _, sl in ipairs(ctx.plan.slots) do
      local chord = sl.chord
      local top = Vc.nearestChordTone(chord, hi - 5 - (rot % 3) * 2, lo + 7, hi)
      rot = rot + 1
      for _, p in ipairs(Vc.closeBelow(chord, top, nv)) do Vc.add(out, ctx, P, sl.t0, sl.len * 0.95, p, 78, { gate = 1 }) end
      Vc.ccRamp(ctx, sl.t0, sl.t0 + sl.len * 0.85, 11, 35, 122, 0.5)
      Vc.cc(ctx, sl.t0 + sl.len * 0.95, 11, 60)
    end
  elseif style == 4 then -- contraponto de linhas
    local lists, idx = {}, {}
    local nvoice = 3
    for v = 1, nvoice do idx[v] = nil end
    for _, bar in ipairs(ctx.bars) do
      for v = 1, nvoice do
        local steps = Vc.onsets(ctx, bar, 0.12 + 0.4 * P.density * (v == 1 and 1.2 or 0.8), 0.5, rng, 2)
        for i, s in ipairs(steps) do
          local t = bar.t0 + s / 4
          local chord = Hm.chordAt(ctx.plan, t)
          local vlo, vhi = lo + (nvoice - v) * 5, lo + 14 + (nvoice - v) * 5
          local list = Th.pitchList(chord.mask, vlo, vhi)
          local cur = idx[v] or Th.nearestIdx(list, (vlo + vhi) // 2)
          cur = Th.nearestIdx(list, list[clamp(cur, 1, #list)])
          cur = Th.stepScale(list, cur, rng.pick({ -2, -1, -1, 0, 1, 1, 2 }))
          if bar.w[s] >= 0.8 then cur = Th.nearestIdx(list, Vc.nearestChordTone(chord, list[cur], vlo, vhi)) end
          idx[v] = cur
          local nxt = steps[i + 1] or bar.steps
          Vc.add(out, ctx, P, t, (nxt - s) / 4, list[cur], 76 + rng.int(-6, 8), { gate = 0.75 })
        end
      end
    end
  else
    for _, bar in ipairs(ctx.bars) do
      local gen
      if style == 2 then
        gen = function(b)
          local o = {}
          local pos = 0
          local cell = rng.pick({ { 3, 3, 2 }, { 3, 1, 4 }, { 2, 1, 1, 4 } })
          while pos < b.steps do
            for _, c in ipairs(cell) do
              if pos < b.steps then o[#o + 1] = pos end
              pos = pos + c
            end
          end
          if Vc.phraseEnd(ctx, b) then
            o[#o + 1] = max(0, b.steps - 3); o[#o + 1] = max(0, b.steps - 2); o[#o + 1] = max(0, b.steps - 1)
          end
          local seen, r = {}, {}
          for _, s in ipairs(o) do if s < b.steps and not seen[s] then seen[s] = true; r[#r + 1] = s end end
          table.sort(r)
          return r
        end
      else
        gen = function(b) return Vc.onsets(ctx, b, 0.12 + 0.45 * P.density, (style == 5) and 0.9 or 0.7, rng, 2) end
      end
      local mut = function(o, b)
        if #o > 1 and rng.chance(0.5) then table.remove(o, rng.int(1, #o)) end
        if rng.chance(0.5) then o[#o + 1] = rng.int(1, b.steps - 1); table.sort(o) end
        return o
      end
      local steps = U.copy(Vc.patternFor(st.pats, bar, rng, P, gen, mut))
      table.sort(steps)
      for i, s in ipairs(steps) do
        local t = bar.t0 + s / 4
        local chord = Hm.chordAt(ctx.plan, t)
        local nxt = steps[i + 1] or bar.steps
        local len = (nxt - s) / 4
        local vel = 84 + 24 * bar.w[s] + rng.int(-4, 6)
        if style == 5 then
          local list = Th.pitchList(chord.mask, lo + 10, hi)
          local ti = Th.nearestIdx(list, hi - 4 - (i % 4) * 2)
          local top = list[Th.stepScale(list, ti, rng.pick({ -1, 0, 1 }))]
          if bar.w[s] >= 0.8 then top = Vc.nearestChordTone(chord, top, lo + 10, hi) end
          local li = Th.nearestIdx(list, top)
          for k = 0, nv - 1 do
            Vc.add(out, ctx, P, t, min(len, 1.0), list[Th.stepScale(list, li, -2 * k)], vel - k * 2, { gate = 0.7 })
          end
        else
          block(chord, t, min(len, style == 2 and 1.5 or 0.75), vel, nil, 0.8)
        end
      end
    end
  end
  return out
end

Ins.def { id = "brass", label = "Metais", ch = 7, prog = 61, lo = 40, hi = 84,
  styles = { "Stabs sincopados", "Fanfarra (ponteado / tercinas)", "Swells longos", "Contraponto de linhas",
    "Shout jazz (bloco paralelo)" },
  defaults = { density = 0.4, variation = 0.4, complexity = 0.4, vel = 0.85, gate = 0.8, seedOff = 71 },
  gen = genBrass }

----------------------------------------------------------------------------
-- MADEIRAS / FLAUTA
----------------------------------------------------------------------------
local function genWinds(ctx, P)
  local out, rng = {}, ctx.rng
  local lo, hi = Vc.reg(P, 67, 96)
  local style = P.style
  local cur = round((lo + hi) / 2)
  local cycle, ci = nil, 0

  for _, bar in ipairs(ctx.bars) do
    local chord = Hm.chordAt(ctx.plan, bar.t0)
    local list = Th.pitchList(chord.mask, lo, hi)
    if style == 1 or style == 4 then -- frases com trilos / linhas respiradas
      local s = 0
      while s < bar.steps do
        local t = bar.t0 + s / 4
        local ch = Hm.chordAt(ctx.plan, t)
        list = Th.pitchList(ch.mask, lo, hi)
        local long = (style == 4)
        local len = long and rng.pick({ 8, 12, 16, 6 }) or rng.pick({ 2, 3, 4, 4, 6, 8 })
        len = min(len, bar.steps - s)
        local rest = rng.chance(long and 0.25 or (0.35 * (1.1 - P.density))) and rng.pick({ 2, 4 }) or 0
        if rest == 0 or s == 0 then
          local i = Th.nearestIdx(list, cur)
          i = Th.stepScale(list, i, rng.pick({ -3, -2, -1, -1, 1, 1, 2, 3, 0 }))
          local p = list[i]
          if bar.w[s] >= 0.8 then p = Vc.nearestChordTone(ch, p, lo, hi) end
          cur = p
          local lenQN = len / 4
          Vc.add(out, ctx, P, t, lenQN, p, 68 + 20 * bar.w[s] + rng.int(-4, 6), { gate = P.gate })
          if long then Vc.ccRamp(ctx, t, t + lenQN, 11, 70, 112, 0.5) end
          if rng.chance(P.complexity * 0.4) and lenQN >= 0.75 then
            local up = list[Th.stepScale(list, Th.nearestIdx(list, p), 1)]
            local tt = t + lenQN * 0.4
            local k = 0
            while tt < t + lenQN - 0.1 and k < 12 do
              Vc.add(out, ctx, P, tt, 0.0833, (k % 2 == 0) and up or p, 58, { gate = 1, noSwing = true })
              tt = tt + 0.0833
              k = k + 1
            end
          end
        end
        s = s + len + rest
      end
    elseif style == 2 then -- corridas de escala
      local probability = 0.25 + 0.6 * P.density
      if rng.chance(probability) or bar.idx == 1 then
        local start = rng.pick({ 0, 0, bar.beatSteps, bar.steps // 2 })
        local n = rng.int(5, 8 + floor(P.complexity * 8))
        local dir = rng.pick({ 1, -1 })
        local startP = Vc.nearestChordTone(chord, dir == 1 and lo + 3 or hi - 3, lo, hi)
        local i = Th.nearestIdx(list, startP)
        for k = 0, n - 1 do
          local s = start + k
          if s >= bar.steps then break end
          local t = bar.t0 + s / 4
          Vc.add(out, ctx, P, t, 0.22, list[clamp(i + dir * k, 1, #list)], 66 + (k * 2 * dir) % 24 + rng.int(-3, 5), { gate = 0.9 })
        end
        cur = list[clamp(i + dir * (n - 1), 1, #list)]
      end
    elseif style == 3 then -- pontilhismo
      local k = clamp(round(bar.steps * (0.1 + 0.3 * P.density)), 1, bar.steps)
      local e = Mt.euclid(k, bar.steps, rng.int(0, bar.steps - 1))
      for s = 0, bar.steps - 1 do
        if e[s] and rng.chance(0.8) then
          local t = bar.t0 + s / 4
          local ch = Hm.chordAt(ctx.plan, t)
          local l2 = Th.pitchList(ch.mask, lo, hi)
          Vc.add(out, ctx, P, t, 0.15, rng.pick(l2), 60 + rng.int(0, 28), { gate = 1 })
        end
      end
    else -- 5: ostinato minimalista em fase
      local n = clamp(5 + (P.variation > 0.5 and 2 or 0) + (P.complexity > 0.7 and 2 or 0), 3, 9)
      if not cycle or #cycle ~= n then
        cycle = {}
        for k = 1, n do cycle[k] = rng.pick({ 0, 1, 2, 4, -1, 3 }) end
      end
      for s = 0, bar.steps - 1, 2 do
        local t = bar.t0 + s / 4
        local ch = Hm.chordAt(ctx.plan, t)
        local l2 = Th.pitchList(ch.mask, lo, hi)
        local base = Th.nearestIdx(l2, Vc.nearestChordTone(ch, (lo + hi) // 2, lo, hi))
        local deg = cycle[ci % n + 1]
        ci = ci + 1
        if rng.chance(0.85 + 0.15 * P.density) then
          Vc.add(out, ctx, P, t, 0.4, l2[clamp(base + deg, 1, #l2)], 70 + (ci % n == 0 and 14 or 0) + rng.int(-3, 4), { gate = 0.8 })
        end
      end
      if rng.chance(P.variation * 0.15) then cycle[rng.int(1, n)] = rng.pick({ 0, 1, 2, 4, -1, 3 }) end
    end
  end
  return out
end

Ins.def { id = "winds", label = "Madeiras / Flauta", ch = 8, prog = 73, lo = 60, hi = 100,
  styles = { "Frases com trilos", "Corridas de escala", "Pontilhismo", "Linhas longas respiradas",
    "Ostinato minimalista em fase" },
  defaults = { density = 0.45, variation = 0.4, complexity = 0.5, vel = 0.72, gate = 0.9, seedOff = 83 },
  gen = genWinds }
