-- Outgrown: Forever - Grading
-- Scores an equipped item against what a typical item for your level and
-- role would be worth, and turns that into a grade: "red", "orange" or nil.

local _, ns = ...
local D = ns.Data
local G = {}
ns.Grading = G

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstantCompat = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemStatsCompat = (C_Item and C_Item.GetItemStats) or GetItemStats

-- Language-independent stat keys from GetItemStats. Equip effects are read
-- from the tooltip instead, so they are never counted twice.
local STAT_KEYS = {
	ITEM_MOD_STRENGTH_SHORT = "STR",
	ITEM_MOD_AGILITY_SHORT = "AGI",
	ITEM_MOD_STAMINA_SHORT = "STA",
	ITEM_MOD_INTELLECT_SHORT = "INT",
	ITEM_MOD_SPIRIT_SHORT = "SPI",
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
	RESISTANCE0_NAME = "ARMOR",
}

local SEVERITY = { orange = 1, red = 2 }

local itemCache = {} -- link -> parsed item
local lastGrade = {} -- slotId -> { link = ..., grade = ... }
local cachedRole
local weaponSlots    -- slotId -> "main" / "off" / "ranged"

---------------------------------------------------------------------------
-- Reading items
---------------------------------------------------------------------------
local scanTip

local function GetTooltipLines(link)
	local lines = {}

	if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
		local data = C_TooltipInfo.GetHyperlink(link)
		if data and data.lines then
			for _, line in ipairs(data.lines) do
				if line.leftText then lines[#lines + 1] = line.leftText end
			end
			return lines
		end
	end

	-- Older clients: read a hidden tooltip.
	if not scanTip then
		scanTip = CreateFrame("GameTooltip", "OutgrownForeverScanTooltip", nil, "GameTooltipTemplate")
	end
	scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	scanTip:ClearLines()
	scanTip:SetHyperlink(link)
	for i = 1, scanTip:NumLines() do
		local fs = _G["OutgrownForeverScanTooltipTextLeft" .. i]
		local text = fs and fs:GetText()
		if text then lines[#lines + 1] = text end
	end
	scanTip:Hide()
	return lines
end

local function StripColors(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function ParseEquipLine(text, values)
	for _, entry in ipairs(D.EQUIP_PATTERNS) do
		local amount = text:match(entry[1])
		if amount then
			values[entry[2]] = (values[entry[2]] or 0) + tonumber(amount)
			return true
		end
	end
	return false
end

-- Returns a parsed item, or nil if the game hasn't sent its data yet.
local function ParseItem(link)
	local cached = itemCache[link]
	if cached then return cached end

	local _, _, quality, _, reqLevel = GetItemInfoCompat(link)
	if quality == nil then return nil end

	local _, _, _, equipLoc, _, classID, subClassID = GetItemInfoInstantCompat(link)

	local item = {
		reqLevel = reqLevel,
		equipLoc = equipLoc,
		classID = classID,
		subClassID = subClassID,
		values = {},
		unrated = false,
	}

	local stats = GetItemStatsCompat and GetItemStatsCompat(link)
	if stats then
		for key, amount in pairs(stats) do
			local short = STAT_KEYS[key]
			if short then item.values[short] = (item.values[short] or 0) + amount end
		end
	end

	for _, raw in ipairs(GetTooltipLines(link)) do
		local text = StripColors(raw)
		local equip = text:match("^Equip: (.+)")
		if equip then
			if not ParseEquipLine(equip, item.values) then item.unrated = true end
		elseif text:match("^Use: ") or text:match("^Chance on hit: ") then
			item.unrated = true
		end
	end

	itemCache[link] = item
	return item
end

---------------------------------------------------------------------------
-- Role
---------------------------------------------------------------------------
-- Points per tree from each talent's rank (Classic-style GetTalentInfo,
-- where the 5th return value is the rank).
local function PointsFromTalents(numTabs)
	if not (GetNumTalents and GetTalentInfo) then return nil end
	local points, total = {}, 0
	for tab = 1, numTabs do
		local sum = 0
		local okCount, numTalents = pcall(GetNumTalents, tab)
		if okCount and type(numTalents) == "number" then
			for i = 1, numTalents do
				local okInfo, _, _, _, _, rank = pcall(GetTalentInfo, tab, i)
				if okInfo and type(rank) == "number" then sum = sum + rank end
			end
		end
		points[tab] = sum
		total = total + sum
	end
	return points, total
end

-- Points per tree from the tree summary. Older clients return
-- name, icon, pointsSpent; newer ones id, name, description, icon, pointsSpent.
local function PointsFromTrees(numTabs)
	if not GetTalentTabInfo then return nil end
	local points, total = {}, 0
	for tab = 1, numTabs do
		local info = { pcall(GetTalentTabInfo, tab) }
		local spent = 0
		if info[1] then
			if type(info[2]) == "number" then
				spent = info[6]
			else
				spent = info[4]
			end
		end
		spent = type(spent) == "number" and spent or 0
		points[tab] = spent
		total = total + spent
	end
	return points, total
end

-- Forever: the Classic talent functions are gone, and each talent tree is
-- exposed as a "specialization" whose 7th return value is the points spent
-- in it: id, name, description, icon, role, primaryStat, pointsSpent.
-- Trees are matched to D.CLASS_SPECS by name, falling back to their order.
local function GetSpecInfoFunction()
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
		return C_SpecializationInfo.GetSpecializationInfo
	end
	return GetSpecializationInfo
end

local function NumSpecializations()
	if GetNumSpecializations then
		local ok, n = pcall(GetNumSpecializations)
		if ok and type(n) == "number" and n > 0 then return n end
	end
	local classID = select(3, UnitClass("player"))
	if classID and C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID then
		local ok, n = pcall(C_SpecializationInfo.GetNumSpecializationsForClassID, classID)
		if ok and type(n) == "number" and n > 0 then return n end
	end
	return 3   -- every class has three trees
end

local function NormalizeName(name)
	return type(name) == "string" and name:upper():gsub("[^A-Z]", "") or nil
end

local function PointsFromSpecializations(class)
	local getInfo = GetSpecInfoFunction()
	local specs = D.CLASS_SPECS[class]
	if not getInfo or not specs then return nil end

	local points, total = {}, 0
	for tab = 1, #specs do points[tab] = 0 end

	for index = 1, NumSpecializations() do
		local info = { pcall(getInfo, index) }
		if info[1] then
			local name, spent = info[3], info[8]
			if type(spent) == "number" and spent > 0 then
				local tab = index
				local normalized = NormalizeName(name)
				for i, spec in ipairs(specs) do
					if spec.id == normalized then tab = i end
				end
				if points[tab] then
					points[tab] = points[tab] + spent
					total = total + spent
				end
			end
		end
	end
	return points, total
end

-- Forever runs talents on the modern trait system (C_Traits). How the three
-- Classic trees are split inside it isn't documented, so nodes are grouped by
-- the first of these that splits them: separate trees, node groups,
-- sub-trees, or failing all else their horizontal position (three columns).
-- Groups are matched to D.CLASS_SPECS by name where the game gives one,
-- otherwise ordered left to right, like the talent window.
-- Debug log. With D.DEBUG_SPEC on, each spec check is written to the saved
-- variable OutgrownForeverDB.log, which the game saves to
-- WTF\Account\<account>\SavedVariables\OutgrownForever.lua on /reload or logout.
-- Repeat checks with the same result aren't logged again.
local logBuffer, lastLogged

local function DebugPrint(...)
	if not D.DEBUG_SPEC then return end
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	logBuffer = logBuffer or {}
	logBuffer[#logBuffer + 1] = table.concat(parts, " ")
end

local function Describe(value, depth)
	depth = depth or 0
	if type(value) ~= "table" then return tostring(value) end
	if depth >= 2 then return "{...}" end
	local parts = {}
	for k, v in pairs(value) do
		parts[#parts + 1] = tostring(k) .. "=" .. Describe(v, depth + 1)
		if #parts >= 12 then
			parts[#parts + 1] = "..."; break
		end
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function FlushLog()
	local lines = logBuffer
	logBuffer = nil
	if not D.DEBUG_SPEC or not lines then return end

	local text = table.concat(lines, "\n")
	if text == lastLogged then return end
	lastLogged = text

	OutgrownForeverDB = OutgrownForeverDB or {}
	local log = OutgrownForeverDB.log or {}
	OutgrownForeverDB.log = log
	log[#log + 1] = "---- " .. date("%Y-%m-%d %H:%M:%S") .. " level " .. UnitLevel("player")
	for _, line in ipairs(lines) do log[#log + 1] = line end
	while #log > 500 do table.remove(log, 1) end

	print(ns.L.DEBUG_LOGGED)
end

local function GroupName(configID, treeID, method, key)
	if method == "subtree" and C_Traits.GetSubTreeInfo then
		local ok, info = pcall(C_Traits.GetSubTreeInfo, configID, key)
		if ok and type(info) == "table" then return info.name end
	elseif method == "group" and C_Traits.GetGroupDisplayInfoByTreeID then
		local ok, list = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
		if ok and type(list) == "table" then
			for _, g in pairs(list) do
				if type(g) == "table" and (g.groupID == key or g.ID == key or g.id == key) then
					return g.name or g.title
				end
			end
		end
	end
end

local function PointsFromTraits(class)
	if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits
				and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then
		return nil
	end
	local specs = D.CLASS_SPECS[class]
	if not specs then return nil end

	local okID, configID = pcall(C_ClassTalents.GetActiveConfigID)
	if not okID or not configID then
		DebugPrint("no active talent config"); return nil
	end
	local okInfo, info = pcall(C_Traits.GetConfigInfo, configID)
	if not okInfo or type(info) ~= "table" or not info.treeIDs then return nil end

	-- Collect every node with its possible grouping keys.
	local nodes = {}
	for treeIndex, treeID in ipairs(info.treeIDs) do
		local okNodes, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
		for _, nodeID in ipairs(okNodes and nodeIDs or {}) do
			local okNode, node = pcall(C_Traits.GetNodeInfo, configID, nodeID)
			if okNode and type(node) == "table" and node.ID and node.ID ~= 0 then
				nodes[#nodes + 1] = {
					treeID = treeID,
					tree = treeIndex,
					group = node.groupIDs and node.groupIDs[1],
					subtree = node.subTreeID,
					x = node.posX or 0,
					ranks = node.ranksPurchased or node.activeRank or 0,
					allGroups = node.groupIDs and table.concat(node.groupIDs, ","),
					groupIDs = node.groupIDs or {},
				}
			end
		end
	end
	if #nodes == 0 then
		DebugPrint("talent config has no nodes"); return nil
	end

	if D.DEBUG_SPEC then
		DebugPrint("config", configID, "type", info.type, "name", info.name,
			"trees", table.concat(info.treeIDs, ","), "nodes", #nodes)
		for _, treeID in ipairs(info.treeIDs) do
			if C_Traits.GetTreeInfo then
				local ok, treeInfo = pcall(C_Traits.GetTreeInfo, configID, treeID)
				DebugPrint("tree", treeID, "info", ok and Describe(treeInfo) or "error")
			end
			if C_Traits.GetGroupDisplayInfoByTreeID then
				local ok, groupInfo = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
				DebugPrint("tree", treeID, "groups", ok and Describe(groupInfo) or "error")
			end
			if C_Traits.GetTreeCurrencyInfo then
				local ok, currency = pcall(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
				DebugPrint("tree", treeID, "currency", ok and Describe(currency) or "error")
			end
		end
		for _, n in ipairs(nodes) do
			if n.ranks > 0 then
				DebugPrint(("node tree=%s group=%s subtree=%s x=%s ranks=%s allGroups=%s"):format(
					tostring(n.treeID), tostring(n.group), tostring(n.subtree),
					tostring(n.x), tostring(n.ranks), n.allGroups or "-"))
			end
		end
	end

	-- Forever: the tree lists its three talent trees as named display groups
	-- (Holy, Protection, Retribution...). A talent belongs to a tree when that
	-- tree's group ID appears anywhere in the talent's own group list.
	local displayGroups = {}
	if C_Traits.GetGroupDisplayInfoByTreeID then
		for _, treeID in ipairs(info.treeIDs) do
			local ok, list = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
			if ok and type(list) == "table" then
				for _, g in pairs(list) do
					if type(g) == "table" and g.groupID then displayGroups[#displayGroups + 1] = g end
				end
			end
		end
	end

	if #displayGroups >= 2 then
		table.sort(displayGroups, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
		local points, total = {}, 0
		for tab = 1, #specs do points[tab] = 0 end
		for order, g in ipairs(displayGroups) do
			local tab = order
			local normalized = NormalizeName(g.displayName or g.name)
			for i, spec in ipairs(specs) do
				if spec.id == normalized then tab = i end
			end
			local spent = 0
			for _, n in ipairs(nodes) do
				for _, id in ipairs(n.groupIDs) do
					if id == g.groupID then
						spent = spent + n.ranks; break
					end
				end
			end
			DebugPrint(("display group %s (%s): %d points -> tree %d"):format(
				tostring(g.groupID), tostring(g.displayName or g.name), spent, tab))
			if points[tab] then
				points[tab] = points[tab] + spent
				total = total + spent
			end
		end
		return points, total
	end

	local function distinct(field)
		local seen, count = {}, 0
		for _, n in ipairs(nodes) do
			local v = n[field]
			if v and v ~= 0 and not seen[v] then
				seen[v] = true; count = count + 1
			end
		end
		return count
	end

	local method
	if distinct("tree") >= 2 then
		method = "tree"
	elseif distinct("group") >= 2 then
		method = "group"
	elseif distinct("subtree") >= 2 then
		method = "subtree"
	else
		method = "column"
	end

	if method == "column" then
		local minX, maxX = math.huge, -math.huge
		for _, n in ipairs(nodes) do
			minX, maxX = math.min(minX, n.x), math.max(maxX, n.x)
		end
		local width = (maxX - minX) / #specs
		for _, n in ipairs(nodes) do
			n.column = width > 0 and math.min(#specs, math.floor((n.x - minX) / width) + 1) or 1
		end
	end
	local field = method == "column" and "column" or method

	-- Build groups: points spent and average position.
	local groups, list = {}, {}
	for _, n in ipairs(nodes) do
		local key = n[field]
		if key and key ~= 0 then
			local g = groups[key]
			if not g then
				g = { key = key, treeID = n.treeID, points = 0, xSum = 0, count = 0 }
				groups[key] = g
				list[#list + 1] = g
			end
			g.points = g.points + n.ranks
			g.xSum = g.xSum + n.x
			g.count = g.count + 1
		end
	end

	-- Left to right, except separate trees which keep the game's order.
	if method == "tree" then
		table.sort(list, function(a, b) return a.key < b.key end)
	else
		table.sort(list, function(a, b) return a.xSum / a.count < b.xSum / b.count end)
	end

	local points, total = {}, 0
	for tab = 1, #specs do points[tab] = 0 end
	for order, g in ipairs(list) do
		local tab = order
		local name = GroupName(configID, g.treeID, method, g.key)
		local normalized = NormalizeName(name)
		for i, spec in ipairs(specs) do
			if spec.id == normalized then tab = i end
		end
		DebugPrint(("%s %s%s: %d points -> tree %d"):format(
			method, tostring(g.key), name and (" (" .. name .. ")") or "", g.points, tab))
		if points[tab] then
			points[tab] = points[tab] + g.points
			total = total + g.points
		end
	end
	return points, total
end

local function TalentPointsPerTree()
	local class = select(2, UnitClass("player"))

	-- Classic-style clients
	if GetNumTalentTabs then
		local ok, numTabs = pcall(GetNumTalentTabs)
		if ok and type(numTabs) == "number" and numTabs > 0 then
			local points, total = PointsFromTalents(numTabs)
			if points and total > 0 then return points, total end
			points, total = PointsFromTrees(numTabs)
			if points and total > 0 then return points, total end
		end
	end

	DebugPrint("classic talent functions:", GetNumTalentTabs and "present" or "missing")

	-- Modern clients that expose trees as specializations
	local points, total = PointsFromSpecializations(class)
	DebugPrint("specializations:", points and table.concat(points, ",") or "unavailable")
	if points and total > 0 then return points, total end

	-- Forever: the trait system
	points, total = PointsFromTraits(class)
	DebugPrint("traits:", points and table.concat(points, ",") or "unavailable")
	return points, total
end

local cachedSpec, cachedClass, currentWeights

local function FindSpec(class, specKey)
	for _, spec in ipairs(D.CLASS_SPECS[class] or {}) do
		if class .. "_" .. spec.id == specKey then return spec end
	end
end

-- Works out the player's spec and role, and the stat weights to use:
-- the role's weights with the spec's adjustments on top.
function G.RefreshRole()
	local class = select(2, UnitClass("player"))
	local specKey, role

	if D.SPEC_OVERRIDE then
		local spec = FindSpec(class, D.SPEC_OVERRIDE)
		if spec then specKey, role = D.SPEC_OVERRIDE, spec.role end
	end

	if not specKey then
		local points, total = TalentPointsPerTree()
		local specs = D.CLASS_SPECS[class]
		if points and specs and total >= D.MIN_TALENT_POINTS then
			local bestTab, bestPoints = 1, -1
			for tab, spent in ipairs(points) do
				if spent > bestPoints then bestTab, bestPoints = tab, spent end
			end
			local spec = specs[bestTab]
			if spec then specKey, role = class .. "_" .. spec.id, spec.role end
		end
	end

	role = role or D.DEFAULT_ROLE[class] or "melee_str"
	DebugPrint("result: spec", tostring(specKey), "role", role)
	FlushLog()
	if specKey == cachedSpec and role == cachedRole and class == cachedClass then
		return     -- nothing changed
	end

	cachedClass = class
	cachedSpec = specKey
	cachedRole = role

	currentWeights = {}
	for stat, weight in pairs(D.WEIGHTS[cachedRole]) do currentWeights[stat] = weight end
	for stat, weight in pairs(specKey and D.SPEC_WEIGHTS[specKey] or {}) do
		currentWeights[stat] = weight
	end

	wipe(lastGrade)
end

function G.GetRole()
	if not cachedRole then G.RefreshRole() end
	return cachedRole
end

-- Returns spec key (nil before talents pick one), role and class.
function G.GetSpec()
	if not cachedRole then G.RefreshRole() end
	return cachedSpec, cachedRole, cachedClass
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------
local function GetWeaponSlot(slotId)
	if not weaponSlots then
		weaponSlots = {}
		for name, kind in pairs({ MainHandSlot = "main", SecondaryHandSlot = "off", RangedSlot = "ranged" }) do
			local ok, id = pcall(GetInventorySlotInfo, name)
			if ok and id then weaponSlots[id] = kind end
		end
	end
	return weaponSlots[slotId]
end

local function DpsFactor(role, slotId)
	local tableName = D.ROLE_DPS_TABLE[role]
	local slotKind = GetWeaponSlot(slotId)
	if not tableName or not slotKind then return 0 end
	return D.DPS_SLOT_FACTOR[tableName][slotKind] or 0
end

local function MaxArmorType(class, level)
	local rule = D.CLASS_ARMOR[class]
	if not rule then return 1 end
	if rule.advanced and level >= rule.unlockLevel then return rule.advanced end
	return rule.base
end

local function Baseline(item, role, level, slotId)
	local loc = item.equipLoc
	local weights = currentWeights
	local isCaster = role == "caster" or role == "healer"
	local slotBudget = (isCaster and D.CASTER_WEAPON_BUDGET[loc]) or D.SLOT_BUDGET[loc]
	if not slotBudget then return nil end

	local base = level * D.BUDGET_PER_LEVEL * slotBudget * D.ROLE_EFFICIENCY

	local kind = D.WEAPON_KIND[loc]
	if kind and weights.DPS then
		local factor = DpsFactor(role, slotId)
		if factor > 0 then
			local a, b = D.EXPECTED_DPS[kind][1], D.EXPECTED_DPS[kind][2]
			base = base + (a * level + b) * weights.DPS * factor
		end
	end

	if weights.ARMOR then
		if loc == "INVTYPE_SHIELD" then
			base = base + level * D.SHIELD_ARMOR_PER_LEVEL * weights.ARMOR
		elseif D.ARMOR_SLOT[loc] then
			local class = select(2, UnitClass("player"))
			local perLevel = D.ARMOR_PER_LEVEL[MaxArmorType(class, level)]
			base = base + level * perLevel * D.ARMOR_SLOT[loc] * weights.ARMOR
		end
	end

	return base
end

local function Score(item, role, slotId)
	local weights = currentWeights
	local score = 0
	for stat, amount in pairs(item.values) do
		local weight = weights[stat]
		if weight then
			if stat == "DPS" then weight = weight * DpsFactor(role, slotId) end
			score = score + amount * weight
		end
	end
	return score
end

---------------------------------------------------------------------------
-- Grades
---------------------------------------------------------------------------
local function GradeFromRatio(ratio, previous)
	local t = D.THRESHOLDS
	local redCut, orangeCut = t.red, t.orange
	if previous == "red" then
		redCut, orangeCut = redCut + t.buffer, orangeCut + t.buffer
	elseif previous == "orange" then
		orangeCut = orangeCut + t.buffer
	end
	if ratio < redCut then return "red" end
	if ratio < orangeCut then return "orange" end
	return nil
end

local function GradeFromLevel(reqLevel, level)
	if not reqLevel or reqLevel <= 1 then return nil end
	local gap = level - reqLevel
	if gap >= D.LEVEL_FALLBACK.red then return "red" end
	if gap >= D.LEVEL_FALLBACK.orange then return "orange" end
	return nil
end

local function Milder(a, b)
	if (SEVERITY[a] or 0) <= (SEVERITY[b] or 0) then return a end
	return b
end

local function CanUseWeapon(class, subClassID)
	if D.ANY_CLASS_WEAPONS[subClassID] then return true end
	local allowed = D.CLASS_WEAPONS[class]
	if not allowed then return nil end
	for _, id in ipairs(allowed) do
		if id == subClassID then return true end
	end
	return false
end

-- Grades the item in an equipment slot.
-- Returns result, pending:
--   result  = nil for an empty slot, otherwise a table with
--             grade ("red"/"orange"/nil), reason, ratio, spec, role, class,
--             level, confident
--   pending = true if the game hasn't sent the item's data yet
function G.GradeSlot(slotId)
	local link = GetInventoryItemLink("player", slotId)
	if not link then return nil, false end

	local item = ParseItem(link)
	if not item then return nil, true end

	local level = UnitLevel("player")
	local class = select(2, UnitClass("player"))
	local spec, role = G.GetSpec()
	local result = { spec = spec, role = role, class = class, level = level, confident = not item.unrated }

	if item.classID == 2 and CanUseWeapon(class, item.subClassID) == false then
		result.grade, result.reason = "red", "weapon"
		return result, false
	end

	-- Items without a level requirement and very low levels aren't graded.
	if not item.reqLevel or item.reqLevel <= 1 or level < D.GRACE_LEVEL then
		return result, false
	end

	local levelGrade = GradeFromLevel(item.reqLevel, level)
	local baseline = Baseline(item, role, level, slotId)

	if not baseline or baseline <= 0 then
		result.grade, result.reason, result.confident = levelGrade, "level", false
		return result, false
	end

	local previous = lastGrade[slotId]
	previous = previous and previous.link == link and previous.grade or nil

	result.ratio = Score(item, role, slotId) / baseline
	local ratioGrade = GradeFromRatio(result.ratio, previous)

	if item.unrated then
		-- Don't be harsher than the level check on items we can't fully read.
		result.grade = Milder(ratioGrade, levelGrade)
	else
		result.grade = ratioGrade
	end
	result.reason = "score"

	lastGrade[slotId] = { link = link, grade = result.grade }
	return result, false
end

---------------------------------------------------------------------------
-- Upgrades: compare any item with what's equipped in the slot it would use
---------------------------------------------------------------------------
local LOC_SLOTS = {
	INVTYPE_HEAD = { "HeadSlot" },
	INVTYPE_NECK = { "NeckSlot" },
	INVTYPE_SHOULDER = { "ShoulderSlot" },
	INVTYPE_CLOAK = { "BackSlot" },
	INVTYPE_CHEST = { "ChestSlot" },
	INVTYPE_ROBE = { "ChestSlot" },
	INVTYPE_WRIST = { "WristSlot" },
	INVTYPE_HAND = { "HandsSlot" },
	INVTYPE_WAIST = { "WaistSlot" },
	INVTYPE_LEGS = { "LegsSlot" },
	INVTYPE_FEET = { "FeetSlot" },
	INVTYPE_FINGER = { "Finger0Slot", "Finger1Slot" },
	INVTYPE_TRINKET = { "Trinket0Slot", "Trinket1Slot" },
	INVTYPE_WEAPON = { "MainHandSlot", "SecondaryHandSlot" },
	INVTYPE_2HWEAPON = { "MainHandSlot" },
	INVTYPE_WEAPONMAINHAND = { "MainHandSlot" },
	INVTYPE_WEAPONOFFHAND = { "SecondaryHandSlot" },
	INVTYPE_SHIELD = { "SecondaryHandSlot" },
	INVTYPE_HOLDABLE = { "SecondaryHandSlot" },
	INVTYPE_RANGED = { "RangedSlot" },
	INVTYPE_RANGEDRIGHT = { "RangedSlot" },
	INVTYPE_THROWN = { "RangedSlot" },
	INVTYPE_RELIC = { "RangedSlot" },
}

local function SlotId(name)
	local ok, id = pcall(GetInventorySlotInfo, name)
	if ok then return id end
end

local function CanDualWieldNow(class, level)
	if CanDualWield then
		local ok, result = pcall(CanDualWield)
		if ok and result ~= nil then return result and true or false end
	end
	local needed = D.DUAL_WIELD_LEVEL[class]
	return needed ~= nil and level >= needed
end

local function CanWear(item, class, level)
	local sub = item.subClassID
	if item.classID == 2 then
		return CanUseWeapon(class, sub) ~= false
	elseif item.classID == 4 then
		if sub == 6 then return D.CLASS_SHIELDS[class] == true end
		if D.RELIC_CLASS[sub] then return D.RELIC_CLASS[sub] == class end
		if sub and sub >= 1 and sub <= 4 and item.equipLoc ~= "INVTYPE_CLOAK" then
			return sub <= MaxArmorType(class, level)
		end
		return true
	end
	return false
end

-- Value of what's equipped in a slot. Returns value, comparable, pending.
-- comparable is false when the equipped item has effects we can't rate,
-- since then we can't honestly say something else beats it.
local function EquippedValue(slotId, role)
	local link = GetInventoryItemLink("player", slotId)
	if not link then return 0, true, false end
	local item = ParseItem(link)
	if not item then return nil, false, true end
	return Score(item, role, slotId), not item.unrated, false, item
end

-- Is the item at this link an upgrade over your equipped gear?
-- levelAhead lets items with a slightly higher required level count.
-- Returns isUpgrade, pending (true if item data is still loading).
function G.IsUpgrade(link, levelAhead)
	if not link then return false, false end
	local item = ParseItem(link)
	if not item then return false, true end

	local slotNames = LOC_SLOTS[item.equipLoc]
	if not slotNames then return false, false end

	local level = UnitLevel("player")
	local class = select(2, UnitClass("player"))
	if (item.reqLevel or 0) > level + (levelAhead or 0) then return false, false end
	if not CanWear(item, class, level) then return false, false end

	-- Don't suggest a lower armor type than the class wears (cloaks aside).
	local isArmorType = item.classID == 4 and item.subClassID and item.subClassID >= 1
			and item.subClassID <= 4 and item.equipLoc ~= "INVTYPE_CLOAK"
	if D.UPGRADE_KEEP_ARMOR_TYPE and isArmorType then
		local best = MaxArmorType(class, level)
		if item.subClassID < best then
			local slotId = SlotId(slotNames[1])
			local equippedLink = slotId and GetInventoryItemLink("player", slotId)
			local equipped = equippedLink and ParseItem(equippedLink)
			if equippedLink and not equipped then return false, true end
			local equippedType = 0
			if equipped and equipped.classID == 4 and equipped.subClassID
					and equipped.subClassID >= 1 and equipped.subClassID <= 4 then
				equippedType = equipped.subClassID
			end
			if item.subClassID < math.min(best, equippedType) then return false, false end
		end
	end

	local role = G.GetRole()
	local margin = 1 + D.UPGRADE_MARGIN

	local mainId, offId = SlotId("MainHandSlot"), SlotId("SecondaryHandSlot")
	local mainLink = mainId and GetInventoryItemLink("player", mainId)
	local mainItem = mainLink and ParseItem(mainLink)
	if mainLink and not mainItem then return false, true end
	local wearingTwoHander = mainItem and mainItem.equipLoc == "INVTYPE_2HWEAPON"

	-- A two-hander replaces both hands.
	if item.equipLoc == "INVTYPE_2HWEAPON" then
		if not mainId then return false, false end
		local mainValue, mainOk, mainPending = EquippedValue(mainId, role)
		local offValue, offOk, offPending = 0, true, false
		if offId and not wearingTwoHander then
			offValue, offOk, offPending = EquippedValue(offId, role)
		end
		if mainPending or offPending then return false, true end
		if not (mainOk and offOk) then return false, false end
		local candidate = Score(item, role, mainId)
		return candidate > 0 and candidate > (mainValue + offValue) * margin, false
	end

	for _, name in ipairs(slotNames) do
		local slotId = SlotId(name)
		local usable = slotId ~= nil
		if usable and slotId == offId then
			-- Nothing goes in the off hand next to a two-hander, and a
			-- one-handed weapon only goes there if you can dual wield.
			if wearingTwoHander then usable = false end
			if item.equipLoc == "INVTYPE_WEAPON" and not CanDualWieldNow(class, level) then
				usable = false
			end
		end

		if usable then
			local value, comparable, pending = EquippedValue(slotId, role)
			if pending then return false, true end
			if comparable then
				local candidate = Score(item, role, slotId)
				if candidate > 0 and candidate > value * margin then
					return true, false
				end
			end
		end
	end

	return false, false
end
