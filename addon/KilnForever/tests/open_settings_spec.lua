-- Run from the repository root: luajit tests/open_settings_spec.lua
-- The shared settings opener asks the client's own restricted C_SettingsUtil.OpenSettingsPanel to open, through
-- CreateSecureDelegate: called directly from addon code the client refuses it (cjber/adventure-guide-forever#411,
-- cjber/forever-core#333). It never opens in combat, and it reports false when the client cannot open anything.
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local settingsCalls = {}
local combat = false
local built = 0
local function RawOpenSettingsPanel(categoryID, element)
	settingsCalls[#settingsCalls + 1] = { categoryID, element }
end
local function CreateDelegate(fn)
	built = built + 1
	return function(...)
		return fn(...)
	end
end

_G.InCombatLockdown = function()
	return combat
end
_G.C_SettingsUtil = { OpenSettingsPanel = RawOpenSettingsPanel }
_G.CreateSecureDelegate = CreateDelegate

local function fresh()
	local ns = {}
	assert(loadfile("Core/OpenSettings.lua"))("ForeverCore", ns)
	return ns
end

local function reset()
	settingsCalls = {}
	combat = false
	built = 0
	_G.C_SettingsUtil = { OpenSettingsPanel = RawOpenSettingsPanel }
	_G.CreateSecureDelegate = CreateDelegate
end

-- The settings panel: the client's opener is wrapped once and run, with and without a category and scroll target.
reset()
local ns = fresh()
equal(ns.OpenSettingsPanel(313), true, "settings: opens")
equal(settingsCalls[1][1], 313, "settings: on the requested category")
equal(settingsCalls[1][2], nil, "settings: with no scroll target")
equal(built, 1, "settings: through one secure delegate")
equal(ns.OpenSettingsPanel(313, "ForeverCore"), true, "settings: opens at a row")
equal(settingsCalls[2][1], 313, "settings: the category is kept")
equal(settingsCalls[2][2], "ForeverCore", "settings: the scroll target is passed")
equal(ns.OpenSettingsPanel(), true, "settings: no category opens the panel")
equal(settingsCalls[3][1], nil, "settings: no category stays nil")
equal(built, 1, "settings: the delegate is reused")

-- In combat nothing opens, and no delegate is built for a call that cannot run.
reset()
combat = true
ns = fresh()
equal(ns.OpenSettingsPanel(313), false, "combat: no settings")
equal(#settingsCalls, 0, "combat: the settings opener is not called")
equal(built, 0, "combat: no delegate is built")

-- A build without CreateSecureDelegate leaves it closed and reports it, rather than erroring (#592).
reset()
_G.CreateSecureDelegate = nil
ns = fresh()
equal(ns.OpenSettingsPanel(313), false, "no delegate: no settings")
equal(#settingsCalls, 0, "no delegate: the settings opener is not called")

-- A client without the C function has nothing to delegate to.
reset()
_G.C_SettingsUtil = {}
ns = fresh()
equal(ns.OpenSettingsPanel(313), false, "no C_SettingsUtil opener: no settings")
equal(built, 0, "no C function: no delegate is built")

print(("open_settings_spec: %d checks passed"):format(checks))
