local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local lplr = playersService.LocalPlayer

local PREFIX = '[SwordScanner]'
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

local function clearLog()
    table.clear(buffer)
    print(PREFIX, 'Log cleared.')
end

local function logPartDetails(part, indent)
    indent = indent or 0
    local pad = string.rep('  ', indent)

    local info = part.ClassName
    if part:IsA('BasePart') then
        info ..= string.format(' | Size=%s | Color=%s | Material=%s | Transparency=%.2f',
            tostring(part.Size),
            tostring(part.Color),
            tostring(part.Material),
            part.Transparency
        )
    end
    if part:IsA('MeshPart') then
        info ..= string.format(' | MeshId=%s | TextureID=%s',
            tostring(part.MeshId),
            tostring(part.TextureID)
        )
    end

    log(pad .. part.Name .. ' (' .. info .. ')')

    if part:IsA('BasePart') then
        for _, child in part:GetChildren() do
            if child:IsA('SpecialMesh') then
                log(pad .. '  SpecialMesh: MeshId=' .. tostring(child.MeshId) .. ' TextureId=' .. tostring(child.TextureId) .. ' Scale=' .. tostring(child.Scale))
            elseif child:IsA('SurfaceAppearance') then
                log(pad .. '  SurfaceAppearance: ColorMap=' .. tostring(child.ColorMap) .. ' NormalMap=' .. tostring(child.NormalMap))
            elseif child:IsA('Texture') or child:IsA('Decal') then
                log(pad .. '  ' .. child.ClassName .. ': Texture=' .. tostring(child.Texture) .. ' Face=' .. tostring(child.Face))
            end
        end
    end

    for _, child in part:GetChildren() do
        if child:IsA('BasePart') or child:IsA('Model') or child:IsA('Accessory') then
            logPartDetails(child, indent + 1)
        end
    end
end

local function logWelds(parent, indent)
    indent = indent or 0
    local pad = string.rep('  ', indent)
    for _, v in parent:GetDescendants() do
        if v:IsA('WeldConstraint') then
            log(pad .. string.format('WeldConstraint: Part0=%s Part1=%s',
                v.Part0 and v.Part0.Name or 'nil',
                v.Part1 and v.Part1.Name or 'nil'
            ))
        elseif v:IsA('Weld') or v:IsA('Motor6D') then
            local x0, y0, z0 = v.C0:ToEulerAnglesXYZ()
            local x1, y1, z1 = v.C1:ToEulerAnglesXYZ()
            log(pad .. string.format('%s: Part0=%s Part1=%s', v.ClassName,
                v.Part0 and v.Part0.Name or 'nil',
                v.Part1 and v.Part1.Name or 'nil'
            ))
            log(pad .. string.format('  C0: Pos=%s Rot=(%.1f, %.1f, %.1f) deg',
                tostring(v.C0.Position), math.deg(x0), math.deg(y0), math.deg(z0)))
            log(pad .. string.format('  C1: Pos=%s Rot=(%.1f, %.1f, %.1f) deg',
                tostring(v.C1.Position), math.deg(x1), math.deg(y1), math.deg(z1)))
        end
    end
end

local function scanPlayerSword(player)
    local char = player.Character
    if not char then return false end

    local found = false
    for _, child in char:GetChildren() do
        local isSword = false
        pcall(function()
            local ItemMeta = require(replicatedStorage.TS.item['item-meta']).items
            if ItemMeta[child.Name] and ItemMeta[child.Name].sword then
                isSword = true
            end
        end)
        if not isSword and not child.Name:find('sword') then
            continue
        end

        found = true
        log('========================================')
        log('PLAYER: ' .. player.Name .. ' (' .. player.DisplayName .. ')')
        log('SWORD: ' .. child.Name)

        local skinAttr = child:GetAttribute('ItemSkin')
        if skinAttr then
            log('SKIN ATTRIBUTE: ' .. tostring(skinAttr))
        end

        log('')
        log('-- FULL TREE --')
        logPartDetails(child, 1)

        log('')
        log('-- WELDS --')
        logWelds(child, 1)

        log('')
        log('-- ALL MESH IDS --')
        for _, v in child:GetDescendants() do
            if v:IsA('MeshPart') and v.MeshId ~= '' then
                log('  ' .. v:GetFullName())
                log('    MeshId: ' .. v.MeshId)
                log('    TextureID: ' .. tostring(v.TextureID))
                log('    Size: ' .. tostring(v.Size))
                log('    Color: ' .. tostring(v.Color))
            elseif v:IsA('SpecialMesh') and v.MeshId ~= '' then
                log('  ' .. v:GetFullName())
                log('    MeshId: ' .. v.MeshId)
                log('    TextureId: ' .. tostring(v.TextureId))
                log('    Scale: ' .. tostring(v.Scale))
            end
        end

        log('')
        log('-- ALL TEXTURES --')
        for _, v in child:GetDescendants() do
            if v:IsA('SurfaceAppearance') then
                log('  ' .. v:GetFullName())
                log('    ColorMap: ' .. tostring(v.ColorMap))
                log('    NormalMap: ' .. tostring(v.NormalMap))
                log('    MetalnessMap: ' .. tostring(v.MetalnessMap))
                log('    RoughnessMap: ' .. tostring(v.RoughnessMap))
            elseif (v:IsA('Texture') or v:IsA('Decal')) and v.Texture ~= '' then
                log('  ' .. v:GetFullName())
                log('    Texture: ' .. v.Texture)
            end
        end

        log('========================================')
    end
    return found
end

local function scanAll()
    table.clear(buffer)
    log('=== SWORD SKIN SCANNER ===')
    log('Scanning all players for sword skins...')
    log('')

    local count = 0
    for _, player in playersService:GetPlayers() do
        if scanPlayerSword(player) then
            count += 1
        end
    end

    if count == 0 then
        log('No players found holding swords. Make sure players have swords equipped.')
    else
        log('')
        log('Found swords on ' .. count .. ' player(s).')
    end

    copyLog()
end

local function scanPlayer(name)
    table.clear(buffer)
    local player = playersService:FindFirstChild(name)
    if not player then
        log('Player "' .. name .. '" not found.')
        copyLog()
        return
    end
    if not scanPlayerSword(player) then
        log('Player "' .. name .. '" has no sword equipped.')
    end
    copyLog()
end

local function scanReplicatedSkins(filter)
    table.clear(buffer)
    log('=== REPLICATED STORAGE SWORD SKINS ===')
    log('Filter: ' .. (filter or 'all swords'))
    log('')

    local count = 0
    for _, item in replicatedStorage.Items:GetChildren() do
        if not item:FindFirstChild('Handle') then continue end
        if not item.Name:find('sword') then continue end
        if filter and not item.Name:lower():find(filter:lower()) then continue end

        count += 1
        log('--- ' .. item.Name .. ' ---')
        logPartDetails(item, 1)

        for _, v in item:GetDescendants() do
            if v:IsA('MeshPart') and v.MeshId ~= '' then
                log('  MeshId: ' .. v.MeshId)
                log('  TextureID: ' .. tostring(v.TextureID))
                log('  Size: ' .. tostring(v.Size))
            end
        end
        log('')
    end

    log('Total sword skins found: ' .. count)
    copyLog()
end

local function watchSwords()
    log('=== WATCHING FOR SWORD EQUIPS ===')
    log('Will scan any player who equips a sword...')

    local connections = {}
    for _, player in playersService:GetPlayers() do
        if player == lplr then continue end
        local char = player.Character
        if char then
            table.insert(connections, char.ChildAdded:Connect(function(child)
                task.defer(function()
                    if child.Name:find('sword') or child:GetAttribute('ItemSkin') then
                        task.wait(0.3)
                        scanPlayerSword(player)
                        copyLog()
                    end
                end)
            end))
        end
        table.insert(connections, player.CharacterAdded:Connect(function(newChar)
            table.insert(connections, newChar.ChildAdded:Connect(function(child)
                task.defer(function()
                    if child.Name:find('sword') or child:GetAttribute('ItemSkin') then
                        task.wait(0.3)
                        scanPlayerSword(player)
                        copyLog()
                    end
                end)
            end))
        end))
    end

    table.insert(connections, playersService.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(newChar)
            table.insert(connections, newChar.ChildAdded:Connect(function(child)
                task.defer(function()
                    if child.Name:find('sword') or child:GetAttribute('ItemSkin') then
                        task.wait(0.3)
                        scanPlayerSword(player)
                        copyLog()
                    end
                end)
            end))
        end)
    end))

    getgenv().SwordScannerStopWatch = function()
        for _, conn in connections do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(connections)
        print(PREFIX, 'Stopped watching.')
    end

    print(PREFIX, 'Watching. Call getgenv().SwordScannerStopWatch() to stop.')
end

getgenv().SwordScan = scanAll
getgenv().SwordScanPlayer = scanPlayer
getgenv().SwordScanSkins = scanReplicatedSkins
getgenv().SwordWatch = watchSwords
getgenv().SwordScanCopy = copyLog
getgenv().SwordScanClear = clearLog

print(PREFIX, '=============================')
print(PREFIX, '  Sword Skin Scanner')
print(PREFIX, '=============================')
print(PREFIX, 'Commands:')
print(PREFIX, '  getgenv().SwordScan()              — scan all players now')
print(PREFIX, '  getgenv().SwordScanPlayer("name")   — scan one player')
print(PREFIX, '  getgenv().SwordScanSkins()          — list all sword skins in ReplicatedStorage')
print(PREFIX, '  getgenv().SwordScanSkins("rabbit")  — filter skins by name')
print(PREFIX, '  getgenv().SwordWatch()              — auto-scan when anyone equips a sword')
print(PREFIX, '  getgenv().SwordScanCopy()            — copy log to clipboard')
print(PREFIX, '')
print(PREFIX, 'All scans auto-copy to clipboard.')
