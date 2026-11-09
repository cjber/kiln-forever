---@meta

-- The tracker contract's classes, declared once here and vendored to every addon that ships the shared
-- UI/Tracker*.lua files, so a new setting or host method is declared in one place instead of a hand copy per addon.

---@class ForeverTrackerSettings
---@field attached boolean the column follows the native quest tracker
---@field locked? boolean the Lock switch, which suppresses the grip's drag
---@field scale? number the player's tracker scale, 0.5 to 2; the host reads a missing one as 1
---@field backdropOpacity? number the optional backdrop's opacity, 0 (off) to 1
---@field x? number the detached position, from UIParent's top left corner
---@field y? number

---@class ForeverTrackerGrip
---@field Show fun(value: boolean) shows or hides the grip, which the host keeps hidden while attached
---@field SetLabel fun(value: boolean) redraws the label from the switch, without waiting for a hover

---@class ForeverTrackerShowSetting
---@field get fun(): boolean whether the section is currently shown
---@field set fun(shown: boolean) the addon's own switch, which hides the section as its settings checkbox does
---@field where string the place the player turns it back on, in the addon's own words

---@class ForeverTrackerHostAPI
---@field Attach fun(module: Frame, show?: ForeverTrackerShowSetting) the section's optional show switch, offered as Hide this section
---@field IsAttached fun(module: Frame?): boolean
---@field GetSettings fun(): ForeverTrackerSettings
---@field GetScale fun(): number
---@field SetScale fun(value: number)
---@field GetBackdropOpacity fun(): number
---@field SetBackdropOpacity fun(value: number)
---@field IsLocked fun(): boolean
---@field SetLocked fun(value: boolean)
---@field IsAttachedToQuestTracker fun(): boolean
---@field SetAttached fun(value: boolean)
---@field OnAttachmentChanged fun(callback: fun(attached: boolean))
---@field SavePosition fun(x: number, y: number)
---@field Debug fun(): string the tracker stack's anchors, heights and in-combat state, for an addon's debug command

---@class ForeverTrackerOrderAPI
---@field Sort fun(modules: ForeverTrackerModule[]) orders the shared column's sections in place

---@class ForeverTrackerLock
---@field Locked fun(): boolean reads the saved switch through the host
---@field Grip fun(host: Frame, source: ForeverTrackerHostAPI): ForeverTrackerGrip draws the grip on the column it drags

---@class ForeverTrackerNamespace
---@field TrackerHost? ForeverTrackerHostAPI
---@field TrackerLock? ForeverTrackerLock
---@field TrackerOrder? ForeverTrackerOrderAPI
---@field TrackerQuestie? ForeverTrackerQuestie
---@field TrackerEqot? ForeverTrackerEqot
---@field TrackerHostSettings? fun(): ForeverTrackerSettings
---@field L table<string, string>
---@field ContextMenu? fun(owner: Frame, generator: fun(owner: Frame, root: any)): any

---@type ForeverTrackerHostAPI?
ForeverTrackerHost = nil
