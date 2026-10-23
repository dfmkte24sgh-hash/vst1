
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
