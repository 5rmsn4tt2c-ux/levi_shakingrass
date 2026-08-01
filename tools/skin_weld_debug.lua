local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local playersService = cloneref(game:GetService('Players'))
local lplr = playersService.LocalPlayer
local gameCamera = workspace.CurrentCamera

local PREFIX = '[WeldDebug]'
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

local function logCFrame(label, cf)
    local x, y, z = cf:ToEulerAnglesXYZ()
    log(string.format('  %s:', label))
    log(string.format('    Position: %s', tostring(cf.Position)))
    log(string.format('    Rotation: (%.2f, %.2f, %.2f) deg', math.deg(x), math.deg(y), math.deg(z)))
end

local function scanSword(item, parentName)
    log('')
    log('═══════════════════════════════════════')
    log('SWORD: ' .. item.Name .. ' in ' .. parentName)
    log('═══════════════════════════════════════')

    local handle = item:FindFirstChild('Handle')
    if handle then
        log('Original Handle:')
        log('  ClassName: ' .. handle.ClassName)
        log('  Size: ' .. tostring(handle.Size))
        log('  Transparency: ' .. tostring(handle.Transparency))
        log('  Position: ' .. tostring(handle.Position))
        logCFrame('Handle CFrame', handle.CFrame)
    else
        log('NO HANDLE FOUND')
    end

    local parent = item.Parent
    if parent then
        local rightHand = parent:FindFirstChild('RightHand')
        if rightHand then
            log('')
            log('RightHand:')
            logCFrame('RightHand CFrame', rightHand.CFrame)
            if handle then
                local offset = rightHand.CFrame:ToObjectSpace(handle.CFrame)
                logCFrame('Handle offset from RightHand', offset)
            end
        end
    end

    log('')
    log('-- ALL WELDS IN SWORD --')
    for _, v in item:GetDescendants() do
        if v:IsA('Weld') or v:IsA('Motor6D') then
            log(string.format('  %s "%s":', v.ClassName, v.Name))
            log(string.format('    Part0: %s (%s)', v.Part0 and v.Part0.Name or 'nil', v.Part0 and v.Part0.ClassName or ''))
            log(string.format('    Part1: %s (%s)', v.Part1 and v.Part1.Name or 'nil', v.Part1 and v.Part1.ClassName or ''))
            if v.C0 then logCFrame('C0', v.C0) end
            if v.C1 then logCFrame('C1', v.C1) end
        elseif v:IsA('WeldConstraint') then
            log(string.format('  WeldConstraint "%s":', v.Name))
            log(string.format('    Part0: %s', v.Part0 and v.Part0.Name or 'nil'))
            log(string.format('    Part1: %s', v.Part1 and v.Part1.Name or 'nil'))
            log(string.format('    Enabled: %s', tostring(v.Enabled)))
        end
    end

    local reskin = item:FindFirstChild('LOCAL_ITEM_RESKIN')
    if reskin then
        log('')
        log('-- LOCAL_ITEM_RESKIN FOUND --')
        log('  ClassName: ' .. reskin.ClassName)
        log('  Children: ' .. #reskin:GetChildren())

        local skinHandle = reskin:FindFirstChild('Handle')
        if skinHandle then
            log('  Skin Handle:')
            log('    ClassName: ' .. skinHandle.ClassName)
            log('    Size: ' .. tostring(skinHandle.Size))
            log('    Position: ' .. tostring(skinHandle.Position))
            log('    Transparency: ' .. tostring(skinHandle.Transparency))
            log('    Anchored: ' .. tostring(skinHandle.Anchored))
            log('    CanCollide: ' .. tostring(skinHandle.CanCollide))
            logCFrame('Skin Handle CFrame', skinHandle.CFrame)

            if handle then
                local skinOffset = handle.CFrame:ToObjectSpace(skinHandle.CFrame)
                logCFrame('Skin offset from OrigHandle', skinOffset)
                log(string.format('    Distance from orig: %.3f studs', (handle.Position - skinHandle.Position).Magnitude))
            end
        end

        log('')
        log('  -- WELDS INSIDE RESKIN --')
        for _, v in reskin:GetDescendants() do
            if v:IsA('Weld') or v:IsA('Motor6D') then
                log(string.format('    %s "%s":', v.ClassName, v.Name))
                log(string.format('      Part0: %s (parent=%s)', v.Part0 and v.Part0.Name or 'nil', v.Part0 and v.Part0.Parent and v.Part0.Parent.Name or 'nil'))
                log(string.format('      Part1: %s (parent=%s)', v.Part1 and v.Part1.Name or 'nil', v.Part1 and v.Part1.Parent and v.Part1.Parent.Name or 'nil'))
                if v.C0 then logCFrame('C0', v.C0) end
                if v.C1 then logCFrame('C1', v.C1) end
            elseif v:IsA('WeldConstraint') then
                log(string.format('    WeldConstraint "%s": Part0=%s Part1=%s Enabled=%s',
                    v.Name,
                    v.Part0 and v.Part0.Name or 'nil',
                    v.Part1 and v.Part1.Name or 'nil',
                    tostring(v.Enabled)
                ))
            end
        end

        log('')
        log('  -- ALL PARTS IN RESKIN --')
        for _, v in reskin:GetDescendants() do
            if v:IsA('BasePart') then
                log(string.format('    %s "%s": Size=%s Pos=%s Trans=%.2f Anchored=%s',
                    v.ClassName, v.Name,
                    tostring(v.Size),
                    tostring(v.Position),
                    v.Transparency,
                    tostring(v.Anchored)
                ))
            end
        end
    else
        log('')
        log('-- NO LOCAL_ITEM_RESKIN --')
    end

    log('')
    log('-- HIDDEN PARTS (Transparency=1) --')
    local hiddenCount = 0
    for _, v in item:GetDescendants() do
        if v:IsA('BasePart') and v.Transparency >= 1 then
            hiddenCount += 1
            log(string.format('  %s "%s" (parent=%s)', v.ClassName, v.Name, v.Parent.Name))
        end
    end
    if hiddenCount == 0 then
        log('  None')
    end

    log('═══════════════════════════════════════')
end

local function scan()
    table.clear(buffer)
    log('╔══════════════════════════════════════╗')
    log('║     SWORD WELD DEBUG SCANNER         ║')
    log('╚══════════════════════════════════════╝')
    log('')

    local found = false

    local char = lplr.Character
    if char then
        for _, child in char:GetChildren() do
            if child:FindFirstChild('Handle') then
                pcall(function()
                    local ItemMeta = require(game:GetService('ReplicatedStorage').TS.item['item-meta']).items
                    if ItemMeta[child.Name] and ItemMeta[child.Name].sword then
                        scanSword(child, 'Character')
                        found = true
                    end
                end)
                if not found and child.Name:find('sword') then
                    scanSword(child, 'Character')
                    found = true
                end
            end
        end
    end

    pcall(function()
        local vm = gameCamera.Viewmodel
        if vm then
            for _, child in vm:GetChildren() do
                if child:FindFirstChild('Handle') and child.Name:find('sword') then
                    scanSword(child, 'Viewmodel')
                    found = true
                end
            end
        end
    end)

    if not found then
        log('No sword found. Make sure you have a sword equipped.')
    end

    log('')
    log('Scan complete.')
    copyLog()
end

getgenv().WeldDebug = scan
getgenv().WeldDebugCopy = copyLog

print(PREFIX, '=============================')
print(PREFIX, '  Sword Weld Debug')
print(PREFIX, '=============================')
print(PREFIX, '')
print(PREFIX, 'Commands:')
print(PREFIX, '  getgenv().WeldDebug()  — scan your current sword + skin welds')
print(PREFIX, '')
print(PREFIX, 'Auto-copies to clipboard.')
print(PREFIX, 'Equip a sword with mannyx2 ON, then run WeldDebug()!')
