-- ShopTierBypass Deep Debug
-- Dumps full shopItem field structure, live purchase request + server response.
-- Auto-copies on each event. Run while in-game with ShopTierBypass enabled.

local ok, err = pcall(function()
local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local lplr = cloneref(game:GetService('Players')).LocalPlayer
local buf = {}
local function log(s) table.insert(buf, s) print('[STB-DEEP]', s) end
local function copy() pcall(setclipboard, table.concat(buf, '\n')) end

-- recursive table dump with cycle protection and depth limit
local function dumpTable(t, indent, seen, depth)
    indent = indent or ''
    seen = seen or {}
    depth = depth or 0
    if depth > 5 then return indent .. '(max depth)' end
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

log('=== ShopTierBypass Deep Debug ===')
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

-- ---- SECTION 1: FULL SHOPITEM STRUCTURE ----
-- Call getShopItem directly to see ALL fields including hidden ones like `require`
log('=== SECTION 1: FULL SHOPITEM FIELD DUMP ===')
log('(showing chestplate chain - most likely to have tier prerequisites)')
log('')

local chestplates = {
    'leather_chestplate', 'iron_chestplate', 'diamond_chestplate',
    'emerald_chestplate', 'void_chestplate'
}

if bedwars.Shop and bedwars.Shop.getShopItem then
    for _, itemType in chestplates do
        local ok2, item = pcall(function()
            return bedwars.Shop.getShopItem(itemType, lplr)
        end)
        if ok2 and item then
            log('[' .. itemType .. ']:')
            log(dumpTable(item, '  '))
            log('')
        elseif ok2 then
            log('[' .. itemType .. ']: nil (not in shop or getShopItem returned nil)')
            log('')
        else
            log('[' .. itemType .. ']: ERROR - ' .. tostring(item))
            log('')
        end
    end
else
    log('bedwars.Shop.getShopItem not available')
end

-- ---- SECTION 2: COMPARE ITEMSBYTYPES IN SHOPITEMS ----
log('=== SECTION 2: RAW SHOPITEMS TABLE ENTRY FOR IRON_CHESTPLATE ===')
if bedwars.Shop and bedwars.Shop.ShopItems then
    for _, v in bedwars.Shop.ShopItems do
        if v.itemType == 'iron_chestplate' or v.itemType == 'leather_chestplate' then
            log('[ShopItems entry: ' .. v.itemType .. ']:')
            log(dumpTable(v, '  '))
            log('')
        end
    end
else
    log('bedwars.Shop.ShopItems not available')
end

-- ---- SECTION 3: BEDWARSSHOPCONTROLLER STATE ----
log('=== SECTION 3: BEDWARSSHOPCONTROLLER ===')
local ctrl = bedwars.BedwarsShopController
if ctrl then
    log('alreadyPurchasedMap:')
    if ctrl.alreadyPurchasedMap then
        local any = false
        for k, v in pairs(ctrl.alreadyPurchasedMap) do
            log('  ' .. tostring(k) .. ' = ' .. tostring(v))
            any = true
        end
        if not any then log('  (empty)') end
    else
        log('  nil')
    end
    log('')
    log('All BedwarsShopController fields:')
    log(dumpTable(ctrl, '  '))
else
    log('BedwarsShopController not found (nil)')
end
log('')

-- ---- SECTION 4: ITEMSMETA FOR CHESTPLATES ----
log('=== SECTION 4: ITEMMETA ENTRIES FOR CHESTPLATES ===')
if bedwars.ItemMeta then
    for _, itemType in chestplates do
        local meta = bedwars.ItemMeta[itemType]
        if meta then
            log('[ItemMeta: ' .. itemType .. ']:')
            log(dumpTable(meta, '  '))
            log('')
        else
            log('[ItemMeta: ' .. itemType .. ']: nil')
        end
    end
else
    log('bedwars.ItemMeta not available')
end

copy()
log('')
log('=== STATIC DUMP COMPLETE - LIVE HOOK ACTIVE ===')
log('Now open the shop and try buying iron_chestplate or diamond_chestplate WITHIN 10 SECONDS.')
log('WITHOUT owning the previous tier. Full request + server response captured below.')
log('')
copy()

-- ---- SECTION 5: LIVE PURCHASE HOOK ----
local origGet = bedwars.Client.Get
bedwars.Client.Get = function(self, name, ...)
    local remote = origGet(self, name, ...)
    if name ~= 'BedwarsPurchaseItem' then return remote end
    return setmetatable({}, {
        __index = function(_, key)
            if key ~= 'CallServerAsync' then return remote[key] end
            return function(_, data, extraArgs)
                log('')
                log('--- LIVE PURCHASE ATTEMPT [' .. os.date() .. '] ---')

                -- dump full shopItem (this is what actually gets sent to server)
                if data then
                    log('shopId sent: ' .. tostring(data.shopId))
                    log('')
                    if data.shopItem then
                        log('FULL shopItem sent to server:')
                        log(dumpTable(data.shopItem, '  '))
                    else
                        log('shopItem: nil')
                    end
                    log('')
                    log('Other data fields:')
                    for k, v in pairs(data) do
                        if k ~= 'shopItem' then
                            log('  ' .. tostring(k) .. ' = ' .. tostring(v))
                        end
                    end
                else
                    log('data: nil')
                end

                copy()

                -- fire real call
                local result = remote:CallServerAsync(data, extraArgs)

                log('')
                log('server raw return: ' .. tostring(result))

                -- wrap andThen to capture resolved value
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
                                if res then
                                    log('>> PURCHASE SUCCEEDED')
                                else
                                    log('>> PURCHASE FAILED/REJECTED by server')
                                end
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
    log('=== Hook removed (10s timeout). Final clipboard copy. ===')
    copy()
end)

log('Hook active for 10s. Buy a tiered item and check clipboard/console.')
copy()
end)
if not ok then
    warn('[STB-DEEP] ERROR: ' .. tostring(err))
    pcall(function() (setclipboard or toclipboard)('[STB-DEEP] ERROR: ' .. tostring(err)) end)
end
