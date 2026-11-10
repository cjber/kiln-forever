-- Art at its native aspect (AGENTS.md, WFA-27). Every atlas is sized from C_Texture.GetAtlasInfo: an icon fits
-- inside its box and stays centred, a file icon is square, and only the client's own frames stretch row backgrounds,
-- dropdown chrome and one-pixel dividers. Nothing outside this file sets a texture or an atlas by hand.

local _, ns = ...

if ns.broken then
	return
end

---@class KilnArt
local Art = {}
ns.Art = Art

-- The atlas's width over its height; square when the client does not know it.
---@param atlas string
---@return number
local function Aspect(atlas)
	local info = C_Texture.GetAtlasInfo(atlas)
	if info and info.width > 0 and info.height > 0 then
		return info.width / info.height
	end
	return 1
end

-- `atlas` at the largest size inside `width` by `height`, at its own aspect. The caller anchors the texture.
---@param texture Texture
---@param atlas string
---@param width number
---@param height number
---@return number width
---@return number height
function Art.Fit(texture, atlas, width, height)
	texture:SetAtlas(atlas)
	local aspect = Aspect(atlas)
	local w, h = width, width / aspect
	if h > height then
		w, h = height * aspect, height
	end
	texture:SetSize(w, h)
	return w, h
end

-- A file icon, square as every one is, `size` across and whole. A texture that drew an atlas first loses its crop.
---@param texture Texture
---@param file string|integer
---@param size number
function Art.Icon(texture, file, size)
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetTexture(file)
	texture:SetSize(size, size)
end

-- `|A:atlas:height:width|a`, with the width from the atlas's aspect, for a line of text.
---@param atlas string
---@param height number
---@return string
function Art.Markup(atlas, height)
	return ("|A:%s:%d:%d|a"):format(atlas, height, math.floor(height * Aspect(atlas) + 0.5))
end

-- A button's hover glow: `atlas` fitted in `width` by `height` and added over the button.
---@param button Button
---@param atlas string
---@param width number
---@param height number
---@return Texture
function Art.Highlight(button, atlas, width, height)
	local glow = button:CreateTexture(nil, "HIGHLIGHT")
	Art.Fit(glow, atlas, width, height)
	glow:SetPoint("CENTER")
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0.35)
	return glow
end

-- A row or dropdown surface the client itself stretches to the width of its list. It carries no fixed shape of its
-- own, so following the host's frame is the native use.
---@param texture Texture
---@param atlas string
function Art.Background(texture, atlas)
	texture:SetAtlas(atlas)
end

-- An atlas drawn at the size the client gives it, for small state marks such as the list's plus and minus.
---@param texture Texture
---@param atlas string
function Art.Native(texture, atlas)
	texture:SetAtlas(atlas, true)
end

-- A coloured status dot, the round highlight the client uses for small marks.
---@param texture Texture
---@param r number
---@param g number
---@param b number
---@param size number
function Art.Dot(texture, r, g, b, size)
	Art.Fit(texture, "common-roundhighlight", size, size)
	texture:SetVertexColor(r, g, b)
end

-- A checkbox check mark in an option row, faded while the option is not chosen.
---@param texture Texture
---@param checked boolean
---@param size number
function Art.Check(texture, checked, size)
	Art.Fit(texture, "common-icon-checkmark", size, size)
	texture:SetAlpha(checked and 1 or 0.2)
end
