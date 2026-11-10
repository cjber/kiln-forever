-- Options > AddOns > Kiln Forever: the shared Forever settings page with this addon's own rows.

local _, ns = ...

local S = {}
ns.Settings = S

local SCALES = {
	{ key = "auto", label = "Automatic" },
	{ key = "normal", label = "Normal" },
	{ key = "large", label = "Large" },
	{ key = "xlarge", label = "Extra large" },
}

local function ScaleLabel(key)
	for _, scale in ipairs(SCALES) do
		if scale.key == key then return scale.label end
	end
	return SCALES[1].label
end

local function StepScale()
	local current = 1
	for index, scale in ipairs(SCALES) do
		if scale.key == (ns.db.settings.windowScale or "auto") then current = index end
	end
	local nextScale = SCALES[(current % #SCALES) + 1]
	ns.db.settings.windowScale = nextScale.key
	ns.Log("info", "settings", "window size %s", nextScale.key)
	ns.Main:ApplyScale()
	S:Refresh()
end

-- The shared page reads each row's getter only when it is built, so keep the rows here and re-read them whenever the
-- page comes back on screen or a value is changed from elsewhere: /kiln tracker, /kiln lock, the tracker's header menu
-- or Reset.
local checks = {}

---@param panel Frame
---@param page table
---@param label string
---@param get fun(): boolean?
---@param set fun(checked: boolean)
---@param tooltip? string
local function AddCheck(panel, page, label, get, set, tooltip)
	local check = page.AddCheck(panel, label, get, set, tooltip)
	checks[#checks + 1] = { check = check, get = get }
	return check
end

-- The page's chrome is Forever Core's UI/SettingsPage.lua. These rows and the phrases they show are Kiln's own.
local function BuildPanel(panel, page)
	AddCheck(panel, page, "Show Kiln Forever in the tracker", function()
		return ns.db.settings.tracker ~= false
	end, function(checked)
		ns.db.settings.tracker = checked
		ns.Log("info", "settings", "tracker %s", checked and "shown" or "hidden")
		ns.Tracker:Refresh()
	end, "Adds the Kiln Forever section to the objective tracker.")

	AddCheck(panel, page, "Keep its header when nothing is running", function()
		return ns.db.settings.trackerAlways ~= false
	end, function(checked)
		ns.db.settings.trackerAlways = checked
		ns.Tracker:Refresh()
	end)

	-- The host's saved table is canonical: another Forever addon may have built it first, so read and write through
	-- the host's own getter and setter.
	AddCheck(panel, page, "Lock the tracker in place", function()
		return ns.Tracker:IsLocked()
	end, function(checked)
		ns.Tracker:SetLocked(checked)
	end, "Turn this off to drag the column from its grip once it is detached from the quest tracker.")

	AddCheck(panel, page, "Pop up a notice when a session finishes or needs you", function()
		return ns.db.settings.toasts ~= false
	end, function(checked)
		ns.db.settings.toasts = checked
	end)

	AddCheck(panel, page, "Play a sound with notices", function()
		return ns.db.settings.sounds ~= false
	end, function(checked)
		ns.db.settings.sounds = checked
	end)

	AddCheck(panel, page, "Stay quiet in dungeons, raids and PvP", function()
		return ns.db.settings.quietInstances ~= false
	end, function(checked)
		ns.db.settings.quietInstances = checked
		ns.Transport:Touch()
	end, "Notices wait until you're out. They always wait during combat.")

	AddCheck(panel, page, "Add Kiln Forever to the game menu", function()
		return ns.db.settings.gameMenu ~= false
	end, function(checked)
		ns.db.settings.gameMenu = checked
	end)

	AddCheck(panel, page, "Show the minimap button", function()
		return ns.db.settings.minimapButton ~= false
	end, function(checked)
		ns.db.settings.minimapButton = checked
		ns.MinimapButton.Refresh()
	end)

	local sizeButton = page.AddButton(panel, "Window size: " .. ScaleLabel(ns.db.settings.windowScale or "auto"), StepScale, "Click to step through Automatic, Normal, Large and Extra large.")
	S.sizeButton = sizeButton

	page.AddButton(panel, "Reload UI", function() ReloadUI() end, "Frees up a fresh set of live updates. Does the same as typing /reload.")
	page.AddButton(panel, "Reset tracker", function()
		ns.Tracker:Reset()
	end, "Puts the tracker back under the quests and forgets where you dragged it.")
	page.AddButton(panel, "Run self-test", function() ns.SelfTest() end, "Checks the link to your desktop step by step and prints what's wrong, if anything.")
	local report = page.AddButton(panel, "Report a problem", function() ns.ReportProblem() end, "Opens a report you can copy into a bug report.")

	local info = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", report, "BOTTOMLEFT", 0, -18)
	info:SetWidth(460)
	info:SetJustifyH("LEFT")
	info:SetJustifyV("TOP")
	info:SetSpacing(3)
	S.info = info
end

local SIGNAL_TEXT = {
	ok = "working",
	muted = "unavailable - game sound is off, so updates arrive more slowly",
	unreliable = "unreliable on this client - using slower polling",
	unavailable = "unavailable - using slower polling",
	untested = "starting",
}

function S:Refresh()
	if not self.panel or not self.panel:IsShown() then return end
	for _, row in ipairs(checks) do
		row.check:SetChecked(row.get() == true)
	end
	if self.sizeButton then self.sizeButton:SetText("Window size: " .. ScaleLabel(ns.db.settings.windowScale or "auto")) end
	local T = ns.Transport
	local b = ns.Store.data.bridge or {}
	local errors = #ns.CaughtErrors()
	self.info:SetText(table.concat({
		"Bridge: " .. (b.version and ns.Color("green", "kiln-forever " .. b.version) or ns.Color("red", "not heard from")),
		"kiln: " .. (b.kiln == "connected" and ns.Color("green", "connected" .. (b.host and (" (" .. b.host .. ")") or "")) or ns.Color("red", b.kiln or "unknown"))
			.. (b.kilnerr and ns.Color("grey", " - " .. b.kilnerr) or ""),
		"kiln write access: " .. (b.write == false and ns.Color("orange", "off (view only)") or ns.Color("green", "on")),
		string.format("Live updates left this session: %s of %d (/reload frees more)", ns.Color("white", T:SlotsLeft()), T.slotCount),
		"Update signals: " .. (SIGNAL_TEXT[T.signals] or T.signals),
		"Errors: " .. (errors > 0 and ns.Color("red", errors .. " recorded - /kiln errors") or ns.Color("green", "none")),
		"Addon " .. ns.version .. ns.Color("grey", "  ·  session " .. (ns.db.session or "?")),
	}, "\n"))
end

function S.Register()
	if S.panel then return S.panel end
	local category, panel = ns.SettingsPage.Register("Kiln Forever", BuildPanel)
	if not panel then return nil end
	S.category, S.panel = category, panel
	panel:HookScript("OnShow", function() S:Refresh() end)
	return panel
end

function S:Open()
	if not self.panel then S.Register() end
	if not self.category then return false end
	Settings.OpenToCategory(self.category:GetID())
	return true
end

ns:On("DataChanged", function()
	if S.panel and S.panel:IsShown() then S:Refresh() end
end)

-- The shared minimap button: the client's own icon, one click to open the window, and the saved hide flag.
local function CreateMinimapButton()
	if ns.minimapButton or not ns.MinimapButton or not ns.MinimapButton.Create then return end
	ns.MinimapButton.Create({
		name = "KilnForeverMinimapButton",
		icon = ns.GAME_ICON,
		title = "Kiln Forever",
		subtext = "Click to open",
		settings = ns.db.settings,
		getShown = function()
			return ns.db.settings.minimapButton ~= false
		end,
		host = ns,
		onClick = function() ns.Launcher:Open() end,
	})
end

ns:On("Login", function()
	ns.SafeCall("settings", S.Register)
	ns.SafeCall("minimap button", CreateMinimapButton)
end)
