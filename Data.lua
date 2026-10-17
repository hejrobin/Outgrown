-- Outgrown: Forever - Data
-- Every number the grading uses lives here so it can be tuned without
-- touching any logic. All values are Classic-style estimates, not verified
-- Forever data: expect to adjust them after playing.

local _, ns = ...
local D = {}
ns.Data = D

---------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------

-- Below this level gear is replaced so fast that grading is just noise.
D.GRACE_LEVEL = 10

-- Item score as a fraction of the expected score for your level.
--   below red    -> red    ("Needs upgrade")
--   below orange -> orange ("Upgrade soon")
-- buffer stops an item flickering between grades as you level: once an item
-- is flagged it has to climb this much above the cut-off to clear it.
D.THRESHOLDS = { orange = 0.90, red = 0.70, buffer = 0.03 }

-- Fallback used for items the addon can't fully rate (e.g. trinkets with
-- "Use:" effects): levels between required level and your level.
D.LEVEL_FALLBACK = { orange = 3, red = 8 }

-- Set to a spec key below to skip talent detection, e.g. "PALADIN_HOLY".
D.SPEC_OVERRIDE = nil

-- Print how the spec was worked out to chat, for troubleshooting.
D.DEBUG_SPEC = false

-- Talent points needed before the addon trusts talents to pick a role.
D.MIN_TALENT_POINTS = 5

-- Show the grey "% of a typical item" line in tooltips. Handy for tuning.
D.SHOW_DETAILS = true

---------------------------------------------------------------------------
-- Specs and roles (display names are in Strings.lua)
---------------------------------------------------------------------------
-- Specs for each talent tree, in the order the game lists the trees.
-- Classic order; check this against Forever's talent window.
-- A spec's key is CLASS_ID, e.g. "PALADIN_RETRIBUTION". Its display name is
-- in Strings.lua and its stat adjustments in D.SPEC_WEIGHTS below.
D.CLASS_SPECS = {
	WARRIOR = { { id = "ARMS", role = "melee_str" }, { id = "FURY", role = "melee_str" }, { id = "PROTECTION", role = "tank" } },
	PALADIN = { { id = "HOLY", role = "healer" }, { id = "PROTECTION", role = "tank" }, { id = "RETRIBUTION", role = "melee_str" } },
	HUNTER  = { { id = "BEASTMASTERY", role = "ranged" }, { id = "MARKSMANSHIP", role = "ranged" }, { id = "SURVIVAL", role = "ranged" } },
	ROGUE   = { { id = "ASSASSINATION", role = "melee_agi" }, { id = "COMBAT", role = "melee_agi" }, { id = "SUBTLETY", role = "melee_agi" } },
	PRIEST  = { { id = "DISCIPLINE", role = "healer" }, { id = "HOLY", role = "healer" }, { id = "SHADOW", role = "caster" } },
	SHAMAN  = { { id = "ELEMENTAL", role = "caster" }, { id = "ENHANCEMENT", role = "melee_str" }, { id = "RESTORATION", role = "healer" } },
	MAGE    = { { id = "ARCANE", role = "caster" }, { id = "FIRE", role = "caster" }, { id = "FROST", role = "caster" } },
	WARLOCK = { { id = "AFFLICTION", role = "caster" }, { id = "DEMONOLOGY", role = "caster" }, { id = "DESTRUCTION", role = "caster" } },
	DRUID   = { { id = "BALANCE", role = "caster" }, { id = "FERAL", role = "melee_agi" }, { id = "RESTORATION", role = "healer" } },
}

-- Role used before enough talent points are spent to pick a spec.
D.DEFAULT_ROLE = {
	WARRIOR = "melee_str",
	PALADIN = "melee_str",
	HUNTER = "ranged",
	ROGUE = "melee_agi",
	PRIEST = "caster",
	SHAMAN = "melee_str",
	MAGE = "caster",
	WARLOCK = "caster",
	DRUID = "caster",
}

---------------------------------------------------------------------------
-- Stat weights: how much one point of each stat is worth to a role.
-- Percent stats (CRIT, HIT, DODGE...) are per 1%.
-- ARMOR counts for everyone so that dropping to a lower armor type costs
-- something; tanks value it most.
---------------------------------------------------------------------------
D.WEIGHTS = {
	tank = {
		STA = 1.0,
		STR = 0.6,
		AGI = 0.6,
		ARMOR = 0.04,
		DEFENSE = 1.5,
		DODGE = 12,
		PARRY = 10,
		BLOCK = 5,
		BLOCKVALUE = 0.2,
		HIT = 8,
		AP = 0.25,
		DPS = 2,
		INT = 0.05,
		SPI = 0.05,
	},
	melee_str = {
		STR = 1.0,
		AGI = 0.7,
		STA = 0.35,
		AP = 0.5,
		CRIT = 12,
		HIT = 12,
		DPS = 7,
		INT = 0.05,
		SPI = 0.05,
		ARMOR = 0.02,
	},
	melee_agi = {
		AGI = 1.0,
		STR = 0.55,
		STA = 0.35,
		AP = 0.5,
		CRIT = 13,
		HIT = 13,
		DPS = 7,
		INT = 0.05,
		SPI = 0.05,
		ARMOR = 0.015,
	},
	ranged = {
		AGI = 1.0,
		INT = 0.35,
		STA = 0.35,
		STR = 0.05,
		SPI = 0.1,
		RAP = 0.45,
		AP = 0.1,
		CRIT = 13,
		HIT = 13,
		DPS = 6,
		ARMOR = 0.015,
	},
	caster = {
		INT = 0.8,
		SPI = 0.35,
		STA = 0.45,
		SP = 0.9,
		SCHOOL_SP = 0.6,
		SPELLCRIT = 10,
		SPELLHIT = 10,
		MP5 = 1.2,
		ARMOR = 0.01,
	},
	healer = {
		INT = 0.9,
		SPI = 0.7,
		STA = 0.35,
		HEAL = 0.5,
		SP = 0.55,
		MP5 = 1.5,
		SPELLCRIT = 8,
		ARMOR = 0.01,
	},
}

---------------------------------------------------------------------------
-- Spec adjustments: only the stats where a spec differs from its role.
-- Anything not listed here uses the role's weight above. 0 = worthless.
---------------------------------------------------------------------------
D.SPEC_WEIGHTS = {
	-- No mana: Intellect and Spirit do nothing.
	WARRIOR_ARMS        = { INT = 0, SPI = 0 },
	WARRIOR_FURY        = { INT = 0, SPI = 0 },
	WARRIOR_PROTECTION  = { INT = 0, SPI = 0 },
	ROGUE_ASSASSINATION = { INT = 0, SPI = 0 },
	ROGUE_COMBAT        = { INT = 0, SPI = 0 },
	ROGUE_SUBTLETY      = { INT = 0, SPI = 0 },

	-- Mana users: Intellect for the mana pool, Spirit stays low.
	PALADIN_HOLY        = { INT = 1.0, SPI = 0.2 },
	PALADIN_PROTECTION  = { INT = 0.3, SPI = 0.05, SP = 0.3 },
	PALADIN_RETRIBUTION = { INT = 0.3, SPI = 0.05, SP = 0.1 },
	SHAMAN_ENHANCEMENT  = { INT = 0.25, SPI = 0.05 },

	-- Hunters already have their own role.
	HUNTER_BEASTMASTERY = {},
	HUNTER_MARKSMANSHIP = {},
	HUNTER_SURVIVAL     = { AGI = 1.1 },

	-- Healers: Spirit matters more for some than others.
	PRIEST_DISCIPLINE   = { SPI = 0.6 },
	PRIEST_HOLY         = { SPI = 0.8 },
	SHAMAN_RESTORATION  = { SPI = 0.4, MP5 = 1.8 },
	DRUID_RESTORATION   = { SPI = 0.9 },

	-- Casters
	PRIEST_SHADOW       = { SPI = 0.5 },
	SHAMAN_ELEMENTAL    = { SPI = 0.25 },
	MAGE_ARCANE         = { SPI = 0.45 },
	MAGE_FIRE           = {},
	MAGE_FROST          = {},
	WARLOCK_AFFLICTION  = { SPI = 0.25 },
	WARLOCK_DEMONOLOGY  = { STA = 0.55 },
	WARLOCK_DESTRUCTION = {},
	DRUID_BALANCE       = { SPI = 0.45 },

	-- Cat and bear forms turn Strength into attack power too.
	DRUID_FERAL         = { STR = 0.9, INT = 0.05, SPI = 0.05 },
}

-- How much weapon DPS counts in each weapon slot.
D.DPS_SLOT_FACTOR = {
	melee  = { main = 1.0, off = 0.5, ranged = 0 },
	ranged = { main = 0.1, off = 0.1, ranged = 1.0 },
}
D.ROLE_DPS_TABLE = {
	tank = "melee", melee_str = "melee", melee_agi = "melee", ranged = "ranged",
}

---------------------------------------------------------------------------
-- Baseline: what a typical uncommon (green) item for your level is worth.
---------------------------------------------------------------------------

-- Stat points on a full-size slot item, per character level.
D.BUDGET_PER_LEVEL = 0.55

-- Share of those points a well-suited item turns into weighted value
-- (usually a main stat plus Stamina).
D.ROLE_EFFICIENCY = 0.65

-- Stat budget per slot, relative to a chest piece.
D.SLOT_BUDGET = {
	INVTYPE_HEAD = 1.0,
	INVTYPE_CHEST = 1.0,
	INVTYPE_ROBE = 1.0,
	INVTYPE_LEGS = 1.0,
	INVTYPE_SHOULDER = 0.74,
	INVTYPE_HAND = 0.74,
	INVTYPE_WAIST = 0.74,
	INVTYPE_FEET = 0.74,
	INVTYPE_WRIST = 0.55,
	INVTYPE_NECK = 0.55,
	INVTYPE_CLOAK = 0.55,
	INVTYPE_FINGER = 0.55,
	INVTYPE_TRINKET = 0.55,
	INVTYPE_HOLDABLE = 0.55,
	INVTYPE_SHIELD = 0.55,
	INVTYPE_WEAPON = 0.42,
	INVTYPE_WEAPONMAINHAND = 0.42,
	INVTYPE_WEAPONOFFHAND = 0.42,
	INVTYPE_2HWEAPON = 0.6,
	INVTYPE_RANGED = 0.32,
	INVTYPE_RANGEDRIGHT = 0.32,
	INVTYPE_THROWN = 0.32,
	INVTYPE_RELIC = 0.32,
}

-- Casters' and healers' weapons carry their value as stats, not DPS.
D.CASTER_WEAPON_BUDGET = {
	INVTYPE_WEAPON = 0.55, INVTYPE_WEAPONMAINHAND = 0.55, INVTYPE_2HWEAPON = 1.0,
}

-- Expected weapon DPS = a * level + b
D.WEAPON_KIND = {
	INVTYPE_WEAPON = "oneHand",
	INVTYPE_WEAPONMAINHAND = "oneHand",
	INVTYPE_WEAPONOFFHAND = "oneHand",
	INVTYPE_2HWEAPON = "twoHand",
	INVTYPE_RANGED = "ranged",
	INVTYPE_RANGEDRIGHT = "ranged",
	INVTYPE_THROWN = "ranged",
}
D.EXPECTED_DPS = {
	oneHand = { 0.6, 2 },
	twoHand = { 0.8, 3 },
	ranged  = { 0.48, 2 },
}

-- Expected armor: chest armor per level for the best armor type the class can
-- wear, scaled by slot. 1 = Cloth, 2 = Leather, 3 = Mail, 4 = Plate.
D.ARMOR_PER_LEVEL = { [1] = 1.8, [2] = 3.6, [3] = 7.5, [4] = 12 }
D.ARMOR_SLOT = {
	INVTYPE_HEAD = 0.8125,
	INVTYPE_CHEST = 1.0,
	INVTYPE_ROBE = 1.0,
	INVTYPE_LEGS = 0.875,
	INVTYPE_SHOULDER = 0.75,
	INVTYPE_FEET = 0.6875,
	INVTYPE_HAND = 0.625,
	INVTYPE_WAIST = 0.5625,
	INVTYPE_WRIST = 0.4375,
}
D.SHIELD_ARMOR_PER_LEVEL = 22

-- Best armor type each class can wear.
D.CLASS_ARMOR = {
	WARRIOR = { base = 3, advanced = 4, unlockLevel = 40 },
	PALADIN = { base = 3, advanced = 4, unlockLevel = 40 },
	HUNTER  = { base = 2, advanced = 3, unlockLevel = 40 },
	SHAMAN  = { base = 2, advanced = 3, unlockLevel = 40 },
	ROGUE   = { base = 2 },
	DRUID   = { base = 2 },
	PRIEST  = { base = 1 },
	MAGE    = { base = 1 },
	WARLOCK = { base = 1 },
}

---------------------------------------------------------------------------
-- Upgrades (bags and quest rewards)
---------------------------------------------------------------------------

-- An item counts as an upgrade when it scores this much higher than what
-- you're wearing in that slot (0.05 = 5% better).
D.UPGRADE_MARGIN = 0.05

-- Quest rewards are marked even if their required level is up to this many
-- levels above you, since you'll often level up before handing the quest in.
D.QUEST_REWARD_LEVEL_AHEAD = 2

-- Only suggest armor of the best type your class can wear (mail for a level 19
-- paladin, say). The one exception: if what you're wearing in that slot is
-- already below that type, anything at least as good as it still counts.
D.UPGRADE_KEEP_ARMOR_TYPE = true

-- Classes that can use shields, and which class uses each relic type.
D.CLASS_SHIELDS = { WARRIOR = true, PALADIN = true, SHAMAN = true }
D.RELIC_CLASS = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" } -- Libram, Idol, Totem

-- Level each class learns to dual wield (classes not listed can't).
D.DUAL_WIELD_LEVEL = { WARRIOR = 1, ROGUE = 1, HUNTER = 20 }

---------------------------------------------------------------------------
-- Weapon proficiencies (weapon subclass IDs)
---------------------------------------------------------------------------
D.CLASS_WEAPONS = {
	WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
	PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
	HUNTER  = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
	ROGUE   = { 2, 3, 4, 7, 13, 15, 16, 18 },
	PRIEST  = { 4, 10, 15, 19 },
	SHAMAN  = { 0, 4, 10, 13, 15 },
	MAGE    = { 7, 10, 15, 19 },
	WARLOCK = { 7, 10, 15, 19 },
	DRUID   = { 4, 6, 10, 13, 15 },
}
-- 14 = Miscellaneous, 20 = Fishing Pole: anyone can equip these.
D.ANY_CLASS_WEAPONS = { [14] = true, [20] = true }

---------------------------------------------------------------------------
-- "Equip:" effects read from the tooltip (English client).
-- First match wins, so more specific patterns come first.
-- Equip lines that match nothing, and all "Use:" / "Chance on hit:" lines,
-- mark the item as not fully rated.
---------------------------------------------------------------------------
D.EQUIP_PATTERNS = {
	{ "Increases healing done by spells and effects by up to (%d+)",                    "HEAL" },
	{ "Increases damage and healing done by magical spells and effects by up to (%d+)", "SP" },
	{ "Increases damage done by %a+ spells and effects by up to (%d+)",                 "SCHOOL_SP" },
	{ "Increases spell power by (%d+)",                                                 "SP" },
	{ "Improves your chance to get a critical strike with spells by (%d+)%%",           "SPELLCRIT" },
	{ "Improves your chance to get a critical strike by (%d+)%%",                       "CRIT" },
	{ "Improves your chance to hit with spells by (%d+)%%",                             "SPELLHIT" },
	{ "Improves your chance to hit by (%d+)%%",                                         "HIT" },
	{ "Restores (%d+) mana per 5 sec",                                                  "MP5" },
	{ "%+(%d+) ranged Attack Power",                                                    "RAP" },
	{ "Increases ranged attack power by (%d+)",                                         "RAP" },
	{ "%+(%d+) Attack Power",                                                           "AP" },
	{ "Increases attack power by (%d+)",                                                "AP" },
	{ "Increases your chance to dodge an attack by (%d+)%%",                            "DODGE" },
	{ "Increases your chance to parry an attack by (%d+)%%",                            "PARRY" },
	{ "Increases your chance to block attacks with a shield by (%d+)%%",                "BLOCK" },
	{ "Increases the block value of your shield by (%d+)",                              "BLOCKVALUE" },
	{ "Increased Defense %+(%d+)",                                                      "DEFENSE" },
}
