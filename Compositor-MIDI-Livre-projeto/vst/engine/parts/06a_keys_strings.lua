
----------------------------------------------------------------------------
-- auxiliares de acordes
----------------------------------------------------------------------------
function Vc.strum(out, ctx, P, t, len, pitches, vel, up, stagger)
  local n = #pitches
  for i = 1, n do
    local idx = up and (n - i + 1) or i
    Vc.add(out, ctx, P, t + (i - 1) * (stagger or 0.02), len, pitches[idx], vel - (i - 1) * 2, { gate = 1 })
  end
end

-- inicio/fim de cada compasso dentro de um slot de acorde
local function barsInSlot(ctx, sl)
  local list = {}
  for _, b in ipairs(ctx.bars) do
    if b.t0 < sl.t0 + sl.len - 1e-6 and b.t0 + b.len > sl.t0 + 1e-6 then list[#list + 1] = b end
  end
  return list
end

local function pedalCC(ctx, t0, t1)
  Vc.cc(ctx, max(0, t0 - 0.02), 64, 0)
  Vc.cc(ctx, t0 + 0.03, 64, 127)
end

----------------------------------------------------------------------------
-- TECLAS (piano / rhodes)
----------------------------------------------------------------------------
local function genKeys(ctx, P)
  local out, rng = {}, ctx.rng
  local lo, hi = Vc.reg(P, 48, 79)
  local style = P.style
  local prev
  local st = { pats = {} }

  if style == 1 or style == 3 or style == 4 or style == 6 then
    for _, sl in ipairs(ctx.plan.slots) do
      local chord = sl.chord
      if style == 1 then
        local v = Vc.voice(chord, lo, hi, prev, { max = 4 + floor(P.complexity * 2) })
        prev = v
        local restrike = P.density > 0.55
        local bl = barsInSlot(ctx, sl)
        for i, b in ipairs(bl) do
          if i == 1 or restrike then
            local t = max(b.t0, sl.t0)
            local z = min(b.t0 + b.len, sl.t0 + sl.len)
            Vc.strum(out, ctx, P, t, z - t, v, i == 1 and 84 or 70, false, P.complexity * 0.03)
          end
        end
        pedalCC(ctx, sl.t0, sl.t0 + sl.len)
      elseif style == 3 then -- balada: baixo + arpejo quebrado
        local v = Vc.voice(chord, lo, hi, prev, { max = 4 })
        prev = v
        local bp = lo - 12
        while bp % 12 ~= chord.root do bp = bp + 1 end
        Vc.add(out, ctx, P, sl.t0, sl.len, bp, 80, { gate = 1 })
        local pat = rng.pick({ { 1, 2, 3, 2 }, { 1, 3, 2, 4, 3, 2 }, { 1, 2, 3, 4, 3, 2 } })
        local step = (P.density > 0.6) and 0.25 or 0.5
        local k = 0
        local t = sl.t0 + step
        while t < sl.t0 + sl.len - 0.01 do
          local vi = clamp(pat[k % #pat + 1], 1, #v)
          Vc.add(out, ctx, P, t, step * 1.8, v[vi] + (rng.chance(P.complexity * 0.1) and 12 or 0), 62 + rng.int(-4, 8), { gate = 1 })
          k = k + 1
          t = t + step
        end
        pedalCC(ctx, sl.t0, sl.t0 + sl.len)
      elseif style == 4 then -- quartal / impressionista
        local list = Th.pitchList(chord.mask, lo, hi)
        local base = Th.nearestIdx(list, lo + 10 + (prev and 0 or 0))
        local n = 3 + floor(P.complexity * 2)
        local notes = {}
        local i0 = clamp(base + rng.int(-2, 4), 1, max(1, #list - 3 * (n - 1)))
        for k = 0, n - 1 do notes[#notes + 1] = list[clamp(i0 + 3 * k, 1, #list)] end
        Vc.strum(out, ctx, P, sl.t0, sl.len, notes, 76, false, 0.03)
        if sl.len > 2 and rng.chance(0.3 + P.variation * 0.5) then
          local t2 = sl.t0 + sl.len * rng.range(0.4, 0.7)
          local alt = {}
          for k, p in ipairs(notes) do
            local ii = Th.nearestIdx(list, p)
            alt[k] = list[Th.stepScale(list, ii, rng.pick({ -1, 1 }))]
          end
          Vc.strum(out, ctx, P, t2, sl.t0 + sl.len - t2, alt, 64, true, 0.04)
        end
        pedalCC(ctx, sl.t0, sl.t0 + sl.len)
      else -- clusters
        local list = Th.pitchList(chord.mask, lo + 5, hi)
        local count = 1 + floor(P.density * 2.5)
        for c = 1, count do
          local t = sl.t0 + (c - 1) * sl.len / count + rng.range(0, 0.3)
          local i0 = rng.int(1, max(1, #list - 4))
          local k = rng.int(2, 3 + floor(P.complexity * 2))
          local notes = {}
          for j = 0, k - 1 do notes[#notes + 1] = list[clamp(i0 + j, 1, #list)] end
          Vc.strum(out, ctx, P, t, min(sl.len / count + 0.5, sl.t0 + sl.len - t), notes, 58 + rng.int(0, 16), false, 0.01)
        end
        pedalCC(ctx, sl.t0, sl.t0 + sl.len)
      end
    end
  else
    -- estilos ritmicos: 2 (jazz), 5 (rhodes lo-fi), 7 (pulso)
    for _, bar in ipairs(ctx.bars) do
      local gen, mut
      if style == 7 then
        gen = function(b)
          local k = clamp(round(b.steps * (0.35 + 0.4 * P.density)), 2, b.steps)
          local e = Mt.euclid(k, b.steps, rng.int(0, 2))
          local o = {}
          for s = 0, b.steps - 1 do if e[s] and s % 2 == 0 or (e[s] and P.density > 0.7) then o[#o + 1] = s end end
          if #o == 0 then o[1] = 0 end
          return o
        end
      else
        gen = function(b) return Vc.onsets(ctx, b, 0.18 + 0.55 * P.density, (style == 2) and 0.9 or 0.75, rng, 2) end
      end
      mut = function(o, b)
        if rng.chance(0.5) and #o > 1 then table.remove(o, rng.int(1, #o)) end
        if rng.chance(0.6) then o[#o + 1] = rng.int(1, b.steps - 1); table.sort(o) end
        return o
      end
      local steps = U.copy(Vc.patternFor(st.pats, bar, rng, P, gen, mut))
      local starts = {}
      for _, sl in ipairs(ctx.plan.slots) do
        if sl.t0 >= bar.t0 - 1e-6 and sl.t0 < bar.t0 + bar.len - 1e-6 then starts[round((sl.t0 - bar.t0) * 4)] = true end
      end
      local have = {}
      for _, s in ipairs(steps) do have[s] = true end
      for s in pairs(starts) do if not have[s] then steps[#steps + 1] = s end end
      table.sort(steps)
      for i, s in ipairs(steps) do
        local t = bar.t0 + s / 4
        local chord = Hm.chordAt(ctx.plan, t)
        local nxt = steps[i + 1] or bar.steps
        local len = (nxt - s) / 4
        local opts = { noRoot = (style == 2), max = (style == 5) and 5 or 4 }
        local v = Vc.voice(chord, lo, hi, prev, opts)
        prev = v
        if style == 2 then
          Vc.strum(out, ctx, P, t, min(len * 0.7, 1.0), v, 72 + rng.int(-6, 12), false, 0.008)
        elseif style == 5 then
          Vc.strum(out, ctx, P, t, min(len * 0.9, 1.5), v, 66 + rng.int(-6, 10), rng.chance(0.3), 0.02 + 0.015 * rng.f())
        else
          local acc = bar.w[s] >= 0.55 and 88 or 66
          Vc.strum(out, ctx, P, t, 0.22, v, acc, false, 0.004)
        end
      end
    end
  end
  return out
end

Ins.def { id = "keys", label = "Teclas (piano / rhodes)", ch = 1, prog = 0, lo = 40, hi = 88,
  styles = { "Acordes sustentados", "Comping jazz (sem raiz)", "Balada (baixo + arpejo quebrado)",
    "Quartal / impressionista", "Rhodes lo-fi (strum)", "Clusters / texturas", "Pulso ostinato (minimal / house)" },
  defaults = { density = 0.45, variation = 0.4, complexity = 0.4, vel = 0.78, gate = 0.95, seedOff = 11 },
  gen = genKeys }

----------------------------------------------------------------------------
-- CORDAS / PAD
----------------------------------------------------------------------------
local function genStrings(ctx, P)
  local out, rng = {}, ctx.rng
  local lo, hi = Vc.reg(P, 48, 84)
  local style = P.style
  local prev
  local st = { pats = {} }

  local function swell(sl, a, b)
    Vc.ccRamp(ctx, sl.t0, sl.t0 + sl.len * 0.55, 11, a, b, 0.5)
    Vc.ccRamp(ctx, sl.t0 + sl.len * 0.55, sl.t0 + sl.len, 11, b, a + 10, 0.5)
  end

  for _, sl in ipairs(ctx.plan.slots) do
    local chord = sl.chord
    local v = Vc.voice(chord, lo, hi, prev, { max = 3 + floor(P.complexity * 3) })
    prev = v
    if style == 1 then
      for i, p in ipairs(v) do Vc.add(out, ctx, P, sl.t0 + (i - 1) * 0.01, sl.len + 0.05, p, 70, { gate = 1 }) end
      swell(sl, 48, 105)
    elseif style == 2 then
      for i, p in ipairs(v) do
        local off = (i - 1) * rng.range(0.05, 0.25) * P.density
        Vc.add(out, ctx, P, sl.t0 + off, sl.len - off + 0.1, p, 66 + rng.int(-4, 8), { gate = 1 })
      end
      swell(sl, 55, 110)
    elseif style == 3 or style == 5 then
      local u = (style == 3) and 2 or 4
      local pat = style == 5 and rng.pick({ { 1, 2, 3, 2 }, { 1, 3, 2, 3 }, { 3, 2, 1, 2 } }) or nil
      local k = 0
      for _, b in ipairs(barsInSlot(ctx, sl)) do
        for s = 0, b.steps - 1, u do
          local t = b.t0 + s / 4
          if t >= sl.t0 - 1e-6 and t < sl.t0 + sl.len - 1e-6 then
            if rng.chance(0.55 + 0.45 * P.density) then
              if style == 3 then
                local acc = b.w[s] >= 0.55 and 92 or 70
                for _, p in ipairs(v) do Vc.add(out, ctx, P, t, u / 4, p, acc + rng.int(-4, 4), { gate = 0.55 }) end
              else
                local p = v[clamp(pat[k % #pat + 1], 1, #v)] + (b.w[s] >= 0.8 and 0 or 12 * (rng.chance(0.25) and 1 or 0))
                Vc.add(out, ctx, P, t, u / 4, p, 80 + rng.int(-6, 6), { gate = 0.4 })
                k = k + 1
              end
            end
          end
        end
      end
    elseif style == 4 then -- tremolo
      local top = { v[#v] }
      if #v >= 3 and P.density > 0.4 then top[2] = v[#v - 1] end
      local t = sl.t0
      while t < sl.t0 + sl.len - 0.01 do
        for _, p in ipairs(top) do Vc.add(out, ctx, P, t, 0.22, p, 58 + rng.int(-4, 6), { gate = 1 }) end
        t = t + 0.25
      end
      if #v >= 3 then Vc.add(out, ctx, P, sl.t0, sl.len, v[1], 60, { gate = 1 }) end
      swell(sl, 40, 100)
    elseif style == 6 then -- suspensao e resolucao
      local third = nil
      for _, iv in ipairs(chord.ivs) do if (iv == 3 or iv == 4) then third = (chord.root + iv) % 12 end end
      local cut = sl.t0 + sl.len * rng.range(0.5, 0.7)
      for _, p in ipairs(v) do
        if third and p % 12 == third then
          local sp = p + ((p % 12 == (chord.root + 3) % 12) and 2 or 1)
          Vc.add(out, ctx, P, sl.t0, cut - sl.t0, sp, 70, { gate = 1 })
          Vc.add(out, ctx, P, cut, sl.t0 + sl.len - cut + 0.05, p, 76, { gate = 1 })
        else
          Vc.add(out, ctx, P, sl.t0, sl.len + 0.05, p, 66, { gate = 1 })
        end
      end
      swell(sl, 50, 108)
    else -- 7: linha lenta de cordas
      local list = Th.pitchList(chord.mask, lo + 12, hi + 4)
      local t = sl.t0
      local idx = Th.nearestIdx(list, v[#v] + 5)
      while t < sl.t0 + sl.len - 0.05 do
        local len = rng.pick({ 1, 1.5, 2, 3, 4 }) * (1.4 - P.density)
        len = min(max(0.5, len), sl.t0 + sl.len - t)
        if t == sl.t0 then idx = Th.nearestIdx(list, Vc.nearestChordTone(chord, list[clamp(idx, 1, #list)], lo + 12, hi + 4)) end
        Vc.add(out, ctx, P, t, len, list[clamp(idx, 1, #list)], 74 + rng.int(-4, 8), { gate = 1 })
        idx = Th.stepScale(list, idx, rng.pick({ -2, -1, -1, 1, 1, 2, 0 }))
        t = t + len
      end
      for i, p in ipairs(v) do if i <= 2 then Vc.add(out, ctx, P, sl.t0, sl.len + 0.05, p - 12, 56, { gate = 1 }) end end
      swell(sl, 55, 100)
    end
  end
  return out
end

Ins.def { id = "strings", label = "Cordas / Pad", ch = 2, prog = 48, lo = 40, hi = 92,
  styles = { "Pad longo", "Cordas legato (vozes)", "Staccato / spiccato ritmico", "Tremolo", "Pizzicato",
    "Suspensao e resolucao", "Linha lenta (melodia de cordas)" },
  defaults = { density = 0.5, variation = 0.4, complexity = 0.45, vel = 0.7, gate = 1, seedOff = 23 },
  gen = genStrings }
