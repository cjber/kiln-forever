-- Questie draws its quest list in Questie_BaseFrame over the native tracker's slot (cjber/shortest-path-forever#214).
-- The shared column must move out from under that list without touching it, and come back when it hides.
-- Every scenario builds fresh closures, which LuaJIT cannot trace; the game runs plain Lua 5.1, so interpret.
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

-- Each scenario runs the files afresh in its own environment; compiling them once keeps that cheap.
local chunks = {}
local function chunk(path)
	chunks[path] = chunks[path] or assert(loadfile(path))
	return chunks[path]
end

-- options: questie = { point, x, y, height } or nil, attached, scale, uiScale, userScale, loadsLate
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
	local questie
	local function makeQuestie()
		local spec = options.questie
		questie = frame(nil, "Questie_BaseFrame", screen)
		questie.width, questie.height = 280, spec.height
		questie:SetPoint(spec.point, screen, spec.point, spec.x, spec.y)
		env.Questie_BaseFrame = questie
		-- Questie hides the native tracker while its own list is enabled.
		native.shown = false
		return questie
	end
	if options.questie or options.questieOff then
		env.Questie = {}
	end
	if options.questie then
		if not options.loadsLate then
			makeQuestie()
		end
	end
	ready()
	drain()
	if options.loadsLate then
		check(#timers == 1, "waits for Questie's tracker while Questie is still starting")
		makeQuestie()
		drain()
		drain()
	end
	return {
		host = host,
		module = module,
		native = native,
		frames = frames,
		questie = questie,
		slot = slot,
		settings = settings,
		drain = drain,
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

			-- Without Questie nothing changes: the native tracker keeps its slot and the column reads below its quests.
			stacked(scenario(base), label .. " no Questie")

			-- Hiding the journey section leaves no companion content: the column hides and the native tracker keeps its slot.
			local empty = scenario(base)
			empty.module.empty = true
			empty.host:MarkDirty()
			empty.drain()
			check(not empty.host:IsShown(), label .. ": no journey section hides the column")
			check(
				empty.native.point[1] == empty.slot[1]
					and empty.native.point[2] == empty.slot[2]
					and empty.native.point[4] == empty.slot[4]
					and empty.native.point[5] == empty.slot[5],
				label .. ": the default tracker can be moved after its section is hidden"
			)

			-- Questie's list over the native slot: the column goes below it, and the native tracker keeps its slot.
			local s = scenario(with({ questie = { point = "TOPRIGHT", x = -24, y = -100, height = 300 } }))
			local _, _, _, _, questieBottom = bounds(s.questie)
			local _, hostTop = bounds(s.host)
			check(s.host:IsShown(), label .. ": the column shows beside Questie")
			check(clears(s.host, s.questie), label .. ": the column clears Questie's list")
			check(hostTop < questieBottom and hostTop > questieBottom - 20, label .. ": the column sits just below it")
			local p, rel, rp, x, y = s.native:GetPoint()
			check(
				p == s.slot[1] and rel == s.slot[2] and rp == s.slot[3] and x == s.slot[4] and y == s.slot[5],
				label .. ": the native tracker stays in its own slot"
			)
			check(s.native:IsClampedToScreen(), label .. ": the native tracker keeps its screen clamp")
			check(
				s.questie.point[1] == "TOPRIGHT" and s.questie.point[4] == -24,
				label .. ": Questie's frame is untouched"
			)
			check(s.host.width == s.native.width, label .. ": the column keeps the tracker's width")
			local hidden = scenario(with({ questie = { point = "TOPRIGHT", x = -24, y = -100, height = 300 } }))
			hidden.module.empty = true
			hidden.host:MarkDirty()
			hidden.drain()
			check(not hidden.host:IsShown(), label .. ": no journey section releases the Questie companion anchor")
			check(
				hidden.native.point[1] == hidden.slot[1] and hidden.native.point[2] == hidden.slot[2],
				label .. ": the hidden companion column leaves the native anchor available to Questie"
			)
			check(
				hidden.questie.point[1] == "TOPRIGHT" and hidden.questie.point[4] == -24,
				label .. ": Questie's anchor stays user-owned"
			)

			-- Nothing of ours may sit in Questie's anchor family. Questie reads the list's own corners and then clears
			-- its points (TrackerBaseFrame.lua, _UpdateTrackerPosition); a frame of ours anchored to the list left
			-- those reads nil and the list unanchored and undraggable (Questie/Questie#8076, #188).
			local anchored = false
			for _, other in ipairs(s.frames) do
				if other.point and other.point[2] == s.questie then
					anchored = true
				end
			end
			check(not anchored, label .. ": no Forever frame is anchored to Questie's list")
			-- A move nothing of the list's own announces - a profile load, MoveAnything - is still noticed.
			s.questie:SetPoint("TOPLEFT", s.host.parent, "TOPLEFT", 24, -100)
			s.tick(1)
			s.drain()
			check(clears(s.host, s.questie), label .. ": a move of Questie's list is noticed and the column follows")

			-- While the player drags the list Questie owns its geometry: the column holds its place, then follows the
			-- list to where the player let go of it.
			s.questie.height = 400
			s.questie.isMoving = true
			local heldLeft, heldTop = bounds(s.host)
			s.questie.hooks.OnSizeChanged(s.questie)
			s.drain()
			local stillLeft, stillTop = bounds(s.host)
			check(
				near(heldLeft, stillLeft) and near(heldTop, stillTop),
				label .. ": a drag of Questie's list holds the column still"
			)
			s.questie.isMoving = false
			s.questie.hooks.OnDragStop(s.questie)
			s.drain()
			check(clears(s.host, s.questie), label .. ": the column follows the list when the drag ends")

			-- Questie hides its list: the column returns below the native quests.
			s.questie:Hide()
			s.native.shown = true
			s.questie.hooks.OnHide(s.questie)
			s.drain()
			stacked(s, label .. " after Questie hides")
			-- And shows it again.
			s.questie:Show()
			s.questie.hooks.OnShow(s.questie)
			s.drain()
			check(clears(s.host, s.questie), label .. ": the column moves off Questie's list when it shows again")
			-- A taller list (more quests tracked) pushes the column down.
			s.questie.height = 400
			s.questie.hooks.OnSizeChanged(s.questie)
			s.drain()
			check(clears(s.host, s.questie), label .. ": the column follows Questie's list as it grows")

			-- In combat the column still moves (it is ours), the protected native tracker does not.
			local late = scenario(with({ questie = { point = "TOPRIGHT", x = -24, y = -100, height = 300 } }))
			late.questie:Hide()
			late.native.shown = true
			late.questie.hooks.OnHide(late.questie)
			late.drain()
			stacked(late, label .. " stacked before combat")
			late.setCombat(true)
			late.questie:Show()
			late.questie.hooks.OnShow(late.questie)
			late.drain()
			check(clears(late.host, late.questie), label .. ": Questie showing in combat moves the column off it")
			local held = { bounds(late.host) }
			late.questie:Hide()
			late.questie.hooks.OnHide(late.questie)
			late.drain()
			local after = { bounds(late.host) }
			check(
				near(held[2], after[2]) and near(held[1], after[1]),
				label .. ": Questie hiding in combat holds the column"
			)
			late.setCombat(false)
			late.host:MarkDirty()
			late.drain()
			stacked(late, label .. " after combat")

			-- No room below a tall list: the column goes beside it.
			s = scenario(with({ questie = { point = "TOPRIGHT", x = -24, y = -100, height = 900 } }))
			check(clears(s.host, s.questie), label .. ": a tall list puts the column beside it")
			local hostLeft, hostTop2 = bounds(s.host)
			local questieLeft, questieTop = bounds(s.questie)
			check(hostLeft < questieLeft and near(hostTop2, questieTop), label .. ": beside, level with its top")

			-- A list at the bottom of the screen: the column goes above it.
			s = scenario(with({ questie = { point = "BOTTOMRIGHT", x = -24, y = 30, height = 200 } }))
			local _, _, _, _, hostBottom = bounds(s.host)
			local _, qTop = bounds(s.questie)
			check(clears(s.host, s.questie), label .. ": a low list puts the column above it")
			check(hostBottom > qTop and hostBottom < qTop + 20, label .. ": the column sits just above it")

			-- A detached column the player has not dragged starts beside Questie's list, not the hidden native one.
			s = scenario(with({ attached = false, questie = { point = "TOPLEFT", x = 24, y = -100, height = 300 } }))
			hostLeft, hostTop2 = bounds(s.host)
			questieLeft, questieTop = bounds(s.questie)
			check(clears(s.host, s.questie), label .. ": the detached column starts clear of Questie's list")
			check(hostLeft > questieLeft and near(hostTop2, questieTop), label .. ": beside it, level with its top")
			-- Once dragged, the player's place wins.
			s.settings.x, s.settings.y = 300, -500
			s.host:MarkDirty()
			s.drain()
			local _, draggedTop = bounds(s.host)
			check(near(draggedTop, (1080 - 500) * uiScale), label .. ": a dragged column stays where it was put")

			-- Questie builds its tracker after we load: a bounded wait finds it.
			s = scenario(with({ loadsLate = true, questie = { point = "TOPRIGHT", x = -24, y = -100, height = 300 } }))
			check(clears(s.host, s.questie), label .. ": a late Questie list still moves the column")
		end
	end
end

-- Without Questie there is nothing to wait for.
local none = scenario({})
check(none.pending() == 0, "no wait without Questie")
-- Questie loaded with its tracker turned off: the wait gives up after 30 seconds and the layout is unchanged.
local off = scenario({ questieOff = true })
local waits = 1 -- the first check already ran with the first layout
for _ = 1, 40 do
	if off.pending() > 0 then
		waits = waits + 1
	end
	off.drain()
end
check(waits == 30, "the wait for Questie's tracker gives up after 30 checks, not " .. waits)
stacked(off, "Questie with its tracker off")
print("tracker_questie_spec: " .. checks .. " checks passed")
