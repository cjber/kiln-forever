-- Core/MinimapButton.lua against a stub of the Minimap and the cursor: two vendored copies share one ring, each button
-- lands on its own angle, a drag saves the angle it stopped on, and the hide flag takes it off the rim.
local function newNs()
	return {
		L = setmetatable({}, {
			__index = function(_, key)
				return key
			end,
		}),
		SafeCall = function(label, fn, ...)
			local ok, err = pcall(fn, ...)
			assert(ok, label .. ": " .. tostring(err))
			return ok
		end,
	}
end

local function frame(name, parent)
	local f = { name = name, shown = true, points = {}, scripts = {}, textures = {} }
	function f:SetSize(width, height)
		self.width, self.height = width, height
	end
	function f:GetWidth()
		return self.width
	end
	function f:GetHeight()
		return self.height
	end
	function f:SetPoint(...)
		self.points = { ... }
	end
	function f:GetPoint()
		return unpack(self.points)
	end
	function f:ClearAllPoints()
		self.points = {}
	end
	function f:SetShown(shown)
		self.shown = shown == true
	end
	function f:IsShown()
		return self.shown
	end
	function f:Show()
		self.shown = true
	end
	function f:Hide()
		self.shown = false
	end
	function f:SetScript(scriptName, value)
		self.scripts[scriptName] = value
	end
	function f:RegisterForClicks(...)
		self.clicks = { ... }
	end
	function f:RegisterForDrag(...)
		self.drags = { ... }
	end
	function f:SetFrameStrata(value)
		self.strata = value
	end
	function f:SetFrameLevel(value)
		self.level = value
	end
	function f:SetFixedFrameStrata(value)
		self.fixedStrata = value
	end
	function f:SetFixedFrameLevel(value)
		self.fixedLevel = value
	end
	function f:SetHighlightTexture(value, blend)
		self.highlight, self.highlightBlend = value, blend
	end
	function f.CreateTexture(_, _, layer)
		local texture = { layer = layer }
		function texture:SetSize(width, height)
			self.width, self.height = width, height
		end
		function texture:SetPoint(...)
			self.points = { ... }
		end
		function texture:SetTexture(value)
			self.texture = value
		end
		function texture:SetTexCoord(...)
			self.texCoord = { ... }
		end
		f.textures[#f.textures + 1] = texture
		return texture
	end
	if parent then
		f.parent = parent
	end
	return f
end

local minimap = frame("Minimap")
minimap.width, minimap.height = 198, 198
minimap.centerX, minimap.centerY = 200, 150
function minimap:GetCenter()
	return self.centerX, self.centerY
end
function minimap.GetEffectiveScale()
	return 1
end
_G.Minimap = minimap

local cursorX, cursorY = 200, 254
function _G.GetCursorPosition()
	return cursorX, cursorY
end

_G.CreateFrame = function(_, name, parent)
	local button = frame(name, parent)
	button.parent = parent
	return button
end
_G.GameTooltip = {
	lines = {},
	SetOwner = function(self, owner)
		self.owner = owner
		self.lines = {}
	end,
	SetText = function(self, text)
		self.title = text
	end,
	AddLine = function(self, text)
		self.lines[#self.lines + 1] = text
	end,
	Show = function() end,
	Hide = function() end,
}
_G.NORMAL_FONT_COLOR = {
	GetRGB = function()
		return 1, 1, 1
	end,
}
_G.GRAY_FONT_COLOR = {
	GetRGB = function()
		return 0.5, 0.5, 0.5
	end,
}
local messages = {}
_G.DEFAULT_CHAT_FRAME = {
	AddMessage = function(_, message)
		messages[#messages + 1] = message
	end,
}

-- Two addons, each with its own vendored copy of the module, like Field Guide and Adventure Guide.
local function load()
	local ns = newNs()
	assert(loadfile("Core/MinimapButton.lua"))("Addon", ns)
	return ns.MinimapButton
end
local first, second = load(), load()
assert(first ~= second)

local clicked = {}
local function spec(name, settings)
	return {
		name = name,
		icon = "icon-" .. name,
		title = "title-" .. name,
		binding = "Shift-F",
		subtext = "subtext-" .. name,
		settings = settings,
		host = {},
		onClick = function(button, mouseButton)
			clicked[#clicked + 1] = { button = button, mouseButton = mouseButton }
		end,
	}
end

local settingsA = {}
local aSpec = spec("FirstMinimapButton", settingsA)
local a = first.Create(aSpec)
assert(a, "no button")
assert(a.parent == minimap, "not parented to the Minimap")

local function textureOn(button, layer)
	for _, texture in ipairs(button.textures) do
		if texture.layer == layer then
			return texture
		end
	end
end

-- LibDBIcon's construction: a 31-unit button with the tracking border over a 24-unit background and 18-unit icon.
assert(a.width == 31 and a.height == 31, "size")
assert(a.strata == "MEDIUM", a.strata)
assert(a.fixedStrata == true and a.level == 8 and a.fixedLevel == true, "pinned above the Minimap")
assert(a.level == 8, a.level)
assert(a.highlight == 136477, a.highlight)
local overlay = textureOn(a, "OVERLAY")
assert(overlay and overlay.width == 50 and overlay.height == 50, "overlay size")
assert(overlay.texture == 136430, overlay.texture)
assert(overlay.points[1] == "TOPLEFT", overlay.points[1])
local background = textureOn(a, "BACKGROUND")
assert(background and background.width == 24 and background.height == 24, "background size")
assert(background.texture == 136467, background.texture)
assert(background.points[1] == "CENTER", background.points[1])
assert(a.icon == textureOn(a, "ARTWORK"), "icon is not the artwork texture")
assert(a.icon.texture == "icon-FirstMinimapButton", a.icon.texture)
assert(a.icon.width == 18 and a.icon.height == 18, "icon size")
assert(a.icon.points[1] == "CENTER", a.icon.points[1])
assert(not a.icon.mask, "icon still masked")
local texCoord = a.icon.texCoord
assert(
	texCoord and texCoord[1] == 0.05 and texCoord[2] == 0.95 and texCoord[3] == 0.05 and texCoord[4] == 0.95,
	"icon texcoord"
)
assert(aSpec.host.minimapButton == a, "host not published")
assert(a.clicks and a.clicks[1] == "LeftButtonUp", "clicks")
assert(a.drags and a.drags[1] == "LeftButton", "drag button")
assert(settingsA.minimapButtonAngle == 225, settingsA.minimapButtonAngle)
assert(a.shown, "hidden on create")

-- Holding the mouse nudges the icon down-right, as LibDBIcon does, and letting go puts it back.
a.scripts.OnMouseDown(a)
assert(a.icon.points[1] == "CENTER" and a.icon.points[2] == a and a.icon.points[3] == "CENTER", "nudge anchor")
assert(a.icon.points[4] == 1 and a.icon.points[5] == -1, "nudge offset")
a.scripts.OnMouseUp(a)
assert(a.icon.points[1] == "CENTER" and #a.icon.points == 1, "nudge stayed")

-- A second addon gets the next free angle rather than landing on the first one.
local settingsB2 = {}
local b = second.Create(spec("SecondMinimapButton", settingsB2))
assert(b, "no second button")
assert(settingsB2.minimapButtonAngle == 195, settingsB2.minimapButtonAngle)
assert(math.abs(a.angle - b.angle) >= 25, "two buttons on one angle")
assert(#_G.ForeverMinimapButtons.buttons == 2, "registry")

-- The angle is an offset from the Minimap's centre, not a screen position.
local point, relativeTo, relativePoint, x, y = a:GetPoint()
assert(point == "CENTER" and relativeTo == minimap and relativePoint == "CENTER", "anchor")
assert(math.abs(x - math.cos(math.rad(225)) * 104) < 0.01, "x")
assert(math.abs(y - math.sin(math.rad(225)) * 104) < 0.01, "y")

-- A click runs the addon's action with the mouse button.
a.scripts.OnClick(a, "LeftButton")
assert(#clicked == 1 and clicked[1].button == a and clicked[1].mouseButton == "LeftButton", "click")

-- Hovering shows the addon's lines; the shared module never draws its own.
a.scripts.OnEnter(a)
assert(GameTooltip.owner == a and GameTooltip.title == "title-FirstMinimapButton", "tooltip title")
assert(GameTooltip.lines[1] == "(Shift-F)", GameTooltip.lines[1])
assert(GameTooltip.lines[2] == "subtext-FirstMinimapButton", GameTooltip.lines[2])
a.scripts.OnLeave(a)

-- A drag around the rim moves the button and saves the angle it stopped on. Straight above the Minimap is 90°.
cursorX, cursorY = 200, 254
a.scripts.OnDragStart(a)
assert(a.dragging and a.scripts.OnUpdate, "drag did not start")
a.scripts.OnUpdate(a, 0.01)
assert(math.abs(a.angle - 90) < 0.01, a.angle)
local points = { a:GetPoint() }
assert(math.abs(points[4]) < 0.01 and math.abs(points[5] - 104) < 0.01, "moved while dragging")
a.scripts.OnDragStop(a)
assert(not a.dragging and not a.scripts.OnUpdate, "drag did not stop")
assert(math.abs(settingsA.minimapButtonAngle - 90) < 0.01, settingsA.minimapButtonAngle)
assert(settingsB2.minimapButtonAngle == 195, "the other button moved")

-- The hide flag is read on create and on refresh; hiding keeps its angle for when it comes back.
settingsA.minimapButtonHidden = true
first.Refresh()
assert(not a:IsShown(), "hide flag ignored")
settingsB2.minimapButtonHidden = true
second.Refresh()
assert(not b:IsShown(), "second hide flag ignored")
settingsA.minimapButtonHidden = false
settingsB2.minimapButtonHidden = false
first.Refresh()
second.Refresh()
assert(a:IsShown() and b:IsShown(), "buttons stayed hidden")
assert(math.abs(a.angle - 90) < 0.01, "angle lost while hidden")

-- Destroy takes the button out of the shared ring and clears the host's reference.
first.Destroy(a)
assert(#_G.ForeverMinimapButtons.buttons == 1, "destroyed button stayed in the registry")
assert(aSpec.host.minimapButton == nil, "host still points at the destroyed button")

-- Without the client's Minimap the module says so and skips the button instead of erroring.
local saved = _G.Minimap
_G.Minimap = nil
assert(second.Create(spec("MissingMinimapButton", {})) == nil, "made a button with no Minimap")
assert(messages[#messages] == "MINIMAP_UNAVAILABLE", messages[#messages])
_G.Minimap = saved
