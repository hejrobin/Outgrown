-- Outgrown: Forever
-- Highlights equipped items that have fallen behind your level and role.
-- The grading lives in Grading.lua, its numbers in Data.lua and all
-- player-facing text in Strings.lua.
--
-- Character window: orange = L.UPGRADE_SOON, red = L.NEEDS_UPGRADE
-- Bags and quest rewards: green glow = upgrade over what you're wearing

local _, ns = ...
local D = ns.Data
local L = ns.L
local Grading = ns.Grading

local STYLES = {
	red = {
		r = 1.0,
		g = 0.15,
		b = 0.15,
		text = L.NEEDS_UPGRADE,
	},
	orange = {
		r = 1.0,
		g = 0.55,
		b = 0.0,
		text = L.UPGRADE_SOON,
	},
	upgrade = {
		r = 0.2, g = 1.0, b = 0.2,
	},
}

-- Chat message shown on login/reload when any equipped item is flagged.
local LOGIN_MESSAGE_HEX = "42b1fe" -- soft blue
local ADDON_ICON = "Interface\\Icons\\Trade_BlackSmithing"
local LOGIN_DELAY = 3              -- seconds after login/reload before checking
local LOGIN_RETRIES = 3            -- extra tries if item info hasn't loaded yet

-- Overlay strength (0 = invisible, 1 = solid). Lower = softer.
local TINT_ALPHA = 0.15
local GLOW_ALPHA = 0.35

-- Arrow drawn on top of highlighted items, one image per highlight.
-- The files can be any power-of-two size (e.g. 32x32); they're drawn at
-- ARROW_SCALE times the icon's width, inside the icon's ARROW_CORNER.
local ARROW_PATH = "Interface\\AddOns\\Outgrown\\Assets\\Textures\\"
local ARROW_TEXTURES = {
	upgrade = ARROW_PATH .. "OutgrownGreen",    -- upgrade in bags / quest rewards
	orange  = ARROW_PATH .. "OutgrownOrange",   -- upgrade soon
	red     = ARROW_PATH .. "OutgrownRed",      -- needs upgrade
}
local ARROW_SCALE = 0.6
local ARROW_CORNER = "BOTTOMLEFT"
local ARROW_OFFSET_X = -3
local ARROW_OFFSET_Y = -3
local ARROW_INSET = 1 -- pixels between the arrow and the icon's edge
-- Part of the file to draw: left, right, top, bottom (0-1). Trim these
-- inwards if the image has empty space around the arrow.
local ARROW_TEXCOORD = { 0, 1, 0, 1 }

-- Shirt and tabard are excluded because they are cosmetic.
local SLOTS = {
	"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot",
	"ChestSlot", "WristSlot", "HandsSlot", "WaistSlot",
	"LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot",
	"Trinket0Slot", "Trinket1Slot", "MainHandSlot",
	"SecondaryHandSlot", "RangedSlot",
}

local waitingForItemData = false
local updateQueued = false
local dirty = {}        -- "character" / "bags" / "quests" -> true
local overlays = {}
local trackedSlots = {} -- slotId -> true
local buttonToSlot = {} -- slot button -> slotId

local function GetSlotId(slotName)
	local ok, slotId = pcall(GetInventorySlotInfo, slotName)
	if ok then return slotId end
end

local function GradeSlot(slotId)
	local result, pending = Grading.GradeSlot(slotId)
	if pending then waitingForItemData = true end
	return result
end

---------------------------------------------------------------------------
-- Character window highlights
---------------------------------------------------------------------------
-- anchor: the region to cover, e.g. the icon on a wide quest reward button.
local function GetOverlay(button, anchor)
	local overlay = overlays[button]
	if overlay then return overlay end
	anchor = anchor or button

	overlay = {}
	overlay.tint = button:CreateTexture(nil, "OVERLAY", nil, 6)
	overlay.tint:SetAllPoints(anchor)

	overlay.glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
	overlay.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	overlay.glow:SetBlendMode("ADD")

	local width, height = anchor:GetSize()
	overlay.glow:SetSize(width * 1.8, height * 1.8)
	overlay.glow:SetPoint("CENTER", anchor, "CENTER")

	-- Kept inside the icon, so scroll frames and neighbouring slots can't clip it.
	overlay.arrow = button:CreateTexture(nil, "OVERLAY", nil, 7)
	overlay.arrow:SetTexCoord(unpack(ARROW_TEXCOORD))
	local size = math.floor(width * ARROW_SCALE + 0.5)
	overlay.arrow:SetSize(size, size)

	local insetX = ARROW_CORNER:find("LEFT") and ARROW_INSET or -ARROW_INSET
	local insetY = ARROW_CORNER:find("TOP") and -ARROW_INSET or ARROW_INSET

	overlay.arrow:SetPoint(ARROW_CORNER, anchor, ARROW_CORNER, insetX + ARROW_OFFSET_X, insetY + ARROW_OFFSET_Y)
	overlay.arrow:Hide()

	overlays[button] = overlay
	return overlay
end

local function SetHighlight(button, grade, anchor)
	if not grade then
		local overlay = overlays[button]
		if overlay then
			overlay.tint:Hide()
			overlay.glow:Hide()
			overlay.arrow:Hide()
		end
		return
	end

	local style = STYLES[grade]
	local overlay = GetOverlay(button, anchor)
	overlay.tint:SetColorTexture(style.r, style.g, style.b, TINT_ALPHA)
	overlay.glow:SetVertexColor(style.r, style.g, style.b, GLOW_ALPHA)
	overlay.tint:Show()
	overlay.glow:Show()
	overlay.arrow:SetTexture(ARROW_TEXTURES[grade])
	overlay.arrow:Show()
end

local function UpdateCharacter()
	for _, slotName in ipairs(SLOTS) do
		local button = _G["Character" .. slotName]
		local slotId = GetSlotId(slotName)

		if button and slotId then
			trackedSlots[slotId] = true
			buttonToSlot[button] = slotId
			local result = GradeSlot(slotId)
			SetHighlight(button, result and result.grade)
		end
	end
end

---------------------------------------------------------------------------
-- Bags: green glow on items that beat what you're wearing
---------------------------------------------------------------------------
local GetContainerItemLinkCompat =
		(C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink

local function MarkUpgrade(button, link, levelAhead, anchor)
	local isUpgrade, pending = false, false
	if link then isUpgrade, pending = Grading.IsUpgrade(link, levelAhead) end
	if pending then waitingForItemData = true end
	SetHighlight(button, isUpgrade and "upgrade" or nil, anchor)
end

local function GetBagFrames()
	local frames = {}
	if ContainerFrameCombinedBags then frames[#frames + 1] = ContainerFrameCombinedBags end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local f = _G["ContainerFrame" .. i]
		if f then frames[#frames + 1] = f end
	end
	return frames
end

local function UpdateBags()
	for _, f in ipairs(GetBagFrames()) do
		if f:IsShown() then
			if f.EnumerateValidItems then
				-- Modern bag frames
				for _, button in f:EnumerateValidItems() do
					local link = GetContainerItemLinkCompat(button:GetBagID(), button:GetID())
					MarkUpgrade(button, link, 0)
				end
			else
				-- Classic bag frames: ContainerFrame1Item1, ...
				local name, bag = f:GetName(), f:GetID()
				for i = 1, (f.size or 0) do
					local button = _G[name .. "Item" .. i]
					if button then
						local link = GetContainerItemLinkCompat(bag, button:GetID())
						MarkUpgrade(button, link, 0)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Quest rewards: quest log and quest giver windows
---------------------------------------------------------------------------
-- Reward buttons live in different frames depending on the UI:
--   MapQuestInfoRewardsFrame: the quest log in the world map's side panel
--                             (Forever and other modern clients)
--   QuestInfoRewardsFrame:    the quest giver window, and the pop-out quest log
--   QuestLogItemN:            the Classic quest log
-- Each source says whether its links come from the quest log or a quest giver.
local REWARD_SOURCES = {
	{ frame = "MapQuestInfoRewardsFrame", prefix = "MapQuestInfoRewardsFrameQuestInfoItem", fromLog = true },
	{ frame = "QuestInfoRewardsFrame",    prefix = "QuestInfoRewardsFrameQuestInfoItem" },
	{ prefix = "QuestInfoItem" },
	{ prefix = "QuestLogItem",            fromLog = true },
}

-- Quest giver window open: links come from the quest giver; otherwise the log.
local function SharedFrameIsLog()
	if QuestInfoFrame and type(QuestInfoFrame.questLog) == "boolean" then
		return QuestInfoFrame.questLog
	end
	return not (QuestFrame and QuestFrame:IsVisible())
end

-- Returns a list of { button = ..., fromLog = true/false }.
local function GetRewardButtons()
	local list, seen = {}, {}
	local function add(b, fromLog)
		if b and not seen[b] then
			seen[b] = true
			list[#list + 1] = { button = b, fromLog = fromLog }
		end
	end
	for _, source in ipairs(REWARD_SOURCES) do
		local fromLog = source.fromLog
		if fromLog == nil then fromLog = SharedFrameIsLog() end
		local frame = source.frame and _G[source.frame]
		if frame and frame.RewardButtons then
			for _, b in ipairs(frame.RewardButtons) do add(b, fromLog) end
		end
		for i = 1, 10 do add(_G[source.prefix .. i], fromLog) end
	end
	return list
end

local function GetRewardLink(button, fromLog)
	local rewardType, index = button.type, button:GetID()
	if not rewardType or not index or index < 1 then return nil end
	if button.objectType and button.objectType ~= "item" then return nil end

	local getLink = fromLog and GetQuestLogItemLink or GetQuestItemLink
	if not getLink then return nil end
	local ok, link = pcall(getLink, rewardType, index)
	return ok and link or nil
end

local function UpdateQuests()
	for _, entry in ipairs(GetRewardButtons()) do
		local button = entry.button
		if button:IsVisible() then
			local anchor = button.Icon or button.icon
					or (button:GetName() and _G[button:GetName() .. "IconTexture"])
			MarkUpgrade(button, GetRewardLink(button, entry.fromLog), D.QUEST_REWARD_LEVEL_AHEAD, anchor)
		else
			SetHighlight(button, nil)
		end
	end
end

---------------------------------------------------------------------------
-- Update scheduling
---------------------------------------------------------------------------
local function RunUpdates()
	updateQueued = false
	waitingForItemData = false
	if dirty.character then UpdateCharacter() end
	if dirty.bags then UpdateBags() end
	if dirty.quests then UpdateQuests() end
	wipe(dirty)
end

local function Queue(...)
	for i = 1, select("#", ...) do dirty[select(i, ...)] = true end
	if updateQueued then return end
	updateQueued = true
	C_Timer.After(0, RunUpdates)
end

local function QueueAll() Queue("character", "bags", "quests") end
local function QueueCharacter() Queue("character") end
local function QueueBags() Queue("bags") end
local function QueueQuests() Queue("quests") end

-- Talents can finish loading after login, so check them again whenever the
-- character window opens.
local function RefreshAndQueueCharacter()
	Grading.RefreshRole()
	Queue("character")
end

local function SetupHooks()
	if PaperDollFrame then
		PaperDollFrame:HookScript("OnShow", RefreshAndQueueCharacter)
	elseif CharacterFrame then
		CharacterFrame:HookScript("OnShow", RefreshAndQueueCharacter)
	end

	for _, f in ipairs(GetBagFrames()) do
		f:HookScript("OnShow", QueueBags)
		if f.UpdateItems then hooksecurefunc(f, "UpdateItems", QueueBags) end
	end
	if ContainerFrame_Update then hooksecurefunc("ContainerFrame_Update", QueueBags) end

	for _, fn in ipairs({ "QuestInfo_Display", "QuestLog_UpdateQuestDetails", "SelectQuestLogEntry",
		"QuestMapFrame_ShowQuestDetails" }) do
		if _G[fn] then hooksecurefunc(fn, QueueQuests) end
	end
	if QuestLogFrame then QuestLogFrame:HookScript("OnShow", QueueQuests) end
	for _, name in ipairs({ "QuestFrame", "QuestMapFrame", "MapQuestInfoRewardsFrame",
		"QuestLogPopupDetailFrame" }) do
		if _G[name] then _G[name]:HookScript("OnShow", QueueQuests) end
	end
end

---------------------------------------------------------------------------
-- Tooltip lines
---------------------------------------------------------------------------
local function AddStatusLines(tooltip, slotId, needsShow)
	if not slotId or not trackedSlots[slotId] then return end

	local result = GradeSlot(slotId)
	if not result then return end

	local added = false
	if result.grade then
		local style = STYLES[result.grade]
		local text = result.reason == "weapon" and L.NOT_PROFICIENT or style.text
		tooltip:AddLine(text, style.r, style.g, style.b)
		added = true
	end

	if D.SHOW_DETAILS and result.ratio then
		local detail = L.DETAIL:format(
			math.floor(result.ratio * 100 + 0.5), result.level,
			(result.spec and L.SPEC_NAMES[result.spec])
			or L.CLASS_NAMES[result.class] or result.class)
		if not result.confident then
			detail = detail .. L.DETAIL_UNRATED
		end
		tooltip:AddLine(detail, 0.6, 0.6, 0.6)
		added = true
	end

	if added and needsShow then tooltip:Show() end
end

local function SetupTooltip()
	if TooltipDataProcessor and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(
			Enum.TooltipDataType.Item,
			function(tooltip)
				if tooltip ~= GameTooltip then return end
				local owner = tooltip:GetOwner()
				AddStatusLines(tooltip, owner and buttonToSlot[owner], false)
			end
		)
	else
		hooksecurefunc(GameTooltip, "SetInventoryItem", function(tooltip, unit, slotId)
			if unit ~= "player" then return end
			AddStatusLines(tooltip, slotId, true)
		end)
	end
end

---------------------------------------------------------------------------
-- Login / reload message
---------------------------------------------------------------------------
local function CheckOnLogin(attempt)
	attempt = attempt or 1
	waitingForItemData = false

	local anyFlagged = false
	for _, slotName in ipairs(SLOTS) do
		local slotId = GetSlotId(slotName)
		local result = slotId and GradeSlot(slotId)
		if result and result.grade then
			anyFlagged = true
			break
		end
	end

	if not anyFlagged and waitingForItemData and attempt <= LOGIN_RETRIES then
		C_Timer.After(2, function() CheckOnLogin(attempt + 1) end)
		return
	end

	if anyFlagged then
		print(("|T%s:0|t |cff%s%s|r"):format(ARROW_TEXTURES.orange, LOGIN_MESSAGE_HEX, L.LOGIN_MESSAGE))
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")

-- Events differ between clients; register whichever exist.
local function RegisterIfExists(event)
	pcall(frame.RegisterEvent, frame, event)
end

local TALENT_EVENTS = {
	CHARACTER_POINTS_CHANGED = true,
	PLAYER_TALENT_UPDATE = true,
	ACTIVE_TALENT_GROUP_CHANGED = true,
	PLAYER_ENTERING_WORLD = true,   -- talent data is often ready by now
	SPELLS_CHANGED = true,          -- and fires again once it loads
}
local QUEST_EVENTS = {
	QUEST_LOG_UPDATE = true,
	QUEST_DETAIL = true,
	QUEST_COMPLETE = true,
}
for _, list in ipairs({ TALENT_EVENTS, QUEST_EVENTS }) do
	for event in pairs(list) do RegisterIfExists(event) end
end
for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
	"GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED" }) do
	RegisterIfExists(event)
end

frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		Grading.RefreshRole()
		SetupHooks()
		SetupTooltip()
		QueueAll()
		C_Timer.After(LOGIN_DELAY, CheckOnLogin)
	elseif TALENT_EVENTS[event] then
		Grading.RefreshRole()
		QueueAll()
	elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_EQUIPMENT_CHANGED" then
		QueueAll()
	elseif event == "BAG_UPDATE_DELAYED" then
		QueueBags()
	elseif QUEST_EVENTS[event] then
		QueueQuests()
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if waitingForItemData then QueueAll() end
	end
end)
