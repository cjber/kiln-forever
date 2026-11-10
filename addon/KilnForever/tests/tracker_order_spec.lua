-- Run from the addon root: luajit tests/tracker_order_spec.lua
-- The shared objective-tracker column lays sections out from the top down, each in the room the ones before it left.
-- Kiln's section is the last numbered one, after every gameplay section, so a long session list cannot hide Shortest
-- Path's Journey, Adventure Guide, Legacy, Field Guide or ForeverCore's own quests.
local checks = 0
local function check(value, message)
	assert(value, message)
	checks = checks + 1
end

-- UI/Tracker.lua's Create builds the section and hands it to ForeverCore; only the calls it makes need to exist here.
local section = {}
function section:SetHeader() end
function section:MarkDirty() end
section.Header = {}
function section.Header:EnableMouse() end
function section.Header:SetScript() end

local env = setmetatable({}, { __index = _G })
env.CreateFrame = function() return section end
env.Mixin = function() end
env.ObjectiveTrackerFrame = {}
env.ObjectiveTrackerModuleMixin = {}
env.ForeverCore = { TrackerHost = { Attach = function() end } }

local ns = {
	db = { settings = { tracker = false } },
	core = { SafeCall = function(fn) return fn end },
	Store = { Active = function() return {} end, data = { threads = {} } },
}
function ns:On() end
setfenv(assert(loadfile("UI/Tracker.lua")), env)("KilnForever", ns)
ns.Tracker:Create()
check(ns.Tracker.module == section, "tracker section created")

-- The gameplay sections as their own addons order them.
local gameplay = {
	{ name = "ForeverCore quests", uiOrder = -10 },
	{ name = "Legacy Forever zone", uiOrder = -5 },
	{ name = "Adventure Guide Forever", uiOrder = -4 },
	{ name = "Shortest Path Forever", uiOrder = -3 },
	{ name = "Legacy Forever", uiOrder = 0 },
	{ name = "Field Guide Forever", uiOrder = 10 },
}

-- ForeverCore's own comparator orders the column in the game; run the real one from the checkout.
local core = dofile("../../tools/forever_core.lua")
local coreNs = core.load({ "UI/TrackerOrder.lua" }, {}, env)
local modules = {}
for _, gameplaySection in ipairs(gameplay) do
	modules[#modules + 1] = { name = gameplaySection.name, uiOrder = gameplaySection.uiOrder }
end
modules[#modules + 1] = section
coreNs.TrackerOrder.Sort(modules)
check(modules[#modules] == section, "Kiln's section sorts after every gameplay section")

print(("tracker_order_spec: %d checks passed"):format(checks))
