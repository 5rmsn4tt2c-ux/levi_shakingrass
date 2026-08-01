local cloneref = cloneref or function(obj) return obj end
local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local lplr = playersService.LocalPlayer
local gameCamera = workspace.CurrentCamera

local PREFIX = '[WeldTest]'
local currentReskins = {}
local lastRx, lastRy, lastRz = -math.pi, 0, -math.pi
local lastPx, lastPy, lastPz = 0, 0, 0

local function cleanAll()
    for _, entry in currentReskins do
        pcall(function()
            if entry.Reskin and entry.Reskin.Parent then
                entry.Reskin:Destroy()
            end
            for part, t in entry.Hidden do
                pcall(function() part.Transparency = t end)
            end
        end)
    end
    table.clear(currentReskins)
end

local function findSkinFor(itemName)
    for _, skin in replicatedStorage.Items:GetChildren() do
        if skin.Name:find('sword') and skin.Name:find('pixel') and skin:FindFirstChild('Handle') then
            for _, tier in {'wood', 'stone', 'iron', 'diamond', 'emerald'} do
                if itemName:find(tier) and skin.Name:find(tier) then
                    return skin
                end
            end
        end
    end
    for _, skin in replicatedStorage.Items:GetChildren() do
        if skin.Name:find('pixel') and skin.Name:find('wood_sword') and skin:FindFirstChild('Handle') then
            return skin
        end
    end
end

local function applySkin(item, rx, ry, rz, px, py, pz)
    local origHandle = item:FindFirstChild('Handle')
    if not origHandle then return end

    local skinSource = findSkinFor(item.Name)
    if not skinSource then
        print(PREFIX, 'No skin found for ' .. item.Name)
        return
    end

    local hidden = {}
    for _, v in item:GetDescendants() do
        if v:IsA('BasePart') then
            hidden[v] = v.Transparency
            v.Transparency = 1
        end
    end

    local reskin = Instance.new('Accessory')
    reskin.Name = 'LOCAL_ITEM_RESKIN'

    local skinHandle = skinSource.Handle:Clone()
    skinHandle.Parent = reskin

    for _, v in reskin:GetDescendants() do
        pcall(function() v.Anchored = false end)
        pcall(function() v.CanCollide = false end)
    end

    local weld = Instance.new('Weld')
    weld.Part0 = origHandle
    weld.Part1 = skinHandle
    weld.C0 = CFrame.new(px, py, pz) * CFrame.Angles(rx, ry, rz)
    weld.C1 = CFrame.new()
    weld.Parent = skinHandle

    reskin.Parent = item

    table.insert(currentReskins, {Reskin = reskin, Hidden = hidden})
    print(PREFIX, string.format('Applied: C0 = CFrame.new(%.1f,%.1f,%.1f) * Angles(%.2f,%.2f,%.2f) | Skin: %s',
        px, py, pz, rx, ry, rz, skinSource.Name))
end

local function tryAll(rx, ry, rz, px, py, pz)
    cleanAll()
    lastRx, lastRy, lastRz = rx, ry, rz
    lastPx, lastPy, lastPz = px, py, pz

    local found = false
    local char = lplr.Character
    if char then
        for _, child in char:GetChildren() do
            if child.Name:find('sword') and child:FindFirstChild('Handle') then
                applySkin(child, rx, ry, rz, px, py, pz)
                found = true
            end
        end
    end

    pcall(function()
        local vm = gameCamera.Viewmodel
        if vm then
            for _, child in vm:GetChildren() do
                if child.Name:find('sword') and child:FindFirstChild('Handle') then
                    applySkin(child, rx, ry, rz, px, py, pz)
                    found = true
                end
            end
        end
    end)

    if not found then
        print(PREFIX, 'No sword found! Equip a sword first.')
    end
end

getgenv().TryWeld = function(rx, ry, rz, px, py, pz)
    tryAll(rx or 0, ry or 0, rz or 0, px or 0, py or 0, pz or 0)
end

getgenv().MoveX = function(v) tryAll(lastRx, lastRy, lastRz, lastPx + v, lastPy, lastPz) end
getgenv().MoveY = function(v) tryAll(lastRx, lastRy, lastRz, lastPx, lastPy + v, lastPz) end
getgenv().MoveZ = function(v) tryAll(lastRx, lastRy, lastRz, lastPx, lastPy, lastPz + v) end

getgenv().RotX = function(v) tryAll(lastRx + v, lastRy, lastRz, lastPx, lastPy, lastPz) end
getgenv().RotY = function(v) tryAll(lastRx, lastRy + v, lastRz, lastPx, lastPy, lastPz) end
getgenv().RotZ = function(v) tryAll(lastRx, lastRy, lastRz + v, lastPx, lastPy, lastPz) end

getgenv().WeldClean = cleanAll

getgenv().WeldInfo = function()
    print(PREFIX, string.format('Current: CFrame.new(%.2f, %.2f, %.2f) * CFrame.Angles(%.4f, %.4f, %.4f)',
        lastPx, lastPy, lastPz, lastRx, lastRy, lastRz))
end

local pi = math.pi

print(PREFIX, '=============================')
print(PREFIX, '  Weld Tester v2')
print(PREFIX, '=============================')
print(PREFIX, '')
print(PREFIX, 'STEP 1: Equip sword, then start with old rotation:')
print(PREFIX, '  getgenv().TryWeld(-math.pi, 0, -math.pi)')
print(PREFIX, '')
print(PREFIX, 'STEP 2: Nudge POSITION with:')
print(PREFIX, '  getgenv().MoveX(1)   or  MoveX(-1)')
print(PREFIX, '  getgenv().MoveY(1)   or  MoveY(-1)')
print(PREFIX, '  getgenv().MoveZ(1)   or  MoveZ(-1)')
print(PREFIX, '  (use 0.5 or 0.25 for smaller nudges)')
print(PREFIX, '')
print(PREFIX, 'STEP 3: Nudge ROTATION with:')
print(PREFIX, '  getgenv().RotX(math.pi/2)   — rotate 90 on X')
print(PREFIX, '  getgenv().RotY(math.pi/2)   — rotate 90 on Y')
print(PREFIX, '  getgenv().RotZ(math.pi/2)   — rotate 90 on Z')
print(PREFIX, '')
print(PREFIX, 'OTHER:')
print(PREFIX, '  getgenv().WeldInfo()    — print current values')
print(PREFIX, '  getgenv().WeldClean()   — remove skin')
print(PREFIX, '')
print(PREFIX, 'When it looks right, run WeldInfo() and paste the output!')
