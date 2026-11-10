local _, ns = ...

-- The game refuses to load this addon when ForeverCore is absent (## Dependencies), but an older ForeverCore still
-- loads. Its API version says whether it has everything this addon calls, so an out-of-date one stops the addon's own
-- files here with one line on screen, never a chat message.
if ForeverCore == nil or (ForeverCore.API or 0) < 1 then
	ns.broken = true
	local errors = rawget(_G, "UIErrorsFrame")
	if errors then
		errors:AddMessage("Kiln Forever needs ForeverCore, which is missing or too old.", 1, 0.1, 0.1)
	end
end
