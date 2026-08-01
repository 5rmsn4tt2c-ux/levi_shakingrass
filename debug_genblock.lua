-- Gen Block Debug — run this standalone to inspect generators + nearby items
-- Auto-copies results to clipboard

local CollectionService = game:GetService('CollectionService')
local Players = game:GetService('Players')
local lplr = Players.LocalPlayer
local log = {}

local function add(msg)
    table.insert(log, msg)
end

local char = lplr.Character
local root = char and char:FindFirstChild('HumanoidRootPart')
if not root then
    add('ERROR: No character/root part found')
    if setclipboard then setclipboard(table.concat(log, '\n')) end
    return
end

local playerPos = root.Position
add('=== GEN BLOCK DEBUG ===')
add('Player position: ' .. tostring(playerPos))
add('')

-- Find all generators
add('--- GENERATORS ---')
local genCount = 0
for _, obj in workspace:GetDescendants() do
    if obj.Name == 'GeneratorAdornee' then
        local ok, id = pcall(function() return obj:GetAttribute('Id') end)
        if ok and id and type(id) == 'string' and id ~= '' then
            genCount = genCount + 1
            local dist = (obj.Position - playerPos).Magnitude
            add('Gen #' .. genCount)
            add('  ID: ' .. id)
            add('  Position: ' .. tostring(obj.Position))
            add('  Distance: ' .. string.format('%.1f', dist) .. ' studs')
            add('  Parent: ' .. tostring(obj.Parent and obj.Parent:GetFullName() or 'nil'))
            add('')
        end
    end
end
add('Total generators: ' .. genCount)
add('')

-- Find all ItemDrop tagged objects
add('--- ITEM DROPS ---')
local drops = CollectionService:GetTagged('ItemDrop')
local dropCount = 0
for _, drop in drops do
    if drop and drop.Parent then
        dropCount = dropCount + 1
        local pos = drop.Position
        if drop:FindFirstChild('Handle') then
            pos = drop.Handle.Position
        end
        local dist = (pos - playerPos).Magnitude
        local amount = drop:GetAttribute('Amount') or '?'
        local dropTime = drop:GetAttribute('ClientDropTime') or '?'
        local anchored = 'N/A'
        local canCollide = 'N/A'
        local velocity = 'N/A'
        if drop:IsA('BasePart') then
            anchored = tostring(drop.Anchored)
            canCollide = tostring(drop.CanCollide)
            velocity = tostring(drop.Velocity)
        elseif drop:FindFirstChild('Handle') then
            anchored = tostring(drop.Handle.Anchored)
            canCollide = tostring(drop.Handle.CanCollide)
            velocity = tostring(drop.Handle.Velocity)
        end

        add('Drop #' .. dropCount)
        add('  Name: ' .. drop.Name)
        add('  Position: ' .. tostring(pos))
        add('  Distance: ' .. string.format('%.1f', dist) .. ' studs')
        add('  Amount: ' .. tostring(amount))
        add('  Anchored: ' .. anchored)
        add('  CanCollide: ' .. canCollide)
        add('  Velocity: ' .. velocity)
        add('  ClientDropTime: ' .. tostring(dropTime))
        add('  Y relative to player: ' .. string.format('%.1f', pos.Y - playerPos.Y))

        -- Check if this drop is near any generator
        for _, gen in workspace:GetDescendants() do
            if gen.Name == 'GeneratorAdornee' then
                local gOk, gId = pcall(function() return gen:GetAttribute('Id') end)
                if gOk and gId and type(gId) == 'string' and gId ~= '' then
                    local genDist = (pos - gen.Position).Magnitude
                    if genDist < 20 then
                        local yDiff = gen.Position.Y - pos.Y
                        add('  >> NEAR GEN: ' .. gId)
                        add('     Gen dist: ' .. string.format('%.1f', genDist))
                        add('     Y below gen: ' .. string.format('%.1f', yDiff))
                    end
                end
            end
        end
        add('')
    end
end
add('Total item drops: ' .. dropCount)
add('')
add('=== END DEBUG ===')

local result = table.concat(log, '\n')
if setclipboard then
    setclipboard(result)
    print('[GenBlock Debug] Copied to clipboard!')
end
print(result)
