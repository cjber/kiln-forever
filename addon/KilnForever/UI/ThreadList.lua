-- Left side of the window: project filter and the grouped thread list.

local _, ns = ...
if ns.broken then
	return
end
local UI = ns.UI

local L = {}
ns.ThreadList = L

local LIST_W_DEFAULT = 280

local GROUPS = {
	{ key = "working", label = "Working" },
	{ key = "input", label = "Needs you" },
	{ key = "open", label = "Open" },
	{ key = "done", label = "Done" },
}

local DOT_COLORS = {
	working = { 0.29, 0.62, 1 },
	input = { 1, 0.6, 0.2 },
	unread = { 0.29, 0.62, 1 },
}

local function InitHeader(button, ed)
	UI.InitGroupHeader(button)
	UI.SetGroupHeader(button, ed.label, ed.count, ed.collapsed)
	button:SetScript("OnClick", function()
		local c = ns.db.settings.collapsed
		c[ed.key] = not c[ed.key]
		PlaySound(c[ed.key] and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		L:Refresh(true)
	end)
end

local function CreateRow(button)
	button:SetHeight(46)
	button:RegisterForClicks("LeftButtonUp")

	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	ns.Art.Background(hover, "Options_List_Hover")
	hover:SetAllPoints()
	hover:SetAlpha(0.5)

	local sel = button:CreateTexture(nil, "BACKGROUND")
	ns.Art.Background(sel, "PetList-ButtonSelect")
	sel:SetPoint("TOPLEFT", -2, 2)
	sel:SetPoint("BOTTOMRIGHT", 2, -2)
	button.Selected = sel

	local dot = button:CreateTexture(nil, "ARTWORK")
	ns.Art.Dot(dot, 1, 1, 1, 7)
	dot:SetPoint("TOPLEFT", 6, -12)
	button.Dot = dot

	local title = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOPLEFT", 18, -7)
	title:SetPoint("RIGHT", -74, 0)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	button.Title = title

	local status = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	status:SetPoint("TOPRIGHT", -6, -8)
	status:SetJustifyH("RIGHT")
	button.Status = status

	local sub = button:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	sub:SetPoint("BOTTOMLEFT", 18, 8)
	sub:SetPoint("RIGHT", -60, 0)
	sub:SetJustifyH("LEFT")
	sub:SetWordWrap(false)
	button.Sub = sub

	local age = button:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	age:SetPoint("BOTTOMRIGHT", -6, 8)
	age:SetJustifyH("RIGHT")
	button.Age = age

	button:SetScript("OnEnter", function(self)
		local t = self.thread
		if not t then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(t.title, 1, 0.82, 0, 1, true)
		GameTooltip:AddLine(ns.Store:ProjectName(t.p), 0.7, 0.7, 0.7)
		GameTooltip:AddLine(t.l or ns.Store.StatusText(t.s), 1, 1, 1, true)
		if t.br then GameTooltip:AddLine("Branch: " .. t.br, 0.6, 0.8, 1) end
		local agent = ns.AGENTS[t.m]
		if agent then GameTooltip:AddLine(agent.label .. (t.w and (" in " .. t.w) or ""), 0.6, 0.6, 0.6) end
		if t.last then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(t.last, 0.9, 0.9, 0.9, true)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button.created = true
end

local function InitRow(button, ed)
	if not button.created then CreateRow(button) end
	local t = ed.thread
	button.thread = t
	button.Selected:SetShown(t.id == ns.viewId and ns.Main.mode ~= "new")
	local tag = ns.AgentTag(t.m)
	button.Title:SetText(tag and (tag .. "  " .. t.title) or t.title)
	if t.s == "done" then
		button.Title:SetTextColor(0.75, 0.75, 0.75)
	else
		button.Title:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
	end
	local color = DOT_COLORS[t.s] or (t.un and DOT_COLORS.unread)
	button.Dot:SetShown(color ~= nil)
	if color then button.Dot:SetVertexColor(color[1], color[2], color[3]) end
	button.Status:SetText(ns.Color(ns.Store.StatusColor(t.s), ns.Store.StatusText(t.s)))
	local sub = ns.Store:ProjectName(t.p)
	if t.br then sub = sub .. "  ·  " .. t.br end
	button.Sub:SetText(sub)
	if t.s == "working" and t.st then
		button.Age:SetText(ns.Duration(time() - t.st))
	else
		button.Age:SetText(ns.Ago(t.u))
	end
	button:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		ns.Main:SelectThread(t.id)
	end)
end

function L:Create(parent)
	local dd = UI.Dropdown(parent, LIST_W_DEFAULT, function(value)
		ns.db.settings.project = value
		L:Refresh(true)
		ns.Main:Refresh()
	end)
	dd:SetPoint("TOPLEFT", 8, -8)
	dd:SetPoint("TOPRIGHT", -10, -8)
	self.dropdown = dd

	local search = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
	search:SetHeight(20)
	search:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 6, -6)
	search:SetPoint("TOPRIGHT", dd, "BOTTOMRIGHT", -2, -6)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function(box)
		L.query = strtrim(box:GetText() or ""):lower()
		L:Refresh(true)
	end)
	self.search = search

	local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", 4, -70)
	scrollBox:SetPoint("BOTTOMRIGHT", -18, 4)
	local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

	local view = CreateScrollBoxListLinearView(2, 2, 2, 2, 2)
	view:SetElementFactory(function(factory, ed)
		if ed.header then
			factory("KilnForeverGroupHeaderTemplate", InitHeader)
		elseif ed.empty then
			factory("KilnForeverEmptyRowTemplate", function(frame)
				if not frame.Text then
					frame.Text = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
					frame.Text:SetPoint("LEFT", 18, 0)
					frame.Text:SetPoint("RIGHT", -8, 0)
					frame.Text:SetJustifyH("LEFT")
				end
				frame.Text:SetText(ed.empty)
			end)
		else
			factory("KilnForeverThreadRowTemplate", InitRow)
		end
	end)
	view:SetElementExtentCalculator(function(_, ed)
		if ed.header then return 28 end
		if ed.empty then return 24 end
		return 46
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	-- A snapshot re-sorts a group while the pointer may be over a row. Keep what is
	-- on screen and apply the new order once the pointer is off the list, so a click
	-- still opens the session the player saw under the cursor. Mouse focus moves to a
	-- row when the pointer reaches it, which fires the list's OnLeave too early;
	-- IsMouseOver stays true over child rows, so a driver frame polls that instead.
	local orderDriver = CreateFrame("Frame", nil, parent)
	self.scrollBox, self.scrollBar, self.view, self.orderDriver = scrollBox, scrollBar, view, orderDriver
end

function L:SetupDropdown()
	local options = { { value = "all", label = "All repositories" } }
	for _, p in ipairs(ns.Store.data.projects) do
		if p.act then table.insert(options, { value = p.id, label = p.name }) end
	end
	self.dropdown:SetOptions(options, ns.db.settings.project)
end

function L:ApplyPendingOrder()
	if not self.pendingOrder then return end
	self.pendingOrder = nil
	self.orderDriver:SetScript("OnUpdate", nil)
	self:Refresh(true)
end

function L:Refresh(force)
	if not self.scrollBox then return end
	local s = ns.db.settings
	if s.project ~= "all" and not ns.Store.projectsById[s.project] and ns.Store.applied > 0 then s.project = "all" end
	local uiKey = table.concat({
		s.project, tostring(s.collapsed.working), tostring(s.collapsed.input),
		tostring(s.collapsed.open), tostring(s.collapsed.done), tostring(ns.viewId), ns.Main.mode, self.query or "",
	}, ":")
	local key = ns.Store.applied .. ":" .. uiKey
	if key == self.key and not force then
		-- Only timers changed: refresh the visible rows in place.
		self.scrollBox:ForEachFrame(function(frame, ed)
			if ed.thread then InitRow(frame, ed) end
		end)
		return
	end
	-- A snapshot re-sorts a group by activity. Rebuilding now would move rows under
	-- the pointer, so keep the order on screen and apply the new one when the pointer
	-- leaves. A click or a filter still rebuilds at once, because its state changed.
	if not force and uiKey == self.uiKey and self.scrollBox:IsMouseOver() then
		self.pendingOrder = true
		self.orderDriver:SetScript("OnUpdate", function()
			if not self.scrollBox:IsMouseOver() then self:ApplyPendingOrder() end
		end)
		return
	end
	self.pendingOrder = nil
	self.orderDriver:SetScript("OnUpdate", nil)
	self.key, self.uiKey = key, uiKey
	self:SetupDropdown()

	local groups = ns.Store:Groups(s.project, self.query)
	local dp = CreateDataProvider()
	for _, g in ipairs(GROUPS) do
		local list = groups[g.key]
		local collapsed = s.collapsed[g.key]
		if #list > 0 or g.key ~= "done" then
			dp:Insert({ header = true, key = g.key, label = g.label, count = #list, collapsed = collapsed })
			if not collapsed then
				for _, t in ipairs(list) do dp:Insert({ thread = t }) end
				if #list == 0 then
					local empty = ({ working = "Nothing running", input = "Nothing needs you", open = "Nothing open", done = "Nothing done" })[g.key]
					dp:Insert({ empty = empty or "Nothing here" })
				end
			end
		end
	end
	if ns.Store.applied == 0 then
		dp:Insert({ empty = "Waiting for the bridge…" })
	end
	self.scrollBox:SetDataProvider(dp, ScrollBoxConstants.RetainScrollPosition)
	ns:Fire("ListRebuilt")
end
