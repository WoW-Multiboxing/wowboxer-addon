--[[ WoWBoxer – hover probe (/wbx probe hover), read-only.
  For PROBE_SECONDS it samples 10 times a second: the frames under the mouse (GetMouseFoci, or GetMouseFocus on older
  clients), the game tooltip's owner, and how often our own code ran meanwhile (bar fit requests with their reasons,
  team panel refreshes). Each sample is one "probe:" line in WoWBoxerDB.log; tools/read_log.py counts them per second.
  It never moves, shows, hides or re-anchors anything (bug 12 Nov 2026: the tooltip flickered at the bar ends).
]]
local _, ns = ...
local PR = {}
ns.Probe = PR

PR.SECONDS = 5
PR.STEP = 0.1

local function G() return _G end

--- A readable name for a frame: its global name, else its parent's name + "/?" (anonymous children), else its type.
function PR.frameName(f)
  if type(f) ~= "table" then return "-" end
  local ok, n = pcall(function() return f.GetDebugName and f:GetDebugName() or f.GetName and f:GetName() end)
  if ok and type(n) == "string" and n ~= "" then return n end
  local p = f.GetParent and f:GetParent()
  local pn = p and p.GetName and p:GetName()
  if type(pn) == "string" and pn ~= "" then return pn .. "/?" end
  local okT, t = pcall(function() return f.GetObjectType and f:GetObjectType() end)
  return okT and t and ("<" .. t .. ">") or "?"
end

--- The frames under the mouse, top first, with strata:level.
function PR.foci()
  local g = G()
  local list = {}
  if type(g.GetMouseFoci) == "function" then
    local ok, r = pcall(g.GetMouseFoci)
    if ok and type(r) == "table" then list = r end
  elseif type(g.GetMouseFocus) == "function" then
    local ok, f = pcall(g.GetMouseFocus)
    if ok and f then list = { f } end
  end
  local out = {}
  for i, f in ipairs(list) do
    if i > 4 then break end
    local s = PR.frameName(f)
    local okS, st = pcall(function() return f:GetFrameStrata() end)
    local okL, lv = pcall(function() return f:GetFrameLevel() end)
    if okS and st then s = s .. "@" .. tostring(st) .. ":" .. tostring(okL and lv or "?") end
    out[#out + 1] = s
  end
  return #out > 0 and table.concat(out, ">") or "-"
end

--- The game tooltip's owner while it is shown, else "-".
function PR.tipOwner()
  local T = G().GameTooltip
  if not (T and T.IsShown and T:IsShown()) then return "-" end
  local ok, o = pcall(function() return T:GetOwner() end)
  return ok and o and PR.frameName(o) or "?"
end

--- Our code reports here while a probe runs (cheap no-op otherwise).
function PR.note(kind, reason)
  local r = PR.run
  if not r then return end
  r.counts[kind] = (r.counts[kind] or 0) + 1
  if reason then r.reasons[#r.reasons + 1] = kind .. ":" .. tostring(reason) end
end

local function sample()
  local r = PR.run
  if not r then return end
  r.n = r.n + 1
  local t = r.n * PR.STEP
  local reasons = #r.reasons > 0 and (" why=" .. table.concat(r.reasons, ";")) or ""
  local line = string.format("probe: t=%.1f foci=%s tip=%s fit=%d team=%d%s", t, PR.foci(), PR.tipOwner(),
    r.counts.fit or 0, r.counts.team or 0, reasons)
  r.counts, r.reasons = {}, {}
  ns.Core.log("info", line)
  if t >= PR.SECONDS - 0.001 then
    PR.run = nil
    ns.Core.log("info", "probe: done")
    ns.Core.print("Hover probe done – /reload so the log is saved.")
    return
  end
  G().C_Timer.After(PR.STEP, sample)
end

--- /wbx probe hover: start sampling (again from 0 if one is running).
function PR.hover()
  local g = G()
  if not (g.C_Timer and g.C_Timer.After) then ns.Core.print("Hover probe: no timer on this client."); return false end
  local fresh = PR.run == nil
  PR.run = { n = 0, counts = {}, reasons = {} }
  ns.Core.log("info", string.format("probe: hover start (%d s, %d per second)", PR.SECONDS, math.floor(1 / PR.STEP + 0.5)))
  ns.Core.print(string.format("Hover probe: keep the mouse on the flickering button for %d seconds.", PR.SECONDS))
  if fresh then g.C_Timer.After(PR.STEP, sample) end
  return true
end

return PR
