-- The host must never enter Blizzard's tracker manager, including through pooled lines.
local harness = dofile("tests/tracker_host_harness.lua")
local t = harness.new({ deferReady = true, headerShown = true })
local check, drain = t.check, t.drain
local host, grip, native, parent = t.host, t.grip, t.native, t.parent
local first, second = t.first, t.second
-- The native tracker is protected: the host reads it and never writes it. Blizzard's own moves set `point` directly.
for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetClampedToScreen" }) do
	native[method] = function()
		error("the host wrote the protected native tracker: " .. method)
	end
end
local function MoveNative(...)
	native.point = { ... }
end

check(t.pending() == 0, "must not render before player and saved data are ready")
check(
	t.initializationEvents()[1] == "PLAYER_ENTERING_WORLD"
		and t.initializationEvents()[2] == "VARIABLES_LOADED"
		and #t.initializationEvents() == 2,
	"first rendering waits for both native load events"
)
t.ready()
check(t.pending() == 1, "first layout is deferred")
drain()
check(first.point[5] == 0 and second.point[5] == -90, "sections follow uiOrder")
check(t.nativeHeader.point[2] == native, "native header stays anchored to its native parent")
check(first.point[5] == 0, "visible native header reserves no top gap")
check(native.point[1] == "TOPRIGHT" and native.point[5] == -100, "the native tracker keeps its own slot")
check(
	host.point[1] == "TOP" and host.point[2] == native.NineSlice and host.point[3] == "BOTTOM" and host.point[5] == 0,
	"the column hangs from the bottom of the native quests"
)
t.native.headerWanted = false
t.updateOrder()
check(not t.headerShown(), "client update hides the native header")
check(t.nativeHeader.point[2] == native, "hidden header remains anchored to native parent")
t.native.headerWanted = true
t.updateOrder()
check(t.headerShown(), "client update shows the native header")
check(t.nativeHeader.point[2] == native, "client update re-anchors header to native parent")
host:MarkDirty()
drain()
check(t.nativeHeader.point[2] == native, "layouts leave header anchored to native parent")
-- The first section's 80 and the gap under it, then the gap the second section leaves under itself.
check(
	math.abs(second.available - (540 - 24 / 1.25 - 90 - 10)) < 1e-9,
	"remaining space runs from the quests to the screen, less each section's gap"
)
check(native:GetHeight() == 300, "native viewport preserves an externally sized height before clamping")
native:SetHeight(420)
native.scripts.OnSizeChanged(native)
drain()
check(native:GetHeight() == 420, "native viewport adopts an external resize before clamping")
native:SetHeight(700)
native.scripts.OnSizeChanged(native)
drain()
check(native:GetHeight() == 700, "native container keeps its externally sized height")
MoveNative("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
t.eventRegistry:TriggerEvent("EditMode.SavedLayouts")
drain()
check(
	native.point[5] == 0 and host.point[2] == native.NineSlice,
	"a saved layout moves the tracker and the column follows it"
)
-- The managed frame layout or a UI addon can put the native frame back in its saved slot with no event at all.
local probe = t.probe()
check(probe ~= nil and probe ~= host, "an addon-owned probe follows the native frame's top left corner")
MoveNative("TOPRIGHT", parent, "TOPRIGHT", 0, -100)
probe.scripts.OnSizeChanged(probe)
check(t.pending() == 1, "a silent native reanchor reflows the column")
drain()
check(
	native.point[5] == -100 and host.point[2] == native.NineSlice,
	"the silent reanchor leaves the tracker where it was put"
)
t.editMode.active, t.editMode.shown = true, true
t.eventRegistry:TriggerEvent("EditMode.Enter")
check(host.shown == false, "private tracker hides while Edit Mode owns native slot")
check(native.clamped == true, "the native frame keeps its screen clamp")
check(probe.point == nil, "Edit Mode disconnects the native geometry probe")
check(host.point[2] == parent, "hidden companion no longer depends on the native tracker's anchors")
drain()
check(native.point[1] == "TOPRIGHT", "queued layouts leave the native slot to Edit Mode")
probe.scripts.OnSizeChanged(probe)
check(t.pending() == 0, "a disconnected probe cannot queue a layout")
-- CheckHideAndLockEditMode hides the manager without exiting it: active stays true and no EditMode.Exit runs.
check(t.editMode.scripts.OnHide ~= nil, "private tracker follows the Edit Mode manager's own hide")
t.editMode.shown = false
t.editMode.scripts.OnHide(t.editMode)
drain()
check(host.shown == true, "private tracker returns when a locked Edit Mode hides its manager")
t.editMode.active, t.editMode.shown = false, false
t.eventRegistry:TriggerEvent("EditMode.Exit")
drain()
check(host.shown == true, "private tracker returns after Edit Mode")
check(probe.point[2] == native, "leaving Edit Mode reconnects the native geometry probe")
check(native.clamped == true and native.point[1] == "TOPRIGHT", "leaving Edit Mode leaves the native tracker alone")
check(t.ns.TrackerHost.IsAttached(first) and not t.ns.TrackerHost.IsAttached(nil), "ownership lookup")
local attachmentChanges = 0
t.ns.TrackerHost.OnAttachmentChanged(function(value)
	attachmentChanges = attachmentChanges + 1
	check(value == false or value == true, "attachment callback receives desired state")
end)
local updatesBeforeDuplicateAttach = first.updates
t.ns.TrackerHost.Attach(first)
host:MarkDirty()
host:MarkDirty()
check(t.pending() == 1, "dirty updates coalesce")
drain()
check(first.updates == updatesBeforeDuplicateAttach + 1, "duplicate attach must not duplicate sections")
local other = {}
t.loadHost(other)
check(other.TrackerHost == t.ns.TrackerHost, "addons share a single private host")
local hostPaths = {}
for path in (os.getenv("AGF_TRACKER_HOSTS") or "UI/TrackerHost.lua"):gmatch("[^\n]+") do
	hostPaths[#hostPaths + 1] = path
end
for index = 2, #hostPaths do
	local joining, count = {}, #t.frames
	t.loadHost(joining, hostPaths[index])
	check(joining.TrackerHost == t.ns.TrackerHost, "companion joins the first loaded host")
	check(#t.frames == count, "companion must not create a second host")
end
check(first:GetContextMenuParent() == host, "menus use private container")
check(grip ~= nil, "the grip is shown by the detached layout")
first.contentHeight, second.contentHeight = 0, 0
host:MarkDirty()
drain()
check(host.shown == false, "host hides when no section draws")
check(first.point[5] == 0 and second.point[5] == 0, "no header gap is reserved without section content")
check(t.nativeHeader.point[2] == native, "empty layout leaves native header in its parent")
local empty = harness.new({ headerShown = true })
empty.first.contentHeight, empty.second.contentHeight = 0, 0
empty.host:MarkDirty()
empty.drain()
empty.check(empty.host.shown == false, "host hides when visible header has no section content")
empty.check(empty.first.point[5] == 0, "visible header reserves no gap without drawn content")
empty.check(empty.nativeHeader.point[2] == empty.native, "visible header remains in native parent")

print("tracker_host_spec: " .. t.checks() .. " checks passed")
