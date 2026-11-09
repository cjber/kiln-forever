-- EQ Objective Tracker draws its own quest list over the native tracker's slot and hides the native frame
-- (cjber/shortest-path-forever#395). The shared column must move clear of that list without touching it, and come
-- back when it hides. Every scenario builds fresh closures, which LuaJIT cannot trace; the game runs plain Lua 5.1,
-- so interpret.
local jit = rawget(_G, "jit")
if jit then
	jit.off()
end
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
-- Screen pixels from the bottom left corner: left, top, width, height, bottom.
local function bounds(frame)
	if frame.root then
		local scale = frame:GetEffectiveScale()
		return 0, frame.height * scale, frame.width * scale, frame.height * scale, 0
	end
	local point, relative, relativePoint, x, y = unpack((assert(frame.point, "missing anchor")))
	local left, top, rw, _, relativeBottom = bounds(relative)
	local rx, ry = fraction(relativePoint)
	local fx, fy = fraction(point)
	local scale = frame:GetEffectiveScale()
	local width, height = frame.width * scale, frame.height * scale
	left = left + rx * rw + (x or 0) * scale - fx * width
	local anchorY = ry == 0 and relativeBottom or ry == 1 and top or (top + relativeBottom) / 2
	local bottom = anchorY + (y or 0) * scale - fy * height
	return left, bottom + height, width, height, bottom
end
local function clears(a, b)
	local al, at, aw, _, ab = bounds(a)
	local bl, bt, bw, _, bb = bounds(b)
	return not (al < bl + bw - 0.01 and al + aw > bl + 0.01 and ab < bt - 0.01 and at > bb + 0.01)
end
local function near(a, b)
	return math.abs(a - b) < 0.01
end
-- The API reports UIParent units; bounds() works in screen pixels.
local function clearsBounds(frame, rectangle, uiScale)
	local fl, ft, fw, _, fb = bounds(frame)
	local left, right = rectangle.left * uiScale, rectangle.right * uiScale
	local top, bottom = rectangle.top * uiScale, rectangle.bottom * uiScale
	return not (fl < right - 0.01 and fl + fw > left + 0.01 and fb < top - 0.01 and ft > bottom + 0.01)
end

-- Each scenario runs the files afresh in its own environment; compiling them once keeps that cheap.
local chunks = {}
local function chunk(path)
	chunks[path] = chunks[path] or assert(loadfile(path))
	return chunks[path]
end

-- options: eqotApi = { left, right, top, bottom } or nil, eqotFrame = { point, x, y, width, height, alpha, shown },
-- questie = { point, x, y, height }, attached, scale, uiScale, userScale, loadsLate
local function scenario(options)
	local frames, timers, ready, combat = {}, {}, nil, false
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
			return (bounds(self)) / self:GetEffectiveScale()
		end
		function f:GetTop()
			return select(2, bounds(self)) / self:GetEffectiveScale()
		end
		function f:GetRight()
			local left, _, width = bounds(self)
			return (left + width) / self:GetEffectiveScale()
		end
		function f:GetBottom()
			return select(5, bounds(self)) / self:GetEffectiveScale()
		end
		function f:GetAlpha()
			return self.alpha == nil and 1 or self.alpha
		end
		function f:GetEffectiveAlpha()
			local ownParent = self.parent
			local parentAlpha = ownParent and ownParent.GetEffectiveAlpha and ownParent:GetEffectiveAlpha() or 1
			return self:GetAlpha() * parentAlpha
		end
		function f:SetClampedToScreen(value)
			self.clamped = value
		end
		function f:IsClampedToScreen()
			return self.clamped
		end
		function f:SetScript(event, fn)
			self.scripts[event] = fn
		end
		function f:HookScript(event, fn)
			self.hooks = self.hooks or {}
			self.hooks[event] = fn
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
	local screen = frame()
	screen.root, screen.width, screen.height, screen.scale = true, 1200, 1080, options.uiScale or 1
	local native = frame(nil, "native", screen)
	native.scale, native.height = options.scale or 1, 300
	native:SetClampedToScreen(true)
	native:SetPoint("TOPRIGHT", screen, "TOPRIGHT", -24, -100)
	local slot = { native:GetPoint() }
	local nineSlice = frame(nil, "nineSlice", native)
	nineSlice:SetPoint("TOP", native, "TOP", 0, -300)
	native.NineSlice = nineSlice
	local rawPoint, rawClear = native.SetPoint, native.ClearAllPoints
	function native:SetPoint(...)
		assert(not combat, "protected combat reposition")
		rawPoint(self, ...)
	end
	function native:ClearAllPoints()
		assert(not combat, "protected combat clear")
		rawClear(self)
	end
	local settings = { attached = options.attached ~= false, scale = options.userScale or 1 }
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
	setfenv(chunk("UI/TrackerEqot.lua"), env)("Test", ns)
	setfenv(chunk("UI/TrackerQuestie.lua"), env)("Test", ns)
	setfenv(chunk("UI/TrackerLock.lua"), env)("Test", ns)
	setfenv(chunk("UI/TrackerOrder.lua"), env)("Test", ns) -- the section order, loaded before the host
	setfenv(chunk(os.getenv("TRACKER_HOST_SOURCE") or "UI/TrackerHost.lua"), env)("Test", ns)
	local host = frames[4]
	local module = frame()
	module.uiOrder = -1
	module.SetContainer, module.Update = noop, noop
	module.SetParent = function(self, parent)
		self.parent = parent
	end
	module.GetContentsHeight = function()
		return module.empty and 0 or 227
	end
	ns.TrackerHost.Attach(module)
	local function drain()
		local pending = timers
		timers = {}
		for _, fn in ipairs(pending) do
			fn()
		end
	end
	local eqotApi, eqotApiState, eqotFrame, eqotListener
	local function makeApi(rectangle)
		eqotApiState = { bounds = rectangle }
		eqotApi = {}
		function eqotApi.GetListBounds()
			return eqotApiState.bounds
		end
		function eqotApi.AddLayoutListener(_, listener)
			eqotListener = listener
			return true
		end
		env.EQObjectiveTracker = {
			GetModule = function(_, name)
				if name == "API" then
					return eqotApi
				end
			end,
		}
		native.shown = false
		return eqotApi
	end
	local function makeFrame(spec)
		eqotFrame = frame(nil, "EQOTTrackerFrame", screen)
		eqotFrame.width, eqotFrame.height = spec.width or 305, spec.height or 600
		eqotFrame.alpha = spec.alpha
		if spec.shown == false then
			eqotFrame.shown = false
		end
		local point = spec.point or "TOPRIGHT"
		eqotFrame:SetPoint(point, screen, point, spec.x or -24, spec.y or -100)
		env.EQOTTrackerFrame = eqotFrame
		native.shown = false
		return eqotFrame
	end
	local questie
	local function makeQuestie()
		local spec = options.questie
		questie = frame(nil, "Questie_BaseFrame", screen)
		questie.width, questie.height = 280, spec.height
		questie:SetPoint(spec.point, screen, spec.point, spec.x, spec.y)
		env.Questie_BaseFrame = questie
		native.shown = false
		return questie
	end
	if options.eqotApi then
		makeApi(options.eqotApi)
	end
	if options.eqotFrame and not options.loadsLate then
		makeFrame(options.eqotFrame)
	end
	if options.loadsLate then
		env.EQObjectiveTracker = {}
		native.shown = false
	end
	if options.questie or options.questieOff then
		env.Questie = {}
	end
	if options.questie then
		makeQuestie()
	end
	ready()
	drain()
	if options.loadsLate then
		check(#timers == 1, "waits for EQOT while it is still starting")
		if options.eqotFrame then
			makeFrame(options.eqotFrame)
		else
			makeApi(options.eqotApi)
		end
		drain()
		drain()
	end
	return {
		host = host,
		module = module,
		native = native,
		frames = frames,
		eqotFrame = eqotFrame,
		questie = questie,
		slot = slot,
		settings = settings,
		drain = drain,
		setBounds = function(rectangle)
			eqotApiState.bounds = rectangle
		end,
		fire = function()
			if eqotListener and eqotListener.onLayout then
				eqotListener.onLayout()
			end
		end,
		-- One watcher tick, the way the game runs the ticker's OnUpdate.
		tick = function(delta)
			for _, other in ipairs(frames) do
				if other.scripts.OnUpdate then
					other.scripts.OnUpdate(other, delta or 1)
				end
			end
		end,
		pending = function()
			return #timers
		end,
		setCombat = function(value)
			combat = value
		end,
	}
end

-- The native tracker keeps its own slot and the column starts where the native quests end.
local function stacked(s, label)
	local p, rel, rp, x, y = s.native:GetPoint()
	check(
		p == s.slot[1] and rel == s.slot[2] and rp == s.slot[3] and x == s.slot[4] and y == s.slot[5],
		label .. ": the native tracker keeps its slot"
	)
	local _, _, _, _, contentBottom = bounds(s.native.NineSlice)
	local _, hostTop = bounds(s.host)
	check(near(hostTop, contentBottom), label .. ": the column starts below the native quests")
end

for _, scale in ipairs({ 0.75, 1, 1.25 }) do
	for _, uiScale in ipairs({ 1, 0.8 }) do
		for _, userScale in ipairs({ 0.5, 1 }) do
			local label = ("scale %s ui %s user %s"):format(scale, uiScale, userScale)
			local base = { scale = scale, uiScale = uiScale, userScale = userScale }
			local function with(extra)
				local result = {}
				for key, value in pairs(base) do
					result[key] = value
				end
				for key, value in pairs(extra) do
					result[key] = value
				end
				return result
			end

			-- Without EQOT nothing changes: the native tracker keeps its slot and the column reads below its quests.
			stacked(scenario(base), label .. " no EQOT")

			-- EQOT's API answers: the column steps clear of the bounds, not of the hidden native frame.
			local apiBounds = { left = 40, right = 440, top = 900, bottom = 100 }
			local s = scenario(with({ eqotApi = apiBounds }))
			check(s.host:IsShown(), label .. ": the column shows beside EQOT")
			check(clearsBounds(s.host, apiBounds, uiScale), label .. ": the column clears EQOT's bounds")
			local p, rel, rp, x, y = s.native:GetPoint()
			check(
				p == s.slot[1] and rel == s.slot[2] and rp == s.slot[3] and x == s.slot[4] and y == s.slot[5],
				label .. ": the native tracker stays in its own slot"
			)
			check(s.native:IsClampedToScreen(), label .. ": the native tracker keeps its screen clamp")

			-- EQOT redraws and moves its list: its listener re-places the column with no ticker of ours.
			local before = { bounds(s.host) }
			local moved = { left = 520, right = 920, top = 820, bottom = 100 }
			s.setBounds(moved)
			s.fire()
			s.drain()
			check(clearsBounds(s.host, moved, uiScale), label .. ": an EQOT layout moves the column off the new bounds")
			local after = { bounds(s.host) }
			check(
				not (near(before[1], after[1]) and near(before[2], after[2])),
				label .. ": the column followed EQOT's move"
			)

			-- GetListBounds() returns nil while EQOT is hidden or off: the column returns to the native anchor.
			s.native.shown = true
			s.setBounds(nil)
			s.fire()
			s.drain()
			stacked(s, label .. " after EQOT hides")

			-- No API: EQOTTrackerFrame is read instead, and its fixed box bottom is never the list end.
			local frameSpec = { point = "TOPRIGHT", x = -24, y = -100, width = 305, height = 600 }
			local f = scenario(with({ eqotFrame = frameSpec }))
			check(f.host:IsShown(), label .. ": the column shows beside EQOT's frame")
			check(clears(f.host, f.eqotFrame), label .. ": the column clears EQOT's frame")
			local frameLeft, frameTop = bounds(f.eqotFrame)
			local hostLeft, hostTop = bounds(f.host)
			local _, _, _, _, frameBottom = bounds(f.eqotFrame)
			local _, _, _, _, hostBottom = bounds(f.host)
			check(hostLeft < frameLeft and near(hostTop, frameTop), label .. ": beside the frame, level with its top")
			check(hostBottom > frameBottom, label .. ": EQOT's box bottom is never treated as the list end")

			-- EQOT can fade its list out while IsShown still answers true: that is hidden too.
			local frameReads, realGetPoint = 0, f.eqotFrame.GetPoint
			f.eqotFrame.GetPoint = function(self)
				frameReads = frameReads + 1
				return realGetPoint(self)
			end
			f.native.shown = true
			f.eqotFrame.alpha = 0
			f.tick(1)
			f.drain()
			stacked(f, label .. " after EQOT fades out")
			-- A hidden list keeps nothing to read, so the watcher stops reading its geometry after the change.
			frameReads = 0
			f.tick(1)
			f.tick(1)
			f.tick(1)
			check(frameReads == 0, label .. ": a faded EQOT list is not read on every tick")

			-- A detached column the player has not dragged starts beside EQOT's bounds, not the hidden native one.
			local detachedBounds = { left = 40, right = 440, top = 900, bottom = 100 }
			local d = scenario(with({ attached = false, eqotApi = detachedBounds }))
			local detachedLeft, detachedTop = bounds(d.host)
			check(
				detachedLeft > detachedBounds.right * uiScale,
				label .. ": the detached column starts clear of EQOT's bounds"
			)
			check(near(detachedTop, detachedBounds.top * uiScale), label .. ": beside them, level with their top")
			-- Once dragged, the player's place wins.
			d.settings.x, d.settings.y = 300, -500
			d.host:MarkDirty()
			d.drain()
			local _, draggedTop = bounds(d.host)
			check(near(draggedTop, (1080 - 500) * uiScale), label .. ": a dragged column stays where it was put")

			-- The same fallback list starts a detached column beside its frame.
			local df = scenario(with({ attached = false, eqotFrame = frameSpec }))
			local fallbackLeft, fallbackTop = bounds(df.host)
			local eqotLeft, eqotTop = bounds(df.eqotFrame)
			check(clears(df.host, df.eqotFrame), label .. ": the detached column clears EQOT's frame")
			check(fallbackLeft < eqotLeft and near(fallbackTop, eqotTop), label .. ": beside it, level with its top")

			-- EQOT hides the native frame, so it is the more specific cover when Questie is installed too.
			local both = scenario(with({
				eqotApi = apiBounds,
				questie = { point = "TOPLEFT", x = 24, y = -100, height = 300 },
			}))
			check(clearsBounds(both.host, apiBounds, uiScale), label .. ": EQOT is consulted before Questie")

			-- EQOT builds its list after we load: a bounded wait finds it and re-places the column.
			local late = scenario(with({
				loadsLate = true,
				eqotFrame = { point = "TOPRIGHT", x = -24, y = -100, width = 305, height = 600 },
			}))
			check(clears(late.host, late.eqotFrame), label .. ": a late EQOT list still moves the column")
		end
	end
end

-- Without EQOT there is nothing to wait for.
local none = scenario({})
check(none.pending() == 0, "no wait without EQOT")
stacked(none, "no EQOT")
print("tracker_eqot_spec: " .. checks .. " checks passed")
