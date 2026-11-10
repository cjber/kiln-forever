local _, ns = ...

-- The client's own restricted settings opener, run with secure execution taint. CreateSecureDelegate wraps a Lua
-- function so a call from addon code runs as the client, not as the addon. C_SettingsUtil.OpenSettingsPanel is a
-- HasRestrictions function: called directly from addon code, the client refuses it and blames the addon
-- (cjber/adventure-guide-forever#411, cjber/forever-core#333). The delegate is created once, on first use, so a spec
-- without the client's delegate never runs it at load.
local secureOpenSettingsPanel

-- CreateSecureDelegate is absent on some Forever builds (cjber/adventure-guide-forever#592), and the C function is
-- itself refused from addon-tainted code: without the delegate there is no secure way to open it, so we leave it
-- closed rather than error or taint the client's fields. False when nothing was opened.
---@param categoryID? integer
---@param element? string
---@return boolean
function ns.OpenSettingsPanel(categoryID, element)
	if InCombatLockdown() then
		return false
	end
	if not secureOpenSettingsPanel then
		local open = C_SettingsUtil and C_SettingsUtil.OpenSettingsPanel
		if type(CreateSecureDelegate) ~= "function" or type(open) ~= "function" then
			return false
		end
		secureOpenSettingsPanel = CreateSecureDelegate(open)
	end
	secureOpenSettingsPanel(categoryID, element)
	return true
end
