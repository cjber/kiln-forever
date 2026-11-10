-- The addon's own phrases. English is the key, so an empty table reads as English; a locale file translates a phrase
-- by assigning it. ForeverCore draws its own tracker, report and debug-log phrases, so only Kiln's strings belong here.

local ns = select(2, ...)

if ns.broken then
	return
end

---@type table<string, string>
local L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
ns.L = L
