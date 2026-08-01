-- Gen Block — standalone script (no Vape required)
-- Collects gen iron underground then bursts it at a fresh spawn to push the spawn point.
-- Toggle with the key set in CONFIG.ToggleKey (default: G). Debug log auto-copies to clipboard.

local Players = game:GetService('Players')
local CollectionService = game:GetService('CollectionService')
local UserInputService = game:GetService('UserInputService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local lplr = Players.LocalPlayer

--== Config (was the module's sliders / toggles) =============================
local CONFIG = {
    StashCount = 10,                 -- items to stash before bursting (module slider: 5-20)
    Debug = true,                    -- copy a debug log to the clipboard
    ToggleKey = Enum.KeyCode.G,      -- press to enable / disable
}

--== Game bindings (was entitylib / getItem / bedwars.Client / remotes) ======
local Store = require(lplr.PlayerScripts.TS.ui.store).ClientStore
local Client = require(ReplicatedStorage.TS.remotes).default.Client

local function getRoot()
    local char = lplr.Character
    return char and char:FindFirstChild('HumanoidRootPart')
end

local function isAlive()
    return getRoot() ~= nil
end

local function getInventoryItems()
    local state = Store:getState()
    local inv = state and state.Inventory and state.Inventory.observedInventory
    return inv and inv.inventory and inv.inventory.items or {}
end

-- Returns the first inventory item matching itemName (item has .tool and .amount)
local function getItem(itemName)
    for _, item in getInventoryItems() do
        if item.itemType == itemName then
            return item
        end
    end
    return nil
end

local function dropItem(item)
    local ok, dropped = pcall(function()
        return Client:Get('DropItem'):CallServer({
            item = item.tool,
            amount = item.amount
        })
    end)
    return ok and dropped or nil
end

--== State ===================================================================
local enabled = false
local mainThread = nil

local stashed = {}
local busy = false
local debugLog = {}

local function dbg(msg)
    if CONFIG.Debug then
        table.insert(debugLog, os.date('%H:%M:%S') .. ' ' .. msg)
        print('[GenBlock] ' .. msg)
        if setclipboard then
            setclipboard(table.concat(debugLog, '\n'))
        end
    end
end

--== Core logic (unchanged from the Vape module) =============================
local function findNearestTeamGen()
    if not isAlive() then return nil end
    local pos = getRoot().Position
    local best, bestDist = nil, math.huge
    for _, obj in workspace:GetDescendants() do
        if obj.Name == 'GeneratorAdornee' then
            local ok, id = pcall(function() return obj:GetAttribute('Id') end)
            if ok and id and type(id) == 'string' and string.match(id, '^%d+_generator') then
                local dist = (obj.Position - pos).Magnitude
                if dist < bestDist then
                    best, bestDist = obj, dist
                end
            end
        end
    end
    if best and bestDist < 30 then return {pos = best.Position} end
    return nil
end

local function freezeAt(drop, pos)
    if drop:IsA('BasePart') then
        drop.Velocity = Vector3.zero
        drop.RotVelocity = Vector3.zero
        drop.CanCollide = false
        drop.Anchored = true
        drop.CFrame = CFrame.new(pos)
    end
    for _, part in drop:GetDescendants() do
        if part:IsA('BasePart') then
            part.Velocity = Vector3.zero
            part.RotVelocity = Vector3.zero
            part.CanCollide = false
            part.Anchored = true
            part.CFrame = CFrame.new(pos)
        end
    end
end

local function maintainStashed()
    for i = #stashed, 1, -1 do
        local e = stashed[i]
        if not e.drop or not e.drop.Parent then
            table.remove(stashed, i)
        else
            freezeAt(e.drop, e.underPos)
        end
    end
end

local function isStashed(drop)
    for _, e in stashed do
        if e.drop == drop then return true end
    end
    return false
end

local function findGenDrop(gen)
    for _, v in CollectionService:GetTagged('ItemDrop') do
        if v and v.Parent
            and not isStashed(v)
            and tick() - (v:GetAttribute('ClientDropTime') or 0) >= 1
            and (v.Position - gen.pos).Magnitude <= 20 then
            return v
        end
    end
    return nil
end

local function stashFromInventory(gen)
    if busy or not isAlive() then return end
    local item = getItem('iron') or getItem('diamond') or getItem('emerald')
    if not item then return end

    busy = true
    task.spawn(function()
        local underPos = Vector3.new(gen.pos.X, gen.pos.Y - 300, gen.pos.Z)

        local caught
        local conn = CollectionService:GetInstanceAddedSignal('ItemDrop'):Connect(function(v)
            if not caught then caught = v end
        end)
        local dropped = dropItem(item)
        if not dropped then task.wait() dropped = caught end
        conn:Disconnect()

        if dropped and dropped.Parent then
            dropped:SetAttribute('ClientDropTime', tick() + 9999)
            if dropped:IsA('BasePart') then
                dropped.CanCollide = false
                dropped.Velocity = Vector3.new(0, -3000, 0)
            end
            for _, part in dropped:GetDescendants() do
                if part:IsA('BasePart') then
                    part.CanCollide = false
                    part.Velocity = Vector3.new(0, -3000, 0)
                end
            end
            task.wait(0.15)
            if dropped and dropped.Parent then
                freezeAt(dropped, underPos)
                table.insert(stashed, { drop = dropped, underPos = underPos })
                dbg('Stashed (' .. #stashed .. '/' .. CONFIG.StashCount .. ')')
            end
        else
            dbg('Drop failed')
        end

        task.wait(0.3)
        busy = false
    end)
end

local function burstRelease(gen)
    dbg('Waiting for fresh gen iron before burst...')

    local freshDrop = nil
    local waited = 0
    repeat
        task.wait(0.1)
        waited = waited + 0.1
        freshDrop = findGenDrop(gen)
    until freshDrop or waited >= 8 or not enabled

    if not freshDrop then
        dbg('No fresh gen iron — bursting anyway')
    else
        dbg('Fresh gen iron found — bursting')
    end

    for _, e in stashed do
        if e.drop and e.drop.Parent then
            if e.drop:IsA('BasePart') then
                e.drop.Anchored = false
                e.drop.CanCollide = true
                e.drop.Velocity = Vector3.zero
            end
            for _, part in e.drop:GetDescendants() do
                if part:IsA('BasePart') then
                    part.Anchored = false
                    part.CanCollide = true
                    part.Velocity = Vector3.zero
                end
            end
            e.drop.CFrame = CFrame.new(gen.pos + Vector3.new(0, 1, 0))
            e.drop:SetAttribute('ClientDropTime', 0)
        end
    end
    table.clear(stashed)
    busy = false
    dbg('Burst done — check if spawn moved')
end

--== Enable / disable (was the module Function callback) =====================
local function start()
    table.clear(debugLog)
    table.clear(stashed)
    busy = false
    dbg('=== Gen Block ENABLED — stand at your gen ===')

    local releaseAt = nil

    repeat
        if isAlive() then
            for i = #stashed, 1, -1 do
                if not stashed[i].drop or not stashed[i].drop.Parent then
                    table.remove(stashed, i)
                end
            end

            local gen = findNearestTeamGen()
            if gen then
                if #stashed < CONFIG.StashCount then
                    stashFromInventory(gen)
                    maintainStashed()
                    releaseAt = nil
                else
                    if not releaseAt then
                        releaseAt = tick()
                        dbg('Stash full (' .. #stashed .. ') — triggering burst')
                    elseif tick() >= releaseAt then
                        burstRelease(gen)
                        releaseAt = nil
                        task.wait(4)
                    else
                        maintainStashed()
                    end
                end
            else
                maintainStashed()
            end
        end
        task.wait(0.15)
    until not enabled

    for _, e in stashed do
        if e.drop and e.drop.Parent then
            if e.drop:IsA('BasePart') then e.drop.Anchored = false e.drop.CanCollide = true end
            for _, part in e.drop:GetDescendants() do
                if part:IsA('BasePart') then part.Anchored = false part.CanCollide = true end
            end
            e.drop:SetAttribute('ClientDropTime', 0)
        end
    end
    table.clear(stashed)
    dbg('=== Gen Block DISABLED ===')
end

local function setEnabled(state)
    if state == enabled then return end
    enabled = state
    if enabled then
        mainThread = task.spawn(start)
    end
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == CONFIG.ToggleKey then
        setEnabled(not enabled)
    end
end)

print(string.format('[GenBlock] Loaded. Press %s to toggle.', CONFIG.ToggleKey.Name))
