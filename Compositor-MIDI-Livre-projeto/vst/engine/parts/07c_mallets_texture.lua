
----------------------------------------------------------------------------
-- MALLETS (marimba / vibrafone / sinos / kalimba)
----------------------------------------------------------------------------
local function genMallets(ctx, P)
  local out, rng = {}, ctx.rng
  local lo, hi = Vc.reg(P, 60, 96)
  local style = P.style
  local cyc, ci = nil, 0

  for _, bar in ipairs(ctx.bars) do
    local chord = Hm.chordAt(ctx.plan, bar.t0)
    if style == 1 or style == 5 then -- celula minimalista / kalimba pentatonico
      local n = (style == 1) and rng.pick({ 5, 7 }) or 6
      if not cyc or (rng.chance(P.variation * 0.08)) then
        cyc = {}
        for k = 1, n do cyc[k] = rng.pick({ 0, 1, 2, 3, 4, -2, -1 }) end
      end
      for s = 0, bar.steps - 1, 2 do
        local t = bar.t0 + s / 4
        local ch = Hm.chordAt(ctx.plan, t)
        local m = (style == 5) and pentaMask(ch, false) or ch.mask
        local list = Th.pitchList(m, lo, hi)
        local base = Th.nearestIdx(list, Vc.nearestChordTone(ch, (lo + hi) // 2, lo, hi))
        local deg = cyc[ci % #cyc + 1]
        ci = ci + 1
        if rng.chance(0.7 + 0.3 * P.density) then
          local p = list[clamp(base + deg, 1, #list)]
          if style == 5 and rng.chance(P.complexity * 0.2) then p = p + 12 end
          Vc.add(out, ctx, P, t, 0.9, p, 66 + (bar.w[s] >= 0.55 and 16 or 0) + rng.int(-4, 4), { gate = P.gate })
        end
      end
    elseif style == 2 then -- sinos esparsos
      local count = 1 + floor(P.density * 5)
      for _ = 1, count do
        if rng.chance(0.6) then
          local s = rng.int(0, bar.steps - 1)
          local t = bar.t0 + s / 4
          local ch = Hm.chordAt(ctx.plan, t)
          local list = Th.pitchList(ch.mask, lo + 12, hi)
          Vc.add(out, ctx, P, t, rng.range(2, 6), rng.pick(list), 56 + rng.int(0, 28), { gate = 1 })
        end
      end
    elseif style == 3 then -- gamelan: duas vozes entrelacadas + gongo
      local ch0 = chord
      local m = pentaMask(ch0, false)
      local list = Th.pitchList(m, lo, hi)
      local c = Th.nearestIdx(list, Vc.nearestChordTone(ch0, (lo + hi) // 2, lo, hi))
      local cellA = { 0, 2, 1, 3 }
      local cellB = { 1, 0, 3, 2 }
      if rng.chance(P.variation * 0.3) then cellA[rng.int(1, 4)] = rng.pick({ 0, 1, 2, 3, 4 }) end
      for s = 0, bar.steps - 1 do
        local t = bar.t0 + s / 4
        local ch = Hm.chordAt(ctx.plan, t)
        local l2 = Th.pitchList(pentaMask(ch, false), lo, hi)
        local base = Th.nearestIdx(l2, Vc.nearestChordTone(ch, (lo + hi) // 2, lo, hi))
        local deg = (s % 2 == 0) and cellA[(s // 2) % 4 + 1] or cellB[(s // 2) % 4 + 1] + 3
        if rng.chance(0.55 + 0.45 * P.density) then
          Vc.add(out, ctx, P, t, 0.45, l2[clamp(base + deg - 1, 1, #l2)], 60 + (s % 4 == 0 and 14 or 0) + rng.int(-3, 4), { gate = P.gate })
        end
      end
      if bar.idx % 4 == 1 then
        local g = Vc.nearestChordTone(chord, lo - 12, 36, 60)
        Vc.add(out, ctx, P, bar.t0, 6, g, 100, { gate = 1 })
      end
    else -- 4: cascata descendente
      for _, sl in ipairs(ctx.plan.slots) do
        if sl.t0 >= bar.t0 - 1e-6 and sl.t0 < bar.t0 + bar.len - 1e-6 then
          local list = Th.pitchList(sl.chord.mask, lo, hi)
          local i = Th.nearestIdx(list, Vc.nearestChordTone(sl.chord, hi - 2, lo, hi))
          local n = rng.int(4, 7 + floor(P.complexity * 6))
          local step = (P.density > 0.5) and 0.25 or 0.5
          for k = 0, n - 1 do
            local t = sl.t0 + k * step
            if t < sl.t0 + sl.len then
              Vc.add(out, ctx, P, t, 1.5, list[clamp(i - k, 1, #list)], 80 - k * 2, { gate = P.gate })
            end
          end
        end
      end
    end
  end
  return out
end

Ins.def { id = "mallets", label = "Mallets / Sinos", ch = 10, prog = 12, lo = 55, hi = 105,
  styles = { "Celula minimalista (fase)", "Sinos esparsos", "Gamelan (vozes entrelacadas)",
    "Cascata descendente", "Kalimba (ciclo pentatonico)" },
  defaults = { density = 0.5, variation = 0.4, complexity = 0.4, vel = 0.72, gate = 1, seedOff = 97 },
  gen = genMallets }

----------------------------------------------------------------------------
-- TEXTURA / DRONE / FX
----------------------------------------------------------------------------
local function genTexture(ctx, P)
  local out, rng = {}, ctx.rng
  local lo, hi = Vc.reg(P, 24, 90)
  local style = P.style
  local G = ctx.G

  if style == 1 then -- drone (tonica + quinta, continua)
    local follow = P.complexity > 0.5
    local active = {}
    local function close(i, t) if active[i] then active[i].l = max(0.1, t - active[i].t) active[i] = nil end end
    for _, sl in ipairs(ctx.plan.slots) do
      local root = follow and sl.chord.root or G.key
      local pitches = { 36 + (root - 36) % 12 + (P.octave or 0) * 12, 48 + (root - 48) % 12 + (P.octave or 0) * 12 }
      pitches[3] = pitches[1] + 7
      for i = 1, 3 do
        local a = active[i]
        if a and a.p == pitches[i] then
          a.l = a.l + sl.len
        else
          close(i, sl.t0)
          Vc.add(out, ctx, P, sl.t0, sl.len, pitches[i], 60 + i * 4, { gate = 1, noSwing = true })
          active[i] = out[#out]
        end
      end
      Vc.ccRamp(ctx, sl.t0, sl.t0 + sl.len, 11, 70, 105, 1)
    end
  elseif style == 2 then -- clusters com swell
    for _, sl in ipairs(ctx.plan.slots) do
      local list = Th.pitchList(sl.chord.mask, lo + 24, hi)
      local i0 = rng.int(1, max(1, #list - 5))
      local k = rng.int(3, 4 + floor(P.complexity * 2))
      for j = 0, k - 1 do
        Vc.add(out, ctx, P, sl.t0 + j * 0.03, sl.len, list[clamp(i0 + j, 1, #list)], 54 + rng.int(0, 10), { gate = 1, noSwing = true })
      end
      Vc.ccRamp(ctx, sl.t0, sl.t0 + sl.len * 0.7, 11, 30, 118, 0.5)
      Vc.ccRamp(ctx, sl.t0 + sl.len * 0.7, sl.t0 + sl.len, 11, 118, 40, 0.5)
    end
  elseif style == 3 then -- acorde evolutivo (vozes entram uma a uma)
    local prev
    for _, sl in ipairs(ctx.plan.slots) do
      local v = Vc.voice(sl.chord, lo + 24, hi - 12, prev, { max = 5 })
      prev = v
      for i, p in ipairs(v) do
        local off = min((i - 1) * rng.range(0.5, 1.5) * (0.5 + P.density), sl.len * 0.7)
        Vc.add(out, ctx, P, sl.t0 + off, sl.len - off + 0.1, p, 56 + i * 3, { gate = 1, noSwing = true })
      end
      Vc.ccRamp(ctx, sl.t0, sl.t0 + sl.len, 11, 40, 110, 0.5)
    end
  elseif style == 4 then -- chuva de pontos
    for _, bar in ipairs(ctx.bars) do
      local n = floor(P.density * 7 + rng.f() * 2)
      for _ = 1, n do
        local t = bar.t0 + rng.range(0, bar.len - 0.1)
        local ch = Hm.chordAt(ctx.plan, t)
        local list = Th.pitchList(ch.mask, lo + 36, hi + 6)
        Vc.add(out, ctx, P, t, rng.range(0.1, 1.2), rng.pick(list), 40 + rng.int(0, 40), { gate = 1, noSwing = true })
      end
    end
  elseif style == 5 then -- riser ate o fim de cada frase
    for _, bar in ipairs(ctx.bars) do
      if Vc.phraseEnd(ctx, bar) then
        local ch = Hm.chordAt(ctx.plan, bar.t0)
        local list = Th.pitchList(ch.mask, lo + 24, hi)
        local i = Th.nearestIdx(list, lo + 30)
        local t = bar.t0
        local gap = 0.5
        local k = 0
        while t < bar.t0 + bar.len - 0.05 do
          Vc.add(out, ctx, P, t, gap * 0.9, list[clamp(i + k, 1, #list)], 50 + floor(60 * (t - bar.t0) / bar.len), { gate = 1, noSwing = true })
          t = t + gap
          gap = max(0.0625, gap * 0.86)
          k = k + 1
        end
        Vc.ccRamp(ctx, bar.t0, bar.t0 + bar.len, 1, 10, 127, 0.25)
      end
    end
  else -- 6: impactos graves
    for _, bar in ipairs(ctx.bars) do
      if bar.idx % 4 == 1 or (P.density > 0.5 and bar.idx % 2 == 1 and rng.chance(0.5)) then
        local ch = Hm.chordAt(ctx.plan, bar.t0)
        local p = 28 + (ch.root - 28) % 12 + (P.octave or 0) * 12
        Vc.add(out, ctx, P, bar.t0, rng.pick({ 4, 6, 8 }), p, 108, { gate = 1, noSwing = true })
      end
    end
  end
  return out
end

Ins.def { id = "texture", label = "Textura / Drone / FX", ch = 11, prog = 89, lo = 24, hi = 96,
  styles = { "Drone (tonica + quinta)", "Clusters com swell", "Acorde evolutivo", "Chuva de pontos",
    "Riser (fim de frase)", "Impactos graves" },
  defaults = { density = 0.4, variation = 0.4, complexity = 0.4, vel = 0.65, gate = 1, on = false, seedOff = 101 },
  gen = genTexture }
