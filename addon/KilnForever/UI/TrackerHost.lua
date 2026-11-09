---@type string, ForeverTrackerNamespace
local _, ns = ...

---@class ForeverTrackerModule : Frame
---@field uiOrder? number
---@field parentContainer? Frame
---@field Header? Frame
---@field headerMenu? boolean
---@field show? ForeverTrackerShowSetting the section's own show switch, when it has one
---@field GetContextMenuParent fun(self: ForeverTrackerModule): Frame
---@field SetContainer fun(self: ForeverTrackerModule, container: Frame)
---@field IsTruncated fun(self: ForeverTrackerModule): boolean
---@field AddHeaderMenuEntries? fun(self: ForeverTrackerModule, root: any) a section's own entries, after the column's

---@class ForeverNativeTrackerHeader : Frame
---@field Text FontString
---@field MinimizeButton Button

---@class ForeverNativeTrackerFrame : Frame
---@field Header ForeverNativeTrackerHeader
---@field NineSlice Frame?
---@field isCollapsed? boolean

-- Sharing the native tracker collection also shares its Edit Mode execution path.
-- Keep our sections and their frame pools entirely outside that collection.
if not ObjectiveTrackerFrame then
	return
end

if ForeverTrackerHost then
	ns.TrackerHost = ForeverTrackerHost
	return
end

local host = CreateFrame("Frame", "ForeverTrackerCompanion", UIParent)
---@class ForeverTrackerHostAPI
local api = {}
local MIN_SCALE, MAX_SCALE = 0.5, 2
local fallbackSettings = { attached = true, scale = 1, backdropOpacity = 0 }
local ready = false
local function Coordinate(value)
	if type(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
end
-- The saved backdrop opacity is a fraction, so the value the slider writes and the value the texture reads are the
-- same number. It is not a separate on/off switch: 0 is off, and every value above it is the texture's opacity.
local function Opacity(value)
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.max(0, math.min(1, value))
end
---@return ForeverTrackerSettings
local function Settings()
	local settings = ns.TrackerHostSettings and ns.TrackerHostSettings() or fallbackSettings
	if type(settings.attached) ~= "boolean" then
		settings.attached = true
	end
	settings.locked = settings.locked == true
	local scale = settings.scale
	if type(scale) ~= "number" or scale ~= scale then
		settings.scale = 1
	else
		settings.scale = math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
	end
	settings.backdropOpacity = Opacity(settings.backdropOpacity)
	settings.x, settings.y = Coordinate(settings.x), Coordinate(settings.y)
	return settings
end
local attached
local dragging = false
local attachmentCallbacks = {}
-- The native tracker is protected and keeps the slot Blizzard, Edit Mode or a UI addon gave it: this host never moves
-- it, in combat or out. The private column reads below it, so the header and the game's quests come first and the
-- Forever sections follow, and the same placement runs in and out of combat, so entering or leaving combat moves
-- nothing. The sections stay outside Blizzard's secure module collection.
local function StackPoints(point)
	if point == "CENTER" or point == "TOP" or point == "BOTTOM" then
		return "TOP", "BOTTOM"
	end
	local horizontal = point:find("RIGHT", 1, true) and "RIGHT" or "LEFT"
	return "TOP" .. horizontal, "BOTTOM" .. horizontal
end
host:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
local function MatchNativeScale()
	local parentScale = UIParent:GetEffectiveScale()
	local nativeScale = ObjectiveTrackerFrame:GetEffectiveScale()
	if parentScale and nativeScale and parentScale > 0 then
		-- Saved variables, and with them the user's scale, are not ready while the files load.
		local userScale = ready and Settings().scale or 1
		host:SetScale(nativeScale / parentScale * userScale)
	end
end
MatchNativeScale()
host:SetWidth(ObjectiveTrackerFrame:GetWidth())
host:SetHeight(1)
host:SetMovable(true)
host:SetClampedToScreen(true)
-- The grip and the Lock switch that suppresses its drag live in their own file (UI/TrackerLock.lua), which the TOC
-- loads before this one. It hands back the label redraw for a Lock change and the show switch for the attachment.
local Grip = ns.TrackerLock.Grip(host, api)
-- The optional backdrop spans the whole private column, so every Forever section sits on it at once. It is one
-- texture on the host rather than chrome each addon draws, and it uses the game's own tooltip background art, tinted
-- the way the tooltip tints it. Off is simply opacity 0; drawing it only changes a texture, never a frame, so the
-- slider is safe to move in combat.
local BACKDROP_ATLAS = "Tooltip-NineSlice-Center"
local BACKDROP_INSET = 6
local backdrop = host:CreateTexture(nil, "BACKGROUND")
-- art-ok: the tooltip's own centre fill, a tiling texture stretched to the column by design
backdrop:SetAtlas(BACKDROP_ATLAS)
-- No inset at the top: the attached column starts at the native quests' bottom edge, so the backdrop must not reach
-- up over the last quest line. It pads the sides and the bottom instead.
backdrop:SetPoint("TOPLEFT", host, "TOPLEFT", -BACKDROP_INSET, 0)
backdrop:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", BACKDROP_INSET, -BACKDROP_INSET)
backdrop:Hide()

local function BackdropTint()
	local color = rawget(_G, "TOOLTIP_DEFAULT_BACKGROUND_COLOR")
	if color then
		local getter = color.GetRGB
		if type(getter) == "function" then
			local r, g, b = getter(color)
			if type(r) == "number" and type(g) == "number" and type(b) == "number" then
				return r, g, b
			end
		end
		if type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
			return color.r, color.g, color.b
		end
	end
	-- The tooltip's saved default when the client's colour object is not available (tests, and a stripped client).
	return 0.09, 0.09, 0.19
end

local function ApplyBackdrop(settings)
	local opacity = settings.backdropOpacity or 0
	backdrop:SetShown(opacity > 0)
	if opacity > 0 then
		local r, g, b = BackdropTint()
		backdrop:SetVertexColor(r, g, b, opacity)
	end
end
local function IsLocked()
	return Settings().locked
end
local modules, queued = {}, false
local pools = CreateFramePoolCollection()

local function NotifyAttachment(value)
	for _, callback in ipairs(attachmentCallbacks) do
		callback(value)
	end
end

local function Acquire(parent, template)
	local info = C_XMLUtil.GetTemplateInfo(template)
	local pool = pools:GetOrCreatePool(info and info.type or "Frame", parent, template)
	---@class ForeverTrackerPooledFrame : Frame
	---@field GetLine? function
	---@field FreeLine? function
	---@field OnAnimFinished? function
	local frame, isNew = pool:Acquire(template)
	frame.template = template
	return frame, isNew
end

local function GetLine(block, key, template)
	template = template or block.parentModule.lineTemplate
	local line = block:GetExistingLine(key)
	if line and line.template ~= template then
		block:FreeLine(line)
		line = nil
	end
	if not line then
		line = Acquire(block, template)
		line:SetParent(block)
		line:Show()
	end
	block.usedLines[key] = line
	line.objectiveKey, line.parentBlock, line.used = key, block, true
	return line
end

local function FreeLine(block, line)
	block.usedLines[line.objectiveKey] = nil
	pools:Release(line)
	line:Hide()
	if line.OnFree then
		line:OnFree(block)
	end
end

local function FreeResources(resources, onFree)
	for key, frame in pairs(resources or {}) do
		if not frame.used then
			resources[key] = nil
			if onFree and frame.OnFree then
				frame:OnFree()
			end
			pools:Release(frame)
		end
	end
end

-- Our blocks have no native reward toasts; their animations stay in the private cache.
local function OnAnimFinished(block)
	if block.activeAnim ~= block.AddAnim then
		block.parentModule:RemoveBlockFromCache(block)
		block.parentModule:MarkDirty()
		block:SetAlpha(0)
	end
	block.activeAnim = nil
	if block.pendingAnim then
		local anim = block.pendingAnim
		block.pendingAnim = nil
		block:TryPlayAnim(anim)
	end
end

local Module = {}
function Module:SetContainer(container)
	self.parentContainer = container
	self:SetParent(container)
end
function Module:AcquireFrame(template)
	local frame, isNew = Acquire(self, template)
	frame:SetParent(self.ContentsFrame)
	if frame.GetLine then
		frame.GetLine, frame.FreeLine = GetLine, FreeLine
		if frame.OnAnimFinished then
			frame.OnAnimFinished = OnAnimFinished
		end
	end
	return frame, isNew
end
function Module:FreeBlock(block)
	self:RemoveBlockFromCache(block, true)
	block:Free()
	self.usedBlocks[block.template][block.id] = nil
	pools:Release(block)
	self:OnFreeBlock(block)
end
function Module:FreeUnusedTimerBars()
	FreeResources(self.usedTimerBars)
end
function Module:FreeUnusedProgressBars()
	FreeResources(self.usedProgressBars, true)
end
function Module:FreeUnusedRightEdgeFrames()
	FreeResources(self.usedRightEdgeFrames)
end
function Module.GetContextMenuParent(_)
	return host
end

local function OverlapsMinimap()
	local minimap = _G.Minimap
	if not minimap or not minimap:IsShown() then
		return false
	end
	local left, right, top, bottom = host:GetLeft(), host:GetRight(), host:GetTop(), host:GetBottom()
	local ml, mr, mt, mb = minimap:GetLeft(), minimap:GetRight(), minimap:GetTop(), minimap:GetBottom()
	local hostScale = host:GetEffectiveScale()
	local mapScale = minimap:GetEffectiveScale()
	local screen = UIParent:GetEffectiveScale()
	if not (left and right and top and bottom and ml and mr and mt and mb) then
		return false
	end
	left, right, top, bottom =
		left * hostScale / screen, right * hostScale / screen, top * hostScale / screen, bottom * hostScale / screen
	ml, mr, mt, mb = ml * mapScale / screen, mr * mapScale / screen, mt * mapScale / screen, mb * mapScale / screen
	return left < mr and right > ml and bottom < mt and top > mb
end

local function AvoidMinimap(point)
	if not OverlapsMinimap() then
		return
	end
	host:ClearAllPoints()
	if point:find("LEFT", 1, true) then
		host:SetPoint("TOPLEFT", ObjectiveTrackerFrame, "TOPRIGHT", 0, 0)
	else
		host:SetPoint("TOPRIGHT", ObjectiveTrackerFrame, "TOPLEFT", 0, 0)
	end
end

local function SidePoint(point)
	local left, right = ObjectiveTrackerFrame:GetLeft(), ObjectiveTrackerFrame:GetRight()
	local screen = UIParent:GetWidth()
	local nativeScale = ObjectiveTrackerFrame:GetEffectiveScale()
	local screenScale = UIParent:GetEffectiveScale()
	if left and right and screen and nativeScale > 0 and screenScale > 0 then
		local nativeCenter = (left + right) * nativeScale / (2 * screenScale)
		return nativeCenter <= screen / 2 and "LEFT" or "RIGHT"
	end
	return point:find("LEFT", 1, true) and "LEFT" or "RIGHT"
end

-- The list's left, right and top in the host's own scale, whether it is a real frame (Questie) or the normalised
-- bounds table UI/TrackerEqot.lua returns.
local function ListEdges(list)
	if list.left then
		return list.left, list.right, list.top
	end
	-- A frame the client has not placed yet answers nil, and multiplying that would throw inside the layout.
	local left, right, top = list:GetLeft(), list:GetRight(), list:GetTop()
	if not (left and right and top) then
		return nil
	end
	local toHost = list:GetEffectiveScale() / host:GetEffectiveScale()
	return left * toHost, right * toHost, top * toHost
end

-- Where a detached column sits until the player drags it: beside the quest list (the native tracker, Questie's or
-- EQOT's) and level with its top, so neither draws over the other. To its left when the column fits there, otherwise
-- to its right. Offsets are from UIParent's top left corner in the host's own scale; the caller keeps them on screen.
local function Beside(list, width, screenHeight)
	local left, right, top = ListEdges(list)
	if not (left and right and top) then
		return 0, -40
	end
	local x = left - 8 - width
	if x < 0 then
		x = right + 8
	end
	return x, top - screenHeight
end

-- UI/TrackerEqot.lua and UI/TrackerQuestie.lua, loaded first, find the quest list another tracker draws over the
-- native slot (a host loaded without either ignores that addon). EQOT is the more specific cover, since it hides the
-- native frame, so its list is consulted before Questie's.
local TrackerEqot = ns.TrackerEqot
	or {
		List = function() end,
		Await = function() end,
		Room = function()
			return 0
		end,
		Places = function()
			return {}
		end,
	}
local TrackerQuestie = ns.TrackerQuestie or { List = function() end, Await = function() end }
-- Whether the last attached layout went round another addon's list, which one, and the room it gave the sections.
---@type boolean, boolean, boolean, "eqot"|"questie"|nil, number
local besideList, besideQuestie, besideEqot, besideKind, displacedRoom = false, false, false, nil, 0

-- Blizzard's Edit Mode owns the native slot while its manager is on screen. The manager can also be hidden and locked
-- without exiting (CheckHideAndLockEditMode), which leaves editModeActive true with no EditMode.Exit: a hidden manager
-- is not editing, and its own show and hide reflow, or the column would stay hidden after the lock.
local managerHooked = false
local function HookEditMode()
	local manager = EditModeManagerFrame
	if managerHooked or not manager then
		return
	end
	managerHooked = true
	manager:HookScript("OnShow", host.MarkDirty)
	manager:HookScript("OnHide", host.MarkDirty)
end

local function Editing()
	local manager = EditModeManagerFrame
	return not not (manager and manager:IsEditModeActive() and manager:IsShown())
end

-- Native methods remain untouched so controller and combat paths retain their secure execution.
local nativeHeader = ObjectiveTrackerFrame.Header --[[@as ForeverNativeTrackerHeader?]]

local function NativeCollapsed()
	return ObjectiveTrackerFrame.isCollapsed == true
end

-- The space under each section that draws.
local GAP = 10

-- Lays every section out from the host's top, each in the room the ones above it left, less the gap under it, so the
-- column never runs past `available`. Returns whether any section drew.
local function LayoutModules(width, available, reserve)
	ns.TrackerOrder.Sort(modules)
	local heights, total = {}, 0
	for index, module in ipairs(modules) do
		module:SetWidth(width)
		module:Update(math.max(0, available - total - GAP))
		local used = module:GetContentsHeight()
		heights[index] = used
		if used > 0 then
			total = total + used + GAP
		end
	end
	local hasSections = total > 0
	local height = hasSections and reserve or 0
	for index, module in ipairs(modules) do
		module:ClearAllPoints()
		module:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -height)
		local used = heights[index]
		if used > 0 then
			height = height + used + GAP
		end
	end
	host:SetHeight(math.max(1, height))
	return hasSections
end
-- Switches the host between attached and detached when the settings or combat state allow, and returns the settings
-- that chose the mode.
local function ApplyAttachment()
	local settings = Settings()
	local desired = settings.attached ~= false
	if attached == nil or not InCombatLockdown() then
		attached = desired
	end
	return settings
end

-- Detached: the private column sits wherever the player dragged it, independent of the native tracker.
local function LayoutDetached(settings)
	host:Show()
	MatchNativeScale()
	local scale = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local screenWidth, screenHeight = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
	local width = math.min(ObjectiveTrackerFrame:GetWidth(), screenWidth)
	host:SetWidth(width)
	if dragging then
		return
	end
	local x, y
	if settings.x and settings.y then
		x, y = settings.x / scale, settings.y / scale
	else
		local list = TrackerEqot.List(host, host.MarkDirty) or TrackerQuestie.List(host, host.MarkDirty)
		x, y = Beside(list or ObjectiveTrackerFrame, width, screenHeight)
	end
	x = math.max(0, math.min(x, math.max(0, screenWidth - width)))
	y = math.min(0, math.max(y, 24 - screenHeight))
	host:ClearAllPoints()
	host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
	-- With no section to show, the column hides entirely, its title too; the next layout with content shows it again.
	if not LayoutModules(width, math.max(24, screenHeight + y - 24), 24) then
		host:Hide()
		return
	end
	y = math.min(0, math.max(y, math.min(host:GetHeight(), screenHeight) - screenHeight))
	host:ClearAllPoints()
	host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
end

-- Attached: the column reads below the native tracker's visible content, measured from its own content region, so the
-- column is the header, the game's quests, then the Forever sections. Only our frames move, and this one placement
-- runs in combat and out, so a fight starting or ending changes nothing on screen. A collapsed All Objectives hides
-- the sections with it.
local function LayoutAttached()
	-- Read the global each time, not once at load: Blizzard_EditMode is load-on-demand, so it may appear later. A
	-- manager hidden while still active is a locked Edit Mode, which owns nothing on screen, so the column shows.
	HookEditMode()
	if Editing() then
		return
	end
	local point = ObjectiveTrackerFrame:GetPoint()
	if not point then
		-- The native frame is between anchors (an Edit Mode or managed-frame transition): hold the column where it is
		-- until the move that follows reflows it.
		return
	end
	if NativeCollapsed() then
		host:Hide()
		return
	end
	host:Show()
	MatchNativeScale()
	local layoutScale = host:GetEffectiveScale()
	local layoutScreenScale = UIParent:GetEffectiveScale()
	-- The user's scale enlarges the column; keep it on screen the way the detached column already is.
	host:SetWidth(math.min(ObjectiveTrackerFrame:GetWidth(), UIParent:GetWidth() * layoutScreenScale / layoutScale))
	host:ClearAllPoints()
	-- The column hangs from the bottom of the native content region (NineSlice, which Blizzard anchors to its last
	-- module), so it follows the quests as they grow or shrink with no reflow of ours. A native tracker with nothing to
	-- show hides itself, and Questie hides it too: then the column takes its slot from the top.
	---@type Frame, FramePoint
	local edge, edgePoint = ObjectiveTrackerFrame, "TOP"
	if ObjectiveTrackerFrame:IsShown() then
		edge, edgePoint = ObjectiveTrackerFrame.NineSlice or ObjectiveTrackerFrame, "BOTTOM"
	end
	host:SetPoint("TOP", edge, edgePoint, 0, 0)
	local contentBottom = edgePoint == "TOP" and edge:GetTop() or edge:GetBottom()
	local layoutMargin = 24 * layoutScreenScale / layoutScale
	contentBottom = (contentBottom or 0) * edge:GetEffectiveScale() / host:GetEffectiveScale()
	-- The sections shrink to the room below the quests: a tall section shows what fits there and never sends the
	-- column elsewhere.
	if LayoutModules(host:GetWidth(), math.max(0, contentBottom - layoutMargin), 0) then
		return
	end
	-- No section fits below at all (quests ending at the bottom of the screen). If there is anything to show, it goes
	-- above the tracker when there is room there, otherwise to the side away from the tracker's anchored edge, so it
	-- stays visible without overlapping the protected frame.
	local screenHeight = (UIParent:GetHeight() or 0) * layoutScreenScale / layoutScale
	if not LayoutModules(host:GetWidth(), math.max(0, screenHeight - layoutMargin), 0) then
		host:Hide()
		return
	end
	local nativePoint, hostPoint = StackPoints(point)
	host:ClearAllPoints()
	local nativeTop = ObjectiveTrackerFrame:GetTop() or 0
	local screenTop = UIParent:GetHeight() or nativeTop
	local nativeScale = ObjectiveTrackerFrame:GetEffectiveScale()
	local room = screenTop * layoutScreenScale - nativeTop * nativeScale
	if room >= math.max(host:GetHeight() or 0, 1) * layoutScale then
		host:SetPoint(hostPoint, ObjectiveTrackerFrame, nativePoint, 0, 0)
	elseif SidePoint(point) == "LEFT" then
		host:SetPoint("TOPLEFT", ObjectiveTrackerFrame, "TOPRIGHT", 0, 0)
	else
		host:SetPoint("TOPRIGHT", ObjectiveTrackerFrame, "TOPLEFT", 0, 0)
	end
	AvoidMinimap(point)
end

-- Attached while another addon's list covers the native slot: the column goes below, above or beside it and the
-- native tracker keeps its slot. Only our frames move, so this runs in combat too; with `list` nil (the addon hid its
-- list in combat) the column holds its place until combat ends.
---@param list ForeverTrackerEqotList|Frame?
---@param kind "eqot"|"questie"?
local function LayoutBesideList(list, kind)
	if Editing() then
		return
	end
	besideList, besideKind = true, kind
	besideEqot, besideQuestie = kind == "eqot", kind == "questie"
	if not list then
		host:SetShown(LayoutModules(host:GetWidth(), displacedRoom, 0))
		return
	end
	local module = kind == "eqot" and TrackerEqot or TrackerQuestie
	host:Show()
	MatchNativeScale()
	local scale = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local screenWidth, screenHeight = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
	local width = math.min(ObjectiveTrackerFrame:GetWidth(), screenWidth)
	host:SetWidth(width)
	displacedRoom = module.Room(list, host)
	if not LayoutModules(width, displacedRoom, 0) then
		host:Hide()
		return
	end
	local besideX = Beside(list, width, screenHeight)
	local places = module.Places(list, host, besideX, screenWidth, screenHeight)
	for index, place in ipairs(places) do
		host:ClearAllPoints()
		host:SetPoint(place[1], UIParent, place[1], place[2], place[3])
		if index == #places or not OverlapsMinimap() then
			return
		end
	end
end

local function Layout()
	queued = false
	if Editing() then
		return
	end
	local settings = ApplyAttachment()
	ApplyBackdrop(settings)
	Grip.Show(not attached)
	-- Lock the host's scale before a list is normalised into it, so a saved user scale is already applied.
	MatchNativeScale()
	if not attached then
		besideList, besideQuestie, besideEqot, besideKind = false, false, false, nil
		LayoutDetached(settings)
		return
	end
	local eqot = TrackerEqot.List(host, host.MarkDirty)
	if eqot then
		LayoutBesideList(eqot, "eqot")
		return
	end
	local questie = TrackerQuestie.List(host, host.MarkDirty)
	if questie then
		LayoutBesideList(questie, "questie")
		return
	end
	-- Both lists are away, so the column holds the place the list it was avoiding gave it until combat ends.
	if besideList and InCombatLockdown() then
		LayoutBesideList(nil, besideKind)
		return
	end
	besideList, besideQuestie, besideEqot, besideKind = false, false, false, nil
	LayoutAttached()
end

function host.MarkDirty(_)
	if ready and not queued then
		queued = true
		C_Timer.After(0, Layout)
	end
end
-- Questie or EQOT hides the native tracker and its header, so a collapsed All Objectives no longer hides the sections.
function host.IsCollapsed(_)
	return attached == true and not besideList and NativeCollapsed()
end
function host:ForceExpand()
	self:MarkDirty()
end

function api.GetSettings()
	return Settings()
end
---@return number
function api.GetScale()
	return Settings().scale or 1
end
-- Only the host scales, so a change applies at the next layout, in combat too.
---@param value number
function api.SetScale(value)
	if type(value) ~= "number" or value ~= value then
		return
	end
	local settings = Settings()
	local scale = math.max(MIN_SCALE, math.min(MAX_SCALE, value))
	if settings.scale == scale then
		return
	end
	settings.scale = scale
	host:MarkDirty()
end
-- The tracker background, from 0 (off) to 1 (opaque as the tooltip draws it). A change only recolours the texture, so
-- it applies at once in combat as well.
---@return number
function api.GetBackdropOpacity()
	return Settings().backdropOpacity
end
---@param value number
function api.SetBackdropOpacity(value)
	if type(value) ~= "number" or value ~= value then
		return
	end
	local settings = Settings()
	local opacity = Opacity(value)
	if settings.backdropOpacity == opacity then
		return
	end
	settings.backdropOpacity = opacity
	ApplyBackdrop(settings)
end
---@return boolean
function api.IsLocked()
	return IsLocked()
end
---@param value boolean
function api.SetLocked(value)
	Settings().locked = not not value
	Grip.SetLabel(value)
end
function api.IsAttachedToQuestTracker()
	return Settings().attached ~= false
end
function api.SetAttached(value)
	value = not not value
	local settings = Settings()
	if settings.attached == value then
		return
	end
	settings.attached = value
	NotifyAttachment(value)
	host:MarkDirty()
end
function api.OnAttachmentChanged(callback)
	attachmentCallbacks[#attachmentCallbacks + 1] = callback
end
function api.SavePosition(x, y)
	if attached or type(x) ~= "number" or type(y) ~= "number" then
		return
	end
	local settings = Settings()
	settings.x, settings.y = x, y
	host:MarkDirty()
end
-- Adventure Guide draws its own context menu because Blizzard_Menu.AcquireMenu can assert in Forever 70009. A consumer
-- that defines one gets it with the same generator shape; the rest keep Blizzard's menu.
---@param owner Frame
---@param generator fun(owner: Frame, root: any)
local function OpenContextMenu(owner, generator)
	if type(ns.ContextMenu) == "function" then
		ns.ContextMenu(owner, generator)
	else
		MenuUtil.CreateContextMenu(owner, generator)
	end
end
-- Every section header answers a right click the same way: the column's own switches, so a player can attach, detach
-- or lock it from whichever section is in front of them. The section's own click runs first and is never replaced;
-- writing a saved setting is safe in combat, and the layout waits for combat's end as ApplyAttachment already does.
---@param module ForeverTrackerModule
local function AddHeaderMenu(module)
	local header = module.Header
	if not header or module.headerMenu then
		return
	end
	module.headerMenu = true
	-- Read through the same keys TrackerLock uses: Adventure Guide's L is constant keyed, the other addons' L answers
	-- the English phrase, and an untranslated line still reads as English.
	local L = ns.L
	local attach = rawget(L, "SETTING_ATTACH_TRACKER") or L["Attach to quest tracker"] or "Attach to quest tracker"
	local lock = rawget(L, "SETTING_LOCK_TRACKER") or L["Lock the tracker"] or "Lock the tracker"
	local background = rawget(L, "SETTING_TRACKER_BACKGROUND") or L["Tracker background"] or "Tracker background"
	local hide = rawget(L, "SETTING_HIDE_SECTION") or L["Hide this section"] or "Hide this section"
	header:EnableMouse(true)
	header:HookScript("OnMouseUp", function(_, button)
		if button ~= "RightButton" then
			return
		end
		OpenContextMenu(module:GetContextMenuParent(), function(_, root)
			root:CreateCheckbox(attach, api.IsAttachedToQuestTracker, function()
				api.SetAttached(not api.IsAttachedToQuestTracker())
			end)
			if api.IsLocked and api.SetLocked then
				root:CreateCheckbox(lock, api.IsLocked, function()
					api.SetLocked(not api.IsLocked())
				end)
			end
			-- Every section's menu offers the same background choices, so no addon has to wire a settings row of its
			-- own. The values are the saved fractions the host draws, and picking one only recolours the texture.
			local backgroundMenu = root:CreateButton(background)
			backgroundMenu:CreateRadio(rawget(_G, "OFF") or "Off", function()
				return api.GetBackdropOpacity() == 0
			end, function()
				api.SetBackdropOpacity(0)
			end)
			for _, percent in ipairs({ 25, 50, 75, 100 }) do
				local value = percent / 100
				backgroundMenu:CreateRadio(percent .. "%", function()
					return api.GetBackdropOpacity() == value
				end, function()
					api.SetBackdropOpacity(value)
				end)
			end
			-- A section with its own show switch offers hiding itself here, and the entry's tooltip names where the
			-- switch lives. Only the addon's own setting is written, so this is safe in combat like the switches above.
			local show = module.show
			if
				type(show) == "table"
				and type(show.get) == "function"
				and type(show.set) == "function"
				and type(show.where) == "string"
			then
				local entry = root:CreateButton(hide, function()
					if show.get() then
						show.set(false)
					end
				end)
				entry:SetTooltip(function(tooltip)
					tooltip:SetText(hide, 1, 1, 1)
					tooltip:AddLine(show.where, nil, nil, nil, true)
				end)
			end
			-- A section may add its own entries after the column's, without the host learning what the section is.
			if type(module.AddHeaderMenuEntries) == "function" then
				module:AddHeaderMenuEntries(root)
			end
		end)
	end)
end
---@param show? ForeverTrackerShowSetting the section's own show switch, when it has one
function api.Attach(module, show)
	---@cast module ForeverTrackerModule
	if show ~= nil then
		module.show = show
	end
	if module.parentContainer == host then
		return
	end
	Mixin(module, Module)
	modules[#modules + 1] = module
	module:SetContainer(host)
	AddHeaderMenu(module)
	host:MarkDirty()
end
function api.IsAttached(module)
	---@cast module ForeverTrackerModule?
	return module ~= nil and module.parentContainer == host
end
-- Combat ending applies an attachment change combat held back. Combat starting changes nothing on screen, so it is no
-- reason to lay the column out again.
host:RegisterEvent("PLAYER_REGEN_ENABLED")
host:RegisterEvent("DISPLAY_SIZE_CHANGED")
host:RegisterEvent("UI_SCALE_CHANGED")
-- Native objective changes and managed-frame transitions can restore the tracker anchor.
-- Observe their events; wrapping its methods taints controller and secure layout paths.
for _, event in ipairs({
	"QUEST_LOG_UPDATE",
	"QUEST_WATCH_UPDATE",
	"QUEST_WATCH_LIST_CHANGED",
	"PLAYER_ALIVE",
	"PLAYER_DEAD",
	"PLAYER_UNGHOST",
	"ZONE_CHANGED_NEW_AREA",
}) do
	host:RegisterEvent(event)
end
host:SetScript("OnEvent", function()
	host:MarkDirty()
end)
ObjectiveTrackerFrame:HookScript("OnSizeChanged", function()
	host:MarkDirty()
end)
-- The game's managed frame layout, Edit Mode and UI addons such as EllesmereUI move the native frame with no event of
-- their own. An addon-owned probe spans from the screen's bottom left corner to the native frame's top left corner, so
-- any move of the native frame resizes the probe and its OnSizeChanged reflows the column.
local probe = CreateFrame("Frame", nil, UIParent)
local probeEnabled = false
local function SetProbeEnabled(enabled)
	if probeEnabled == enabled then
		return
	end
	probeEnabled = enabled
	probe:ClearAllPoints()
	if enabled then
		probe:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		probe:SetPoint("TOPRIGHT", ObjectiveTrackerFrame, "TOPLEFT", 0, 0)
	end
end
probe:SetScript("OnSizeChanged", function()
	if probeEnabled then
		host:MarkDirty()
	end
end)
SetProbeEnabled(not Editing())
-- Collapsing "All Objectives" hides the shared sections too. Mark the host dirty on the click that flips it; the
-- native collapse method itself stays unhooked and untouched, and the native header keeps its parent so its button
-- resolves the native container normally.
if nativeHeader and nativeHeader.MinimizeButton then
	nativeHeader.MinimizeButton:HookScript("OnClick", function()
		host:MarkDirty()
	end)
end
-- Edit Mode restores Blizzard's saved anchor through its public callbacks. Reflow
-- on those events instead of polling the native frame every frame.
local function OnEditModeChanged()
	HookEditMode()
	local editing = Editing()
	SetProbeEnabled(not editing)
	if editing and attached then
		host:Hide()
		-- Hidden frames still participate in anchor dependencies; detach our column too.
		host:ClearAllPoints()
		host:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
	else
		host:Show()
	end
	host:MarkDirty()
end
EventRegistry:RegisterCallback("EditMode.Enter", OnEditModeChanged, host)
EventRegistry:RegisterCallback("EditMode.Exit", OnEditModeChanged, host)
EventRegistry:RegisterCallback("EditMode.SavedLayouts", OnEditModeChanged, host)
-- A developer diagnostic for the tracker stack (/agf tracker). The combat overlap is otherwise invisible headlessly: it
-- prints both frames' anchors, heights and who each is anchored to.
---@return string
function api.Debug()
	-- Raw literals on purpose: this host is shared with the companion addons, whose ns.L has no AGF keys, and
	-- lint_copy only rejects literals passed straight to Print/SetText (this returns a string instead).
	local function point(frame)
		local p = { frame:GetPoint() }
		local relative = p[2] == host and "host" or tostring(p[2])
		return ("%s rel %s %s %.1f,%.1f"):format(
			tostring(p[1]),
			relative,
			tostring(p[3]),
			tonumber(p[4]) or 0,
			tonumber(p[5]) or 0
		)
	end
	local function geometry(frame)
		return ("%.1f,%.1f-%.1f,%.1f s%.2f"):format(
			frame:GetLeft() or -1,
			frame:GetTop() or -1,
			frame:GetRight() or -1,
			frame:GetBottom() or -1,
			frame:GetEffectiveScale()
		)
	end
	local form = "combat=%s shown=%s hostH=%.1f host[%s] g[%s] nativeH=%.1f native[%s] g[%s] uiS%.2f"
	return (form .. " questie=%s eqot=%s"):format(
		tostring(InCombatLockdown()),
		tostring(host:IsShown()),
		host:GetHeight() or -1,
		point(host),
		geometry(host),
		ObjectiveTrackerFrame:GetHeight() or -1,
		point(ObjectiveTrackerFrame),
		geometry(ObjectiveTrackerFrame),
		UIParent:GetEffectiveScale(),
		tostring(besideQuestie),
		tostring(besideEqot)
	)
end

ForeverTrackerHost = api
ns.TrackerHost = api

EventUtil.ContinueAfterAllEvents(function()
	ready = true
	host:MarkDirty()
	TrackerEqot.Await(host.MarkDirty)
	TrackerQuestie.Await(host.MarkDirty)
end, "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED")
