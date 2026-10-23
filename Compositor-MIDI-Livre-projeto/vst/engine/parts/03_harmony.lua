
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
