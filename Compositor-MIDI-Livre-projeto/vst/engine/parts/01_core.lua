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
