-- The latest snapshot from the bridge, plus derived views of it.

local _, ns = ...

local Store = {
	data = { threads = {}, projects = {}, bridge = {} },
	byId = {},
	projectsById = {},
	applied = 0,
}
ns.Store = Store

local GROUP_OF = {
	working = "working", input = "working", plan = "working",
	open = "open", failed = "open",
	settled = "settled",
}
Store.GROUP_OF = GROUP_OF

function Store:Apply(data)
	data.threads = data.threads or {}
	data.projects = data.projects or {}
	data.bridge = data.bridge or {}
	local before = self.byId
	local byId, projectsById = {}, {}
	for _, t in ipairs(data.threads) do byId[t.id] = t end
	for _, p in ipairs(data.projects) do projectsById[p.id] = p end
	self.data, self.byId, self.projectsById = data, byId, projectsById
	self.applied = self.applied + 1

	if self.applied > 1 then
		for id, t in pairs(byId) do
			local old = before[id]
			if old and old.s ~= t.s then
				ns:Fire("ThreadTransition", t, old.s, t.s)
			elseif not old and (t.s == "working" or t.s == "input") then
				ns:Fire("ThreadTransition", t, nil, t.s)
			end
		end
	end
	ns:Fire("DataChanged")
	if data.view and data.view.id == ns.viewId then ns:Fire("ViewChanged") end
end

function Store:Thread(id)
	return id and self.byId[id]
end

function Store:ProjectName(id)
	local p = id and self.projectsById[id]
	return p and p.name or ""
end

-- Threads grouped for the sidebar, filtered by project.
-- projectFilter: "all" or a project id.
function Store:Groups(projectFilter, query)
	local groups = { working = {}, open = {}, settled = {} }
	for _, t in ipairs(self.data.threads) do
		local match = projectFilter == "all" or projectFilter == nil or t.p == projectFilter
		if match and query and query ~= "" then
			match = t.title:lower():find(query, 1, true) or self:ProjectName(t.p):lower():find(query, 1, true)
		end
		if match then
			local g = GROUP_OF[t.s] or "open"
			table.insert(groups[g], t)
		end
	end
	return groups
end

function Store:Active()
	local list = {}
	for _, t in ipairs(self.data.threads) do
		if t.s == "working" or t.s == "input" or t.s == "plan" then table.insert(list, t) end
	end
	return list
end

function Store:View()
	local v = self.data.view
	if v and v.id == ns.viewId then return v end
end

---------------------------------------------------------------------------
-- Status words and colors

local STATUS_TEXT = {
	working = "Working", input = "Waiting", plan = "Plan ready",
	open = "Finished", failed = "Failed", settled = "Settled",
}
local STATUS_COLOR = {
	working = "blue", input = "orange", plan = "orange",
	open = "white", failed = "red", settled = "grey",
}

function Store.StatusText(s)
	return STATUS_TEXT[s] or s or ""
end

function Store.StatusColor(s)
	return STATUS_COLOR[s] or "white"
end

---------------------------------------------------------------------------
-- Plain text for places that need to match against what a message says.

function ns.StripMarkup(text)
	text = tostring(text or "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "|")
	return text
end
