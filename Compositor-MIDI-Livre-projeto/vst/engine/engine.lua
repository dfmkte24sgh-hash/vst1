--[[
  COMPOSITOR MIDI LIVRE  -  script para REAPER (ReaScript Lua + ReaImGui)

  O que faz: gera linhas de MIDI para varios instrumentos (bateria, baixo, teclas,
  cordas, arpejo, melodia, segunda voz, violao, metais, madeiras, mallets e
  atmosfera). A harmonia e pensada em ESCALAS (tonal, modal, experimental ou
  hibrida), nao em padroes prontos. Aceita varios compassos, tap de BPM + ritmo e
  descricao em texto da intencao musical.

  Requisitos: REAPER 6.x/7.x + extensao ReaImGui (ReaPack > ReaTeam Extensions).
  Instalar: Actions > Show action list > New action > Load ReaScript > este arquivo.
]]
local r = reaper
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

-- espacos de nome (evita estourar o limite de 200 locals do Lua)
local U, Th, Mt, Hm, Vc, Ins, Tx, Tp, Wr, Ui, Cp = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}

----------------------------------------------------------------------------
-- utilidades
----------------------------------------------------------------------------
function U.clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
function U.lerp(a, b, t) return a + (b - a) * t end
function U.round(x) return floor(x + 0.5) end
local clamp, lerp, round = U.clamp, U.lerp, U.round

function U.hashStr(s)
  local h = 5381
  for i = 1, #s do h = ((h * 33) ~ s:byte(i)) & 0x7fffffff end
  return h
end

-- gerador pseudo-aleatorio deterministico (xorshift32): mesma semente = mesma musica
function U.newRng(seed)
  seed = floor(seed) & 0x7fffffff
  local s = (seed * 2654435761 + 40503) & 0xffffffff
  if s == 0 then s = 2463534242 end
  local R = {}
  local function nxt()
    s = s ~ ((s << 13) & 0xffffffff)
    s = s ~ (s >> 17)
    s = s ~ ((s << 5) & 0xffffffff)
    return s
  end
  for _ = 1, 8 do nxt() end
  function R.f() return nxt() / 4294967296 end
  function R.int(a, b) return a + floor(R.f() * (b - a + 1)) end
  function R.chance(p) return R.f() < p end
  function R.pick(t) return t[R.int(1, #t)] end
  function R.range(a, b) return a + (b - a) * R.f() end
  function R.gauss() return (R.f() + R.f() + R.f() + R.f() - 2) * 1.732 end
  function R.weighted(items, weights)
    local tot = 0
    for i = 1, #items do tot = tot + weights[i] end
    if tot <= 0 then return items[R.int(1, #items)] end
    local x = R.f() * tot
    for i = 1, #items do
      x = x - weights[i]
      if x <= 0 then return items[i] end
    end
    return items[#items]
  end
  function R.shuffle(t)
    for i = #t, 2, -1 do
      local j = R.int(1, i)
      t[i], t[j] = t[j], t[i]
    end
    return t
  end
  return R
end

function U.copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = U.copy(v) end
  return o
end

-- serializacao simples (numeros, strings, booleanos, tabelas) para salvar ajustes
function U.serialize(v)
  local t = type(v)
  if t == "number" then return tostring(v)
  elseif t == "boolean" then return v and "true" or "false"
  elseif t == "string" then return string.format("%q", v)
  elseif t == "table" then
    local parts = {}
    for k, x in pairs(v) do
      local ks = type(k) == "string" and string.format("[%q]", k) or "[" .. tostring(k) .. "]"
      parts[#parts + 1] = ks .. "=" .. U.serialize(x)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end
function U.deserialize(s)
  if not s or s == "" then return nil end
  local f = load("return " .. s, "state", "t", {})
  if not f then return nil end
  local ok, res = pcall(f)
  return ok and res or nil
end

----------------------------------------------------------------------------
-- teoria: escalas, mascaras de notas, listas de alturas
----------------------------------------------------------------------------
Th.NOTE_NAMES = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }

-- {nome, intervalos, familias}  t=tonal  m=modal  x=experimental
Th.SCALES = {
  { "Maior (Jonio)", { 0, 2, 4, 5, 7, 9, 11 }, "t" },
  { "Menor Natural (Eolio)", { 0, 2, 3, 5, 7, 8, 10 }, "tm" },
  { "Dorico", { 0, 2, 3, 5, 7, 9, 10 }, "m" },
  { "Frigio", { 0, 1, 3, 5, 7, 8, 10 }, "m" },
  { "Lidio", { 0, 2, 4, 6, 7, 9, 11 }, "m" },
  { "Mixolidio", { 0, 2, 4, 5, 7, 9, 10 }, "tm" },
  { "Locrio", { 0, 1, 3, 5, 6, 8, 10 }, "mx" },
  { "Menor Harmonica", { 0, 2, 3, 5, 7, 8, 11 }, "t" },
  { "Menor Melodica", { 0, 2, 3, 5, 7, 9, 11 }, "tx" },
  { "Dorico b2", { 0, 1, 3, 5, 7, 9, 10 }, "m" },
  { "Lidio Aumentado", { 0, 2, 4, 6, 8, 9, 11 }, "mx" },
  { "Lidio Dominante", { 0, 2, 4, 6, 7, 9, 10 }, "mx" },
  { "Mixolidio b6", { 0, 2, 4, 5, 7, 8, 10 }, "mx" },
  { "Locrio Natural 2", { 0, 2, 3, 5, 6, 8, 10 }, "mx" },
  { "Alterada", { 0, 1, 3, 4, 6, 8, 10 }, "x" },
  { "Frigio Dominante", { 0, 1, 4, 5, 7, 8, 10 }, "mx" },
  { "Hungara Menor", { 0, 2, 3, 6, 7, 8, 11 }, "x" },
  { "Dupla Harmonica", { 0, 1, 4, 5, 7, 8, 11 }, "x" },
  { "Tons Inteiros", { 0, 2, 4, 6, 8, 10 }, "x" },
  { "Octatonica T-S", { 0, 2, 3, 5, 6, 8, 9, 11 }, "x" },
  { "Octatonica S-T", { 0, 1, 3, 4, 6, 7, 9, 10 }, "x" },
  { "Pentatonica Maior", { 0, 2, 4, 7, 9 }, "t" },
  { "Pentatonica Menor", { 0, 3, 5, 7, 10 }, "t" },
  { "Blues", { 0, 3, 5, 6, 7, 10 }, "t" },
  { "Hirajoshi", { 0, 2, 3, 7, 8 }, "x" },
  { "In-Sen", { 0, 1, 5, 7, 10 }, "x" },
  { "Iwato", { 0, 1, 5, 6, 10 }, "x" },
  { "Prometeu", { 0, 2, 4, 6, 9, 10 }, "x" },
  { "Enigmatica", { 0, 1, 4, 6, 8, 10, 11 }, "x" },
  { "Napolitana Menor", { 0, 1, 3, 5, 7, 8, 11 }, "x" },
  { "Bebop Dominante", { 0, 2, 4, 5, 7, 9, 10, 11 }, "t" },
  { "Lidio #2", { 0, 3, 4, 6, 7, 9, 11 }, "x" },
  { "Maior Harmonica", { 0, 2, 4, 5, 7, 8, 11 }, "t" },
  { "Cromatica (livre)", { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }, "" },
}
Th.SCALE_IDX = {}
for i, s in ipairs(Th.SCALES) do Th.SCALE_IDX[s[1]] = i end
function Th.scaleNames()
  local t = {}
  for i, s in ipairs(Th.SCALES) do t[i] = s[1] end
  return t
end
function Th.famPool(f)
  local t = {}
  for i, s in ipairs(Th.SCALES) do if s[3]:find(f, 1, true) then t[#t + 1] = i end end
  return t
end
function Th.maskOf(iv, rootPc)
  local m = 0
  for _, x in ipairs(iv) do m = m | (1 << ((x + rootPc) % 12)) end
  return m
end
function Th.inMask(m, pc) return ((m >> (pc % 12)) & 1) == 1 end
function Th.maskCount(m)
  local c = 0
  for i = 0, 11 do if (m >> i) & 1 == 1 then c = c + 1 end end
  return c
end

local plCache = {}
function Th.pitchList(mask, lo, hi)
  local key = mask * 1000000 + lo * 1000 + hi
  local l = plCache[key]
  if l then return l end
  l = {}
  for p = lo, hi do if Th.inMask(mask, p) then l[#l + 1] = p end end
  if #l == 0 then l[1] = lo end
  plCache[key] = l
  return l
end
function Th.nearestIdx(list, p)
  local best, bd = 1, 1e9
  for i = 1, #list do
    local d = abs(list[i] - p)
    if d < bd then best, bd = i, d end
  end
  return best
end
-- move n graus dentro da escala (n pode ser negativo)
function Th.stepScale(list, idx, n) return clamp(idx + n, 1, #list) end
-- ajusta uma altura para a nota mais proxima dentro da mascara
function Th.snap(p, mask)
  if Th.inMask(mask, p) then return p end
  for d = 1, 6 do
    if Th.inMask(mask, p - d) then return p - d end
    if Th.inMask(mask, p + d) then return p + d end
  end
  return p
end

----------------------------------------------------------------------------
-- acordes: estrutura {root=pc, ivs={semitons a partir da raiz}, mask=escala local}
----------------------------------------------------------------------------
Th.QUALS = {
  { "", { 0, 4, 7 } }, { "m", { 0, 3, 7 } }, { "dim", { 0, 3, 6 } }, { "aug", { 0, 4, 8 } },
  { "sus2", { 0, 2, 7 } }, { "sus4", { 0, 5, 7 } }, { "5", { 0, 7 } },
  { "maj7", { 0, 4, 7, 11 } }, { "7", { 0, 4, 7, 10 } }, { "m7", { 0, 3, 7, 10 } },
  { "m7b5", { 0, 3, 6, 10 } }, { "dim7", { 0, 3, 6, 9 } }, { "mMaj7", { 0, 3, 7, 11 } },
  { "6", { 0, 4, 7, 9 } }, { "m6", { 0, 3, 7, 9 } }, { "add9", { 0, 2, 4, 7 } },
  { "madd9", { 0, 2, 3, 7 } }, { "maj9", { 0, 2, 4, 7, 11 } }, { "9", { 0, 2, 4, 7, 10 } },
  { "m9", { 0, 2, 3, 7, 10 } }, { "7sus4", { 0, 5, 7, 10 } }, { "7b9", { 0, 1, 4, 7, 10 } },
  { "7#9", { 0, 3, 4, 7, 10 } }, { "7#11", { 0, 4, 6, 7, 10 } }, { "maj7#11", { 0, 4, 6, 7, 11 } },
  { "m11", { 0, 2, 3, 5, 7, 10 } }, { "13", { 0, 2, 4, 7, 9, 10 } }, { "7b5", { 0, 4, 6, 10 } },
  { "7#5", { 0, 4, 8, 10 } }, { "quartal", { 0, 5, 10 } }, { "maj7b5", { 0, 4, 6, 11 } },
  { "m(maj9)", { 0, 2, 3, 7, 11 } }, { "m6/9", { 0, 2, 3, 7, 9 } }, { "6/9", { 0, 2, 4, 7, 9 } },
  { "7alt", { 0, 1, 4, 6, 10 } }, { "m7b9", { 0, 1, 3, 7, 10 } },
}
for _, q in ipairs(Th.QUALS) do
  local m = 0
  for _, x in ipairs(q[2]) do m = m | (1 << (x % 12)) end
  q.mask = m
end

function Th.chordName(root, ivs)
  local m = 0
  for _, x in ipairs(ivs) do m = m | (1 << (x % 12)) end
  local rn = Th.NOTE_NAMES[root + 1]
  for _, q in ipairs(Th.QUALS) do if q.mask == m then return rn .. q[1] end end
  local best, bc = nil, -1
  for _, q in ipairs(Th.QUALS) do
    if (q.mask & m) == q.mask then
      local c = Th.maskCount(q.mask)
      if c > bc then best, bc = q, c end
    end
  end
  if best then
    local ex = {}
    for i = 0, 11 do
      if (m >> i) & 1 == 1 and (best.mask >> i) & 1 == 0 then ex[#ex + 1] = tostring(i) end
    end
    return rn .. best[1] .. "(+" .. table.concat(ex, ",") .. ")"
  end
  return rn .. "(cluster)"
end

function Th.chordPcs(ch)
  local out, seen = {}, {}
  for _, iv in ipairs(ch.ivs) do
    local pc = (ch.root + iv) % 12
    if not seen[pc] then seen[pc] = true; out[#out + 1] = pc end
  end
  return out
end
function Th.chordMask(ch)
  local m = 0
  for _, iv in ipairs(ch.ivs) do m = m | (1 << ((ch.root + iv) % 12)) end
  return m
end
function Th.makeChord(root, ivs, scaleMask, scaleName, kind, name)
  root = root % 12
  local ch = { root = root, ivs = ivs, mask = scaleMask, scaleName = scaleName or "?", kind = kind or "t" }
  ch.name = name or Th.chordName(root, ivs)
  return ch
end

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

----------------------------------------------------------------------------
-- harmonia: cada acorde carrega a sua ESCALA LOCAL (mask). Os instrumentos
-- melodicos pensam na escala; os acordes sao apenas "ancoras" dentro dela.
----------------------------------------------------------------------------
local ceil = math.ceil

-- ---- ritmo harmonico: onde os acordes trocam -------------------------------
local function groupStarts(b)
  local t = {}
  for s in pairs(b.gstart) do t[#t + 1] = s end
  table.sort(t)
  return t
end
local function halfCut(b, rng)
  local gs = groupStarts(b)
  if #gs >= 2 then
    if rng and rng.chance(0.4) then return { 0, gs[rng.int(2, #gs)] } end
    local best, bd = gs[2], 1e9
    for i = 2, #gs do
      local d = abs(gs[i] - b.steps / 2)
      if d < bd then best, bd = gs[i], d end
    end
    return { 0, best }
  end
  local c = max(b.beatSteps, round(b.steps / 2 / b.beatSteps) * b.beatSteps)
  if c >= b.steps then return { 0 } end
  return { 0, c }
end
local function thirdCuts(b)
  local u = b.beatSteps
  local c1 = round(b.steps / 3 / u) * u
  local c2 = round(2 * b.steps / 3 / u) * u
  if c1 > 0 and c2 > c1 and c2 < b.steps then return { 0, c1, c2 } end
  return halfCut(b)
end
local function pulseCuts(b)
  if b.den >= 8 then return groupStarts(b) end
  local t = {}
  for s = 0, b.steps - 1, b.beatSteps do t[#t + 1] = s end
  return t
end

function Hm.slots(bars, G, rng)
  local out = {}
  local function add(t0, len, bi) out[#out + 1] = { t0 = t0, len = len, bar = bi } end
  local i = 1
  while i <= #bars do
    local b = bars[i]
    local hr = G.hr
    if hr == 1 then
      local len = b.len
      local nb = bars[i + 1]
      if nb then len = len + nb.len end
      add(b.t0, len, i)
      i = i + (nb and 2 or 1)
    elseif hr == 2 then
      add(b.t0, b.len, i); i = i + 1
    else
      local cuts
      if hr == 3 then cuts = halfCut(b)
      elseif hr == 4 then
        local x = rng.f()
        if x < 0.35 then cuts = { 0 } elseif x < 0.8 then cuts = halfCut(b, rng) else cuts = thirdCuts(b) end
      else cuts = pulseCuts(b) end
      for k = 1, #cuts do
        local a, z = cuts[k], cuts[k + 1] or b.steps
        add(b.t0 + a / 4, (z - a) / 4, i)
      end
      i = i + 1
    end
  end
  return out
end

-- ---- construcao de acordes a partir de graus de escala ---------------------
function Hm.stack(iv, degIdx, nTones, skip)
  local n, out = #iv, {}
  local base = iv[(degIdx - 1) % n + 1]
  for k = 0, nTones - 1 do
    local d = (degIdx - 1) + k * (skip or 2)
    local semis = iv[d % n + 1] + 12 * (d // n)
    local rel = semis - (iv[(degIdx - 1) % n + 1] + 12 * ((degIdx - 1) // n))
    out[#out + 1] = rel
  end
  return out, base
end

local function nTonesFor(G, rng, philo)
  local rr = G.richness
  local n = 3
  if rng.chance(0.3 + rr * 0.7) then n = 4 end
  if rr > 0.35 and rng.chance(rr * 0.8) then n = 5 end
  if rr > 0.6 and rng.chance((rr - 0.35) * 0.9) then n = 6 end
  if philo == 1 then n = min(n, 5) end
  return n
end

local function scaleLabel(rootPc, idx)
  return Th.NOTE_NAMES[rootPc % 12 + 1] .. " " .. Th.SCALES[idx][1]
end

function Hm.diatonic(keyPc, scaleIdx, deg, nT, kind)
  local sc = Th.SCALES[scaleIdx]
  local ivs, base = Hm.stack(sc[2], deg, nT, 2)
  local root = (keyPc + base) % 12
  return Th.makeChord(root, ivs, Th.maskOf(sc[2], keyPc), scaleLabel(keyPc, scaleIdx), kind or "t")
end

-- dominante (usada em cadencias tonais, dominantes secundarias, substitutos)
function Hm.domChord(root, nT, minorish, alt, scaleLabelOverride)
  local ivs
  if alt then ivs = { 0, 4, 10, 13, 18, 20 }
  elseif minorish then ivs = { 0, 4, 7, 10, 13, 20 }
  else ivs = { 0, 4, 7, 10, 14, 21 } end
  local out = {}
  for i = 1, max(3, min(nT, #ivs)) do out[i] = ivs[i] end
  local sidx = alt and Th.SCALE_IDX["Alterada"]
      or (minorish and Th.SCALE_IDX["Frigio Dominante"] or Th.SCALE_IDX["Mixolidio"])
  local sc = Th.SCALES[sidx]
  return Th.makeChord(root, out, Th.maskOf(sc[2], root), scaleLabel(root, sidx), "t")
end

local function makeSus(ch, rng)
  local ivs = {}
  local to = rng.chance(0.5) and 5 or 2
  for i, x in ipairs(ch.ivs) do
    local pc = x % 12
    if (pc == 3 or pc == 4) and x < 12 then ivs[i] = to else ivs[i] = x end
  end
  local c = Th.makeChord(ch.root, ivs, Th.chordMask({ root = ch.root, ivs = ivs }) | ch.mask, ch.scaleName, ch.kind)
  return c
end

-- ---- escala que contem um acorde (para acordes experimentais) --------------
local candCache = {}
function Hm.scaleFor(ivs, root, rng, G)
  local cm = Th.chordMask({ root = root, ivs = ivs })
  local cands = candCache[cm]
  if not cands then
    cands = {}
    for si, sc in ipairs(Th.SCALES) do
      if sc[3] ~= "" then
        for rt = 0, 11 do
          local sm = Th.maskOf(sc[2], rt)
          if (sm & cm) == cm then cands[#cands + 1] = { rt = rt, si = si, mask = sm, n = #sc[2], fam = sc[3] } end
        end
      end
    end
    candCache[cm] = cands
  end
  if #cands == 0 then
    local km = Th.maskOf(Th.SCALES[G.scaleIdx][2], G.key)
    return km | cm, "Livre (escala + acorde)"
  end
  local items, ws = {}, {}
  for i, c in ipairs(cands) do
    items[i] = c
    local w = 1
    if c.rt == root then w = w + 2.5 end
    if c.n >= 6 and c.n <= 8 then w = w + 1 end
    if c.fam:find("x", 1, true) then w = w + 1 end
    ws[i] = w
  end
  local c = rng.weighted(items, ws)
  return c.mask, scaleLabel(c.rt, c.si)
end

-- ---- frases por filosofia ---------------------------------------------------
local TPL_MAJOR = { { 1, 6, 4, 5 }, { 1, 4, 5, 1 }, { 1, 5, 6, 4 }, { 2, 5, 1, 6 }, { 1, 3, 4, 5 },
  { 1, 6, 2, 5 }, { 4, 5, 3, 6 }, { 1, 4, 2, 5 }, { 6, 4, 1, 5 } }
local TPL_MINOR = { { 1, 7, 6, 5 }, { 1, 4, 5, 1 }, { 1, 6, 7, 1 }, { 1, 4, 7, 3 }, { 6, 7, 1, 5 },
  { 1, 3, 7, 6 }, { 1, 4, 6, 5 }, { 1, 6, 3, 7 } }

local function degreesFor(n, minor, rng, isFirst, isLast)
  local tpls = minor and TPL_MINOR or TPL_MAJOR
  local d = {}
  while #d < n do
    local t = rng.pick(tpls)
    for _, x in ipairs(t) do if #d < n then d[#d + 1] = x end end
  end
  if isFirst then d[1] = 1 end
  if isLast then
    d[n] = 1
    if n >= 2 and rng.chance(0.8) then d[n - 1] = 5 end
    if n >= 3 and rng.chance(0.6) then d[n - 2] = rng.pick({ 4, 2, 6 }) end
  elseif n >= 2 and rng.chance(0.5) then d[n] = 5 end
  return d
end

function Hm.tonalPhrase(G, rng, n, isFirst, isLast)
  local sidx = G.scaleIdx
  local sc = Th.SCALES[sidx]
  local iv = sc[2]
  local nn = #iv
  local minor = (iv[3] == 3)
  local degs = degreesFor(n, minor, rng, isFirst, isLast)
  local chords = {}
  for k = 1, n do
    local d = degs[k]
    local nT = nTonesFor(G, rng, 1)
    local ch
    local degIdx = ((d - 1) % nn) + 1
    if d == 5 and nn >= 7 and rng.chance(0.85) then
      ch = Hm.domChord((G.key + iv[degIdx]) % 12, nT, minor, G.tension > 0.65 and rng.chance(0.4))
    elseif rng.chance(G.borrow * 0.6) then
      local pool = Th.famPool("m")
      local bi = rng.pick(pool)
      if #Th.SCALES[bi][2] ~= 7 then bi = Th.SCALE_IDX[minor and "Dorico" or "Mixolidio"] end
      ch = Hm.diatonic(G.key, bi, degIdx, nT, "t")
      ch.name = ch.name .. "*"
    else
      ch = Hm.diatonic(G.key, sidx, degIdx, nT, "t")
      if k > 1 and rng.chance(G.tension * 0.3) and d ~= 1 then ch = makeSus(ch, rng) end
    end
    chords[k] = ch
  end
  -- dominantes secundarias e substitutos de trítono
  for k = 1, n - 1 do
    local nxt = chords[k + 1]
    if rng.chance(G.chroma * 0.45) and degs[k] ~= 5 then
      chords[k] = Hm.domChord((nxt.root + 7) % 12, nTonesFor(G, rng, 1), false, G.tension > 0.7)
      chords[k].name = chords[k].name .. "(V/)"
    elseif chords[k].name:find("7") and rng.chance(G.tension * G.chroma * 0.5) then
      local c = Hm.domChord((chords[k].root + 6) % 12, 4, false, false)
      local sidx2 = Th.SCALE_IDX["Lidio Dominante"]
      c.mask = Th.maskOf(Th.SCALES[sidx2][2], c.root)
      c.scaleName = scaleLabel(c.root, sidx2)
      c.name = c.name .. "(tritono)"
      chords[k] = c
    end
  end
  return chords
end

local MODAL_PATTERNS = {
  ["Dorico"] = { { 1, 4 }, { 1, 7 }, { 1, 4, 7, 4 }, { 1, 2, 1, 7 } },
  ["Frigio"] = { { 1, 2 }, { 1, 2, 1, 7 }, { 1, 2, 3, 2 } },
  ["Lidio"] = { { 1, 2 }, { 1, 2, 5, 1 }, { 1, 7, 2, 1 } },
  ["Mixolidio"] = { { 1, 7 }, { 1, 7, 4, 1 }, { 1, 4 }, { 1, 7, 6, 7 } },
  ["Menor Natural (Eolio)"] = { { 1, 6, 7 }, { 1, 7, 6, 7 }, { 1, 4, 7, 1 } },
  ["Locrio"] = { { 1, 2 }, { 1, 5, 1, 4 } },
  ["Dorico b2"] = { { 1, 2 }, { 1, 4, 2, 1 } },
  ["Lidio Dominante"] = { { 1, 2 }, { 1, 7, 4, 2 } },
}
function Hm.modalPhrase(G, rng, n, isFirst, isLast)
  local sidx = G.scaleIdx
  local sc = Th.SCALES[sidx]
  if not sc[3]:find("m", 1, true) or #sc[2] ~= 7 or rng.chance(G.borrow * 0.5) then
    local pool = {}
    for _, i in ipairs(Th.famPool("m")) do if #Th.SCALES[i][2] == 7 then pool[#pool + 1] = i end end
    sidx = rng.pick(pool)
    sc = Th.SCALES[sidx]
  end
  local pats = MODAL_PATTERNS[sc[1]] or { { 1, 2 }, { 1, 3 }, { 1, 4 }, { 1, 7 }, { 1, 5 }, { 1, 6, 7 } }
  local pat = rng.pick(pats)
  local chords = {}
  for k = 1, n do
    local d = pat[(k - 1) % #pat + 1]
    if isLast and k == n then d = 1 end
    local nT = max(3, nTonesFor(G, rng, 2))
    local ch = Hm.diatonic(G.key, sidx, d, nT, "m")
    if rng.chance(G.tension * 0.35) then ch = makeSus(ch, rng) end
    if G.pedal then ch.pedal = G.key end
    chords[k] = ch
  end
  return chords
end

local function expIvs(typ, rng, nT)
  if typ == "tertian" then
    local all = { 0, 4, 7, 11, 14, 18 }
    if rng.chance(0.5) then all = { 0, 3, 7, 10, 14, 17 } end
    local o = {}
    for i = 1, max(3, min(nT + 1, 6)) do o[i] = all[i] end
    return o
  elseif typ == "quartal" then
    local o = {}
    for i = 0, max(2, min(nT, 5)) do o[#o + 1] = i * 5 end
    return o
  elseif typ == "cluster" then return rng.pick({ { 0, 1, 2, 7 }, { 0, 2, 3, 7 }, { 0, 1, 5, 6 }, { 0, 2, 4, 6 } })
  elseif typ == "sus" then return rng.pick({ { 0, 5, 7, 14 }, { 0, 2, 7, 12, 16 }, { 0, 5, 7, 10, 14 } })
  elseif typ == "maj7#11" then return { 0, 4, 6, 7, 11, 14 }
  elseif typ == "alt" then return rng.pick({ { 0, 4, 10, 13, 18 }, { 0, 4, 8, 10, 15 }, { 0, 4, 6, 10, 13 } })
  elseif typ == "sowhat" then return { 0, 5, 10, 14, 19 }
  elseif typ == "poly" then return rng.pick({ { 0, 4, 7, 14, 18, 21 }, { 0, 3, 7, 13, 17, 20 }, { 0, 7, 10, 15, 19, 22 } })
  end
  return { 0, 4, 7 }
end

function Hm.expPhrase(G, rng, n, isFirst, isLast, prev)
  local chords = {}
  local root = prev and prev.root or G.key
  local types = { "tertian", "quartal", "cluster", "sus", "maj7#11", "alt", "sowhat", "poly" }
  local tw = { 2, 1.5 + G.chroma, 1 + G.tension, 1, 1, 0.6 + G.tension, 1.2, 0.8 + G.chroma }
  local moves = { "plane", "med", "tri", "cyc", "sym", "free" }
  local mw = { 1, 1.4, 0.8, 1.2, 1, 1 }
  for k = 1, n do
    if not (isFirst and k == 1) then
      local mv = rng.weighted(moves, mw)
      if mv == "plane" then root = root + rng.pick({ 1, -1, 2, -2 })
      elseif mv == "med" then root = root + rng.pick({ 3, 4, 8, 9 })
      elseif mv == "tri" then root = root + 6
      elseif mv == "cyc" then root = root + rng.pick({ 5, 7, -5, -7, 5 })
      elseif mv == "sym" then root = root + rng.pick({ 3, -3, 2, -2, 6 })
      else root = G.key + rng.pick({ 0, 1, 2, 3, 5, 6, 7, 8, 10, 11 }) end
      root = root % 12
    else root = G.key end
    local typ = rng.weighted(types, tw)
    local ivs = expIvs(typ, rng, nTonesFor(G, rng, 3))
    local mask, sname = Hm.scaleFor(ivs, root, rng, G)
    local ch = Th.makeChord(root, ivs, mask, sname, "x")
    if typ == "poly" then
      local up = ivs[4]
      ch.name = Th.NOTE_NAMES[(root + up) % 12 + 1] .. "/" .. Th.NOTE_NAMES[root + 1]
    end
    chords[k] = ch
  end
  if isLast then
    local ivs = rng.pick({ { 0, 7, 14, 16 }, { 0, 5, 7, 14 }, { 0, 3, 7, 11, 14 }, { 0, 4, 7, 11, 14, 18 } })
    local sidx = G.scaleIdx
    local mask = Th.maskOf(Th.SCALES[sidx][2], G.key) | Th.chordMask({ root = G.key, ivs = ivs })
    chords[n] = Th.makeChord(G.key, ivs, mask, scaleLabel(G.key, sidx), "x")
  end
  return chords
end

-- ---- forma e plano completo --------------------------------------------------
Hm.FORMS = { "Livre (frases novas)", "A-B", "A-A-B-A", "Rondo (A-B-A-C)", "Loop (uma frase)" }
function Hm.formLabels(form, nPhr)
  local out = {}
  local letters = "ABCDEFGHIJKLMNOP"
  for i = 1, nPhr do
    local L
    if form == 1 then L = letters:sub(i, i)
    elseif form == 2 then L = (i <= ceil(nPhr / 2)) and "A" or "B"
    elseif form == 3 then
      local pat = { "A", "A", "B", "A" }
      local blk = (i - 1) // 4
      L = pat[(i - 1) % 4 + 1]
      if blk > 0 then L = L .. blk end
    elseif form == 4 then
      local pat = { "A", "B", "A", "C" }
      L = pat[(i - 1) % 4 + 1]
      if i > 4 then L = L .. ((i - 1) // 4) end
    else L = "A" end
    out[i] = L
  end
  return out
end

function Hm.pickPhilo(G, rng, label, prev)
  if G.philo ~= 4 then return G.philo end
  local w = { max(0.001, G.mixT), max(0.001, G.mixM), max(0.001, G.mixX) }
  local p = rng.weighted({ 1, 2, 3 }, w)
  if p == prev and rng.chance(0.4) then p = rng.weighted({ 1, 2, 3 }, w) end
  return p
end

function Hm.buildPlan(G, bars, rng)
  local slots = Hm.slots(bars, G, rng)
  local ps = max(1, G.phraseSlots)
  local nPhr = ceil(#slots / ps)
  local labels = Hm.formLabels(G.form, nPhr)
  local cache, philoOf = {}, {}
  local plan = { slots = slots, phrases = {} }
  local prevPhilo, prevChord
  for pi = 1, nPhr do
    local lab = labels[pi]
    local from, to = (pi - 1) * ps + 1, min(#slots, pi * ps)
    local n = to - from + 1
    local chords = cache[lab]
    local philo = philoOf[lab]
    if not chords or #chords ~= n then
      philo = Hm.pickPhilo(G, rng, lab, prevPhilo)
      local isFirst, isLast = (pi == 1), (pi == nPhr)
      if philo == 1 then chords = Hm.tonalPhrase(G, rng, n, isFirst, isLast)
      elseif philo == 2 then chords = Hm.modalPhrase(G, rng, n, isFirst, isLast)
      else chords = Hm.expPhrase(G, rng, n, isFirst, isLast, prevChord) end
      cache[lab], philoOf[lab] = chords, philo
    end
    for k = 1, n do slots[from + k - 1].chord = chords[k] end
    prevChord = chords[n]
    prevPhilo = philo
    plan.phrases[#plan.phrases + 1] = { label = lab, philo = philo, from = from, to = to }
  end
  return plan
end

function Hm.chordAt(plan, t)
  local sl = plan.slots
  local lo, hi = 1, #sl
  while lo < hi do
    local mid = (lo + hi + 1) // 2
    if sl[mid].t0 <= t + 1e-6 then lo = mid else hi = mid - 1 end
  end
  return sl[lo].chord, sl[lo], lo
end

Hm.PHILO_NAMES = { "Tonal", "Modal", "Experimental", "Hibrida" }
function Hm.describe(plan)
  local lines = {}
  for _, ph in ipairs(plan.phrases) do
    local parts = {}
    for k = ph.from, ph.to do
      parts[#parts + 1] = plan.slots[k].chord.name
    end
    lines[#lines + 1] = string.format("%s (%s): %s", ph.label, Hm.PHILO_NAMES[ph.philo]:sub(1, 3), table.concat(parts, "  |  "))
  end
  return lines
end

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

----------------------------------------------------------------------------
-- registro de instrumentos
-- gen(ctx,P) devolve lista de notas {t,l,p,v}; CCs vao em ctx.ccOut
----------------------------------------------------------------------------
Ins.list, Ins.byId = {}, {}
function Ins.def(d)
  d.defaults = d.defaults or {}
  local df = d.defaults
  df.on = (df.on == nil) and true or df.on
  df.density = df.density or 0.5
  df.variation = df.variation or 0.4
  df.complexity = df.complexity or 0.4
  df.octave = df.octave or 0
  df.vel = df.vel or 0.8
  df.gate = df.gate or 0.9
  df.style = df.style or 1
  df.seedOff = df.seedOff or 0
  Ins.list[#Ins.list + 1] = d
  Ins.byId[d.id] = d
end

----------------------------------------------------------------------------
-- BATERIA / PERCUSSAO (canal 10, mapa GM)
----------------------------------------------------------------------------
local DR = { K = 36, K2 = 35, S = 38, RIM = 37, CLAP = 39, HC = 42, HP = 44, HO = 46, TL = 41, TM = 47,
  TH = 50, TLF = 43, CR = 49, RD = 51, RB = 53, TAMB = 54, COW = 56, CLV = 75, CGH = 63, CGL = 64,
  BGH = 60, BGL = 61, SHK = 70, TIMH = 65, TIML = 66 }

local function backbeats(bar)
  local out = {}
  if bar.den >= 8 then
    local gs = {}
    for s in pairs(bar.gstart) do if s > 0 then gs[#gs + 1] = s end end
    table.sort(gs)
    if #gs == 0 then out[1] = min(bar.steps - 1, 2 * bar.beatSteps) else out = gs end
  else
    local pos = 0
    for _, g in ipairs(bar.groups) do
      if g / bar.beatSteps >= 2 then out[#out + 1] = pos + bar.beatSteps end
      pos = pos + g
    end
    if #out == 0 and bar.steps > bar.beatSteps then out[1] = bar.beatSteps end
  end
  return out
end
local function halfTimeStep(bar)
  if bar.groups[2] then return bar.groups[1] end
  if bar.steps > 2 * bar.beatSteps then return 2 * bar.beatSteps end
  return backbeats(bar)[1] or 0
end
local function setOf(list) local t = {} for _, v in ipairs(list) do t[v] = true end return t end

-- cada estilo preenche pat (lista de eventos {s=passo, n=nota, v=vel, l=duracao em passos})
local DSTYLE = {}
local function E(pat, s, n, v, l) pat[#pat + 1] = { s = s, n = n, v = v, l = l or 0.5 } end

local function kicksFrom(ctx, bar, P, dens, sync, avoid)
  local out = { [0] = true }
  local list = Vc.onsets(ctx, bar, dens, sync, ctx.rng, 2)
  for _, s in ipairs(list) do if not avoid[s] then out[s] = true end end
  return out
end

DSTYLE[1] = function(ctx, P, bar, pat) -- Rock / Pop
  local rng, bb = ctx.rng, backbeats(bar)
  local bbs = setOf(bb)
  local hs = (P.density > 0.55) and max(1, bar.beatSteps // 2) or bar.beatSteps
  for s = 0, bar.steps - 1, hs do
    local acc = (s % bar.beatSteps == 0) and 85 or 62
    E(pat, s, DR.HC, acc + rng.int(-4, 4))
  end
  for s in pairs(kicksFrom(ctx, bar, P, P.density * 0.75, 0.45, bbs)) do E(pat, s, DR.K, s == 0 and 112 or 96) end
  for _, s in ipairs(bb) do E(pat, s, DR.S, 108) end
  if rng.chance(P.complexity * 0.6) then E(pat, max(0, bar.steps - 2), DR.HO, 78, 1) end
end

DSTYLE[2] = function(ctx, P, bar, pat) -- Funk / Groove com ghost notes
  local rng, bb = ctx.rng, backbeats(bar)
  local bbs = setOf(bb)
  for s = 0, bar.steps - 1 do
    local acc = (s % bar.beatSteps == 0) and 88 or ((s % 2 == 0) and 66 or 48)
    if rng.chance(0.55 + 0.4 * P.density) then E(pat, s, DR.HC, acc + rng.int(-5, 5), 0.4) end
  end
  for s in pairs(kicksFrom(ctx, bar, P, P.density * 0.9, 0.8, bbs)) do E(pat, s, DR.K, s == 0 and 115 or 92) end
  for _, s in ipairs(bb) do E(pat, s, DR.S, 112) end
  for s = 0, bar.steps - 1 do
    if not bbs[s] and bar.w[s] <= 0.35 and rng.chance(0.08 + 0.3 * P.complexity) then E(pat, s, DR.S, rng.int(24, 42), 0.3) end
  end
end

DSTYLE[3] = function(ctx, P, bar, pat) -- Jazz (ride em swing, bumbo leve, caixa de comping)
  local rng, bb = ctx.rng, backbeats(bar)
  local u = bar.beatSteps
  local idx = 0
  for s = 0, bar.steps - 1, u do
    E(pat, s, DR.RD, 84 + rng.int(-5, 5), 1)
    if idx % 2 == 1 and s + u * 0.5 < bar.steps then E(pat, s + math.floor(u * 0.5), DR.RD, 66, 0.7) end
    if rng.chance(0.55) then E(pat, s, DR.K, rng.int(28, 46), 0.4) end
    idx = idx + 1
  end
  for _, s in ipairs(bb) do E(pat, s, DR.HP, 78, 0.4) end
  for s = 0, bar.steps - 1, max(1, u // 2) do
    if bar.w[s] < 0.55 and rng.chance(0.05 + 0.35 * P.density * P.complexity) then
      E(pat, s, rng.chance(0.3) and DR.RIM or DR.S, rng.int(40, 82), 0.4)
    end
  end
  if rng.chance(P.density * 0.35) then E(pat, 0, DR.K, 80, 0.5) end
end

DSTYLE[4] = function(ctx, P, bar, pat) -- Eletronica (four-on-the-floor / breaks)
  local rng, bb = ctx.rng, backbeats(bar)
  if P.complexity < 0.62 then
    local pts = {}
    for s in pairs(bar.gstart) do pts[#pts + 1] = s end
    if bar.den <= 4 then for s = 0, bar.steps - 1, bar.beatSteps do pts[#pts + 1] = s end end
    for _, s in ipairs(pts) do E(pat, s, DR.K, 118) end
    for s = bar.beatSteps // 2, bar.steps - 1, bar.beatSteps do E(pat, s, DR.HO, 72, 1) end
  else
    local ks = kicksFrom(ctx, bar, P, P.density, 0.9, setOf(bb))
    for s in pairs(ks) do E(pat, s, DR.K, 112) end
  end
  for _, s in ipairs(bb) do E(pat, s, DR.CLAP, 104) E(pat, s, DR.S, 70) end
  for s = 0, bar.steps - 1 do
    if rng.chance(0.25 + 0.6 * P.density) then E(pat, s, DR.HC, 50 + (s % 2 == 0 and 14 or 0) + rng.int(-4, 4), 0.3) end
  end
  if rng.chance(P.complexity * 0.5) then E(pat, rng.int(1, bar.steps - 1), DR.TAMB, 60, 0.3) end
end

DSTYLE[5] = function(ctx, P, bar, pat) -- Trap / half-time
  local rng = ctx.rng
  E(pat, halfTimeStep(bar), DR.S, 112)
  E(pat, halfTimeStep(bar), DR.CLAP, 90)
  for s in pairs(kicksFrom(ctx, bar, P, P.density * 0.6, 0.9, {})) do E(pat, s, DR.K, s == 0 and 118 or 100) end
  local gridStep = bar.beatSteps >= 4 and 2 or 1
  for s = 0, bar.steps - 1, gridStep do
    if rng.chance(0.75) then E(pat, s, DR.HC, 58 + (s % bar.beatSteps == 0 and 20 or 0), 0.3) end
    if rng.chance(P.complexity * 0.22) then
      local trip = rng.chance(0.5)
      local n = trip and 3 or 4
      for k = 0, n - 1 do
        local pos = s + k * (gridStep / n)
        E(pat, pos, DR.HC, 50 + k * 8, 0.25)
      end
    end
  end
  if rng.chance(P.complexity * 0.3) then E(pat, rng.int(1, bar.steps - 1), DR.HO, 70, 1) end
end

DSTYLE[6] = function(ctx, P, bar, pat) -- Latino / Afro (clave, conga, cowbell)
  local rng = ctx.rng
  local k = clamp(round(bar.steps * (0.28 + 0.12 * P.complexity)), 2, bar.steps)
  local clave = Mt.euclid(k, bar.steps, 0)
  for s = 0, bar.steps - 1 do
    if clave[s] then E(pat, s, DR.CLV, 88, 0.4) end
    if s % bar.beatSteps == 0 and rng.chance(0.5 + 0.4 * P.density) then E(pat, s, DR.COW, 66, 0.4) end
  end
  for s = 0, bar.steps - 1, 2 do
    local hi = ((s // 2) % 2 == 0)
    if rng.chance(0.4 + 0.5 * P.density) then E(pat, s, hi and DR.CGH or DR.CGL, 70 + rng.int(-6, 8), 0.4) end
  end
  for s = 0, bar.steps - 1 do
    if rng.chance(0.25 + 0.5 * P.density) then E(pat, s, DR.SHK, 44 + (s % 2 == 0 and 14 or 0), 0.25) end
  end
  for s in pairs(bar.gstart) do E(pat, s, DR.K, 102) end
  if bar.steps >= 16 then E(pat, 10, DR.K, 86) end
  for _, s in ipairs(backbeats(bar)) do E(pat, s, DR.RIM, 84) end
end

DSTYLE[7] = function(ctx, P, bar, pat) -- Cinematografico (taiko, tímpanos)
  local rng = ctx.rng
  for s in pairs(bar.gstart) do
    E(pat, s, DR.TL, 124, 3)
    E(pat, s, DR.K2, 110, 2)
    if s == 0 and bar.idx % 4 == 1 then E(pat, 0, DR.CR, 96, 4) end
  end
  for s = 0, bar.steps - 1 do
    if s % bar.beatSteps == 0 and not bar.gstart[s] and rng.chance(0.25 + 0.5 * P.density) then
      E(pat, s, rng.pick({ DR.TLF, DR.TM }), 88 + rng.int(-6, 6), 1.5)
    end
    if rng.chance(0.04 + 0.28 * P.density * P.complexity) and bar.w[s] < 0.55 then
      E(pat, s, DR.TM, 70 + rng.int(0, 20), 0.6)
    end
  end
  if rng.chance(P.complexity * 0.5) then
    local c = max(0, bar.steps - 4)
    for k = 0, 3 do E(pat, c + k, DR.TH - (k % 2) * 3, 70 + k * 10, 0.5) end
  end
end

DSTYLE[8] = function(ctx, P, bar, pat) -- Euclidiano / poliritmia
  local rng = ctx.rng
  local st = ctx.drumState
  local drift = st.drift or 0
  local kk = clamp(round(2 + P.density * 5 + P.complexity * 2), 1, bar.steps)
  local ks = Mt.euclid(kk, bar.steps, 0)
  local ss = Mt.euclid(clamp(round(1 + P.density * 3 + P.complexity * 3), 1, bar.steps), bar.steps, drift + 2)
  local hs = Mt.euclid(clamp(round(3 + P.density * 8), 1, bar.steps), bar.steps, 0)
  local ps = Mt.euclid(clamp(round(2 + P.complexity * 5), 1, bar.steps), bar.steps, drift + 1)
  local ts = Mt.euclid(clamp(round(1 + P.complexity * 3), 1, bar.steps), bar.steps, drift + 5)
  for s = 0, bar.steps - 1 do
    if ks[s] then E(pat, s, DR.K, s == 0 and 114 or 96) end
    if ss[s] then E(pat, s, rng.chance(0.3) and DR.RIM or DR.S, 96) end
    if hs[s] then E(pat, s, DR.HC, 60 + (s % 2 == 0 and 16 or 0), 0.3) end
    if ps[s] then E(pat, s, rng.pick({ DR.COW, DR.CLV, DR.TAMB, DR.CGH }), 70, 0.4) end
    if ts[s] then E(pat, s, rng.pick({ DR.TL, DR.TM, DR.TH }), 84, 0.5) end
  end
  if rng.chance(P.variation * 0.6) then st.drift = (drift + rng.pick({ 1, 2, -1 })) end
end

local function mutateDrums(ctx, P)
  return function(pat, bar)
    local rng = ctx.rng
    if rng.chance(0.55) then
      for _ = 1, rng.int(1, 3) do
        local s = rng.int(0, bar.steps - 1)
        local style = P.style
        local n = (style == 3) and DR.RIM or (style == 4 and DR.HC or (rng.chance(0.5) and DR.HC or DR.S))
        E(pat, s, n, rng.int(26, 52), 0.3)
      end
    end
    if rng.chance(0.4) and #pat > 4 then
      local i = rng.int(1, #pat)
      if pat[i].v < 80 and pat[i].s ~= 0 then table.remove(pat, i) end
    end
    if rng.chance(0.4) then
      for _, e in ipairs(pat) do
        if (e.n == DR.K or e.n == DR.K2) and e.s ~= 0 and rng.chance(0.5) then
          e.s = clamp(e.s + rng.pick({ -2, -1, 1, 2 }), 1, bar.steps - 1)
          break
        end
      end
    end
    return pat
  end
end

local function drumFill(ctx, P, bar, pat)
  local rng = ctx.rng
  local len = min(bar.steps // 2, rng.pick({ 4, 6, 8 }))
  local from = bar.steps - len
  for i = #pat, 1, -1 do if pat[i].s >= from and pat[i].n ~= DR.CR then table.remove(pat, i) end end
  local kind = rng.int(1, 3)
  for k = 0, len - 1 do
    local s = from + k
    local x = k / max(len - 1, 1)
    if kind == 1 then E(pat, s, DR.S, 60 + round(x * 55), 0.4)
    elseif kind == 2 then
      if k % 2 == 0 then
        E(pat, s, rng.pick({ DR.TH, DR.TM, DR.TL, DR.TLF }), 80 + round(x * 35), 0.8)
      end
    else
      if rng.chance(0.65) then E(pat, s, rng.pick({ DR.S, DR.TH, DR.TM, DR.TL }), 78 + round(x * 30), 0.5) end
    end
  end
  E(pat, from, DR.K, 100, 0.5)
  return true
end

local function genDrums(ctx, P)
  local out = {}
  ctx.drumState = {}
  local st = { pats = {}, crash = false }
  local style = clamp(P.style, 1, #DSTYLE)
  local P2 = setmetatable({ style = style }, { __index = P })
  local mut = mutateDrums(ctx, P2)
  for _, bar in ipairs(ctx.bars) do
    local pat = Vc.patternFor(st.pats, bar, ctx.rng, P, function(b)
      local p = {}
      DSTYLE[style](ctx, P2, b, p)
      return p
    end, mut)
    pat = U.copy(pat)
    local filled = false
    if Vc.phraseEnd(ctx, bar) and bar.steps >= 6 and ctx.rng.chance(0.15 + 0.7 * P.complexity * (0.4 + 0.6 * P.variation)) then
      filled = drumFill(ctx, P, bar, pat)
    end
    if st.crash and style ~= 7 then E(pat, 0, DR.CR, 100, 4) end
    if bar.idx == 1 and style ~= 3 and ctx.rng.chance(0.6) then E(pat, 0, DR.CR, 96, 4) end
    st.crash = filled
    for _, e in ipairs(pat) do
      local t = bar.t0 + e.s / 4
      local opts = { gate = 1, noSwing = (e.s % 1 ~= 0) }
      if style == 3 then opts.swingAmt = max(0.55, ctx.G.swing); opts.swingGrid = 8 end
      if style == 2 and ctx.G.swing > 0 then opts.swingGrid = 16 end
      Vc.add(out, ctx, P, t, max(0.08, e.l / 4), e.n, e.v, opts)
      if e.n == DR.K or e.n == DR.K2 then ctx.shared.kick[round(t * 4)] = true end
      if e.n == DR.S or e.n == DR.CLAP then ctx.shared.snare[round(t * 4)] = true end
    end
  end
  return out
end

Ins.def { id = "drums", label = "Bateria / Percussao", ch = 9, prog = 0, lo = 35, hi = 81,
  styles = { "Rock / Pop", "Funk (ghost notes)", "Jazz (swing)", "Eletronica (four-on-floor / breaks)",
    "Trap / half-time", "Latino / Afro (clave)", "Cinematografico (taiko)", "Euclidiano / poliritmia" },
  defaults = { density = 0.55, variation = 0.45, complexity = 0.45, vel = 0.8 }, gen = genDrums }

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

----------------------------------------------------------------------------
-- orquestracao: parametros globais, curva de energia, execucao dos instrumentos
----------------------------------------------------------------------------
function Cp.defaultG()
  return {
    key = 9, scaleIdx = 2, philo = 4, mixT = 0.4, mixM = 0.45, mixX = 0.3,
    tension = 0.4, chroma = 0.3, borrow = 0.3, richness = 0.5, hr = 2, phraseSlots = 4,
    pedal = false, form = 1, scaleFreedom = 0.5,
    meterIdx = 1, customNum = 4, customDen = 4, meterSeq = "", altGroup = false,
    harmSeed = 0, bpm = 100, bars = 8, swing = 0, swingGrid = 8, humanize = 0.5, seed = 20260, energyCurve = 3,
    layering = false, tapInfluence = 0.5, intent = "",
    startAtCursor = false, applyTempo = true, reuseTracks = true, sendPC = false, colorTracks = true,
  }
end

function Cp.defaultP()
  local P = {}
  for _, d in ipairs(Ins.list) do P[d.id] = U.copy(d.defaults) end
  return P
end

Cp.ENERGY_NAMES = { "Constante", "Crescente", "Arco (sobe e desce)", "Ondas (4 compassos)", "Por secao (B mais forte)" }
Cp.LAYER_THRESHOLD = { drums = 0.0, bass = 0.0, keys = 0.0, strings = 0.0, guitar = 0.1, lead = 0.0,
  arp = 0.55, counter = 0.72, brass = 0.88, winds = 0.65, mallets = 0.6, texture = 0.3 }

function Cp.applyEnergy(G, bars, plan)
  local n = #bars
  local barPhrase = {}
  for _, ph in ipairs(plan.phrases) do
    for k = ph.from, ph.to do barPhrase[plan.slots[k].bar] = ph end
  end
  for i, b in ipairs(bars) do
    local x = (n > 1) and ((i - 1) / (n - 1)) or 0
    local e = 1
    local c = G.energyCurve
    if c == 2 then e = 0.5 + 0.5 * x
    elseif c == 3 then e = 0.52 + 0.48 * math.sin(math.pi * x)
    elseif c == 4 then e = 0.72 + 0.28 * math.sin(2 * math.pi * (i - 1) / 4)
    elseif c == 5 then
      local ph = barPhrase[i] or barPhrase[i - 1]
      e = (ph and ph.label:sub(1, 1) ~= "A") and 1.0 or 0.72
    end
    b.energy = clamp(e, 0.3, 1)
  end
end

-- executa o motor. which = { [id]=true } instrumentos a devolver
function Cp.run(G, Pset, which, opts)
  opts = opts or {}
  local bars, total = Mt.buildBars(G)
  local rngH = U.newRng(G.seed * 7919 + 13 + (G.harmSeed or 0) * 104729)
  local plan = Hm.buildPlan(G, bars, rngH)
  Cp.applyEnergy(G, bars, plan)
  local base = { G = G, bars = bars, plan = plan, total = total,
    shared = { kick = {}, snare = {}, lead = {}, leadNotes = {} }, tapProfile = G.tapProfile }
  local res = { plan = plan, bars = bars, total = total, tracks = {} }
  local need = {}
  for id in pairs(which) do need[id] = true end
  if need.bass and Pset.bass.lock then need.drums = need.drums or "dep" end
  if need.counter then need.lead = need.lead or "dep" end
  for _, d in ipairs(Ins.list) do
    local P = Pset[d.id]
    if need[d.id] and P then
      local ctx = setmetatable({}, { __index = base })
      ctx.rng = U.newRng(G.seed * 131 + U.hashStr(d.id) + (P.seedOff or 0) * 977)
      ctx.ccOut = {}
      local notes = d.gen(ctx, P)
      if which[d.id] then
        if opts.layer and G.layering then
          local th = Cp.LAYER_THRESHOLD[d.id] or 0
          local keep = {}
          for _, n in ipairs(notes) do
            if Mt.barAt(bars, n.t).energy >= th + 0.0001 or th == 0 then keep[#keep + 1] = n end
          end
          notes = keep
        end
        table.sort(notes, function(a, b) if a.t == b.t then return a.p < b.p end return a.t < b.t end)
        res.tracks[d.id] = { notes = notes, cc = ctx.ccOut, def = d, P = P }
      end
    end
  end
  return res
end

-- so a harmonia (para exibir na interface)
function Cp.planOnly(G)
  local bars = Mt.buildBars(G)
  local rngH = U.newRng(G.seed * 7919 + 13 + (G.harmSeed or 0) * 104729)
  local plan = Hm.buildPlan(G, bars, rngH)
  Cp.applyEnergy(G, bars, plan)
  return plan, bars
end

----------------------------------------------------------------------------
-- TAP: detecta BPM e aprende o ritmo tocado (perfil de ataques por passo)
----------------------------------------------------------------------------
Tp.taps = {}
Tp.info = nil
Tp.MODES = { "BPM + ritmo (ambos)", "So BPM (batida constante)", "So ritmo (usa o BPM atual)" }

local function median(t)
  local c = {}
  for i, v in ipairs(t) do c[i] = v end
  table.sort(c)
  if #c == 0 then return 0 end
  return (#c % 2 == 1) and c[(#c + 1) // 2] or (c[#c // 2] + c[#c // 2 + 1]) / 2
end

local function foldBpm(b)
  if b <= 0 then return 100 end
  while b < 60 do b = b * 2 end
  while b > 190 do b = b / 2 end
  return b
end

function Tp.reset() Tp.taps = {}; Tp.info = nil end

-- registra um toque (now em segundos). Mais de 3s de pausa recomeca.
function Tp.tap(now)
  local n = #Tp.taps
  if n > 0 and now - Tp.taps[n] > 3.0 then Tp.taps = {}; n = 0 end
  Tp.taps[n + 1] = now
  return Tp.liveBpm()
end

function Tp.liveBpm()
  local n = #Tp.taps
  if n < 2 then return nil end
  local iois = {}
  for i = max(2, n - 6), n do iois[#iois + 1] = Tp.taps[i] - Tp.taps[i - 1] end
  local m = median(iois)
  if m <= 0.05 then return nil end
  return foldBpm(60 / m)
end

-- acha a menor unidade de tempo que se repete (aglomerado de intervalos)
local function findPulse(iois)
  local sorted = {}
  for i, v in ipairs(iois) do sorted[i] = v end
  table.sort(sorted)
  local best
  for _, base in ipairs(sorted) do
    local cluster = {}
    for _, v in ipairs(sorted) do if abs(v - base) <= base * 0.16 then cluster[#cluster + 1] = v end end
    if #cluster >= max(2, floor(#iois * 0.25 + 0.5)) then
      local sum = 0
      for _, v in ipairs(cluster) do sum = sum + v end
      best = sum / #cluster
      break
    end
  end
  return best or median(iois)
end

-- mode: 1 ambos, 2 so BPM, 3 so ritmo. loopSteps = passos do compasso atual
function Tp.analyze(G, mode, loopSteps)
  local taps = Tp.taps
  local n = #taps
  if n < 4 then return nil, "Faca pelo menos 4 toques (o primeiro e o tempo 1)." end
  local iois = {}
  for i = 2, n do iois[#iois + 1] = taps[i] - taps[i - 1] end
  local info = { n = n }
  local beat
  if mode == 3 then beat = 60 / G.bpm
  else
    -- escolhe o periodo (60..190 BPM) em que mais toques caem sobre a grade
    local cands, seen = {}, {}
    for _, v in ipairs(iois) do
      for _, m in ipairs({ 0.5, 1, 2, 3, 4 }) do
        local per = v * m
        local bpm = 60 / per
        local key = floor(bpm + 0.5)
        if bpm >= 60 and bpm <= 190 and not seen[key] then seen[key] = true; cands[#cands + 1] = per end
      end
    end
    local bestPer, bestScore = nil, -1
    for _, per in ipairs(cands) do
      local hit = 0
      for i = 1, n do
        local x = (taps[i] - taps[1]) / per
        if abs(x - round(x)) <= 0.12 then hit = hit + 1 end
      end
      local score = hit / n - 0.04 * (60 / per) / 100
      if score > bestScore then bestScore, bestPer = score, per end
    end
    local per = bestPer or median(iois)
    -- refina por regressao linear sobre os toques que caem na grade
    local sk, st, skk, skt, cnt = 0, 0, 0, 0, 0
    for i = 1, n do
      local x = (taps[i] - taps[1]) / per
      if abs(x - round(x)) <= 0.12 then
        local k, tt = round(x), taps[i] - taps[1]
        sk, st, skk, skt, cnt = sk + k, st + tt, skk + k * k, skt + k * tt, cnt + 1
      end
    end
    local den = cnt * skk - sk * sk
    if cnt >= 3 and den > 0 then per = (cnt * skt - sk * st) / den end
    info.bpm = floor(foldBpm(60 / per) * 10 + 0.5) / 10
    beat = 60 / info.bpm
  end
  if mode == 2 then
    info.summary = string.format("BPM %.1f (a partir de %d toques)", info.bpm, n)
    return info
  end
  local g = beat / 4
  local L = loopSteps or 16
  local counts, swingSamples = {}, {}
  local offbeats, total = 0, 0
  for s = 0, L - 1 do counts[s] = 0 end
  for i = 1, n do
    local raw = (taps[i] - taps[1]) / g
    local bi = floor(raw / 4)
    local f = raw - 4 * bi
    local pos
    if f >= 2.35 and f <= 3.3 then
      swingSamples[#swingSamples + 1] = (f - 2) / 0.667
      pos = bi * 4 + 2
    else pos = round(raw) end
    local sp = pos % L
    counts[sp] = counts[sp] + 1
    total = total + 1
    if pos % 4 ~= 0 then offbeats = offbeats + 1 end
  end
  local mx = 0
  for s = 0, L - 1 do mx = max(mx, counts[s]) end
  local w, distinct = {}, 0
  for s = 0, L - 1 do
    w[s] = (mx > 0) and counts[s] / mx or 0
    if counts[s] > 0 then distinct = distinct + 1 end
  end
  for s = 0, L - 1 do
    local nb = max(w[(s - 1) % L], w[(s + 1) % L])
    if w[s] == 0 and nb > 0 then w[s] = 0.12 * nb end
  end
  info.profile = { len = L, w = w }
  info.sync = (total > 0) and offbeats / total or 0
  local dur = taps[n] - taps[1]
  local ratio = (dur > 0) and (n - 1) / (dur / beat) or 1
  info.density = clamp((ratio - 0.4) / 1.8, 0.08, 1)
  if #swingSamples >= 2 and #swingSamples >= offbeats * 0.5 then
    info.swing = clamp(median(swingSamples), 0, 1)
  else info.swing = 0 end
  local parts = {}
  if info.bpm then parts[#parts + 1] = string.format("BPM %.1f", info.bpm) end
  parts[#parts + 1] = string.format("%d toques em %d posicoes diferentes", n, distinct)
  parts[#parts + 1] = string.format("sincope %d%%", round(info.sync * 100))
  if info.swing > 0.15 then parts[#parts + 1] = string.format("swing %d%%", round(info.swing * 100)) end
  parts[#parts + 1] = string.format("densidade sugerida %.2f", info.density)
  info.summary = table.concat(parts, "  |  ")
  return info
end

-- aplica o resultado nos parametros; devolve linhas de log
function Tp.apply(info, G, P, mode)
  local log = {}
  if info.bpm then
    G.bpm = info.bpm
    log[#log + 1] = string.format("BPM do projeto = %.1f", info.bpm)
  end
  if info.profile and mode ~= 2 then
    G.tapProfile = info.profile
    if G.tapInfluence < 0.2 then G.tapInfluence = 0.55 end
    log[#log + 1] = string.format("Ritmo aprendido (%d passos): os instrumentos agora favorecem os pontos que voce tocou (influencia %.0f%%)", info.profile.len, G.tapInfluence * 100)
    if info.swing and info.swing > 0.15 then
      G.swing = info.swing
      log[#log + 1] = string.format("Swing detectado: %.0f%%", info.swing * 100)
    end
    for _, id in ipairs({ "drums", "bass", "arp", "guitar", "keys" }) do
      if P[id] then P[id].density = U.lerp(P[id].density, info.density, 0.5) end
    end
    log[#log + 1] = string.format("Densidade de bateria/baixo/teclas/arpejo/violao aproximada de %.2f", info.density)
  end
  return log
end

----------------------------------------------------------------------------
-- INTENCAO EM TEXTO: interpreta palavras-chave (pt/en) e ajusta os parametros
----------------------------------------------------------------------------
local ACC = { ["á"]="a", ["à"]="a", ["â"]="a", ["ã"]="a", ["é"]="e", ["ê"]="e", ["í"]="i", ["ó"]="o", ["ô"]="o",
  ["õ"]="o", ["ú"]="u", ["ü"]="u", ["ç"]="c" }
function Tx.norm(s)
  s = tostring(s or ""):lower()
  s = s:gsub("[\195][\128-\191]", function(c) return ACC[c] or c end)
  return s
end

local function has(s, words)
  for _, w in ipairs(words) do
    if s:find("%f[%w]" .. w) then return w end
  end
  return nil
end
local function setScale(G, name) G.scaleIdx = Th.SCALE_IDX[name] or G.scaleIdx end
local function sty(P, id, n) if P[id] then P[id].style = n end end
local function on(P, id, v) if P[id] then P[id].on = v end end
local function dens(P, ids, v) for _, id in ipairs(ids) do if P[id] then P[id].density = clamp(v, 0.05, 1) end end end
local function allP(P, k, f) for _, p in pairs(P) do p[k] = clamp(f(p[k]), 0, 1) end end

Tx.INSTR_WORDS = {
  drums = { "bateria", "drums", "percussao", "percussion" }, bass = { "baixo", "bass" },
  keys = { "piano", "teclas", "teclado", "keys", "rhodes" }, strings = { "cordas", "strings", "violino", "orquestra" },
  arp = { "arpejo", "arpeggio", "sequencer", "sequenciador" }, guitar = { "violao", "guitarra", "guitar" },
  lead = { "melodia", "lead", "solo" }, counter = { "contracanto", "contraponto", "segunda voz" },
  brass = { "metais", "brass", "trompete", "trompa", "sax" },
  winds = { "flauta", "madeiras", "woodwind", "woodwinds", "clarinete", "oboe", "flute" },
  mallets = { "marimba", "vibrafone", "sinos", "mallets", "kalimba", "glockenspiel", "celesta" },
  texture = { "textura", "drone", "atmosfera", "fx" },
}

local SOLFEGE = { ["do"]=0, ["re"]=2, ["mi"]=4, ["fa"]=5, ["sol"]=7, ["la"]=9, ["si"]=11 }
local LETTER = { c=0, d=2, e=4, f=5, g=7, a=9, b=11 }
local SCALE_WORDS = {
  { "maior", "major", "ionian", "jonio" }, { "menor", "minor", "eolio", "aeolian" }, { "dorico", "dorian" },
  { "frigio", "phrygian" }, { "lidio", "lydian" }, { "mixolidio", "mixolydian" }, { "locrio", "locrian" },
}
local SCALE_NAMES = { "Maior (Jonio)", "Menor Natural (Eolio)", "Dorico", "Frigio", "Lidio", "Mixolidio", "Locrio" }

local function parseKey(raw, s, G, log)
  -- solfejo: "re menor", "do# maior", "la bemol dorico"
  for name, pc in pairs(SOLFEGE) do
    local acc, word = s:match("%f[%a]" .. name .. "%s*([#b]?)%s*[%s]*(%a+)")
    if word == nil then acc, word = s:match("%f[%a]" .. name .. "%s+(sustenido)%s+(%a+)") end
    if word == nil then acc, word = s:match("%f[%a]" .. name .. "%s+(bemol)%s+(%a+)") end
    if word then
      for si, ws in ipairs(SCALE_WORDS) do
        for _, w in ipairs(ws) do
          if word == w then
            local a = (acc == "#" or acc == "sustenido") and 1 or ((acc == "b" or acc == "bemol") and -1 or 0)
            G.key = (pc + a) % 12; setScale(G, SCALE_NAMES[si])
            log[#log + 1] = string.format("Tom: %s %s", Th.NOTE_NAMES[G.key + 1], SCALE_NAMES[si])
            return true
          end
        end
      end
    end
  end
  -- letras maiusculas no texto original: "D minor", "F# dorian"
  for letter, acc, word in raw:gmatch("%f[%w]([A-G])([#b]?)%s+(%a+)") do
    local w = Tx.norm(word)
    for si, ws in ipairs(SCALE_WORDS) do
      for _, x in ipairs(ws) do
        if w == x then
          local a = (acc == "#") and 1 or ((acc == "b") and -1 or 0)
          G.key = (LETTER[letter:lower()] + a) % 12; setScale(G, SCALE_NAMES[si])
          log[#log + 1] = string.format("Tom: %s %s", Th.NOTE_NAMES[G.key + 1], SCALE_NAMES[si])
          return true
        end
      end
    end
  end
  return false
end

function Tx.apply(raw, G, P)
  local log = {}
  local s = Tx.norm(raw)
  if s:match("^%s*$") then return { "Escreva algo, por exemplo: 'tenso e sombrio, jazz em re dorico, 7/8, 90 bpm, sem bateria'." } end
  local function note(t) log[#log + 1] = t end

  -- filosofia harmonica
  if has(s, { "experimental", "atonal", "avant", "contemporane" }) then
    G.philo = 4; G.mixX = 0.9; G.mixT = 0.1; G.mixM = 0.3; G.chroma = max(G.chroma, 0.7); G.tension = max(G.tension, 0.7)
    sty(P, "lead", 4); sty(P, "winds", 3); note("Harmonia experimental (acordes quartais, mediantes cromaticas, escalas simetricas)")
  end
  if has(s, { "classico", "classical", "barroco", "romantico", "tradicional" }) then
    G.philo = 1; G.tension = 0.2; G.chroma = 0.15; G.borrow = 0.1; G.hr = 3
    sty(P, "strings", 2); sty(P, "keys", 3); sty(P, "lead", 1); sty(P, "counter", 1); sty(P, "bass", 1)
    note("Harmonia tonal tradicional, frases cantadas")
    if s:find("barroco") then sty(P, "arp", 3); on(P, "arp", true); note("Barroco: arpejos sobe-desce e vozes paralelas") end
  end
  if has(s, { "modal" }) then G.philo = 2; G.pedal = true; note("Harmonia modal com pedal") end
  if has(s, { "tonal" }) and not s:find("atonal") then G.philo = 1; note("Harmonia tonal") end
  if has(s, { "hibrido", "hybrid", "misturado" }) then G.philo = 4; note("Harmonia hibrida") end

  -- clima / emocao
  if has(s, { "sombrio", "escuro", "dark", "sinistro", "tenebroso", "noir", "misterio" }) then
    setScale(G, "Frigio"); G.tension = max(G.tension, 0.6); G.bpm = clamp(G.bpm * 0.88, 60, 105)
    on(P, "texture", true); sty(P, "texture", 2); sty(P, "strings", 6); allP(P, "vel", function(v) return v * 0.92 end)
    note("Sombrio: escala Frigia, tensao alta, textura de clusters, cordas em suspensao")
  end
  if has(s, { "triste", "melancol", "nostalg", "sad", "saudade" }) then
    setScale(G, s:find("dorico") and "Dorico" or "Menor Natural (Eolio)"); G.tension = 0.3; G.bpm = clamp(G.bpm * 0.85, 55, 100)
    sty(P, "keys", 3); sty(P, "strings", 1); sty(P, "lead", 1); dens(P, { "drums", "lead" }, 0.35)
    note("Triste/melancolico: menor, andamento lento, piano em balada, melodia cantabile")
  end
  if has(s, { "alegre", "feliz", "happy", "brilhante", "bright", "solar", "otimista" }) then
    setScale(G, "Lidio"); G.tension = 0.2; G.bpm = clamp(max(G.bpm, 110), 100, 135); sty(P, "drums", 1); sty(P, "lead", 2)
    note("Alegre: escala Lidia, andamento animado")
  end
  if has(s, { "epico", "epic", "cinematograf", "cinematic", "trailer", "orquestral", "heroico" }) then
    setScale(G, "Menor Natural (Eolio)"); G.energyCurve = 2; G.layering = true; G.bars = max(G.bars, 16); G.tension = 0.5
    sty(P, "drums", 7); sty(P, "strings", 3); sty(P, "brass", 2); sty(P, "bass", 7); sty(P, "lead", 1)
    for _, id in ipairs({ "drums", "strings", "brass", "texture", "lead", "bass" }) do on(P, id, true) end
    note("Epico: arco crescente, taiko, cordas staccato, fanfarra de metais, camadas por intensidade")
  end
  if has(s, { "tenso", "tensao", "suspense", "thriller", "horror", "terror", "angustia" }) then
    G.philo = 4; G.mixX = 0.8; G.mixT = 0.1; G.tension = 0.9; G.chroma = 0.7
    sty(P, "strings", 4); sty(P, "winds", 3); sty(P, "texture", 5); on(P, "texture", true); dens(P, { "drums" }, 0.25)
    note("Tenso: harmonia experimental, tremolo de cordas, risers, pontilhismo")
  end
  if has(s, { "calmo", "relax", "ambient", "ambiente", "suave", "meditac", "sereno", "chill", "dormir" }) then
    allP(P, "density", function(v) return v * 0.6 end); G.bpm = clamp(G.bpm * 0.8, 50, 90); G.tension = min(G.tension, 0.3)
    on(P, "texture", true); sty(P, "texture", 1); sty(P, "strings", 1)
    note("Calmo: densidade reduzida, drone, pad longo")
  end
  if has(s, { "lofi", "lo%-fi", "lo fi" }) then
    G.swing = 0.4; G.humanize = 1; G.bpm = clamp(G.bpm, 70, 88); sty(P, "keys", 5); sty(P, "drums", 2); dens(P, { "drums" }, 0.4)
    sty(P, "bass", 1); note("Lo-fi: swing, humanizacao alta, Rhodes com strum")
  end
  if has(s, { "agressivo", "aggressive", "pesado", "heavy", "metal", "raiva", "energetico", "intenso" }) then
    G.bpm = clamp(max(G.bpm, 130), 120, 190); allP(P, "density", function(v) return v + 0.2 end)
    sty(P, "drums", 1); sty(P, "guitar", 3); sty(P, "bass", 1); on(P, "guitar", true); dens(P, { "drums" }, 0.8)
    note("Agressivo: andamento rapido, power chords, bateria densa")
  end
  if has(s, { "sonhador", "etereo", "onirico", "dreamy", "ethereal", "espacial", "cosmico" }) then
    setScale(G, "Lidio"); sty(P, "mallets", 2); sty(P, "texture", 3); sty(P, "guitar", 4); sty(P, "strings", 1)
    for _, id in ipairs({ "mallets", "texture", "guitar" }) do on(P, id, true) end
    allP(P, "density", function(v) return v * 0.75 end); note("Sonhador: Lidio, sinos, acorde evolutivo, guitarra com delay")
  end

  -- generos
  if has(s, { "jazz", "bebop", "bossa" }) then
    if s:find("bossa") then
      setScale(G, "Dorico"); G.bpm = clamp(G.bpm, 100, 130); sty(P, "guitar", 2); sty(P, "drums", 6); dens(P, { "drums" }, 0.35)
      on(P, "guitar", true); note("Bossa: violao alternado, percussao suave")
    else
      setScale(G, s:find("bebop") and "Bebop Dominante" or "Dorico"); G.swing = 0.6; sty(P, "drums", 3); sty(P, "bass", 2)
      sty(P, "keys", 2); sty(P, "brass", 5); sty(P, "lead", 2)
      note("Jazz: swing, walking bass, comping sem raiz, shout de metais")
    end
    G.richness = 0.9; G.hr = 3; G.tension = max(G.tension, 0.45)
  end
  if has(s, { "samba", "latino", "afro", "salsa", "tropical", "brasileir" }) then
    sty(P, "drums", 6); sty(P, "guitar", 1); sty(P, "bass", 3); on(P, "guitar", true); G.bpm = clamp(G.bpm, 95, 125)
    note("Latino/afro: clave, congas e baixo sincopado")
  end
  if has(s, { "eletronic", "edm", "house", "techno", "synth", "dance", "club" }) then
    G.bpm = clamp(max(G.bpm, 122), 118, 135); sty(P, "drums", 4); sty(P, "bass", 4); sty(P, "keys", 7); sty(P, "arp", 1)
    on(P, "arp", true); G.energyCurve = 4; G.philo = 4; G.mixT = 0.6; G.mixX = 0.1; note("Eletronico: four-on-floor, sub bass, arpejos, pulso")
  end
  if has(s, { "trap", "hip hop", "hiphop", "boom bap" }) then
    sty(P, "drums", 5); sty(P, "bass", 4); sty(P, "keys", 5); sty(P, "mallets", 2); on(P, "mallets", true); G.swing = 0.2
    note("Trap/hip hop: half-time, hi-hat rolls, 808")
  end
  if has(s, { "funk", "groove", "soul" }) then
    sty(P, "drums", 2); sty(P, "bass", 3); sty(P, "guitar", 5); sty(P, "keys", 2); sty(P, "brass", 1)
    on(P, "guitar", true); on(P, "brass", true); G.swing = max(G.swing, 0.25); G.bpm = clamp(G.bpm, 95, 112)
    note("Funk: ghost notes, slap sincopado, guitarra muted, stabs de metais")
  end
  if has(s, { "minimalis", "minimal", "reich", "repetitiv", "ciclic" }) then
    sty(P, "mallets", 1); sty(P, "winds", 5); sty(P, "keys", 7); sty(P, "arp", 6); G.philo = 2
    for _, id in ipairs({ "mallets", "winds", "keys", "arp" }) do on(P, id, true) end
    allP(P, "variation", function(v) return min(v, 0.25) end); note("Minimalista: celulas em fase, poliritmia, modal")
  end
  if has(s, { "japones", "oriental", "asiatic" }) then setScale(G, "Hirajoshi"); sty(P, "mallets", 5); note("Escala Hirajoshi") end
  if has(s, { "arabe", "arabic", "persa", "egipci" }) then setScale(G, "Dupla Harmonica"); note("Escala Dupla Harmonica") end
  if has(s, { "flamenco", "espanhol" }) then setScale(G, "Frigio Dominante"); sty(P, "guitar", 6); on(P, "guitar", true); note("Flamenco: Frigio dominante e rasgueado") end
  if has(s, { "gamelan", "balines", "indones" }) then sty(P, "mallets", 3); on(P, "mallets", true); setScale(G, "Pentatonica Menor"); note("Gamelan com vozes entrelacadas") end

  -- tom e escalas citados explicitamente tem prioridade sobre o clima
  parseKey(raw, s, G, log)
  -- escalas citadas sem tom
  local named = { { "tons inteiros", "Tons Inteiros" }, { "whole tone", "Tons Inteiros" }, { "octatonica", "Octatonica T-S" },
    { "diminuta", "Octatonica T-S" }, { "blues", "Blues" }, { "pentatonica", "Pentatonica Menor" },
    { "hirajoshi", "Hirajoshi" }, { "harmonica", "Menor Harmonica" }, { "melodica", "Menor Melodica" },
    { "alterada", "Alterada" }, { "bebop", "Bebop Dominante" } }
  for _, n in ipairs(named) do
    if s:find(n[1], 1, true) then setScale(G, n[2]); note("Escala: " .. n[2]); break end
  end

  -- compasso
  local a, b = s:match("(%d+)%s*/%s*(%d+)")
  if a then
    a, b = tonumber(a), tonumber(b)
    local found
    for i, p in ipairs(Mt.PRESETS) do if p[2] == a and p[3] == b and p[4] then found = i end end
    if found then G.meterIdx = found
    elseif a >= 1 and a <= 32 and (b == 2 or b == 4 or b == 8 or b == 16) then
      G.meterIdx = #Mt.PRESETS; G.customNum = a; G.customDen = b
    end
    note("Compasso " .. a .. "/" .. b)
  elseif has(s, { "valsa", "waltz" }) then G.meterIdx = 2; note("Valsa: 3/4")
  elseif has(s, { "balcan", "balkan" }) then G.meterIdx = 11; note("Balcanico: 7/8")
  elseif has(s, { "marcha", "march" }) then G.meterIdx = 3; note("Marcha: 2/4") end

  -- tempo, tamanho, dinamica
  local bpm = s:match("(%d+)%s*bpm")
  if bpm then G.bpm = clamp(tonumber(bpm), 40, 240); note("BPM " .. G.bpm)
  elseif has(s, { "lento", "slow", "devagar" }) then G.bpm = clamp(G.bpm * 0.8, 40, 240); note("Andamento mais lento")
  elseif has(s, { "rapido", "fast", "veloz", "acelerado" }) then G.bpm = clamp(G.bpm * 1.2, 40, 240); note("Andamento mais rapido") end
  local nb = s:match("(%d+)%s*compass") or s:match("(%d+)%s*bars")
  if nb then G.bars = clamp(tonumber(nb), 2, 64); note(G.bars .. " compassos") end
  if has(s, { "crescendo", "build", "climax", "dramatic", "crescente" }) then G.energyCurve = 2; G.layering = true; note("Intensidade crescente com camadas") end

  -- carater geral
  if has(s, { "cromatic", "chromatic" }) then G.chroma = 0.8; note("Mais cromatismo") end
  if has(s, { "livre", "free" }) then G.scaleFreedom = 0.9; note("Melodias mais livres (escala em vez de acordes)") end
  if has(s, { "swing", "balanco", "shuffle" }) and not s:find("jazz") then G.swing = 0.55; note("Swing") end
  if has(s, { "straight", "reto" }) then G.swing = 0; note("Sem swing") end
  if has(s, { "humaniz", "humano", "organico" }) then G.humanize = 0.85; note("Humanizacao alta") end
  if has(s, { "mecanic", "robotic", "quantizado" }) then G.humanize = 0; note("Sem humanizacao") end
  if has(s, { "simples", "simple", "basico" }) then
    allP(P, "complexity", function() return 0.2 end); allP(P, "variation", function() return 0.2 end); G.richness = 0.2; note("Simples: menos variacao e acordes basicos")
  end
  if has(s, { "complex", "sofisticad", "denso", "rico", "elaborad" }) then
    allP(P, "complexity", function() return 0.8 end); allP(P, "variation", function(v) return max(v, 0.6) end); G.richness = 0.85
    note("Complexo: ornamentos, variacoes e acordes ricos")
  end

  -- instrumentos citados: "sem X", "so X", "com X"
  local words = {}
  for w in s:gmatch("[%w]+") do words[#words + 1] = w end
  local only, mentioned, without = {}, {}, {}
  local function instOf(i)
    for id, ws in pairs(Tx.INSTR_WORDS) do
      for _, w in ipairs(ws) do if words[i] == w then return id end end
    end
  end
  for i = 1, #words do
    local id = instOf(i)
    if id then
      local p1, p2 = words[i - 1], words[i - 2]
      if p1 == "sem" or p1 == "without" or p1 == "no" or p2 == "sem" or p2 == "without" then without[id] = true
      elseif p1 == "so" or p1 == "apenas" or p1 == "somente" or p1 == "only" or p2 == "so" or p2 == "apenas" or p2 == "only" then only[id] = true
      else mentioned[id] = true end
    end
  end
  local anyOnly = next(only) ~= nil
  if anyOnly then
    for id in pairs(P) do P[id].on = only[id] and true or false end
    note("Somente: " .. table.concat((function() local t = {} for id in pairs(only) do t[#t + 1] = id end table.sort(t) return t end)(), ", "))
  end
  for id in pairs(mentioned) do if P[id] and not anyOnly then P[id].on = true end end
  for id in pairs(without) do if P[id] then P[id].on = false; note("Sem " .. id) end end
  if #log == 0 then note("Nenhuma palavra-chave reconhecida. Tente: sombrio, epico, jazz, lofi, 7/8, 90 bpm, re dorico, sem bateria...") end
  return log
end

Tx.PRESETS = {
  { "Cinematografico epico", "epico cinematografico em D minor, 16 compassos, crescendo" },
  { "Jazz noturno", "jazz sombrio em re dorico, 4/4, 92 bpm" },
  { "Lo-fi relaxante", "lofi calmo triste em la menor, 78 bpm, sem metais" },
  { "Misterio experimental", "tenso experimental atonal, 7/8, 96 bpm" },
  { "Bossa sonhadora", "bossa sonhadora em do lidio, 108 bpm" },
  { "Eletronico hipnotico", "eletronico minimalista, 124 bpm, 16 compassos" },
  { "Funk groove", "funk groove em mi dorico, 102 bpm" },
  { "Balcanico", "balcanico alegre, 7/8, 130 bpm, flauta e violao" },
  { "Valsa classica", "valsa classica romantica em re maior, 3/4, 96 bpm" },
  { "Flamenco intenso", "flamenco intenso em la frigio, 12/8, 110 bpm" },
}

if COMPOSER_TEST then
  return { U = U, Th = Th, Mt = Mt, Hm = Hm, Vc = Vc, Ins = Ins, Tx = Tx, Tp = Tp, Wr = Wr, Cp = Cp, Ui = Ui }
end
