-- Entering and leaving combat must leave the attached column exactly where it was: the native header and quests first,
-- then the Forever sections, same anchors, same height, every section still drawn. In combat the game's managed-frame
-- layout puts the protected native tracker back in its saved slot, and the host may not move it there. Section heights
-- are fractional, as the client's font metrics are, and a section fits a block only when it fits exactly, as
-- Blizzard's ObjectiveTrackerModuleMixin:CanFitBlock does.
local harness = dofile("tests/tracker_host_harness.lua")
local t = harness.new({ headerShown = true, deferReady = true })
local check, drain = t.check, t.drain
local host, native = t.host, t.native
local sections = { t.first, t.second }
-- The slot Edit Mode gave the native tracker, before the host's first layout.
local slot = { unpack(native.point) }

local function Blocks(section, heights)
	section.blocks, section.contents, section.hides = heights, 0, 0
	function section:Update(available)
		self.updates = (self.updates or 0) + 1
		local used = 0
		for _, height in ipairs(self.blocks) do
			if used + height > available then
				break
			end
			used = used + height
		end
		if used == 0 and self.contents > 0 then
			self.hides = self.hides + 1
		end
		self.contents = used
		self:SetShown(used > 0)
	end
	function section:GetContentsHeight()
		return self.contents
	end
	function section:IsTruncated()
		local full = 0
		for _, height in ipairs(self.blocks) do
			full = full + height
		end
		return self.contents < full
	end
end
Blocks(sections[1], { 13.1, 13.1, 13.1, 13.1 })
Blocks(sections[2], { 12.7, 33.1 })
t.ready()
drain()

local function Snapshot()
	local parts =
		{ ("host %s %s h%.4f"):format(table.concat(host.point, " ", 3), tostring(host:IsShown()), host.height) }
	parts[#parts + 1] = "native " .. table.concat(native.point, " ", 3)
	for index, section in ipairs(sections) do
		parts[#parts + 1] = ("section%d y%.4f h%.4f %s"):format(
			index,
			section.point[5],
			section:GetContentsHeight(),
			tostring(section:IsShown())
		)
	end
	return table.concat(parts, " | ")
end
local settled = Snapshot()
check(not sections[1]:IsTruncated() and not sections[2]:IsTruncated(), "both sections draw in full out of combat")

t.setCombat(true)
t.fire("PLAYER_REGEN_DISABLED")
native.point = { unpack(slot) }
t.probe().scripts.OnSizeChanged(t.probe())
drain()
check(Snapshot() == settled, "entering combat leaves the column still: " .. settled .. " became " .. Snapshot())
-- An objective ticking over in combat redraws the sections within the stack's height; unchanged content stays put.
t.fire("QUEST_LOG_UPDATE")
drain()
check(Snapshot() == settled, "a combat redraw keeps every section whole: " .. settled .. " became " .. Snapshot())
t.setCombat(false)
t.fire("PLAYER_REGEN_ENABLED")
drain()
check(Snapshot() == settled, "leaving combat leaves the column still: " .. settled .. " became " .. Snapshot())
check(sections[1].hides + sections[2].hides == 0, "no section blinks out across the combat toggle")
check(native.point[1] == slot[1] and native.point[5] == slot[5], "the native tracker keeps its saved slot")
check(
	host.point[2] == native.NineSlice and host.point[3] == "BOTTOM",
	"the Forever sections read below the native quests"
)

print("tracker_combat_spec: " .. t.checks() .. " checks passed")
