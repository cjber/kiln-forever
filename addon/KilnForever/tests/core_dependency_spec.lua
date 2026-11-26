-- Run from the addon root: luajit tests/core_dependency_spec.lua
-- Kiln Forever requires ForeverCore. The game already refuses to load the addon when ForeverCore is absent; an installed
-- one that cannot serve it gets one on-screen line, and the addon's entry points stay quiet.
local function Login(loader)
	local lines, frame = {}, nil
	local env = {
		C_AddOns = { GetAddOnMetadata = function() return "dev" end },
		CreateFrame = function()
			frame = {
				RegisterEvent = function() end,
				HookScript = function() end,
				SetScript = function(self, _, handler) self.handler = handler end,
			}
			return frame
		end,
		UIErrorsFrame = { AddMessage = function(_, text) lines[#lines + 1] = text end },
		ForeverCoreLoader = loader,
		SlashCmdList = {},
	}
	env._G = env
	setmetatable(env, { __index = _G })
	local addon = {}
	for _, file in ipairs({ "Core/Init.lua", "Core/Slash.lua" }) do
		setfenv(assert(loadfile(file)), env)("KilnForever", addon)
	end
	frame.handler(frame, "PLAYER_LOGIN")
	frame.handler(frame, "PLAYER_ENTERING_WORLD", true)
	env.SlashCmdList.KILNFOREVER("")
	env.KilnForever_OnAddonCompartmentClick("KilnForever", "LeftButton")
	env.KilnForever_Binding("toggle")
	return addon, lines
end

local failedBoot = { OnReady = function(callback) callback(nil) end }
for name, loader in pairs({ ["no loader"] = false, ["a loader that failed to boot"] = failedBoot }) do
	local addon, lines = Login(loader or nil)
	assert(addon.core == nil and addon.db == nil, name .. " starts nothing")
	assert(#lines == 1 and lines[1]:find("ForeverCore", 1, true), name .. " names ForeverCore in one error line")
end

print("core_dependency_spec: ok")
