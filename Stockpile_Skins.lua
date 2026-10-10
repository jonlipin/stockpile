-- Stockpile's pieces in the window styles. Styles.lua does the choosing and the drawing
-- (Blizzard, Dark, or EllesmereUI's look); this file says what Stockpile has to restyle.

local ADDON, ns = ...
local Styles = ns.Styles
local Try = Styles.Try

local function S() return Styles.S end

local function Fonts(...)
	for i = 1, select("#", ...) do
		local fs = select(i, ...)
		if type(fs) == "table" and fs.GetFont then S().Font(fs) end
	end
end

-- state: the label grays out while the button is disabled (Restock now, with nothing open).
local function SkinButton(button, state)
	if type(button) ~= "table" then return end
	S().Button(button)
	if state then S().StateButtonLabel(button) else S().WhiteButtonLabel(button) end
	if button.GetFontString then Fonts(button:GetFontString()) end
end

-- A border a style lays over a window sits above its children; a corner button goes back on top,
-- but no higher than its own window.
local function Raise(button, parent)
	local level = parent:GetFrameLevel() or 1
	for _, child in ipairs({ parent:GetChildren() }) do
		if child ~= button then level = math.max(level, child:GetFrameLevel() or 0) end
	end
	button:SetFrameLevel(level + 5)
end

-- ---- the main window ----------------------------------------------------------------------------

local function SkinWindow(P)
	local frame = P.frame
	-- The footer sits in the window's bottom band, under the list, when the window has one.
	S().Shell(frame, { bottomBar = P.hasBand and 26 or nil })
	-- EllesmereUI takes the round portrait off the game's windows it dresses, and so does this;
	-- the search box moves into the room it leaves.
	local portraits = frame.PortraitContainer
	if type(portraits) == "table" then
		S().FadeRegions(portraits)
		if type(portraits.portrait) == "table" then portraits.portrait:SetAlpha(0) end
	end
	if type(frame.portrait) == "table" and frame.portrait.SetAlpha then frame.portrait:SetAlpha(0) end
	if P.hasBand then
		P.search:ClearAllPoints()
		P.search:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -33)
	end
	if type(frame.Inset) == "table" then S().Inset(frame.Inset) end
	if type(frame.CloseButton) == "table" then
		S().CloseButton(frame.CloseButton)
		Raise(frame.CloseButton, frame)
	end

	-- The toolbar.
	S().EditBox(P.search)
	-- The magnifier is part of the search box's art, but it says what the box is for.
	if type(P.search.searchIcon) == "table" then P.search.searchIcon:SetAlpha(1) end
	S().EditBox(P.addBox)
	SkinButton(P.addButton)
	SkinButton(P.lookButton)
	Fonts(P.addLabel, P.emptyText)

	-- The column headers, as the sort header bar of a list. The bar fades every texture on the
	-- headers, the sort arrow too, but it says which column the list is sorted by, so it comes back.
	P.body.HeaderContainer = P.header
	S().SortHeaderBar(P.body)
	for _, b in pairs(P.headerButtons) do
		b.arrow:SetAlpha(1)
		Fonts(b.text)
	end
	if type(P.scroll.ScrollBar) == "table" then S().ScrollBar(P.scroll.ScrollBar) end

	-- The footer.
	for _, cb in ipairs(P.toggles) do
		S().Checkbox(cb)
		Fonts(cb.label)
	end
	for _, box in ipairs(P.reserveBoxes) do S().EditBox(box) end
	SkinButton(P.nowButton, true)
	Fonts(P.countText)
end

-- The Look panel. Its slider has no drawing call in either style, so it stays as the game draws it;
-- the opacity label and value change font objects with the style, so they keep the game's fonts.
local function SkinLook(look)
	S().Shell(look)
	S().CloseButton(look.close)
	Raise(look.close, look)
	SkinButton(look.styleButton)
	Fonts(look.note)
end

-- ---- pieces built later, as they are needed -----------------------------------------------------

function ns.SkinRow(row)
	if not S() or row.skinned then return end
	row.skinned = true
	Try("list row", function()
		S().Checkbox(row.check)
		for _, cb in pairs(row.src) do S().Checkbox(cb) end
		S().Checkbox(row.extras)
		S().EditBox(row.want)
		S().CloseButton(row.del)
		-- A flat hover in place of the auction house's highlight.
		row.hover:SetTexCoord(0, 1, 0, 1)
		row.hover:SetColorTexture(1, 1, 1, 0.06)
		-- A square icon cannot be cropped through the round mask, so the mask goes first. The rounded
		-- quality border goes too; a thin edge in the item's quality color takes its place.
		if row.iconMask and row.icon.RemoveMaskTexture then pcall(row.icon.RemoveMaskTexture, row.icon, row.iconMask) end
		row.iconBorder:SetAlpha(0)
		row.icon:SetSize(18, 18)
		S().SquareIcon(row.icon)
		row.qualityEdge = Styles.Outline(row, row.icon, "OVERLAY", 1, 1, 1, 1, 1)
		Fonts(row.name, row.have, row.bank)
	end)
end

-- Every refresh, as the row is given an item.
function ns.SkinRowQuality(row, quality)
	if not row.qualityEdge then return end
	local r, g, b = ns.GetQualityColor(quality)
	for _, line in ipairs(row.qualityEdge) do line:SetColorTexture(r, g, b, 1) end
end

-- The Restock button on the merchant, bank and guild bank windows sits on the game's own window,
-- so it follows that window: EllesmereUI dresses those windows, Dark leaves them as the game draws them.
function ns.SkinAttached(button)
	if not S() or Styles.Applied() ~= "eui" then return end
	Try("restock button", function() SkinButton(button) end)
end

-- ---- everything that exists when a style is applied ---------------------------------------------

local function SkinAll()
	local P = ns.UI and ns.UI.parts
	if not P then return end
	Try("window", function() SkinWindow(P) end)
	Try("look panel", function() SkinLook(P.look) end)
	for _, row in pairs(P.rows) do ns.SkinRow(row) end
	for _, key in ipairs({ "merchantButton", "bankButton", "guildButton" }) do
		if ns.UI[key] then ns.SkinAttached(ns.UI[key]) end
	end
end

Styles.Setup({
	addon = ADDON,
	title = "Stockpile",
	db = function() return ns.db and ns.db.settings end,
	report = ns.templateReport,
	accent = { 0, 0.8, 1 }, -- the blue of Stockpile's name in chat
	skin = SkinAll,
})
