local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local soundService = cloneref(game:GetService('SoundService'))
local lplr = playersService.LocalPlayer
local gameCamera = workspace.CurrentCamera

local PREFIX = '[SoundDebug]'
local buffer = {}
local watching = false
local connections = {}

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

local function watchAllSounds()
    table.clear(buffer)
    if watching then
        print(PREFIX, 'Already watching! Call SoundStop() first.')
        return
    end
    watching = true

    log('╔══════════════════════════════════════╗')
    log('║   GLOBAL SOUND WATCHER               ║')
    log('╚══════════════════════════════════════╝')
    log('')
    log('Watching ALL sounds everywhere.')
    log('Swing your sword now! Every sound that plays will be logged.')
    log('')

    local seen = {}

    local function hookSound(sound)
        if seen[sound] then return end
        seen[sound] = true

        local conn = sound.Played:Connect(function()
            local path = sound:GetFullName()
            local id = tostring(sound.SoundId)
            if id == '' then return end

            log(string.format('[PLAYED] %s', os.date('%H:%M:%S')))
            log(string.format('  Name: %s', sound.Name))
            log(string.format('  SoundId: %s', id))
            log(string.format('  Path: %s', path))
            log(string.format('  Volume: %s | Speed: %s | Looped: %s',
                tostring(sound.Volume),
                tostring(sound.PlaybackSpeed),
                tostring(sound.Looped)))
            log('')
            copyLog()
        end)
        table.insert(connections, conn)
    end

    for _, v in game:GetDescendants() do
        if v:IsA('Sound') then
            hookSound(v)
        end
    end

    table.insert(connections, game.DescendantAdded:Connect(function(v)
        if v:IsA('Sound') then
            task.defer(hookSound, v)
        end
    end))

    print(PREFIX, 'Watching ALL sounds globally. Swing your sword!')
    print(PREFIX, 'Call getgenv().SoundStop() to stop.')
end

local function stopWatch()
    watching = false
    for _, conn in connections do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(connections)
    copyLog()
    print(PREFIX, 'Stopped. Log copied to clipboard.')
end

local function scanSkinSoundConfig()
    table.clear(buffer)
    log('╔══════════════════════════════════════╗')
    log('║   SKIN SOUND CONFIG SCANNER          ║')
    log('╚══════════════════════════════════════╝')
    log('')

    log('-- Scanning bedwars.BedwarsKitSkin for sound data --')
    pcall(function()
        local bedwars = require(replicatedStorage.TS.bedwars)
        if bedwars.BedwarsKitSkin then
            for _, skinData in bedwars.BedwarsKitSkin do
                if skinData.itemSkins then
                    local hasSword = false
                    for _, s in skinData.itemSkins do
                        if tostring(s):find('sword') then
                            hasSword = true
                            break
                        end
                    end
                    if hasSword then
                        log('  Skin: ' .. tostring(skinData.name))
                        for key, val in skinData do
                            if tostring(key):lower():find('sound') or tostring(key):lower():find('audio') then
                                log('    ' .. tostring(key) .. ' = ' .. tostring(val))
                            end
                        end
                        if skinData.sounds then
                            log('    sounds:')
                            for k, v in skinData.sounds do
                                log('      ' .. tostring(k) .. ' = ' .. tostring(v))
                            end
                        end
                        if skinData.hitSound then
                            log('    hitSound: ' .. tostring(skinData.hitSound))
                        end
                        if skinData.swingSound then
                            log('    swingSound: ' .. tostring(skinData.swingSound))
                        end
                        log('    ALL KEYS:')
                        for key, val in skinData do
                            log('      ' .. tostring(key) .. ' = ' .. tostring(val))
                        end
                        log('')
                    end
                end
            end
        else
            log('  BedwarsKitSkin not found')
        end
    end)

    log('')
    log('-- Scanning ItemMeta for sound data --')
    pcall(function()
        local ItemMeta = require(replicatedStorage.TS.item['item-meta']).items
        for name, meta in ItemMeta do
            if tostring(name):find('sword') and meta.sword then
                log('  ' .. tostring(name) .. ':')
                for key, val in meta do
                    if tostring(key):lower():find('sound') or tostring(key):lower():find('audio') or tostring(key):lower():find('sfx') then
                        log('    ' .. tostring(key) .. ' = ' .. tostring(val))
                    end
                end
            end
        end
    end)

    log('')
    log('-- Scanning SoundService --')
    for _, v in soundService:GetDescendants() do
        if v:IsA('Sound') or v:IsA('SoundGroup') then
            log('  ' .. v:GetFullName() .. ' (' .. v.ClassName .. ')')
            if v:IsA('Sound') then
                log('    SoundId: ' .. tostring(v.SoundId))
            end
        end
    end

    log('')
    log('-- Scanning for sound modules --')
    pcall(function()
        local ts = replicatedStorage:FindFirstChild('TS')
        if ts then
            for _, child in ts:GetDescendants() do
                if child:IsA('ModuleScript') and (child.Name:lower():find('sound') or child.Name:lower():find('audio') or child.Name:lower():find('sfx')) then
                    log('  Module: ' .. child:GetFullName())
                end
            end
        end
    end)

    copyLog()
end

getgenv().SoundWatch = watchAllSounds
getgenv().SoundStop = stopWatch
getgenv().SoundConfig = scanSkinSoundConfig
getgenv().SoundCopy = copyLog

print(PREFIX, '=============================')
print(PREFIX, '  Sword Sound Debug v2')
print(PREFIX, '=============================')
print(PREFIX, '')
print(PREFIX, 'Commands:')
print(PREFIX, '  getgenv().SoundWatch()    — watch ALL sounds globally (swing sword!)')
print(PREFIX, '  getgenv().SoundStop()     — stop watching')
print(PREFIX, '  getgenv().SoundConfig()   — scan game config for sound data')
print(PREFIX, '')
print(PREFIX, 'Auto-copies to clipboard.')
print(PREFIX, 'Run SoundWatch(), then swing your sword!')
