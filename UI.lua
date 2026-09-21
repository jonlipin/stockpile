-- Restocker UI: an auction-house style list built from the client's own templates.
-- Every template is tried through pcall with a fallback, and the result is recorded
-- in ns.templateReport so "/stockpile debug" shows what resolved on this client.

local ADDON, ns = ...
local Restocker = ns.Restocker
local UI = {}
ns.UI = UI
ns.templateReport = {}

local ROW_HEIGHT = 24
local FRAME_W, FRAME_H = 820, 520
local ICON = "Interface\\Icons\\INV_Misc_Bag_10"

-- Column x offsets measured from the RIGHT edge of a row, plus widths.
local COL = {
	del    = { x = -26,  w = 24 },
	extras = { x = -114, w = 84 },
	guild  = { x = -164, w = 48 },
	bank   = { x = -214, w = 48 },
	vendor = { x = -278, w = 62 },
	want   = { x = -380, w = 96 },
	inbank = { x = -440, w = 56 },
	have   = { x = -498, w = 54 },
	nameLeft = 52,
	nameRight = -506,
}

local SOURCE_TIPS = {
	vendor = "Buy from any merchant that sells it, up to Want.",
	bank   = "Withdraw from your bank when short. With Extras ticked, deposit the surplus too.",
	guild  = "Withdraw from any guild bank tab you can view when short (respects withdrawal limits). With Extras ticked, deposit the surplus into the tab you have open.",
}

-- ------------------------------------------------------------------
-- Template helpers
-- ------------------------------------------------------------------
local function TryCreateFrame(ftype, name, parent, candidates)
	for _, c in ipairs(candidates) do
		local tmpl, check = c[1], c[2]
		local ok, f = pcall(CreateFrame, ftype, name, parent, tmpl)
		if ok and f and (not check or check(f)) then
			ns.templateReport[tmpl] = "ok"
			return f, tmpl
		end
		ns.templateReport[tmpl] = "missing"
		if ok and f then f:Hide() end
	end
	return CreateFrame(ftype, name, parent), nil
end

local function HasAtlas(atlas)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function SetRowHighlight(tex)
	for _, atlas in ipairs({ "auctionhouse-ui-row-highlight", "search-highlight" }) do
		if HasAtlas(atlas) then
			tex:SetAtlas(atlas)
			ns.templateReport["atlas:" .. atlas] = "ok"
			return
		else
			ns.templateReport["atlas:" .. atlas] = "missing"
		end
	end
	tex:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	tex:SetBlendMode("ADD")
end

-- AH row icons wear a quality-coloured border; use the same atlases when present.
local ICON_BORDER_ATLAS = {
	[0] = "auctionhouse-itemicon-border-gray",   [1] = "auctionhouse-itemicon-border-white",
	[2] = "auctionhouse-itemicon-border-green",  [3] = "auctionhouse-itemicon-border-blue",
	[4] = "auctionhouse-itemicon-border-purple", [5] = "auctionhouse-itemicon-border-orange",
}
local function SetIconBorder(tex, quality)
	local atlas = ICON_BORDER_ATLAS[quality or 1] or ICON_BORDER_ATLAS[1]
	if HasAtlas(atlas) then
		tex:SetAtlas(atlas)
		tex:Show()
		ns.templateReport["atlas:auctionhouse-itemicon-border"] = "ok"
	else
		tex:Hide()
		ns.templateReport["atlas:auctionhouse-itemicon-border"] = "missing"
	end
end

local function SetFrameTitle(f, text)
	if f.SetTitle then f:SetTitle(text)
	elseif f.TitleText then f.TitleText:SetText(text)
	elseif f.TitleContainer and f.TitleContainer.TitleText then f.TitleContainer.TitleText:SetText(text)
	else
		local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		t:SetPoint("TOP", 0, -12)
		t:SetText(text)
	end
end

local function SetFramePortrait(f, icon)
	if f.SetPortraitToAsset then f:SetPortraitToAsset(icon)
	elseif f.portrait and SetPortraitToTexture then SetPortraitToTexture(f.portrait, icon)
	elseif f.PortraitContainer and f.PortraitContainer.portrait then f.PortraitContainer.portrait:SetTexture(icon)
	end
end

local function ShowItemTooltip(owner, itemID)
	if not itemID then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(itemID)
	else
		GameTooltip:SetHyperlink("item:" .. itemID)
	end
	GameTooltip:Show()
end

local function ShowTextTooltip(owner, title, text)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, 1, 1, 1)
	if text then GameTooltip:AddLine(text, nil, nil, nil, true) end
	GameTooltip:Show()
end

-- Add whatever item is on the cursor. Returns true if the drop was consumed.
function UI:HandleCursorDrop()
	local kind, id = GetCursorInfo()
	if kind ~= "item" or not id then return false end
	ClearCursor()
	local ok, err = Restocker:AddItem(id)
	if not ok and err then ns.Print(err) end
	return true
end

local function EnableDrop(f)
	f:EnableMouse(true)
	f:HookScript("OnReceiveDrag", function() UI:HandleCursorDrop() end)
	f:HookScript("OnMouseUp", function() UI:HandleCursorDrop() end)
end

-- ------------------------------------------------------------------
-- Main window
-- ------------------------------------------------------------------
local frame, frameTemplate = TryCreateFrame("Frame", "StockpileFrame", UIParent, {
	{ "ButtonFrameTemplate", function(f) return f.Inset ~= nil end },
	{ "BasicFrameTemplateWithInset", function(f) return f.Inset ~= nil end },
	{ "BackdropTemplate" },
})
UI.frame = frame
frame:SetSize(FRAME_W, FRAME_H)
frame:SetPoint("CENTER")
frame:SetFrameStrata("HIGH")
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() UI:SavePosition() end)
frame:SetScript("OnShow", function() UI:Refresh() end)
frame:SetScript("OnHide", function() GameTooltip:Hide() end)
frame:Hide()
tinsert(UISpecialFrames, "StockpileFrame")
EnableDrop(frame)

SetFrameTitle(frame, "Stockpile")
SetFramePortrait(frame, ICON)

if not frameTemplate or frameTemplate == "BackdropTemplate" then
	-- Bare fallback: give it a dialog border and a close button.
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
end

-- Body: the area inside the inset that holds toolbar, header and list.
local body = CreateFrame("Frame", nil, frame)
local footerInBody = frameTemplate ~= "ButtonFrameTemplate"
if frame.Inset then
	body:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 0, 0)
	body:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", 0, footerInBody and 28 or 0)
else
	body:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -34)
	body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 42)
end
EnableDrop(body)

-- ---- Toolbar ------------------------------------------------------
-- ButtonFrameTemplate leaves a band between the title bar and the inset (the AH puts its search
-- bar there). Use it when we have it; otherwise the toolbar sits inside the list area.
local hasBand = frameTemplate == "ButtonFrameTemplate"
local toolbarParent = hasBand and frame or body
local search = TryCreateFrame("EditBox", "StockpileSearchBox", toolbarParent, {
	{ "SearchBoxTemplate", function(f) return f.Instructions ~= nil or f.searchIcon ~= nil end },
	{ "InputBoxTemplate" },
})
search:SetSize(190, 20)
if hasBand then
	search:SetPoint("TOPLEFT", frame, "TOPLEFT", 72, -33)
else
	search:SetPoint("TOPLEFT", body, "TOPLEFT", 14, -9)
end
search:SetAutoFocus(false)
search:HookScript("OnTextChanged", function() UI:Refresh() end)
search:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
if search.Instructions then search.Instructions:SetText("Search") end

local addLabel = toolbarParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
addLabel:SetPoint("LEFT", search, "RIGHT", 16, 0)
addLabel:SetText("Add by item ID:")

local addBox = CreateFrame("EditBox", "StockpileAddBox", toolbarParent, "InputBoxTemplate")
addBox:SetSize(110, 20)
addBox:SetPoint("LEFT", addLabel, "RIGHT", 10, 0)
addBox:SetAutoFocus(false)

local addButton = CreateFrame("Button", nil, toolbarParent, "UIPanelButtonTemplate")
addButton:SetSize(52, 22)
addButton:SetPoint("LEFT", addBox, "RIGHT", 4, 0)
addButton:SetText("Add")

local function AddFromBox()
	local id = ns.ParseItemInput(addBox:GetText())
	if not id then
		ns.Print("Type an item ID (or paste an item link) in the box first.")
		return
	end
	local ok, err = Restocker:AddItem(id)
	if ok then addBox:SetText("") addBox:ClearFocus() elseif err then ns.Print(err) end
end
addButton:SetScript("OnClick", AddFromBox)
addBox:SetScript("OnEnterPressed", AddFromBox)
addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- ---- Column header ------------------------------------------------
-- Styled after the auction house browse list: raised tab-like header buttons
-- (the WhoFrame column-tab art), label left-aligned, sort arrow right after it.
local HEADER_H = 22
local header = CreateFrame("Frame", nil, body)
header:SetHeight(HEADER_H)
local headerY = hasBand and -3 or -38
header:SetPoint("TOPLEFT", body, "TOPLEFT", 6, headerY)
header:SetPoint("TOPRIGHT", body, "TOPRIGHT", -28, headerY)
EnableDrop(header)

local COLUMN_TABS = "Interface\FriendsFrame\WhoFrame-ColumnTabs"
local function SkinHeaderButton(b)
	b.left = b:CreateTexture(nil, "BACKGROUND")
	b.left:SetTexture(COLUMN_TABS)
	b.left:SetTexCoord(0, 0.078125, 0, 0.75)
	b.left:SetSize(5, HEADER_H)
	b.left:SetPoint("TOPLEFT")
	b.right = b:CreateTexture(nil, "BACKGROUND")
	b.right:SetTexture(COLUMN_TABS)
	b.right:SetTexCoord(0.90625, 0.96875, 0, 0.75)
	b.right:SetSize(4, HEADER_H)
	b.right:SetPoint("TOPRIGHT")
	b.middle = b:CreateTexture(nil, "BACKGROUND")
	b.middle:SetTexture(COLUMN_TABS)
	b.middle:SetTexCoord(0.078125, 0.90625, 0, 0.75)
	b.middle:SetPoint("TOPLEFT", b.left, "TOPRIGHT")
	b.middle:SetPoint("BOTTOMRIGHT", b.right, "BOTTOMLEFT")
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture("Interface\PaperDollInfoFrame\UI-Character-Tab-Highlight")
	hl:SetBlendMode("ADD")
	hl:SetPoint("TOPLEFT", 2, -2)
	hl:SetPoint("BOTTOMRIGHT", -2, 2)
	hl:SetAlpha(0.5)
end

local function SetSortArrow(tex)
	if HasAtlas("auctionhouse-ui-sortarrow") then
		tex:SetAtlas("auctionhouse-ui-sortarrow")
		tex:SetSize(9, 10)
		ns.templateReport["atlas:auctionhouse-ui-sortarrow"] = "ok"
		return true
	end
	ns.templateReport["atlas:auctionhouse-ui-sortarrow"] = "missing"
	tex:SetTexture("Interface\Buttons\UI-SortArrow")
	tex:SetSize(9, 8)
	return false
end

local headerButtons = {}
local function CreateHeaderButton(key, title)
	local b = CreateFrame("Button", nil, header)
	b:SetHeight(HEADER_H)
	SkinHeaderButton(b)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("LEFT", 8, 0)
	b.text:SetJustifyH("LEFT")
	b.text:SetText(title)
	b.arrow = b:CreateTexture(nil, "ARTWORK")
	b.arrowIsAtlas = SetSortArrow(b.arrow)
	b.arrow:SetPoint("LEFT", b.text, "RIGHT", 3, 0)
	b.arrow:Hide()
	b.sortKey = key
	b:SetScript("OnClick", function()
		local s = ns.db.settings
		if s.sortKey == key then s.sortAsc = not s.sortAsc else s.sortKey, s.sortAsc = key, true end
		UI:Refresh()
	end)
	headerButtons[key] = b
	return b
end

local hName = CreateHeaderButton("name", "Item")
hName:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
hName:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", COL.nameRight, 0)
local HEADER_TIPS = {
	vendor = { "Vendor", SOURCE_TIPS.vendor },
	bank   = { "Bank", SOURCE_TIPS.bank },
	guild  = { "Guild bank", SOURCE_TIPS.guild },
	extras = { "Bank extras", "Ticked: when you have more than Want, the surplus is deposited when you open the bank or guild bank.\nNeeds Bank or Guild ticked." },
	inbank = { "In bank", "How many are in your personal bank (updates when you open it)." },
}
local HEADER_ORDER = { "have", "inbank", "want", "vendor", "bank", "guild", "extras" }
local HEADER_TITLES = { have = "Have", inbank = "In bank", want = "Want", vendor = "Vendor", bank = "Bank", guild = "Guild", extras = "Bank extras" }
for i, key in ipairs(HEADER_ORDER) do
	local b = CreateHeaderButton(key, HEADER_TITLES[key])
	b:SetPoint("TOPLEFT", header, "TOPRIGHT", COL[key].x, 0)
	-- Each tab runs up to the start of the next column so the strip has no gaps.
	local nextKey = HEADER_ORDER[i + 1]
	local rightEdge = nextKey and COL[nextKey].x or 0
	b:SetWidth(rightEdge - COL[key].x)
	if HEADER_TIPS[key] then
		b:SetScript("OnEnter", function(self) ShowTextTooltip(self, HEADER_TIPS[key][1], HEADER_TIPS[key][2] .. "\n\nClick to sort.") end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
end

local function UpdateHeaderArrows()
	local s = ns.db.settings
	for key, b in pairs(headerButtons) do
		if key == s.sortKey then
			b.arrow:Show()
			-- Both arrow arts point one way by default; flip vertically for the other direction.
			if b.arrowIsAtlas then
				if s.sortAsc then b.arrow:SetTexCoord(0, 1, 1, 0) else b.arrow:SetTexCoord(0, 1, 0, 1) end
			else
				if s.sortAsc then b.arrow:SetTexCoord(0, 0.5625, 1, 0) else b.arrow:SetTexCoord(0, 0.5625, 0, 1) end
			end
		else
			b.arrow:Hide()
		end
	end
end

-- ---- Scrolling list ---------------------------------------------
local scroll = CreateFrame("ScrollFrame", "StockpileScrollFrame", body, "StockpileScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
-- The AH list sits on a darker backdrop than the marble inset.
local listBg = body:CreateTexture(nil, "BACKGROUND", nil, 1)
listBg:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
listBg:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -26, 4)
listBg:SetColorTexture(0, 0, 0, 0.45)
scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -28, 6)
ns.templateReport["StockpileScrollFrameTemplate(ScrollFrameTemplate)"] = scroll.ScrollBar and "ok" or "no ScrollBar"
EnableDrop(scroll)

local scrollChild = CreateFrame("Frame", nil, scroll)
scrollChild:SetSize(1, 1)
scroll:SetScrollChild(scrollChild)
EnableDrop(scrollChild)

local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
emptyText:SetPoint("TOP", scrollChild, "TOP", 0, -60)
emptyText:SetWidth(400)
emptyText:SetText("Drag an item from your bags here,\nor type its item ID above.")

-- ---- Rows ---------------------------------------------------------
local rows = {}

local function CommitWant(row, value)
	if not row.cfg then return end
	value = math.max(0, math.floor(tonumber(value) or row.cfg.want))
	if value ~= row.cfg.want then
		row.cfg.want = value
		Restocker:RequestRefresh()
	end
end

local function CreateWantInput(row)
	local input, tmpl = TryCreateFrame("EditBox", nil, row, {
		{ "NumericInputSpinnerTemplate", function(f) return f.SetMinMaxValues ~= nil and f.IncrementButton ~= nil end },
		{ "InputBoxTemplate" },
	})
	input:SetAutoFocus(false)
	if tmpl == "NumericInputSpinnerTemplate" then
		input:SetSize(40, 20)
		input:SetMinMaxValues(0, 9999)
		-- The spinner fires its value callback for ANY text change - row recycling,
		-- refreshes, even the UI clearing boxes at logout - and not always synchronously,
		-- which once overwrote saved Wants. So a value is only committed while the player
		-- is demonstrably the one changing it: holding an arrow, or typing in the box.
		-- The edited item is pinned at the start of the interaction so a row that gets
		-- recycled mid-edit can never write into a different item.
		local function BeginEdit() row.editing = true row.editCfg = row.cfg end
		local function EndEdit()
			if row.editing and row.editCfg and row.editCfg == row.cfg then
				CommitWant(row, tonumber(input:GetText()) or input:GetValue())
			end
			row.editing, row.editCfg = false, nil
		end
		input:SetOnValueChangedCallback(function(self, value)
			if row.updating or not row.editing or row.editCfg ~= row.cfg then return end
			CommitWant(row, value)
		end)
		for _, btn in ipairs({ input.IncrementButton, input.DecrementButton }) do
			btn:HookScript("OnMouseDown", BeginEdit)
			btn:HookScript("OnMouseUp", function() C_Timer.After(0, EndEdit) end) -- after the template's own handler
		end
		input:HookScript("OnEditFocusGained", BeginEdit)
		input:HookScript("OnEditFocusLost", EndEdit)
		input:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)
		input:HookScript("OnEscapePressed", function(self)
			row.editing, row.editCfg = false, nil -- discard
			if row.cfg then self:SetWant(row.cfg.want) end
			self:ClearFocus()
		end)
		input.SetWant = function(self, v)
			if row.editing and self:HasFocus() then return end -- don't stomp what the player is typing
			row.updating = true
			self:SetValue(v)
			row.updating = false
		end
	else
		input:SetSize(50, 20)
		input:SetNumeric(true)
		input:SetMaxLetters(4)
		input:SetJustifyH("CENTER")
		-- Same rule as the spinner: only commit what the player typed, into the item they were editing.
		input:SetScript("OnEditFocusGained", function() row.editCfg = row.cfg end)
		input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
		input:SetScript("OnEditFocusLost", function(self)
			if row.editCfg and row.editCfg == row.cfg and self:GetText() ~= "" then CommitWant(row, self:GetText()) end
			row.editCfg = nil
		end)
		input:SetScript("OnEscapePressed", function(self) row.editCfg = nil if row.cfg then self:SetText(tostring(row.cfg.want)) end self:ClearFocus() end)
		input.SetWant = function(self, v) if not self:HasFocus() then self:SetText(tostring(v)) end end
	end
	return input
end

local function CreateRow(index)
	local row = CreateFrame("Button", nil, scrollChild)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	row.stripe:SetColorTexture(1, 1, 1, 0.03)
	if index % 2 == 1 then row.stripe:Hide() end

	-- The AH highlight atlas is opaque, so it must sit UNDER the icon and text
	-- (BACKGROUND sublayer 1, above the stripe) and be toggled by hover rather
	-- than living in the HIGHLIGHT layer, which draws on top of everything.
	row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.hover:SetAllPoints()
	SetRowHighlight(row.hover)
	row.hover:Hide()

	-- Child controls (spinner, buttons) steal mouse focus from the row, so every
	-- part re-checks whether the pointer is still somewhere over the row.
	local function UpdateHover()
		if row:IsMouseOver() then row.hover:Show() else row.hover:Hide() end
	end
	row.UpdateHover = UpdateHover

	row.check = TryCreateFrame("CheckButton", nil, row, {
		{ "UICheckButtonTemplate" },
		{ "ChatConfigCheckButtonTemplate" },
	})
	row.check:SetSize(20, 20)
	row.check:SetPoint("LEFT", row, "LEFT", 4, 0)
	local ct = row.check.text or row.check.Text
	if ct then ct:SetText("") end
	row.check:SetScript("OnClick", function(self)
		if row.cfg then row.cfg.enabled = self:GetChecked() and true or false end
		UI:Refresh()
	end)
	row.check:SetScript("OnEnter", function(self) ShowTextTooltip(self, "Enabled", "Untick to keep the item on the list without restocking it.") end)
	row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- The AH frames each row icon in a quality-coloured border whose art is a ROUNDED
	-- frame with a transparent margin. So the border is the fixed 20x20 box, the icon
	-- sits well inside it, and a round mask clips the icon's corners so they can never
	-- poke out past the frame, whatever the exact proportions of the art.
	row.iconBorder = row:CreateTexture(nil, "OVERLAY")
	row.iconBorder:SetSize(20, 20)
	row.iconBorder:SetPoint("LEFT", row, "LEFT", 28, 0)
	row.iconBorder:Hide()

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(14, 14)
	row.icon:SetPoint("CENTER", row.iconBorder, "CENTER", 0, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	if row.CreateMaskTexture then
		local ok = pcall(function()
			local mask = row:CreateMaskTexture()
			mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -1, 1)
			mask:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
			row.icon:AddMaskTexture(mask)
		end)
		ns.templateReport["icon mask"] = ok and "ok" or "failed"
	else
		ns.templateReport["icon mask"] = "unsupported"
	end

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", row, "LEFT", COL.nameLeft, 0)
	row.name:SetPoint("RIGHT", row, "RIGHT", COL.nameRight, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	row.have = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	-- Values sit left-aligned under left-aligned headers, as in the AH list.
	row.have:SetPoint("LEFT", row, "RIGHT", COL.have.x + 8, 0)
	row.have:SetWidth(COL.have.w - 8)
	row.have:SetJustifyH("LEFT")

	row.bank = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	row.bank:SetPoint("LEFT", row, "RIGHT", COL.inbank.x + 8, 0)
	row.bank:SetWidth(COL.inbank.w - 8)
	row.bank:SetJustifyH("LEFT")

	row.want = CreateWantInput(row)
	row.want:SetPoint("CENTER", row, "RIGHT", COL.want.x + 46, 0)

	-- One checkbox per source, plus Extras. All are plain flags on the item config.
	local function MakeFlagBox(colKey, title, tooltip)
		local cb = TryCreateFrame("CheckButton", nil, row, {
			{ "UICheckButtonTemplate" },
			{ "ChatConfigCheckButtonTemplate" },
		})
		cb:SetSize(20, 20)
		cb:SetPoint("LEFT", row, "RIGHT", COL[colKey].x + 6, 0)
		local t = cb.text or cb.Text
		if t then t:SetText("") end
		cb:SetScript("OnEnter", function(self) ShowTextTooltip(self, title, type(tooltip) == "function" and tooltip() or tooltip) end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return cb
	end

	row.src = {}
	for _, s in ipairs(ns.SOURCES) do
		local key = s.key
		local cb = MakeFlagBox(key, s.label, SOURCE_TIPS[key])
		cb:SetScript("OnClick", function(self)
			if not row.cfg then return end
			row.cfg[key] = self:GetChecked() and true or false
			row:UpdateExtras()
			if ns.db.settings.sortKey == key then UI:Refresh() end
		end)
		row.src[key] = cb
	end

	-- Extras: deposit the surplus. Only meaningful when a bank-type source is ticked.
	row.extras = MakeFlagBox("extras", "Bank extras", function()
		if row.cfg and not ns.HasStorageSource(row.cfg) then
			return "Tick Bank or Guild first."
		end
		return "When you have more than Want, deposit the surplus into the bank (or guild bank) when you open it."
	end)
	row.extras:SetScript("OnClick", function(self)
		if row.cfg then row.cfg.deposit = self:GetChecked() and true or false end
	end)
	function row:UpdateExtras()
		if not self.cfg then return end
		local usable = ns.HasStorageSource(self.cfg) and true or false
		self.extras:SetChecked(usable and self.cfg.deposit)
		self.extras:SetEnabled(usable)
		self.extras:SetAlpha(usable and 1 or 0.35)
	end

	row.del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
	row.del:SetSize(22, 22)
	row.del:SetPoint("LEFT", row, "RIGHT", COL.del.x, 0)
	row.del:SetScript("OnClick", function()
		if row.itemID then Restocker:RemoveItem(row.itemID) end
	end)
	row.del:SetScript("OnEnter", function(self) ShowTextTooltip(self, "Remove from list") end)
	row.del:SetScript("OnLeave", function() GameTooltip:Hide() end)

	row:SetScript("OnEnter", function(self) UpdateHover() ShowItemTooltip(self, self.itemID) end)
	row:SetScript("OnLeave", function() UpdateHover() GameTooltip:Hide() end)
	for _, child in ipairs({ row.check, row.want, row.src.vendor, row.src.bank, row.src.guild, row.extras, row.del }) do
		if child.HookScript then
			child:HookScript("OnEnter", UpdateHover)
			child:HookScript("OnLeave", UpdateHover)
		end
	end
	if row.want.IncrementButton then row.want.IncrementButton:HookScript("OnEnter", UpdateHover) row.want.IncrementButton:HookScript("OnLeave", UpdateHover) end
	if row.want.DecrementButton then row.want.DecrementButton:HookScript("OnEnter", UpdateHover) row.want.DecrementButton:HookScript("OnLeave", UpdateHover) end
	row:SetScript("OnReceiveDrag", function() UI:HandleCursorDrop() end)
	row:SetScript("OnClick", function(self, button)
		if UI:HandleCursorDrop() then return end
		if button == "LeftButton" and IsModifiedClick and IsModifiedClick("CHATLINK") and self.link then
			ChatEdit_InsertLink(self.link)
		end
	end)
	return row
end

local function GetRow(index)
	if not rows[index] then rows[index] = CreateRow(index) end
	return rows[index]
end

local function SortList(list)
	local s = ns.db.settings
	local key, asc = s.sortKey, s.sortAsc
	table.sort(list, function(a, b)
		local av, bv
		if key == "have" then av, bv = a.have, b.have
		elseif key == "inbank" then av, bv = a.bank, b.bank
		elseif key == "want" then av, bv = a.cfg.want, b.cfg.want
		elseif key == "vendor" or key == "bank" or key == "guild" then av, bv = a.cfg[key] and 1 or 0, b.cfg[key] and 1 or 0
		elseif key == "extras" then av, bv = a.cfg.deposit and 1 or 0, b.cfg.deposit and 1 or 0
		else av, bv = a.name:lower(), b.name:lower()
		end
		if av == bv then return a.name:lower() < b.name:lower() end
		if asc then return av < bv else return av > bv end
	end)
end

-- ---- Footer -------------------------------------------------------
local footer = CreateFrame("Frame", nil, frame)
footer:SetHeight(24)
if footerInBody then
	footer:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 6, -26)
	footer:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -6, -26)
else
	footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 4)
	footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 4)
end

local countText = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
countText:SetPoint("LEFT", footer, "LEFT", 4, 0)

local function CreateToggle(anchor, x, label, settingKey, tooltip)
	local cb = TryCreateFrame("CheckButton", nil, footer, {
		{ "UICheckButtonTemplate" },
		{ "ChatConfigCheckButtonTemplate" },
	})
	cb:SetSize(22, 22)
	cb:SetPoint("LEFT", anchor, "RIGHT", x, 0)
	local ct = cb.text or cb.Text
	if ct then ct:SetText("") end
	cb.label = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	cb.label:SetPoint("LEFT", cb, "RIGHT", 0, 0)
	cb.label:SetText(label)
	cb:SetScript("OnClick", function(self) ns.db.settings[settingKey] = self:GetChecked() and true or false end)
	cb:SetScript("OnEnter", function(self) ShowTextTooltip(self, label, tooltip) end)
	cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	cb.settingKey = settingKey
	return cb
end

local toggles = {}
toggles[1] = CreateToggle(countText, 24, "Auto vendor", "autoVendor", "Buy automatically whenever you open a merchant.")
toggles[2] = CreateToggle(toggles[1].label, 12, "Auto bank", "autoBank", "Move items automatically whenever you open your bank.")
toggles[3] = CreateToggle(toggles[2].label, 12, "Auto guild", "autoGuild", "Move items automatically whenever you open the guild bank.")
toggles[4] = CreateToggle(toggles[3].label, 12, "Chat", "announce", "Print a summary in chat after restocking.")

-- Gold reserve: "never spend below this much at vendors".
local RESERVE_TIP = "When ticked, vendor buying never takes you below this amount.\nIf you already have less, nothing is bought at all.\nBank and guild bank moves are not affected."
toggles[5] = CreateToggle(toggles[4].label, 12, "Keep", "reserveEnabled", RESERVE_TIP)

local function CreateCoinBox(anchor, x, width, maxLetters, iconFile, tipTitle)
	local box = CreateFrame("EditBox", nil, footer, "InputBoxTemplate")
	box:SetSize(width, 18)
	box:SetPoint("LEFT", anchor, "RIGHT", x, 0)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(maxLetters)
	-- InputBoxTemplate draws its left cap 5px OUTSIDE the frame and its right cap inside,
	-- so the visible box is [-5, width]. Centre the text and inset the right side by the
	-- same 5px so the digits sit in the middle of what the player actually sees.
	box:SetJustifyH("CENTER")
	box:SetTextInsets(0, 5, 0, 0)
	box:SetFontObject("GameFontHighlightSmall")
	box.coin = footer:CreateTexture(nil, "ARTWORK")
	box.coin:SetSize(13, 13)
	box.coin:SetTexture(iconFile)
	box.coin:SetPoint("LEFT", box, "RIGHT", 3, 0)
	box:SetScript("OnEnter", function(self) ShowTextTooltip(self, tipTitle, RESERVE_TIP) end)
	box:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return box
end
-- x offsets include the 5px the left cap sticks out, so the gaps look even.
local reserveGold   = CreateCoinBox(toggles[5].label, 12, 48, 6, "Interface\\MoneyFrame\\UI-GoldIcon", "Gold to keep")
local reserveSilver = CreateCoinBox(reserveGold.coin, 12, 30, 2, "Interface\\MoneyFrame\\UI-SilverIcon", "Silver to keep")

local function CommitReserve()
	if not ns.db then return end
	local g = tonumber(reserveGold:GetText()) or 0
	local s = math.min(99, tonumber(reserveSilver:GetText()) or 0)
	ns.db.settings.reserveCopper = g * 10000 + s * 100
end
local function ShowReserve()
	if not ns.db then return end
	local copper = tonumber(ns.db.settings.reserveCopper) or 0
	if not reserveGold:HasFocus() then reserveGold:SetText(tostring(math.floor(copper / 10000))) end
	if not reserveSilver:HasFocus() then reserveSilver:SetText(tostring(math.floor(copper % 10000 / 100))) end
	local on = ns.db.settings.reserveEnabled and true or false
	for _, box in ipairs({ reserveGold, reserveSilver }) do
		box:SetAlpha(on and 1 or 0.45)
		box.coin:SetAlpha(on and 1 or 0.45)
	end
end
for _, box in ipairs({ reserveGold, reserveSilver }) do
	box:SetScript("OnEnterPressed", function(self) CommitReserve() self:ClearFocus() end)
	-- Escape clears focus too, so flag it: focus-lost must not commit a discarded edit.
	box:SetScript("OnEditFocusLost", function(self)
		if self.discard then self.discard = nil else CommitReserve() end
		ShowReserve()
	end)
	box:SetScript("OnEscapePressed", function(self) self.discard = true self:ClearFocus() end)
	box:SetScript("OnTabPressed", function(self) CommitReserve() if self == reserveGold then reserveSilver:SetFocus() else reserveGold:SetFocus() end end)
end
toggles[5]:HookScript("OnClick", function() ShowReserve() end)

local nowButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
nowButton:SetSize(110, 22)
nowButton:SetPoint("RIGHT", footer, "RIGHT", -2, 0)
nowButton:SetText("Restock now")
nowButton:SetScript("OnClick", function() Restocker:RunOpen(true) end)
nowButton:SetScript("OnEnter", function(self)
	ShowTextTooltip(self, "Restock now", "Runs a restock pass against whatever is open: a merchant, your bank, or the guild bank.")
end)
nowButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ------------------------------------------------------------------
-- Refresh
-- ------------------------------------------------------------------
function UI:Refresh()
	if not ns.db or not frame:IsShown() then return end
	local s = ns.db.settings

	local query = (search:GetText() or ""):lower()
	if search.Instructions and query == search.Instructions:GetText():lower() then query = "" end
	local list, total = {}, 0
	for id, cfg in pairs(ns.db.items) do
		total = total + 1
		local name, link, quality, icon = ns.GetItemDisplay(id)
		if not name then ns.RequestItemLoad(id) end
		local display = name or ("Item " .. id)
		if query == "" or display:lower():find(query, 1, true) then
			list[#list + 1] = {
				id = id, cfg = cfg, name = display, loaded = name ~= nil, link = link,
				quality = quality, icon = icon, have = ns.GetHave(id), bank = ns.GetBankCount(id),
			}
		end
	end
	SortList(list)
	UpdateHeaderArrows()

	local width = scroll:GetWidth()
	if not width or width < 100 then width = FRAME_W - 70 end
	scrollChild:SetWidth(width)

	for i, entry in ipairs(list) do
		local row = GetRow(i)
		row.itemID, row.cfg, row.link = entry.id, entry.cfg, entry.link
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)

		row.check:SetChecked(entry.cfg.enabled)
		row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		SetIconBorder(row.iconBorder, entry.quality)
		row.name:SetText(entry.name)
		if entry.loaded then
			row.name:SetTextColor(ns.GetQualityColor(entry.quality))
		else
			row.name:SetTextColor(0.6, 0.6, 0.6)
		end

		row.have:SetText(entry.have)
		if not entry.cfg.enabled then row.have:SetTextColor(0.5, 0.5, 0.5)
		elseif entry.have >= entry.cfg.want then row.have:SetTextColor(0.4, 1, 0.4)
		else row.have:SetTextColor(1, 0.45, 0.45) end
		row.bank:SetText(entry.bank > 0 and tostring(entry.bank) or "-")

		row.want:SetWant(entry.cfg.want)
		for _, s in ipairs(ns.SOURCES) do row.src[s.key]:SetChecked(entry.cfg[s.key] and true or false) end
		row:UpdateExtras()
		row:SetAlpha(entry.cfg.enabled and 1 or 0.55)
		row:Show()
	end
	for i = #list + 1, #rows do
		rows[i]:Hide()
		rows[i].itemID, rows[i].cfg, rows[i].link = nil, nil, nil
	end
	scrollChild:SetHeight(math.max(#list * ROW_HEIGHT, 1))

	if total == 0 then emptyText:Show() else emptyText:Hide() end
	if total == 0 then
		countText:SetText("No items yet")
	elseif #list ~= total then
		countText:SetText(string.format("%d of %d items", #list, total))
	else
		countText:SetText(string.format("%d item%s", total, total == 1 and "" or "s"))
	end
	for _, cb in ipairs(toggles) do cb:SetChecked(s[cb.settingKey]) end
	ShowReserve()
	nowButton:SetEnabled(Restocker.merchantOpen or Restocker.bankOpen or Restocker.guildOpen)
end

-- ------------------------------------------------------------------
-- Window management
-- ------------------------------------------------------------------
function UI:Toggle()
	if frame:IsShown() then frame:Hide() else frame:Show() end
end
function UI:Show() frame:Show() end

function UI:SavePosition()
	local point, _, relPoint, x, y = frame:GetPoint(1)
	if point then ns.db.settings.pos = { point, relPoint, x, y } end
end

function UI:RestorePosition()
	local p = ns.db.settings.pos
	if p and p[1] then
		frame:ClearAllPoints()
		frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
	end
end

-- ------------------------------------------------------------------
-- "Restock" button on the merchant and bank windows
-- ------------------------------------------------------------------
local function AttachButton(parentName, key, onClick)
	local parent = _G[parentName]
	if not parent or UI[key] then return end
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(96, 22)
	b:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -8, 2)
	b:SetText("Restock")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self) ShowTextTooltip(self, "Stockpile", "Run a restock pass now. Right-click to open the list.") end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	UI[key] = b
end

function UI:OnMerchantShow()
	AttachButton("MerchantFrame", "merchantButton", function(_, button)
		if button == "RightButton" then UI:Toggle() else Restocker:RunVendor(true) end
	end)
end

function UI:OnBankShow()
	AttachButton("BankFrame", "bankButton", function(_, button)
		if button == "RightButton" then UI:Toggle() else Restocker:RunBank(true) end
	end)
end

function UI:OnGuildBankShow()
	AttachButton("GuildBankFrame", "guildButton", function(_, button)
		if button == "RightButton" then UI:Toggle() else Restocker:RunGuild(true) end
	end)
end

-- ------------------------------------------------------------------
-- Minimap button
-- ------------------------------------------------------------------
local mm = CreateFrame("Button", "StockpileMinimapButton", Minimap)
mm:SetSize(32, 32)
mm:SetFrameStrata("MEDIUM")
mm:SetFrameLevel(8)
mm:SetMovable(true)
mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mm:RegisterForDrag("LeftButton")
mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local mmBg = mm:CreateTexture(nil, "BACKGROUND")
mmBg:SetSize(20, 20)
mmBg:SetPoint("CENTER", 0, 1)
mmBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

local mmIcon = mm:CreateTexture(nil, "ARTWORK")
mmIcon:SetSize(19, 19)
mmIcon:SetPoint("CENTER", 0, 1)
mmIcon:SetTexture(ICON)
mmIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local mmBorder = mm:CreateTexture(nil, "OVERLAY")
mmBorder:SetSize(54, 54)
mmBorder:SetPoint("TOPLEFT", 0, 0)
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function MinimapPosition()
	local angle = math.rad(ns.db.settings.minimapAngle or 220)
	local radius = (Minimap:GetWidth() / 2) + 6
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

mm:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		cx, cy = cx / scale, cy / scale
		ns.db.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
		MinimapPosition()
	end)
end)
mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mm:SetScript("OnClick", function(_, button)
	if button == "RightButton" then
		Restocker:RunOpen(true)
	else
		UI:Toggle()
	end
end)
mm:SetScript("OnEnter", function(self)
	ShowTextTooltip(self, "Stockpile", "Left-click: open the list\nRight-click: restock now\nDrag to move")
end)
mm:SetScript("OnLeave", function() GameTooltip:Hide() end)

function UI:UpdateMinimapButton()
	if ns.db.settings.minimapHide then mm:Hide() else mm:Show() MinimapPosition() end
end

-- ------------------------------------------------------------------
function UI:OnDBReady()
	ns.templateReport["frame"] = frameTemplate or "plain"
	self:RestorePosition()
	self:UpdateMinimapButton()
	self:Refresh()
end
