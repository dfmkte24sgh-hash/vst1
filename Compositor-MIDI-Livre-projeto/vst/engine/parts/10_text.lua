
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
