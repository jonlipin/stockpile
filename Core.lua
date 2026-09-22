-- Stockpile: keep your bags topped up from vendors, your bank and the guild bank.
-- Core.lua holds the data model, the restock logic and events.
-- UI.lua builds the window and registers itself as ns.UI.

local ADDON, ns = ...

local Restocker = CreateFrame("Frame")
ns.Restocker = Restocker
ns.PREFIX = "|cff00ccffStockpile|r: "

-- ------------------------------------------------------------------
-- API compat: this client exposes the modern C_* namespaces; keep the
-- old globals as a fallback so nothing here hard-crashes on a rename.
-- ------------------------------------------------------------------
local GetItemInfo              = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant       = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemCount             = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemQualityColor      = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
local GetContainerNumSlots     = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetContainerNumFreeSlots = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
local PickupContainerItem      = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
local SplitContainerItem       = (C_Container and C_Container.SplitContainerItem) or SplitContainerItem

-- Normalise GetContainerItemInfo to the modern table form.
local function GetSlotInfo(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		return C_Container.GetContainerItemInfo(bag, slot)
	end
	local texture, count, locked, quality, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
	if not texture then return nil end
	return { iconFileID = texture, stackCount = count, isLocked = locked, quality = quality, hyperlink = link, itemID = itemID }
end
ns.GetSlotInfo = GetSlotInfo

-- Merchant item info: this client uses C_MerchantFrame.GetItemInfo (a table); older ones the flat globals.
local function GetMerchantInfo(idx)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(idx)
		if not info then return nil end
		return info.name, info.texture, info.price, info.stackCount, info.numAvailable, info.isPurchasable
	elseif GetMerchantItemInfo then
		return GetMerchantItemInfo(idx)
	end
	return nil
end

local function FormatMoney(copper)
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then return C_CurrencyInfo.GetCoinTextureString(copper) end
	if GetCoinTextureString then return GetCoinTextureString(copper) end
	return tostring(copper) .. "c"
end

function ns.Print(msg) print(ns.PREFIX .. msg) end
local Print = ns.Print

local function Announce(msg)
	if ns.db and ns.db.settings.announce then Print(msg) end
end

-- ------------------------------------------------------------------
-- Saved data
-- ------------------------------------------------------------------
local DEFAULT_SETTINGS = {
	announce = true,
	autoVendor = true,
	autoBank = true,
	autoGuild = true,
	reserveEnabled = false,
	reserveCopper = 0,
	sortKey = "name",
	sortAsc = true,
	minimapAngle = 220,
	minimapHide = false,
}

-- Per-item sources are independent flags: cfg.vendor, cfg.bank, cfg.guild.
ns.SOURCES = {
	{ key = "vendor", label = "Vendor",     short = "Vendor" },
	{ key = "bank",   label = "Bank",       short = "Bank" },
	{ key = "guild",  label = "Guild bank", short = "Guild" },
}

function ns.SourceLabel(cfg)
	local parts = {}
	for _, s in ipairs(ns.SOURCES) do if cfg[s.key] then parts[#parts + 1] = s.short end end
	if #parts == 0 then return "|cffff6060None|r" end
	return table.concat(parts, ", ")
end

function ns.SourceOrder(cfg)
	return (cfg.vendor and 1 or 0) + (cfg.bank and 2 or 0) + (cfg.guild and 4 or 0)
end

-- Bank-type sources are where Extras can be deposited.
function ns.HasStorageSource(cfg) return cfg.bank or cfg.guild end

-- ------------------------------------------------------------------
-- Account-wide mirror.
-- The per-character save once came back empty after a cold client start even
-- though a valid file was on disk. So every character's list is mirrored into
-- an account-wide saved variable (a different file in a different folder), and
-- each load is journalled so a repeat can be diagnosed from /stockpile debug.
-- ------------------------------------------------------------------
local function CharKey()
	local name = UnitName and UnitName("player") or "?"
	-- GetNormalizedRealmName() is nil early in login, so it yields a different key
	-- at different times; GetRealmName() is stable.
	local realm = (GetRealmName and GetRealmName()) or "?"
	return tostring(name) .. "-" .. tostring(realm)
end

local function CopyItems(items)
	local out = {}
	for id, cfg in pairs(items) do
		if type(cfg) == "table" then
			local c = {}
			for k, v in pairs(cfg) do c[k] = v end
			out[id] = c
		end
	end
	return out
end

local function CountItems(items)
	local n = 0
	for _ in pairs(items or {}) do n = n + 1 end
	return n
end

-- Called after every deliberate change to the list and at logout, so the mirror
-- always reflects what the player meant - including a deliberately emptied list.
function ns.SyncMirror()
	if not ns.db then return end
	local stamp = time and time() or 0
	if StockpileAccountDB and StockpileAccountDB.chars then
		StockpileAccountDB.chars[CharKey()] = { items = CopyItems(ns.db.items), savedAt = stamp }
	end
end


local function InitDB(when)
	local fresh = (StockpileDB == nil)
	StockpileAccountDB = StockpileAccountDB or {}
	StockpileAccountDB.chars = StockpileAccountDB.chars or {}
	StockpileAccountDB.journal = StockpileAccountDB.journal or {}

	StockpileDB = StockpileDB or {}
	StockpileDB.items = StockpileDB.items or {}

	-- A brand-new per-character table while the mirror remembers a list for this
	-- character means the character save did not load: put the list back.
	local key = CharKey()
	local mirror = StockpileAccountDB.chars[key]
	local restored = 0
	if fresh and mirror and CountItems(mirror.items) > 0 then
		StockpileDB.items = CopyItems(mirror.items)
		restored = CountItems(StockpileDB.items)
		ns.restoredFromMirror = restored
	end
	local journal = StockpileAccountDB.journal
	journal[#journal + 1] = string.format("%s %s @%s fresh=%s items=%d restored=%d",
		date and date("%m-%d %H:%M:%S") or "?", key, tostring(when or "?"), tostring(fresh), CountItems(StockpileDB.items), restored)
	while #journal > 12 do table.remove(journal, 1) end

	StockpileDB.settings = StockpileDB.settings or {}
	for k, v in pairs(DEFAULT_SETTINGS) do
		if StockpileDB.settings[k] == nil then StockpileDB.settings[k] = v end
	end
	-- Sanitise item entries so a bad save can never break the list.
	for id, cfg in pairs(StockpileDB.items) do
		if type(cfg) ~= "table" or type(id) ~= "number" then
			StockpileDB.items[id] = nil
		else
			cfg.want = tonumber(cfg.want) or 20
			if cfg.enabled == nil then cfg.enabled = true end
			if cfg.deposit == nil then cfg.deposit = false end
			-- Migrate the old single "source" string to flags.
			if cfg.source then
				cfg.vendor = (cfg.source == "vendor" or cfg.source == "both")
				cfg.bank   = (cfg.source == "bank" or cfg.source == "both")
				cfg.guild  = false
				cfg.source = nil
			end
			if cfg.vendor == nil then cfg.vendor = true end
			if cfg.bank == nil then cfg.bank = false end
			if cfg.guild == nil then cfg.guild = false end
		end
	end
	ns.db = StockpileDB
	ns.dbFresh = fresh and restored == 0
	ns.SyncMirror()
	if restored > 0 then
		C_Timer.After(4, function()
			Print(string.format("|cffffd100your character save did not load, so I restored %d item%s from the account backup.|r Run /stockpile debug if this keeps happening.", restored, restored == 1 and "" or "s"))
		end)
	end
end

-- ------------------------------------------------------------------
-- Item helpers
-- ------------------------------------------------------------------
function ns.GetItemDisplay(itemID)
	local name, link, quality = GetItemInfo(itemID)
	local _, _, _, _, icon = GetItemInfoInstant(itemID)
	return name, link, quality, icon
end

function ns.GetQualityColor(quality)
	if quality and GetItemQualityColor then
		local r, g, b = GetItemQualityColor(quality)
		if r then return r, g, b end
	end
	return 1, 1, 1
end

local requested = {}
function ns.RequestItemLoad(itemID)
	if requested[itemID] then return end
	requested[itemID] = true
	if Item and Item.CreateFromItemID then
		local item = Item:CreateFromItemID(itemID)
		if not item:IsItemEmpty() then
			item:ContinueOnItemLoad(function() Restocker:RequestRefresh() end)
		end
	else
		GetItemInfo(itemID) -- triggers a server query; GET_ITEM_INFO_RECEIVED refreshes
	end
end

local function MaxStackOf(itemID)
	local _, _, _, _, _, _, _, maxStack = GetItemInfo(itemID)
	return maxStack or 1
end

function ns.GetHave(itemID) return GetItemCount(itemID) or 0 end

-- Accepts an item ID, an item link, or a string containing one.
function ns.ParseItemInput(text)
	if type(text) == "number" then return text end
	if type(text) ~= "string" then return nil end
	return tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
end

function Restocker:AddItem(itemID)
	itemID = tonumber(itemID)
	if not itemID or itemID <= 0 or not GetItemInfoInstant(itemID) then
		return false, "That is not a valid item."
	end
	if ns.db.items[itemID] then
		return false, "That item is already on the list."
	end
	local _, _, _, _, _, _, _, stackCount = GetItemInfo(itemID)
	ns.db.items[itemID] = {
		want = (stackCount and stackCount > 0) and stackCount or 20,
		vendor = true, bank = false, guild = false,
		enabled = true,
		deposit = false,
	}
	ns.RequestItemLoad(itemID)
	ns.SyncMirror()
	self:RequestRefresh()
	return true
end

function Restocker:RemoveItem(itemID)
	ns.db.items[itemID] = nil
	ns.SyncMirror()
	self:RequestRefresh()
end

-- Debounced UI refresh so a burst of bag events only redraws once.
local refreshPending = false
function Restocker:RequestRefresh()
	if refreshPending then return end
	refreshPending = true
	C_Timer.After(0.05, function()
		refreshPending = false
		if ns.UI then ns.UI:Refresh() end
	end)
end

-- ------------------------------------------------------------------
-- Vendor restock
-- ------------------------------------------------------------------
Restocker.merchantOpen = false
Restocker.bankOpen = false
Restocker.guildOpen = false

function Restocker:RunVendor(manual)
	if not self.merchantOpen then
		if manual then Print("Open a vendor first.") end
		return
	end
	local numItems = GetMerchantNumItems() or 0
	local onSale = {}
	for i = 1, numItems do
		local id = GetMerchantItemID(i)
		if id then onSale[id] = i end
	end

	-- Units: BuyMerchantItem's quantity and GetMerchantItemMaxStack are in ITEMS.
	-- The merchant's price is for a bundle of `bundle` items (vendors sell food in 5s),
	-- so the per-item price is price / bundle.
	-- Gold reserve: when enabled, that much money is simply not available for buying.
	-- Below the reserve nothing is bought; above it, buying stops at the reserve.
	local reserve = 0
	if ns.db.settings.reserveEnabled then reserve = math.max(0, tonumber(ns.db.settings.reserveCopper) or 0) end
	local budget = GetMoney() - reserve
	local shortNote = reserve > 0 and "gold reserve reached" or "short on gold"

	local spent, plan = 0, {}
	for itemID, cfg in pairs(ns.db.items) do
		local idx = onSale[itemID]
		if idx and cfg.enabled and cfg.vendor then
			local have = ns.GetHave(itemID)
			local need = cfg.want - have
			if need > 0 then
				local name, _, price, bundle, numAvailable, isPurchasable = GetMerchantInfo(idx)
				if name and isPurchasable ~= false then
					bundle = (bundle and bundle > 0) and bundle or 1
					local unitPrice = (price or 0) / bundle
					local qty = need
					if numAvailable and numAvailable >= 0 then qty = math.min(qty, numAvailable * bundle) end
					local maxPerCall = GetMerchantItemMaxStack and GetMerchantItemMaxStack(idx) or 0
					if not maxPerCall or maxPerCall < 1 then maxPerCall = bundle end
					local asked, short = 0, false
					while qty > 0 do
						local n = math.min(qty, maxPerCall)
						if unitPrice > 0 then
							local affordable = math.floor((budget - spent) / unitPrice)
							if affordable <= 0 then short = true break end
							if n > affordable then n, short = affordable, true end
						end
						BuyMerchantItem(idx, n)
						spent = spent + unitPrice * n
						asked = asked + n
						qty = qty - n
						if short then break end
					end
					if asked > 0 or short then
						plan[#plan + 1] = { itemID = itemID, name = name, have = have, asked = asked, short = short }
					end
				end
			end
		end
	end

	if #plan == 0 then
		if manual then Print("Nothing to buy here.") end
		return
	end

	-- Nothing was bought at all because of the reserve: say so plainly, right away.
	if spent == 0 and reserve > 0 then
		local names = {}
		for _, p in ipairs(plan) do names[#names + 1] = p.name end
		Announce(string.format("|cffffd100not buying|r %s - you have %s and your gold reserve is %s.",
			table.concat(names, ", "), FormatMoney(GetMoney()), FormatMoney(reserve)))
		return
	end

	-- Report once the server has delivered, using what actually arrived in the bags.
	C_Timer.After(1.0, function()
		local lines = {}
		for _, p in ipairs(plan) do
			local got = math.max(0, ns.GetHave(p.itemID) - p.have)
			local text
			if got > 0 then
				text = string.format("%dx %s", got, p.name)
			else
				text = string.format("|cffff6060no %s|r", p.name)
			end
			if p.short then
				text = text .. " |cffff6060(" .. shortNote .. ")|r"
			elseif got < p.asked then
				text = text .. string.format(" |cffff6060(asked for %d)|r", p.asked)
			end
			lines[#lines + 1] = text
		end
		Announce(string.format("bought %s for about %s.", table.concat(lines, ", "), FormatMoney(math.floor(spent + 0.5))))
	end)
end

-- ------------------------------------------------------------------
-- Stores: bags, bank, guild bank.
-- Every store answers the same questions so one mover serves all of
-- them. Locations are plain tables; the store knows how to read them.
--   Stacks(itemID)            -> { {loc, count}, ... } (unlocked only)
--   Pickup(loc, n)            -> put n items (or the whole stack) on the cursor
--   FindDropTarget(itemID, n) -> loc that can take n items, or nil
--   Drop(loc)                 -> drop the cursor onto loc
-- Moves are always Pickup on one store then Drop on another.
-- ------------------------------------------------------------------
local function ContainerStacks(containers, itemID)
	local out = {}
	for _, bag in ipairs(containers) do
		for slot = 1, GetContainerNumSlots(bag) do
			local info = GetSlotInfo(bag, slot)
			if info and info.itemID == itemID and not info.isLocked then
				out[#out + 1] = { loc = { bag = bag, slot = slot }, count = info.stackCount or 1 }
			end
		end
	end
	return out
end

-- `exclude` is a set of container keys (see LocKey) that refused a drop earlier.
local function ContainerDropTarget(containers, itemID, n, exclude)
	local maxStack = MaxStackOf(itemID)
	for _, bag in ipairs(containers) do
		if not exclude["bag:" .. bag] then
			for slot = 1, GetContainerNumSlots(bag) do
				local info = GetSlotInfo(bag, slot)
				if info and info.itemID == itemID and not info.isLocked and (info.stackCount or 1) + n <= maxStack then
					return { bag = bag, slot = slot }
				end
			end
		end
	end
	for _, bag in ipairs(containers) do
		if not exclude["bag:" .. bag] then
			local free, family = GetContainerNumFreeSlots(bag)
			if free and free > 0 and (family or 0) == 0 then
				for slot = 1, GetContainerNumSlots(bag) do
					if not GetSlotInfo(bag, slot) then return { bag = bag, slot = slot } end
				end
			end
		end
	end
	return nil
end

local function MakeContainerStore(name, listContainers)
	return {
		name = name,
		Stacks = function(_, itemID) return ContainerStacks(listContainers(), itemID) end,
		Pickup = function(_, loc, n, count)
			if n and n < count then SplitContainerItem(loc.bag, loc.slot, n) else PickupContainerItem(loc.bag, loc.slot) end
		end,
		FindDropTarget = function(_, itemID, n, exclude) return ContainerDropTarget(listContainers(), itemID, n, exclude) end,
		Drop = function(_, loc) PickupContainerItem(loc.bag, loc.slot) end,
		-- An empty slot in the same store, preferring the same bag as `near`.
		FindEmptySlotNear = function(_, near)
			local order = { near.bag }
			for _, bag in ipairs(listContainers()) do if bag ~= near.bag then order[#order + 1] = bag end end
			for _, bag in ipairs(order) do
				local free, family = GetContainerNumFreeSlots(bag)
				if free and free > 0 and (family or 0) == 0 then
					for slot = 1, GetContainerNumSlots(bag) do
						if not GetSlotInfo(bag, slot) then return { bag = bag, slot = slot } end
					end
				end
			end
			return nil
		end,
		-- count, locked at a location (count 0 when empty)
		StateAt = function(_, loc)
			local info = GetSlotInfo(loc.bag, loc.slot)
			if not info then return 0, false end
			return info.stackCount or 1, info.isLocked and true or false
		end,
		LocKey = function(_, loc) return "bag:" .. loc.bag end,
		LocText = function(_, loc) return string.format("bag %d slot %d", loc.bag, loc.slot) end,
		Ready = function() return true end,
	}
end

local function BagContainers()
	local list = {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do list[#list + 1] = bag end
	return list
end

-- Bank storage container ids. Two layouts exist:
--  * retail-style tabs: Enum.BagIndex.CharacterBankTab_1..6. When any of these has
--    slots, they are the ONLY real bank storage - the legacy main-bank id (-1) still
--    reports slots on this client but refuses every drop ("Couldn't split those items").
--  * classic: main bank (-1) plus purchased bank bags (5..11).
local function BankContainers()
	local out = {}
	if Enum and Enum.BagIndex then
		for i = 1, 6 do
			local b = Enum.BagIndex["CharacterBankTab_" .. i]
			if b and (GetContainerNumSlots(b) or 0) > 0 then out[#out + 1] = b end
		end
		if #out > 0 then return out end
	end
	local main = (Enum and Enum.BagIndex and Enum.BagIndex.Bank) or BANK_CONTAINER or -1
	local list = { main }
	local first = (NUM_BAG_SLOTS or 4) + 1
	for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do list[#list + 1] = bag end
	for _, bag in ipairs(list) do
		if (GetContainerNumSlots(bag) or 0) > 0 then out[#out + 1] = bag end
	end
	return out
end
ns.BankContainers = BankContainers

local BagStore  = MakeContainerStore("bags", BagContainers)
local BankStore = MakeContainerStore("bank", BankContainers)

-- Guild bank: tabs are numbered, slots 1..MAX_GUILDBANK_SLOTS_PER_TAB. Contents only
-- exist client-side after QueryGuildBankTab; withdrawals are rate-limited per tab.
local GUILD_SLOTS = MAX_GUILDBANK_SLOTS_PER_TAB or 98
local guildQueried = {}

local function GuildTabInfo(tab)
	if not GetGuildBankTabInfo then return nil end
	local name, icon, isViewable, canDeposit, numWithdrawals, remaining = GetGuildBankTabInfo(tab)
	return { name = name, viewable = isViewable, canDeposit = canDeposit, remaining = remaining }
end

local function GuildSlotItemID(tab, slot)
	local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)
	if not link then return nil end
	return tonumber(link:match("item:(%d+)"))
end

local function GuildTabs(viewableOnly)
	local out = {}
	local n = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
	for tab = 1, n do
		local info = GuildTabInfo(tab)
		if info and (not viewableOnly or info.viewable) then out[#out + 1] = tab end
	end
	return out
end

function ns.QueryGuildTabs()
	if not QueryGuildBankTab then return end
	for _, tab in ipairs(GuildTabs(true)) do
		if not guildQueried[tab] then
			guildQueried[tab] = true
			QueryGuildBankTab(tab)
		end
	end
end

local GuildStore = {
	name = "guild bank",
	Stacks = function(self, itemID)
		local out = {}
		self.limitedHit = false
		for _, tab in ipairs(GuildTabs(true)) do
			local info = GuildTabInfo(tab)
			-- remaining == -1 means unlimited; 0 means this tab is tapped out for today.
			local tapped = info and info.remaining == 0
			for slot = 1, GUILD_SLOTS do
				local texture, count, locked = GetGuildBankItemInfo(tab, slot)
				if texture and not locked and GuildSlotItemID(tab, slot) == itemID then
					if tapped then
						self.limitedHit = true
					else
						out[#out + 1] = { loc = { tab = tab, slot = slot }, count = count or 1 }
					end
				end
			end
		end
		return out
	end,
	Pickup = function(_, loc, n, count)
		if n and n < count then SplitGuildBankItem(loc.tab, loc.slot, n) else PickupGuildBankItem(loc.tab, loc.slot) end
	end,
	-- Deposits go into the tab you are looking at, if it allows deposits.
	FindDropTarget = function(_, itemID, n, exclude)
		local tab = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
		local info = tab and GuildTabInfo(tab)
		if not info or not info.canDeposit or exclude["tab:" .. tab] then return nil end
		local maxStack = MaxStackOf(itemID)
		for slot = 1, GUILD_SLOTS do
			local texture, count, locked = GetGuildBankItemInfo(tab, slot)
			if texture and not locked and GuildSlotItemID(tab, slot) == itemID and (count or 1) + n <= maxStack then
				return { tab = tab, slot = slot }
			end
		end
		for slot = 1, GUILD_SLOTS do
			local texture = GetGuildBankItemInfo(tab, slot)
			if not texture then return { tab = tab, slot = slot } end
		end
		return nil
	end,
	Drop = function(_, loc) PickupGuildBankItem(loc.tab, loc.slot) end,
	-- Splits stay inside the same tab (moving between tabs may need extra rights).
	FindEmptySlotNear = function(_, near)
		for slot = 1, GUILD_SLOTS do
			local texture = GetGuildBankItemInfo(near.tab, slot)
			if not texture then return { tab = near.tab, slot = slot } end
		end
		return nil
	end,
	StateAt = function(_, loc)
		local texture, count, locked = GetGuildBankItemInfo(loc.tab, loc.slot)
		if not texture then return 0, false end
		return count or 1, locked and true or false
	end,
	LocKey = function(_, loc) return "tab:" .. loc.tab end,
	LocText = function(_, loc) return string.format("guild tab %d slot %d", loc.tab, loc.slot) end,
	-- Tab contents arrive asynchronously after QueryGuildBankTab, so give them a moment.
	Ready = function() return (GetTime() - (Restocker.guildOpenedAt or 0)) > 1.0 end,
}

-- Bank counts come from scanning the bank containers while the bank is open;
-- the snapshot is kept so the Bank column still shows after it closes.
local bankSnapshot = nil
function ns.RefreshBankSnapshot()
	if not Restocker.bankOpen then return end
	local counts = {}
	for _, bag in ipairs(BankContainers()) do
		for slot = 1, GetContainerNumSlots(bag) do
			local info = GetSlotInfo(bag, slot)
			if info and info.itemID then
				counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
			end
		end
	end
	bankSnapshot = counts
end

function ns.GetBankCount(itemID)
	if bankSnapshot then return bankSnapshot[itemID] or 0 end
	local total = GetItemCount(itemID, true) or 0
	return math.max(0, total - ns.GetHave(itemID))
end

-- ------------------------------------------------------------------
-- Mover: one job per item, one physical move per tick, in either direction.
-- ------------------------------------------------------------------
local mover = nil -- { store=, plan=, ticker=, ticks= }

-- Largest whole stack that fits, else the smallest stack big enough to split.
local function ChooseStack(stacks, need)
	local whole, split
	for _, s in ipairs(stacks) do
		if s.count <= need then
			if not whole or s.count > whole.count then whole = s end
		else
			if not split or s.count < split.count then split = s end
		end
	end
	return whole or split
end

local function FinishMove(reason)
	if not mover then return end
	if mover.ticker then mover.ticker:Cancel() end
	local store, plan = mover.store, mover.plan
	mover = nil
	ns.RefreshBankSnapshot()
	local withdrew, deposited, failed = {}, {}, {}
	for _, job in ipairs(plan) do
		if job.moved > 0 then
			local note = job.fail and (" |cffff6060(" .. job.fail .. ")|r") or ""
			local list = job.dir == "deposit" and deposited or withdrew
			list[#list + 1] = string.format("%dx %s%s", job.moved, job.name, note)
		elseif job.fail then
			failed[#failed + 1] = string.format("%s (%s)", job.name, job.fail)
		end
	end
	if #withdrew > 0 then Announce("withdrew " .. table.concat(withdrew, ", ") .. " from the " .. store.name .. ".") end
	if #deposited > 0 then Announce("deposited " .. table.concat(deposited, ", ") .. " into the " .. store.name .. ".") end
	if #failed > 0 then Announce("|cffff6060skipped|r " .. table.concat(failed, ", ") .. ".") end
	if reason then Print(reason) end
	Restocker:RequestRefresh()
end

local function Trace(msg)
	if ns.db and ns.db.settings.trace then print("|cff888888Stockpile trace:|r " .. msg) end
end

-- Pace of the mover. A move is never issued until the previous one is confirmed,
-- so a short interval cannot outrun the server: it only cuts the idle waiting.
local MOVE_INTERVAL = 0.1   -- seconds between ticks
local MOVE_WAIT     = 2.0   -- how long to let the server confirm a single move
local MOVE_TIMEOUT  = 90    -- give up on the whole pass after this long

-- Every move is issued on one tick and VERIFIED on the next by re-reading the
-- source slot. A refused drop (item bounces back, or stays on the cursor) marks
-- that container bad for the rest of the pass, so it is never retried blindly.
local function VerifyPending()
	local p = mover.pending
	local job, from, to = p.job, p.from, p.to
	local count, locked = from:StateAt(p.loc)

	local now = GetTime and GetTime() or 0
	if CursorHasItem and CursorHasItem() then
		-- Pickup worked, drop was refused: put it back where it came from.
		if not p.returned then
			p.returned, p.returnedAt = true, now
			Trace("drop into " .. to:LocText(p.target) .. " refused, returning item to " .. from:LocText(p.loc))
			from:Drop(p.loc)
			return
		elseif (now - (p.returnedAt or now)) < MOVE_WAIT then
			return -- give the return-drop a moment
		end
		-- Could not even put it back; leave it on the cursor for the player and stop.
		mover.pending = nil
		job.fail = "item left on cursor"
		job.done = true
		return
	end

	if locked and (now - (p.issuedAt or now)) < MOVE_WAIT then
		return -- server still processing
	end
	mover.pending = nil

	if p.stage == "split" then
		-- A split inside the source store. Nothing is credited: the new stack gets
		-- moved whole on a later tick. If the split did not take, stop splitting
		-- this job and fall back to direct cross-container splits.
		if count < p.count then
			job.splitLoc = p.target -- move this piece next, leaving the original stack where it was
			Trace(string.format("split %d off %s into %s", p.n, from:LocText(p.loc), from:LocText(p.target)))
		else
			job.noSplit = true
			Trace("split inside " .. from.name .. " did not happen; will split directly")
		end
		return
	end

	if count < p.count then
		job.moved = job.moved + p.n
		job.need = job.need - p.n
		job.refusals = 0
		Trace(string.format("moved %d from %s to %s", p.n, from:LocText(p.loc), to:LocText(p.target)))
	else
		local key = to:LocKey(p.target)
		mover.bad[key] = true
		job.refusals = (job.refusals or 0) + 1
		Trace("move to " .. to:LocText(p.target) .. " did not happen; excluding " .. key)
		if job.refusals >= 3 then
			job.fail = to.name .. " refused it"
			job.done = true
		end
	end
end

local function MoveStep()
	if not mover then return end
	local store = mover.store
	if not store.IsOpen() then FinishMove() return end
	mover.ticks = mover.ticks + 1
	local now = GetTime and GetTime() or 0
	if mover.startedAt and (now - mover.startedAt) > MOVE_TIMEOUT then FinishMove("restock timed out.") return end
	if mover.pending then
		VerifyPending()
		if not mover or mover.pending then return end
		-- Confirmed. Carry straight on and issue the next move in this same tick,
		-- rather than idling for another one.
	end
	if CursorHasItem and CursorHasItem() then return end -- player is holding something
	if not store.Ready() then return end

	-- Completed jobs stay in the plan (marked done) so the summary can list them.
	local job
	for _, j in ipairs(mover.plan) do
		if not j.done then job = j break end
	end
	if not job then FinishMove() return end
	if job.need <= 0 or job.fail then job.done = true return end

	local from, to = store, BagStore
	if job.dir == "deposit" then from, to = BagStore, store end

	local stack
	if job.splitLoc then
		-- The piece we just split off, if it is still there and still the right size.
		local c, locked = from:StateAt(job.splitLoc)
		if c > 0 and c <= job.need and not locked then stack = { loc = job.splitLoc, count = c } end
		job.splitLoc = nil
	end
	stack = stack or ChooseStack(from:Stacks(job.itemID), job.need)
	if not stack then
		-- Async stores may not have reported contents yet: be patient a few ticks.
		job.waited = (job.waited or 0) + 1
		if job.moved == 0 and job.waited < 6 and from ~= BagStore then return end
		if from.limitedHit then job.fail = "withdrawal limit reached"
		elseif job.moved == 0 then job.fail = "not in " .. from.name
		else job.fail = "only " .. job.moved .. " in " .. from.name end
		job.done = true
		return
	end
	local n = math.min(stack.count, job.need)

	-- Splitting straight into another container is refused by this client
	-- ("Couldn't split those items"), so split inside the source first and move
	-- the resulting stack whole on the next pass.
	if n < stack.count and not job.noSplit then
		local spare = from:FindEmptySlotNear(stack.loc)
		if spare then
			Trace(string.format("%s: splitting %d x %s off %s into %s first", job.dir, n, job.name, from:LocText(stack.loc), from:LocText(spare)))
			from:Pickup(stack.loc, n, stack.count)
			from:Drop(spare)
			mover.pending = { job = job, from = from, to = from, loc = stack.loc, count = stack.count, n = n, target = spare, stage = "split", issuedAt = GetTime and GetTime() or 0 }
			return
		end
		Trace("no empty slot in " .. from.name .. " to split into; splitting directly")
	end

	local target = to:FindDropTarget(job.itemID, n, mover.bad)
	if not target then
		local what = to.name .. " full"
		if next(mover.bad) then what = to.name .. " refused it" end
		for _, j in ipairs(mover.plan) do if not j.done and j.need > 0 and j.dir == job.dir then j.fail = what end end
		return
	end

	Trace(string.format("%s: %d x %s from %s to %s", job.dir, n, job.name, from:LocText(stack.loc), to:LocText(target)))
	from:Pickup(stack.loc, n, stack.count)
	to:Drop(target)
	mover.pending = { job = job, from = from, to = to, loc = stack.loc, count = stack.count, n = n, target = target, issuedAt = GetTime and GetTime() or 0 }
end

-- which = "bank" | "guild"
function Restocker:RunStorage(which, manual)
	local store = which == "guild" and GuildStore or BankStore
	store.IsOpen = which == "guild" and function() return Restocker.guildOpen end or function() return Restocker.bankOpen end
	if not store.IsOpen() then
		if manual then Print("Open your " .. store.name .. " first.") end
		return
	end
	if mover then return end -- already running

	local plan, tracked = {}, 0
	for itemID, cfg in pairs(ns.db.items) do
		if cfg.enabled and cfg[which] then
			tracked = tracked + 1
			local diff = cfg.want - ns.GetHave(itemID)
			local name = GetItemInfo(itemID) or ("item " .. itemID)
			if diff > 0 then
				plan[#plan + 1] = { itemID = itemID, dir = "withdraw", need = diff, moved = 0, name = name }
			elseif diff < 0 and cfg.deposit then
				plan[#plan + 1] = { itemID = itemID, dir = "deposit", need = -diff, moved = 0, name = name }
			end
		end
	end
	if #plan == 0 then
		if manual then
			Print("Nothing to move.")
		elseif tracked > 0 then
			-- Say so on auto-runs too, but only when there are items sourced from here.
			Announce(store.name .. ": everything is already at Want.")
		end
		return
	end
	mover = { store = store, plan = plan, ticks = 0, bad = {}, startedAt = GetTime and GetTime() or 0 }
	mover.ticker = C_Timer.NewTicker(MOVE_INTERVAL, MoveStep)
end

function Restocker:RunBank(manual) self:RunStorage("bank", manual) end
function Restocker:RunGuild(manual) self:RunStorage("guild", manual) end

-- Runs whichever restock sources are currently open.
function Restocker:RunOpen(manual)
	local any = false
	if self.merchantOpen then self:RunVendor(manual) any = true end
	if self.bankOpen then self:RunBank(manual) any = true end
	if self.guildOpen then self:RunGuild(manual) any = true end
	if not any and manual then Print("Open a vendor, your bank or the guild bank first.") end
end

-- ------------------------------------------------------------------
-- Events
-- ------------------------------------------------------------------
local function SafeRegister(event)
	pcall(Restocker.RegisterEvent, Restocker, event)
end
SafeRegister("ADDON_LOADED")
SafeRegister("MERCHANT_SHOW")
SafeRegister("MERCHANT_CLOSED")
SafeRegister("BANKFRAME_OPENED")
SafeRegister("BANKFRAME_CLOSED")
SafeRegister("GUILDBANKFRAME_OPENED")
SafeRegister("GUILDBANKFRAME_CLOSED")
SafeRegister("GUILDBANKBAGSLOTS_CHANGED")
SafeRegister("BAG_UPDATE_DELAYED")
SafeRegister("PLAYERBANKSLOTS_CHANGED")
SafeRegister("GET_ITEM_INFO_RECEIVED")
SafeRegister("PLAYER_LOGOUT")
SafeRegister("PLAYER_LOGIN")

Restocker:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			InitDB("ADDON_LOADED")
			if ns.UI then ns.UI:OnDBReady() end
			self:UnregisterEvent("ADDON_LOADED")
		end
	elseif event == "PLAYER_LOGIN" then
		-- If saved variables arrived after ADDON_LOADED, the game replaced the globals
		-- and ns.db points at an orphan. Adopt the real tables.
		if ns.db ~= StockpileDB or not ns.db then
			InitDB("PLAYER_LOGIN(late)")
			if ns.UI then ns.UI:OnDBReady() end
		end
	elseif event == "PLAYER_LOGOUT" then
		ns.SyncMirror()
	elseif event == "MERCHANT_SHOW" then
		self.merchantOpen = true
		if ns.UI then ns.UI:OnMerchantShow() end
		if ns.db.settings.autoVendor then C_Timer.After(0.1, function() self:RunVendor(false) end) end
		self:RequestRefresh()
	elseif event == "MERCHANT_CLOSED" then
		self.merchantOpen = false
		self:RequestRefresh()
	elseif event == "BANKFRAME_OPENED" then
		self.bankOpen = true
		ns.RefreshBankSnapshot()
		if ns.UI then ns.UI:OnBankShow() end
		if ns.db.settings.autoBank then C_Timer.After(0.2, function() self:RunBank(false) end) end
		self:RequestRefresh()
	elseif event == "BANKFRAME_CLOSED" then
		self.bankOpen = false
		if mover and mover.store == BankStore then FinishMove() end
		self:RequestRefresh()
	elseif event == "GUILDBANKFRAME_OPENED" then
		self.guildOpen = true
		self.guildOpenedAt = GetTime()
		guildQueried = {}
		ns.QueryGuildTabs()
		if ns.UI then ns.UI:OnGuildBankShow() end
		if ns.db.settings.autoGuild then C_Timer.After(1.2, function() self:RunGuild(false) end) end
		self:RequestRefresh()
	elseif event == "GUILDBANKFRAME_CLOSED" then
		self.guildOpen = false
		if mover and mover.store == GuildStore then FinishMove() end
		self:RequestRefresh()
	else
		ns.RefreshBankSnapshot() -- no-op unless the bank is open
		self:RequestRefresh()
	end
end)

-- ------------------------------------------------------------------
-- Slash commands
-- ------------------------------------------------------------------
SLASH_STOCKPILE1 = "/stockpile"
SLASH_STOCKPILE2 = "/restock"
SlashCmdList.STOCKPILE = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "debug" then
		Print("UI template report:")
		local keys = {}
		for k in pairs(ns.templateReport or {}) do keys[#keys + 1] = k end
		table.sort(keys)
		for _, k in ipairs(keys) do print("   " .. k .. " = " .. tostring(ns.templateReport[k])) end
		print("   C_Item=" .. tostring(C_Item ~= nil) .. " C_Container=" .. tostring(C_Container ~= nil)
			.. " ItemMixin=" .. tostring(Item ~= nil and Item.CreateFromItemID ~= nil)
			.. " GetMerchantItemMaxStack=" .. tostring(GetMerchantItemMaxStack ~= nil)
			.. " C_MerchantFrame=" .. tostring(C_MerchantFrame ~= nil and C_MerchantFrame.GetItemInfo ~= nil))
		print("   save journal (newest last):")
		for _, line in ipairs((StockpileAccountDB and StockpileAccountDB.journal) or {}) do print("     " .. line) end
		print("   guild API: GetNumGuildBankTabs=" .. tostring(GetNumGuildBankTabs ~= nil)
			.. " GetGuildBankItemInfo=" .. tostring(GetGuildBankItemInfo ~= nil)
			.. " PickupGuildBankItem=" .. tostring(PickupGuildBankItem ~= nil)
			.. " SplitGuildBankItem=" .. tostring(SplitGuildBankItem ~= nil)
			.. " GetCurrentGuildBankTab=" .. tostring(GetCurrentGuildBankTab ~= nil))
		local bags = BankContainers()
		print("   bank containers: " .. (#bags > 0 and table.concat(bags, ",") or "(none - bank closed)"))
		for _, bag in ipairs(bags) do
			local free, family = GetContainerNumFreeSlots(bag)
			local used = 0
			for slot = 1, GetContainerNumSlots(bag) do if GetSlotInfo(bag, slot) then used = used + 1 end end
			print(string.format("     bag %d: slots=%d free=%s family=%s used=%d", bag, GetContainerNumSlots(bag) or 0, tostring(free), tostring(family), used))
		end
		if Restocker.bankOpen then
			print("   tracked items in bank:")
			local any = false
			for itemID, cfg in pairs(ns.db.items) do
				local n = ns.GetBankCount(itemID)
				if n > 0 then
					any = true
					print(string.format("     %s x%d  (have %d, want %d, source %s)", tostring(GetItemInfo(itemID) or itemID), n, ns.GetHave(itemID), cfg.want, ns.SourceLabel(cfg)))
				end
			end
			if not any then print("     (none)") end
		end
		if Restocker.guildOpen then
			print("   guild bank tabs:")
			for _, tab in ipairs(GuildTabs(false)) do
				local info = GuildTabInfo(tab)
				print(string.format("     [%d] %s  viewable=%s deposit=%s remaining=%s  current=%s", tab, tostring(info.name), tostring(info.viewable), tostring(info.canDeposit), tostring(info.remaining), tostring(GetCurrentGuildBankTab and GetCurrentGuildBankTab() == tab)))
			end
			print("   tracked items in guild bank:")
			local any = false
			for itemID, cfg in pairs(ns.db.items) do
				local total = 0
				for _, s in ipairs(GuildStore:Stacks(itemID)) do total = total + s.count end
				if total > 0 then
					any = true
					print(string.format("     %s x%d  (have %d, want %d, source %s)", tostring(GetItemInfo(itemID) or itemID), total, ns.GetHave(itemID), cfg.want, ns.SourceLabel(cfg)))
				end
			end
			if not any then print("     (none visible yet - tabs load a moment after opening)") end
		end
		if Restocker.merchantOpen then
			print("   merchant items on your list:")
			for i = 1, (GetMerchantNumItems() or 0) do
				local id = GetMerchantItemID(i)
				if id and ns.db.items[id] then
					local name, _, price, bundle, avail = GetMerchantInfo(i)
					local maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(i)
					print(string.format("     [%d] %s  price=%s  bundle=%s  avail=%s  maxPerBuy=%s",
						i, tostring(name), tostring(price), tostring(bundle), tostring(avail), tostring(maxStack)))
				end
			end
		end
	elseif msg == "minimap" then
		ns.db.settings.minimapHide = not ns.db.settings.minimapHide
		if ns.UI then ns.UI:UpdateMinimapButton() end
	elseif msg == "trace" then
		ns.db.settings.trace = not ns.db.settings.trace
		Print("move tracing " .. (ns.db.settings.trace and "ON - every bank/guild move will be printed" or "off"))
	elseif msg == "vendor" then
		Restocker:RunVendor(true)
	elseif msg == "bank" then
		Restocker:RunBank(true)
	elseif msg == "guild" then
		Restocker:RunGuild(true)
	elseif msg == "help" then
		Print("/stockpile - toggle the window")
		print("   /stockpile vendor | bank | guild - restock now (with that window open)")
		print("   /stockpile minimap - show/hide the minimap button")
		print("   /stockpile debug - print which UI pieces resolved on this client")
		print("   /stockpile trace - toggle printing every bank/guild move (for troubleshooting)")
	else
		if ns.UI then ns.UI:Toggle() end
	end
end
