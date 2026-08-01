-- Hephaestus ShopTierBypass Debug
-- Dumps full field structure for hephaestus items + live purchase hook.
-- Run while in-game. STB does NOT need to be active - run this standalone.

local ok, err = pcall(function()
local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local lplr = cloneref(game:GetService('Players')).LocalPlayer
local buf = {}
local function log(s) table.insert(buf, s) print('[HEPH-DBG]', s) end
local function copy() pcall(setclipboard, table.concat(buf, '\n')) end

local function dumpTable(t, indent, seen, depth)
    indent = indent or ''
    seen = seen or {}
    depth = depth or 0
    if depth > 6 then return indent .. '(max depth)' end
    if type(t) ~= 'table' then return indent .. tostring(t) end
    if seen[t] then return indent .. '(circular ref)' end
    seen[t] = true
    local lines = {}
    local ok2, iterErr = pcall(function()
        for k, v in pairs(t) do
            local vt = type(v)
            if vt == 'table' then
                table.insert(lines, indent .. tostring(k) .. ':')
                table.insert(lines, dumpTable(v, indent .. '  ', seen, depth + 1))
            elseif vt == 'function' then
                local info = debug and debug.getinfo and debug.getinfo(v, 'S')
                local src = info and info.short_src or '?'
                table.insert(lines, indent .. tostring(k) .. ' = [function @ ' .. src .. ']')
            elseif vt == 'userdata' or vt == 'thread' then
                table.insert(lines, indent .. tostring(k) .. ' = [' .. vt .. ': ' .. tostring(v) .. ']')
            else
                table.insert(lines, indent .. tostring(k) .. ' = ' .. tostring(v))
            end
        end
    end)
    if not ok2 then
        table.insert(lines, indent .. '(pairs error: ' .. tostring(iterErr) .. ')')
    end
    seen[t] = nil
    return table.concat(lines, '\n')
end

log('=== Hephaestus Debug ===')
log('Time: ' .. os.date())
log('Player: ' .. lplr.Name)

local bedwars = getgenv and getgenv().bedwars
local store   = getgenv and getgenv().store
if not bedwars or not store then
    log('ERROR: bedwars/store not in genv - main script not loaded')
    copy() return
end
log('shopLoaded: ' .. tostring(store.shopLoaded))
log('')

-- ---- SECTION 1: FIND ALL HEPHAESTUS ITEMS IN SHOPITEMS ----
log('=== SECTION 1: ALL SHOPITEMS MATCHING "hephaestus" ===')
if not bedwars.Shop or not bedwars.Shop.ShopItems then
    log('bedwars.Shop.ShopItems not available')
else
    local found = 0
    for _, v in bedwars.Shop.ShopItems do
        local it = tostring(v.itemType or '')
        if it:lower():find('hephaestus') then
            found = found + 1
            log('[ShopItems entry: ' .. it .. ']:')
            log(dumpTable(v, '  '))
            log('')
        end
    end
    if found == 0 then
        log('(none found - trying partial scan for "heph")')
        for _, v in bedwars.Shop.ShopItems do
            local it = tostring(v.itemType or '')
            if it:lower():find('heph') then
                log('[ShopItems entry: ' .. it .. ']:')
                log(dumpTable(v, '  '))
                log('')
                found = found + 1
            end
        end
    end
    if found == 0 then
        log('(still none - dumping ALL ShopItems itemTypes so you can find the right name)')
        for _, v in bedwars.Shop.ShopItems do
            log('  ' .. tostring(v.itemType))
        end
    end
end
log('')

-- ---- SECTION 2: GETSHOPITEM FOR KNOWN NAMES ----
log('=== SECTION 2: getShopItem FOR LIKELY ITEMTYPE STRINGS ===')
local candidates = {
    'little_hephaestus', 'hephaestus', 'hephaestus_hammer',
    'little_hephaestus_hammer', 'wood_hephaestus', 'stone_hephaestus',
    'iron_hephaestus', 'diamond_hephaestus', 'mythic_hephaestus',
}
if bedwars.Shop and bedwars.Shop.getShopItem then
    for _, name in candidates do
        local ok2, item = pcall(function()
            return bedwars.Shop.getShopItem(name, lplr)
        end)
        if ok2 and item then
            log('[' .. name .. '] FOUND via getShopItem:')
            log(dumpTable(item, '  '))
            log('')
        end
    end
else
    log('getShopItem not available')
end
log('')

-- ---- SECTION 3: ITEMMETA SCAN FOR HEPHAESTUS ----
log('=== SECTION 3: ITEMMETA MATCHING "hephaestus" ===')
if bedwars.ItemMeta then
    local found = 0
    for itemType, meta in pairs(bedwars.ItemMeta) do
        if tostring(itemType):lower():find('hephaestus') or tostring(itemType):lower():find('heph') then
            found = found + 1
            log('[ItemMeta: ' .. itemType .. ']:')
            log(dumpTable(meta, '  '))
            log('')
        end
    end
    if found == 0 then log('(none found in ItemMeta)') end
else
    log('bedwars.ItemMeta not available')
end
log('')

copy()
log('=== STATIC DUMP COMPLETE - LIVE HOOK ACTIVE FOR 10s ===')
log('Buy a hephaestus item now to capture the full request + server response.')
log('')
copy()

-- ---- SECTION 4: LIVE PURCHASE HOOK ----
local origGet = bedwars.Client.Get
bedwars.Client.Get = function(self, name, ...)
    local remote = origGet(self, name, ...)
    if name ~= 'BedwarsPurchaseItem' then return remote end
    return setmetatable({}, {
        __index = function(_, key)
            if key ~= 'CallServerAsync' then return remote[key] end
            return function(_, data, extraArgs)
                local itemType = data and data.shopItem and data.shopItem.itemType or '?'
                -- only log hephaestus-related purchases
                if not tostring(itemType):lower():find('heph') then
                    return remote:CallServerAsync(data, extraArgs)
                end

                log('')
                log('--- LIVE PURCHASE [' .. os.date() .. '] itemType=' .. itemType .. ' ---')
                if data then
                    log('shopId: ' .. tostring(data.shopId))
                    if data.shopItem then
                        log('FULL shopItem sent to server:')
                        log(dumpTable(data.shopItem, '  '))
                    end
                    log('Other data fields:')
                    for k, v in pairs(data) do
                        if k ~= 'shopItem' then
                            log('  ' .. tostring(k) .. ' = ' .. tostring(v))
                        end
                    end
                end
                copy()

                local result = remote:CallServerAsync(data, extraArgs)
                log('server raw return: ' .. tostring(result))

                return {
                    andThen = function(_, cb)
                        if result and type(result.andThen) == 'function' then
                            result:andThen(function(res)
                                if type(res) == 'table' then
                                    log('server resolved (table):')
                                    log(dumpTable(res, '  '))
                                else
                                    log('server resolved: ' .. tostring(res))
                                end
                                log(res and '>> PURCHASE SUCCEEDED' or '>> PURCHASE FAILED/REJECTED by server')
                                copy()
                                if cb then cb(res) end
                            end)
                        else
                            log('result has no andThen - raw: ' .. tostring(result))
                            copy()
                            if cb then cb(result) end
                        end
                    end
                }
            end
        end
    })
end

task.delay(10, function()
    bedwars.Client.Get = origGet
    log('')
    log('=== Hook removed (10s). Final clipboard copy. ===')
    copy()
end)

log('Hook active for 10s.')
copy()
end)
if not ok then
    warn('[HEPH-DBG] ERROR: ' .. tostring(err))
    pcall(function() (setclipboard or toclipboard)('[HEPH-DBG] ERROR: ' .. tostring(err)) end)
end
