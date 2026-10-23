
----------------------------------------------------------------------------
-- ferramentas comuns aos instrumentos: voicings, emissao de notas, padroes
----------------------------------------------------------------------------
-- registro efetivo (aplica o deslocamento de oitava do instrumento)
function Vc.reg(P, lo, hi)
  local o = (P.octave or 0) * 12
  return clamp(lo + o, 0, 127), clamp(hi + o, 0, 127)
end

-- adiciona uma nota aplicando velocidade, swing, humanizacao, legato e limite do fim
function Vc.add(out, ctx, P, t, len, pitch, vel, opts)
  opts = opts or {}
  local G = ctx.G
  pitch = clamp(round(pitch), 0, 127)
  local bar = Mt.barAt(ctx.bars, t)
  local en = bar.energy or 1
  local hum = (G.humanize or 0) * (P.human or 1)
  if not opts.noSwing then
    local sw = opts.swingAmt or ((G.swing or 0) * (P.swing or 1))
    t = Mt.swing(t, sw, opts.swingGrid or G.swingGrid or 8)
  end
  t = max(0, t + ctx.rng.gauss() * hum * 0.012)
  local g = opts.gate or P.gate or 0.9
  local l = max(0.06, len * g)
  if t + l > ctx.total then l = max(0.05, ctx.total - t) end
  if t >= ctx.total then return end
  local fac = (P.vel or 0.8) / 0.8
  local v = vel * fac * (0.62 + 0.38 * en) + ctx.rng.gauss() * hum * 5
  v = clamp(round(v), 1, 127)
  out[#out + 1] = { t = t, l = l, p = pitch, v = v }
end

function Vc.cc(ctx, t, num, val)
  ctx.ccOut[#ctx.ccOut + 1] = { t = max(0, t), cc = num, val = clamp(round(val), 0, 127) }
end

-- rampa de CC (swell de expressao) de t0 a t1
function Vc.ccRamp(ctx, t0, t1, num, v0, v1, step)
  step = step or 0.5
  local n = max(1, floor((t1 - t0) / step))
  for i = 0, n do
    local x = i / n
    Vc.cc(ctx, t0 + (t1 - t0) * x, num, lerp(v0, v1, x))
  end
end

-- voicing por conducao de vozes: um tom do acorde por voz dentro de [lo,hi]
function Vc.voice(chord, lo, hi, prev, opts)
  opts = opts or {}
  local pcs, seen = {}, {}
  for i, iv in ipairs(chord.ivs) do
    local pc = (chord.root + iv) % 12
    if not seen[pc] and not (opts.noRoot and i == 1) then
      seen[pc] = true
      pcs[#pcs + 1] = pc
    end
  end
  if opts.max and #pcs > opts.max then
    local fifth = (chord.root + 7) % 12
    for i = #pcs, 1, -1 do
      if #pcs > opts.max and pcs[i] == fifth and #pcs > 3 then table.remove(pcs, i) end
    end
    while #pcs > opts.max do table.remove(pcs, #pcs) end
  end
  local n = #pcs
  local out, used = {}, {}
  for i, pc in ipairs(pcs) do
    local target
    if prev and #prev > 0 then
      target = prev[clamp(round((i - 1) / max(n - 1, 1) * (#prev - 1)) + 1, 1, #prev)]
    else
      local span = (hi - lo) * (opts.spread or 1)
      target = lo + span * (i - 0.5) / n
    end
    local best, bd = nil, 1e9
    for p = lo, hi do
      if p % 12 == pc and not used[p] then
        local d = abs(p - target)
        if d < bd then best, bd = p, d end
      end
    end
    if best then out[#out + 1] = best; used[best] = true end
  end
  table.sort(out)
  return out
end

-- empilha um acorde "fechado" a partir de um topo (naipes, cordas)
function Vc.closeBelow(chord, top, n, mask)
  local pcs = Th.chordPcs(chord)
  local out = {}
  local p = top
  local guard = 0
  while #out < n and guard < 60 do
    guard = guard + 1
    local ok = false
    for _, pc in ipairs(pcs) do if p % 12 == pc then ok = true break end end
    if ok then table.insert(out, 1, p) end
    p = p - 1
  end
  return out
end

-- voicing de violao: da corda grave para a aguda
function Vc.guitar(chord, nStrings, power)
  local pcs = Th.chordPcs(chord)
  local root = chord.root
  local fifth = (root + 7) % 12
  local pri = { root }
  local has5 = false
  for _, pc in ipairs(pcs) do if pc == fifth then has5 = true end end
  if has5 then pri[#pri + 1] = fifth end
  if power then pri = { root, fifth } else
    for _, pc in ipairs(pcs) do
      if pc ~= root and pc ~= fifth then pri[#pri + 1] = pc end
    end
    if has5 then pri[#pri + 1] = fifth end
    pri[#pri + 1] = root
  end
  local out = {}
  local prev = 39
  local lowest = 40
  for i = 1, nStrings do
    local pc = pri[(i - 1) % #pri + 1]
    local p = (i == 1) and lowest or (prev + 2)
    while p % 12 ~= pc do p = p + 1 end
    if i > 1 and p - prev > 9 then
      -- tenta uma nota de acorde mais proxima
      for _, c in ipairs(pcs) do
        local q = prev + 1
        while q % 12 ~= c do q = q + 1 end
        if q < p then p = q end
      end
    end
    if p > 79 then break end
    out[#out + 1] = p
    prev = p
  end
  return out
end

-- onde ha ataques num compasso (lista de passos)
function Vc.onsets(ctx, bar, density, sync, rng, minGap)
  local list, last = {}, -99
  for s = 0, bar.steps - 1 do
    local p = Mt.onsetProb(ctx, bar, s, density, sync)
    if s >= last + (minGap or 1) and rng.chance(p) then
      list[#list + 1] = s
      last = s
    end
  end
  if #list == 0 then list[1] = 0 end
  return list
end

-- padrao por compasso com memoria: repete a base e muta conforme "variacao"
function Vc.patternFor(state, bar, rng, P, gen, mutate)
  local key = bar.name .. ":" .. #bar.groups
  local b = state[key]
  local pat
  if not b then
    pat = gen(bar)
    state[key] = pat
  else
    if rng.chance((P.variation or 0.5) * 0.65) then
      pat = mutate and mutate(U.copy(b), bar) or gen(bar)
    else pat = b end
    if rng.chance((P.variation or 0.5) * 0.15) then state[key] = pat end
  end
  return pat
end

-- fim de frase? (a cada 4 compassos e no ultimo)
function Vc.phraseEnd(ctx, bar)
  return bar.idx % 4 == 0 or bar.idx == #ctx.bars
end

-- tom (altura) mais proximo de uma meta dentro das notas de acorde
function Vc.nearestChordTone(chord, target, lo, hi)
  local best, bd = nil, 1e9
  for p = lo, hi do
    for _, iv in ipairs(chord.ivs) do
      if p % 12 == (chord.root + iv) % 12 then
        local d = abs(p - target)
        if d < bd then best, bd = p, d end
      end
    end
  end
  return best or clamp(target, lo, hi)
end

function Vc.isChordTone(chord, p)
  for _, iv in ipairs(chord.ivs) do if p % 12 == (chord.root + iv) % 12 then return true end end
  return false
end

-- ocupacao compartilhada entre instrumentos (por semicolcheia absoluta)
function Vc.mark(tbl, t, len)
  local a, z = round(t * 4), max(round(t * 4), round((t + len) * 4) - 1)
  for s = a, z do tbl[s] = true end
end
