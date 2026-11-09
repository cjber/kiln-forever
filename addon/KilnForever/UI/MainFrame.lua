-- The Kiln Forever window: a standard portrait frame with the session list on the left and the
-- selected session on the right.

local _, ns = ...
local UI = ns.UI

local M = {}
ns.Main = M

local WIDTH, HEIGHT = 940, 640
local LIST_W = 300
local COMPOSER_H = 92

M.page = "threads"
M.mode = "thread" -- "thread" | "new"

---------------------------------------------------------------------------
-- Frame

local function CreateSideTab(f, index, icon, tooltip, page)
	local tab = CreateFrame("Frame", nil, f, "LargeSideTabButtonTemplate")
	ns.Art.Icon(tab.Icon, icon, 24)
	tab:SetFillToInterior(true, 40)
	tab.tooltipText = tooltip
	tab:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -36 - (index - 1) * 48)
	tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
		if button == "LeftButton" and upInside then M:ShowPage(page) end
	end)
	tab:EnableMouse(true)
	tab.page = page
	return tab
end

function M:Create()
	if self.frame then return self.frame end
	local f = CreateFrame("Frame", "KilnForeverFrame", UIParent, "ButtonFrameTemplate")
	self.frame = f
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER", 0, 20)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()
	f:SetTitle("Kiln Forever")
	-- ButtonFrameTemplate inherits PortraitFrameTemplate, which masks its portrait round.
	f:SetPortraitToAsset(ns.icon)
	tinsert(UISpecialFrames, "KilnForeverFrame")

	-- Drag by the title bar.
	local drag = CreateFrame("Frame", nil, f)
	drag:SetPoint("TOPLEFT", 60, 0)
	drag:SetPoint("TOPRIGHT", -30, 0)
	drag:SetHeight(24)
	drag:EnableMouse(true)
	drag:RegisterForDrag("LeftButton")
	drag:SetScript("OnDragStart", function() f:StartMoving() end)
	drag:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		local point, _, rel, x, y = f:GetPoint()
		ns.db.settings.windowPoint = { point, rel, x, y }
	end)
	local wp = ns.db.settings.windowPoint
	if wp then
		f:ClearAllPoints()
		f:SetPoint(wp[1], UIParent, wp[2], wp[3], wp[4])
	end

	-- Subtitle: the thread you're looking at, and the link status under it.
	f.Subtitle = UI.Text(f, "GameFontNormalLarge", "CENTER")
	f.Subtitle:SetPoint("TOP", 20, -30)
	f.Subtitle:SetWidth(WIDTH - 220)
	f.Subtitle:SetWordWrap(false)
	f.Status = UI.Text(f, "GameFontGreenSmall", "CENTER")
	f.Status:SetPoint("TOP", f.Subtitle, "BOTTOM", 0, -2)
	f.Status:SetWidth(WIDTH - 220)

	-- Collapse the thread list (arrow under the close button).
	f.SidebarToggle = UI.IconButton(f, "common-dropdown-icon-back", 24, "Hide the session list", function() M:ToggleSidebar() end)
	f.SidebarToggle:SetPoint("TOPRIGHT", -10, -32)

	-- Shown when the session's live updates are running low: a reload frees them.
	f.RefreshSlots = UI.Button(f, "Refresh live updates", 170, function() ReloadUI() end)
	f.RefreshSlots:SetPoint("TOPRIGHT", f.SidebarToggle, "TOPLEFT", -8, 0)
	f.RefreshSlots:Hide()
	UI.Tooltip(f.RefreshSlots, "Refresh live updates", "Reloads the interface (a couple of seconds) to free a fresh set of live updates.")

	-- The sessions page lives inside the inset.
	f.Pages = {}
	f.Pages.threads = CreateFrame("Frame", nil, f.Inset)
	f.Pages.threads:SetAllPoints()
	self:CreateThreadsPage(f.Pages.threads)

	-- Bottom button bar.
	self:CreateButtonBar(f)

	-- Side tabs.
	f.Tabs = {
		CreateSideTab(f, 1, ns.icon, "Sessions", "threads"),
	}

	f:SetScript("OnShow", ns.Safe(function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
		ns.windowOpen = true
		ns.Interacted()
		ns.Transport:Touch()
		M:Refresh()
		ns:Fire("WindowShown", f)
	end))
	f:SetScript("OnHide", ns.Safe(function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
		M:SaveDraft()
		ns.windowOpen = false
		ns.Transport:Touch()
		ns:Fire("WindowHidden", f)
	end))

	self:ApplyScale()
	self:ShowPage("threads")
	return f
end

function M:CreateThreadsPage(page)
	-- Left: project filter + thread list.
	local left = CreateFrame("Frame", nil, page)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(LIST_W)
	page.Left = left

	-- A plain gap keeps the two panes apart without drawing chrome of our own.
	local divider = CreateFrame("Frame", nil, page)
	divider:SetWidth(4)
	divider:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, -2)
	divider:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 0, 2)
	page.Divider = divider

	ns.ThreadList:Create(left)

	-- Right: header bar, transcript, composer.
	local right = CreateFrame("Frame", nil, page)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 4, 0)
	right:SetPoint("BOTTOMRIGHT")
	page.Right = right

	local header = CreateFrame("Frame", nil, right)
	header:SetPoint("TOPLEFT", 4, -4)
	header:SetPoint("TOPRIGHT", -4, -4)
	header:SetHeight(30)
	local hbg = header:CreateTexture(nil, "BACKGROUND")
	ns.Art.Background(hbg, "common-button-list-collapseExpand")
	hbg:SetAllPoints()
	header.Text = UI.Text(header, "GameFontHighlight", "CENTER")
	header.Text:SetPoint("LEFT", 12, 0)
	header.Text:SetPoint("RIGHT", -240, 0)
	header.Text:SetWordWrap(false)

	header.Reply = UI.Button(header, "Reply", 80, function() M:FocusComposer() end)
	header.Reply:SetPoint("RIGHT", -4, 0)
	UI.Tooltip(header.Reply, "Reply", "Put the cursor in the message box.")

	header.Stop = UI.Button(header, "Stop", 70, function()
		if ns.viewId then
			ns.Transport:Send("stop", ns.viewId)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		end
	end)
	header.Stop:SetPoint("RIGHT", header.Reply, "LEFT", -4, 0)
	UI.Tooltip(header.Stop, "Stop", "Stop what the agent is doing.")

	-- Shown instead of Reply when kiln says it can't type into the session now.
	header.Note = UI.Text(header, "GameFontDisableSmall", "RIGHT")
	header.Note:SetPoint("RIGHT", header.Stop, "LEFT", -8, 0)
	header.Note:SetWidth(150)
	header.Note:SetWordWrap(false)
	header.Note:Hide()

	header.Directory = UI.Dropdown(header, 200, function(value)
		M.newDirectory = value
		M:Refresh()
	end)
	header.Directory:SetPoint("RIGHT", -6, 0)
	header.Directory:Hide()

	header.Agent = UI.Dropdown(header, 130, function(value)
		M.newAgent = value
		M:Refresh()
	end)
	header.Agent:SetPoint("RIGHT", header.Directory, "LEFT", -6, 0)
	header.Agent:Hide()
	right.Header = header

	local composer = UI.Inset(right)
	composer:SetPoint("BOTTOMLEFT", 2, 2)
	composer:SetPoint("BOTTOMRIGHT", -2, 2)
	composer:SetHeight(COMPOSER_H)
	right.ComposerInset = composer

	local box = CreateFrame("Frame", nil, composer, "KilnForeverComposerTemplate")
	box:SetPoint("TOPLEFT", 8, -6)
	box:SetPoint("BOTTOMRIGHT", -8, 18)
	box:RegisterCallback("OnEnterPressed", function()
		if IsShiftKeyDown() then
			box:Insert("\n")
		else
			M:Send()
		end
	end, M)
	box:RegisterCallback("OnTextChanged", function() M:UpdateCounter() ns.Interacted() end, M)
	box:RegisterCallback("OnEscapePressed", function() box:ClearFocus() end, M)
	right.Composer = box
	self.composer = box
	self:SetPlaceholder("Message the agent  (Shift+Enter for a new line)")

	local counter = UI.Text(composer, "GameFontDisableSmall", "RIGHT")
	counter:SetPoint("BOTTOMRIGHT", -8, 5)
	right.Counter = counter

	ns.Transcript:Create(right, header, composer)
end

function M:CreateButtonBar(f)
	local bar = {}
	bar.Refresh = UI.Button(f, "Refresh", 110, function()
		ns.Transport:Send("ping")
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end)
	bar.Refresh:SetPoint("BOTTOMLEFT", 6, 4)
	UI.Tooltip(bar.Refresh, "Refresh", "Ask the bridge for a fresh update now.")

	bar.New = UI.Button(f, "New Session", 130, function() M:StartNewThread() end)
	bar.New:SetPoint("LEFT", bar.Refresh, "RIGHT", 60, 0)

	bar.Back = UI.Button(f, "Back", 110, function() M:Back() end)
	bar.Back:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", LIST_W + 18, 4)

	bar.Send = UI.Button(f, "Send", 110, function() M:Send() end)
	bar.Send:SetPoint("BOTTOMRIGHT", -6, 4)
	f.Bar = bar
end

---------------------------------------------------------------------------
-- Pages, sidebar

function M:ShowPage(page)
	local f = self.frame
	self.page = page
	for name, p in pairs(f.Pages) do p:SetShown(name == page) end
	for _, tab in ipairs(f.Tabs) do tab:SetChecked(tab.page == page) end
	local threads = page == "threads"
	for _, key in ipairs({ "Back", "Send" }) do f.Bar[key]:SetShown(threads) end
	f.SidebarToggle:SetShown(threads)
	self:Refresh()
	ns:Fire("PageChanged", page)
end

function M:ToggleSidebar(show)
	local page = self.frame.Pages.threads
	if show == nil then show = not page.Left:IsShown() end
	page.Left:SetShown(show)
	page.Divider:SetShown(show)
	page.Right:ClearAllPoints()
	if show then
		page.Right:SetPoint("TOPLEFT", page.Left, "TOPRIGHT", 4, 0)
	else
		page.Right:SetPoint("TOPLEFT", 0, 0)
	end
	page.Right:SetPoint("BOTTOMRIGHT")
	self.frame.Bar.Refresh:SetShown(show)
	self.frame.Bar.New:SetShown(show)
	self.frame.Bar.Back:ClearAllPoints()
	if show then
		self.frame.Bar.Back:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", LIST_W + 18, 4)
	else
		self.frame.Bar.Back:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 6, 4)
	end
	self.frame.SidebarToggle.Icon:SetRotation(show and 0 or math.pi)
	ns.Transcript:Relayout()
end

---------------------------------------------------------------------------
-- Selecting threads, drafts

function M:SaveDraft()
	if not self.composer then return end
	local key = self.mode == "new" and "__new" or ns.viewId
	if key then
		local text = self.composer:GetInputText()
		ns.db.drafts[key] = (text and text ~= "") and text or nil
	end
end

function M:LoadDraft()
	local key = self.mode == "new" and "__new" or ns.viewId
	self.composer:SetText(key and ns.db.drafts[key] or "")
	self:UpdateCounter()
end

function M:SelectThread(id, opts)
	self:Create()
	if id == ns.viewId and self.mode == "thread" then
		if opts and opts.show then self:Open() end
		return
	end
	self:SaveDraft()
	self.mode = "thread"
	self.previous = ns.viewId
	ns.viewId = id
	local t = ns.Store:Thread(id)
	if t and t.un then ns.Transport:Send("read", id) end
	ns.Transport:Touch()
	self:LoadDraft()
	if opts and opts.show then self:Open() end
	if self.page ~= "threads" then self:ShowPage("threads") end
	self:Refresh()
	ns:Fire("ViewSelected", id)
end

function M:Back()
	if self.mode == "new" then
		self.mode = "thread"
		self:LoadDraft()
		self:Refresh()
		return
	end
	if not self.frame.Pages.threads.Left:IsShown() then
		self:ToggleSidebar(true)
		return
	end
	self:SaveDraft()
	ns.viewId = nil
	ns.Transport:Touch()
	self:LoadDraft()
	self:Refresh()
	ns:Fire("ViewSelected", nil)
end

function M:StartNewThread(agent, directory)
	self:Create()
	self:SaveDraft()
	self.mode = "new"
	local data = ns.Store.data
	self.newAgent = agent or ns.db.settings.lastAgent
	local known = false
	for _, a in ipairs(data.agents or {}) do
		if a == self.newAgent then known = true end
	end
	if not known then self.newAgent = (data.agents and data.agents[1]) or "claude" end
	local filter = ns.db.settings.project
	self.newDirectory = directory or (filter ~= "all" and filter) or ns.db.settings.lastDirectory
	if not ns.Store.projectsById[self.newDirectory or ""] then
		local first = data.projects[1]
		self.newDirectory = first and first.id
	end
	self:LoadDraft()
	if self.page ~= "threads" then self:ShowPage("threads") end
	self:Open()
	self:Refresh()
	self.composer:SetFocus()
end

function M:FocusComposer()
	if not self.composer then return end
	self.composer:SetFocus()
	ns.Interacted()
end

---------------------------------------------------------------------------
-- Sending

function M:UpdateCounter()
	local right = self.frame and self.frame.Pages.threads.Right
	if not right then return end
	local text = self.composer:GetInputText() or ""
	right.Counter:SetText(2000 - strlenutf8(text))
end

function M:Send(textOverride)
	local text = textOverride or self.composer:GetInputText() or ""
	text = strtrim(text)
	if text == "" then return end
	if #text > 2300 then
		ns.Error("That message is too long to send from the game (max ~2,000 characters).")
		return
	end
	if self.mode == "new" then
		if not self.newAgent then
			ns.Error("Pick an agent for the new session first.")
			return
		end
		if not self.newDirectory then
			ns.Error("Pick a directory for the new session first.")
			return
		end
		ns.db.settings.lastAgent = self.newAgent
		ns.db.settings.lastDirectory = self.newDirectory
		self.pendingNew = ns.Transport:Send("new", self.newAgent, self.newDirectory, text)
		self.pendingNewText = text
		ns.db.drafts.__new = nil
	elseif ns.viewId and not textOverride and ns.Transcript:CustomAnswer(text) then
		ns.db.drafts[ns.viewId] = nil
	elseif ns.viewId then
		ns.Transport:Send("send", ns.viewId, text)
		ns.Transcript:AddLocalEcho(ns.viewId, text)
		ns.db.drafts[ns.viewId] = nil
	else
		ns.Error("Pick a session, or start a new one.")
		return
	end
	if not textOverride then
		self.composer:SetText("")
		self.composer:ClearFocus()
	end
	PlaySound(SOUNDKIT.TELL_MESSAGE or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	self:Refresh()
end

---------------------------------------------------------------------------

local SCALES = { normal = 1, large = 1.15, xlarge = 1.3 }

function M:ApplyScale()
	if not self.frame then return end
	local pref = ns.db.settings.windowScale or "auto"
	self.frame:SetScale(SCALES[pref] or 1)
end

---------------------------------------------------------------------------
-- Status line and refresh

local LINK_TEXT = {
	connected = { "green", "Connected" },
	waiting = { "orange", "Waiting for the bridge… (run kiln-forever install on your desktop)" },
	stale = { "red", "Bridge not responding - is kiln-forever running?" },
	kilnoffline = { "red", "Bridge connected, but kiln is offline" },
	kilnunpaired = { "red", "kiln is not paired - run kiln-forever install on your desktop" },
	kilnwrite = { "orange", "kiln write access is off - viewing only" },
	exhausted = { "orange", "Live updates paused - /reload to resume" },
}

function M:StatusLine()
	local T = ns.Transport
	if T.slotError == "MISSING" then
		return ns.Color("red", "Live-update files missing - run kiln-forever install, then restart WoW")
	end
	local state = T:BridgeState()
	local entry = LINK_TEXT[state] or LINK_TEXT.waiting
	local text = ns.Color(entry[1], entry[2])
	if #T.queue > 0 then
		text = text .. ns.Color("grey", "  ·  sending…")
	end
	local left = T:SlotsLeft()
	if state == "connected" and left > 0 and left < math.max(40, T.slotCount * 0.15) then
		text = text .. ns.Color("orange", string.format("  ·  %d live updates left", left))
	end
	return text
end

function M:UpdateRefreshButton()
	local f = self.frame
	if not f then return end
	local T = ns.Transport
	local low = T.exhausted or (T.slotCount > 0 and T:SlotsLeft() < T.slotCount * 0.15)
	f.RefreshSlots:SetShown(low and not InCombatLockdown())
end

-- Blizzard's edit box keeps a shown placeholder as the box's text, and only swaps
-- it while the box is empty. Changed in place, the old placeholder stayed behind as
-- text that focusing no longer cleared, so typing went after it. Set it again on an
-- empty box so the new one replaces the old.
function M:SetPlaceholder(text)
	if self.placeholder == text then return end
	self.placeholder = text
	self.composer:SetDefaultText(text)
	if self.composer:GetInputText() == "" then self.composer:SetText("") end
end

function M:Refresh()
	local f = self.frame
	if not f or not f:IsShown() then return end
	f.Status:SetText(self:StatusLine())
	self:UpdateRefreshButton()

	local right = f.Pages.threads.Right
	local header = right.Header
	local t = ns.Store:Thread(ns.viewId)
	if self.mode == "new" then
		f.Subtitle:SetText("New Session")
		header.Text:SetText(ns.Color("gold", "Start an agent session in"))
		header.Text:ClearAllPoints()
		header.Text:SetPoint("LEFT", 12, 0)
		header.Text:SetPoint("RIGHT", header.Agent, "LEFT", -8, 0)
		header.Text:SetJustifyH("RIGHT")
		header.Reply:Hide()
		header.Stop:Hide()
		header.Note:Hide()
		header.Agent:Show()
		header.Directory:Show()
		self:SetupNewDropdowns()
		self:SetPlaceholder("Describe what the agent should do  (Shift+Enter for a new line)")
		f.Bar.Send:SetText("Start")
	else
		header.Text:ClearAllPoints()
		header.Text:SetPoint("LEFT", 12, 0)
		header.Text:SetPoint("RIGHT", -240, 0)
		header.Text:SetJustifyH("CENTER")
		header.Agent:Hide()
		header.Directory:Hide()
		f.Bar.Send:SetText("Send")
		if t then
			f.Subtitle:SetText(t.title)
			local status = ns.Color(ns.Store.StatusColor(t.s), ns.Store.StatusText(t.s))
			local age = (t.s == "working" and t.st) and ns.Duration(time() - t.st) or ns.Ago(t.u)
			header.Text:SetText(string.format("%s  ·  %s  ·  %s", status, ns.Store:ProjectName(t.p), age))
			local can = t.can or "r"
			local v = ns.Store:View()
			local reason = v and v.reply
			header.Stop:SetShown(can:find("x", 1, true) ~= nil and self.mode ~= "new")
			if reason and reason ~= "" then
				header.Note:SetText(ns.Color("grey", reason))
				header.Note:Show()
			else
				header.Note:Hide()
			end
			header.Reply:SetShown(can:find("r", 1, true) ~= nil)
			self:SetPlaceholder(t.s == "working" and "Queue a follow-up  (Shift+Enter for a new line)" or "Message the agent  (Shift+Enter for a new line)")
		else
			f.Subtitle:SetText(ns.Color("grey", "No session selected"))
			header.Text:SetText(ns.Color("grey", "Pick a session on the left, or start a new one"))
			header.Reply:Hide()
			header.Stop:Hide()
			header.Note:Hide()
		end
	end
	f.Bar.Back:SetEnabled(self.mode == "new" or ns.viewId ~= nil or not f.Pages.threads.Left:IsShown())
	self:UpdateCounter()
	ns.ThreadList:Refresh()
	ns.Transcript:Refresh()
end

function M:SetupNewDropdowns()
	local header = self.frame.Pages.threads.Right.Header
	local agents = {}
	for _, a in ipairs(ns.Store.data.agents or {}) do
		local label = ns.AGENTS[a] and ns.AGENTS[a].label or a
		table.insert(agents, { value = a, label = label })
	end
	if #agents == 0 then table.insert(agents, { value = "claude", label = "Claude" }) end
	header.Agent:SetOptions(agents, self.newAgent)
	local options = {}
	for _, p in ipairs(ns.Store.data.projects) do table.insert(options, { value = p.id, label = p.name }) end
	header.Directory:SetOptions(options, self.newDirectory)
end

---------------------------------------------------------------------------

function M:Open()
	self:Create()
	if not self.frame:IsShown() then self.frame:Show() end
end

function M:Toggle()
	self:Create()
	self.frame:SetShown(not self.frame:IsShown())
end

ns:On("Login", function()
	M:Create()
end)

ns:On("DataChanged", function()
	if M.frame and M.frame:IsShown() then M:Refresh() end
end)
ns:On("LinkChanged", function()
	if M.frame and M.frame:IsShown() then
		M.frame.Status:SetText(M:StatusLine())
		M:UpdateRefreshButton()
	end
end)
ns:On("CommandResult", function(r)
	if r.ok == false and r.msg then
		ns.Error(r.msg)
	elseif r.ok and r.msg and r.msg:find("^Queued", 1, true) then
		ns.Notice(r.msg)
	end
	if r.id == M.pendingNew then
		M.pendingNew = nil
		if r.ok then
			M.mode = "thread"
			M:LoadDraft()
			M:Refresh()
			if r.open then M:SelectThread(r.open) end
		end
	end
end)

-- Live elapsed timers in the header.
C_Timer.NewTicker(1, ns.Safe(function()
	if M.frame and M.frame:IsShown() and M.page == "threads" then
		local t = ns.Store:Thread(ns.viewId)
		if t and t.s == "working" and M.mode == "thread" then M:Refresh() end
	end
end))

---------------------------------------------------------------------------
-- Launcher and game menu entry

local L = {}
ns.Launcher = L

function L:Open()
	local main = ns.Main
	if main.frame and main.frame:IsShown() then
		main.frame:Hide()
		return
	end
	local toastThread = ns.Toasts and ns.Toasts:VisibleThread()
	if toastThread then
		main:SelectThread(toastThread, { show = true })
	else
		main:Open()
	end
end

function L:HookGameMenu()
	if self.menuHooked or not GameMenuFrame or not GameMenuFrame.InitButtons then return end
	self.menuHooked = true
	hooksecurefunc(GameMenuFrame, "InitButtons", function(menu)
		if ns.db.settings.gameMenu == false then return end
		local ok, err = pcall(function()
			local button = menu:AddButton("Kiln Forever", function()
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
				HideUIPanel(menu)
				L:Open()
			end)
			-- Sit just above "Log Out" rather than under "Exit Game".
			local logoutText = menu.GetLogoutText and menu:GetLogoutText() or LOG_OUT
			for _, b in ipairs(menu.buttons or {}) do
				if b ~= button and b.GetText and b:GetText() == logoutText and b.layoutIndex then
					button.layoutIndex = b.layoutIndex - 0.5
					button.topPadding = nil
					break
				end
			end
		end)
		if not ok then ns.RecordError("game menu", err) end
	end)
end

ns:On("Login", function()
	L:HookGameMenu()
end)
