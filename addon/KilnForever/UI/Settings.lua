-- Settings tab (also reachable from the game's Options > AddOns list).

local _, ns = ...
local UI = ns.UI

local S = {}
ns.Settings = S

local CHECKS = {
	{ key = "tracker", label = "Show Kiln Forever in the tracker area", after = function() ns.Tracker:Refresh() end },
	{ key = "trackerAlways", label = "Keep its header when nothing is running", after = function() ns.Tracker:Refresh() end },
	{ key = "trackerLocked", label = "Lock the tracker in place", after = function() ns.Tracker:Refresh() end },
	{ key = "toasts", label = "Pop up a notice when a thread finishes or needs you" },
	{ key = "sounds", label = "Play a sound with notices" },
	{ key = "quietInstances", label = "Stay quiet in dungeons, raids and PvP", tip = "Notices wait until you're out. They always wait during combat.", after = function() ns.Transport:Touch() end },
	{ key = "quickReplies", label = "Show quick replies under finished threads", after = function() ns.Transcript:Refresh(true) end },
	{ key = "gameMenu", label = "Add Kiln Forever to the game menu" },
	{ key = "minimapButton", label = "Show the minimap button", after = function() ns.MinimapButton:Refresh() end },
}

function S:Create(page)
	self.page = page
	local title = UI.Text(page, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 20, -16)
	title:SetText("Settings")

	local y = -48
	self.checks = {}
	for _, c in ipairs(CHECKS) do
		local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", 16, y)
		cb.Text:SetFontObject("GameFontHighlight")
		cb.Text:SetText(c.label)
		cb:SetScript("OnClick", function(check)
			ns.db.settings[c.key] = check:GetChecked() and true or false
			PlaySound(check:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			if c.after then c.after() end
		end)
		cb.key = c.key
		cb.Text:SetWidth(400)
		cb.Text:SetWordWrap(false)
		if c.tip then UI.Tooltip(cb, c.label, c.tip) end
		table.insert(self.checks, cb)
		y = y - 28
	end

	local sizeLabel = UI.Text(page, "GameFontHighlight")
	sizeLabel:SetPoint("TOPLEFT", 22, y - 12)
	sizeLabel:SetText("Window size")
	local size = UI.Dropdown(page, 240, function(value)
		ns.db.settings.windowScale = value
		ns.Main:ApplyScale()
	end)
	size:SetPoint("LEFT", sizeLabel, "RIGHT", 16, 0)
	size:SetOptions({
		{ value = "auto", label = "Automatic" },
		{ value = "normal", label = "Normal" },
		{ value = "large", label = "Large" },
		{ value = "xlarge", label = "Extra large" },
	}, ns.db.settings.windowScale or "auto")
	self.size = size

	local infoTitle = UI.Text(page, "GameFontNormal")
	infoTitle:SetPoint("TOPLEFT", 480, -16)
	infoTitle:SetText("Connection")
	self.info = UI.Text(page, "GameFontHighlightSmall")
	self.info:SetPoint("TOPLEFT", infoTitle, "BOTTOMLEFT", 0, -8)
	self.info:SetWidth(400)
	self.info:SetJustifyV("TOP")
	self.info:SetSpacing(3)

	local reload = UI.Button(page, "Reload UI", 130, function() ReloadUI() end)
	reload:SetPoint("BOTTOMLEFT", 20, 16)
	UI.Tooltip(reload, "Reload UI", "Frees up a fresh set of live updates. Does the same as typing /reload.")
	local resetTracker = UI.Button(page, "Reset tracker", 130, function()
		ns.db.settings.trackerPoint = nil
		ns.Tracker:Refresh(true)
	end)
	resetTracker:SetPoint("LEFT", reload, "RIGHT", 10, 0)
	local selftest = UI.Button(page, "Run self-test", 130, function() ns.SelfTest() end)
	selftest:SetPoint("LEFT", resetTracker, "RIGHT", 10, 0)
	UI.Tooltip(selftest, "Run self-test", "Checks the link to your desktop step by step and prints what's wrong, if anything.")
	local report = UI.Button(page, "Report a problem", 150, function() ns.Main:ShowPage("threads") ns.Main:Report() end)
	report:SetPoint("LEFT", selftest, "RIGHT", 10, 0)
	UI.Tooltip(report, "Report a problem", "Puts diagnostics in the message box, for the thread you have open (or a new one).")
	self.controls = { size, reload, resetTracker, selftest, report }
end

local SIGNAL_TEXT = {
	ok = "working",
	muted = "unavailable - game sound is off, so updates arrive more slowly",
	unreliable = "unreliable on this client - using slower polling",
	unavailable = "unavailable - using slower polling",
	untested = "starting",
}

function S:Refresh()
	if not self.page then return end
	for _, cb in ipairs(self.checks) do cb:SetChecked(ns.db.settings[cb.key] and true or false) end
	self.size.value = ns.db.settings.windowScale or "auto"
	self.size:Update()
	local T = ns.Transport
	local b = ns.Store.data.bridge or {}
	local lines = {
		"Bridge: " .. (b.version and ns.Color("green", "kiln-forever " .. b.version) or ns.Color("red", "not heard from")),
		"T3 Code: " .. (b.t3 == "connected" and ns.Color("green", "connected" .. (b.server and (" (" .. b.server .. ")") or "")) or ns.Color("red", b.t3 or "unknown"))
			.. (b.t3err and ns.Color("grey", " - " .. b.t3err) or ""),
		string.format("Live updates left this session: %s of %d (/reload frees more)", ns.Color("white", T:SlotsLeft()), T.slotCount),
		"Update signals: " .. (SIGNAL_TEXT[T.signals] or T.signals),
		"Errors: " .. ((ns.db.errors and #ns.db.errors > 0) and ns.Color("red", #ns.db.errors .. " recorded - /kiln errors") or ns.Color("green", "none")),
		"Addon " .. ns.version .. ns.Color("grey", "  ·  session " .. (ns.db.session or "?")),
	}
	self.info:SetText(table.concat(lines, "\n"))
end

ns:On("DataChanged", function()
	if ns.Main.page == "settings" and ns.Main.frame and ns.Main.frame:IsShown() then S:Refresh() end
end)

-- Options > AddOns entry that opens the real settings tab.
ns:On("Login", function()
	if not Settings or not Settings.RegisterCanvasLayoutCategory then return end
	local panel = CreateFrame("Frame")
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Kiln Forever")
	local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	text:SetText("Watch and steer your kiln agent sessions in game. Type /kiln to open the window.")
	local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	open:SetSize(200, 24)
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)
	open:SetText("Open Kiln Forever settings")
	open:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
		ns.Main:Open()
		ns.Main:ShowPage("settings")
	end)
	local category = Settings.RegisterCanvasLayoutCategory(panel, "Kiln Forever")
	Settings.RegisterAddOnCategory(category)
	ns.settingsCategory = category
end)
