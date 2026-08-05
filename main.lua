repeat task.wait() until game:IsLoaded()
if shared.vape then shared.vape:Uninject() end

local vape
local loadstring = function(...)
	local res, err = loadstring(...)
	if err and vape then
		vape:CreateNotification('Vape', 'Failed to load : '..err, 30, 'alert')
	end
	return res
end
local queue_on_teleport = queue_on_teleport or function() end
local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local cloneref = cloneref or function(obj)
	return obj
end
local playersService = cloneref(game:GetService('Players'))
local httpService = cloneref(game:GetService('HttpService'))

if not isfolder('levi_shakingrass') then
	makefolder('levi_shakingrass')
end
if not isfolder('levi_shakingrass/profiles') then
	makefolder('levi_shakingrass/profiles')
end
if not isfile('levi_shakingrass/profiles/commit.txt') then
	writefile('levi_shakingrass/profiles/commit.txt', 'main')
end

local function downloadFile(path, func)
	local filePath = select(1, path:gsub('levi_shakingrass/', ''))
	local function fetchFile(ref)
		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/5rmsn4tt2c-ux/levi_shakingrass/'..ref..'/'..filePath, true)
		end)
		if suc and res ~= '404: Not Found' then return res end
		return nil
	end
	if not isfile(path) then
		local commit = (isfile('levi_shakingrass/profiles/commit.txt') and readfile('levi_shakingrass/profiles/commit.txt')) or 'main'
		local res = fetchFile(commit)
		if not res and commit ~= 'main' then
			res = fetchFile('main')
		end
		if not res then
			error('404: Not Found ('..filePath..')')
		end
		if path:find('.lua') then
			res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..res
		end
		writefile(path, res)
	else
		local content = readfile(path)
		if not content:find('--This watermark') then
			local commit = (isfile('levi_shakingrass/profiles/commit.txt') and readfile('levi_shakingrass/profiles/commit.txt')) or 'main'
			local res = fetchFile(commit) or fetchFile('main')
			if res then
				res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..res
				writefile(path, res)
			end
		end
	end
	return (func or readfile)(path)
end

local function finishLoading()
	vape.Init = nil
	vape:Load()
	task.spawn(function()
		repeat
			vape:Save()
			task.wait(10)
		until not vape.Loaded
	end)

	local teleportedServers
	vape:Clean(playersService.LocalPlayer.OnTeleport:Connect(function(state)
		if (not teleportedServers) and (not shared.VapeIndependent) then
			teleportedServers = true
			local teleportScript = [[
				if shared.VapeDeveloper then
					loadstring(readfile('levi_shakingrass/main.lua'), 'main')(_scriptconfig)
				else
					loadstring(game:HttpGet('https://raw.githubusercontent.com/5rmsn4tt2c-ux/levi_shakingrass/main/main.lua'), 'init')(_scriptconfig)
				end
			]]
			local teleportConfig = httpService:JSONEncode({})
			teleportConfig = teleportConfig:gsub('":true', "=true"):gsub('{"', '{')
			teleportConfig = teleportConfig:gsub(',"', ','):gsub('":', '=')
			teleportConfig = teleportConfig:gsub('%[', '{'):gsub('%]', '}')
			teleportScript = teleportScript:gsub('_scriptconfig', teleportConfig)
			if shared.VapeDeveloper then
				teleportScript = 'shared.VapeDeveloper = true\n'..teleportScript
			end
			if shared.VapeCustomProfile then
				teleportScript = 'shared.VapeCustomProfile = "'..shared.VapeCustomProfile..'"\n'..teleportScript
			end
			queue_on_teleport(teleportScript)
		end
	end))

	if not shared.vapereload then
		if not vape.Categories then return end
		local appVersion = '0'
		pcall(function()
			appVersion = readfile('levi_shakingrass/profiles/version.txt'):match('%d+') or '0'
		end)
		if vape.Categories.Main.Options['GUI bind indicator'].Enabled then
			vape:CreateNotification('Milyonpuffnoodles v' .. appVersion, (vape.VapeButton and 'Press the button in the top right' or 'Press '..table.concat(vape.Keybind, ' + '):upper())..' to open GUI', 5)
		end
	end
end

if not isfile('levi_shakingrass/profiles/gui.txt') then
	writefile('levi_shakingrass/profiles/gui.txt', 'new')
end
local gui = 'new'

if not isfolder('levi_shakingrass/assets/'..gui) then
	makefolder('levi_shakingrass/assets/'..gui)
end
vape = loadstring(downloadFile('levi_shakingrass/guis/'..gui..'.lua'), 'gui')()
shared.vape = vape

if not shared.VapeIndependent then
	loadstring(downloadFile('levi_shakingrass/games/universal.lua'), 'universal')()
	local suc, err = pcall(function()
    loadstring(downloadFile('levi_shakingrass/games/'..game.PlaceId..'.lua'), tostring(game.PlaceId))()
end)
if not suc then
    vape:CreateNotification('Milyonpuffnoodles', 'Game file failed: '..tostring(err), 10, 'warning')
end
	finishLoading()
else
	vape.Init = finishLoading
	return vape
end
