local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local runService = cloneref(game:GetService('RunService'))
local lplr = playersService.LocalPlayer
local gameCamera = workspace.CurrentCamera

local PREFIX = '[SkinDebug]'
local connections = {}
local buffer = {}

local function log(...)
    local parts = {}
    for _, v in {... } do
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

local function clearLog()
    table.clear(buffer)
    print(PREFIX, 'Log cleared.')
end

local function logTree(instance, indent)
    indent = indent or 0
    local pad = string.rep('  ', indent)
    local info = instance.ClassName
    if instance:IsA('BasePart') then
        info ..= string.format(' | Size=%s | Transparency=%.2f | Anchored=%s | CanCollide=%s',
            tostring(instance.Size),
            instance.Transparency,
            tostring(instance.Anchored),
            tostring(instance.CanCollide)
        )
    end
    log(pad .. instance.Name .. ' (' .. info .. ')')
    for _, child in instance:GetChildren() do
        logTree(child, indent + 1)
    end
end

local function logCFrame(label, cf)
    local x, y, z = cf:ToEulerAnglesXYZ()
    log(string.format('  %s: Position=%s | Rotation=(%.1f, %.1f, %.1f) deg',
        label,
        tostring(cf.Position),
        math.deg(x), math.deg(y), math.deg(z)
    ))
end

local function logWelds(parent)
    for _, v in parent:GetDescendants() do
        if v:IsA('WeldConstraint') then
            log(string.format('  Weld: Part0=%s Part1=%s Enabled=%s',
                v.Part0 and v.Part0.Name or 'nil',
                v.Part1 and v.Part1.Name or 'nil',
                tostring(v.Enabled)
            ))
        elseif v:IsA('Weld') or v:IsA('Motor6D') then
            log(string.format('  %s: Part0=%s Part1=%s', v.ClassName,
                v.Part0 and v.Part0.Name or 'nil',
                v.Part1 and v.Part1.Name or 'nil'
            ))
            if v.C0 then logCFrame(v.Name .. '.C0', v.C0) end
            if v.C1 then logCFrame(v.Name .. '.C1', v.C1) end
        end
    end
end

local function dumpSkinAssets()
    log('=== AVAILABLE SKIN ASSETS ===')
    local items = replicatedStorage:FindFirstChild('Items')
    if items then
        local count = 0
        for _, item in items:GetChildren() do
            if item:FindFirstChild('Handle') then
                count += 1
                if count <= 30 then
                    log('  Items/' .. item.Name .. ' — Handle children: ' .. #item.Handle:GetChildren())
                end
            end
        end
        log('  Total items with Handle: ' .. count)
    else
        log('  replicatedStorage.Items not found')
    end

    local blocks = replicatedStorage:FindFirstChild('Assets')
    if blocks then
        blocks = blocks:FindFirstChild('Blocks')
        if blocks then
            log('  Assets/Blocks children: ' .. #blocks:GetChildren())
        end
    end
    log('=== END SKIN ASSETS ===')
end

local function scanItem(model, parent)
    log('--- ITEM SCAN ---')
    log('Item: ' .. model.Name .. ' | Parent: ' .. parent.Name)

    local handle = model:FindFirstChild('Handle')
    if handle then
        log('Has Handle: true')
        logCFrame('Handle CFrame', handle.CFrame)
    else
        log('Has Handle: false')
    end

    local rightHand = parent:FindFirstChild('RightHand')
    if rightHand then
        logCFrame('RightHand CFrame', rightHand.CFrame)
        if handle then
            local offset = rightHand.CFrame:ToObjectSpace(handle.CFrame)
            logCFrame('Handle offset from RightHand', offset)
        end
    end

    local skinAttr = model:GetAttribute('ItemSkin')
    if skinAttr then
        log('ItemSkin attribute: ' .. tostring(skinAttr))
    end

    log('Model tree:')
    logTree(model, 1)

    log('Welds in model:')
    logWelds(model)

    for _, child in model:GetChildren() do
        if child:IsA('Model') then
            log('Found sub-model (likely skin): ' .. child.Name)
            log('Sub-model tree:')
            logTree(child, 2)
            log('Sub-model welds:')
            logWelds(child)
            if child:FindFirstChild('Handle') then
                logCFrame('Skin Handle CFrame', child.Handle.CFrame)
                if rightHand then
                    local skinOffset = rightHand.CFrame:ToObjectSpace(child.Handle.CFrame)
                    logCFrame('Skin offset from RightHand', skinOffset)
                end
            end
        end
    end
    log('--- END ITEM SCAN ---')
    copyLog()
end

local function watchCharacter(char)
    log('Watching character: ' .. char.Name)
    table.insert(connections, char.ChildAdded:Connect(function(child)
        task.defer(function()
            if child:IsA('Model') or child:FindFirstChild('Handle') then
                log('New item in Character: ' .. child.Name)
                task.wait(0.5)
                scanItem(child, char)
            end
        end)
    end))

    for _, child in char:GetChildren() do
        if child:FindFirstChild('Handle') or child:GetAttribute('ItemSkin') then
            scanItem(child, char)
        end
    end
end

local function watchViewmodel()
    local vm = gameCamera:FindFirstChild('Viewmodel')
    if not vm then
        log('Viewmodel not found yet, waiting...')
        vm = gameCamera:WaitForChild('Viewmodel', 30)
    end
    if not vm then
        log('Viewmodel not found after 30s')
        return
    end

    log('Watching Viewmodel')
    table.insert(connections, vm.ChildAdded:Connect(function(child)
        task.defer(function()
            if child:IsA('Model') or child:FindFirstChild('Handle') then
                log('New item in Viewmodel: ' .. child.Name)
                task.wait(0.5)
                scanItem(child, vm)
            end
        end)
    end))
end

local function watchBlocks()
    local map = workspace:FindFirstChild('Map')
    if not map then
        map = workspace:WaitForChild('Map', 60)
    end
    if not map then
        log('Map not found')
        return
    end

    local worlds = map:FindFirstChild('Worlds')
    local mapFolder = worlds and worlds:GetChildren()[1] or map
    local blocks = mapFolder and mapFolder:FindFirstChild('Blocks')
    if not blocks then
        log('Blocks folder not found')
        return
    end

    log('Watching blocks in: ' .. blocks:GetFullName())
    table.insert(connections, blocks.ChildAdded:Connect(function(v)
        task.defer(function()
            local skinAttr = v:GetAttribute('ItemSkin')
            if skinAttr then
                log('--- BLOCK SKIN ---')
                log('Block: ' .. v.Name .. ' | Skin: ' .. tostring(skinAttr))
                log('Block tree:')
                logTree(v, 1)

                for _, child in workspace:GetChildren() do
                    if child.Name == skinAttr or (child:IsA('Model') and child:GetAttribute('ItemSkin') == skinAttr) then
                        log('Found skin model in workspace: ' .. child.Name)
                        logTree(child, 1)
                        logCFrame('Skin pivot', child:GetPivot())
                    end
                end

                local base = v:FindFirstChild('Barrel') or v:FindFirstChild('Bottom') or v
                if base:IsA('BasePart') then
                    logCFrame('Base CFrame (' .. base.Name .. ')', base.CFrame)
                end
                log('--- END BLOCK SKIN ---')
                copyLog()
            end
        end)
    end))
end

local function start()
    log('=============================')
    log('  Skin Changer Debug Tool')
    log('=============================')
    log('Auto-copies to clipboard every time a skin is scanned.')
    log('Manual: getgenv().SkinDebugCopy() to copy anytime.')
    log('        getgenv().SkinDebugClear() to clear the log.')
    log('')

    dumpSkinAssets()
    copyLog()

    if lplr.Character then
        watchCharacter(lplr.Character)
    end
    table.insert(connections, lplr.CharacterAdded:Connect(function(char)
        watchCharacter(char)
    end))

    task.spawn(watchViewmodel)
    task.spawn(watchBlocks)

    log('Debug tool running. Swap items to see skin data.')
end

local function stop()
    copyLog()
    for _, conn in connections do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(connections)
    print(PREFIX, 'Stopped. Final log copied to clipboard.')
end

getgenv().SkinDebugStop = stop
getgenv().SkinDebugCopy = copyLog
getgenv().SkinDebugClear = clearLog

start()

return stop
