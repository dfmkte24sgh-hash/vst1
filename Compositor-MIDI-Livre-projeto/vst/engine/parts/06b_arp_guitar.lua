
----------------------------------------------------------------------------
-- ARPEJO / SEQUENCIA
----------------------------------------------------------------------------
local function arpPool(chord, lo, hi, useScale)
  if useScale then return Th.pitchList(chord.mask, lo, hi) end
  local pool = {}
  for p = lo, hi do if Vc.isChordTone(chord, p) then pool[#pool + 1] = p end end
  if #pool == 0 then pool[1] = lo end
  return pool
end

local function genArp(ctx, P)
  local out, rng = {}, ctx.rng
  local lo, hi = Vc.reg(P, 52, 88)
  local style = P.style
  local octs = 1 + floor(P.complexity * 2.4)
  local grid = (P.density > 0.75) and 1 or ((P.density > 0.35) and 2 or 4)
  local cyc = rng.pick({ 3, 5, 6, 7, 9 })
  local counter, dir, idx = 0, 1, 1
  local state = { pats = {} }
  local lastBarSlot

  for _, bar in ipairs(ctx.bars) do
    local euc
    if style == 8 then
      local k = clamp(round(bar.steps * (0.3 + 0.35 * P.density)), 2, bar.steps)
      euc = Mt.euclid(k, bar.steps, floor(bar.idx * P.variation * 2) % bar.steps)
    end
    local omit = {}
    if P.variation > 0.3 then
      for s = 0, bar.steps - 1 do omit[s] = rng.chance((P.variation - 0.3) * 0.25) and bar.w[s] < 0.55 end
    end
    for s = 0, bar.steps - 1, grid do
      local t = bar.t0 + s / 4
      local chord, sl = Hm.chordAt(ctx.plan, t)
      local fire = true
      if style == 8 then fire = euc[s] end
      if omit[s] then fire = false end
      local base = lo + 12 * 0
      local pool = arpPool(chord, lo, min(hi, lo + 12 * octs + 4), style == 4 or style == 7)
      if sl ~= lastBarSlot then idx, dir, lastBarSlot = 1, 1, sl end
      local p
      local n = #pool
      if style == 1 then idx = counter % n + 1
      elseif style == 2 then idx = n - (counter % n)
      elseif style == 3 then
        local m = max(1, 2 * n - 2)
        local k = counter % m
        idx = (k < n) and (k + 1) or (m - k + 1)
      elseif style == 4 then
        if bar.w[s] >= 0.8 then idx = Th.nearestIdx(pool, Vc.nearestChordTone(chord, pool[clamp(idx, 1, n)], lo, hi))
        else idx = Th.stepScale(pool, idx, rng.pick({ -3, -2, -1, 1, 2, 3, 4 })) end
      elseif style == 5 then
        local pat = { 1, 3, 2, 4 }
        idx = (pat[counter % 4 + 1] + floor(counter / 4) % 2 * 2 - 1) % n + 1
      elseif style == 6 then
        idx = (counter * 2 + counter % cyc) % n + 1
      elseif style == 7 then
        if counter % 8 == 0 then dir = rng.pick({ 1, -1 }) end
        idx = idx + dir
        if idx > n then idx = 1 elseif idx < 1 then idx = n end
      else idx = counter % n + 1 end
      counter = counter + 1
      if fire then
        p = pool[clamp(idx, 1, n)]
        local acc = bar.w[s] >= 0.55 and 84 or 66
        Vc.add(out, ctx, P, t, grid / 4, p, acc + rng.int(-5, 5), { gate = P.gate })
        if P.complexity > 0.65 and rng.chance(0.1) and grid >= 2 then
          Vc.add(out, ctx, P, t + grid / 8, grid / 8, p, 52, { gate = 0.8 })
        end
      end
    end
  end
  return out
end

Ins.def { id = "arp", label = "Arpejo / Sequencia", ch = 3, prog = 46, lo = 48, hi = 96,
  styles = { "Subindo", "Descendo", "Sobe-desce", "Aleatorio na escala", "Padrao cruzado",
    "Poliritmia (ciclo independente)", "Cascata de escala", "Euclidiano" },
  defaults = { density = 0.5, variation = 0.35, complexity = 0.4, vel = 0.7, gate = 0.8, seedOff = 37 },
  gen = genArp }

----------------------------------------------------------------------------
-- VIOLAO / GUITARRA
----------------------------------------------------------------------------
local function genGuitar(ctx, P)
  local out, rng = {}, ctx.rng
  local lo, hi = Vc.reg(P, 40, 84)
  local style = P.style
  local state = { pats = {} }
  local shift = (P.octave or 0) * 12
  local function g(chord, n, power)
    local v = Vc.guitar(chord, n, power)
    for i, p in ipairs(v) do v[i] = clamp(p + shift, 0, 127) end
    return v
  end

  for _, bar in ipairs(ctx.bars) do
    local starts = {}
    for _, sl in ipairs(ctx.plan.slots) do
      if sl.t0 >= bar.t0 - 1e-6 and sl.t0 < bar.t0 + bar.len - 1e-6 then starts[round((sl.t0 - bar.t0) * 4)] = true end
    end
    local function chordAtStep(s) return Hm.chordAt(ctx.plan, bar.t0 + s / 4) end

    if style == 1 then -- strum
      local gen = function(b)
        local o = Vc.onsets(ctx, b, 0.2 + 0.6 * P.density, 0.55, rng, 2)
        local pat = {}
        for i, s in ipairs(o) do pat[i] = { s = s, up = (s % b.beatSteps ~= 0) and rng.chance(0.75) } end
        return pat
      end
      local mut = function(p, b)
        if rng.chance(0.5) then p[#p + 1] = { s = rng.int(1, b.steps - 1), up = true } end
        table.sort(p, function(a, c) return a.s < c.s end)
        return p
      end
      local pat = U.copy(Vc.patternFor(state.pats, bar, rng, P, gen, mut))
      for s in pairs(starts) do
        local f = false
        for _, e in ipairs(pat) do if e.s == s then f = true end end
        if not f then pat[#pat + 1] = { s = s, up = false } end
      end
      table.sort(pat, function(a, c) return a.s < c.s end)
      for i, e in ipairs(pat) do
        local chord = chordAtStep(e.s)
        local nxt = pat[i + 1] and pat[i + 1].s or bar.steps
        local v = g(chord, 4 + floor(P.complexity * 2) + (e.up and 0 or 1))
        if e.up then v = { table.unpack(v, max(1, #v - 3)) } end
        Vc.strum(out, ctx, P, bar.t0 + e.s / 4, min((nxt - e.s) / 4, 1.5), v, e.up and 66 or 88, e.up, 0.018)
      end
    elseif style == 2 then -- fingerpicking alternado
      local u = bar.beatSteps
      local flip = false
      for s = 0, bar.steps - 1, max(1, u // 2) do
        local chord = chordAtStep(s)
        local v = g(chord, 6)
        local t = bar.t0 + s / 4
        local onBeat = (s % u == 0)
        if onBeat then
          local bn = flip and v[min(2, #v)] or v[1]
          Vc.add(out, ctx, P, t, u / 4 * 1.5, bn, 90, { gate = 1 })
          flip = not flip
        else
          local hi3 = { v[min(3, #v)], v[min(4, #v)], v[min(5, #v)], v[#v] }
          Vc.add(out, ctx, P, t, 0.5, rng.pick(hi3), 70 + rng.int(-4, 6), { gate = 1 })
        end
        if P.complexity > 0.5 and rng.chance(0.2) and not onBeat then
          Vc.add(out, ctx, P, t + 0.125, 0.25, v[#v], 56, { gate = 1 })
        end
      end
    elseif style == 3 then -- power chords / riff
      local u = max(1, bar.beatSteps // 2)
      for s = 0, bar.steps - 1, u do
        local chord = chordAtStep(s)
        local power = g(chord, 3, true)
        local accent = bar.gstart[s] or s == 0
        if accent or rng.chance(0.55 + 0.45 * P.density) then
          local palm = not accent and rng.chance(0.7)
          Vc.strum(out, ctx, P, bar.t0 + s / 4, palm and 0.15 or (u / 4) * 0.9, power, accent and 100 or (palm and 66 or 82), false, 0.006)
        end
      end
    elseif style == 4 then -- ambiente com delay pontuado
      local s = 0
      local k = 0
      while s < bar.steps do
        local chord = chordAtStep(s)
        local pool = arpPool(chord, max(lo, 55) + shift * 0, min(hi + 12, 88), false)
        local pat = { 1, 2, 4, 3, 2, 3 }
        local p = pool[clamp(pat[k % #pat + 1] + (k // #pat) % 2, 1, #pool)]
        if rng.chance(0.7 + 0.3 * P.density) then
          Vc.add(out, ctx, P, bar.t0 + s / 4, 0.75, p, 74 - (k % 3) * 6, { gate = 1 })
        end
        k = k + 1
        s = s + 3
      end
    elseif style == 5 then -- funk muted 16ths
      for s = 0, bar.steps - 1 do
        local chord = chordAtStep(s)
        local v = g(chord, 4)
        local t = bar.t0 + s / 4
        local stab = rng.chance(0.08 + 0.3 * P.density) and bar.w[s] < 0.55 or bar.gstart[s]
        if stab then
          Vc.strum(out, ctx, P, t, 0.15, { table.unpack(v, 2) }, 92, rng.chance(0.4), 0.008)
        elseif rng.chance(0.35 + 0.55 * P.density) then
          Vc.add(out, ctx, P, t, 0.08, v[2] or v[1], 34 + (s % 2 == 0 and 10 or 0) + rng.int(-4, 4), { gate = 1 })
        end
      end
    else -- 6: flamenco / rasgueado
      for gi, gst in ipairs(bar.groups) do
        local gpos = 0
        for k = 1, gi - 1 do gpos = gpos + bar.groups[k] end
        local chord = chordAtStep(gpos)
        local v = g(chord, 5)
        local nb = floor(3 + P.density * 3)
        for k = 0, nb do
          local up = (k % 2 == 1)
          local vv = up and { table.unpack(v, max(1, #v - 2)) } or v
          Vc.strum(out, ctx, P, bar.t0 + gpos / 4 + k * 0.125, 0.12, vv, up and 62 or 92, up, 0.008)
        end
        local list = Th.pitchList(chord.mask, 60, 84)
        if rng.chance(P.complexity) then
          local i = rng.int(1, #list)
          for k = 0, 3 do
            local t = bar.t0 + gpos / 4 + (nb + 2) * 0.125 + k * 0.125
            if t < bar.t0 + bar.len - 0.1 then Vc.add(out, ctx, P, t, 0.12, list[clamp(i + k * rng.pick({ -1, 1 }), 1, #list)], 70, { gate = 1 }) end
          end
        end
      end
    end
  end
  return out
end

Ins.def { id = "guitar", label = "Violao / Guitarra", ch = 4, prog = 25, lo = 40, hi = 88,
  styles = { "Strum (acordes ritmicos)", "Fingerpicking alternado", "Power chords / riff", "Ambiente (delay pontuado)",
    "Funk (muted 16ths)", "Flamenco / rasgueado" },
  defaults = { density = 0.5, variation = 0.4, complexity = 0.4, vel = 0.78, gate = 1, seedOff = 41 },
  gen = genGuitar }
