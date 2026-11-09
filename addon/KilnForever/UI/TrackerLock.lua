---@type string, ForeverTrackerNamespace
local _, ns = ...

-- The shared tracker's grip, drawn on the private column UI/TrackerHost.lua owns, and the Lock switch that keeps the
-- column where the player put it: while Lock is on the grip ignores drag and says so rather than offering one. Locking
-- writes the saved switch and redraws the label, never a frame, so it is safe to change in combat. This file and
-- UI/TrackerHost.lua are the same in every Forever addon that ships the host.
--
-- Shared with UI/TrackerHost.lua: TrackerLock.Locked reads the switch through the host's own IsLocked, and the grip's
-- OnDragStop hands a finished drag to the host's SavePosition.
---@class ForeverTrackerLock
local TrackerLock = {}
ns.TrackerLock = TrackerLock

-- The switch lives in the player's saved tracker settings, which the host owns, so this module keeps no copy of it.
---@return boolean
function TrackerLock.Locked()
	local host = ns.TrackerHost
	return host ~= nil and host.IsLocked ~= nil and host.IsLocked() == true
end

-- Draws the grip on `host`, the column it drags, and returns what the host needs from it: whether the grip is shown at
-- all, and the label redrawn from the settings the moment Lock is switched rather than on the next hover.
---@param host Frame
---@param source ForeverTrackerHostAPI
---@return ForeverTrackerGrip
function TrackerLock.Grip(host, source)
	local grip = CreateFrame("Button", nil, host)
	grip:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
	grip:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
	grip:SetHeight(24)
	grip:RegisterForDrag("LeftButton")
	-- Read with rawget: the host is shared with the companion addons, whose ns.L carries no tracker keys at all. A
	-- constant a translation file sets wins; otherwise the English is the addon's own L phrase, so a translation of
	-- that phrase reaches the grip as it reaches Settings.
	local L = ns.L
	local title = rawget(L, "TRACKER_DRAG_TITLE") or L["Forever tracker"]
	local drag = rawget(L, "TRACKER_DRAG_TOOLTIP") or L["Drag to move"]
	local locked = rawget(L, "TRACKER_LOCKED_TOOLTIP")
		or L["The tracker is locked. Turn off Lock the tracker to move it."]
	local label = grip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER", grip, "CENTER", 0, 0)
	label:SetText(title)
	-- While Lock is on the grip draws no sentence of its own: one unclamped FontString centred on the grip is wider
	-- than the column, so it overlaps the UI below and runs off screen at an edge. The locked sentence lives only in
	-- the tooltip, which the game keeps on screen; the short title returns only while the pointer is over the grip.
	local hovered = false
	local function DrawLabel(isLocked)
		label:SetText(isLocked and (hovered and title or "") or title)
	end
	-- Only a drag this grip started keeps moving, so OnDragStop ignores whatever the host refused to start.
	local dragging = false
	grip:SetScript("OnEnter", function(self)
		local isLocked = TrackerLock.Locked()
		hovered = true
		DrawLabel(isLocked)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(isLocked and locked or drag)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function()
		hovered = false
		DrawLabel(TrackerLock.Locked())
		GameTooltip:Hide()
	end)
	grip:SetScript("OnDragStart", function()
		-- The host refuses a drag while the column is attached to the quest tracker and in combat, so ask it first.
		if TrackerLock.Locked() or source.IsAttachedToQuestTracker() or InCombatLockdown() then
			return
		end
		dragging = true
		host:StartMoving()
	end)
	grip:SetScript("OnDragStop", function()
		if not dragging then
			return
		end
		dragging = false
		host:StopMovingOrSizing()
		local scale = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
		source.SavePosition((host:GetLeft() or 0) * scale, (host:GetTop() or 0) * scale - UIParent:GetHeight())
	end)
	grip:Hide()
	return {
		Show = function(value)
			grip:SetShown(value)
		end,
		SetLabel = function(value)
			DrawLabel(value)
		end,
	}
end
