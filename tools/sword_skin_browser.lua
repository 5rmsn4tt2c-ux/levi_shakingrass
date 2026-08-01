local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))

local PREFIX = '[SkinBrowser]'
local buffer = {}
local allSkins = {}

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

local function dumpPart(part, indent)
    local pad = string.rep('  ', indent)
    local info = part.ClassName

    if part:IsA('MeshPart') then
        info ..= string.format('\n%s  MeshId: %s\n%s  TextureID: %s\n%s  Size: %s\n%s  Color: %s\n%s  Material: %s\n%s  Transparency: %.2f',
            pad, tostring(part.MeshId),
            pad, tostring(part.TextureID),
            pad, tostring(part.Size),
            pad, tostring(part.Color),
            pad, tostring(part.Material),
            pad, part.Transparency
        )
    elseif part:IsA('BasePart') then
        info ..= string.format(' | Size=%s | Color=%s | Transparency=%.2f',
            tostring(part.Size), tostring(part.Color), part.Transparency
        )
    end

    log(pad .. part.Name .. ' (' .. info .. ')')

    for _, child in part:GetChildren() do
        if child:IsA('SpecialMesh') then
            log(pad .. '  SpecialMesh: MeshId=' .. tostring(child.MeshId) .. ' TextureId=' .. tostring(child.TextureId) .. ' Scale=' .. tostring(child.Scale))
        elseif child:IsA('SurfaceAppearance') then
            log(pad .. '  SurfaceAppearance: ColorMap=' .. tostring(child.ColorMap))
        elseif child:IsA('Beam') then
            log(pad .. '  Beam: ' .. child.Name)
        end
    end

    for _, child in part:GetChildren() do
        if child:IsA('BasePart') then
            dumpPart(child, indent + 1)
        end
    end
end

local function scanAllSwordSkins()
    table.clear(buffer)
    table.clear(allSkins)

    log('╔══════════════════════════════════════╗')
    log('║     BEDWARS SWORD SKIN BROWSER       ║')
    log('╚══════════════════════════════════════╝')
    log('')

    local items = replicatedStorage:FindFirstChild('Items')
    if not items then
        log('ERROR: replicatedStorage.Items not found')
        copyLog()
        return
    end

    local swordSkins = {}
    for _, item in items:GetChildren() do
        if item.Name:find('sword') and item:FindFirstChild('Handle') then
            table.insert(swordSkins, item)
        end
    end

    table.sort(swordSkins, function(a, b) return a.Name < b.Name end)

    log('Found ' .. #swordSkins .. ' sword skins total')
    log('')

    local groups = {}
    for _, skin in swordSkins do
        local baseSword = skin.Name:match('_([%w_]*sword[%w_]*)$') or skin.Name
        local skinSet = skin.Name:gsub('_' .. baseSword, '')
        if skinSet == skin.Name then
            skinSet = 'default'
        end

        if not groups[skinSet] then
            groups[skinSet] = {}
        end
        table.insert(groups[skinSet], skin)
        table.insert(allSkins, skin.Name)
    end

    local sortedGroups = {}
    for name in groups do
        table.insert(sortedGroups, name)
    end
    table.sort(sortedGroups)

    for _, groupName in sortedGroups do
        log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
        log('SKIN SET: ' .. groupName)
        log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')

        for _, skin in groups[groupName] do
            log('')
            log('  ► ' .. skin.Name)
            log('    Children: ' .. #skin.Handle:GetChildren())

            local handle = skin.Handle
            if handle:IsA('MeshPart') then
                log('    Handle MeshId: ' .. tostring(handle.MeshId))
                log('    Handle TextureID: ' .. tostring(handle.TextureID))
                log('    Handle Size: ' .. tostring(handle.Size))
                log('    Handle Color: ' .. tostring(handle.Color))
                log('    Handle Material: ' .. tostring(handle.Material))
            end

            local meshCount, beamCount, partCount = 0, 0, 0
            for _, v in skin.Handle:GetDescendants() do
                if v:IsA('MeshPart') then
                    meshCount += 1
                    log('    SubMesh: ' .. v.Name .. ' | MeshId=' .. tostring(v.MeshId) .. ' | Size=' .. tostring(v.Size))
                elseif v:IsA('Beam') then
                    beamCount += 1
                elseif v:IsA('BasePart') then
                    partCount += 1
                end
            end

            if meshCount > 0 or beamCount > 0 or partCount > 0 then
                log(string.format('    Stats: %d sub-meshes, %d beams, %d parts', meshCount, beamCount, partCount))
            end
        end
        log('')
    end

    log('')
    log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    log('QUICK LIST (for mannyx2):')
    log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
    for i, name in allSkins do
        log(string.format('  %d. %s', i, name))
    end

    log('')
    log('Total: ' .. #allSkins .. ' sword skins')
    log('')
    log('To inspect one skin in detail:')
    log('  getgenv().SwordInspect("skin_name_here")')

    copyLog()
end

local function inspectSkin(skinName)
    table.clear(buffer)

    local items = replicatedStorage:FindFirstChild('Items')
    if not items then
        log('ERROR: Items not found')
        copyLog()
        return
    end

    local skin = items:FindFirstChild(skinName)
    if not skin then
        log('Skin "' .. skinName .. '" not found. Searching...')
        for _, item in items:GetChildren() do
            if item.Name:lower():find(skinName:lower()) and item.Name:find('sword') then
                skin = item
                log('Found match: ' .. item.Name)
                break
            end
        end
        if not skin then
            log('No sword skin found matching "' .. skinName .. '"')
            copyLog()
            return
        end
    end

    log('╔══════════════════════════════════════╗')
    log('║  SKIN DETAIL: ' .. skin.Name)
    log('╚══════════════════════════════════════╝')
    log('')

    log('Full tree:')
    dumpPart(skin, 1)

    log('')
    log('-- ALL MESH IDS (copy these to replicate) --')
    for _, v in skin:GetDescendants() do
        if v:IsA('MeshPart') then
            log('  Part: ' .. v.Name)
            log('    MeshId:    ' .. tostring(v.MeshId))
            log('    TextureID: ' .. tostring(v.TextureID))
            log('    Size:      ' .. tostring(v.Size))
            log('    Color:     ' .. tostring(v.Color))
            log('    Material:  ' .. tostring(v.Material))
            log('')
        end
    end

    log('-- ALL TEXTURES / APPEARANCES --')
    for _, v in skin:GetDescendants() do
        if v:IsA('SurfaceAppearance') then
            log('  SurfaceAppearance on ' .. v.Parent.Name)
            log('    ColorMap:     ' .. tostring(v.ColorMap))
            log('    NormalMap:    ' .. tostring(v.NormalMap))
            log('    MetalnessMap: ' .. tostring(v.MetalnessMap))
            log('    RoughnessMap: ' .. tostring(v.RoughnessMap))
            log('')
        elseif v:IsA('SpecialMesh') then
            log('  SpecialMesh on ' .. v.Parent.Name)
            log('    MeshId:    ' .. tostring(v.MeshId))
            log('    TextureId: ' .. tostring(v.TextureId))
            log('    Scale:     ' .. tostring(v.Scale))
            log('')
        end
    end

    log('-- BEAMS --')
    local beamCount = 0
    for _, v in skin:GetDescendants() do
        if v:IsA('Beam') then
            beamCount += 1
            log('  ' .. v.Name .. ' on ' .. v.Parent.Name)
            pcall(function()
                log('    Texture: ' .. tostring(v.Texture))
                log('    Width0: ' .. tostring(v.Width0) .. ' Width1: ' .. tostring(v.Width1))
                log('    Color: ' .. tostring(v.Color))
            end)
        end
    end
    if beamCount == 0 then
        log('  None')
    end

    log('')
    log('-- WELDS --')
    for _, v in skin:GetDescendants() do
        if v:IsA('WeldConstraint') then
            log(string.format('  WeldConstraint: Part0=%s Part1=%s',
                v.Part0 and v.Part0.Name or 'nil',
                v.Part1 and v.Part1.Name or 'nil'
            ))
        elseif v:IsA('Weld') then
            local x0, y0, z0 = v.C0:ToEulerAnglesXYZ()
            local x1, y1, z1 = v.C1:ToEulerAnglesXYZ()
            log(string.format('  Weld: Part0=%s Part1=%s',
                v.Part0 and v.Part0.Name or 'nil',
                v.Part1 and v.Part1.Name or 'nil'
            ))
            log(string.format('    C0: Pos=%s Rot=(%.1f, %.1f, %.1f)',
                tostring(v.C0.Position), math.deg(x0), math.deg(y0), math.deg(z0)))
            log(string.format('    C1: Pos=%s Rot=(%.1f, %.1f, %.1f)',
                tostring(v.C1.Position), math.deg(x1), math.deg(y1), math.deg(z1)))
        end
    end

    copyLog()
end

getgenv().SwordBrowse = scanAllSwordSkins
getgenv().SwordInspect = inspectSkin
getgenv().SwordBrowserCopy = copyLog
getgenv().SwordBrowserClear = clearLog

print(PREFIX, '=============================')
print(PREFIX, '  Sword Skin Browser')
print(PREFIX, '=============================')
print(PREFIX, '')
print(PREFIX, 'Commands:')
print(PREFIX, '  getgenv().SwordBrowse()              — list ALL sword skins in the game')
print(PREFIX, '  getgenv().SwordInspect("skin_name")  — full detail on one skin')
print(PREFIX, '')
print(PREFIX, 'Everything auto-copies to clipboard.')
print(PREFIX, 'Run SwordBrowse() to start!')
