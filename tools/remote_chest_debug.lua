-- Remote ChestGiveItem debug (no proximity required)
-- Tests if server accepts ChestGiveItem from anywhere, auto-copies results

local lplr = game:GetService('Players').LocalPlayer
local replicatedStorage = game:GetService('ReplicatedStorage')

local resourceTypes = {'iron', 'diamond', 'emerald'}
local log = {}

local function addLog(msg)
    local line = os.date('%H:%M:%S') .. ' ' .. msg
    table.insert(log, line)
    print('[ChestDebug] ' .. line)
    if setclipboard then
        setclipboard(table.concat(log, '\n'))
    end
end

local function getStore()
    -- grab store the same way the main script does
    local ok, store = pcall(function()
        return require(replicatedStorage:WaitForChild('Modules'):WaitForChild('Store'))
    end)
    return ok and store or nil
end

local function getBedwarsClient()
    local ok, client = pcall(function()
        return require(replicatedStorage:WaitForChild('Modules'):WaitForChild('Client'))
    end)
    return ok and client or nil
end

addLog('=== Remote Chest Debug START ===')
addLog('Player: ' .. lplr.Name)

local chest = replicatedStorage:FindFirstChild('Inventories') and
    replicatedStorage.Inventories:FindFirstChild(lplr.Name .. '_personal')

if not chest then
    addLog('!! NO PERSONAL CHEST FOUND in ReplicatedStorage.Inventories')
    addLog('=== DONE (no chest) ===')
    return
end

addLog('Chest found: ' .. chest:GetFullName())

local store = getStore()
if not store then
    addLog('!! Could not require Store module')
    return
end

local bedwars = getBedwarsClient()
if not bedwars then
    addLog('!! Could not require Client module')
    return
end

local items = store.inventory and store.inventory.inventory and store.inventory.inventory.items
if not items then
    addLog('!! Could not read inventory items from store')
    return
end

local attempted = 0
local succeeded = 0

for _, v in items do
    local isResource = false
    for _, t in resourceTypes do
        if v.itemType == t then isResource = true break end
    end
    if not isResource then continue end

    attempted += 1
    addLog('Trying to deposit: ' .. v.itemType .. ' (tool=' .. tostring(v.tool) .. ')')

    local ok, result = pcall(function()
        return bedwars:GetNamespace('Inventory'):Get('ChestGiveItem'):CallServer(chest, v.tool)
    end)

    if ok then
        succeeded += 1
        addLog('  -> SUCCESS result=' .. tostring(result))
    else
        addLog('  -> FAILED err=' .. tostring(result))
    end

    task.wait(0.1)
end

addLog('=== DONE | attempted=' .. attempted .. ' succeeded=' .. succeeded .. ' ===')
addLog('Results auto-copied to clipboard.')
