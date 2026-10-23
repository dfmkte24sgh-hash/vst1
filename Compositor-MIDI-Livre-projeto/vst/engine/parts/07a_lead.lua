
----------------------------------------------------------------------------
-- MELODIA PRINCIPAL  (frase de 4 compassos: afirmar, repetir/variar, contrastar, cadenciar)
-- Pensa em ESCALA: a escala local do acorde e o campo de notas; os tons do acorde
-- so ancoram os tempos fortes (com liberdade controlada por "Liberdade de escala").
----------------------------------------------------------------------------
local function pentaMask(chord, blues)
  local minor = Th.inMask(chord.mask, chord.root + 3) and not Th.inMask(chord.mask, chord.root + 4)
  local rel = minor and { 0, 3, 5, 7, 10 } or { 0, 2, 4, 7, 9 }
  if blues and minor then rel[#rel + 1] = 6 end
  local m = 0
  for _, x in ipairs(rel) do m = m | (1 << ((chord.root + x) % 12)) end
  return m
end

-- estilos: densidade (mult), tamanho maximo (passos), prob. de pausa final, gerador de movimento
local LEAD_CFG = {
  { dens = 0.55, maxLen = 16, sync = 0.25, mv = function(rng, prev)
      if prev and abs(prev) >= 3 then return (prev > 0) and -1 or 1 end
      return rng.pick({ -1, -1, 1, 1, 0, -2, 2, 3, -3, 1, -1 }) end },
  { dens = 0.85, maxLen = 8, sync = 0.45, mv = function(rng) return rng.pick({ -2, -1, 0, 0, 1, 2, -3, 3, 1, -1, 4 }) end },
  { dens = 0.85, maxLen = 6, sync = 0.7, penta = true, mv = function(rng) return rng.pick({ 0, 1, -1, 2, -2, 1, 0, 3, -3 }) end },
  { dens = 0.6, maxLen = 8, sync = 0.6, mv = function(rng)
      local m = rng.pick({ 3, 4, 5, 6, 2, 4, 3 }); return rng.chance(0.5) and m or -m end },
  { dens = 0.5, maxLen = 2, sync = 0.7, mv = function(rng)
      local m = rng.int(1, 7); return rng.chance(0.5) and m or -m end },
  { dens = 0.8, maxLen = 4, sync = 0.35, cell = true, mv = function(rng) return 0 end },
}

local function genLead(ctx, P)
  local out, rng = {}, ctx.rng
  local lo, hi = Vc.reg(P, 60, 88)
  local style = clamp(P.style, 1, #LEAD_CFG)
  local cfg = LEAD_CFG[style]
  local G = ctx.G
  local snapProb = 1 - (G.scaleFreedom or 0.5) * 0.7
  local cur = round((lo + hi) / 2)
  local motif = nil -- {steps={}, moves={}}
  local cell = nil
  local prevMove
  local sh = ctx.shared
  sh.leadNotes = {}

  local function listFor(chord)
    local m = cfg.penta and pentaMask(chord, true) or chord.mask
    return Th.pitchList(m, lo, hi)
  end

  local function newMotif(bar, nOn)
    local ons = Vc.onsets(ctx, bar, clamp(0.1 + 0.55 * P.density * cfg.dens + 0.1, 0.08, 0.95), cfg.sync * (0.4 + P.complexity), rng, style == 5 and 3 or 1)
    local moves = {}
    for i = 1, #ons do
      if cfg.cell then
        cell = cell or {}
        if #cell < 3 or rng.chance(0.05) then
          cell = {}
          for k = 1, rng.int(3, 5) do cell[k] = rng.pick({ 1, 1, -1, 2, -1, 1, 0, -2 }) end
        end
        moves[i] = cell[(i - 1) % #cell + 1]
      else
        moves[i] = cfg.mv(rng, moves[i - 1])
      end
    end
    return { steps = ons, moves = moves }
  end

  for _, bar in ipairs(ctx.bars) do
    local pos = (bar.idx - 1) % 4 + 1
    local lastBar = (bar.idx == #ctx.bars)
    if pos == 1 or not motif then motif = newMotif(bar) end
    local steps, moves = U.copy(motif.steps), U.copy(motif.moves)
    -- ajusta o motivo a este compasso (outro compasso pode ter mais/menos passos)
    for i = #steps, 1, -1 do if steps[i] >= bar.steps then table.remove(steps, i); table.remove(moves, i) end end
    if #steps == 0 then steps, moves = { 0 }, { 0 } end
    local shiftDeg = 0
    if pos == 2 then
      shiftDeg = rng.pick({ 0, 1, -1, 2, -2 })
      if rng.chance(P.variation * 0.6) and #steps > 2 then
        local k = rng.int(2, #steps); steps[k] = clamp(steps[k] + rng.pick({ -1, 1 }), 1, bar.steps - 1)
      end
    elseif pos == 3 then
      if rng.chance(0.5 + 0.4 * P.variation) then
        for i = 1, #moves do moves[i] = -moves[i] end
      else
        local nm = newMotif(bar); steps, moves = nm.steps, nm.moves
      end
    elseif pos == 4 then
      if rng.chance(0.5) then
        local half = max(1, #steps // 2 + 1)
        for i = #steps, half + 1, -1 do table.remove(steps, i); table.remove(moves, i) end
      end
    end
    -- respiro: ultimos tempos livres em fim de semifrase
    local breath = false
    if (pos == 2 or pos == 3) and not lastBar and rng.chance(0.4 + 0.4 * (1 - P.density)) then
      breath = true
      local limit = floor(bar.steps * rng.range(0.45, 0.7))
      for i = #steps, 2, -1 do if steps[i] >= limit then table.remove(steps, i); table.remove(moves, i) end end
    end
    local idx
    for i, s in ipairs(steps) do
      local t = bar.t0 + s / 4
      local chord = Hm.chordAt(ctx.plan, t)
      local list = listFor(chord)
      idx = Th.nearestIdx(list, cur)
      local mv = moves[i]
      if i == 1 then mv = mv + shiftDeg end
      -- tendencia a voltar ao centro do registro
      if cur > hi - 4 and mv > 0 then mv = -abs(mv) elseif cur < lo + 4 and mv < 0 then mv = abs(mv) end
      idx = Th.stepScale(list, idx, mv)
      local p = list[idx]
      local strong = bar.w[s] >= 0.8
      local last = (i == #steps)
      if (strong or (last and (pos == 4 or lastBar))) and rng.chance(snapProb) then
        p = Vc.nearestChordTone(chord, p, lo, hi)
      end
      if lastBar and last then p = Vc.nearestChordTone({ root = ctx.G.key, ivs = { 0, 4, 7 } }, p, lo, hi) end
      cur = p
      local nxt = steps[i + 1] or bar.steps
      local len = min((nxt - s), cfg.maxLen)
      if last and (pos == 4 or lastBar) then len = max(len, min(bar.steps - s, 8)) end
      if breath and last then len = min(len, max(2, round(bar.steps * 0.16))) end
      local lenQN = len / 4
      local vel = 70 + 28 * bar.w[s] + (pos == 1 and 4 or 0) + rng.int(-4, 4)
      -- ornamentos: nota de aproximacao cromatica e trilos
      if strong and rng.chance(P.complexity * (G.chroma or 0.3) * 0.5) and s > 0 then
        Vc.add(out, ctx, P, t - 0.1, 0.1, p - 1, 58, { gate = 1, noSwing = true })
      elseif rng.chance(P.complexity * 0.12) and style ~= 5 then
        local gl = list[Th.stepScale(list, idx, rng.pick({ -1, 1 }))]
        Vc.add(out, ctx, P, t - 0.08, 0.08, gl, 56, { gate = 1, noSwing = true })
      end
      Vc.add(out, ctx, P, t, lenQN, p, vel, { gate = (style == 5) and 0.5 or P.gate })
      local note = out[#out]
      if note then sh.leadNotes[#sh.leadNotes + 1] = note; Vc.mark(sh.lead, note.t, note.l) end
      if lenQN >= 1.5 and rng.chance(P.complexity * 0.18) and style ~= 5 then
        local up = list[Th.stepScale(list, idx, 1)]
        local tt = t + lenQN * 0.5
        local k = 0
        while tt < t + lenQN - 0.1 and k < 8 do
          Vc.add(out, ctx, P, tt, 0.12, (k % 2 == 0) and up or p, 62, { gate = 1, noSwing = true })
          tt = tt + 0.125
          k = k + 1
        end
      end
      prevMove = mv
    end
  end
  return out
end

Ins.def { id = "lead", label = "Melodia principal", ch = 5, prog = 73, lo = 55, hi = 96,
  styles = { "Cantabile (lirica)", "Motivica (desenvolvimento)", "Pentatonica / blues (riffs)",
    "Moderna (saltos largos)", "Pontilhista (staccato)", "Celula modal (repetida)" },
  defaults = { density = 0.5, variation = 0.45, complexity = 0.45, vel = 0.82, gate = 0.9, seedOff = 53 },
  gen = genLead }

----------------------------------------------------------------------------
-- SEGUNDA VOZ / CONTRACANTO (usa a melodia principal como referencia)
----------------------------------------------------------------------------
local function genCounter(ctx, P)
  local out, rng = {}, ctx.rng
  local lo, hi = Vc.reg(P, 52, 84)
  local style = P.style
  local sh = ctx.shared
  local lead = sh.leadNotes or {}
  local function wideList(chord) return Th.pitchList(chord.mask, 24, 108) end
  local function fit(p)
    while p > hi do p = p - 12 end
    while p < lo do p = p + 12 end
    return p
  end

  if style == 1 then -- harmonia paralela (tercas/sextas na escala)
    local interval = rng.pick({ 2, 2, 5, -2 })
    for i, n in ipairs(lead) do
      if (n.l >= 0.4 or rng.chance(0.3)) and rng.chance(0.55 + 0.45 * P.density) then
        local chord = Hm.chordAt(ctx.plan, n.t)
        local list = wideList(chord)
        local idx = Th.nearestIdx(list, n.p)
        local p = list[Th.stepScale(list, idx, -interval)]
        if rng.chance(P.complexity * 0.2) then p = list[Th.stepScale(list, idx, -(interval + 2))] end
        Vc.add(out, ctx, P, n.t, n.l / max(P.gate, 0.1), fit(p), n.v * 0.82, { gate = P.gate, noSwing = true })
      end
    end
  elseif style == 2 then -- resposta nos vazios
    local state, idxp = nil, nil
    for _, bar in ipairs(ctx.bars) do
      local s = 0
      while s < bar.steps do
        local abs0 = round((bar.t0 + s / 4) * 4)
        if not sh.lead[abs0] then
          local e = s
          while e < bar.steps and not sh.lead[round((bar.t0 + e / 4) * 4)] do e = e + 1 end
          local gap = e - s
          if gap >= 2 and rng.chance(0.35 + 0.6 * P.density) then
            local t = bar.t0 + s / 4
            local chord = Hm.chordAt(ctx.plan, t)
            local list = Th.pitchList(chord.mask, lo, hi)
            local i = idxp or Th.nearestIdx(list, Vc.nearestChordTone(chord, round((lo + hi) / 2), lo, hi))
            local n = clamp(rng.int(2, 3 + floor(P.complexity * 3)), 2, gap)
            local dir = rng.pick({ 1, -1 })
            local pos = s
            for k = 1, n do
              if pos >= e then break end
              local ln = (k == n) and (e - pos) or max(1, rng.int(1, max(1, (gap // n))))
              Vc.add(out, ctx, P, bar.t0 + pos / 4, min(ln, 6) / 4, list[clamp(i, 1, #list)], 70 + rng.int(-4, 8), { gate = P.gate })
              i = Th.stepScale(list, i, dir * rng.pick({ 1, 1, 2 }))
              if rng.chance(0.3) then dir = -dir end
              pos = pos + ln
            end
            idxp = i
          end
          s = e
        else s = s + 1 end
      end
    end
  elseif style == 3 then -- movimento contrario
    local prevLead, prevC
    for _, n in ipairs(lead) do
      local chord = Hm.chordAt(ctx.plan, n.t)
      local bar = Mt.barAt(ctx.bars, n.t)
      local st = round((n.t - bar.t0) * 4)
      local strongish = bar.w[min(st, bar.steps - 1)] >= 0.55
      if strongish and rng.chance(0.45 + 0.5 * P.density) then
        local list = Th.pitchList(chord.mask, lo, hi)
        local p
        if prevLead and prevC then
          local dir = (n.p > prevLead) and -1 or ((n.p < prevLead) and 1 or 0)
          local i = Th.nearestIdx(list, prevC)
          p = list[Th.stepScale(list, i, dir * rng.pick({ 1, 2 }))]
        else p = Vc.nearestChordTone(chord, lo + 8, lo, hi) end
        if bar.w[min(st, bar.steps - 1)] >= 0.8 then p = Vc.nearestChordTone(chord, p, lo, hi) end
        Vc.add(out, ctx, P, n.t, max(n.l * 1.5, 0.5), p, n.v * 0.8, { gate = P.gate })
        prevC = p
      end
      prevLead = n.p
    end
  elseif style == 4 then -- pedal / ostinato agudo
    for _, bar in ipairs(ctx.bars) do
      local k = clamp(round(bar.steps * (0.2 + 0.4 * P.density)), 2, bar.steps)
      local e = Mt.euclid(k, bar.steps, floor(bar.idx * P.variation * 3) % bar.steps)
      for s = 0, bar.steps - 1 do
        if e[s] then
          local t = bar.t0 + s / 4
          local chord = Hm.chordAt(ctx.plan, t)
          local base = Vc.nearestChordTone(chord, hi - 7, lo, hi)
          if P.complexity > 0.6 and rng.chance(0.25) then base = Vc.nearestChordTone(chord, hi - 12, lo, hi) end
          Vc.add(out, ctx, P, t, 0.2, base, 62 + 24 * bar.w[s], { gate = 1 })
        end
      end
    end
  else -- 5: eco / canone (imita a melodia depois de um tempo, transposta na escala)
    local delay = rng.pick({ 0.75, 1, 1.5, 2 })
    local shiftDeg = rng.pick({ -2, 2, -4, 0, 4 })
    for _, n in ipairs(lead) do
      if rng.chance(0.6 + 0.4 * P.density) then
        local t = n.t + delay
        if t < ctx.total - 0.1 then
          local chord = Hm.chordAt(ctx.plan, t)
          local list = Th.pitchList(chord.mask, 24, 108)
          local p = list[Th.stepScale(list, Th.nearestIdx(list, n.p), shiftDeg)]
          Vc.add(out, ctx, P, t, n.l, fit(p), n.v * 0.7, { gate = P.gate, noSwing = true })
        end
      end
    end
  end
  return out
end

Ins.def { id = "counter", label = "Segunda voz / contracanto", ch = 6, prog = 40, lo = 48, hi = 90,
  styles = { "Harmonia paralela (tercas/sextas)", "Resposta nos vazios", "Movimento contrario",
    "Pedal / ostinato agudo", "Eco / canone" },
  defaults = { density = 0.55, variation = 0.4, complexity = 0.4, vel = 0.7, gate = 0.9, seedOff = 67 },
  gen = genCounter }
