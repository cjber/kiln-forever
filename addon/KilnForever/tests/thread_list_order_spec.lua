-- The session list against a reordering snapshot: rows hold their place under the pointer, and the
-- new order appears once the pointer leaves the list.
local checks = 0
local function check(value, message)
	assert(value, message)
	checks = checks + 1
end

local ns = {
	UI = {},
	db = {
		settings = {
			project = "all",
			collapsed = { working = false, input = false, open = false, done = false },
		},
	},
	Main = { mode = "thread" },
}
function ns:Fire() end

local hovered, rows = false, {}
local function frame()
	local f = { scripts = {} }
	function f:SetPoint() end
	function f:SetHeight() end
	function f:SetAutoFocus() end
	function f:SetScript(name, fn)
		self.scripts[name] = fn
	end
	function f:HookScript(name, fn)
		local old = self.scripts[name]
		self.scripts[name] = old and function(...)
			old(...)
			fn(...)
		end or fn
	end
	function f:GetScript(name)
		return self.scripts[name]
	end
	function f:EnableMouse() end
	function f:SetOptions() end
	function f:IsMouseOver()
		return hovered
	end
	function f:SetDataProvider(dp)
		self.dp = dp
		rows = {}
		for _, ed in ipairs(dp._items) do
			if ed.thread then rows[#rows + 1] = ed.thread.id end
		end
	end
	function f:ForEachFrame(fn)
		for _, ed in ipairs(self.dp and self.dp._items or {}) do
			if ed.thread then fn({ thread = ed.thread }, ed) end
		end
	end
	return f
end
ns.UI.Dropdown = frame

local env = setmetatable({}, { __index = _G })
env.CreateFrame = frame
env.CreateScrollBoxListLinearView = function()
	local view = {}
	function view:SetElementFactory(fn)
		self.factory = fn
	end
	function view:SetElementExtentCalculator(fn)
		self.extent = fn
	end
	return view
end
env.ScrollUtil = {
	InitScrollBoxListWithScrollBar = function(box, _, view)
		box._view = view
	end,
}
env.ScrollBoxConstants = { RetainScrollPosition = true }
env.CreateDataProvider = function()
	local dp = { _items = {} }
	function dp:Insert(item)
		self._items[#self._items + 1] = item
	end
	return dp
end
for _, path in ipairs({ "Core/Store.lua", "UI/ThreadList.lua" }) do
	setfenv(assert(loadfile(path)), env)("KilnForever", ns)
end

local L = ns.ThreadList
L:Create(nil)

local function snapshot(ids)
	local threads = {}
	for _, id in ipairs(ids) do
		threads[#threads + 1] = { id = id, title = id, p = "/src/demo", s = "working", st = 1 }
	end
	return { threads = threads, projects = {}, bridge = {} }
end

local function order()
	return table.concat(rows, ",")
end

ns.Store:Apply(snapshot({ "first", "second" }))
L:Refresh(true)
check(order() == "first,second", "the list starts in the snapshot's order")

hovered = true
ns.Store:Apply(snapshot({ "second", "first" }))
L:Refresh()
check(order() == "first,second", "a snapshot that reorders the group while hovered leaves the rows in place")

-- Moving onto a row gives the row mouse focus, which the client reports to the list as
-- OnLeave, but IsMouseOver stays true because the pointer is still inside the list.
local leave = L.scrollBox:GetScript("OnLeave")
if leave then leave(L.scrollBox) end
check(order() == "first,second", "mouse focus moving to a row does not apply the pending order")

local update = L.orderDriver and L.orderDriver:GetScript("OnUpdate")
check(update ~= nil, "the list watches the pointer while an order is pending")
update()
check(order() == "first,second", "the rows stay put while the pointer is still over a row")

hovered = false
update()
check(order() == "second,first", "the new order shows on the first update after the pointer leaves the list")
check(L.orderDriver:GetScript("OnUpdate") == nil, "the pointer watch stops once the order is applied")

hovered = true
ns.Store:Apply(snapshot({ "first", "second" }))
L:Refresh()
check(order() == "second,first", "another snapshot still waits while hovered")
ns.viewId = "first"
L:Refresh()
check(order() == "first,second", "a selection change updates the list at once, even while hovered")
check(L.orderDriver:GetScript("OnUpdate") == nil, "the pointer watch stops when a selection change applies the order")

print("thread_list_order_spec: " .. checks .. " checks passed")
