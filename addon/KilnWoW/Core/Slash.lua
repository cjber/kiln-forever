-- Slash commands, key bindings and the addon compartment entry.

local _, ns = ...

BINDING_HEADER_KILNWOW = "Kiln"
BINDING_NAME_KILNWOW_TOGGLE = "Open or close Kiln"
BINDING_NAME_KILNWOW_NEW = "Start a new thread"

function KilnWoW_Binding(action)
	if action == "toggle" then
		ns.Launcher:Open()
	elseif action == "new" then
		ns.Main:StartNewThread()
	end
end

function KilnWoW_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then
		ns.Main:Open()
		ns.Main:ShowPage("settings")
	else
		ns.Main:Toggle()
	end
end

function KilnWoW_OnAddonCompartmentEnter(_, menuButtonFrame)
	GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
	GameTooltip:SetText("Kiln", 1, 0.82, 0)
	local active = ns.Store:Active()
	GameTooltip:AddLine(#active > 0 and (#active .. " active thread" .. (#active == 1 and "" or "s")) or "Nothing running", 1, 1, 1)
	GameTooltip:AddLine("Click to open, right-click for settings", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

function KilnWoW_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

-- Step-by-step check of everything between the game and T3 Code.
function ns.SelfTest()
	local T = ns.Transport
	local b = ns.Store.data.bridge or {}
	-- The game font has no check/cross characters; use the game's own icons.
	local ok, bad = CreateAtlasMarkup("common-icon-checkmark", 14, 14), CreateAtlasMarkup("common-icon-redx", 14, 14)
	local function line(pass, text, fix)
		ns.Print((pass and ok or bad) .. " " .. text .. ((not pass and fix) and ns.Color("grey", " - " .. fix) or ""))
	end
	ns.Print(ns.Color("gold", "Self-test"))
	line(T.slotCount > 0, string.format("live-update files: %d found", T.slotCount), "run kiln-wow install, then fully restart the game")
	T:SelfTest(function(result)
		line(result == "ok", "update bells: " .. result .. (result == "ok" and (" (" .. tostring(T.channel) .. " channel)") or ""),
			"turn game sound on; the addon falls back to slower polling until then")
	end)
	local age = T.bridgeNow and (time() - T.bridgeNow) or nil
	line(age ~= nil and age < 300, "bridge: " .. (b.version and ("kiln-wow " .. b.version) or "not heard from") .. (age and string.format(", last update %ds ago", age) or ""),
		"check `kiln-wow status` on your desktop")
	line(b.t3 == "connected", "T3 Code on this computer: " .. tostring(b.t3), b.t3err)
	line(T:SlotsLeft() > 40, string.format("live updates left: %d of %d", T:SlotsLeft(), T.slotCount), "/reload to free a fresh set")
	local errs = ns.db.errors or {}
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
				"is the game window visible on screen? `kiln-wow status --log` shows what the bridge sees")
		end
	end)
end

local function Status()
	local T = ns.Transport
	local b = ns.Store.data.bridge or {}
	ns.Print(string.format("link %s · T3 %s · %d threads · live updates left %d/%d · signals %s · queued %d",
		T:BridgeState(), b.t3 or "?", #ns.Store.data.threads, T:SlotsLeft(), T.slotCount, T.signals .. " (" .. tostring(T.channel) .. ", " .. tostring(T.selfTests or 0) .. " tests)", #T.queue))
end

SLASH_KILNWOW1 = "/kiln"
SlashCmdList.KILNWOW = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "" then
		ns.Main:Toggle()
	elseif cmd == "new" then
		ns.Main:StartNewThread()
		if rest ~= "" then ns.Main.composer:SetText(rest) end
	elseif cmd == "settings" or cmd == "options" then
		ns.Main:Open()
		ns.Main:ShowPage("settings")
	elseif cmd == "status" then
		Status()
	elseif cmd == "tracker" then
		ns.db.settings.tracker = not ns.db.settings.tracker
		ns.Tracker:Refresh()
		ns.Print("Tracker " .. (ns.db.settings.tracker and "shown" or "hidden"))
	elseif cmd == "unlock" or cmd == "lock" then
		ns.db.settings.trackerLocked = cmd == "lock"
		ns.Print("Tracker " .. (cmd == "lock" and "locked" or "unlocked - drag its header to move it"))
	elseif cmd == "selftest" or cmd == "test" then
		ns.SelfTest()
	elseif cmd == "report" then
		ns.Main:ShowPage("threads")
		ns.Main:Report(rest)
	elseif cmd == "errors" then
		local list = ns.db.errors or {}
		if rest == "clear" then
			ns.db.errors = {}
			ns.errors = {}
			ns.Print("Cleared.")
		elseif #list == 0 then
			ns.Print("No errors recorded.")
		else
			for i = math.max(1, #list - 4), #list do
				local e = list[i]
				ns.Print(ns.Color("grey", date("%H:%M:%S", e.t)) .. " " .. ns.Color("red", e.msg))
			end
			ns.Print(ns.Color("grey", "(/kiln errors clear to reset. They're also saved with the addon's data on /reload.)"))
		end
	else
		ns.Print("/kiln - open the window")
		ns.Print("/kiln new [text] - start a new thread")
		ns.Print("/kiln report [what went wrong] - diagnostics into the message box")
		ns.Print("/kiln selftest | settings | status | tracker | unlock | lock | errors")
	end
end
