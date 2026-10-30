--[[ WoWBoxer – the Automation bookmark (docs/automation-policy.md §2, docs/feedback-2026-10-30-night.md §5–§6): "Accept
  from" at the top (used by every accept), one tick per automation with one line about what it does, All on / All off,
  the "Levelling squad" preset and the reward rule. Options live in WoWBoxerDB.settings.auto (account-wide). ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local AP = {}
ns.AutomationPage = AP
local tab = { key = "automation", label = "Automation", icon = "Trade_Engineering",
  tip = "Squad automation: invites, quests, dialogs, resurrections, summons, the vendor – one tick each." }
--- Rail state word: OFF while no automation beyond resurrections and summons is on.
function tab.badge() if ns.Auto and not ns.Auto.anyOn() then return "OFF", "warn" end end

local function AU() return ns.Auto end
local function settings() return ns.Core.db.settings end

--- Set "Accept from"; Everyone warns first.
function AP.setFrom(v)
  if v == "everyone" then
    UI.Popup("Anyone can then invite you, share quests or summon you.", {
      { "Use Everyone", function() settings().acceptFrom = "everyone"; ns.Core.log("info", "automation: accept from everyone"); UI.Refresh() end,
        "Every automation that accepts something does it for anyone." },
      { "Cancel", function() UI.Refresh() end, "Keeps your choice." } })
    return
  end
  settings().acceptFrom = v
  ns.Core.log("info", "automation: accept from " .. v)
  UI.Refresh()
end

function tab.build(p)
  p.title = W.text(p, "GameFontNormalLarge", 15, W.GOLD)
  p.title:SetPoint("TOPLEFT", 2, -2)
  p.title:SetText("Automation")
  p.title.wbxCopy = "label"
  p.sub = W.text(p, "GameFontHighlightSmall", nil, W.MUTED)
  p.sub:SetPoint("LEFT", p.title, "RIGHT", 12, 0)
  p.sub:SetText("Hold Shift to skip once")
  p.sub.wbxCopy = "hint"
  p.from = W.dropdown(p, { width = 190,
    values = function() local v = {}; for _, f in ipairs(AU().FROM) do v[#v + 1] = { f[1], f[2] } end return v end,
    get = function() return AU().acceptFrom() end, set = function(v) AP.setFrom(v) end })
  local fl = W.labelled(p, "Accept from", p.from)
  fl:SetPoint("TOPRIGHT", p, "TOPRIGHT", -200, -6)
  W.ddTip(p.from, "Accept from", "Who the accepting automations react to: your WoWBoxer squad in your party (safest), also your friends and guild, or everyone.")
  p.ticks = {}
  local per = math.ceil(#AU().OPTIONS / 2)
  for i, o in ipairs(AU().OPTIONS) do
    local col, row = math.floor((i - 1) / per), (i - 1) % per
    local c = W.check(p, o[2], function(_, v) AU().set(o[1], v); ns.Core.log("info", "automation " .. o[1] .. (v and " on" or " off")); UI.Refresh() end)
    c:SetPoint("TOPLEFT", -2 + col * 336, -34 - row * 38)
    c.key = o[1]
    c.line = W.line(p, "GameFontHighlightSmall", 10, W.MUTED)
    c.line:SetPoint("TOPLEFT", 24 + col * 336, -34 - row * 38 - 19)
    c.line:SetWidth(306)
    c.line.wbxCopy = "data"
    W.tip(c, o[2], o[3])
    if AU().ACCEPTS[o[1]] then
      -- Advanced: this row's own "Accept from"
      c.own = W.dropdown(p, { width = 110,
        values = function() local v = { { "default", "Like the top" } }; for _, f in ipairs(AU().FROM) do if f[1] ~= "everyone" then v[#v + 1] = { f[1], f[2] } end end return v end,
        get = function() local t = settings().acceptOverride; return (type(t) == "table" and t[o[1]]) or "default" end,
        set = function(v) settings().acceptOverride = type(settings().acceptOverride) == "table" and settings().acceptOverride or {}
          settings().acceptOverride[o[1]] = v ~= "default" and v or nil; UI.Refresh() end })
      c.own:SetPoint("TOPLEFT", 200 + col * 336, -34 - row * 38 - 14)
      W.ddTip(c.own, "Accept from (this one)", "Advanced: this automation uses its own choice instead of the one at the top.")
    end
    p.ticks[#p.ticks + 1] = c
  end
  p.reward = W.dropdown(p, { width = 170,
    values = function() return { { "leader", "Reward: the leader's pick", "Followers take the reward the leader took." },
      { "value", "Reward: best vendor value", "Takes the reward that sells for most." }, { "ask", "Reward: ask me", "You pick the reward yourself." } } end,
    get = function() return AU().rewardRule() end, set = function(v) settings().autoReward = v; UI.Refresh() end })
  p.reward:SetPoint("BOTTOMRIGHT", -2, 4)
  W.ddTip(p.reward, "Quest rewards", "When a quest offers a choice: the leader's pick, the best vendor value, or ask.")
  p.preset = W.button(p, "Levelling squad", 130, 24, function() AU().preset(); ns.Core.log("info", "automation preset: levelling squad"); UI.Refresh() end,
    "Turns on invites, quests, quest sharing and turn-in, dialogs, resurrections, summons, role checks, selling junk and repairing.")
  p.preset.wbxBig = true
  p.preset:SetPoint("BOTTOMLEFT", 0, 2)
  p.allOn = W.button(p, "All on", 70, 24, function() AU().setAll(true); UI.Refresh() end, "Turns every automation on.")
  p.allOn:SetPoint("LEFT", p.preset, "RIGHT", 8, 0)
  p.allOff = W.button(p, "All off", 70, 24, function() AU().setAll(false); UI.Refresh() end, "Turns every automation off.")
  p.allOff:SetPoint("LEFT", p.allOn, "RIGHT", 6, 0)
  AP.panel = p
  AP.frame = p
end

function tab.refresh(p)
  local adv = ns.Advanced and ns.Advanced.on()
  p.from.Refresh(); p.reward.Refresh()
  for i, c in ipairs(p.ticks) do
    local o = AU().OPTIONS[i]
    c:SetChecked(AU().on(c.key))
    local text = o[3]
    if AU().ACCEPTS[c.key] then text = "Accepts from: " .. AU().FROM_SHORT[AU().acceptFrom(c.key)] .. " · " .. text end
    c.line:SetText(text)
    if c.own then c.own:SetShown(adv and true or false); c.own.Refresh() end
    c.line:SetWidth((c.own and adv) and 170 or 306)
  end
end

--- Open the Automation bookmark.
function AP.Open() UI.Open("automation") end
function AP.Refresh() if AP.panel and AP.panel:IsShown() then tab.refresh(AP.panel) end end

UI.RegisterTab(tab)
return AP
