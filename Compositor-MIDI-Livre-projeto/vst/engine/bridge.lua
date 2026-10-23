-- Ponte entre o plugin (C++) e o motor de composicao. Tudo que sai e JSON.
local M = ...
local U, Th, Mt, Hm, Cp, Ins, Tx, Tp = M.U, M.Th, M.Mt, M.Hm, M.Cp, M.Ins, M.Tx, M.Tp
local B = {}
local G, P = Cp.defaultG(), Cp.defaultP()
local lastResult

---------------------------------------------------------------- JSON
local function esc(s)
  return '"' .. tostring(s):gsub('[%c"\\]', function(c)
    local m = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    return m[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end
local function isArray(t)
  if getmetatable(t) and getmetatable(t).__obj then return false end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return true end
  return #t == n
end
local function enc(v)
  local t = type(v)
  if t == "nil" then return "null"
  elseif t == "boolean" then return v and "true" or "false"
  elseif t == "number" then
    if math.type(v) == "integer" then return tostring(v) end
    if v ~= v or v == math.huge or v == -math.huge then return "0" end
    return string.format("%.9g", v)
  elseif t == "string" then return esc(v)
  elseif t == "table" then
    local out = {}
    if isArray(v) then
      for i = 1, #v do out[i] = enc(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do out[#out + 1] = esc(k) .. ":" .. enc(v[k] ~= nil and v[k] or v[tonumber(k)]) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return "null"
end
local function obj(t) return setmetatable(t, { __obj = true }) end

---------------------------------------------------------------- metadados da interface
local LISTS = {
  notes = Th.NOTE_NAMES, scales = Th.scaleNames(), meters = Mt.presetNames(), dens = { "2", "4", "8", "16" },
  forms = Hm.FORMS, energy = Cp.ENERGY_NAMES, philos = Hm.PHILO_NAMES, swgrid = { "Colcheias", "Semicolcheias" },
  hr = { "Lento (2 compassos por acorde)", "1 acorde por compasso", "2 acordes por compasso", "Variavel (livre)", "Por pulso / grupo (rapido)" },
  tapmodes = Tp.MODES,
}
local function C(tab, key, label, kind, extra)
  local c = { tab = tab, key = key, label = label, kind = kind }
  for k, v in pairs(extra or {}) do c[k] = v end
  return obj(c)
end
local CONTROLS = {
  C("geral", "key", "Tonalidade", "combo", { items = "notes" }),
  C("geral", "scaleIdx", "Escala base", "combo", { items = "scales" }),
  C("geral", "meterIdx", "Compasso", "combo", { items = "meters" }),
  C("geral", "customNum", "Numerador", "int", { min = 1, max = 32, showKey = "meterIdx", showEq = #Mt.PRESETS }),
  C("geral", "customDen", "Denominador", "combo", { items = "dens", values = { 2, 4, 8, 16 }, showKey = "meterIdx", showEq = #Mt.PRESETS }),
  C("geral", "altGroup", "Agrupamento alternativo (3+2 vira 2+3)", "check"),
  C("geral", "meterSeq", "Sequencia de compassos", "text"),
  C("geral", "bars", "Compassos", "int", { min = 2, max = 64 }),
  C("geral", "bpm", "BPM (referencia / exportacao)", "int", { min = 40, max = 220 }),
  C("geral", "form", "Forma", "combo", { items = "forms" }),
  C("geral", "energyCurve", "Dinamica", "combo", { items = "energy" }),
  C("geral", "layering", "Camadas por intensidade", "check"),
  C("geral", "swing", "Swing", "float", { min = 0, max = 1 }),
  C("geral", "swingGrid", "Grade do swing", "combo", { items = "swgrid", values = { 8, 16 } }),
  C("geral", "humanize", "Humanizar", "float", { min = 0, max = 1 }),
  C("geral", "seed", "Semente", "int", { min = 1, max = 999999 }),
  C("harmonia", "philo", "Filosofia", "combo", { items = "philos" }),
  C("harmonia", "mixT", "Peso tonal", "float", { min = 0, max = 1, showKey = "philo", showEq = 4 }),
  C("harmonia", "mixM", "Peso modal", "float", { min = 0, max = 1, showKey = "philo", showEq = 4 }),
  C("harmonia", "mixX", "Peso experimental", "float", { min = 0, max = 1, showKey = "philo", showEq = 4 }),
  C("harmonia", "tension", "Tensao", "float", { min = 0, max = 1 }),
  C("harmonia", "chroma", "Cromatismo", "float", { min = 0, max = 1 }),
  C("harmonia", "borrow", "Emprestimo modal", "float", { min = 0, max = 1 }),
  C("harmonia", "richness", "Riqueza dos acordes", "float", { min = 0, max = 1 }),
  C("harmonia", "scaleFreedom", "Liberdade de escala (melodias)", "float", { min = 0, max = 1 }),
  C("harmonia", "hr", "Ritmo harmonico", "combo", { items = "hr" }),
  C("harmonia", "phraseSlots", "Acordes por frase", "int", { min = 1, max = 8 }),
  C("harmonia", "pedal", "Pedal na tonica (frases modais)", "check"),
  C("tap", "tapInfluence", "Influencia do ritmo tocado", "float", { min = 0, max = 1 }),
}

function B.meta()
  local ins = {}
  for i, d in ipairs(Ins.list) do
    ins[i] = obj({ id = d.id, label = d.label, ch = d.ch, prog = d.prog, styles = d.styles })
  end
  local pre = {}
  for i, p in ipairs(Tx.PRESETS) do pre[i] = obj({ name = p[1], text = p[2] }) end
  return enc(obj({ lists = obj(LISTS), controls = CONTROLS, instruments = ins, presets = pre }))
end

---------------------------------------------------------------- estado
local function profileOut()
  local tp = G.tapProfile
  if not tp then return nil end
  local w = {}
  for s = 0, tp.len - 1 do w[#w + 1] = tp.w[s] or 0 end
  return obj({ len = tp.len, w = w })
end

function B.state()
  local g = {}
  for k, v in pairs(G) do
    local t = type(v)
    if t == "number" or t == "boolean" or t == "string" then g[k] = v end
  end
  local p = {}
  for id, t in pairs(P) do
    local q = {}
    for k, v in pairs(t) do if type(v) == "number" or type(v) == "boolean" then q[k] = v end end
    p[id] = obj(q)
  end
  return enc(obj({ G = obj(g), P = obj(p), tapProfile = profileOut() }))
end

function B.set(scope, key, value)
  if scope == "G" then G[key] = value
  elseif P[scope] then P[scope][key] = value end
end

function B.save() return U.serialize({ G = G, P = P }) end
function B.load(s)
  local d = U.deserialize(s)
  if type(d) ~= "table" then return "false" end
  local dg, dp = Cp.defaultG(), Cp.defaultP()
  for k, v in pairs(d.G or {}) do if dg[k] ~= nil and type(v) == type(dg[k]) then dg[k] = v end end
  if type((d.G or {}).tapProfile) == "table" then dg.tapProfile = d.G.tapProfile end
  for id, t in pairs(d.P or {}) do
    if dp[id] and type(t) == "table" then
      for k, v in pairs(t) do if dp[id][k] ~= nil and type(v) == type(dp[id][k]) then dp[id][k] = v end end
    end
  end
  G, P = dg, dp
  return "true"
end

function B.reset()
  local intent = G.intent
  G, P = Cp.defaultG(), Cp.defaultP()
  G.intent = intent
end

---------------------------------------------------------------- geracao
function B.generate()
  local which = {}
  for _, d in ipairs(Ins.list) do if P[d.id].on then which[d.id] = true end end
  local res = Cp.run(G, P, which, { layer = true })
  lastResult = res
  local tracks = {}
  for _, d in ipairs(Ins.list) do
    local tk = res.tracks[d.id]
    if tk then
      local notes, cc = {}, {}
      for _, n in ipairs(tk.notes) do
        notes[#notes + 1] = math.floor(n.t * 1e5 + 0.5) / 1e5
        notes[#notes + 1] = math.floor(n.l * 1e5 + 0.5) / 1e5
        notes[#notes + 1] = n.p
        notes[#notes + 1] = n.v
      end
      for _, c in ipairs(tk.cc) do
        cc[#cc + 1] = math.floor(c.t * 1e5 + 0.5) / 1e5
        cc[#cc + 1] = c.cc
        cc[#cc + 1] = c.val
      end
      tracks[#tracks + 1] = obj({ id = d.id, label = d.label, ch = d.ch, prog = d.prog,
        style = d.styles[tk.P.style] or "", notes = notes, cc = cc })
    end
  end
  local bars = {}
  for i, b in ipairs(res.bars) do bars[i] = obj({ t0 = b.t0, len = b.len, name = b.name, energy = b.energy }) end
  local chords = {}
  local philoOf = {}
  for _, ph in ipairs(res.plan.phrases) do for k = ph.from, ph.to do philoOf[k] = ph end end
  for i, sl in ipairs(res.plan.slots) do
    local ph = philoOf[i]
    chords[i] = obj({ t0 = sl.t0, len = sl.len, name = sl.chord.name, scale = sl.chord.scaleName,
      philo = ph and ph.philo or 1, label = ph and ph.label or "A" })
  end
  local b1 = res.bars[1]
  return enc(obj({ total = res.total, bpm = G.bpm, tsNum = b1.num, tsDen = b1.den, tracks = tracks, bars = bars,
    chords = chords, plan = Hm.describe(res.plan) }))
end

---------------------------------------------------------------- tap e texto
function B.tap(csv, mode)
  Tp.reset()
  for x in tostring(csv):gmatch("[%d%.]+") do Tp.taps[#Tp.taps + 1] = tonumber(x) end
  local first = Mt.buildBars(G)[1]
  local info, err = Tp.analyze(G, mode, first.steps)
  if not info then return enc(obj({ ok = false, log = { err } })) end
  local log = Tp.apply(info, G, P, mode)
  table.insert(log, 1, "Analise: " .. info.summary)
  return enc(obj({ ok = true, log = log }))
end

function B.liveBpm(csv)
  Tp.reset()
  for x in tostring(csv):gmatch("[%d%.]+") do Tp.taps[#Tp.taps + 1] = tonumber(x) end
  return Tp.liveBpm() or 0
end

function B.forgetRhythm() G.tapProfile = nil end

function B.intent(text)
  G.intent = text
  return enc(Tx.apply(text, G, P))
end

return B
