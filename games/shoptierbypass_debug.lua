local ok, err = pcall(function()
local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local lplr = cloneref(game:GetService('Players')).LocalPlayer
local buf = {}
local function log(s) table.insert(buf, s) print('[STB-DBG]', s) end
local function copy() pcall(setclipboard, table.concat(buf, '\n')) end

log('=== ShopTierBypass Debug ===')
log('Time: ' .. os.date())
log('Player: ' .. lplr.Name)

local bedwars = getgenv and getgenv().bedwars
local store   = getgenv and getgenv().store

if not bedwars then
    log('ERROR: bedwars not in genv - main script not loaded yet?')
    copy() return
end
if not store then
    log('ERROR: store not in genv - main script not loaded yet?')
    copy() return
end

log('shopLoaded: ' .. tostring(store.shopLoaded))
log('')

-- replicate getItem + hasItemOwned from the main script
local function getItem(itemType)
    for _, item in store.inventory.inventory.items do
        if item.itemType == itemType then return item end
    end
end

local function hasItemOwned(itemType)
    if getItem(itemType) then return true end
    local armor = store.inventory.inventory.armor
    if armor then
        for _, a in armor do
            if type(a) == 'table' and a.itemType == itemType then return true end
        end
    end
    return false
end

-- ---- INVENTORY ----
log('--- INVENTORY ---')
local invCount = 0
for slot, item in store.inventory.inventory.items do
    log('  [' .. tostring(slot) .. '] ' .. tostring(item.itemType))
    invCount += 1
end
if invCount == 0 then log('  (empty)') end

log('Armor:')
local armorCount = 0
local armor = store.inventory.inventory.armor
if armor then
    for _, a in armor do
        if type(a) == 'table' then
            log('  ' .. tostring(a.itemType))
            armorCount += 1
        end
    end
end
if armorCount == 0 then log('  (empty)') end
log('')

-- ---- SHOP ITEMS ----
log('--- SHOP ITEMS (itemType | tiered/nextTier flags) ---')
if not bedwars.Shop then
    log('  ERROR: bedwars.Shop is nil - shopLoaded may be false')
else
    local tieredCount = 0
    for _, v in bedwars.Shop.ShopItems do
        local flagStr = ''
        if v.tiered ~= nil or v.nextTier ~= nil then
            flagStr = '  [tiered=' .. tostring(v.tiered) .. ' nextTier=' .. tostring(v.nextTier) .. ']'
            tieredCount += 1
        end
        log('  ' .. tostring(v.itemType) .. flagStr)
    end
    log('')
    if tieredCount == 0 then
        log('>> All tiered/nextTier flags cleared - bypass hook is active')
    else
        log('>> WARNING: ' .. tieredCount .. ' item(s) still have tiered/nextTier set')
        log('   Bypass may not be enabled or shop loaded before the hook ran')
    end
end
log('')

-- ---- TIER CHAIN SIMULATION ----
-- mirrors the exact knownTiers + chain-building logic in ShopTierBypass
local knownTiers = {
    {'wood_pickaxe', 'stone_pickaxe', 'iron_pickaxe', 'diamond_pickaxe'},
    {'wood_axe', 'stone_axe', 'iron_axe', 'diamond_axe'},
    {'leather_chestplate', 'iron_chestplate', 'diamond_chestplate', 'emerald_chestplate', 'void_chestplate'},
    {'wood_sword', 'stone_sword', 'iron_sword', 'diamond_sword', 'emerald_sword', 'void_sword'},
    {'wood_gun_blade', 'stone_gun_blade', 'iron_gun_blade', 'diamond_gun_blade', 'emerald_gun_blade'},
    {'wood_scythe', 'stone_scythe', 'iron_scythe', 'diamond_scythe', 'mythic_scythe'},
    {'wood_great_hammer', 'stone_great_hammer', 'iron_great_hammer', 'diamond_great_hammer', 'mythic_great_hammer'},
    {'wood_dagger', 'stone_dagger', 'iron_dagger', 'diamond_dagger', 'mythic_dagger'},
    {'wood_gauntlets', 'stone_gauntlets', 'iron_gauntlets', 'diamond_gauntlets', 'mythic_gauntlets_plain'},
    {'wood_dao', 'stone_dao', 'iron_dao', 'diamond_dao', 'emerald_dao'},
}

local itemsByType = {}
if bedwars.Shop then
    for _, v in bedwars.Shop.ShopItems do
        if v.itemType then itemsByType[v.itemType] = v end
    end
end

log('--- KNOWNTIERS vs ACTUAL SHOP itemTypes ---')
for _, group in knownTiers do
    for _, it in group do
        local inShop = itemsByType[it] ~= nil
        local ownedMark = hasItemOwned(it) and ' [OWNED]' or ''
        log('  ' .. it .. ' | in shop: ' .. tostring(inShop) .. ownedMark)
    end
end
log('  (if "in shop: false" - that itemType string doesnt match the games actual name)')
log('')

local tierChains = {}
for _, group in knownTiers do
    local hasAny = false
    for _, it in group do
        if itemsByType[it] then hasAny = true break end
    end
    if hasAny then
        local chain = {items = {}, index = {}}
        for _, it in group do
            if itemsByType[it] then
                table.insert(chain.items, it)
                chain.index[it] = #chain.items
            end
        end
        if #chain.items > 1 then
            for _, it in chain.items do tierChains[it] = chain end
        end
    end
end

log('--- CHAINS BUILT ---')
if not next(tierChains) then
    log('  EMPTY - none of the knownTiers strings matched any ShopItem.itemType')
    log('  This means shouldBlock() always returns false immediately')
    log('  -> ShopTierBypass is NOT the cause of blocked upgrades')
    log('  -> The server is likely rejecting the purchase instead')
else
    local seen = {}
    for _, chain in tierChains do
        local id = tostring(chain)
        if not seen[id] then
            seen[id] = true
            local parts = {}
            for _, it in chain.items do
                table.insert(parts, it .. (hasItemOwned(it) and '[OWNED]' or ''))
            end
            log('  ' .. table.concat(parts, ' -> '))
        end
    end
end
log('')

-- ---- BLOCK PREDICTIONS ----
local function isDowngrade(itemType)
    local chain = tierChains[itemType]
    if not chain then return false, nil end
    local myIndex = chain.index[itemType]
    for i = myIndex + 1, #chain.items do
        if hasItemOwned(chain.items[i]) then
            return true, chain.items[i]
        end
    end
    return false, nil
end

local function shouldBlock(itemType)
    if not tierChains[itemType] then return false, 'not_in_chain' end
    if hasItemOwned(itemType) then return true, 'already_owned' end
    local dg, dgItem = isDowngrade(itemType)
    if dg then return true, 'downgrade (you own ' .. tostring(dgItem) .. ')' end
    return false, 'allowed'
end

log('--- BLOCK PREDICTIONS (items in chains only) ---')
local anyChained = false
if bedwars.Shop then
    for _, v in bedwars.Shop.ShopItems do
        if v.itemType and tierChains[v.itemType] then
            anyChained = true
            local blocked, reason = shouldBlock(v.itemType)
            local displayName = (bedwars.ItemMeta and bedwars.ItemMeta[v.itemType] and bedwars.ItemMeta[v.itemType].displayName) or v.itemType
            local verdict = blocked and ('BLOCKED (' .. reason .. ')') or 'ALLOWED'
            log('  ' .. displayName .. ' [' .. v.itemType .. '] -> ' .. verdict)
        end
    end
end
if not anyChained then
    log('  (no chained items found in shop)')
end
log('  Items not in chains are always passed straight to the server')
log('')
log('=== END (auto-copied to clipboard) ===')

copy()
end)
if not ok then
    warn('[STB-DBG] ERROR: ' .. tostring(err))
    pcall(function() (setclipboard or toclipboard)('[STB-DBG] ERROR: ' .. tostring(err)) end)
end
