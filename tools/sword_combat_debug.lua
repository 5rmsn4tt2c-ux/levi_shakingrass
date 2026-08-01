local ok, err = pcall(function()

local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local getconnections = getconnections or function() return {} end
local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local runService = cloneref(game:GetService('RunService'))
local httpService = cloneref(game:GetService('HttpService'))
local lplr = playersService.LocalPlayer

local PREFIX = '[SwordDebug]'
local buffer = {}
local hooks = {}
local watching = false

local function log(...)
    local parts = {}
    for _, v in {...} do
        table.insert(parts, tostring(v))
    end
    local line = table.concat(parts, ' ')
    table.insert(buffer, line)
    print(PREFIX, line)
end

local function sep(title)
    log('====== ' .. title .. ' ======')
end

local function copyLog()
    local text = table.concat(buffer, '\n')
    pcall(setclipboard, text)
    print(PREFIX, 'Copied ' .. #buffer .. ' lines to clipboard!')
end

local function safeGet(func)
    local ok, res = pcall(func)
    return ok and res or nil
end

local function dumpTable(t, indent, visited)
    indent = indent or ''
    visited = visited or {}
    if type(t) ~= 'table' then return tostring(t) end
    if visited[t] then return '<circular>' end
    visited[t] = true
    local lines = {}
    for k, v in pairs(t) do
        if type(v) == 'table' and not visited[v] then
            table.insert(lines, indent .. tostring(k) .. ':')
            table.insert(lines, dumpTable(v, indent .. '  ', visited))
        else
            table.insert(lines, indent .. tostring(k) .. ' = ' .. tostring(v))
        end
    end
    return table.concat(lines, '\n')
end

local function run()
    table.clear(buffer)
    log('Sword Combat Debug - ' .. os.date('%Y-%m-%d %H:%M:%S'))
    log('PlaceId: ' .. tostring(game.PlaceId))
    log('Executor: ' .. tostring(safeGet(function() return ({identifyexecutor()})[1] end) or 'unknown'))

    sep('KNIT / CONTROLLERS')

    local Knit = safeGet(function()
        return require(replicatedStorage.rbxts_include.node_modules["@easy-games"].knit.src).KnitClient
    end)

    if not Knit then
        log('ERROR: Knit failed to load')
        copyLog()
        return
    end
    log('Knit loaded: true')

    local knitStarted = safeGet(function() return debug.getupvalue(Knit.Start, 1) end)
    log('Knit started: ' .. tostring(knitStarted ~= nil and knitStarted ~= false))

    local swc = safeGet(function() return Knit.Controllers.SwordController end)
    log('SwordController exists: ' .. tostring(swc ~= nil))

    if not swc then
        log('ERROR: SwordController is nil - this is likely why sword scripts break')
        copyLog()
        return
    end

    sep('SWORD CONTROLLER METHODS')

    local methods = {
        'sendServerRequest', 'swingSwordAtMouse', 'swingSwordInRegion',
        'isClickingTooFast', 'playSwordEffect', 'getTargetInRegion',
        'lastSwing', 'lastAttack'
    }

    for _, name in methods do
        local val = safeGet(function() return swc[name] end)
        local valType = type(val)
        if valType == 'function' then
            log('  ' .. name .. ': function')
            local constCount = safeGet(function()
                local consts = debug.getconstants(val)
                return #consts
            end) or '?'
            log('    constants count: ' .. tostring(constCount))
        elseif valType == 'number' then
            log('  ' .. name .. ': ' .. tostring(val))
        else
            log('  ' .. name .. ': ' .. valType .. ' = ' .. tostring(val))
        end
    end

    sep('REMOTE EXTRACTION')

    local function getproto(...)
        local success, res = pcall(debug.getproto, ...)
        return success and res or nil
    end

    local function dumpRemote(tab)
        if not tab then return '' end
        local ind
        for i, v in tab do
            if v == 'Client' then
                ind = i
                break
            end
        end
        return ind and tab[ind + 1] or ''
    end

    local attackRemote = safeGet(function()
        local fn = swc.sendServerRequest
        if not fn then return nil end
        local consts = debug.getconstants(fn)
        return dumpRemote(consts)
    end)
    log('AttackEntity remote from sendServerRequest: "' .. tostring(attackRemote) .. '"')

    if attackRemote == '' or not attackRemote then
        log('WARNING: Could not extract attack remote from sendServerRequest')
        log('  This means the remote name may have changed or the function structure was patched')

        log('  Dumping sendServerRequest constants:')
        safeGet(function()
            local consts = debug.getconstants(swc.sendServerRequest)
            for i, v in consts do
                log('    [' .. i .. '] = ' .. tostring(v) .. ' (' .. type(v) .. ')')
            end
        end)
    end

    local swingRemote = safeGet(function()
        local fn = swc.swingSwordAtMouse
        if not fn then return nil end
        local consts = debug.getconstants(fn)
        return dumpRemote(consts)
    end)
    log('Remote from swingSwordAtMouse: "' .. tostring(swingRemote) .. '"')

    sep('COMBAT CONSTANTS')

    local CombatConstant = safeGet(function()
        return require(replicatedStorage.TS.combat['combat-constant']).CombatConstant
    end)

    if CombatConstant then
        log('CombatConstant loaded: true')
        for _, key in {'RAYCAST_SWORD_CHARACTER_DISTANCE', 'SWORD_ATTACK_RANGE', 'SWORD_SWING_RANGE', 'MAX_CPS', 'ATTACK_COOLDOWN', 'COMBO_WINDOW'} do
            local val = safeGet(function() return CombatConstant[key] end)
            if val ~= nil then
                log('  ' .. key .. ' = ' .. tostring(val))
            end
        end

        log('  All CombatConstant keys:')
        safeGet(function()
            for k, v in pairs(CombatConstant) do
                if type(v) ~= 'function' and type(v) ~= 'table' then
                    log('    ' .. tostring(k) .. ' = ' .. tostring(v))
                end
            end
        end)
    else
        log('ERROR: CombatConstant failed to load')
    end

    sep('CPS CONSTANTS')

    local CpsConstants = safeGet(function()
        return require(replicatedStorage.TS['shared-constants']).CpsConstants
    end)
    if CpsConstants then
        log('CpsConstants loaded: true')
        safeGet(function()
            for k, v in pairs(CpsConstants) do
                log('  ' .. tostring(k) .. ' = ' .. tostring(v))
            end
        end)
    else
        log('CpsConstants: not found or failed to load')
    end

    sep('CLIENT NETWORKING')

    local Client = safeGet(function()
        return require(replicatedStorage.TS.remotes).default.Client
    end)

    if Client then
        log('Client remote module loaded: true')
        log('Client.Get exists: ' .. tostring(type(Client.Get) == 'function'))

        if attackRemote and attackRemote ~= '' then
            local remoteObj = safeGet(function()
                local call = Client:Get(attackRemote)
                return call
            end)
            log('Attack remote callable: ' .. tostring(remoteObj ~= nil))
            if remoteObj then
                log('  Has SendToServer: ' .. tostring(type(safeGet(function() return remoteObj.SendToServer end)) == 'function'))
                log('  Has instance: ' .. tostring(safeGet(function() return remoteObj.instance end) ~= nil))
                local inst = safeGet(function() return remoteObj.instance end)
                if inst then
                    log('  Instance class: ' .. tostring(inst.ClassName))
                    log('  Instance name: ' .. tostring(inst.Name))
                end
            end
        end
    else
        log('ERROR: Client remote module failed to load')
    end

    sep('SWORD CONTROLLER UPVALUES')

    local fns = {
        {'sendServerRequest', swc.sendServerRequest},
        {'swingSwordAtMouse', swc.swingSwordAtMouse},
        {'swingSwordInRegion', swc.swingSwordInRegion},
        {'isClickingTooFast', swc.isClickingTooFast},
    }

    for _, pair in fns do
        local name, fn = pair[1], pair[2]
        if type(fn) == 'function' then
            log('Upvalues for ' .. name .. ':')
            for i = 1, 30 do
                local ok, uname, uval = pcall(function()
                    return debug.getupvalue(fn, i)
                end)
                if not ok then break end
                if uname then
                    local valStr = type(uval) == 'table' and '<table>' or tostring(uval)
                    log('  [' .. i .. '] ' .. tostring(uname) .. ' = ' .. valStr)
                end
            end
        end
    end

    sep('VALIDATE STRUCTURE TEST')

    log('Testing attack payload structure...')
    local char = lplr.Character
    local rootPart = char and char:FindFirstChild('HumanoidRootPart')
    if rootPart and attackRemote and attackRemote ~= '' and Client then
        log('Building test validate table:')
        local testPayload = {
            weapon = 'test',
            chargedAttack = {chargeRatio = 0},
            entityInstance = char,
            validate = {
                raycast = {
                    cameraPosition = {value = rootPart.Position},
                    cursorDirection = {value = rootPart.CFrame.LookVector},
                },
                targetPosition = {value = rootPart.Position},
                selfPosition = {value = rootPart.Position},
            },
        }
        log('  Payload keys: weapon, chargedAttack, entityInstance, validate')
        log('  validate keys: raycast, targetPosition, selfPosition')
        log('  raycast keys: cameraPosition, cursorDirection')
        log('  (NOT sending - structure check only)')

        log('Checking if validate structure has new required fields...')
        safeGet(function()
            local fn = swc.sendServerRequest
            if not fn then return end
            local consts = debug.getconstants(fn)
            log('  sendServerRequest constants:')
            for i, v in consts do
                log('    [' .. i .. '] ' .. type(v) .. ' = ' .. tostring(v))
            end
        end)

        safeGet(function()
            local fn = swc.swingSwordAtMouse
            if not fn then return end
            local consts = debug.getconstants(fn)
            log('  swingSwordAtMouse constants:')
            for i, v in consts do
                log('    [' .. i .. '] ' .. type(v) .. ' = ' .. tostring(v))
            end
        end)
    else
        log('Cannot test: character or remote not available')
    end

    sep('SWORDCONTROLLER PROTO CHECK')

    safeGet(function()
        local fn = swc.sendServerRequest
        if not fn then
            log('sendServerRequest is nil')
            return
        end
        log('sendServerRequest proto count: ' .. tostring(#{debug.getprotos(fn)}))
        for i = 1, 5 do
            local proto = getproto(fn, i)
            if proto then
                log('  proto[' .. i .. '] constants:')
                local pconsts = debug.getconstants(proto)
                for j, v in pconsts do
                    log('    [' .. j .. '] ' .. type(v) .. ' = ' .. tostring(v))
                end
            end
        end
    end)

    sep('ITEM META SWORD CHECK')

    local ItemMeta = safeGet(function()
        return require(replicatedStorage.TS.item['item-meta']).items
    end)

    if ItemMeta then
        log('ItemMeta loaded: true')
        local swordCount = 0
        local sampleSword = nil
        safeGet(function()
            for k, v in pairs(ItemMeta) do
                if type(v) == 'table' and v.sword then
                    swordCount += 1
                    if not sampleSword then
                        sampleSword = {name = k, meta = v.sword}
                    end
                end
            end
        end)
        log('Sword items found: ' .. swordCount)
        if sampleSword then
            log('Sample sword: ' .. sampleSword.name)
            safeGet(function()
                for k, v in pairs(sampleSword.meta) do
                    log('  ' .. tostring(k) .. ' = ' .. tostring(v))
                end
            end)
        end
    end

    sep('DAO CONTROLLER CHECK')

    local daoCtrl = safeGet(function() return Knit.Controllers.DaoController end)
    log('DaoController exists: ' .. tostring(daoCtrl ~= nil))
    if daoCtrl then
        log('  chargingMaid: ' .. tostring(safeGet(function() return daoCtrl.chargingMaid end)))
    end

    sep('STUN CHECK')

    if char then
        local stunTime = safeGet(function() return char:GetAttribute('StunnedUntilTime') end) or 0
        local serverTime = safeGet(function() return workspace:GetServerTimeNow() end) or 0
        log('StunnedUntilTime: ' .. tostring(stunTime))
        log('ServerTimeNow: ' .. tostring(serverTime))
        log('Currently stunned: ' .. tostring(stunTime > serverTime))
    end

    sep('TOOL / INVENTORY CHECK')

    if char then
        local handItem = safeGet(function() return char:FindFirstChild('HandInvItem') end)
        log('HandInvItem exists: ' .. tostring(handItem ~= nil))
        if handItem then
            log('  Value: ' .. tostring(safeGet(function() return handItem.Value end)))
        end

        local tools = {}
        for _, child in char:GetChildren() do
            if child:IsA('Tool') then
                table.insert(tools, child.Name)
            end
        end
        log('Tools in character: ' .. (#tools > 0 and table.concat(tools, ', ') or 'none'))

        local backpack = lplr:FindFirstChild('Backpack')
        if backpack then
            local bpTools = {}
            for _, child in backpack:GetChildren() do
                if child:IsA('Tool') then
                    table.insert(bpTools, child.Name)
                end
            end
            log('Tools in backpack: ' .. (#bpTools > 0 and table.concat(bpTools, ', ') or 'none'))
        end
    end

    sep('TOUCHINTEREST / TOUCHTRANSMITTER')

    if char then
        local touchCount = 0
        for _, tool in char:GetChildren() do
            if tool:IsA('Tool') then
                local tt = tool:FindFirstChildWhichIsA('TouchTransmitter', true)
                log('Tool "' .. tool.Name .. '" TouchTransmitter: ' .. tostring(tt ~= nil))
                if tt then
                    touchCount += 1
                    log('  Parent: ' .. tostring(tt.Parent and tt.Parent.Name))
                end
            end
        end
        log('Total TouchTransmitters found: ' .. touchCount)
    end

    sep('FIRETOUCHINTEREST CHECK')

    log('firetouchinterest available: ' .. tostring(type(safeGet(function() return firetouchinterest end)) == 'function'))

    sep('DEBUG LIBRARY CHECK')

    local debugFuncs = {'getconstants', 'setconstant', 'getupvalue', 'setupvalue', 'getproto', 'getprotos'}
    for _, name in debugFuncs do
        log('debug.' .. name .. ': ' .. tostring(type(safeGet(function() return debug[name] end)) == 'function'))
    end

    sep('HOOKFUNCTION CHECK')

    log('hookfunction: ' .. tostring(type(safeGet(function() return hookfunction end)) == 'function'))
    log('hookmetamethod: ' .. tostring(type(safeGet(function() return hookmetamethod end)) == 'function'))
    log('newcclosure: ' .. tostring(type(safeGet(function() return newcclosure end)) == 'function'))

    sep('NEW / CHANGED FIELDS SCAN')

    log('Scanning SwordController for all fields...')
    safeGet(function()
        local keys = {}
        for k, v in pairs(swc) do
            table.insert(keys, {key = tostring(k), valType = type(v)})
        end
        table.sort(keys, function(a, b) return a.key < b.key end)
        for _, kv in keys do
            log('  ' .. kv.key .. ': ' .. kv.valType)
        end
    end)

    sep('DONE')
    log('Total lines: ' .. #buffer)
    copyLog()
end

local function startLiveWatch()
    if watching then
        print(PREFIX, 'Already watching - call SwordStop() first')
        return
    end
    table.clear(buffer)
    watching = true
    log('Live sword combat monitor started')

    local Knit = safeGet(function()
        return require(replicatedStorage.rbxts_include.node_modules["@easy-games"].knit.src).KnitClient
    end)
    local swc = Knit and safeGet(function() return Knit.Controllers.SwordController end)
    local Client = safeGet(function() return require(replicatedStorage.TS.remotes).default.Client end)
    local OldGet = Client and Client.Get

    if not swc or not Client then
        log('ERROR: Cannot hook - SwordController or Client missing')
        watching = false
        return
    end

    local attackCount, blockCount, errorCount = 0, 0, 0

    Client.Get = function(self, remoteName)
        local call = OldGet(self, remoteName)

        return setmetatable({}, {
            __index = function(_, key)
                if key == 'SendToServer' then
                    return function(_, payload, ...)
                        attackCount += 1
                        log('[ATTACK #' .. attackCount .. '] Remote: ' .. tostring(remoteName))

                        if type(payload) == 'table' then
                            log('  weapon: ' .. tostring(payload.weapon))
                            log('  entityInstance: ' .. tostring(payload.entityInstance))

                            if payload.validate then
                                for k, v in pairs(payload.validate) do
                                    if type(v) == 'table' and v.value then
                                        log('  validate.' .. k .. '.value = ' .. tostring(v.value))
                                    elseif type(v) == 'table' then
                                        for k2, v2 in pairs(v) do
                                            if type(v2) == 'table' and v2.value then
                                                log('  validate.' .. k .. '.' .. k2 .. '.value = ' .. tostring(v2.value))
                                            else
                                                log('  validate.' .. k .. '.' .. k2 .. ' = ' .. tostring(v2))
                                            end
                                        end
                                    else
                                        log('  validate.' .. k .. ' = ' .. tostring(v))
                                    end
                                end
                            else
                                log('  WARNING: No validate table in payload!')
                            end

                            for k, v in pairs(payload) do
                                if k ~= 'weapon' and k ~= 'chargedAttack' and k ~= 'entityInstance' and k ~= 'validate' then
                                    log('  NEW FIELD: ' .. tostring(k) .. ' = ' .. tostring(v))
                                end
                            end
                        end

                        local ok, result = pcall(function()
                            return call:SendToServer(payload, ...)
                        end)

                        if not ok then
                            errorCount += 1
                            log('  ERROR on send: ' .. tostring(result))
                        else
                            log('  Sent OK')
                        end

                        return result
                    end
                elseif key == 'instance' then
                    return call.instance
                end
                return call[key]
            end
        })
    end

    table.insert(hooks, function()
        Client.Get = OldGet
    end)

    local origSwing = swc.swingSwordAtMouse
    swc.swingSwordAtMouse = function(self, ...)
        log('[SWING] swingSwordAtMouse called, args: ' .. select('#', ...))
        local ok, res = pcall(origSwing, self, ...)
        if not ok then
            log('[SWING] ERROR: ' .. tostring(res))
        end
        return res
    end

    table.insert(hooks, function()
        swc.swingSwordAtMouse = origSwing
    end)

    local origClick = swc.isClickingTooFast
    swc.isClickingTooFast = function(self, ...)
        local result = origClick(self, ...)
        if result then
            blockCount += 1
            log('[CPS BLOCKED #' .. blockCount .. '] isClickingTooFast returned true, lastSwing=' .. tostring(swc.lastSwing))
        end
        return result
    end

    table.insert(hooks, function()
        swc.isClickingTooFast = origClick
    end)

    log('Hooks installed - swing your sword to capture data')
    log('Call SwordStop() when done')
    copyLog()
end

local function stopWatch()
    if not watching then
        print(PREFIX, 'Not currently watching')
        return
    end
    watching = false
    for _, unhook in hooks do
        pcall(unhook)
    end
    table.clear(hooks)
    log('Stopped - ' .. #buffer .. ' lines captured')
    copyLog()
end

getgenv().SwordDebug = run
getgenv().SwordWatch = startLiveWatch
getgenv().SwordStop = stopWatch
getgenv().SwordCopy = copyLog

run()

end)
if not ok then
    warn('[SwordDebug] SCRIPT ERROR: ' .. tostring(err))
end
