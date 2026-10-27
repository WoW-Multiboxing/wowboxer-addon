--[[ WoWBoxer – multibox setup checklist (display only: it never follows, targets or sets focus for you). ]]
local _, ns = ...
local CL = {}
ns.Checklist = CL

--- {{ok=true|false|nil, text, hint}} – nil ok means "not relevant / info"
function CL.items()
  local Core, C, S = ns.Core, ns.Compat, ns.State
  local out = {}
  local function add(ok, text, hint, fix) out[#out + 1] = { ok = ok, text = text, hint = hint, fix = fix } end
  local s, m = Core.me()
  if not m then
    add(false, "This character is in a squad", "Squad tab: start a squad, add this character, or import your squad string.")
    return out
  end
  add(true, "This character is " .. m.name .. " in " .. s.name, m.leader and "Leader: plays normally." or ("Follower: assists the leader via " .. m.unit .. "."))
  local leader = S.leaderOf(s)
  local inParty = C.inParty()
  if #s.members > 1 then add(inParty, "In a party", inParty and "Group found." or "Invite your other characters (one manual invite per character).") end
  if not m.leader and leader then
    local unitOfLeader = C.partyUnitOf(leader.name)
    if m.unit == "focus" then
      local f = C.unitName("focus")
      local okf = f ~= nil and f:lower() == leader.name:lower()
      add(okf, "Focus is " .. leader.name, okf and "Your keys assist your focus." or "Target " .. leader.name .. " and press your Focus key (after every login).")
    elseif unitOfLeader then
      add(unitOfLeader == m.unit, leader.name .. " is " .. unitOfLeader .. " on this client",
        unitOfLeader == m.unit and "Matches your unit." or ("Your keys use " .. m.unit .. ". Fix switches them to " .. unitOfLeader .. "; then update your keys."),
        unitOfLeader ~= m.unit and { label = "Use " .. unitOfLeader, fn = function() Core.setPlaysAs(unitOfLeader) end } or nil)
    elseif inParty then
      add(nil, "Leader's party slot unknown", "Names can be hidden in this client; check that " .. leader.name .. " is " .. m.unit .. " yourself.")
    end
  end
  local ctx = Core.compute()
  if ctx then
    local c = ctx.macros.counts
    local made = c.same + c.update
    add(ctx.macros.changes == 0 and c.noslot == 0, made .. " keys created, " .. ctx.macros.changes .. " to create or update",
      c.noslot > 0 and (c.noslot .. (c.noslot == 1 and " key has" or " keys have") .. " no free macro slot: delete a macro in /macro, or leave a key out (right-click it in the book).") or (ctx.macros.free .. " character macro slots free."))
    local b = ctx.bars.counts
    add(b.occupied + b.empty + b.ours + b.missing == 0, b.placed .. " keys on your bars",
      b.occupied > 0 and (b.occupied .. (b.occupied == 1 and " button holds" or " buttons hold") .. " something else: drag those keys yourself, or tick Replace above.") or "My keys: press Place all.")
    if not m.leader then add(nil, "Follow and Assist keys", "Press them yourself. WoWBoxer never follows or targets for you.") end
    if #ctx.missing > 0 then add(false, #ctx.missing .. " spell(s) to learn at your trainer", "They are left out of your keys until you learn them.") end
  end
  local TM = ns.Team
  if TM and TM.enabled() and #s.members > 1 and C.inParty() then
    local heard = 0
    for _, row in ipairs(TM.rows()) do if row.st and not row.me then heard = heard + 1 end end
    add(heard == #s.members - 1, "Team status: " .. heard .. " of " .. (#s.members - 1) .. " other clients report",
      heard == #s.members - 1 and "The team panel shows follow, target and mana. Display only." or "Clients without WoWBoxer (or not grouped yet) show 'no signal'.")
  end
  local changes = 0
  for _, cv in ipairs(Core.cvarPlan(Core.cdb.importCVars)) do if cv.status == "change" then changes = changes + 1 end end
  add(changes == 0, "Recommended settings", changes == 0 and "All set." or (changes .. " differ: see the list."))
  return out
end
