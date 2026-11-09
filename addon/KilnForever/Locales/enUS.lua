-- The phrases Forever Core's shared UI draws. English is the key, so an empty translation table reads as English.
local ns = select(2, ...)

---@type table<string, string>
local L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
ns.L = L

L["Forever tracker"] = "Forever tracker"
L["Drag to move"] = "Drag to move"
L["The tracker is locked. Turn off Lock the tracker to move it."] =
	"The tracker is locked. Turn off Lock the tracker to move it."
L["Attach to quest tracker"] = "Attach to quest tracker"
L["Lock the tracker"] = "Lock the tracker"
L["Tracker background"] = "Tracker background"
L["Hide this section"] = "Hide this section"
L.MINIMAP_UNAVAILABLE = "Minimap unavailable; skipping custom button."

-- The shared report window.
L["Report a bug or request a feature"] = "Report a bug or request a feature"
L["Bug"] = "Bug"
L["Feature request"] = "Feature request"
L["Bug: "] = "Bug: "
L["Feature request: "] = "Feature request: "
L["Title"] = "Title"
L["What happened, or what you would like"] = "What happened, or what you would like"
L["Copy issue link"] = "Copy issue link"
L["Copy report"] = "Copy report"
L["The text is selected. Press Ctrl+C (Cmd+C on a Mac) to copy it, then paste it into your bug report."] =
	"The text is selected. Press Ctrl+C (Cmd+C on a Mac) to copy it, then paste it into your bug report."
L["The link is selected. Press Ctrl+C (Cmd+C on a Mac), then paste into a browser; GitHub opens a filled-in issue."] =
	"The link is selected. Press Ctrl+C (Cmd+C on a Mac), then paste into a browser; GitHub opens a filled-in issue."

-- The shared debug log.
L["Debug log is off."] = "Debug log is off."
L["Debug log is on for this session."] = "Debug log is on for this session."
L["Debug log is on and pinned for this character."] = "Debug log is on and pinned for this character."
L["Debug log is already on and pinned for this character."] = "Debug log is already on and pinned for this character."
L["Debug log is off for this session; it is still pinned."] = "Debug log is off for this session; it is still pinned."
L["Debug log is off and unpinned."] = "Debug log is off and unpinned."
L["No addon has attached its log yet."] = "No addon has attached its log yet."
L["%s (last %d):"] = "%s (last %d):"
L["%s: no lines yet."] = "%s: no lines yet."
L["Usage: /forever debug, /forever debug pin, /forever debug off, /forever debug show"] =
	"Usage: /forever debug, /forever debug pin, /forever debug off, /forever debug show"
