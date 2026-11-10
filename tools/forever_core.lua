-- ForeverCore, the addon every Forever addon requires, loaded the way the client loads it: the files its TOC lists, in
-- order, from the checkout the FOREVER_CORE environment variable names. Local runs default to the sibling checkout
-- ../forever-core; CI checks the ref in tools/forever-core.txt out into forever-core/.
--
--   local core = dofile("tools/forever_core.lua")
--   core.install(_G)                                -- every core file, into the global environment
--   core.install(env, { "Core/OpenSettings.lua" })  -- only the files a spec calls
--
-- With no file list, every file the TOC names loads. Locales/enUS.lua always loads first: its phrases are the keys
-- every core module reads.

local ForeverCore = {}

local function Exists(path)
	local file = io.open(path .. "/ForeverCore.toc", "r")
	if file then
		file:close()
		return true
	end
	return false
end

-- The repository root, from this file's own path, so a spec run from the addon folder finds the same checkout the
-- smoke test run from the root does.
local source = debug.getinfo(1, "S").source:sub(2)
local toolsDirectory = source:match("^(.*)[/\\][^/\\]+$") or "."
local root = toolsDirectory:match("^(.*)[/\\][^/\\]+$") or "."
-- The checkout's usual home is the repository's sibling, whatever the working directory is.
local parent = root .. "/.."

-- The checkout, as FOREVER_CORE names it. A relative path is read from the working directory first, then from the
-- repository root and GITHUB_WORKSPACE, because the specs run from the addon's own folder in CI.
---@return string
function ForeverCore.directory()
	local configured = os.getenv("FOREVER_CORE")
	local candidates = {}
	if configured and configured ~= "" then
		candidates[#candidates + 1] = configured
		if configured:sub(1, 1) ~= "/" then
			candidates[#candidates + 1] = root .. "/" .. configured
			local workspace = os.getenv("GITHUB_WORKSPACE")
			if workspace and workspace ~= "" then
				candidates[#candidates + 1] = workspace .. "/" .. configured
			end
		end
	else
		candidates[#candidates + 1] = parent .. "/forever-core"
	end
	for _, path in ipairs(candidates) do
		local cleaned = path:gsub("/+$", "")
		if cleaned ~= "" and Exists(cleaned) then
			return cleaned
		end
	end
	error(
		"ForeverCore's checkout is not at "
			.. table.concat(candidates, " or ")
			.. "; set FOREVER_CORE to it (tools/forever-core.txt names the ref)"
	)
end

-- The files ForeverCore.toc lists, in its order, with forward slashes for loadfile.
---@param directory string
---@return string[]
function ForeverCore.files(directory)
	local files = {}
	for line in io.lines(directory .. "/ForeverCore.toc") do
		line = line:gsub("\r$", "")
		if not (line:match("^%s*$") or line:match("^%s*#")) then
			files[#files + 1] = line:gsub("\\", "/")
		end
	end
	return files
end

---@param names string[]?
---@return table<string, boolean>
local function Wanted(names)
	local set = { ["Locales/enUS.lua"] = true }
	for _, name in ipairs(names or {}) do
		set[name] = true
	end
	return set
end

-- Load ForeverCore into `ns`, a namespace of its own, and run its chunks in `env`. Returns the namespace.
---@param names string[]? core files to load, in TOC order; every file when nil
---@param ns table
---@param env table
---@return table
function ForeverCore.load(names, ns, env)
	env = env or _G
	local directory = ForeverCore.directory()
	local selected = names and Wanted(names) or nil
	for _, path in ipairs(ForeverCore.files(directory)) do
		if selected == nil or selected[path] then
			-- Core's own quest section needs the full native tracker template; a harness without one skips that
			-- optional section, as core's own api_spec does. A harness with no GetLocale skips the translations after
			-- enUS, whose guard would stop on the missing client call.
			local native = env.ObjectiveTrackerFrame
			local translated = path:match("^Locales/") and path ~= "Locales/enUS.lua"
			if path ~= "UI/TrackerQuests.lua" or native ~= nil then
				if not (translated and type(env.GetLocale) ~= "function") then
					local chunk = assert(loadfile(directory .. "/" .. path), path)
					setfenv(chunk, env)
					chunk("ForeverCore", ns)
				end
			end
			env.ObjectiveTrackerFrame = native
		end
	end
	return ns
end

-- Load ForeverCore into a namespace of its own, in `env`, and return the global its TOC publishes.
---@param env table?
---@param names string[]?
---@return ForeverCoreAPI
function ForeverCore.install(env, names)
	env = env or _G
	local ns = {}
	ForeverCore.load(names, ns, env)
	return assert(env.ForeverCore or _G.ForeverCore, "ForeverCore did not publish its global")
end

return ForeverCore
