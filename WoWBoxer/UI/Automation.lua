--[[ WoWBoxer – the Automation bookmark (docs/automation-policy.md §2, docs/feedback-2026-10-30-night.md §5–§6): "Accept
  from" at the top (used by every accept), one tick per automation with one line about what it does, All on / All off,
  the "Default squad values" preset and the reward rule. Options live in WoWBoxerDB.settings.auto (account-wide). ]]
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
  local shown, subs = {}, {}
  for _, o in ipairs(AU().OPTIONS) do if o[6] then subs[o[6]] = o else shown[#shown + 1] = o end end
  local per = math.ceil(#shown / 2)
  local themed = W.themed()
  -- rows get a little tighter when a column holds more than 9 (the buttons at the bottom keep their room)
  local _, ph = UI.PanelSize()
  local pitch = math.max(33, math.min(38, math.floor(((ph or 420) - 32 - 36) / per)))
  local cardH = pitch - 3
  for i, o in ipairs(shown) do
    local col, row = math.floor((i - 1) / per), (i - 1) % per
    local function onClick(_, v) AU().set(o[1], v); ns.Core.log("info", "automation " .. o[1] .. (v and " on" or " off")); UI.Refresh() end
    local c
    if themed then
      -- a toggle card (docs/ui-redesign.md §3): switch, the option's name, one muted line about what it does
      local card = W.card(p)
      card:SetPoint("TOPLEFT", col * 336, -32 - row * pitch)
      card:SetSize(328, cardH)
      c = W.toggle(p, o[2], onClick)
      c:SetPoint("LEFT", card, "LEFT", 10, 0)
      c.card = card
      c.label:ClearAllPoints()
      c.label:SetPoint("TOPLEFT", card, "TOPLEFT", 66, cardH < 35 and -3 or -4)
      ns.Theme.font(c.label, "bold", 12)
      c.label:SetWordWrap(false); if c.label.SetMaxLines then c.label:SetMaxLines(1) end
      c.label.wbxTrunc = true
      c.label:SetWidth(222)
      c.line = W.line(card, "GameFontHighlightSmall", 10, W.MUTED)
      c.line:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 66, cardH < 35 and 3 or 5)
      c.line:SetWidth(222)
      -- ON / OFF at the right of the card; the card lifts while ON (§2 "On and off")
      c.word:ClearAllPoints()
      c.word:SetPoint("RIGHT", card, "RIGHT", -10, 0)
      c.wbxRow = card
      c.wbxPaint(c)
    else
      c = W.check(p, o[2], onClick)
      c:SetPoint("TOPLEFT", -2 + col * 336, -34 - row * pitch)
      c.line = W.line(p, "GameFontHighlightSmall", 10, W.MUTED)
      c.line:SetPoint("TOPLEFT", 24 + col * 336, -34 - row * pitch - 19)
      c.line:SetWidth(306)
    end
    c.key, c.opt = o[1], o
    c.line.wbxCopy = "data"
    local sub = subs[o[1]]
    if sub then
      -- a small on/off button for the sub-option (Warning sound inside Follow warning)
      c.sub = W.button(p, "Sound on", 72, 18, function()
        local v = not AU().on(sub[1]); AU().set(sub[1], v)
        ns.Core.log("info", "automation " .. sub[1] .. (v and " on" or " off")); UI.Refresh()
      end, { sub[2], sub[3] })
      c.sub.key = sub[1]
      if themed then c.sub:SetPoint("RIGHT", c.card, "RIGHT", -44, 0)
      else c.sub:SetPoint("TOPLEFT", 230 + col * 336, -34 - row * pitch) end
    end
    W.tip(c, o[2], o[3])
    if AU().ACCEPTS[o[1]] then
      -- Advanced: this row's own "Accept from"
      c.own = W.dropdown(p, { width = themed and 84 or 110,
        values = function() local v = { { "default", "Like the top" } }; for _, f in ipairs(AU().FROM) do if f[1] ~= "everyone" then v[#v + 1] = { f[1], f[2] } end end return v end,
        get = function() local t = settings().acceptOverride; return (type(t) == "table" and t[o[1]]) or "default" end,
        set = function(v) settings().acceptOverride = type(settings().acceptOverride) == "table" and settings().acceptOverride or {}
          settings().acceptOverride[o[1]] = v ~= "default" and v or nil; UI.Refresh() end })
      if themed then c.own:SetPoint("RIGHT", c.card, "RIGHT", -38, 0)
      else c.own:SetPoint("TOPLEFT", 200 + col * 336, -34 - row * pitch - 14) end
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
  p.preset = W.button(p, "Default squad values", 150, 24, function() AU().preset(); ns.Core.log("info", "automation preset: default squad values"); UI.Refresh() end,
    "Turns on invites, quests, quest sharing and turn-in, dialogs, resurrections, summons, role checks, selling junk and repairing.")
  p.preset.wbxBig = true
  W.primary(p.preset)
  p.preset:SetPoint("BOTTOMLEFT", 0, 2)
  p.defaults = W.button(p, "Default", 70, 24, function() AU().defaults(); ns.Core.log("info", "automation: default"); UI.Refresh() end,
    "WoWBoxer's recommendation: everything on except Accept any quest, Abandon together, Restock reagents and Auto-equip.")
  p.defaults:SetPoint("LEFT", p.preset, "RIGHT", 8, 0)
  p.allOn = W.button(p, "All on", 70, 24, function() AU().setAll(true); UI.Refresh() end, "Turns every automation on.")
  p.allOn:SetPoint("LEFT", p.defaults, "RIGHT", 6, 0)
  p.allOff = W.button(p, "All off", 70, 24, function() AU().setAll(false); UI.Refresh() end, "Turns every automation off.")
  p.allOff:SetPoint("LEFT", p.allOn, "RIGHT", 6, 0)
  AP.panel = p
  AP.frame = p
end

function tab.refresh(p)
  local adv = ns.Advanced and ns.Advanced.on()
  p.from.Refresh(); p.reward.Refresh()
  for _, c in ipairs(p.ticks) do
    local o = c.opt
    c:SetChecked(AU().on(c.key))
    local text = o[3]
    if AU().ACCEPTS[c.key] then text = "Accepts from: " .. AU().FROM_SHORT[AU().acceptFrom(c.key)] .. " · " .. text end
    c.line:SetText(text)
    if c.own then c.own:SetShown(adv and true or false); c.own.Refresh() end
    if c.sub then W.setLabel(c.sub, AU().on(c.sub.key) and "Sound on" or "Sound off") end
    local narrow = (c.own and adv) or c.sub
    if c.card then c.line:SetWidth(narrow and 132 or 222); c.label:SetWidth(narrow and 132 or 222)
    else c.line:SetWidth(narrow and 170 or 306) end
  end
end

--- Open the Automation bookmark.
function AP.Open() UI.Open("automation") end
function AP.Refresh() if AP.panel and AP.panel:IsShown() then tab.refresh(AP.panel) end end

UI.RegisterTab(tab)
return AP
