-- The shared tracker's grip, now its own file (UI/TrackerLock.lua), draws the column's drag handle and reads the Lock
-- switch that suppresses a drag. It is loaded on its own here: the host's settings arrive through ns.TrackerHost, so
-- the module holds no copy of the switch, and a host that is not loaded yet simply reads as unlocked.
local checks = 0
local function check(value, message)
	assert(value, message)
	checks = checks + 1
end
local function noop() end
local tooltipText
local GameTooltip = {
	SetOwner = noop,
	Show = noop,
	Hide = noop,
	SetText = function(_, text)
		tooltipText = text
	end,
}
local frames, combat = {}, false
local function frame()
	local f = { width = 250, height = 0, scripts = {}, shown = true, scale = 1, left = 0, top = 640 }
	function f:SetParent(owner)
		self.parent = owner
	end
	function f:SetPoint(...)
		self.point = { ... }
	end
	function f:GetPoint()
		return unpack(self.point or {})
	end
	function f:SetHeight(value)
		self.height = value
	end
	function f:GetHeight()
		return self.height
	end
	function f:GetEffectiveScale()
		return self.scale
	end
	function f:SetScript(event, fn)
		self.scripts[event] = fn
	end
	f.RegisterForDrag = noop
	function f:SetShown(value)
		self.shown = value
	end
	function f:IsShown()
		return self.shown
	end
	function f.Hide(self)
		self.shown = false
	end
	function f.Show(self)
		self.shown = true
	end
	function f:StartMoving()
		self.moving = true
	end
	function f:StopMovingOrSizing()
		self.moving = false
	end
	function f:GetLeft()
		return self.left
	end
	function f:GetTop()
		return self.top
	end
	function f:CreateFontString()
		local fontString = { SetPoint = noop }
		function fontString.SetText(font, value)
			font.text = value
		end
		self.label = fontString
		return fontString
	end
	frames[#frames + 1] = f
	return f
end
local parent = frame()
parent.height = 1080
-- English phrases with no constants set, as the addon has them: every fallback sentence is the one a player reads.
local ns = {
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
}
local env = setmetatable({
	UIParent = parent,
	CreateFrame = function(...)
		local made = frame(...)
		made.parent = select(3, ...)
		return made
	end,
	GameTooltip = GameTooltip,
	InCombatLockdown = function()
		return combat
	end,
}, { __index = _G })
env._G = env
setfenv(assert(loadfile("UI/TrackerLock.lua")), env)("Test", ns)
local module = assert(ns.TrackerLock, "the module registers itself on the namespace")

-- A host standing in for UI/TrackerHost.lua, which is what the grip asks for the switch and to save a drag. The module
-- finds it on the namespace, as it does at runtime.
local locked, attached, saved = false, false, {}
local host = {
	IsLocked = function()
		return locked
	end,
	IsAttachedToQuestTracker = function()
		return attached
	end,
	SavePosition = function(x, y)
		saved[#saved + 1] = { x, y }
	end,
}

-- With no host loaded yet the module reads as unlocked rather than erroring: the TOC loads this file first.
check(module.Locked() == false, "a host that is not loaded yet reads as unlocked")
ns.TrackerHost = host
local column = frame()
local grip = module.Grip(column, host)
local handle = frames[#frames]
check(handle.parent == column, "the grip is made on the column it drags")
local label = handle.label
local function hover()
	tooltipText = nil
	handle.scripts.OnEnter(handle)
end

-- A host that answers but has no IsLocked, as an older companion addon's would.
host.IsLocked = nil
check(module.Locked() == false, "a host without IsLocked reads as unlocked")
host.IsLocked = function()
	return locked
end

-- Unlocked and detached: the grip offers a drag, moves the column and saves where it stopped.
hover()
check(tooltipText == "Drag to move", "an unlocked grip offers a drag")
check(label.text == "Forever tracker", "an unlocked grip keeps the column's title")
handle.scripts.OnDragStart(handle)
check(column.moving == true, "an unlocked drag moves the column")
column.left, column.top = 500, 900
handle.scripts.OnDragStop(handle)
check(column.moving == false, "letting go stops the move")
check(#saved == 1, "the drag saves once")
check(saved[1][1] == 500 and saved[1][2] == -180, "the drag saves the column's screen position")
handle.scripts.OnLeave(handle)

-- Locked: the drag is refused before it starts, so letting go saves nothing. The grip draws no sentence of its own:
-- the long text lives only in the tooltip, and the short title returns only while the pointer is over the grip.
locked = true
check(module.Locked(), "lock reads back from the host")
grip.SetLabel(true)
check(label.text == "", "a locked grip draws no text until it is hovered")
hover()
check(tooltipText == "The tracker is locked. Turn off Lock the tracker to move it.", "a locked grip says so")
check(label.text == "Forever tracker", "a hovered locked grip shows only the column's title")
handle.scripts.OnLeave(handle)
check(label.text == "", "leaving a locked grip hides its text again")
handle.scripts.OnDragStart(handle)
check(column.moving == false, "a locked drag never starts")
column.left, column.top = 510, 910
handle.scripts.OnDragStop(handle)
check(#saved == 1, "a locked drag saves no new position")
-- The host redraws the label the moment the switch flips, without waiting for a hover.
locked = false
grip.SetLabel(false)
check(label.text == "Forever tracker", "the label follows the switch back to the column's title")
grip.SetLabel(true)
check(label.text == "", "and the locked sentence never returns to the label")

-- Attached, the host moves the column itself, so the grip refuses a drag whether or not Lock is on.
locked = false
attached = true
hover()
check(tooltipText == "Drag to move", "an attached grip still offers no lock wording")
handle.scripts.OnDragStart(handle)
check(column.moving == false, "an attached column's grip starts no drag")

-- In combat the drag waits for it to end, as the host does, and the switch itself changes nothing.
attached = false
combat = true
handle.scripts.OnDragStart(handle)
check(column.moving == false, "a drag in combat waits")
combat = false
handle.scripts.OnDragStart(handle)
check(column.moving == true, "the drag works once combat ends")
handle.scripts.OnDragStop(handle)

-- The host hides the grip while the column is attached, and shows it again when it is let go.
grip.Show(false)
check(handle.shown == false, "the host can hide the grip")
grip.Show(true)
check(handle.shown == true, "and show it again")

print("tracker_lock_spec: " .. checks .. " checks passed")
