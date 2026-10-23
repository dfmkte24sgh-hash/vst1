
----------------------------------------------------------------------------
-- compassos e ritmo (a grade interna e sempre de semicolcheias = 0.25 tempo)
----------------------------------------------------------------------------
-- {nome, numerador, denominador, agrupamento (em unidades do denominador)}
Mt.PRESETS = {
  { "4/4", 4, 4, { 2, 2 } }, { "3/4", 3, 4, { 3 } }, { "2/4", 2, 4, { 2 } },
  { "5/4", 5, 4, { 3, 2 } }, { "6/4", 6, 4, { 3, 3 } }, { "7/4", 7, 4, { 4, 3 } },
  { "6/8", 6, 8, { 3, 3 } }, { "9/8", 9, 8, { 3, 3, 3 } }, { "12/8", 12, 8, { 3, 3, 3, 3 } },
  { "5/8", 5, 8, { 3, 2 } }, { "7/8", 7, 8, { 2, 2, 3 } }, { "11/8", 11, 8, { 3, 3, 3, 2 } },
  { "3/8", 3, 8, { 3 } }, { "Personalizado", 4, 4, nil },
}
function Mt.presetNames()
  local t = {}
  for i, p in ipairs(Mt.PRESETS) do t[i] = p[1] end
  return t
end

function Mt.autoGroups(num)
  local g, n = {}, num
  while n > 4 do g[#g + 1] = 3; n = n - 3 end
  if n == 4 then g[#g + 1] = 2; g[#g + 1] = 2
  elseif n > 0 then g[#g + 1] = n end
  return g
end

-- cria um compasso. t0 em tempos (seminimas). alt inverte o agrupamento.
function Mt.makeBar(num, den, groups, alt, t0, idx)
  groups = groups or Mt.autoGroups(num)
  if alt then
    local rg = {}
    for i = #groups, 1, -1 do rg[#rg + 1] = groups[i] end
    groups = rg
  end
  local unit = 16 // den
  if unit < 1 then unit = 1 end
  local steps = num * unit
  local gs, pos = {}, 0
  local gstart = { [0] = true }
  for _, g in ipairs(groups) do
    gs[#gs + 1] = g * unit
    pos = pos + g * unit
    if pos < steps then gstart[pos] = true end
  end
  local w = {}
  for s = 0, steps - 1 do
    if s == 0 then w[s] = 1.0
    elseif gstart[s] then w[s] = 0.8
    elseif s % unit == 0 then w[s] = 0.55
    elseif s % 2 == 0 then w[s] = 0.35
    else w[s] = 0.2 end
  end
  return { idx = idx, t0 = t0, len = steps / 4, steps = steps, beatSteps = unit, num = num, den = den,
           groups = gs, gstart = gstart, w = w, name = num .. "/" .. den }
end

function Mt.parseSeq(str)
  local out = {}
  for a, b in tostring(str or ""):gmatch("(%d+)%s*/%s*(%d+)") do
    a, b = tonumber(a), tonumber(b)
    if a >= 1 and a <= 32 and (b == 2 or b == 4 or b == 8 or b == 16) then out[#out + 1] = { a, b } end
  end
  return out
end

-- monta a lista de compassos de toda a peca
function Mt.buildBars(G)
  local bars, t = {}, 0
  local seq = Mt.parseSeq(G.meterSeq)
  local pre = Mt.PRESETS[G.meterIdx] or Mt.PRESETS[1]
  local num, den, groups = pre[2], pre[3], pre[4]
  if pre[1] == "Personalizado" then num, den, groups = G.customNum, G.customDen, nil end
  for i = 1, G.bars do
    local n, d, g = num, den, groups
    if #seq > 0 then
      local s = seq[(i - 1) % #seq + 1]
      n, d = s[1], s[2]
      g = nil
      for _, p in ipairs(Mt.PRESETS) do if p[2] == n and p[3] == d and p[4] then g = p[4] end end
    end
    local b = Mt.makeBar(n, d, g, G.altGroup, t, i)
    bars[i] = b
    t = t + b.len
  end
  return bars, t
end

function Mt.barAt(bars, t)
  for i = #bars, 1, -1 do if t >= bars[i].t0 - 1e-6 then return bars[i] end end
  return bars[1]
end

-- euclidiano: k pulsos em n passos com rotacao
function Mt.euclid(k, n, rot)
  local p = {}
  for i = 0, n - 1 do p[i] = false end
  if k <= 0 then return p end
  k = min(k, n)
  local acc = 0
  for i = 0, n - 1 do
    acc = acc + k
    if acc >= n then acc = acc - n; p[(i + (rot or 0)) % n] = true end
  end
  return p
end

-- probabilidade de ataque num passo, combinando peso metrico, densidade, sincopa e tap
-- ctx.tapProfile (opcional) = {len=N, w={[0..N-1]=0..1}} e ctx.G.tapInfluence
function Mt.onsetProb(ctx, bar, s, density, syncopation)
  local w = bar.w[s]
  local base
  if w >= 0.8 then base = 0.55 + 0.45 * density
  elseif w >= 0.5 then base = 0.15 + 0.85 * density
  elseif w >= 0.3 then base = 0.55 * density * density + 0.05 + 0.35 * density * (syncopation or 0.3)
  else base = 0.5 * density * density * (0.4 + (syncopation or 0.3)) end
  local tp = ctx.tapProfile
  local inf = ctx.G.tapInfluence or 0
  if tp and inf > 0 then
    local tw = tp.w[s % tp.len] or 0
    base = base * (1 - inf) + (tw * 0.95 + 0.02) * inf
  end
  return clamp(base, 0, 1)
end

-- aplica swing a um tempo (em seminimas). amt 0..1 ; grade: 8 (colcheias) ou 16
function Mt.swing(t, amt, grid)
  if amt <= 0 then return t end
  local frac = t % 1
  if grid == 16 then
    local k = floor(frac * 4 + 0.001)
    if k % 2 == 1 and abs(frac * 4 - k) < 0.01 then return t + amt * (1 / 12) end
  else
    if abs(frac - 0.5) < 0.01 then return t + amt * (1 / 6) end
  end
  return t
end
