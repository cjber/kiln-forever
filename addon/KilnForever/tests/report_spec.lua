-- Contract for the shared report window, issue composer and slash-command dispatch.
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local widgets = {}
local function widget(widgetKind, widgetName)
	local value = { kind = widgetKind, name = widgetName, scripts = {}, text = "" }
	local methods = {}
	function methods:SetScript(name, callback)
		self.scripts[name] = callback
	end
	function methods:SetText(text)
		self.text = text
		self.highlighted = nil
	end
	function methods:GetText()
		return self.text
	end
	function methods:HighlightText(start)
		if start ~= nil and type(start) ~= "number" then
			error("HighlightText start must be a number")
		end
		self.highlighted = self.text
	end
	function methods:SetFocus()
		self.focused = true
	end
	function methods:Show()
		self.shown = true
	end
	function methods:Hide()
		self.shown = false
	end
	function methods:SetTitle(text)
		self.title = text
	end
	function methods:GetPortrait()
		self.hasPortrait = true
		return widget("Texture")
	end
	function methods:CreateFontString()
		self.createdFontString = true
		return widget("FontString")
	end
	function methods:SetScrollChild(child)
		self.child = child
	end
	setmetatable(value, {
		__index = function(_, key)
			return methods[key] or function() end
		end,
	})
	widgets[#widgets + 1] = value
	return value
end

_G.UIParent = {}
_G.UISpecialFrames = {}
_G.CreateFrame = function(kind, name)
	return widget(kind, name)
end
_G.GameFontNormal, _G.ChatFontNormal = {}, {}
_G.C_AddOns = {
	GetAddOnMetadata = function(_, key)
		return key == "X-Website" and "https://github.com/cjber/example-addon" or "1.0.0"
	end,
	GetNumAddOns = function()
		return 0
	end,
	GetAddOnInfo = function() end,
	IsAddOnLoaded = function()
		return false
	end,
}
_G.GetBuildInfo = function()
	return "1.0", "build", "", 16001
end
_G.GetLocale = function()
	return "enUS"
end
_G.UnitClass = function()
	return nil, "Mage"
end
_G.UnitRace = function()
	return nil, "Human"
end
_G.UnitLevel = function()
	return 60
end
_G.UnitFactionGroup = function()
	return "Alliance"
end
_G.C_Map = {
	GetBestMapForUnit = function()
		return nil
	end,
}

local phrases = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
local reportLinesCalls = 0
local ns = {
	L = phrases,
	Art = { Icon = function() end },
	ReportLines = function()
		reportLinesCalls = reportLinesCalls + 1
		return { "addon details" }
	end,
}
_G.strtrim = function(text)
	return text:match("^%s*(.-)%s*$")
end
_G.geterrorhandler = function()
	return function() end
end
_G.seterrorhandler = function() end
_G.GetTime = function()
	return 1
end
_G.date = function()
	return "d"
end
assert(loadfile("Core/SafeCall.lua"))("ForeverCore", ns)
assert(loadfile("Core/Log.lua"))("ForeverCore", ns)
local chunk = assert(loadfile("UI/Report.lua"))
chunk("ExampleAddon", ns)
ns.ReportTitle = "ExampleAddon report"
local reportText = ns.Report.Text
ns.Report.Text = function(lines)
	return table.concat(lines, "\n")
end

local longError = ("long error "):rep(30)
-- BugGrabber v12.1.1: the report reads its database directly, and its own error links resolve by table id.
_G.BugGrabber = {
	GetDB = function()
		return { { message = "independent error", counter = 1, session = 1 } }
	end,
	GetSessionId = function()
		return 1
	end,
	GetErrorByID = function()
		return nil
	end,
}
ns.RecordError("test", longError, "stack")
local uniqueText = reportText({})
equal(uniqueText:find("Recent Lua errors (BugGrabber):", 1, true) ~= nil, true, "unique BugGrabber errors are shown")
_G.BugGrabber.GetDB = function()
	return { { message = longError, counter = 1, session = 1 } }
end
local duplicateText = reportText({})
equal(duplicateText:find("Recent Lua errors (BugGrabber):", 1, true), nil, "duplicate BugGrabber errors are omitted")
local caughtErrors = ns.CaughtErrors
ns.CaughtErrors = function()
	return { { label = "test", message = ns.CutText(longError, 300), count = 1, stack = "stack" } }
end
local legacyText = reportText({})
equal(
	legacyText:find("Recent Lua errors (BugGrabber):", 1, true) ~= nil,
	true,
	"ambiguous clipped legacy errors remain visible"
)
ns.CaughtErrors = function()
	return { { label = "test", message = "A", count = 1, stack = "stack" } }
end
_G.BugGrabber.GetDB = function()
	return { { message = "A", counter = 1, session = 1 } }
end
local exactLegacyText = reportText({})
equal(exactLegacyText:find("Recent Lua errors (BugGrabber):", 1, true), nil, "exact short legacy errors deduplicate")
_G.BugGrabber.GetDB = function()
	return { { message = "A suffix", counter = 1, session = 1 } }
end
local shortLegacyText = reportText({})
equal(
	shortLegacyText:find("Recent Lua errors (BugGrabber):", 1, true) ~= nil,
	true,
	"distinct short legacy errors remain visible"
)
ns.CaughtErrors = caughtErrors
local sharedPrefix = ("same prefix "):rep(30)
ns.RecordError("first", sharedPrefix .. "A", "stack")
ns.RecordError("second", sharedPrefix .. "B", "stack")
_G.BugGrabber.GetDB = function()
	return {
		{ message = sharedPrefix .. "A", counter = 1, session = 1 },
		{ message = sharedPrefix .. "C", counter = 1, session = 1 },
	}
end
local distinctText = reportText({})
equal(
	select(2, distinctText:gsub("Recent Lua errors %(BugGrabber%):", "")),
	1,
	"distinct long errors keep one external section"
)

ns.AttachErrorJournal({
	{
		signature = "earlier\n",
		kind = "error",
		message = "error from an earlier session",
		stack = "",
		count = 2,
		firstSeen = 1,
		lastSeen = 2,
	},
})
local earlierText = reportText({})
equal(earlierText:find("Earlier sessions (1):", 1, true) ~= nil, true, "earlier sessions have their own heading")
equal(
	earlierText:find("error from an earlier session", 1, true) ~= nil,
	true,
	"earlier sessions are included in the report"
)

-- The copy carries the newest log lines after the error journal.
local logStore = {}
ns.AttachLog(logStore)
ns.Log("info", "test", "first log line")
ns.Log("debug", "test", "dropped debug line")
ns.Log("warn", "test", "second log line")
local loggedText = reportText({})
equal(loggedText:find("Log %(last 2%):", 1) ~= nil, true, "the log has its own heading")
equal(loggedText:find("dropped debug line", 1, true), nil, "a dropped debug line is not in the copy")
local errorAt = loggedText:find("error from an earlier session", 1, true)
local logAt = loggedText:find("first log line", 1, true)
equal(errorAt ~= nil and logAt ~= nil and errorAt < logAt, true, "the log follows the error journal")

ns.CaughtErrors = function()
	return {}
end
_G.BugGrabber = nil
for index = 1, 60 do
	ns.Log("info", "test", "log-%d", index)
end
local fullText = reportText({})
equal(fullText:find("Log %(last 50%):", 1) ~= nil, true, "the copy shows the newest 50 log lines")
equal(fullText:find("log-10\n", 1, true), nil, "the 51st newest line is left out")
equal(fullText:find("log-11\n", 1, true) ~= nil, true, "the 50th newest line is included")
equal(fullText:find("log-60\n", 1, true) ~= nil, true, "the newest line is included")

-- A log too long for the report keeps the newest lines, not the oldest: the section is built newest-first.
for index = 1, 30 do
	ns.Log("info", "test", ("long-%02d "):format(index) .. string.rep("x", 110))
end
local longText = reportText({})
equal(longText:find("long-30 ", 1, true) ~= nil, true, "the newest line survives the report cap")
equal(longText:find("long-01 ", 1, true), nil, "the oldest line is dropped for room")

equal(ns.Report.Command("unknown"), false, "unknown command remains for addon handler")
equal(ns.Report.Command("report"), true, "report command handled")
equal(reportLinesCalls, 1, "report command gets addon lines")

local reportBox
for _, value in ipairs(widgets) do
	if value.kind == "EditBox" and value.scripts.OnEditFocusGained then
		reportBox = value
		break
	end
end
equal(reportBox ~= nil, true, "report edit box created")
reportBox.scripts.OnEditFocusGained(reportBox, true)
equal(reportBox.highlighted, "addon details", "focus selects report text")

equal(ns.Report.Command("issue", "feature"), true, "issue command handled")
local issueWindow
for _, value in ipairs(widgets) do
	if value.name == "ExampleAddonIssue" then
		issueWindow = value
	end
end
equal(issueWindow.kind, "feature", "issue argument selects feature request")
local issueBox
for _, value in ipairs(widgets) do
	if value.kind == "EditBox" and value.scripts.OnEditFocusGained and value ~= reportBox then
		issueBox = value
	end
end
equal(issueBox ~= nil, true, "issue output box created")
issueBox.scripts.OnEditFocusGained(issueBox, true)
equal(issueBox.highlighted, issueBox.text, "focus selects issue link")

print(("report_spec: %d checks passed"):format(checks))
