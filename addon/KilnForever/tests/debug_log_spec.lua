-- Contract for the shared structured log, its saved ring and the /forever debug switch.
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function check(value, label)
	checks = checks + 1
	assert(value, label)
end

-- SafeCall, loaded for its shared CutText, with the client stubs it needs to install its handler.
_G.strtrim = function(text)
	return text:match("^%s*(.-)%s*$")
end
_G.geterrorhandler = function()
	return function() end
end
_G.seterrorhandler = function() end
_G.CreateFrame = function()
	local frame = {}
	frame.RegisterEvent = function() end
	frame.SetScript = function() end
	return frame
end

-- A deterministic client clock, and the error frame every confirmation goes to.
local seconds = 0
_G.GetTime = function()
	return seconds
end
_G.date = function()
	return "2026-11-08 12:00:00"
end
local shown = {}
_G.UIErrorsFrame = {
	AddMessage = function(_, text)
		shown[#shown + 1] = text
	end,
}

---@param target table
---@param name? string
local function Load(target, name)
	target.L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	})
	name = name or "LogAddon"
	assert(loadfile("Core/SafeCall.lua"))(name, target)
	assert(loadfile("Core/Log.lua"))(name, target)
end

local ns = {}
Load(ns)
local copied = {}
ns.Report = {
	Show = function(text)
		copied[#copied + 1] = text
	end,
}

---@param list string[]
---@param needle string
---@return boolean
local function Has(list, needle)
	for _, line in ipairs(list) do
		if line:find(needle, 1, true) then
			return true
		end
	end
	return false
end

-- The ring ---------------------------------------------------------------------------------------------------------
seconds = 1.5
for index = 1, 250 do
	ns.Log("info", "ring", "line %d", index)
end
local kept = ns.LogLines(1000)
equal(#kept, 200, "the ring keeps 200 lines")
check(kept[1]:find("line 51", 1, true) ~= nil, "the oldest lines are dropped first")
check(kept[200]:find("line 250", 1, true) ~= nil, "the newest line is last")
check(
	kept[200]:find("2026-11-08 12:00:00 +1.5s info ring: line 250", 1, true) ~= nil,
	"a line carries the date, session seconds, level, topic and message"
)
equal(#ns.LogLines(7), 7, "LogLines returns only the requested newest lines")
check(ns.LogLines(2)[2]:find("line 250", 1, true) ~= nil, "LogLines returns them oldest first")

-- Levels and the debug switch -------------------------------------------------------------------------------------
ns.Log("debug", "off", "dropped while off")
check(not Has(ns.LogLines(1000), "dropped while off"), "a debug line is dropped while the switch is off")
check(not ns.DebugEnabled(), "the switch starts off")
equal(ns.DebugCommand(""), true, "a bare debug command is handled")
check(ns.DebugEnabled(), "the bare command turns the switch on")
equal(shown[#shown], "Debug log is on for this session.", "the confirmation is on screen, unpinned")
ns.Log("debug", "on", "kept while on")
check(Has(ns.LogLines(1000), "kept while on"), "a debug line is kept while the switch is on")
ns.Log("warn", "on", "warn always kept")
check(Has(ns.LogLines(1000), "warn always kept"), "warn is kept while debug is off or on")
ns.Log("error", "on", "error always kept")
check(Has(ns.LogLines(1000), "error always kept"), "error is kept")

-- Formatting costs nothing for a dropped line ----------------------------------------------------------------------
equal(ns.DebugCommand(""), true, "the bare command turns the switch off again")
local formatted = 0
local argument = setmetatable({}, {
	__tostring = function()
		formatted = formatted + 1
		return "value"
	end,
})
ns.Log("debug", "format", "%s", argument)
equal(formatted, 0, "a dropped debug line never formats its arguments")
ns.DebugCommand("")
ns.Log("debug", "format", "%s", argument)
equal(formatted, 1, "a kept line formats its arguments")
ns.Log("debug", "format", "%d", "not a number")
local fallback = ns.LogLines(1)[1]
check(fallback:find("format: %d", 1, true) ~= nil, "a failed format falls back to the template")
ns.DebugCommand("")
check(not ns.DebugEnabled(), "the switch is off again")

-- Attach and persistence across a reload ---------------------------------------------------------------------------
local saved = {}
ns.AttachLog(saved)
equal(type(saved.lines), "table", "attach creates the saved ring")
equal(saved.pinned, false, "a fresh saved table is unpinned")
ns.Log("info", "saved", "before reload")
ns.DebugCommand("pin")
equal(saved.pinned, true, "pin is written to the attached saved table")
check(ns.DebugEnabled(), "pin turns the switch on")
equal(shown[#shown], "Debug log is on and pinned for this character.", "pin confirms on screen")
ns.Log("debug", "saved", "debug before reload")
local savedCount = #saved.lines
check(savedCount >= 2, "the ring is the saved table")

-- A reload drops the globals but keeps SavedVariables, which is exactly what a /reload does.
_G.ForeverDebugLog = nil
local reloaded = {}
Load(reloaded)
check(not reloaded.DebugEnabled(), "a new session starts with the switch off")
reloaded.AttachLog(saved)
equal(#saved.lines, savedCount, "attach does not duplicate the saved lines")
check(reloaded.DebugEnabled(), "the saved pin turns the switch on after a reload")
local recovered = reloaded.LogLines(1000)
check(Has(recovered, "before reload"), "earlier sessions survive the reload")
check(Has(recovered, "debug before reload"), "debug lines from the pinned session survive")

-- Off unpins every attached saved table, and the next session stays off.
equal(reloaded.DebugCommand("off"), true, "off is handled")
check(not reloaded.DebugEnabled(), "off turns the switch off")
equal(saved.pinned, false, "off unpins the attached saved table")
equal(shown[#shown], "Debug log is off and unpinned.", "off confirms on screen")
_G.ForeverDebugLog = nil
local again = {}
Load(again)
again.AttachLog(saved)
check(not again.DebugEnabled(), "an unpinned saved table stays off after a reload")

-- Pin is idempotent and written to every attached addon's table.
local other = {}
again.AttachLog(other)
equal(again.DebugCommand("  pin  "), true, "pin trims its argument")
check(other.pinned, "pin writes the pin to a second attached table")
equal(shown[#shown], "Debug log is on and pinned for this character.", "the first pin confirms")
again.DebugCommand("pin")
equal(shown[#shown], "Debug log is already on and pinned for this character.", "a second pin says so")

-- Show and unknown arguments ---------------------------------------------------------------------------------------
local copies = {}
again.Report = {
	Show = function(text)
		copies[#copies + 1] = text
	end,
}
for index = 1, 60 do
	again.Log("info", "show", "show-%d", index)
end
copies = {}
equal(again.DebugCommand("show"), true, "show is handled")
check(copies[1]:find("Debug log is on and pinned for this character.", 1, true) ~= nil, "show opens with the status")
check(copies[1]:find("LogAddon (last 50):", 1, true) ~= nil, "show names the addon and carries the newest 50 lines")
check(copies[1]:find("show-10\n", 1, true) == nil, "the oldest line beyond 50 is left out")
check(copies[1]:find("show-11\n", 1, true) ~= nil, "the 50th oldest is shown")
check(copies[1]:find("show-60", 1, true) ~= nil, "the newest line is shown")
equal(again.DebugCommand("bogus"), false, "an unknown argument is not a subcommand")
equal(
	shown[#shown],
	"Usage: /forever debug, /forever debug pin, /forever debug off, /forever debug show",
	"an unknown argument shows the usage on screen"
)
-- show lists every attached addon's lines under its name, not only the copy that owns /forever.
_G.ForeverDebugLog = nil
local first = {}
Load(first, "FirstAddon")
local second = {}
Load(second, "SecondAddon")
first.AttachLog({})
second.AttachLog({})
first.Log("info", "first", "first line")
second.Log("info", "second", "second line one")
second.Log("info", "second", "second line two")
local both = {}
first.Report = {
	Show = function(text)
		both[#both + 1] = text
	end,
}
equal(first.DebugCommand("show"), true, "show is handled with two copies loaded")
check(both[1]:find("FirstAddon (last 1):", 1, true) ~= nil, "the first addon's name heads its lines")
check(both[1]:find("SecondAddon (last 2):", 1, true) ~= nil, "the second addon's name heads its lines")
check(both[1]:find("first line", 1, true) ~= nil, "the first addon's line is shown")
check(both[1]:find("second line one", 1, true) ~= nil, "the second addon's first line is shown")
check(both[1]:find("second line two", 1, true) ~= nil, "the second addon's second line is shown")
check(
	both[1]:find("FirstAddon", 1, true) < both[1]:find("SecondAddon", 1, true),
	"attached addons are listed in registration order"
)

-- A copy without the report window still answers in the client's error frame.
_G.ForeverDebugLog = nil
local bare = {}
Load(bare)
equal(bare.DebugCommand("show"), true, "show works without a report window")
check(Has(shown, "Debug log is off."), "the fallback answer reaches the error frame")

print(("debug_log_spec: %d checks passed"):format(checks))
