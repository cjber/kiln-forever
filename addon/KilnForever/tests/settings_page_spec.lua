-- Contract for the shared settings-page chrome: the category it registers, the four row kinds, where each row lands
-- on the canvas, and that every phrase goes through the addon's ns.L rather than a string written in the module. The
-- client is stubbed the way the other specs stub it: frames remember what the module sets and the spec reads it back.
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end
local function check(value, message)
	checks = checks + 1
	assert(value, message)
end

-- The client's frame: a table of what was set on it, its children, its scripts and its anchors.
local function widget(kind, parent, template)
	local frame = { kind = kind, parent = parent, template = template, scripts = {}, children = {}, points = {} }
	local methods = {}
	function methods:SetPoint(point, first, second)
		self.points[#self.points + 1] = { point = point, first = first, second = second }
		-- Only a canvas position is a y: a point anchored to another frame is placed relative to that frame, so the
		-- page's cursor is not what put it there.
		if type(first) == "number" and type(second) == "number" then
			self.y = second
		end
	end
	function methods:SetScript(name, callback)
		self.scripts[name] = callback
	end
	function methods:SetChecked(checked)
		self.checked = checked
	end
	function methods:GetChecked()
		return self.checked
	end
	function methods:SetText(text)
		self.text = text
	end
	function methods:GetText()
		return self.text
	end
	function methods:SetWidth(width)
		self.width = width
	end
	function methods:SetSize(width, height)
		self.width, self.height = width, height
	end
	function methods:SetMinMaxValues(minimum, maximum)
		self.minimum, self.maximum = minimum, maximum
	end
	function methods:SetValueStep(step)
		self.step = step
	end
	function methods:SetObeyStepOnDrag(obey)
		self.obeyStepOnDrag = obey
	end
	function methods:SetValue(value)
		self.value = value
		if self.scripts.OnValueChanged then
			self.scripts.OnValueChanged(self, value)
		end
	end
	function methods:GetValue()
		return self.value
	end
	function methods:CreateFontString(_, _, font)
		local text = widget("FontString", self)
		text.font = font
		return text
	end
	-- A client frame answers a method it has and nothing else: reading a field it never had gives nil, as the client
	-- does, so a value the page keeps on the panel is the page's own and not a stub's.
	setmetatable(frame, {
		__index = methods,
	})
	if parent then
		parent.children[#parent.children + 1] = frame
	end
	return frame
end

-- The client's Settings API: every call is recorded so the spec can read the page back.
local calls = { categories = {}, initializers = {} }
_G.CreateFrame = function(kind, _, parent, template)
	return widget(kind, parent, template)
end
_G.Settings = {
	RegisterCanvasLayoutCategory = function(panel, name)
		local category = { panel = panel, name = name }
		calls.canvas = category
		return category
	end,
	RegisterAddOnCategory = function(category)
		calls.categories[#calls.categories + 1] = category
	end,
}
-- An addon's L: the phrases it translated, and English for the rest, exactly as Locales/enUS.lua answers.
local function Locale(phrases)
	return setmetatable(phrases, {
		__index = function(_, phrase)
			return phrase
		end,
	})
end

local function Load(phrases)
	calls = { categories = {}, initializers = {} }
	local ns = { L = phrases and Locale(phrases) or nil }
	assert(loadfile("UI/SettingsPage.lua"))("ExampleAddon", ns)
	return ns.SettingsPage, ns
end

-- Children of a kind, in the order the page made them.
local function Children(frame, kind)
	local found = {}
	for _, child in ipairs(frame.children) do
		if child.kind == kind then
			found[#found + 1] = child
		end
	end
	return found
end

-- A page with one of everything, the way an addon's own Core/Settings.lua builds it.
local saved = { enabled = true, scale = 1.5 }
local Page = Load({ ["Example options"] = "Options d'exemple", ["Tick"] = "Cocher", ["Wide"] = "Large" })
local seen = {}
local category, panel = Page.Register("Example options", function(target, page)
	seen.target, seen.page = target, page
	page.AddCheck(target, "Tick", function()
		return saved.enabled
	end, function(checked)
		saved.enabled = checked
	end, "Wide")
	page.AddSlider(target, "Tick", function()
		return saved.scale
	end, function(value)
		saved.scale = value
	end, 0.5, 2, 0.5)
	page.AddButton(target, "Tick", function()
		saved.pressed = true
	end)
end)

-- Register: one canvas category, registered by name, and the panel the rows are drawn on.
check(seen.page == Page, "the builder gets the module to draw with")
check(seen.target == panel, "and the panel it draws on")
equal(category.name, "Options d'exemple", "the category is named through ns.L")
equal(panel.name, "Options d'exemple", "and so is the frame, as the client's search reads it")
check(calls.categories[1] == category and #calls.categories == 1, "the category is registered once, by the page")
check(calls.canvas.panel == panel, "the canvas is the panel")
equal(panel.title.text, "Options d'exemple", "the page has its title, translated")
equal(panel.title.font, "GameFontHighlightHuge", "in the font Blizzard's own settings pages title theirs with")

-- AddCheck: checked from the getter, writes the setter, carries its tooltip.
local check_ = Children(panel, "CheckButton")[1]
check(check_ ~= nil, "the page has its tick box")
check(check_.template == "InterfaceOptionsCheckButtonTemplate", "on the client's own template")
check(check_.checked == true, "it shows the saved setting")
equal(check_.children[1].text, "Cocher", "its label is translated")
equal(check_.tooltipText, "Large", "and so is its tooltip")
check_.checked = false
check_.scripts.OnClick(check_)
equal(saved.enabled, false, "unticking writes the setting")
check_.checked = true
check_.scripts.OnClick(check_)
equal(saved.enabled, true, "ticking writes it back")

-- AddSlider: the saved value, the range, and a write per move.
local sliders = Children(panel, "Slider")
equal(#sliders, 1, "the page has its slider")
local slider = sliders[1]
equal(slider.template, "OptionsSliderTemplate", "on the client's slider template")
equal(slider.value, 1.5, "it starts at the saved value")
equal(slider.minimum, 0.5, "and knows its range")
equal(slider.maximum, 2, "both ends")
equal(slider.step, 0.5, "and its step")
slider:SetValue(2)
equal(saved.scale, 2, "moving it writes the setting")

-- AddButton: the label, and the callback behind it.
local button = Children(panel, "Button")[1]
check(button ~= nil and button.template == "SharedButtonSmallTemplate", "the page has its button")
equal(button.text, "Cocher", "its label is translated")
equal(button.width, 180, "and it is the page's button width")
button.scripts.OnClick(button)
equal(saved.pressed, true, "clicking runs the addon's callback")

-- The rows stack down the canvas in the order they were added, each below the one before it, and none of them
-- overlapping the title.
local rows = {}
for _, child in ipairs(panel.children) do
	if child.y then
		rows[#rows + 1] = child
	end
end
check(#rows == 4, "the title and the three rows are placed on the canvas")
check(rows[1] == panel.title and panel.title.y == -16, "the title sits at the top")
for index = 2, #rows do
	check(rows[index].y < rows[index - 1].y, "row " .. index .. " sits below row " .. (index - 1))
end

-- A second page is its own: a new panel, its own category, and no rows left over from the one before.
local only = Load(nil)
local second, secondPanel = only.Register("Plain", function(target, page)
	page.AddButton(target, "Untranslated", function() end)
end)
check(secondPanel ~= panel, "a new page is a new panel")
equal(second.name, "Plain", "with its own name")
equal(Children(secondPanel, "Button")[1].text, "Untranslated", "no ns.L at all: the phrase reads as English")
equal(#Children(secondPanel, "CheckButton"), 0, "and it has none of the first page's rows")
check(calls.categories[1] == second, "registered in its own right")

-- A client without the Settings API: the addon keeps its options off the interface instead of erroring on load.
local bare = Load(nil)
local noSettings = _G.Settings
_G.Settings = nil
local none, nonePanel = bare.Register("Plain", function()
	error("the builder must not run without a page to build on")
end)
check(none == nil and nonePanel == nil, "no Settings API, no page")
_G.Settings = noSettings

print(("settings_page_spec: %d checks passed"):format(checks))
