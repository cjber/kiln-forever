-- The Kiln Forever section of the shared objective tracker column: what's running, what needs you first,
-- and what just finished. Click a session to open it.

local _, ns = ...

if ns.broken then
	return
end

local K = {}
ns.Tracker = K

local MAX_LINES = 6
local HEADER = "Kiln Forever"

---------------------------------------------------------------------------
-- What the section shows

-- Sessions waiting on the player come first, then working ones, then unread finished ones. The cap applies while
-- collecting, so a queue of waiting sessions never pushes the section past its six rows.
---@return table[]
local function Entries()
	local entries = {}
	local active = ns.Store:Active()
	for _, t in ipairs(active) do
		if #entries >= MAX_LINES then return entries end
		if t.s == "input" then table.insert(entries, t) end
	end
	for _, t in ipairs(active) do
		if #entries >= MAX_LINES then return entries end
		if t.s ~= "input" then table.insert(entries, t) end
	end
	for _, t in ipairs(ns.Store.data.threads) do
		if #entries >= MAX_LINES then break end
		if (t.s == "open" or t.s == "done") and t.un then table.insert(entries, t) end
	end
	return entries
end

---@param t table
---@return string text, table color
local function StatusText(t)
	if t.s == "working" then
		return string.format("%s  %s", t.l or "Working", ns.Duration(time() - (t.st or time()))), OBJECTIVE_TRACKER_COLOR.Normal
	elseif t.s == "input" then
		return t.l or "Needs you", OBJECTIVE_TRACKER_COLOR.NormalHighlight
	elseif t.s == "done" then
		return "Done  " .. ns.Ago(t.u), OBJECTIVE_TRACKER_COLOR.Complete
	end
	return "Open  " .. ns.Ago(t.u), OBJECTIVE_TRACKER_COLOR.Normal
end

---@return table?
local function Notice()
	local state = ns.Transport:BridgeState()
	if state == "exhausted" then
		return { text = "Live updates paused", sub = "Click to reload", action = function() ReloadUI() end, color = OBJECTIVE_TRACKER_COLOR.TimeLeft }
	elseif state == "stale" then
		return { text = "Connection lost", sub = "Is kiln-forever running?", color = OBJECTIVE_TRACKER_COLOR.Failed }
	elseif state == "kilnoffline" then
		return { text = "Connection lost", sub = "kiln is offline", color = OBJECTIVE_TRACKER_COLOR.Failed }
	elseif state == "kilnunpaired" then
		return { text = "Connection lost", sub = "kiln is not paired", color = OBJECTIVE_TRACKER_COLOR.Failed }
	elseif state == "kilnwrite" then
		return { text = "Viewing only", sub = "kiln write access is off", color = OBJECTIVE_TRACKER_COLOR.TimeLeft }
	end
end

---------------------------------------------------------------------------
-- ForeverCore's column state

-- ForeverCore owns the column's scale, Lock and position. Read and write them through its own API; Kiln keeps only its
-- section's show switches, in ns.db.settings.

---@return boolean
function K:IsLocked()
	return ForeverCore.TrackerHost.IsLocked()
end

---@param locked boolean
function K:SetLocked(locked)
	ForeverCore.TrackerHost.SetLocked(locked)
end

---------------------------------------------------------------------------
-- Rows

---@param line Frame
---@param t table
local function StyleSessionLine(line, t)
	line:EnableMouse(true)
	line:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then ns.Main:SelectThread(t.id, { show = true }) end
	end)
	line:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(t.title, 1, 0.82, 0, 1, true)
		local repository = ns.Store:ProjectName(t.p)
		if repository ~= "" then GameTooltip:AddLine(repository, 0.7, 0.7, 0.7) end
		if t.last then GameTooltip:AddLine(t.last, 1, 1, 1, true) end
		GameTooltip:AddLine("Click to open", 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end)
	line:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local ModuleMixin = { headerText = HEADER }

function ModuleMixin:OnBlockHeaderClick(block, button)
	if button == "LeftButton" and block.thread then
		ns.Main:SelectThread(block.thread.id, { show = true })
	end
end

function ModuleMixin:LayoutContents()
	local s = ns.db.settings
	if not s.tracker then return end
	local shown = 0
	for _, t in ipairs(Entries()) do
		local block = self:GetBlock("session:" .. t.id)
		block.thread = t
		block:SetHeader(t.title)
		local text, color = StatusText(t)
		local line = block:AddObjective("status", text, nil, true, nil, color)
		StyleSessionLine(line, t)
		if not self:LayoutBlock(block) then return end
		shown = shown + 1
	end
	local notice = Notice()
	if notice then
		local block = self:GetBlock("notice")
		block:SetHeader(ns.Color("red", notice.text))
		local line = block:AddObjective("notice", notice.sub, nil, true, nil, notice.color)
		if notice.action then
			line:EnableMouse(true)
			line:SetScript("OnMouseUp", notice.action)
		end
		self:LayoutBlock(block)
	elseif shown == 0 and s.trackerAlways then
		local block = self:GetBlock("empty")
		block:SetHeader(ns.Color("grey", "Nothing running"))
		self:LayoutBlock(block)
	end
end

---------------------------------------------------------------------------
-- Timer text

local ticker

-- Rewrite only the live timer text, and lay the column out again only when a line grew.
local function RefreshTimers()
	if not K.module or InCombatLockdown() or not K.module:IsShown() then return end
	local resized = false
	for _, t in ipairs(Entries()) do
		if t.s == "working" then
			local block = K.module:GetExistingBlock("session:" .. t.id)
			local line = block and block.used and block:GetExistingLine("status")
			if line and line.used and line.Text then
				local text, color = StatusText(t)
				if line.Text:GetText() ~= text then
					local height = block:SetStringText(line.Text, text, true, color, block.isHighlighted)
					resized = resized or height > line:GetHeight() + 0.5
				end
			end
		end
	end
	if resized then K.module:MarkDirty() end
end

local function UpdateTicker()
	local working = ns.db.settings.tracker ~= false
	if working then
		working = false
		for _, t in ipairs(Entries()) do
			if t.s == "working" then working = true break end
		end
	end
	if working and not ticker then
		ticker = C_Timer.NewTicker(1, ns.Safe(RefreshTimers))
	elseif not working and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

---------------------------------------------------------------------------
-- Lifecycle

function K:Create()
	if self.module or not ObjectiveTrackerFrame or not ObjectiveTrackerModuleMixin then return end
	local module = CreateFrame("Frame", "KilnForeverObjectiveTracker", UIParent, "ObjectiveTrackerModuleTemplate")
	Mixin(module, ModuleMixin)
	self.module = module
	module.headerText = HEADER
	module:SetHeader(HEADER)
	-- Above quests, Legacy Forever (0, -1), SkillUp Forever (-2), Shortest Path Forever (-3) and Adventure Guide
	-- Forever (-4): each needs its own slot in the shared column.
	module.uiOrder = -5
	module.Header:EnableMouse(true)
	module.Header:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then ns.Main:Toggle() end
	end)
	module.safeCall = ns.core.SafeCall
	-- The column's scale, Lock and position were Kiln's before ForeverCore kept them; the host copies this table once,
	-- so the player keeps the layout they chose.
	module.legacySettings = ns.db and ns.db.trackerHost or nil
	ForeverCore.TrackerHost.Attach(module, {
		get = function()
			return ns.db.settings.tracker ~= false
		end,
		set = function(shown)
			ns.db.settings.tracker = shown
			K:Refresh()
		end,
		where = "Turn it back on with /kiln settings, under Kiln Forever.",
	})
	-- ForeverCore has the layout now; the old table would only make a later copy look newer.
	if ns.db then ns.db.trackerHost = nil end
	self:Refresh()
end

function K:Refresh()
	if not self.module then return end
	self.module:SetHeader(HEADER)
	self.module:MarkDirty()
	UpdateTicker()
	-- /kiln tracker, /kiln lock, the header menu and Reset all land here; the settings page re-reads its checkboxes
	-- when it is on screen, and does nothing while it is hidden.
	if ns.Settings then ns.Settings:Refresh() end
end

function K:Reset()
	local host = ForeverCore.TrackerHost
	local settings = host.GetSettings()
	-- The column ignores its saved position while it is attached, so clearing it forgets a drag before the next
	-- detach. The section's MarkDirty in Refresh asks the host to lay the column out again.
	settings.x, settings.y = nil, nil
	host.SetLocked(false)
	host.SetAttached(true)
	self:Refresh()
end

ns:On("Login", function() K:Create() end)
ns:On("DataChanged", function() K:Refresh() end)
ns:On("LinkChanged", function() K:Refresh() end)
