-- The optional tracker backdrop (cjber/forever-core#241): one texture behind the whole shared column, drawn with the
-- game's own tooltip background art, off at opacity 0, and stored in the tracker settings the host already owns. The
-- saved opacity is the texture's alpha, so moving it only recolours the texture and works in combat.
local harness = dofile("tests/tracker_host_harness.lua")
local t = harness.new({})
local check = t.check
local host = t.ns.TrackerHost
local backdrop = t.textures[1]
local function near(a, b)
	return math.abs((a or -1) - b) < 1e-9
end

-- A fresh player gets the switch off, and the texture is already there but hidden.
check(backdrop ~= nil, "the host builds the optional backdrop")
check(backdrop.atlas == "Tooltip-NineSlice-Center", "the backdrop uses the game's tooltip background art")
check(#backdrop.points == 2, "the backdrop spans the column's two corners")
check(backdrop.points[1][5] == 0, "the backdrop stops at the column's top, clear of the native quests")
check(backdrop.points[2][5] == -6, "the backdrop pads the column's bottom")
check(backdrop.shown == false, "a fresh tracker draws no backdrop")
check(host.GetBackdropOpacity() == 0, "the backdrop opacity starts at 0")
check(t.hostSettings.backdropOpacity == 0, "a fresh tracker settings table saves the backdrop as off")

-- The slider writes the saved value, which is the texture's own alpha. The tint is the tooltip's colour.
t.env.TOOLTIP_DEFAULT_BACKGROUND_COLOR = {
	GetRGB = function()
		return 0.2, 0.3, 0.4
	end,
}
host.SetBackdropOpacity(0.5)
check(host.GetBackdropOpacity() == 0.5, "the opacity reads back from the saved settings")
check(t.hostSettings.backdropOpacity == 0.5, "the slider writes the host's saved table")
check(backdrop.shown == true, "a value above 0 shows the backdrop")
check(near(backdrop.a, 0.5), "the texture's alpha is the saved opacity")
check(near(backdrop.r, 0.2) and near(backdrop.g, 0.3) and near(backdrop.b, 0.4), "the tooltip colour tints the art")

-- Broken and out-of-range values are repaired the way the host repairs a saved scale.
host.SetBackdropOpacity(2)
check(host.GetBackdropOpacity() == 1 and near(backdrop.a, 1), "an opacity above 1 clamps to 1")
host.SetBackdropOpacity(-1)
check(host.GetBackdropOpacity() == 0 and backdrop.shown == false, "an opacity at or below 0 turns the backdrop off")
host.SetBackdropOpacity(0 / 0)
check(host.GetBackdropOpacity() == 0, "a not-a-number opacity leaves the saved value alone")
host.SetBackdropOpacity("loud")
check(host.GetBackdropOpacity() == 0, "a value that is not a number leaves the saved value alone")

-- Changing the switch writes no frame, so it is safe where the player is fighting.
host.SetBackdropOpacity(0.75)
local point, height = host.point, host.height
t.setCombat(true)
host.SetBackdropOpacity(0.25)
check(host.point == point and host.height == height, "moving the slider in combat moves no frame")
t.setCombat(false)
check(host.GetBackdropOpacity() == 0.25, "the opacity changes in combat")

-- A saved value applies on the first layout, clamped the same way.
local saved = harness.new({ hostSettings = { attached = true, backdropOpacity = 4 } })
check(saved.textures[1].shown == true, "a saved backdrop appears on the first layout")
check(near(saved.textures[1].a, 1), "a saved opacity above 1 clamps on layout")

print("tracker_backdrop_spec: " .. t.checks() .. " checks passed")
