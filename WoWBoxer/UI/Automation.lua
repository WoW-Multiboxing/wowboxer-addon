--[[ WoWBoxer – Setup → Automation (docs/automation-policy.md §2): one tick per automation with one line about what it does,
  All on / All off and the "Levelling squad" preset. The options live in WoWBoxerDB.settings.auto (account-wide, the
  same on every character). Automations only ever react to squad members in the party (Auto.lua). ]]
local _, ns = ...
local UI, W = ns.UI, ns.Widgets
local AP = {}
ns.AutomationPage = AP

local function AU() return ns.Auto end

local function build(parent)
  local f = W.box(parent, 0.11, 0.085, 0.05, 0.99)
  f:SetAllPoints(parent)
  f:SetFrameLevel((parent:GetFrameLevel() or 1) + 40)
  f:EnableMouse(true)
  f.wbxModal = true
  f:Hide()
  f.title = W.text(f, "GameFontNormalLarge", 15, W.GOLD)
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetText("Automation")
  f.title.wbxCopy = "label"
  f.sub = W.text(f, "GameFontHighlightSmall", nil, W.MUTED)
  f.sub:SetPoint("TOPLEFT", 12, -32)
  f.sub:SetPoint("TOPRIGHT", -12, -32)
  f.sub:SetText("Your squad only · hold Shift to skip")
  f.sub.wbxCopy = "hint"
  f.ticks = {}
  local per = math.ceil(#AU().OPTIONS / 2)
  for i, o in ipairs(AU().OPTIONS) do
    local col, row = math.floor((i - 1) / per), (i - 1) % per
    local c = W.check(f, o[2], function(_, v) AU().set(o[1], v); ns.Core.log("info", "automation " .. o[1] .. (v and " on" or " off")); AP.Refresh() end)
    c:SetPoint("TOPLEFT", 10 + col * 330, -52 - row * 36)
    c.key = o[1]
    c.line = W.text(f, "GameFontHighlightSmall", 10, W.MUTED)
    c.line:SetPoint("TOPLEFT", 36 + col * 330, -52 - row * 36 - 19)
    c.line:SetWidth(296)
    if c.line.SetMaxLines then c.line:SetMaxLines(1) end
    c.line:SetText(o[3])
    c.line.wbxCopy = "data"
    W.tip(c, o[2], o[3])
    f.ticks[#f.ticks + 1] = c
  end
  f.reward = W.dropdown(f, { width = 170,
    values = function() return { { "leader", "Reward: the leader's pick", "Followers take the reward the leader took." },
      { "value", "Reward: best vendor value", "Takes the reward that sells for most." }, { "ask", "Reward: ask me", "You pick the reward yourself." } } end,
    get = function() return AU().rewardRule() end, set = function(v) ns.Core.db.settings.autoReward = v; AP.Refresh() end })
  f.reward:SetPoint("BOTTOMLEFT", 12, 40)
  W.ddTip(f.reward, "Quest rewards", "When a quest offers a choice: the leader's pick, the best vendor value, or ask.")
  f.preset = W.button(f, "Levelling squad", 130, 24, function() AU().preset(); ns.Core.log("info", "automation preset: levelling squad"); AP.Refresh() end,
    "Turns on invites, quests, quest sharing and turn-in, dialogs, resurrections, summons, role checks, selling junk and repairing.")
  f.preset.wbxBig = true
  f.preset:SetPoint("BOTTOMLEFT", 10, 8)
  f.allOn = W.button(f, "All on", 70, 24, function() AU().setAll(true); AP.Refresh() end, "Turns every automation on.")
  f.allOn:SetPoint("LEFT", f.preset, "RIGHT", 8, 0)
  f.allOff = W.button(f, "All off", 70, 24, function() AU().setAll(false); AP.Refresh() end, "Turns every automation off.")
  f.allOff:SetPoint("LEFT", f.allOn, "RIGHT", 6, 0)
  f.close = W.button(f, "Close", 70, 24, function() f:Hide() end, "Back to Setup.")
  f.close:SetPoint("BOTTOMRIGHT", -10, 8)
  AP.frame = f
  return f
end

function AP.Open()
  UI.Open("setup")
  local f = AP.frame or build(UI.panels.setup)
  f:Show()
  AP.Refresh()
end
function AP.Refresh()
  local f = AP.frame
  if not (f and f:IsShown()) then return end
  for _, c in ipairs(f.ticks) do c:SetChecked(AU().on(c.key)) end
  f.reward.Refresh()
end

return AP
