local ok, err = pcall(function()
local cloneref = cloneref or function(obj) return obj end
local setclipboard = setclipboard or toclipboard or function() end
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local runService = cloneref(game:GetService('RunService'))
local lplr = cloneref(game:GetService('Players')).LocalPlayer
local buf = {}
local function log(s) table.insert(buf, s) print('[CANNON]', s) end
local function copy() pcall(setclipboard, table.concat(buf, '\n')) end
local function safe(f) local o, r = pcall(f) return o and r or nil end

log('=== Cannon Debug ===')
log('Time: ' .. os.date())
log('Player: ' .. lplr.Name)

-- Grab the same Client the game/vape fires remotes through
local remotesModule = safe(function() return require(replicatedStorage.TS.remotes).default end)
if not remotesModule or not remotesModule.Client then
	log('ERROR: could not find remotes.Client (require path changed?)')
	copy()
	return
end
local Client = remotesModule.Client
local OldGet = Client.Get

-- After a launch, sample body velocity for ~1.5s to see the real resulting speed
local sampling = false
local function sampleVelocity(tag)
	if sampling then return end
	sampling = true
	task.spawn(function()
		local peak, t0 = 0, os.clock()
		while os.clock() - t0 < 1.5 do
			local char = lplr.Character
			local root = char and (char:FindFirstChild('HumanoidRootPart') or char.PrimaryPart)
			if root then
				local v = root.AssemblyLinearVelocity.Magnitude
				if v > peak then peak = v end
			end
			runService.Heartbeat:Wait()
		end
		log(string.format('  -> [%s] peak body speed after launch: %.1f studs/s', tag, peak))
		copy()
		sampling = false
	end)
end

-- Transparent proxy: only SendToServer/CallServer are intercepted for logging,
-- every other method/property is forwarded to the real remote with correct self.
Client.Get = function(self, name)
	local obj = OldGet(self, name)
	if type(obj) ~= 'table' then return obj end

	return setmetatable({
		SendToServer = function(_, data, ...)
			if type(data) == 'table' and data.cannonBlockPos ~= nil and typeof(data.lookVector) == 'Vector3' then
				log(string.format('CannonAim  | mass(mag)=%.2f | dir=%s | pos=%s',
					data.lookVector.Magnitude,
					tostring(data.lookVector.Magnitude > 0 and data.lookVector.Unit or Vector3.zero),
					tostring(data.cannonBlockPos)))
				copy()
			end
			return obj.SendToServer(obj, data, ...)
		end,
		CallServer = function(_, data, ...)
			local isLaunch = type(data) == 'table' and data.cannonBlockPos ~= nil and data.lookVector == nil
			if isLaunch then
				log('CannonLaunch requested | pos=' .. tostring(data.cannonBlockPos))
				copy()
			end
			local res = obj.CallServer(obj, data, ...)
			if isLaunch then
				log('CannonLaunch result = ' .. tostring(res))
				sampleVelocity('launch')
				copy()
			end
			return res
		end,
	}, {
		__index = function(_, k)
			local v = obj[k]
			if type(v) == 'function' then
				return function(_, ...) return v(obj, ...) end
			end
			return v
		end
	})
end

log('')
log('Hooked. Now go AIM + LAUNCH a cannon.')
log('Legit aim shows mass(mag) ~200. With Cannon Speed on it shows your slider value.')
log('Watch the peak body speed line to see how far/fast the launch actually threw you.')
log('Runs 180s, then unhooks and auto-copies. Test in a calm spot (not mid-fight).')
copy()

task.delay(180, function()
	Client.Get = OldGet
	log('')
	log('=== Cannon debug ended (Client.Get restored). Copied to clipboard. ===')
	copy()
end)
end)
if not ok then warn('[CANNON] ERROR: ' .. tostring(err)) end
