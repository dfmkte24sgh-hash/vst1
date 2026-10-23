
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
