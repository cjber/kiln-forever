-- Notices when a session finishes or needs you: the client's own alert toast, queued through its AlertFrame
-- system, and a sound. The scenario toast is the alert the game shows when a scenario completes: a neutral
-- gold toast with the icon on the left and no achievement shield, points or reward frames.

local _, ns = ...

if ns.broken then
	return
end

local N = {}
ns.Toasts = N

-- Registered on first use, so an addon that never notifies adds nothing to the client's alert queue.
local TEMPLATE = "ScenarioAlertFrameTemplate"
local MAX = 3
local QUEUE = 6
local LIFETIME = 7

local function Sound(kind)
	if not ns.db.settings.sounds then return end
	local id
	if kind == "input" then id = SOUNDKIT.READY_CHECK
	else id = SOUNDKIT.IG_QUEST_LIST_COMPLETE end
	if id then PlaySound(id, "Master") end
end

-- The template's first line has no parentKey, so it is the FontString that is not the named session line.
local function Heading(frame)
	if not frame.kfHeading then
		for _, region in ipairs({ frame:GetRegions() }) do
			if region:IsObjectType("FontString") and region ~= frame.dungeonName then
				frame.kfHeading = region
				break
			end
		end
	end
	return frame.kfHeading
end

local function OnClick(frame, button)
	if button == "LeftButton" and frame.kfThreadId then
		ns.Main:SelectThread(frame.kfThreadId, { show = true })
		frame:Hide()
	end
end

-- The scenario toast's own parts: the status goes on the small top line and the session title (and its latest
-- reply) on the name line, as AchievementAlertFrame_SetUp does for its alert.
local function SetUp(frame, t, kind)
	if not frame.kfHooked then
		frame:HookScript("OnClick", OnClick)
		frame.dungeonName:SetMaxLines(2)
		frame.dungeonName:SetWordWrap(true)
		frame.kfHooked = true
		if not frame.kfKnown then
			frame.kfKnown = true
			table.insert(N.frames, frame)
		end
	end
	frame.kfThreadId = t.id
	frame.shownAt = GetTime()
	frame.duration = LIFETIME
	local status = ({ input = "Needs you", done = "Done", open = "Finished" })[kind] or ""
	local tone = ({ input = "orange", done = "green", open = "green" })[kind] or "white"
	local heading = Heading(frame)
	if heading then
		heading:SetText(ns.Color(tone, status) .. ns.Color("grey", "  ·  " .. ns.Store:ProjectName(t.p)))
	end
	frame.dungeonName:SetText(t.title .. (t.last and ("\n" .. t.last) or ""))
	frame.BonusStar:Hide()
	ns.Art.Icon(frame.dungeonTexture, ns.GAME_ICON, 45)
end

N.frames = {}

-- The newest notice still on screen, so a shortcut press can open its thread.
function N:VisibleThread()
	local newest
	for _, f in ipairs(self.frames) do
		if f:IsShown() and f.kfThreadId and (not newest or (f.shownAt or 0) > (newest.shownAt or 0)) then newest = f end
	end
	return newest and newest.kfThreadId
end

local system
local function System()
	if not system and AlertFrame and ScenarioAlertSystem then
		system = AlertFrame:AddQueuedAlertFrameSubSystem(TEMPLATE, SetUp, MAX, QUEUE)
	end
	return system
end

function N:Show(t, kind)
	local alerts = System()
	if alerts then alerts:AddAlert(t, kind) end
end

N.held = {}

local function Notify(t, kind, quietSound)
	local s = ns.db.settings
	if not quietSound then Sound(kind) end
	local viewing = ns.windowOpen and ns.viewId == t.id
	if s.toasts and not viewing then N:Show(t, kind) end
end

ns:On("ThreadTransition", function(t, before, after)
	local finished = before == "working" and (after == "open" or after == "done")
	local needsYou = after == "input" and before ~= after
	if not finished and not needsYou then return end
	local kind = after
	if ns.IsQuiet() then
		-- In a fight (or a quiet instance): hold the pop-up until after.
		for i = #N.held, 1, -1 do
			if N.held[i].t.id == t.id then table.remove(N.held, i) end
		end
		table.insert(N.held, { t = t, kind = kind })
		while #N.held > 3 do table.remove(N.held, 1) end
		return
	end
	Notify(t, kind)
end)

local function Flush()
	if #N.held == 0 or ns.IsQuiet() then return end
	local held = N.held
	N.held = {}
	for i, h in ipairs(held) do
		local current = ns.Store:Thread(h.t.id) or h.t
		-- Only one sound for the batch.
		Notify(current, h.kind, i > 1)
	end
end

ns:On("Combat", function(inCombat) if not inCombat then C_Timer.After(1, Flush) end end)
ns:On("EnteringWorld", function() C_Timer.After(3, Flush) end)
