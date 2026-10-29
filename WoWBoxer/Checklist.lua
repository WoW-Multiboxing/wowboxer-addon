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
    add(false, "No squad yet", "Squad tab: start a squad, add this character, or import your squad string.")
    return out
  end
  add(true, "Squad: " .. s.name, m.leader and "Leader: plays normally." or ("Follower: assists the leader via " .. m.unit .. "."))
  local leader = S.leaderOf(s)
  local inParty = C.inParty()
  if #s.members > 1 then add(inParty, "In a party", inParty and "Group found." or "Invite your other characters (one manual invite per character).") end
  if not m.leader and leader then
    local unitOfLeader = C.partyUnitOf(leader.name)
    if m.unit == "focus" then
      local f = C.unitName("focus")
      local okf = f ~= nil and f:lower() == leader.name:lower()
      add(okf, "Focus: " .. leader.name, okf and "Your macros assist your focus." or "Target " .. leader.name .. " and press your Focus macro (after every login).")
    elseif unitOfLeader then
      add(unitOfLeader == m.unit, leader.name .. " is " .. unitOfLeader .. " here",
        unitOfLeader == m.unit and "Matches your unit." or ("Your macros use " .. m.unit .. ". Fix switches them to " .. unitOfLeader .. "; then update your macros."),
        unitOfLeader ~= m.unit and { label = "Use " .. unitOfLeader, fn = function() Core.setPlaysAs(unitOfLeader) end } or nil)
    elseif inParty then
      add(nil, "Leader's slot unknown", "Names can be hidden in this client; check that " .. leader.name .. " is " .. m.unit .. " yourself.")
    end
  end
  -- keys 1–= that press a WBX macro directly (the 0.9.4 bind bug): offer to give them back to their buttons
  for _, l in ipairs(ns.Binds.lostButtons()) do
    add(false, "Your " .. l.key .. " presses " .. l.macro .. " directly", "So action button " .. l.slot .. " has no keybind. Give " .. l.key .. " back to button " .. l.slot ..
      " (the macro stays on your bars).", { label = "Give back", fn = function() Core.giveBack(l.key) end })
  end
  local ctx = Core.compute()
  if ctx then
    local c = ctx.macros.counts
    local made = c.same + c.update
    add(ctx.macros.changes == 0 and c.noslot == 0, "Macros: " .. made .. " made, " .. ctx.macros.changes .. " to do",
      c.noslot > 0 and (c.noslot .. (c.noslot == 1 and " macro has" or " macros have") .. " no free macro slot: delete a macro in /macro, or leave a macro out (right-click it in the book).") or (ctx.macros.free .. " character macro slots free."))
    local b = ctx.bars.counts
    add(b.occupied + b.empty + b.ours + b.missing == 0, b.placed .. " macros on bars",
      b.occupied > 0 and (b.occupied .. (b.occupied == 1 and " button holds" or " buttons hold") .. " something else: drag those macros yourself, or tick Replace above.") or "My macros: press Place all.")
    if not m.leader then
      -- Follow (line): display only; the Fix changes WoWBoxer data, the macro follows after Update keys
      local u, ahead, how = ns.Squad.lineFor(s, m)
      if ahead and how == "leader" then
        add(true, "Follow (line): you follow " .. ahead.name, "You are first in the line: both follow macros follow the leader (" .. u .. ").")
      elseif ahead and how == "party" then
        local fix = m.lineUnit ~= nil and u ~= m.lineUnit
        add(not fix, "Follow (line): you follow " .. ahead.name .. " (" .. u .. ")",
          fix and (ahead.name .. " is now " .. u .. ". Fix uses " .. u .. "; then update your macros.") or "Matches your Follow (line) macro.",
          fix and { label = "Use " .. u, fn = function() Core.setLineUnit(u) end } or nil)
      elseif ahead then
        add(false, ahead.name .. " is not in your party", how == "saved" and ("Follow (line) follows the last known slot (" .. u .. "); use Follow leader.")
          or "Follow (line) follows the leader until you group; use Follow leader.")
      end
      add(nil, "Follow and Assist", "Press them yourself. WoWBoxer never follows or targets for you.")
    end
    if #ctx.missing > 0 then add(false, #ctx.missing .. " spells to learn", "They are left out of your macros until you learn them.") end
  end
  local TM = ns.Team
  if TM and TM.enabled() and #s.members > 1 and C.inParty() then
    local heard = 0
    for _, row in ipairs(TM.rows()) do if row.st and not row.me then heard = heard + 1 end end
    add(heard == #s.members - 1, "Team status: " .. heard .. "/" .. (#s.members - 1) .. " report",
      heard == #s.members - 1 and "The team panel shows follow, target and mana. Display only." or "Clients without WoWBoxer (or not grouped yet) show 'no signal'.")
  end
  if ns.Auto and #s.members > 1 and not ns.Auto.anyOn() then
    add(nil, "Automation is off", "Invites, quests, dialogs, summons and the vendor for your squad: turn on Levelling squad, or choose on the Automation page.",
      { label = "Levelling squad", fn = function() ns.Auto.preset(); Core.log("info", "automation: levelling squad (checklist)"); Core.changed() end })
  end
  local changes = 0
  for _, cv in ipairs(Core.cvarPlan(Core.cdb.importCVars)) do if cv.status == "change" then changes = changes + 1 end end
  add(changes == 0, "Recommended settings", changes == 0 and "All set." or (changes .. " differ: see the list."))
  return out
end
