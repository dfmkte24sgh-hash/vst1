
----------------------------------------------------------------------------
-- BAIXO
----------------------------------------------------------------------------
local function rootPitch(chord, lo, pedal)
  local pc = pedal or chord.root
  local p = lo
  while p % 12 ~= pc % 12 do p = p + 1 end
  return p
end

local function seventhIv(chord)
  for _, iv in ipairs(chord.ivs) do
    local pc = iv % 12
    if (pc == 10 or pc == 11 or pc == 9) and iv ~= 0 then return pc end
  end
  return 10
end
local function thirdIv(chord)
  for _, iv in ipairs(chord.ivs) do
    local pc = iv % 12
    if pc == 3 or pc == 4 or pc == 2 or pc == 5 then return pc end
  end
  return 4
end
local function fifthIv(chord)
  for _, iv in ipairs(chord.ivs) do
    local pc = iv % 12
    if pc == 7 or pc == 6 or pc == 8 then return pc end
  end
  return 7
end

local function bassRole(chord, role, lo, hi, rng, list, prevIdx)
  local base = rootPitch(chord, lo)
  local p
  if role == "root" then p = base
  elseif role == "fifth" then p = base + fifthIv(chord)
  elseif role == "oct" then p = base + 12
  elseif role == "seventh" then p = base + seventhIv(chord)
  elseif role == "third" then p = base + thirdIv(chord)
  else
    local i = Th.nearestIdx(list, base)
    p = list[Th.stepScale(list, i, rng.pick({ -2, -1, 1, 2 }))]
  end
  while p > hi do p = p - 12 end
  while p < lo do p = p + 12 end
  return p
end

-- passos obrigatorios: inicio de cada acorde dentro do compasso
local function chordStarts(ctx, bar)
  local out = {}
  for _, sl in ipairs(ctx.plan.slots) do
    if sl.t0 >= bar.t0 - 1e-6 and sl.t0 < bar.t0 + bar.len - 1e-6 then
      out[round((sl.t0 - bar.t0) * 4)] = true
    end
  end
  return out
end

local function genBass(ctx, P)
  local out, rng = {}, ctx.rng
  local lo, hi = Vc.reg(P, 28, 55)
  local style = P.style
  local st = { pats = {}, prev = nil, motif = nil }
  local lastNote

  local function emit(t, len, p, v, opts) Vc.add(out, ctx, P, t, len, p, v, opts); lastNote = p end

  for _, bar in ipairs(ctx.bars) do
    local starts = chordStarts(ctx, bar)
    if style == 2 then ------------------------------------------------ walking
      local u = bar.beatSteps
      local prev = lastNote
      for s = 0, bar.steps - 1, u do
        local t = bar.t0 + s / 4
        local chord, sl = Hm.chordAt(ctx.plan, t)
        local list = Th.pitchList(chord.mask, lo, hi)
        local nextT = t + u / 4
        local nchord = Hm.chordAt(ctx.plan, min(nextT, ctx.total - 0.01))
        local p
        local pedal = P.useFrench
        if starts[s] or not prev then p = rootPitch(chord, lo + 5) 
        elseif nchord ~= chord then
          local target = rootPitch(nchord, lo + 5)
          if rng.chance(0.5 + 0.4 * P.complexity) then p = target + rng.pick({ -1, 1 })
          else p = list[Th.stepScale(list, Th.nearestIdx(list, target), rng.pick({ -1, 1 }))] end
        else
          local cands = {}
          for q = max(lo, prev - 5), min(hi, prev + 5) do
            if q ~= prev and Vc.isChordTone(chord, q) then cands[#cands + 1] = q end
          end
          if #cands == 0 or rng.chance(P.complexity * 0.35) then
            local i = Th.nearestIdx(list, prev)
            p = list[Th.stepScale(list, i, rng.pick({ -1, 1, 1, -2, 2 }))]
          else p = rng.pick(cands) end
        end
        p = clamp(p, lo, hi + 2)
        emit(t, u / 4, p, (s == 0 and 100 or 88) + rng.int(-6, 6))
        prev = p
        if rng.chance(P.complexity * 0.25 * P.density) and u >= 4 then
          local i = Th.nearestIdx(list, p)
          emit(t + u / 8 * 1.0, u / 8, list[Th.stepScale(list, i, rng.pick({ -1, 1 }))], 60)
        end
      end
    elseif style == 4 then ------------------------------------------- sub / 808
      local steps = {}
      for s = 0, bar.steps - 1 do
        if s == 0 or starts[s] or (P.lock and ctx.shared.kick[round((bar.t0 + s / 4) * 4)] and rng.chance(0.85))
            or (not P.lock and rng.chance(Mt.onsetProb(ctx, bar, s, P.density * 0.5, 0.7) * 0.5)) then
          steps[#steps + 1] = s
        end
      end
      for i, s in ipairs(steps) do
        local t = bar.t0 + s / 4
        local chord = Hm.chordAt(ctx.plan, t)
        local nxt = steps[i + 1] or bar.steps
        local len = (nxt - s) / 4
        local p = rootPitch(chord, lo, ctx.G.pedalBass and chord.pedal)
        if rng.chance(P.complexity * 0.3) and s ~= 0 then p = p + 12 end
        emit(t, len, p, s == 0 and 118 or 100, { gate = 0.95 })
      end
    elseif style == 7 then ------------------------------------------- drone movel
      local pc = ctx.G.key
      for _, sl in ipairs(ctx.plan.slots) do
        if sl.t0 >= bar.t0 - 1e-6 and sl.t0 < bar.t0 + bar.len - 1e-6 then
          local chord = sl.chord
          local root = rootPitch(chord, lo, chord.pedal or (P.complexity < 0.5 and pc or nil))
          emit(sl.t0, sl.len, root, 92)
          if P.density > 0.3 then
            local list = Th.pitchList(chord.mask, lo + 7, hi + 7)
            local n = rng.int(1, 1 + floor(P.density * 3 + P.complexity * 2))
            for k = 1, n do
              local t = sl.t0 + rng.range(0.5, max(0.6, sl.len - 0.5))
              if t < sl.t0 + sl.len - 0.2 then emit(t, rng.range(0.5, 1.5), rng.pick(list), 64 + rng.int(0, 18)) end
            end
          end
        end
      end
    else -------------------------------------------------- estilos ritmicos 1,3,5,6
      local gen, mut
      local sync = (style == 3) and 0.85 or 0.35
      if style == 6 then
        gen = function(b)
          if not st.motif or rng.chance(0.2) then
            st.motif = {}
            for _ = 1, rng.int(3, 6) do st.motif[#st.motif + 1] = rng.pick({ 0, 0, 0, 1, 2, 3, 4, -1, -2, 7 }) end
          end
          local o = Vc.onsets(ctx, b, 0.3 + P.density * 0.6, 0.55, rng, 1)
          local pat = {}
          for i, s in ipairs(o) do pat[i] = { s = s, deg = st.motif[(i - 1) % #st.motif + 1] } end
          return pat
        end
      else
        gen = function(b)
          local o = Vc.onsets(ctx, b, 0.15 + P.density * 0.75, sync, rng, (style == 3) and 1 or 2)
          local pat = {}
          for i, s in ipairs(o) do
            local role = "root"
            local x = rng.f()
            if s ~= 0 then
              if style == 3 then
                role = x < 0.35 and "root" or (x < 0.55 and "oct" or (x < 0.72 and "fifth" or (x < 0.88 and "seventh" or "pass")))
              elseif style == 5 then role = "pass"
              else
                role = x < 0.55 and "root" or (x < 0.7 and "fifth" or (x < 0.8 and "oct" or (x < 0.9 and "seventh" or "third")))
              end
            end
            pat[i] = { s = s, role = role, ghost = (style == 3 and s % 2 == 1 and rng.chance(0.4)) }
          end
          return pat
        end
      end
      mut = function(pat, b)
        for _, e in ipairs(pat) do
          if e.s ~= 0 and rng.chance(0.25) then e.role = rng.pick({ "root", "fifth", "oct", "third", "pass" }); e.deg = rng.pick({ 0, 1, 2, -1, 4 }) end
        end
        if rng.chance(0.4) then
          pat[#pat + 1] = { s = rng.int(1, b.steps - 1), role = "root" }
          table.sort(pat, function(a, c) return a.s < c.s end)
        end
        return pat
      end
      local pat = Vc.patternFor(st.pats, bar, rng, P, gen, mut)
      pat = U.copy(pat)
      for s in pairs(starts) do
        local found = false
        for _, e in ipairs(pat) do if e.s == s then e.role = "root"; e.deg = 0; found = true end end
        if not found then pat[#pat + 1] = { s = s, role = "root", deg = 0 } end
      end
      table.sort(pat, function(a, c) return a.s < c.s end)
      local sidx
      for i, e in ipairs(pat) do
        local t = bar.t0 + e.s / 4
        local chord = Hm.chordAt(ctx.plan, t)
        local list = Th.pitchList(chord.mask, lo, hi)
        local nxt = pat[i + 1] and pat[i + 1].s or bar.steps
        local len = (nxt - e.s) / 4
        local p, v = nil, 96
        if style == 6 then
          local ri = Th.nearestIdx(list, rootPitch(chord, lo + 3))
          p = list[Th.stepScale(list, ri, e.deg or 0)]
          v = e.s == 0 and 105 or 92
          emit(t, min(len, 1.0), p, v, { gate = 0.85 })
        elseif style == 5 then
          local strong = bar.w[e.s] >= 0.8
          if not sidx then sidx = Th.nearestIdx(list, rootPitch(chord, lo + 5)) end
          if starts[e.s] then sidx = Th.nearestIdx(list, rootPitch(chord, lo + 5))
          elseif strong then
            local tp = Vc.nearestChordTone(chord, list[clamp(sidx, 1, #list)], lo, hi)
            sidx = Th.nearestIdx(list, tp)
          else sidx = Th.stepScale(list, sidx, rng.pick({ -2, -1, -1, 0, 1, 1, 2 })) end
          emit(t, len, list[clamp(sidx, 1, #list)], strong and 100 or 84, { gate = 0.9 })
        else
          p = bassRole(chord, e.role, lo, hi, rng, list)
          if e.ghost then emit(t, 0.12, p, 34, { gate = 1 })
          else
            emit(t, len, p, e.s == 0 and 108 or 92, { gate = style == 3 and 0.55 or 0.92 })
            if style == 3 and rng.chance(P.complexity * 0.2) then
              emit(t + len * 0.5, 0.12, p + 12 > hi and p or p + 12, 40, { gate = 1 })
            end
          end
        end
      end
    end
  end
  return out
end

Ins.def { id = "bass", label = "Baixo", ch = 0, prog = 33, lo = 28, hi = 57,
  styles = { "Raiz / pedal", "Walking (jazz)", "Funk / slap sincopado", "Sub / 808 (segue o bumbo)",
    "Melodico (linha cantante)", "Ostinato (riff por escala)", "Modal / drone movel" },
  defaults = { density = 0.5, variation = 0.4, complexity = 0.4, octave = 0, vel = 0.82, gate = 0.9, lock = true },
  gen = genBass }
