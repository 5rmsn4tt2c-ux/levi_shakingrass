local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))

local PREFIX = '[SoundDump]'
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

local function dumpTable(t, indent, maxDepth)
    indent = indent or 0
    maxDepth = maxDepth or 4
    if indent > maxDepth then
        log(string.rep('  ', indent) .. '...')
        return
    end
    local pad = string.rep('  ', indent)
    if type(t) ~= 'table' then
        log(pad .. tostring(t))
        return
    end
    for key, val in pairs(t) do
        local keyStr = tostring(key)
        if type(val) == 'table' then
            log(pad .. keyStr .. ':')
            dumpTable(val, indent + 1, maxDepth)
        else
            log(pad .. keyStr .. ' = ' .. tostring(val))
        end
    end
end

local function dumpAll()
    table.clear(buffer)
    log('╔══════════════════════════════════════╗')
    log('║   SOUND MODULE DUMP                  ║')
    log('╚══════════════════════════════════════╝')
    log('')

    log('━━━ item-meta-hit-sounds ━━━')
    pcall(function()
        local mod = require(replicatedStorage.TS.item['item-meta-hit-sounds'])
        for key, val in pairs(mod) do
            log('EXPORT: ' .. tostring(key))
            if type(val) == 'table' then
                dumpTable(val, 1)
            else
                log('  ' .. tostring(val))
            end
            log('')
        end
    end)

    log('')
    log('━━━ create-sounds ━━━')
    pcall(function()
        local mod = require(replicatedStorage.TS.item['create-sounds'])
        for key, val in pairs(mod) do
            log('EXPORT: ' .. tostring(key))
            if type(val) == 'function' then
                log('  [function]')
            elseif type(val) == 'table' then
                dumpTable(val, 1)
            else
                log('  ' .. tostring(val))
            end
            log('')
        end
    end)

    log('')
    log('━━━ game-sound ━━━')
    pcall(function()
        local mod = require(replicatedStorage.TS.sound['game-sound'])
        for key, val in pairs(mod) do
            log('EXPORT: ' .. tostring(key))
            if type(val) == 'function' then
                log('  [function]')
            elseif type(val) == 'table' then
                dumpTable(val, 1, 3)
            else
                log('  ' .. tostring(val))
            end
            log('')
        end
    end)

    log('')
    log('━━━ sound-encoding ━━━')
    pcall(function()
        local mod = require(replicatedStorage.TS.encoding['sound-encoding'])
        for key, val in pairs(mod) do
            log('EXPORT: ' .. tostring(key))
            if type(val) == 'function' then
                log('  [function]')
            elseif type(val) == 'table' then
                dumpTable(val, 1, 3)
            else
                log('  ' .. tostring(val))
            end
            log('')
        end
    end)

    log('')
    log('━━━ Scanning BedwarsKitSkin for pixel skin ━━━')
    pcall(function()
        local bedwars = require(replicatedStorage.TS.bedwars)
        for _, skinData in bedwars.BedwarsKitSkin do
            if skinData.name and tostring(skinData.name):lower():find('pixel') then
                log('Found: ' .. tostring(skinData.name))
                dumpTable(skinData, 1, 4)
                log('')
            end
        end
    end)

    copyLog()
end

getgenv().DumpSounds = dumpAll

print(PREFIX, '=============================')
print(PREFIX, '  Sound Module Dump')
print(PREFIX, '=============================')
print(PREFIX, '')
print(PREFIX, 'Run: getgenv().DumpSounds()')
print(PREFIX, 'Auto-copies to clipboard.')
