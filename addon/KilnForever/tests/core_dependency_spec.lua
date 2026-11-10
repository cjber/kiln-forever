-- Run from the addon root: luajit tests/core_dependency_spec.lua
-- Kiln Forever requires ForeverCore. The game already refuses to load the addon when ForeverCore is absent; this stops
-- the addon's own files with one on-screen line when an installed ForeverCore is too old for what they call.
local function Require(foreverCore)
	local lines = {}
	local env = {
		UIErrorsFrame = {
			AddMessage = function(_, text, red, green, blue)
				lines[#lines + 1] = { text = text, red = red, green = green, blue = blue }
			end,
		},
		ForeverCore = foreverCore,
	}
	env._G = env
	setmetatable(env, { __index = _G })
	local addon = {}
	setfenv(assert(loadfile("Core/Require.lua")), env)("KilnForever", addon)
	return addon, lines
end

local missing, missingLines = Require(nil)
assert(missing.broken == true, "a missing ForeverCore stops the addon")
assert(#missingLines == 1 and missingLines[1].text:find("ForeverCore", 1, true), "and names it in one error line")

local old, oldLines = Require({ API = 0 })
assert(old.broken == true and #oldLines == 1, "a ForeverCore older than API 1 stops the addon too")

local ready, readyLines = Require({ API = 1 })
assert(ready.broken == nil, "API 1 runs the addon")
assert(#readyLines == 0, "and says nothing")

print("core_dependency_spec: ok")
