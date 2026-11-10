-- Run from the addon root: luajit tests/settings_open_spec.lua
-- UI/Settings hands its category to the shared secure opener and returns what it says. Calling the client's
-- restricted Settings.OpenToCategory instead makes the client refuse the request and blame the addon
-- (cjber/forever-core#333).
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local settingsCalls = {}
local restrictedCalls = 0
local combat = false

_G.InCombatLockdown = function()
	return combat
end
_G.CreateSecureDelegate = function(fn)
	return function(...)
		return fn(...)
	end
end
_G.C_SettingsUtil = {
	OpenSettingsPanel = function(categoryID, element)
		settingsCalls[#settingsCalls + 1] = { categoryID, element }
	end,
}
_G.Settings = {
	OpenToCategory = function()
		restrictedCalls = restrictedCalls + 1
	end,
}

local ns = { On = function() end }
assert(loadfile("Core/OpenSettings.lua"))("KilnForever", ns)
assert(loadfile("UI/Settings.lua"))("KilnForever", ns)

ns.Settings.panel = {}
ns.Settings.category = { GetID = function() return 313 end }

equal(ns.Settings:Open(), true, "settings: opens")
equal(settingsCalls[1][1], 313, "settings: at the page's own category")
equal(settingsCalls[1][2], nil, "settings: with no scroll target")
equal(restrictedCalls, 0, "settings: never through the restricted Settings.OpenToCategory")

-- The opener's answer is the page's answer, so /kiln settings can still say when nothing opened.
local open = ns.OpenSettingsPanel
ns.OpenSettingsPanel = function() return false end
equal(ns.Settings:Open(), false, "settings: a failed open reports false")
ns.OpenSettingsPanel = open

-- In combat the shared opener leaves Options closed and the page reports that.
combat = true
equal(ns.Settings:Open(), false, "combat: no settings")
combat = false
equal(#settingsCalls, 1, "combat: the client opener is not called")

-- A page without a category has nothing to open.
ns.Settings.category = nil
local called = false
ns.OpenSettingsPanel = function()
	called = true
	return true
end
equal(ns.Settings:Open(), false, "no category: no settings")
equal(called, false, "no category: the opener is not called")

print(("settings_open_spec: %d checks passed"):format(checks))
