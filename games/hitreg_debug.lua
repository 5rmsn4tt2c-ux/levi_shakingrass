local ok, err = pcall(function()
local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local lplr = cloneref(game:GetService('Players')).LocalPlayer
local rs = cloneref(game:GetService('RunService'))
local b = {}
local function log(s) table.insert(b, s) print('[DBG]', s) end
local function safe(f) local o, r = pcall(f) return o and r or nil end
local function copy() setclipboard(table.concat(b, '\n')) end

log('=== Hit Reg Debug ===')
log('Time: ' .. os.date())
log('Player: ' .. lplr.Name)

local ZapNet = safe(function() return require(lplr.PlayerScripts.TS.lib.network) end)
local getItemMeta = safe(function() return require(replicatedStorage.TS.item['item-meta']).getItemMeta end)
local SwordController = safe(function()
    local knit = require(lplr.PlayerScripts.TS.knit).default or require(lplr.PlayerScripts.TS.knit)
    return knit.GetController and knit:GetController('SwordController') or nil
end)

if not ZapNet then
    log('ERROR: ZapNet not found')
    copy()
    return
end

local sword, swordName, attackSpeed = nil, 'unknown', 0.30
safe(function()
    if lplr.Character then
        for _, child in lplr.Character:GetDescendants() do
            local meta = safe(function() return getItemMeta(child.Name) end)
            if meta and meta.sword then
                sword = child
                swordName = child.Name
                attackSpeed = meta.sword.attackSpeed or 0.30
                break
            end
        end
    end
end)
log('Sword: ' .. swordName .. ' (attackSpeed=' .. tostring(attackSpeed) .. 's)')
log('')
log('Waiting for first hit... start swinging!')
copy()

local hits = {}
local started = false
local startTime = 0
local lastCopy = 0
local windowSize = 10
local conn

conn = safe(function()
    return ZapNet.EntityDamageEventZap.On(function()
        local now = tick()

        if not started then
            started = true
            startTime = now
            log('')
            log('>>> TRACKING STARTED <<<')
            log('')
        end

        local elapsed = now - startTime
        table.insert(hits, {time = elapsed, tick = now})

        local interval = #hits > 1 and (now - hits[#hits - 1].tick) or 0

        local window = math.floor(elapsed / windowSize)
        local windowHits = 0
        for i = #hits, 1, -1 do
            if hits[i].time >= window * windowSize then
                windowHits += 1
            else
                break
            end
        end

        local line = string.format(
            'Hit #%d | %.2fs | gap=%.3fs | window %d-%ds: %d hits',
            #hits, elapsed, interval,
            window * windowSize, (window + 1) * windowSize,
            windowHits
        )
        log(line)

        if now - lastCopy >= 2 then
            lastCopy = now
            copy()
        end
    end)
end)

if not conn then
    log('ERROR: Could not hook damage event')
    copy()
    return
end

local reportConn
reportConn = rs.Heartbeat:Connect(function()
    if not started then return end

    local elapsed = tick() - startTime

    if elapsed > 0 and math.floor(elapsed) % windowSize == 0 and math.floor(elapsed) > 0 then
        local window = math.floor(elapsed / windowSize) - 1
        local windowHits = 0
        for _, h in hits do
            if h.time >= window * windowSize and h.time < (window + 1) * windowSize then
                windowHits += 1
            end
        end

        if windowHits > 0 then
            local summary = string.format(
                '\n--- Window %d-%ds: %d hits (%.1f per 10s) ---',
                window * windowSize, (window + 1) * windowSize,
                windowHits, windowHits / windowSize * 10
            )
            log(summary)
            copy()
        end
    end
end)

task.delay(120, function()
    if conn then pcall(conn) end
    if reportConn then reportConn:Disconnect() end

    log('')
    log('========================================')
    log('=== FINAL RESULTS ===')
    log('========================================')
    log('Player: ' .. lplr.Name)
    log('Sword: ' .. swordName .. ' (attackSpeed=' .. tostring(attackSpeed) .. 's)')
    log('Total hits: ' .. #hits)

    if #hits > 1 then
        local duration = hits[#hits].time
        log('Duration: ' .. string.format('%.1fs', duration))
        log('Overall rate: ' .. string.format('%.1f hits/10s', #hits / duration * 10))

        local intervals = {}
        for i = 2, #hits do
            table.insert(intervals, hits[i].tick - hits[i - 1].tick)
        end
        table.sort(intervals)

        local sum = 0
        for _, v in intervals do sum += v end
        local avg = sum / #intervals
        local median = intervals[math.ceil(#intervals / 2)]
        local min = intervals[1]
        local max = intervals[#intervals]

        log('')
        log('=== HIT INTERVALS ===')
        log('Average:  ' .. string.format('%.4fs', avg))
        log('Median:   ' .. string.format('%.4fs', median))
        log('Fastest:  ' .. string.format('%.4fs', min))
        log('Slowest:  ' .. string.format('%.4fs', max))

        log('')
        log('=== PER 10s WINDOWS ===')
        local maxWindow = math.floor(duration / windowSize)
        local peakHits, peakWindow = 0, 0
        for w = 0, maxWindow do
            local wHits = 0
            for _, h in hits do
                if h.time >= w * windowSize and h.time < (w + 1) * windowSize then
                    wHits += 1
                end
            end
            if wHits > 0 then
                log(string.format('  %d-%ds: %d hits (%.1f/10s)', w * windowSize, (w + 1) * windowSize, wHits, wHits / windowSize * 10))
                if wHits > peakHits then
                    peakHits = wHits
                    peakWindow = w
                end
            end
        end

        log('')
        log('PEAK: ' .. peakHits .. ' hits in ' .. peakWindow * windowSize .. '-' .. (peakWindow + 1) * windowSize .. 's (' .. string.format('%.1f/10s', peakHits / windowSize * 10) .. ')')

        if peakHits >= 35 then
            log('>>> 35+ HIT REG CONFIRMED <<<')
            log('Effective interval: ' .. string.format('%.4fs', windowSize / peakHits))
        end

        log('')
        log('=== INTERVAL DISTRIBUTION ===')
        local buckets = {
            {name = '<0.25s', min = 0, max = 0.25, count = 0},
            {name = '0.25-0.28s', min = 0.25, max = 0.28, count = 0},
            {name = '0.28-0.30s', min = 0.28, max = 0.30, count = 0},
            {name = '0.30-0.33s', min = 0.30, max = 0.33, count = 0},
            {name = '>0.33s', min = 0.33, max = 999, count = 0},
        }
        for _, v in intervals do
            for _, bucket in buckets do
                if v >= bucket.min and v < bucket.max then
                    bucket.count += 1
                    break
                end
            end
        end
        for _, bucket in buckets do
            if bucket.count > 0 then
                log(string.format('  %s: %d (%.0f%%)', bucket.name, bucket.count, bucket.count / #intervals * 100))
            end
        end
    end

    log('')
    log('=== DONE (auto-copied) ===')
    copy()
end)

log('')
log('Debug running for 2 minutes. Auto-copies every 2s.')
log('Just swing at a dummy or player to start.')
copy()
end)
if not ok then warn('[DBG] ERROR: ' .. tostring(err)) end
