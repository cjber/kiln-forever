-- Headless smoke test: load the addon against tools/wowstub.lua and drive it.
--   lua5.1 tools/smoke.lua <addon dir> <snapshot.lua> [viewId]
local addonDir, snapshot, viewId = arg[1], arg[2], arg[3]
package.path = "./tools/?.lua;" .. package.path
local Stub = dofile("tools/wowstub.lua")
Stub.slotData.default = snapshot

-- The client loads a required dependency before the addon's own files.
Stub.installForeverCore()

local function check(cond, msg)
	if not cond then for _, e in ipairs(KilnForever and KilnForever.errors or {}) do print("RECORDED ERROR: " .. e.msg) end error("CHECK FAILED: " .. msg, 2) end
	print("ok - " .. msg)
end

-- Load files in TOC order.
local ns = {}
for line in io.lines(addonDir .. "/KilnForever.toc") do
	line = line:gsub("\r", "")
	if line ~= "" and not line:match("^#") and line:match("%.lua$") then
		local path = addonDir .. "/" .. line:gsub("\\", "/")
		local chunk = assert(loadfile(path))
		chunk("KilnForever", ns)
	end
end
check(KilnForever == ns, "namespace exported")

Stub.Fire("ADDON_LOADED", "KilnForever")
check(ns.db and ns.db.session and #ns.db.session == 8, "saved variables initialised")
Stub.Fire("PLAYER_LOGIN")
check(ns.Transport.slotCount == 600, "found 600 slots by binary search")
check(ns.Store.applied == 1, "bootstrap slot applied")
check(#ns.Store.data.threads > 0, "threads loaded: " .. #ns.Store.data.threads)
check(ns.Transport.stripShown, "hello strip shown")
check(ns.Transport:Encrypted(), "link keys loaded from the bootstrap slot")
check(KilnForever_Inbox == nil, "slot global cleared after loading")
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
local data = KilnForever_Inbox
KilnForever_Inbox = nil
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

-- A queued mailbox message draws as a user message with a dim "Queued" label.
do
	data.gen = data.gen + 1
	data.view.msgs = data.view.msgs or {}
	table.insert(data.view.msgs, { r = "user", t = "Please run the tests again", at = Stub.now, q = true })
	ns.Transport:Apply(data)
	local label
	for _, r in ipairs(ns.Transcript.scrollBox._rows or {}) do
		if r.ed.kind == "msg" and r.ed.msg.q then label = r.frame.Label._text end
	end
	check(label ~= nil and label:find("Queued", 1, true) ~= nil, "a queued message draws with a dim Queued label")
	table.remove(data.view.msgs)
	data.gen = data.gen + 1
	ns.Transport:Apply(data)
end

-- An inbox reason leaves the reply box open and explains the wait.
do
	data.gen = data.gen + 1
	data.view.inbox = "Messages wait in kiln until this session is idle"
	ns.Transport:Apply(data)
	local header = ns.Main.frame.Pages.threads.Right.Header
	check(header.Note._shown and header.Note._text:find("Messages wait", 1, true) ~= nil, "an inbox reason shows beside an open reply box")
	check(header.Reply._shown, "the reply box stays enabled for an inbox session")
	data.view.inbox = nil
	data.gen = data.gen + 1
	ns.Transport:Apply(data)
end

-- Send a message: queued, echoed, and present in the strip payload.
ns.Main.composer._text = "Please run the tests"
ns.Main:Send()
check(#ns.Transport.queue >= 1, "command queued")
check(ns.Transport:Payload():find("Please run the tests", 1, true) ~= nil, "message in strip payload")
check(ns.Transcript.echo[ns.viewId] ~= nil, "local echo shown")

-- The shared settings page is registered, and the window has only its sessions page.
check(ns.Settings.panel ~= nil, "settings page registered")
check(ns.Settings:Open(), "settings page opens")
check(WOWSTUB.openedSettings == ns.Settings.category:GetID(), "settings open through the client's own opener")
ns.Main:ShowPage("threads")
check(true, "pages switch")

-- The shared page reads a checkbox when it builds it, so Kiln re-reads its rows when the value changes elsewhere.
do
	local panel = ns.Settings.panel
	panel:Show()
	local function checked(label)
		for _, frame in ipairs(WOWSTUB.frames) do
			if frame._parent == panel and frame._kind == "CheckButton" then
				for _, child in ipairs(WOWSTUB.frames) do
					if child._parent == frame and child._text == label then return frame._checked end
				end
			end
		end
	end
	ns.db.settings.tracker = true
	ns.Tracker:Refresh()
	check(checked("Show Kiln Forever in the tracker") == true, "the tracker row follows its value")
	SlashCmdList.KILNFOREVER("tracker")
	check(checked("Show Kiln Forever in the tracker") == false, "/kiln tracker updates the settings row")
	SlashCmdList.KILNFOREVER("tracker")
	check(checked("Show Kiln Forever in the tracker") == true, "the tracker row follows it back")
	SlashCmdList.KILNFOREVER("unlock")
	check(checked("Lock the tracker in place") == false, "/kiln unlock updates the settings row")
	SlashCmdList.KILNFOREVER("lock")
	check(checked("Lock the tracker in place") == true, "the lock row follows it back")
	panel:Hide()
end

-- New session flow: agent, directory, then the prompt.
ns.Main:StartNewThread()
check(ns.Main.mode == "new" and ns.Main.newAgent ~= nil and ns.Main.newDirectory ~= nil, "new session mode with " .. tostring(ns.Main.newAgent) .. " in " .. tostring(ns.Main.newDirectory))
ns.Main.composer._text = "Build a thing"
ns.Main:Send()
check(ns.Transport:Payload():find("\031new\031" .. ns.Main.newAgent .. "\031" .. ns.Main.newDirectory .. "\031Build a thing", 1, true) ~= nil, "new-session command in payload")
ns.Transport:Apply({ gen = data.gen + 2, results = { { id = ns.Main.pendingNew, ok = true, msg = "Started in kitty-1" } }, threads = data.threads, projects = data.projects, agents = data.agents, bridge = data.bridge, ack = { ui = ns.ui, seq = ns.Transport.stripSeq } })
check(ns.Main.mode == "thread", "the new-session result left new mode")
check(#ns.Transport.queue == 0, "all commands acknowledged")

-- Agent tags and statuses in the thread list.
do
	local tagged = {}
	for _, r in ipairs(ns.ThreadList.scrollBox._rows or {}) do
		if r.ed.thread and r.frame.Title and r.frame.Title._text then
			if r.frame.Title._text:find("Claude", 1, true) or r.frame.Title._text:find("Codex", 1, true)
				or r.frame.Title._text:find("OpenCode", 1, true) or r.frame.Title._text:find("Pi", 1, true) then
				tagged[#tagged + 1] = r.ed.thread.id
			end
		end
	end
	check(#tagged > 0, "sessions show a coloured agent tag before the title")
	local groups = ns.Store:Groups("all")
	check(groups.working and groups.input and groups.open and groups.done, "groups are Working, Needs you, Open and Done")
	check(ns.db.settings.collapsed.done == true, "Done is collapsed by default")
end

-- Question with an option that takes typed text.
data.gen = data.gen + 10
data.view = data.view or { id = ns.viewId }
data.view.id = ns.viewId
data.view.pending = { id = "prompt-9", kind = "question", questions = { { id = "q", h = "Mode", q = "Which mode?", custom = true, opts = { { l = "Fast", d = "quick", v = "1" }, { l = "Custom", d = "your own", v = "2", t = "inline" } } } } }
ns.Transcript.typed = {}
ns.Transcript.answered = {}
ns.Transport:Apply(data)
local optionRows = 0
for _, r in ipairs(ns.Transcript.scrollBox._rows) do if r.ed.kind == "option" then optionRows = optionRows + 1 end end
check(optionRows >= 2, "question options rendered: " .. optionRows)
for _, r in ipairs(ns.Transcript.scrollBox._rows) do
	if r.ed.kind == "option" and r.ed.label == "Fast" then r.frame:Click() break end
end
check(ns.Transport:Payload():find("answer\031" .. ns.viewId .. "\031prompt-9\0311", 1, true) ~= nil, "a plain option answers with its number")

-- A typed option remembers the choice and takes the composer's text.
ns.Transcript.answered = {}
ns.Transcript:Refresh(true)
for _, r in ipairs(ns.Transcript.scrollBox._rows) do
	if r.ed.kind == "option" and r.ed.label == "Custom" then r.frame:Click() break end
end
check(ns.Transcript.typed["prompt-9"] ~= nil, "the typed option is selected")
ns.Main.composer._text = "my own answer"
ns.Main:Send()
check(ns.Transport:Payload():find("answer\031" .. ns.viewId .. "\031prompt-9\0312\031my own answer", 1, true) ~= nil, "the typed answer sends its number and text")
data.gen = data.gen + 1
data.view.pending = nil
for _, th in ipairs(data.threads) do if th.id == ns.viewId then th.s = "open" end end
ns.Transport:Apply(data)
do
	local options = 0
	for _, r in ipairs(ns.Transcript.scrollBox._rows or {}) do if r.ed.kind == "option" then options = options + 1 end end
	check(options == 0, "a quiet session shows no quick replies")
end

-- Notices wait during combat
_G.InCombatLockdown = function() return true end
local t1 = ns.Store.data.threads[2]
ns.Toasts.held = {}
ns:Fire("ThreadTransition", t1, "working", "done")
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

-- Report: the shared window, with the player's note and the addon's diagnostics.
ns.ReportProblem("the list flickers")
local reportText
for _, f in ipairs(WOWSTUB.frames) do
	if f._kind == "EditBox" and f._text and f._text:find("the list flickers", 1, true) then reportText = f._text end
end
check(reportText and reportText:find("KilnForever", 1, true), "report opens in the shared window")
check(KilnForeverReport and KilnForeverReport._shown, "report window shown")
KilnForeverReport:Hide()

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
local t = ns.Store.data.threads[2]
-- A fresh list of thread tables so Store sees the change: mutating the snapshot's own tables would also
-- change the old ones it compares against.
local function threads_with(id, status)
	local list = {}
	for _, th in ipairs(ns.Store.data.threads) do
		local copy = {}
		for k, v in pairs(th) do copy[k] = v end
		if copy.id == id then
			copy.s = status
			if status == "done" then copy.un = true end
		end
		list[#list + 1] = copy
	end
	return list
end
local toastsBefore = #ns.Toasts.frames
data.gen = data.gen + 1
data.threads = threads_with(t.id, "working")
ns.Transport:Apply(data)
data.gen = data.gen + 1
data.threads = threads_with(t.id, "done")
ns.Transport:Apply(data)
local toast = ns.Toasts.frames[#ns.Toasts.frames]
check(#ns.Toasts.frames > toastsBefore and toast._shown, "finish transition produced a toast")
check(toast.kfThreadId == t.id, "the toast names the finished session")
check(toast.dungeonName._text and toast.dungeonName._text:find(t.title, 1, true), "the toast shows the session title")
check(toast.dungeonTexture._texture ~= nil, "the toast carries the addon icon")
ns.Toasts.held = {}
toastsBefore = #ns.Toasts.frames
ns:Fire("ThreadTransition", ns.Store.data.threads[3], "open", "input")
local needs = ns.Toasts.frames[#ns.Toasts.frames]
check(#ns.Toasts.held == 1 or (#ns.Toasts.frames > toastsBefore and needs._shown), "needs-you transition produced a notice")
check(#ns.Toasts.frames == toastsBefore or needs.kfHeading._text:find("Needs you", 1, true), "the notice says it needs you")

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
for _, b in ipairs(GameMenuFrame.buttons) do if b.text == "Kiln Forever" then entry = b end end
check(entry and entry.layoutIndex == 4.5, "game menu entry sits above Log Out")
_G.HideUIPanel = function() end
mainFrame:Hide()
entry.cb()
check(mainFrame._shown, "game menu entry opens the window")
KilnForever_Binding("toggle")
check(not mainFrame._shown, "shortcut toggles it closed")
check(#(ns.db.errors or {}) == 0, "no errors recorded")

-- Slash command
SlashCmdList.KILNFOREVER("status")
check(#Stub.printed > 0, "status printed: " .. Stub.printed[#Stub.printed])

-- /kiln debug hands the rest to the shared debug log.
SlashCmdList.KILNFOREVER("debug")
check(ns.core.DebugEnabled(), "/kiln debug turns the shared debug log on")
SlashCmdList.KILNFOREVER("debug off")
check(not ns.core.DebugEnabled(), "/kiln debug off turns it off")

-- Self-test: the long control plays, the empty one doesn't -> bells usable
Stub.validSounds = { ["Interface\\AddOns\\KilnForever\\Signals\\03999.wav"] = true }
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
local function BellPath(k) return string.format("Interface\\AddOns\\KilnForever\\Signals\\%05d.wav", 3991 + (k - 1) % 8) end
local freshFile = os.tmpname()
do
	local fh = assert(io.open(freshFile, "w"))
	fh:write(string.format("dofile(%q) KilnForever_Inbox.gen = 9e15 KilnForever_Inbox.nextSig = 503\n", snapshot))
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
Stub.validSounds = { [BellPath(503)] = true, ["Interface\\AddOns\\KilnForever\\Signals\\04000.wav"] = true }
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

-- Tracker section: the shared column's next free slot, with Kiln's rows.
do
	local module = ns.Tracker.module
	check(module ~= nil, "tracker section created")
	check(module.uiOrder == -5, "tracker section takes the shared column's next slot")
	check(ForeverCore.TrackerHost.IsAttached(module), "tracker section attached to the shared column")
	check(module.headerText == "Kiln Forever", "tracker header named")
	WOWSTUB.Tick(0.3)
	ns.db.settings.tracker = true
	ns.Tracker:Refresh()
	module:Update(600)
	check(module:GetContentsHeight() > 0, "tracker shows its sessions")
	ns.db.settings.tracker = false
	ns.Tracker:Refresh()
	module:Update(600)
	check(module:GetContentsHeight() == 0, "tracker hides with its setting")
	ns.db.settings.tracker = true
	ns.Tracker:Reset()
	local hostSettings = ForeverCore.TrackerHost.GetSettings()
	check(ns.db.trackerHost == nil and hostSettings.attached == true and hostSettings.locked == false, "reset reattaches and unlocks the column")
	ns.Tracker:Refresh()
	module:Update(600)
end

-- Minimap button: the shared button, the addon icon, one click to open.
do
	local mb = ns.minimapButton
	check(mb ~= nil, "minimap button created")
	local wasOpen = ns.windowOpen
	mb._scripts.OnClick(mb, "LeftButton")
	check(ns.windowOpen ~= wasOpen, "minimap click toggles the window")
	mb._scripts.OnClick(mb, "LeftButton")
	mb._scripts.OnEnter(mb)
	mb._scripts.OnDragStart(mb)
	mb._scripts.OnDragStop(mb)
	check(type(ns.db.settings.minimapButtonAngle) == "number", "minimap drag saves its position")
	ns.db.settings.minimapButton = false
	ForeverCore.MinimapButton.Refresh()
	check(mb._shown == false, "minimap button can be hidden")
	ns.db.settings.minimapButton = true
	ForeverCore.MinimapButton.Refresh()
end

-- Exhaustion
Stub.now = Stub.now + 2
ns.Transport.slotCursor = ns.Transport.slotCount + 1
ns.Transport:LoadNextSlot("signal")
check(ns.Transport:BridgeState() == "exhausted", "slot exhaustion detected")
ns.Tracker:Refresh()

print("\nall smoke checks passed; slots loaded: " .. tostring(Stub.loadCount))
