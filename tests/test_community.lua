-- Community links and "Report a problem": one link table, the copy box (only on the player's click / slash command,
-- no keyboard in combat), the report (redaction, length, both flavours), and nothing is ever sent.
-- Run: lua tests/test_community.lua
local dir = (arg[0]:match("^(.*)/[^/]+$") or ".")
local H = dofile(dir .. "/harness.lua")
local Mock = dofile(dir .. "/wowmock.lua")

local function boot(opts)
  local W = Mock.new(H, opts)
  -- three loaded addons, one not loaded (by index, like the real API)
  local list = { { "WoWBoxer", "0.13.0" }, { "Questie", "9.1" }, { "Leatrix_Plus", "1.15" }, { "Details", "1.0", off = true } }
  W.env.C_AddOns.GetNumAddOns = function() return #list end
  W.env.C_AddOns.GetAddOnInfo = function(i) local a = list[i]; if a then return a[1], a[1], "", true, nil end end
  W.env.C_AddOns.IsAddOnLoaded = function(n) for _, a in ipairs(list) do if a[1] == n then return not a.off end end return false end
  W.env.C_AddOns.GetAddOnMetadata = function(n, field) for _, a in ipairs(list) do if a[1] == n and field == "Version" then return a[2] end end end
  W.env.GetPhysicalScreenSize = function() return 2560, 1440 end
  local ns = H.loadAddon({ env = W.env })
  W.fire("ADDON_LOADED", "WoWBoxer"); W.fire("PLAYER_LOGIN")
  W.flush()
  ns.Core.ensureMe()
  return W, ns
end

-- the links: one table, the real URLs, no GitHub
do
  local _, ns = boot({ name = "Dorin", class = "PALADIN", level = 20 })
  local L = ns.Links
  H.eq(L.discord, "https://discord.gg/Q5xwbqhKzQ", "Discord (general)")
  H.eq(L.discordHelp, "https://discord.gg/3GY3HgF3HC", "Discord help (#setup-help)")
  H.eq(L.youtube, "https://www.youtube.com/@WoWBoxerHQ", "YouTube")
  H.eq(L.website, "https://wowboxer.com/", "website")
  for _, d in ipairs(L.LIST) do H.ok(L[d[1]] and not L[d[1]]:find("github", 1, true), "listed link " .. d[1]) end
end

-- slash commands open the copy box with the right link, selected and focused; nothing is sent, nothing at login
do
  local W, ns = boot({ name = "Dorin", class = "PALADIN", level = 20 })
  local CM = ns.Community
  H.ok(not (CM.box and CM.box:IsShown()), "no box at login")
  local chatBefore = #W.chat
  for _, cmd in ipairs({ "discord", "youtube", "website" }) do
    W.env.SlashCmdList.WOWBOXER(cmd)
    H.ok(CM.box:IsShown(), cmd .. ": box shown")
    H.eq(CM.box.url:GetText(), ns.Links[cmd], cmd .. ": the URL in the box")
    H.eq(CM.focused, CM.box.url, cmd .. ": selected for Ctrl+C")
    H.ok(CM.box.hint:GetText():find("Ctrl+C", 1, true) ~= nil, cmd .. ": hint says Ctrl+C")
  end
  H.eq(#W.chat, chatBefore, "links print nothing in chat")
  -- typing cannot change the link
  CM.box.url:SetText("x"); CM.box.url._scripts.OnTextChanged(CM.box.url, true)
  H.eq(CM.box.url:GetText(), ns.Links.website, "the link cannot be edited")
  W.env.SlashCmdList.WOWBOXER("help")
  H.eq(CM.box.url:GetText(), ns.Links.discordHelp, "/wbx help: the #setup-help invite")
  H.ok(W.chatHas("|Haddon:WoWBoxer:discordHelp|h"), "/wbx help: a clickable help link in its own chat lines")
  -- in combat: shown without the keyboard
  W.combat = true
  W.env.SlashCmdList.WOWBOXER("discord")
  H.eq(CM.focused, nil, "combat: no keyboard focus")
  H.ok(CM.box.hint:GetText():find("Click", 1, true) ~= nil, "combat: 'click, then Ctrl+C'")
  W.combat = false
  -- the rail and the minimap menu
  ns.UI.Open("keys")
  H.ok(CM.railBlock and CM.railBlock:IsVisible() and #CM.railBlock.rows == 4, "rail: Community block with 4 rows")
  CM.railBlock.rows[2]:Click()
  H.eq(CM.box.url:GetText(), ns.Links.youtube, "rail: YouTube row")
  local labels = {}
  for _, it in ipairs(ns.Minimap.MENU) do labels[it[1]] = it[2] end
  H.ok(labels.Discord and labels.YouTube and labels.Website and labels["Report a problem"], "minimap menu has the links and the report")
  labels.Website()
  H.eq(CM.box.url:GetText(), ns.Links.website, "minimap: Website")
  H.eq(#W.sent, 0, "no addon messages")
  H.eq(W.calls.CreateMacro, nil, "nothing written")
end

-- the report, on both flavours
for _, toc in ipairs({ 16001, 11509 }) do
  local tag = toc == 16001 and "Forever" or "Era"
  local W, ns = boot({ name = "Dorin", class = "PALADIN", level = 24, toc = toc, spellbookStyle = toc == 11509 and "classic" or nil,
    party = { party1 = "Bodil" } })
  local s = ns.Core.me()
  table.insert(s.members, ns.State.newMember({ name = "Bodil", cls = "priest", race = "undead", unit = "party1", level = 24 }))
  for i = 1, 50 do ns.Core.log("info", "line " .. i .. " Dorin did a thing on Realm with Bodil at the Bottom Left Bar") end
  ns.Core.log("error", string.rep("long ", 100))
  local sentBefore = #W.sent
  local r = ns.Report.build({ what = "Dorin's Follow key did nothing" })
  H.ok(r:find("WoWBoxer problem report", 1, true) == 1, tag .. ": title")
  H.ok(r:find("What happened: <name>'s Follow key did nothing", 1, true) ~= nil, tag .. ": what happened, redacted")
  H.ok(r:find("Game: " .. (toc == 16001 and "forever" or "era"), 1, true) ~= nil, tag .. ": flavour")
  H.ok(r:find("interface " .. toc, 1, true) ~= nil, tag .. ": interface version")
  H.ok(r:find("Paladin 24", 1, true) ~= nil and r:find("squad slot 1 of 2", 1, true) ~= nil, tag .. ": class, level, slot")
  H.ok(r:find("Screen: 2560 x 1440", 1, true) ~= nil, tag .. ": screen size")
  H.ok(r:find("Macros: character", 1, true) ~= nil and r:find("Waiting until combat ends: nothing", 1, true) ~= nil, tag .. ": macros, queue")
  H.ok(r:find("Questie 9.1", 1, true) ~= nil and r:find("Leatrix_Plus 1.15", 1, true) ~= nil and not r:find("Details", 1, true), tag .. ": loaded addons + versions only")
  H.ok(not r:find("Dorin", 1, true) and not r:find("Bodil", 1, true) and not r:find("Realm", 1, true), tag .. ": no character, squad or realm name")
  H.ok(r:find("Bottom Left Bar", 1, true) ~= nil, tag .. ": a short name is not cut out of other words")
  local logLines = 0
  for l in r:gmatch("\n [%d:]+ %a+: [^\n]*") do logLines = logLines + 1; H.ok(#l <= ns.Report.LINE_MAX + 40, tag .. ": log line kept short") end
  H.eq(logLines, ns.Report.LOG_LINES, tag .. ": the last 30 log lines")
  H.ok(#r <= ns.Report.MAX_LEN, tag .. ": length capped (" .. #r .. ")")
  local named = ns.Report.build({ names = true })
  H.ok(named:find("Dorin", 1, true) ~= nil and named:find("Dorin-Realm", 1, true) ~= nil, tag .. ": names only when ticked")
  -- the window: report text, the names tick, Select all, the help link; never sends
  local f = ns.Community.ShowReport()
  H.ok(f:IsShown() and f.eb:GetText():find("WoWBoxer problem report", 1, true) ~= nil, tag .. ": report window filled")
  f.what:SetText("Bodil does not follow"); f.what._scripts.OnEnterPressed(f.what)
  H.ok(f.eb:GetText():find("What happened: <name> does not follow", 1, true) ~= nil, tag .. ": what happened goes in")
  f.names:Click()
  H.ok(f.eb:GetText():find("Bodil does not follow", 1, true) ~= nil, tag .. ": the tick puts names back")
  f.select:Click()
  H.eq(ns.Community.focused, f.eb, tag .. ": Select all selects the report")
  f.help:Click()
  H.eq(ns.Community.box.url:GetText(), ns.Links.discordHelp, tag .. ": the #setup-help invite")
  W.env.SlashCmdList.WOWBOXER("report")
  H.ok(f:IsShown(), tag .. ": /wbx report")
  H.eq(#W.sent, sentBefore, tag .. ": nothing sent")
  H.eq(W.calls.CreateMacro, nil, tag .. ": nothing written")
end

os.exit(H.report("community") and 0 or 1)
