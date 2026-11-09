local addonName, ns = ...

-- Shared structured log for the Forever addons. ns.Log remembers the last 200 lines, oldest dropped, so a bug report
-- can say what led to the error instead of only the error. Info, warn and error are always kept; debug is kept only
-- while the switch is on, and a dropped debug line costs no formatting at all. Nothing goes to chat: /forever debug
-- answers in the client's error frame, /forever debug show opens the report window with every attached addon's latest
-- lines selected for copying, and the report's own copy carries the last lines that fit after the error journal.
--
-- Lines stay in memory until a consumer hands the addon's saved table to ns.AttachLog(store), the same way the error
-- journal is attached, so earlier sessions survive a reload. The debug switch is one state every loaded Forever copy
-- shares for the character: the first copy publishes it and later copies join it, as ForeverLeaderboards does.

local L = ns.L
local MAX_LINES = 200
local MAX_LINE = 300
local MAX_SHOWN = 50
local LOG_VERSION = 1
local LEVELS = { debug = true, info = true, warn = true, error = true }
local NAME = addonName or "?"

-- Oldest first. This copy's memory until ns.AttachLog gives it the addon's saved table.
---@type string[]
local lines = {}

-- The saved table this copy writes to, once AttachLog has it.
---@type ForeverDebugLogStore?
local attached

---@class ForeverDebugLogStore
---@field lines string[] the saved ring, oldest first
---@field pinned boolean the debug switch stays on across sessions

---@class ForeverDebugLogAttachment
---@field name string the addon that attached the store
---@field store ForeverDebugLogStore

-- The state every loaded copy shares for the character. A pin is written to every attached addon's saved table, so it
-- survives whichever of them loads next, and `show` reads every attached ring, not only this copy's.
---@class ForeverDebugLogState
---@field VERSION integer
---@field enabled boolean
---@field pinned boolean
---@field stores ForeverDebugLogAttachment[]

local published = _G.ForeverDebugLog
if type(published) ~= "table" then
	published = { VERSION = LOG_VERSION, enabled = false, pinned = false, stores = {} }
	_G.ForeverDebugLog = published
elseif (tonumber(published.VERSION) or 0) < LOG_VERSION then
	published.VERSION = LOG_VERSION
end
if type(published.stores) ~= "table" then
	published.stores = {}
end
published.enabled = published.enabled == true
published.pinned = published.pinned == true
---@type ForeverDebugLogState
local shared = published --[[@as ForeverDebugLogState]]

---@param value any
---@return string
local function ToString(value)
	local ok, text = pcall(tostring, value)
	return ok and text or "?"
end

-- The client's own date and this session's seconds. The client's sandbox has no os table, so both are the client's
-- globals; a spec installs the same two.
---@return string
local function Stamp()
	return ("%s +%.1fs"):format(date("%Y-%m-%d %H:%M:%S"), GetTime())
end

-- Keep `list` bounded from the oldest end.
---@param list string[]
---@param limit integer
local function Trim(list, limit)
	while #list > limit do
		table.remove(list, 1)
	end
end

---@param list string[]
---@param count integer
---@return string[]
local function Newest(list, count)
	local first = #list - count + 1
	if first < 1 then
		first = 1
	end
	local result = {}
	for index = first, #list do
		result[#result + 1] = list[index]
	end
	return result
end

---@param line string
local function Append(line)
	lines[#lines + 1] = line
	Trim(lines, MAX_LINES)
end

-- One line: the client's clock, this session's seconds, the level, the caller's topic and the message. The level is
-- checked before anything is formatted, so a debug line that is off costs one comparison.
---@param level string debug, info, warn or error
---@param topic string the part of the addon the line came from
---@param message any the line, or a string.format template when arguments follow
---@param ... any
function ns.Log(level, topic, message, ...)
	if level == "debug" and shared.enabled ~= true then
		return
	end
	if not LEVELS[level] then
		level = "info"
	end
	local text
	if select("#", ...) > 0 then
		local ok, formatted = pcall(string.format, message, ...)
		text = ok and formatted or ToString(message)
	else
		text = ToString(message)
	end
	Append(ns.CutText(("%s %s %s: %s"):format(Stamp(), level, ToString(topic), text), MAX_LINE))
end

-- The newest `count` lines, oldest first, as copies.
---@param count? integer
---@return string[]
function ns.LogLines(count)
	local limit = tonumber(count) or MAX_SHOWN
	if limit < 0 then
		limit = 0
	end
	return Newest(lines, limit)
end

---@return boolean
function ns.DebugEnabled()
	return shared.enabled == true
end

-- Keep or drop the pin in every attached addon's saved table.
---@param value boolean
local function SavePin(value)
	shared.pinned = value
	for _, entry in ipairs(shared.stores) do
		entry.store.pinned = value
	end
end

-- A one-line answer goes in the client's error frame; the copyable answer (`show`) opens the report window.
---@param text string
---@param copyable? boolean
local function Notify(text, copyable)
	local report = ns.Report
	if copyable and type(report) == "table" and type(report.Show) == "function" then
		report.Show(text)
		return
	end
	local frame = rawget(_G, "UIErrorsFrame")
	if type(frame) == "table" and type(frame.AddMessage) == "function" then
		pcall(frame.AddMessage, frame, text, 1, 1, 0, 2)
	end
end

---@return string
local function State()
	if not shared.enabled then
		return L["Debug log is off."]
	end
	return shared.pinned and L["Debug log is on and pinned for this character."]
		or L["Debug log is on for this session."]
end

-- Every attached addon's newest lines, under its name. This is the copyable answer, so it may be longer than one line.
---@return string
local function ShowText()
	local parts = { State() }
	if not shared.stores[1] then
		parts[#parts + 1] = L["No addon has attached its log yet."]
		return table.concat(parts, "\n")
	end
	for _, entry in ipairs(shared.stores) do
		local kept = Newest(entry.store.lines, MAX_SHOWN)
		if kept[1] then
			parts[#parts + 1] = (L["%s (last %d):"]):format(entry.name, #kept)
			for _, line in ipairs(kept) do
				parts[#parts + 1] = line
			end
		else
			parts[#parts + 1] = (L["%s: no lines yet."]):format(entry.name)
		end
	end
	return table.concat(parts, "\n")
end

-- Repair a saved store so one hand-edited or older table cannot break logging.
---@param store table
local function Prepare(store)
	if type(store.lines) ~= "table" then
		store.lines = {}
	end
	for index = #store.lines, 1, -1 do
		if type(store.lines[index]) ~= "string" then
			table.remove(store.lines, index)
		end
	end
	Trim(store.lines, MAX_LINES)
	store.pinned = store.pinned == true
end

-- Use `store`, a table from the addon's saved variables, for the ring and the pin, and keep what was logged before it
-- arrived. The addon's defaults should make the table exist before this line runs.
---@param store table
function ns.AttachLog(store)
	if type(store) ~= "table" or store == attached then
		return
	end
	Prepare(store)
	for _, line in ipairs(lines) do
		store.lines[#store.lines + 1] = line
	end
	Trim(store.lines, MAX_LINES)
	lines = store.lines
	attached = store --[[@as ForeverDebugLogStore]]
	local known = false
	for _, entry in ipairs(shared.stores) do
		if entry.name == NAME then
			entry.store = attached
			known = true
			break
		end
	end
	if not known then
		shared.stores[#shared.stores + 1] = { name = NAME, store = attached }
	end
	-- A pin from an earlier session turns the switch on; a store that has never seen a pin never turns it off.
	if attached.pinned then
		shared.pinned = true
		shared.enabled = true
	end
end

-- `/forever debug` routes here: no argument toggles the session, "pin" keeps it, "off" turns it off and unpins, and
-- "show" puts every attached addon's latest lines on screen in the report window. Returns whether the argument was a
-- known subcommand.
---@param argument? string
---@return boolean handled
function ns.DebugCommand(argument)
	local command = type(argument) == "string" and argument:match("^%s*(.-)%s*$") or ""
	if command == "" then
		shared.enabled = not shared.enabled
		if shared.enabled then
			Notify(
				shared.pinned and L["Debug log is on and pinned for this character."]
					or L["Debug log is on for this session."]
			)
		else
			Notify(
				shared.pinned and L["Debug log is off for this session; it is still pinned."] or L["Debug log is off."]
			)
		end
		return true
	end
	if command == "pin" then
		local already = shared.enabled and shared.pinned
		shared.enabled = true
		SavePin(true)
		Notify(
			already and L["Debug log is already on and pinned for this character."]
				or L["Debug log is on and pinned for this character."]
		)
		return true
	end
	if command == "off" then
		shared.enabled = false
		SavePin(false)
		Notify(L["Debug log is off and unpinned."])
		return true
	end
	if command == "show" then
		Notify(ShowText(), true)
		return true
	end
	Notify(L["Usage: /forever debug, /forever debug pin, /forever debug off, /forever debug show"])
	return false
end
