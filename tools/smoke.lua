-- Headless smoke test: load the addon against tools/wowstub.lua and drive it.
--   lua5.1 tools/smoke.lua <addon dir> <snapshot.lua> [viewId]
local addonDir, snapshot, viewId = arg[1], arg[2], arg[3]
package.path = "./tools/?.lua;" .. package.path
local Stub = dofile("tools/wowstub.lua")
Stub.slotData.default = snapshot

local function check(cond, msg)
	if not cond then for _, e in ipairs(KilnWoW and KilnWoW.errors or {}) do print("RECORDED ERROR: " .. e.msg) end error("CHECK FAILED: " .. msg, 2) end
	print("ok - " .. msg)
end

-- Load files in TOC order.
local ns = {}
for line in io.lines(addonDir .. "/KilnWoW.toc") do
	line = line:gsub("\r", "")
	if line ~= "" and not line:match("^#") and line:match("%.lua$") then
		local path = addonDir .. "/" .. line:gsub("\\", "/")
		local chunk = assert(loadfile(path))
		chunk("KilnWoW", ns)
	end
end
check(KilnWoW == ns, "namespace exported")

Stub.Fire("ADDON_LOADED", "KilnWoW")
check(ns.db and ns.db.session and #ns.db.session == 8, "saved variables initialised")
Stub.Fire("PLAYER_LOGIN")
check(ns.Transport.slotCount == 600, "found 600 slots by binary search")
check(ns.Store.applied == 1, "bootstrap slot applied")
check(#ns.Store.data.threads > 0, "threads loaded: " .. #ns.Store.data.threads)
check(ns.Transport.stripShown, "hello strip shown")
check(ns.Transport:Encrypted(), "link keys loaded from the bootstrap slot")
check(KilnWoW_Inbox == nil, "slot global cleared after loading")
do
	local drawn = WOWSTUB.StripCells()
	-- Header byte 3 (version) spans cells 6..8: bits 16..23 of the frame.
	local bits = {}
	for i = 1, 9 do local v = drawn[i] bits[#bits + 1] = math.floor(v / 4) % 2 bits[#bits + 1] = math.floor(v / 2) % 2 bits[#bits + 1] = v % 2 end
	local version = 0
	for i = 17, 24 do version = version * 2 + bits[i] end
	check(version == 2, "strip is drawn encrypted (frame version 2)")
end
local payload = ns.Transport:Payload()
check(payload:sub(1, 2) == "H\031", "payload starts with hello record")

-- Strip encodes within capacity and the cells are valid.
local cells = ns.Codec.Encode(ns.Transport.stripSeq, payload)
check(#cells > 0, "strip cells: " .. #cells)

-- Simulate the bridge acknowledging the hello via the next slot.
Stub.validSounds = {}
ns.Transport.signals = "ok"
local sig = ns.db.sigNext
-- Patch the snapshot's ack to this UI session.
local chunk = assert(loadfile(snapshot))
chunk()
local data = KilnWoW_Inbox
KilnWoW_Inbox = nil
data.ack = { ui = ns.ui, seq = ns.Transport.stripSeq }
data.gen = data.gen + 1
data.nextSig = sig + 1
ns.Transport:Apply(data)
check(not ns.Transport.stripShown, "strip hidden after ack")

-- Open the window, select a thread, render.
ns.Main:Open()
check(ns.windowOpen, "window open")
check(ns.Transport.stripShown, "window open bumps the strip")
local firstThread = (data.view and data.view.id and ns.Store:Thread(data.view.id)) or ns.Store.data.threads[1]
ns.Main:SelectThread((viewId and viewId ~= "") and viewId or firstThread.id)
check(ns.viewId ~= nil, "thread selected")
ns.Store:Apply(data) -- view arrives
local rows = ns.Transcript.scrollBox._rows or {}
check(#rows > 0, "transcript rendered " .. #rows .. " elements")
local listRows = ns.ThreadList.scrollBox._rows or {}
check(#listRows > 0, "thread list rendered " .. #listRows .. " rows")

-- Send a message: queued, echoed, and present in the strip payload.
ns.Main.composer._text = "Please run the tests"
ns.Main:Send()
check(#ns.Transport.queue >= 1, "command queued")
check(ns.Transport:Payload():find("Please run the tests", 1, true) ~= nil, "message in strip payload")
check(ns.Transcript.echo[ns.viewId] ~= nil, "local echo shown")

-- Pages
ns.Main:ShowPage("settings")
ns.Main:ShowPage("threads")
check(true, "pages switch")

-- New thread flow
ns.Main:StartNewThread()
check(ns.Main.mode == "new" and ns.Main.newProject ~= nil, "new thread mode with project " .. tostring(ns.Main.newProject))
ns.Main.composer._text = "Build a thing"
ns.Main:Send()
check(ns.Transport:Payload():find("\031new\031", 1, true) ~= nil, "new-thread command in payload")
ns.Transport:Apply({ gen = data.gen + 2, results = { { id = ns.Main.pendingNew, ok = true, open = firstThread.id } }, threads = data.threads, projects = data.projects, bridge = data.bridge, ack = { ui = ns.ui, seq = ns.Transport.stripSeq } })
check(ns.Main.mode == "thread" and ns.viewId == firstThread.id, "result opened the new thread")
check(#ns.Transport.queue == 0, "all commands acknowledged")

-- Question / approval rendering
data.gen = data.gen + 10
data.view = data.view or { id = ns.viewId }
data.view.id = ns.viewId
data.view.pending = { id = "req1", kind = "question", questions = { { id = "q1", h = "Mode", q = "Which mode?", opts = { { l = "Fast", d = "quick", v = "fast" }, { l = "Careful", d = "slow", v = "careful" } } } } }
ns.Transport:Apply(data)
local optionRows = 0
for _, r in ipairs(ns.Transcript.scrollBox._rows) do if r.ed.kind == "option" then optionRows = optionRows + 1 end end
check(optionRows >= 2, "question options rendered: " .. optionRows)
for _, r in ipairs(ns.Transcript.scrollBox._rows) do
	if r.ed.kind == "option" and r.ed.label == "Fast" then r.frame:Click() break end
end
check(ns.Transport:Payload():find("answer\031" .. ns.viewId .. "\031req1\031q1\031fast", 1, true) ~= nil, "answer command queued")

-- Plan, approval details, run summary, queued note
data.gen = data.gen + 1
for _, th in ipairs(data.threads) do if th.id == ns.viewId then th.s = "plan" end end
data.view = data.view or {}
data.view.id = ns.viewId
data.view.pending = nil
data.view.plan = "|cffffd100Plan|r\n• step one"
data.view.sum = "Last run: 2 commands · 4m 12s"
data.view.queued = 1
ns.Transport:Apply(data)
local found = {}
for _, r in ipairs(ns.Transcript.scrollBox._rows) do
	if r.ed.text then
		if r.ed.text:find("step one", 1, true) then found.plan = true end
		if r.ed.text:find("Last run", 1, true) then found.sum = true end
		if r.ed.text:find("queued", 1, true) then found.queued = true end
	end
end
check(found.plan, "plan text shown")
check(found.sum and found.queued, "run summary and queued follow-ups shown")
data.gen = data.gen + 1
for _, th in ipairs(data.threads) do if th.id == ns.viewId then th.s = "input" end end
data.view.plan, data.view.queued = nil, nil
data.view.pending = { id = "ap1", kind = "approval", what = "Change files", detail = "", files = { { f = "a.lua", a = 12, d = 3 } }, always = true }
ns.Transport:Apply(data)
found = {}
for _, r in ipairs(ns.Transcript.scrollBox._rows) do
	if r.ed.text and r.ed.text:find("a.lua", 1, true) and r.ed.text:find("+12", 1, true) then found.files = true end
	if r.ed.label == "Always allow this" then found.always = r end
end
check(found.files, "approval lists the files with +/- counts")
found.always.frame:Click()
check(ns.Transport:Payload():find("approve\031" .. ns.viewId .. "\031ap1\031acceptAlways", 1, true) ~= nil, "Always allow sends acceptAlways")
data.gen = data.gen + 1
data.view.pending = nil
for _, th in ipairs(data.threads) do if th.id == ns.viewId then th.s = "open" end end
ns.Transport:Apply(data)

-- Notices wait during combat
_G.InCombatLockdown = function() return true end
local t1 = ns.Store.data.threads[2]
ns.Toasts.held = {}
ns:Fire("ThreadTransition", t1, "working", "open")
check(#ns.Toasts.held == 1, "notice held during combat")
_G.InCombatLockdown = function() return false end
ns:Fire("Combat", false)
check(#ns.Toasts.held == 0, "held notice shown after combat")

-- Search
ns.ThreadList.query = "zzzz-no-match"
ns.ThreadList:Refresh(true)
local threadRows = 0
for _, r in ipairs(ns.ThreadList.scrollBox._rows) do if r.ed.thread then threadRows = threadRows + 1 end end
check(threadRows == 0, "search hides non-matching threads")
ns.ThreadList.query = nil
ns.ThreadList:Refresh(true)

-- Report: diagnostics in the box
ns.Main.composer._text = ""
ns.Main:Report("the list flickers")
check(ns.Main.composer._text:find("the list flickers", 1, true) and ns.Main.composer._text:find("diagnostics", 1, true), "report fills the message box")
ns.Main.composer._text = ""

-- Attending flag: set while the window is in use, cleared after 90s idle
ns.Main:Open()
ns.Interacted()
Stub.Tick(0.1)
check(ns.Transport:Flags():find("a", 1, true) ~= nil, "attending while using the window")
Stub.now = Stub.now + 100
Stub.Tick(0.1)
check(ns.Transport:Flags():find("a", 1, true) == nil, "not attending after 90s idle")

-- Self-test runs
ns.SelfTest()
check(true, "self-test ran")

-- Window size
ns.db.settings.windowScale = "xlarge"
ns.Main:ApplyScale()
check(true, "window scale applied")
ns.db.settings.windowScale = "auto"

-- Transitions -> toast
local t = ns.Store.data.threads[1]
data.gen = data.gen + 1
for _, th in ipairs(data.threads) do if th.id == t.id then th.s = "working" end end
ns.Transport:Apply(data)
data.gen = data.gen + 1
for _, th in ipairs(data.threads) do if th.id == t.id then th.s = "open" th.un = true end end
ns.Transport:Apply(data)
local toastShown = ns.Toasts.frames[1] and ns.Toasts.frames[1]._shown
check(toastShown or (ns.windowOpen and ns.viewId == t.id), "finish transition produced a toast")

-- Tracker and tickers run
ns.Tracker:Refresh()
for _ = 1, 5 do Stub.Tick(1) end
check(true, "tickers ran")

-- Project dropdown: click opens, clicking a row picks
local mainFrame = ns.Main.frame
ns.Main:Open()
ns.ThreadList.dropdown._scripts.OnClick(ns.ThreadList.dropdown, "LeftButton")
check(ns.UI.ListOpen() ~= nil, "click opens the list")
local projectRows = ns.UI.ListOpen().Box._rows or {}
check(#projectRows >= 2, "list shows the projects: " .. #projectRows)
ns.UI.ListOpen().Box._rows[2].frame:Click()
check(ns.db.settings.project ~= "all", "click on a row picks it")
ns.db.settings.project = "all"

-- Launching without a keyboard
GameMenuFrame:InitButtons()
local entry
for _, b in ipairs(GameMenuFrame.buttons) do if b.text == "Kiln" then entry = b end end
check(entry and entry.layoutIndex == 4.5, "game menu entry sits above Log Out")
_G.HideUIPanel = function() end
mainFrame:Hide()
entry.cb()
check(mainFrame._shown, "game menu entry opens the window")
KilnWoW_Binding("toggle")
check(not mainFrame._shown, "shortcut toggles it closed")
check(#(ns.db.errors or {}) == 0, "no errors recorded")

-- Slash command
SlashCmdList.KILNWOW("status")
check(#Stub.printed > 0, "status printed: " .. Stub.printed[#Stub.printed])

-- Self-test: the long control plays, the empty one doesn't -> bells usable
Stub.validSounds = { ["Interface\\AddOns\\KilnWoW\\Signals\\03999.wav"] = true }
ns.Transport.signals = "untested"
ns.Transport.testing = nil
ns.Transport:SelfTest()
check(ns.Transport.signals == "ok", "self-test passes when the long control plays: " .. ns.Transport.signals)
Stub.validSounds = {}
ns.Transport.testing = nil
ns.Transport:SelfTest()
check(ns.Transport.signals == "muted", "self-test fails when nothing really plays (Forever says willPlay=true anyway)")
ns.Transport.signals = "ok"

-- A bell rung a couple of numbers ahead is still heard; bells map onto 8 rotating
-- files. Only a fresh snapshot moves the bell position (to the bridge's nextSig).
local function BellPath(k) return string.format("Interface\\AddOns\\KilnWoW\\Signals\\%05d.wav", 3991 + (k - 1) % 8) end
local freshFile = os.tmpname()
do
	local fh = assert(io.open(freshFile, "w"))
	fh:write(string.format("dofile(%q) KilnWoW_Inbox.gen = 9e15 KilnWoW_Inbox.nextSig = 503\n", snapshot))
	fh:close()
end
ns.Transport.exhausted = nil
ns.Transport.bellProbe = nil
ns.Transport.ringCooldownUntil = nil
ns.db.sigNext = 500
Stub.slotData[ns.Transport.slotCursor] = freshFile
Stub.validSounds = { [BellPath(502)] = true }
local loadsBefore = Stub.loadCount or 0
Stub.Tick(0.6) -- starts listening
Stub.Tick(0.2) -- checks which bell is really playing
check((Stub.loadCount or 0) > loadsBefore, "loaded a slot when bell 502 rang")
check(ns.db.sigNext == 503, "took the bridge's next bell from the fresh snapshot: " .. ns.db.sigNext)

-- A bell that leads to old data is a false alarm: no moving ahead (which would
-- alias still-rung bells and run away), a short cooldown, and a fresh strip.
Stub.validSounds = { [BellPath(504)] = true }
local loads1 = Stub.loadCount
ns.Transport.bellProbe = nil
Stub.Tick(0.6)
Stub.Tick(0.2)
check(Stub.loadCount == loads1 + 1 and ns.db.sigNext == 503, "false ring: one slot loaded, position kept at " .. ns.db.sigNext)
check(ns.Transport.falseRings == 1 and ns.Transport.stripShown, "false ring counted and the strip redrawn")
Stub.Tick(0.6)
Stub.Tick(0.2)
check(Stub.loadCount == loads1 + 1, "cooldown: no slot burned by the same false alarm")

-- A laggy client: even the empty control still "plays" at check time. Wait it out
-- instead of trusting the bells.
Stub.now = Stub.now + 5
ns.Transport:HideStrip() -- (as if the bridge acknowledged it; isolates the bell check)
ns.Transport.lastLoadAt = Stub.now
ns.Transport.bellProbe = nil
Stub.validSounds = { [BellPath(503)] = true, ["Interface\\AddOns\\KilnWoW\\Signals\\04000.wav"] = true }
local loads2 = Stub.loadCount
for _ = 1, 12 do Stub.Tick(0.2) end
check(Stub.loadCount == loads2, "no slot loaded while the client is too slow to tell bells apart")
Stub.validSounds = {}
ns.Transport.bellProbe = nil
local loads3 = Stub.loadCount
Stub.Tick(0.6)
Stub.Tick(0.2)
check(Stub.loadCount == loads3, "no slot spent while no bell rings")
os.remove(freshFile)

-- Tracker section follows the objective tracker, in the quest column.
do
	local trackerFrame = ns.Tracker.frame
	local function anchoredTo(target)
		for _, pt in ipairs(trackerFrame._points or {}) do if pt[2] == target then return true end end
		return false
	end
	WOWSTUB.Tick(0.3)
	check(ns.Tracker.attached == "below" and anchoredTo(ObjectiveTrackerFrame.NineSlice), "tracker section sits under the quests: " .. tostring(ns.Tracker.attached))
	check(trackerFrame:GetWidth() == 280, "same width as the objective tracker")
	ObjectiveTrackerFrame.isCollapsed = true
	for _, ticker in ipairs(WOWSTUB.tickers) do ticker.fn() end
	check(ns.Tracker.attached == "header" and anchoredTo(ObjectiveTrackerFrame.Header), "under the header when All Objectives is collapsed")
	ObjectiveTrackerFrame.isCollapsed = nil
	ObjectiveTrackerFrame._shown = false
	for _, ticker in ipairs(WOWSTUB.tickers) do ticker.fn() end
	check(ns.Tracker.attached == "replace", "takes the tracker's place when it's empty")
	ObjectiveTrackerFrame._shown = true
	ns.db.settings.trackerPoint = { "CENTER", "CENTER", 10, 10 }
	for _, ticker in ipairs(WOWSTUB.tickers) do ticker.fn() end
	check(ns.Tracker.attached == "custom", "a dragged position is kept")
	ns.db.settings.trackerPoint = nil
	for _, ticker in ipairs(WOWSTUB.tickers) do ticker.fn() end
	check(ns.Tracker.attached == "below", "reset reattaches it")
end

-- Minimap button
do
	local mb = ns.MinimapButton.button
	check(mb ~= nil, "minimap button created")
	local wasOpen = ns.windowOpen
	mb._scripts.OnClick(mb, "LeftButton")
	check(ns.windowOpen ~= wasOpen, "minimap click toggles the window")
	mb._scripts.OnClick(mb, "LeftButton")
	mb._scripts.OnEnter(mb)
	mb._scripts.OnDragStart(mb)
	mb._scripts.OnDragStop(mb)
	check(type(ns.db.settings.minimapAngle) == "number", "minimap drag saves its position")
	ns.db.settings.minimapButton = false
	ns.MinimapButton:Refresh()
	check(mb._shown == false, "minimap button can be hidden")
	ns.db.settings.minimapButton = true
	ns.MinimapButton:Refresh()
end

-- Exhaustion
Stub.now = Stub.now + 2
ns.Transport.slotCursor = ns.Transport.slotCount + 1
ns.Transport:LoadNextSlot("signal")
check(ns.Transport:BridgeState() == "exhausted", "slot exhaustion detected")
ns.Tracker:Refresh()

print("\nall smoke checks passed; slots loaded: " .. tostring(Stub.loadCount))
