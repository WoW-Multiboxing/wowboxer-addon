--[[ WoWBoxer – Classic Era: the hand-written macro data of this game (the addon is the source of truth,
  docs/multi-flavor-plan.md §0). Loads on every client but only fills ns.Data on Classic Era.
  Its own data since plan step 3: talent trees, spell ranks, trainer levels and icons from the client's tables
  (Data/Era/, tools/fetch_client.py era); macro rules, recommended macros and starter builds in datasrc/era/.
  sequences: the built-in sequence macros per class and role (_all = every role), tiers simple / medium / advanced;
  a step is a spell name or a list of alternatives (first learned wins); k: 'dot' | 'cd' | 'hot' | 'nuke'.
  Protected by tests/golden/era.json. ]]
local _, ns = ...
if ns.dataGame ~= "era" then return end
local D = ns.Data

--- The game's rules: max level, talent points at max level, the Wowhead path of talent links, and whether the live
--- spellbook alone decides which spells a character has.
D.game = { key = "era", name = "Classic Era", maxLevel = 60, maxPoints = 51, wowhead = "classic", liveSpells = false }

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
          medium = { steps = { { s = "Holy Shield", self = true }, "Judgement", { s = "Consecration", self = true } } },
          advanced = { steps = { { s = "Holy Shield", self = true }, "Hammer of Wrath", "Judgement", { s = "Consecration", self = true } } } } } },
    _all = {
      { id = "dps", label = "Damage", kind = "priority", aim = "melee", tip = "Judgement",
        tiers = {
          simple = { steps = { "Judgement" } },
          medium = { steps = { "Hammer of Wrath", "Judgement" } },
          advanced = { steps = { "Hammer of Wrath", "Exorcism", "Judgement", { s = "Consecration", self = true } } } } } } },
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
          medium = { steps = { "Execute", "Overpower", { "Mortal Strike", "Bloodthirst" }, { s = "Whirlwind", self = true } } },
          advanced = { steps = { "Execute", "Overpower", { "Mortal Strike", "Bloodthirst" }, { s = "Whirlwind", self = true }, "Slam" } } } } } },
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
          simple = { steps = { { s = "Fire Blast", k = "cd" } }, filler = { "Frostbolt", "Fireball" } },
          medium = { steps = { { s = "Fire Blast", k = "cd" }, { s = "Cone of Cold", k = "cd" } }, filler = { "Frostbolt", "Fireball" } },
          advanced = { steps = { { s = "Pyroblast" }, { s = "Fire Blast", k = "cd" }, { s = "Cone of Cold", k = "cd" } }, filler = { "Frostbolt", "Fireball" } } } } } },
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
          simple = { steps = { { s = "Lesser Healing Wave" } }, filler = { "Healing Wave" } },
          medium = { steps = { { s = "Lesser Healing Wave" } }, filler = { "Healing Wave" } },
          advanced = { steps = { { s = "Lesser Healing Wave" }, { s = "Chain Heal" } }, filler = { "Healing Wave" } } } },
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
          simple = { steps = { "Maul" } },
          medium = { steps = { "Swipe", "Maul" } },
          advanced = { steps = { { s = "Demoralizing Roar", self = true }, "Swipe", "Maul" } } } } },
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
          advanced = { steps = { { s = "Rejuvenation", k = "hot" }, { s = "Swiftmend", k = "cd" }, { s = "Regrowth", k = "hot" } }, filler = { "Healing Touch" } } } },
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
