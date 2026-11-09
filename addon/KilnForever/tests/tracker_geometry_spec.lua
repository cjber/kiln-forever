-- The attached column on a geometry that resolves anchors recursively in screen pixels, native screen clamping
-- included, across tracker anchors and scales: the protected native tracker keeps its slot and the column reads below
-- its quests, in combat and out. Nominal GetPoint anchors remain unchanged when Blizzard clamps a frame.
local checks = 0
local function check(value, message)
	assert(value, message)
	checks = checks + 1
end
local function noop() end
local function fraction(point)
	local x = point:find("LEFT", 1, true) and 0 or point:find("RIGHT", 1, true) and 1 or 0.5
	local y = point:find("BOTTOM", 1, true) and 0 or point:find("TOP", 1, true) and 1 or 0.5
	return x, y
end
local function bounds(frame, seen)
	if frame.root then
		local scale = frame:GetEffectiveScale()
		return 0, frame.height * scale, frame.width * scale, frame.height * scale, 0
	end
	seen = seen or {}
	assert(not seen[frame], "anchor dependency cycle")
	seen[frame] = true
	local point, relative, relativePoint, x, y = unpack((assert(frame.point, "missing anchor")))
	local left, top, rw, _, relativeBottom = bounds(relative, seen)
	local rx, ry = fraction(relativePoint)
	local fx, fy = fraction(point)
	local scale = frame:GetEffectiveScale()
	local width, height = frame.width * scale, frame.height * scale
	left = left + rx * rw + (x or 0) * scale - fx * width
	local anchorY = ry == 0 and relativeBottom or ry == 1 and top or (top + relativeBottom) / 2
	local bottom = anchorY + (y or 0) * scale - fy * height
	top = fy == 1 and anchorY + (y or 0) * scale or bottom + height
	if frame.clamped then
		left = math.max(0, math.min(left, frame.screen.width * frame.screen:GetEffectiveScale() - width))
		local clampedTop = math.max(height, math.min(top, frame.screen.height * frame.screen:GetEffectiveScale()))
		if clampedTop ~= top then
			bottom = clampedTop - height
		end
		top = clampedTop
	end
	seen[frame] = nil
	return left, top, width, height, bottom
end
-- Touching edges (a column that starts at the content's bottom) are clear, floating point included.
local function clears(a, b)
	local al, at, aw, _, ab = bounds(a)
	local bl, bt, bw, _, bb = bounds(b)
	return not (al < bl + bw - 0.01 and al + aw > bl + 0.01 and ab < bt - 0.01 and at > bb + 0.01)
end
-- `fill`: the section takes all the room it is given, as a long guide does; otherwise it is one 227-high block, shown
-- whole when it fits and skipped when it does not, as Blizzard's modules lay out blocks.
local function scenario(anchor, scale, uiScale, userScale, fill)
	local frames, timers, ready, combat = {}, {}, nil, false
	local screen
	local function frame(_, name, parent)
		local f = { name = name, parent = parent, width = 250, height = 1, scripts = {} }
		function f:GetEffectiveScale()
			return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1)
		end
		function f:SetScale(value)
			self.scale = value
		end
		function f:SetPoint(...)
			self.point = { ... }
		end
		function f:GetPoint()
			return unpack(self.point or {})
		end
		function f:ClearAllPoints()
			self.point = nil
		end
		function f:SetWidth(value)
			self.width = value
		end
		function f:GetWidth()
			return self.width
		end
		function f:SetHeight(value)
			self.height = value
		end
		function f:GetHeight()
			return self.height
		end
		function f:GetLeft()
			local left = bounds(self)
			return left / self:GetEffectiveScale()
		end
		function f:GetTop()
			local _, top = bounds(self)
			return top / self:GetEffectiveScale()
		end
		function f:GetRight()
			local left, _, width = bounds(self)
			return (left + width) / self:GetEffectiveScale()
		end
		function f:GetBottom()
			local _, _, _, _, bottom = bounds(self)
			return bottom / self:GetEffectiveScale()
		end
		function f:SetClampedToScreen(value)
			self.clamped, self.screen = value, screen
		end
		function f:IsClampedToScreen()
			return self.clamped
		end
		function f:SetScript(event, fn)
			self.scripts[event] = fn
		end
		function f:HookScript(event, fn)
			self.scripts[event] = fn
		end
		function f:SetShown(value)
			self.shown = value
		end
		function f:Hide()
			self.shown = false
		end
		function f:Show()
			self.shown = true
		end
		function f:IsShown()
			return self.shown ~= false
		end
		function f.CreateFontString(_)
			return { SetPoint = noop, SetText = noop }
		end
		function f.CreateTexture(_)
			return {
				SetPoint = noop,
				SetAtlas = noop,
				SetVertexColor = noop,
				SetShown = noop,
				Hide = noop,
			}
		end
		f.SetMovable, f.RegisterForDrag, f.RegisterEvent = noop, noop, noop
		frames[#frames + 1] = f
		return f
	end
	screen = frame()
	screen.root, screen.width, screen.height, screen.scale = true, 1200, 1080, uiScale
	local native = frame(nil, "native", screen)
	native.scale, native.height = scale, 300
	native:SetClampedToScreen(true)
	local x = anchor:find("LEFT", 1, true) and 24 or anchor:find("RIGHT", 1, true) and -24 or 0
	local y = anchor:find("BOTTOM", 1, true) and 180 or -100
	native:SetPoint(anchor, screen, anchor, x, y)
	local nineSlice = frame(nil, "nineSlice", native)
	nineSlice.width, nineSlice.height, nineSlice.scale = 250, 1, 1
	nineSlice:SetPoint("TOP", native, "TOP", 0, -300)
	native.NineSlice = nineSlice
	-- The host never writes the protected native tracker; Blizzard's own moves below go through the raw methods.
	local rawPoint, rawHeight = native.SetPoint, native.SetHeight
	for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetHeight", "SetClampedToScreen" }) do
		native[method] = function()
			error("the host wrote the protected native tracker: " .. method)
		end
	end
	local settings = { attached = true, scale = userScale or 1 }
	local ns = {
		L = setmetatable({}, {
			__index = function(_, key)
				return key
			end,
		}),
		TrackerHostSettings = function()
			return settings
		end,
	}
	local env = setmetatable({
		UIParent = screen,
		ObjectiveTrackerFrame = native,
		CreateFrame = frame,
		InCombatLockdown = function()
			return combat
		end,
		C_Timer = {
			After = function(_, fn)
				timers[#timers + 1] = fn
			end,
		},
		EventUtil = {
			ContinueAfterAllEvents = function(fn)
				ready = fn
			end,
		},
		EventRegistry = { RegisterCallback = noop },
		Mixin = function(target, mixin)
			for key, value in pairs(mixin) do
				target[key] = value
			end
		end,
		hooksecurefunc = function() end,
		CreateFramePoolCollection = function()
			return {}
		end,
	}, { __index = _G })
	env._G = env
	setfenv(assert(loadfile("UI/TrackerLock.lua")), env)("Test", ns)
	setfenv(assert(loadfile("UI/TrackerOrder.lua")), env)("Test", ns) -- the section order, loaded before the host
	setfenv(assert(loadfile(os.getenv("TRACKER_HOST_SOURCE") or "UI/TrackerHost.lua")), env)("Test", ns)
	local host = frames[4]
	local module = frame()
	module.uiOrder = -1
	local used = 0
	module.SetContainer = noop
	module.Update = function(_, available)
		used = fill and math.max(0, math.floor(available)) or (available >= 227 and 227 or 0)
	end
	module.SetParent = function(self, parent)
		self.parent = parent
	end
	module.GetContentsHeight = function()
		return used
	end
	ns.TrackerHost.Attach(module)
	local function drain()
		local pending = timers
		timers = {}
		for _, fn in ipairs(pending) do
			fn()
		end
	end
	local label = anchor .. " scale " .. scale .. " ui " .. uiScale .. " user " .. userScale .. (fill and " fill" or "")
	local slot = { native:GetPoint() }
	ready()
	drain()
	local function below()
		local _, _, _, _, contentBottom = bounds(nineSlice)
		local left, top, width, height = bounds(host)
		local screenWidth = screen.width * screen:GetEffectiveScale()
		check(left >= -0.01 and left + width <= screenWidth + 0.01, "the column stays on screen: " .. label)
		check(clears(host, nineSlice), "the column clears the native quests: " .. label)
		return top, contentBottom, height
	end
	local function inSlot()
		local p, rel, rp, nx, ny = native:GetPoint()
		return p == slot[1] and rel == slot[2] and rp == slot[3] and nx == slot[4] and ny == slot[5]
	end
	check(inSlot(), "the native tracker keeps its Edit Mode slot: " .. label)
	local top, contentBottom = below()
	-- Only the off-screen fallback, for quests ending too low to fit the column below them, places it elsewhere.
	local fits = host.point[2] == nineSlice
	if fill and used > 0 then
		-- A section that fills the room below the quests shrinks to it: it never sends the column to the side.
		check(fits, "a section filling the room stays below the quests: " .. label)
		local _, _, _, _, hostBottom = bounds(host)
		check(hostBottom >= -0.01, "and ends on screen: " .. label)
	end
	if fits then
		check(math.abs(top - contentBottom) < 0.01, "the column starts where the native quests end: " .. label)
	end
	local before = { bounds(host) }
	local function still(message)
		local now = { bounds(host) }
		for index = 1, 4 do
			check(math.abs(now[index] - before[index]) < 0.01, message .. ": " .. label)
		end
	end
	for _ = 1, 3 do
		host:MarkDirty()
		drain()
	end
	still("repeated layout does not drift")
	combat = true
	host.scripts.OnEvent(host, "PLAYER_REGEN_DISABLED")
	drain()
	still("entering combat leaves the column still")
	-- Blizzard's managed-frame layout puts the protected frame back in its saved slot in combat: already there.
	rawPoint(native, unpack(slot))
	host:MarkDirty()
	drain()
	still("a native restore in combat leaves the column still")
	-- Quests grow in combat: the column follows the native content down.
	nineSlice.point = { "TOP", native, "TOP", 0, -320 }
	host:MarkDirty()
	drain()
	top, contentBottom = below()
	if fits then
		check(math.abs(top - contentBottom) < 0.01, "the column follows growing quests in combat: " .. label)
	end
	nineSlice.point = { "TOP", native, "TOP", 0, -300 }
	rawHeight(native, 300)
	combat = false
	host.scripts.OnEvent(host, "PLAYER_REGEN_ENABLED")
	drain()
	still("leaving combat leaves the column still")
	-- When the column would run off the bottom of the screen, the fallback still clears the native content.
	nineSlice.point = { "BOTTOM", native, "BOTTOM", 0, 0 }
	host:MarkDirty()
	drain()
	below()
	ns.TrackerHost.SetAttached(false)
	drain()
	check(inSlot(), "detaching leaves the native tracker in its slot: " .. label)
end
for _, scale in ipairs({ 0.75, 1, 1.25 }) do
	for _, anchor in ipairs({ "TOPRIGHT", "TOPLEFT", "TOP", "CENTER", "BOTTOM", "BOTTOMRIGHT" }) do
		for _, userScale in ipairs({ 0.5, 1 }) do
			scenario(anchor, scale, 1, userScale)
			scenario(anchor, scale, 0.8, userScale)
			scenario(anchor, scale, 1, userScale, true)
		end
	end
end
print("tracker_geometry_spec: " .. checks .. " checks passed")
