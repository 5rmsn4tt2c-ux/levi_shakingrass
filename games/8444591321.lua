local function _isfile(f) local ok, r = pcall(readfile, f); return ok and r ~= nil and r ~= '' end
local commit = _isfile('levi_shakingrass/profiles/commit.txt') and readfile('levi_shakingrass/profiles/commit.txt') or 'main'
local target = 'levi_shakingrass/games/6872274481.lua'
if not _isfile(target) then
	local ok, src = pcall(game.HttpGet, game, 'https://raw.githubusercontent.com/5rmsn4tt2c-ux/levi_shakingrass/'..commit..'/games/6872274481.lua', true)
	if ok and src and src ~= '404: Not Found' and #src > 100 then
		writefile(target, '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..src)
	end
end
if _isfile(target) then
	local fn, err = loadstring(readfile(target), '6872274481')
	if fn then fn() else error('6872274481 parse error: '..tostring(err)) end
end
