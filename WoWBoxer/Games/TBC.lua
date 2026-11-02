--[[ WoWBoxer – TBC Anniversary (interface 20506): the hand-written macro data of this game (the addon is the source of
  truth, docs/multi-flavor-plan.md §0). Loads on every client but only fills ns.Data on TBC Anniversary.
  Talent trees, spell ranks, trainer levels and icons from the client's tables (Data/TBC/, tools/fetch_client.py tbc);
  macro rules (incl. the spells new in TBC), recommended macros and starter builds in datasrc/tbc/.
  liveSpells: the spellbook alone decides which spells get macros (talent spells too, without a plan in WoWBoxer);
  the data's trainer levels still drive future spells, the trainer to-do and level-up offers.
  sequences: as in Games/Forever.lua, with TBC's spells (Steady Shot, Mangle, Earth Shield, Avenger's Shield …).
  Protected by tests/golden/tbc.json. ]]
local _, ns = ...
if ns.dataGame ~= "tbc" then return end
local D = ns.Data

D.game = { key = "tbc", name = "TBC Anniversary", maxLevel = 70, maxPoints = 61, wowhead = "tbc", liveSpells = true }

D.sequences = {
  warlock = {
    _all = {
      { id = "dps", label = "Damage", kind = "sequence", aim = "harm", pet = true,
        tiers = {
          simple = { steps = { { s = "Immolate", k = "dot" } }, filler = { "Shadow Bolt" } },
          medium = { steps = { { s = "Corruption", k = "dot" }, { s = "Immolate", k = "dot" } }, filler = { "Shadow Bolt" } },
          advanced = { steps = { { s = "Curse of Agony", k = "dot" }, { s = "Corruption", k = "dot" }, { s = "Siphon Life", k = "dot" }, { s = "Immolate", k = "dot" } }, filler = { "Shadow Bolt" } } } } } },
  priest = {
    _all = {
      { id = "dps", label = "Damage", kind = "sequence", aim = "harm",
        tiers = {
          simple = { steps = { { s = "Mind Blast", k = "cd" } }, filler = { "Smite" } },
          medium = { steps = { { s = "Shadow Word: Pain", k = "dot" }, { s = "Mind Blast", k = "cd" } }, filler = { "Smite" } },
          advanced = { steps = { { s = "Shadow Word: Pain", k = "dot" }, { s = "Mind Blast", k = "cd" }, { s = "Holy Fire" } }, filler = { "Smite" } } } },
      { id = "heal", label = "Heal", kind = "sequence", aim = "help", reset = "combat/12", fixedFill = 2,
        tiers = {
          simple = { steps = { { s = "Renew", k = "hot" } }, filler = { "Greater Heal", "Heal", "Lesser Heal" } },
          medium = { steps = { { s = "Renew", k = "hot" } }, filler = { "Greater Heal", "Heal", "Lesser Heal" } },
          advanced = { steps = { { s = "Renew", k = "hot" } }, filler = { "Greater Heal", "Heal", "Lesser Heal" } } } } } },
  paladin = {
    tank = {
      { id = "dps", label = "Threat", kind = "priority", aim = "melee", tip = "Judgement",
        tiers = {
          simple = { steps = { { s = "Holy Shield", self = true }, "Judgement" } },
          medium = { steps = { { s = "Holy Shield", self = true }, "Avenger's Shield", "Judgement" } },
          advanced = { steps = { { s = "Holy Shield", self = true }, "Avenger's Shield", "Judgement", { s = "Consecration", self = true } } } } } },
    _all = {
      { id = "dps", label = "Damage", kind = "priority", aim = "melee", tip = "Crusader Strike",
        tiers = {
          simple = { steps = { "Crusader Strike", "Judgement" } },
          medium = { steps = { "Hammer of Wrath", "Crusader Strike", "Judgement" } },
          advanced = { steps = { "Hammer of Wrath", "Crusader Strike", "Judgement", "Exorcism", { s = "Consecration", self = true } } } } } } },
  warrior = {
    tank = {
      { id = "dps", label = "Threat", kind = "priority", aim = "melee", tip = "Sunder Armor",
        tiers = {
          simple = { steps = { "Revenge", { "Devastate", "Sunder Armor" } } },
          medium = { steps = { "Shield Slam", "Revenge", { "Devastate", "Sunder Armor" } } },
          advanced = { steps = { "Shield Slam", "Revenge", { s = "Thunder Clap", self = true }, { "Devastate", "Sunder Armor" } } } } } },
    _all = {
      { id = "dps", label = "Damage", kind = "priority", aim = "melee", tip = "Mortal Strike",
        tiers = {
          simple = { steps = { "Execute", "Overpower", { "Mortal Strike", "Bloodthirst" } } },
          medium = { steps = { "Execute", "Overpower", { "Mortal Strike", "Bloodthirst" }, "Victory Rush" } },
          advanced = { steps = { "Execute", "Overpower", { "Mortal Strike", "Bloodthirst" }, { s = "Whirlwind", self = true }, "Victory Rush", "Slam" } } } } } },
  rogue = {
    _all = {
      { id = "dps", label = "Combo", kind = "sequence", aim = "harm", startattack = true, allowDup = true,
        tiers = {
          simple = { steps = { { s = { "Hemorrhage", "Sinister Strike" } }, { s = { "Hemorrhage", "Sinister Strike" } }, { s = { "Hemorrhage", "Sinister Strike" } }, { s = "Eviscerate" } } },
          medium = { steps = { { s = { "Hemorrhage", "Sinister Strike" } }, { s = { "Hemorrhage", "Sinister Strike" } }, { s = "Slice and Dice" }, { s = { "Hemorrhage", "Sinister Strike" } }, { s = { "Hemorrhage", "Sinister Strike" } }, { s = { "Hemorrhage", "Sinister Strike" } }, { s = "Eviscerate" } } },
          advanced = { steps = { { s = { "Hemorrhage", "Sinister Strike" } }, { s = { "Hemorrhage", "Sinister Strike" } }, { s = "Slice and Dice" }, { s = { "Hemorrhage", "Sinister Strike" } }, { s = { "Hemorrhage", "Sinister Strike" } }, { s = { "Hemorrhage", "Sinister Strike" } }, { s = { "Hemorrhage", "Sinister Strike" } }, { s = "Eviscerate" } } } } } } },
  hunter = {
    _all = {
      { id = "dps", label = "Shots", kind = "priority", aim = "ranged", pet = true, autoshot = true, tip = "Arcane Shot",
        tiers = {
          simple = { steps = { "Arcane Shot", "Steady Shot" } },
          medium = { steps = { "Kill Command", "Arcane Shot", { "Steady Shot", "Aimed Shot" } } },
          advanced = { steps = { "Kill Command", "Arcane Shot", "Multi-Shot", { "Steady Shot", "Aimed Shot" } } } } } } },
  mage = {
    _all = {
      { id = "dps", label = "Damage", kind = "sequence", aim = "harm",
        tiers = {
          simple = { steps = { { s = "Fire Blast", k = "cd" } }, filler = { "Frostbolt", "Fireball" } },
          medium = { steps = { { s = "Fire Blast", k = "cd" }, { s = "Ice Lance", k = "cd" } }, filler = { "Frostbolt", "Fireball" } },
          advanced = { steps = { { s = "Pyroblast" }, { s = "Fire Blast", k = "cd" }, { s = "Ice Lance", k = "cd" } }, filler = { "Frostbolt", "Fireball" } } } } } },
  shaman = {
    melee = {
      { id = "dps", label = "Damage", kind = "priority", aim = "melee", tip = "Stormstrike",
        tiers = {
          simple = { steps = { "Stormstrike", "Earth Shock" } },
          medium = { steps = { "Stormstrike", { "Flame Shock", "Earth Shock" } } },
          advanced = { steps = { "Stormstrike", { "Flame Shock", "Earth Shock" }, { s = "Fire Nova Totem", self = true } } } } } },
    healer = {
      { id = "heal", label = "Heal", kind = "sequence", aim = "help", reset = "combat/12", fixedFill = 2,
        tiers = {
          simple = { steps = { { s = "Earth Shield", k = "hot" } }, filler = { "Healing Wave" } },
          medium = { steps = { { s = "Earth Shield", k = "hot" } }, filler = { "Healing Wave" } },
          advanced = { steps = { { s = "Earth Shield", k = "hot" }, { s = "Chain Heal" } }, filler = { "Healing Wave" } } } },
      { id = "dps", label = "Damage", kind = "sequence", aim = "harm",
        tiers = {
          simple = { steps = { { s = "Flame Shock", k = "dot" } }, filler = { "Lightning Bolt" } },
          medium = { steps = { { s = "Flame Shock", k = "dot" } }, filler = { "Lightning Bolt" } },
          advanced = { steps = { { s = "Flame Shock", k = "dot" } }, filler = { "Lightning Bolt" } } } } },
    _all = {
      { id = "dps", label = "Damage", kind = "sequence", aim = "harm",
        tiers = {
          simple = { steps = { { s = "Flame Shock", k = "dot" } }, filler = { "Lightning Bolt" } },
          medium = { steps = { { s = "Flame Shock", k = "dot" }, { s = "Chain Lightning", k = "cd" } }, filler = { "Lightning Bolt" } },
          advanced = { steps = { { s = "Flame Shock", k = "dot" }, { s = "Chain Lightning", k = "cd" } }, filler = { "Lightning Bolt" } } } } } },
  druid = {
    tank = {
      { id = "dps", label = "Threat", kind = "priority", aim = "melee", tip = "Maul",
        tiers = {
          simple = { steps = { "Mangle (Bear)", "Maul" } },
          medium = { steps = { "Mangle (Bear)", "Lacerate", "Maul" } },
          advanced = { steps = { "Mangle (Bear)", "Lacerate", "Swipe", "Maul" } } } } },
    melee = {
      { id = "dps", label = "Combo", kind = "sequence", aim = "harm", startattack = true, allowDup = true,
        tiers = {
          simple = { steps = { { s = { "Mangle (Cat)", "Claw" } }, { s = { "Mangle (Cat)", "Claw" } }, { s = { "Mangle (Cat)", "Claw" } }, { s = { "Ferocious Bite", "Rip" } } } },
          medium = { steps = { { s = "Rake", k = "dot" }, { s = { "Mangle (Cat)", "Claw" } }, { s = { "Mangle (Cat)", "Claw" } }, { s = { "Mangle (Cat)", "Claw" } }, { s = { "Ferocious Bite", "Rip" } } } },
          advanced = { steps = { { s = "Rake", k = "dot" }, { s = { "Mangle (Cat)", "Claw" } }, { s = { "Mangle (Cat)", "Claw" } }, { s = { "Mangle (Cat)", "Claw" } }, { s = { "Mangle (Cat)", "Claw" } }, { s = "Rip" }, { s = "Rake", k = "dot" },
            { s = { "Mangle (Cat)", "Claw" } }, { s = { "Mangle (Cat)", "Claw" } }, { s = { "Mangle (Cat)", "Claw" } }, { s = { "Mangle (Cat)", "Claw" } }, { s = { "Ferocious Bite", "Rip" } } } } } } },
    healer = {
      { id = "heal", label = "Heal", kind = "sequence", aim = "help", reset = "combat/12", fixedFill = 2,
        tiers = {
          simple = { steps = { { s = "Rejuvenation", k = "hot" } }, filler = { "Healing Touch" } },
          medium = { steps = { { s = "Rejuvenation", k = "hot" }, { s = "Regrowth", k = "hot" } }, filler = { "Healing Touch" } },
          advanced = { steps = { { s = "Rejuvenation", k = "hot" }, { s = "Lifebloom", k = "hot" }, { s = "Regrowth", k = "hot" } }, filler = { "Healing Touch" } } } },
      { id = "dps", label = "Damage", kind = "sequence", aim = "harm",
        tiers = {
          simple = { steps = { { s = "Moonfire", k = "dot" } }, filler = { "Wrath" } },
          medium = { steps = { { s = "Moonfire", k = "dot" } }, filler = { "Wrath" } },
          advanced = { steps = { { s = "Moonfire", k = "dot" } }, filler = { "Wrath" } } } } },
    _all = {
      { id = "dps", label = "Damage", kind = "sequence", aim = "harm",
        tiers = {
          simple = { steps = { { s = "Moonfire", k = "dot" } }, filler = { "Wrath" } },
          medium = { steps = { { s = "Moonfire", k = "dot" }, { s = "Insect Swarm", k = "dot" } }, filler = { "Wrath" } },
          advanced = { steps = { { s = "Insect Swarm", k = "dot" }, { s = "Moonfire", k = "dot" } }, filler = { "Starfire", "Wrath" } } } } } },
}
