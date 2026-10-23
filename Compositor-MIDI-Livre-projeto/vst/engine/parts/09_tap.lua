
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
