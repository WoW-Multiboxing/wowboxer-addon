--[[ WoWBoxer – Classic Era: the hand-written macro data of this game (the addon is the source of truth,
  docs/multi-flavor-plan.md §0). Loads on every client but only fills ns.Data on Classic Era.
  Same as Forever until the Era data pipeline (plan step 3); protected by tests/golden/era.json.
  sequences: the built-in sequence keys per class and role (_all = every role). Each def has the tiers simple / medium /
  advanced; a step is a spell name or a list of alternatives (first learned wins); k: 'dot' | 'cd' | 'hot' | 'nuke'. ]]
local _, ns = ...
if ns.dataGame ~= "era" then return end
local D = ns.Data

D.sequences = {
  warlock = {
    _all = {
      { id = "dps", label = "Damage", kind = "sequence", aim = "harm", pet = true,
        tiers = {
          simple = { steps = { { s = "Immolate", k = "dot" } }, filler = { "Shadow Bolt" } },
          medium = { steps = { { s = "Corruption", k = "dot" }, { s = "Immolate", k = "dot" } }, filler = { "Shadow Bolt" } },
          advanced = { steps = { { s = "Bane of Agony", k = "dot" }, { s = "Corruption", k = "dot" }, { s = "Siphon Life", k = "dot" }, { s = "Immolate", k = "dot" } }, filler = { "Shadow Bolt" } } } } } },
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
      { id = "dps", label = "Threat", kind = "priority", aim = "melee", tip = "Holy Strike",
        tiers = {
          simple = { steps = { "Holy Strike", "Judgement" } },
          medium = { steps = { { s = "Holy Shield", self = true }, "Hammer of the Righteous", "Holy Strike", "Judgement" } },
          advanced = { steps = { { s = "Holy Shield", self = true }, "Hammer of the Righteous", "Holy Strike", "Judgement", { s = "Consecration", self = true } } } } } },
    _all = {
      { id = "dps", label = "Damage", kind = "priority", aim = "melee", tip = "Holy Strike",
        tiers = {
          simple = { steps = { "Holy Strike", "Judgement" } },
          medium = { steps = { "Hammer of Wrath", "Holy Strike", "Judgement" } },
          advanced = { steps = { "Hammer of Wrath", "Exorcism", "Holy Strike", "Judgement", { s = "Consecration", self = true } } } } } } },
  warrior = {
    tank = {
      { id = "dps", label = "Threat", kind = "priority", aim = "melee", tip = "Sunder Armor",
        tiers = {
          simple = { steps = { "Revenge", "Sunder Armor" } },
          medium = { steps = { "Shield Slam", "Revenge", "Sunder Armor" } },
          advanced = { steps = { "Shield Slam", "Revenge", { s = "Thunder Clap", self = true }, "Sunder Armor" } } } } },
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
          simple = { steps = { "Arcane Shot" } },
          medium = { steps = { "Arcane Shot", "Aimed Shot" } },
          advanced = { steps = { "Aimed Shot", "Arcane Shot", "Multi-Shot" } } } } } },
  mage = {
    _all = {
      { id = "dps", label = "Damage", kind = "sequence", aim = "harm",
        tiers = {
          simple = { steps = { { s = "Fire Blast", k = "cd" } }, filler = { "Frostfire Bolt", "Frostbolt", "Fireball" } },
          medium = { steps = { { s = "Fire Blast", k = "cd" }, { s = "Arcane Wrath", k = "cd" } }, filler = { "Frostfire Bolt", "Frostbolt", "Fireball" } },
          advanced = { steps = { { s = "Pyroblast" }, { s = "Fire Blast", k = "cd" }, { s = "Arcane Wrath", k = "cd" } }, filler = { "Frostfire Bolt", "Frostbolt", "Fireball" } } } } } },
  shaman = {
    melee = {
      { id = "dps", label = "Damage", kind = "priority", aim = "melee", tip = "Stormstrike",
        tiers = {
          simple = { steps = { "Stormstrike", "Earth Shock" } },
          medium = { steps = { "Stormstrike", { "Flame Shock", "Earth Shock" } } },
          advanced = { steps = { "Stormstrike", { "Flame Shock", "Earth Shock" }, { s = "Fire Nova", self = true } } } } } },
    healer = {
      { id = "heal", label = "Heal", kind = "sequence", aim = "help", reset = "combat/12", fixedFill = 2,
        tiers = {
          simple = { steps = { { s = "Riptide", k = "hot" } }, filler = { "Healing Wave" } },
          medium = { steps = { { s = "Riptide", k = "hot" } }, filler = { "Healing Wave" } },
          advanced = { steps = { { s = "Riptide", k = "hot" }, { s = "Chain Heal" } }, filler = { "Healing Wave" } } } },
      { id = "dps", label = "Damage", kind = "sequence", aim = "harm",
        tiers = {
          simple = { steps = { { s = "Flame Shock", k = "dot" } }, filler = { "Lightning Bolt" } },
          medium = { steps = { { s = "Flame Shock", k = "dot" } }, filler = { "Lightning Bolt" } },
          advanced = { steps = { { s = "Flame Shock", k = "dot" } }, filler = { "Lightning Bolt" } } } } },
    _all = {
      { id = "dps", label = "Damage", kind = "sequence", aim = "harm",
        tiers = {
          simple = { steps = { { s = "Flame Shock", k = "dot" } }, filler = { "Lightning Bolt" } },
          medium = { steps = { { s = "Flame Shock", k = "dot" }, { s = "Lava Burst", k = "cd" } }, filler = { "Lightning Bolt" } },
          advanced = { steps = { { s = "Flame Shock", k = "dot" }, { s = "Lava Burst", k = "cd" }, { s = "Chain Lightning", k = "cd" } }, filler = { "Lightning Bolt" } } } } } },
  druid = {
    tank = {
      { id = "dps", label = "Threat", kind = "priority", aim = "melee", tip = "Swipe",
        tiers = {
          simple = { steps = { "Primal Bite", "Swipe" } },
          medium = { steps = { "Primal Bite", { "Lacerate", "Swipe" } } },
          advanced = { steps = { "Primal Bite", { "Lacerate", "Swipe" } } } } } },
    melee = {
      { id = "dps", label = "Combo", kind = "sequence", aim = "harm", startattack = true, allowDup = true,
        tiers = {
          simple = { steps = { { s = "Claw" }, { s = "Claw" }, { s = "Claw" }, { s = { "Ferocious Bite", "Rip" } } } },
          medium = { steps = { { s = "Rake", k = "dot" }, { s = "Claw" }, { s = "Claw" }, { s = "Claw" }, { s = { "Ferocious Bite", "Rip" } } } },
          advanced = { steps = { { s = "Rake", k = "dot" }, { s = "Claw" }, { s = "Claw" }, { s = "Claw" }, { s = "Claw" }, { s = "Rip" }, { s = "Rake", k = "dot" },
            { s = "Claw" }, { s = "Claw" }, { s = "Claw" }, { s = "Claw" }, { s = { "Ferocious Bite", "Rip" } } } } } } },
    healer = {
      { id = "heal", label = "Heal", kind = "sequence", aim = "help", reset = "combat/12", fixedFill = 2,
        tiers = {
          simple = { steps = { { s = "Rejuvenation", k = "hot" } }, filler = { "Healing Touch" } },
          medium = { steps = { { s = "Rejuvenation", k = "hot" }, { s = "Regrowth", k = "hot" } }, filler = { "Healing Touch" } },
          advanced = { steps = { { s = "Rejuvenation", k = "hot" }, { s = "Wild Growth", k = "cd" }, { s = "Regrowth", k = "hot" } }, filler = { "Healing Touch" } } } },
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
