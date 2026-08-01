local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local lplr = playersService.LocalPlayer
local gameCamera = workspace.CurrentCamera

local PREFIX = '[OffsetCalc]'
local buffer = {}

local function log(...)
    local parts = {}
    for _, v in {...} do
        table.insert(parts, tostring(v))
    end
    local line = table.concat(parts, ' ')
    table.insert(buffer, line)
    print(PREFIX, line)
end

local function copyLog()
    local text = table.concat(buffer, '\n')
    pcall(setclipboard, text)
    print(PREFIX, 'Copied ' .. #buffer .. ' lines to clipboard!')
end

local Tiers = {'wood', 'stone', 'iron', 'diamond', 'emerald'}

local function getHandleInfo(handle)
    local info = {}
    info.Size = handle.Size
    info.CFrame = handle.CFrame
    info.Position = handle.Position
    info.ClassName = handle.ClassName
    pcall(function() info.MeshSize = handle.MeshSize end)
    pcall(function() info.PivotOffset = handle:GetPivot() end)
    pcall(function()
        local ext = handle.ExtentsSize
        if ext then info.ExtentsSize = ext end
    end)
    return info
end

local function logHandleInfo(label, handle)
    log(string.format('  %s:', label))
    log(string.format('    ClassName: %s', handle.ClassName))
    log(string.format('    Size: %s', tostring(handle.Size)))
    log(string.format('    Position: %s', tostring(handle.Position)))
    pcall(function()
        if handle:IsA('MeshPart') then
            log(string.format('    MeshSize: %s', tostring(handle.MeshSize)))
            log(string.format('    MeshId: %s', tostring(handle.MeshId)))
        end
    end)
    pcall(function()
        local pivot = handle:GetPivot()
        local rx, ry, rz = pivot:ToEulerAnglesXYZ()
        log(string.format('    Pivot Position: %s', tostring(pivot.Position)))
        log(string.format('    Pivot Rotation: (%.2f, %.2f, %.2f) deg', math.deg(rx), math.deg(ry), math.deg(rz)))
    end)
    pcall(function()
        log(string.format('    PivotOffset: %s', tostring(handle.PivotOffset)))
    end)
    pcall(function()
        local cf = handle.CFrame
        local rx, ry, rz = cf:ToEulerAnglesXYZ()
        log(string.format('    CFrame Pos: %s', tostring(cf.Position)))
        log(string.format('    CFrame Rot: (%.2f, %.2f, %.2f) deg', math.deg(rx), math.deg(ry), math.deg(rz)))
    end)
end

local function scanAll()
    table.clear(buffer)
    log('╔══════════════════════════════════════════════╗')
    log('║   SKIN OFFSET CALCULATOR                     ║')
    log('╚══════════════════════════════════════════════╝')
    log('')

    local char = lplr.Character
    if not char then
        log('No character found!')
        copyLog()
        return
    end

    local origSword = nil
    local origTier = nil
    for _, child in char:GetChildren() do
        pcall(function()
            local ItemMeta = require(replicatedStorage.TS.item['item-meta']).items
            if ItemMeta[child.Name] and ItemMeta[child.Name].sword and child:FindFirstChild('Handle') then
                origSword = child
                for _, tier in Tiers do
                    if child.Name:find(tier) then
                        origTier = tier
                        break
                    end
                end
            end
        end)
        if origSword then break end
    end

    if not origSword then
        log('No sword equipped! Equip a sword first.')
        copyLog()
        return
    end

    local origHandle = origSword:FindFirstChild('Handle')
    log('EQUIPPED SWORD: ' .. origSword.Name .. ' (tier: ' .. (origTier or '?') .. ')')
    logHandleInfo('Original Handle', origHandle)
    log('')

    local SkinMap = {}
    local SetNames = {}
    local SetList = {}

    for _, item in replicatedStorage.Items:GetChildren() do
        if item.Name:find('sword') and item:FindFirstChild('Handle') then
            SkinMap[item.Name] = item
        end
    end

    for skinName in SkinMap do
        for _, tier in Tiers do
            local tierSword = tier .. '_sword'
            if skinName:find(tierSword) then
                local setName = skinName:gsub('_?' .. tierSword .. '_?', ''):gsub('^_+', ''):gsub('_+$', '')
                if setName == '' then continue end
                if not SetNames[setName] then
                    SetNames[setName] = {}
                    table.insert(SetList, setName)
                end
                SetNames[setName][tier] = skinName
                break
            end
        end
    end

    table.sort(SetList)

    log('━━━ OFFSET COMPARISON FOR EACH SKIN SET ━━━')
    log('')

    for _, setName in SetList do
        local set = SetNames[setName]
        local skinName = set[origTier]
        if not skinName then
            for _, fallback in Tiers do
                if set[fallback] then
                    skinName = set[fallback]
                    break
                end
            end
        end
        if not skinName then continue end

        local skinSource = SkinMap[skinName]
        if not skinSource then continue end

        local skinHandle = skinSource:FindFirstChild('Handle')
        if not skinHandle then continue end

        log(string.format('SET: %s  |  Skin: %s', setName, skinName))
        logHandleInfo('Skin Handle', skinHandle)

        local origY = origHandle.Size.Y
        local skinY = skinHandle.Size.Y
        local sizeDiff = skinY - origY

        pcall(function()
            if origHandle:IsA('MeshPart') and skinHandle:IsA('MeshPart') then
                local origMeshY = origHandle.MeshSize.Y
                local skinMeshY = skinHandle.MeshSize.Y
                log(string.format('    MeshSize Y diff: %.3f (skin) - %.3f (orig) = %.3f', skinMeshY, origMeshY, skinMeshY - origMeshY))
            end
        end)

        log(string.format('    Size Y diff: %.3f (skin) - %.3f (orig) = %.3f', skinY, origY, sizeDiff))

        pcall(function()
            local origPivot = origHandle.PivotOffset
            local skinPivot = skinHandle.PivotOffset
            if origPivot and skinPivot then
                local pivotDiff = skinPivot.Position - origPivot.Position
                log(string.format('    PivotOffset diff: (%.3f, %.3f, %.3f)', pivotDiff.X, pivotDiff.Y, pivotDiff.Z))
            end
        end)

        local suggestedY = sizeDiff / 2
        log(string.format('    >>> Suggested Y offset: %.2f  (half size diff)', suggestedY))
        log('')
    end

    log('')
    log('━━━ QUICK REFERENCE TABLE ━━━')
    log(string.format('%-25s %-10s %-10s %-12s', 'Set Name', 'SkinSizeY', 'OrigSizeY', 'SuggestedY'))
    log(string.rep('-', 60))

    for _, setName in SetList do
        local set = SetNames[setName]
        local skinName = set[origTier]
        if not skinName then
            for _, fallback in Tiers do
                if set[fallback] then
                    skinName = set[fallback]
                    break
                end
            end
        end
        if not skinName then continue end

        local skinSource = SkinMap[skinName]
        if not skinSource then continue end
        local skinHandle = skinSource:FindFirstChild('Handle')
        if not skinHandle then continue end

        local origY = origHandle.Size.Y
        local skinY = skinHandle.Size.Y
        local suggested = (skinY - origY) / 2

        log(string.format('%-25s %-10.3f %-10.3f %-12.3f', setName, skinY, origY, suggested))
    end

    log('')
    log('NOTE: Suggested Y is (SkinSizeY - OrigSizeY) / 2')
    log('This is a starting point — paste this output and we can fine-tune!')

    copyLog()
end

local function scanTier(tierName)
    table.clear(buffer)
    log('╔══════════════════════════════════════════════╗')
    log('║   TIER OFFSET SCAN: ' .. tierName)
    log('╚══════════════════════════════════════════════╝')
    log('')

    local SkinMap = {}
    local SetNames = {}
    local SetList = {}

    for _, item in replicatedStorage.Items:GetChildren() do
        if item.Name:find('sword') and item:FindFirstChild('Handle') then
            SkinMap[item.Name] = item
        end
    end

    for skinName in SkinMap do
        for _, tier in Tiers do
            local tierSword = tier .. '_sword'
            if skinName:find(tierSword) then
                local setName = skinName:gsub('_?' .. tierSword .. '_?', ''):gsub('^_+', ''):gsub('_+$', '')
                if setName == '' then continue end
                if not SetNames[setName] then
                    SetNames[setName] = {}
                    table.insert(SetList, setName)
                end
                SetNames[setName][tier] = skinName
                break
            end
        end
    end

    table.sort(SetList)

    local origName = tierName .. '_sword'
    local origSource = SkinMap[origName]
    if not origSource then
        log('Could not find original: ' .. origName)
        copyLog()
        return
    end

    local origHandle = origSource:FindFirstChild('Handle')
    log('ORIGINAL: ' .. origName)
    logHandleInfo('Handle', origHandle)
    log('')

    log(string.format('%-25s %-10s %-10s %-12s', 'Set Name', 'SkinSizeY', 'OrigSizeY', 'SuggestedY'))
    log(string.rep('-', 60))

    for _, setName in SetList do
        local set = SetNames[setName]
        local skinName = set[tierName]
        if not skinName then continue end

        local skinSource = SkinMap[skinName]
        if not skinSource then continue end
        local skinHandle = skinSource:FindFirstChild('Handle')
        if not skinHandle then continue end

        local origY = origHandle.Size.Y
        local skinY = skinHandle.Size.Y
        local suggested = (skinY - origY) / 2

        log(string.format('%-25s %-10.3f %-10.3f %-12.3f', setName, skinY, origY, suggested))
    end

    copyLog()
end

getgenv().OffsetCalc = scanAll
getgenv().OffsetTier = scanTier

print(PREFIX, '=============================')
print(PREFIX, '  Skin Offset Calculator')
print(PREFIX, '=============================')
print(PREFIX, '')
print(PREFIX, 'Commands:')
print(PREFIX, '  getgenv().OffsetCalc()            — scan your equipped sword vs all skins')
print(PREFIX, '  getgenv().OffsetTier("wood")      — scan all skins for a specific tier')
print(PREFIX, '  getgenv().OffsetTier("iron")      — scan all skins for iron tier')
print(PREFIX, '')
print(PREFIX, 'Auto-copies to clipboard.')
print(PREFIX, 'Equip a sword, then run OffsetCalc()!')
