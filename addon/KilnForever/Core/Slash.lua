-- Slash commands, key bindings and the addon compartment entry.

local _, ns = ...

if ns.broken then
	return
end

BINDING_HEADER_KILNFOREVER = "Kiln Forever"
BINDING_NAME_KILNFOREVER_TOGGLE = "Open or close Kiln Forever"
BINDING_NAME_KILNFOREVER_NEW = "Start a new session"

function KilnForever_Binding(action)
	if action == "toggle" then
		ns.Launcher:Open()
	elseif action == "new" then
		ns.Main:StartNewThread()
	end
end

function KilnForever_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then
		if not ns.Settings:Open() then ns.Main:Open() end
	else
		ns.Main:Toggle()
	end
end

function KilnForever_OnAddonCompartmentEnter(_, menuButtonFrame)
	GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
	GameTooltip:SetText("Kiln Forever", 1, 0.82, 0)
	local active = ns.Store:Active()
	GameTooltip:AddLine(#active > 0 and (#active .. " active session" .. (#active == 1 and "" or "s")) or "Nothing running", 1, 1, 1)
	GameTooltip:AddLine("Click to open, right-click for settings", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

function KilnForever_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Reports

-- The addon's own lines for the shared report window. The header, errors and debug log are Forever Core's.
function ns.ReportLines()
	local T = ns.Transport
	local b = ns.Store.data.bridge or {}
	return {
		string.format("addon %s, bridge %s, kiln %s (%s)", ns.version, b.version or "?", b.kiln or "?", b.host or "?"),
		string.format("link %s, signals %s via %s, live updates left %d/%d, queued %d", T:BridgeState(), T.signals, tostring(T.channel), T:SlotsLeft(), T.slotCount, #T.queue),
		string.format("page %s, mode %s, window scale %.2f", ns.Main.page, ns.Main.mode, (ns.Main.frame and ns.Main.frame:GetScale()) or 1),
	}
end

-- `/kiln report` and the settings button: the shared report window, with the player's note on top when there is one.
function ns.ReportProblem(note)
	local ok, lines = ns.core.SafeCall("report lines", ns.ReportLines)
	if not ok then lines = { "Report lines failed: " .. tostring(lines) } end
	if note and note ~= "" then table.insert(lines, 1, note) end
	ns.core.Report.Show(ns.core.Report.Text(lines))
end

-- The shared report commands, with the player's note on top for /kiln report. Core owns report, issue, bug and
-- feature; Kiln keeps the note it has always accepted after `report`.
---@param command string
---@param argument string
---@return boolean
local function ReportCommand(command, argument)
	if command == "report" then
		ns.ReportProblem(argument)
		return true
	end
	if command == "issue" or command == "bug" or command == "feature" then
		return ns.core.Report.Command(command, argument)
	end
	return false
end

---------------------------------------------------------------------------
-- Self-test

-- Step-by-step check of everything between the game and kiln.
function ns.SelfTest()
	local T = ns.Transport
	local b = ns.Store.data.bridge or {}
	-- The game font has no check/cross characters; use the game's own marks.
	local ok, bad = ns.Art.Markup("common-icon-checkmark", 14), ns.Art.Markup("common-icon-redx", 14)
	local function line(pass, text, fix)
		ns.Print((pass and ok or bad) .. " " .. text .. ((not pass and fix) and ns.Color("grey", " - " .. fix) or ""))
	end
	ns.Print(ns.Color("gold", "Self-test"))
	line(T.slotCount > 0, string.format("live-update files: %d found", T.slotCount), "run kiln-forever install, then fully restart the game")
	T:SelfTest(function(result)
		line(result == "ok", "update bells: " .. result .. (result == "ok" and (" (" .. tostring(T.channel) .. " channel)") or ""),
			"turn game sound on; the addon falls back to slower polling until then")
	end)
	local age = T.bridgeNow and (time() - T.bridgeNow) or nil
	line(age ~= nil and age < 300, "bridge: " .. (b.version and ("kiln-forever " .. b.version) or "not heard from") .. (age and string.format(", last update %ds ago", age) or ""),
		"check `kiln-forever status` on your desktop")
	line(b.kiln == "connected", "kiln: " .. tostring(b.kiln or "unknown"), b.kilnerr)
	line(b.write ~= false, "kiln write access: " .. (b.write == false and "off" or "on"),
		"turn on kiln's [phone] write access on your desktop")
	line(T:SlotsLeft() > 40, string.format("live updates left: %d of %d", T:SlotsLeft(), T.slotCount), "/reload to free a fresh set")
	local errs = ns.core.CaughtErrors()
	line(#errs == 0, string.format("addon errors recorded: %d", #errs), "/kiln errors to see them")
	-- Round trip: show the strip and time the bridge's acknowledgement.
	T:Touch()
	local seq, started = T.stripSeq, GetTime()
	local ticker
	ticker = C_Timer.NewTicker(0.1, function()
		local elapsed = GetTime() - started
		if T.ackedSeq >= seq then
			ticker:Cancel()
			line(true, string.format("round trip to the bridge: %.1fs", elapsed))
		elseif elapsed > 8 then
			ticker:Cancel()
			line(false, "round trip to the bridge: no answer in 8s",
				"is the game window visible on screen? `kiln-forever status --log` shows what the bridge sees")
		end
	end)
end

---------------------------------------------------------------------------
-- Commands

local function Status()
	local T = ns.Transport
	local b = ns.Store.data.bridge or {}
	ns.Print(string.format("link %s · kiln %s · %d sessions · live updates left %d/%d · signals %s · queued %d",
		T:BridgeState(), b.kiln or "?", #ns.Store.data.threads, T:SlotsLeft(), T.slotCount, T.signals .. " (" .. tostring(T.channel) .. ", " .. tostring(T.selfTests or 0) .. " tests)", #T.queue))
end

local function SetLocked(locked)
	ns.Tracker:SetLocked(locked)
	ns.Tracker:Refresh()
end

SLASH_KILNFOREVER1 = "/kiln"
SlashCmdList.KILNFOREVER = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if ReportCommand(cmd, rest) then
		return
	end
	if cmd == "" then
		ns.Main:Toggle()
	elseif cmd == "new" then
		ns.Main:StartNewThread()
		if rest ~= "" then ns.Main.composer:SetText(rest) end
	elseif cmd == "settings" or cmd == "options" then
		if not ns.Settings:Open() then ns.Print("The settings page is unavailable on this client.") end
	elseif cmd == "status" then
		Status()
	elseif cmd == "tracker" then
		ns.db.settings.tracker = not ns.db.settings.tracker
		ns.Tracker:Refresh()
		ns.Print("Tracker " .. (ns.db.settings.tracker and "shown" or "hidden"))
	elseif cmd == "unlock" or cmd == "lock" then
		local locked = cmd == "lock"
		SetLocked(locked)
		ns.Print(locked and "Tracker locked." or "Tracker unlocked. Right-click its header to detach it, then drag the grip.")
	elseif cmd == "selftest" or cmd == "test" then
		ns.SelfTest()
	elseif cmd == "errors" then
		local list = ns.core.CaughtErrors()
		if #list == 0 then
			ns.Print("No errors recorded.")
		else
			for i = math.max(1, #list - 4), #list do
				local e = list[i]
				ns.Print(ns.Color("grey", date("%H:%M:%S", e.lastSeen or e.firstSeen or time())) .. " " .. ns.Color("red", e.message))
			end
			ns.Print(ns.Color("grey", "(Errors also reach BugSack and /kiln report.)"))
		end
	elseif cmd == "debug" then
		ns.core.DebugCommand(rest)
	else
		ns.Print("/kiln - open the window")
		ns.Print("/kiln new [text] - start a new agent session")
		ns.Print("/kiln report [what went wrong] - open a report to copy")
		ns.Print("/kiln issue - open a ready-made GitHub issue")
		ns.Print("/kiln debug [pin | off | show] - turn the shared debug log on, keep it, or show it")
		ns.Print("/kiln selftest | settings | status | tracker | unlock | lock | errors")
	end
end
