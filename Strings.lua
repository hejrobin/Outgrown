-- Outgrown: Forever - Strings
-- Every piece of text the addon shows to the player.
-- To translate the addon, this is the file to copy and change.

local _, ns = ...
local L = {}
ns.L = L

-- Tooltip grade lines
L.NEEDS_UPGRADE = "Outgrown: Needs upgrade"
L.UPGRADE_SOON = "Outgrown: Upgrade soon"
L.NOT_PROFICIENT = "Not proficient with this weapon type"

-- Grey tooltip detail line: percent, level, role name
L.DETAIL = "%d%% of a typical item for a level %d %s"
L.DETAIL_UNRATED = " (some effects not rated)"

-- Chat message on login/reload when any equipped item is flagged
L.LOGIN_MESSAGE = "You have outgrown some of your gear, open Character Info to find out more"

-- Chat line when D.DEBUG_SPEC has written spec details to the log
L.DEBUG_LOGGED = "|cff42b1feOutgrown:|r spec details logged. Type /reload, then open "
		.. "WTF\\Account\\<account>\\SavedVariables\\Outgrown.lua"

-- Who the item is compared for, in the detail line: "...for a level 30 <name>"
-- Spec names, used once talents decide the spec
L.SPEC_NAMES = {
	WARRIOR_ARMS = "Arms Warrior",
	WARRIOR_FURY = "Fury Warrior",
	WARRIOR_PROTECTION = "Protection Warrior",
	PALADIN_HOLY = "Holy Paladin",
	PALADIN_PROTECTION = "Protection Paladin",
	PALADIN_RETRIBUTION = "Retribution Paladin",
	HUNTER_BEASTMASTERY = "Beast Mastery Hunter",
	HUNTER_MARKSMANSHIP = "Marksmanship Hunter",
	HUNTER_SURVIVAL = "Survival Hunter",
	ROGUE_ASSASSINATION = "Assassination Rogue",
	ROGUE_COMBAT = "Combat Rogue",
	ROGUE_SUBTLETY = "Subtlety Rogue",
	PRIEST_DISCIPLINE = "Discipline Priest",
	PRIEST_HOLY = "Holy Priest",
	PRIEST_SHADOW = "Shadow Priest",
	SHAMAN_ELEMENTAL = "Elemental Shaman",
	SHAMAN_ENHANCEMENT = "Enhancement Shaman",
	SHAMAN_RESTORATION = "Restoration Shaman",
	MAGE_ARCANE = "Arcane Mage",
	MAGE_FIRE = "Fire Mage",
	MAGE_FROST = "Frost Mage",
	WARLOCK_AFFLICTION = "Affliction Warlock",
	WARLOCK_DEMONOLOGY = "Demonology Warlock",
	WARLOCK_DESTRUCTION = "Destruction Warlock",
	DRUID_BALANCE = "Balance Druid",
	DRUID_FERAL = "Feral Druid",
	DRUID_RESTORATION = "Restoration Druid",
}

-- Class names, used before talents decide the spec
L.CLASS_NAMES = {
	WARRIOR = "Warrior",
	PALADIN = "Paladin",
	HUNTER = "Hunter",
	ROGUE = "Rogue",
	PRIEST = "Priest",
	SHAMAN = "Shaman",
	MAGE = "Mage",
	WARLOCK = "Warlock",
	DRUID = "Druid",
}
