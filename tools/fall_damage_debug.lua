local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local getconnections = getconnections or function() return {} end
local playersService = cloneref(game:GetService('Players'))
local runService = cloneref(game:GetService('RunService'))
local lplr = playersService.LocalPlayer
local gameCamera = workspace.CurrentCamera

local PREFIX = '[FallDebug]'
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

local function getHumanoid()
    local char = lplr.Character
    if not char then return nil end
    return char:FindFirstChildWhichIsA('Humanoid')
end

local function getRootPart()
    local char = lplr.Character
    if not char then return nil end
    local hum = char:FindFirstChildWhichIsA('Humanoid')
    if hum then return hum.RootPart end
    return char:FindFirstChild('HumanoidRootPart')
end

local function startWatch()
    table.clear(buffer)
    if watching then
        print(PREFIX, 'Already watching! Call FallStop() first.')
        return
    end
    watching = true

    log('╔═══════════════════════════════════════════╗')
    log('║   FALL DAMAGE DEBUG TOOL                  ║')
    log('╚═══════════════════════════════════════════╝')
    log('')

    log('── ENVIRONMENT ──')
    log('  Game PlaceId:', game.PlaceId)
    log('  Game Name:', marketplaceService and pcall(function() return game:GetService('MarketplaceService'):GetProductInfo(game.PlaceId).Name end) and select(2, pcall(function() return game:GetService('MarketplaceService'):GetProductInfo(game.PlaceId).Name end)) or 'N/A')
    log('  Workspace.Gravity:', workspace.Gravity)
    log('  Workspace.FallenPartsDestroyHeight:', workspace.FallenPartsDestroyHeight)
    log('')

    local hum = getHumanoid()
    local root = getRootPart()

    if not hum or not root then
        log('ERROR: No humanoid or root part found! Respawn and try again.')
        return
    end

    log('── HUMANOID INFO ──')
    log('  Health:', string.format('%.1f / %.1f', hum.Health, hum.MaxHealth))
    log('  WalkSpeed:', hum.WalkSpeed)
    log('  JumpPower:', hum.JumpPower)
    log('  JumpHeight:', hum.JumpHeight)
    log('  HipHeight:', hum.HipHeight)
    log('  UseJumpPower:', hum.UseJumpPower)
    log('  RigType:', hum.RigType.Name)
    log('  Current State:', hum:GetState().Name)
    log('  RootPart Size:', tostring(root.Size))
    log('')

    log('── ENABLED STATES ──')
    for _, v in Enum.HumanoidStateType:GetEnumItems() do
        if v.Name ~= 'None' then
            local enabled = pcall(function() return hum:GetStateEnabled(v) end) and hum:GetStateEnabled(v)
            if not enabled then
                log('  DISABLED:', v.Name)
            end
        end
    end
    log('')

    log('── SIGNAL CONNECTIONS ──')
    local stateConns = getconnections(hum.StateChanged)
    log('  Humanoid.StateChanged:', #stateConns, 'connections')
    for i, v in stateConns do
        local info = debug.getinfo and debug.getinfo(v.Function) or {}
        log('    ['..i..'] enabled='..tostring(v.Enabled)..' source='..(info.source or info.short_src or 'unknown')..':'..(info.currentline or info.linedefined or '?'))
    end
    log('')

    local freefallConns = getconnections(hum.FreeFalling)
    log('  Humanoid.FreeFalling:', #freefallConns, 'connections')
    for i, v in freefallConns do
        local info = debug.getinfo and debug.getinfo(v.Function) or {}
        log('    ['..i..'] enabled='..tostring(v.Enabled)..' source='..(info.source or info.short_src or 'unknown')..':'..(info.currentline or info.linedefined or '?'))
    end
    log('')

    local landedConns = getconnections(hum.Landed) or {}
    log('  Humanoid.Landed:', #landedConns, 'connections')
    for i, v in landedConns do
        local info = debug.getinfo and debug.getinfo(v.Function) or {}
        log('    ['..i..'] enabled='..tostring(v.Enabled)..' source='..(info.source or info.short_src or 'unknown')..':'..(info.currentline or info.linedefined or '?'))
    end
    log('')

    local healthConns = getconnections(hum:GetPropertyChangedSignal('Health'))
    log('  Humanoid.Health changed:', #healthConns, 'connections')
    for i, v in healthConns do
        local info = debug.getinfo and debug.getinfo(v.Function) or {}
        log('    ['..i..'] enabled='..tostring(v.Enabled)..' source='..(info.source or info.short_src or 'unknown')..':'..(info.currentline or info.linedefined or '?'))
    end
    log('')

    local velConns = getconnections(root:GetPropertyChangedSignal('Velocity'))
    log('  RootPart.Velocity changed:', #velConns, 'connections')
    log('')

    local cframeConns = getconnections(root:GetPropertyChangedSignal('CFrame'))
    log('  RootPart.CFrame changed:', #cframeConns, 'connections')
    log('')

    log('── LOOKING FOR FALL DAMAGE SCRIPTS ──')
    local function scanFor(parent, keyword, depth)
        depth = depth or 0
        if depth > 5 then return end
        local suc, children = pcall(function() return parent:GetChildren() end)
        if not suc then return end
        for _, child in children do
            local name = child.Name:lower()
            if name:find(keyword) then
                log('  FOUND:', child:GetFullName(), '(' .. child.ClassName .. ')')
            end
            scanFor(child, keyword, depth + 1)
        end
    end
    for _, keyword in {'fall', 'damage', 'landing', 'ground'} do
        scanFor(lplr.Character, keyword, 0)
    end
    local suc1 = pcall(function()
        for _, keyword in {'fall', 'damage', 'landing', 'ground'} do
            scanFor(game:GetService('ReplicatedStorage'), keyword, 0)
        end
    end)
    local suc2 = pcall(function()
        for _, keyword in {'fall', 'damage', 'landing', 'ground'} do
            scanFor(lplr.PlayerScripts, keyword, 0)
        end
    end)
    log('')

    log('── LIVE TRACKING STARTED ──')
    log('Jump off something! All state changes, velocity, and damage will be logged.')
    log('')

    local lastHealth = hum.Health
    local lastState = hum:GetState()
    local fallStartY = nil
    local fallStartTick = nil
    local fallStartVel = 0
    local peakFallVel = 0
    local wasFalling = false
    local fallNum = 0

    table.insert(connections, hum.StateChanged:Connect(function(old, new)
        local root = getRootPart()
        local vel = root and root.AssemblyLinearVelocity or Vector3.zero
        local pos = root and root.Position or Vector3.zero
        log(string.format('[%.2f] STATE: %s -> %s | pos Y=%.1f | vel Y=%.1f | vel mag=%.1f',
            tick(), old.Name, new.Name, pos.Y, vel.Y, vel.Magnitude))

        if new == Enum.HumanoidStateType.Freefall and not wasFalling then
            wasFalling = true
            fallNum += 1
            fallStartY = pos.Y
            fallStartTick = tick()
            fallStartVel = vel.Y
            peakFallVel = vel.Y
            log(string.format('  >> FALL #%d STARTED at Y=%.1f', fallNum, fallStartY))
        end

        if wasFalling and (new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running) then
            local fallDist = fallStartY - pos.Y
            local fallTime = tick() - (fallStartTick or tick())
            log(string.format('  >> FALL #%d ENDED', fallNum))
            log(string.format('     Distance: %.1f studs', fallDist))
            log(string.format('     Duration: %.2f seconds', fallTime))
            log(string.format('     Start vel Y: %.1f', fallStartVel))
            log(string.format('     Peak fall vel Y: %.1f', peakFallVel))
            log(string.format('     Impact vel Y: %.1f', vel.Y))
            log(string.format('     Impact vel magnitude: %.1f', vel.Magnitude))
            log(string.format('     Landing state: %s', new.Name))
            log(string.format('     Health at landing: %.1f / %.1f', hum.Health, hum.MaxHealth))
            wasFalling = false
        end
    end))

    table.insert(connections, runService.Heartbeat:Connect(function()
        local root = getRootPart()
        if not root then return end
        local vel = root.AssemblyLinearVelocity
        if wasFalling and vel.Y < peakFallVel then
            peakFallVel = vel.Y
        end
    end))

    table.insert(connections, hum.HealthChanged:Connect(function(newHealth)
        local diff = newHealth - lastHealth
        local root = getRootPart()
        local vel = root and root.AssemblyLinearVelocity or Vector3.zero
        local pos = root and root.Position or Vector3.zero
        local state = hum:GetState()

        if diff < 0 then
            log('')
            log(string.format('!! DAMAGE TAKEN: %.1f !!', -diff))
            log(string.format('   Health: %.1f -> %.1f / %.1f', lastHealth, newHealth, hum.MaxHealth))
            log(string.format('   State: %s', state.Name))
            log(string.format('   Position Y: %.1f', pos.Y))
            log(string.format('   Velocity Y: %.1f | magnitude: %.1f', vel.Y, vel.Magnitude))
            log(string.format('   FloorMaterial: %s', hum.FloorMaterial.Name))
            if wasFalling then
                local fallDist = fallStartY - pos.Y
                log(string.format('   Fall distance so far: %.1f studs', fallDist))
                log(string.format('   Peak fall velocity: %.1f', peakFallVel))
            else
                log('   Was NOT in tracked freefall state')
            end
            log('')
        elseif diff > 0 then
            log(string.format('[%.2f] HEALED: +%.1f (%.1f -> %.1f)', tick(), diff, lastHealth, newHealth))
        end

        lastHealth = newHealth
    end))

    table.insert(connections, hum.FreeFalling:Connect(function(active)
        log(string.format('[%.2f] FreeFalling signal fired: %s', tick(), tostring(active)))
    end))

    local landedSuc = pcall(function()
        table.insert(connections, hum.Landed:Connect(function()
            local root = getRootPart()
            local vel = root and root.AssemblyLinearVelocity or Vector3.zero
            log(string.format('[%.2f] Landed signal fired | vel Y=%.1f', tick(), vel.Y))
        end))
    end)

    log('Watching... jump off something high and come back here.')
    log('Call FallCopy() to copy everything to clipboard.')
    log('Call FallStop() to stop watching.')
    log('')
end

local function stopWatch()
    watching = false
    for _, v in connections do
        if typeof(v) == 'RBXScriptConnection' then
            v:Disconnect()
        end
    end
    table.clear(connections)
    log('')
    log('── STOPPED ──')
    log('Call FallCopy() to copy the log to clipboard.')
    print(PREFIX, 'Stopped watching.')
end

getgenv().FallDebug = startWatch
getgenv().FallStop = stopWatch
getgenv().FallCopy = copyLog

print('')
print('╔═══════════════════════════════════════════╗')
print('║   FALL DAMAGE DEBUG TOOL LOADED           ║')
print('╠═══════════════════════════════════════════╣')
print('║  FallDebug()  - Start watching falls      ║')
print('║  FallStop()   - Stop watching             ║')
print('║  FallCopy()   - Copy log to clipboard     ║')
print('╚═══════════════════════════════════════════╝')
print('')

startWatch()
