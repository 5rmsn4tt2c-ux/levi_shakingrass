--[[
    Godmode Debug Tool
    Execute this BEFORE running your friend's godmode script, then activate godmode.
    Everything that changes on your character will be printed and auto-copied to clipboard.

    Commands:
        GodmodeDebug()   - start watching (auto-runs on load)
        GodmodeStop()    - stop watching
        GodmodeCopy()    - copy full log to clipboard
        GodmodeSnap()    - print a fresh snapshot of current state
]]

local cloneref      = cloneref      or function(o) return o end
local setclipboard  = setclipboard  or toclipboard  or function() end
local getconnections = getconnections or function() return {} end

local Players    = cloneref(game:GetService('Players'))
local RunService = cloneref(game:GetService('RunService'))
local lplr       = Players.LocalPlayer
local camera     = workspace.CurrentCamera

local PREFIX = '[GodmodeDBG]'
local buffer  = {}
local conns   = {}
local watching = false

-- ── helpers ──────────────────────────────────────────────────────────────────

local function log(...)
    local parts = {}
    for _, v in {...} do table.insert(parts, tostring(v)) end
    local line = '[' .. string.format('%.2f', tick()) .. '] ' .. table.concat(parts, ' ')
    table.insert(buffer, line)
    print(PREFIX, line)
end

local function sep(title)
    local bar = ('─'):rep(40)
    log(bar)
    log('  ' .. title)
    log(bar)
end

local function copyLog()
    pcall(setclipboard, table.concat(buffer, '\n'))
    print(PREFIX, 'Copied ' .. #buffer .. ' lines to clipboard.')
end

local function safe(f, ...)
    local ok, r = pcall(f, ...)
    return ok and r or nil
end

local function connCount(signal)
    local ok, list = pcall(getconnections, signal)
    return ok and #list or '?'
end

-- ── snapshot ─────────────────────────────────────────────────────────────────

local function snapshot()
    sep('CHARACTER SNAPSHOT')

    local char = lplr.Character
    if not char then log('No character found.') return end

    local hum  = char:FindFirstChildWhichIsA('Humanoid')
    local root = char:FindFirstChild('HumanoidRootPart')

    log('Character name : ' .. char.Name)
    log('Character parent : ' .. tostring(char.Parent))

    if hum then
        log('Health         : ' .. string.format('%.1f / %.1f', hum.Health, hum.MaxHealth))
        log('WalkSpeed      : ' .. hum.WalkSpeed)
        log('JumpPower      : ' .. hum.JumpPower)
        log('JumpHeight     : ' .. hum.JumpHeight)
        log('AutoRotate     : ' .. tostring(hum.AutoRotate))
        log('BreakJointsOnDeath : ' .. tostring(hum.BreakJointsOnDeath))
        log('DisplayDistanceType : ' .. tostring(hum.DisplayDistanceType))
        log('State          : ' .. hum:GetState().Name)
        log('RigType        : ' .. hum.RigType.Name)

        log('── Disabled states:')
        for _, s in Enum.HumanoidStateType:GetEnumItems() do
            if s.Name ~= 'None' then
                local enabled = safe(function() return hum:GetStateEnabled(s) end)
                if enabled == false then
                    log('   DISABLED: ' .. s.Name)
                end
            end
        end

        log('── Signal connections:')
        log('   Health.Changed    : ' .. connCount(hum.HealthChanged))
        log('   StateChanged      : ' .. connCount(hum.StateChanged))
        log('   Died              : ' .. connCount(hum.Died))
        log('   FreeFalling       : ' .. connCount(hum.FreeFalling))
    else
        log('No Humanoid found in character.')
    end

    if root then
        log('Root position  : ' .. tostring(root.Position))
        log('Root anchored  : ' .. tostring(root.Anchored))
        log('Root CanCollide: ' .. tostring(root.CanCollide))
        log('Root mass      : ' .. tostring(root.AssemblyMass))
    else
        log('No HumanoidRootPart found.')
    end

    -- Attributes on character
    log('── Character attributes:')
    local attrs = safe(function() return char:GetAttributes() end) or {}
    local attrCount = 0
    for k, v in pairs(attrs) do
        log('   ' .. tostring(k) .. ' = ' .. tostring(v))
        attrCount += 1
    end
    if attrCount == 0 then log('   (none)') end

    -- Attributes on player
    log('── Player attributes:')
    local plrAttrs = safe(function() return lplr:GetAttributes() end) or {}
    local plrAttrCount = 0
    for k, v in pairs(plrAttrs) do
        log('   ' .. tostring(k) .. ' = ' .. tostring(v))
        plrAttrCount += 1
    end
    if plrAttrCount == 0 then log('   (none)') end

    -- Team
    local team = safe(function() return lplr.Team end)
    log('Team           : ' .. tostring(team and team.Name or 'nil'))
    log('TeamColor      : ' .. tostring(safe(function() return lplr.TeamColor end)))
    log('Neutral        : ' .. tostring(safe(function() return lplr.Neutral end)))

    -- Camera
    local camSubject = safe(function() return camera.CameraSubject end)
    log('Camera subject : ' .. tostring(camSubject and camSubject:GetFullName() or 'nil'))
    log('Camera type    : ' .. tostring(safe(function() return camera.CameraType end)))

    -- NetworkOwnership / physics scripts
    log('── LocalScripts in character:')
    local scriptCount = 0
    for _, v in char:GetDescendants() do
        if v:IsA('LocalScript') or v:IsA('ModuleScript') then
            log('   ' .. v:GetFullName() .. '  [' .. v.ClassName .. ']  enabled=' .. tostring(v.Enabled))
            scriptCount += 1
        end
    end
    if scriptCount == 0 then log('   (none)') end

    log('── Tools in character:')
    local toolCount = 0
    for _, v in char:GetChildren() do
        if v:IsA('Tool') then
            log('   ' .. v.Name)
            toolCount += 1
        end
    end
    if toolCount == 0 then log('   (none)') end

    sep('END SNAPSHOT')
    copyLog()
end

-- ── live watch ───────────────────────────────────────────────────────────────

local function startWatch()
    if watching then
        print(PREFIX, 'Already watching. Call GodmodeStop() first.')
        return
    end
    watching = true
    table.clear(buffer)
    table.clear(conns)

    sep('GODMODE DEBUG — LIVE WATCH STARTED')
    log('Execute the godmode script now and watch what changes.')
    log('')

    snapshot()

    local char = lplr.Character
    if not char then
        log('ERROR: No character. Respawn and re-run GodmodeDebug().')
        watching = false
        return
    end

    local hum  = char:FindFirstChildWhichIsA('Humanoid')
    local root = char:FindFirstChild('HumanoidRootPart')

    -- ── Humanoid property watch ──────────────────────────────────────────────

    if hum then
        local lastHealth   = hum.Health
        local lastMaxHealth = hum.MaxHealth
        local lastWalk     = hum.WalkSpeed
        local lastJump     = hum.JumpPower
        local lastState    = hum:GetState()

        table.insert(conns, hum.HealthChanged:Connect(function(hp)
            local diff = hp - lastHealth
            if math.abs(diff) > 0.01 then
                log(string.format('HEALTH CHANGED: %.1f -> %.1f (diff %+.1f)', lastHealth, hp, diff))
                if hp >= hum.MaxHealth and lastHealth < hum.MaxHealth then
                    log('  >> Possibly healed to full (godmode heal?)')
                end
            end
            lastHealth = hp
        end))

        table.insert(conns, hum:GetPropertyChangedSignal('MaxHealth'):Connect(function()
            log(string.format('MAXHEALTH CHANGED: %.1f -> %.1f', lastMaxHealth, hum.MaxHealth))
            lastMaxHealth = hum.MaxHealth
        end))

        table.insert(conns, hum:GetPropertyChangedSignal('WalkSpeed'):Connect(function()
            log(string.format('WALKSPEED CHANGED: %.1f -> %.1f', lastWalk, hum.WalkSpeed))
            lastWalk = hum.WalkSpeed
        end))

        table.insert(conns, hum:GetPropertyChangedSignal('JumpPower'):Connect(function()
            log(string.format('JUMPPOWER CHANGED: %.1f -> %.1f', lastJump, hum.JumpPower))
            lastJump = hum.JumpPower
        end))

        table.insert(conns, hum:GetPropertyChangedSignal('AutoRotate'):Connect(function()
            log('AUTOROTATE CHANGED: ' .. tostring(hum.AutoRotate))
        end))

        table.insert(conns, hum:GetPropertyChangedSignal('BreakJointsOnDeath'):Connect(function()
            log('BREAKJOINTSONDEATH CHANGED: ' .. tostring(hum.BreakJointsOnDeath))
        end))

        table.insert(conns, hum.StateChanged:Connect(function(old, new)
            log('STATE CHANGED: ' .. old.Name .. ' -> ' .. new.Name)
            if new == Enum.HumanoidStateType.Physics then
                log('  >> Physics state! Character may be spectating or noclipping.')
            elseif new == Enum.HumanoidStateType.Dead then
                log('  >> Humanoid died')
            end
        end))

        table.insert(conns, hum.Died:Connect(function()
            log('!! HUMANOID.DIED FIRED !!')
        end))

        -- Watch for state being enabled/disabled
        for _, s in Enum.HumanoidStateType:GetEnumItems() do
            if s.Name ~= 'None' then
                local wasEnabled = safe(function() return hum:GetStateEnabled(s) end)
                local stateName = s.Name
                table.insert(conns, RunService.Heartbeat:Connect(function()
                    local nowEnabled = safe(function() return hum:GetStateEnabled(s) end)
                    if nowEnabled ~= wasEnabled then
                        log('HUMANOID STATE ENABLED CHANGED: ' .. stateName .. ' -> ' .. tostring(nowEnabled))
                        wasEnabled = nowEnabled
                    end
                end))
            end
        end
    end

    -- ── Root position / anchor watch ─────────────────────────────────────────

    if root then
        local lastPos    = root.Position
        local lastAnchor = root.Anchored
        local lastColl   = root.CanCollide
        local BIG_MOVE   = 100

        table.insert(conns, RunService.Heartbeat:Connect(function()
            if not root or not root.Parent then return end
            local dist = (root.Position - lastPos).Magnitude
            if dist > BIG_MOVE then
                log(string.format('BIG TELEPORT: %.0f studs | from %s to %s',
                    dist, tostring(lastPos), tostring(root.Position)))
                log('  >> This could be a spectate teleport!')
            end
            lastPos = root.Position

            if root.Anchored ~= lastAnchor then
                log('ROOT ANCHORED CHANGED: ' .. tostring(root.Anchored))
                lastAnchor = root.Anchored
            end

            if root.CanCollide ~= lastColl then
                log('ROOT CANCOLLIDE CHANGED: ' .. tostring(root.CanCollide))
                lastColl = root.CanCollide
            end
        end))
    end

    -- ── Character attribute watch ─────────────────────────────────────────────

    table.insert(conns, char.AttributeChanged:Connect(function(attr)
        local val = safe(function() return char:GetAttribute(attr) end)
        log('CHAR ATTRIBUTE CHANGED: ' .. attr .. ' = ' .. tostring(val))
    end))

    table.insert(conns, lplr.AttributeChanged:Connect(function(attr)
        local val = safe(function() return lplr:GetAttribute(attr) end)
        log('PLAYER ATTRIBUTE CHANGED: ' .. attr .. ' = ' .. tostring(val))
    end))

    -- ── New descendants added to character (scripts, parts, values) ──────────

    table.insert(conns, char.DescendantAdded:Connect(function(obj)
        log('CHILD ADDED to character: ' .. obj:GetFullName() .. '  [' .. obj.ClassName .. ']')
        if obj:IsA('LocalScript') or obj:IsA('Script') then
            log('  >> A SCRIPT was added! This could be the godmode mechanism.')
            log('  >> Script name: ' .. obj.Name)
            log('  >> Script enabled: ' .. tostring(obj.Enabled))
        elseif obj:IsA('BoolValue') or obj:IsA('IntValue') or obj:IsA('StringValue') or obj:IsA('NumberValue') then
            log('  >> Value object: ' .. obj.Name .. ' = ' .. tostring(safe(function() return obj.Value end)))
        end
    end))

    table.insert(conns, char.DescendantRemoving:Connect(function(obj)
        log('CHILD REMOVED from character: ' .. obj:GetFullName() .. '  [' .. obj.ClassName .. ']')
    end))

    -- ── Team watch ───────────────────────────────────────────────────────────

    table.insert(conns, lplr:GetPropertyChangedSignal('Team'):Connect(function()
        local team = safe(function() return lplr.Team end)
        log('TEAM CHANGED: ' .. tostring(team and team.Name or 'nil'))
    end))

    table.insert(conns, lplr:GetPropertyChangedSignal('TeamColor'):Connect(function()
        log('TEAMCOLOR CHANGED: ' .. tostring(safe(function() return lplr.TeamColor end)))
    end))

    table.insert(conns, lplr:GetPropertyChangedSignal('Neutral'):Connect(function()
        log('NEUTRAL CHANGED: ' .. tostring(safe(function() return lplr.Neutral end)))
    end))

    -- ── Camera watch ─────────────────────────────────────────────────────────

    table.insert(conns, camera:GetPropertyChangedSignal('CameraSubject'):Connect(function()
        local subject = safe(function() return camera.CameraSubject end)
        log('CAMERA SUBJECT CHANGED: ' .. tostring(subject and subject:GetFullName() or 'nil'))
        if subject and subject ~= (char and char:FindFirstChildWhichIsA('Humanoid')) then
            log('  >> Camera no longer on YOUR humanoid — spectate mode?')
        end
    end))

    table.insert(conns, camera:GetPropertyChangedSignal('CameraType'):Connect(function()
        log('CAMERA TYPE CHANGED: ' .. tostring(safe(function() return camera.CameraType end)))
    end))

    -- ── Character removed / replaced ─────────────────────────────────────────

    table.insert(conns, lplr.CharacterRemoving:Connect(function(oldChar)
        log('CHARACTER REMOVING: ' .. oldChar.Name)
    end))

    table.insert(conns, lplr.CharacterAdded:Connect(function(newChar)
        log('CHARACTER ADDED (respawned): ' .. newChar.Name)
        log('  >> Re-run GodmodeDebug() after this to watch the new character.')
    end))

    -- ── Periodic auto-copy ───────────────────────────────────────────────────

    local lastCopyTick = tick()
    table.insert(conns, RunService.Heartbeat:Connect(function()
        if tick() - lastCopyTick >= 5 then
            lastCopyTick = tick()
            copyLog()
        end
    end))

    sep('WATCHING — activate godmode now!')
    log('All changes will be logged. Call GodmodeStop() when done.')
    log('Auto-copies to clipboard every 5 seconds.')
    copyLog()
end

-- ── stop ─────────────────────────────────────────────────────────────────────

local function stopWatch()
    if not watching then
        print(PREFIX, 'Not currently watching.')
        return
    end
    watching = false
    for _, c in conns do
        if typeof(c) == 'RBXScriptConnection' then
            c:Disconnect()
        end
    end
    table.clear(conns)

    sep('STOPPED')
    log('Total log lines: ' .. #buffer)
    copyLog()
end

-- ── globals ──────────────────────────────────────────────────────────────────

getgenv().GodmodeDebug = startWatch
getgenv().GodmodeStop  = stopWatch
getgenv().GodmodeCopy  = copyLog
getgenv().GodmodeSnap  = snapshot

-- ── banner ───────────────────────────────────────────────────────────────────

print('')
print('╔══════════════════════════════════════════════╗')
print('║   GODMODE DEBUG TOOL LOADED                  ║')
print('╠══════════════════════════════════════════════╣')
print('║  GodmodeDebug() - start watching (auto-run)  ║')
print('║  GodmodeStop()  - stop watching              ║')
print('║  GodmodeCopy()  - copy log to clipboard      ║')
print('║  GodmodeSnap()  - snapshot current state     ║')
print('╚══════════════════════════════════════════════╝')
print('')

startWatch()
