---@type string, ForeverTrackerNamespace
local _, ns = ...

-- EQ Objective Tracker (cjber/shortest-path-forever#395) hides ObjectiveTrackerFrame (Hide and SetAlpha(0)) and draws
-- its own quest list in EQOTTrackerFrame, a frame parented to UIParent. The shared column normally hangs from the
-- native top, which is where EQOT's list sits, so the two lists draw over each other and neither is readable.
--
-- EQOT's public API names that list: EQObjectiveTracker:GetModule("API").GetListBounds() returns its left, right, top
-- and bottom in UIParent units, or nil while EQOT is hidden or off, and AddLayoutListener calls us after each redraw
-- and move, so that path needs no ticker. When the API is absent, EQOTTrackerFrame is read the way
-- UI/TrackerQuestie.lua reads Questie's frame. Everything here is a read: nothing moves, sizes or otherwise touches
-- another addon's frames or the native tracker.
---@class ForeverTrackerEqot
local TrackerEqot = {}
ns.TrackerEqot = TrackerEqot

---@class ForeverEqotTrackerFrame : Frame
---@field isMoving? boolean true while the player drags the list
---@field isSizing? boolean true while the player resizes it

---@class ForeverTrackerEqotList
---@field left number
---@field right number
---@field top number
---@field bottom number the API's content bottom; EQOT's fixed box bottom is not used as the list end
---@field frame? Frame the fallback frame, when there is no API
---@field topOnly? boolean true when only the top edge means anything, as with EQOT's fixed box

-- The room the column leaves between itself and the list, and from the screen's edges.
local GAP, MARGIN = 8, 24
local WATCH_INTERVAL = 0.25
-- An alpha-only hide is EQOT's other way of turning its list off: IsShown still answers true while nothing draws.
local ALPHA_HIDDEN = 0.01
local LISTENER_ID = "ShortestPathForeverTrackerEqot"

local watched = false
local waits = 0
local ticker, sinceTick, lastPlace
local listenerModule, listenerActive, apiDisabled = nil, false, false

-- Another addon's globals, read with rawget: neither exists unless EQOT is installed.
---@return ForeverEqotTrackerFrame?
local function Frame()
	return rawget(_G, "EQOTTrackerFrame")
end

-- EQOT's module host and its API module, when both are loaded and shaped as expected.
---@return table?
local function Api()
	local tracker = rawget(_G, "EQObjectiveTracker")
	if type(tracker) ~= "table" and type(tracker) ~= "userdata" then
		return nil
	end
	local getModule = tracker.GetModule
	if type(getModule) ~= "function" then
		return nil
	end
	local ok, api = pcall(getModule, tracker, "API")
	if not ok or (type(api) ~= "table" and type(api) ~= "userdata") then
		return nil
	end
	return api
end

-- Whether EQOT has started loading at all, so Await knows there is something to wait for.
---@return boolean
local function Installed()
	return rawget(_G, "EQObjectiveTracker") ~= nil or rawget(_G, "EQOTTrackerFrame") ~= nil
end

-- Whether a bound list or an API module is on screen yet.
---@return boolean
local function Present()
	return Frame() ~= nil or Api() ~= nil
end

-- EQOT can fade its list out instead of hiding it, so an alpha at or near zero counts as hidden too.
---@param frame ForeverEqotTrackerFrame
---@return number
local function EffectiveAlpha(frame)
	if type(frame.GetEffectiveAlpha) == "function" then
		local ok, alpha = pcall(frame.GetEffectiveAlpha, frame)
		if ok and type(alpha) == "number" then
			return alpha
		end
	end
	if type(frame.GetAlpha) == "function" then
		local ok, alpha = pcall(frame.GetAlpha, frame)
		if ok and type(alpha) == "number" then
			return alpha
		end
	end
	return 1
end

---@param frame ForeverEqotTrackerFrame
---@return boolean
local function Visible(frame)
	return frame:IsShown() and EffectiveAlpha(frame) > ALPHA_HIDDEN
end

-- Where the list says it is, as one string, so a move, a resize or a fade shows up as a different one.
---@param frame ForeverEqotTrackerFrame
---@return string
local function Place(frame)
	local point, relativeTo, relativePoint, x, y = frame:GetPoint()
	return table.concat({
		tostring(point),
		tostring(relativeTo),
		tostring(relativePoint),
		x or 0,
		y or 0,
		frame:GetWidth() or 0,
		frame:GetHeight() or 0,
		EffectiveAlpha(frame),
	}, "|")
end

-- Another addon's show, hide, size and drag-stop scripts call `onChange` when the list toggles, grows or is dragged,
-- and one addon-owned ticker notices the moves and resizes nothing of the list's own does: a profile load, or a UI
-- addon such as MoveAnything, sets the list's anchor with no event and no script of its own. The ticker also notices
-- the alpha-only hide, which has no event.
--
-- Nothing of ours is ever anchored to the list. Questie's file records why (Questie/Questie#8076, #188): a probe
-- reaching from the screen's corner to the list's corner put the list inside our anchor family, and Questie's drag
-- code reads the list's corners just before clearing its points, so a layout pass landing in that window errored and
-- left the list unanchored, invisible and undraggable. EQOT reads its own corners the same way. Read here, never
-- written.
---@param frame ForeverEqotTrackerFrame
---@param onChange function
local function Watch(frame, onChange)
	watched = true
	frame:HookScript("OnShow", onChange)
	frame:HookScript("OnHide", onChange)
	frame:HookScript("OnDragStop", onChange)
	-- While the player drags or resizes the list EQOT owns its geometry: the column holds its place, and one reflow
	-- follows the list to where the player let go of it.
	local function Moved()
		if frame.isMoving or frame.isSizing then
			return
		end
		onChange()
	end
	frame:HookScript("OnSizeChanged", Moved)
	ticker = ticker or CreateFrame("Frame")
	lastPlace = Place(frame)
	-- A faded or hidden list keeps nothing to read: the ticker notices the change once, then stops reading
	-- the geometry until the list is shown again. Its OnShow/OnHide hooks still reflow at once.
	local hidden = not Visible(frame)
	ticker:SetScript("OnUpdate", function(_, elapsed)
		sinceTick = (sinceTick or 0) + (elapsed or 0)
		if sinceTick < WATCH_INTERVAL or frame.isMoving or frame.isSizing then
			return
		end
		sinceTick = 0
		if not Visible(frame) then
			if not hidden then
				hidden = true
				onChange()
			end
			return
		end
		hidden = false
		local place = Place(frame)
		if place ~= lastPlace then
			lastPlace = place
			onChange()
		end
	end)
end

-- Stop consulting the API and drop our listener through whichever removal method this EQOT build exposes. Without
-- one the registration is simply left behind: the callback only marks our column dirty, and it is never consulted
-- again after this.
local function RemoveListener()
	if not listenerActive or not listenerModule then
		return
	end
	local removed = false
	for _, name in ipairs({ "RemoveLayoutListener", "UnregisterLayoutListener", "RemoveListener" }) do
		local method = listenerModule[name]
		if type(method) == "function" then
			local ok = pcall(method, listenerModule, LISTENER_ID)
			removed = ok
			break
		end
	end
	listenerActive, listenerModule = false, nil
	-- With no way to take the callback back, stop consulting this API rather than leave it behind.
	apiDisabled = not removed
end

-- Register the layout listener once. If EQOT exposes no usable listener, the API path is abandoned and the fallback
-- frame is read instead.
---@param api table
---@param onChange function
---@return boolean
local function Listen(api, onChange)
	if listenerActive then
		if listenerModule == api then
			return true
		end
		RemoveListener()
	end
	if apiDisabled then
		return false
	end
	local method = api.AddLayoutListener
	if type(method) ~= "function" then
		return false
	end
	local ok = pcall(method, api, { id = LISTENER_ID, onLayout = onChange })
	if not ok then
		return false
	end
	listenerActive, listenerModule = true, api
	return true
end

-- The API bounds in `host`'s own scale, whether EQOT returns them positionally or as a table. A nil answer means
-- EQOT is hidden or turned off, and the column should return to the native anchor.
---@param api table
---@param host Frame
---@return number?, number?, number?, number?
local function ApiEdges(api, host)
	local method = api.GetListBounds
	if type(method) ~= "function" then
		return nil
	end
	local ok, first, second, third, fourth = pcall(method, api)
	if not ok or first == nil then
		return nil
	end
	local left, right, top, bottom
	if type(first) == "table" then
		left, right, top, bottom = first.left, first.right, first.top, first.bottom
	else
		left, right, top, bottom = first, second, third, fourth
	end
	if type(left) ~= "number" or type(right) ~= "number" or type(top) ~= "number" or type(bottom) ~= "number" then
		return nil
	end
	local toHost = UIParent:GetEffectiveScale() / host:GetEffectiveScale()
	return left * toHost, right * toHost, top * toHost, bottom * toHost
end

-- EQOT's fixed box while it is drawn, or nil. Quests draw from the box's TOP, so only that edge is the list's edge.
---@param host Frame
---@param onChange function
---@return ForeverTrackerEqotList?
local function FrameList(host, onChange)
	local frame = Frame()
	if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then
		return nil
	end
	if not watched then
		Watch(frame, onChange)
	end
	if not Visible(frame) then
		return nil
	end
	local _, relativeTo = frame:GetPoint()
	if relativeTo == host then
		return nil
	end
	local rawLeft, rawRight, rawTop, rawBottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
	if not (rawLeft and rawRight and rawTop and rawBottom) then
		return nil
	end
	local toHost = frame:GetEffectiveScale() / host:GetEffectiveScale()
	local left, right = rawLeft * toHost, rawRight * toHost
	local top, bottom = rawTop * toHost, rawBottom * toHost
	return { left = left, right = right, top = top, bottom = bottom, frame = frame, topOnly = true }
end

-- EQOT's list while it is on screen, or nil. The API answers first because EQOT hides the native frame and is the
-- more specific cover; the fixed frame is read only when the API path is unavailable.
---@param host Frame
---@param onChange function
---@return ForeverTrackerEqotList?
function TrackerEqot.List(host, onChange)
	local api = Api()
	if api then
		if not Listen(api, onChange) then
			return FrameList(host, onChange)
		end
		local left, right, top, bottom = ApiEdges(api, host)
		if not (left and right and top and bottom) then
			return nil
		end
		return { left = left, right = right, top = top, bottom = bottom }
	end
	return FrameList(host, onChange)
end

-- EQOT loads after us, or builds its list in stages. While it has started and no list is there yet, check once a
-- second, at most 30 times, and call `onFound` as soon as it appears.
---@param onFound function
function TrackerEqot.Await(onFound)
	if waits >= 30 or not Installed() or Present() then
		return
	end
	waits = waits + 1
	C_Timer.After(1, function()
		if Present() then
			onFound()
		else
			TrackerEqot.Await(onFound)
		end
	end)
end

-- Drop our EQOT listener, if one was registered, so disabling or updating EQOT cannot leave our callback behind.
function TrackerEqot.Unregister()
	RemoveListener()
end

-- The height the sections may take: the room above the list's top, the most any place gives.
---@param list ForeverTrackerEqotList
---@param host Frame
---@return number
function TrackerEqot.Room(list, host)
	local _ = host
	return math.max(0, list.top - MARGIN)
end

-- Where `host`, as laid out, can go round the list, best first, each as { point on UIParent, x, y } in the host's
-- scale: below the list, then above it, each only when it fits on screen, then beside it at `besideX`, level with its
-- top, which always comes last. Below and above line up with the list's edge nearer the screen's side. A fixed box
-- never offers the room below its top, because its bottom says nothing about where its quests end.
---@param list ForeverTrackerEqotList
---@param host Frame
---@param besideX number
---@param screenWidth number
---@param screenHeight number
---@return { [1]: FramePoint, [2]: number, [3]: number }[]
function TrackerEqot.Places(list, host, besideX, screenWidth, screenHeight)
	local left, right, top, bottom = list.left, list.right, list.top, list.bottom
	local width, height = host:GetWidth(), host:GetHeight()
	local function onScreen(x)
		return math.max(0, math.min(x, math.max(0, screenWidth - width)))
	end
	local x = onScreen((left + right) / 2 <= screenWidth / 2 and left or right - width)
	local places = {}
	if not list.topOnly and bottom - GAP - height >= MARGIN then
		places[#places + 1] = { "TOPLEFT", x, bottom - GAP - screenHeight }
	end
	if top + GAP + height <= screenHeight - MARGIN then
		places[#places + 1] = { "BOTTOMLEFT", x, top + GAP }
	end
	places[#places + 1] = { "TOPLEFT", onScreen(besideX), top - screenHeight }
	return places
end
