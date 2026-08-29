-- Restore Plugin-level thread identity — try all executor variants
if setthreadidentity then pcall(setthreadidentity, 8)
elseif setidentity then pcall(setidentity, 8)
elseif syn and syn.set_thread_identity then pcall(syn.set_thread_identity, 8)
elseif getgenv and getgenv().setthreadidentity then pcall(getgenv().setthreadidentity, 8)
end

local canDebug = true
local VERSION = 42
local run = function(func)
	func()
end
local cloneref = cloneref or function(obj)
	return obj
end
local function safeInstance(class)
	local ok, r = pcall(Instance.new, class)
	return ok and r or nil
end
local vapeEvents = setmetatable({
	EntityDamageEvent = safeInstance('BindableEvent')
}, {
	__index = function(self, index)
		self[index] = safeInstance('BindableEvent')
		return self[index]
	end
})
shared.bindable = safeInstance('BindableEvent')
getgenv().vapeEvents = vapeEvents

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local runService = cloneref(game:GetService('RunService'))
local inputService = cloneref(game:GetService('UserInputService'))
local lightingService = cloneref(game:GetService('Lighting'))
local textService = cloneref(game:GetService('TextService'))
local tweenService = cloneref(game:GetService('TweenService'))
local proximityPromptService = cloneref(game:GetService('ProximityPromptService'))
local httpService = cloneref(game:GetService('HttpService'))
local textChatService = cloneref(game:GetService('TextChatService'))
local collectionService = cloneref(game:GetService('CollectionService'))
local contextActionService = cloneref(game:GetService('ContextActionService'))
local guiService = cloneref(game:GetService('GuiService'))
local coreGui = cloneref(game:GetService('CoreGui'))
local starterGui = cloneref(game:GetService('StarterGui'))

local isnetworkowner = isnetworkowner or function()
	return true
end
local gameCamera = workspace.CurrentCamera
local lplr = playersService.LocalPlayer
local _gd = {fn = nil, fv = nil, on = false}
local assetfunction = getcustomasset

local vape = shared.vape
local entitylib = vape.Libraries.entity
local targetinfo = vape.Libraries.targetinfo
local sessioninfo = vape.Libraries.sessioninfo
local uipallet = vape.Libraries.uipallet
local tween = vape.Libraries.tween
local color = vape.Libraries.color
local whitelist = vape.Libraries.whitelist
local prediction = vape.Libraries.prediction
local getfontsize = vape.Libraries.getfontsize
local getcustomasset = vape.Libraries.getcustomasset

local function downloadFile(path, func)
	if not isfile(path) then
		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/5rmsn4tt2c-ux/levi_shakingrass/'..readfile('levi_shakingrass/profiles/commit.txt')..'/'..select(1, path:gsub('levi_shakingrass/', '')), true)
		end)
		if not suc or res == '404: Not Found' then
			error(res)
		end
		if path:find('.lua') then
			res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..res
		end
		writefile(path, res)
	end
	return (func or readfile)(path)
end

local rankCache = {}
local store = {
	lastHit = 0,
	attackReach = 0,
	attackReachUpdate = tick(),
	damageBlockFail = tick(),
	hand = {},
	rank = setmetatable({}, {
		__index = function(self, index)
			return {
				async = function()
					if rankCache[index] then
						return rankCache[index]
					end

					if index then
						local rank = bedwars.Client:Get('FetchRanks'):CallServer({index.UserId})
						if typeof(rank) == 'table' and rank[1] and rank[1].rankDivision then
							rankCache[index] = rank[1].rankDivision
							return rankCache[index]
						end
					end

					return nil
				end,
			}
		end
	}),
	inventory = {
		inventory = {
			items = {},
			armor = {}
		},
		hotbar = {}
	},
	selfProjectiles = {},
	inventories = {},
	matchState = 0,
	queueType = 'bedwars_test',
	tools = {}
}
getgenv().store = store

local Reach = {}
local HitBoxes = {}
local HeadHit = {}
local InfiniteFly = {}
local TrapDisabler
local NoFallDamage
local AntiFallPart
local bedwars, remotes, sides, oldinvrender, oldSwing = {}, {}, {}

local function addBlur(parent)
	local blur = Instance.new('ImageLabel')
	blur.Name = 'Blur'
	blur.Size = UDim2.new(1, 89, 1, 52)
	blur.Position = UDim2.fromOffset(-48, -31)
	blur.BackgroundTransparency = 1
	blur.Image = getcustomasset('levi_shakingrass/assets/new/blur.png')
	blur.ScaleType = Enum.ScaleType.Slice
	blur.SliceCenter = Rect.new(52, 31, 261, 502)
	blur.Parent = parent
	return blur
end

local function collection(tags, module, customadd, customremove)
	tags = typeof(tags) ~= 'table' and {tags} or tags
	local objs, connections = {}, {}

	for _, tag in tags do
		table.insert(connections, collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
			if customadd then
				customadd(objs, v, tag)
				return
			end
			table.insert(objs, v)
		end))
		table.insert(connections, collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
			if customremove then
				customremove(objs, v, tag)
				return
			end
			v = table.find(objs, v)
			if v then
				table.remove(objs, v)
			end
		end))

		for _, v in collectionService:GetTagged(tag) do
			if customadd then
				customadd(objs, v, tag)
				continue
			end
			table.insert(objs, v)
		end
	end

	local cleanFunc = function(self)
		for _, v in connections do
			v:Disconnect()
		end
		table.clear(connections)
		table.clear(objs)
		table.clear(self)
	end
	if module then
		module:Clean(cleanFunc)
	end
	return objs, cleanFunc
end

local function getBestArmor(slot)
	local closest, mag = nil, 0

	for _, item in store.inventory.inventory.items do
		local meta = item and bedwars.ItemMeta[item.itemType] or {}

		if meta.armor and meta.armor.slot == slot then
			local newmag = (meta.armor.damageReductionMultiplier or 0)

			if newmag > mag then
				closest, mag = item, newmag
			end
		end
	end

	return closest
end

local function getBow()
	local bestBow, bestBowSlot, bestBowDamage = nil, nil, 0
	for slot, item in store.inventory.inventory.items do
		local bowMeta = bedwars.ItemMeta[item.itemType].projectileSource
		if bowMeta and table.find(bowMeta.ammoItemTypes, 'arrow') then
			local bowDamage = bedwars.ProjectileMeta[bowMeta.projectileType('arrow')].combat.damage or 0
			if bowDamage > bestBowDamage then
				bestBow, bestBowSlot, bestBowDamage = item, slot, bowDamage
			end
		end
	end
	return bestBow, bestBowSlot
end

local function getItem(itemName, inv, find)
	for slot, item in (inv or store.inventory.inventory.items) do
		if find and item.itemType:find(itemName) or item.itemType == itemName then
			return item, slot
		end
	end
	return nil
end

local function getRoactRender(func)
	return debug.getupvalue(debug.getupvalue(debug.getupvalue(func, 3).render, 2).render, 1)
end

local function getSword()
	local bestSword, bestSwordSlot, bestSwordDamage = nil, nil, 0
	for slot, item in store.inventory.inventory.items do
		local swordMeta = bedwars.ItemMeta[item.itemType].sword
		if swordMeta then
			local swordDamage = swordMeta.damage or 0
			if swordDamage > bestSwordDamage then
				bestSword, bestSwordSlot, bestSwordDamage = item, slot, swordDamage
			end
		end
	end
	return bestSword, bestSwordSlot
end

local function getTool(breakType)
	local bestTool, bestToolSlot, bestToolDamage = nil, nil, 0
	for slot, item in store.inventory.inventory.items do
		local toolMeta = bedwars.ItemMeta[item.itemType].breakBlock
		if toolMeta then
			local toolDamage = toolMeta[breakType] or 0
			if toolDamage > bestToolDamage then
				bestTool, bestToolSlot, bestToolDamage = item, slot, toolDamage
			end
		end
	end
	return bestTool, bestToolSlot
end

local function getWool()
	for _, wool in (inv or store.inventory.inventory.items) do
		if wool.itemType:find('wool') then
			return wool and wool.itemType, wool and wool.amount
		end
	end
end

local function getStrength(plr)
	if not plr.Player then
		return 0
	end

	local strength = 0
	for _, v in (store.inventories[plr.Player] or {items = {}}).items do
		local itemmeta = bedwars.ItemMeta[v.itemType]
		if itemmeta and itemmeta.sword and itemmeta.sword.damage > strength then
			strength = itemmeta.sword.damage
		end
	end

	return strength
end

local function getPlacedBlock(pos)
	if not pos then
		return
	end
	local roundedPosition = bedwars.BlockController:getBlockPosition(pos)
	return bedwars.BlockController:getStore():getBlockAt(roundedPosition), roundedPosition
end
getgenv().getPlacedBlock = getPlacedBlock

local function getBlocksInPoints(s, e)
	local blocks, list = bedwars.BlockController:getStore(), {}
	for x = s.X, e.X do
		for y = s.Y, e.Y do
			for z = s.Z, e.Z do
				local vec = Vector3.new(x, y, z)
				if blocks:getBlockAt(vec) then
					table.insert(list, vec * 3)
				end
			end
		end
	end
	return list
end

local function getNearGround(range)
	range = Vector3.new(3, 3, 3) * (range or 10)
	local localPosition, mag, closest = entitylib.character.RootPart.Position, 60
	local blocks = getBlocksInPoints(bedwars.BlockController:getBlockPosition(localPosition - range), bedwars.BlockController:getBlockPosition(localPosition + range))

	for _, v in blocks do
		if not getPlacedBlock(v + Vector3.new(0, 3, 0)) then
			local newmag = (localPosition - v).Magnitude
			if newmag < mag then
				mag, closest = newmag, v + Vector3.new(0, 3, 0)
			end
		end
	end

	table.clear(blocks)
	return closest
end

local function getShieldAttribute(char)
	local returned = 0
	for name, val in char:GetAttributes() do
		if name:find('Shield') and type(val) == 'number' and val > 0 then
			returned = returned + val
		end
	end
	return returned
end


local knockbackSpeed, knockbackBoost = 0, tick()
local function getSpeed()
	local multi, increase, modifiers = 0, true, bedwars.SprintController:getMovementStatusModifier():getModifiers()

	for v in modifiers do
		local val = v.constantSpeedMultiplier and v.constantSpeedMultiplier or 0
		if val and val > math.max(multi, 1) then
			increase = false
			multi = val - (0.06 * math.round(val))
		end
	end

	for v in modifiers do
		multi = multi + math.max((v.moveSpeedMultiplier or 0) - 1, 0)
	end

	if multi > 0 and increase then
		multi = multi + 0.16 + (0.02 * math.round(multi))
	end

	return (20 + (knockbackBoost > tick() and knockbackSpeed or 0)) * (multi + 1)
end
getgenv().getSpeed = getSpeed

local function getTableSize(tab)
	local ind = 0
	for _ in tab do
		ind = ind + 1
	end
	return ind
end

local function getHotbar(tool)
	for i, v in (store.inventory.hotbar or {}) do
		if v.item and v.item.tool == tool then
			return i - 1
		end
	end
	return nil
end
getgenv().getHotbar = getHotbar

local function hotbarSwitch(slot)
	if slot and store.inventory.hotbarSlot ~= slot then
		bedwars.Store:dispatch({
			type = 'InventorySelectHotbarSlot',
			slot = slot
		})
		vapeEvents.InventoryChanged.Event:Wait()
		return true
	end
	return false
end
getgenv().hotbarSwitch = hotbarSwitch

local function isFriend(plr, recolor)
	if vape.Categories.Friends.Options['Use friends'].Enabled then
		local friend = table.find(vape.Categories.Friends.ListEnabled, plr.Name) and true
		if recolor then
			friend = friend and vape.Categories.Friends.Options['Recolor visuals'].Enabled
		end
		return friend
	end
	return nil
end

local function isTarget(plr)
	return table.find(vape.Categories.Targets.ListEnabled, plr.Name) and true
end

local function notif(...) return vape:CreateNotification(...) end
local loadMessages = {
	'king auto the best',
	'manny blantant',
	'bloopybestkav2 don\'t cheat',
	'king draco worst solo q',
	'kolipoo is the best',
	'we love kolipoo',
	'i love money',
	'draco dookie',
	'bby boo',
	'manny here',
	'ta daaa',
	'hahaha',
	'ready to cheat',
	'hello 👋',
	'love is beautiful',
	'kemby',
	'mannyalt',
	'manny is gay',
	'osoi',
	'why you cheating',
	'yall know manny gay right',
	'we all gay only that not',
	'auto 5ft 4',
}
notif('Loaded', loadMessages[math.random(#loadMessages)] .. ' | Update ' .. VERSION, 90, 'info')

local function removeTags(str)
	str = str:gsub('<br%s*/>', '\n')
	return (str:gsub('<[^<>]->', ''))
end

local function roundPos(vec)
	return Vector3.new(math.round(vec.X / 3) * 3, math.round(vec.Y / 3) * 3, math.round(vec.Z / 3) * 3)
end

local function switchItem(tool, delayTime)
	delayTime = delayTime or 0.05
	local check = lplr.Character and lplr.Character:FindFirstChild('HandInvItem') or nil
	if check and check.Value ~= tool and tool.Parent ~= nil then
		task.spawn(function()
			bedwars.Client:Get(remotes.EquipItem):CallServerAsync({hand = tool})
		end)
		check.Value = tool
		if delayTime > 0 then
			task.wait(delayTime)
		end
		return true
	end
end
getgenv().switchItem = switchItem

local function waitForChildOfType(obj, name, timeout, prop)
	local check, returned = tick() + timeout, nil
	repeat
		returned = prop and obj[name] or obj:FindFirstChildOfClass(name)
		if returned and returned.Name ~= 'UpperTorso' or check < tick() then
			break
		end
		task.wait()
	until false
	return returned
end

local function waitForChildYield(obj, timeout, ...)
	local check, returned = tick(), obj
	for _, v in { ... } do
		if not returned then
			break
		end
		check = tick() + timeout
		repeat
			local new = returned:FindFirstChild(v)
			if new or tick() > check then
				returned = new
				break
			end
			task.wait()
		until false
	end
	return returned
end

local function rakNetCheck(module)
	if not (raknet and raknet.add_send_hook and pcall(raknet.add_send_hook, function() end)) then
		notif(module, 'This feature requires raknet! (risky feature, please do not use on mains.)', 10, 'warning')
		return false
	end

	return true
end

local frictionTable, oldfrict = {}, {}
local frictionConnection
local frictionState

local function modifyVelocity(v)
	if v:IsA('BasePart') and v.Name ~= 'HumanoidRootPart' and not oldfrict[v] then
		oldfrict[v] = v.CustomPhysicalProperties or 'none'
		v.CustomPhysicalProperties = PhysicalProperties.new(0.0001, 0.2, 0.5, 1, 1)
	end
end

local function updateVelocity(force)
	local newState = getTableSize(frictionTable) > 0
	if frictionState ~= newState or force then
		if frictionConnection then
			frictionConnection:Disconnect()
		end
		if newState then
			if entitylib.isAlive then
				for _, v in entitylib.character.Character:GetDescendants() do
					modifyVelocity(v)
				end
				frictionConnection = entitylib.character.Character.DescendantAdded:Connect(modifyVelocity)
			end
		else
			for i, v in oldfrict do
				i.CustomPhysicalProperties = v ~= 'none' and v or nil
			end
			table.clear(oldfrict)
		end
	end
	frictionState = newState
end

local kitorder = {
	hannah = 5,
	spirit_assassin = 4,
	dasher = 3,
	jade = 2,
	regent = 1
}

local getBlockHits
local sortmethods, breakmethods = {
	Damage = function(a, b)
		return a.Entity.Character:GetAttribute('LastDamageTakenTime') < b.Entity.Character:GetAttribute('LastDamageTakenTime')
	end,
	Threat = function(a, b)
		return getStrength(a.Entity) > getStrength(b.Entity)
	end,
	Kit = function(a, b)
		return (a.Entity.Player and kitorder[a.Entity.Player:GetAttribute('PlayingAsKit')] or 0) > (b.Entity.Player and kitorder[b.Entity.Player:GetAttribute('PlayingAsKit')] or 0)
	end,
	Health = function(a, b)
		return a.Entity.Health < b.Entity.Health
	end,
	Angle = function(a, b)
		local selfrootpos = entitylib.character.RootPart.Position
		local localfacing = entitylib.character.RootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
		local angle = math.acos(localfacing:Dot(((a.Entity.RootPart.Position - selfrootpos) * Vector3.new(1, 0, 1)).Unit))
		local angle2 = math.acos(localfacing:Dot(((b.Entity.RootPart.Position - selfrootpos) * Vector3.new(1, 0, 1)).Unit))
		return angle < angle2
	end,
	Mouse = function(a, b)
		local mouse = lplr:GetMouse()
		local origin = Vector2.new(mouse.X, mouse.Y)

		local posa, visa = gameCamera:WorldToScreenPoint(a.Entity.RootPart.Position)
		local posb, visb = gameCamera:WorldToScreenPoint(b.Entity.RootPart.Position)
		local dista = visa and (Vector2.new(posa.X, posa.Y) - origin).Magnitude or math.huge
        local distb = visb and (Vector2.new(posb.X, posb.Y) - origin).Magnitude or math.huge
        return (dista == dista and dista or math.huge) < (distb == distb and distb or math.huge)
	end
}, {
	Health = function(...)
		return getBlockHits(...)
	end,
	Distance = function(a)
		local pos = (entitylib.isAlive and (entitylib.character.RootPart.Position - Vector3.new(0, 1, 0)) or Vector3.zero)
		return (pos - Vector3.new(a.Position.X, pos.Y, a.Position.Z)).Magnitude
	end
}

run(function()
	local oldstart = entitylib.start
	local function customEntity(ent)
		if ent:HasTag('inventory-entity') and not ent:HasTag('Monster') and not ent:HasTag('trainingRoomDummy') then
			return
		end

		entitylib.addEntity(ent, nil, ent:HasTag('Drone') and function(self)
			local droneplr = playersService:GetPlayerByUserId(self.Character:GetAttribute('PlayerUserId'))
			return not droneplr or lplr:GetAttribute('Team') ~= droneplr:GetAttribute('Team')
		end or function(self)
			return lplr:GetAttribute('Team') ~= self.Character:GetAttribute('Team')
		end)
	end

	entitylib.start = function()
		oldstart()
		if entitylib.Running then
			for _, ent in collectionService:GetTagged('entity') do
				customEntity(ent)
			end
			table.insert(entitylib.Connections, collectionService:GetInstanceAddedSignal('entity'):Connect(customEntity))
			table.insert(entitylib.Connections, collectionService:GetInstanceRemovedSignal('entity'):Connect(function(ent)
				entitylib.removeEntity(ent)
			end))
		end
	end

	entitylib.addPlayer = function(plr)
		if plr.Character then
			entitylib.refreshEntity(plr.Character, plr)
		end
		entitylib.PlayerConnections[plr] = {
			plr.CharacterAdded:Connect(function(char)
				entitylib.refreshEntity(char, plr)
			end),
			plr.CharacterRemoving:Connect(function(char)
				entitylib.removeEntity(char, plr == lplr)
			end),
			plr:GetAttributeChangedSignal('Team'):Connect(function()
				for _, v in entitylib.List do
					if v.Targetable ~= entitylib.targetCheck(v) then
						entitylib.refreshEntity(v.Character, v.Player)
					end
				end

				if plr == lplr then
					entitylib.start()
				else
					entitylib.refreshEntity(plr.Character, plr)
				end
			end)
		}
	end

	entitylib.addEntity = function(char, plr, teamfunc)
		if not char then return end
		entitylib.EntityThreads[char] = task.spawn(function()
			local hum, humrootpart, head
			if plr then
				hum = waitForChildOfType(char, 'Humanoid', 10)
				humrootpart = hum and waitForChildOfType(hum, 'RootPart', workspace.StreamingEnabled and 9e9 or 10, true)
				head = char:WaitForChild('Head', 10) or humrootpart
			else
				hum = {HipHeight = 0.5}
				humrootpart = waitForChildOfType(char, 'PrimaryPart', 10, true)
				head = humrootpart
			end
			local updateobjects = plr and plr ~= lplr and {
				char:WaitForChild('ArmorInvItem_0', 5),
				char:WaitForChild('ArmorInvItem_1', 5),
				char:WaitForChild('ArmorInvItem_2', 5),
				char:WaitForChild('HandInvItem', 5)
			} or {}

			if hum and humrootpart then
				local entity = {
					Connections = {},
					Character = char,
					Health = (char:GetAttribute('Health') or 100) + getShieldAttribute(char),
					Head = head,
					Humanoid = hum,
					HumanoidRootPart = humrootpart,
					HipHeight = hum.HipHeight + (humrootpart.Size.Y / 2) + (hum.RigType == Enum.HumanoidRigType.R6 and 2 or 0),
					Jumps = 0,
					JumpTick = tick(),
					Jumping = false,
					LandTick = tick(),
					MaxHealth = char:GetAttribute('MaxHealth') or 100,
					NPC = plr == nil,
					Player = plr,
					RootPart = humrootpart,
					TeamCheck = teamfunc
				}

				if plr == lplr then
					entity.AirTime = tick()
					entitylib.character = entity
					entitylib.isAlive = true
					entitylib.Events.LocalAdded:Fire(entity)
					table.insert(entitylib.Connections, char.AttributeChanged:Connect(function(attr)
						vapeEvents.AttributeChanged:Fire(attr)
					end))
				else
					entity.Targetable = entitylib.targetCheck(entity)
					if plr ~= nil then
						table.insert(entity.Connections, hum.AnimationPlayed:Connect(function(track)
							entitylib.Events.AnimationPlayed:Fire(plr, track)
						end))
					end
					
					for _, v in entitylib.getUpdateConnections(entity) do
						table.insert(entity.Connections, v:Connect(function()
							entity.Health = (char:GetAttribute('Health') or 100) + getShieldAttribute(char)
							entity.MaxHealth = char:GetAttribute('MaxHealth') or 100
							entitylib.Events.EntityUpdated:Fire(entity)
						end))
					end

					for _, v in updateobjects do
						table.insert(entity.Connections, v:GetPropertyChangedSignal('Value'):Connect(function()
							task.delay(0.1, function()
								if bedwars.getInventory then
									store.inventories[plr] = bedwars.getInventory(plr)
									entitylib.Events.EntityUpdated:Fire(entity)
								end
							end)
						end))
					end

					if plr then
						local anim = char:FindFirstChild('Animate')
						if anim then
							pcall(function()
								anim = anim.jump:FindFirstChildWhichIsA('Animation').AnimationId
								table.insert(entity.Connections, hum.Animator.AnimationPlayed:Connect(function(playedanim)
									if playedanim.Animation.AnimationId == anim then
										entity.JumpTick = tick()
										entity.Jumps = entity.Jumps + 1
										entity.LandTick = tick() + 1
										entity.Jumping = entity.Jumps > 1
									end
								end))
							end)
						end

						task.delay(0.1, function()
							if bedwars.getInventory then
								store.inventories[plr] = bedwars.getInventory(plr)
							end
						end)
					end
					table.insert(entitylib.List, entity)
					entitylib.Events.EntityAdded:Fire(entity)
				end

				table.insert(entity.Connections, char.ChildRemoved:Connect(function(part)
					if part == humrootpart or part == hum or part == head then
						if part == humrootpart and hum.RootPart then
							humrootpart = hum.RootPart
							entity.RootPart = hum.RootPart
							entity.HumanoidRootPart = hum.RootPart
							return
						end
						entitylib.removeEntity(char, plr == lplr)
					end
				end))
			end
			entitylib.EntityThreads[char] = nil
		end)
	end

	entitylib.getUpdateConnections = function(ent)
		local char = ent.Character
		local tab = {
			char:GetAttributeChangedSignal('Health'),
			char:GetAttributeChangedSignal('MaxHealth'),
			{
				Connect = function()
					ent.Friend = ent.Player and isFriend(ent.Player) or nil
					ent.Target = ent.Player and isTarget(ent.Player) or nil
					return {Disconnect = function() end}
				end
			}
		}

		if ent.Player then
			table.insert(tab, ent.Player:GetAttributeChangedSignal('PlayingAsKit'))
		end

		for name, val in char:GetAttributes() do
			if name:find('Shield') and type(val) == 'number' then
				table.insert(tab, char:GetAttributeChangedSignal(name))
			end
		end

		return tab
	end

	entitylib.targetCheck = function(ent)
		if ent.TeamCheck then
			return ent:TeamCheck()
		end
		if ent.NPC then return true end
		if isFriend(ent.Player) then return false end
		if not select(2, whitelist:get(ent.Player)) then return false end
		return lplr:GetAttribute('Team') ~= ent.Player:GetAttribute('Team')
	end
	vape:Clean(entitylib.Events.LocalAdded:Connect(updateVelocity))
end)
entitylib.start()

local require, debug = require, debug
shared.gg = {}
run(function()
	canDebug = not table.find({'Solara', 'Xeno'}, ({identifyexecutor()})[1]) and true or false
	if not canDebug then
		local cheatenginelib = loadstring(downloadFile('levi_shakingrass/libraries/cheatenginelib.lua'), 'cheatenginelib')(vape, vapeEvents, entitylib)
		require = function(v) 
			return cheatenginelib[({v:GetFullName():gsub(lplr.Name, 'PlayerTemplate')})[1]]:await()
		end
		debug = setmetatable({getproto = function() return function() end end}, {
			__index = function(self, index)
				self[index] = function() end
				return self[index]
			end
		})
	end
end)

local calculatePath
local CheatersFlagged = {}
local function safeRequire(fn)
	local ok, r = pcall(fn)
	return ok and r or nil
end
run(function()
	local KnitInit, Knit
	repeat
		KnitInit, Knit = pcall(function()
			return require(replicatedStorage.rbxts_include.node_modules["@easy-games"].knit.src).KnitClient
		end)
		if KnitInit then break end
		task.wait()
	until KnitInit

	if canDebug and not debug.getupvalue(Knit.Start, 1) then
		repeat task.wait() until debug.getupvalue(Knit.Start, 1)
	end
	
	local Flamework = safeRequire(function() return require(replicatedStorage['rbxts_include']['node_modules']['@flamework'].core.out).Flamework end)
	local InventoryUtil = safeRequire(function() return require(replicatedStorage.TS.inventory['inventory-util']).InventoryUtil end)
	local Client = safeRequire(function() return require(replicatedStorage.TS.remotes).default.Client end)
	local OldGet, OldBreak = Client and Client.Get or nil, nil

	bedwars = setmetatable({
		AbilityController = safeRequire(function() return Flamework.resolveDependency('@easy-games/game-core:client/controllers/ability/ability-controller@AbilityController') end),
		AnimationType = safeRequire(function() return require(replicatedStorage.TS.animation['animation-type']).AnimationType end),
		AdetundeUpgradeMeta = safeRequire(function() return require(replicatedStorage.TS.games.bedwars.items['frosty-hammer']['frosty-hammer-upgrades']).FrostyHammerUpgradeMeta end),
		AdetundeUtil = safeRequire(function() return require(replicatedStorage.TS.games.bedwars.items['frosty-hammer']['frosty-hammer-util']).FrostyHammerUtil end),
		AnimationUtil = safeRequire(function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out['shared'].util['animation-util']).AnimationUtil end),
		AppController = safeRequire(function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out.client.controllers['app-controller']).AppController end),
		BedBreakEffectMeta = safeRequire(function() return require(replicatedStorage.TS.locker['bed-break-effect']['bed-break-effect-meta']).BedBreakEffectMeta end),
		BedwarsKitMeta = safeRequire(function() return require(replicatedStorage.TS.games.bedwars.kit['bedwars-kit-meta']).BedwarsKitMeta end),
		BedwarsKitSkin = canDebug and debug.getupvalue(require(replicatedStorage.TS.games.bedwars['kit-skin']['bedwars-kit-skin-meta']).getKitSkinMetadata, 1) or {},
		BlockBreaker = Knit.Controllers.BlockBreakController.blockBreaker,
		BlockController = safeRequire(function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out).BlockEngine end),
		BlockEngine = safeRequire(function() return require(lplr.PlayerScripts.TS.lib['block-engine']['client-block-engine']).ClientBlockEngine end),
		BlockPlacer = safeRequire(function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out.client.placement['block-placer']).BlockPlacer end),
		BlockSelector = safeRequire(function() return require(replicatedStorage.rbxts_include.node_modules['@easy-games']['block-engine'].out.client.select['block-selector']).BlockSelector end),
		BowConstantsTable = canDebug and debug.getupvalue(Knit.Controllers.ProjectileController.enableBeam, 8) or {RelX = 0, RelY = 0, RelZ = 0},
		ClickHold = safeRequire(function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out.client.ui.lib.util['click-hold']).ClickHold end),
		Client = Client,
		ClientConstructor = safeRequire(function() return require(replicatedStorage['rbxts_include']['node_modules']['@rbxts'].net.out.client) end),
		ClientDamageBlock = safeRequire(function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out.shared.remotes).BlockEngineRemotes.Client end),
		CombatConstant = safeRequire(function() return require(replicatedStorage.TS.combat['combat-constant']).CombatConstant end),
		ChargeState = safeRequire(function() return require(replicatedStorage.TS.combat['charge-state']).ChargeState end),
		SyncEvents = safeRequire(function() return require(lplr.PlayerScripts.TS['client-sync-events']).ClientSyncEvents end),
		DamageIndicator = Knit.Controllers.DamageIndicatorController.spawnDamageIndicator,
		DefaultKillEffect = safeRequire(function() return require(lplr.PlayerScripts.TS.controllers.global.locker['kill-effect'].effects['default-kill-effect']) end),
		EnchantMeta = safeRequire(function() return require(replicatedStorage.TS.enchant['enchant-meta']).EnchantMeta end),
		EmoteType = safeRequire(function() return require(replicatedStorage.TS.locker.emote['emote-type']).EmoteType end),
		GamePlayer = safeRequire(function() return require(replicatedStorage.TS.player['game-player']) end),
		GameAnimationUtil = safeRequire(function() return require(replicatedStorage.TS.animation['animation-util']).GameAnimationUtil end),
		getIcon = function(item, showinv)
			local itemmeta = bedwars.ItemMeta[item.itemType]
			return itemmeta and showinv and itemmeta.image or ''
		end,
		getInventory = function(plr)
			local suc, res = pcall(function()
				return InventoryUtil.getInventory(plr)
			end)
			return suc and res or {
				items = {},
				armor = {}
			}
		end,
		HudAliveCount = safeRequire(function() return require(lplr.PlayerScripts.TS.controllers.global['top-bar'].ui.game['hud-alive-player-counts']).HudAlivePlayerCounts end),
		ItemMeta = safeRequire(function() return require(replicatedStorage.TS.item['item-meta']).items end),
		KillEffectMeta = safeRequire(function() return require(replicatedStorage.TS.locker['kill-effect']['kill-effect-meta']).KillEffectMeta end),
		KillFeedController = safeRequire(function() return Flamework.resolveDependency('client/controllers/game/kill-feed/kill-feed-controller@KillFeedController') end),
		Knit = Knit,
		KnockbackUtil = safeRequire(function() return require(replicatedStorage.TS.damage['knockback-util']).KnockbackUtil end),
		MageKitUtil = safeRequire(function() return require(replicatedStorage.TS.games.bedwars.kit.kits.mage['mage-kit-util']).MageKitUtil end),
		MatchHistroyController = Knit.Controllers.MatchHistoryController,
		NotificationController = safeRequire(function() return Flamework.resolveDependency('@easy-games/game-core:client/controllers/notification-controller@NotificationController') end),
		NametagController = Knit.Controllers.NametagController,
		PartyController = safeRequire(function() return Flamework.resolveDependency('@easy-games/lobby:client/controllers/party-controller@PartyController') end),
		ProjectileMeta = safeRequire(function() return require(replicatedStorage.TS.projectile['projectile-meta']).ProjectileMeta end),
		QueryUtil = safeRequire(function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).GameQueryUtil end),
		QueueCard = safeRequire(function() return require(lplr.PlayerScripts.TS.controllers.global.queue.ui['queue-card']).QueueCard end),
		QueueMeta = safeRequire(function() return require(replicatedStorage.TS.game['queue-meta']).QueueMeta end),
		Roact = safeRequire(function() return require(replicatedStorage['rbxts_include']['node_modules']['@rbxts']['roact'].src) end),
		RankMeta = safeRequire(function() return require(replicatedStorage.TS.rank['rank-meta']).RankMeta end),
		RuntimeLib = safeRequire(function() return require(replicatedStorage['rbxts_include'].RuntimeLib) end),
		SummonerKitBalance = safeRequire(function() return require(replicatedStorage.TS.games.bedwars.kit.kits.summoner['summoner-kit-balance']).SummonerKitBalance end),
		StatusEffectUtil = safeRequire(function() return require(replicatedStorage.TS['status-effect']['status-effect-util']).StatusEffectUtil end),
		StatusEffectMeta = safeRequire(function() return require(replicatedStorage.TS['status-effect']['status-effect-type']).StatusEffectType end),
		SharedConstants = canDebug and require(replicatedStorage.TS['shared-constants']).CpsConstants or {},
		SoundList = safeRequire(function() return require(replicatedStorage.TS.sound['game-sound']).GameSound end),
		SoundManager = safeRequire(function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).SoundManager end),
		Store = safeRequire(function() return require(lplr.PlayerScripts.TS.ui.store).ClientStore end),
		TeamUpgradeMeta = canDebug and debug.getupvalue(require(replicatedStorage.TS.games.bedwars['team-upgrade']['team-upgrade-meta']).getTeamUpgradeMetaForQueue, 7) or {},
		UILayers = safeRequire(function() return require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out).UILayers end),
		VisualizerUtils = safeRequire(function() return require(lplr.PlayerScripts.TS.lib.visualizer['visualizer-utils']).VisualizerUtils end),
		WeldTable = safeRequire(function() return require(replicatedStorage.TS.util['weld-util']).WeldUtil end),
		WinEffectMeta = safeRequire(function() return require(replicatedStorage.TS.locker['win-effect']['win-effect-meta']).WinEffectMeta end),
		ZapNetworking = safeRequire(function() return require(lplr.PlayerScripts.TS.lib.network) end)
	}, {
		__index = function(self, ind)
			rawset(self, ind, Knit.Controllers[ind])
			return rawget(self, ind)
		end
	})
	getgenv().bedwars = bedwars
	store.enchants = setmetatable({}, {
		__index = function(self, plr)
			return {
				async = function()
					if plr and plr.Character then
						for i in plr.Character:GetAttributes() do
							if i:find('StatusEffect_') and not i:find('_stacks') then
								local name = bedwars.StatusEffectMeta[({i:gsub('StatusEffect_', '')})[1]]
								if bedwars.StatusEffectMeta[name] then
									name = bedwars.StatusEffectMeta[name]
									for num = 1, 3 do
										name = name:gsub(`_{num}`, '')
									end

									if bedwars.EnchantMeta[name] then
										return bedwars.EnchantMeta[name].image
									end
								end
							end
						end
					end
					return nil
				end,
			}
		end
	})

	local function createMethodHook(object, method)
		local original = object[method]
		local hooks, order = {}, 0
		local wrapper

		local function sync()
			if #hooks > 0 then
				object[method] = wrapper
			elseif object[method] == wrapper then
				object[method] = original
			end
		end

		wrapper = function(...)
			local index = 0
			local function nextHook(...)
				index = index + 1
				local hook = hooks[index]
				if hook then
					return hook.Callback(nextHook, ...)
				end
				return original(...)
			end
			return nextHook(...)
		end

		return {
			Add = function(_, id, priority, callback)
				for i = #hooks, 1, -1 do
					if hooks[i].Id == id then
						table.remove(hooks, i)
					end
				end

				order = order + 1
				local entry = {
					Id = id,
					Priority = priority or 100,
					Order = order,
					Callback = callback,
				}

				table.insert(hooks, entry)
				table.sort(hooks, function(a, b)
					return a.Priority == b.Priority and a.Order < b.Order or a.Priority < b.Priority
				end)
				sync()

				return function()
					for i = #hooks, 1, -1 do
						if hooks[i] == entry then
							table.remove(hooks, i)
						end
					end
					sync()
				end
			end,
			Destroy = function()
				table.clear(hooks)
				sync()
			end,
		}
	end

	bedwars.ProjectileLaunchHook = createMethodHook(bedwars.ProjectileController, 'calculateImportantLaunchValues')
	vape:Clean(function()
		bedwars.ProjectileLaunchHook:Destroy()
	end)

	local function getproto(...)
		local success, res = pcall(debug.getproto, ...)
		return success and res or function() end
	end
	local remoteNames = {
		AfkStatus = canDebug and getproto(Knit.Controllers.AfkController.KnitStart, 1) or function() end,
		AttackEntity = canDebug and Knit.Controllers.SwordController.sendServerRequest or function() end,
		BeePickup = canDebug and Knit.Controllers.BeeNetController.trigger or function() end,
		CannonAim = canDebug and getproto(Knit.Controllers.CannonController.startAiming, 5) or function() end,
		CannonLaunch = canDebug and Knit.Controllers.CannonHandController.launchSelf or function() end,
		ConsumeBattery = canDebug and getproto(Knit.Controllers.BatteryController.onKitLocalActivated, 1) or function() end,
		ConsumeItem = canDebug and getproto(Knit.Controllers.ConsumeController.onEnable, 1) or function() end,
		ConsumeSoul = canDebug and Knit.Controllers.GrimReaperController.consumeSoul or function() end,
		ConsumeTreeOrb = canDebug and getproto(Knit.Controllers.EldertreeController.createTreeOrbInteraction, 1) or function() end,
		DepositPinata = canDebug and getproto(getproto(Knit.Controllers.PiggyBankController.KnitStart, 2), 5) or function() end,
		DragonBreath = canDebug and getproto(Knit.Controllers.VoidDragonController.onKitLocalActivated, 5) or function() end,
		DragonEndFly = canDebug and getproto(Knit.Controllers.VoidDragonController.flapWings, 1) or function() end,
		DragonFly = canDebug and Knit.Controllers.VoidDragonController.flapWings or function() end,
		DropItem = canDebug and Knit.Controllers.ItemDropController.dropItemInHand or function() end,
		EquipItem = canDebug and getproto(require(replicatedStorage.TS.entity.entities['inventory-entity']).InventoryEntity.equipItem, 4) or function() end,
		FireProjectile = canDebug and debug.getupvalue(Knit.Controllers.ProjectileController.launchProjectileWithValues, 2) or function() end,
		GroundHit = canDebug and getproto(Knit.Controllers.FallDamageController.KnitStart, 1) or function() end,
		GuitarHeal = canDebug and Knit.Controllers.GuitarController.performHeal or function() end,
		HannahKill = canDebug and getproto(Knit.Controllers.HannahController.registerExecuteInteractions, 1) or function() end,
		HarvestCrop = canDebug and getproto(getproto(Knit.Controllers.CropController.KnitStart, 4), 1) or function() end,
		KaliyahPunch = canDebug and getproto(Knit.Controllers.DragonSlayerController.onKitLocalActivated, 1) or function() end,
		MageSelect = canDebug and getproto(Knit.Controllers.MageController.registerTomeInteraction, 1) or function() end,
		MinerDig = canDebug and getproto(Knit.Controllers.MinerController.setupMinerPrompts, 1) or function() end,
		PickupItem = canDebug and Knit.Controllers.ItemDropController.checkForPickup or function() end,
		PickupMetal = canDebug and getproto(Knit.Controllers.HiddenMetalController.onKitLocalActivated, 4) or function() end,
		ReportPlayer = canDebug and require(lplr.PlayerScripts.TS.controllers.global.report['report-controller']).default.reportPlayer or function() end,
		ResetCharacter = canDebug and getproto(Knit.Controllers.ResetController.createBindable, 1) or function() end,
		SpawnRaven = canDebug and getproto(Knit.Controllers.RavenController.KnitStart, 1) or function() end,
		SummonerClawAttack = canDebug and Knit.Controllers.SummonerClawHandController.attack or function() end,
		WarlockTarget = canDebug and getproto(Knit.Controllers.WarlockStaffController.KnitStart, 2) or function() end
	}

	local packages = httpService:JSONDecode(downloadFile('levi_shakingrass/profiles/packages.json'))	
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

	for i, v in remoteNames do
		local _ok, _constants = pcall(debug.getconstants, v)
		local remote = dumpRemote(_ok and _constants or nil)
		if remote == '' and packages.remotes[i] then
			remote = packages.remotes[i]
		end
		if remote == '' then
			notif('Vape', 'Failed to grab remote ('..i..')', 10, 'alert')
		end
		remotes[i] = remote
	end
    getgenv().remotes = remotes

	OldBreak = bedwars.BlockController.isBlockBreakable
	OldHit = bedwars.BlockBreaker.hitBlock

	bedwars.BlockBreaker.hitBlock = function(...)
        store.lastHit = tick()
        return OldHit(...)
    end
	if canDebug then
		Client.Get = function(self, remoteName)
			local call = OldGet(self, remoteName)

			if remoteName == remotes.AttackEntity then
				return {
					instance = call.instance,
					SendToServer = function(_, attackTable, ...)
						local suc, plr = pcall(function()
							return playersService:GetPlayerFromCharacter(attackTable.entityInstance)
						end)

						local selfpos = attackTable.validate.selfPosition.value
						local targetpos = attackTable.validate.targetPosition.value
						store.attackReach = math.floor((selfpos - targetpos).Magnitude * 100) / 100
						store.attackReachUpdate = tick() + 1

						if Reach.Enabled or HitBoxes.Enabled then
							attackTable.validate.raycast = attackTable.validate.raycast or {}
							attackTable.validate.selfPosition.value = attackTable.validate.selfPosition.value + CFrame.lookAt(selfpos, targetpos).LookVector * math.max((selfpos - targetpos).Magnitude - 14.399, 0)
						end

						if suc and plr then
							if not select(2, whitelist:get(plr)) then return end
						end

						return call:SendToServer(attackTable, ...)
					end
				}
			elseif remoteName == 'StepOnSnapTrap' and TrapDisabler.Enabled then
				return {SendToServer = function() end}
			elseif remoteName == remotes.GroundHit and NoFallDamage and NoFallDamage.Enabled then
				return {SendToServer = function() end}
			end

			return call
		end
	end

	bedwars.BlockController.isBlockBreakable = function(self, breakTable, plr)
		local obj = bedwars.BlockController:getStore():getBlockAt(breakTable.blockPosition)

		if obj and obj.Name == 'bed' then
			for _, plr in playersService:GetPlayers() do
				if obj:GetAttribute('Team'..(plr:GetAttribute('Team') or 0)..'NoBreak') and not select(2, whitelist:get(plr)) then
					return false
				end
			end
		end

		return OldBreak(self, breakTable, plr)
	end

	local cache, blockhealthbar = {}, {blockHealth = -1, breakingBlockPosition = Vector3.zero}
	store.blockPlacer = bedwars.BlockPlacer.new(bedwars.BlockEngine, 'wool_white')

	local function getBlockHealth(block, blockpos)
		local blockdata = bedwars.BlockController:getStore():getBlockData(blockpos)
		return (blockdata and (blockdata:GetAttribute('1') or blockdata:GetAttribute('Health')) or block:GetAttribute('Health'))
	end

	getBlockHits = function(block, blockpos)
		if not block then return 0 end
		local breaktype = bedwars.ItemMeta[block.Name].block.breakType
		local tool = store.tools[breaktype]
		tool = tool and bedwars.ItemMeta[tool.itemType].breakBlock[breaktype] or 2
		return getBlockHealth(block, bedwars.BlockController:getBlockPosition(blockpos)) / tool
	end

	--[[
		Pathfinding using a luau version of dijkstra's algorithm
		Source: https://stackoverflow.com/questions/39355587/speeding-up-dijkstras-algorithm-to-solve-a-3d-maze
	]]
	local function isMinable(pos)
		for _, side in {Vector3.new(0, 3, 0), Vector3.new(3, 0, 0), Vector3.new(0, 0, 3)} do
			side = pos + side
			local block = getPlacedBlock(side)
			if not block or (block:GetAttribute("PlacedByUserId") or 0) ~= 0 then
				return true
			end
		end
		return false
	end
	calculatePath = function(target, blockpos, method, angle, wallcheck)
		local visited, unvisited, distances, air, path = {}, {{0, blockpos}}, {[blockpos] = 0}, {}, {}

		for _ = 1, 10000 do
			local _, node = next(unvisited)
			if not node then break end
			table.remove(unvisited, 1)
			visited[node[2]] = true

			for _, side in sides do
				local block
				local curdist
				side = node[2] + side
				if visited[side] then continue end

				block = getPlacedBlock(side)
				if not block or block:GetAttribute('NoBreak') or block == target then
					if not block then
						air[node[2]] = true
					end
					continue
				end

				if math.acos((gameCamera.CFrame.LookVector * Vector3.new(1, 0, 1)):Dot(((block.Position - entitylib.character.RootPart.Position) * Vector3.new(1, 0, 1)).Unit)) > (math.rad(angle) / 2) then
					continue
				end

				curdist = (method and method(block, side) or getBlockHits(block, side)) + node[1]
				if curdist < (distances[side] or math.huge) then
					table.insert(unvisited, {curdist, side})
					distances[side] = curdist
					path[side] = node[2]
				end
			end
		end

		local pos, cost = nil, math.huge
		for node in air do
			if distances[node] < cost and (not wallcheck or isMinable(node)) then
				pos, cost = node, distances[node]
			end
		end

		if pos then
			cache[blockpos] = {
				pos,
				cost,
				path,
			}
			return pos, cost, path
		end
		return nil
	end

	bedwars.placeBlock = function(pos, item)
		if getItem(item) then
			store.blockPlacer.blockType = item
			return store.blockPlacer:placeBlock(bedwars.BlockController:getBlockPosition(pos))
		end
	end

	bedwars.breakBlock = function(block, effects, anim, customHealthbar, visualise, sort, angle, wallcheck, keepTarget, noSwitch)
		if lplr:GetAttribute('DenyBlockBreak') or not entitylib.isAlive or InfiniteFly.Enabled then return end

		local handler = bedwars.BlockController:getHandlerRegistry():getHandler(block.Name)
		local cost, pos, target, path = math.huge, nil, nil, nil

		for _, v in (handler and handler:getContainedPositions(block) or {block.Position / 3}) do
			local dpos, dcost, dpath = calculatePath(block, v * 3, sort, angle or 360, wallcheck)
			if dpos and dcost < cost then
				cost, pos, target, path = dcost, dpos, v * 3, dpath
			end
		end

		if pos then
			if (entitylib.character.RootPart.Position - pos).Magnitude > 30 then return end
			local dblock, dpos = getPlacedBlock(pos)
			if not dblock then return end
			if keepTarget and dblock == block then return end

			if not noSwitch and (workspace:GetServerTimeNow() - bedwars.SwordController.lastAttack) > 0.4 then
				local breaktype = dblock.Name == 'gumdrop_bounce_pad' and 'stone' or bedwars.ItemMeta[dblock.Name].block.breakType
				local tool = store.tools[breaktype]
				if tool then
					if visualise then
						local hotbar = getHotbar(tool.tool)
						if hotbar then
							hotbarSwitch(hotbar)
						end
					else
						switchItem(tool.tool)
					end
				end
			end

			if blockhealthbar.blockHealth == -1 or dpos ~= blockhealthbar.breakingBlockPosition then
				blockhealthbar.blockHealth = getBlockHealth(dblock, dpos)
				blockhealthbar.breakingBlockPosition = dpos
			end

			bedwars.ClientDamageBlock:Get('DamageBlock'):CallServerAsync({
				blockRef = {blockPosition = dpos},
				hitPosition = pos,
				hitNormal = Vector3.FromNormalId(Enum.NormalId.Top)
			}):andThen(function(result)
				if result then
					if result == 'cancelled' then
						store.damageBlockFail = tick() + 1
						return
					end

					if effects then
						local blockdmg = (blockhealthbar.blockHealth - (result == 'destroyed' and 0 or getBlockHealth(dblock, dpos)))
						customHealthbar = customHealthbar or bedwars.BlockBreaker.updateHealthbar
						customHealthbar(bedwars.BlockBreaker, {blockPosition = dpos}, blockhealthbar.blockHealth, dblock:GetAttribute('MaxHealth'), blockdmg, dblock)
						blockhealthbar.blockHealth = math.max(blockhealthbar.blockHealth - blockdmg, 0)

						if blockhealthbar.blockHealth <= 0 then
							bedwars.BlockBreaker.breakEffect:playBreak(dblock.Name, dpos, lplr)
							bedwars.BlockBreaker.healthbarMaid:DoCleaning()
							blockhealthbar.breakingBlockPosition = Vector3.zero
						else
							bedwars.BlockBreaker.breakEffect:playHit(dblock.Name, dpos, lplr)
						end
					end

					if anim then
						local animation = bedwars.AnimationUtil:playAnimation(lplr, bedwars.BlockController:getAnimationController():getAssetId(1))
						bedwars.ViewmodelController:playAnimation(15)
						task.wait(0.3)
						animation:Stop()
						animation:Destroy()
					end
				end
			end)

			if effects then
				return pos, path, target
			end
		end
		return nil
	end

	for _, v in Enum.NormalId:GetEnumItems() do
		table.insert(sides, Vector3.FromNormalId(v) * 3)
	end

	local function updateStore(new, old)
		if new.Bedwars ~= old.Bedwars then
			store.equippedKit = new.Bedwars.kit ~= 'none' and new.Bedwars.kit or ''
		end

		if new.Game ~= old.Game then
			store.matchState = new.Game.matchState
			store.queueType = new.Game.queueType or 'bedwars_test'
		end

		if new.Inventory ~= old.Inventory then
			local newinv = (new.Inventory and new.Inventory.observedInventory or {inventory = {}})
			local oldinv = (old.Inventory and old.Inventory.observedInventory or {inventory = {}})
			store.inventory = newinv

			if newinv ~= oldinv then
				vapeEvents.InventoryChanged:Fire()
			end

			if newinv.inventory.items ~= oldinv.inventory.items then
				vapeEvents.InventoryAmountChanged:Fire()
				store.tools.sword = getSword()
				for _, v in {'stone', 'wood', 'wool'} do
					store.tools[v] = getTool(v)
				end
			end

			if newinv.inventory.hand ~= oldinv.inventory.hand then
				local currentHand, toolType = new.Inventory.observedInventory.inventory.hand, ''
				if currentHand then
					local handData = bedwars.ItemMeta[currentHand.itemType]
					if handData then
						toolType = handData.sword and 'sword' or handData.block and 'block' or currentHand.itemType:find('bow') and 'bow'
					end
				end

				store.hand = {
					tool = currentHand and currentHand.tool,
					amount = currentHand and currentHand.amount or 0,
					toolType = toolType
				}
			end
		end
	end

	local storeChanged = bedwars.Store.changed:connect(updateStore)
	updateStore(bedwars.Store:getState(), {})

	for _, event in {'MatchEndEvent', 'EntityDeathEvent', 'BedwarsBedBreak', 'BalloonPopped', 'AngelProgress', 'GrapplingHookFunctions'} do
		if not vape.Connections then return end
		bedwars.Client:WaitFor(event):andThen(function(connection)
			vape:Clean(connection:Connect(function(...)
				vapeEvents[event]:Fire(...)
			end))
		end)
	end

	vape:Clean(bedwars.ZapNetworking.EntityDamageEventZap.On(function(...)
		local a = {
			entityInstance = ...,
			damage = select(2, ...),
			damageType = select(3, ...),
			fromPosition = select(4, ...),
			fromEntity = select(5, ...),
			knockbackMultiplier = select(6, ...),
			knockbackId = select(7, ...),
			disableDamageHighlight = select(13, ...)
		}
		shared.bindable:Fire(a)
		vapeEvents.EntityDamageEvent:Fire(a)
	end))
	
	vape:Clean(workspace.ChildAdded:Connect(function(projectile)
		task.delay(0, function()
			if projectile and projectile.Parent and entitylib.isAlive and projectile:GetAttribute('ProjectileShooter') == lplr.UserId then
				table.insert(store.selfProjectiles, projectile)
				projectile.Destroying:Once(function()
					local index = table.find(store.selfProjectiles, projectile)
					if index then
						table.remove(store.selfProjectiles, index)
					end
				end)
			end
		end)
	end))

	for _, event in {'BreakBlockEvent'} do
		vape:Clean(bedwars.ZapNetworking[event..'Zap'].On(function(...)
			local data = {
				blockRef = {
					blockPosition = ...,
				},
				player = select(5, ...)
			}
			for i, v in cache do
				if ((data.blockRef.blockPosition * 3) - v[1]).Magnitude <= 30 then
					table.clear(v[3])
					table.clear(v)
					cache[i] = nil
				end
			end
			vapeEvents[event]:Fire(data)
		end))
	end

	store.blocks = collection('block', vape)
	store.shop = collection({'BedwarsItemShop', 'TeamUpgradeShopkeeper'}, vape, function(tab, obj)
		table.insert(tab, {
			Id = obj.Name,
			RootPart = obj,
			Shop = obj:HasTag('BedwarsItemShop'),
			Upgrades = obj:HasTag('TeamUpgradeShopkeeper')
		})
	end)
	store.enchant = collection({'enchant-table', 'broken-enchant-table'}, vape, nil, function(tab, obj, tag)
		if obj:HasTag('enchant-table') and tag == 'broken-enchant-table' then return end
		obj = table.find(tab, obj)
		if obj then
			table.remove(tab, obj)
		end
	end)

	local kills = sessioninfo:AddItem('Kills')
	local beds = sessioninfo:AddItem('Beds')
	local wins = sessioninfo:AddItem('Wins')
	local games = sessioninfo:AddItem('Games')
	sessioninfo:AddItem('Cheater List', '', function()
		local text = ''
		for _, plr in playersService:GetPlayers() do
			if CheatersFlagged[plr] then
				text = text..'\n'..(plr.DisplayName ~= plr.Name and plr.DisplayName..' ('..plr.Name..')' or plr.Name)
			end
		end

		return text
	end, false)

	local mapname = 'Unknown'
	sessioninfo:AddItem('Map', 0, function()
		return mapname
	end, false)

	task.delay(1, function()
		games:Increment()
	end)

	task.spawn(function()
		pcall(function()
			repeat task.wait() until store.matchState ~= 0 or vape.Loaded == nil
			if vape.Loaded == nil then return end
			store.map = waitForChildYield(workspace, 9e9, 'Map', 'Worlds'):GetChildren()[1]
			mapname = store.map.Name
			mapname = string.gsub(string.split(mapname, '_')[2] or mapname, '-', '') or 'Blank'
			if store.map then
				vape:Clean(store.map.Blocks.ChildAdded:Connect(function(v) -- bedwars game is so bad bro 😭 how did you even break this event
					task.delay(0, function()
						if v:GetAttribute('Block') and (v:GetAttribute('PlacedByUserId') or 0) ~= 0 then
							local data = {
								blockRef = {
									blockPosition = v.Position / 3,
								},
								player = playersService:GetPlayerByUserId(v:GetAttribute('PlacedByUserId')),
							}
							for i, v in cache do
								if ((data.blockRef.blockPosition * 3) - v[1]).Magnitude <= 30 then
									table.clear(v[3])
									table.clear(v)
									cache[i] = nil
								end
							end
							vapeEvents.PlaceBlockEvent:Fire(data)
						end
					end)
				end))
			end
		end)
	end)

	vape:Clean(vapeEvents.BedwarsBedBreak.Event:Connect(function(bedTable)
		if bedTable.player and bedTable.player.UserId == lplr.UserId then
			beds:Increment()
		end
	end))

	vape:Clean(vapeEvents.MatchEndEvent.Event:Connect(function(winTable)
		if (bedwars.Store:getState().Game.myTeam or {}).id == winTable.winningTeamId or lplr.Neutral then
			wins:Increment()
		end
	end))

	vape:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
		local killer = playersService:GetPlayerFromCharacter(deathTable.fromEntity)
		local killed = playersService:GetPlayerFromCharacter(deathTable.entityInstance)
		if not killed or not killer then return end

		if killed ~= lplr and killer == lplr then
			kills:Increment()
		end
	end))

	task.spawn(function()
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = {workspace:WaitForChild('Map', 9e9)}
		store.airRay = rayParams

		repeat
			if entitylib.isAlive then
				entitylib.character.AirTime = workspace:Raycast((store.rootpart or entitylib.character.RootPart).Position, Vector3.new(0, -4.5, 0), rayParams) and tick() or entitylib.character.AirTime
			end

			for _, v in entitylib.List do
				v.LandTick = math.abs(v.RootPart.Velocity.Y) < 0.1 and v.LandTick or tick()
				if (tick() - v.LandTick) > 0.2 and v.Jumps ~= 0 then
					v.Jumps = 0
					v.Jumping = false
				end
			end
			task.wait()
		until vape.Loaded == nil
	end)

	pcall(function()
		if getthreadidentity and setthreadidentity or not canDebug then
			local old = getthreadidentity()
			setthreadidentity(2)

			bedwars.Shop = require(replicatedStorage.TS.games.bedwars.shop['bedwars-shop']).BedwarsShop
			bedwars.ShopItems = debug.getupvalue(debug.getupvalue(bedwars.Shop.getShopItem, 1), 2)
			bedwars.Shop.getShopItem('iron_sword', lplr)

			setthreadidentity(old)
			store.shopLoaded = true
		else
			task.spawn(function()
				repeat
					task.wait(0.1)
				until vape.Loaded == nil or bedwars.AppController:isAppOpen('BedwarsItemShopApp')

				bedwars.Shop = require(replicatedStorage.TS.games.bedwars.shop['bedwars-shop']).BedwarsShop
				bedwars.ShopItems = debug.getupvalue(debug.getupvalue(bedwars.Shop.getShopItem, 1), 2)
				store.shopLoaded = true
			end)
		end
	end)

	vape:Clean(function()
		Client.Get = OldGet
		bedwars.BlockController.isBlockBreakable = OldBreak
		store.blockPlacer:disable()
		shared.bindable:Destroy()
		for _, v in vapeEvents do
			v:Destroy()
		end
		for _, v in cache do
			table.clear(v[3])
			table.clear(v)
		end
		table.clear(store.blockPlacer)
		table.clear(vapeEvents)
		table.clear(bedwars)
		table.clear(store)
		table.clear(cache)
		table.clear(sides)
		table.clear(remotes)
		storeChanged:disconnect()
		storeChanged = nil
	end)
end)

for _, v in {'Anti Ragdoll', 'Trigger Bot', 'Silent Aim', 'Auto Rejoin', 'Rejoin', 'Disabler', 'Timer', 'Server Hop', 'Mouse TP', 'Murder Mystery', 'No Fall Damage'} do
	vape:Remove(v)
end

local AntiFallDirection
local Fly
local LongJump
local Attacking

--[[
    Combat
]]

run(function()
    local AimAssist
    local AimMode
    local Mode
    local Targets
    local Sort
    local AimPart
    local AimSpeed
    local Shake
    local Distance
    local AngleSlider
    local StrafeIncrease
    local BlockBreak
    local KillauraTarget
    local ClickAim
    local Mouse
    local Limit

    -- aim smoothing modes (keys of aimfuncs) and target-sort methods
    local modes = {'Simple', 'Adaptive'}
    local methods = {'Damage', 'Distance'}
    for i in sortmethods do
        if not table.find(methods, i) then
            table.insert(methods, i)
        end
    end

    local function ease(t)
        return t < 0.5 and 4 * t * t * t or 1 - math.pow(-2 * t + 2, 3) / 2
    end
    
    local cache = {}
    local function getMousePosition()
        if inputService.TouchEnabled then
            return gameCamera.ViewportSize / 2
        end
        return inputService.GetMouseLocation(inputService)
    end
    
    local function getAim(ent)
        if AimPart.Value == 'Closest' then
            if not cache[ent.Character] then
                cache[ent.Character] = ent.Character:GetChildren()
            end
            local localPosition, magnitude, part = getMousePosition(), 9e9, nil
            for _, v in cache[ent.Character] do
                if v and v.Parent and v:IsA('BasePart') then
                    local position, vis = gameCamera.WorldToViewportPoint(gameCamera, v.Position)
                    if vis then
                        local mag = (localPosition - Vector2.new(position.x, position.y)).Magnitude
                        if mag < magnitude then
                            magnitude = mag
                            part = v
                        end
                    end
                end
            end
            if part then
                return part.Position
            end
        end
        return ent.RootPart.Position
    end
    
    local started, lasttarget = 0, nil
    local aimfuncs = {
        Simple = function(localcframe, ent, fps)
            local rng = Random.new()
            local speed = (AimSpeed.Value + (StrafeIncrease.Enabled and (inputService:IsKeyDown(Enum.KeyCode.A) or inputService:IsKeyDown(Enum.KeyCode.D)) and 10 or 0))
            return localcframe:Lerp(CFrame.lookAt(localcframe.p, getAim(ent) + Vector3.new((rng:NextNumber() - 0.5) * Shake.Value * fps, (rng:NextNumber() - 0.5) * Shake.Value * fps, (rng:NextNumber() - 0.5) * Shake.Value * fps)), speed * fps), speed
        end,
        Adaptive = function(localcframe, ent, fps)
            local prog, rng = ease(math.min(tick() - started, 1)), Random.new()
            local speed = (AimSpeed.Value * 0.1 * prog) + (1 - prog) + (StrafeIncrease.Enabled and (inputService:IsKeyDown(Enum.KeyCode.A) or inputService:IsKeyDown(Enum.KeyCode.D)) and 10 or 5)
            return localcframe:Lerp(CFrame.lookAt(localcframe.p, getAim(ent) + Vector3.new((rng:NextNumber() - 0.5) * Shake.Value * fps, (rng:NextNumber() - 0.5) * Shake.Value * fps, (rng:NextNumber() - 0.5) * Shake.Value * fps)), speed * fps), speed
        end
    }
    
    local function GetTarget()
        if lasttarget then
            local localPosition = entitylib.character.RootPart.Position
            if not lasttarget or not lasttarget.RootPart or not lasttarget.Humanoid or not lasttarget.Humanoid.Health or lasttarget.Humanoid.Health <= 0 then
                return false
            end
            if (localPosition - lasttarget.RootPart.Position).Magnitude > Distance.Value then
                return false
            end
            if Targets.Walls.Enabled and entitylib.Wallcheck(localPosition, lasttarget.RootPart.Position, Targets.Walls.Enabled) then
                return false
            end
            return lasttarget
        end
        return false
    end
    
    local function getAttackData()
        if Mouse.Enabled and not inputService:IsMouseButtonPressed(0) and (tick() - bedwars.SwordController.lastSwing) > 0.15 then
            return false
        end
        if ClickAim.Enabled and (tick() - bedwars.SwordController.lastSwing) > 0.3 then
            return false
        end
        if BlockBreak.Enabled and (tick() - store.lastHit) < 0.3 then
            return false
        end
        if Limit.Enabled and store.hand.toolType ~= 'sword' then
            return false
        end
        if (tick() - started) > 1 or not lasttarget or not lasttarget.Parent or not lasttarget.Humanoid or lasttarget.Humanoid.Health <= 0 then
            local ent = GetTarget() or KillauraTarget.Enabled and store.KillauraTarget or entitylib.EntityPosition({
                Range = Distance.Value,
                Part = 'RootPart',
                Wallcheck = Targets.Walls.Enabled,
                Players = Targets.Players.Enabled,
                NPCs = Targets.NPCs.Enabled,
                Sort = sortmethods[Sort.Value],
            })
            if ent then
                started = tick()
            end
            lasttarget = ent
        end
        return lasttarget
    end
    
    AimAssist = vape.Categories.Combat:CreateModule({
        Name = 'Aim Assist',
        Function = function(callback)
            if callback then
                local rotate = 0
                AimAssist:Clean(runService.PostSimulation:Connect(function(dt)
                    if entitylib.isAlive then
                        entitylib.character.Humanoid.AutoRotate = tick() > rotate
                        local ent = getAttackData()
                        if ent then
                            local root = entitylib.character.RootPart
                            local delta = (ent.RootPart.Position - root.Position)
                            local localfacing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
                            local angle = math.acos(localfacing:Dot((delta * Vector3.new(1, 0, 1)).Unit))
                            if angle >= (math.rad(AngleSlider.Value) / 2) then
                                return
                            end
                            targetinfo.Targets[ent] = tick() + 1
                            local cframe, speed = aimfuncs[Mode.Value](gameCamera.CFrame, ent, dt)
                            if AimMode.Value == 'First person' or AimMode.Value == 'Dynamic' and entitylib.character.Head.LocalTransparencyModifier == 1 then
                                gameCamera.CFrame = cframe
                            elseif AimMode.Value == 'Third person' or AimMode.Value == 'Dynamic' and entitylib.character.Head.LocalTransparencyModifier ~= 1 then
                                cframe, speed = aimfuncs[Mode.Value](root.CFrame, ent, dt)
                                entitylib.character.Humanoid.AutoRotate = false
                                root.CFrame = CFrame.lookAlong(root.Position, cframe.LookVector * Vector3.new(1, 0, 1))
                                rotate = tick() + 0.1
                            elseif AimMode.Value == 'Mouse' then
                                local viewport = gameCamera:WorldToViewportPoint(cframe.Position)
                                local pos = (Vector2.new(viewport.X, viewport.Y) - inputService:GetMouseLocation()) * (speed / 15)
                                mousemoverel(pos.X, pos.Y)
                            end
                        end
                    end
                end))
            end
        end,
        Tooltip = 'Smoothly aims to closest valid target with sword'
    })

    -- Dropdowns & sliders
    AimMode = AimAssist:CreateDropdown({ Name = 'Aim perspective', List = {'First person', 'Third person', 'Dynamic'}, Default = 'First person' })
    Mode    = AimAssist:CreateDropdown({ Name = 'Mode', List = modes, Default = modes[1] })
    Targets = AimAssist:CreateTargets({ Players = true, Walls = true })
    ClickAim       = AimAssist:CreateToggle({ Name = 'Click aim', Default = true })
    Mouse          = AimAssist:CreateToggle({ Name = 'Require mouse down' })
    StrafeIncrease = AimAssist:CreateToggle({ Name = 'Strafe increase' })
    BlockBreak     = AimAssist:CreateToggle({ Name = 'Check block break' })
    KillauraTarget = AimAssist:CreateToggle({ Name = 'Use killaura target' })
    AimSpeed  = AimAssist:CreateSlider({ Name = 'Aim speed', Min = 1, Max = 20, Default = 6 })
    Distance  = AimAssist:CreateSlider({ Name = 'Distance', Min = 1, Max = 30, Default = 30 })
    Shake     = AimAssist:CreateSlider({ Name = 'Shake', Min = 0, Max = 100, Default = 0 })
    AngleSlider = AimAssist:CreateSlider({ Name = 'Max angle', Min = 1, Max = 360, Default = 70 })
    Limit     = AimAssist:CreateToggle({ Name = 'Limit to items', Tooltip = 'Only attacks when sword is held' })
    Sort      = AimAssist:CreateDropdown({ Name = 'Target mode', List = methods, Default = 'Angle' })
    AimPart   = AimAssist:CreateDropdown({ Name = 'Target area', List = {'Center', 'Closest'}, Default = 'Center' })
end)

run(function()
    local AutoClicker
    local CPS
    local Wool
    local BlockCPS
    local Thread
    local MobileCPS
    local MobileDutyCycle
    local MobileThread

    -- Support keyboard, mouse, and gamepad (controller) attack inputs
    local function isAttack(input)
        local keybinds = bedwars.KeybindLoadController:getKeybinds()
        local keyboard = keybinds and keybinds.keyboard and keybinds.keyboard.controlActions.Attack or Enum.UserInputType.MouseButton1
        local gamepad  = keybinds and keybinds.gamepad  and keybinds.gamepad.controlActions.Attack  or Enum.KeyCode.ButtonR2
        return input.UserInputType == keyboard or input.KeyCode == keyboard or input.KeyCode == gamepad
    end

    local function woolOk()
        return not (Wool and Wool.Enabled) or (store.hand.tool and store.hand.tool.Name:find('wool_'))
    end

    local function MobileClick()
        if MobileThread then
            task.cancel(MobileThread)
        end

        MobileThread = task.delay(1 / (store.hand.toolType == 'block' and BlockCPS or CPS).GetRandomValue(), function()
            repeat
                if not bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then
                    if store.hand.toolType == 'block' and woolOk() then
                        local blockPlacer = bedwars.BlockPlacementController.blockPlacer
                        if blockPlacer and canDebug then
                            task.spawn(function()
                                blockPlacer:autoBridge(
                                    workspace:GetServerTimeNow() - bedwars.KnockbackController:getLastKnockbackTime()
                                        >= 0.2
                                )
                            end)
                        end
                    elseif store.hand.toolType == 'sword' then
                        bedwars.SwordController:swingSwordAtMouse(0.39)
                    end
                end
                local _period = 1 / (store.hand.toolType == 'block' and BlockCPS or CPS).GetRandomValue()
                local _dc = MobileDutyCycle.Value / 100
                task.wait(_period * _dc)
                task.wait(_period * (1 - _dc))
            until not AutoClicker.Enabled
        end)
    end

    local function AutoClick()
    	if Thread then
    		task.cancel(Thread)
    	end

    	Thread = task.delay(1 / (store.hand.toolType == 'block' and BlockCPS or CPS).GetRandomValue(), function()
    		repeat
    			if not bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then
    				local blockPlacer = bedwars.BlockPlacementController.blockPlacer
    				if store.hand.toolType == 'block' and blockPlacer and woolOk() then
    					if canDebug then
    						if inputService.TouchEnabled then
    							task.spawn(function()
    								blockPlacer:autoBridge(
    									workspace:GetServerTimeNow() - bedwars.KnockbackController:getLastKnockbackTime()
    										>= 0.2
    								)
    							end)
    						else
    							if
    								(workspace:GetServerTimeNow() - bedwars.BlockCpsController.lastPlaceTimestamp)
    								>= ((1 / 12) * 0.5)
    							then
    								local mouseinfo
    								if canDebug then
    									mouseinfo = blockPlacer.clientManager:getBlockSelector():getMouseInfo(0)
    								else
    									mouseinfo = { placementPosition = lplr:GetMouse().Hit.Position }
    								end
    								if mouseinfo and mouseinfo.placementPosition == mouseinfo.placementPosition then
    									if canDebug then
    										task.spawn(blockPlacer.placeBlock, blockPlacer, mouseinfo.placementPosition)
    									else
    										bedwars.placeBlock(({ getPlacedBlock(mouseinfo.placementPosition) })[2])
    									end
    								end
    							end
    						end
    					end
    				elseif store.hand.toolType == 'sword' then
    					bedwars.SwordController:swingSwordAtMouse(0.39)
    				end
    			end

    			task.wait(1 / (store.hand.toolType == 'block' and BlockCPS or CPS).GetRandomValue())
    		until not AutoClicker.Enabled
    	end)
    end

    AutoClicker = vape.Categories.Combat:CreateModule({
    	Name = 'Auto Clicker',
    	Function = function(callback)
    		if callback then
    			AutoClicker:Clean(inputService.InputBegan:Connect(function(input)
    				if isAttack(input) then
    					AutoClick()
    				end
    			end))

    			AutoClicker:Clean(inputService.InputEnded:Connect(function(input)
    				if isAttack(input) and Thread then
    					task.cancel(Thread)
    					Thread = nil
    				end
    			end))

    			if inputService.TouchEnabled then
    				local hooked = {}
    				local function hookButton(button)
    					if hooked[button] or not button:IsA('GuiButton') or not tonumber(button.Name) then return end
    					hooked[button] = true
    					AutoClicker:Clean(button.MouseButton1Down:Connect(MobileClick))
    					AutoClicker:Clean(button.MouseButton1Up:Connect(function()
    						if MobileThread then
    							task.cancel(MobileThread)
    							MobileThread = nil
    						end
    					end))
    				end

    				task.spawn(function()
    					local mobileUI = lplr.PlayerGui:WaitForChild('MobileUI', 20)
    					if not mobileUI or not AutoClicker.Enabled then return end
    					for _, v in mobileUI:GetChildren() do
    						hookButton(v)
    					end
    					AutoClicker:Clean(mobileUI.ChildAdded:Connect(hookButton))
    				end)
    			end
    		else
    			if Thread then
    				task.cancel(Thread)
    				Thread = nil
    			end
    			if MobileThread then
    				task.cancel(MobileThread)
    				MobileThread = nil
    			end
    		end
    	end,
    	Tooltip = 'Hold attack button to automatically click',
    })
    CPS = AutoClicker:CreateTwoSlider({
    	Name = 'CPS',
    	Min = 1,
    	Max = 9,
    	DefaultMin = 7,
    	DefaultMax = 7,
    })
    AutoClicker:CreateToggle({
    	Name = 'Place Blocks',
    	Default = true,
    	Function = function(callback)
    		if BlockCPS and BlockCPS.Object then
    			BlockCPS.Object.Visible = callback
    		end
    		if Wool and Wool.Object then
    			Wool.Object.Visible = callback
    		end
    	end,
    })
    Wool = AutoClicker:CreateToggle({
    	Name = 'Wool only',
    	Tooltip = 'Only places blocks when you are holding wool.',
    	Darker = true,
    })
    BlockCPS = AutoClicker:CreateTwoSlider({
    	Name = 'Block CPS',
    	Min = 1,
    	Max = 20,
    	DefaultMin = 12,
    	DefaultMax = 12,
    	Darker = true,
    })
    MobileCPS = AutoClicker:CreateTwoSlider({
    	Name = 'Click Rate',
    	Min = 1,
    	Max = 9,
    	DefaultMin = 7,
    	DefaultMax = 7,
    	Darker = true,
    })
    MobileDutyCycle = AutoClicker:CreateSlider({
    	Name = 'Duty Cycle',
    	Min = 1,
    	Max = 50,
    	Default = 24,
    	Suffix = '%',
    	Tooltip = 'Click hold time as % of each period — lower = quicker taps',
    	Darker = true,
    })
    if MobileCPS.Object then MobileCPS.Object.Visible = false end
    if MobileDutyCycle.Object then MobileDutyCycle.Object.Visible = false end
end)

run(function()
    local ShopQuickBuy
    local HoldDelay
    local CPS

    local holding = false
    local clickThread

    local function getShopId()
        if not entitylib.isAlive then return nil end
        local localPosition = entitylib.character.RootPart.Position
        local id
        for _, v in store.shop do
            if v.Shop and (v.RootPart.Position - localPosition).Magnitude <= 20 then
                id = v.Id
            end
        end
        return id
    end

    local function findShopCards(parent, results)
        results = results or {}
        for _, child in parent:GetChildren() do
            local itemType = child.Name:match('^(.+)_ShopItemCard$')
            if itemType then
                table.insert(results, {element = child, itemType = itemType})
            end
            if #child:GetChildren() > 0 then
                findShopCards(child, results)
            end
        end
        return results
    end

    local function getHoveredItem(touchPos)
        local screenPos = touchPos or (inputService:GetMouseLocation() - guiService:GetGuiInset())

        local guiObjects = lplr.PlayerGui:GetGuiObjectsAtPosition(screenPos.X, screenPos.Y)
        for _, v in guiObjects do
            local obj = v
            while obj and obj ~= lplr.PlayerGui do
                local itemType = obj.Name:match('^(.+)_ShopItemCard$')
                if itemType then
                    return itemType
                end
                obj = obj.Parent
            end
        end

        local cards = findShopCards(lplr.PlayerGui)
        local inset = guiService:GetGuiInset()
        for _, card in cards do
            local el = card.element
            local abs = el.AbsolutePosition
            local sz = el.AbsoluteSize
            local checkX = screenPos.X + inset.X
            local checkY = screenPos.Y + inset.Y
            if checkX >= abs.X and checkX <= abs.X + sz.X and checkY >= abs.Y and checkY <= abs.Y + sz.Y then
                return card.itemType
            end
        end
    end

    local function canBuy(item)
        if item.ignoredByKit and table.find(item.ignoredByKit, store.equippedKit or '') then return false end
        if item.lockedByForge or item.disabled then return false end
        if item.require and item.require.teamUpgrade then
            if (bedwars.Store:getState().Bedwars.teamUpgrades[item.require.teamUpgrade.upgradeId] or -1) < item.require.teamUpgrade.lowestTierIndex then
                return false
            end
        end
        local currency = getItem(item.currency)
        return (currency and currency.amount or 0) >= item.price
    end

    local function purchase(itemType, shopId)
        if bedwars.BedwarsShopController.alreadyPurchasedMap[itemType] ~= nil then return end
        if not bedwars.ItemMeta[itemType] or not bedwars.ItemMeta[itemType].block then return end

        local item = bedwars.Shop.getShopItem(itemType, lplr, {shopId = shopId})
        if not item or not canBuy(item) then return end

        bedwars.Client:Get('BedwarsPurchaseItem'):CallServerAsync({
            shopItem = item,
            shopId = shopId
        }):andThen(function(suc)
            if not suc then return end
            bedwars.SoundManager:playSound(bedwars.SoundList.BEDWARS_PURCHASE_ITEM)
            bedwars.Store:dispatch({
                type = 'BedwarsAddItemPurchased',
                itemType = itemType
            })
            if item.tiered then
                bedwars.BedwarsShopController.alreadyPurchasedMap[itemType] = true
            end
        end)
    end

    local function startClicking(itemType)
        if clickThread then
            task.cancel(clickThread)
        end
        clickThread = task.spawn(function()
            repeat
                local shopId = bedwars.AppController:isAppOpen('BedwarsItemShopApp') and store.shopLoaded and getShopId()
                if shopId then
                    purchase(itemType, shopId)
                end
                task.wait(1 / CPS.Value)
            until not holding
            clickThread = nil
        end)
    end

    ShopQuickBuy = vape.Categories.Combat:CreateModule({
        Name = 'Shop Clicker',
        Function = function(callback)
            if callback then
                ShopQuickBuy:Clean(inputService.InputBegan:Connect(function(input)
                    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
                    if not bedwars.AppController:isAppOpen('BedwarsItemShopApp') then return end

                    local touchPos = input.UserInputType == Enum.UserInputType.Touch and Vector2.new(input.Position.X, input.Position.Y) or nil
                    local itemType = getHoveredItem(touchPos)
                    if not itemType then return end

                    holding = true
                    task.delay(HoldDelay.Value, function()
                        if holding and getHoveredItem(touchPos) == itemType then
                            startClicking(itemType)
                        end
                    end)
                end))

                ShopQuickBuy:Clean(inputService.InputEnded:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                        holding = false
                    end
                end))

                ShopQuickBuy:Clean(inputService.InputChanged:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.Touch and input.UserInputState == Enum.UserInputState.Cancel then
                        holding = false
                    end
                end))
            else
                holding = false
                if clickThread then
                    task.cancel(clickThread)
                    clickThread = nil
                end
            end
        end,
        Tooltip = 'Hold on a shop item to rapidly buy it.'
    })
    HoldDelay = ShopQuickBuy:CreateSlider({
        Name = 'Hold Delay',
        Min = 0,
        Max = 1,
        Default = 0.15,
        Decimal = 20,
        Suffix = 'seconds'
    })
    CPS = ShopQuickBuy:CreateSlider({
        Name = 'CPS',
        Min = 1,
        Max = 20,
        Default = 20,
        Darker = true
    })
end)

run(function()
    local BowAssist
    local Targets
    local Sort
    local Shake
    local Speed
    local Angle
    local FOV
    local Blacklist
    local Mouse
    local ThirdPerson
    local Projectiles
    
    local function ease(t)
    	return t < 0.5 and 4 * t * t * t or 1 - math.pow(-2 * t + 2, 3) / 2
    end
    
    local function findAim(localcframe, predicted, fps, started, offset)
    	local prog, rng = ease(math.min((tick() - started) / (1 / (Speed.Value * 0.5)), 1)), Random.new()
    	local speed = Speed.Value * prog
    
    	return localcframe:Lerp(CFrame.lookAt(localcframe.p, predicted + Vector3.new((rng:NextNumber() - 0.5) * Shake.Value * fps, offset + ((rng:NextNumber() - 0.5) * Shake.Value * fps), (rng:NextNumber() - 0.5) * Shake.Value * fps)), speed * fps), speed
    end
    
    local launchHook
    local lasttarget, started = nil, 0
    local function getAttackData()
    	if not entitylib.isAlive then
    		return false
    	end
    	if Mouse.Enabled and not inputService:IsMouseButtonPressed(0) then
    		return false
    	end
    	if not store.hand.tool or not bedwars.ItemMeta[store.hand.tool.Name].projectileSource and store.hand.toolType ~= 'bow' then
    		return false
    	end
    	if Blacklist.Enabled and table.find(Projectiles.ListEnabled, store.hand.tool.Name == 'glue_trap' and 'gloop' or store.hand.tool.Name) then
    		return false
    	end
    
    	if (tick() - started) > 1 or not lasttarget or not lasttarget.Parent or not lasttarget.Humanoid or lasttarget.Humanoid.Health <= 0 then
    		local ent = entitylib.EntityMouse({
    			Origin = entitylib.character.RootPart.Position,
    			Range = FOV.Value,
    			Part = 'RootPart',
    			Wallcheck = Targets.Walls.Enabled,
    			Players = Targets.Players.Enabled,
    			NPCs = Targets.NPCs.Enabled,
    			Sort = sortmethods[Sort.Value],
    		})
    		if ent then
    			started = tick()
    		end
    		lasttarget = ent
    	end
    	return lasttarget
    end
    
    local rayCheck = RaycastParams.new()
    
    BowAssist = vape.Categories.Combat:CreateModule({
    	Name = 'Bow Assist',
    	Function = function(callback)
    		if callback then
    			local multi, predicted = 0, nil
    			local lastpredicted = 0
    			local lastent, found, update = nil, 0, 0
    
    			launchHook = bedwars.ProjectileLaunchHook:Add('BowAssist', 10, function(nextLaunch, ...)
    				local res = nextLaunch(...)
    				local projmeta = select(2, ...)
    				multi = projmeta and (projmeta.velocityMultiplier + 2) or 0
    				if projmeta and tick() - update < 0.1 and lastent and lastent.RootPart then
    					local meta = projmeta:getProjectileMeta()
    					local gravity = (meta.gravitationalAcceleration or 196.2) * projmeta.gravityMultiplier
    					local calc = prediction.SolveTrajectory(entitylib.character.RootPart.Position, (meta.launchVelocity or 100) * (1 - lplr:GetNetworkPing()), gravity, lastent.RootPart.Position, lastent.RootPart.Velocity, workspace.Gravity, entitylib.character.HipHeight, nil, rayCheck)
    					predicted = calc
    					lastpredicted = tick()
    				else
    					predicted = nil
    				end
    				return res
    			end)
    
    			BowAssist:Clean(runService.PostSimulation:Connect(function(dt)
    				local ent = getAttackData()
    				if ent then
    					local delta = (ent.RootPart.Position - entitylib.character.RootPart.Position)
    					local localfacing = entitylib.character.RootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
    					local angle = math.acos(localfacing:Dot((delta * Vector3.new(1, 0, 1)).Unit))
    					if angle >= (math.rad(Angle.Value) / 2) then
    						return
    					end
    					if ent ~= lastent then
    						found = tick()
    					end
    					lastent = ent
    					update = tick()
    					if tick() - lastpredicted < 0.1 then
    						targetinfo.Targets[ent] = tick() + 1
    						local cframe, speed = findAim(gameCamera.CFrame, predicted or ent.RootPart.Position, dt, found, multi + ((entitylib.character.RootPart.Position.Y - ent.RootPart.Position.Y) / 7))
    						if inputService.MouseEnabled and entitylib.character.Head.LocalTransparencyModifier == 1 then
    							gameCamera.CFrame = cframe
    						elseif ThirdPerson.Enabled and inputService.MouseEnabled then
    							local viewport = gameCamera:WorldToViewportPoint(predicted)
    							local pos = (Vector2.new(viewport.X, viewport.Y) - inputService:GetMouseLocation()) * (speed / 15)
    							mousemoverel(pos.X, pos.Y)
    						end
    					end
    				end
    			end))
    		else
    			if launchHook then
    				launchHook()
    				launchHook = nil
    			end
    		end
    	end,
        Tooltip = 'Smoothly aims your projectile trajectory to the target'
    })
    
    Targets = BowAssist:CreateTargets({
    	Players = true,
    	Walls = true,
    })
    local methods = {'Damage', 'Distance'}
    for i in sortmethods do
    	if not table.find(methods, i) then
    		table.insert(methods, i)
    	end
    end
    Sort = BowAssist:CreateDropdown({
    	Name = 'Target mode',
    	List = methods,
    	Default = 'Angle',
    })
    Speed = BowAssist:CreateSlider({
    	Name = 'Aim speed',
    	Min = 1,
    	Max = 20,
    	Default = 7,
    	Suffix = 'sp/s',
    	Tooltip = 'How fast you will aim per second',
    })
    Angle = BowAssist:CreateSlider({
    	Name = 'Max angle',
    	Min = 1,
    	Max = 360,
    	Default = 120,
    })
    Shake = BowAssist:CreateSlider({
    	Name = 'Shake',
    	Min = 1,
    	Max = 100,
    	Default = 5,
    	Tooltip = 'Jitters your screen, Simulating human aim',
    })
    FOV = BowAssist:CreateSlider({
    	Name = 'FOV',
    	Min = 1,
    	Max = 1000,
    	Default = 200,
    })
    Mouse = BowAssist:CreateToggle({
    	Name = 'Require mouse down',
    	Default = inputService.KeyboardEnabled,
    })
    ThirdPerson = BowAssist:CreateToggle({
    	Name = 'Use mouse aim',
    	Tooltip = 'Aims using the mouse if ur on third person',
    	Default = true,
    })
    Blacklist = BowAssist:CreateToggle({
    	Name = 'Use blacklist',
    	Default = true,
    	Function = function(callback)
    		if Projectiles then
    			Projectiles.Object.Visible = callback
    		end
    	end,
    	Tooltip = 'Doesn\'t bow-assist if your holding one of the blacklisted projectiles',
    })
    Projectiles = BowAssist:CreateTextList({
    	Name = 'Blacklisted',
    	Default = { 'fireball', 'telepearl', 'gloop' },
    	Darker = true,
    })
end)

run(function()
    if canDebug then
run(function()
	local BlockReach
	local BlockRange
	local BreakReach
	local BreakRange
	local SwordReach
	local SwordRange
	
	local old
	
	Reach = vape.Categories.Combat:CreateModule({
		Name = 'Reach',
		Tooltip = 'Allows you to place, attack, and break further',
		Function = function(callback)
			bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = callback and SwordReach.Enabled and SwordRange.Value + 2 or 14.4
			if callback then
				old = bedwars.BlockSelector.getMouseInfo
				bedwars.BlockSelector.getMouseInfo = function(...)
					local Self, Select, Args = ...
					if not Args then
						Args = {}
					end
					if Select == 0 then
						Args.range = BlockReach.Enabled and BlockRange.Value or 24
					elseif Select == 1 then
						Args.range = BreakReach.Enabled and BreakRange.Value or 18
					end
					return old(Self, Select, Args)
				end
			else
				bedwars.BlockSelector.getMouseInfo = old
				old = nil
			end
		end,
	})
	SwordReach = Reach:CreateToggle({
		Name = 'Sword Reach',
		Function = function(callback)
			bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = Reach.Enabled and callback and SwordRange.Value + 2 or 14.4
			pcall(function()
				SwordRange.Object.Visible = callback
			end)
		end,
		Default = true
	})
	SwordRange = Reach:CreateSlider({
		Name = 'Sword Range',
		Min = 1,
		Max = 18,
		Default = 18,
		Decimal = 5,
		Darker = true,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end,
		Function = function(val)
			bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE = Reach.Enabled and SwordReach.Enabled and val or 14.4
		end
	})
	BlockReach = Reach:CreateToggle({
		Name = 'Placement Reach',
		Function = function(callback)
			BlockRange.Object.Visible = callback
		end
	})
	BlockRange = Reach:CreateSlider({
		Name = 'Placement Range',
		Min = 1,
		Max = 60,
		Default = 18,
		Darker = true,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end,
		Visible = false
	})
	BreakReach = Reach:CreateToggle({
		Name = 'Break Reach',
		Function = function(callback)
			BreakRange.Object.Visible = callback
		end
	})
	BreakRange = Reach:CreateSlider({
		Name = 'Break Range',
		Min = 1,
		Max = 30,
		Default = 30,
		Decimal = 5,
		Darker = true,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end,
		Visible = false
	})
	Reach:CreateButton({
		Name = 'Reset to default reach',
		Tooltip = 'Resets every range back to default',
		Function = function()
			BreakRange:SetValue(18)
			BlockRange:SetValue(24)
			SwordRange:SetValue(12.4)
		end
	})
end)
    else
    	local Value
    	local rayParams = RaycastParams.new()
    	rayParams.RespectCanCollide = true
    
    	Reach = vape.Categories.Combat:CreateModule({
    		Name = 'Reach',
    		Function = function(callback)
    			if callback then
    				Reach:Clean(vapeEvents.CEAttacked.Event:Connect(function()
    					local doAttack
    					if not bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then
    						if
    							entitylib.isAlive
    							and store.hand.toolType == 'sword'
    							and bedwars.DaoController.chargingMaid == nil
    						then
    							local attackRange = Value.Value + 2
    							rayParams.FilterDescendantsInstances = { lplr.Character }
    
    							local unit = lplr:GetMouse().UnitRay
    							local localPos = entitylib.character.RootPart.Position
    							local rayRange = (attackRange or 14.4)
    							local ray = workspace:Raycast(unit.Origin, unit.Direction * 200, rayParams)
    							if ray and (localPos - ray.Instance.Position).Magnitude <= rayRange then
    								for _, ent in entitylib.List do
    									doAttack = ent.Targetable
    										and ray.Instance:IsDescendantOf(ent.Character)
    										and (localPos - ent.RootPart.Position).Magnitude <= rayRange
    									if doAttack then
    										break
    									end
    								end
    							end
    
    							local region = bedwars.SwordController:getTargetInRegion(attackRange or 3.8 * 3, 0)
    							if doAttack then
    								doAttack = region
    							end
    							if doAttack then
    								local selfpos = entitylib.character.RootPart.Position
    								local delta = (doAttack.RootPart.Position - selfpos)
    								local dir = CFrame.lookAt(selfpos, doAttack.RootPart.Position).LookVector
    								local pos = selfpos + dir * math.max(delta.Magnitude - 14.4, 0)
    
    								bedwars.Client:Get('SwordHit'):SendToServer({
    									weapon = store.hand.tool,
    									chargedAttack = {chargeRatio = 0},
    									entityInstance = doAttack.Character,
    									validate = {
    										raycast = {
    											cameraPosition = {value = pos},
    											cursorDirection = {value = dir},
    										},
    										targetPosition = {value = doAttack.RootPart.Position},
    										selfPosition = {value = pos},
    									},
    								})
    							end
    						end
    					end
    				end))
    			end
    		end,
    	})
    	Value = Reach:CreateSlider({
    		Name = 'Range',
    		Min = 0,
    		Max = 18,
    		Default = 18,
    		Suffix = function(val)
    			return val == 1 and 'stud' or 'studs'
    		end,
    	})
    end
end)

run(function()
    local Sprint
    local old
    
    Sprint = vape.Categories.Combat:CreateModule({
        Name = 'Sprint',
        Function = function(callback)
            if callback then
                if inputService.TouchEnabled then 
                    pcall(function() 
                        lplr.PlayerGui.MobileUI['4'].Visible = false 
                    end) 
                end
                old = bedwars.SprintController.stopSprinting
                bedwars.SprintController.stopSprinting = function(...)
                    local call = old(...)
                    bedwars.SprintController:startSprinting()
                    return call
                end
                Sprint:Clean(entitylib.Events.LocalAdded:Connect(function() 
                    task.delay(0.1, function() 
                        bedwars.SprintController:stopSprinting() 
                    end) 
                end))
                bedwars.SprintController:stopSprinting()
            else
                if inputService.TouchEnabled then 
                    pcall(function() 
                        lplr.PlayerGui.MobileUI['4'].Visible = true 
                    end) 
                end
                bedwars.SprintController.stopSprinting = old
                bedwars.SprintController:stopSprinting()
            end
        end,
        Tooltip = 'Sets your sprinting to true.'
    })
end)

run(function()
    local TriggerBot
    local CPS
    local rayParams = RaycastParams.new()
    
    TriggerBot = vape.Categories.Combat:CreateModule({
        Name = 'Trigger Bot',
        Function = function(callback)
            if callback then
                repeat
                    local doAttack
                    if not bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then
                        if entitylib.isAlive and store.hand.toolType == 'sword' and bedwars.DaoController.chargingMaid == nil then
                            local attackRange = bedwars.ItemMeta[store.hand.tool.Name].sword.attackRange
                            rayParams.FilterDescendantsInstances = {lplr.Character}
    
                            local unit = lplr:GetMouse().UnitRay
                            local localPos = entitylib.character.RootPart.Position
                            local rayRange = (attackRange or 14.4)
                            local ray = bedwars.QueryUtil:raycast(unit.Origin, unit.Direction * 200, rayParams)
                            if ray and (localPos - ray.Instance.Position).Magnitude <= rayRange then
                                local limit = (attackRange)
                                for _, ent in entitylib.List do
                                    doAttack = ent.Targetable and ray.Instance:IsDescendantOf(ent.Character) and (localPos - ent.RootPart.Position).Magnitude <= rayRange
                                    if doAttack then
                                        break
                                    end
                                end
                            end
    
                            doAttack = doAttack or bedwars.SwordController:getTargetInRegion(attackRange or 3.8 * 3, 0)
                            if doAttack then
                                bedwars.SwordController:swingSwordAtMouse()
                            end
                        end
                    end
    
                    task.wait(doAttack and 1 / CPS.GetRandomValue() or 0.016)
                until not TriggerBot.Enabled
            end
        end,
        Tooltip = 'Automatically swings when hovering over a entity'
    })
    CPS = TriggerBot:CreateTwoSlider({
        Name = 'CPS',
        Min = 1,
        Max = 9,
        DefaultMin = 7,
        DefaultMax = 7
    })
end)

run(function()
    local Velocity
    local Horizontal
    local Vertical
    local Chance
    local TargetCheck
    local rand, old = Random.new()
    
    Velocity = vape.Categories.Combat:CreateModule({
        Name = 'Velocity',
        Function = function(callback)
            if callback then
                old = bedwars.KnockbackUtil.applyKnockback
                bedwars.KnockbackUtil.applyKnockback = function(root, mass, dir, knockback, ...)
                    if rand:NextNumber(0, 100) > Chance.Value then return end
                    local check = (not TargetCheck.Enabled) or entitylib.EntityPosition({
                        Range = 50,
                        Part = 'RootPart',
                        Players = true
                    })
    
                    if check then
                        knockback = knockback or {}
                        if Horizontal.Value == 0 and Vertical.Value == 0 then return end
                        knockback.horizontal = (knockback.horizontal or 1) * (Horizontal.Value / 100)
                        knockback.vertical = (knockback.vertical or 1) * (Vertical.Value / 100)
                    end
                    
                    return old(root, mass, dir, knockback, ...)
                end
            else
                bedwars.KnockbackUtil.applyKnockback = old
            end
        end,
        Tooltip = 'Reduces knockback taken'
    })
    Horizontal = Velocity:CreateSlider({
        Name = 'Horizontal',
        Min = 0,
        Max = 100,
        Default = 0,
        Suffix = '%'
    })
    Vertical = Velocity:CreateSlider({
        Name = 'Vertical',
        Min = 0,
        Max = 100,
        Default = 0,
        Suffix = '%'
    })
    Chance = Velocity:CreateSlider({
        Name = 'Chance',
        Min = 0,
        Max = 100,
        Default = 100,
        Suffix = '%'
    })
    TargetCheck = Velocity:CreateToggle({Name = 'Only when targeting'})
end)

--[[
    Blatant
]]

run(function()
    local AutoKaida
    local Targets
    local SwingRange
    local AttackRange
    local Sort
    local Limit
    local Swing
    local Mouse
    local GUI
    local Perfect
    local Distance
    
    local function getAttackData()
        local claw = (Limit.Enabled and store.hand.tool and store.hand) or not Limit.Enabled and getItem('summoner_claw', nil, true)
        if claw and claw.tool.Name:find('summoner_claw') then
            if Mouse.Enabled and not inputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                return false
            end
            if GUI.Enabled and bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then
                return false
            end
            return claw
        end
        return false
    end
    
    AutoKaida = vape.Categories.Blatant:CreateModule({
        Name = 'Auto Kaida',
        Function = function(callback)
            if callback then
                repeat
                    if entitylib.isAlive and (workspace:GetServerTimeNow() - bedwars.SummonerClawHandController.lastAttackTime) > bedwars.SummonerKitBalance.CLAW_COOLDOWN then
                        local claw = getAttackData()
                        if claw then
                            local ent = entitylib.EntityPosition({
                                Range = SwingRange.Value,
                                Wallcheck = Targets.Walls.Enabled or nil,
                                Part = 'RootPart',
                                Players = Targets.Players.Enabled,
                                NPCs = Targets.NPCs.Enabled,
                                Sort = sortmethods[Sort.Value]
                            })
                            if ent then
                                local selfpos = entitylib.character.RootPart.Position
                                local dir = CFrame.lookAt(selfpos, ent.RootPart.Position).LookVector
                                local delta = (ent.RootPart.Position - selfpos)
    
                                if Perfect.Enabled and (selfpos - ent.RootPart.Position).Magnitude <= Distance.Value then
                                    if bedwars.AbilityController:canUseAbility('summoner_start_charging') and bedwars.AbilityController:canUseAbility('summoner_finish_charging') then
                                        bedwars.AbilityController:useAbility('summoner_start_charging')
                                        task.wait(0.5)
                                        bedwars.AbilityController:useAbility('summoner_finish_charging')
                                        if not Swing.Enabled then
                                            continue
                                        end
                                    end
                                end
    
                                if not Swing.Enabled then
                                    local active = false
                                    for _, v in workspace:QueryDescendants('#Summoner_SummonCircle') do
                                        local pivot = v:FindFirstChild('Pivot')
                                        if pivot and math.floor(pivot.Position.X) == math.floor(entitylib.character.RootPart.Position.X) and math.floor(pivot.Position.Z) == math.floor(entitylib.character.RootPart.Position.Z) then
                                            active = true
                                            break
                                        end
                                    end
                                    if active then
                                        task.wait()
                                        continue
                                    end
                                end
    
                                if (selfpos - ent.RootPart.Position).Magnitude <= AttackRange.Value then
                                    bedwars.Client:Get('SummonerClawAttackRequest'):SendToServer({
                                        position = selfpos + dir * math.max(delta.Magnitude - 16.399, 0),
                                        direction = dir,
                                        clientTime = workspace:GetServerTimeNow()
                                    })
                                end
                                bedwars.SummonerClawHandController.lastAttackTime = workspace:GetServerTimeNow()
                                bedwars.SummonerClawController:clawAttack(lplr, selfpos, dir, claw.tool.Name)
                            end
                        end
                    end
                    task.wait(0.1)
                until not AutoKaida.Enabled
            end
        end
    })
    
    Targets = AutoKaida:CreateTargets({Players = true})
    SwingRange = AutoKaida:CreateSlider({
        Name = 'Swing Range',
        Min = 1,
        Max = 32,
        Default = 32,
        Suffix = function(val)
            return val <= 1 and 'stud' or 'studs'
        end
    })
    AttackRange = AutoKaida:CreateSlider({
        Name = 'Attack Range',
        Min = 1,
        Max = 32,
        Default = 32,
        Suffix = function(val)
            return val <= 1 and 'stud' or 'studs'
        end
    })
    local methods = {'Damage', 'Distance'}
    for i in sortmethods do
        if not table.find(methods, i) then
            table.insert(methods, i)
        end
    end
    Sort = AutoKaida:CreateDropdown({
        Name = 'Target mode',
        List = methods,
        Default = methods[2]
    })
    Mouse = AutoKaida:CreateToggle({Name = 'Require mouse down'})
    GUI = AutoKaida:CreateToggle({Name = 'GUI check'})
    Swing = AutoKaida:CreateToggle({
        Name = 'Swing during ability',
        Default = true,
        Tooltip = 'Continue claw attacks while charging ability'
    })
    Limit = AutoKaida:CreateToggle({Name = 'Limit to items'})
    Perfect = AutoKaida:CreateToggle({
        Name = 'Perfect ability',
        Function = function(callback)
            pcall(function()
                Distance.Object.Visible = callback
            end)
        end
    })
    Distance = AutoKaida:CreateSlider({
        Name = 'Distance',
    	Min = 3,
    	Max = 15,
    	Default = 6,
    	Visible = false,
    	Suffix = function(val)
    		return val <= 1 and 'stud' or 'studs'
    	end,
        Darker = true
    })
end)

run(function()
    local DamageBoost
    local stack
    
    DamageBoost = vape.Categories.Blatant:CreateModule({
    	Name = 'Damage Boost',
    	Function = function(callback)
    		if callback then
    			DamageBoost:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
    				if entitylib.isAlive and tick() > (stack or 0) and damageTable.entityInstance == lplr.Character and not LongJump.Enabled then
    					local horizontal = (damageTable.knockbackMultiplier and damageTable.knockbackMultiplier.horizontal or 0)
    					knockbackSpeed = bedwars.KnockbackUtil.calculateKnockbackVelocity(Vector3.one, 1, {
    						vertical = 0,
    						horizontal = horizontal,
    					}).Magnitude * (0.9 + lplr:GetNetworkPing())
                        stack = tick() + (knockbackSpeed / 45)
                        knockbackBoost = tick() + (horizontal / 3.5)
    				end
    			end))
    		end
    	end,
        Tooltip = 'Makes you go slightly faster when damaged'
    })
end)

run(function()
    local Value
    local VerticalValue
    local WallCheck
    local PopBalloons
    local TP
    local rayCheck = RaycastParams.new()
    rayCheck.RespectCanCollide = true
    local up, down, old = 0, 0
    
    Fly = vape.Categories.Blatant:CreateModule({
        Name = 'Fly',
        Function = function(callback)
            frictionTable.Fly = callback or nil
            updateVelocity()
            if callback then
                up, down, old = 0, 0, bedwars.BalloonController.deflateBalloon
                bedwars.BalloonController.deflateBalloon = function() end
                local tpTick, tpToggle, oldy = tick(), true
    
                if lplr.Character and (lplr.Character:GetAttribute('InflatedBalloons') or 0) == 0 and getItem('balloon') then
                    bedwars.BalloonController:inflateBalloon()
                end
                Fly:Clean(vapeEvents.AttributeChanged.Event:Connect(function(changed)
                    if changed == 'InflatedBalloons' and (lplr.Character:GetAttribute('InflatedBalloons') or 0) == 0 and getItem('balloon') then
                        bedwars.BalloonController:inflateBalloon()
                    end
                end))
                Fly:Clean(runService.PreSimulation:Connect(function(dt)
                    if entitylib.isAlive and not InfiniteFly.Enabled and isnetworkowner(entitylib.character.RootPart) then
                        local flyAllowed = (lplr.Character:GetAttribute('InflatedBalloons') and lplr.Character:GetAttribute('InflatedBalloons') > 0) or store.matchState == 2
                        local mass = (0.9 + (flyAllowed and 6 or 0) * (tick() % 0.4 < 0.2 and -1 or 1)) + ((up + down) * VerticalValue.Value)
                        local root, moveDirection = entitylib.character.RootPart, entitylib.character.Humanoid.MoveDirection
                        local velo = getSpeed()
                        local destination = (moveDirection * math.max(Value.Value - velo, 0) * dt)
                        rayCheck.FilterDescendantsInstances = {lplr.Character, gameCamera, AntiFallPart}
                        rayCheck.CollisionGroup = root.CollisionGroup
    
                        if WallCheck.Enabled then
                            local ray = workspace:Raycast(root.Position, destination, rayCheck)
                            if ray then
                                destination = ((ray.Position + ray.Normal) - root.Position)
                            end
                        end
    
                        if not flyAllowed then
                            if tpToggle then
                                local airleft = (tick() - entitylib.character.AirTime)
                                if airleft > 2 then
                                    if not oldy then
                                        local ray = workspace:Raycast(root.Position, Vector3.new(0, -1000, 0), rayCheck)
                                        if ray and TP.Enabled then
                                            tpToggle = false
                                            oldy = root.Position.Y
                                            tpTick = tick() + 0.11
                                            root.CFrame = CFrame.lookAlong(Vector3.new(root.Position.X, ray.Position.Y + entitylib.character.HipHeight, root.Position.Z), root.CFrame.LookVector)
                                        end
                                    end
                                end
                            else
                                if oldy then
                                    if tpTick < tick() then
                                        local newpos = Vector3.new(root.Position.X, oldy, root.Position.Z)
                                        root.CFrame = CFrame.lookAlong(newpos, root.CFrame.LookVector)
                                        tpToggle = true
                                        oldy = nil
                                    else
                                        mass = 0
                                    end
                                end
                            end
                        end
    
                        root.CFrame = root.CFrame + destination
                        root.AssemblyLinearVelocity = (moveDirection * velo) + Vector3.new(0, mass, 0)
                    end
                end))
                Fly:Clean(inputService.InputBegan:Connect(function(input)
                    if not inputService:GetFocusedTextBox() then
                        if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
                            up = 1
                        elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
                            down = -1
                        end
                    end
                end))
                Fly:Clean(inputService.InputEnded:Connect(function(input)
                    if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
                        up = 0
                    elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
                        down = 0
                    end
                end))
                if inputService.TouchEnabled then
                    pcall(function()
                        local jumpButton = lplr.PlayerGui.TouchGui.TouchControlFrame.JumpButton
                        Fly:Clean(jumpButton:GetPropertyChangedSignal('ImageRectOffset'):Connect(function()
                            up = jumpButton.ImageRectOffset.X == 146 and 1 or 0
                        end))
                    end)
                end
            else
                bedwars.BalloonController.deflateBalloon = old
                if PopBalloons.Enabled and entitylib.isAlive and (lplr.Character:GetAttribute('InflatedBalloons') or 0) > 0 then
                    for _ = 1, 3 do
                        bedwars.BalloonController:deflateBalloon()
                    end
                end
            end
        end,
        ExtraText = function()
            return 'Heatseeker'
        end,
        Tooltip = 'Makes you go zoom.'
    })
    Value = Fly:CreateSlider({
        Name = 'Speed',
        Min = 1,
        Max = 23,
        Default = 23,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    VerticalValue = Fly:CreateSlider({
        Name = 'Vertical Speed',
        Min = 1,
        Max = 150,
        Default = 50,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    WallCheck = Fly:CreateToggle({
        Name = 'Wall Check',
        Default = true
    })
    PopBalloons = Fly:CreateToggle({
        Name = 'Pop Balloons',
        Default = true
    })
    TP = Fly:CreateToggle({
        Name = 'TP Down',
        Default = true
    })
end)

run(function()
    local Mode
    local Expand
    local objects, set = {}
    
    local function createHitbox(ent)
        if ent.Targetable and ent.Player then
            local hitbox = Instance.new('Part')
            hitbox.Size = Vector3.new(3, 6, 3) + Vector3.one * (Expand.Value / 5)
            hitbox.Position = ent.RootPart.Position
            hitbox.CanCollide = false
            hitbox.Massless = true
            hitbox.Transparency = 1
            hitbox.Parent = ent.Character
            local weld = Instance.new('Motor6D')
            weld.Part0 = hitbox
            weld.Part1 = ent.RootPart
            weld.Parent = hitbox
            objects[ent] = hitbox
        end
    end
    
    HitBoxes = vape.Categories.Blatant:CreateModule({
        Name = 'Hit Boxes',
        Function = function(callback)
            if callback then
                if Mode.Value == 'Sword' then
                    debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, (Expand.Value / 3))
                    set = true
                else
                    HitBoxes:Clean(entitylib.Events.EntityAdded:Connect(createHitbox))
                    HitBoxes:Clean(entitylib.Events.EntityRemoving:Connect(function(ent)
                        if objects[ent] then
                            objects[ent]:Destroy()
                            objects[ent] = nil
                        end
                    end))
                    for _, ent in entitylib.List do
                        createHitbox(ent)
                    end
                end
            else
                if set then
                    debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, 3.8)
                    set = nil
                end
                for _, part in objects do
                    part:Destroy()
                end
                table.clear(objects)
            end
        end,
        Tooltip = 'Expands attack hitbox'
    })
    Mode = HitBoxes:CreateDropdown({
        Name = 'Mode',
        List = {'Sword', 'Player'},
        Function = function()
            if HitBoxes.Enabled then
                HitBoxes:Toggle()
                HitBoxes:Toggle()
            end
        end,
        Tooltip = 'Sword - Increases the range around you to hit entities\nPlayer - Increases the players hitbox'
    })
    Expand = HitBoxes:CreateSlider({
        Name = 'Expand amount',
        Min = 0,
        Max = 14.4,
        Default = 14.4,
        Decimal = 10,
        Function = function(val)
            if HitBoxes.Enabled then
                if Mode.Value == 'Sword' then
                    debug.setconstant(bedwars.SwordController.swingSwordInRegion, 6, (val / 3))
                else
                    for _, part in objects do
                        part.Size = Vector3.new(3, 6, 3) + Vector3.one * (val / 5)
                    end
                end
            end
        end,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
end)


run(function()
    vape.Categories.Blatant:CreateModule({
        Name = 'Keep Sprint',
        Function = function(callback)
            debug.setconstant(bedwars.SprintController.startSprinting, 5, callback and 'blockSprinting' or 'blockSprint')
            bedwars.SprintController:stopSprinting()
        end,
        Tooltip = 'Lets you sprint with a speed potion.'
    })
end)

run(function()
    local Killaura
    local Continue
    local Targets
    local Mode
    local Sort
    local SwingRange
    local AttackRange
    local AirChance
    local SwingTime
    local Hitreg
    local Dynamic
    local Sync = {}
    local Attackable
    local AngleSlider
    local MaxTargets
    local Mouse
    local Swing
    local GUI
    local BoxRender
    local BoxSwingColor
    local BoxAttackColor
    local ParticleTexture
    local ParticleColor1
    local ParticleColor2
    local ParticleSize
    local Face
    local Animation
    local AnimationMode
    local AnimationSpeed
    local AnimationTween
    local Limit
    local LegitAura
    local Particles, Boxes, Rings = {}, {}, {}
    local anims, AnimDelay, AnimTween, armC0 = vape.Libraries.auraanims, tick()
    local AttackRemote = {FireServer = function(self, ...) end}
    local SwingMissRemote = {FireServer = function(self, ...) end}
    local projectileRemote = {InvokeServer = function(self, ...) end}
    task.spawn(function()
        AttackRemote = bedwars.Client:Get(remotes.AttackEntity).instance
    end)
    task.spawn(function()
        SwingMissRemote = bedwars.Client:Get('SwordSwingMiss').instance
    end)
    task.spawn(function()
    	projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
    end)

    local FastHits
    local Legit
    local FireRate
    local Whitelist
    local FireRates = {}

    local function getAmmo(check)
    	for _, item in store.inventory.inventory.items do
    		if check.ammoItemTypes and table.find(check.ammoItemTypes, item.itemType) then
    			return item.itemType
    		end
    	end
    	return nil
    end
    local function getProjectiles()
    	local items = {}
    	for _, item in store.inventory.inventory.items do
    		local proj = bedwars.ItemMeta[item.itemType].projectileSource
    		local ammo = proj and getAmmo(proj)
    		if ammo and not proj.maxStrengthChargeSec and (table.find(Whitelist.ListEnabled, ammo) or table.find(Whitelist.ListEnabled, item.itemType)) then
    			table.insert(items, {
    				item,
    				ammo,
    				proj.projectileType(ammo),
    				proj,
    			})
    		end
    	end
    	return items
    end
    local function getAttackData()
        if Mouse.Enabled then
            if not inputService:IsMouseButtonPressed(0) then return false end
        end
    
        if Attackable.Enabled then
            if not entitylib.isAlive then return false end
            if (lplr.Character:GetAttribute('StunnedUntilTime') or 0) > workspace:GetServerTimeNow() then return false end
            if lplr.Character:FindFirstChild('elk') then return false end
            if bedwars.StatusEffectUtil:isActive(lplr.Character, 'frozen') then return false end
        end
    
        if GUI.Enabled then
            if bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then return false end
        end
    
        local sword = Limit.Enabled and store.hand or store.tools.sword
        if not sword or not sword.tool then return false end
    
        local meta = bedwars.ItemMeta[sword.tool.Name]
        if Limit.Enabled then
            if store.hand.toolType ~= 'sword' or bedwars.DaoController.chargingMaid then return false end
        end
    
        if LegitAura.Enabled then
            if (tick() - bedwars.SwordController.lastSwing) > 0.2 then return false end
        end
    
        return sword, meta
    end
    
    local part = Instance.new('Part')
    part.Anchored = true
    part.CanCollide = false
    part.Size = Vector3.one
    part.Parent = workspace
    vape:Clean(part)
    
    Killaura = vape.Categories.Blatant:CreateModule({
        Name = 'Killaura',
        Function = function(callback)
            if callback then
                if Animation.Enabled then
                    local fake = {
                        Controllers = {
                            ViewmodelController = {
                                isVisible = function()
                                    return not Attacking
                                end,
                                playAnimation = function(...)
                                    if not Attacking then
                                        bedwars.ViewmodelController:playAnimation(select(2, ...))
                                    end
                                end
                            }
                        }
                    }
                    debug.setupvalue(bedwars.SwordController.playSwordEffect, 7, fake)
                    debug.setupvalue(bedwars.ScytheController.playLocalAnimation, 3, fake)
    
                    task.spawn(function()
                        local started = false
                        repeat
                            if Attacking then
                                if not armC0 then
                                    armC0 = gameCamera.Viewmodel.RightHand.RightWrist.C0
                                end
                                local first = not started
                                started = true
    
                                if AnimationMode.Value == 'Random' then
                                    anims.Random = {{CFrame = CFrame.Angles(math.rad(math.random(1, 360)), math.rad(math.random(1, 360)), math.rad(math.random(1, 360))), Time = 0.12}}
                                end
    
                                for _, v in anims[AnimationMode.Value] do
                                    AnimTween = tweenService:Create(gameCamera.Viewmodel.RightHand.RightWrist, TweenInfo.new(first and (AnimationTween.Enabled and 0.001 or 0.1) or v.Time / AnimationSpeed.Value, Enum.EasingStyle.Linear), {
                                        C0 = armC0 * v.CFrame
                                    })
                                    AnimTween:Play()
                                    AnimTween.Completed:Wait()
                                    first = false
                                    if (not Killaura.Enabled) or (not Attacking) then break end
                                end
                            elseif started then
                                started = false
                                AnimTween = tweenService:Create(gameCamera.Viewmodel.RightHand.RightWrist, TweenInfo.new(AnimationTween.Enabled and 0.001 or 0.3, Enum.EasingStyle.Exponential), {
                                    C0 = armC0
                                })
                                AnimTween:Play()
                            end
    
                            if not started then
                                task.wait()
                            end
                        until (not Killaura.Enabled) or (not Animation.Enabled)
                    end)
                end
    
                local swingCooldown, switchCooldown, lastSwing, targetIndex = tick(), tick(), 0, 0
                local lastShot, projectileIndex = tick(), 0
                local lastHit = 0
                local lastRealSend = 0
                repeat
                    local attacked, sword, meta = {}, getAttackData()
                    Attacking = false
                    store.KillauraTarget = nil
                    if sword then
                        local plrs = entitylib.AllPosition({
                            Range = SwingRange.Value,
                            Wallcheck = Targets.Walls.Enabled or nil,
                            Part = 'RootPart',
                            Players = Targets.Players.Enabled,
                            NPCs = Targets.NPCs.Enabled,
                            Limit = Mode.Value == 'Single' and 1 or MaxTargets.Value,
                            Sort = sortmethods[Sort.Value]
                        })
    
                        if #plrs > 0 then
                            switchItem(sword.tool, 0)
                            local selfpos = entitylib.character.RootPart.Position
                            local localfacing = entitylib.character.RootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
                            if tick() > switchCooldown and Mode.Value == 'Switch' then
    							switchCooldown = tick() + 0.7
    							targetIndex = targetIndex + 1
    						end
                            if not plrs[targetIndex] then
                                targetIndex = 1
                            end
                            for i, v in plrs do
                                if Mode.Value == 'Switch' and i ~= targetIndex then
    								continue
    							end
                                local delta = (v.RootPart.Position - selfpos)
                                local angle = math.acos(localfacing:Dot((delta * Vector3.new(1, 0, 1)).Unit))
                                if angle > (math.rad(AngleSlider.Value) / 2) then continue end
    
                                table.insert(attacked, {
                                    Entity = v,
                                    Check = delta.Magnitude > AttackRange.Value and BoxSwingColor or BoxAttackColor
                                })
                                targetinfo.Targets[v] = tick() + 1
    
                                if not Attacking then
                                    Attacking = true
                                    store.KillauraTarget = v
                                    if not Swing.Enabled and AnimDelay < tick() and not LegitAura.Enabled then
                                        AnimDelay = tick() + math.max(SwingTime.Value, 0.11)
                                        lastSwing = tick()
                                        bedwars.SwordController:playSwordEffect(meta, false)
                                        if meta.displayName:find(' Scythe') then
                                            bedwars.ScytheController:playLocalAnimation()
                                        end
    
                                        if vape.ThreadFix then
                                            setthreadidentity(8)
                                        end
                                    end
                                end
    
                                local minHitInterval = (meta.sword.attackSpeed or 0.33) - 0.009
                                print(string.format("[KA Debug] sword: %s | attackSpeed: %s | minHitInterval: %.4f", tostring(sword.itemType), tostring(meta.sword.attackSpeed), minHitInterval))
                                local current = tick()
                                if delta.Magnitude > AttackRange.Value then
                                    if (current - lastHit) >= minHitInterval then
                                        lastHit = lastHit + minHitInterval
                                        if current - lastHit > minHitInterval then lastHit = current end
                                        pcall(SwingMissRemote.FireServer, SwingMissRemote, {chargeRatio = 0, weapon = sword.tool})
                                    end
                                    continue
                                end

                                local actualRoot = v.Character.PrimaryPart
                                if actualRoot and (not Sync.Enabled or (current - swingCooldown >= SwingTime.Value)) and (v.Humanoid.FloorMaterial ~= Enum.Material.Air or math.random(1, 100) < AirChance.Value) then
                                    if (current - lastHit) >= minHitInterval and (current - lastRealSend) >= minHitInterval then
                                        lastHit = lastHit + minHitInterval
                                        if current - lastHit > minHitInterval then lastHit = current end
                                        lastRealSend = current

                                        local dir = CFrame.lookAt(selfpos, actualRoot.Position).LookVector
                                        local pos = selfpos + dir * math.max(delta.Magnitude - 14.4, 0)
                                        bedwars.SwordController.lastAttack = workspace:GetServerTimeNow()
                                        store.attackReach = math.floor(delta.Magnitude * 100) / 100
                                        store.attackReachUpdate = tick() + 1
                                        swingCooldown = tick()

                                        AttackRemote:FireServer({
                                            weapon = sword.tool,
                                            chargedAttack = {chargeRatio = 0},
                                            entityInstance = v.Character,
                                            validate = {
                                                raycast = {
                                                    cameraPosition = {value = pos},
                                                    cursorDirection = {value = dir}
                                                },
                                                targetPosition = {value = actualRoot.Position},
                                                selfPosition = {value = pos}
                                            }
                                        })
    
                                        if FastHits.Enabled and tick() > lastShot and not entitylib.Wallcheck(entitylib.character.RootPart.Position, actualRoot.Position, {gameCamera, lplr.Character, v.Character}) then
                                            local projectiles = getProjectiles()
                                            if #projectiles > 0 then
                                                projectileIndex = projectileIndex + 1
                                                if not projectiles[projectileIndex] then
                                                    projectileIndex = 1
                                                end
                                                
                                                local item, ammo, projectile, itemMeta = unpack(projectiles[projectileIndex])
                                                if tick() > (FireRates[item.itemType] or 0) and not (store.hand.tool and store.hand.tool.Name == 'telepearl') then
                                                    local projmeta = bedwars.ProjectileMeta[projectile]
                                                    local projSpeed = projmeta.launchVelocity
                                                    local gravity = projmeta.gravitationalAcceleration or 196.2
                                                    local oldhotbar, oldtool = store.inventory.hotbarSlot, store.hand.tool
                                                    local hotbar = getHotbar(item.tool)

                                                    if hotbar then
                                                        switchItem(item.tool)
                                                        if Legit.Enabled then hotbarSwitch(hotbar) end
                                                    end

                                                    local calc = prediction.SolveTrajectory(selfpos, projSpeed, gravity, v.RootPart.Position, v.RootPart.Velocity, workspace.Gravity, v.HipHeight, v.Jumping and 42.6 or nil, nil, nil, lplr:GetNetworkPing())
                                                    if calc then
                                                        local sdir, id = CFrame.lookAt(selfpos, calc).LookVector, httpService:GenerateGUID(true)
                                                        local shootPosition = (CFrame.new(selfpos, calc) * CFrame.new(Vector3.new(-bedwars.BowConstantsTable.RelX, -bedwars.BowConstantsTable.RelY, -bedwars.BowConstantsTable.RelZ))).Position

                                                        bedwars.ProjectileController:createLocalProjectile(itemMeta, ammo, projectile, shootPosition, id, sdir * projSpeed, {drawDurationSeconds = 1})
                                                        local _, res = pcall(function() return projectileRemote:InvokeServer(
                                                            item.tool,
                                                            ammo,
                                                            projectile,
                                                            shootPosition,
                                                            selfpos,
                                                            sdir * projSpeed,
                                                            id,
                                                            {
                                                                drawDurationSeconds = 1,
                                                                shotId = httpService:GenerateGUID(false)
                                                            },
                                                            workspace:GetServerTimeNow() - 0.045
                                                        ) end)
                                                        if res then
                                                            pcall(function()
                                                                res.Parent = replicatedStorage
                                                            end)
                                                            FireRates[item.itemType] = tick() + itemMeta.fireDelaySec
                                                            local shoot = itemMeta.launchSound
                                                            shoot = shoot and shoot[math.random(1, #shoot)] or nil
                                                            if shoot then
                                                                bedwars.SoundManager:playSound(shoot)
                                                            end
                                                        end
                                                        lastShot = tick() + (lplr:GetNetworkPing() + FireRate.Value)
                                                    end
                                                    if oldtool then switchItem(oldtool) end
                                                    task.spawn(function()
                                                        if Legit.Enabled then hotbarSwitch(oldhotbar) end
                                                    end)
                                                end
                                            end
                                        end

                                        if Mode.Value ~= 'Multi' then
                                            break
                                        end
                                    end
                                end
                            end
                        else
                            if (tick() - lastSwing) < Continue:GetRandomValue() and not Swing.Enabled and not LegitAura.Enabled and AnimDelay < tick() then
                                AnimDelay = tick() + math.max(SwingTime.Value, 0.11)
                                if vape.ThreadFix then
    								setthreadidentity(8)
    							end
                                
    							pcall(function()
    								bedwars.SwordController:playSwordEffect(meta, false)
                                    if meta.displayName:find(' Scythe') then
                                        bedwars.ScytheController:playLocalAnimation()
                                    end
    							end)
                            end
                        end
                    end
    
                    for i, v in Boxes do
                        v.Adornee = BoxRender.Value == 'Box' and attacked[i] and attacked[i].Entity.RootPart or nil
                        if v.Adornee then
                            v.Color3 = Color3.fromHSV(attacked[i].Check.Hue, attacked[i].Check.Sat, attacked[i].Check.Value)
                            v.Transparency = 1 - attacked[i].Check.Opacity
                        end
                    end
    
                    for i, v in Rings do
                        local root = BoxRender.Value == 'Ring' and attacked[i] and attacked[i].Entity.RootPart or nil
                        v.Transparency = 1
                        v.Parent = root and workspace or replicatedStorage
                        v.Position = root and Vector3.new(root.Position.X, (root.Position.Y - 1) + (v.Size.Y / 2), root.Position.Z) or Vector3.zero
                        if root then
                            for i2 = 1, 4 do
                                v[tostring(i2)].Color3 = Color3.fromHSV(attacked[i].Check.Hue, attacked[i].Check.Sat, attacked[i].Check.Value)
                                v[tostring(i2)].Transparency = 1 - attacked[i].Check.Opacity
                            end
                        end
                    end
    
                    for i, v in Particles do
                        v.Position = attacked[i] and attacked[i].Entity.RootPart.Position or Vector3.new(9e9, 9e9, 9e9)
                        v.Parent = attacked[i] and gameCamera or nil
                    end
    
                    if Face.Enabled and attacked[1] then
                        local vec = attacked[1].Entity.RootPart.Position * Vector3.new(1, 0, 1)
                        entitylib.character.RootPart.CFrame = CFrame.lookAt(entitylib.character.RootPart.Position, Vector3.new(vec.X, entitylib.character.RootPart.Position.Y + 0.001, vec.Z))
                    end
    
                    task.wait()
                until not Killaura.Enabled
            else
                store.KillauraTarget = nil
                for _, v in Boxes do
                    v.Adornee = nil
                end
                for _, v in Rings do
                    v.Parent = nil
                end
                for _, v in Particles do
                    v.Parent = nil
                end
                debug.setupvalue(oldSwing or bedwars.SwordController.playSwordEffect, 7, bedwars.Knit)
                debug.setupvalue(bedwars.ScytheController.playLocalAnimation, 3, bedwars.Knit)
                Attacking = false
                if armC0 then
                    AnimTween = tweenService:Create(gameCamera.Viewmodel.RightHand.RightWrist, TweenInfo.new(AnimationTween.Enabled and 0.001 or 0.3, Enum.EasingStyle.Exponential), {
                        C0 = armC0
                    })
                    AnimTween:Play()
                end
            end
        end,
        Tooltip = 'Attack players around you\nwithout aiming at them.',
        ExtraText = function()
            return Mode.Value
        end
    })
    Targets = Killaura:CreateTargets({
        Players = true,
        NPCs = true
    })
    Continue = Killaura:CreateTwoSlider({
    	Name = 'Continue Swinging',
    	Min = 0,
    	Max = 2,
    	Decimal = 100,
    	DefaultMin = 0,
    	DefaultMax = 0.1,
    	Suffix = 'seconds',
    	Tooltip = 'Continues to swing ur sword'
    })
    local methods = {'Damage', 'Distance'}
    for i in sortmethods do
        if not table.find(methods, i) then
            table.insert(methods, i)
        end
    end
    SwingRange = Killaura:CreateSlider({
        Name = 'Swing range',
        Min = 1,
        Max = 40,
        Default = 22,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    AttackRange = Killaura:CreateSlider({
        Name = 'Attack range',
        Min = 1,
        Max = 22,
        Default = 22,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    AngleSlider = Killaura:CreateSlider({
        Name = 'Max angle',
        Min = 1,
        Max = 360,
        Default = 360
    })
    AirChance = Killaura:CreateSlider({
        Name = 'Air Hit Chance',
        Min = 0,
    	Max = 100,
    	Default = 100,
    	Suffix = '%'
    })
    SwingTime = Killaura:CreateSlider({
        Name = 'Swing time',
        Min = 0,
        Max = 2,
        Decimal = 100,
        Default = 0.11,
        Suffix = 'seconds'
    })
    Sync = Killaura:CreateToggle({
        Name = 'Sync with hitreg',
        Darker = true,
        Tooltip = 'Syncs the hitreg with swing time'
    })
    FastHits = Killaura:CreateToggle({
    	Name = 'Fast Hits',
    	Tooltip = 'Deals more damage quicker using projectiles',
    	Default = false,
    	Function = function(callback)
            pcall(function()
                Legit.Object.Visible = callback
                FireRate.Object.Visible = callback
                Whitelist.Object.Visible = callback
            end)
    	end
    })
    Whitelist = Killaura:CreateTextList({
        Name = 'Projectiles',
        Default = {'arrow', 'snowball'},
        Darker = true,
        Visible = false,
        Tooltip = 'Projectiles to use for fasthits'
    })
    Legit = Killaura:CreateToggle({
    	Name = 'Legit Switch',
    	Darker = true,
    	Visible = false
    })
    FireRate = Killaura:CreateSlider({
    	Name = 'Fire rate',
    	Suffix = 'seconds',
    	Min = 0,
    	Max = 2,
    	Decimal = 100,
    	Darker = true,
    	Visible = false,
    	Default = 0.05
    })
    MaxTargets = Killaura:CreateSlider({
        Name = 'Max targets',
        Min = 1,
        Max = 5,
        Default = 5
    })
    Mode = Killaura:CreateDropdown({
    	Name = 'Attack Mode',
    	List = {'Single', 'Multi', 'Switch'},
    	Tooltip = 'Single - Attacks one person at a time\nMulti - Attack multiple people at once\nSwitch - Switch between targets',
    	Default = 'Switch',
    	Function = function(val)
    		pcall(function()
    			MaxTargets.Object.Visible = val ~= 'Single'
    		end)
    	end,
    })
    Sort = Killaura:CreateDropdown({
        Name = 'Target Mode',
        List = methods
    })
    Dynamic = Killaura:CreateToggle({
        Name = 'Dynamic hits',
        Tooltip = 'Calculates ur hitreg depending on ur distance'
    })
    Mouse = Killaura:CreateToggle({Name = 'Require mouse down'})
    Swing = Killaura:CreateToggle({Name = 'No Swing'})
    GUI = Killaura:CreateToggle({Name = 'GUI check'})
    Killaura:CreateToggle({
        Name = 'Show target',
        Function = function(callback)
            BoxSwingColor.Object.Visible = callback
            BoxAttackColor.Object.Visible = callback
            BoxRender.Object.Visible = callback
            if callback then
                for i = 1, 10 do
                    local box = Instance.new('BoxHandleAdornment')
                    box.Adornee = nil
                    box.AlwaysOnTop = true
                    box.Size = Vector3.new(3, 5, 3)
                    box.CFrame = CFrame.new(0, -0.5, 0)
                    box.ZIndex = 0
                    box.Parent = vape.gui
                    Boxes[i] = box
                    if vape.ThreadFix then
                        setthreadidentity(8)
                    end
                    local ring = Instance.new('MeshPart')
    				ring.Size = Vector3.new(2.5, 5, 2.5)
    				ring.CanCollide = false
    				ring.Massless = true
                    ring.MeshContent = Content.fromAssetId(12812752257)
                    ring.MeshId = 'rbxassetid://12812752257'
    				ring.Anchored = true
                    local grad = Instance.new('Decal')
                    grad.ColorMapContent = Content.fromAssetId(106171062072708)
                    grad.Face = Enum.NormalId.Front
                    grad.Name = '1'
                    for i, v in {'Back', 'Right', 'Left'} do
                        local new = grad:Clone()
                        new.Name = tostring(i + 1)
                        new.Face = Enum.NormalId[v]
                        new.Parent = ring
                    end
                    grad.Parent = ring
                    Rings[i] = ring
    				bedwars.QueryUtil:setQueryIgnored(ring, true)
                end
            else
                for _, v in Boxes do
                    v:Destroy()
                end
                table.clear(Boxes)
            end
        end
    })
    BoxSwingColor = Killaura:CreateColorSlider({
        Name = 'Target Color',
        Darker = true,
        DefaultHue = 0.6,
        DefaultOpacity = 0.5,
        Visible = false
    })
    BoxAttackColor = Killaura:CreateColorSlider({
        Name = 'Attack Color',
        Darker = true,
        DefaultOpacity = 0.5,
        Visible = false
    })
    BoxRender = Killaura:CreateDropdown({
        Name = 'Render type',
        List = {'Box', 'Ring'},
        Darker = true,
        Default = 'Ring',
        Visible = false
    })
    Killaura:CreateToggle({
        Name = 'Target particles',
        Function = function(callback)
            ParticleTexture.Object.Visible = callback
            ParticleColor1.Object.Visible = callback
            ParticleColor2.Object.Visible = callback
            ParticleSize.Object.Visible = callback
            if callback then
                for i = 1, 10 do
                    local part = Instance.new('Part')
                    part.Size = Vector3.new(2, 4, 2)
                    part.Anchored = true
                    part.CanCollide = false
                    part.Transparency = 1
                    part.CanQuery = false
                    part.Parent = Killaura.Enabled and gameCamera or nil
                    local particles = Instance.new('ParticleEmitter')
                    particles.Brightness = 1.5
                    particles.Size = NumberSequence.new(ParticleSize.Value)
                    particles.Shape = Enum.ParticleEmitterShape.Sphere
                    particles.Texture = ParticleTexture.Value
                    particles.Transparency = NumberSequence.new(0)
                    particles.Lifetime = NumberRange.new(0.4)
                    particles.Speed = NumberRange.new(16)
                    particles.Rate = 128
                    particles.Drag = 16
                    particles.ShapePartial = 1
                    particles.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.fromHSV(ParticleColor1.Hue, ParticleColor1.Sat, ParticleColor1.Value)),
                        ColorSequenceKeypoint.new(1, Color3.fromHSV(ParticleColor2.Hue, ParticleColor2.Sat, ParticleColor2.Value))
                    })
                    particles.Parent = part
                    Particles[i] = part
                end
            else
                for _, v in Particles do
                    v:Destroy()
                end
                table.clear(Particles)
            end
        end
    })
    ParticleTexture = Killaura:CreateTextBox({
        Name = 'Texture',
        Default = 'rbxassetid://14736249347',
        Function = function()
            for _, v in Particles do
                v.ParticleEmitter.Texture = ParticleTexture.Value
            end
        end,
        Darker = true,
        Visible = false
    })
    ParticleColor1 = Killaura:CreateColorSlider({
        Name = 'Color Begin',
        Function = function(hue, sat, val)
            for _, v in Particles do
                v.ParticleEmitter.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHSV(hue, sat, val)),
                    ColorSequenceKeypoint.new(1, Color3.fromHSV(ParticleColor2.Hue, ParticleColor2.Sat, ParticleColor2.Value))
                })
            end
        end,
        Darker = true,
        Visible = false
    })
    ParticleColor2 = Killaura:CreateColorSlider({
        Name = 'Color End',
        Function = function(hue, sat, val)
            for _, v in Particles do
                v.ParticleEmitter.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHSV(ParticleColor1.Hue, ParticleColor1.Sat, ParticleColor1.Value)),
                    ColorSequenceKeypoint.new(1, Color3.fromHSV(hue, sat, val))
                })
            end
        end,
        Darker = true,
        Visible = false
    })
    ParticleSize = Killaura:CreateSlider({
        Name = 'Size',
        Min = 0,
        Max = 1,
        Default = 0.2,
        Decimal = 100,
        Function = function(val)
            for _, v in Particles do
                v.ParticleEmitter.Size = NumberSequence.new(val)
            end
        end,
        Darker = true,
        Visible = false
    })
    Face = Killaura:CreateToggle({Name = 'Face target'})
    Animation = Killaura:CreateToggle({
        Name = 'Custom Animation',
        Function = function(callback)
            AnimationMode.Object.Visible = callback
            AnimationTween.Object.Visible = callback
            AnimationSpeed.Object.Visible = callback
            if Killaura.Enabled then
                Killaura:Toggle()
                Killaura:Toggle()
            end
        end
    })
    local animnames = {}
    for i in anims do
        table.insert(animnames, i)
    end
    AnimationMode = Killaura:CreateDropdown({
        Name = 'Animation Mode',
        List = animnames,
        Darker = true,
        Visible = false
    })
    AnimationSpeed = Killaura:CreateSlider({
        Name = 'Animation Speed',
        Min = 0,
        Max = 2,
        Default = 1,
        Decimal = 10,
        Darker = true,
        Visible = false
    })
    AnimationTween = Killaura:CreateToggle({
        Name = 'No Tween',
        Darker = true,
        Visible = false
    })
    Attackable = Killaura:CreateToggle({
        Name = 'Attackable check',
        Tooltip = 'Checks if your in a state where you can attack'
    })
    Limit = Killaura:CreateToggle({
        Name = 'Limit to items',
        Tooltip = 'Only attacks when the sword is held'
    })
    LegitAura = Killaura:CreateToggle({
        Name = 'Swing only',
        Tooltip = 'Only attacks while swinging manually'
    })
end)


run(function()
    local Value
    local CameraDir
    local start
    local JumpTick, JumpSpeed, Direction = tick(), 0
    local projectileRemote = {InvokeServer = function() end}
    task.spawn(function()
        projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
    end)
    
    local function launchProjectile(item, pos, proj, speed, dir)
        if not pos then return end
    
        pos = pos - dir * 0.1
        local shootPosition = (CFrame.lookAlong(pos, Vector3.new(0, -speed, 0)) * CFrame.new(Vector3.new(-bedwars.BowConstantsTable.RelX, -bedwars.BowConstantsTable.RelY, -bedwars.BowConstantsTable.RelZ)))
        switchItem(item.tool, 0)
        task.wait(0.1)
        bedwars.ProjectileController:createLocalProjectile(bedwars.ProjectileMeta[proj], proj, proj, shootPosition.Position, '', shootPosition.LookVector * speed, {drawDurationSeconds = 1})
        if projectileRemote:InvokeServer(item.tool, proj, proj, shootPosition.Position, pos, shootPosition.LookVector * speed, httpService:GenerateGUID(true), {drawDurationSeconds = 1}, workspace:GetServerTimeNow() - 0.045) then
            local shoot = bedwars.ItemMeta[item.itemType].projectileSource.launchSound
            shoot = shoot and shoot[math.random(1, #shoot)] or nil
            if shoot then
                bedwars.SoundManager:playSound(shoot)
            end
        end
    end
    
    local LongJumpMethods = {
        cannon = function(_, pos, dir)
            pos = pos - Vector3.new(0, (entitylib.character.HipHeight + (entitylib.character.RootPart.Size.Y / 2)) - 3, 0)
            local rounded = Vector3.new(math.round(pos.X / 3) * 3, math.round(pos.Y / 3) * 3, math.round(pos.Z / 3) * 3)
            bedwars.placeBlock(rounded, 'cannon', false)
    
            task.delay(0, function()
                local block, blockpos = getPlacedBlock(rounded)
                if block and block.Name == 'cannon' and (entitylib.character.RootPart.Position - block.Position).Magnitude < 20 then
                    local breaktype = bedwars.ItemMeta[block.Name].block.breakType
                    local tool = store.tools[breaktype]
                    if tool then
                        switchItem(tool.tool)
                    end
    
                    bedwars.Client:Get(remotes.CannonAim):SendToServer({
                        cannonBlockPos = blockpos,
                        lookVector = dir
                    })
    
                    local broken = 0.1
                    if bedwars.BlockController:calculateBlockDamage(lplr, {blockPosition = blockpos}) < block:GetAttribute('Health') then
                        broken = 0.4
                        bedwars.breakBlock(block, true, true)
                    end
    
                    task.delay(broken, function()
                        for _ = 1, 3 do
                            local call = bedwars.Client:Get(remotes.CannonLaunch):CallServer({cannonBlockPos = blockpos})
                            if call then
                                bedwars.breakBlock(block, true, true)
                                JumpSpeed = 5.25 * Value.Value
                                JumpTick = tick() + 2.3
                                Direction = Vector3.new(dir.X, 0, dir.Z).Unit
                                break
                            end
                            task.wait(0.1)
                        end
                    end)
                end
            end)
        end,
        cat = function(_, _, dir)
            LongJump:Clean(vapeEvents.CatPounce.Event:Connect(function()
                JumpSpeed = 4 * Value.Value
                JumpTick = tick() + 2.5
                Direction = Vector3.new(dir.X, 0, dir.Z).Unit
                entitylib.character.RootPart.Velocity = Vector3.zero
            end))
    
            if not bedwars.AbilityController:canUseAbility('CAT_POUNCE') then
                repeat task.wait() until bedwars.AbilityController:canUseAbility('CAT_POUNCE') or not LongJump.Enabled
            end
    
            if bedwars.AbilityController:canUseAbility('CAT_POUNCE') and LongJump.Enabled then
                bedwars.AbilityController:useAbility('CAT_POUNCE')
            end
        end,
        fireball = function(item, pos, dir)
            launchProjectile(item, pos, 'fireball', 60, dir)
        end,
        grappling_hook = function(item, pos, dir)
            launchProjectile(item, pos, 'grappling_hook_projectile', 140, dir)
        end,
        jade_hammer = function(item, _, dir)
            if not bedwars.AbilityController:canUseAbility(item.itemType..'_jump') then
                repeat task.wait() until bedwars.AbilityController:canUseAbility(item.itemType..'_jump') or not LongJump.Enabled
            end
    
            if bedwars.AbilityController:canUseAbility(item.itemType..'_jump') and LongJump.Enabled then
                bedwars.AbilityController:useAbility(item.itemType..'_jump')
                JumpSpeed = 1.4 * Value.Value
                JumpTick = tick() + 2.5
                Direction = Vector3.new(dir.X, 0, dir.Z).Unit
            end
        end,
        tnt = function(item, pos, dir)
            pos = pos - Vector3.new(0, (entitylib.character.HipHeight + (entitylib.character.RootPart.Size.Y / 2)) - 3, 0)
            local rounded = Vector3.new(math.round(pos.X / 3) * 3, math.round(pos.Y / 3) * 3, math.round(pos.Z / 3) * 3)
            start = Vector3.new(rounded.X, start.Y, rounded.Z) + (dir * (item.itemType == 'pirate_gunpowder_barrel' and 2.6 or 0.2))
            bedwars.placeBlock(rounded, item.itemType, false)
        end,
        wood_dao = function(item, pos, dir)
            if (lplr.Character:GetAttribute('CanDashNext') or 0) > workspace:GetServerTimeNow() or not bedwars.AbilityController:canUseAbility('dash') then
                repeat task.wait() until (lplr.Character:GetAttribute('CanDashNext') or 0) < workspace:GetServerTimeNow() and bedwars.AbilityController:canUseAbility('dash') or not LongJump.Enabled
            end
    
            if LongJump.Enabled then
                bedwars.SwordController.lastAttack = workspace:GetServerTimeNow()
                switchItem(item.tool, 0.1)
                replicatedStorage['events-@easy-games/game-core:shared/game-core-networking@getEvents.Events'].useAbility:FireServer('dash', {
                    direction = dir,
                    origin = pos,
                    weapon = item.itemType
                })
                JumpSpeed = 4.5 * Value.Value
                JumpTick = tick() + 2.4
                Direction = Vector3.new(dir.X, 0, dir.Z).Unit
            end
        end
    }
    for _, v in {'stone_dao', 'iron_dao', 'diamond_dao', 'emerald_dao'} do
        LongJumpMethods[v] = LongJumpMethods.wood_dao
    end
    LongJumpMethods.void_axe = LongJumpMethods.jade_hammer
    LongJumpMethods.siege_tnt = LongJumpMethods.tnt
    LongJumpMethods.pirate_gunpowder_barrel = LongJumpMethods.tnt
    
    LongJump = vape.Categories.Blatant:CreateModule({
        Name = 'Long Jump',
        Function = function(callback)
            frictionTable.LongJump = callback or nil
            updateVelocity()
            if callback then
                LongJump:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
                    if damageTable.entityInstance == lplr.Character and damageTable.fromEntity == lplr.Character and (not damageTable.knockbackMultiplier or not damageTable.knockbackMultiplier.disabled) then
                        local knockbackBoost = bedwars.KnockbackUtil.calculateKnockbackVelocity(Vector3.one, 1, {
                            vertical = 0,
                            horizontal = (damageTable.knockbackMultiplier and damageTable.knockbackMultiplier.horizontal or 1)
                        }).Magnitude * 1.1
    
                        if knockbackBoost >= JumpSpeed then
                            local pos = damageTable.fromPosition and Vector3.new(damageTable.fromPosition.X, damageTable.fromPosition.Y, damageTable.fromPosition.Z) or damageTable.fromEntity and damageTable.fromEntity.PrimaryPart.Position
                            if not pos then return end
                            local vec = (entitylib.character.RootPart.Position - pos)
                            JumpSpeed = knockbackBoost
                            JumpTick = tick() + 2.5
                            Direction = Vector3.new(vec.X, 0, vec.Z).Unit
                        end
                    end
                end))
                LongJump:Clean(vapeEvents.GrapplingHookFunctions.Event:Connect(function(dataTable)
                    if dataTable.hookFunction == 'PLAYER_IN_TRANSIT' then
                        local vec = entitylib.character.RootPart.CFrame.LookVector
                        JumpSpeed = 2.5 * Value.Value
                        JumpTick = tick() + 2.5
                        Direction = Vector3.new(vec.X, 0, vec.Z).Unit
                    end
                end))
    
                start = entitylib.isAlive and entitylib.character.RootPart.Position or nil
                LongJump:Clean(runService.PreSimulation:Connect(function(dt)
                    local root = entitylib.isAlive and entitylib.character.RootPart or nil
    
                    if root and isnetworkowner(root) then
                        if JumpTick > tick() then
                            root.AssemblyLinearVelocity = Direction * (getSpeed() + ((JumpTick - tick()) > 1.1 and JumpSpeed or 0)) + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
                            if entitylib.character.Humanoid.FloorMaterial == Enum.Material.Air and not start then
                                root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + Vector3.new(0, dt * (workspace.Gravity - 23), 0)
                            else
                                root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 15, root.AssemblyLinearVelocity.Z)
                            end
                            start = nil
                        else
                            if start then
                                root.CFrame = CFrame.lookAlong(start, root.CFrame.LookVector)
                            end
                            root.AssemblyLinearVelocity = Vector3.zero
                            JumpSpeed = 0
                        end
                    else
                        start = nil
                    end
                end))
    
                if store.hand and LongJumpMethods[store.hand.tool.Name] then
                    task.spawn(LongJumpMethods[store.hand.tool.Name], getItem(store.hand.tool.Name), start, (CameraDir.Enabled and gameCamera or entitylib.character.RootPart).CFrame.LookVector)
                    return
                end
    
                for i, v in LongJumpMethods do
                    local item = getItem(i)
                    if item or store.equippedKit == i then
                        task.spawn(v, item, start, (CameraDir.Enabled and gameCamera or entitylib.character.RootPart).CFrame.LookVector)
                        break
                    end
                end
            else
                JumpTick = tick()
                Direction = nil
                JumpSpeed = 0
            end
        end,
        ExtraText = function()
            return 'Heatseeker'
        end,
        Tooltip = 'Lets you jump farther'
    })
    Value = LongJump:CreateSlider({
        Name = 'Speed',
        Min = 1,
        Max = 37,
        Default = 37,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    CameraDir = LongJump:CreateToggle({
        Name = 'Camera Direction'
    })
end)

run(function()
    local OwlAura
    local Targets
    local Range
    
    local function getProjectileMeta()
        local meta = table.clone(bedwars.ProjectileMeta.owl_projectile)
        return meta
    end
    
    OwlAura = vape.Categories.Blatant:CreateModule({
        Name = 'Owl Aura',
        Function = function(callback)
            if callback then
                local owls = collection('Owl', OwlAura, function(self, obj)
                    task.delay(1, function()
                        if obj and obj.Parent and obj:GetAttribute('Owner') == lplr.UserId then
                            table.insert(self, obj)
                        end
                    end)
                end)
                repeat
                    if store.equippedKit ~= 'owl' then
                        task.wait(3)
                        continue
                    end
    
                    if entitylib.isAlive then
                        local owl = owls[1]
                        if owl then
                            local origin = owl.Part.Position
                            local plr = entitylib.EntityPosition({
                                Origin = origin,
                                Range = Range.Value,
                                Part = 'RootPart',
                                Players = Targets.Players.Enabled,
                                NPCs = Targets.NPCs.Enabled,
                                Wallcheck = Targets.Walls.Enabled,
                                Sort = sortmethods.Health,
                            })
    
                            if plr then
                                local meta = getProjectileMeta()
                                local calc = prediction.SolveTrajectory(origin, meta.launchVelocity, meta.gravitationalAcceleration, plr.RootPart.Position, plr.RootPart.Velocity, workspace.Gravity, plr.HipHeight, plr.Jumping and 42.6 or nil)
                                if calc then
                                    local dir = CFrame.lookAt(origin, calc).LookVector * meta.launchVelocity
                                    bedwars.Client:Get('OwlAiming'):SendToServer({
                                        owl = owl.Part,
                                        starting = true,
                                    })
                                    bedwars.Client:Get('OwlFireProjectile'):SendToServer({
                                        ProjectileRefId = vape.Libraries.string:GenerateString(8),
                                        direction = dir,
                                        fromPosition = origin,
                                        initialVelocity = dir,
                                    })
                                    task.wait(lplr:GetNetworkPing())
                                end
                            end
                        end
                    end
                    task.wait(0.1)
                until not OwlAura.Enabled
            else
                bedwars.Client:Get('OwlAiming'):SendToServer({
                    starting = false,
                })
            end
        end,
        Tooltip = 'Automatically shoots projectiles with whisper kit'
    })
    
    Targets = OwlAura:CreateTargets({
        Players = true,
        Wallcheck = true,
    })
    Range = OwlAura:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 50,
        Suffix = function(val)
            return val <= 0 and 'stud' or 'studs'
        end,
        Default = 50,
    })
end)

run(function()
    local Prediction
    local AutoCharge
    local TargetPart
    local Targets
    local FOV
    local Sort
    local Horizontal
    local Vertical
    local OtherProjectiles
    local Blacklist
    local rayCheck = RaycastParams.new()
    rayCheck.FilterType = Enum.RaycastFilterType.Include
    rayCheck.FilterDescendantsInstances = {workspace:FindFirstChild('Map')}
    local launchHook

    -- ============================================================
    -- Projectile Aimbot DEBUG
    -- Writes levi_shakingrass/pa_debug.txt. For each shot it records what PA
    -- predicted vs where the target actually was when the projectile arrived,
    -- so a missed shot can be diagnosed: cross-track = they dodged unpredictably,
    -- along-track = lead/latency off, vertical = jump/gravity off. It also logs
    -- what the model had learned (strafe/turn/jump/knockback) at fire time.
    -- ============================================================
    local ProjectileAimbot
    local PADebug
    local paDebugPending = {}
    local paShotId = 0
    local paDebugFile = 'levi_shakingrass/pa_debug.txt'
    local paWeaponStats = {}
    local paDeathHooked = setmetatable({}, {__mode = 'k'})

    local function paLog(line)
        pcall(function()
            if appendfile then
                appendfile(paDebugFile, line .. '\n')
            else
                local ex = (isfile and isfile(paDebugFile) and readfile(paDebugFile)) or ''
                writefile(paDebugFile, ex .. line .. '\n')
            end
        end)
    end

    local function paFmtV(v)
        if typeof(v) ~= 'Vector3' then return 'nil' end
        return string.format('(%.1f, %.1f, %.1f)', v.X, v.Y, v.Z)
    end
    local function paFmtN(n, d)
        if type(n) ~= 'number' then return 'nil' end
        return string.format('%.' .. (d or 3) .. 'f', n)
    end

    local paFinishAndCopy

    local paLastShotRoot, paLastShotTime = nil, 0
    local function paDebugCapture(plr, origin, aimPart, predImpact, predTime, projmeta)
        local root = plr.RootPart
        if not root then return end
        local now = workspace:GetServerTimeNow()
        -- Dedupe: the launch hook fires twice per trigger-pull (predict + replicate).
        if root == paLastShotRoot and now - paLastShotTime < 0.03 then return end
        paLastShotRoot, paLastShotTime = root, now
        local bias, epochRate = prediction.getLatencyBias()
        local spread, spreadN = prediction.getResidualSpread()
        local latency = prediction.getLatency()
        -- What are we shooting WITH (crossbow / headhunter / bow ...) and firing?
        local weapon = 'unknown'
        pcall(function()
            if store.hand and store.hand.tool and store.hand.tool.Name then
                weapon = store.hand.tool.Name
            end
        end)
        local projName = (projmeta and projmeta.projectile) or 'unknown'
        paShotId += 1
        table.insert(paDebugPending, {
            id = paShotId,
            fireTime = now,
            -- Measure at travelTime + latency: predImpact was extrapolated from the
            -- replicated (stale-by-latency) position by exactly latency+travelTime, so
            -- the honest comparison waits that long for the replicated stream to catch up.
            arriveTime = now + (predTime or 0) + latency,
            travelTime = predTime or 0,
            root = root,
            plrName = (plr.Player and plr.Player.Name) or 'NPC',
            weapon = weapon,
            projName = projName,
            origin = origin,
            firePos = root.Position,
            fireVel = root.Velocity,
            aimOffset = (typeof(aimPart) == 'Vector3') and (aimPart - root.Position) or Vector3.zero,
            predImpact = predImpact,
            latency = latency,
            rawLatency = prediction.getRawLatency(),
            bias = bias,
            epochRate = epochRate,
            spread = spread,
            spreadN = spreadN,
            motion = prediction.getMotionDebug(root),
            dist = (root.Position - origin).Magnitude,
        })

        -- Auto-copy the log when the target we're shooting dies (the kill).
        local char = root.Parent
        if char and not paDeathHooked[char] then
            paDeathHooked[char] = true
            local hum = char:FindFirstChildOfClass('Humanoid')
            if hum then
                local charName = (plr.Player and plr.Player.Name) or char.Name
                local conn
                conn = hum.Died:Connect(function()
                    if conn then conn:Disconnect() end
                    task.wait(0.25) -- let the killing shot resolve first
                    paFinishAndCopy('killed ' .. charName)
                end)
                ProjectileAimbot:Clean(conn)
            end
        end
    end

    local function paDebugWrite(s)
        local root = s.root
        if not root or not root.Parent then
            paLog(string.format('#%d  target gone before arrival (died/left) | weapon: %s | proj: %s | led dist %s | travel %ss',
                s.id, tostring(s.weapon), tostring(s.projName), paFmtN(s.dist, 1), paFmtN(s.travelTime)))
            paLog('')
            return
        end
        local actualPos = root.Position
        local actualVel = root.Velocity
        -- Aim-part actual position at arrival (rigid offset from root)
        local actualAim = actualPos + s.aimOffset
        -- PA prediction error against where PA aimed the projectile to arrive
        local resPA = (typeof(s.predImpact) == 'Vector3') and (actualAim - s.predImpact) or Vector3.zero
        -- Naive constant-velocity lead (what a dumb solver would have aimed)
        local naive = s.firePos + s.fireVel * (s.travelTime + (s.latency or 0))
        local resNaive = actualPos - naive
        -- Decompose PA error along/cross the fire-time horizontal heading
        local flat = Vector3.new(s.fireVel.X, 0, s.fireVel.Z)
        local dir = flat.Magnitude > 0.1 and flat.Unit or Vector3.zero
        local flatRes = Vector3.new(resPA.X, 0, resPA.Z)
        local along = (dir.Magnitude > 0) and flatRes:Dot(dir) or 0
        local cross = (dir.Magnitude > 0) and (flatRes - dir * along).Magnitude or flatRes.Magnitude
        local vert = resPA.Y
        local m = s.motion
        -- Accumulate per-weapon stats for the end-of-fight summary
        local st = paWeaponStats[s.weapon or 'unknown']
        if not st then
            st = {shots = 0, miss = 0, along = 0, cross = 0, vert = 0}
            paWeaponStats[s.weapon or 'unknown'] = st
        end
        st.shots += 1
        st.miss += resPA.Magnitude
        st.along += math.abs(along)
        st.cross += cross
        st.vert += math.abs(vert)
        paLog(string.format('#%d  %s | weapon: %s | proj: %s | %s | dist %ss | travel %ss',
            s.id, s.plrName, tostring(s.weapon), tostring(s.projName), os.date('%H:%M:%S'), paFmtN(s.dist, 1), paFmtN(s.travelTime)))
        paLog(string.format('   MISS total %ss | along %ss (%s) | cross %ss (dodge) | vert %ss',
            paFmtN(resPA.Magnitude, 1),
            paFmtN(math.abs(along), 1), along >= 0 and 'under-led' or 'over-led',
            paFmtN(cross, 1), paFmtN(vert, 1)))
        paLog(string.format('   naive-lead miss %ss  ->  PA improved by %ss',
            paFmtN(resNaive.Magnitude, 1), paFmtN(resNaive.Magnitude - resPA.Magnitude, 1)))
        paLog(string.format('   latency %ss (raw %ss, bias %ss) | hitRate %s | residualSpread %s (n=%d)',
            paFmtN(s.latency), paFmtN(s.rawLatency), paFmtN(s.bias),
            s.epochRate and paFmtN(s.epochRate, 2) or 'n/a', paFmtN(s.spread, 2), s.spreadN or 0))
        paLog(string.format('   fireVel %s (h.spd %ss) | arriveVel %s',
            paFmtV(s.fireVel), paFmtN(flat.Magnitude, 1), paFmtV(actualVel)))
        if m then
            paLog(string.format('   model: strafeSeen %s half %ss | turnSeen %s rate %s | jumpV %s period %ss | flying %s | knockback %s | missRate %s | updInt %ss',
                tostring(m.strafeSeen or 0), paFmtN(m.strafeHalf, 2),
                tostring(m.turnSeen or 0), paFmtN(m.turnRate, 2),
                paFmtN(m.jumpVelocity, 1), paFmtN(m.jumpPeriod, 2),
                tostring(m.flying or false), tostring(m.knockback or false),
                paFmtN(m.missRate, 1), paFmtN(m.stale)))
        else
            paLog('   model: (no per-target state — root not passed / target too new)')
        end
        paLog('')
    end

    local function paDebugResolve()
        if #paDebugPending == 0 then return end
        local now = workspace:GetServerTimeNow()
        for i = #paDebugPending, 1, -1 do
            local s = paDebugPending[i]
            if now >= s.arriveTime then
                table.remove(paDebugPending, i)
                paDebugWrite(s)
            end
        end
    end

    -- Resolve remaining shots, write a per-weapon summary, and copy the whole
    -- log to the clipboard. Fired automatically when a shot target dies.
    paFinishAndCopy = function(reason)
        for i = #paDebugPending, 1, -1 do
            local s = paDebugPending[i]
            table.remove(paDebugPending, i)
            paDebugWrite(s)
        end
        paLog('=== SUMMARY (' .. tostring(reason) .. ') ===')
        local any = false
        for weap, st in paWeaponStats do
            if st.shots > 0 then
                any = true
                paLog(string.format('%s: %d shots | avg miss %ss | along %ss | cross %ss | vert %ss',
                    weap, st.shots,
                    paFmtN(st.miss / st.shots, 1), paFmtN(st.along / st.shots, 1),
                    paFmtN(st.cross / st.shots, 1), paFmtN(st.vert / st.shots, 1)))
            end
        end
        if not any then paLog('(no measured shots)') end
        paLog('')
        local copied = false
        pcall(function()
            if setclipboard and isfile and isfile(paDebugFile) then
                setclipboard(readfile(paDebugFile))
                copied = true
            end
        end)
        notif('Projectile Aimbot', (copied and 'Debug copied to clipboard' or 'Debug saved (clipboard unavailable)') .. ' — ' .. tostring(reason), 6, 'info')
    end
    
    local function getMousePosition()
    	if inputService.TouchEnabled then
    		return gameCamera.ViewportSize / 2
    	end
    	return inputService.GetMouseLocation(inputService)
    end
    
    local function getPosition(ent, proj)
    	if TargetPart.Value == 'Closest' then
    		local localPosition, magnitude, part = getMousePosition(), 9e9, nil
    		for _, v in ent:GetChildren() do
    			if pcall(function() return v.Position; end) then
    				local position, vis = gameCamera.WorldToViewportPoint(gameCamera, v.Position)
    
    				if vis then
    					local mag = (localPosition - Vector2.new(position.x, position.y)).Magnitude
    
    					if mag < magnitude then
    						magnitude = mag
    						part = v
    					end
    				end
    			end
    		end
    		return part and part.Position or ent.PrimaryPart.Position
    	elseif TargetPart.Value == 'Dynamic' then
    		local tool = store.hand.tool
    		if tool and tool.Name:find('headhunter') then
    			return ent.Head.Position
    		end
    		return ent.PrimaryPart.Position
    	end
    	return
    end

    ProjectileAimbot = vape.Categories.Blatant:CreateModule({
    	Name = 'Projectile Aimbot',
    	Disabled = not canDebug,
    	Function = function(callback)
    		if callback then
    			oldd = bedwars.BlockKickerKitController.getKickBlockProjectileOriginPosition
    			-- Resolver runs while PA is on; it no-ops unless Debug Log captured shots.
    			ProjectileAimbot:Clean(runService.Heartbeat:Connect(paDebugResolve))
    			launchHook = bedwars.ProjectileLaunchHook:Add('ProjectileAimbot', 100, function(nextLaunch, ...)
    				local self, projmeta, worldmeta, origin, shootpos = ...
    				local plr = entitylib.EntityMouse({
    					Part = 'RootPart',
    					Range = FOV.Value,
    					Players = Targets.Players.Enabled,
    					NPCs = Targets.NPCs.Enabled,
    					Wallcheck = Targets.Walls.Enabled,
    					Sort = sortmethods[Sort.Value or 'Distance'],
    					Origin = entitylib.isAlive and (shootpos or entitylib.character.RootPart.Position) or Vector3.zero,
    				})
    
    				if plr then
    					local pos = shootpos or self:getLaunchPosition(origin)
    					if not pos then
    						return nextLaunch(...)
    					end
    
    					if (not OtherProjectiles.Enabled) and not projmeta.projectile:find('arrow') then
    						return nextLaunch(...)
    					end
    
    					if table.find(Blacklist.ListEnabled or {}, ((projmeta.projectile == 'glue_trap' or projmeta.projectile == 'glue_projectile') and 'gloop' or projmeta.projectile)) then
    						return nextLaunch(...)
    					end
    
    					local meta = projmeta:getProjectileMeta()
    					local lifetime = (worldmeta and meta.predictionLifetimeSec or meta.lifetimeSec or 3)
    					local gravity = (meta.gravitationalAcceleration or 196.2) * projmeta.gravityMultiplier
    					local projSpeed = (meta.launchVelocity or 100)
    					local offsetpos = pos + (projmeta.projectile == 'owl_projectile' and Vector3.zero or projmeta.fromPositionOffset)
    					local balloons = plr.Character:GetAttribute('InflatedBalloons')
    					local playerGravity = workspace.Gravity
    
    					if balloons and balloons > 0 then
    						playerGravity = (workspace.Gravity * (1 - (balloons >= 4 and 1.2 or balloons >= 3 and 1 or 0.975)))
    					end
    
    					if plr.Character.PrimaryPart:FindFirstChild('rbxassetid://8200754399') then
    						playerGravity = 6
    					end
    
    					if plr.Player and plr.Player:GetAttribute('IsOwlTarget') then
    						for _, owl in collectionService:GetTagged('Owl') do
    							if owl:GetAttribute('Target') == plr.Player.UserId and owl:GetAttribute('Status') == 2 then
    								playerGravity = 0
    							end
    						end
    					end
    
    					local targetpos = getPosition(plr.Character) or plr[TargetPart.Value].Position
    					local newlook = CFrame.new(offsetpos, targetpos) * CFrame.new(projmeta.projectile == 'owl_projectile' and Vector3.zero or Vector3.new(bedwars.BowConstantsTable.RelX, bedwars.BowConstantsTable.RelY, bedwars.BowConstantsTable.RelZ))
    					-- Pass the target's RootPart so the prediction library can learn its per-target
    					-- motion (strafe/turn/jump/knockback) and apply latency compensation internally.
    					-- targetpos stays the aim part; the library derives the aim/root offset itself.
    					local targetVelocity = projmeta.projectile == 'telepearl' and Vector3.zero or plr.RootPart.Velocity
    					local calc, predImpact, predTime = prediction.SolveTrajectory(newlook.p, projSpeed * Prediction.Value, gravity, targetpos, targetVelocity, playerGravity, plr.HipHeight, plr.Jumping and 42.6 or nil, rayCheck, nil, plr.RootPart)
    					-- Directional prediction: independently scale how far we lead the target
    					-- sideways (Horizontal, the X/Z plane) vs while it rises or falls (Vertical, Y).
    					-- 1 = the solver's own lead, <1 under-leads that axis, >1 over-leads it. We
    					-- offset the aim point by the extra/less lead over the solved travel time and
    					-- re-solve so gravity is recomputed for the new point.
    					if calc and predTime and (Horizontal.Value ~= 1 or Vertical.Value ~= 1) then
    						local lead = Vector3.new(
    							targetVelocity.X * (Horizontal.Value - 1),
    							targetVelocity.Y * (Vertical.Value - 1),
    							targetVelocity.Z * (Horizontal.Value - 1)
    						) * predTime
    						calc = prediction.SolveTrajectory(newlook.p, projSpeed * Prediction.Value, gravity, targetpos + lead, targetVelocity, playerGravity, plr.HipHeight, plr.Jumping and 42.6 or nil, rayCheck, nil, plr.RootPart) or calc
    					end
    					if calc then
    						if PADebug and PADebug.Enabled then
    							paDebugCapture(plr, offsetpos, targetpos, predImpact, predTime, projmeta)
    						end
    						targetinfo.Targets[plr] = tick() + 1
    						return {
    							initialVelocity = CFrame.new(newlook.Position, calc).LookVector * (projSpeed * (AutoCharge.Enabled and 1 or projmeta.velocityMultiplier)),
    							positionFrom = offsetpos,
    							deltaT = lifetime,
    							gravitationalAcceleration = gravity,
    							drawDurationSeconds = AutoCharge.Enabled and 5 or projmeta.drawDurationSeconds,
    						}
    					end
    				end
    
    				return nextLaunch(...)
    			end)
    		else
    			if launchHook then
    				launchHook()
    				launchHook = nil
    			end
    		end
    	end,
    	Tooltip = 'Silently adjusts your aim towards the enemy',
    })
    Targets = ProjectileAimbot:CreateTargets({
    	Players = true,
    	Walls = true,
    })
    TargetPart = ProjectileAimbot:CreateDropdown({
    	Name = 'Part',
    	List = {'RootPart', 'Head', 'Dynamic', 'Closest'},
    })
    local methods = {'Damage', 'Distance'}
    for i in sortmethods do
    	if not table.find(methods, i) then
    		table.insert(methods, i)
    	end
    end
    Sort = ProjectileAimbot:CreateDropdown({
    	Name = 'Target Mode',
    	List = methods,
    	Default = 'Distance',
    })
    Prediction = ProjectileAimbot:CreateSlider({
    	Name = 'Prediction',
    	Min = 0.1,
    	Max = 2,
    	Default = 1,
    	Decimal = 10,
    })
    FOV = ProjectileAimbot:CreateSlider({
    	Name = 'FOV',
    	Min = 1,
    	Max = 1000,
    	Default = 1000,
    })
    Horizontal = ProjectileAimbot:CreateSlider({
    	Name = 'Horizontal prediction',
    	Min = 0,
    	Max = 2,
    	Default = 1,
    	Decimal = 100,
    	Tooltip = 'Scales how far ahead of the target you aim sideways',
    })
    Vertical = ProjectileAimbot:CreateSlider({
    	Name = 'Vertical prediction',
    	Min = 0,
    	Max = 2,
    	Default = 1,
    	Decimal = 100,
    	Tooltip = 'Scales how far ahead of the target you aim while it rises or falls',
    })
    AutoCharge = ProjectileAimbot:CreateToggle({
    	Name = 'Auto Charge',
    	Default = true,
    	Tooltip = 'Fully charges your bow, Allowing your projectile to deal more damage',
    })
    OtherProjectiles = ProjectileAimbot:CreateToggle({
    	Name = 'Other Projectiles',
    	Default = true,
    	Function = function(call)
    		if Blacklist and Blacklist.Object then
    			Blacklist.Object.Visible = call
    		end
    	end,
    })
    Blacklist = ProjectileAimbot:CreateTextList({
    	Name = 'Blacklist',
    	Default = {'gloop', 'telepearl'},
    	Darker = true,
    	Placeholder = 'projectile',
    })
    PADebug = ProjectileAimbot:CreateToggle({
    	Name = 'Debug Log',
    	Default = false,
    	Function = function(call)
    		if call then
    			paDebugPending = {}
    			paWeaponStats = {}
    			pcall(function()
    				writefile(paDebugFile, '=== Projectile Aimbot debug — ' .. os.date('%Y-%m-%d %H:%M:%S') .. ' ===\n'
    					.. 'along = lead/latency error (under-led = arrow behind them) | cross = they dodged | vert = jump/gravity\n'
    					.. 'auto-copies to clipboard when the target you are shooting dies\n\n')
    			end)
    			notif('Projectile Aimbot', 'Debug on — auto-copies on kill', 5, 'info')
    		end
    	end,
    	Tooltip = 'Logs each shot vs where the target actually was, to pa_debug.txt in your workspace',
    })
end)

run(function()
    local Mode
    local Value
    local WallCheck
    local AutoJump
    local AlwaysJump
    local rayCheck = RaycastParams.new()
    rayCheck.RespectCanCollide = true
    
    Speed = vape.Categories.Blatant:CreateModule({
        Name = 'Speed',
        Function = function(callback)
            frictionTable.Speed = callback or nil
            updateVelocity()
            pcall(function()
                debug.setconstant(bedwars.WindWalkerController.updateSpeed, 7, callback and 'constantSpeedMultiplier' or 'moveSpeedMultiplier')
            end)
    
            if callback then
                Speed:Clean(runService.PreSimulation:Connect(function(dt)
                    bedwars.StatefulEntityKnockbackController.lastImpulseTime = callback and math.huge or time()
                    if entitylib.isAlive then
                        if not (Fly and Fly.Enabled) and not (LongJump and LongJump.Enabled) then
                            bedwars.SprintController:setSpeed(Mode.Value == 'CFrame' and 20 or Value.Value)
                            if Mode.Value == 'CFrame' then
                                local state = entitylib.character.Humanoid:GetState()
                                if state == Enum.HumanoidStateType.Climbing then return end
            
                                local root, velo = entitylib.character.RootPart, getSpeed()
                                local moveDirection = AntiFallDirection or entitylib.character.Humanoid.MoveDirection
                                local destination = (moveDirection * math.max(Value.Value - velo, 0) * dt)
            
                                if WallCheck.Enabled then
                                    rayCheck.FilterDescendantsInstances = {lplr.Character, gameCamera}
                                    rayCheck.CollisionGroup = root.CollisionGroup
                                    local ray = workspace:Raycast(root.Position, destination, rayCheck)
                                    if ray then
                                        destination = ((ray.Position + ray.Normal) - root.Position)
                                    end
                                end
            
                                root.CFrame = root.CFrame + destination
                                root.AssemblyLinearVelocity = (moveDirection * velo) + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
                                if AutoJump.Enabled and (state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.Landed) and moveDirection ~= Vector3.zero and (Attacking or AlwaysJump.Enabled) then
                                    entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                                end
                            end
                        end
                    end
                end))
            else
                bedwars.SprintController:setSpeed(bedwars.SprintController:isSprinting() and 20 or 14)
            end
        end,
        ExtraText = function()
            return 'Heatseeker'
        end,
        Tooltip = 'Increases your movement with various methods.'
    })
    Mode = Speed:CreateDropdown({
        Name = 'Method',
        List = {'Bedwars', 'CFrame'},
        Default = 'CFrame'
    })
    Value = Speed:CreateSlider({
        Name = 'Speed',
        Min = 1,
        Max = 23,
        Default = 23,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    WallCheck = Speed:CreateToggle({
        Name = 'Wall Check',
        Default = true
    })
    AutoJump = Speed:CreateToggle({
        Name = 'AutoJump',
        Function = function(callback)
            AlwaysJump.Object.Visible = callback
        end
    })
    AlwaysJump = Speed:CreateToggle({
        Name = 'Always Jump',
        Visible = false,
        Darker = true
    })
end)

run(function()
    local TerraAimbot
    local Range
    local Mode
    
    local old
    
    TerraAimbot = vape.Categories.Blatant:CreateModule({
        Name = 'Terra Aimbot',
        Function = function(callback)
            if callback then
                old = bedwars.BlockKickerKitController.getKickBlockProjectileOriginPosition
                bedwars.BlockKickerKitController.getKickBlockProjectileOriginPosition = function(...)
                    local origin, dir = select(2, ...)
                    local plr = entitylib['Entity'.. Mode.Value]({
                        Part = 'RootPart',
                        Range = Range.Value,
                        Origin = origin,
                        Players = true,
                        Wallcheck = true
                    })
    
                    if plr then
                        local calc = prediction.SolveTrajectory(origin, 100, 20, plr.RootPart.Position, plr.RootPart.Velocity, workspace.Gravity, plr.HipHeight, plr.Jumping and 42.6 or nil)
    
                        if calc then
                            for i, v in debug.getstack(2) do
                                if v == dir then
                                    debug.setstack(2, i, CFrame.lookAt(origin, calc).LookVector)
                                end
                            end
                        end
                    end
    
                    return old(...)
                end
            end
        end,
        Tooltip = 'Silently adjusts where terra blocks are heading towards.'
    })
    
    Mode = TerraAimbot:CreateDropdown({
        Name = 'Mode',
        List = {'Position', 'Mouse'},
        Default = 'Mouse'
    })
    Range = TerraAimbot:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 1000,
        Default = 1000,
        Suffix = function(val)
            return val <= 1 and 'studs' or 'stud'
        end
    })
end)

run(function()
    local VulcanAimbot
    local Targets
    local Range
    local Sort
    
    VulcanAimbot = vape.Categories.Blatant:CreateModule({
        Name = 'Vulcan Aimbot',
        Function = function(callback)
            if callback then
                repeat
                    if entitylib.isAlive then
                        local turret = bedwars.Store:getState().Game.selectedTurret
                        if turret then
                            local origin = turret.Rotate.Position
                            local ent = entitylib.EntityMouse({
                                Range = Range.Value,
                                Origin = origin,
                                Wallcheck = Targets.Walls.Enabled or nil,
                                Part = 'RootPart',
                                Players = Targets.Players.Enabled,
                                NPCs = Targets.NPCs.Enabled,
                                Sort = sortmethods[Sort.Value]
                            })
                            if ent then
                                local pos = prediction.SolveTrajectory(origin, 320, 10, ent.RootPart.Position, ent.RootPart.Velocity, workspace.Gravity, ent.HipHeight, nil, store.airRay)
                                if pos then
                                    local delta = pos - origin
    
                                    -- mathing
                                    bedwars.TurretCameraController.angleX = math.atan2(-delta.X, -delta.Z)
                                    bedwars.TurretCameraController.angleY = math.clamp(math.atan2(delta.Y, math.sqrt(delta.X^2 + delta.Z^2)), -0.8, 0.8)
                                end
                            end
                        end
                    end
                    task.wait(0.1)
                until not VulcanAimbot.Enabled
            end
        end,
        Tooltip = 'Automatically aims ur camera toward opponents.'
    })
    
    Targets = VulcanAimbot:CreateTargets({Walls = true, Players = true})
    local methods = {'Distance', 'Damage'}
    for i in sortmethods do
        if not table.find(methods, i) then
            table.insert(methods, i)
        end
    end
    Sort = VulcanAimbot:CreateDropdown({
        Name = 'Target mode',
        List = methods,
        Default = methods[1]
    })
    Range = VulcanAimbot:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 1000,
        Default = 500
    })
end)

run(function()
    local DronePhase
    local modified = {}

    DronePhase = vape.Categories.Blatant:CreateModule({
        Name = 'Drone Phase',
        Function = function(callback)
            if callback then
                DronePhase:Clean(runService.Stepped:Connect(function()
                    local myDrone
                    for _, drone in collectionService:GetTagged('Drone') do
                        if drone:GetAttribute('PlayerUserId') == lplr.UserId then
                            myDrone = drone
                            break
                        end
                    end

                    for part in modified do
                        if not myDrone or not part:IsDescendantOf(myDrone) then
                            modified[part] = nil
                            part.CanCollide = true
                        end
                    end

                    if myDrone then
                        for _, part in myDrone:GetDescendants() do
                            if part:IsA('BasePart') and part.CanCollide then
                                modified[part] = true
                                part.CanCollide = false
                            end
                        end
                    end
                end))
            else
                for part in modified do
                    part.CanCollide = true
                end
                table.clear(modified)
            end
        end,
        Tooltip = 'Phases your Cyber Drone through walls.',
    })
end)

--[[
    Render
]]

run(function()
    local ArmorHighlight
    local Boots, Helmet, Chestplate, UseParts
    
    local Instances, Decoys = {}, {}
    local Properties = {
        OutlineTransparency = 'Slider',
        FillTransparency = 'Slider',
        FillColor = 'ColorSlider',
        OutlineColor = 'ColorSlider'
    }
    
    local function getArmor(v)
        if v:GetAttribute('ArmorSlot') == 0 and Helmet.Enabled then
            return 'Helmet'
        elseif v:GetAttribute('ArmorSlot') == 1 and Chestplate.Enabled then
            return 'Chestplate'
        elseif v:GetAttribute('ArmorSlot') == 2 and Boots.Enabled then
            return 'Boots'
        end
        return nil
    end
    
    ArmorHighlight = vape.Categories.Render:CreateModule({
        Name = 'Armor Highlight',
        Function = function(call)
            if call then
                ArmorHighlight:Clean(lplr.CharacterAdded:Connect(function(char)
                    ArmorHighlight:Clean(char.ChildAdded:Connect(function(part)
                        task.wait(1)
                        local armor = getArmor(part)
                        if armor then
                            if false then
                                local v = Instance.new('Part')
                                v.CanCollide = false
                                for name, prop in getproperties(part:WaitForChild('Handle')) do
                                    pcall(function()
                                        v[name] = prop
                                    end)
                                end
                                v.Anchored = true
                                part.Handle.Transparency = 1
                                v.Material = Enum.Material.Neon
                                for _, child in part.Handle:GetChildren() do
                                    child.Parent = v
                                end
                                v.Parent = part
                                table.insert(Decoys, {
                                    TP = part.Handle,
                                    Main = v
                                })
                            else
                                local highlight = Instance.new('Highlight', part:WaitForChild('Handle'))
                                for i,v in Properties do
                                    highlight[i] = typeof(v.Hue) == 'number' and Color3.fromHSV(v.Hue, v.Sat, v.Value) or v.Value
                                end
                                
                                table.insert(Instances, highlight)
                            end
                        end
                    end))
                    for _, part in char:GetChildren() do
                        local armor = getArmor(part)
                        if armor then
                            if UseParts.Enabled then
                                local v = Instance.new('Part')
                                v.CanCollide = false
                                for name, prop in getproperties(part:WaitForChild('Handle')) do
                                    pcall(function()
                                        v[name] = prop
                                    end)
                                end
                                part.Handle.Transparency = 1
                                v.Anchored = true
                                v.Material = Enum.Material.Neon
                                for _, child in part.Handle:GetChildren() do
                                    child.Parent = v
                                end
                                table.insert(Decoys, {
                                    TP = part.Handle,
                                    Main = v
                                })
                            else
                                local highlight = Instance.new('Highlight', part:WaitForChild('Handle'))
                                for i,v in Properties do
                                    highlight[i] = typeof(v.Hue) == 'number' and Color3.fromHSV(v.Hue, v.Sat, v.Value) or v.Value
                                end
                                
                                table.insert(Instances, highlight)
                            end
                        end
                    end
                end))
    
                ArmorHighlight:Clean(runService.PreRender:Connect(function()
                    for _, data in Decoys do
                        if data.Main and data.Main.Parent and data.TP and data.TP.Parent then
                            data.Main.Velocity = Vector3.new(0, 1, 0)
                            data.Main.CFrame = data.TP.CFrame
                        end
                    end
                end))
    
                if entitylib.isAlive then
                    ArmorHighlight:Clean(lplr.Character.ChildAdded:Connect(function(part)
                        task.wait(1)
                        local armor = getArmor(part)
                        if armor then
                            if UseParts.Enabled then
                                local v = Instance.new('Part')
                                v.CanCollide = false
                                for name, prop in getproperties(part:WaitForChild('Handle')) do
                                    pcall(function()
                                        v[name] = prop
                                    end)
                                end
                                v.Anchored = true
                                part.Handle.Transparency = 1
                                v.Material = Enum.Material.Neon
                                for _, child in part.Handle:GetChildren() do
                                    child.Parent = v
                                end
                                v.Parent = part
                                table.insert(Decoys, {
                                    TP = part.Handle,
                                    Main = v
                                })
                            else
                                local highlight = Instance.new('Highlight', part:WaitForChild('Handle'))
                                for i,v in Properties do
                                    highlight[i] = typeof(v.Hue) == 'number' and Color3.fromHSV(v.Hue, v.Sat, v.Value) or v.Value
                                end
                                
                                table.insert(Instances, highlight)
                            end
                        end
                    end))
    
                    for _, part in lplr.Character:GetChildren() do
                        local armor = getArmor(part)
                        if armor then
                            if UseParts.Enabled then
                                local v = Instance.new('Part')
                                v.CanCollide = false
                                for name, prop in getproperties(part:WaitForChild('Handle')) do
                                    pcall(function()
                                        v[name] = prop
                                    end)
                                end
                                part.Handle.Transparency = 1
                                v.Anchored = true
                                v.Material = Enum.Material.Neon
                                for _, child in part.Handle:GetChildren() do
                                    child.Parent = v
                                end
                                table.insert(Decoys, {
                                    TP = part.Handle,
                                    Main = v
                                })
                            else
                                local highlight = Instance.new('Highlight', part:WaitForChild('Handle'))
                                for i,v in Properties do
                                    highlight[i] = typeof(v.Hue) == 'number' and Color3.fromHSV(v.Hue, v.Sat, v.Value) or v.Value
                                end
                                
                                table.insert(Instances, highlight)
                            end
                        end
                    end
                end
            else
                for i,v in Instances do
                    v:Destroy()
                end
                table.clear(Decoys)
                table.clear(Instances)
            end
        end
    })
    
    for i,v in Properties do
        local name = i
    
        Properties[name] = ArmorHighlight['Create'.. v](ArmorHighlight, {
            Name = i,
            Min = 0,
            Max = 1,
            Decimal = 35,
            Function = function(hue, sat, val)
                pcall(function()
                    for _, ins in Instances do
                        ins[name] = sat and Color3.fromHSV(hue, sat, val) or hue
                    end
                end)
    
                if sat then
                    for _, ins in Decoys do
                        ins.Main.Color = Color3.fromHSV(hue, sat, val)
                    end
                end
            end
        })
    end
    
    Helmet = ArmorHighlight:CreateToggle({
        Name = 'Helmet',
        Function = function()
            if ArmorHighlight.Enabled then
                ArmorHighlight:Toggle()
                ArmorHighlight:Toggle()
            end
        end
    })
    
    Chestplate = ArmorHighlight:CreateToggle({
        Name = 'Chestplate',
        Function = function()
            if ArmorHighlight.Enabled then
                ArmorHighlight:Toggle()
                ArmorHighlight:Toggle()
            end
        end
    })
    
    Boots = ArmorHighlight:CreateToggle({
        Name = 'Boots',
        Default = true,
        Function = function()
            if ArmorHighlight.Enabled then
                ArmorHighlight:Toggle()
                ArmorHighlight:Toggle()
            end
        end
    })
    
    UseParts = ArmorHighlight:CreateToggle({
        Name = 'Use Parts',
        Default = true,
        Function = function()
            if ArmorHighlight.Enabled then
                ArmorHighlight:Toggle()
                ArmorHighlight:Toggle()
            end
        end
    })
end)

run(function()
    local BedESP
    local Reference = {}
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui

    local function Added(bed)
    	if not BedESP.Enabled then
    		return
    	end
    	local BedFolder = Instance.new('Folder')
    	BedFolder.Parent = Folder
    	Reference[bed] = BedFolder
    	local parts = bed:GetChildren()
    	table.sort(parts, function(a, b)
    		return a.Name > b.Name
    	end)

    	for _, part in parts do
    		if part:IsA('BasePart') and part.Name ~= 'Blanket' then
    			local handle = Instance.new('BoxHandleAdornment')
    			handle.Size = part.Size + Vector3.new(0.01, 0.01, 0.01)
    			handle.AlwaysOnTop = true
    			handle.ZIndex = 2
    			handle.Visible = true
    			handle.Adornee = part
    			handle.Color3 = part.Color
    			if part.Name == 'Legs' then
    				handle.Color3 = Color3.fromRGB(167, 112, 64)
    				handle.Size = part.Size + Vector3.new(0.01, -1, 0.01)
    				handle.CFrame = CFrame.new(0, -0.4, 0)
    				handle.ZIndex = 0
    			end
    			handle.Parent = BedFolder
    		end
    	end

    	table.clear(parts)
    end

    BedESP = vape.Categories.Render:CreateModule({
    	Name = 'Bed ESP',
    	Function = function(callback)
    		if callback then
    			BedESP:Clean(collectionService:GetInstanceAddedSignal('bed'):Connect(function(bed)
    				task.delay(0.2, Added, bed)
    			end))
    			BedESP:Clean(collectionService:GetInstanceRemovedSignal('bed'):Connect(function(bed)
    				if Reference[bed] then
    					Reference[bed]:Destroy()
    					Reference[bed] = nil
    				end
    			end))
    			for _, bed in collectionService:GetTagged('bed') do
    				Added(bed)
    			end
    		else
    			Folder:ClearAllChildren()
    			table.clear(Reference)
    		end
    	end,
    	Tooltip = 'Render Beds through walls'
    })
end)

run(function()
    local HiveESP
    local Background

    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui

    local Reference = {}

    local function Added(ent)
    	local Name = playersService:GetNameFromUserIdAsync(ent:GetAttribute('PlacedByUserId')) or 'Unknown'

    	local card = Instance.new('Frame')
    	card.AnchorPoint = Vector2.new(0.5, 1)
    	card.BackgroundColor3 = Color3.new()
    	card.BackgroundTransparency = Background.Enabled and 0.35 or 1
    	card.BorderSizePixel = 0
    	card.AutomaticSize = Enum.AutomaticSize.XY
    	card.Visible = false
    	local cardCorner = Instance.new('UICorner')
    	cardCorner.CornerRadius = UDim.new(0, 4)
    	cardCorner.Parent = card
    	local cardPadding = Instance.new('UIPadding')
    	cardPadding.PaddingLeft = UDim.new(0, 6)
    	cardPadding.PaddingRight = UDim.new(0, 6)
    	cardPadding.PaddingTop = UDim.new(0, 3)
    	cardPadding.PaddingBottom = UDim.new(0, 3)
    	cardPadding.Parent = card
    	local cardLayout = Instance.new('UIListLayout')
    	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    	cardLayout.Padding = UDim.new(0, 1)
    	cardLayout.Parent = card

    	local title = Instance.new('TextLabel')
    	title.Name = 'Title'
    	title.AutomaticSize = Enum.AutomaticSize.XY
    	title.BackgroundTransparency = 1
    	title.Font = Enum.Font.GothamBold
    	title.TextSize = 9
    	title.TextColor3 = Color3.fromRGB(255, 200, 50)
    	title.Text = Name .. "'s Beehive"
    	title.LayoutOrder = 1
    	title.Parent = card

    	local info = Instance.new('TextLabel')
    	info.Name = 'Info'
    	info.AutomaticSize = Enum.AutomaticSize.XY
    	info.BackgroundTransparency = 1
    	info.Font = Enum.Font.GothamBold
    	info.TextSize = 8
    	info.TextColor3 = Color3.fromRGB(200, 200, 200)
    	info.RichText = true
    	info.LayoutOrder = 2
    	info.Parent = card

    	card.Parent = Folder
    	Reference[ent] = card
    end

    local function Removing(ent)
    	if Reference[ent] then
    		Reference[ent]:Destroy()
    		Reference[ent] = nil
    	end
    end

    HiveESP = vape.Categories.Render:CreateModule({
    	Name = 'Beehive ESP',
    	Function = function(call)
    		if call then
    			for _, v in collectionService:GetTagged('beehive') do
    				Added(v)
    			end
    			HiveESP:Clean(collectionService:GetInstanceAddedSignal('beehive'):Connect(Added))
    			HiveESP:Clean(collectionService:GetInstanceRemovedSignal('beehive'):Connect(Removing))
    			HiveESP:Clean(runService.PreRender:Connect(function()
    				for ent, card in Reference do
    					local headPos, headVis = gameCamera:WorldToViewportPoint(ent.Position + Vector3.new(0, 2, 0))
    					card.Visible = headVis
    					if headVis then
    						local level = ent:GetAttribute('Level') or 0
    						local dist = entitylib.isAlive and math.floor((entitylib.character.RootPart.Position - ent.Position).Magnitude) or 0
    						card.Info.Text = level .. ' Bee' .. (level >= 2 and 's' or '') .. '  <font color="rgb(130,130,130)">' .. dist .. 'm</font>'
    						card.Position = UDim2.fromOffset(headPos.X, headPos.Y)
    					end
    				end
    			end))
    		else
    			for i in Reference do
    				Removing(i)
    			end
    		end
    	end,
    	Tooltip = 'Renders hives locations and info'
    })
    Background = HiveESP:CreateToggle({
    	Name = 'Background',
    	Function = function(callback)
    		for _, card in Reference do
    			card.BackgroundTransparency = callback and 0.35 or 1
    		end
    	end,
    	Default = true
    })
end)

run(function()
    local CustomTags
    local Color
    local TAG
    local old, old2
    local tagRenderConn
    local tagGuiConn

    local function Color3ToHex(r, g, b)
    	return string.lower(string.format('#%02X%02X%02X', r, g, b))
    end

    local function CompleteTagEffect()
    	if not lplr:FindFirstChild('Tags') then
    		return
    	end
    	local tagObj = lplr.Tags:FindFirstChild('0')
    	if not tagObj then
    		return
    	end

    	if not old then
    		old = tagObj.Value
    		old2 = tagObj:GetAttribute('Text')
    	end

    	local color = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
    	local R = math.floor(color.R * 255)
    	local G = math.floor(color.G * 255)
    	local B = math.floor(color.B * 255)

    	tagObj.Value = string.format("<font color='rgb(%d,%d,%d)'>[%s]</font>", R, G, B, TAG.Value)
    	tagObj:SetAttribute('Text', TAG.Value)
    	lplr:SetAttribute('ClanTag', TAG.Value)

    	if tagRenderConn then
    		tagRenderConn:Disconnect()
    		tagRenderConn = nil
    	end
    	if tagGuiConn then
    		tagGuiConn:Disconnect()
    		tagGuiConn = nil
    	end

    	tagGuiConn = lplr.PlayerGui.ChildAdded:Connect(function(child)
    		if child.Name ~= 'TabListScreenGui' or not child:IsA('ScreenGui') then
    			return
    		end
    		tagRenderConn = runService.RenderStepped:Connect(function()
    			local nameToFind = (lplr.DisplayName == '' or lplr.DisplayName == lplr.Name) and lplr.Name
    				or lplr.DisplayName
    			for _, v in ipairs(child:GetDescendants()) do
    				if v:IsA('TextLabel') and string.find(string.lower(v.Text), string.lower(nameToFind)) then
    					v.Text = string.format(
    						'<font transparency="0.3" color="%s">[%s]</font> %s',
    						Color3ToHex(R, G, B),
    						TAG.Value,
    						nameToFind
    					)
    				end
    			end
    		end)
    	end)
    end

    local function RemoveTagEffect()
    	if tagRenderConn then
    		tagRenderConn:Disconnect()
    		tagRenderConn = nil
    	end

    	if tagGuiConn then
    		tagGuiConn:Disconnect()
    		tagGuiConn = nil
    	end

    	if lplr:FindFirstChild('Tags') then
    		local tagObj = lplr.Tags:FindFirstChild('0')
    		if tagObj then
    			if old then
    				tagObj.Value = old
    			end
    			if old2 then
    				tagObj:SetAttribute('Text', old2)
    			end
    		end
    	end

    	if lplr:GetAttribute('ClanTag') then
    		lplr:SetAttribute('ClanTag', old)
    	end

    	old = nil
    	old2 = nil
    end

    CustomTags = vape.Categories.Render:CreateModule({
    	Name = 'Custom Tags',
    	Function = function(callback)
    		if callback then
    			CompleteTagEffect()
    		else
    			RemoveTagEffect()
    		end
    	end,
    	Tooltip = 'Client-Sided visual custom clan tag on-chat'
    })

    Color = CustomTags:CreateColorSlider({
    	Name = 'Color',
    	Function = function()
    		if CustomTags.Enabled then
    			CompleteTagEffect()
    		end
    	end,
    })
    TAG = CustomTags:CreateTextBox({
    	Name = 'Tag',
    	Default = 'gg',
    	Function = function()
    		if CustomTags.Enabled then
    			CompleteTagEffect()
    		end
    	end,
    })
end)

run(function()
    local GeneratorESP
    DiamondToggle = nil
    EmeraldToggle = nil
    TeamGenToggle = nil
    ShowOwnTeamGen = nil
    ShowEnemyTeamGen = nil
    local UIStyle
    local CompactDiamondToggle
    local CompactEmeraldToggle
    local CollectionService = collectionService
    local RunService = runService
    local Reference = {}
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui
    local CompactFolder = Instance.new('Folder')
    CompactFolder.Parent = vape.gui
    local teamColors = {
        [1] = {name = "Blue",   color = Color3.fromRGB(85, 150, 255)},
        [2] = {name = "Orange", color = Color3.fromRGB(255, 150, 50)},
        [3] = {name = "Pink",   color = Color3.fromRGB(255, 100, 200)},
        [4] = {name = "Yellow", color = Color3.fromRGB(255, 255, 50)}
    }

    local generatorTypes = {
        diamond = {
            keywords = {'diamond'},
            color = Color3.fromRGB(85, 200, 255),
            icon = 'diamond',
            displayName = 'Diamond',
            isTeamGen = false
        },
        emerald = {
            keywords = {'emerald'},
            color = Color3.fromRGB(0, 255, 100),
            icon = 'emerald',
            displayName = 'Emerald',
            isTeamGen = false
        }
    }

    local compactUI = Instance.new('ScreenGui')
    compactUI.Name = 'GeneratorCompactUI'
    compactUI.Parent = vape.gui
    compactUI.Enabled = false
    compactUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    compactUI.DisplayOrder = 10
    compactUI.ResetOnSpawn = false

    local mainFrame = Instance.new('Frame')
    mainFrame.Name = 'MainFrame'
    mainFrame.Parent = compactUI
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    mainFrame.BackgroundTransparency = 0.3
    mainFrame.BorderSizePixel = 0
    mainFrame.Position = UDim2.new(1, -8, 1, -8)
    mainFrame.Size = UDim2.new(0, 120, 0, 100)
    mainFrame.AnchorPoint = Vector2.new(1, 1)

    local uicorner = Instance.new('UICorner')
    uicorner.CornerRadius = UDim.new(0, 8)
    uicorner.Parent = mainFrame

    local title = Instance.new('TextLabel')
    title.Name = 'Title'
    title.Parent = mainFrame
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, 0, 0, 25)
    title.Position = UDim2.new(0, 0, 0, 5)
    title.Text = "GEN ESP"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 14
    title.Font = Enum.Font.GothamBold
    title.TextStrokeTransparency = 0.5
    title.TextStrokeColor3 = Color3.new(0, 0, 0)

    local diamondFrame = Instance.new('Frame')
    diamondFrame.Name = 'DiamondFrame'
    diamondFrame.Parent = mainFrame
    diamondFrame.BackgroundTransparency = 1
    diamondFrame.Size = UDim2.new(1, -20, 0, 25)
    diamondFrame.Position = UDim2.new(0, 10, 0, 35)

    local diamondIcon = Instance.new('ImageLabel')
    diamondIcon.Name = 'DiamondIcon'
    diamondIcon.Parent = diamondFrame
    diamondIcon.BackgroundTransparency = 1
    diamondIcon.Size = UDim2.new(0, 18, 0, 18)
    diamondIcon.Position = UDim2.new(0, 0, 0.5, -9)
    diamondIcon.Image = bedwars.getIcon({itemType = 'diamond'}, true)

    local diamondTimer = Instance.new('TextLabel')
    diamondTimer.Name = 'DiamondTimer'
    diamondTimer.Parent = diamondFrame
    diamondTimer.BackgroundTransparency = 1
    diamondTimer.Size = UDim2.new(1, -25, 1, 0)
    diamondTimer.Position = UDim2.new(0, 25, 0, 0)
    diamondTimer.Text = "00"
    diamondTimer.TextColor3 = Color3.fromRGB(85, 200, 255)
    diamondTimer.TextSize = 18
    diamondTimer.Font = Enum.Font.GothamBold
    diamondTimer.TextXAlignment = Enum.TextXAlignment.Left

    local emeraldFrame = Instance.new('Frame')
    emeraldFrame.Name = 'EmeraldFrame'
    emeraldFrame.Parent = mainFrame
    emeraldFrame.BackgroundTransparency = 1
    emeraldFrame.Size = UDim2.new(1, -20, 0, 25)
    emeraldFrame.Position = UDim2.new(0, 10, 0, 65)

    local emeraldIcon = Instance.new('ImageLabel')
    emeraldIcon.Name = 'EmeraldIcon'
    emeraldIcon.Parent = emeraldFrame
    emeraldIcon.BackgroundTransparency = 1
    emeraldIcon.Size = UDim2.new(0, 18, 0, 18)
    emeraldIcon.Position = UDim2.new(0, 0, 0.5, -9)
    emeraldIcon.Image = bedwars.getIcon({itemType = 'emerald'}, true)

    local emeraldTimer = Instance.new('TextLabel')
    emeraldTimer.Name = 'EmeraldTimer'
    emeraldTimer.Parent = emeraldFrame
    emeraldTimer.BackgroundTransparency = 1
    emeraldTimer.Size = UDim2.new(1, -25, 1, 0)
    emeraldTimer.Position = UDim2.new(0, 25, 0, 0)
    emeraldTimer.Text = "00"
    emeraldTimer.TextColor3 = Color3.fromRGB(0, 255, 100)
    emeraldTimer.TextSize = 18
    emeraldTimer.Font = Enum.Font.GothamBold
    emeraldTimer.TextXAlignment = Enum.TextXAlignment.Left

    local diamondTimes = {}
    local emeraldTimes = {}

    local function getMyTeamId()
        local myTeam = lplr:GetAttribute('Team')
        if myTeam == nil then return nil end
        return tonumber(myTeam)
    end

    local function getGeneratorTeamId(generatorId)
        local teamNum = string.match(generatorId, "^(%d+)_generator")
        if teamNum then
            return tonumber(teamNum)
        end
        return nil
    end

    local function isTeamGenerator(generatorId)
        return string.match(generatorId, "^%d+_generator") ~= nil
    end

    local function getGeneratorType(generatorId)
        local idLower = string.lower(generatorId)

        if isTeamGenerator(generatorId) then
            return 'teamgen', {
                color = Color3.fromRGB(200, 200, 200),
                icon = 'iron',
                displayName = 'Team Gen',
                isTeamGen = true
            }
        end

        for genType, config in pairs(generatorTypes) do
            for _, keyword in ipairs(config.keywords) do
                if idLower:find(keyword) then
                    return genType, config
                end
            end
        end
        return nil, nil
    end

    local function isGeneratorEnabled(genType, teamId)
        if genType == 'diamond' then
            return DiamondToggle.Enabled
        elseif genType == 'emerald' then
            return EmeraldToggle.Enabled
        elseif genType == 'teamgen' then
            if not TeamGenToggle.Enabled then return false end
            local myTeamId = getMyTeamId()
            if not myTeamId or not teamId then return TeamGenToggle.Enabled end
            if teamId == myTeamId then
                return ShowOwnTeamGen.Enabled
            else
                return ShowEnemyTeamGen.Enabled
            end
        end
        return false
    end

    local function getProperIcon(iconType)
        local icon = bedwars.getIcon({itemType = iconType}, true)
        if not icon or icon == "" then return nil end
        return icon
    end

    local function getTierText(generatorAdornee)
        if not generatorAdornee then return nil end
        if generatorAdornee.Name ~= 'GeneratorAdornee' then return nil end
        local reactTree = generatorAdornee:FindFirstChild('RoactTree')
        if not reactTree then return nil end
        local teamApp = reactTree:FindFirstChild('TeamOreGeneratorApp')
        if not teamApp then return nil end
        local globalGen = teamApp:FindFirstChild('GlobalOreGenerator')
        if globalGen then
            for _, child in pairs(globalGen:GetDescendants()) do
                if child:IsA('TextLabel') then
                    local text = child.Text
                    if text:find("Tier") or text:match("^[IVX]+$") or text == "0" then
                        return child
                    end
                end
            end
        end
        local teamGenMain = teamApp:FindFirstChild('TeamGenMain')
        if teamGenMain then
            for _, child in pairs(teamGenMain:GetDescendants()) do
                if child:IsA('TextLabel') then
                    local text = child.Text
                    if text:find("Tier") or text:match("^[IVX]+$") or text == "0" then
                        return child
                    end
                end
            end
        end
        return nil
    end

    local function extractTierLevel(tierText)
        if not tierText or tierText == "" then return "0" end
        if tierText == "0" then return "0" end
        local tierMatch = tierText:match("Tier%s+([IVX]+)")
        if tierMatch then return tierMatch end
        if tierText:match("^[IVX]+$") then return tierText end
        local numTier = tierText:match("Tier%s+(%d+)")
        if numTier then
            local num = tonumber(numTier)
            if num == 0 then return "0"
            elseif num == 1 then return "I"
            elseif num == 2 then return "II"
            elseif num == 3 then return "III"
            end
        end
        return "0"
    end

    local function getCountdownText(generatorAdornee)
        if not generatorAdornee then return nil end
        if generatorAdornee.Name ~= 'GeneratorAdornee' then return nil end
        local reactTree = generatorAdornee:FindFirstChild('RoactTree')
        if not reactTree then return nil end
        local teamApp = reactTree:FindFirstChild('TeamOreGeneratorApp')
        if not teamApp then return nil end
        local globalGen = teamApp:FindFirstChild('GlobalOreGenerator')
        if not globalGen then return nil end
        local countdown = globalGen:FindFirstChild('Countdown')
        if not countdown then return nil end
        local textLabel = countdown:FindFirstChild('Text')
        if not textLabel then
            if countdown:IsA('TextLabel') then return countdown end
            return nil
        end
        return textLabel
    end

    local function extractSecondsFromText(text)
        if not text or text == "" then return 0 end
        local seconds = text:match("%[(%d+)%]")
        if seconds then return tonumber(seconds) or 0 end
        local justNumber = text:match("(%d+)")
        if justNumber then return tonumber(justNumber) or 0 end
        return 0
    end

    local function getResourceCount(position, resourceType)
        local count = 0
        for _, drop in pairs(CollectionService:GetTagged('ItemDrop')) do
            if drop:FindFirstChild('Handle') then
                local dropName = drop.Name:lower()
                if dropName:find(resourceType) then
                    local dist = (drop.Handle.Position - position).Magnitude
                    if dist <= 10 then
                        local amount = drop:GetAttribute('Amount') or 1
                        count = count + amount
                    end
                end
            end
        end
        return count
    end

    local CompactGenerators = {}

    local function rebuildCompactGenerators()
        table.clear(CompactGenerators)
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj.Name == 'GeneratorAdornee' then
                local ok, generatorId = pcall(function() return obj:GetAttribute('Id') end)
                if ok and generatorId and type(generatorId) == 'string' and generatorId ~= '' then
                    local genType = getGeneratorType(generatorId)
                    if genType == 'diamond' or genType == 'emerald' then
                        table.insert(CompactGenerators, {obj = obj, genType = genType})
                    end
                end
            end
        end
    end

    local function updateCompactUI()
        if not GeneratorESP.Enabled or UIStyle.Value ~= 'Compact' then
            compactUI.Enabled = false
            return
        end
        compactUI.Enabled = true
        local bestDiamondTime = math.huge
        local bestEmeraldTime = math.huge
        for i = #CompactGenerators, 1, -1 do
            local countdownText
            local entry = CompactGenerators[i]
            if not entry.obj or not entry.obj.Parent then
                table.remove(CompactGenerators, i)
                continue
            end
            countdownText = getCountdownText(entry.obj)
            if countdownText and countdownText.Text then
                local timeLeft = extractSecondsFromText(countdownText.Text)
                if entry.genType == 'diamond' and timeLeft > 0 and timeLeft < bestDiamondTime then
                    bestDiamondTime = timeLeft
                elseif entry.genType == 'emerald' and timeLeft > 0 and timeLeft < bestEmeraldTime then
                    bestEmeraldTime = timeLeft
                end
            end
        end
        local showDiamond = CompactDiamondToggle and CompactDiamondToggle.Enabled
        local showEmerald = CompactEmeraldToggle and CompactEmeraldToggle.Enabled

        if not showDiamond and not showEmerald then
            compactUI.Enabled = false
            return
        end

        diamondFrame.Visible = showDiamond
        emeraldFrame.Visible = showEmerald

        if showDiamond then
            diamondFrame.Position = UDim2.new(0, 10, 0, 35)
        end
        if showEmerald then
            emeraldFrame.Position = UDim2.new(0, 10, 0, showDiamond and 65 or 35)
        end

        diamondTimes[1] = bestDiamondTime ~= math.huge and bestDiamondTime or 0
        emeraldTimes[1] = bestEmeraldTime ~= math.huge and bestEmeraldTime or 0
        if bestDiamondTime == math.huge then
            diamondTimer.Text = "00"
        else
            diamondTimer.Text = string.format("%02d", bestDiamondTime)
            if bestDiamondTime <= 5 then
                diamondTimer.TextColor3 = Color3.fromRGB(255, 50, 50)
            elseif bestDiamondTime <= 10 then
                diamondTimer.TextColor3 = Color3.fromRGB(255, 165, 0)
            else
                diamondTimer.TextColor3 = Color3.fromRGB(85, 200, 255)
            end
        end
        if bestEmeraldTime == math.huge then
            emeraldTimer.Text = "00"
        else
            emeraldTimer.Text = string.format("%02d", bestEmeraldTime)
            if bestEmeraldTime <= 5 then
                emeraldTimer.TextColor3 = Color3.fromRGB(255, 50, 50)
            elseif bestEmeraldTime <= 10 then
                emeraldTimer.TextColor3 = Color3.fromRGB(255, 165, 0)
            else
                emeraldTimer.TextColor3 = Color3.fromRGB(0, 255, 100)
            end
        end
    end

    local function clearAllESP()
        Folder:ClearAllChildren()
        table.clear(Reference)
        compactUI.Enabled = false
    end

    local function createESP(generatorAdornee, genType, config, position, teamId)
        if not isGeneratorEnabled(genType, teamId) then return end
        if Reference[generatorAdornee] then return end

        if UIStyle.Value == 'Compact' then
            Reference[generatorAdornee] = {
                genType = genType,
                position = position,
                teamId = teamId,
                isTeamGen = config.isTeamGen
            }
            return
        end

        local displayColor = config.color
        local teamName = nil
        if config.isTeamGen and teamId and teamColors[teamId] then
            displayColor = teamColors[teamId].color
            teamName = teamColors[teamId].name
        end

        local billboard = Instance.new('BillboardGui')
        billboard.Parent = Folder
        billboard.Name = 'generator-esp-' .. genType
        billboard.AlwaysOnTop = true
        billboard.ClipsDescendants = false
        billboard.Adornee = generatorAdornee

        if config.isTeamGen then
            billboard.Size = UDim2.fromOffset(180, 55)
            billboard.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
        else
            billboard.Size = UDim2.fromOffset(80, 30)
            billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
        end

        local blur = addBlur(billboard)
        blur.Visible = true

        if config.isTeamGen and teamName then
            local dot = Instance.new('Frame')
            dot.Name = 'TeamDot'
            dot.Parent = billboard
            dot.Size = UDim2.fromOffset(8, 8)
            dot.Position = UDim2.new(0, 10, 0, 5)
            dot.BackgroundColor3 = displayColor
            dot.BorderSizePixel = 0
            local dotCorner = Instance.new('UICorner')
            dotCorner.CornerRadius = UDim.new(1, 0)
            dotCorner.Parent = dot

            local teamLabel = Instance.new('TextLabel')
            teamLabel.Name = 'TeamLabel'
            teamLabel.Parent = billboard
            teamLabel.BackgroundTransparency = 1
            teamLabel.Size = UDim2.new(1, 0, 0, 18)
            teamLabel.Position = UDim2.new(0, 0, 0, 0)
            teamLabel.Text = teamName
            teamLabel.TextColor3 = displayColor
            teamLabel.TextSize = 13
            teamLabel.Font = Enum.Font.GothamBold
            teamLabel.TextStrokeTransparency = 0.4
            teamLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            teamLabel.TextXAlignment = Enum.TextXAlignment.Center
        end

        local frame = Instance.new('Frame')
        frame.Size = config.isTeamGen and UDim2.new(1, 0, 0, 35) or UDim2.fromScale(1, 1)
        frame.Position = config.isTeamGen and UDim2.new(0, 0, 0, 20) or UDim2.new(0, 0, 0, 0)
        frame.BackgroundColor3 = Color3.new(0, 0, 0)
        frame.BackgroundTransparency = 0.3
        frame.BorderSizePixel = 0
        frame.Parent = billboard

        if config.isTeamGen and teamId and teamColors[teamId] then
            local stripe = Instance.new('Frame')
            stripe.Name = 'TeamStripe'
            stripe.Parent = frame
            stripe.Size = UDim2.new(0, 3, 1, 0)
            stripe.Position = UDim2.new(0, 0, 0, 0)
            stripe.BackgroundColor3 = displayColor
            stripe.BorderSizePixel = 0
            local stripeCorner = Instance.new('UICorner')
            stripeCorner.CornerRadius = UDim.new(0, 3)
            stripeCorner.Parent = stripe
        end

        local uicorner2 = Instance.new('UICorner')
        uicorner2.CornerRadius = UDim.new(0, 6)
        uicorner2.Parent = frame

        if config.isTeamGen then
            local tierLabel = Instance.new('TextLabel')
            tierLabel.Name = 'Tier'
            tierLabel.Size = UDim2.new(0, 25, 1, 0)
            tierLabel.Position = UDim2.new(0, 8, 0, 0)
            tierLabel.BackgroundTransparency = 1
            tierLabel.Text = "0"
            tierLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
            tierLabel.TextSize = 16
            tierLabel.Font = Enum.Font.GothamBold
            tierLabel.TextStrokeTransparency = 0.5
            tierLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            tierLabel.Parent = frame

            local resources = {
                {name = 'iron',    color = Color3.fromRGB(200, 200, 200), icon = 'iron',    xOffset = 35},
                {name = 'diamond', color = Color3.fromRGB(85, 200, 255),  icon = 'diamond', xOffset = 85},
                {name = 'emerald', color = Color3.fromRGB(0, 255, 100),   icon = 'emerald', xOffset = 135}
            }

            local resourceLabels = {}
            for _, resource in ipairs(resources) do
                local iconImage = getProperIcon(resource.icon)
                if iconImage then
                    local image = Instance.new('ImageLabel')
                    image.Size = UDim2.fromOffset(18, 18)
                    image.Position = UDim2.new(0, resource.xOffset, 0.5, 0)
                    image.AnchorPoint = Vector2.new(0, 0.5)
                    image.BackgroundTransparency = 1
                    image.Image = iconImage
                    image.Parent = frame
                end
                local countLabel = Instance.new('TextLabel')
                countLabel.Name = resource.name .. '_count'
                countLabel.Size = UDim2.new(0, 25, 1, 0)
                countLabel.Position = UDim2.new(0, resource.xOffset + 20, 0, 0)
                countLabel.BackgroundTransparency = 1
                countLabel.Text = "0"
                countLabel.TextColor3 = resource.color
                countLabel.TextSize = 16
                countLabel.Font = Enum.Font.GothamBold
                countLabel.TextStrokeTransparency = 0.5
                countLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
                countLabel.TextXAlignment = Enum.TextXAlignment.Left
                countLabel.Parent = frame
                resourceLabels[resource.name] = countLabel
            end

            Reference[generatorAdornee] = {
                billboard = billboard,
                tierLabel = tierLabel,
                ironLabel = resourceLabels.iron,
                diamondLabel = resourceLabels.diamond,
                emeraldLabel = resourceLabels.emerald,
                genType = genType,
                position = position,
                teamId = teamId,
                isTeamGen = true
            }
        else
            local iconImage = getProperIcon(config.icon)
            if iconImage then
                local image = Instance.new('ImageLabel')
                image.Size = UDim2.fromOffset(20, 20)
                image.Position = UDim2.new(0, 5, 0.5, 0)
                image.AnchorPoint = Vector2.new(0, 0.5)
                image.BackgroundTransparency = 1
                image.Image = iconImage
                image.Parent = frame
            end
            local timerLabel = Instance.new('TextLabel')
            timerLabel.Name = 'Timer'
            timerLabel.Size = UDim2.new(0, 30, 1, 0)
            timerLabel.Position = UDim2.new(0.5, 0, 0, 0)
            timerLabel.AnchorPoint = Vector2.new(0.5, 0)
            timerLabel.BackgroundTransparency = 1
            timerLabel.Text = "00"
            timerLabel.TextColor3 = displayColor
            timerLabel.TextSize = 18
            timerLabel.Font = Enum.Font.GothamBold
            timerLabel.TextStrokeTransparency = 0.5
            timerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            timerLabel.Parent = frame
            local amountLabel = Instance.new('TextLabel')
            amountLabel.Name = 'Amount'
            amountLabel.Size = UDim2.new(0, 20, 1, 0)
            amountLabel.Position = UDim2.new(1, -20, 0, 0)
            amountLabel.BackgroundTransparency = 1
            amountLabel.Text = "0"
            amountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            amountLabel.TextSize = 16
            amountLabel.Font = Enum.Font.GothamBold
            amountLabel.TextStrokeTransparency = 0.5
            amountLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            amountLabel.Parent = frame
            Reference[generatorAdornee] = {
                billboard = billboard,
                timerLabel = timerLabel,
                amountLabel = amountLabel,
                genType = genType,
                position = position,
                teamId = teamId,
                isTeamGen = false
            }
        end
    end

    local function updateESP(generatorAdornee)
        local ref = Reference[generatorAdornee]
        if not ref then return end
        if UIStyle.Value == 'Compact' then return end

        if ref.isTeamGen then
            if ref.tierLabel then
                local tierTextLabel = getTierText(generatorAdornee)
                if tierTextLabel and tierTextLabel.Text then
                    ref.tierLabel.Text = extractTierLevel(tierTextLabel.Text)
                else
                    ref.tierLabel.Text = "0"
                end
            end
            if ref.ironLabel then
                ref.ironLabel.Text = tostring(getResourceCount(ref.position, 'iron'))
            end
            if ref.diamondLabel then
                ref.diamondLabel.Text = tostring(getResourceCount(ref.position, 'diamond'))
            end
            if ref.emeraldLabel then
                ref.emeraldLabel.Text = tostring(getResourceCount(ref.position, 'emerald'))
            end
        else
            local countdownText = getCountdownText(generatorAdornee)
            if countdownText and countdownText.Text then
                local timeLeft = extractSecondsFromText(countdownText.Text)
                if ref.timerLabel then
                    ref.timerLabel.Text = string.format("%02d", timeLeft)
                    if timeLeft <= 5 then
                        ref.timerLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
                    elseif timeLeft <= 10 then
                        ref.timerLabel.TextColor3 = Color3.fromRGB(255, 165, 0)
                    else
                        ref.timerLabel.TextColor3 = generatorTypes[ref.genType].color
                    end
                end
            else
                if ref.timerLabel then
                    ref.timerLabel.Text = "00"
                    ref.timerLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
                end
            end
            if ref.amountLabel then
                ref.amountLabel.Text = tostring(getResourceCount(ref.position, ref.genType))
            end
        end
    end

    local function processGeneratorAdornee(obj)
        if obj.Name ~= 'GeneratorAdornee' then return end
        local ok, generatorId = pcall(function() return obj:GetAttribute('Id') end)
        if not ok then return end
        if generatorId == nil then return end
        if type(generatorId) ~= 'string' then return end
        if generatorId == '' then return end

        local position = obj:GetPivot().Position
        local genType, config = getGeneratorType(generatorId)
        if not genType or not config then return end

        local teamId = getGeneratorTeamId(generatorId)
        if isGeneratorEnabled(genType, teamId) then
            createESP(obj, genType, config, position, teamId)
        end
    end

    local function findAllGenerators()
        for _, obj in pairs(workspace:GetDescendants()) do
            pcall(processGeneratorAdornee, obj)
        end
    end

    local function refreshESP()
        clearAllESP()
        if GeneratorESP.Enabled then
            findAllGenerators()
        end
    end

    local updateTimer = 0

    GeneratorESP = vape.Categories.Render:CreateModule({
        Name = 'GeneratorESP',
        Function = function(callback)
            if callback then
                findAllGenerators()
                rebuildCompactGenerators()

                GeneratorESP:Clean(workspace.DescendantAdded:Connect(function(obj)
                    if not GeneratorESP.Enabled then return end
                    task.wait(0.2)
                    pcall(processGeneratorAdornee, obj)
                    if obj.Name == 'GeneratorAdornee' then
                        rebuildCompactGenerators()
                    end
                end))

                GeneratorESP:Clean(runService.Heartbeat:Connect(function(dt)
                    if not GeneratorESP.Enabled then return end
                    updateTimer = updateTimer + dt
                    if updateTimer < 0.2 then return end
                    updateTimer = 0
                    for generatorAdornee, ref in pairs(Reference) do
                        if generatorAdornee and generatorAdornee.Parent then
                            updateESP(generatorAdornee)
                        else
                            if ref.billboard then ref.billboard:Destroy() end
                            Reference[generatorAdornee] = nil
                        end
                    end
                    updateCompactUI()
                end))

                GeneratorESP:Clean(workspace.DescendantRemoving:Connect(function(obj)
                    if not GeneratorESP.Enabled then return end
                    if Reference[obj] then
                        if Reference[obj].billboard then Reference[obj].billboard:Destroy() end
                        Reference[obj] = nil
                    end
                end))
            else
                clearAllESP()
            end
        end,
        Tooltip = 'ESP for generators showing timer and item counts'
    })

    UIStyle = GeneratorESP:CreateDropdown({
        Name = 'UI Style',
        List = {'Original', 'Compact'},
        Default = 'Original',
        Function = function(val)
            local isOriginal = val == 'Original'
            if DiamondToggle then DiamondToggle.Object.Visible = isOriginal end
            if EmeraldToggle then EmeraldToggle.Object.Visible = isOriginal end
            if TeamGenToggle then TeamGenToggle.Object.Visible = isOriginal end
            if ShowOwnTeamGen then ShowOwnTeamGen.Object.Visible = isOriginal and TeamGenToggle.Enabled end
            if ShowEnemyTeamGen then ShowEnemyTeamGen.Object.Visible = isOriginal and TeamGenToggle.Enabled end
            if CompactDiamondToggle then CompactDiamondToggle.Object.Visible = not isOriginal end
            if CompactEmeraldToggle then CompactEmeraldToggle.Object.Visible = not isOriginal end
            refreshESP()
        end,
        Tooltip = 'Choose between original billboard ESP or compact side UI'
    })

    DiamondToggle = GeneratorESP:CreateToggle({
        Name = 'Diamond',
        Function = function() refreshESP() end,
        Default = false,
        Visible = true
    })

    EmeraldToggle = GeneratorESP:CreateToggle({
        Name = 'Emerald',
        Function = function() refreshESP() end,
        Default = false,
        Visible = true
    })

    CompactDiamondToggle = GeneratorESP:CreateToggle({
        Name = 'Compact Diamond',
        Default = false,
        Visible = false,
        Function = function()
            refreshESP()
        end
    })

    CompactEmeraldToggle = GeneratorESP:CreateToggle({
        Name = 'Compact Emerald',
        Default = false,
        Visible = false,
        Function = function()
            refreshESP()
        end
    })

    TeamGenToggle = GeneratorESP:CreateToggle({
        Name = 'Team Generators',
        Function = function(callback)
            if ShowOwnTeamGen then ShowOwnTeamGen.Object.Visible = callback end
            if ShowEnemyTeamGen then ShowEnemyTeamGen.Object.Visible = callback end
            refreshESP()
        end,
        Default = true
    })

    ShowOwnTeamGen = GeneratorESP:CreateToggle({
        Name = 'Show Own Team',
        Function = function() refreshESP() end,
        Default = false,
        Visible = true
    })

    ShowEnemyTeamGen = GeneratorESP:CreateToggle({
        Name = 'Show Enemy Teams',
        Function = function() refreshESP() end,
        Default = true,
        Visible = true
    })
end)


run(function()
    local Health

    Health = vape.Categories.Render:CreateModule({
    	Name = 'Health',
    	Function = function(callback)
    		if callback then
    			local label = Instance.new('TextLabel')
    			label.Size = UDim2.fromOffset(100, 20)
    			label.Position = UDim2.new(0.5, 6, 0.5, 30)
    			label.BackgroundTransparency = 1
    			label.AnchorPoint = Vector2.new(0.5, 0)
    			label.Text = entitylib.isAlive and math.round(lplr.Character:GetAttribute('Health')) .. ' ❤️' or ''
    			label.TextColor3 = entitylib.isAlive and Color3.fromHSV((lplr.Character:GetAttribute('Health') / lplr.Character:GetAttribute('MaxHealth')) / 2.8, 0.86, 1) or Color3.new()
    			label.TextSize = 18
    			label.Font = Enum.Font.Arial
    			label.Parent = vape.gui
    			Health:Clean(label)
    			Health:Clean(vapeEvents.AttributeChanged.Event:Connect(function()
    				label.Text = entitylib.isAlive and math.round(lplr.Character:GetAttribute('Health')) .. ' ❤️' or ''
    				label.TextColor3 = entitylib.isAlive and Color3.fromHSV((lplr.Character:GetAttribute('Health') / lplr.Character:GetAttribute('MaxHealth')) / 2.8, 0.86, 1) or Color3.new()
    			end))
    		end
    	end,
    	Tooltip = 'Displays your health in the center of your screen.'
    })
end)

run(function()
    local ItemESP
    local Background
    local WhitelistOnly
    local Whitelist = {ListEnabled = {}, Object = nil}

    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui

    local Reference = {}

    local function Added(ent)
    	local Name = bedwars.ItemMeta[ent.Name] and bedwars.ItemMeta[ent.Name].displayName or ent.Name
    	if WhitelistOnly.Enabled and not table.find(Whitelist.ListEnabled, Name:lower()) then
    		return
    	end

    	local card = Instance.new('Frame')
    	card.Name = ent.Name
    	card.AnchorPoint = Vector2.new(0.5, 1)
    	card.BackgroundColor3 = Color3.new()
    	card.BackgroundTransparency = Background.Enabled and 0.35 or 1
    	card.BorderSizePixel = 0
    	card.AutomaticSize = Enum.AutomaticSize.XY
    	card.Visible = false
    	local cardCorner = Instance.new('UICorner')
    	cardCorner.CornerRadius = UDim.new(0, 4)
    	cardCorner.Parent = card
    	local cardPadding = Instance.new('UIPadding')
    	cardPadding.PaddingLeft = UDim.new(0, 6)
    	cardPadding.PaddingRight = UDim.new(0, 6)
    	cardPadding.PaddingTop = UDim.new(0, 3)
    	cardPadding.PaddingBottom = UDim.new(0, 3)
    	cardPadding.Parent = card
    	local cardLayout = Instance.new('UIListLayout')
    	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    	cardLayout.Padding = UDim.new(0, 1)
    	cardLayout.Parent = card

    	local title = Instance.new('TextLabel')
    	title.Name = 'Title'
    	title.AutomaticSize = Enum.AutomaticSize.XY
    	title.BackgroundTransparency = 1
    	title.Font = Enum.Font.GothamBold
    	title.TextSize = 9
    	title.TextColor3 = Color3.new(1, 1, 1)
    	title.Text = Name
    	title.LayoutOrder = 1
    	title.Parent = card

    	local info = Instance.new('TextLabel')
    	info.Name = 'Info'
    	info.AutomaticSize = Enum.AutomaticSize.XY
    	info.BackgroundTransparency = 1
    	info.Font = Enum.Font.GothamBold
    	info.TextSize = 8
    	info.TextColor3 = Color3.fromRGB(200, 200, 200)
    	info.RichText = true
    	info.LayoutOrder = 2
    	info.Parent = card

    	card.Parent = Folder
    	Reference[ent] = card
    end

    local function Removing(ent)
    	if Reference[ent] then
    		Reference[ent]:Destroy()
    		Reference[ent] = nil
    	end
    end

    ItemESP = vape.Categories.Render:CreateModule({
    	Name = 'Item ESP',
    	Function = function(call)
    		if call then
    			ItemESP:Clean(collectionService:GetInstanceAddedSignal('ItemDrop'):Connect(Added))
    			ItemESP:Clean(collectionService:GetInstanceRemovedSignal('ItemDrop'):Connect(Removing))
    			ItemESP:Clean(runService.PreRender:Connect(function()
    				for ent, card in Reference do
    					local headPos, headVis
    					if not ent.Parent then continue end
    					headPos, headVis = gameCamera:WorldToViewportPoint(ent.Position + Vector3.new(0, 1, 0))
    					card.Visible = headVis
    					if headVis then
    						local amt = ent:GetAttribute('Amount')
    						local dist = entitylib.isAlive and math.floor((entitylib.character.RootPart.Position - ent.Position).Magnitude) or 0
    						card.Info.Text = (amt >= 2 and 'x' .. amt .. '  ' or '') .. '<font color="rgb(130,130,130)">' .. dist .. 'm</font>'
    						card.Position = UDim2.fromOffset(headPos.X, headPos.Y)
    					end
    				end
    			end))

    			for _, v in collectionService:GetTagged('ItemDrop') do
    				Added(v)
    			end
    		else
    			for i in Reference do
    				Removing(i)
    			end
    		end
    	end,
    	Tooltip = 'Renders tags dropped items'
    })
    Background = ItemESP:CreateToggle({
    	Name = 'Background',
    	Function = function(callback)
    		for _, card in Reference do
    			card.BackgroundTransparency = callback and 0.35 or 1
    		end
    	end,
    	Default = true
    })
    ItemESP:CreateToggle({
    	Name = 'Group items',
    	Tooltip = 'Group items into easier to read tags'
    })
    WhitelistOnly = ItemESP:CreateToggle({
    	Name = 'Whitelist Only',
    	Tooltip = 'Only renders whitelisted items',
    	Function = function(call)
    		if Whitelist.Object then
    			Whitelist.Object.Visible = call

    			if ItemESP.Enabled then
    				ItemESP:Toggle()
    				ItemESP:Toggle()
    			end
    		end
    	end
    })
    Whitelist = ItemESP:CreateTextList({
    	Name = 'Allowed items',
    	Visible = false,
    	Darker = true,
    	Function = function()
    		if ItemESP.Enabled then
    			ItemESP:Toggle()
    			ItemESP:Toggle()
    		end
    	end
    })
end)

run(function()
    local KitDisplay

    local function getKitMeta(player)
    	local kit = player:GetAttribute('PlayingAsKits') or player:GetAttribute('PlayingAsKit') or 'none'
    	return bedwars.BedwarsKitMeta[kit] or bedwars.BedwarsKitMeta.none
    end

    local function getPlayerFromDraft(render, name)
    	local id = render and render:match('id=(%d+)')
    	if id then
    		local player = playersService:GetPlayerByUserId(tonumber(id))
    		if player then
    			return player
    		end
    	end

    	for _, v in playersService:GetPlayers() do
    		if render and render:find('id=' .. v.UserId, 1, true) then
    			return v
    		end

    		if name and (v.Name == name or v.DisplayName == name or v:GetAttribute('DisguiseDisplayName') == name) then
    			return v
    		end

    		local displayName
    		pcall(function()
    			displayName = bedwars.StreamerModeController:getDisplayName(v)
    		end)
    		if name and displayName == name then
    			return v
    		end
    	end
    	return nil
    end

    local waitForChild = function(start, ...)
    	local parent = start
    	for _, v in {...} do
    		parent = parent and parent:WaitForChild(v, 5)
    		if not parent then
    			break
    		end
    	end
    	return parent
    end

    local function getPlayerName(card)
    	local textbar = card and card:FindFirstChild('TextBackgroundBar')
    	local label = textbar and textbar:FindFirstChild('PlayerName') or card and card:FindFirstChild('PlayerName', true)
    	return label and label.Text or ''
    end

    local function getDraftCard(container)
    	if not container then
    		return
    	end
    	return container.Name == 'MatchDraftPlayerCard' and container or container:FindFirstChild('MatchDraftPlayerCard', true)
    end

    local function callback5v5(v, plr)
    	if not v then
    		return
    	end
    	local render = v:FindFirstChild('PlayerRender', true)
    	local player = plr or getPlayerFromDraft(render and render.Image or '', getPlayerName(v))

    	if player then
    		local kitImage = getKitMeta(player)
    		local roact = v:FindFirstChild('KitImage')

    		if not roact then
    			roact = Instance.new('ImageLabel', v)
    			roact.BackgroundTransparency = 1
    			roact.AnchorPoint = Vector2.new(1, 0.5)
    			roact.Position = UDim2.fromScale(1.05, 0.5)
    			roact.Name = 'KitImage'
    			roact.Size = UDim2.fromScale(1.5, 1.5)
    			roact.ZIndex = 1
    			roact.ImageTransparency = 0.4
    			roact.SliceCenter = Rect.new(0, 0, 0, 0)
    			roact.SliceScale = 1
    			roact.ScaleType = Enum.ScaleType.Crop

    			KitDisplay:Clean(roact)

    			local ratio = Instance.new('UIAspectRatioConstraint', roact)
    			ratio.Name = '1'
    			ratio.AspectRatio = 1
    			ratio.AspectType = Enum.AspectType.FitWithinMaxSize
    			ratio.DominantAxis = Enum.DominantAxis.Width
    		end

    		roact.Image = kitImage.renderImage
    		roact.Position = UDim2.fromScale(1.05, 0)
    		tweenService:Create(roact, TweenInfo.new(0.2, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {Position = UDim2.fromScale(1.05, 0.4)}):Play()

    		local function update()
    			kitImage = getKitMeta(player)
    			roact.Image = kitImage.renderImage
    		end

    		KitDisplay:Clean(player:GetAttributeChangedSignal('PlayingAsKits'):Connect(update))
    		KitDisplay:Clean(player:GetAttributeChangedSignal('PlayingAsKit'):Connect(update))
    	end
    end

    local function callbacksquad(v)
    	if not v then
    		return
    	end
    	local render = v:FindFirstChild('PlayerRender', true)
    	local player = render and getPlayerFromDraft(render.Image, '') or nil

    	if player then
    		local kitImage = getKitMeta(player)
    		local Roact = v:FindFirstChild('Kitcvrender')

    		if not Roact then
    			local base = v:FindFirstChild('3') or v:WaitForChild('3', 5)
    			if not base then
    				return
    			end
    			Roact = base:Clone()
    			Roact.Parent = v
    			Roact.Name = 'Kitcvrender'
    			KitDisplay:Clean(Roact)
    		end

    		Roact.Image = kitImage.renderImage

    		KitDisplay:Clean(render:GetPropertyChangedSignal('Image'):Connect(function()
    			local newplayer = getPlayerFromDraft(render.Image, '')
    			if newplayer then
    				player = newplayer
    				kitImage = getKitMeta(player)
    				Roact.Image = kitImage.renderImage
    			end
    		end))

    		local function update()
    			kitImage = getKitMeta(player)
    			Roact.Image = kitImage.renderImage
    		end

    		KitDisplay:Clean(player:GetAttributeChangedSignal('PlayingAsKits'):Connect(update))
    		KitDisplay:Clean(player:GetAttributeChangedSignal('PlayingAsKit'):Connect(update))
    	end
    end

    local function setup5v5(DraftApp)
    	local Background = DraftApp:FindFirstChild('DraftAppBackground')
    	local BodyContainer = Background and Background:FindFirstChild('1') and Background['1']:FindFirstChild('BodyContainer')
    	local hooked = false

    	for i = 1, 2 do
    		local dtc = BodyContainer and BodyContainer:FindFirstChild('Team' .. i .. 'Column')
    		if dtc then
    			hooked = true
    			KitDisplay:Clean(dtc.ChildAdded:Connect(function(child)
    				task.delay(0.2, function()
    					if KitDisplay.Enabled then
    						callback5v5(getDraftCard(child))
    					end
    				end)
    			end))

    			for _, v in dtc:GetChildren() do
    				if v:IsA('Frame') then
    					callback5v5(getDraftCard(v))
    				end
    			end
    		end
    	end

    	if not hooked then
    		for _, label in DraftApp:GetDescendants() do
    			if label:IsA('TextLabel') and label.Name == 'PlayerName' then
    				local container = label.Parent
    				for _ = 1, 3 do
    					container = container and container.Parent
    				end
    				if container then
    					callback5v5(getDraftCard(container))
    				end
    			end
    		end

    		KitDisplay:Clean(DraftApp.DescendantAdded:Connect(function(child)
    			if child:IsA('TextLabel') and child.Name == 'PlayerName' then
    				task.delay(0.2, function()
    					local container = child.Parent
    					for _ = 1, 3 do
    						container = container and container.Parent
    					end
    					if KitDisplay.Enabled and container then
    						callback5v5(getDraftCard(container))
    					end
    				end)
    			end
    		end))
    	end

    	return hooked
    end

    local function setupSquad(DraftApp)
    	local Background = DraftApp:FindFirstChild('DraftAppBackground')
    	local BodyContainer = Background and Background:FindFirstChild('1') and Background['1']:FindFirstChild('BodyContainer')
    	local TeamsColumn = BodyContainer and BodyContainer:FindFirstChild('TeamsColumn')
    	if not TeamsColumn then
    		return
    	end

    	for _, v: Instance in TeamsColumn:GetChildren() do
    		if v:IsA('Frame') then
    			local plrframe = waitForChild(v, '1', '2', '4')
    			if plrframe then
    				for _, plr in plrframe:GetChildren() do
    					callbacksquad(plr)
    				end

    				KitDisplay:Clean(plrframe.ChildAdded:Connect(function(plr)
    					KitDisplay:Toggle()
    					KitDisplay:Toggle()
    				end))
    			end
    		end
    	end
    end

    KitDisplay = vape.Categories.Render:CreateModule({
    	Name = 'Kit Display',
    	Function = function(call)
    		if call then
    			local DraftApp = lplr.PlayerGui:WaitForChild('MatchDraftApp', 9e9)
    			setup5v5(DraftApp)
    			setupSquad(DraftApp)
    		end
    	end,
    	Tooltip = 'Allows you to see the other opponent kits'
    })
end)

run(function()
    local KitESP
    local Background
    local Scale
    local Reference = {}
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui

    local ESPKits = {
    	alchemist = {'alchemist_ingedients', 'wild_flower'},
    	beekeeper = {'bee', 'bee'},
    	bigman = {'treeOrb', 'natures_essence_1'},
    	ghost_catcher = {'ghost', 'ghost_orb'},
    	metal_detector = {'hidden-metal', 'iron'},
    	sheep_herder = {'SheepModel', 'purple_hay_bale'},
    	sorcerer = {'alchemy_crystal', 'wild_flower'},
    	star_collector = {'stars', 'crit_star'},
    }

    local function Added(v, icon)
    	local card = Instance.new('Frame')
    	card.Name = icon
    	card.AnchorPoint = Vector2.new(0.5, 1)
    	card.BackgroundColor3 = Color3.new()
    	card.BackgroundTransparency = Background.Enabled and 0.35 or 1
    	card.BorderSizePixel = 0
    	card.AutomaticSize = Enum.AutomaticSize.XY
    	card.Visible = false
    	local cardCorner = Instance.new('UICorner')
    	cardCorner.CornerRadius = UDim.new(0, 4)
    	cardCorner.Parent = card
    	local cardPadding = Instance.new('UIPadding')
    	cardPadding.PaddingLeft = UDim.new(0, 6)
    	cardPadding.PaddingRight = UDim.new(0, 6)
    	cardPadding.PaddingTop = UDim.new(0, 3)
    	cardPadding.PaddingBottom = UDim.new(0, 3)
    	cardPadding.Parent = card
    	local cardLayout = Instance.new('UIListLayout')
    	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    	cardLayout.FillDirection = Enum.FillDirection.Horizontal
    	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    	cardLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    	cardLayout.Padding = UDim.new(0, 4)
    	cardLayout.Parent = card

    	local s = Scale and Scale.Value or 1
    	local img = Instance.new('ImageLabel')
    	img.Name = 'Icon'
    	img.Size = UDim2.fromOffset(math.floor(12 * s), math.floor(12 * s))
    	img.BackgroundTransparency = 1
    	img.Image = bedwars.getIcon({ itemType = icon }, true)
    	img.LayoutOrder = 1
    	img.Parent = card

    	local info = Instance.new('TextLabel')
    	info.Name = 'Info'
    	info.AutomaticSize = Enum.AutomaticSize.XY
    	info.BackgroundTransparency = 1
    	info.Font = Enum.Font.GothamBold
    	info.TextSize = math.floor(9 * s)
    	info.TextColor3 = Color3.fromRGB(200, 200, 200)
    	info.RichText = true
    	info.LayoutOrder = 2
    	info.Parent = card

    	card.Parent = Folder
    	Reference[v] = card
    end

    local function addKit(tag, icon)
    	KitESP:Clean(collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
    		Added(v.PrimaryPart, icon)
    	end))
    	KitESP:Clean(collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
    		if Reference[v.PrimaryPart] then
    			Reference[v.PrimaryPart]:Destroy()
    			Reference[v.PrimaryPart] = nil
    		end
    	end))
    	for _, v in collectionService:GetTagged(tag) do
    		Added(v.PrimaryPart, icon)
    	end
    end

    KitESP = vape.Categories.Render:CreateModule({
    	Name = 'Kit ESP',
    	Function = function(callback)
    		if callback then
    			repeat
    				task.wait()
    			until store.equippedKit ~= '' or not KitESP.Enabled
    			local kit = KitESP.Enabled and ESPKits[store.equippedKit] or nil
    			if kit then
    				addKit(kit[1], kit[2])
    			end
    			KitESP:Clean(runService.PreRender:Connect(function()
    				for obj, card in Reference do
    					local headPos, headVis = gameCamera:WorldToViewportPoint(obj.Position + Vector3.new(0, 2, 0))
    					card.Visible = headVis
    					if headVis then
    						local dist = entitylib.isAlive and math.floor((entitylib.character.RootPart.Position - obj.Position).Magnitude) or 0
    						card.Info.Text = '<font color="rgb(130,130,130)">' .. dist .. 'm</font>'
    						card.Position = UDim2.fromOffset(headPos.X, headPos.Y)
    					end
    				end
    			end))
    		else
    			Folder:ClearAllChildren()
    			table.clear(Reference)
    		end
    	end,
    	Tooltip = 'ESP for certain kit related objects'
    })
    Background = KitESP:CreateToggle({
    	Name = 'Background',
    	Function = function(callback)
    		for _, card in Reference do
    			card.BackgroundTransparency = callback and 0.35 or 1
    		end
    	end,
    	Default = true
    })
    Scale = KitESP:CreateSlider({
    	Name = 'Scale',
    	Default = 1,
    	Min = 0.5,
    	Max = 2,
    	Decimal = 10,
    	Function = function(val)
    		for _, card in Reference do
    			local icon = card:FindFirstChild('Icon')
    			if icon then
    				icon.Size = UDim2.fromOffset(math.floor(12 * val), math.floor(12 * val))
    			end
    			local info = card:FindFirstChild('Info')
    			if info then
    				info.TextSize = math.floor(9 * val)
    			end
    		end
    	end
    })
end)

run(function()
    local NameTags
    local Targets
    local Color
    local Background
    local DisplayName
    local Health
    local Distance
    local Equipment
    local Rank
    local Enchant
    local DrawingToggle
    local Scale
    local FontOption
    local Teammates
    local DistanceCheck
    local DistanceLimit
    local Strings, Sizes, Reference = {}, {}, {}
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui
    local methodused

    local Added = {
    	Normal = function(ent)
    		if not Targets.Players.Enabled and ent.Player then
    			return
    		end
    		if not Targets.NPCs.Enabled and ent.NPC then
    			return
    		end
    		if Teammates.Enabled and not ent.Targetable and not ent.Friend then
    			return
    		end

    		local nametag = Instance.new('TextLabel')
    		Strings[ent] = ent.Player
    				and whitelist:tag(ent.Player, true, true) .. (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name)
    			or ent.Character.Name

    		if Health.Enabled then
    			local healthColor = Color3.fromHSV(math.clamp(ent.Health / ent.MaxHealth, 0, 1) / 2.5, 0.89, 0.75)
    			Strings[ent] = Strings[ent]
    				.. ' <font color="rgb('
    				.. tostring(math.floor(healthColor.R * 255))
    				.. ','
    				.. tostring(math.floor(healthColor.G * 255))
    				.. ','
    				.. tostring(math.floor(healthColor.B * 255))
    				.. ')">'
    				.. math.round(ent.Health)
    				.. '</font>'
    		end

    		if Distance.Enabled then
    			Strings[ent] = '<font color="rgb(85, 255, 85)">[</font><font color="rgb(255, 255, 255)">%s</font><font color="rgb(85, 255, 85)">]</font> '
    				.. Strings[ent]
    		end

    		if Equipment.Enabled then
    			for i, v in {'Hand', 'Helmet', 'Chestplate', 'Boots', 'Kit'} do
    				local Icon = Instance.new('ImageLabel')
    				Icon.Name = v
    				Icon.Size = UDim2.fromOffset(30, 30)
    				Icon.Position = UDim2.fromOffset(-60 + (i * 30), -30)
    				Icon.BackgroundTransparency = 1
    				Icon.Image = ''
    				Icon.Parent = nametag
    			end
    		end

    		nametag.TextSize = 14 * Scale.Value
    		nametag.FontFace = FontOption.Value
    		local size =
    			getfontsize(removeTags(Strings[ent]), nametag.TextSize, nametag.FontFace, Vector2.new(100000, 100000))
    		nametag.Name = ent.Player and ent.Player.Name or ent.Character.Name
    		nametag.Size = UDim2.fromOffset(size.X + 8, size.Y + 7)
    		nametag.AnchorPoint = Vector2.new(0.5, 1)
    		nametag.BackgroundColor3 = Color3.new()
    		nametag.BackgroundTransparency = Background.Value
    		nametag.BorderSizePixel = 0
    		nametag.Visible = false
    		nametag.Text = Strings[ent]
    		nametag.TextColor3 = entitylib.getEntityColor(ent) or Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
    		nametag.RichText = true
    		nametag.Parent = Folder
    		task.spawn(function()
    			if Rank.Enabled and ent.Player then
    				local Icon = Instance.new('ImageLabel')
    				Icon.Name = 'RankIcon'
    				Icon.Size = UDim2.fromOffset(30, 30)
    				Icon.Position = UDim2.fromOffset(size.X + 10, -4)
    				Icon.BackgroundTransparency = 1
    				Icon.Image = store.rank[ent.Player]:async() and bedwars.RankMeta[store.rank[ent.Player]:async()].image
    					or ''
    				Icon.Parent = nametag
    			end
    		end)
    		task.spawn(function()
    			if Enchant.Enabled and ent.Player then
    				local Icon = Instance.new('ImageLabel')
    				Icon.Name = 'EnchantIcon'
    				Icon.Size = UDim2.fromOffset(30, 30)
    				Icon.Position = UDim2.fromOffset(-30, -4)
    				Icon.BackgroundTransparency = 1
    				Icon.Image = store.enchants[ent.Player]:async() or ''
    				Icon.Parent = nametag
    			end
    		end)
    		Reference[ent] = nametag
    	end,
    	Drawing = function(ent)
    		if not Targets.Players.Enabled and ent.Player then
    			return
    		end
    		if not Targets.NPCs.Enabled and ent.NPC then
    			return
    		end
    		if Teammates.Enabled and not ent.Targetable and not ent.Friend then
    			return
    		end

    		local nametag = {}
    		nametag.BG = Drawing.new('Square')
    		nametag.BG.Filled = true
    		nametag.BG.Transparency = 1 - Background.Value
    		nametag.BG.Color = Color3.new()
    		nametag.BG.ZIndex = 1
    		nametag.Text = Drawing.new('Text')
    		nametag.Text.Size = 15 * Scale.Value
    		nametag.Text.Font = 0
    		nametag.Text.ZIndex = 2
    		Strings[ent] = ent.Player
    				and whitelist:tag(ent.Player, true) .. (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name)
    			or ent.Character.Name

    		if Health.Enabled then
    			Strings[ent] = Strings[ent] .. ' ' .. math.round(ent.Health)
    		end

    		if Distance.Enabled then
    			Strings[ent] = '[%s] ' .. Strings[ent]
    		end

    		nametag.Text.Text = Strings[ent]
    		nametag.Text.Color = entitylib.getEntityColor(ent) or Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
    		nametag.BG.Size = Vector2.new(nametag.Text.TextBounds.X + 8, nametag.Text.TextBounds.Y + 7)
    		Reference[ent] = nametag
    	end,
    }

    local Removed = {
    	Normal = function(ent)
    		local v = Reference[ent]
    		if v then
    			Reference[ent] = nil
    			Strings[ent] = nil
    			Sizes[ent] = nil
    			v:Destroy()
    		end
    	end,
    	Drawing = function(ent)
    		local v = Reference[ent]
    		if v then
    			Reference[ent] = nil
    			Strings[ent] = nil
    			Sizes[ent] = nil
    			for _, obj in v do
    				pcall(function()
    					obj.Visible = false
    					obj:Remove()
    				end)
    			end
    		end
    	end,
    }

    local Updated = {
    	Normal = function(ent)
    		local nametag = Reference[ent]
    		if nametag then
    			Sizes[ent] = nil
    			Strings[ent] = ent.Player
    					and whitelist:tag(ent.Player, true, true) .. (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name)
    				or ent.Character.Name

    			if Health.Enabled then
    				local healthColor = Color3.fromHSV(math.clamp(ent.Health / ent.MaxHealth, 0, 1) / 2.5, 0.89, 0.75)
    				Strings[ent] = Strings[ent]
    					.. ' <font color="rgb('
    					.. tostring(math.floor(healthColor.R * 255))
    					.. ','
    					.. tostring(math.floor(healthColor.G * 255))
    					.. ','
    					.. tostring(math.floor(healthColor.B * 255))
    					.. ')">'
    					.. math.round(ent.Health)
    					.. '</font>'
    			end

    			if Distance.Enabled then
    				Strings[ent] = '<font color="rgb(85, 255, 85)">[</font><font color="rgb(255, 255, 255)">%s</font><font color="rgb(85, 255, 85)">]</font> '
    					.. Strings[ent]
    			end

    			if Equipment.Enabled and store.inventories[ent.Player] then
    				local kit = ent.Player:GetAttribute('PlayingAsKit')
    				local inventory = store.inventories[ent.Player]
    				nametag.Hand.Image = bedwars.getIcon(inventory.hand or {itemType = ''}, true)
    				nametag.Helmet.Image = bedwars.getIcon(inventory.armor[4] or {itemType = ''}, true)
    				nametag.Chestplate.Image = bedwars.getIcon(inventory.armor[5] or {itemType = ''}, true)
    				nametag.Boots.Image = bedwars.getIcon(inventory.armor[6] or {itemType = ''}, true)
    				nametag.Kit.Image = kit and bedwars.BedwarsKitMeta[kit].renderImage or ''
    			end

    			if Enchant.Enabled and nametag:FindFirstChild('EnchantIcon') then
    				nametag.EnchantIcon.Image = store.enchants[ent.Player]:async() or ''
    			end

    			local size = getfontsize(removeTags(Strings[ent]), nametag.TextSize, nametag.FontFace, Vector2.new(100000, 100000))
    			nametag.Size = UDim2.fromOffset(size.X + 8, size.Y + 7)
    			nametag.Text = Strings[ent]
    		end
    	end,
    	Drawing = function(ent)
    		local nametag = Reference[ent]
    		if nametag then
    			if vape.ThreadFix then
    				setthreadidentity(8)
    			end
    			Sizes[ent] = nil
    			Strings[ent] = ent.Player
    					and whitelist:tag(ent.Player, true) .. (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name)
    				or ent.Character.Name

    			if Health.Enabled then
    				Strings[ent] = Strings[ent] .. ' ' .. math.round(ent.Health)
    			end

    			if Distance.Enabled then
    				Strings[ent] = '[%s] ' .. Strings[ent]
    				nametag.Text.Text = entitylib.isAlive and string.format(Strings[ent], math.floor((entitylib.character.RootPart.Position - ent.RootPart.Position).Magnitude)) or Strings[ent]
    			else
    				nametag.Text.Text = Strings[ent]
    			end

    			nametag.BG.Size = Vector2.new(nametag.Text.TextBounds.X + 8, nametag.Text.TextBounds.Y + 7)
    			nametag.Text.Color = entitylib.getEntityColor(ent) or Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
    		end
    	end,
    }

    local ColorFunc = {
    	Normal = function(hue, sat, val)
    		local color = Color3.fromHSV(hue, sat, val)
    		for i, v in Reference do
    			v.TextColor3 = entitylib.getEntityColor(i) or color
    		end
    	end,
    	Drawing = function(hue, sat, val)
    		local color = Color3.fromHSV(hue, sat, val)
    		for i, v in Reference do
    			v.Text.Color = entitylib.getEntityColor(i) or color
    		end
    	end,
    }

    local Loop = {
    	Normal = function()
    		local alive = entitylib.isAlive
    		local localPosition = alive and entitylib.character.RootPart.Position
    		for ent, nametag in Reference do
    			local headPos, headVis
    			local distance
    			if alive and (DistanceCheck.Enabled or Distance.Enabled) then
    				distance = (localPosition - ent.RootPart.Position).Magnitude
    			end

    			if DistanceCheck.Enabled then
    				distance = distance or math.huge
    				if distance < DistanceLimit.ValueMin or distance > DistanceLimit.ValueMax then
    					nametag.Visible = false
    					continue
    				end
    			end

    			headPos, headVis = gameCamera:WorldToViewportPoint(ent.RootPart.Position + Vector3.new(0, ent.HipHeight + 1, 0))
    			nametag.Visible = headVis
    			if not headVis then
    				continue
    			end

    			if Distance.Enabled then
    				local mag = alive and math.floor(distance) or 0
    				if Sizes[ent] ~= mag then
    					nametag.Text = string.format(Strings[ent], mag)
    					local ize = getfontsize(
    						removeTags(nametag.Text),
    						nametag.TextSize,
    						nametag.FontFace,
    						Vector2.new(100000, 100000)
    					)
    					nametag.Size = UDim2.fromOffset(ize.X + 8, ize.Y + 7)
    					Sizes[ent] = mag
    				end
    			end
    			nametag.Position = UDim2.fromOffset(headPos.X, headPos.Y)
    		end
    	end,
    	Drawing = function()
    		local alive = entitylib.isAlive
    		local localPosition = alive and entitylib.character.RootPart.Position
    		for ent, nametag in Reference do
    			local headPos, headVis
    			local distance
    			if alive and (DistanceCheck.Enabled or Distance.Enabled) then
    				distance = (localPosition - ent.RootPart.Position).Magnitude
    			end

    			if DistanceCheck.Enabled then
    				distance = distance or math.huge
    				if distance < DistanceLimit.ValueMin or distance > DistanceLimit.ValueMax then
    					nametag.Text.Visible = false
    					nametag.BG.Visible = false
    					continue
    				end
    			end

    			headPos, headVis = gameCamera:WorldToViewportPoint(ent.RootPart.Position + Vector3.new(0, ent.HipHeight + 1, 0))
    			nametag.Text.Visible = headVis
    			nametag.BG.Visible = headVis
    			if not headVis then
    				continue
    			end

    			if Distance.Enabled then
    				local mag = alive and math.floor(distance) or 0
    				if Sizes[ent] ~= mag then
    					nametag.Text.Text = string.format(Strings[ent], mag)
    					nametag.BG.Size = Vector2.new(nametag.Text.TextBounds.X + 8, nametag.Text.TextBounds.Y + 7)
    					Sizes[ent] = mag
    				end
    			end
    			nametag.BG.Position = Vector2.new(headPos.X - (nametag.BG.Size.X / 2), headPos.Y - nametag.BG.Size.Y)
    			nametag.Text.Position = nametag.BG.Position + Vector2.new(4, 3)
    		end
    	end,
    }

    NameTags = vape.Categories.Render:CreateModule({
    	Name = 'Name Tags',
    	Function = function(callback)
    		if callback then
    			methodused = DrawingToggle.Enabled and 'Drawing' or 'Normal'
    			if Removed[methodused] then
    				NameTags:Clean(entitylib.Events.EntityRemoved:Connect(Removed[methodused]))
    			end
    			if Added[methodused] then
    				for _, v in entitylib.List do
    					if Reference[v] then
    						Removed[methodused](v)
    					end
    					Added[methodused](v)
    				end
    				NameTags:Clean(entitylib.Events.EntityAdded:Connect(function(ent)
    					if Reference[ent] then
    						Removed[methodused](ent)
    					end
    					Added[methodused](ent)
    				end))
    			end
    			if Updated[methodused] then
    				NameTags:Clean(entitylib.Events.EntityUpdated:Connect(Updated[methodused]))
    				for _, v in entitylib.List do
    					Updated[methodused](v)
    				end
    			end
    			if ColorFunc[methodused] then
    				NameTags:Clean(vape.Categories.Friends.ColorUpdate.Event:Connect(function()
    					ColorFunc[methodused](Color.Hue, Color.Sat, Color.Value)
    				end))
    			end
    			if Loop[methodused] then
    				NameTags:Clean(runService.RenderStepped:Connect(Loop[methodused]))
    			end
    		else
    			if Removed[methodused] then
    				for i in Reference do
    					Removed[methodused](i)
    				end
    			end
    		end
    	end,
    	Tooltip = 'Renders nametags on entities through walls.'
    })
    Targets = NameTags:CreateTargets({
    	Players = true,
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    })
    FontOption = NameTags:CreateFont({
    	Name = 'Font',
    	Blacklist = 'Arial',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    })
    Color = NameTags:CreateColorSlider({
    	Name = 'Player Color',
    	Function = function(hue, sat, val)
    		if NameTags.Enabled and ColorFunc[methodused] then
    			ColorFunc[methodused](hue, sat, val)
    		end
    	end,
    })
    Scale = NameTags:CreateSlider({
    	Name = 'Scale',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    	Default = 1,
    	Min = 0.1,
    	Max = 1.5,
    	Decimal = 10,
    })
    Background = NameTags:CreateSlider({
    	Name = 'Transparency',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    	Default = 0.5,
    	Min = 0,
    	Max = 1,
    	Decimal = 10,
    })
    Health = NameTags:CreateToggle({
    	Name = 'Health',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    })
    Distance = NameTags:CreateToggle({
    	Name = 'Distance',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    })
    Rank = NameTags:CreateToggle({
    	Name = 'Rank',
    	Tooltip = "Displays player's rank",
    })
    Enchant = NameTags:CreateToggle({
    	Name = 'Enchant',
    	Tooltip = "Displays player's enchant",
    	Default = true,
    })
    Equipment = NameTags:CreateToggle({
    	Name = 'Equipment',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    })
    DisplayName = NameTags:CreateToggle({
    	Name = 'Use Displayname',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    	Default = true,
    })
    Teammates = NameTags:CreateToggle({
    	Name = 'Priority Only',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    	Default = true,
    })
    DrawingToggle = NameTags:CreateToggle({
    	Name = 'Drawing',
    	Function = function()
    		if NameTags.Enabled then
    			NameTags:Toggle()
    			NameTags:Toggle()
    		end
    	end,
    })
    DistanceCheck = NameTags:CreateToggle({
    	Name = 'Distance Check',
    	Function = function(callback)
    		DistanceLimit.Object.Visible = callback
    	end,
    })
    DistanceLimit = NameTags:CreateTwoSlider({
    	Name = 'Player Distance',
    	Min = 0,
    	Max = 256,
    	DefaultMin = 0,
    	DefaultMax = 64,
    	Darker = true,
    	Visible = false,
    })
end)

run(function()
    local BoxESP
    local BTargets
    local BColor
    local BThickness
    local BTeammates
    local bReference = {}
    local bGui
    local bCamera = workspace.CurrentCamera

    -- Project 8 corners of character bounding box to viewport and return
    -- screen-space (x, y, width, height). Returns nil if entirely off-screen.
    local function bGetScreenBox(character)
        local hrp = character:FindFirstChild('HumanoidRootPart')
        local hum = character:FindFirstChildOfClass('Humanoid')
        if not hrp or not hum then return nil end
        local pos = hrp.Position
        local hip = hum.HipHeight
        local hw = 1.0  -- half-width (studs)
        local yBot = pos.Y - hip - 0.1
        local yTop = pos.Y + hip + 0.6  -- +0.6 reaches roughly the top of the head
        local minX, minY = math.huge, math.huge
        local maxX, maxY = -math.huge, -math.huge
        local anyVisible = false
        local corners = {
            Vector3.new(pos.X - hw, yBot, pos.Z - hw),
            Vector3.new(pos.X + hw, yBot, pos.Z - hw),
            Vector3.new(pos.X - hw, yBot, pos.Z + hw),
            Vector3.new(pos.X + hw, yBot, pos.Z + hw),
            Vector3.new(pos.X - hw, yTop, pos.Z - hw),
            Vector3.new(pos.X + hw, yTop, pos.Z - hw),
            Vector3.new(pos.X - hw, yTop, pos.Z + hw),
            Vector3.new(pos.X + hw, yTop, pos.Z + hw),
        }
        for _, c in corners do
            local sp, vis = bCamera:WorldToViewportPoint(c)
            if vis and sp.Z > 0 then
                anyVisible = true
                if sp.X < minX then minX = sp.X end
                if sp.Y < minY then minY = sp.Y end
                if sp.X > maxX then maxX = sp.X end
                if sp.Y > maxY then maxY = sp.Y end
            end
        end
        if not anyVisible then return nil end
        return minX, minY, maxX - minX, maxY - minY
    end

    local function bAddBox(ent)
        if not BTargets.Players.Enabled and ent.Player then return end
        if not BTargets.NPCs.Enabled and ent.NPC then return end
        if BTeammates.Enabled and not ent.Targetable and not ent.Friend then return end
        if not ent.Character or not ent.Character.PrimaryPart then return end
        if bReference[ent] then return end

        local frame = Instance.new('Frame')
        frame.BackgroundTransparency = 1
        frame.BorderSizePixel = 0
        frame.Visible = false
        local stroke = Instance.new('UIStroke')
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color = entitylib.getEntityColor(ent) or Color3.fromHSV(BColor.Hue, BColor.Sat, BColor.Value)
        stroke.Thickness = BThickness.Value
        stroke.Parent = frame
        frame.Parent = bGui
        bReference[ent] = {frame = frame, stroke = stroke}
    end

    local function bRemoveBox(ent)
        local v = bReference[ent]
        if v then
            bReference[ent] = nil
            pcall(function() v.frame:Destroy() end)
        end
    end

    BoxESP = vape.Categories.Render:CreateModule({
        Name = 'Box ESP',
        Function = function(callback)
            if callback then
                bGui = Instance.new('ScreenGui')
                bGui.Name = 'VapeBoxESP'
                bGui.IgnoreGuiInset = true
                bGui.DisplayOrder = 999
                bGui.ResetOnSpawn = false
                local ok = pcall(function() bGui.Parent = game:GetService('CoreGui') end)
                if not ok or not bGui.Parent then bGui.Parent = lplr.PlayerGui end
                for _, ent in entitylib.List do bAddBox(ent) end
                BoxESP:Clean(entitylib.Events.EntityAdded:Connect(bAddBox))
                BoxESP:Clean(entitylib.Events.EntityRemoved:Connect(bRemoveBox))
                BoxESP:Clean(runService.RenderStepped:Connect(function()
                    for ent, data in bReference do
                        local ch = ent.Character
                        if not ch or not ch.PrimaryPart then
                            data.frame.Visible = false
                            continue
                        end
                        local x, y, w, h = bGetScreenBox(ch)
                        if not x then
                            data.frame.Visible = false
                            continue
                        end
                        data.frame.Visible = true
                        data.frame.Position = UDim2.fromOffset(x, y)
                        data.frame.Size = UDim2.fromOffset(w, h)
                        data.stroke.Color = entitylib.getEntityColor(ent) or Color3.fromHSV(BColor.Hue, BColor.Sat, BColor.Value)
                        data.stroke.Thickness = BThickness.Value
                    end
                end))
            else
                for ent in bReference do bRemoveBox(ent) end
                if bGui then pcall(function() bGui:Destroy() end) bGui = nil end
            end
        end,
        Tooltip = 'Box ESP — outline only, no text, works on Delta and all executors'
    })
    BTargets = BoxESP:CreateTargets({Players = true})
    BColor = BoxESP:CreateColorSlider({Name = 'Color'})
    BThickness = BoxESP:CreateSlider({
        Name = 'Thickness',
        Default = 1,
        Min = 1,
        Max = 4,
        Decimal = 1,
    })
    BTeammates = BoxESP:CreateToggle({
        Name = 'Priority Only',
        Default = true,
        Tooltip = 'Only show enemies and priority targets'
    })
end)

run(function()
    local BulletTracers
    local Material
    local Lifetime
    local Curve
    local Opacity
    local Thickness
    local Color
    local Fade

    local rayCheck = RaycastParams.new()
    rayCheck.FilterType = Enum.RaycastFilterType.Exclude

    BulletTracers = vape.Categories.Render:CreateModule({
    	Name = 'Projectile Tracers',
    	Function = function(callback)
    		if callback then
    			BulletTracers:Clean(workspace.ChildAdded:Connect(function(projectile)
    				task.delay(0, function()
    					rayCheck.FilterDescendantsInstances = {projectile, lplr.Character}
    					if projectile:GetAttribute('ProjectileShooter') ~= lplr.UserId then
    						return
    					end
    					local origin = projectile:GetPivot().Position
    					local velocity = projectile.PrimaryPart and projectile.PrimaryPart.Velocity or Vector3.zero
    					local velocityMagnitude = velocity.Magnitude
    					if velocityMagnitude <= 0 then
    						return
    					end
    					local velocityUnit = velocity / velocityMagnitude
    					local gravity = bedwars.ProjectileMeta[projectile.Name].gravitationalAcceleration
    					local ray = workspace:Raycast(origin, velocityUnit * 2000, rayCheck)
    					local endpoint = ray and ray.Position or (origin + velocityUnit * 2000)
    					local travelTime = (endpoint - origin).Magnitude / velocityMagnitude

    					prediction.SpawnArcTracer(
    						origin,
    						velocityUnit,
    						velocityMagnitude,
    						gravity,
    						travelTime,
    						Curve.Value,
    						{
    							Color = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value),
    							Transparency = Opacity.Value,
    							Thick = Thickness.Value,
    							Material = Enum.Material[Material.Value],
    							Lifetime = Lifetime.Value,
    							Fade = Fade.Enabled,
    						}
    					)
    				end)
    			end))
    		end
    	end,
    	Tooltip = 'Replacement tracers for projectiles'
    })

    local materials = {'SmoothPlastic'}
    for _, v in Enum.Material:GetEnumItems() do
    	if v.Name ~= 'SmoothPlastic' then
    		table.insert(materials, v.Name)
    	end
    end
    Material = BulletTracers:CreateDropdown({
    	Name = 'Material',
    	List = materials
    })
    Color = BulletTracers:CreateColorSlider({
    	Name = 'Tracer Color',
    	DefaultOpacity = 0.5
    })
    Thickness = BulletTracers:CreateSlider({
    	Name = 'Thickness',
    	Min = 0.01,
    	Max = 1,
    	Default = 0.1,
    	Decimal = 100
    })
    Curve = BulletTracers:CreateSlider({
    	Name = 'Curveness',
    	Min = 1,
    	Max = 100,
    	Default = 40,
    	Tooltip = 'How curve the projectile is gonna be\n(More curve = more lag)'
    })
    Opacity = BulletTracers:CreateSlider({
    	Name = 'Opacity',
    	Min = 0,
    	Max = 1,
    	Default = 0,
    	Decimal = 100
    })
    Lifetime = BulletTracers:CreateSlider({
    	Name = 'Lifetime',
    	Min = 0,
    	Max = 5,
    	Decimal = 100,
    	Default = 2,
    	Suffix = 'secs'
    })
    Fade = BulletTracers:CreateToggle({
    	Name = 'Fade',
    	Default = true
    })
end)

run(function()
    local Shader
    local changed = false
    local lightingSettings = {}
    local Objects = {}
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui
    
    Shader = vape.Categories.Render:CreateModule({
    	Name = 'Shader',
    	Function = function(callback)
    		if callback then
    			if vape.ThreadFix then
    				setthreadidentity(8)
    			end
    
    			for _, v in lightingService:GetChildren() do
    				v.Parent = Folder
    			end
    
    			for _, v in {'Ambient', 'Brightness', 'ColorShift_Top', 'ColorShift_Bottom', 'ExposureCompensation', 'EnvironmentDiffuseScale', 'OutdoorAmbient'} do
    				lightingSettings[v] = lightingService[v]
    			end
    
    			Shader:Clean(lightingService.Changed:Connect(function(v)
    				if lightingSettings[v] and not changed then
    					changed = true
    					lightingSettings[v] = lightingService[v]
    					lightingService.Ambient = Color3.fromRGB(20, 20, 20)
    					lightingService.Brightness = 2.5
    					lightingService.ColorShift_Top = Color3.fromRGB(206, 206, 206)
    					lightingService.ColorShift_Bottom = Color3.fromRGB(231, 231, 231)
    					lightingService.ExposureCompensation = -0.5
    					lightingService.EnvironmentDiffuseScale = 0.15
    					lightingService.EnvironmentSpecularScale = 0.25
    					lightingService.OutdoorAmbient = Color3.fromRGB(30, 30, 30)
    					changed = false
    				end
    			end))
    
    			lightingService.Ambient = Color3.fromRGB(20, 20, 20)
    			lightingService.Brightness = 2.5
    			lightingService.ColorShift_Top = Color3.fromRGB(206, 206, 206)
    			lightingService.ColorShift_Bottom = Color3.fromRGB(231, 231, 231)
    			lightingService.ExposureCompensation = -0.5
    			lightingService.EnvironmentDiffuseScale = 0.15
    			lightingService.EnvironmentSpecularScale = 0.25
    			lightingService.OutdoorAmbient = Color3.fromRGB(30, 30, 30)
    
    			Objects.Atmosphere = Instance.new('Atmosphere')
    			Objects.Atmosphere.Color = Color3.fromRGB(103, 103, 103)
    			Objects.Atmosphere.Decay = Color3.fromRGB(80, 80, 80)
    			Objects.Atmosphere.Density = 0.3
    			Objects.Atmosphere.Glare = 0.8
    			Objects.Atmosphere.Haze = 0
    			Objects.Atmosphere.Offset = 0
    
    			Objects.Sky = Instance.new('Sky')
    			Objects.Sky.CelestialBodiesShown = true
    			Objects.Sky.SkyboxBk = 'http://www.roblox.com/asset/?id=245710263'
    			Objects.Sky.SkyboxDn = 'http://www.roblox.com/asset/?id=245710630'
    			Objects.Sky.SkyboxFt = 'http://www.roblox.com/asset/?id=245710380'
    			Objects.Sky.SkyboxLf = 'http://www.roblox.com/asset/?id=245710319'
    			Objects.Sky.SkyboxRt = 'http://www.roblox.com/asset/?id=245710230'
    			Objects.Sky.SkyboxUp = 'http://www.roblox.com/asset/?id=245710496'
    
    			Objects.Bloom = Instance.new('BloomEffect')
    			Objects.Bloom.Intensity = 1
    			Objects.Bloom.Size = 56
    			Objects.Bloom.Threshold = 0.5
    
    			Objects.Bloom2 = Instance.new('BloomEffect')
    			Objects.Bloom2.Intensity = 0
    			Objects.Bloom2.Size = 120
    			Objects.Bloom2.Threshold = 1
    
    			Objects.ColorCorrection = Instance.new('ColorCorrectionEffect')
    			Objects.ColorCorrection.Brightness = 0.15
    			Objects.ColorCorrection.Contrast = 0.5
    			Objects.ColorCorrection.Saturation = 0.2
    			Objects.ColorCorrection.TintColor = Color3.fromRGB(255, 245, 231)
    			Objects.ColorCorrection.Enabled = false
    
    			Objects.ColorCorrection2 = Instance.new('ColorCorrectionEffect')
    			Objects.ColorCorrection2.Brightness = 0.1
    			Objects.ColorCorrection2.Contrast = 0.3
    			Objects.ColorCorrection2.Saturation = -0.2
    
    			Objects.ColorCorrection3 = Instance.new('ColorCorrectionEffect')
    			Objects.ColorCorrection3.Brightness = 0
    			Objects.ColorCorrection3.Contrast = 0.05
    			Objects.ColorCorrection3.Saturation = 0
    			Objects.ColorCorrection3.TintColor = Color3.fromRGB(255,255,255)
    
    			Objects.DepthOfField = Instance.new('DepthOfFieldEffect')
    			Objects.DepthOfField.FarIntensity = 0.1
    			Objects.DepthOfField.InFocusRadius = 30
    
    			Objects.SunRays = Instance.new('SunRaysEffect')
    
    			Objects.SunRays2 = Instance.new('SunRaysEffect')
    			Objects.SunRays2.Intensity = 0.2
    			Objects.SunRays2.Spread = 0.2
    
    			Objects.SunRays3 = Instance.new('SunRaysEffect')
    			Objects.SunRays3.Intensity = 0.04
    			Objects.SunRays3.Spread = 1
    
    			for _, v in Objects do
    				v.Parent = lightingService
    			end
    		else
    			for _, v in Objects do
    				v:Destroy()
    			end
    
    			for _, v in Folder:GetChildren() do
    				v.Parent = lightingService
    			end
    
    			for i, v in lightingSettings do
    				lightingService[i] = v
    			end
    
    			table.clear(Objects)
    		end
    	end
    })
end)

run(function()
    local SkinChanger
    local Skin, SkinType

    local Names, Saved = {}, {}
    local OldTransparencies = {}

    local function CleanSaved()
        for _, entry in Saved do
            pcall(function()
                if entry.Reskin and entry.Reskin.Parent then
                    entry.Reskin:Destroy()
                end
                if entry.Original then
                    for part, transparency in entry.Hidden do
                        pcall(function() part.Transparency = transparency end)
                    end
                end
            end)
        end
        table.clear(Saved)
    end

    local function Added(Item, Parent)
        if not Skin.Value or not Item then
            return
        end
        local Meta = bedwars.ItemMeta[Item.Name]
        if not Meta then return end

        for _, skin in Names[Skin.Value] do
            local SkinSource, OrigHandle, Hidden, Reskin, SkinHandle, Weld, entry
            if not skin:find(Item.Name) then
                continue
            end
            if SkinType.Value ~= 'All' and not skin:find(SkinType.Value:lower()) then
                continue
            end
            SkinSource = replicatedStorage.Items:FindFirstChild(skin)
            if not SkinSource or not SkinSource:FindFirstChild('Handle') then
                continue
            end

            OrigHandle = Item:FindFirstChild('Handle')
            if not OrigHandle then continue end

            Hidden = {}
            for _, v in Item:GetDescendants() do
                if v:IsA('BasePart') then
                    Hidden[v] = v.Transparency
                    v.Transparency = 1
                end
            end

            Reskin = Instance.new('Accessory')
            Reskin.Name = 'LOCAL_ITEM_RESKIN'

            SkinHandle = SkinSource.Handle:Clone()
            SkinHandle.Parent = Reskin

            for _, v in Reskin:GetDescendants() do
                pcall(function() v.Anchored = false end)
                pcall(function() v.CanCollide = false end)
            end

            Weld = Instance.new('Weld')
            Weld.Part0 = OrigHandle
            Weld.Part1 = SkinHandle
            Weld.C0 = CFrame.Angles(-math.pi, 0, -math.pi)
            Weld.C1 = CFrame.new()
            Weld.Parent = SkinHandle

            Reskin.Parent = Item
            Item:SetAttribute('ItemSkin', skin)

            entry = {Reskin = Reskin, Original = Item, Hidden = Hidden}
            table.insert(Saved, entry)
            SkinChanger:Clean(Reskin)

            break
        end
    end

    SkinChanger = vape.Categories.Render:CreateModule({
        Name = 'Skin Changer',
        Tooltip = 'Changes ur item skins with others',
        Function = function(callback)
            if callback then
                repeat
                    task.wait()
                until store.map or not SkinChanger.Enabled
                if not SkinChanger.Enabled then return end

                SkinChanger:Clean(vapeEvents.InventoryHeldChanged.Event:Connect(function(Tool)
                    CleanSaved()
                    if Tool then
                        for _, parent in {lplr.Character, gameCamera.Viewmodel} do
                            local Model = parent:WaitForChild(Tool.Name, 5)
                            if Model then
                                task.delay(0, Added, Model, parent)
                            end
                        end
                    end
                end))
                SkinChanger:Clean(store.map.Blocks.ChildAdded:Connect(function(v)
                    task.defer(function()
                        local Meta = bedwars.ItemMeta[v.Name]
                        if Meta then
                            for _, SkinName in Names[Skin.Value] do
                                local ItemSkin
                                if not SkinName:find(v.Name) then
                                    continue
                                end
                                if SkinType.Value ~= 'All' and not SkinName:find(SkinType.Value:lower()) then
                                    continue
                                end
                                ItemSkin = replicatedStorage.Assets.Blocks:FindFirstChild(SkinName)
                                if ItemSkin then
                                    ItemSkin = ItemSkin:Clone()
                                    ItemSkin.Parent = workspace
                                    local BlockHidden = {}
                                    for _, v2 in v:QueryDescendants('BasePart') do
                                        BlockHidden[v2] = v2.Transparency
                                        v2.Transparency = 1
                                    end
                                    task.spawn(pcall, function()
                                        v:WaitForChild('TeamLight', 5):Destroy()
                                    end)

                                    for _, v2 in ItemSkin:GetDescendants() do
                                        pcall(function()
                                            v2.CanCollide = false
                                            v2.CanQuery = false
                                            v2.CanTouch = false
                                        end)
                                    end

                                    v:SetAttribute('ItemSkin', SkinName)

                                    local Base = v:FindFirstChild('Barrel') or v:FindFirstChild('Bottom') or v

                                    local Connection = runService.PreRender:Connect(function()
                                        if not Base or not Base.Parent then
                                            return
                                        end
                                        ItemSkin:PivotTo(Base.CFrame)
                                    end)

                                    local restoreCallback = function()
                                        if v and v.Parent then
                                            for i, v in BlockHidden do
                                                i.Transparency = v
                                            end
                                        end
                                    end
                                    SkinChanger:Clean(ItemSkin)
                                    SkinChanger:Clean(Connection)
                                    SkinChanger:Clean(restoreCallback)
                                    v.Destroying:Once(function()
                                        if Connection then
                                            Connection:Disconnect()
                                        end
                                        if ItemSkin and ItemSkin.Parent then
                                            ItemSkin:Destroy()
                                        end
                                    end)
                                end
                            end
                        end
                    end)
                end))
            else
                CleanSaved()
            end
        end,
    })
    
    local list = {}
    for _, v in bedwars.BedwarsKitSkin do
        if v.itemSkins then
            if Names[v.name] then
                for _, v2 in v.itemSkins do
                    table.insert(Names[v.name], v2)
                end
            else
                table.insert(list, v.name)
                Names[v.name] = v.itemSkins
            end
        end
    end
    table.sort(list, function(a, b)
        return a < b
    end)
    Skin = SkinChanger:CreateDropdown({
        Name = 'Item Skin',
        List = list,
    })
    SkinType = SkinChanger:CreateDropdown({
        Name = 'Skin Type',
        List = { 'All', 'Gold', 'Platinum', 'Diamond', 'Emerald', 'Nightmare', 'Void' },
        Default = 'All',
    })
end)

run(function()
    local MannyX2
    local SkinDropdown
    local Saved = {}

    local Tiers = {'wood', 'stone', 'iron', 'diamond', 'emerald'}

    local SkinMap = {}
    local SetNames = {}
    local SetList = {}

    for _, item in replicatedStorage.Items:GetChildren() do
        if item.Name:find('sword') and item:FindFirstChild('Handle') then
            SkinMap[item.Name] = item
        end
    end

    for skinName in SkinMap do
        for _, tier in Tiers do
            local tierSword = tier .. '_sword'
            if skinName:find(tierSword) then
                local setName = skinName:gsub('_?' .. tierSword .. '_?', ''):gsub('^_+', ''):gsub('_+$', '')
                if setName == '' then continue end
                if not SetNames[setName] then
                    SetNames[setName] = {}
                    table.insert(SetList, setName)
                end
                SetNames[setName][tier] = skinName
                break
            end
        end
    end

    table.sort(SetList)

    local DefaultSwings = {
        ['rbxassetid://6760544639'] = true,
        ['rbxassetid://6760544595'] = true,
    }

    local SkinSounds = {
        pixel = {
            swing = 'rbxassetid://121090646461615',
        },
    }

    local function SwapSound(sound)
        if not MannyX2 or not MannyX2.Enabled then return end
        if not SkinDropdown or not SkinDropdown.Value then return end
        local skinData = SkinSounds[SkinDropdown.Value]
        if not skinData or not skinData.swing then return end
        if DefaultSwings[sound.SoundId] then
            sound.SoundId = skinData.swing
        end
    end

    local function HookSoundPlayed(sound)
        return sound.Played:Connect(function()
            if not MannyX2 or not MannyX2.Enabled then return end
            if not SkinDropdown or not SkinDropdown.Value then return end
            local skinData = SkinSounds[SkinDropdown.Value]
            if not skinData or not skinData.swing then return end
            if DefaultSwings[sound.SoundId] then
                sound:Stop()
                local rep = Instance.new('Sound')
                rep.SoundId = skinData.swing
                rep.Volume = sound.Volume
                rep.PlaybackSpeed = sound.PlaybackSpeed
                rep.Parent = sound.Parent
                rep:Play()
                game:GetService('Debris'):AddItem(rep, 3)
            end
        end)
    end

    local function GetSkinForItem(itemName)
        if not SkinDropdown or not SkinDropdown.Value then return end
        local setName = SkinDropdown.Value
        local set = SetNames[setName]
        if not set then return end

        for _, tier in Tiers do
            if itemName:find(tier) then
                local skinName = set[tier]
                if skinName then
                    return SkinMap[skinName]
                end
                break
            end
        end
    end

    local function CleanSaved()
        for _, entry in Saved do
            pcall(function()
                if entry.Reskin and entry.Reskin.Parent then
                    entry.Reskin:Destroy()
                end
                for part, t in entry.Hidden do
                    pcall(function() part.Transparency = t end)
                end
            end)
        end
        table.clear(Saved)
    end

    local function ApplySword(Item)
        if not Item then return end
        local Meta = bedwars.ItemMeta[Item.Name]
        if not Meta or not Meta.sword then return end

        local OrigHandle = Item:FindFirstChild('Handle')
        if not OrigHandle then return end

        local SkinSource = GetSkinForItem(Item.Name)
        if not SkinSource then return end

        local Hidden = {}
        for _, v in Item:GetDescendants() do
            if v:IsA('BasePart') then
                Hidden[v] = v.Transparency
                v.Transparency = 1
            end
        end

        local Reskin = Instance.new('Accessory')
        Reskin.Name = 'LOCAL_ITEM_RESKIN'

        local SkinHandle = SkinSource.Handle:Clone()
        SkinHandle.Parent = Reskin

        for _, v in Reskin:GetDescendants() do
            pcall(function() v.Anchored = false end)
            pcall(function() v.CanCollide = false end)
        end

        local setName = SkinDropdown and SkinDropdown.Value or ''
        local norm = setName:lower():gsub('_', '')
        local yOffset = 0
        if norm == 'pixel' then
            if OrigHandle.Size.Y < 3 then
                yOffset = 1.8
            end
        else
            yOffset = (SkinHandle.Size.Y - OrigHandle.Size.Y) / 2
        end

        local Weld = Instance.new('Weld')
        Weld.Part0 = OrigHandle
        Weld.Part1 = SkinHandle
        Weld.C0 = CFrame.new(0, yOffset, 0) * CFrame.Angles(-math.pi, 0, -math.pi)
        Weld.C1 = CFrame.new()
        Weld.Parent = SkinHandle

        Reskin.Parent = Item
        Item:SetAttribute('ItemSkin', SkinSource.Name)

        table.insert(Saved, {Reskin = Reskin, Hidden = Hidden})
        MannyX2:Clean(Reskin)
    end

    local function ApplyCurrentHeld()
        CleanSaved()
        local char = lplr.Character
        if not char then return end
        for _, child in char:GetChildren() do
            local Meta = bedwars.ItemMeta[child.Name]
            if Meta and Meta.sword then
                ApplySword(child)
            end
        end
        pcall(function()
            local vm = gameCamera.Viewmodel
            if vm then
                for _, child in vm:GetChildren() do
                    local Meta = bedwars.ItemMeta[child.Name]
                    if Meta and Meta.sword then
                        ApplySword(child)
                    end
                end
            end
        end)
    end

    local function TryApply(child)
        local Meta = bedwars.ItemMeta[child.Name]
        if Meta and Meta.sword and not child:FindFirstChild('LOCAL_ITEM_RESKIN') then
            task.delay(0, ApplySword, child)
        end
    end

    local function WatchParent(parent)
        for _, child in parent:GetChildren() do
            TryApply(child)
        end
        return parent.ChildAdded:Connect(function(child)
            task.defer(function()
                TryApply(child)
            end)
        end)
    end

    MannyX2 = vape.Categories.Render:CreateModule({
        Name = 'Sword Changer',
        Tooltip = 'Sword skin changer — auto matches sword tier',
        Function = function(callback)
            if callback then
                repeat
                    task.wait()
                until store.map or not MannyX2.Enabled
                if not MannyX2.Enabled then return end

                ApplyCurrentHeld()

                for _, v in game:GetDescendants() do
                    if v:IsA('Sound') then
                        pcall(SwapSound, v)
                        pcall(function() MannyX2:Clean(HookSoundPlayed(v)) end)
                    end
                end

                MannyX2:Clean(game.DescendantAdded:Connect(function(v)
                    if v:IsA('Sound') then
                        pcall(SwapSound, v)
                        pcall(function() MannyX2:Clean(HookSoundPlayed(v)) end)
                    end
                end))

                MannyX2:Clean(vapeEvents.InventoryHeldChanged.Event:Connect(function(Tool)
                    CleanSaved()
                    if Tool then
                        for _, parent in {lplr.Character, gameCamera.Viewmodel} do
                            local Model = parent:WaitForChild(Tool.Name, 5)
                            if Model then
                                task.delay(0, ApplySword, Model)
                            end
                        end
                    end
                end))

                if lplr.Character then
                    MannyX2:Clean(WatchParent(lplr.Character))
                end
                MannyX2:Clean(lplr.CharacterAdded:Connect(function(char)
                    MannyX2:Clean(WatchParent(char))
                end))
                pcall(function()
                    MannyX2:Clean(WatchParent(gameCamera.Viewmodel))
                end)
            else
                CleanSaved()
            end
        end,
    })

    SkinDropdown = MannyX2:CreateDropdown({
        Name = 'Skin Set',
        List = SetList,
        Default = 'pixel',
    })
end)

run(function()
    local StorageESP
    local List
    local Background
    local Reference = {}
    local Enabled = {}
    local Connections = {}
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui

    local function nearStorageItem(item)
    	for _, v in List.ListEnabled do
    		if item:find(v) then
    			return v
    		end
    	end
    	return nil
    end

    local function refreshAdornee(obj, card)
    	local chestRef = obj:FindFirstChild('ChestFolderValue')
    	local chest = chestRef and chestRef.Value or nil
    	if not chest then
    		Enabled[obj] = false
    		return
    	end

    	local items = card:FindFirstChild('Items')
    	if items then
    		for _, child in items:GetChildren() do
    			if child:IsA('Frame') and child.Name == 'ItemSlot' then
    				child:Destroy()
    			end
    		end
    	end

    	Enabled[obj] = false
    	local slotCounts = {}
    	local order = {}
    	local ironCount, diamondCount, emeraldCount = 0, 0, 0
    	for _, item in chest:GetChildren() do
    		local n = item.Name:lower()
    		if n:find('iron') then ironCount = ironCount + 1
    		elseif n:find('diamond') then diamondCount = diamondCount + 1
    		elseif n:find('emerald') then emeraldCount = emeraldCount + 1 end
    		if table.find(List.ListEnabled, item.Name) or nearStorageItem(item.Name) then
    			if not slotCounts[item.Name] then
    				slotCounts[item.Name] = 0
    				table.insert(order, item.Name)
    			end
    			slotCounts[item.Name] = slotCounts[item.Name] + 1
    		end
    	end
    	if ironCount > 0 or diamondCount > 0 or emeraldCount > 0 then
    		Enabled[obj] = true
    	end
    	for _, itemName in order do
    		Enabled[obj] = true
    		local slot = Instance.new('Frame')
    		slot.Name = 'ItemSlot'
    		slot.Size = UDim2.fromOffset(16, 16)
    		slot.BackgroundTransparency = 1
    		slot.Parent = items
    		local blockimage = Instance.new('ImageLabel')
    		blockimage.Size = UDim2.fromOffset(14, 14)
    		blockimage.Position = UDim2.fromOffset(1, 0)
    		blockimage.BackgroundTransparency = 1
    		blockimage.Image = bedwars.getIcon({ itemType = itemName }, true)
    		blockimage.Parent = slot
    		if slotCounts[itemName] > 1 then
    			local countLabel = Instance.new('TextLabel')
    			countLabel.Size = UDim2.fromOffset(14, 8)
    			countLabel.Position = UDim2.new(1, -1, 1, -1)
    			countLabel.AnchorPoint = Vector2.new(1, 1)
    			countLabel.BackgroundTransparency = 1
    			countLabel.Text = 'x' .. slotCounts[itemName]
    			countLabel.TextColor3 = Color3.new(1, 1, 1)
    			countLabel.TextStrokeTransparency = 0.3
    			countLabel.TextStrokeColor3 = Color3.new()
    			countLabel.TextSize = 7
    			countLabel.Font = Enum.Font.GothamBold
    			countLabel.TextXAlignment = Enum.TextXAlignment.Right
    			countLabel.Parent = slot
    		end
    	end
    end

    local function Removing(v)
    	local card = Reference[v]
    	if card then
    		card:Destroy()
    		Reference[v] = nil
    		Enabled[v] = nil
    	end

    	local connections = Connections[v]
    	if connections then
    		for _, connection in connections do
    			connection:Disconnect()
    		end
    		table.clear(connections)
    		Connections[v] = nil
    	end
    end

    local function Clear()
    	local references = table.clone(Reference)
    	for v in references do
    		Removing(v)
    	end
    	table.clear(references)
    	Folder:ClearAllChildren()
    end

    local function Added(v)
    	local chestRef = v:WaitForChild('ChestFolderValue', 3)
    	if not (chestRef and StorageESP.Enabled and v:HasTag('chest')) then
    		return
    	end
    	if Reference[v] then
    		Removing(v)
    	end
    	local chest = chestRef.Value
    	if not chest then
    		return
    	end

    	local card = Instance.new('Frame')
    	card.AnchorPoint = Vector2.new(0.5, 1)
    	card.BackgroundColor3 = Color3.new()
    	card.BackgroundTransparency = Background.Enabled and 0.35 or 1
    	card.BorderSizePixel = 0
    	card.AutomaticSize = Enum.AutomaticSize.XY
    	card.Visible = false
    	local cardCorner = Instance.new('UICorner')
    	cardCorner.CornerRadius = UDim.new(0, 4)
    	cardCorner.Parent = card
    	local cardPadding = Instance.new('UIPadding')
    	cardPadding.PaddingLeft = UDim.new(0, 6)
    	cardPadding.PaddingRight = UDim.new(0, 6)
    	cardPadding.PaddingTop = UDim.new(0, 3)
    	cardPadding.PaddingBottom = UDim.new(0, 3)
    	cardPadding.Parent = card
    	local cardLayout = Instance.new('UIListLayout')
    	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    	cardLayout.Padding = UDim.new(0, 1)
    	cardLayout.Parent = card

    	local title = Instance.new('TextLabel')
    	title.Name = 'Title'
    	title.AutomaticSize = Enum.AutomaticSize.XY
    	title.BackgroundTransparency = 1
    	title.Font = Enum.Font.GothamBold
    	title.TextSize = 9
    	title.TextColor3 = Color3.fromRGB(180, 140, 255)
    	title.Text = 'Storage'
    	title.LayoutOrder = 1
    	title.Parent = card

    	local items = Instance.new('Frame')
    	items.Name = 'Items'
    	items.AutomaticSize = Enum.AutomaticSize.XY
    	items.BackgroundTransparency = 1
    	items.LayoutOrder = 2
    	local itemsLayout = Instance.new('UIListLayout')
    	itemsLayout.FillDirection = Enum.FillDirection.Horizontal
    	itemsLayout.Padding = UDim.new(0, 2)
    	itemsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    	itemsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    	itemsLayout.Parent = items
    	items.Parent = card

    	card.Parent = Folder
    	Reference[v] = card
    	Enabled[v] = false

    	Connections[v] = {
    		chest.ChildAdded:Connect(function()
    			refreshAdornee(v, card)
    		end),
    		chest.ChildRemoved:Connect(function()
    			refreshAdornee(v, card)
    		end),
    	}
    	task.spawn(refreshAdornee, v, card)
    end

    StorageESP = vape.Categories.Render:CreateModule({
    	Name = 'Storage ESP',
    	Function = function(callback)
    		if callback then
    			StorageESP:Clean(collectionService:GetInstanceAddedSignal('chest'):Connect(Added))
    			StorageESP:Clean(collectionService:GetInstanceRemovedSignal('chest'):Connect(Removing))
    			StorageESP:Clean(Clear)
    			StorageESP:Clean(runService.PreRender:Connect(function()
    				for obj, card in Reference do
    					local part, pos, headPos, headVis
    					if not Enabled[obj] then
    						card.Visible = false
    						continue
    					end
    					part = obj:IsA('Model') and (obj.PrimaryPart or obj:FindFirstChildWhichIsA('BasePart')) or obj
    					if not part then card.Visible = false continue end
    					pos = part.Position
    					headPos, headVis = gameCamera:WorldToViewportPoint(pos + Vector3.new(0, 3, 0))
    					card.Visible = headVis
    					if headVis then
    						card.Position = UDim2.fromOffset(headPos.X, headPos.Y)
    					end
    				end
    			end))
    			for _, v in collectionService:GetTagged('chest') do
    				task.spawn(Added, v)
    			end
    		else
    			Clear()
    		end
    	end,
    	Tooltip = 'Displays items in chests'
    })
    List = StorageESP:CreateTextList({
    	Name = 'Item',
    	Function = function()
    		for obj, card in Reference do
    			task.spawn(refreshAdornee, obj, card)
    		end
    	end,
    })
    Background = StorageESP:CreateToggle({
    	Name = 'Background',
    	Function = function(callback)
    		for _, card in Reference do
    			card.BackgroundTransparency = callback and 0.35 or 1
    		end
    	end,
    	Default = true
    })
end)

run(function()
    local old

    vape.Categories.Render:CreateModule({
    	Name = 'Stream Remover',
    	Function = function(call)
    		if call then
    			old = bedwars.GamePlayer.canSeeThroughDisguise
    			bedwars.GamePlayer.canSeeThroughDisguise = function()
    				return true
    			end
    		else
    			bedwars.GamePlayer.canSeeThroughDisguise = old
    			old = nil
    		end
    	end,
    	Tooltip = 'Disables player\'s streamer mode clientsidedly'
    })
end)

run(function()
    local TrapESP
    local Background

    local Reference = {}
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui

    local function Added(v)
    	local card = Instance.new('Frame')
    	card.AnchorPoint = Vector2.new(0.5, 1)
    	card.BackgroundColor3 = Color3.new()
    	card.BackgroundTransparency = Background.Enabled and 0.35 or 1
    	card.BorderSizePixel = 0
    	card.AutomaticSize = Enum.AutomaticSize.XY
    	card.Visible = false
    	local cardCorner = Instance.new('UICorner')
    	cardCorner.CornerRadius = UDim.new(0, 4)
    	cardCorner.Parent = card
    	local cardPadding = Instance.new('UIPadding')
    	cardPadding.PaddingLeft = UDim.new(0, 6)
    	cardPadding.PaddingRight = UDim.new(0, 6)
    	cardPadding.PaddingTop = UDim.new(0, 3)
    	cardPadding.PaddingBottom = UDim.new(0, 3)
    	cardPadding.Parent = card
    	local cardLayout = Instance.new('UIListLayout')
    	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    	cardLayout.FillDirection = Enum.FillDirection.Horizontal
    	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    	cardLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    	cardLayout.Padding = UDim.new(0, 4)
    	cardLayout.Parent = card

    	local img = Instance.new('ImageLabel')
    	img.Name = 'Icon'
    	img.Size = UDim2.fromOffset(12, 12)
    	img.BackgroundTransparency = 1
    	img.Image = bedwars.getIcon({ itemType = 'snap_trap' }, true)
    	img.LayoutOrder = 1
    	img.Parent = card

    	local info = Instance.new('TextLabel')
    	info.Name = 'Info'
    	info.AutomaticSize = Enum.AutomaticSize.XY
    	info.BackgroundTransparency = 1
    	info.Font = Enum.Font.GothamBold
    	info.TextSize = 9
    	info.TextColor3 = Color3.fromRGB(255, 100, 100)
    	info.Text = 'Trap'
    	info.RichText = true
    	info.LayoutOrder = 2
    	info.Parent = card

    	card.Parent = Folder
    	Reference[v] = card
    end

    TrapESP = vape.Categories.Render:CreateModule({
    	Name = 'Trap ESP',
    	Function = function(callback)
    		if callback then
    			repeat
    				task.wait()
    			until store.matchState ~= 0 or not TrapESP.Enabled
    			if not TrapESP.Enabled then
    				return
    			end

    			TrapESP:Clean(collectionService:GetInstanceAddedSignal('snap_trap'):Connect(Added))
    			TrapESP:Clean(collectionService:GetInstanceRemovedSignal('snap_trap'):Connect(function(v)
    				if Reference[v] then
    					Reference[v]:Destroy()
    					Reference[v] = nil
    				end
    			end))
    			TrapESP:Clean(runService.PreRender:Connect(function()
    				for obj, card in Reference do
    					local headPos, headVis = gameCamera:WorldToViewportPoint(obj.Position + Vector3.new(0, 2, 0))
    					card.Visible = headVis
    					if headVis then
    						local dist = entitylib.isAlive and math.floor((entitylib.character.RootPart.Position - obj.Position).Magnitude) or 0
    						card.Info.Text = 'Trap  <font color="rgb(130,130,130)">' .. dist .. 'm</font>'
    						card.Position = UDim2.fromOffset(headPos.X, headPos.Y)
    					end
    				end
    			end))
    		else
    			table.clear(Reference)
    			Folder:ClearAllChildren()
    		end
    	end,
    	Tooltip = 'Render traps placed by other teams'
    })
    Background = TrapESP:CreateToggle({
    	Name = 'Background',
    	Function = function(callback)
    		for _, card in Reference do
    			card.BackgroundTransparency = callback and 0.35 or 1
    		end
    	end,
    	Default = true
    })
end)

run(function()
    local TeslaESP
    local TeslaBG

    local Reference = {}
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui

    local function Added(v)
        task.delay(0.1, function()
            if not v.Parent then return end
            local placer = playersService:GetPlayerByUserId(v:GetAttribute('PlacedByUserId'))
            if placer and placer:GetAttribute('Team') == lplr:GetAttribute('Team') then return end

            local card = Instance.new('Frame')
            card.AnchorPoint = Vector2.new(0.5, 1)
            card.BackgroundColor3 = Color3.new()
            card.BackgroundTransparency = TeslaBG.Enabled and 0.35 or 1
            card.BorderSizePixel = 0
            card.AutomaticSize = Enum.AutomaticSize.XY
            card.Visible = false
            local cardCorner = Instance.new('UICorner')
            cardCorner.CornerRadius = UDim.new(0, 4)
            cardCorner.Parent = card
            local cardPadding = Instance.new('UIPadding')
            cardPadding.PaddingLeft = UDim.new(0, 6)
            cardPadding.PaddingRight = UDim.new(0, 6)
            cardPadding.PaddingTop = UDim.new(0, 3)
            cardPadding.PaddingBottom = UDim.new(0, 3)
            cardPadding.Parent = card
            local cardLayout = Instance.new('UIListLayout')
            cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
            cardLayout.FillDirection = Enum.FillDirection.Horizontal
            cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
            cardLayout.VerticalAlignment = Enum.VerticalAlignment.Center
            cardLayout.Padding = UDim.new(0, 4)
            cardLayout.Parent = card

            local img = Instance.new('ImageLabel')
            img.Name = 'Icon'
            img.Size = UDim2.fromOffset(12, 12)
            img.BackgroundTransparency = 1
            img.Image = bedwars.getIcon({ itemType = 'tesla_trap' }, true)
            img.LayoutOrder = 1
            img.Parent = card

            local info = Instance.new('TextLabel')
            info.Name = 'Info'
            info.AutomaticSize = Enum.AutomaticSize.XY
            info.BackgroundTransparency = 1
            info.Font = Enum.Font.GothamBold
            info.TextSize = 9
            info.TextColor3 = Color3.fromRGB(100, 160, 255)
            info.Text = 'Tesla'
            info.RichText = true
            info.LayoutOrder = 2
            info.Parent = card

            card.Parent = Folder
            Reference[v] = card
        end)
    end

    TeslaESP = vape.Categories.Render:CreateModule({
        Name = 'Tesla ESP',
        Function = function(callback)
            if callback then
                repeat task.wait() until store.matchState ~= 0 or not TeslaESP.Enabled
                if not TeslaESP.Enabled then return end

                for _, v in collectionService:GetTagged('tesla-trap') do
                    Added(v)
                end
                TeslaESP:Clean(collectionService:GetInstanceAddedSignal('tesla-trap'):Connect(Added))
                TeslaESP:Clean(collectionService:GetInstanceRemovedSignal('tesla-trap'):Connect(function(v)
                    if Reference[v] then
                        Reference[v]:Destroy()
                        Reference[v] = nil
                    end
                end))
                TeslaESP:Clean(runService.PreRender:Connect(function()
                    for obj, card in Reference do
                        local pos, vis = gameCamera:WorldToViewportPoint(obj.Position + Vector3.new(0, 2, 0))
                        card.Visible = vis
                        if vis then
                            local dist = entitylib.isAlive and math.floor((entitylib.character.RootPart.Position - obj.Position).Magnitude) or 0
                            card.Info.Text = 'Tesla  <font color="rgb(130,130,130)">' .. dist .. 'm</font>'
                            card.Position = UDim2.fromOffset(pos.X, pos.Y)
                        end
                    end
                end))
            else
                table.clear(Reference)
                Folder:ClearAllChildren()
            end
        end,
        Tooltip = 'Show enemy Tesla Traps through walls'
    })
    TeslaBG = TeslaESP:CreateToggle({
        Name = 'Background',
        Function = function(callback)
            for _, card in Reference do
                card.BackgroundTransparency = callback and 0.35 or 1
            end
        end,
        Default = true
    })
end)

run(function()
    local PotESP

    local Reference = {}
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui

    local function getPos(v)
        if v:IsA('Model') then
            local p = v.PrimaryPart or v:FindFirstChildWhichIsA('BasePart')
            return p and p.Position
        end
        return v:IsA('BasePart') and v.Position
    end

    local function Added(v)
        if Reference[v] then return end
        local label = Instance.new('TextLabel')
        label.Size = UDim2.fromOffset(60, 18)
        label.AnchorPoint = Vector2.new(0.5, 1)
        label.BackgroundColor3 = Color3.new(0, 0, 0)
        label.BackgroundTransparency = 0.4
        label.BorderSizePixel = 0
        label.TextSize = 12
        label.Font = Enum.Font.GothamBold
        label.TextColor3 = Color3.fromRGB(255, 210, 100)
        label.Text = 'Pot'
        label.Visible = false
        label.RichText = true
        local corner = Instance.new('UICorner')
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = label
        label.Parent = Folder
        Reference[v] = label
    end

    local function Removing(v)
        if Reference[v] then
            Reference[v]:Destroy()
            Reference[v] = nil
        end
    end

    PotESP = vape.Categories.Render:CreateModule({
        Name = 'Pot ESP',
        Function = function(callback)
            if callback then
                PotESP:Clean(workspace.DescendantAdded:Connect(function(v)
                    if v.Name == 'desert_pot' then
                        task.spawn(Added, v)
                    end
                end))
                PotESP:Clean(workspace.DescendantRemoving:Connect(Removing))
                PotESP:Clean(runService.PreRender:Connect(function()
                    local char = lplr.Character
                    local root = char and char:FindFirstChild('HumanoidRootPart')
                    for pot, label in Reference do
                        local screen, vis
                        local pos = getPos(pot)
                        if not pos then label.Visible = false continue end
                        screen, vis = gameCamera:WorldToViewportPoint(pos + Vector3.new(0, 2, 0))
                        label.Visible = vis
                        if vis then
                            local dist = root and math.round((root.Position - pos).Magnitude) or 0
                            label.Text = string.format('Pot <font color="#aaaaaa">• %dm</font>', dist)
                            local size = getfontsize(removeTags(label.Text), label.TextSize, label.FontFace, Vector2.new(100000, 100000))
                            label.Size = UDim2.fromOffset(size.X + 10, size.Y + 6)
                            label.Position = UDim2.fromOffset(screen.X, screen.Y)
                        end
                    end
                end))
                for _, v in workspace:GetDescendants() do
                    if v.Name == 'desert_pot' then
                        task.spawn(Added, v)
                    end
                end
            else
                table.clear(Reference)
                Folder:ClearAllChildren()
            end
        end,
        Tooltip = 'Shows desert pots with distance'
    })
end)

run(function()
    local ViewmodelVisuals
    local StrokeColor
    local Color
    
    local Instances = {}
    
    ViewmodelVisuals = vape.Categories.Render:CreateModule({
        Name = 'Viewmodel Visuals',
        Function = function(call)
            if call then
                local viewmodel = gameCamera:WaitForChild('Viewmodel', 9e9)
                if not ViewmodelVisuals.Enabled then
                    return
                end
    
                for i,v in viewmodel:GetChildren() do
                    if v:IsA('Accessory') then
                        local highlight = v.Handle:FindFirstChildOfClass('Highlight') or Instance.new('Highlight', v.Handle)
                        highlight.FillColor = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
                        highlight.FillTransparency = Color.Opacity
                        highlight.OutlineTransparency = StrokeColor.Opacity
                        highlight.OutlineColor = Color3.fromHSV(StrokeColor.Hue, StrokeColor.Sat, StrokeColor.Value)
    
                        ViewmodelVisuals:Clean(highlight)
                        table.insert(Instances, highlight)
    
                        break
                    end
                end
    
                ViewmodelVisuals:Clean(viewmodel.ChildAdded:Connect(function(visual)
                    if visual:IsA('Accessory') then
                        local highlight = visual.Handle:FindFirstChildOfClass('Highlight') or Instance.new('Highlight', visual.Handle)
                        highlight.FillColor = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
                        highlight.FillTransparency = Color.Opacity
                        highlight.OutlineTransparency = StrokeColor.Opacity
                        highlight.OutlineColor = Color3.fromHSV(StrokeColor.Hue, StrokeColor.Sat, StrokeColor.Value)
                        
                        ViewmodelVisuals:Clean(highlight)
                        table.insert(Instances, highlight)
                    end
                end))
    
                ViewmodelVisuals:Clean(gameCamera.ChildAdded:Connect(function(visual)
                    if visual.Name == 'Viewmodel' then
                        ViewmodelVisuals:Toggle()
                        ViewmodelVisuals:Toggle()
                    end
                end))
            end
        end
    })
    
    Color = ViewmodelVisuals:CreateColorSlider({
        Name = 'Color',
        Default = Color3.new(1, 1, 1),
        Function = function(hue, sat, val, opacity)
            for _, v in Instances do
                v.FillColor = Color3.fromHSV(hue, sat, val)
                v.FillTransparency = opacity
            end
        end
    })
    StrokeColor = ViewmodelVisuals:CreateColorSlider({
        Name = 'Stroke Color',
        Default = Color3.new(),
        Function = function(hue, sat, val, opacity)
            for _, v in Instances do
                v.OutlineColor = Color3.fromHSV(hue, sat, val)
                v.OutlineTransparency = opacity
            end
        end
    })
end)

run(function()
    local LegacyAnimation

    local function isFirstPerson()
        local char = lplr.Character
        if not char then return false end
        local head = char:FindFirstChild('Head')
        if not head then return false end
        return head.LocalTransparencyModifier == 1
    end

    LegacyAnimation = vape.Categories.Render:CreateModule({
        Name = 'LegacyAnimation',
        Function = function(callback)
            if callback then
                local frameCounter = 0
                workspace:SetAttribute('RbxLegacyAnimationBlending', not isFirstPerson())
                LegacyAnimation:Clean(runService.Heartbeat:Connect(function()
                    frameCounter = frameCounter + 1
                    if frameCounter % 6 == 0 then
                        workspace:SetAttribute('RbxLegacyAnimationBlending', not isFirstPerson())
                    end
                end))
            else
                workspace:SetAttribute('RbxLegacyAnimationBlending', false)
            end
        end,
        Tooltip = 'Enables legacy animation blending in 3rd person only'
    })
end)

run(function()
    local KingAuto
    local BrightnessSlider
    -- Block overhaul
    local saved = {}
    local stash = Instance.new('Folder')
    stash.Name = 'KingAutoStash'
    stash.Parent = vape.gui
    -- Lighting / sky
    local lightStash = Instance.new('Folder')
    lightStash.Name = 'KingAutoLightStash'
    lightStash.Parent = vape.gui
    local addedLighting = {}
    local origLighting = {}
    local origCloudEnabled = nil
    local hasFF = false
    local savedLightProps = {'Ambient','OutdoorAmbient','Brightness','ExposureCompensation','FogColor','FogEnd','FogStart','GlobalShadows'}

    local C = Color3.fromRGB
    local blockColors = {
        -- Wool
        wool_white = C(184,184,184), wool_red    = C(140, 47, 47),
        wool_blue  = C( 47, 79,140), wool_green  = C( 47,107, 58),
        wool_yellow = C(140,122, 47), wool_cyan  = C( 47,140,140),
        wool_pink  = C(140, 58,107), wool_orange = C(140, 74, 47),
        wool_purple = C( 90, 47,140), wool_brown = C(107, 74, 47),
        wool_builder = C(184,184,184),
        -- Stone / rock
        stone        = C( 74, 74, 74), stone_brick  = C( 63, 63, 63),
        cobblestone  = C( 58, 58, 58), stone_slab   = C( 63, 63, 63),
        stone_tiles  = C( 58, 58, 58), stone_pillar = C( 74, 74, 74),
        stone_player_block = C( 74, 74, 74), stone_brick_builder = C( 63, 63, 63),
        granite          = C( 90, 74, 69), granite_polished  = C(106, 90, 85),
        diorite          = C(106,106,106), diorite_polished  = C(122,122,122),
        andesite         = C( 80, 80, 80), andesite_polished = C( 90, 90, 90),
        marble       = C(106,106,106), marble_pillar = C(106,106,106),
        limestone    = C(138,126,106),
        slate_brick  = C( 47, 47, 47), slate_tiles  = C( 47, 47, 47),
        galactite    = C( 47, 42, 74), galactite_brick = C( 47, 42, 74),
        kobblak      = C( 58, 58, 74), void_grass   = C( 42, 42, 42),
        altar_block_one = C( 74, 74, 74), altar_block_two   = C( 74, 74, 74),
        altar_block_three = C( 74, 74, 74), broken_altar_block = C( 74, 74, 74),
        -- Wood
        oak_log          = C(107, 74, 47), spruce_log      = C( 74, 53, 38),
        birch_log        = C(122,106, 74), hickory_log     = C( 74, 53, 38),
        wood_plank_oak   = C(107, 74, 47), wood_plank_oak_builder = C(107, 74, 47),
        wood_plank_birch = C(122,106, 74), wood_plank_spruce = C( 74, 53, 38),
        wood_plank_maple = C(107, 74, 47), bookshelf       = C( 90, 58, 42),
        -- Earth / terrain
        dirt         = C( 75, 58, 42), grass         = C( 47, 90, 47),
        sand         = C(122,111, 74), red_sand      = C(122, 74, 58),
        sandstone    = C(111,102, 80), sandstone_smooth    = C(122,114, 90),
        sandstone_polished = C(111,102, 80),
        red_sandstone = C(111, 74, 63), red_sandstone_smooth = C(122, 90, 79),
        red_sandstone_polished = C(111, 74, 63),
        moss_block   = C( 47, 95, 58), clay          = C(107, 90, 90),
        haybale      = C(140,122, 47),
        -- Clay variants
        clay_black  = C( 42, 42, 42), clay_white  = C(184,184,184),
        clay_red    = C(140, 47, 47), clay_blue   = C( 47, 79,140),
        clay_green  = C( 47,107, 58), clay_yellow = C(140,122, 47),
        clay_cyan   = C( 47,140,140), clay_pink   = C(140, 58,107),
        clay_orange = C(140, 74, 47), clay_purple = C( 90, 47,140),
        clay_dark_brown = C( 74, 53, 38), clay_dark_green = C( 47, 90, 47),
        clay_light_brown = C(107, 74, 47), clay_light_green = C( 47,140, 90),
        clay_gray   = C( 80, 80, 80), clay_tan    = C(122,111, 74),
        -- Glass / ice / misc terrain
        brick        = C(106, 47, 47),
        glass        = C(154,167,176), magic_glass   = C(154,167,176),
        ice          = C( 79,111,140), snow          = C(176,184,192),
        snow_pile    = C(176,184,192),
        glowstone    = C(140,122, 47), magma_block   = C(140, 58, 31),
        concrete_green = C( 47,107, 58), blue_tile   = C( 47, 79,140),
        -- Defense
        obsidian     = C( 26, 15, 46), bedrock       = C( 42, 42, 42),
        ceramic      = C( 90, 90,106), barrier       = C( 15, 15, 15),
        -- Metal / ore blocks
        iron_block   = C(138,138,138), iron_ore         = C(138,138,138),
        iron_ore_mesh_block = C(138,138,138),
        gold_block   = C(140,122, 47), diamond_block    = C( 47,111,140),
        emerald_block = C( 47,140, 90), copper_block    = C(140, 90, 58),
        steel_block  = C( 74, 79, 90), guilded_iron     = C(122,106, 74),
        diamond_ore  = C( 47,111,140), emerald_ore      = C( 47,140, 90),
        diamond_capture_block = C( 47,111,140),
        -- Beds / team
        bed          = C(140, 47, 58), og_bed        = C(140, 47, 58),
        royale_bed   = C(140, 47, 58), fake_bed      = C( 90, 31, 37),
        team_door    = C( 58, 58, 58),
        -- Utility
        enchant_table         = C( 47, 42, 74),
        enchant_table_glitched = C( 47, 42, 74),
        broken_enchant_table  = C( 47, 42, 74),
        forge        = C( 74, 58, 47), chest         = C( 90, 63, 42),
        personal_chest = C( 74, 51, 37), og_personal_chest = C( 74, 51, 37),
        brewing_cauldron = C( 47, 74, 74), barrel    = C(107, 74, 47),
        drawbridge   = C( 58, 74, 90), christmas_drawbridge = C( 58, 74, 90),
        scaffold     = C( 90, 74, 53), christmas_scaffold   = C( 90, 74, 53),
        zipline_base = C( 47, 90, 90), jump_pad      = C( 74, 90, 47),
        gumdrop_bounce_pad = C( 74, 90, 47),
        camera_turret = C( 58, 58, 74), lasso_hook   = C( 90, 74, 53),
        ladder       = C(107, 74, 47), vine_ladder   = C( 47,106, 58),
        survival_crate = C( 90, 63, 42), team_crate  = C( 90, 63, 42),
        juggernaut_crate = C(138,138,138),
        solar_panel  = C( 74, 79, 90), satellite_dish = C(138,138,138),
        healing_fountain = C( 47,140, 90), healing_turret = C( 47,140, 90),
        -- Combat / traps
        tnt          = C(140, 58, 47), siege_tnt     = C(106, 42, 31),
        snap_trap    = C( 74, 31, 47), invisible_landmine = C( 10, 10, 10),
        tesla_trap   = C( 47, 47,106), void_turret   = C( 26, 10, 42),
        spike_trap   = C( 58, 26, 26), grave_trap    = C( 58, 26, 26),
        grave_trap_block = C( 58, 26, 26),
        volatile_stone   = C(140, 58, 47),
        exploding_tank_block = C(140, 58, 47),
        lightning_coil   = C( 47, 47,106),
        -- Cannons / machines
        cannon       = C( 74, 74, 90), auto_cannon    = C( 74, 74, 90),
        manual_cannon = C( 74, 74, 90), ballista      = C( 74, 74, 90),
        classic_auto_turret = C( 74, 74, 90), spread_cannon = C( 74, 74, 90),
        classic_shock_wave_turret = C( 74, 74, 90), squad_launcher = C( 74, 74, 90),
        party_cannon = C( 90, 42, 42), firework_crate = C( 90, 42, 42),
        vending_machine = C( 58, 58, 74), snow_cone_machine = C( 74,106,122),
        broken_snow_cone_machine = C( 74,106,122),
        target_dummy_block_tier_1 = C(138,138,138),
        target_dummy_block_tier_2 = C( 47,111,140),
        target_dummy_block_tier_3 = C( 47,140, 90),
        target_dummy_block_tier_4 = C(122,106, 74),
        -- Lucky blocks
        lucky_block  = C(140,122, 47), cosmic_lucky_block   = C( 90, 47,140),
        flying_lucky_block = C( 47,111,140), food_lucky_block = C(140, 90, 47),
        huge_lucky_block = C(122,106, 47), lucky_block_trap  = C(106, 31, 47),
        forge_lucky_block = C( 74, 58, 47),
        lucky_block_item_smelter = C( 74, 58, 47),
        halloween_lucky_block = C(106, 31, 47),
        growing_halloween_lucky_block = C(106, 31, 47),
        purple_lucky_block = C( 90, 47,140),
        rainbow_lucky_block = C(140,122, 47),
        new_years_lucky_block = C( 47,140,106),
        new_years_lucky_block_2024 = C( 47,140,106),
        magical_hero_lucky_block = C( 90, 47,140),
        glitched_lucky_block = C( 15, 15, 15),
        -- Special / Kit
        beehive      = C(140,122, 47), chicken_egg_block = C(176,160,122),
        egg_block    = C(176,160,122), fisherman_coral   = C( 47,140,122),
        pinata       = C(140, 58,107), smoke_block       = C( 58, 58, 58),
        damage_banner = C(140, 47, 47), heal_banner      = C( 47,140, 58),
        defense_banner = C( 47, 74,140),
        aquamarine_lantern = C( 47,140,140), lantern_block = C(140,122, 47),
        nest         = C( 74, 58, 47), nest_deposit_block = C( 74, 58, 47),
        pirate_gunpowder_barrel = C(140, 58, 47),
        sacrophagus  = C(111,102, 80), desert_pot        = C(122,111, 74),
        scarab_portal = C(122,111, 74),
        cake_one     = C(176,160,122), cake_three    = C(176,160,122),
        -- Nature / decoration
        large_bush   = C( 47,106, 58), small_bush    = C( 47,106, 58),
        flower_purple = C(106, 58,106), pumpkin      = C(140, 74, 47),
        pumpkin_block = C(140, 74, 47), melon        = C( 47,106, 58),
        carrot       = C(140, 74, 47),
        crystalheart_flower = C( 47,140,122),
        soulvine_flower = C( 90, 47,140), tearbloom_flower = C( 47,140,122),
        radioactive_plant = C( 47,140, 90),
        slime_block  = C( 47,106, 58), spider_web    = C( 90, 90, 90),
        spider_queen_web = C( 90, 90, 90),
        -- Void / dark
        void_block   = C( 10, 10, 10), void_bait     = C( 10, 10, 10),
        invisible_block = C( 10, 10, 10),
        void_portal  = C(  5,  5,  5), void_teleport_portal = C( 26, 26, 42),
        teleport_block = C( 26, 26, 42),
        styx_entrance_portal = C( 26, 10, 42), styx_exit_portal = C( 26, 10, 42),
        void_dirt    = C( 42, 26, 10), void_growth   = C( 26, 10, 42),
        -- Misc / special
        gum_block    = C(106, 90,122), dragon_egg    = C( 47, 47, 74),
        fire_sheep_statue = C( 74, 31, 31),
        excalibur    = C(138,138,138),
        spawn_gadget = C(138,138,138),
        global_generator_gadget = C(140,122, 47),
        team_generator_gadget   = C(140,122, 47),
        merchant_region_block   = C(140,122, 47),
        black_market_shop       = C( 42, 42, 42),
        defense_scanner_block_snapping = C( 47, 74,140),
        jellyfish_block_snapping = C( 47,140,140),
        pirate_flag  = C( 42, 42, 42),
    }

    local function applyPart(part, colorOverride)
        if saved[part] or part.Material == Enum.Material.Neon or part.Material == Enum.Material.ForceField then return end
        if part.Name ~= 'Handle' then
            for _, child in part:GetChildren() do
                if child:IsA('SurfaceAppearance') or child:IsA('Decal') or child:IsA('Texture') then
                    pcall(function() child:Destroy() end)
                end
            end
        end
        local origMat   = part.Material
        local origColor = part.Color
        pcall(function() part.Material = Enum.Material.SmoothPlastic end)
        if colorOverride then pcall(function() part.Color = colorOverride end) end
        saved[part] = { Material = origMat, Color = origColor }
    end

    local function restorePart(part)
        local entry = saved[part]
        if not entry then return end
        pcall(function() part.Material = entry.Material end)
        pcall(function() part.Color    = entry.Color end)
        saved[part] = nil
    end

    local function scanBlock(model, col)
        if model:IsA('BasePart') then pcall(applyPart, model, col) end
        for _, v in model:GetDescendants() do
            if v:IsA('BasePart') then pcall(applyPart, v, col) end
        end
    end

    KingAuto = vape.Categories.Render:CreateModule({
        Name = 'King Auto',
        Tooltip = 'Flat blocks + grey sky + full bright + no clouds',
        Function = function(callback)
            if callback then
                repeat task.wait() until store.map or not KingAuto.Enabled
                if not KingAuto.Enabled then return end

                -- FFlags: if executor supports them, kill textures at engine level (no RenderStepped needed)
                hasFF = type(setfflag) == 'function' and pcall(setfflag, 'RenderShadowIntensity', '0')
                if hasFF then
                    pcall(setfflag, 'PartTexturePackTable2022', '{}')
                    pcall(setfflag, 'PartTexturePackTablePre2022', '{}')
                    pcall(setfflag, 'TextureCompositorActiveJobs', '0')
                    pcall(setfflag, 'FRMQualityLevelOverride', '1')
                    pcall(setfflag, 'GrassMaxDistance', '0')
                    pcall(setfflag, 'CSGLevelOfDetailSwitchingDistance', '0')
                    pcall(setfflag, 'CSGLevelOfDetailSwitchingDistanceL12', '0')
                    pcall(setfflag, 'CSGLevelOfDetailSwitchingDistanceL23', '0')
                    pcall(setfflag, 'CSGLevelOfDetailSwitchingDistanceL34', '0')
                    pcall(setfflag, 'DebugPauseVoxelizer', 'True')
                    pcall(setfflag, 'RenderLocalLightUpdatesMax', '0')
                    pcall(setfflag, 'RenderLocalLightUpdatesMin', '0')
                end

                -- === Block overhaul ===
                local blocks = store.map:FindFirstChild('Blocks')
                if blocks then
                    for _, blockModel in blocks:GetChildren() do
                        pcall(scanBlock, blockModel, blockColors[blockModel.Name])
                    end
                end
                for _, v in store.map:GetDescendants() do
                    if v:IsA('BasePart') then pcall(applyPart, v, nil) end
                end
                local function flattenPart(part, col)
                    part.LocalTransparencyModifier = 1
                    pcall(applyPart, part, col)
                    task.defer(function()
                        if part.Parent then part.LocalTransparencyModifier = 0 end
                    end)
                end
                KingAuto:Clean(store.map.Blocks.ChildAdded:Connect(function(v)
                    if not KingAuto.Enabled then return end
                    local col = blockColors[v.Name]
                    for _, p in v:GetDescendants() do
                        if p:IsA('BasePart') then p.LocalTransparencyModifier = 1 end
                    end
                    pcall(scanBlock, v, col)
                    task.defer(function()
                        for _, p in v:GetDescendants() do
                            if p:IsA('BasePart') and p.Parent then
                                p.LocalTransparencyModifier = 0
                            end
                        end
                    end)
                    KingAuto:Clean(v.DescendantAdded:Connect(function(d)
                        if not KingAuto.Enabled then return end
                        if d:IsA('BasePart') then
                            flattenPart(d, col)
                        elseif d:IsA('SurfaceAppearance') or d:IsA('Decal') or d:IsA('Texture') then
                            pcall(function() d:Destroy() end)
                        end
                    end))
                end))
                local function getToolBlockColor(inst, char)
                    local p = inst.Parent
                    while p and p ~= char do
                        if blockColors[p.Name] then return blockColors[p.Name] end
                        p = p.Parent
                    end
                    return blockColors[inst.Name]
                end
                local function watchChar(char)
                    for _, v in char:GetDescendants() do
                        if v:IsA('BasePart') then
                            local col = getToolBlockColor(v, char)
                            if col then pcall(applyPart, v, col) end
                        end
                    end
                    KingAuto:Clean(char.DescendantAdded:Connect(function(v)
                        if not KingAuto.Enabled then return end
                        if v:IsA('BasePart') then
                            local col = getToolBlockColor(v, char)
                            if col then flattenPart(v, col) end
                        elseif v:IsA('SurfaceAppearance') or v:IsA('Decal') or v:IsA('Texture') then
                            pcall(function() v:Destroy() end)
                        end
                    end))
                end
                if lplr.Character then watchChar(lplr.Character) end
                KingAuto:Clean(lplr.CharacterAdded:Connect(function(newChar)
                    if KingAuto.Enabled then watchChar(newChar) end
                end))

                -- First-person ViewModel lives under Camera, not the character
                local cam = workspace.CurrentCamera
                local function flattenCamDescendant(v)
                    if v:IsA('SurfaceAppearance') or v:IsA('Decal') or v:IsA('Texture') then
                        pcall(function() v:Destroy() end)
                    elseif v:IsA('BasePart') then
                        local col = getToolBlockColor(v, cam)
                        if col then flattenPart(v, col) end
                    end
                end
                for _, v in cam:GetDescendants() do flattenCamDescendant(v) end
                KingAuto:Clean(cam.DescendantAdded:Connect(function(v)
                    if KingAuto.Enabled then flattenCamDescendant(v) end
                end))
                local function hasBlockAncestor(inst)
                    local p = inst.Parent
                    while p and p ~= workspace do
                        if blockColors[p.Name] then return blockColors[p.Name] end
                        p = p.Parent
                    end
                end
                KingAuto:Clean(workspace.DescendantAdded:Connect(function(v)
                    if not KingAuto.Enabled then return end
                    if v:IsA('SurfaceAppearance') or v:IsA('Decal') or v:IsA('Texture') then
                        if hasBlockAncestor(v) then pcall(function() v:Destroy() end) end
                    elseif v:IsA('Model') and blockColors[v.Name] then
                        pcall(scanBlock, v, blockColors[v.Name])
                    elseif v:IsA('BasePart') and not saved[v] then
                        local col = hasBlockAncestor(v) or blockColors[v.Name]
                        if col then flattenPart(v, col) end
                    end
                end))
                if not hasFF then
                    KingAuto:Clean(game:GetService('RunService').RenderStepped:Connect(function()
                        if not KingAuto.Enabled then return end
                        local blks = store.map:FindFirstChild('Blocks')
                        if not blks then return end
                        for _, v in blks:GetDescendants() do
                            if v:IsA('SurfaceAppearance') or v:IsA('Decal') or v:IsA('Texture') then
                                pcall(function() v:Destroy() end)
                            end
                        end
                    end))
                end

                -- === Grey sky + full bright + no clouds ===
                for _, p in savedLightProps do
                    origLighting[p] = lightingService[p]
                end
                -- Remove ALL sky/atmosphere/bloom/sunrays so game can't restore them
                for _, child in lightingService:GetChildren() do
                    if child:IsA('Sky') or child:IsA('Atmosphere') or child:IsA('BloomEffect') or child:IsA('SunRaysEffect') then
                        child.Parent = lightStash
                    end
                end
                -- Disable workspace clouds (Terrain.Clouds)
                local terrain = workspace:FindFirstChildOfClass('Terrain')
                if terrain then
                    local clouds = terrain:FindFirstChildOfClass('Clouds')
                    if clouds then
                        origCloudEnabled = clouds.Enabled
                        clouds.Enabled = false
                    end
                end
                lightingService.Ambient              = Color3.fromRGB(120, 120, 120)
                lightingService.OutdoorAmbient       = Color3.fromRGB(100, 100, 100)
                lightingService.Brightness           = BrightnessSlider.Value
                lightingService.ExposureCompensation = -0.3
                lightingService.GlobalShadows        = false
                lightingService.FogColor             = Color3.fromRGB(140, 140, 140)
                lightingService.FogEnd               = 1200
                lightingService.FogStart             = 600
                -- High density so sky background appears solid grey
                local atmo = Instance.new('Atmosphere')
                atmo.Density = 0.85
                atmo.Color   = Color3.fromRGB(145, 145, 145)
                atmo.Decay   = Color3.fromRGB(125, 125, 125)
                atmo.Glare   = 0
                atmo.Haze    = 0
                atmo.Offset  = 0
                atmo.Parent  = lightingService
                table.insert(addedLighting, atmo)
                -- If game tries to re-add a Sky, immediately remove it
                KingAuto:Clean(lightingService.ChildAdded:Connect(function(child)
                    if child:IsA('Sky') or (child:IsA('Atmosphere') and child ~= atmo) then
                        child.Parent = lightStash
                    end
                end))
                -- Fight game resets of Lighting/Fog properties
                local lightChanged = false
                KingAuto:Clean(lightingService.Changed:Connect(function(prop)
                    if lightChanged then return end
                    if prop == 'FogEnd' or prop == 'FogStart' or prop == 'FogColor' or
                       prop == 'Ambient' or prop == 'OutdoorAmbient' or prop == 'Brightness' or
                       prop == 'ExposureCompensation' or prop == 'GlobalShadows' then
                        lightChanged = true
                        lightingService.Ambient              = Color3.fromRGB(120, 120, 120)
                        lightingService.OutdoorAmbient       = Color3.fromRGB(100, 100, 100)
                        lightingService.Brightness           = BrightnessSlider.Value
                        lightingService.ExposureCompensation = -0.3
                        lightingService.GlobalShadows        = false
                        lightingService.FogColor             = Color3.fromRGB(140, 140, 140)
                        lightingService.FogEnd               = 1200
                        lightingService.FogStart             = 600
                        lightChanged = false
                    end
                end))
            else
                -- Restore FFlags (only if they were set)
                if hasFF then
                    pcall(setfflag, 'TextureCompositorActiveJobs', '8')
                    pcall(setfflag, 'RenderShadowIntensity', '1')
                    pcall(setfflag, 'FRMQualityLevelOverride', '0')
                    pcall(setfflag, 'GrassMaxDistance', '100')
                    pcall(setfflag, 'CSGLevelOfDetailSwitchingDistance', '250')
                    pcall(setfflag, 'CSGLevelOfDetailSwitchingDistanceL12', '400')
                    pcall(setfflag, 'CSGLevelOfDetailSwitchingDistanceL23', '600')
                    pcall(setfflag, 'CSGLevelOfDetailSwitchingDistanceL34', '800')
                    pcall(setfflag, 'DebugPauseVoxelizer', 'False')
                    pcall(setfflag, 'RenderLocalLightUpdatesMax', '8')
                    pcall(setfflag, 'RenderLocalLightUpdatesMin', '6')
                end
                -- Restore blocks
                for part in saved do restorePart(part) end
                table.clear(saved)
                -- Restore lighting
                for _, v in addedLighting do v:Destroy() end
                table.clear(addedLighting)
                for _, child in lightStash:GetChildren() do
                    child.Parent = lightingService
                end
                for _, p in savedLightProps do
                    lightingService[p] = origLighting[p]
                end
                table.clear(origLighting)
                -- Restore clouds
                local terrain = workspace:FindFirstChildOfClass('Terrain')
                if terrain then
                    local clouds = terrain:FindFirstChildOfClass('Clouds')
                    if clouds and origCloudEnabled ~= nil then
                        clouds.Enabled = origCloudEnabled
                        origCloudEnabled = nil
                    end
                end
            end
        end,
    })
    BrightnessSlider = KingAuto:CreateSlider({
        Name = 'Brightness',
        Min = 0,
        Max = 10,
        Default = 2,
        Tooltip = 'Controls how bright the grey sky looks',
    })
end)

run(function()
    local NoShadows
    local origGlobalShadows

    NoShadows = vape.Categories.Render:CreateModule({
        Name = 'No Shadows',
        Tooltip = 'Removes all shadows from the map',
        Function = function(callback)
            if callback then
                origGlobalShadows = lightingService.GlobalShadows
                lightingService.GlobalShadows = false
            else
                lightingService.GlobalShadows = origGlobalShadows
            end
        end,
    })
end)


--[[
    Utility
]]

run(function()
	local AntiLasso
	local Chance
	local Check
	
	local function Added(ent)
		AntiLasso:Clean(ent.ChildAdded:Connect(function(v)
			if v:IsA('Accessory') and v:FindFirstChild('Rope') and Random.new(os.clock()):NextNumber(1, 100) < Chance.Value and (not Check.Enabled or entitylib.EntityPosition({
				Range = 50,
				Part = 'RootPart',
				Players = true
			})) then
				ent.PrimaryPart.Anchored = true
				v.Destroying:Once(function()
					task.wait(0.5)
					ent.PrimaryPart.Anchored = false
				end)
			end
		end))
	end
	
	AntiLasso = vape.Categories.Utility:CreateModule({
		Name = 'AntiLasso',
		Function = function(callback)
			if callback then
				AntiLasso:Clean(entitylib.Events.LocalAdded:Connect(function(ent)
					task.delay(1, function()
						Added(ent.Character)
					end)
				end))
				if entitylib.isAlive then
					Added(lplr.Character)
				end
			end
		end,
		Tooltip = 'Prevents you from getting pulled by lasso projectile.'
	})
	Chance = AntiLasso:CreateSlider({
		Name = 'Chance',
		Min = 0,
		Max = 100,
		Default = 100,
		Suffix = '%'
	})
	Check = AntiLasso:CreateToggle({Name = 'Only when targeting'})
end)

run(function()
    local AutoReset

    AutoReset = vape.Categories.Utility:CreateModule({
        Name = 'Auto Reset',
        Tooltip = 'Instantly resets your character',
        Function = function(callback)
            if callback then
                if entitylib.character and entitylib.character.Humanoid then
                    entitylib.character.Humanoid.Health = 0
                end
                AutoReset:Toggle()
            end
        end,
    })
end)

run(function()
    local AntiSuffocate
    
    AntiSuffocate = vape.Categories.Utility:CreateModule({
    	Name = 'Anti Suffocate',
    	Function = function(call)
    		if call then
    			repeat
    				if entitylib.isAlive then
    					if
    						getPlacedBlock(entitylib.character.RootPart.Position)
    						and (
    							getPlacedBlock(entitylib.character.RootPart.Position + Vector3.new(0, 2, 0))
    							and getPlacedBlock(entitylib.character.RootPart.Position - Vector3.new(0, 2, 0))
    						)
    					then
    						entitylib.character.RootPart.CFrame = entitylib.character.RootPart.CFrame + Vector3.new(0, 0.5, 0)
    						if entitylib.character.RootPart.AssemblyLinearVelocity.Y < -1 then
    							entitylib.character.RootPart.AssemblyLinearVelocity = Vector3.zero
    						end
    					end
    				end
    				task.wait()
    			until not AntiSuffocate.Enabled
    		end
    	end,
    	Tooltip = 'Prevents you from suffocating in blocks',
    })
end)


run(function()
    local AutoBalloon
    
    AutoBalloon = vape.Categories.Utility:CreateModule({
        Name = 'Auto Balloon',
        Function = function(callback)
            if callback then
                repeat task.wait() until store.matchState ~= 0 or (not AutoBalloon.Enabled)
                if not AutoBalloon.Enabled then return end
    
                local lowestpoint = math.huge
                for _, v in store.blocks do
                    local point = (v.Position.Y - (v.Size.Y / 2)) - 50
                    if point < lowestpoint then 
                        lowestpoint = point 
                    end
                end
    
                repeat
                    if entitylib.isAlive then
                        if entitylib.character.RootPart.Position.Y < lowestpoint and (lplr.Character:GetAttribute('InflatedBalloons') or 0) < 3 then
                            local balloon = getItem('balloon')
                            if balloon then
                                for _ = 1, 3 do 
                                    bedwars.BalloonController:inflateBalloon() 
                                end
                            end
                            task.wait(0.1)
                        end
                    end
                    task.wait(0.1)
                until not AutoBalloon.Enabled
            end
        end,
        Tooltip = 'Inflates when you fall into the void'
    })
end)

run(function()
    local AutoCounter
    local Mode
    local Range
    local Limit
    local AutoSwitch
    
    local function getAttackData()
        if Limit.Enabled then
            local tool = store.hand.tool
            return tool and tool.Name == 'tnt' and tool or nil
        end
        local item = getItem('tnt')
        return item and item.tool or nil
    end
    
    AutoCounter = vape.Categories.Utility:CreateModule({
        Name = 'Auto Counter TNT',
        Function = function(callback)
            if callback then
                local tnts, placed = {}, {}
                AutoCounter:Clean(workspace.ChildAdded:Connect(function(v)
                    if v.Name == 'tnt' then
                        table.insert(tnts, v)
                        AutoCounter:Clean(v.Destroying:Connect(function()
                            local index = table.find(tnts, v)
                            if index then
                                table.remove(tnts, index)
                            end
                        end))
                    end
                end))
                repeat
                    if entitylib.isAlive then
                        local item = getAttackData()
                        if item then
                            local localPosition = entitylib.character.RootPart.Position
                            for _, v in tnts do
                                if v.Velocity.Y >= 0 and not table.find(placed, Vector3.new(math.round(v.Position.X), math.round(v.Position.Y), math.round(v.Position.Z))) and (localPosition - v.Position).Magnitude <= Range.Value then
                                    if not Limit.Enabled and AutoSwitch.Enabled then
                                        local hotbar = getHotbar(item)
                                        switchItem(item)
                                        if hotbar then
                                            hotbarSwitch(hotbar)
                                        end
                                    end
                                    table.insert(placed, Vector3.new(math.round(v.Position.X), math.round(v.Position.Y), math.round(v.Position.Z)))
                                    task.spawn(bedwars.placeBlock, v.Position, item.Name)
                                    task.wait(0.12)
                                end
                            end
                        end
                    end
                    task.wait(0.1)
                until not AutoCounter.Enabled
            end
        end,
        Tooltip = 'Automatically places tnt on opponent\'s tnt'
    })
    
    Mode = AutoCounter:CreateDropdown({
        Name = 'Mode',
        List = {'Toggle', 'On key'},
        Default = 'Toggle'
    })
    Range = AutoCounter:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 60,
        Default = 30
    })
    Limit = AutoCounter:CreateToggle({
        Name = 'Limit to item',
        Function = function(callback)
            pcall(function()
                AutoSwitch.Object.Visible = not callback
            end)
        end
    })
    AutoSwitch = AutoCounter:CreateToggle({
        Name = 'Auto Switch',
        Function = function(callback)
            Limit.Object.Visible = not callback
        end,
        Default = true
    })
end)

run(function()
    local AutoLasso
    local Targets
    local Range
    local Angle
    
    local projectileRemote, lastshot = {InvokeServer = function() end}, tick()
    task.spawn(function()
        projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
    end)
    
    local rayCheck = RaycastParams.new()
    
    AutoLasso = vape.Categories.Utility:CreateModule({
        Name = 'Auto Lasso',
        Function = function(callback)
            if callback then
                repeat
                    if entitylib.isAlive and tick() > lastshot then
                        local lasso = getItem('lasso')
                        if lasso then
                            local ent = entitylib.EntityPosition({
                                Range = Range.Value,
                                Part = 'RootPart',
                                Wallcheck = Targets.Walls.Enabled,
                                Players = Targets.Players.Enabled,
                                NPCs = Targets.NPCs.Enabled,
                                Sort = sortmethods.Distance
                            })
    
                            if ent then
                                local selfpos = entitylib.character.RootPart.Position
                                local localfacing = gameCamera.CFrame.LookVector * Vector3.new(1, 0, 1)
                                local delta = (ent.RootPart.Position - selfpos) * Vector3.new(1, 0, 1)
                                if delta.Magnitude > 0.001 and math.acos(math.clamp(localfacing:Dot(delta.Unit), -1, 1)) <= (math.rad(Angle.Value) / 2) then
                                    local calc = prediction.SolveTrajectory(selfpos, 200, 135, ent.RootPart.Position, ent.RootPart.Velocity, workspace.Gravity, ent.Humanoid.HipHeight or 2, nil, rayCheck)
                                    if calc then
                                        local old = store.inventory.hotbarSlot
                                        local new = getHotbar(lasso.tool)
                                        if new then
                                            switchItem(lasso.tool)
                                            hotbarSwitch(new)
                                        end
                                        
                                        local res = projectileRemote:InvokeServer(
                                            lasso.tool,
                                            'lasso',
                                            'lasso',
                                            selfpos, 
                                            selfpos, 
                                            CFrame.lookAt(selfpos, calc).LookVector * 200,
                                            httpService:GenerateGUID(true),
                                            {
                                                drawDurationSeconds = 1, 
                                                shotId = httpService:GenerateGUID(false)
                                            },
                                            workspace:GetServerTimeNow() - 0.045
                                        )
                                        if res then
                                            lastshot = tick() + 10.5 
                                        end
                                        hotbarSwitch(old)
                                        task.wait(0.1)
                                    end
                                end
                            end
                        end
                    end
                    task.wait(0.05)
                until not AutoLasso.Enabled
            end
        end
    })
    
    Targets = AutoLasso:CreateTargets({Players = true})
    Range = AutoLasso:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 60,
        Default = 60,
        Suffix = function(val)
            return val <= 1 and 'stud' or 'studs'
        end
    })
    Angle = AutoLasso:CreateSlider({
        Name = 'Max angle',
        Min = 1,
        Max = 360,
        Default = 120
    })
end)

run(function()
    local AutoPearl
    local Legit
    local Back
    local Check
    local LandCheck
    local BackDelay
    local Limit
    
    local rayCheck = RaycastParams.new()
    rayCheck.RespectCanCollide = true
    rayCheck.FilterType = Enum.RaycastFilterType.Include
    local projectileRemote = {InvokeServer = function(self, ...) end}
    task.spawn(function()
    	projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
    end)
    
    local function firePearl(pos, spot, item)
    	if Check.Enabled then
    		for _, v in store.selfProjectiles do
    			if v.Name == 'telepearl' then
    				return
    			end
    		end
    	end
    	local hotbar, old = getHotbar(item.tool), store.hand
    
    	switchItem(item.tool)
    	if Legit.Enabled and hotbar then
    		hotbarSwitch(hotbar)
    	end
    
    	local meta = bedwars.ProjectileMeta.telepearl
    	local calc = prediction.SolveTrajectory(pos, meta.launchVelocity, meta.gravitationalAcceleration, spot, Vector3.zero, workspace.Gravity, 0, 0)
    	local landed = false
    
    	if calc then
    		local dir = CFrame.lookAt(pos, calc).LookVector * meta.launchVelocity
    		local projectile = bedwars.ProjectileController:createLocalProjectile(meta, 'telepearl', 'telepearl', pos, nil, dir, {drawDurationSeconds = 1})
    		local res = projectileRemote:InvokeServer(
    			item.tool,
    			'telepearl',
    			'telepearl',
    			pos,
    			pos,
    			dir,
    			httpService:GenerateGUID(true),
    			{ 
                    drawDurationSeconds = 1, 
                    shotId = httpService:GenerateGUID(false) 
                },
    			workspace:GetServerTimeNow() - 0.045
    		)
    		task.spawn(function()
    			repeat
    				task.wait()
    			until not projectile or not projectile.Parent
    			landed = true
    		end)
    		if res then
    			pcall(function()
    				res.Parent = replicatedStorage
    			end)
    		end
    	end
    
    	if Back.Enabled and LandCheck.Enabled then
    		repeat
    			task.wait()
    		until landed
    	end
    	if Back.Enabled and old and old.tool then
    		task.wait(BackDelay:GetRandomValue())
    		switchItem(old.tool)
    		if Legit.Enabled and getHotbar(old.tool) then
    			hotbarSwitch(getHotbar(old.tool))
    		end
    	end
    end
    
    local function findNearGround(origin)
    	for _, v in {Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1)} do
    		for i = 1, 24 do
    			local ray = workspace:Raycast((origin.Position + (Vector3.yAxis * 3)) + (v * i), Vector3.new(0, -60, 0), rayCheck)
    			if ray then
    				return ray.Position
    			end
    		end
    	end
    	return nil
    end
    
    AutoPearl = vape.Categories.Utility:CreateModule({
    	Name = 'Auto Pearl',
    	Function = function(callback)
    		if callback then
    			local check, lasty
    			repeat
    				if entitylib.isAlive and (not Limit.Enabled or store.hand.tool and store.hand.tool.Name == 'telepearl') then
    					local root = entitylib.character.RootPart
    					local pearl = getItem('telepearl')
    					rayCheck.FilterDescendantsInstances = {store.map}
    					rayCheck.CollisionGroup = root.CollisionGroup
    
    					if entitylib.character.Humanoid.FloorMaterial ~= Enum.Material.Air then
    						lasty = root.CFrame
    					end
    
    					if pearl and root.Velocity.Y < -100 and not workspace:Raycast(root.Position, Vector3.new(0, -200, 0), rayCheck) then
    						if not check then
    							check = true
    							local ground = findNearGround(root.CFrame + Vector3.new(0, 40, 0)) or findNearGround(lasty and lasty + Vector3.new(0, 5, 0) or root.CFrame)
    							if ground then
    								firePearl(root.Position, ground, pearl)
    							end
    						end
    					else
    						check = false
    					end
    				end
    				task.wait(0.1)
    			until not AutoPearl.Enabled
    		end
    	end,
    	Tooltip = 'Automatically throws a pearl onto nearby ground after\nfalling a certain distance.'
    })
    
    Legit = AutoPearl:CreateToggle({
    	Name = 'Legit Switch',
    	Tooltip = 'Visualizes the switching clientside',
    	Default = true
    })
    Back = AutoPearl:CreateToggle({
    	Name = 'Switch back',
    	Default = true,
    	Function = function(callback)
    		if BackDelay then
    			BackDelay.Object.Visible = callback
    		end
    		if LandCheck then
    			LandCheck.Object.Visible = callback
    		end
    	end,
    	Tooltip = 'Switches back to the last slot before pearl'
    })
    LandCheck = AutoPearl:CreateToggle({
    	Name = 'Only after landed',
    	Tooltip = 'Only switches back after your pearl landed',
    	Darker = true
    })
    Check = AutoPearl:CreateToggle({
    	Name = 'Pearl check',
    	Tooltip = 'Doesn\'t throw a pearl if ur already pearling',
    	Default = true
    })
    BackDelay = AutoPearl:CreateTwoSlider({
    	Name = 'Switch Back Delay',
    	Min = 0,
    	Max = 2,
    	DefaultMin = 0.1,
    	DefaultMax = 0.2,
    	Darker = true
    })
    Limit = AutoPearl:CreateToggle({
    	Name = 'Limit to item',
    	Tooltip = 'Only throws pearl when holding a pearl'
    })
end)

run(function()
    local AutoPlay
    local Random
    
    local function isEveryoneDead()
        return #bedwars.Store:getState().Party.members <= 0
    end
    
    local function joinQueue()
        if not bedwars.Store:getState().Game.customMatch and bedwars.Store:getState().Party.leader.userId == lplr.UserId and bedwars.Store:getState().Party.queueState == 0 then
            if Random.Enabled then
                local listofmodes = {}
                for i, v in bedwars.QueueMeta do
                    if not v.disabled and not v.voiceChatOnly and not v.rankCategory then 
                        table.insert(listofmodes, i) 
                    end
                end
                bedwars.QueueController:joinQueue(listofmodes[math.random(1, #listofmodes)])
            else
                bedwars.QueueController:joinQueue(store.queueType)
            end
        end
    end
    
    AutoPlay = vape.Categories.Utility:CreateModule({
        Name = 'Auto Play',
        Function = function(callback)
            if callback then
                AutoPlay:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
                    if deathTable.finalKill and deathTable.entityInstance == lplr.Character and isEveryoneDead() and store.matchState ~= 2 then
                        joinQueue()
                    end
                end))
                AutoPlay:Clean(vapeEvents.MatchEndEvent.Event:Connect(joinQueue))
            end
        end,
        Tooltip = 'Automatically queues after the match ends.'
    })
    Random = AutoPlay:CreateToggle({
        Name = 'Random',
        Tooltip = 'Chooses a random mode'
    })
end)

run(function()
    local AutoRelease
    local Percentage
    local Delay
    local Whitelist

    local launchHook, last = nil, 0
    local charge = 0

    AutoRelease = vape.Categories.Utility:CreateModule({
    	Name = 'Auto Release',
    	Function = function(call)
    		if call then
    			launchHook = bedwars.ProjectileLaunchHook:Add('AutoRelease', 20, function(nextLaunch, ...)
    				local args = {...}
    				local projmeta = args[2]
    				if projmeta and typeof(projmeta) == 'table' then
    					local tool = store.hand.tool
    					local toolName = tool and tool.Name
    					local projSource = toolName and bedwars.ItemMeta[toolName] and bedwars.ItemMeta[toolName].projectileSource
    					local allowed = false
    					if projSource and projSource.ammoItemTypes then
    						for _, ammo in projSource.ammoItemTypes do
    							if table.find(Whitelist.ListEnabled, ammo) then
    								allowed = true
    								break
    							end
    						end
    					end
    					if allowed then
    						charge = (projmeta.velocityMultiplier / 1) * 100
    						last = os.clock() + 0.1
    					end
    				end
    				return nextLaunch(...)
    			end)

    			repeat
    				if last > os.clock() and charge >= Percentage.Value then
    					task.wait(Delay.Value)
    					mouse1click()
    					task.wait(0.2)
    				end
    				task.wait()
    			until not AutoRelease.Enabled
    		else
    			if launchHook then
    				launchHook()
    				launchHook = nil
    			end
    		end
    	end,
        Tooltip = 'Automatically releases ur projectile source when\nat certain charging percentage'
    })

    Percentage = AutoRelease:CreateSlider({
    	Name = 'Percentage',
    	Min = 0,
    	Max = 100,
    	Suffix = '%',
    	Default = 100,
    })
    Delay = AutoRelease:CreateSlider({
    	Name = 'Release delay',
    	Min = 0,
    	Max = 5,
    	Default = 0.5,
    	Decimal = 10,
    	Suffix = function(val)
    		return val <= 1 and 'sec' or 'secs'
    	end,
    })
    Whitelist = AutoRelease:CreateTextList({
    	Name = 'Projectiles',
    	Default = {'arrow'},
    	Tooltip = 'Ammo types Auto Release is allowed to use',
    })
end)

run(function()
    local AutoShoot
    local Targets
    local Check
    local Range
    local Projectiles
    local Delay
    local Next
    local Rate
    
    local function getAmmo(check)
    	for _, item in store.inventory.inventory.items do
    		if check.ammoItemTypes and table.find(check.ammoItemTypes, item.itemType) then
    			return item.itemType
    		end
    	end
    	return
    end
    
    local function getProjectiles()
    	local items = {}
    	for _, item in store.inventory.inventory.items do
    		local proj = bedwars.ItemMeta[item.itemType].projectileSource
    		local ammo = proj and getAmmo(proj)
    		if ammo and (table.find(Projectiles.ListEnabled, ammo) or table.find(Projectiles.ListEnabled, item.itemType)) then
    			table.insert(items, {
    				item,
    				ammo,
    				proj.projectileType(ammo),
    				proj,
    			})
    		end
    	end
    	return items
    end
    
    local FireRate = {}
    
    local function getAttackData()
    	local hand = store.hand
    	if not hand or not hand.tool then
    		return
    	end
    
    	local meta = bedwars.ItemMeta[hand.tool.Name]
    	if not meta or not meta.projectileSource then
    		return
    	end
    
    	if (FireRate[hand.tool.Name] or 0) > tick() then
    		return
    	end
    
    	local ammo = getAmmo(meta.projectileSource)
    	local frosty = hand.tool.Name:find('frost_staff')
    	if not ammo and not frosty then
    		return
    	end
    
    	if frosty then
    		ammo = hand.tool.Name:gsub('frost_staff', 'frosty_snowball')
    	end
    
    	local callback = canDebug and meta.projectileType or function(res)
    		return 'arrow'
    	end
    
    	return hand, meta, ammo, callback(ammo)
    end
    
    local function shootFunc(ignore)
    	if not inputService.MouseEnabled or ignore then
    		local proj, meta, ammo, projectile = getAttackData()
    
    		if proj then
    			local projmeta = bedwars.ProjectileMeta[ammo]
    			local projSpeed = projmeta.launchVelocity
    
    			local selfpos = entitylib.character.RootPart.Position
    			local calc = selfpos + gameCamera.CFrame.LookVector * 50
    			local ent = ignore and entitylib.EntityPosition({
                    Part = 'RootPart',
                    Range = 1000,
                    Players = true,
                    NPCs = true,
                    Wallcheck = true,
                }) or nil
    			if ent then
    				calc = prediction.SolveTrajectory(
    					selfpos,
    					projSpeed,
    					meta.gravitationalAcceleration or 196.2,
    					Vector3.new(ent.RootPart.Velocity.X, 0, ent.RootPart.Velocity.Z),
    					workspace.Gravity,
    					ent.HipHeight,
    					nil,
    					RaycastParams.new(),
    					nil,
    					lplr:GetNetworkPing()
    				)
    			end
    
    			local dir = CFrame.lookAt(selfpos, calc).LookVector
    			local shootPosition, id = (CFrame.new(selfpos, calc) * CFrame.new(Vector3.new(-bedwars.BowConstantsTable.RelX,-bedwars.BowConstantsTable.RelY,-bedwars.BowConstantsTable.RelZ))).Position,
    				httpService:GenerateGUID(true)
    
    			--bedwars.ProjectileController:createLocalProjectile(meta, ammo, projectile, shootPosition, id, dir * projSpeed, {drawDurationSeconds = 1})
    			bedwars.Client:Get(remotes.FireProjectile):CallServerAsync(proj.tool, ammo, projectile, shootPosition, selfpos, dir * projSpeed, id, {
                    drawDurationSeconds = 1,
                    shotId = httpService:GenerateGUID(false),
                }, workspace:GetServerTimeNow() - 0.045):andThen(function(res)
                    if res then
                        res.Parent = replicatedStorage
                    end
                end)
    			local shoot = meta.projectileSource.launchSound
    			shoot = shoot and shoot[math.random(1, #shoot)] or nil
    			if shoot then
    				bedwars.SoundManager:playSound(shoot)
    			end
    		end
    	else
    		mouse1click()
    	end
    end
    
    AutoShoot = vape.Categories.Utility:CreateModule({
    	Name = 'Auto Shoot',
    	Function = function(call)
    		if call then
    			local start = tick()
    			repeat
    				if store.hand.toolType == 'sword' then
    					if (tick() - bedwars.SwordController.lastSwing) < 0.29 and (not Check.Enabled or entitylib.EntityPosition({
    						Range = Range.Value,
                            Wallcheck = Targets.Walls.Enabled or nil,
                            Part = 'RootPart',
                            Players = Targets.Players.Enabled,
                            NPCs = Targets.NPCs.Enabled
    					})) then
    						if tick() > start then
    							for _, data in getProjectiles() do
    								if (FireRate[data[1].itemType] or 0) < tick() then
    									local hotbar, old = getHotbar(data[1].tool), store.hand.tool and getHotbar(store.hand.tool) or 0
    									if hotbar and old and hotbarSwitch(hotbar) then
    										local ignore = vape.Modules['Silent Aura'].Enabled or not inputService.MouseEnabled
    										task.wait(Delay.Value)
    										shootFunc()
    										if vape.Modules['Auto Clicker'].Enabled and not ignore then
    											task.delay(runService.PostSimulation:Wait(), mouse1press)
    										end
    										task.wait(Delay.Value)
    										FireRate[data[1].itemType] = tick() + (data[4].fireDelaySec + Rate:GetRandomValue())
    										hotbarSwitch(old)
    										task.wait(Next.Value)
    										if (tick() - bedwars.SwordController.lastSwing) > 0.29 then
    											break
    										end
    									end
    								end
    							end
    						end
    					else
    						start = tick() + 0.75
    					end
    				end
    				task.wait(0.1)
    			until not AutoShoot.Enabled
    		end
    	end,
        Tooltip = 'Automatically swaps to another projectile source while swinging ur sword'
    })
    
    Targets = AutoShoot:CreateTargets({Walls = true, Darker = true})
    Check = AutoShoot:CreateToggle({
    	Name = 'Target Check',
    	Default = true,
    	Function = function(callback)
    		Targets.Object.Visible = callback
    		pcall(function()
    			Range.Object.Visible = callback
    		end)
    	end
    })
    Range = AutoShoot:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 80,
    	Default = 65,
    	Darker = true,
    	Suffix = function(val)
    		return val <= 1 and 'stud' or 'studs'
    	end
    })
    Projectiles = AutoShoot:CreateTextList({
    	Name = 'Projectiles',
    	Default = {'arrow'},
    	Placeholder = 'projectile'
    })
    Rate = AutoShoot:CreateTwoSlider({
    	Name = 'Fire Rate',
    	Min = 0,
    	Max = 1,
    	DefaultMin = 0.05,
    	DefaultMax = 0.12,
    	Decimal = 100
    })
    Next = AutoShoot:CreateSlider({
    	Name = 'Change Delay',
    	Min = 0,
    	Max = 1,
    	Decimal = 100,
    	Suffix = 'seconds',
    	Default = 0.75
    })
    Delay = AutoShoot:CreateSlider({
    	Name = 'Delay',
    	Min = 0,
    	Max = 1,
    	Decimal = 100,
    	Suffix = 'seconds',
    	Default = 0.05
    })
end)

run(function()
    local AutoToxic
    local GG
    local Toggles, Lists, said, dead = {}, {}, {}
    
    local function sendMessage(name, obj, default)
        local tab = Lists[name].ListEnabled
        local custommsg = #tab > 0 and tab[math.random(1, #tab)] or default
        if not custommsg then return end
        if #tab > 1 and custommsg == said[name] then
            repeat 
                task.wait() 
                custommsg = tab[math.random(1, #tab)] 
            until custommsg ~= said[name]
        end
        said[name] = custommsg
    
        custommsg = custommsg and custommsg:gsub('<obj>', obj or '') or ''
        if textChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            textChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync(custommsg)
        else
            replicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(custommsg, 'All')
        end
    end
    
    AutoToxic = vape.Categories.Utility:CreateModule({
        Name = 'Auto Toxic',
        Function = function(callback)
            if callback then
                AutoToxic:Clean(vapeEvents.BedwarsBedBreak.Event:Connect(function(bedTable)
                    if Toggles.BedDestroyed.Enabled and bedTable.brokenBedTeam.id == lplr:GetAttribute('Team') then
                        sendMessage('BedDestroyed', (bedTable.player.DisplayName or bedTable.player.Name), 'how dare you >:( | <obj>')
                    elseif Toggles.Bed.Enabled and bedTable.player.UserId == lplr.UserId then
                        local team = bedwars.QueueMeta[store.queueType].teams[tonumber(bedTable.brokenBedTeam.id)]
                        sendMessage('Bed', team and team.displayName:lower() or 'white', 'nice bed lul | <obj>')
                    end
                end))
                AutoToxic:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
                    if deathTable.finalKill then
                        local killer = playersService:GetPlayerFromCharacter(deathTable.fromEntity)
                        local killed = playersService:GetPlayerFromCharacter(deathTable.entityInstance)
                        if not killed or not killer then return end
                        if killed == lplr then
                            if (not dead) and killer ~= lplr and Toggles.Death.Enabled then
                                dead = true
                                sendMessage('Death', (killer.DisplayName or killer.Name), 'my gaming chair subscription expired :( | <obj>')
                            end
                        elseif killer == lplr and Toggles.Kill.Enabled then
                            sendMessage('Kill', (killed.DisplayName or killed.Name), 'vxp on top | <obj>')
                        end
                    end
                end))
                AutoToxic:Clean(vapeEvents.MatchEndEvent.Event:Connect(function(winstuff)
                    if GG.Enabled then
                        if textChatService.ChatVersion == Enum.ChatVersion.TextChatService then
                            textChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync('gg')
                        else
                            replicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer('gg', 'All')
                        end
                    end
                    
                    local myTeam = bedwars.Store:getState().Game.myTeam
                    if myTeam and myTeam.id == winstuff.winningTeamId or lplr.Neutral then
                        if Toggles.Win.Enabled then 
                            sendMessage('Win', nil, 'yall garbage') 
                        end
                    end
                end))
            end
        end,
        Tooltip = 'Says a message after a certain action'
    })
    GG = AutoToxic:CreateToggle({
        Name = 'AutoGG',
        Default = true
    })
    for _, v in {'Kill', 'Death', 'Bed', 'BedDestroyed', 'Win'} do
        Toggles[v] = AutoToxic:CreateToggle({
            Name = v..' ',
            Function = function(callback)
                if Lists[v] then
                    Lists[v].Object.Visible = callback
                end
            end
        })
        Lists[v] = AutoToxic:CreateTextList({
            Name = v,
            Darker = true,
            Visible = false
        })
    end
end)

run(function()
    local AutoVoidDrop
    local OwlCheck
    
    AutoVoidDrop = vape.Categories.Utility:CreateModule({
        Name = 'Auto Void Drop',
        Function = function(callback)
            if callback then
                repeat task.wait() until store.matchState ~= 0 or (not AutoVoidDrop.Enabled)
                if not AutoVoidDrop.Enabled then return end
    
                local lowestpoint = math.huge
                for _, v in store.blocks do
                    local point = (v.Position.Y - (v.Size.Y / 2)) - 50
                    if point < lowestpoint then
                        lowestpoint = point
                    end
                end
    
                repeat
                    if entitylib.isAlive then
                        local root = entitylib.character.RootPart
                        if root.Position.Y < lowestpoint and (lplr.Character:GetAttribute('InflatedBalloons') or 0) <= 0 and not getItem('balloon') then
                            if not OwlCheck.Enabled or not root:FindFirstChild('OwlLiftForce') then
                                for _, item in {'iron', 'diamond', 'emerald', 'gold'} do
                                    item = getItem(item)
                                    if item then
                                        item = bedwars.Client:Get(remotes.DropItem):CallServer({
                                            item = item.tool,
                                            amount = item.amount
                                        })
    
                                        if item then
                                            item:SetAttribute('ClientDropTime', tick() + 100)
                                        end
                                    end
                                end
                            end
                        end
                    end
    
                    task.wait(0.1)
                until not AutoVoidDrop.Enabled
            end
        end,
        Tooltip = 'Drops resources when you fall into the void'
    })
    OwlCheck = AutoVoidDrop:CreateToggle({
        Name = 'Owl check',
        Default = true,
        Tooltip = 'Refuses to drop items if being picked up by an owl'
    })
end)

run(function()
    local BackTrack
    local Mode
    local Latency
    local Tick
    
    BackTrack = vape.Categories.Utility:CreateModule({
        Name = 'Back Track',
        Function = function(callback)
            if callback then
                repeat
                    local ent = entitylib.EntityPosition({
                        Part = 'RootPart',
                        Range = 22,
                        Players = true,
                        Wallcheck = true,
                    })
    
                    if ent then
                        if Mode.Value == 'Manual' then
                            setfflag('TargetTimeDelayFacctorTenths', '50000')
                            task.wait(0.05 * Tick.Value)
                            setfflag('TargetTimeDelayFacctorTenths', '20')
                            task.wait(0.05 * Tick.Value)
                        else
                            setfflag('TargetTimeDelayFacctorTenths', tostring(math.floor(20 + (Latency:GetRandomValue() / 20))))
                            task.wait(1)
                        end
                    else
                        setfflag('TargetTimeDelayFacctorTenths', '20')
                    end
                    task.wait()
                until not BackTrack.Enabled
            end
        end,
        Tooltip = 'Lags targets at certain times to increase attack distance'
    })
    getgenv().Backtrack = BackTrack
    Latency = BackTrack:CreateTwoSlider({
        Name = 'Latency',
        Min = 1,
        Max = 500,
        DefaultMin = 50,
        DefaultMax = 120,
        Darker = true,
    })
    Tick = BackTrack:CreateSlider({
        Name = 'Ticks',
        Min = 1,
        Max = 20,
        Default = 5,
        Darker = true,
        Visible = false,
    })
    Mode = BackTrack:CreateDropdown({
        Name = 'Mode',
        List = { 'Manual', 'Lag Based' },
        Default = 'Manual',
        Function = function(val)
            if Latency and Tick then
                Latency.Object.Visible = val == 'Manual'
                Tick.Object.Visible = val == 'Lag Based'
            end
        end,
    })
end)

run(function()
    local CheatDetector
    
    local function Added(player, reason)
        if not CheatersFlagged[player] then
            CheatersFlagged[player] = true
            whitelist.customtags[player.Name] = {{ text = 'CHEATER', color = Color3.new(1, 0, 0)}}
            notif('CheatDetector', tostring(player.Name)..' flagged for '..tostring(reason:lower())..'ing', 10, 'info')
        end
    end
    local function checkPoint(pos, params)
        for _, v in workspace:GetPartBoundsInRadius(pos, 0, params) do
            if v.CanCollide and (v:GetClosestPointOnSurface(pos) - pos).Magnitude <= 0 then
                return false
            end
        end
    
        return true
    end
    
    local overlap = OverlapParams.new()
    overlap.FilterDescendantsInstances = {workspace:WaitForChild('Map', 9e9)}
    overlap.FilterType = Enum.RaycastFilterType.Include
    
    local Checks = {
        Killaura = function()
            local AttackData = {}
            local Strikes = {}
    
            CheatDetector:Clean(shared.bindable.Event:Connect(function(damageTable)
                if damageTable.damageType == 0 and damageTable.fromEntity then
                    local from = playersService:GetPlayerFromCharacter(damageTable.fromEntity)
    
                    if from and from ~= lplr then
                        local lastHit = (os.clock() - (AttackData[from] or 0))
                        if lastHit <= 0.28 then
                            Strikes[from] = (Strikes[from] or 0) + 1
    
                            task.delay(60, function()
                                pcall(function()
                                    Strikes[from] = Strikes[from] - 1
                                end)
                            end)
    
                            if Strikes[from] > 2 then
                                Added(from, 'Killaura')
                            end
                        end
    
                        AttackData[from] = os.clock()
                    end
                end
            end))
        end,
        Reach = function() -- this is so disgusting, but whatever
            CheatDetector:Clean(shared.bindable.Event:Connect(function(damageTable)
                if damageTable.damageType == 0 and damageTable.fromEntity then
                    local player = playersService:GetPlayerFromCharacter(damageTable.fromEntity) 
                    if player and player ~= lplr then
                        local magnitude = (damageTable.fromEntity.PrimaryPart.Position - damageTable.entityInstance.PrimaryPart.Position).Magnitude
                        local held = (store.inventories[player] or {}).hand
                        local meta = held and bedwars.ItemMeta[held.tool.Name].sword or nil
                        local reach = math.floor(meta and meta.attackRange or 14.4) + 4
                        
                        if magnitude > (reach + lplr:GetNetworkPing()) then
                            Added(player, 'Reach')
                        end
                    end
                end
            end))
        end,
        Invisible = function() end,
        HighJump = function() end,
        Phase = function() end
    }
    
    CheatDetector = vape.Categories.Utility:CreateModule({
        Name = 'Cheat Detector',
        Function = function(callback)
            if callback then
                for i, v in Checks do
                    if CheatDetector.Options and CheatDetector.Options[i].Enabled then
                        task.spawn(v)
                    end
                end
    
                repeat
                    for _, v in entitylib.List do
                        if v.Player and v.Player ~= lplr and v.Health > 0 and not CheatersFlagged[v.Player] then
                            if CheatDetector.Options.Invisible.Enabled and (v.RootPart.Position - v.Head.Position).Magnitude > 5 then
                                Added(v.Player, 'Invisible')
                            end
                            if CheatDetector.Options.HighJump.Enabled and v.RootPart.AssemblyLinearVelocity.Y > 80 then
                                Added(v.Player, 'HighJump')
                            end
                            if CheatDetector.Options.Phase.Enabled and not checkPoint(v.Head.Position, overlap) then
                                Added(v.Player, 'Phas')
                            end
                        end
                    end
                    task.wait(0.1)
                until not CheatDetector.Enabled
            end
        end,
        Tooltip = 'Alerts for any possible cheaters.'
    })
    
    for i in Checks do
        CheatDetector:CreateToggle({
            Name = i,
            Default = true
        })
    end
end)

run(function()
    local FakeLag
    local TransmissionOffset
    local Mode
    local Delay
    
    local rng
    
    FakeLag = vape.Categories.Utility:CreateModule({
        Name = 'Fake Lag',
        Function = function(callback)
            if callback then
                rng = Random.new()
    
                local clock, restore, after = os.clock(), os.clock(), 0
                repeat
                    local ms = Delay.Value / 1000
    
                    if Mode.Value == 'Dynamic' then
                        if (os.clock() - clock) >= ms or restore > os.clock() then
                            if clock ~= 9e9 then
                                restore = os.clock() + TransmissionOffset.Value
                                clock = 9e9
                            end
                            setfflag('PhysicsSenderMaxBandwidthBps', '38760')
                        else
                            if clock == 9e9 then
                                clock = os.clock()
                                restore = 0
                            end
                            setfflag('PhysicsSenderMaxBandwidthBps', '0')
                        end
                    elseif Mode.Value == 'Repel' then
                        if store.update > tick() then
                            setfflag('PhysicsSenderMaxBandwidthBps', '0')
                            setfflag('S2PhysicsSenderRate', '0')
                            setfflag('DataSenderRate', '-1')
                            task.wait(rng:NextNumber(70, 150) / 1000)
                            setfflag('PhysicsSenderMaxBandwidthBps', '38760')
                            setfflag('DataSenderRate', '60')
                            setfflag('S2PhysicsSenderRate', '15')
                            after = os.clock() + rng:NextNumber(0.001, (Delay.Value / 1000))
                            store.update = 0
                            num = rng:NextNumber()
                        end
                        if os.clock() > after then
                            num = rng:NextNumber()
                            after = os.clock() + rng:NextNumber(0.001, (Delay.Value / 1000))
                        end
                    elseif Mode.Value == 'Latency' then
                        setfflag('PhysicsSenderMaxBandwidthBps', '0')
                        task.wait(Delay.Value / 1500)
                        setfflag('PhysicsSenderMaxBandwidthBps', '38760')
                        task.wait(ms)
                    end
                    runService.PreRender:Wait()
                until not FakeLag.Enabled
            else
                setfflag('DataSenderRate', '60')
                setfflag('PhysicsSenderMaxBandwidthBps', '38760')
            end
        end,
        Tooltip = 'Delays packets, simulating lag',
        ExtraText = function()
            return Mode and Mode.Value or 'Dynamic'
        end
    })
    getgenv().FakeLag = FakeLag
    
    TransmissionOffset = FakeLag:CreateSlider({
        Name = 'Transmission Offset',
        Min = 1,
        Max = 10,
        Default = 3,
        Decimal = 5,
        Darker = true,
    })
    Mode = FakeLag:CreateDropdown({
        Name = 'Mode',
        List = { 'Dynamic', 'Repel', 'Latency' },
        Default = 'Dynamic',
        Function = function(val)
            TransmissionOffset.Object.Visible = val == 'Dynamic'
            setfflag('PhysicsSenderMaxBandwidthBps', '38760')
        end,
    })
    Delay = FakeLag:CreateSlider({
        Name = 'Delay',
        Suffix = function()
            return 'ms'
        end,
        Min = 1,
        Max = 500,
        Default = 100,
    })
end)

run(function()
    local KnockbackDelay
    local Chance
    local AirDelay
    local GroundDelay
    local TargetCheck
    
    local old, rand
    local function apply(type, env, ...)
    	local root, mass, dir, knockback = ...
    	knockback = knockback and table.clone(knockback) or {}
    	knockback[type] = env[type] and knockback[type] or 0
    	return old(root, mass, dir, knockback, select(5, ...))
    end
    
    KnockbackDelay = vape.Categories.Utility:CreateModule({
    	Name = 'Knockback Delay',
    	Function = function(callback)
    		if callback then
    			old, rand = bedwars.KnockbackUtil.applyKnockback, Random.new()
    			bedwars.KnockbackUtil.applyKnockback = function(...)
    				if rand:NextNumber(0, 100) > Chance.Value then
    					return old(...)
    				end
    
    				local root, mass, dir, knockback = ...
    				if not TargetCheck.Enabled or entitylib.EntityPosition({
    					Range = 50,
    					Part = 'RootPart',
    					Players = true,
    				}) then
    					local env = {}
    					task.delay(AirDelay:GetRandomValue() / 1000, apply, 'horizontal', env, root, mass, dir, knockback, select(5, ...))
    					task.delay(GroundDelay:GetRandomValue() / 1000, apply, 'vertical', env, root, mass, dir, knockback, select(5, ...))
    					return
    				end
    				return old(...)
    			end
    		else
    			bedwars.KnockbackUtil.applyKnockback = old or bedwars.KnockbackUtil.applyKnockback
    		end
    	end,
    	Tooltip = 'Delays incoming knockback packets'
    })
    
    Chance = KnockbackDelay:CreateSlider({
    	Name = 'Chance',
    	Min = 1,
    	Max = 100,
    	Default = 40,
    	Suffix = '%',
    })
    AirDelay = KnockbackDelay:CreateTwoSlider({
    	Name = 'Air delay',
    	Min = 0,
    	Max = 500,
    	DefaultMin = 50,
    	DefaultMax = 200,
    })
    GroundDelay = KnockbackDelay:CreateTwoSlider({
    	Name = 'Ground delay',
    	Min = 0,
    	Max = 500,
    	DefaultMin = 50,
    	DefaultMax = 200,
    })
    TargetCheck = KnockbackDelay:CreateToggle({ Name = 'Target check' })
end)

run(function()
    local old
    
    vape.Categories.Kits:CreateModule({
        Name = 'Krystal Disabler',
        Function = function(callback)
            if callback then
                bedwars.GlacialSkaterController:updateMomentum(9e9)
                old = bedwars.GlacialSkaterController.updateMomentum
                bedwars.GlacialSkaterController.updateMomentum = function(self)
                    self.momentum = 9e9
                    self.lastMomentumReport = 9e9
                    bedwars.Client:Get('MomentumUpdate'):SendToServer({
                        momentumValue = 9e9
                    })
                end
                bedwars.GlacialSkaterController:updateMomentum()
            else
                bedwars.GlacialSkaterController.updateMomentum = old
            end
        end
    })
end)

run(function()
    local MissileTP
    
    MissileTP = vape.Categories.Utility:CreateModule({
        Name = 'Missile TP',
        Function = function(callback)
            if callback then
                MissileTP:Toggle()
                local plr = entitylib.EntityMouse({
                    Range = 1000,
                    Players = true,
                    Part = 'RootPart'
                })
    
                if getItem('guided_missile') and plr then
                    local projectile = bedwars.RuntimeLib.await(bedwars.GuidedProjectileController.fireGuidedProjectile:CallServerAsync('guided_missile'))
                    if projectile then
                        local projectilemodel = projectile.model
                        if not projectilemodel.PrimaryPart then
                            projectilemodel:GetPropertyChangedSignal('PrimaryPart'):Wait()
                        end
    
                        local bodyforce = Instance.new('BodyForce')
                        bodyforce.Force = Vector3.new(0, projectilemodel.PrimaryPart.AssemblyMass * workspace.Gravity, 0)
                        bodyforce.Name = 'AntiGravity'
                        bodyforce.Parent = projectilemodel.PrimaryPart
    
                        repeat
                            projectile.model:SetPrimaryPartCFrame(CFrame.lookAlong(plr.RootPart.CFrame.p, gameCamera.CFrame.LookVector))
                            task.wait(0.1)
                        until not projectile.model or not projectile.model.Parent
                    else
                        notif('MissileTP', 'Missile on cooldown.', 3)
                    end
                end
            end
        end,
        Tooltip = 'Spawns and teleports a missile to a player\nnear your mouse.'
    })
end)

run(function()
    local PickupRange
    local Range
    local Network
    local Lower

    PickupRange = vape.Categories.Utility:CreateModule({
        Name = 'Pickup Range',
        Function = function(callback)
            if callback then
                local items = collection('ItemDrop', PickupRange)
                repeat
                    if entitylib.isAlive then
                        local localPosition = entitylib.character.RootPart.Position
                        for _, v in items do
                            local cdt = v:GetAttribute('ClientDropTime') or 0
                            if tick() - cdt < 2 then
                                if _gd.on then _gd.fn('PR:SKIP', v.Name .. ' CDT blocked (CDT=' .. string.format('%.1f', cdt) .. ' age=' .. string.format('%.1f', tick() - cdt) .. ')') end
                                continue
                            end
                            local nown = isnetworkowner(v)
                            if _gd.on then _gd.fn('PR:CHECK', v.Name .. ' NOwn=' .. tostring(nown) .. ' NetTP=' .. tostring(Network.Enabled) .. ' pos=' .. _gd.fv(v.Position) .. ' CC=' .. tostring(pcall(function() return v.CanCollide end) and v.CanCollide or 'unk')) end
                            if nown and Network.Enabled and entitylib.character.Humanoid.Health > 0 then
                                local beforePos = v.Position
                                local tpTarget = localPosition - Vector3.new(0, 3, 0)
                                v.CFrame = CFrame.new(tpTarget)
                                if _gd.on then _gd.fn('PR:TP', v.Name .. ' TELEPORTED from=' .. _gd.fv(beforePos) .. ' to=' .. _gd.fv(tpTarget) .. ' (3 below player Y=' .. string.format('%.2f', localPosition.Y) .. ' -> Y=' .. string.format('%.2f', tpTarget.Y) .. ')') end
                            end

                            if (localPosition - v.Position).Magnitude <= Range.Value then
                                if Lower.Enabled and (localPosition.Y - v.Position.Y) < (entitylib.character.HipHeight - 1) then continue end
                                if _gd.on then _gd.fn('PR:PICKUP', v.Name .. ' picking up at ' .. _gd.fv(v.Position) .. ' dist=' .. string.format('%.2f', (localPosition - v.Position).Magnitude)) end
                                task.spawn(function()
                                    bedwars.Client:Get(remotes.PickupItem):CallServerAsync({
                                        itemDrop = v
                                    }):andThen(function(suc)
                                        if suc and bedwars.SoundList then
                                            bedwars.SoundManager:playSound(bedwars.SoundList.PICKUP_ITEM_DROP)
                                            local sound = bedwars.ItemMeta[v.Name].pickUpOverlaySound
                                            if sound then
                                                bedwars.SoundManager:playSound(sound, {
                                                    position = v.Position,
                                                    volumeMultiplier = 0.9
                                                })
                                            end
                                        end
                                    end)
                                end)
                            end
                        end
                    end
                    task.wait(0.1)
                until not PickupRange.Enabled
            end
        end,
        Tooltip = 'Picks up items from a farther distance'
    })
    Range = PickupRange:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 10,
        Default = 10,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    Network = PickupRange:CreateToggle({
        Name = 'Network TP',
        Default = true
    })
    Lower = PickupRange:CreateToggle({Name = 'Feet Check'})
end)

run(function()
    local RavenTP
    
    RavenTP = vape.Categories.Utility:CreateModule({
        Name = 'Raven TP',
        Function = function(callback)
            if callback then
                RavenTP:Toggle()
                local plr = entitylib.EntityMouse({
                    Range = 1000,
                    Players = true,
                    Part = 'RootPart'
                })
    
                if getItem('raven') and plr then
                    bedwars.Client:Get(remotes.SpawnRaven):CallServerAsync():andThen(function(projectile)
                        if projectile then
                            local bodyforce = Instance.new('BodyForce')
                            bodyforce.Force = Vector3.new(0, projectile.PrimaryPart.AssemblyMass * workspace.Gravity, 0)
                            bodyforce.Parent = projectile.PrimaryPart
    
                            if plr then
                                task.spawn(pcall, function()
                                    for _ = 1, 20 do
                                        if plr.RootPart and projectile then
                                            projectile:SetPrimaryPartCFrame(CFrame.lookAlong(plr.RootPart.Position, gameCamera.CFrame.LookVector))
                                        end
                                        task.wait(0.05)
                                    end
                                end)
                                task.wait(0.3)
                                bedwars.RavenController:detonateRaven()
                            end
                        end
                    end)
                end
            end
        end,
        Tooltip = 'Spawns and teleports a raven to a player\nnear your mouse.'
    })
end)

run(function()
    local Scaffold
    local Expand
    local Tower
    local Downwards
    local Diagonal
    local LimitItem
    local Mouse
    local adjacent, lastpos, label = {}, Vector3.zero
    
    for x = -3, 3, 3 do
        for y = -3, 3, 3 do
            for z = -3, 3, 3 do
                local vec = Vector3.new(x, y, z)
                if vec ~= Vector3.zero then
                    table.insert(adjacent, vec)
                end
            end
        end
    end
    
    local function nearCorner(poscheck, pos)
        local startpos = poscheck - Vector3.new(3, 3, 3)
        local endpos = poscheck + Vector3.new(3, 3, 3)
        local check = poscheck + (pos - poscheck).Unit * 100
        return Vector3.new(math.clamp(check.X, startpos.X, endpos.X), math.clamp(check.Y, startpos.Y, endpos.Y), math.clamp(check.Z, startpos.Z, endpos.Z))
    end
    
    local function blockProximity(pos)
        local mag, returned = 60, nil
        local tab = getBlocksInPoints(bedwars.BlockController:getBlockPosition(pos - Vector3.new(21, 21, 21)), bedwars.BlockController:getBlockPosition(pos + Vector3.new(21, 21, 21)))
        for _, v in tab do
            local blockpos = nearCorner(v, pos)
            local newmag = (pos - blockpos).Magnitude
            if newmag < mag then
                mag, returned = newmag, blockpos
            end
        end
        table.clear(tab)
        return returned
    end
    
    local function checkAdjacent(pos)
        for _, v in adjacent do
            if getPlacedBlock(pos + v) then
                return true
            end
        end
        return false
    end
    
    local function getScaffoldBlock()
        if store.hand.toolType == 'block' then
            return store.hand.tool.Name, store.hand.amount
        elseif (not LimitItem.Enabled) then
            local wool, amount = getWool()
            if wool then
                return wool, amount
            else
                for _, item in store.inventory.inventory.items do
                    if bedwars.ItemMeta[item.itemType].block then
                        return item.itemType, item.amount
                    end
                end
            end
        end
    
        return nil, 0
    end
    
    Scaffold = vape.Categories.Utility:CreateModule({
        Name = 'Scaffold',
        Function = function(callback)
            if label then
                label.Visible = callback
            end
    
            if callback then
                repeat
                    if entitylib.isAlive then
                        local wool, amount = getScaffoldBlock()
    
                        if Mouse.Enabled then
                            if not inputService:IsMouseButtonPressed(0) then
                                wool = nil
                            end
                        end
    
                        if label then
                            amount = amount or 0
                            label.Text = amount..' <font color="rgb(170, 170, 170)">(Scaffold)</font>'
                            label.TextColor3 = Color3.fromHSV((amount / 128) / 2.8, 0.86, 1)
                        end
    
                        if wool then
                            local root = entitylib.character.RootPart
                            if Tower.Enabled and inputService:IsKeyDown(Enum.KeyCode.Space) and (not inputService:GetFocusedTextBox()) then
                                root.Velocity = Vector3.new(root.Velocity.X, 38, root.Velocity.Z)
                            end
    
                            for i = Expand.Value, 1, -1 do
                                local currentpos = roundPos(root.Position - Vector3.new(0, entitylib.character.HipHeight + (Downwards.Enabled and inputService:IsKeyDown(Enum.KeyCode.LeftShift) and 4.5 or 1.5), 0) + entitylib.character.Humanoid.MoveDirection * (i * 3))
                                if Diagonal.Enabled then
                                    if math.abs(math.round(math.deg(math.atan2(-entitylib.character.Humanoid.MoveDirection.X, -entitylib.character.Humanoid.MoveDirection.Z)) / 45) * 45) % 90 == 45 then
                                        local dt = (lastpos - currentpos)
                                        if ((dt.X == 0 and dt.Z ~= 0) or (dt.X ~= 0 and dt.Z == 0)) and ((lastpos - root.Position) * Vector3.new(1, 0, 1)).Magnitude < 2.5 then
                                            currentpos = lastpos
                                        end
                                    end
                                end
    
                                local block, blockpos = getPlacedBlock(currentpos)
                                if not block then
                                    blockpos = checkAdjacent(blockpos * 3) and blockpos * 3 or blockProximity(currentpos)
                                    if blockpos then
                                        task.spawn(bedwars.placeBlock, blockpos, wool, false)
                                    end
                                end
                                lastpos = currentpos
                            end
                        end
                    end
    
                    task.wait(0.03)
                until not Scaffold.Enabled
            else
                Label = nil
            end
        end,
        Tooltip = 'Helps you make bridges/scaffold walk.'
    })
    Expand = Scaffold:CreateSlider({
        Name = 'Expand',
        Min = 1,
        Max = 6
    })
    Tower = Scaffold:CreateToggle({
        Name = 'Tower',
        Default = true
    })
    Downwards = Scaffold:CreateToggle({
        Name = 'Downwards',
        Default = true
    })
    Diagonal = Scaffold:CreateToggle({
        Name = 'Diagonal',
        Default = true
    })
    LimitItem = Scaffold:CreateToggle({Name = 'Limit to items'})
    Mouse = Scaffold:CreateToggle({Name = 'Require mouse down'})
    Count = Scaffold:CreateToggle({
        Name = 'Block Count',
        Function = function(callback)
            if callback then
                label = Instance.new('TextLabel')
                label.Size = UDim2.fromOffset(100, 20)
                label.Position = UDim2.new(0.5, 6, 0.5, 60)
                label.BackgroundTransparency = 1
                label.AnchorPoint = Vector2.new(0.5, 0)
                label.Text = '0'
                label.TextColor3 = Color3.new(0, 1, 0)
                label.TextSize = 18
                label.RichText = true
                label.Font = Enum.Font.Arial
                label.Visible = Scaffold.Enabled
                label.Parent = vape.gui
            else
                label:Destroy()
                label = nil
            end
        end
    })
end)

run(function()
    local ShopTierBypass
    local savedTiered, savedNextTier, savedPrevTier = {}, {}, {}
    local oldGetShop, oldGetShopItem, oldClientGet
    local debugConn
    local tierChains = {}
    local knownTiers = {
        {'wood_pickaxe', 'stone_pickaxe', 'iron_pickaxe', 'diamond_pickaxe'},
        {'wood_axe', 'stone_axe', 'iron_axe', 'diamond_axe'},
        {'leather_chestplate', 'iron_chestplate', 'diamond_chestplate', 'emerald_chestplate', 'void_chestplate'},
        {'wood_sword', 'stone_sword', 'iron_sword', 'diamond_sword', 'emerald_sword', 'void_sword'},
        {'wood_gun_blade', 'stone_gun_blade', 'iron_gun_blade', 'diamond_gun_blade', 'emerald_gun_blade'},
        {'wood_scythe', 'stone_scythe', 'iron_scythe', 'diamond_scythe', 'mythic_scythe'},
        {'wood_great_hammer', 'stone_great_hammer', 'iron_great_hammer', 'diamond_great_hammer', 'mythic_great_hammer'},
        {'wood_dagger', 'stone_dagger', 'iron_dagger', 'diamond_dagger', 'mythic_dagger'},
        {'wood_gauntlets', 'stone_gauntlets', 'iron_gauntlets', 'diamond_gauntlets', 'mythic_gauntlets_plain'},
        {'wood_dao', 'stone_dao', 'iron_dao', 'diamond_dao', 'emerald_dao'},
    }

    local function hasItemOwned(itemType)
        if getItem(itemType) then return true end
        local armor = store.inventory.inventory.armor
        if armor then
            for _, a in armor do
                if type(a) == 'table' and a.itemType == itemType then
                    return true
                end
            end
        end
        return false
    end

    local function isDowngrade(itemType)
        local chain = tierChains[itemType]
        if not chain then return false end
        local myIndex = chain.index[itemType]
        for i = myIndex + 1, #chain.items do
            if hasItemOwned(chain.items[i]) then return true end
        end
        return false
    end

    local function shouldBlock(itemType)
        if not tierChains[itemType] then return false end
        if hasItemOwned(itemType) then return true end
        if isDowngrade(itemType) then return true end
        return false
    end

    ShopTierBypass = vape.Categories.Utility:CreateModule({
        Name = 'Shop Tier Bypass',
        Function = function(callback)
            if callback then
                repeat task.wait() until store.shopLoaded or not ShopTierBypass.Enabled
                if ShopTierBypass.Enabled then
                    local itemsByType = {}
                    for _, v in bedwars.Shop.ShopItems do
                        savedTiered[v] = v.tiered
                        savedNextTier[v] = v.nextTier
                        savedPrevTier[v] = v.prevTier
                        if v.itemType then
                            itemsByType[v.itemType] = v
                        end
                    end

                    for _, group in knownTiers do
                        local hasAny = false
                        for _, it in group do
                            if itemsByType[it] then
                                hasAny = true
                                break
                            end
                        end
                        if hasAny then
                            local chain = {items = {}, index = {}}
                            for _, it in group do
                                if itemsByType[it] then
                                    table.insert(chain.items, it)
                                    chain.index[it] = #chain.items
                                end
                            end
                            if #chain.items > 1 then
                                for _, it in chain.items do
                                    tierChains[it] = chain
                                end
                            end
                        end
                    end

                    for _, v in bedwars.Shop.ShopItems do
                        v.nextTier = nil
                        v.tiered = nil
                        v.prevTier = nil
                    end

                    oldGetShop = bedwars.Shop.getShop
                    bedwars.Shop.getShop = function(...)
                        local res = {oldGetShop(...)}
                        for i, v in res[1] do
                            v.nextTier = nil
                            v.tiered = nil
                            v.prevTier = nil
                        end
                        return unpack(res)
                    end

                    oldGetShopItem = bedwars.Shop.getShopItem
                    bedwars.Shop.getShopItem = function(itemType, ...)
                        local result = oldGetShopItem(itemType, ...)
                        if result then
                            result.nextTier = nil
                            result.tiered = nil
                            result.prevTier = nil
                        end
                        return result
                    end

                    oldClientGet = bedwars.Client.Get
                    bedwars.Client.Get = function(self, name, ...)
                        local remote = oldClientGet(self, name, ...)
                        if name == 'BedwarsPurchaseItem' then
                            local wrapper = {}
                            setmetatable(wrapper, {
                                __index = function(_, key)
                                    if key == 'CallServerAsync' then
                                        return function(_, data, ...)
                                            if data and data.shopItem and data.shopItem.itemType then
                                                local itemType = data.shopItem.itemType
                                                local inChain = tierChains[itemType] ~= nil
                                                local owned = hasItemOwned(itemType)
                                                local downgrade = isDowngrade(itemType)
                                                print('[ShopTierBypass] attempt: '..itemType..' | inChain='..tostring(inChain)..' owned='..tostring(owned)..' downgrade='..tostring(downgrade))
                                                if shouldBlock(itemType) then
                                                    local displayName = bedwars.ItemMeta[itemType] and bedwars.ItemMeta[itemType].displayName or itemType
                                                    if downgrade then
                                                        notif('ShopTierBypass', 'Blocked downgrade: '..displayName, 3, 'alert')
                                                    else
                                                        notif('ShopTierBypass', 'Already owned: '..displayName, 3, 'alert')
                                                    end
                                                    return {andThen = function() end}
                                                end
                                            end
                                            print('[ShopTierBypass] sending to server: '..(data and data.shopItem and data.shopItem.itemType or 'unknown'))
                                            if data and data.shopItem then
                                                data.shopItem.prevTier = nil
                                                data.shopItem.tiered = nil
                                                data.shopItem.nextTier = nil
                                            end
                                            return remote:CallServerAsync(data, ...)
                                        end
                                    end
                                    return remote[key]
                                end
                            })
                            return wrapper
                        end
                        return remote
                    end

                    debugConn = inputService.InputBegan:Connect(function(input, gpe)
                        if gpe then return end
                        if input.KeyCode == Enum.KeyCode.F5 and ShopTierBypass.Enabled then
                            local lines = {'[ShopTierBypass Debug]'}
                            table.insert(lines, 'shopLoaded: '..tostring(store.shopLoaded))
                            table.insert(lines, '')
                            table.insert(lines, 'Tier chains built:')
                            local seen = {}
                            for itemType, chain in tierChains do
                                local id = tostring(chain)
                                if not seen[id] then
                                    seen[id] = true
                                    local parts = {}
                                    for _, it in chain.items do
                                        local ownedMark = hasItemOwned(it) and '[OWNED]' or ''
                                        table.insert(parts, it..ownedMark)
                                    end
                                    table.insert(lines, '  '..table.concat(parts, ' -> '))
                                end
                            end
                            if not next(tierChains) then
                                table.insert(lines, '  (empty - shopLoaded may be false, or itemType names dont match knownTiers)')
                            end
                            table.insert(lines, '')
                            table.insert(lines, 'Inventory items:')
                            for slot, item in store.inventory.inventory.items do
                                table.insert(lines, '  ['..tostring(slot)..'] '..tostring(item.itemType))
                            end
                            local armor = store.inventory.inventory.armor
                            if armor then
                                table.insert(lines, 'Armor slots:')
                                for _, a in armor do
                                    if type(a) == 'table' then
                                        table.insert(lines, '  '..tostring(a.itemType))
                                    end
                                end
                            end
                            table.insert(lines, '')
                            table.insert(lines, 'Shop items still tiered (should be empty if bypass active):')
                            local anyTiered = false
                            for _, v in bedwars.Shop.ShopItems do
                                if v.tiered ~= nil or v.nextTier ~= nil or v.prevTier ~= nil then
                                    table.insert(lines, '  '..tostring(v.itemType)..' | tiered='..tostring(v.tiered)..' nextTier='..tostring(v.nextTier)..' prevTier='..tostring(v.prevTier))
                                    anyTiered = true
                                end
                            end
                            if not anyTiered then
                                table.insert(lines, '  (none - tiered/nextTier/prevTier flags all cleared)')
                            end
                            local text = table.concat(lines, '\n')
                            if setclipboard then setclipboard(text) end
                            print(text)
                            notif('ShopTierBypass', 'Debug dumped (F5) - check console/clipboard', 3, 'info')
                        end
                    end)

                end
            else
                if oldGetShop then
                    bedwars.Shop.getShop = oldGetShop
                    oldGetShop = nil
                end
                if oldGetShopItem then
                    bedwars.Shop.getShopItem = oldGetShopItem
                    oldGetShopItem = nil
                end
                if oldClientGet then
                    bedwars.Client.Get = oldClientGet
                    oldClientGet = nil
                end
                if debugConn then
                    debugConn:Disconnect()
                    debugConn = nil
                end
                for i, v in savedTiered do
                    i.tiered = v
                end
                for i, v in savedNextTier do
                    i.nextTier = v
                end
                for i, v in savedPrevTier do
                    i.prevTier = v
                end
                table.clear(savedNextTier)
                table.clear(savedTiered)
                table.clear(savedPrevTier)
                table.clear(tierChains)
            end
        end,
        Tooltip = 'Click any tier to buy it directly, skipping prerequisites. Blocks already-owned and downgrades.'
    })
end)

run(function()
    local UpgradeShopBypass
    local debugConn
    local oldRequestPurchase
    local savedTierData = {}

    UpgradeShopBypass = vape.Categories.Utility:CreateModule({
        Name = 'Upgrade Shop Bypass',
        Function = function(callback)
            if callback then
                repeat task.wait() until next(bedwars.TeamUpgradeMeta) or not UpgradeShopBypass.Enabled
                if not UpgradeShopBypass.Enabled then return end

                for upgradeType, upgrade in bedwars.TeamUpgradeMeta do
                    savedTierData[upgradeType] = {}
                    for i, tier in upgrade.tiers do
                        savedTierData[upgradeType][i] = {
                            availableOnlyInQueue = tier.availableOnlyInQueue,
                            disabledInQueue = upgrade.disabledInQueue
                        }
                        tier.availableOnlyInQueue = nil
                    end
                    upgrade.disabledInQueue = nil
                end

                oldRequestPurchase = bedwars.Client.Get
                bedwars.Client.Get = function(self, name, ...)
                    local remote = oldRequestPurchase(self, name, ...)
                    if name == 'RequestPurchaseTeamUpgrade' then
                        local wrapper = {}
                        setmetatable(wrapper, {
                            __index = function(_, key)
                                if key == 'CallServerAsync' then
                                    return function(_, upgradeType, ...)
                                        local upgrade = bedwars.TeamUpgradeMeta[upgradeType]
                                        local team = lplr:GetAttribute('Team')
                                        local currentUpgrades = bedwars.Store:getState().Bedwars.teamUpgrades[team] or {}
                                        local currentTier = (currentUpgrades[upgradeType] or 0) + 1
                                        local upgradeName = upgrade and (upgrade.name == 'Armor' and 'Protection' or upgrade.name) or upgradeType
                                        if upgrade and currentTier > #upgrade.tiers then
                                            notif('UpgradeShopBypass', 'Already maxed: '..upgradeName, 3, 'alert')
                                            return {andThen = function() end}
                                        end
                                        notif('UpgradeShopBypass', 'Purchasing '..upgradeName..' tier '..currentTier, 3, 'info')
                                        return remote:CallServerAsync(upgradeType, ...)
                                    end
                                end
                                return remote[key]
                            end
                        })
                        return wrapper
                    end
                    return remote
                end

                debugConn = inputService.InputBegan:Connect(function(input, gpe)
                    if gpe then return end
                    if input.KeyCode == Enum.KeyCode.F4 and UpgradeShopBypass.Enabled then
                        local lines = {'[UpgradeShopBypass Debug]'}
                        local team = lplr:GetAttribute('Team')
                        local teamUpgrades = bedwars.Store:getState().Bedwars.teamUpgrades[team] or {}
                        table.insert(lines, 'Team: '..(team or 'none'))
                        table.insert(lines, 'Queue: '..(store.queueType or 'unknown'))
                        table.insert(lines, '')
                        table.insert(lines, 'Available upgrades:')
                        for upgradeType, upgrade in bedwars.TeamUpgradeMeta do
                            local currentTier = teamUpgrades[upgradeType] or 0
                            local maxTier = #upgrade.tiers
                            local upgradeName = upgrade.name == 'Armor' and 'Protection' or upgrade.name
                            local status = currentTier >= maxTier and 'MAXED' or ('tier '..currentTier..'/'..maxTier)
                            table.insert(lines, '  '..upgradeName..' ['..upgradeType..'] - '..status)

                            for i, tier in upgrade.tiers do
                                local owned = i <= currentTier and ' [OWNED]' or ''
                                local queueLock = ''
                                if savedTierData[upgradeType] and savedTierData[upgradeType][i] then
                                    local orig = savedTierData[upgradeType][i]
                                    if orig.availableOnlyInQueue then
                                        queueLock = ' (queue-locked: '..table.concat(orig.availableOnlyInQueue, ',')..')'
                                    end
                                    if orig.disabledInQueue then
                                        queueLock = queueLock..' (disabled-in: '..table.concat(orig.disabledInQueue, ',')..')'
                                    end
                                end
                                table.insert(lines, '    tier '..i..': '..tier.cost..' diamonds'..owned..queueLock)
                            end
                        end

                        table.insert(lines, '')
                        table.insert(lines, 'Raw teamUpgrades state:')
                        for k, v in teamUpgrades do
                            if type(v) == 'table' then
                                for uk, uv in v do
                                    table.insert(lines, '  '..tostring(k)..'.'..tostring(uk)..' = '..tostring(uv))
                                end
                            else
                                table.insert(lines, '  '..tostring(k)..' = '..tostring(v))
                            end
                        end

                        table.insert(lines, '')
                        table.insert(lines, 'Bypass status:')
                        for upgradeType, upgrade in bedwars.TeamUpgradeMeta do
                            local bypassed = {}
                            if savedTierData[upgradeType] then
                                for i, orig in savedTierData[upgradeType] do
                                    if orig.availableOnlyInQueue then
                                        table.insert(bypassed, 'tier '..i..' queue-lock removed')
                                    end
                                end
                                if savedTierData[upgradeType][1] and savedTierData[upgradeType][1].disabledInQueue then
                                    table.insert(bypassed, 'disabledInQueue removed')
                                end
                            end
                            if #bypassed > 0 then
                                local upgradeName = upgrade.name == 'Armor' and 'Protection' or upgrade.name
                                table.insert(lines, '  '..upgradeName..': '..table.concat(bypassed, ', '))
                            end
                        end

                        local text = table.concat(lines, '\n')
                        if setclipboard then
                            setclipboard(text)
                        end
                        print(text)
                        notif('UpgradeShopBypass', 'Debug copied to clipboard & console', 3, 'info')
                    end
                end)
            else
                if oldRequestPurchase then
                    bedwars.Client.Get = oldRequestPurchase
                    oldRequestPurchase = nil
                end
                if debugConn then
                    debugConn:Disconnect()
                    debugConn = nil
                end
                for upgradeType, tiers in savedTierData do
                    local upgrade = bedwars.TeamUpgradeMeta[upgradeType]
                    if upgrade then
                        for i, orig in tiers do
                            if upgrade.tiers[i] then
                                upgrade.tiers[i].availableOnlyInQueue = orig.availableOnlyInQueue
                            end
                            upgrade.disabledInQueue = orig.disabledInQueue
                        end
                    end
                end
                table.clear(savedTierData)
            end
        end,
        Tooltip = 'Bypasses queue/tier locks on team upgrades. F4 for debug.'
    })
end)

run(function()
    local StaffDetector
    local Mode
    local Clans
    local Party
    local Profile
    local Users
    local blacklistedclans = {'gg', 'gg2', 'DV', 'DV2'}
    local blacklisteduserids = {1502104539, 3826146717, 4531785383, 1049767300, 4926350670, 653085195, 184655415, 2752307430, 5087196317, 5744061325, 1536265275}
    local joined = {}
    
    local function getRole(plr, id)
        local suc, res = pcall(function()
            return plr:GetRankInGroup(id)
        end)
        if not suc then
            notif('StaffDetector', res, 30, 'alert')
        end
        return suc and res or 0
    end
    
    local function staffFunction(plr, checktype)
        if not vape.Loaded then
            repeat task.wait() until vape.Loaded
        end
    
        notif('StaffDetector', 'Staff Detected ('..checktype..'): '..plr.Name..' ('..plr.UserId..')', 60, 'alert')
        whitelist.customtags[plr.Name] = {{text = 'GAME STAFF', color = Color3.new(1, 0, 0)}}
    
        if Party.Enabled and not checktype:find('clan') then
            bedwars.PartyController:leaveParty()
        end
    
        if Mode.Value == 'Uninject' then
            task.spawn(function()
                vape:Uninject()
            end)
            game:GetService('StarterGui'):SetCore('SendNotification', {
                Title = 'StaffDetector',
                Text = 'Staff Detected ('..checktype..')\n'..plr.Name..' ('..plr.UserId..')',
                Duration = 60,
            })
        elseif Mode.Value == 'Requeue' then
            bedwars.QueueController:joinQueue(store.queueType)
        elseif Mode.Value == 'Profile' then
            vape.Save = function() end
            if vape.Profile ~= Profile.Value then
                vape:Load(true, Profile.Value)
            end
        elseif Mode.Value == 'AutoConfig' then
            local safe = {'AutoClicker', 'Reach', 'Sprint', 'HitFix', 'StaffDetector'}
            vape.Save = function() end
            for i, v in vape.Modules do
                if not (table.find(safe, i) or v.Category == 'Render') then
                    if v.Enabled then
                        v:Toggle()
                    end
                    v:SetBind('')
                end
            end
        end
    end
    
    local function checkFriends(list)
        for _, v in list do
            if joined[v] then
                return joined[v]
            end
        end
        return nil
    end
    
    local function checkJoin(plr, connection)
        if not plr:GetAttribute('Team') and plr:GetAttribute('Spectator') and not bedwars.Store:getState().Game.customMatch then
            connection:Disconnect()
            local tab, pages = {}, playersService:GetFriendsAsync(plr.UserId)
            for _ = 1, 200 do
                for _, v in pages:GetCurrentPage() do
                    table.insert(tab, v.Id)
                end
                if pages.IsFinished then break end
                pages:AdvanceToNextPageAsync()
            end
    
            local friend = checkFriends(tab)
            if not friend then
                staffFunction(plr, 'impossible_join')
                return true
            else
                notif('StaffDetector', string.format('Spectator %s joined from %s', plr.Name, friend), 20, 'warning')
            end
        end
    end
    
    local function playerAdded(plr)
        joined[plr.UserId] = plr.Name
        if plr == lplr then return end
    
        if table.find(blacklisteduserids, plr.UserId) or table.find(Users.ListEnabled, tostring(plr.UserId)) then
            staffFunction(plr, 'blacklisted_user')
        elseif getRole(plr, 5774246) >= 100 then
            staffFunction(plr, 'staff_role')
        else
            local connection
            connection = plr:GetAttributeChangedSignal('Spectator'):Connect(function()
                checkJoin(plr, connection)
            end)
            StaffDetector:Clean(connection)
            if checkJoin(plr, connection) then
                return
            end
    
            if not plr:GetAttribute('ClanTag') then
                plr:GetAttributeChangedSignal('ClanTag'):Wait()
            end
    
            if table.find(blacklistedclans, plr:GetAttribute('ClanTag')) and vape.Loaded and Clans.Enabled then
                connection:Disconnect()
                staffFunction(plr, 'blacklisted_clan_'..plr:GetAttribute('ClanTag'):lower())
            end
        end
    end
    
    StaffDetector = vape.Categories.Utility:CreateModule({
        Name = 'Staff Detector',
        Function = function(callback)
            if callback then
                StaffDetector:Clean(playersService.PlayerAdded:Connect(playerAdded))
                for _, v in playersService:GetPlayers() do
                    task.spawn(playerAdded, v)
                end
            else
                table.clear(joined)
            end
        end,
        Tooltip = 'Detects people with a staff rank ingame'
    })
    Mode = StaffDetector:CreateDropdown({
        Name = 'Mode',
        List = {'Uninject', 'Profile', 'Requeue', 'AutoConfig', 'Notify'},
        Function = function(val)
            if Profile.Object then
                Profile.Object.Visible = val == 'Profile'
            end
        end
    })
    Clans = StaffDetector:CreateToggle({
        Name = 'Blacklist clans',
        Default = true
    })
    Party = StaffDetector:CreateToggle({
        Name = 'Leave party'
    })
    Profile = StaffDetector:CreateTextBox({
        Name = 'Profile',
        Default = 'default',
        Darker = true,
        Visible = false
    })
    Users = StaffDetector:CreateTextList({
        Name = 'Users',
        Placeholder = 'player (userid)'
    })
end)

run(function()
    TrapDisabler = vape.Categories.Utility:CreateModule({
        Name = 'Trap Disabler',
        Tooltip = 'Disables Snap Traps'
    })
end)

run(function()
    local oldGroundHit
    local Method

    NoFallDamage = vape.Categories.Blatant:CreateModule({
        Name = 'No Fall Damage',
        Function = function(callback)
            if callback then
                pcall(function()
                    local controller = bedwars.Knit.Controllers.FallDamageController
                    local groundHitFunc = debug.getproto(controller.KnitStart, 1)
                    if groundHitFunc then
                        oldGroundHit = hookfunction(groundHitFunc, function() end)
                    end
                end)

                local fallConns = {}
                local function disableFallConns(ent)
                    for _, v in getconnections(ent.Humanoid.StateChanged) do
                        local matched = false
                        pcall(function()
                            local src = debug.getinfo(v.Function).source or ''
                            matched = src:find('fall%-damage') ~= nil
                        end)
                        if matched then
                            table.insert(fallConns, v)
                            v:Disable()
                        end
                    end
                end
                if entitylib.isAlive then
                    disableFallConns(entitylib.character)
                end
                NoFallDamage:Clean(entitylib.Events.LocalAdded:Connect(function(ent)
                    task.delay(1, function()
                        disableFallConns(ent)
                    end)
                end))

                if Method.Value == 'Spoof' then
                    if not rakNetCheck('No Fall Damage') then
                        NoFallDamage:Toggle()
                        return
                    end
                    local hook = function(packet)
                        if packet.AsArray[1] == 0x1b then
                            local data = packet.AsBuffer
                            local stateVal = buffer.readu8(data, 25)
                            local rawState = stateVal % 32
                            if rawState == Enum.HumanoidStateType.Freefall.Value
                                or rawState == Enum.HumanoidStateType.FallingDown.Value then
                                buffer.writeu8(data, 25, Enum.HumanoidStateType.Running.Value + (stateVal - rawState))
                                packet:SetData(data)
                            end
                        end
                    end
                    raknet.add_send_hook(hook)
                    NoFallDamage:Clean(function()
                        raknet.remove_send_hook(hook)
                    end)
                elseif Method.Value == 'Block' then
                    local placed = false
                    local rayCheck = RaycastParams.new()
                    rayCheck.RespectCanCollide = true
                    NoFallDamage:Clean(runService.PreSimulation:Connect(function()
                        if entitylib.isAlive then
                            local root = entitylib.character.RootPart
                            local vel = root.AssemblyLinearVelocity.Y

                            if entitylib.character.Humanoid.FloorMaterial ~= Enum.Material.Air then
                                placed = false
                                return
                            end

                            if vel < -40 and not placed then
                                local woolType = getWool()
                                if not woolType then return end

                                rayCheck.FilterDescendantsInstances = {lplr.Character, gameCamera}
                                rayCheck.CollisionGroup = root.CollisionGroup
                                local ray = workspace:Raycast(root.Position, Vector3.new(0, -30, 0), rayCheck)
                                if ray then
                                    local placePos = ray.Position + Vector3.new(0, 3, 0)
                                    bedwars.placeBlock(placePos, woolType)
                                    placed = true
                                end
                            end
                        end
                    end))
                end

                NoFallDamage:Clean(function()
                    for _, v in fallConns do
                        v:Enable()
                    end
                    table.clear(fallConns)
                    if oldGroundHit then
                        pcall(function()
                            hookfunction(debug.getproto(bedwars.Knit.Controllers.FallDamageController.KnitStart, 1), oldGroundHit)
                        end)
                        oldGroundHit = nil
                    end
                end)
            end
        end,
        Tooltip = 'Prevents fall damage.\nSpoof - Rewrites freefall packets to running (requires raknet)\nBlock - Auto-places a block under you before landing',
    })
    Method = NoFallDamage:CreateDropdown({
        Name = 'Method',
        List = { 'Spoof', 'Block' },
        Function = function()
            if NoFallDamage.Enabled then
                NoFallDamage:Toggle()
                NoFallDamage:Toggle()
            end
        end,
        Tooltip = 'Spoof - Network level state spoof (needs raknet)\nBlock - Places a block under you to break the fall',
    })
end)

run(function()
	local NoFallTry1

	NoFallTry1 = vape.Categories.Blatant:CreateModule({
		Name = 'No Fall',
		Function = function(callback)
			if callback then
				if entitylib.isAlive then
					for _, v in getconnections(entitylib.character.Humanoid.StateChanged) do
						v:Disable()
					end
				end
				local tracked = 0
				NoFallTry1:Clean(runService.PostSimulation:Connect(function()
					if entitylib.isAlive and store.matchState == 1 and not (vape.Modules.InfiniteFly or {}).Enabled then
						local root = entitylib.character.RootPart
						local velo = root.Velocity
						if tracked < -45 then
							root.Velocity = Vector3.new(0, 2.5, 0)
							entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Landed)
							runService.PreRender:Wait()
							root.Velocity = velo
							bedwars.Client:Get(remotes.GroundHit):SendToServer(nil, Vector3.new(0, tracked, 0), workspace:GetServerTimeNow())
						end
						tracked = velo.Y
					end
				end))

				NoFallTry1:Clean(entitylib.Events.LocalAdded:Connect(function(ent)
					if ent.Humanoid:WaitForChild('Animator', 5) then
						task.wait(0.5)
						if NoFallTry1.Enabled then
							NoFallTry1:Toggle()
							NoFallTry1:Toggle()
						end
					end
				end))
			end
		end,
		Tooltip = 'Prevents taking fall damage.'
	})
end)

--[[
    World
]]

run(function()
    vape.Categories.World:CreateModule({
        Name = 'Anti-AFK',
        Function = function(callback)
            if callback then
                for _, v in getconnections(lplr.Idled) do
                    v:Disconnect()
                end
    
                for _, v in getconnections(runService.Heartbeat) do
                    if type(v.Function) == 'function' and table.find(debug.getconstants(v.Function), remotes.AfkStatus) then
                        v:Disconnect()
                    end
                end
    
                bedwars.Client:Get(remotes.AfkStatus):SendToServer({
                    afk = false
                })
            end
        end,
        Tooltip = 'Lets you stay ingame without getting kicked'
    })
end)

run(function()
    local AutoSuffocate
    local Range
    local LimitItem
    
    local function fixPosition(pos)
        return bedwars.BlockController:getBlockPosition(pos) * 3
    end
    
    AutoSuffocate = vape.Categories.World:CreateModule({
        Name = 'Auto Suffocate',
        Function = function(callback)
            if callback then
                repeat
                    local item = store.hand.toolType == 'block' and store.hand.tool.Name or not LimitItem.Enabled and getWool()
    
                    if item then
                        local plrs = entitylib.AllPosition({
                            Part = 'RootPart',
                            Range = Range.Value,
                            Players = true
                        })
    
                        for _, ent in plrs do
                            local needPlaced = {}
    
                            for _, side in Enum.NormalId:GetEnumItems() do
                                side = Vector3.fromNormalId(side)
                                if side.Y ~= 0 then continue end
    
                                side = fixPosition(ent.RootPart.Position + side * 2)
                                if not getPlacedBlock(side) then
                                    table.insert(needPlaced, side)
                                end
                            end
    
                            if #needPlaced < 3 then
                                table.insert(needPlaced, fixPosition(ent.Head.Position))
                                table.insert(needPlaced, fixPosition(ent.RootPart.Position - Vector3.new(0, 1, 0)))
    
                                for _, pos in needPlaced do
                                    if not getPlacedBlock(pos) then
                                        task.spawn(bedwars.placeBlock, pos, item)
                                        break
                                    end
                                end
                            end
                        end
                    end
    
                    task.wait(0.09)
                until not AutoSuffocate.Enabled
            end
        end,
        Tooltip = 'Places blocks on nearby confined entities'
    })
    Range = AutoSuffocate:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 20,
        Default = 20,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    LimitItem = AutoSuffocate:CreateToggle({
        Name = 'Limit to Items',
        Default = true
    })
end)

run(function()
    local AutoTool
    local old, event
    
    local function switchHotbarItem(block)
        if block and not block:GetAttribute('NoBreak') and not block:GetAttribute('Team'..(lplr:GetAttribute('Team') or 0)..'NoBreak') then
            local tool, slot = store.tools[bedwars.ItemMeta[block.Name].block.breakType], nil
            if tool then
                for i, v in store.inventory.hotbar do
                    if v.item and v.item.itemType == tool.itemType then slot = i - 1 break end
                end
    
                if hotbarSwitch(slot) then
                    if inputService:IsMouseButtonPressed(0) then 
                        event:Fire() 
                    end
                    return true
                end
            end
        end
    end
    
    AutoTool = vape.Categories.World:CreateModule({
        Name = 'Auto Tool',
        Function = function(callback)
            if callback then
                event = Instance.new('BindableEvent')
                AutoTool:Clean(event)
                AutoTool:Clean(event.Event:Connect(function()
                    contextActionService:CallFunction('block-break', Enum.UserInputState.Begin, newproxy(true))
                end))
                old = bedwars.BlockBreaker.hitBlock
                bedwars.BlockBreaker.hitBlock = function(self, maid, raycastparams, ...)
                    local block = self.clientManager:getBlockSelector():getMouseInfo(1, {ray = raycastparams})
                    if switchHotbarItem(block and block.target and block.target.blockInstance or nil) then return end
                    return old(self, maid, raycastparams, ...)
                end
            else
                bedwars.BlockBreaker.hitBlock = old
                old = nil
            end
        end,
        Tooltip = 'Automatically selects the correct tool'
    })
end)

run(function()
    local BedAssist
    local AimMode
    local Speed
    local Range
    local Shake
    local Angle
    local Sort
    local Mode
    local Limit
    
    local function ease(t)
        return t < 0.5 and 4 * t * t * t or 1 - math.pow(-2 * t + 2, 3) / 2
    end
    
    local started = 0
    local aimfuncs = {
        Simple = function(localcframe, pos, fps)
            local rng = Random.new()
            return localcframe:Lerp(
                CFrame.lookAt(
                    localcframe.p,
                    pos
                        + Vector3.new(
                            (rng:NextNumber() - 0.5) * Shake.Value * fps,
                            (rng:NextNumber() - 0.5) * Shake.Value * fps,
                            (rng:NextNumber() - 0.5) * Shake.Value * fps
                        )
                ),
                Speed.Value * fps
            ),
                Speed.Value
        end,
        Adaptive = function(localcframe, pos, fps)
            local prog, rng = ease(math.min((tick() - started) / (1 / (Speed.Value * 0.5)), 1)), Random.new()
            local speed = Speed.Value * prog
            return localcframe:Lerp(CFrame.lookAt(localcframe.p, pos + Vector3.new((rng:NextNumber() - 0.5) * Shake.Value * fps, (rng:NextNumber() - 0.5) * Shake.Value * fps, (rng:NextNumber() - 0.5) * Shake.Value * fps)), speed * fps), speed
        end
    }
    
    local function getMousePosition()
        local suc, mouseinfo = pcall(function()
            return bedwars.BlockBreaker.clientManager:getBlockSelector():getMouseInfo(0)
        end)
    
        if suc and mouseinfo then
            if mouseinfo.target and mouseinfo.target.blockRef then
                return mouseinfo.target.blockRef.blockPosition * 3
            end
            if mouseinfo.placementPosition then
                return mouseinfo.placementPosition * 3
            end
        end
        return nil
    end
    
    local function getBestPosition(block)
        local handler = bedwars.BlockController:getHandlerRegistry():getHandler(block.Name)
        local cost, pos = math.huge, nil
        local mag = 9e9
    
        local positions = (handler and handler:getContainedPositions(block) or { block.Position / 3 })
    
        for _, v in positions do
            local dpos, dcost = calculatePath(block, v * 3, breakmethods[Sort.Value], Angle.Value, getMousePosition())
            local dmag = dpos and (entitylib.character.RootPart.Position - dpos).Magnitude
    
            if dpos then
                if dcost < cost or (dcost == cost and dmag < mag) then
                    cost, pos, mag = dcost, dpos, dmag
                end
            end
        end
    
        if pos and (entitylib.character.RootPart.Position - pos).Magnitude <= Range.Value then
            return pos
        end
        return nil
    end
    
    BedAssist = vape.Categories.World:CreateModule({
        Name = 'Bed Assist',
        Function = function(call)
            if call then
                repeat
                    task.wait()
                until store.matchState ~= 0 or not BedAssist.Enabled
                if not BedAssist.Enabled then
                    return
                end
    
                local beds = collection('bed', BedAssist, function(tab, obj)
                    task.delay(0, function()
                        if not obj:GetAttribute('Team' .. (lplr:GetAttribute('Team') or -1) .. 'NoBreak') then
                            table.insert(tab, obj)
                        end
                    end)
                end)
                local rng = Random.new()
                local lastbed = nil
    
                BedAssist:Clean(runService.PostSimulation:Connect(function(dt)
                    if entitylib.isAlive and (not Limit.Enabled or store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name].breakBlock) then
                        local localPosition = entitylib.character.RootPart.Position
                        for _, v in beds do
                            if (localPosition - v.Position).Magnitude <= Range.Value then
                                if lastbed ~= v then
                                    started = tick()
                                end
                                lastbed = v
    
                                local pos = getBestPosition(v)
                                if pos then
                                    local pred, speed = aimfuncs[AimMode.Value](gameCamera.CFrame, pos, dt)
    
                                    if Mode.Value == 'Mouse' then
                                        pos = pos + Vector3.new(
                                            (rng:NextNumber() - 0.5) * Shake.Value * 0.1,
                                            (rng:NextNumber() - 0.5) * Shake.Value * 0.1,
                                            (rng:NextNumber() - 0.5) * Shake.Value * 0.1
                                        )
                                        local campos, vis = gameCamera:WorldToViewportPoint(pos)
    
                                        if vis then
                                            local vec2 = (
                                                Vector2.new(campos.X, campos.Y) - inputService:GetMouseLocation()
                                            ) * (speed * dt)
                                            mousemoverel(vec2.X, vec2.Y)
                                        end
                                    else
                                        gameCamera.CFrame = pred
                                    end
                                end
                                break
                            end
                        end
                    end
                end))
            end
        end,
        Tooltip = 'Smoothly aims towards a bed close to your mouse'
    })
    
    local list = {'Camera'}
    if inputService.MouseEnabled and mousemoverel then
        table.insert(list, 'Mouse')
    end
    AimMode = BedAssist:CreateDropdown({
        Name = 'Mode',
        List = {'Simple', 'Adaptive'},
        Default = 'Simple',
    })
    Mode = BedAssist:CreateDropdown({
        Name = 'Aim Mode',
        List = list,
        Default = 'Camera',
    })
    Sort = BedAssist:CreateDropdown({
        Name = 'Target Mode',
        List = {'Distance', 'Health'},
        Default = 'Distance',
    })
    Speed = BedAssist:CreateSlider({
        Name = 'Aim Speed',
        Min = 1,
        Max = 20,
        Default = 7,
    })
    Range = BedAssist:CreateSlider({
        Name = 'Assist Range',
        Min = 1,
        Max = 30,
        Default = 20,
        Suffix = function(val)
            return val <= 1 and 'stud' or 'studs'
        end,
    })
    Shake = BedAssist:CreateSlider({
        Name = 'Shake',
        Min = 1,
        Max = 100,
        Default = 3,
    })
    Angle = BedAssist:CreateSlider({
        Name = 'Max angle',
        Min = 1,
        Max = 360,
        Default = 200,
    })
    Limit = BedAssist:CreateToggle({Name = 'Limit to item', Default = true})
end)

run(function()
    local BedProtector
    local PlaceRange
    local Blacklist
    local Mode
    local Smart
    local Switch
    local Layers
    local PlaceHz
    local AutoPatch
    local ProtectedLayers
    local PlacementSpeed

    local function getBedNear()
        local best, bestDist = nil, math.huge
        for _, v in collectionService:GetTagged('bed') do
            if not v:GetAttribute('Team' .. (lplr:GetAttribute('Team') or -1) .. 'NoBreak') then continue end
            local d = entitylib.isAlive and (entitylib.character.RootPart.Position - v.Position).Magnitude or math.huge
            if d < bestDist then
                best, bestDist = v, d
            end
        end
        return best
    end

    local function getBlocks()
        local blocks = {}
        for _, item in store.inventory.inventory.items do
            local block = bedwars.ItemMeta[item.itemType].block
            if
                block and not table.find(Blacklist.ListEnabled, item.itemType:find('wool') and 'wool' or item.itemType)
            then
                table.insert(blocks, { item.itemType, block.health, item.tool })
            end
        end
        table.sort(blocks, function(a, b)
            return a[2] > b[2]
        end)
        return blocks
    end

    local function getPyramid(size, grid)
        local positions = {}
        for h = size, 0, -1 do
            for w = h, 0, -1 do
                table.insert(positions, Vector3.new(w, (size - h), ((h + 1) - w)) * grid)
                table.insert(positions, Vector3.new(w * -1, (size - h), ((h + 1) - w)) * grid)
                table.insert(positions, Vector3.new(w, (size - h), (h - w) * -1) * grid)
                table.insert(positions, Vector3.new(w * -1, (size - h), (h - w) * -1) * grid)
            end
        end
        return positions
    end

    local function isEnemy(player)
        if not player then return false end
        local myTeam = lplr:GetAttribute('Team')
        return player:GetAttribute('Team') ~= myTeam
    end

    local function isWithinProtectedLayers(worldPos, bed)
        if not bed then return false end
        local relPos = bed.CFrame:PointToObjectSpace(worldPos)
        local gx = math.floor(relPos.X / 3 + 0.5)
        local gy = math.floor(relPos.Y / 3 + 0.5)
        local gz = math.floor(relPos.Z / 3 + 0.5)
        local maxLayer = ProtectedLayers.Value
        for layer = 1, maxLayer do
            for _, pos in getPyramid(layer, 3) do
                local px = math.floor(pos.X / 3 + 0.5)
                local py = math.floor(pos.Y / 3 + 0.5)
                local pz = math.floor(pos.Z / 3 + 0.5)
                if px == gx and py == gy and pz == gz then
                    return true
                end
            end
        end
        return false
    end

    BedProtector = vape.Categories.World:CreateModule({
        Name = 'Draco X2',
        Function = function(callback)
            if callback then
                BedProtector:Clean(vapeEvents.BreakBlockEvent.Event:Connect(function(data)
                    if not BedProtector.Enabled then return end
                    if not AutoPatch.Enabled then return end
                    if not entitylib.isAlive then return end
                    if not isEnemy(data.player) then return end

                    local worldPos = data.blockRef.blockPosition * 3
                    local bed = getBedNear()
                    if not bed then return end
                    if (worldPos - bed.Position).Magnitude > PlaceRange.Value then return end
                    if not isWithinProtectedLayers(worldPos, bed) then return end
                    if getPlacedBlock(worldPos) then return end

                    local blocks = getBlocks()
                    if #blocks == 0 then return end
                    local block = blocks[1]

                    task.spawn(function()
                        if PlacementSpeed.Value > 0 then
                            task.wait(PlacementSpeed.Value / 1000)
                        end

                        if getPlacedBlock(worldPos) then return end

                        local old = store.hand and store.hand.tool and getHotbar(store.hand.tool) or nil
                        local switched = false

                        if Switch.Enabled then
                            local hotbar = getHotbar(block[3])
                            if hotbar and hotbarSwitch(hotbar) then
                                switched = true
                                task.wait()
                            end
                        end

                        bedwars.placeBlock(worldPos, block[1], false)

                        if switched and old then
                            task.wait()
                            hotbarSwitch(old)
                        end
                    end)
                end))

                repeat
                    local bed = getBedNear()
                    if bed then
                        for i, block in getBlocks() do
                            if i > Layers.Value then
                                break
                            end
                            local switch, old = Switch.Enabled, store.hand and store.hand.tool and getHotbar(store.hand.tool) or nil
                            local hotbar = nil

                            if switch then
                                hotbar = getHotbar(block[3])
                            end

                            for _, pos in getPyramid(i, 3) do
                                if not BedProtector.Enabled then
                                    break
                                end
                                pos = (bed.CFrame * CFrame.new(pos)).Position
                                -- Respect Place Range: only place blocks within that distance of the player
                                if entitylib.isAlive and (pos - entitylib.character.RootPart.Position).Magnitude > PlaceRange.Value then
                                    continue
                                end
                                if getPlacedBlock(pos) then
                                    continue
                                end
                                if hotbar and hotbarSwitch(hotbar) then
                                    task.wait()
                                end
                                task.spawn(bedwars.placeBlock, pos, block[1], false)
                                task.wait(1 / PlaceHz.Value)
                            end

                            if switch and old and hotbarSwitch(old) then
                                task.wait()
                            end
                        end
                    else
                        if Mode.Value == 'On Key' then
                            notif('Draco X2', 'Unable to locate bed', 5)
                            BedProtector:Toggle()
                        end
                    end
                    task.wait(0.5)
                    if Mode.Value == 'On Key' then
                        BedProtector:Toggle()
                        break
                    end
                until not BedProtector.Enabled
            end
        end,
        Tooltip = 'Automatically places and defends blocks around the bed.'
    })

    Mode = BedProtector:CreateDropdown({
        Name = 'Mode',
        List = {'Toggle', 'On Key'},
        Default = 'Toggle',
        Function = function(val)
            if Smart then
                Smart.Object.Visible = val == 'Toggle'
            end
        end,
    })
    Blacklist = BedProtector:CreateTextList({
        Name = 'Blacklist',
        Default = {'siege_tnt', 'tnt'},
    })
    PlaceRange = BedProtector:CreateSlider({
        Name = 'Place Range',
        Min = 1,
        Max = 40,
        Default = 15,
        Suffix = function(v) return v == 1 and 'stud' or 'studs' end,
        Tooltip = 'Only place/patch blocks within this distance of you; lower it to build tighter around the bed'
    })
    Layers = BedProtector:CreateSlider({
        Name = 'Layers',
        Min = 1,
        Max = 8,
        Default = 3,
        Suffix = function(v) return v == 1 and 'layer' or 'layers' end,
        Tooltip = 'How many pyramid layers to build around the bed; set to 1 to only build the closest layer'
    })
    PlaceHz = BedProtector:CreateSlider({
        Name = 'Place Hz',
        Min = 1,
        Max = 20,
        Default = 10,
        Suffix = 'hz',
        Tooltip = 'How many blocks to place per second; higher = faster'
    })
    Switch = BedProtector:CreateToggle({Name = 'Auto Switch'})
    Smart = BedProtector:CreateToggle({Name = 'Smart', Default = true})
    AutoPatch = BedProtector:CreateToggle({
        Name = 'AutoPatch',
        Default = false,
        Tooltip = 'When enabled, automatically replaces blocks broken by enemies within the protected layers'
    })
    ProtectedLayers = BedProtector:CreateSlider({
        Name = 'Protected Layers',
        Min = 1,
        Max = 8,
        Default = 2,
        Suffix = function(v) return v == 1 and 'layer' or 'layers' end,
        Tooltip = 'How many pyramid layers AutoPatch will monitor and rebuild when broken by enemies'
    })
    PlacementSpeed = BedProtector:CreateSlider({
        Name = 'Placement Speed',
        Min = 0,
        Max = 500,
        Default = 100,
        Suffix = 'ms',
        Tooltip = 'Delay in milliseconds before AutoPatch places a replacement block; 0 for instant'
    })

    local HiveProtector
    local HiveProtectRange
    local HiveLayers
    local HiveSwitch
    local HiveTeam
    local HiveAutoPatch
    local HiveProtectedLayers
    local HivePlacementSpeed

    local function getProtectedHives()
        local result = {}
        local myId = lplr.UserId
        local myTeam = lplr:GetAttribute('Team')
        for _, v in collectionService:GetTagged('beehive') do
            local placedById = v:GetAttribute('PlacedByUserId')
            if placedById == myId then
                table.insert(result, v)
            elseif HiveTeam.Enabled and myTeam then
                local ok, owner = pcall(game.Players.GetPlayerByUserId, game.Players, placedById)
                if ok and owner and owner:GetAttribute('Team') == myTeam then
                    table.insert(result, v)
                end
            end
        end
        return result
    end

    local function isNearHive(worldPos)
        for _, hive in getProtectedHives() do
            if (worldPos - hive.Position).Magnitude <= HiveProtectRange.Value then
                local relPos = hive.CFrame:PointToObjectSpace(worldPos)
                local gx = math.floor(relPos.X / 3 + 0.5)
                local gy = math.floor(relPos.Y / 3 + 0.5)
                local gz = math.floor(relPos.Z / 3 + 0.5)
                for layer = 1, HiveProtectedLayers.Value do
                    for _, pos in getPyramid(layer, 3) do
                        local px = math.floor(pos.X / 3 + 0.5)
                        local py = math.floor(pos.Y / 3 + 0.5)
                        local pz = math.floor(pos.Z / 3 + 0.5)
                        if px == gx and py == gy and pz == gz then
                            return hive
                        end
                    end
                end
            end
        end
        return nil
    end

    HiveProtector = vape.Categories.Kits:CreateModule({
        Name = 'Hive Protector',
        Function = function(callback)
            if callback then
                HiveProtector:Clean(vapeEvents.BreakBlockEvent.Event:Connect(function(data)
                    if not HiveProtector.Enabled then return end
                    if not HiveAutoPatch.Enabled then return end
                    if not entitylib.isAlive then return end
                    if not isEnemy(data.player) then return end

                    local worldPos = data.blockRef.blockPosition * 3
                    if getPlacedBlock(worldPos) then return end
                    if not isNearHive(worldPos) then return end

                    local blocks = getBlocks()
                    if #blocks == 0 then return end
                    local block = blocks[1]

                    task.spawn(function()
                        if HivePlacementSpeed.Value > 0 then
                            task.wait(HivePlacementSpeed.Value / 1000)
                        end
                        if getPlacedBlock(worldPos) then return end
                        if (entitylib.character.RootPart.Position - worldPos).Magnitude > HiveProtectRange.Value then return end

                        local old = store.hand and store.hand.tool and getHotbar(store.hand.tool) or nil
                        local switched = false
                        if HiveSwitch.Enabled then
                            local hotbar = getHotbar(block[3])
                            if hotbar and hotbarSwitch(hotbar) then
                                switched = true
                                task.wait()
                            end
                        end
                        bedwars.placeBlock(worldPos, block[1], false)
                        if switched and old then
                            task.wait()
                            hotbarSwitch(old)
                        end
                    end)
                end))

                repeat
                    if entitylib.isAlive then
                        for _, hive in getProtectedHives() do
                            for i, block in getBlocks() do
                                if i > HiveLayers.Value then break end

                                local switch = HiveSwitch.Enabled
                                local old = store.hand and store.hand.tool and getHotbar(store.hand.tool) or nil
                                local hotbar = nil
                                if switch then hotbar = getHotbar(block[3]) end

                                for _, pos in getPyramid(i, 3) do
                                    if not HiveProtector.Enabled then break end
                                    pos = (hive.CFrame * CFrame.new(pos)).Position
                                    if getPlacedBlock(pos) then continue end
                                    if (entitylib.character.RootPart.Position - pos).Magnitude > HiveProtectRange.Value then continue end
                                    if hotbar and hotbarSwitch(hotbar) then task.wait() end
                                    task.spawn(bedwars.placeBlock, pos, block[1], false)
                                    task.wait(0.1)
                                end

                                if switch and old and hotbarSwitch(old) then task.wait() end
                            end
                        end
                    end
                    task.wait(0.5)
                until not HiveProtector.Enabled
            end
        end,
        Tooltip = 'Automatically places and defends blocks around your beehive(s)'
    })
    HiveProtectRange = HiveProtector:CreateSlider({
        Name = 'Place Range',
        Min = 1,
        Max = 30,
        Default = 15,
    })
    HiveLayers = HiveProtector:CreateSlider({
        Name = 'Layers',
        Min = 1,
        Max = 8,
        Default = 3,
        Suffix = function(v) return v == 1 and 'layer' or 'layers' end,
        Tooltip = 'How many pyramid layers to build around each hive'
    })
    HiveSwitch = HiveProtector:CreateToggle({Name = 'Auto Switch'})
    HiveTeam = HiveProtector:CreateToggle({
        Name = 'Team hives',
        Tooltip = 'Also protect beehives placed by your teammates'
    })
    HiveAutoPatch = HiveProtector:CreateToggle({
        Name = 'AutoPatch',
        Default = false,
        Tooltip = 'Instantly re-places blocks broken by enemies in the protected zone around your hive(s)'
    })
    HiveProtectedLayers = HiveProtector:CreateSlider({
        Name = 'Protected Layers',
        Min = 1,
        Max = 8,
        Default = 2,
        Suffix = function(v) return v == 1 and 'layer' or 'layers' end,
        Tooltip = 'How many layers around each hive AutoPatch monitors and rebuilds'
    })
    HivePlacementSpeed = HiveProtector:CreateSlider({
        Name = 'Placement Speed',
        Min = 0,
        Max = 500,
        Default = 100,
        Suffix = 'ms',
        Tooltip = 'Delay before AutoPatch places a replacement block; 0 for instant'
    })
end)

run(function()
	local BlockIn
	local Mode
	local Priority
	local Return
	local Switch
	local Wool
	local Blacklist
	
	local scan = 30
	local dirs = {
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1)
	}
	local priorities = {
		['Lowest cost'] = function(a, b)
			return a[2] < b[2]
		end,
		['Hardest'] = function(a, b)
			return a[2] > b[2]
		end
	}
	
	local function round(p)
		return Vector3.new(
			math.floor(p.X / 3 + 0.5) * 3,
			math.floor(p.Y / 3 + 0.5) * 3,
			math.floor(p.Z / 3 + 0.5) * 3
		)
	end
	
	local function getOrigin()
		local pos = entitylib.character.RootPart.Position
		local ray = entitylib.Raycast(pos, Vector3.new(0, -scan, 0), store.airRay)
		return roundPos(ray and Vector3.new(pos.X, ray.Position.Y + 1.5, pos.Z) or pos)
	end
	
	local function isDefended(bed)
		local handler = bedwars.BlockController:getHandlerRegistry():getHandler(bed.Name)
		local cells = handler and handler:getContainedPositions(bed) or {bed.Position / 3}
		local occupied = {}
		for _, v in cells do
			occupied[v * 3] = true
		end
		for _, v in cells do
			for _, side in sides do
				local pos = (v * 3) + side
				if not occupied[pos] and not getPlacedBlock(pos) then
					return false
				end
			end
		end
		return true
	end
	
	local function getBedNear()
		local localPosition = entitylib.character.RootPart.Position
		for _, v in collectionService:GetTagged('bed') do
			if (localPosition - v.Position).Magnitude < 14 and not v:GetAttribute(`Team{lplr:GetAttribute('Team') or -1}NoBreak`) and isDefended(v) then
				return v
			end
		end
		return nil
	end
	
	local function find(getBlock, col, topY)
		local y = topY
		local bot = topY - scan
		while y >= bot do
			local pos = Vector3.new(col.X, y, col.Z)
			if getBlock(round(pos)) then
				return y
			end
			y -= 3
		end
		return nil
	end
	
	local function buildCol(getBlock, root, dir, height)
		local out = {}
		local col = root + dir * 3
		local topY = root.Y + 2 * 3
		local sup = find(getBlock, col, topY)
		local sy
		if sup then
			sy = sup + 3
		else
			sy = topY - (height - 1) * 3
		end
		local y = sy
		while y <= topY do
			table.insert(out, Vector3.new(dir.X * 3, y - root.Y, dir.Z * 3))
			y += 3
		end
		return out
	end
	
	local function getPattern(root, getBlock)
		local pattern = {}
		local cols = {}
		for _, dir in ipairs(dirs) do
			local out = buildCol(getBlock, root, dir, 2)
			table.insert(cols, {dir = dir, out = out, cost = #out})
		end
		table.sort(cols, function(a, b)
			return a.cost < b.cost
		end)
		cols[1].out = buildCol(getBlock, root, cols[1].dir, 2)
		cols[1].cost = #cols[1].out
		local capY = 0
		for _, c in ipairs(cols) do
			if #c.out > 0 then
				local top = c.out[#c.out]
				if top.Y > capY then
					capY = top.Y
				end
			end
		end
		for _, o in ipairs(cols[1].out) do
			table.insert(pattern, o)
		end
		table.insert(pattern, Vector3.new(0, capY, 0))
		for i = 2, #cols do
			for _, o in ipairs(cols[i].out) do
				if o.Y ~= capY then
					table.insert(pattern, o)
				end
			end
		end
		return pattern
	end
	
	local function getBlocks()
		local blocks = {}
		for _, item in store.inventory.inventory.items do
			local block = bedwars.ItemMeta[item.itemType].block
			if block and (Wool.Enabled and item.itemType:find('wool') or not Wool.Enabled and not table.find(Blacklist.ListEnabled, item.itemType:find('wool') and 'wool' or item.itemType)) then
				table.insert(blocks, {item.itemType, block.health, item.tool})
			end
		end
		if #blocks > 1 then
			table.sort(blocks, priorities[Priority.Value])
		end
		return blocks
	end
	
	local function placePattern(origin, patterns, limit)
		local hotbar = store.hand.tool and getHotbar(store.hand.tool) or 0
		local placed = 0
		for _, v in getBlocks() do
			if placed >= limit then break end
			local block = getHotbar(v[3])
			if not block and Switch.Enabled then
				continue
			end
	
			if Switch.Enabled then
				hotbarSwitch(block)
			end
			for _, pos in patterns do
				if placed >= limit or not entitylib.isAlive then break end
				if getPlacedBlock(origin + pos) then continue end
				repeat task.wait() until not entitylib.isAlive or (workspace:GetServerTimeNow() - bedwars.BlockCpsController.lastPlaceTimestamp) >= (1 / 12)
				if not entitylib.isAlive then break end
	
				local root = entitylib.character.RootPart
				if math.abs(root.Position.X - origin.X) > 0.5 or math.abs(root.Position.Z - origin.Z) > 0.5 then
					root.CFrame = CFrame.new(origin.X, root.Position.Y, origin.Z) * (root.CFrame - root.Position)
				end
				bedwars.placeBlock(origin + pos, v[1], true)
				placed += 1
			end
		end
		if Return.Enabled and Switch.Enabled and hotbar then
			hotbarSwitch(hotbar)
		end
	end
	
	BlockIn = vape.Categories.World:CreateModule({
		Name = 'Block-In',
		Function = function(callback)
			if callback then
				repeat
					if entitylib.isAlive and (Mode.Value == 'On bind' or getBedNear()) then
						local early = false
						repeat
							task.wait()
							if entitylib.isAlive and not early then
								local origin = getOrigin()
								local drop = entitylib.character.RootPart.Position.Y - origin.Y
								early = drop >= 6 and drop <= 24
								if early then
									placePattern(origin, getPattern(origin, getPlacedBlock), 3)
								end
							end
						until not BlockIn.Enabled or not entitylib.isAlive or entitylib.character.Humanoid.FloorMaterial ~= Enum.Material.Air
	
						if entitylib.isAlive then
							local origin = getOrigin()
							placePattern(origin, getPattern(origin, getPlacedBlock), math.huge)
						end
					end
	
					if Mode.Value == 'On bind' then
						BlockIn:Toggle()
						break
					end
					task.wait(0.5)
				until not BlockIn.Enabled
			end
		end,
		Tooltip = 'Automatically blocks you in by building walls around you'
	})
	Mode = BlockIn:CreateDropdown({
		Name = 'Mode',
		List = {'On bind', 'When near'},
		Default = 'On bind',
		Tooltip = 'On bind blocks you in once per keypress, When near keeps you blocked in while you are on an enemy bed'
	})
	Priority = BlockIn:CreateDropdown({
		Name = 'Block priority',
		List = {'Lowest cost', 'Hardest'},
		Default = 'Lowest cost'
	})
	Switch = BlockIn:CreateToggle({Name = 'Switch', Default = true})
	Return = BlockIn:CreateToggle({Name = 'Return to last slot', Default = true})
	Wool = BlockIn:CreateToggle({Name = 'Wool only'})
	Blacklist = BlockIn:CreateTextList({
		Name = 'Blacklist',
		Default = {'cannon', 'siege_tnt', 'tnt'}
	})
end)

run(function()
    local ChestSteal
    local Range
    local Open
    local Skywars
    local Delays = {}
    
    local function lootChest(chest)
        chest = chest and chest.Value or nil
        local chestitems = chest and chest:GetChildren() or {}
        if #chestitems > 1 and (Delays[chest] or 0) < tick() then
            Delays[chest] = tick() + 0.2
            bedwars.Client:GetNamespace('Inventory'):Get('SetObservedChest'):SendToServer(chest)
    
            for _, v in chestitems do
                if v:IsA('Accessory') then
                    task.spawn(pcall, function()
                        bedwars.Client:GetNamespace('Inventory'):Get('ChestGetItem'):CallServer(chest, v)
                    end)
                end
            end
    
            bedwars.Client:GetNamespace('Inventory'):Get('SetObservedChest'):SendToServer(nil)
        end
    end
    
    ChestSteal = vape.Categories.World:CreateModule({
        Name = 'Chest Steal',
        Function = function(callback)
            if callback then
                local chests = collection('chest', ChestSteal)
                repeat task.wait() until store.queueType ~= 'bedwars_test'
                if (not Skywars.Enabled) or store.queueType:find('skywars') then
                    repeat
                        if entitylib.isAlive and store.matchState ~= 2 then
                            if Open.Enabled then
                                if bedwars.AppController:isAppOpen('ChestApp') then
                                    lootChest(lplr.Character:FindFirstChild('ObservedChestFolder'))
                                end
                            else
                                local localPosition = entitylib.character.RootPart.Position
                                for _, v in chests do
                                    if (localPosition - v.Position).Magnitude <= Range.Value then
                                        lootChest(v:FindFirstChild('ChestFolderValue'))
                                    end
                                end
                            end
                        end
                        task.wait(0.1)
                    until not ChestSteal.Enabled
                end
            end
        end,
        Tooltip = 'Grabs items from near chests.'
    })
    Range = ChestSteal:CreateSlider({
        Name = 'Range',
        Min = 0,
        Max = 18,
        Default = 18,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    Open = ChestSteal:CreateToggle({Name = 'GUI Check'})
    Skywars = ChestSteal:CreateToggle({
        Name = 'Only Skywars',
        Function = function()
            if ChestSteal.Enabled then
                ChestSteal:Toggle()
                ChestSteal:Toggle()
            end
        end,
        Default = true
    })
end)

run(function()
    local FastPlace
    local CPS
    
    local old = bedwars.SharedConstants.BLOCK_PLACE_CPS
    
    FastPlace = vape.Categories.World:CreateModule({
    	Name = 'Fast Place',
    	Function = function(call)
    		bedwars.SharedConstants.BLOCK_PLACE_CPS = call and CPS.Value or old
    	end,
        Tooltip = 'Changes place delay'
    })
    CPS = FastPlace:CreateSlider({
    	Name = 'Cps',
    	Min = 1,
    	Max = 100,
    	Default = 13,
    	Function = function(val)
    		if FastPlace.Enabled then
    			bedwars.SharedConstants.BLOCK_PLACE_CPS = val
    		end
    	end,
    })
    FastPlace:CreateButton({
    	Name = 'Reset to bedwars cps',
    	Function = function()
    		CPS:SetValue(12)
    	end,
    })
end)

run(function()
    local Schematica
    local File
    local Mode
    local Transparency
    local parts, guidata, poschecklist = {}, {}, {}
    local point1, point2
    
    for x = -3, 3, 3 do
        for y = -3, 3, 3 do
            for z = -3, 3, 3 do
                if Vector3.new(x, y, z) ~= Vector3.zero then
                    table.insert(poschecklist, Vector3.new(x, y, z))
                end
            end
        end
    end
    
    local function checkAdjacent(pos)
        for _, v in poschecklist do
            if getPlacedBlock(pos + v) then return true end
        end
        return false
    end
    
    local function getPlacedBlocksInPoints(s, e)
        local list, blocks = {}, bedwars.BlockController:getStore()
        for x = (e.X > s.X and s.X or e.X), (e.X > s.X and e.X or s.X) do
            for y = (e.Y > s.Y and s.Y or e.Y), (e.Y > s.Y and e.Y or s.Y) do
                for z = (e.Z > s.Z and s.Z or e.Z), (e.Z > s.Z and e.Z or s.Z) do
                    local vec = Vector3.new(x, y, z)
                    local block = blocks:getBlockAt(vec)
                    if block and block:GetAttribute('PlacedByUserId') == lplr.UserId then
                        list[vec] = block
                    end
                end
            end
        end
        return list
    end
    
    local function loadMaterials()
        for _, v in guidata do 
            v:Destroy() 
        end
        local suc, read = pcall(function() 
            return isfile(File.Value) and httpService:JSONDecode(readfile(File.Value)) 
        end)
    
        if suc and read then
            local items = {}
            for _, v in read do 
                items[v[2]] = (items[v[2]] or 0) + 1 
            end
            
            for i, v in items do
                local holder = Instance.new('Frame')
                holder.Size = UDim2.new(1, 0, 0, 32)
                holder.BackgroundTransparency = 1
                holder.Parent = Schematica.Children
                local icon = Instance.new('ImageLabel')
                icon.Size = UDim2.fromOffset(24, 24)
                icon.Position = UDim2.fromOffset(4, 4)
                icon.BackgroundTransparency = 1
                icon.Image = bedwars.getIcon({itemType = i}, true)
                icon.Parent = holder
                local text = Instance.new('TextLabel')
                text.Size = UDim2.fromOffset(100, 32)
                text.Position = UDim2.fromOffset(32, 0)
                text.BackgroundTransparency = 1
                text.Text = (bedwars.ItemMeta[i] and bedwars.ItemMeta[i].displayName or i)..': '..v
                text.TextXAlignment = Enum.TextXAlignment.Left
                text.TextColor3 = uipallet.Text
                text.TextSize = 14
                text.FontFace = uipallet.Font
                text.Parent = holder
                table.insert(guidata, holder)
            end
            table.clear(read)
            table.clear(items)
        end
    end
    
    local function save()
        if point1 and point2 then
            local tab = getPlacedBlocksInPoints(point1, point2)
            local savetab = {}
            point1 = point1 * 3
            for i, v in tab do
                i = bedwars.BlockController:getBlockPosition(CFrame.lookAlong(point1, entitylib.character.RootPart.CFrame.LookVector):PointToObjectSpace(i * 3)) * 3
                table.insert(savetab, {
                    {
                        x = i.X, 
                        y = i.Y, 
                        z = i.Z
                    }, 
                    v.Name
                })
            end
            point1, point2 = nil, nil
            writefile(File.Value, httpService:JSONEncode(savetab))
            notif('Schematica', 'Saved '..getTableSize(tab)..' blocks', 5)
            loadMaterials()
            table.clear(tab)
            table.clear(savetab)
        else
            local mouseinfo = bedwars.BlockBreaker.clientManager:getBlockSelector():getMouseInfo(0)
            if mouseinfo and mouseinfo.target then
                if point1 then
                    point2 = mouseinfo.target.blockRef.blockPosition
                    notif('Schematica', 'Selected position 2, toggle again near position 1 to save it', 3)
                else
                    point1 = mouseinfo.target.blockRef.blockPosition
                    notif('Schematica', 'Selected position 1', 3)
                end
            end
        end
    end
    
    local function load(read)
        local mouseinfo = bedwars.BlockBreaker.clientManager:getBlockSelector():getMouseInfo(0)
        if mouseinfo and mouseinfo.target then
            local position = CFrame.new(mouseinfo.placementPosition * 3) * CFrame.Angles(0, math.rad(math.round(math.deg(math.atan2(-entitylib.character.RootPart.CFrame.LookVector.X, -entitylib.character.RootPart.CFrame.LookVector.Z)) / 45) * 45), 0)
    
            for _, v in read do
                local handler
                local blockpos = bedwars.BlockController:getBlockPosition((position * CFrame.new(v[1].x, v[1].y, v[1].z)).p) * 3
                if parts[blockpos] then continue end
                handler = bedwars.BlockController:getHandlerRegistry():getHandler(v[2]:find('wool') and getWool() or v[2])
                if handler then
                    local part = handler:place(blockpos / 3, 0)
                    part.Transparency = Transparency.Value
                    part.CanCollide = false
                    part.Anchored = true
                    part.Parent = workspace
                    parts[blockpos] = part
                end
            end
            table.clear(read)
    
            repeat
                if entitylib.isAlive then
                    local localPosition = entitylib.character.RootPart.Position
                    for i, v in parts do
                        if (i - localPosition).Magnitude < 60 and checkAdjacent(i) then
                            if not Schematica.Enabled then break end
                            if not getItem(v.Name) then continue end
                            bedwars.placeBlock(i, v.Name, false)
                            task.delay(0.1, function()
                                local block = getPlacedBlock(i)
                                if block then
                                    v:Destroy()
                                    parts[i] = nil
                                end
                            end)
                        end
                    end
                end
                task.wait()
            until getTableSize(parts) <= 0
    
            if getTableSize(parts) <= 0 and Schematica.Enabled then
                notif('Schematica', 'Finished building', 5)
                Schematica:Toggle()
            end
        end
    end
    
    Schematica = vape.Categories.World:CreateModule({
        Name = 'Schematica',
        Function = function(callback)
            if callback then
                if not File.Value:find('.json') then
                    notif('Schematica', 'Invalid file', 3)
                    Schematica:Toggle()
                    return
                end
    
                if Mode.Value == 'Save' then
                    save()
                    Schematica:Toggle()
                else
                    local suc, read = pcall(function() 
                        return isfile(File.Value) and httpService:JSONDecode(readfile(File.Value)) 
                    end)
    
                    if suc and read then
                        load(read)
                    else
                        notif('Schematica', 'Missing / corrupted file', 3)
                        Schematica:Toggle()
                    end
                end
            else
                for _, v in parts do 
                    v:Destroy() 
                end
                table.clear(parts)
            end
        end,
        Tooltip = 'Save and load placements of buildings'
    })
    File = Schematica:CreateTextBox({
        Name = 'File',
        Function = function()
            loadMaterials()
            point1, point2 = nil, nil
        end
    })
    Mode = Schematica:CreateDropdown({
        Name = 'Mode',
        List = {'Load', 'Save'}
    })
    Transparency = Schematica:CreateSlider({
        Name = 'Transparency',
        Min = 0,
        Max = 1,
        Default = 0.7,
        Decimal = 10,
        Function = function(val)
            for _, v in parts do 
                v.Transparency = val 
            end
        end
    })
end)

--[[
    Inventory
]]

run(function()
    local ArmorSwitch
    local Mode
    local Targets
    local Range
    
    ArmorSwitch = vape.Categories.Inventory:CreateModule({
        Name = 'Armor Switch',
        Function = function(callback)
            if callback then
                if Mode.Value == 'Toggle' then
                    repeat
                        local state = entitylib.EntityPosition({
                            Part = 'RootPart',
                            Range = Range.Value,
                            Players = Targets.Players.Enabled,
                            NPCs = Targets.NPCs.Enabled,
                            Wallcheck = Targets.Walls.Enabled
                        }) and true or false
    
                        for i = 0, 2 do
                            if (store.inventory.inventory.armor[i + 1] ~= 'empty') ~= state and ArmorSwitch.Enabled then
                                bedwars.Store:dispatch({
                                    type = 'InventorySetArmorItem',
                                    item = store.inventory.inventory.armor[i + 1] == 'empty' and state and getBestArmor(i) or nil,
                                    armorSlot = i
                                })
                                vapeEvents.InventoryChanged.Event:Wait()
                            end
                        end
                        task.wait(0.1)
                    until not ArmorSwitch.Enabled
                else
                    ArmorSwitch:Toggle()
                    for i = 0, 2 do
                        bedwars.Store:dispatch({
                            type = 'InventorySetArmorItem',
                            item = store.inventory.inventory.armor[i + 1] == 'empty' and getBestArmor(i) or nil,
                            armorSlot = i
                        })
                        vapeEvents.InventoryChanged.Event:Wait()
                    end
                end
            end
        end,
        Tooltip = 'Puts on / takes off armor when toggled for baiting.'
    })
    Mode = ArmorSwitch:CreateDropdown({
        Name = 'Mode',
        List = {'Toggle', 'On Key'}
    })
    Targets = ArmorSwitch:CreateTargets({
        Players = true,
        NPCs = true
    })
    Range = ArmorSwitch:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 30,
        Default = 30,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
end)

run(function()
	local NoCollision
	local connections = {}
	local trackedParts = {}
	local lastWeaponState = nil
	local weaponCheckCounter = 0

	local function hasValidWeapon()
		local toolType = store.hand and store.hand.toolType
		return toolType == 'sword' or toolType == 'bow'
	end

	local function removeCollision(character)
		if not character then return end

		local charParts = trackedParts[character]
		if not charParts then
			charParts = {}
			trackedParts[character] = charParts

			for _, part in character:GetDescendants() do
				if part:IsA("BasePart") then
					table.insert(charParts, {part = part, origCollide = part.CanCollide, origQuery = part.CanQuery})
					part.CanCollide = false
					part.CanQuery = false
				end
			end
		else
			for _, entry in charParts do
				if entry.part and entry.part.Parent then
					entry.part.CanCollide = false
					entry.part.CanQuery = false
				end
			end
		end
	end

	local function restoreCollision(character)
		if not character then return end

		local charParts = trackedParts[character]
		if charParts then
			for _, entry in charParts do
				if entry.part and entry.part.Parent then
					entry.part.CanCollide = entry.origCollide
					entry.part.CanQuery = entry.origQuery
				end
			end
		end
	end

	local function updateAllCollisions(forceUpdate)
		weaponCheckCounter = weaponCheckCounter + 1
		local shouldCheck = forceUpdate or (weaponCheckCounter % 3 == 0)

		if not shouldCheck then return end

		local isWeaponEquipped = hasValidWeapon()

		if not forceUpdate and lastWeaponState == isWeaponEquipped then
			return
		end

		lastWeaponState = isWeaponEquipped

		for _, entity in entitylib.List do
			if entity.Player and entity.Character and entity.Character.Parent then
				if isWeaponEquipped then
					restoreCollision(entity.Character)
				else
					removeCollision(entity.Character)
				end
			end
		end
	end

	local motorParts = {}
	local function updateMotorParts()
		for _, entity in entitylib.List do
			if entity.Player and entity.Character then
				local charMotors = motorParts[entity.Character]

				if not charMotors then
					charMotors = {}
					motorParts[entity.Character] = charMotors

					for _, part in entity.Character:GetChildren() do
						if part:IsA("BasePart") and part.Name == "Part" and part:FindFirstChildOfClass("Motor6D") then
							table.insert(charMotors, part)
						end
					end
				end

				for _, part in charMotors do
					if part and part.Parent then
						part.CanCollide = false
					end
				end
			end
		end
	end

	NoCollision = vape.Categories.World:CreateModule({
		Name = 'NoCollision',
		Function = function(callback)
			if callback then
				local frameCounter = 0
				local heartbeatConn = runService.Heartbeat:Connect(function()
					if not NoCollision.Enabled then return end

					frameCounter = frameCounter + 1

					if frameCounter % 6 == 0 then
						updateAllCollisions(false)
					end

					if frameCounter % 15 == 0 then
						updateMotorParts()
					end
				end)
				table.insert(connections, heartbeatConn)

				lastWeaponState = hasValidWeapon()
				for _, entity in entitylib.List do
					if entity.Player and entity.Character and entity.Character.Parent then
						if not lastWeaponState then
							removeCollision(entity.Character)
						end
					end
				end

				local entityAddedConn = entitylib.Events.EntityAdded:Connect(function(entity)
					if not NoCollision.Enabled then return end
					if entity.Player and entity.Character then
						task.wait(0.05)
						if not hasValidWeapon() then
							removeCollision(entity.Character)
						end
					end
				end)
				table.insert(connections, entityAddedConn)

				local entityRemovedConn = entitylib.Events.EntityRemoving:Connect(function(entity)
					if entity.Character then
						trackedParts[entity.Character] = nil
						motorParts[entity.Character] = nil
					end
				end)
				table.insert(connections, entityRemovedConn)

				if vapeEvents and vapeEvents.InventoryChanged then
					local inventoryConn = vapeEvents.InventoryChanged.Event:Connect(function()
						if NoCollision.Enabled then
							updateAllCollisions(true)
						end
					end)
					table.insert(connections, inventoryConn)
				else
					local lastTool = store.hand and store.hand.tool
					local toolFrameCounter = 0
					local monitorConn = runService.Heartbeat:Connect(function()
						if not NoCollision.Enabled then return end

						toolFrameCounter = toolFrameCounter + 1
						if toolFrameCounter % 5 == 0 then
							local currentTool = store.hand and store.hand.tool
							if currentTool ~= lastTool then
								lastTool = currentTool
								updateAllCollisions(true)
							end
						end
					end)
					table.insert(connections, monitorConn)
				end

				updateAllCollisions(true)
			else
				for _, conn in connections do
					conn:Disconnect()
				end
				table.clear(connections)

				for _, entity in entitylib.List do
					if entity.Character then
						restoreCollision(entity.Character)
					end
				end

				table.clear(trackedParts)
				table.clear(motorParts)
				lastWeaponState = nil
				weaponCheckCounter = 0
			end
		end,
		Tooltip = 'Mine/build through players and NPCs'
	})
end)

run(function()
    local AutoBank
    local UIToggle
    local UI
    local Chests
    local Items = {}

    local function addItem(itemType, shop)
        local item = Instance.new('ImageLabel')
        item.Image = bedwars.getIcon({itemType = itemType}, true)
        item.Size = UDim2.fromOffset(32, 32)
        item.Name = itemType
        item.BackgroundTransparency = 1
        item.LayoutOrder = #UI:GetChildren()
        item.Parent = UI
        local itemtext = Instance.new('TextLabel')
        itemtext.Name = 'Amount'
        itemtext.Size = UDim2.fromScale(1, 1)
        itemtext.BackgroundTransparency = 1
        itemtext.Text = ''
        itemtext.TextColor3 = Color3.new(1, 1, 1)
        itemtext.TextSize = 16
        itemtext.TextStrokeTransparency = 0.3
        itemtext.Font = Enum.Font.Arial
        itemtext.Parent = item
        Items[itemType] = {Object = itemtext, Type = shop}
    end

    local function refreshBank(echest)
        for i, v in Items do
            local item = echest:FindFirstChild(i)
            v.Object.Text = item and item:GetAttribute('Amount') or ''
        end
    end

    local function nearChest()
        if entitylib.isAlive then
            local pos = entitylib.character.RootPart.Position
            for _, chest in Chests do
                if (chest.Position - pos).Magnitude < 20 then
                    return true
                end
            end
        end
    end

    local function handleState()
        local chest = replicatedStorage.Inventories:FindFirstChild(lplr.Name..'_personal')
        if not chest then return end

        local mapCF = workspace.MapCFrames:FindFirstChild((lplr:GetAttribute('Team') or 1)..'_spawn')
        if mapCF and (entitylib.character.RootPart.Position - mapCF.Value.Position).Magnitude < 80 then
            for _, v in chest:GetChildren() do
                local item = Items[v.Name]
                if item then
                    task.spawn(function()
                        bedwars.Client:GetNamespace('Inventory'):Get('ChestGetItem'):CallServer(chest, v)
                        refreshBank(chest)
                    end)
                end
            end
        else
            for _, v in store.inventory.inventory.items do
                local item = Items[v.itemType]
                if item then
                    task.spawn(function()
                        bedwars.Client:GetNamespace('Inventory'):Get('ChestGiveItem'):CallServer(chest, v.tool)
                        refreshBank(chest)
                    end)
                end
            end
        end
    end

    AutoBank = vape.Categories.Inventory:CreateModule({
        Name = 'Auto Bank',
        Function = function(callback)
            if callback then
                Chests = collection('personal-chest', AutoBank)
                UI = Instance.new('Frame')
                UI.Size = UDim2.new(1, 0, 0, 32)
                UI.Position = UDim2.fromOffset(0, -240)
                UI.BackgroundTransparency = 1
                UI.Visible = UIToggle.Enabled
                UI.Parent = vape.gui
                AutoBank:Clean(UI)
                local Sort = Instance.new('UIListLayout')
                Sort.FillDirection = Enum.FillDirection.Horizontal
                Sort.HorizontalAlignment = Enum.HorizontalAlignment.Center
                Sort.SortOrder = Enum.SortOrder.LayoutOrder
                Sort.Parent = UI
                addItem('iron', true)
                addItem('gold', true)
                addItem('diamond', false)
                addItem('emerald', true)
                addItem('void_crystal', true)

                repeat
                    local hotbar = lplr.PlayerGui:FindFirstChild('hotbar')
                    hotbar = hotbar and hotbar['1']:FindFirstChild('HotbarHealthbarContainer')
                    if hotbar then
                        UI.Position = UDim2.fromOffset(0, (hotbar.AbsolutePosition.Y + guiService:GetGuiInset().Y) - 40)
                    end

                    local newState = nearChest()
                    if newState then
                        handleState()
                    end

                    task.wait(0.1)
                until (not AutoBank.Enabled)
            else
                table.clear(Items)
            end
        end,
        Tooltip = 'Automatically puts resources in ender chest'
    })
    UIToggle = AutoBank:CreateToggle({
        Name = 'UI',
        Function = function(callback)
            if AutoBank.Enabled then
                UI.Visible = callback
            end
        end,
        Default = true
    })
end)

run(function()
	local CatVapeAutoBank
	local CatVapeWhitelist
	local CatVapeGUICheck
	local CatVapeUIToggle
	local CatVapeUI
	local CatVapeReference, CatVapeBlacklist = {}, {}
	local CatVapeItems = {}

	local function cvGetShopNPC()
		local shop, items, upgrades, newid = nil, false, false, nil
		if entitylib.isAlive then
			local localPosition = entitylib.character.RootPart.Position
			for _, v in store.shop do
				if v.RootPart and v.RootPart.Parent and (v.RootPart.Position - localPosition).Magnitude <= 30 and not entitylib.EntityPosition({
					Origin = v.RootPart.Position,
					Range = 40,
					Part = 'RootPart',
					Players = true
				}) then
					shop = v.Upgrades or v.Shop or nil
					upgrades = upgrades or v.Upgrades
					items = items or v.Shop
					newid = v.Shop and v.Id or newid
				end
			end
		end
		return shop, items, upgrades, newid
	end

	local cvColors = {
		iron = Color3.fromRGB(200, 200, 200),
		diamond = Color3.fromRGB(100, 200, 255),
		emerald = Color3.fromRGB(100, 255, 100),
		gold = Color3.fromRGB(255, 215, 0)
	}

	local function cvDisplayName(itemType)
		return (itemType:sub(1, 1):upper() .. itemType:sub(2)):gsub('_', ' ')
	end

	local function cvAdded(itemType)
		local display = cvDisplayName(itemType)
		local label = Instance.new('TextLabel')
		label.Name = itemType
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, -16, 0, 18)
		label.LayoutOrder = #CatVapeUI:GetChildren()
		label.Text = display .. ': 0'
		label.TextColor3 = cvColors[itemType] or Color3.fromRGB(200, 200, 200)
		label.TextSize = 12
		label.Font = Enum.Font.Gotham
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = CatVapeUI

		CatVapeItems[itemType] = {Amount = 0, Object = label, Display = display}
	end

	local function cvRemoved(part)
		local index = table.find(CatVapeReference, part)
		if index then
			table.remove(CatVapeReference, index)
		end
	end

	CatVapeAutoBank = vape.Categories.Inventory:CreateModule({
		Name = 'AutoBank v2',
		Function = function(callback)
			if callback then
				-- Match AutoBank V3 UI style: bottom-left dark card, gold title, colored rows
				local itemCount = #CatVapeWhitelist.ListEnabled
				local cardH = 26 + (itemCount * 18) + 8

				CatVapeUI = Instance.new('Frame')
				CatVapeUI.Name = 'CatVapeBankUI'
				CatVapeUI.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
				CatVapeUI.BackgroundTransparency = 0.3
				CatVapeUI.BorderSizePixel = 0
				CatVapeUI.Position = UDim2.new(0, 8, 1, -100)
				CatVapeUI.Size = UDim2.new(0, 150, 0, cardH)
				CatVapeUI.AnchorPoint = Vector2.new(0, 1)
				CatVapeUI.Visible = CatVapeUIToggle.Enabled
				CatVapeUI.Parent = vape.gui
				CatVapeAutoBank:Clean(CatVapeUI)
				Instance.new('UICorner', CatVapeUI).CornerRadius = UDim.new(0, 8)

				-- Title
				local title = Instance.new('TextLabel')
				title.Parent = CatVapeUI
				title.BackgroundTransparency = 1
				title.Size = UDim2.new(1, 0, 0, 20)
				title.Position = UDim2.new(0, 0, 0, 4)
				title.Text = 'AutoBank v2'
				title.TextColor3 = Color3.fromRGB(255, 215, 0)
				title.TextSize = 13
				title.Font = Enum.Font.GothamBold

				-- Items list container
				local itemsRow = Instance.new('Frame')
				itemsRow.Name = 'Items'
				itemsRow.BackgroundTransparency = 1
				itemsRow.Position = UDim2.new(0, 8, 0, 26)
				itemsRow.Size = UDim2.new(1, -8, 1, -30)
				itemsRow.Parent = CatVapeUI
				local itemsLayout = Instance.new('UIListLayout', itemsRow)
				itemsLayout.FillDirection = Enum.FillDirection.Vertical
				itemsLayout.SortOrder = Enum.SortOrder.LayoutOrder
				itemsLayout.Padding = UDim.new(0, 0)

				-- Swap CatVapeUI to itemsRow for cvAdded
				local _oldUI = CatVapeUI
				CatVapeUI = itemsRow
				for _, v in CatVapeWhitelist.ListEnabled do
					cvAdded(v)
				end
				CatVapeUI = _oldUI

				local near = false
				local base = CFrame.new(1e3, 1e5, 1e3)
				local rows = Random.new():NextInteger(0, 20000)
				CatVapeAutoBank:Clean(runService.PreRender:Connect(function()
					local new = {}
					for i, v in CatVapeReference do
						if v and v.Parent and v.Parent == workspace.ItemDrops then
							new[v.Name] = (new[v.Name] or 0) + (v:GetAttribute('Amount') or 0)
							v.Velocity = Vector3.zero
							v.CFrame = near and entitylib.character.Head.CFrame or base + Vector3.new((i % rows) * 1200, 0, math.floor(i / rows) * 1200)
						elseif v and v.Parent then
							cvRemoved(v)
						end
					end
					for i, v in CatVapeItems do
						v.Amount = new[i] or 0
						v.Object.Text = v.Display .. ': ' .. tostring(v.Amount)
					end
				end))

				repeat
					-- Decide whether to retrieve loot back to the player.
					-- GUI Check ON  -> only retrieve while the chest GUI is open.
					-- GUI Check OFF -> retrieve whenever near a shop NPC (original behavior).
					local shouldRetrieve
					if CatVapeGUICheck.Enabled then
						shouldRetrieve = bedwars.AppController:isAppOpen('ChestApp')
					else
						shouldRetrieve = cvGetShopNPC() ~= nil
					end

					if entitylib.isAlive and not shouldRetrieve then
						near = false
						for _, v in store.inventory.inventory.items do
							local name = v.tool and v.tool.Name or nil
							if name and table.find(CatVapeWhitelist.ListEnabled, name) and (CatVapeBlacklist[name] or 0) < tick() then
								task.spawn(function()
									local part = bedwars.Client:Get(remotes.DropItem):CallServer({
										item = v.tool,
										amount = v.amount
									})
									if CatVapeAutoBank.Enabled and part and part.Parent and not table.find(CatVapeReference, part) then
										table.insert(CatVapeReference, part)
										-- Hide + fling to the sky IMMEDIATELY so it never renders at your head.
										-- ClearAllChildren removes the visual mesh; setting CFrame/velocity
										-- here (before the next PreRender) closes the one-frame flicker gap.
										part:ClearAllChildren()
										pcall(function()
											if part:IsA('BasePart') then
												part.Transparency = 1
												part.LocalTransparencyModifier = 1
											end
										end)
										local idx = #CatVapeReference
										part.Velocity = Vector3.zero
										part.CFrame = base + Vector3.new((idx % rows) * 1200, 0, math.floor(idx / rows) * 1200)
										part.AncestryChanged:Once(function()
											cvRemoved(part)
										end)
									elseif CatVapeAutoBank.Enabled then
										CatVapeBlacklist[name] = tick() + 5
									end
								end)
							end
						end
					elseif entitylib.isAlive then
						near = true
						for _, v in CatVapeReference do
							v.Velocity = Vector3.zero
							v.CFrame = entitylib.character.Head.CFrame
							task.spawn(function()
								bedwars.Client:Get(remotes.PickupItem):CallServerAsync({ itemDrop = v }):andThen(function(suc)
									if suc then cvRemoved(v) end
								end)
							end)
						end
					end
					task.wait(0.1)
				until not CatVapeAutoBank.Enabled
			else
				repeat
					for _, v in CatVapeReference do
						v.Velocity = Vector3.zero
						v.CFrame = entitylib.character.Head.CFrame
						task.spawn(function()
							bedwars.Client:Get(remotes.PickupItem):CallServerAsync({ itemDrop = v }):andThen(function(suc)
								if suc then cvRemoved(v) end
							end)
						end)
					end
					task.wait()
				until CatVapeAutoBank.Enabled
			end
		end,
		Tooltip = 'Drops whitelisted resources and floats them in the sky. With GUI Check on, retrieves them only when you open a chest.'
	})
	CatVapeWhitelist = CatVapeAutoBank:CreateTextList({
		Name = 'Whitelist',
		Default = {'emerald', 'diamond', 'iron'},
		Function = function()
			if CatVapeAutoBank.Enabled then
				CatVapeAutoBank:Toggle()
				CatVapeAutoBank:Toggle()
			end
		end
	})
	CatVapeGUICheck = CatVapeAutoBank:CreateToggle({
		Name = 'GUI Check',
		Default = true,
		Tooltip = 'Only teleport the loot back to you when you open a chest'
	})
	CatVapeUIToggle = CatVapeAutoBank:CreateToggle({Name = 'Display resources', Default = true})
end)


run(function()
    local AutoBuy
    local Sword
    local Armor
    local Upgrades
    local TierCheck
    local BedwarsCheck
    local GUI
    local SmartCheck
    local Custom = {}
    local CustomPost = {}
    local UpgradeToggles = {}
    local Functions, id = {}
    local Callbacks = {Custom, Functions, CustomPost}
    local npctick = tick()
    
    local swords = {
        'wood_sword',
        'stone_sword',
        'iron_sword',
        'diamond_sword',
        'emerald_sword'
    }
    
    local armors = {
        'none',
        'leather_chestplate',
        'iron_chestplate',
        'diamond_chestplate',
        'emerald_chestplate'
    }
    
    local axes = {
        'none',
        'wood_axe',
        'stone_axe',
        'iron_axe',
        'diamond_axe'
    }
    
    local pickaxes = {
        'none',
        'wood_pickaxe',
        'stone_pickaxe',
        'iron_pickaxe',
        'diamond_pickaxe'
    }
    
    local function getShopNPC()
        local shop, items, upgrades, newid = nil, false, false, nil
        if entitylib.isAlive then
            local localPosition = entitylib.character.RootPart.Position
            for _, v in store.shop or {} do
                if (v.RootPart.Position - localPosition).Magnitude <= 20 then
                    shop = v.Upgrades or v.Shop or nil
                    upgrades = upgrades or v.Upgrades
                    items = items or v.Shop
                    newid = v.Shop and v.Id or newid
                end
            end
        end
        return shop, items, upgrades, newid
    end
    
    local function canBuy(item, currencytable, amount)
        amount = amount or 1
        if not currencytable[item.currency] then
            local currency = getItem(item.currency)
            currencytable[item.currency] = currency and currency.amount or 0
        end
        if item.ignoredByKit and table.find(item.ignoredByKit, store.equippedKit or '') then return false end
        if item.lockedByForge or item.disabled then return false end
        if item.require and item.require.teamUpgrade then
            if (bedwars.Store:getState().Bedwars.teamUpgrades[item.require.teamUpgrade.upgradeId] or -1) < item.require.teamUpgrade.lowestTierIndex then
                return false
            end
        end
        return currencytable[item.currency] >= (item.price * amount)
    end
    
    local function buyItem(item, currencytable)
        if not id then return end
        notif('AutoBuy', 'Bought '..bedwars.ItemMeta[item.itemType].displayName, 3)
        bedwars.Client:Get('BedwarsPurchaseItem'):CallServerAsync({
            shopItem = item,
            shopId = id
        }):andThen(function(suc)
            if suc then
                bedwars.SoundManager:playSound(bedwars.SoundList.BEDWARS_PURCHASE_ITEM)
                bedwars.Store:dispatch({
                    type = 'BedwarsAddItemPurchased',
                    itemType = item.itemType
                })
                bedwars.BedwarsShopController.alreadyPurchasedMap[item.itemType] = true
            end
        end)
        currencytable[item.currency] = currencytable[item.currency] - item.price
    end
    
    local function buyUpgrade(upgradeType, currencytable)
        if not Upgrades.Enabled then return end
        local upgrade = bedwars.TeamUpgradeMeta[upgradeType]
        local currentUpgrades = bedwars.Store:getState().Bedwars.teamUpgrades[lplr:GetAttribute('Team')] or {}
        local currentTier = (currentUpgrades[upgradeType] or 0) + 1
        local bought = false
    
        for i = currentTier, #upgrade.tiers do
            local tier = upgrade.tiers[i]
            if tier.availableOnlyInQueue and not table.find(tier.availableOnlyInQueue, store.queueType) then continue end
    
            if canBuy({currency = 'diamond', price = tier.cost}, currencytable) then
                notif('AutoBuy', 'Bought '..(upgrade.name == 'Armor' and 'Protection' or upgrade.name)..' '..i, 3)
                bedwars.Client:Get('RequestPurchaseTeamUpgrade'):CallServerAsync(upgradeType)
                currencytable.diamond = currencytable.diamond - tier.cost
                bought = true
            else
                break
            end
        end
    
        return bought
    end
    
    local function buyTool(tool, tools, currencytable)
        local bought, buyable = false
        tool = tool and table.find(tools, tool.itemType) and table.find(tools, tool.itemType) + 1 or math.huge
    
        for i = tool, #tools do
            local v = bedwars.Shop.getShopItem(tools[i], lplr)
            if canBuy(v, currencytable) then
                if SmartCheck.Enabled and bedwars.ItemMeta[tools[i]].breakBlock and i > 2 then
                    if Armor.Enabled then
                        local currentarmor = store.inventory.inventory.armor[2]
                        currentarmor = currentarmor and currentarmor ~= 'empty' and currentarmor.itemType or 'none'
                        if (table.find(armors, currentarmor) or 3) < 3 then break end
                    end
                    if Sword.Enabled then
                        if store.tools.sword and (table.find(swords, store.tools.sword.itemType) or 2) < 2 then break end
                    end
                end
                bought = true
                buyable = v
            end
            if TierCheck.Enabled and v.nextTier then break end
        end
    
        if buyable then
            buyItem(buyable, currencytable)
        end
    
        return bought
    end
    
    AutoBuy = vape.Categories.Inventory:CreateModule({
        Name = 'Auto Buy',
        Function = function(callback)
            if callback then
                repeat task.wait() until store.queueType ~= 'bedwars_test'
                if BedwarsCheck.Enabled and not store.queueType:find('bedwars') then return end
    
                local lastupgrades
                AutoBuy:Clean(vapeEvents.InventoryAmountChanged.Event:Connect(function()
                    if (npctick - tick()) > 1 then npctick = tick() end
                end))
    
                repeat
                    local npc, shop, upgrades, newid = getShopNPC()
                    id = newid
                    if GUI.Enabled then
                        if not (bedwars.AppController:isAppOpen('BedwarsItemShopApp') or bedwars.AppController:isAppOpen('TeamUpgradeApp')) then
                            npc = nil
                        end
                    end
    
                    if npc and lastupgrades ~= upgrades then
                        if (npctick - tick()) > 1 then npctick = tick() end
                        lastupgrades = upgrades
                    end
    
                    if npc and npctick <= tick() and store.matchState ~= 2 and store.shopLoaded then
                        local currencytable = {}
                        local waitcheck
                        for _, tab in Callbacks do
                            for _, callback in tab do
                                if callback(currencytable, shop, upgrades) then
                                    waitcheck = true
                                end
                            end
                        end
                        npctick = tick() + (waitcheck and 0.4 or math.huge)
                    end
    
                    task.wait(0.1)
                until not AutoBuy.Enabled
            else
                npctick = tick()
            end
        end,
        Tooltip = 'Automatically buys items when you go near the shop'
    })
    Sword = AutoBuy:CreateToggle({
        Name = 'Buy Sword',
        Function = function(callback)
            npctick = tick()
            Functions[2] = callback and function(currencytable, shop)
                if not shop then return end
    
                if store.equippedKit == 'dasher' then
                    swords = {
                        [1] = 'wood_dao',
                        [2] = 'stone_dao',
                        [3] = 'iron_dao',
                        [4] = 'diamond_dao',
                        [5] = 'emerald_dao'
                    }
                elseif store.equippedKit == 'ice_queen' then
                    swords[5] = 'ice_sword'
                elseif store.equippedKit == 'ember' then
                    swords[5] = 'infernal_saber'
                elseif store.equippedKit == 'lumen' then
                    swords[5] = 'light_sword'
                end
    
                return buyTool(store.tools.sword, swords, currencytable)
            end or nil
        end
    })
    Armor = AutoBuy:CreateToggle({
        Name = 'Buy Armor',
        Function = function(callback)
            npctick = tick()
            Functions[1] = callback and function(currencytable, shop)
                if not shop then return end
                local currentarmor = store.inventory.inventory.armor[2] ~= 'empty' and store.inventory.inventory.armor[2] or getBestArmor(1)
                currentarmor = currentarmor and currentarmor.itemType or 'none'
                return buyTool({itemType = currentarmor}, armors, currencytable)
            end or nil
        end,
        Default = true
    })
    AutoBuy:CreateToggle({
        Name = 'Buy Axe',
        Function = function(callback)
            npctick = tick()
            Functions[3] = callback and function(currencytable, shop)
                if not shop then return end
                return buyTool(store.tools.wood or {itemType = 'none'}, axes, currencytable)
            end or nil
        end
    })
    AutoBuy:CreateToggle({
        Name = 'Buy Pickaxe',
        Function = function(callback)
            npctick = tick()
            Functions[4] = callback and function(currencytable, shop)
                if not shop then return end
                return buyTool(store.tools.stone, pickaxes, currencytable)
            end or nil
        end
    })
    Upgrades = AutoBuy:CreateToggle({
        Name = 'Buy Upgrades',
        Function = function(callback)
            for _, v in UpgradeToggles do
                v.Object.Visible = callback
            end
        end,
        Default = true
    })
    local count = 0
    for i, v in bedwars.TeamUpgradeMeta do
        local toggleCount = count
        table.insert(UpgradeToggles, AutoBuy:CreateToggle({
            Name = 'Buy '..(v.name == 'Armor' and 'Protection' or v.name),
            Function = function(callback)
                npctick = tick()
                Functions[5 + toggleCount + (v.name == 'Armor' and 20 or 0)] = callback and function(currencytable, shop, upgrades)
                    if not upgrades then return end
                    if v.disabledInQueue and table.find(v.disabledInQueue, store.queueType) then return end
                    return buyUpgrade(i, currencytable)
                end or nil
            end,
            Darker = true,
            Default = (i == 'ARMOR' or i == 'DAMAGE')
        }))
        count = count + 1
    end
    TierCheck = AutoBuy:CreateToggle({Name = 'Tier Check'})
    BedwarsCheck = AutoBuy:CreateToggle({
        Name = 'Only Bedwars',
        Function = function()
            if AutoBuy.Enabled then
                AutoBuy:Toggle()
                AutoBuy:Toggle()
            end
        end,
        Default = true
    })
    GUI = AutoBuy:CreateToggle({Name = 'GUI check'})
    SmartCheck = AutoBuy:CreateToggle({
        Name = 'Smart check',
        Default = true,
        Tooltip = 'Buys iron armor before iron axe'
    })
    AutoBuy:CreateTextList({
        Name = 'Item',
        Placeholder = 'priority/item/amount/after',
        Default = {'99/wool_white/64'},
        Function = function(list)
            table.clear(Custom)
            table.clear(CustomPost)
            for _, entry in list do
                local tab = entry:split('/')
                local ind = tonumber(tab[1])
                if ind then
                    (tab[4] and CustomPost or Custom)[ind] = function(currencytable, shop)
                        if not shop then return end
    
                        local v = bedwars.Shop.getShopItem(tab[2], lplr)
                        if v then
                            local item = getItem(tab[2] == 'wool_white' and bedwars.Shop.getTeamWool(lplr:GetAttribute('Team')) or tab[2])
                            item = math.floor((item and tonumber(tab[3]) - item.amount or tonumber(tab[3])) / v.amount)
                            if item > 0 and canBuy(v, currencytable, item) then
                                for _ = 1, item do
                                    buyItem(v, currencytable)
                                end
                                return true
                            end
                        end
                    end
                end
            end
        end
    })
end)

run(function()
    local AutoConsume
    local AutoPotion
    local Health
    local SpeedPotion
    local Apple
    local ShieldPotion
    local HealSplash
    local SerpentsTouch
    local JumpPotion
    local LegitSwitch

    local function getConsumeDuration(itemType)
        local meta = bedwars.ItemMeta[itemType]
        if meta and meta.consumable and meta.consumable.clickHoldSeconds then
            return meta.consumable.clickHoldSeconds
        end
        return 1
    end

    local consuming = false

    local consumeGui = Instance.new('ScreenGui')
    consumeGui.Name = 'AutoConsumeUI'
    consumeGui.Parent = vape.gui
    consumeGui.Enabled = false
    consumeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    consumeGui.DisplayOrder = 15
    consumeGui.ResetOnSpawn = false

    local consumeBar = Instance.new('Frame')
    consumeBar.Name = 'Bar'
    consumeBar.Parent = consumeGui
    consumeBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    consumeBar.BackgroundTransparency = 0.3
    consumeBar.BorderSizePixel = 0
    consumeBar.Size = UDim2.new(0, 140, 0, 20)
    consumeBar.Position = UDim2.new(0.5, 0, 0.75, 0)
    consumeBar.AnchorPoint = Vector2.new(0.5, 0.5)
    consumeBar.ClipsDescendants = true

    local consumeCorner = Instance.new('UICorner')
    consumeCorner.CornerRadius = UDim.new(0, 6)
    consumeCorner.Parent = consumeBar

    local consumeFill = Instance.new('Frame')
    consumeFill.Name = 'Fill'
    consumeFill.Parent = consumeBar
    consumeFill.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
    consumeFill.BorderSizePixel = 0
    consumeFill.Size = UDim2.new(0, 0, 1, 0)

    local consumeFillCorner = Instance.new('UICorner')
    consumeFillCorner.CornerRadius = UDim.new(0, 6)
    consumeFillCorner.Parent = consumeFill

    local consumeText = Instance.new('TextLabel')
    consumeText.Name = 'Text'
    consumeText.Parent = consumeBar
    consumeText.BackgroundTransparency = 1
    consumeText.Size = UDim2.new(1, 0, 1, 0)
    consumeText.TextColor3 = Color3.fromRGB(255, 255, 255)
    consumeText.TextSize = 12
    consumeText.Font = Enum.Font.GothamBold
    consumeText.TextStrokeTransparency = 0.5
    consumeText.TextStrokeColor3 = Color3.new(0, 0, 0)
    consumeText.Text = ''
    consumeText.TextTruncate = Enum.TextTruncate.AtEnd
    consumeText.ZIndex = 2

    -- The third-person body consume animation isn't referenced by name anywhere,
    -- so resolve its AnimationType from the enum at runtime (cached).
    local consumeAnimType
    local consumeAnimResolved = false
    local function resolveConsumeAnimType()
        consumeAnimResolved = true
        local at = bedwars.AnimationType
        if type(at) ~= 'table' then return end
        for _, name in {'USE_ITEM', 'CONSUME', 'DRINK', 'EAT', 'CONSUME_ITEM', 'USE_CONSUMABLE'} do
            if at[name] ~= nil then consumeAnimType = at[name] return end
        end
        for k, v in at do
            if type(k) == 'string' then
                local lk = k:lower()
                if (not lk:find('fp')) and (lk:find('consum') or lk:find('drink') or lk:find('eat') or (lk:find('use') and lk:find('item'))) then
                    consumeAnimType = v
                    return
                end
            end
        end
    end

    local function playConsumeAnimation()
        -- first-person viewmodel (only visible in first person)
        pcall(function()
            bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_USE_ITEM)
        end)
        -- third-person body animation so the drink is visible when not in first person
        pcall(function()
            if not consumeAnimResolved then resolveConsumeAnimType() end
            if consumeAnimType and lplr.Character then
                bedwars.GameAnimationUtil:playAnimation(lplr.Character, consumeAnimType)
            end
        end)
    end

    local function consumeItem(name, item, isEnabled)
        local duration = getConsumeDuration(item.itemType)
        local startTime = tick()
        local displayName = name:gsub('_', ' ')
        consumeFill.Size = UDim2.new(0, 0, 1, 0)
        consumeText.Text = displayName
        consumeGui.Enabled = true
        playConsumeAnimation()
        -- Mimic the real drinking slowdown: legit potions/food halve your speed
        -- while drinking. Restored the moment the consume finishes, cancels, or times out.
        local slowHum = lplr.Character and lplr.Character:FindFirstChildOfClass('Humanoid')
        local origWalkSpeed
        if slowHum then
            origWalkSpeed = slowHum.WalkSpeed
            slowHum.WalkSpeed = origWalkSpeed * 0.5
        end
        local done = false
        -- Keep the first-person drink/eat animation running for the whole hold
        -- so it looks like a genuine manual consume instead of a single flick.
        task.spawn(function()
            while not done do
                task.wait(0.8)
                if (not done) and store.hand.tool and store.hand.tool.Name == name then
                    playConsumeAnimation()
                end
            end
        end)
        task.spawn(function()
            while not done do
                local elapsed = tick() - startTime
                local progress = math.clamp(elapsed / duration, 0, 1)
                consumeFill.Size = UDim2.new(progress, 0, 1, 0)
                consumeText.Text = displayName .. ' ' .. string.format('%.1fs', math.max(0, duration - elapsed))
                task.wait()
            end
        end)
        -- Poll instead of a flat wait so the bar hides immediately if the drink
        -- is cancelled mid-hold (module disabled, player died, or item switched).
        while (tick() - startTime) < duration do
            if (isEnabled and not isEnabled()) or (not entitylib.isAlive) or (not store.hand.tool) or store.hand.tool.Name ~= name then
                break
            end
            task.wait()
        end
        done = true
        consumeGui.Enabled = false
        -- Restore movement speed the instant drinking ends/cancels
        if slowHum and slowHum.Parent and origWalkSpeed then
            slowHum.WalkSpeed = origWalkSpeed
        end
        consumeFill.Size = UDim2.new(0, 0, 1, 0)
        if entitylib.isAlive and store.hand.tool and store.hand.tool.Name == name then
            local currentItem = getItem(name)
            if currentItem then
                for _ = 1, 4 do
                    if bedwars.Client:Get(remotes.ConsumeItem):CallServer({item = currentItem.tool}) then break end
                end
            end
        end
        task.wait(0.5)
    end

    -- Auto Consume: food consumables (apple / golden apple / orange)
    local function foodCheck()
        if not entitylib.isAlive then return end
        local handTool = store.hand.tool
        if not handTool then return end
        local name = handTool.Name

        if Apple.Enabled and (name == 'apple' or name == 'golden_apple' or name == 'orange') then
            local apple = getItem('orange') or (not lplr.Character:GetAttribute('StatusEffect_golden_apple') and getItem('golden_apple')) or getItem('apple')
            if apple then
                consumeItem(name, apple, function() return AutoConsume.Enabled end)
            end
            return
        end
    end

    -- Auto Potion: drinkable potions (speed / shield / serpents touch / jump)
    local function potionCheck()
        if not entitylib.isAlive then return end
        local handTool = store.hand.tool
        if not handTool then return end
        local name = handTool.Name

        if SpeedPotion.Enabled and name == 'speed_potion' then
            local speedpotion = getItem('speed_potion')
            if speedpotion and (not lplr.Character:GetAttribute('StatusEffect_speed')) then
                consumeItem('speed_potion', speedpotion, function() return AutoPotion.Enabled end)
            end
            return
        end

        if ShieldPotion.Enabled and (name == 'big_shield' or name == 'mini_shield') then
            if (lplr.Character:GetAttribute('Shield_POTION') or 0) == 0 then
                local shield = getItem('big_shield') or getItem('mini_shield')
                if shield then
                    consumeItem(name, shield, function() return AutoPotion.Enabled end)
                end
            end
            return
        end

        if SerpentsTouch.Enabled and name == 'serpents_touch_potion' then
            local serpent = getItem('serpents_touch_potion')
            if serpent then
                consumeItem('serpents_touch_potion', serpent, function() return AutoPotion.Enabled end)
            end
            return
        end

        if JumpPotion.Enabled and name == 'jump_potion' then
            local jumppotion = getItem('jump_potion')
            if jumppotion then
                consumeItem('jump_potion', jumppotion, function() return AutoPotion.Enabled end)
            end
            return
        end
    end

    local function healSplashCheck()
        if not entitylib.isAlive then return end
        if not AutoPotion.Enabled then return end
        if not HealSplash.Enabled then return end
        if (lplr.Character:GetAttribute('Health') / lplr.Character:GetAttribute('MaxHealth')) > (Health.Value / 100) then return end
        local splash = getItem('heal_splash_potion')
        if not splash then return end
        local oldhotbar, oldtool = store.inventory.hotbarSlot, store.hand.tool
        local hotbar = getHotbar(splash.tool)
        local localPosition = entitylib.character.RootPart.Position
        local feetPos = localPosition - Vector3.new(0, 3, 0)
        local shootPosition = (CFrame.new(localPosition, feetPos) * CFrame.new(Vector3.new(-bedwars.BowConstantsTable.RelX, -bedwars.BowConstantsTable.RelY, -bedwars.BowConstantsTable.RelZ))).Position
        switchItem(splash.tool)
        if LegitSwitch.Enabled and hotbar then hotbarSwitch(hotbar) end
        bedwars.Client:Get(remotes.FireProjectile):CallServerAsync(
            splash.tool,
            'heal_splash_potion',
            'heal_splash_potion',
            shootPosition,
            localPosition,
            CFrame.new(localPosition, feetPos).LookVector * 50,
            httpService:GenerateGUID(true),
            {
                drawDurationSeconds = 1,
                shotId = httpService:GenerateGUID(false),
            },
            workspace:GetServerTimeNow() - 0.045
        )
        if oldtool then switchItem(oldtool) end
        if LegitSwitch.Enabled then hotbarSwitch(oldhotbar) end
    end

    AutoConsume = vape.Categories.Inventory:CreateModule({
        Name = 'Auto Consume',
        Function = function(callback)
            if not callback then return end
            task.spawn(function()
                while AutoConsume.Enabled do
                    if entitylib.isAlive and store.hand.tool and not consuming then
                        consuming = true
                        task.spawn(function()
                            foodCheck()
                            consuming = false
                        end)
                    end
                    task.wait(0.2)
                end
            end)
        end,
        Tooltip = 'Eats food (apple / golden apple / orange) when held in hand.'
    })
    Apple = AutoConsume:CreateToggle({
        Name = 'Apple',
        Default = true
    })

    AutoPotion = vape.Categories.Inventory:CreateModule({
        Name = 'Auto Potion',
        Function = function(callback)
            if not callback then return end
            AutoPotion:Clean(vapeEvents.AttributeChanged.Event:Connect(function(attribute)
                if attribute:find('Health') then
                    healSplashCheck()
                end
            end))
            task.spawn(function()
                while AutoPotion.Enabled do
                    if entitylib.isAlive and store.hand.tool and not consuming then
                        consuming = true
                        task.spawn(function()
                            potionCheck()
                            consuming = false
                        end)
                    end
                    task.wait(0.2)
                end
            end)
            healSplashCheck()
        end,
        Tooltip = 'Drinks potions when held in hand. Heal splash triggers on low health.'
    })
    Health = AutoPotion:CreateSlider({
        Name = 'Health Percent',
        Min = 1,
        Max = 99,
        Default = 70,
        Suffix = '%'
    })
    SpeedPotion = AutoPotion:CreateToggle({
        Name = 'Speed Potions',
        Default = true
    })
    HealSplash = AutoPotion:CreateToggle({
        Name = 'Heal Splash Potion',
        Default = true
    })
    SerpentsTouch = AutoPotion:CreateToggle({
        Name = 'Serpents Touch Potion',
        Default = true
    })
    JumpPotion = AutoPotion:CreateToggle({
        Name = 'Jump Potion',
        Default = true
    })
    LegitSwitch = AutoPotion:CreateToggle({
        Name = 'Legit Switch',
        Default = true,
        Tooltip = 'Visualizes the hotbar switching clientside for heal splash'
    })
    ShieldPotion = AutoPotion:CreateToggle({
        Name = 'Shield Potions',
        Default = true
    })
end)

run(function()
    local AutoFish
    local Show
    local Blacklist
    local Minigame
    local CompleteDelay
    local Cast
    local CastDelay
    
    local old
    local function getBait()
    	for _, v in workspace:GetChildren() do
    		if v.Name == 'fisherman_bobber' and v:GetAttribute('ProjectileShooter') == lplr.UserId then
    			return v
    		end
    	end
    
    	return
    end
    
    AutoFish = vape.Categories.Inventory:CreateModule({
    	Name = 'Auto Fish',
    	Function = function(call)
    		if call then
    			old = bedwars.FishingMinigameController.startMinigame
    			bedwars.FishingMinigameController.startMinigame = function(_, _, complete)
    				if Minigame.Enabled then
    					task.wait(CompleteDelay:GetRandomValue())
    					complete({win = true})
    				end
    			end
    
    			AutoFish:Clean(bedwars.Client:Get('FishFound'):Connect(function(data)
    				if data.dropData and data.dropData.drops then
    					for _, v in data.dropData.drops do
    						if Show.Enabled then
    							local itemDisplay = bedwars.ItemMeta[v.itemType] and bedwars.ItemMeta[v.itemType].displayName or v.itemType
    
    							notif('AutoFish', `You can get {v.amount} {itemDisplay:lower()}{v.amount >= 2 and 's' or ''} on ur next fish`, 20, 'info')
    						end
    
    						if entitylib.isAlive and table.find(Blacklist.ListEnabled, v.itemType) then
    							lplr.Character.Humanoid.Jump = true
    						end
    					end
    				end
    			end))
    
    			repeat
    				if
    					entitylib.isAlive
    					and Cast.Enabled
    					and (store.hand.tool and store.hand.tool.Name == 'fishing_rod')
    				then
    					local position = workspace.CurrentCamera.ViewportSize / 2
    					local ray = cloneref(lplr:GetMouse()).UnitRay
    
    					if
    						not getBait()
    						and not workspace:Raycast(entitylib.character.Head.Position + (ray.Direction * 6), Vector3.new(0, -20, 0))
    					then
    						task.wait(CastDelay:GetRandomValue())
    
    						for _, v in {true, false} do
    							virtualInputManager:SendMouseButtonEvent(position.X, position.Y, 0, v, game, 1)
    							task.wait()
    						end
    						task.wait(0.5)
    					end
    				end
    				task.wait(0.1)
    			until not AutoFish.Enabled
    		else
    			bedwars.FishingMinigameController.startMinigame = old
    			old = nil
    		end
    	end,
    	Tooltip = 'Automatically fishes with fishing rod'
    })
    
    Blacklist = AutoFish:CreateTextList({
    	Name = 'Blacklisted loot',
    	Tooltip = 'Automatically jumps if u found a fish with the blacklisted item',
    	Default = {'iron'},
    })
    Show = AutoFish:CreateToggle({
    	Name = 'Show loot drops',
    	Tooltip = 'Notifies ur next lootdrops',
    })
    Minigame = AutoFish:CreateToggle({
    	Name = 'Auto Minigame',
    	Tooltip = 'Automatically completes the minigame',
    	Default = true,
    	Function = function(call)
    		pcall(function()
    			CompleteDelay.Object.Visible = call
    		end)
    	end,
    })
    CompleteDelay = AutoFish:CreateTwoSlider({
    	Name = 'Complete delay',
    	Min = 0,
    	Max = 25,
    	Decimal = 5,
    	DefaultMin = 0.1,
    	DefaultMax = 0.9,
    	Darker = true,
    })
    Cast = AutoFish:CreateToggle({
    	Name = 'Auto Cast',
    	Tooltip = 'Automatically casts ur fishng rod',
    	Function = function(call)
    		pcall(function()
    			CastDelay.Object.Visible = call
    		end)
    	end,
    })
    CastDelay = AutoFish:CreateTwoSlider({
    	Name = 'Cast delay',
    	Min = 0,
    	Max = 5,
    	Decimal = 5,
    	DefaultMin = 0.3,
    	DefaultMax = 1.2,
    	Darker = true,
    	Visible = false,
    })
end)

run(function()
    local AutoHotbar
    local Mode
    local Clear
    local List
    local Active
    
    local function CreateWindow(self)
        local selectedslot = 1
        local window = Instance.new('Frame')
        window.Name = 'HotbarGUI'
        window.Size = UDim2.fromOffset(660, 465)
        window.Position = UDim2.fromScale(0.5, 0.5)
        window.BackgroundColor3 = uipallet.Main
        window.AnchorPoint = Vector2.new(0.5, 0.5)
        window.Visible = false
        window.Parent = vape.gui.ScaledGui
        local title = Instance.new('TextLabel')
        title.Name = 'Title'
        title.Size = UDim2.new(1, -10, 0, 20)
        title.Position = UDim2.fromOffset(math.abs(title.Size.X.Offset), 12)
        title.BackgroundTransparency = 1
        title.Text = 'AutoHotbar'
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextColor3 = uipallet.Text
        title.TextSize = 13
        title.FontFace = uipallet.Font
        title.Parent = window
        local divider = Instance.new('Frame')
        divider.Name = 'Divider'
        divider.Size = UDim2.new(1, 0, 0, 1)
        divider.Position = UDim2.fromOffset(0, 40)
        divider.BackgroundColor3 = color.Light(uipallet.Main, 0.04)
        divider.BorderSizePixel = 0
        divider.Parent = window
        addBlur(window)
        local modal = Instance.new('TextButton')
        modal.Text = ''
        modal.BackgroundTransparency = 1
        modal.Modal = true
        modal.Parent = window
        local corner = Instance.new('UICorner')
        corner.CornerRadius = UDim.new(0, 5)
        corner.Parent = window
        local close = Instance.new('ImageButton')
        close.Name = 'Close'
        close.Size = UDim2.fromOffset(24, 24)
        close.Position = UDim2.new(1, -35, 0, 9)
        close.BackgroundColor3 = Color3.new(1, 1, 1)
        close.BackgroundTransparency = 1
        close.Image = getcustomasset('levi_shakingrass/assets/new/close.png')
        close.ImageColor3 = color.Light(uipallet.Text, 0.2)
        close.ImageTransparency = 0.5
        close.AutoButtonColor = false
        close.Parent = window
        close.MouseEnter:Connect(function()
            close.ImageTransparency = 0.3
            tween:Tween(close, TweenInfo.new(0.2), {
                BackgroundTransparency = 0.6
            })
        end)
        close.MouseLeave:Connect(function()
            close.ImageTransparency = 0.5
            tween:Tween(close, TweenInfo.new(0.2), {
                BackgroundTransparency = 1
            })
        end)
        close.MouseButton1Click:Connect(function()
            window.Visible = false
            vape.gui.ScaledGui.ClickGui.Visible = true
        end)
        local closecorner = Instance.new('UICorner')
        closecorner.CornerRadius = UDim.new(1, 0)
        closecorner.Parent = close
        local bigslot = Instance.new('Frame')
        bigslot.Size = UDim2.fromOffset(110, 111)
        bigslot.Position = UDim2.fromOffset(11, 71)
        bigslot.BackgroundColor3 = color.Dark(uipallet.Main, 0.02)
        bigslot.Parent = window
        local bigslotcorner = Instance.new('UICorner')
        bigslotcorner.CornerRadius = UDim.new(0, 4)
        bigslotcorner.Parent = bigslot
        local bigslotstroke = Instance.new('UIStroke')
        bigslotstroke.Color = color.Light(uipallet.Main, 0.034)
        bigslotstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        bigslotstroke.Parent = bigslot
        local slotnum = Instance.new('TextLabel')
        slotnum.Size = UDim2.fromOffset(80, 20)
        slotnum.Position = UDim2.fromOffset(25, 200)
        slotnum.BackgroundTransparency = 1
        slotnum.Text = 'SLOT 1'
        slotnum.TextColor3 = color.Dark(uipallet.Text, 0.1)
        slotnum.TextSize = 12
        slotnum.FontFace = uipallet.Font
        slotnum.Parent = window
        for i = 1, 9 do
            local slotbkg = Instance.new('TextButton')
            slotbkg.Name = 'Slot'..i
            slotbkg.Size = UDim2.fromOffset(51, 52)
            slotbkg.Position = UDim2.fromOffset(89 + (i * 55), 382)
            slotbkg.BackgroundColor3 = color.Dark(uipallet.Main, 0.02)
            slotbkg.Text = ''
            slotbkg.AutoButtonColor = false
            slotbkg.Parent = window
            local slotimage = Instance.new('ImageLabel')
            slotimage.Size = UDim2.fromOffset(32, 32)
            slotimage.Position = UDim2.new(0.5, -16, 0.5, -16)
            slotimage.BackgroundTransparency = 1
            slotimage.Image = ''
            slotimage.Parent = slotbkg
            local slotcorner = Instance.new('UICorner')
            slotcorner.CornerRadius = UDim.new(0, 4)
            slotcorner.Parent = slotbkg
            local slotstroke = Instance.new('UIStroke')
            slotstroke.Color = color.Light(uipallet.Main, 0.04)
            slotstroke.Thickness = 2
            slotstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            slotstroke.Enabled = i == selectedslot
            slotstroke.Parent = slotbkg
            slotbkg.MouseEnter:Connect(function()
                slotbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.034)
            end)
            slotbkg.MouseLeave:Connect(function()
                slotbkg.BackgroundColor3 = color.Dark(uipallet.Main, 0.02)
            end)
            slotbkg.MouseButton1Click:Connect(function()
                window['Slot'..selectedslot].UIStroke.Enabled = false
                selectedslot = i
                slotstroke.Enabled = true
                slotnum.Text = 'SLOT '..selectedslot
            end)
            slotbkg.MouseButton2Click:Connect(function()
                local obj = self.Hotbars[self.Selected]
                if obj then
                    window['Slot'..i].ImageLabel.Image = ''
                    obj.Hotbar[tostring(i)] = nil
                    obj.Object['Slot'..i].Image = '	'
                end
            end)
        end
        local searchbkg = Instance.new('Frame')
        searchbkg.Size = UDim2.fromOffset(496, 31)
        searchbkg.Position = UDim2.fromOffset(142, 80)
        searchbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.034)
        searchbkg.Parent = window
        local search = Instance.new('TextBox')
        search.Size = UDim2.new(1, -10, 0, 31)
        search.Position = UDim2.fromOffset(10, 0)
        search.BackgroundTransparency = 1
        search.Text = ''
        search.PlaceholderText = ''
        search.TextXAlignment = Enum.TextXAlignment.Left
        search.TextColor3 = uipallet.Text
        search.TextSize = 12
        search.FontFace = uipallet.Font
        search.ClearTextOnFocus = false
        search.Parent = searchbkg
        local searchcorner = Instance.new('UICorner')
        searchcorner.CornerRadius = UDim.new(0, 4)
        searchcorner.Parent = searchbkg
        local searchicon = Instance.new('ImageLabel')
        searchicon.Size = UDim2.fromOffset(14, 14)
        searchicon.Position = UDim2.new(1, -26, 0, 8)
        searchicon.BackgroundTransparency = 1
        searchicon.Image = getcustomasset('levi_shakingrass/assets/new/search.png')
        searchicon.ImageColor3 = color.Light(uipallet.Main, 0.37)
        searchicon.Parent = searchbkg
        local children = Instance.new('ScrollingFrame')
        children.Name = 'Children'
        children.Size = UDim2.fromOffset(500, 240)
        children.Position = UDim2.fromOffset(144, 122)
        children.BackgroundTransparency = 1
        children.BorderSizePixel = 0
        children.ScrollBarThickness = 2
        children.ScrollBarImageTransparency = 0.75
        children.CanvasSize = UDim2.new()
        children.Parent = window
        local windowlist = Instance.new('UIGridLayout')
        windowlist.SortOrder = Enum.SortOrder.LayoutOrder
        windowlist.FillDirectionMaxCells = 9
        windowlist.CellSize = UDim2.fromOffset(51, 52)
        windowlist.CellPadding = UDim2.fromOffset(4, 3)
        windowlist.Parent = children
        windowlist:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
            if vape.ThreadFix then
                setthreadidentity(8)
            end
            children.CanvasSize = UDim2.fromOffset(0, windowlist.AbsoluteContentSize.Y / vape.guiscale.Scale)
        end)
        table.insert(vape.Windows, window)
    
        local function createitem(id, image)
            local slotbkg = Instance.new('TextButton')
            slotbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.02)
            slotbkg.Text = ''
            slotbkg.AutoButtonColor = false
            slotbkg.Parent = children
            local slotimage = Instance.new('ImageLabel')
            slotimage.Size = UDim2.fromOffset(32, 32)
            slotimage.Position = UDim2.new(0.5, -16, 0.5, -16)
            slotimage.BackgroundTransparency = 1
            slotimage.Image = image
            slotimage.Parent = slotbkg
            local slotcorner = Instance.new('UICorner')
            slotcorner.CornerRadius = UDim.new(0, 4)
            slotcorner.Parent = slotbkg
            slotbkg.MouseEnter:Connect(function()
                slotbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.04)
            end)
            slotbkg.MouseLeave:Connect(function()
                slotbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.02)
            end)
            slotbkg.MouseButton1Click:Connect(function()
                local obj = self.Hotbars[self.Selected]
                if obj then
                    window['Slot'..selectedslot].ImageLabel.Image = image
                    obj.Hotbar[tostring(selectedslot)] = id
                    obj.Object['Slot'..selectedslot].Image = image
                end
            end)
        end
    
        local function indexSearch(text)
            for _, v in children:GetChildren() do
                if v:IsA('TextButton') then
                    v:ClearAllChildren()
                    v:Destroy()
                end
            end
    
            if text == '' then
                for _, v in {'diamond_sword', 'diamond_pickaxe', 'diamond_axe', 'shears', 'wood_bow', 'wool_white', 'fireball', 'apple', 'iron', 'gold', 'diamond', 'emerald'} do
                    createitem(v, bedwars.ItemMeta[v].image)
                end
                return
            end
    
            for i, v in bedwars.ItemMeta do
                if text:lower() == i:lower():sub(1, text:len()) then
                    if not v.image then continue end
                    createitem(i, v.image)
                end
            end
        end
    
        search:GetPropertyChangedSignal('Text'):Connect(function()
            indexSearch(search.Text)
        end)
        indexSearch('')
    
        return window
    end
    
    vape.Components.HotbarList = function(optionsettings, children, api)
        if vape.ThreadFix then
            setthreadidentity(8)
        end
        local optionapi = {
            Type = 'HotbarList',
            Hotbars = {},
            Selected = 1
        }
        local hotbarlist = Instance.new('TextButton')
        hotbarlist.Name = 'HotbarList'
        hotbarlist.Size = UDim2.fromOffset(220, 40)
        hotbarlist.BackgroundColor3 = optionsettings.Darker and (children.BackgroundColor3 == color.Dark(uipallet.Main, 0.02) and color.Dark(uipallet.Main, 0.04) or color.Dark(uipallet.Main, 0.02)) or children.BackgroundColor3
        hotbarlist.Text = ''
        hotbarlist.BorderSizePixel = 0
        hotbarlist.AutoButtonColor = false
        hotbarlist.Parent = children
        local textbkg = Instance.new('Frame')
        textbkg.Name = 'BKG'
        textbkg.Size = UDim2.new(1, -20, 0, 31)
        textbkg.Position = UDim2.fromOffset(10, 4)
        textbkg.BackgroundColor3 = color.Light(uipallet.Main, 0.034)
        textbkg.Parent = hotbarlist
        local textbkgcorner = Instance.new('UICorner')
        textbkgcorner.CornerRadius = UDim.new(0, 4)
        textbkgcorner.Parent = textbkg
        local textbutton = Instance.new('TextButton')
        textbutton.Name = 'HotbarList'
        textbutton.Size = UDim2.new(1, -2, 1, -2)
        textbutton.Position = UDim2.fromOffset(1, 1)
        textbutton.BackgroundColor3 = uipallet.Main
        textbutton.Text = ''
        textbutton.AutoButtonColor = false
        textbutton.Parent = textbkg
        textbutton.MouseEnter:Connect(function()
            tween:Tween(textbkg, TweenInfo.new(0.2), {
                BackgroundColor3 = color.Light(uipallet.Main, 0.14)
            })
        end)
        textbutton.MouseLeave:Connect(function()
            tween:Tween(textbkg, TweenInfo.new(0.2), {
                BackgroundColor3 = color.Light(uipallet.Main, 0.034)
            })
        end)
        local textbuttoncorner = Instance.new('UICorner')
        textbuttoncorner.CornerRadius = UDim.new(0, 4)
        textbuttoncorner.Parent = textbutton
        local textbuttonicon = Instance.new('ImageLabel')
        textbuttonicon.Size = UDim2.fromOffset(12, 12)
        textbuttonicon.Position = UDim2.fromScale(0.5, 0.5)
        textbuttonicon.AnchorPoint = Vector2.new(0.5, 0.5)
        textbuttonicon.BackgroundTransparency = 1
        textbuttonicon.Image = getcustomasset('levi_shakingrass/assets/new/add.png')
        textbuttonicon.ImageColor3 = Color3.fromHSV(0.46, 0.96, 0.52)
        textbuttonicon.Parent = textbutton
        local childrenlist = Instance.new('Frame')
        childrenlist.Size = UDim2.new(1, 0, 1, -40)
        childrenlist.Position = UDim2.fromOffset(0, 40)
        childrenlist.BackgroundTransparency = 1
        childrenlist.Parent = hotbarlist
        local windowlist = Instance.new('UIListLayout')
        windowlist.SortOrder = Enum.SortOrder.LayoutOrder
        windowlist.HorizontalAlignment = Enum.HorizontalAlignment.Center
        windowlist.Padding = UDim.new(0, 3)
        windowlist.Parent = childrenlist
        windowlist:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
            if vape.ThreadFix then
                setthreadidentity(8)
            end
            hotbarlist.Size = UDim2.fromOffset(220, math.min(43 + windowlist.AbsoluteContentSize.Y / vape.guiscale.Scale, 603))
        end)
        textbutton.MouseButton1Click:Connect(function()
            optionapi:AddHotbar()
        end)
        optionapi.Window = CreateWindow(optionapi)
    
        function optionapi:Save(savetab)
            local hotbars = {}
            for _, v in self.Hotbars do
                table.insert(hotbars, v.Hotbar)
            end
            savetab.HotbarList = {
                Selected = self.Selected,
                Hotbars = hotbars
            }
        end
    
        function optionapi:Load(savetab)
            for _, v in self.Hotbars do
                v.Object:ClearAllChildren()
                v.Object:Destroy()
                table.clear(v.Hotbar)
            end
            table.clear(self.Hotbars)
            for _, v in savetab.Hotbars do
                self:AddHotbar(v)
            end
            self.Selected = savetab.Selected or 1
        end
    
        function optionapi:AddHotbar(data)
            local hotbardata = {Hotbar = data or {}}
            table.insert(self.Hotbars, hotbardata)
            local hotbar = Instance.new('TextButton')
            hotbar.Size = UDim2.fromOffset(200, 27)
            hotbar.BackgroundColor3 = table.find(self.Hotbars, hotbardata) == self.Selected and color.Light(uipallet.Main, 0.034) or uipallet.Main
            hotbar.Text = ''
            hotbar.AutoButtonColor = false
            hotbar.Parent = childrenlist
            hotbardata.Object = hotbar
            local hotbarcorner = Instance.new('UICorner')
            hotbarcorner.CornerRadius = UDim.new(0, 4)
            hotbarcorner.Parent = hotbar
            for i = 1, 9 do
                local slot = Instance.new('ImageLabel')
                slot.Name = 'Slot'..i
                slot.Size = UDim2.fromOffset(17, 18)
                slot.Position = UDim2.fromOffset(-7 + (i * 18), 5)
                slot.BackgroundColor3 = color.Dark(uipallet.Main, 0.02)
                slot.Image = hotbardata.Hotbar[tostring(i)] and bedwars.getIcon({itemType = hotbardata.Hotbar[tostring(i)]}, true) or ''
                slot.BorderSizePixel = 0
                slot.Parent = hotbar
            end
            hotbar.MouseButton1Click:Connect(function()
                local ind = table.find(optionapi.Hotbars, hotbardata)
                if ind == optionapi.Selected then
                    vape.gui.ScaledGui.ClickGui.Visible = false
                    optionapi.Window.Visible = true
                    for i = 1, 9 do
                        optionapi.Window['Slot'..i].ImageLabel.Image = hotbardata.Hotbar[tostring(i)] and bedwars.getIcon({itemType = hotbardata.Hotbar[tostring(i)]}, true) or ''
                    end
                else
                    if optionapi.Hotbars[optionapi.Selected] then
                        optionapi.Hotbars[optionapi.Selected].Object.BackgroundColor3 = uipallet.Main
                    end
                    hotbar.BackgroundColor3 = color.Light(uipallet.Main, 0.034)
                    optionapi.Selected = ind
                end
            end)
            local close = Instance.new('ImageButton')
            close.Name = 'Close'
            close.Size = UDim2.fromOffset(16, 16)
            close.Position = UDim2.new(1, -23, 0, 6)
            close.BackgroundColor3 = Color3.new(1, 1, 1)
            close.BackgroundTransparency = 1
            close.Image = getcustomasset('levi_shakingrass/assets/new/closemini.png')
            close.ImageColor3 = color.Light(uipallet.Text, 0.2)
            close.ImageTransparency = 0.5
            close.AutoButtonColor = false
            close.Parent = hotbar
            local closecorner = Instance.new('UICorner')
            closecorner.CornerRadius = UDim.new(1, 0)
            closecorner.Parent = close
            close.MouseEnter:Connect(function()
                close.ImageTransparency = 0.3
                tween:Tween(close, TweenInfo.new(0.2), {
                    BackgroundTransparency = 0.6
                })
            end)
            close.MouseLeave:Connect(function()
                close.ImageTransparency = 0.5
                tween:Tween(close, TweenInfo.new(0.2), {
                    BackgroundTransparency = 1
                })
            end)
            close.MouseButton1Click:Connect(function()
                local ind = table.find(self.Hotbars, hotbardata)
                local obj = self.Hotbars[self.Selected]
                local obj2 = self.Hotbars[ind]
                if obj and obj2 then
                    obj2.Object:ClearAllChildren()
                    obj2.Object:Destroy()
                    table.remove(self.Hotbars, ind)
                    ind = table.find(self.Hotbars, obj)
                    self.Selected = table.find(self.Hotbars, obj) or 1
                end
            end)
        end
    
        api.Options.HotbarList = optionapi
    
        return optionapi
    end
    
    local function getBlock()
        local clone = table.clone(store.inventory.inventory.items)
        table.sort(clone, function(a, b)
            return a.amount < b.amount
        end)
    
        for _, item in clone do
            local block = bedwars.ItemMeta[item.itemType].block
            if block and not block.seeThrough then
                return item
            end
        end
    end
    
    local function getCustomItem(v)
        if v == 'diamond_sword' then
            local sword = store.tools.sword
            v = sword and sword.itemType or 'wood_sword'
        elseif v == 'diamond_pickaxe' then
            local pickaxe = store.tools.stone
            v = pickaxe and pickaxe.itemType or 'wood_pickaxe'
        elseif v == 'diamond_axe' then
            local axe = store.tools.wood
            v = axe and axe.itemType or 'wood_axe'
        elseif v == 'wood_bow' then
            local bow = getBow()
            v = bow and bow.itemType or 'wood_bow'
        elseif v == 'wool_white' then
            local block = getBlock()
            v = block and block.itemType or 'wool_white'
        end
    
        return v
    end
    
    local function findItemInTable(tab, item)
        for slot, v in tab do
            if item.itemType == getCustomItem(v) then
                return tonumber(slot)
            end
        end
    end
    
    local function findInHotbar(item)
        for i, v in store.inventory.hotbar do
            if v.item and v.item.itemType == item.itemType then
                return i - 1, v.item
            end
        end
    end
    
    local function findInInventory(item)
        for _, v in store.inventory.inventory.items do
            if v.itemType == item.itemType then
                return v
            end
        end
    end
    
    local function dispatch(...)
        bedwars.Store:dispatch(...)
        vapeEvents.InventoryChanged.Event:Wait()
    end
    
    local function sortCallback()
        if Active then return end
        Active = true
        local items = (List.Hotbars[List.Selected] and List.Hotbars[List.Selected].Hotbar or {})
    
        for _, v in store.inventory.inventory.items do
            local slot = findItemInTable(items, v)
            if slot then
                local olditem = store.inventory.hotbar[slot]
                if olditem.item and olditem.item.itemType == v.itemType then continue end
                if olditem.item then
                    dispatch({
                        type = 'InventoryRemoveFromHotbar',
                        slot = slot - 1
                    })
                end
    
                local newslot = findInHotbar(v)
                if newslot then
                    dispatch({
                        type = 'InventoryRemoveFromHotbar',
                        slot = newslot
                    })
                    if olditem.item then
                        dispatch({
                            type = 'InventoryAddToHotbar',
                            item = findInInventory(olditem.item),
                            slot = newslot
                        })
                    end
                end
    
                dispatch({
                    type = 'InventoryAddToHotbar',
                    item = findInInventory(v),
                    slot = slot - 1
                })
            elseif Clear.Enabled then
                local newslot = findInHotbar(v)
                if newslot then
                    dispatch({
                        type = 'InventoryRemoveFromHotbar',
                        slot = newslot
                    })
                end
            end
        end
    
        Active = false
    end
    
    AutoHotbar = vape.Categories.Inventory:CreateModule({
        Name = 'Auto Hotbar',
        Function = function(callback)
            if callback then
                task.spawn(sortCallback)
                if Mode.Value == 'On Key' then
                    AutoHotbar:Toggle()
                    return
                end
    
                AutoHotbar:Clean(vapeEvents.InventoryAmountChanged.Event:Connect(sortCallback))
            end
        end,
        Tooltip = 'Automatically arranges hotbar to your liking.'
    })
    Mode = AutoHotbar:CreateDropdown({
        Name = 'Activation',
        List = {'Toggle', 'On Key'},
        Function = function()
            if AutoHotbar.Enabled then
                AutoHotbar:Toggle()
                AutoHotbar:Toggle()
            end
        end
    })
    Clear = AutoHotbar:CreateToggle({Name = 'Clear Hotbar'})
    List = AutoHotbar:CreateHotbarList({})
end)

run(function()
	local AutoSteal
	local Range
	local Delay
	local GUI
	local Stash = {}
	
	local function getInventoryRemote(name)
		return bedwars.Client:GetNamespace('Inventory'):Get(name)
	end
	
	local function stealCrate(crate)
		local value = crate:FindFirstChild('ChestFolderValue')
		local folder = value and value.Value or nil
		if not folder then return end
	
		local items = {}
		for _, v in folder:GetChildren() do
			if v:IsA('Accessory') then
				table.insert(items, v)
			end
		end
		if #items == 0 then return end
	
		getInventoryRemote('SetObservedChest'):SendToServer(folder)
	
		for _, v in items do
			local itemType = v.Name
			task.spawn(function()
				local suc, res = pcall(function()
					return getInventoryRemote('ChestGetItem'):CallServer(folder, v)
				end)
	
				if suc and res then
					table.insert(Stash, {Type = itemType, Expire = tick() + 5})
				end
			end)
		end
	
		getInventoryRemote('SetObservedChest'):SendToServer(nil)
	end
	
	local function depositStash()
		local inventory = replicatedStorage:FindFirstChild('Inventories')
		inventory = inventory and inventory:FindFirstChild(`{lplr.Name}_personal`) or nil
		if not inventory then return end
	
		local pending = table.clone(Stash)
		table.clear(Stash)
	
		for _, v in pending do
			local item = getItem(v.Type)
			if item then
				task.spawn(function()
					local suc, res = pcall(function()
						return getInventoryRemote('ChestGiveItem'):CallServer(inventory, item.tool)
					end)
	
					if not (suc and res) and tick() < v.Expire then
						table.insert(Stash, v)
					end
				end)
			elseif tick() < v.Expire then
				table.insert(Stash, v)
			end
		end
	end
	
	AutoSteal = vape.Categories.Inventory:CreateModule({
		Name = 'AutoSteal',
		Function = function(callback)
			if callback then
				repeat task.wait() until store.matchState ~= 0 or (not AutoSteal.Enabled)
				if not AutoSteal.Enabled then return end
	
				local crates = collection('team-crate', AutoSteal)
				local chests = collection('personal-chest', AutoSteal)
				local nextSteal = 0
	
				repeat
					if entitylib.isAlive and tick() > nextSteal and (not GUI.Enabled or bedwars.AppController:isAppOpen('ChestApp')) then
						nextSteal = tick() + Delay.Value
						local localPosition = entitylib.character.RootPart.Position
						local team = lplr:GetAttribute('Team')
	
						for _, v in crates do
							if v:GetAttribute('Team') ~= team and (localPosition - v.Position).Magnitude <= Range.Value then
								stealCrate(v)
							end
						end
	
						if #Stash > 0 then
							for _, v in chests do
								if (localPosition - v.Position).Magnitude <= Range.Value then
									depositStash()
									break
								end
							end
						end
					end
					task.wait(0.1)
				until not AutoSteal.Enabled
			end
	
			table.clear(Stash)
		end,
		Tooltip = 'Automatically steals loot from the enemy team\'s crate and banks it in your personal chest'
	})
	Range = AutoSteal:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 18,
		Default = 18,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	Delay = AutoSteal:CreateSlider({
		Name = 'Delay',
		Min = 0,
		Max = 1,
		Decimal = 100,
		Suffix = 'seconds',
		Default = 0
	})
	GUI = AutoSteal:CreateToggle({Name = 'GUI Check'})
end)


run(function()
    local Value
    local oldclickhold, oldshowprogress
    
    local FastConsume = vape.Categories.Inventory:CreateModule({
        Name = 'Fast Consume',
        Function = function(callback)
            if callback then
                oldclickhold = bedwars.ClickHold.startClick
                oldshowprogress = bedwars.ClickHold.showProgress
                bedwars.ClickHold.startClick = function(self)
                    self.startedClickTime = tick()
                    local handle = self:showProgress()
                    local clicktime = self.startedClickTime
                    bedwars.RuntimeLib.Promise.defer(function()
                        task.wait(self.durationSeconds * (Value.Value / 40))
                        if handle == self.handle and clicktime == self.startedClickTime and self.closeOnComplete then
                            self:hideProgress()
                            if self.onComplete then self.onComplete() end
                            if self.onPartialComplete then self.onPartialComplete(1) end
                            self.startedClickTime = -1
                        end
                    end)
                end
    
                bedwars.ClickHold.showProgress = function(self)
                    local roact = debug.getupvalue(oldshowprogress, 1)
                    local countdown = roact.mount(roact.createElement('ScreenGui', {}, { roact.createElement('Frame', {
                        [roact.Ref] = self.wrapperRef,
                        Size = UDim2.new(),
                        Position = UDim2.fromScale(0.5, 0.55),
                        AnchorPoint = Vector2.new(0.5, 0),
                        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
                        BackgroundTransparency = 0.8
                    }, { roact.createElement('Frame', {
                        [roact.Ref] = self.progressRef,
                        Size = UDim2.fromScale(0, 1),
                        BackgroundColor3 = Color3.new(1, 1, 1),
                        BackgroundTransparency = 0.5
                    }) }) }), lplr:FindFirstChild('PlayerGui'))
    
                    self.handle = countdown
                    local sizetween = tweenService:Create(self.wrapperRef:getValue(), TweenInfo.new(0.1), {
                        Size = UDim2.fromScale(0.11, 0.005)
                    })
                    local countdowntween = tweenService:Create(self.progressRef:getValue(), TweenInfo.new(self.durationSeconds * (Value.Value / 100), Enum.EasingStyle.Linear), {
                        Size = UDim2.fromScale(1, 1)
                    })
    
                    sizetween:Play()
                    countdowntween:Play()
                    table.insert(self.tweens, countdowntween)
                    table.insert(self.tweens, sizetween)
                    
                    return countdown
                end
            else
                bedwars.ClickHold.startClick = oldclickhold
                bedwars.ClickHold.showProgress = oldshowprogress
                oldclickhold = nil
                oldshowprogress = nil
            end
        end,
        Tooltip = 'Use/Consume items quicker.'
    })
    Value = FastConsume:CreateSlider({
        Name = 'Multiplier',
        Min = 0,
        Max = 100
    })
end)

run(function()
    local FastDrop
    
    FastDrop = vape.Categories.Inventory:CreateModule({
        Name = 'Fast Drop',
        Function = function(callback)
            if callback then
                repeat
                    if entitylib.isAlive and (not store.inventory.opened) and (inputService:IsKeyDown(Enum.KeyCode.H) or inputService:IsKeyDown(Enum.KeyCode.Backspace)) and inputService:GetFocusedTextBox() == nil then
                        task.spawn(bedwars.ItemDropController.dropItemInHand)
                        task.wait()
                    else
                        task.wait(0.1)
                    end
                until not FastDrop.Enabled
            end
        end,
        Tooltip = 'Drops items fast when you hold Q'
    })
end)

--[[
    Minigames
]]

run(function()
    local AutoHonor
    local Delay
    
    local Honored = {}
    local function honor()
        if #Honored > 1 then return end
        local list, team = table.clone(entitylib.List), lplr:GetAttribute('Team')
        table.sort(list, function(a, b)
            return a.Player:GetAttribute('Team') == team and b.Player:GetAttribute('Team') ~= team
        end)
        for _, v in list do
            if #Honored > 1 then break end
            if not table.find(Honored, v.Player) then
                bedwars.HonorController:honorPlayer(v.Player.UserId)
                table.insert(Honored, v.Player)
                task.wait(Delay.Value)
            end
        end
    end
    
    AutoHonor = vape.Categories.Minigames:CreateModule({
        Name = 'Auto Honor',
        Function = function(callback)
            if callback then
                AutoHonor:Clean(vapeEvents.EntityDeathEvent.Event:Connect(function(deathTable)
                    if deathTable.finalKill and deathTable.entityInstance == lplr.Character and #bedwars.Store:getState().Party.members <= 0 and store.matchState ~= 2 then
                        honor()
                    end
                end))
                AutoHonor:Clean(vapeEvents.MatchEndEvent.Event:Connect(honor))
            end
        end
    })
    
    Delay = AutoHonor:CreateSlider({
        Name = 'Delay',
        Min = 0,
        Max = 2,
        Decimal = 100,
        Suffix = 'seconds',
        Default = 0.1
    })
end)

run(function()
    local BedPlates
    local Background
    local Color
    local LayerCounter
    local LayerColor
    local Reference = {}
    local Folder = Instance.new('Folder')
    Folder.Parent = vape.gui
    
    local function getBlockLayerHealth(block)
    	local meta = bedwars.ItemMeta[block]
    	return meta and meta.block and meta.block.health or 0
    end
    
    local function getLayerColor()
    	return LayerColor and Color3.fromHSV(LayerColor.Hue, LayerColor.Sat, LayerColor.Value) or Color3.new(1, 1, 1)
    end
    
    local function scanSide(self, start, tab)
    	for _, side in sides do
    		local layers = {}
    		for i = 1, 15 do
    			local block = getPlacedBlock(start + (side * i))
    			if not block or block == self or block.Name == 'bed' then
    				break
    			end
    			if not block:GetAttribute('NoBreak') then
    				layers[block.Name] = (layers[block.Name] or 0) + 1
    			end
    		end
    
    		for block, amount in layers do
    			tab[block] = math.max(tab[block] or 0, amount)
    		end
    	end
    end
    
    local function refreshAdornee(v)
    	for _, obj in v.Frame:GetChildren() do
    		if obj:IsA('ImageLabel') and obj.Name ~= 'Blur' then
    			obj:Destroy()
    		end
    	end
    
    	local start = v.Adornee.Position
    	local layers = {}
    	local alreadygot = {}
    	scanSide(v.Adornee, start, layers)
    	scanSide(v.Adornee, start + Vector3.new(0, 0, 3), layers)
    	for block, amount in layers do
    		table.insert(alreadygot, {block, amount})
    	end
    	table.sort(alreadygot, function(a, b)
    		local healthA, healthB = getBlockLayerHealth(a[1]), getBlockLayerHealth(b[1])
    		return healthA == healthB and a[1] < b[1] or healthA > healthB
    	end)
    	v.Enabled = #alreadygot > 0
    
    	for _, blockData in alreadygot do
    		local block, amount = blockData[1], blockData[2]
    		local blockimage = Instance.new('ImageLabel')
    		blockimage.Size = UDim2.fromOffset(32, 32)
    		blockimage.BackgroundTransparency = 1
    		blockimage.Image = bedwars.getIcon({ itemType = block }, true)
    		blockimage.Parent = v.Frame
    		if amount > 1 and (not LayerCounter or LayerCounter.Enabled) then
    			local amounttext = Instance.new('TextLabel')
    			amounttext.Name = 'Amount'
    			amounttext.Size = UDim2.fromScale(1, 1)
    			amounttext.BackgroundTransparency = 1
    			amounttext.Text = tostring(amount)
    			amounttext.TextColor3 = getLayerColor()
    			amounttext.TextSize = 16
    			amounttext.TextStrokeTransparency = 0.3
    			amounttext.Font = Enum.Font.Arial
    			amounttext.Parent = blockimage
    		end
    	end
    end
    
    local function refreshAll()
    	for _, v in Reference do
    		refreshAdornee(v)
    	end
    end
    
    local function updateLayerTextColor()
    	local textColor = getLayerColor()
    	for _, v in Reference do
    		for _, obj in v.Frame:GetDescendants() do
    			if obj:IsA('TextLabel') and obj.Name == 'Amount' then
    				obj.TextColor3 = textColor
    			end
    		end
    	end
    end
    
    local function Added(v)
    	local billboard = Instance.new('BillboardGui')
    	billboard.Parent = Folder
    	billboard.Name = 'bed'
    	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
    	billboard.Size = UDim2.fromOffset(36, 36)
    	billboard.AlwaysOnTop = true
    	billboard.ClipsDescendants = false
    	billboard.Adornee = v
    	local blur = addBlur(billboard)
    	blur.Visible = Background.Enabled
    	local frame = Instance.new('Frame')
    	frame.Size = UDim2.fromScale(1, 1)
    	frame.BackgroundColor3 = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
    	frame.BackgroundTransparency = 1 - (Background.Enabled and Color.Opacity or 0)
    	frame.Parent = billboard
    	local layout = Instance.new('UIListLayout')
    	layout.FillDirection = Enum.FillDirection.Horizontal
    	layout.Padding = UDim.new(0, 4)
    	layout.VerticalAlignment = Enum.VerticalAlignment.Center
    	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    	layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
    		billboard.Size = UDim2.fromOffset(math.max(layout.AbsoluteContentSize.X + 4, 36), 36)
    	end)
    	layout.Parent = frame
    	local corner = Instance.new('UICorner')
    	corner.CornerRadius = UDim.new(0, 4)
    	corner.Parent = frame
    	Reference[v] = billboard
    	refreshAdornee(billboard)
    end
    
    local function refreshNear(data)
    	data = data.blockRef.blockPosition * 3
    	for i, v in Reference do
    		if (data - i.Position).Magnitude <= 30 then
    			refreshAdornee(v)
    		end
    	end
    end
    
    BedPlates = vape.Categories.Minigames:CreateModule({
    	Name = 'Bed Plates',
    	Function = function(callback)
    		if callback then
    			for _, v in collectionService:GetTagged('bed') do
    				task.spawn(Added, v)
    			end
    			BedPlates:Clean(vapeEvents.PlaceBlockEvent.Event:Connect(refreshNear))
    			BedPlates:Clean(vapeEvents.BreakBlockEvent.Event:Connect(refreshNear))
    			BedPlates:Clean(collectionService:GetInstanceAddedSignal('bed'):Connect(Added))
    			BedPlates:Clean(collectionService:GetInstanceRemovedSignal('bed'):Connect(function(v)
    				if Reference[v] then
    					Reference[v]:Destroy()
    					Reference[v]:ClearAllChildren()
    					Reference[v] = nil
    				end
    			end))
    		else
    			table.clear(Reference)
    			Folder:ClearAllChildren()
    		end
    	end,
    	Tooltip = 'Displays blocks over the bed',
    })
    Background = BedPlates:CreateToggle({
    	Name = 'Background',
    	Function = function(callback)
    		if Color and Color.Object then
    			Color.Object.Visible = callback
    		end
    		for _, v in Reference do
    			v.Frame.BackgroundTransparency = 1 - (callback and Color.Opacity or 0)
    			v.Blur.Visible = callback
    		end
    	end,
    	Default = true,
    })
    Color = BedPlates:CreateColorSlider({
    	Name = 'Background Color',
    	DefaultValue = 0,
    	DefaultOpacity = 0.5,
    	Function = function(hue, sat, val, opacity)
    		for _, v in Reference do
    			v.Frame.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
    			v.Frame.BackgroundTransparency = 1 - opacity
    		end
    	end,
    	Darker = true,
    })
    LayerCounter = BedPlates:CreateToggle({
    	Name = 'Layer Counter',
    	Function = function(callback)
    		if LayerColor and LayerColor.Object then
    			LayerColor.Object.Visible = callback
    		end
    		refreshAll()
    	end,
    	Default = true,
    })
    LayerColor = BedPlates:CreateColorSlider({
    	Name = 'Counter Text Color',
    	DefaultSat = 0,
    	DefaultValue = 1,
    	Function = function()
    		updateLayerTextColor()
    	end,
    	Visible = LayerCounter.Enabled,
    })
end)

run(function()
    local Breaker
    local Mode
    local Range
    local Angle
    local AutoTool
    local BreakSpeed
    local UpdateRate
    local Custom
    local Bed
    local Tesla
    local Hive
    local LuckyBlock
    local IronOre
    local Effect
    local CustomHealth = {}
    local Animation
    local SelfBreak
    local InstantBreak
    local LimitItem
    local TargetLock
    local targetGlow
    local customlist, parts = {}, {}
    
    local function customHealthbar(self, blockRef, health, maxHealth, changeHealth, block)
        --if block:GetAttribute('NoHealthbar') then return end
        if not self.healthbarPart or not self.healthbarBlockRef or self.healthbarBlockRef.blockPosition ~= blockRef.blockPosition then
            self.healthbarMaid:DoCleaning()
            self.healthbarBlockRef = blockRef
            local create = bedwars.Roact.createElement
            local percent = math.clamp(health / maxHealth, 0, 1)
            local cleanCheck = true
            local part = Instance.new('Part')
            part.Size = Vector3.one
            part.CFrame = CFrame.new(bedwars.BlockController:getWorldPosition(blockRef.blockPosition))
            part.Transparency = 1
            part.Anchored = true
            part.CanCollide = false
            part.Parent = workspace
            self.healthbarPart = part
            bedwars.QueryUtil:setQueryIgnored(self.healthbarPart, true)
    
            local mounted = bedwars.Roact.mount(create('BillboardGui', {
                Size = UDim2.fromOffset(249, 102),
                StudsOffset = Vector3.new(0, 2.5, 0),
                Adornee = part,
                MaxDistance = 40,
                AlwaysOnTop = true
            }, {
                create('Frame', {
                    Size = UDim2.fromOffset(160, 50),
                    Position = UDim2.fromOffset(44, 32),
                    BackgroundColor3 = Color3.new(),
                    BackgroundTransparency = 0.5
                }, {
                    create('UICorner', {CornerRadius = UDim.new(0, 5)}),
                    create('ImageLabel', {
                        Size = UDim2.new(1, 89, 1, 52),
                        Position = UDim2.fromOffset(-48, -31),
                        BackgroundTransparency = 1,
                        Image = getcustomasset('levi_shakingrass/assets/new/blur.png'),
                        ScaleType = Enum.ScaleType.Slice,
                        SliceCenter = Rect.new(52, 31, 261, 502)
                    }),
                    create('TextLabel', {
                        Size = UDim2.fromOffset(145, 14),
                        Position = UDim2.fromOffset(13, 12),
                        BackgroundTransparency = 1,
                        Text = bedwars.ItemMeta[block.Name].displayName or block.Name,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextYAlignment = Enum.TextYAlignment.Top,
                        TextColor3 = Color3.new(),
                        TextScaled = true,
                        Font = Enum.Font.Arial
                    }),
                    create('TextLabel', {
                        Size = UDim2.fromOffset(145, 14),
                        Position = UDim2.fromOffset(12, 11),
                        BackgroundTransparency = 1,
                        Text = bedwars.ItemMeta[block.Name].displayName or block.Name,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextYAlignment = Enum.TextYAlignment.Top,
                        TextColor3 = color.Dark(uipallet.Text, 0.16),
                        TextScaled = true,
                        Font = Enum.Font.Arial
                    }),
                    create('Frame', {
                        Size = UDim2.fromOffset(138, 4),
                        Position = UDim2.fromOffset(12, 32),
                        BackgroundColor3 = uipallet.Main
                    }, {
                        create('UICorner', {CornerRadius = UDim.new(1, 0)}),
                        create('Frame', {
                            [bedwars.Roact.Ref] = self.healthbarProgressRef,
                            Size = UDim2.fromScale(percent, 1),
                            BackgroundColor3 = Color3.fromHSV(math.clamp(percent / 2.5, 0, 1), 0.89, 0.75)
                        }, {create('UICorner', {CornerRadius = UDim.new(1, 0)})})
                    })
                })
            }), part)
    
            self.healthbarMaid:GiveTask(function()
                cleanCheck = false
                self.healthbarBlockRef = nil
                bedwars.Roact.unmount(mounted)
                if self.healthbarPart then
                    self.healthbarPart:Destroy()
                end
                self.healthbarPart = nil
            end)
    
            bedwars.RuntimeLib.Promise.delay(5):andThen(function()
                if cleanCheck then
                    self.healthbarMaid:DoCleaning()
                end
            end)
        end
    
        local newpercent = math.clamp((health - changeHealth) / maxHealth, 0, 1)
        tweenService:Create(self.healthbarProgressRef:getValue(), TweenInfo.new(0.3), {
            Size = UDim2.fromScale(newpercent, 1), BackgroundColor3 = Color3.fromHSV(math.clamp(newpercent / 2.5, 0, 1), 0.89, 0.75)
        }):Play()
    end

    local hit = 0

    local losFilter
    local function refreshFilter()
        if not losFilter then
            losFilter = RaycastParams.new()
            losFilter.FilterType = Enum.RaycastFilterType.Include
            losFilter.RespectCanCollide = false
        end
        local list = {}
        for _, b in store.blocks do
            if b and b.Parent then table.insert(list, b) end
        end
        losFilter.FilterDescendantsInstances = list
    end

    local function isVisible(worldPos)
        local eye = gameCamera.CFrame.Position
        for _, off in {
            Vector3.zero,
            Vector3.new(1.35, 0, 0), Vector3.new(-1.35, 0, 0),
            Vector3.new(0, 1.35, 0), Vector3.new(0, -1.35, 0),
            Vector3.new(0, 0, 1.35), Vector3.new(0, 0, -1.35)
        } do
            local probe = worldPos + off
            local ray = probe - eye
            local res = workspace:Raycast(eye, ray, losFilter)
            if not res then return true end
            if (res.Position - eye).Magnitude >= ray.Magnitude - 1.5 then return true end
            if res.Instance and (res.Instance.Position - worldPos).Magnitude < 2.5 then return true end
        end
        return false
    end

    local function isBedVisible(bed)
        local handler = bedwars.BlockController:getHandlerRegistry():getHandler(bed.Name)
        local positions = handler and handler:getContainedPositions(bed) or {bed.Position / 3}
        for _, gridPos in positions do
            if isVisible(gridPos * 3) then return true end
        end
        return false
    end

    -- The placed block standing between the camera and the bed. Breaking it opens the sightline.
    local function firstOccluder(bed)
        local eye = gameCamera.CFrame.Position
        local handler = bedwars.BlockController:getHandlerRegistry():getHandler(bed.Name)
        local positions = handler and handler:getContainedPositions(bed) or {bed.Position / 3}
        for _, gridPos in positions do
            local worldPos = gridPos * 3
            local res = workspace:Raycast(eye, worldPos - eye, losFilter)
            if res and res.Instance and res.Instance ~= bed then
                return res.Instance
            end
        end
        return nil
    end

    -- True only when the currently held tool can actually break this block (e.g. a pickaxe for iron ore).
    local function holdingToolFor(block)
        local meta = bedwars.ItemMeta[block.Name]
        local breaktype = meta and meta.block and meta.block.breakType
        local heldMeta = store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name]
        return breaktype and heldMeta and heldMeta.breakBlock and (heldMeta.breakBlock[breaktype] or 0) > 0
    end

    local function attemptBreak(tab, localPosition, visGate, heldOnly)
        if not tab then return end
        if visGate then refreshFilter() end
        for _, v in tab do
            if (v.Position - localPosition).Magnitude < Range.Value and bedwars.BlockController:isBlockBreakable({blockPosition = v.Position / 3}, lplr) then
                if not SelfBreak.Enabled and v:GetAttribute('PlacedByUserId') == lplr.UserId then continue end
                if (v:GetAttribute('BedShieldEndTime') or 0) > workspace:GetServerTimeNow() then continue end
                if LimitItem.Enabled and not (store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name].breakBlock) then continue end
                -- Iron ore: never force-swap to the pickaxe; only mine while it is already in hand.
                if heldOnly and not holdingToolFor(v) then continue end
    
                hit = hit + 1
                -- Bed target: only strike the bed itself once it is visible from the camera. While it is
                -- exposed but still hidden, break whatever block is blocking our line of sight so a hole we
                -- can actually see through keeps opening; only fall back to clearing defense if none is found.
                local breakTarget, useWall, protect = v, true, false
                if visGate and not isBedVisible(v) then
                    local occ = firstOccluder(v)
                    if occ then
                        breakTarget, useWall, protect = occ, false, false
                    else
                        protect = true
                    end
                end
                -- Target Lock: glow the block we're currently locked onto and breaking (ported from KingDraco).
                if targetGlow then targetGlow.Adornee = breakTarget end
                local target, path, endpos = bedwars.breakBlock(breakTarget, Effect.Enabled, Animation.Enabled, CustomHealth.Enabled and customHealthbar or nil, AutoTool.Enabled, breakmethods[Mode.Value], Angle.Value, useWall, protect, heldOnly)
                if path then
                    local currentnode = target
                    for _, part in parts do
                        part.Position = currentnode or Vector3.zero
                        if currentnode then
                            part.BoxHandleAdornment.Color3 = currentnode == endpos and Color3.new(1, 0.2, 0.2) or currentnode == target and Color3.new(0.2, 0.2, 1) or Color3.new(0.2, 1, 0.2)
                        end
                        currentnode = path[currentnode]
                    end
                end
    
                task.wait(InstantBreak.Enabled and (store.damageBlockFail > tick() and 4.5 or 0) or BreakSpeed.Value)
    
                return true
            end
        end
    
        return false
    end
    
    Breaker = vape.Categories.Minigames:CreateModule({
        Name = 'Breaker',
        Function = function(callback)
            if callback then
                for _ = 1, 30 do
                    local part = Instance.new('Part')
                    part.Anchored = true
                    part.CanQuery = false
                    part.CanCollide = false
                    part.Transparency = 1
                    part.Parent = gameCamera
                    local highlight = Instance.new('BoxHandleAdornment')
                    highlight.Size = Vector3.one
                    highlight.AlwaysOnTop = true
                    highlight.ZIndex = 1
                    highlight.Transparency = 0.5
                    highlight.Adornee = part
                    highlight.Parent = part
                    table.insert(parts, part)
                end

                -- Target Lock glow: locks a red highlight onto the block being broken (ported from KingDraco).
                targetGlow = Instance.new('Highlight')
                targetGlow.FillTransparency = 0.75
                targetGlow.OutlineTransparency = 0
                targetGlow.FillColor = Color3.fromRGB(255, 80, 80)
                targetGlow.OutlineColor = Color3.fromRGB(255, 200, 200)
                targetGlow.Enabled = TargetLock.Enabled
                targetGlow.Parent = gameCamera

                local beds = collection('bed', Breaker)
                local luckyblock = collection('LuckyBlock', Breaker)
                local ironores = collection('iron_ore_mesh_block', Breaker)
                local teslas = collection('tesla-trap', Breaker, function(tab, obj)
    				task.delay(0.1, function()
    					local player = playersService:GetPlayerByUserId(obj:GetAttribute('PlacedByUserId'))
    					if player and player:GetAttribute('Team') ~= lplr:GetAttribute('Team') then
    						table.insert(tab, obj)
    					end
    				end)
    			end)
    			local hives = collection('beehive', Breaker, function(tab, obj)
    				task.delay(0.1, function()
    					local player = playersService:GetPlayerByUserId(obj:GetAttribute('PlacedByUserId'))
    					if player and player:GetAttribute('Team') ~= lplr:GetAttribute('Team') then
    						table.insert(tab, obj)
    					end
    				end)
    			end)
                
                customlist = collection('block', Breaker, function(tab, obj)
                    if table.find(Custom.ListEnabled, obj.Name) then
                        table.insert(tab, obj)
                    end
                end)
    
                repeat
                    task.wait(1 / UpdateRate.Value)
                    if not Breaker.Enabled then break end
                    if entitylib.isAlive then
                        local localPosition = entitylib.character.RootPart.Position
    
                        if attemptBreak(Bed.Enabled and beds, localPosition, true) then continue end
                        if attemptBreak(Tesla.Enabled and teslas, localPosition) then continue end
                        if attemptBreak(Hive.Enabled and hives, localPosition) then continue end
                        if attemptBreak(customlist, localPosition) then continue end
                        if attemptBreak(LuckyBlock.Enabled and luckyblock, localPosition) then continue end
                        if IronOre.Enabled then
                            local myTeam = lplr:GetAttribute('Team')
                            local myBed
                            if myTeam then
                                for _, b in beds do
                                    if b and b.Parent and tonumber(b:GetAttribute('TeamId')) == tonumber(myTeam) then
                                        myBed = b
                                        break
                                    end
                                end
                            end
                            if myBed then
                                local baseOres = {}
                                for _, ore in ironores do
                                    if (ore.Position - myBed.Position).Magnitude <= 40 then
                                        table.insert(baseOres, ore)
                                    end
                                end
                                if attemptBreak(baseOres, localPosition, nil, true) then continue end
                            end
                        end
    
                        for _, v in parts do
                            v.Position = Vector3.zero
                        end
                        if targetGlow then targetGlow.Adornee = nil end
                    end
                until not Breaker.Enabled
            else
                for _, v in parts do
                    v:ClearAllChildren()
                    v:Destroy()
                end
                table.clear(parts)
                if targetGlow then targetGlow:Destroy() targetGlow = nil end
            end
        end,
        Tooltip = 'Break blocks around you automatically'
    })
    local methods = {}
    for i in breakmethods do
        table.insert(methods, i)
    end
    Mode = Breaker:CreateDropdown({
        Name = 'Break mode',
        List = methods,
        Default = methods[1]
    })
    Range = Breaker:CreateSlider({
        Name = 'Break range',
        Min = 1,
        Max = 30,
        Default = 30,
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    BreakSpeed = Breaker:CreateSlider({
        Name = 'Break speed',
        Min = 0,
        Max = 0.3,
        Default = 0.25,
        Decimal = 100,
        Suffix = 'seconds'
    })
    Angle = Breaker:CreateSlider({
        Name = 'Max angle',
        Min = 1,
        Max = 360,
        Default = 120
    })
    UpdateRate = Breaker:CreateSlider({
        Name = 'Update rate',
        Min = 1,
        Max = 120,
        Default = 60,
        Suffix = 'hz'
    })
    Custom = Breaker:CreateTextList({
        Name = 'Custom',
        Function = function()
            if not customlist then return end
            table.clear(customlist)
            for _, obj in store.blocks do
                if table.find(Custom.ListEnabled, obj.Name) then
                    table.insert(customlist, obj)
                end
            end
        end
    })
    Bed = Breaker:CreateToggle({
        Name = 'Break Bed',
        Default = true
    })
    Tesla = Breaker:CreateToggle({
    	Name = 'Break Tesla',
    	Default = true,
    })
    Hive = Breaker:CreateToggle({
    	Name = 'Break Hive',
    	Default = true,
    })
    LuckyBlock = Breaker:CreateToggle({
        Name = 'Break Lucky Block',
        Default = true
    })
    IronOre = Breaker:CreateToggle({
        Name = 'Break Iron Ore',
        Default = true
    })
    Effect = Breaker:CreateToggle({
        Name = 'Show Healthbar & Effects',
        Function = function(callback)
            if CustomHealth.Object then
                CustomHealth.Object.Visible = callback
            end
        end,
        Default = true
    })
    CustomHealth = Breaker:CreateToggle({
        Name = 'Custom Healthbar',
        Default = true,
        Darker = true
    })
    Animation = Breaker:CreateToggle({Name = 'Animation'})
    SelfBreak = Breaker:CreateToggle({Name = 'Self Break'})
    InstantBreak = Breaker:CreateToggle({Name = 'Instant Break'})
    AutoTool = Breaker:CreateToggle({Name = 'Auto Tool'})
    LimitItem = Breaker:CreateToggle({
        Name = 'Limit to items',
        Tooltip = 'Only breaks when tools are held'
    })
    TargetLock = Breaker:CreateToggle({
        Name = 'Target Lock',
        Tooltip = 'Glows the block you are currently locked onto and breaking (ported from KingDraco)',
        Default = true,
        Function = function(callback)
            if targetGlow then
                targetGlow.Enabled = callback
                if not callback then targetGlow.Adornee = nil end
            end
        end
    })
end)

run(function()
    local KingDraco
    local RangeSetting, SpeedSetting, TickRate, BreakMode
    local ToolSwitch, ItemLimit, BreakSelf, QuickBreak, BaseOre, BreakerFallback, DebugMode
    local EffectsOn, HealthDisplay, Anim, PathOverlay

    local hp = {gui = nil, fill = nil, block = nil, current = -1, max = -1}
    local targetGlow, bedGlow
    local pathParts = {}
    local losFilter
    local debugLog = {}
    local MAX_LOG = 200

    local function dbg(msg)
        warn(msg)
        table.insert(debugLog, os.clock() .. ' ' .. msg)
        if #debugLog > MAX_LOG then table.remove(debugLog, 1) end
    end

    local function refreshFilter()
        if not losFilter then
            losFilter = RaycastParams.new()
            losFilter.FilterType = Enum.RaycastFilterType.Include
            losFilter.RespectCanCollide = false
        end
        local list = {}
        for _, b in store.blocks do
            if b and b.Parent then table.insert(list, b) end
        end
        losFilter.FilterDescendantsInstances = list
    end

    local function isVisible(worldPos)
        local eye = gameCamera.CFrame.Position
        for _, off in {
            Vector3.zero,
            Vector3.new(1.35, 0, 0), Vector3.new(-1.35, 0, 0),
            Vector3.new(0, 1.35, 0), Vector3.new(0, -1.35, 0),
            Vector3.new(0, 0, 1.35), Vector3.new(0, 0, -1.35)
        } do
            local probe = worldPos + off
            local ray = probe - eye
            local hit = workspace:Raycast(eye, ray, losFilter)
            if not hit then return true end
            if (hit.Position - eye).Magnitude >= ray.Magnitude - 1.5 then return true end
            if hit.Instance and (hit.Instance.Position - worldPos).Magnitude < 2.5 then return true end
        end
        return false
    end

    local function isBedVisible(bed)
        local handler = bedwars.BlockController:getHandlerRegistry():getHandler(bed.Name)
        local positions = handler and handler:getContainedPositions(bed) or {bed.Position / 3}
        for _, gridPos in positions do
            if isVisible(gridPos * 3) then return true end
        end
        return false
    end

    local function eligible(block)
        if (block:GetAttribute('BedShieldEndTime') or 0) > workspace:GetServerTimeNow() then return false end
        if not BreakSelf.Enabled then
            local myTeam = lplr.Character and (lplr.Character:GetAttribute('Team') or lplr.Character:GetAttribute('TeamId'))
            if block.Name == 'bed' and myTeam and tonumber(block:GetAttribute('TeamId')) == tonumber(myTeam) then return false end
            local bTeam = block:GetAttribute('Team') or block:GetAttribute('TeamId')
            if bTeam and myTeam and tonumber(bTeam) == tonumber(myTeam) then return false end
            if block:GetAttribute('PlacedByUserId') == lplr.UserId then return false end
        end
        if ItemLimit.Enabled then
            local handMeta = store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name]
            if not (handMeta and handMeta.breakBlock) then return false end
        end
        return true
    end

    local function equipFor(block)
        if not ToolSwitch.Enabled then return end
        if (workspace:GetServerTimeNow() - bedwars.SwordController.lastAttack) <= 0.4 then return end
        local meta = bedwars.ItemMeta[block.Name]
        if not meta or not meta.block then return end
        local tool = store.tools[meta.block.breakType]
        if not tool then return end
        local slot = getHotbar(tool.tool)
        if slot and store.inventory.hotbarSlot ~= slot then
            bedwars.Store:dispatch({
                type = 'InventorySelectHotbarSlot',
                slot = slot
            })
        end
    end

    local function readHP(block, gridPos)
        local data = bedwars.BlockController:getStore():getBlockData(gridPos)
        return data and (data:GetAttribute('1') or data:GetAttribute('Health')) or block:GetAttribute('Health') or block:GetAttribute('MaxHealth') or 0
    end

    local function spawnBar(block)
        if hp.gui then hp.gui:Destroy() end

        local bb = Instance.new('BillboardGui')
        bb.Size = UDim2.fromOffset(120, 22)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true
        bb.MaxDistance = 40
        bb.Adornee = block

        local label = Instance.new('TextLabel')
        label.Size = UDim2.new(1, 0, 0, 13)
        label.BackgroundTransparency = 1
        label.Text = (bedwars.ItemMeta[block.Name] and bedwars.ItemMeta[block.Name].displayName) or block.Name
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.3
        label.TextStrokeColor3 = Color3.new()
        label.TextSize = 12
        label.Font = Enum.Font.GothamBold
        label.Parent = bb

        local track = Instance.new('Frame')
        track.Size = UDim2.new(1, 0, 0, 5)
        track.Position = UDim2.new(0, 0, 0, 15)
        track.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        track.BackgroundTransparency = 0.15
        track.BorderSizePixel = 0
        track.Parent = bb
        local tc = Instance.new('UICorner')
        tc.CornerRadius = UDim.new(1, 0)
        tc.Parent = track
        local ts = Instance.new('UIStroke')
        ts.Thickness = 1
        ts.Color = Color3.fromRGB(55, 55, 55)
        ts.Parent = track

        local fill = Instance.new('Frame')
        fill.Size = UDim2.fromScale(1, 1)
        fill.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
        fill.BorderSizePixel = 0
        fill.Parent = track
        local fc = Instance.new('UICorner')
        fc.CornerRadius = UDim.new(1, 0)
        fc.Parent = fill

        bb.Parent = gameCamera
        hp.gui = bb
        hp.fill = fill
        hp.block = block
        hp.current = -1
        hp.max = -1
    end

    local function tweenBar(pct)
        if not hp.fill or not hp.fill.Parent then return end
        local c = math.clamp(pct, 0, 1)
        tweenService:Create(hp.fill, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
            Size = UDim2.fromScale(c, 1),
            BackgroundColor3 = Color3.fromHSV(c / 3, 0.85, 0.9)
        }):Play()
    end

    local function killBar()
        if hp.gui then
            hp.gui:Destroy()
            hp.gui = nil
            hp.fill = nil
            hp.block = nil
            hp.current = -1
        end
    end

    local function strike(block)
        if lplr:GetAttribute('DenyBlockBreak') or not entitylib.isAlive or InfiniteFly.Enabled then return false end

        local gridPos = bedwars.BlockController:getBlockPosition(block.Position)
        equipFor(block)

        local curHP = readHP(block, gridPos)
        local maxHP = block:GetAttribute('MaxHealth') or curHP
        if HealthDisplay.Enabled and hp.block ~= block then
            spawnBar(block)
        end
        if hp.block == block and hp.current == -1 then
            hp.current = curHP
            hp.max = maxHP
        end

        local dir = entitylib.character.RootPart.Position - block.Position
        local ax, ay, az = math.abs(dir.X), math.abs(dir.Y), math.abs(dir.Z)
        local hitNormal
        if ay >= ax and ay >= az then
            hitNormal = Vector3.new(0, dir.Y > 0 and 1 or -1, 0)
        elseif ax >= az then
            hitNormal = Vector3.new(dir.X > 0 and 1 or -1, 0, 0)
        else
            hitNormal = Vector3.new(0, 0, dir.Z > 0 and 1 or -1)
        end

        bedwars.ClientDamageBlock:Get('DamageBlock'):CallServerAsync({
            blockRef = {blockPosition = gridPos},
            hitPosition = block.Position + hitNormal * 1.5,
            hitNormal = hitNormal
        }):andThen(function(result)
            if not result then return end
            if result == 'cancelled' then
                store.damageBlockFail = tick() + 0.3
                return
            end

            if EffectsOn.Enabled then
                local afterHP = readHP(block, gridPos)
                local dmg = hp.current - (result == 'destroyed' and 0 or afterHP)
                hp.current = math.max(hp.current - dmg, 0)

                if hp.max > 0 then
                    tweenBar(hp.current / hp.max)
                end

                if hp.current <= 0 then
                    pcall(function() bedwars.BlockBreaker.breakEffect:playBreak(block.Name, gridPos, lplr) end)
                    killBar()
                else
                    pcall(function() bedwars.BlockBreaker.breakEffect:playHit(block.Name, gridPos, lplr) end)
                end
            end

            if Anim.Enabled then
                task.spawn(function()
                    local a = bedwars.AnimationUtil:playAnimation(lplr, bedwars.BlockController:getAnimationController():getAssetId(1))
                    bedwars.ViewmodelController:playAnimation(15)
                    task.wait(0.3)
                    if a then a:Stop() a:Destroy() end
                end)
            end
        end)
        return true
    end

    local function planAttack(bed, origin)
        local handler = bedwars.BlockController:getHandlerRegistry():getHandler(bed.Name)
        local contained = handler and handler:getContainedPositions(bed) or {bed.Position / 3}
        local best = {entry = nil, cost = math.huge, route = nil, anchor = nil}
        local useDistance = BreakMode and BreakMode.Value == 'Distance'

        for _, cp in contained do
            local anchor = cp * 3
            local seen = {}
            local frontier = {{0, anchor}}
            local costs = {}
            costs[anchor] = 0
            local prev = {}

            for _ = 1, 5000 do
                local pick, pickI = nil, nil
                for i, f in frontier do
                    if not seen[f[2]] and (not pick or f[1] < pick[1]) then
                        pick, pickI = f, i
                    end
                end
                if not pick then break end
                seen[pick[2]] = true

                local exposed = false
                for _, dir in sides do
                    local nb
                    local h, nc
                    local np = pick[2] + dir
                    if seen[np] then continue end
                    nb = getPlacedBlock(np)
                    if not nb or nb:GetAttribute('NoBreak') or nb == bed then
                        if not nb then exposed = true end
                        continue
                    end
                    h = useDistance and (origin - Vector3.new(np.X, origin.Y, np.Z)).Magnitude or getBlockHits(nb, np)
                    nc = pick[1] + h
                    if nc < (costs[np] or math.huge) then
                        costs[np] = nc
                        prev[np] = pick[2]
                        table.insert(frontier, {nc, np})
                    end
                end

                if exposed and pick[2] ~= anchor and pick[1] < best.cost then
                    if isVisible(pick[2]) then
                        local route = {}
                        local cur = pick[2]
                        while cur and cur ~= anchor do
                            table.insert(route, cur)
                            cur = prev[cur]
                        end
                        best.entry = pick[2]
                        best.cost = pick[1]
                        best.route = route
                        best.anchor = anchor
                    end
                end
            end
        end

        return best.entry, best.route, best.anchor, best.cost
    end

    local function getRouteCost(positions, origin)
        local useDistance = BreakMode and BreakMode.Value == 'Distance'
        local total = 0
        for _, pos in positions do
            local block = getPlacedBlock(pos)
            if block and not block:GetAttribute('NoBreak') then
                if useDistance and origin then
                    total = total + (origin - Vector3.new(pos.X, origin.Y, pos.Z)).Magnitude
                else
                    total = total + getBlockHits(block, pos)
                end
            end
        end
        return total
    end

    local function drawPath(route, entry, anchor)
        local need = (route and #route or 0) + 2
        while #pathParts < need do
            local p = Instance.new('Part')
            p.Anchored = true
            p.CanQuery = false
            p.CanCollide = false
            p.Transparency = 1
            p.Size = Vector3.new(3, 3, 3)
            p.Parent = gameCamera
            local box = Instance.new('SelectionBox')
            box.Name = 'Box'
            box.LineThickness = 0.04
            box.SurfaceTransparency = 0.75
            box.Adornee = p
            box.Parent = p
            table.insert(pathParts, p)
        end

        local idx = 1
        if entry and idx <= #pathParts then
            pathParts[idx].Position = entry
            pathParts[idx].Box.Color3 = Color3.fromRGB(255, 50, 50)
            pathParts[idx].Box.SurfaceColor3 = Color3.fromRGB(255, 50, 50)
            idx = idx + 1
        end
        if route then
            for _, pos in route do
                if pos == entry then continue end
                if idx > #pathParts then break end
                pathParts[idx].Position = pos
                pathParts[idx].Box.Color3 = Color3.fromRGB(50, 255, 50)
                pathParts[idx].Box.SurfaceColor3 = Color3.fromRGB(50, 255, 50)
                idx = idx + 1
            end
        end
        if anchor and idx <= #pathParts then
            pathParts[idx].Position = anchor
            pathParts[idx].Box.Color3 = Color3.fromRGB(50, 80, 255)
            pathParts[idx].Box.SurfaceColor3 = Color3.fromRGB(50, 80, 255)
            idx = idx + 1
        end
        for i = idx, #pathParts do
            pathParts[i].Position = Vector3.new(0, -9999, 0)
        end
    end

    local function clearPath()
        for _, p in pathParts do
            p.Position = Vector3.new(0, -9999, 0)
        end
    end

    local f4Conn

    local function fullCleanup()
        store._lockedDefenseBlock = nil
        store._routePositions = nil
        store._routeAnchor = nil
        killBar()
        for _, p in pathParts do p:ClearAllChildren() p:Destroy() end
        table.clear(pathParts)
        if targetGlow then targetGlow:Destroy() targetGlow = nil end
        if bedGlow then bedGlow:Destroy() bedGlow = nil end
        if f4Conn then f4Conn:Disconnect() f4Conn = nil end
        table.clear(debugLog)
    end

    KingDraco = vape.Categories.Minigames:CreateModule({
        Name = 'KingDraco',
        Function = function(callback)
            if callback then
                targetGlow = Instance.new('Highlight')
                targetGlow.FillTransparency = 0.75
                targetGlow.OutlineTransparency = 0
                targetGlow.FillColor = Color3.fromRGB(255, 80, 80)
                targetGlow.OutlineColor = Color3.fromRGB(255, 200, 200)
                targetGlow.Parent = gameCamera

                bedGlow = Instance.new('Highlight')
                bedGlow.FillTransparency = 0.85
                bedGlow.OutlineTransparency = 0.3
                bedGlow.FillColor = Color3.fromRGB(80, 80, 255)
                bedGlow.OutlineColor = Color3.fromRGB(180, 180, 255)
                bedGlow.Parent = gameCamera

                f4Conn = inputService.InputBegan:Connect(function(input, gpe)
                    if gpe then return end
                    if input.KeyCode == Enum.KeyCode.F4 and DebugMode and DebugMode.Enabled then
                        local text = table.concat(debugLog, '\n')
                        if setclipboard then
                            setclipboard(text)
                            notif('KingDraco', 'Debug log copied (' .. #debugLog .. ' lines)', 3, 'info')
                        end
                    end
                end)

                local beds = collection('bed', KingDraco)
                local ironores = collection('iron_ore_mesh_block', KingDraco)

                local lastBedVis = false

                repeat
                    local origin, bestBed, bestDist, bedVis, freshEntry, freshRoute, freshAnchor, freshCost, useStored
                    if not KingDraco.Enabled then break end
                    if not entitylib.isAlive then
                        clearPath()
                        killBar()
                        targetGlow.Adornee = nil
                        bedGlow.Adornee = nil
                        store._routePositions = nil
                        store._routeAnchor = nil
                        store._lockedDefenseBlock = nil
                        task.wait(0.1)
                        continue
                    end

                    origin = entitylib.character.RootPart.Position
                    refreshFilter()

                    bestBed, bestDist = nil, math.huge
                    for _, b in beds do
                        local d
                        if not b or not b.Parent then continue end
                        if not eligible(b) then continue end
                        d = (b.Position - origin).Magnitude
                        if d < RangeSetting.Value and d < bestDist then
                            bestBed, bestDist = b, d
                        end
                    end

                    if not bestBed then
                        store._lockedDefenseBlock = nil
                        store._routePositions = nil
                        store._routeAnchor = nil
                        clearPath()
                        killBar()
                        bedGlow.Adornee = nil
                        if BaseOre and BaseOre.Enabled and store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name] and bedwars.ItemMeta[store.hand.tool.Name].breakBlock then
                            local myTeam = lplr:GetAttribute('Team')
                            local myBed
                            if myTeam then
                                for _, b in beds do
                                    if b and b.Parent and tonumber(b:GetAttribute('TeamId')) == tonumber(myTeam) then
                                        myBed = b
                                        break
                                    end
                                end
                            end
                            if myBed then
                                local baseOres = {}
                                for _, ore in ironores do
                                    if (ore.Position - myBed.Position).Magnitude <= 40 then
                                        table.insert(baseOres, ore)
                                    end
                                end
                                for _, ore in baseOres do
                                    if (ore.Position - origin).Magnitude < RangeSetting.Value and bedwars.BlockController:isBlockBreakable({blockPosition = ore.Position / 3}, lplr) then
                                        bedwars.breakBlock(ore, EffectsOn.Enabled, Anim.Enabled, nil, false)
                                        if DebugMode and DebugMode.Enabled then dbg('[KD] break base ore') end
                                        task.wait(QuickBreak.Enabled and 0 or SpeedSetting.Value)
                                        break
                                    end
                                end
                            end
                        end
                        targetGlow.Adornee = nil
                        task.wait(0.1)
                        continue
                    end

                    bedGlow.Adornee = bestBed

                    bedVis = isBedVisible(bestBed)
                    if bedVis and not lastBedVis then
                        store.damageBlockFail = 0
                    end
                    lastBedVis = bedVis
                    if DebugMode and DebugMode.Enabled then
                        local dist = (bestBed.Position - origin).Magnitude
                        dbg('[KD] bed=' .. bestBed.Name .. ' dist=' .. math.floor(dist) .. ' visible=' .. tostring(bedVis) .. ' failCD=' .. tostring(store.damageBlockFail > tick()))
                    end

                    if bedVis and store.damageBlockFail <= tick() then
                        store._routePositions = nil
                        store._routeAnchor = nil
                        store._lockedDefenseBlock = nil
                        targetGlow.Adornee = bestBed
                        if PathOverlay.Enabled then clearPath() end
                        strike(bestBed)
                        if DebugMode and DebugMode.Enabled then dbg('[KD] strike bed (visible)') end
                        task.wait(QuickBreak.Enabled and 0 or 0.25)
                        continue
                    end

                    if BreakerFallback and BreakerFallback.Enabled and bedVis then
                        if not ItemLimit.Enabled or (store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name] and bedwars.ItemMeta[store.hand.tool.Name].breakBlock) then
                            targetGlow.Adornee = bestBed
                            if PathOverlay.Enabled then clearPath() end
                            bedwars.breakBlock(bestBed, EffectsOn.Enabled, Anim.Enabled, nil, ToolSwitch.Enabled)
                            if DebugMode and DebugMode.Enabled then dbg('[KD] breaker bed') end
                            task.wait(QuickBreak.Enabled and 0 or 0.25)
                            continue
                        end
                    end

                    if store._routePositions then
                        local advanced = {}
                        for _, pos in store._routePositions do
                            local blk = getPlacedBlock(pos)
                            if blk and not blk:GetAttribute('NoBreak') then
                                table.insert(advanced, pos)
                            end
                        end
                        if #advanced == 0 then
                            store._routePositions = nil
                            store._routeAnchor = nil
                            store._lockedDefenseBlock = nil
                        else
                            store._routePositions = advanced
                        end
                    end

                    freshEntry, freshRoute, freshAnchor, freshCost = planAttack(bestBed, origin)

                    useStored = false
                    if store._routePositions and #store._routePositions > 0 then
                        local storedCost = getRouteCost(store._routePositions, origin)
                        local firstBlock = getPlacedBlock(store._routePositions[1])
                        local damaged = false
                        if firstBlock then
                            local blockData = bedwars.BlockController:getStore():getBlockData(bedwars.BlockController:getBlockPosition(store._routePositions[1]))
                            local curHp = blockData and (blockData:GetAttribute('1') or blockData:GetAttribute('Health')) or firstBlock:GetAttribute('Health')
                            local maxHp = firstBlock:GetAttribute('MaxHealth') or curHp
                            if maxHp > 0 and curHp < maxHp then
                                damaged = true
                            end
                        end
                        if freshRoute then
                            if damaged then
                                useStored = storedCost <= freshCost * 1.5
                            else
                                useStored = storedCost <= freshCost
                            end
                        else
                            useStored = true
                        end
                        if DebugMode and DebugMode.Enabled then
                            local hpStr = ''
                            if firstBlock then
                                local blockData = bedwars.BlockController:getStore():getBlockData(bedwars.BlockController:getBlockPosition(store._routePositions[1]))
                                local curHp = blockData and (blockData:GetAttribute('1') or blockData:GetAttribute('Health')) or firstBlock:GetAttribute('Health')
                                local maxHp = firstBlock:GetAttribute('MaxHealth') or curHp
                                hpStr = ' hp=' .. string.format('%.0f/%.0f', curHp, maxHp)
                            end
                            dbg('[KD] route compare: stored=' .. string.format('%.1f', storedCost) .. ' (' .. #store._routePositions .. ' blocks)' .. hpStr .. (damaged and ' [damaged]' or '') .. ' fresh=' .. (freshRoute and string.format('%.1f', freshCost) or 'none') .. ' -> ' .. (useStored and 'keep' or 'switch'))
                        end
                    end

                    if useStored then
                        local hitPos = store._routePositions[1]
                        local hitBlock = getPlacedBlock(hitPos)
                        if hitBlock and isVisible(hitPos) and (hitPos - origin).Magnitude <= RangeSetting.Value then
                            store._lockedDefenseBlock = hitBlock
                            targetGlow.Adornee = hitBlock
                            if PathOverlay.Enabled then drawPath(store._routePositions, hitPos, store._routeAnchor) end
                            equipFor(hitBlock)
                            strike(hitBlock)
                            if DebugMode and DebugMode.Enabled then dbg('[KD] strike stored route (' .. hitBlock.Name .. ')') end
                            task.wait(QuickBreak.Enabled and 0 or SpeedSetting.Value)
                            continue
                        end
                    end

                    if freshEntry then
                        local entryBlock = getPlacedBlock(freshEntry)
                        if DebugMode and DebugMode.Enabled then
                            dbg('[KD] defense: ' .. tostring(entryBlock and entryBlock.Name) .. ' entryVis=' .. tostring(entryBlock and isVisible(freshEntry)))
                        end
                        if entryBlock and isVisible(freshEntry) then
                            store._routePositions = freshRoute
                            store._routeAnchor = freshAnchor
                            store._lockedDefenseBlock = entryBlock
                            targetGlow.Adornee = entryBlock
                            if PathOverlay.Enabled then drawPath(freshRoute, freshEntry, freshAnchor) end
                            equipFor(entryBlock)
                            strike(entryBlock)
                            if DebugMode and DebugMode.Enabled then dbg('[KD] strike fresh route (' .. entryBlock.Name .. ')') end
                            task.wait(QuickBreak.Enabled and 0 or SpeedSetting.Value)
                            continue
                        end
                    elseif bedVis then
                        targetGlow.Adornee = bestBed
                        strike(bestBed)
                        if DebugMode and DebugMode.Enabled then dbg('[KD] strike bed (no defense found)') end
                        task.wait(QuickBreak.Enabled and 0 or 0.25)
                        continue
                    else
                        if BaseOre and BaseOre.Enabled and store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name] and bedwars.ItemMeta[store.hand.tool.Name].breakBlock then
                            local myTeam = lplr:GetAttribute('Team')
                            local myBed
                            if myTeam then
                                for _, b in beds do
                                    if b and b.Parent and tonumber(b:GetAttribute('TeamId')) == tonumber(myTeam) then
                                        myBed = b
                                        break
                                    end
                                end
                            end
                            if myBed then
                                local baseOres = {}
                                for _, ore in ironores do
                                    if (ore.Position - myBed.Position).Magnitude <= 40 then
                                        table.insert(baseOres, ore)
                                    end
                                end
                                for _, ore in baseOres do
                                    if (ore.Position - origin).Magnitude < RangeSetting.Value and bedwars.BlockController:isBlockBreakable({blockPosition = ore.Position / 3}, lplr) then
                                        bedwars.breakBlock(ore, EffectsOn.Enabled, Anim.Enabled, nil, false)
                                        if DebugMode and DebugMode.Enabled then dbg('[KD] break base ore') end
                                        task.wait(QuickBreak.Enabled and 0 or SpeedSetting.Value)
                                        break
                                    end
                                end
                            end
                        end
                        if DebugMode and DebugMode.Enabled then dbg('[KD] no action') end
                    end

                    targetGlow.Adornee = nil
                    clearPath()
                    killBar()
                    task.wait(1 / TickRate.Value)
                until not KingDraco.Enabled
            else
                fullCleanup()
            end
        end,
        Tooltip = 'Camera-aware bed breaker — only breaks blocks visible from your camera, never through walls'
    })

    RangeSetting = KingDraco:CreateSlider({
        Name = 'Range',
        Min = 1, Max = 30, Default = 30,
        Suffix = function(val) return val == 1 and 'stud' or 'studs' end
    })
    SpeedSetting = KingDraco:CreateSlider({
        Name = 'Break delay',
        Min = 0, Max = 0.3, Default = 0.25, Decimal = 100,
        Suffix = 'seconds'
    })
    TickRate = KingDraco:CreateSlider({
        Name = 'Tick rate',
        Min = 1, Max = 120, Default = 60,
        Suffix = 'hz'
    })
    BreakMode = KingDraco:CreateDropdown({
        Name = 'Break mode',
        List = {'Health', 'Distance'},
        Default = 'Health',
        Tooltip = 'Health = fewest hits first, Distance = closest blocks first'
    })
    EffectsOn = KingDraco:CreateToggle({Name = 'Effects', Default = true})
    HealthDisplay = KingDraco:CreateToggle({Name = 'Health display', Default = true, Darker = true})
    Anim = KingDraco:CreateToggle({Name = 'Break animation'})
    PathOverlay = KingDraco:CreateToggle({
        Name = 'Path overlay',
        Default = true,
        Tooltip = 'Shows the planned break path: red = entry, green = route, blue = bed'
    })
    ToolSwitch = KingDraco:CreateToggle({
        Name = 'Auto tool',
        Default = true,
        Tooltip = 'Equips the best tool for each block type before breaking'
    })
    BreakSelf = KingDraco:CreateToggle({Name = 'Self break'})
    QuickBreak = KingDraco:CreateToggle({Name = 'Instant break'})
    BaseOre = KingDraco:CreateToggle({
        Name = 'Base ore',
        Tooltip = 'Mines iron ore near your own bed when idle'
    })
    ItemLimit = KingDraco:CreateToggle({
        Name = 'Limit to items',
        Tooltip = 'Only breaks when holding a tool'
    })
    BreakerFallback = KingDraco:CreateToggle({
        Name = 'Breaker',
        Default = true,
        Tooltip = 'When server cancels bed strike, use Breaker to pathfind through defense. Uses Auto tool and Limit to items'
    })
    DebugMode = KingDraco:CreateToggle({
        Name = 'Debug',
        Tooltip = 'Prints debug info to console (F9). Press F4 to copy log to clipboard'
    })
end)

--[[
    Kits
]]

run(function()
    local AutoAdetunde

    AutoAdetunde = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Adetunde',
    	Function = function(callback)
    		if callback then
    			repeat
    				local crystal = getItem('frost_crystal')
    				if crystal then
    					for i, v in bedwars.AdetundeUtil.getUpgradesFromHammer(lplr) do
    						local new = getItem('frost_crystal')
    						if not new then
    							break
    						end

    						crystal = new

    						local nextUpgrade = AutoAdetunde.Options['Buy ' .. i].Enabled and bedwars.AdetundeUpgradeMeta[i].tiers[v + 1] or nil
    						if nextUpgrade then
    							if crystal.amount >= nextUpgrade.price then
    								bedwars.Client:Get('UpgradeFrostyHammer'):CallServer(i)
    								task.wait(0.1)
    							end
    						end
    					end
    				end
    				task.wait(0.5)
    			until not AutoAdetunde.Enabled
    		end
    	end,
    	Tooltip = 'Automatically upgrades ur frosty hammer'
    })

    for i in bedwars.AdetundeUpgradeMeta do
    	AutoAdetunde:CreateToggle({
    		Name = 'Buy ' .. i,
    		Default = true,
    	})
    end
end)

run(function()
    local AutoBee
    local Collect
    local CollectRange
    local CollectDelay
    local LimitCollect
    local Deposit
    local DepositRange
    local DepositDelay
    local DepositNow
    local DangerDeposit
    local depositAll
    local dangerDepositToken = nil

    local function instPos(v)
        if v:IsA('BasePart') then return v.Position end
        return v:GetPivot().Position
    end

    AutoBee = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Beekeeper',
    	Function = function(callback)
    		if callback then
    			local hives = collection('beehive', AutoBee)

    			repeat
    				if entitylib.isAlive then
    					pcall(function()
    						if Collect.Enabled and (not LimitCollect.Enabled or store.hand.tool and store.hand.tool.Name == 'bee_net') then
    							local localPosition = entitylib.character.RootPart.Position
    							for _, v in collectionService:GetTagged('bee') do
    								if (localPosition - v.PrimaryPart.Position).Magnitude <= CollectRange.Value then
    									bedwars.Client:Get('PickUpBee'):SendToServer({
    										beeId = v:GetAttribute('BeeId'),
    									})
    									if CollectDelay.Value > 0 then
    										task.wait(CollectDelay.Value)
    									end
    								end
    							end
    						end
    						if Deposit.Enabled and getItem('bee') then
    							local localPosition = entitylib.character.RootPart.Position
    							for _, v in hives do
    								if not getItem('bee') then
    									break
    								end
								if v:GetAttribute('PlacedByUserId') == lplr.UserId and (localPosition - instPos(v)).Magnitude <= DepositRange.Value then
    									pcall(depositAll, v)
    									break
    								end
    							end
    						end
    					end)
    				end
    				task.wait(0.1)
    			until not AutoBee.Enabled
    		end
    	end,
    	Tooltip = 'Automatically deposit bees, and collects nearby bees'
    })
    Collect = AutoBee:CreateToggle({
    	Name = 'Collect bees',
    	Default = true,
    	Function = function(call)
    		pcall(function()
    			CollectRange.Object.Visible = call
    			CollectDelay.Object.Visible = call
    			LimitCollect.Object.Visible = call
    		end)
    	end
    })
    CollectRange = AutoBee:CreateSlider({
    	Name = 'Collect Range',
    	Min = 1,
    	Max = 22,
    	Default = 20,
    	Darker = true,
    	Suffix = function(val)
    		return val <= 1 and 'stud' or 'studs'
    	end
    })
    CollectDelay = AutoBee:CreateSlider({
    	Name = 'Collect delay',
    	Min = 0,
    	Max = 2,
    	Decimal = 100,
    	Default = 0.1,
    	Darker = true
    })
    LimitCollect = AutoBee:CreateToggle({
    	Name = 'Limit to item',
    	Darker = true
    })
    Deposit = AutoBee:CreateToggle({
    	Name = 'Deposit bees',
    	Function = function(call)
    		pcall(function()
    			DepositRange.Object.Visible = call
    			DepositDelay.Object.Visible = call
    		end)
    	end,
    	Tooltip = 'Automatically puts the bees into a beehive'
    })
    DepositRange = AutoBee:CreateSlider({
    	Name = 'Deposit Range',
    	Min = 1,
    	Max = 14,
    	Default = 14,
    	Darker = true,
    	Visible = false,
    	Suffix = function(val)
    		return val <= 1 and 'stud' or 'studs'
    	end
    })
    DepositDelay = AutoBee:CreateSlider({
    	Name = 'Deposit Delay',
    	Min = 0,
    	Max = 2,
    	Decimal = 100,
    	Default = 0.1,
    	Visible = false,
    	Darker = true
    })

    local function findOwnedHive()
        local best, bestDist = nil, math.huge
        for _, v in collectionService:GetTagged('beehive') do
            if v:GetAttribute('PlacedByUserId') == lplr.UserId then
                local ok, d = pcall(function() return (entitylib.character.RootPart.Position - instPos(v)).Magnitude end)
                if ok and d < bestDist then best, bestDist = v, d end
            end
        end
        return best
    end

    local function findKnitRemote(fn, maxDepth)
        local function scan(f, depth)
            if depth <= 0 or type(f) ~= 'function' then return nil end
            local ok, consts = pcall(debug.getconstants, f)
            if ok and consts then
                for i, v in consts do
                    if v == 'Client' and type(consts[i + 1]) == 'string' then
                        return consts[i + 1]
                    end
                end
            end
            local i = 1
            while true do
                local ok2, p = pcall(getproto, f, i)
                if not ok2 or not p then break end
                local result = scan(p, depth - 1)
                if result then return result end
                i = i + 1
            end
            return nil
        end
        return scan(fn, maxDepth)
    end

    local beeDepositRemote = nil
    local beeDepositScanned = false

    local function lazyInitBeeDeposit()
        if beeDepositScanned then return end
        beeDepositScanned = true
        local controllerCandidates = {
            'BeehiveController', 'BeekeeperController', 'BeeKeeperController',
            'BeekeeperKitController', 'BeeKeeperKitController', 'BeeHiveController',
            'BeeController', 'HiveController', 'BeehiveKitController'
        }
        local methodCandidates = {
            'KnitStart', 'onKitLocalActivated', 'deposit', 'depositBee',
            'storeBeesInHive', 'onProximityPrompt', 'setupHive', 'setupBeehive',
            'onHiveDeposit', 'onBeehiveInteract', 'interact'
        }
        for _, ctrlName in controllerCandidates do
            local ok, ctrl = pcall(function() return bedwars[ctrlName] end)
            if ok and ctrl and type(ctrl) == 'table' then
                for _, method in methodCandidates do
                    local fn = rawget(ctrl, method)
                    if type(fn) == 'function' then
                        local remote = findKnitRemote(fn, 8)
                        if remote and remote ~= '' then
                            beeDepositRemote = remote
                            return
                        end
                    end
                end
            end
        end
    end

    depositAll = function(hive)
        lazyInitBeeDeposit()

        local totalBees = 0
        for _, item in store.inventory.inventory.items do
            if item.itemType == 'bee' then totalBees = totalBees + (item.amount or 1) end
        end
        if totalBees == 0 then return 0 end

        if beeDepositRemote then
            local n = 0
            for _ = 1, totalBees do
                if not getItem('bee') then break end
                pcall(function()
                    local remote = bedwars.Client:Get(beeDepositRemote)
                    local ok = pcall(function() remote:CallServer(hive) end)
                    if not ok then remote:SendToServer(hive) end
                end)
                n = n + 1
                task.wait(0.1)
            end
            return n
        end

        local prompt = hive:FindFirstChildOfClass('ProximityPrompt')
        if not prompt then return 0 end
        local n = 0
        for _ = 1, totalBees do
            if not getItem('bee') then break end
            pcall(fireproximityprompt, prompt)
            n = n + 1
            task.wait(0.15)
        end
        return n
    end

    DepositNow = AutoBee:CreateButton({
        Name    = 'Deposit to Hive Now',
        Tooltip = 'Instantly sends all bees to your beehive from anywhere on the map',
        Function = function()
            if not entitylib.isAlive then return end
            if not getItem('bee') then
                notif('AutoBeekeeper', 'No bees in inventory', 3, 'alert')
                return
            end
            local hive = findOwnedHive()
            if not hive then
                notif('AutoBeekeeper', 'No owned hive found — place one first', 4, 'alert')
                return
            end
            local n = depositAll(hive)
            notif('AutoBeekeeper', 'Deposited ' .. n .. ' bee(s) into hive', 3, 'info')
        end
    })

    -- Every bee picked up goes straight to the hive from anywhere, instantly.
    DangerDeposit = AutoBee:CreateToggle({
        Name    = 'Auto Instant Deposit',
        Tooltip = 'Every bee you pick up is automatically sent to your hive from anywhere on the map',
        Function = function(call)
            if not call then
                dangerDepositToken = nil
                return
            end
            local token = {}
            dangerDepositToken = token
            task.spawn(function()
                while DangerDeposit.Enabled and dangerDepositToken == token do
                    task.wait(0.1)
                    if not entitylib.isAlive or not getItem('bee') then continue end
                    local ok, hive = pcall(findOwnedHive)
                    if ok and hive then depositAll(hive) end
                end
            end)
        end
    })
end)

run(function()
    local AutoBuilder
    local Animation
    local Blacklist
    local BedCheck
    local Limit

    local function getBedNear(pos)
    	local bed, lastmag = nil, math.huge
    	local localPosition = pos or Vector3.zero
    	for _, v in collectionService:GetTagged('bed') do
    		local mag = (localPosition - v.Position).Magnitude
    		if mag < lastmag and v:GetAttribute('Team' .. (lplr:GetAttribute('Team') or -1) .. 'NoBreak') then
    			bed = v
    			lastmag = mag
    		end
    	end
    	return bed, lastmag
    end

    AutoBuilder = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Builder',
    	Function = function(callback)
    		if callback then
    			repeat
    				task.wait()
    			until store.matchState ~= 0 and store.equippedKit == 'builder' or not AutoBuilder.Enabled
    			if not AutoBuilder.Enabled then
    				return
    			end

    			local bed = getBedNear(entitylib.character.RootPart.Position)
    			local blocks = collection('block', AutoBuilder, function(tab, obj)
    				task.delay(0, function()
    					if obj and not obj:GetAttribute('NoBreak') and obj:GetAttribute('PlacedByUserId') ~= nil then
    						table.insert(tab, obj)
    					end
    				end)
    			end)
    			repeat
    				if entitylib.isAlive and (not Limit.Enabled and getItem('hammer') or Limit.Enabled and store.hand.tool and store.hand.tool.Name == 'hammer') then
    					bed = getBedNear(entitylib.character.RootPart.Position)

    					for _, v in blocks do
    						if not BedCheck.Enabled or (bed.Position - v.Position).Magnitude <= 30 then
    							local name = v.Name
    							if name:find('wool_') then
    								name = 'wool'
    							end
    							if not table.find(Blacklist.ListEnabled, name) and not v:FindFirstChild('BuilderFortify') then
    								bedwars.Client:Get('FortifyBlock'):SendToServer(({getPlacedBlock(v.Position)})[2])
    								if Animation.Enabled then
    									bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.GameAnimationUtil:getAssetId(bedwars.AnimationType.BUILDER_HAMMER_HIT), {
    										fadeInTime = 0.02
    									})
                						bedwars.SoundManager:playSound(bedwars.SoundList.FORTIFY_BLOCK,lplr.Character.HumanoidRootPart.Position)
    								end
    							end
    						end
    					end
    				end
    				task.wait(0.1)
    			until not AutoBuilder.Enabled
    		end
    	end
    })

    BedCheck = AutoBuilder:CreateToggle({
    	Name = 'Bed Check',
    	Tooltip = 'Checks if the block is near your bed'
    })
    Animation = AutoBuilder:CreateToggle({
    	Name = 'Animation',
    	Default = true,
    	Tooltip = 'Plays builder visuals (sfx and anim)'
    })
    Limit = AutoBuilder:CreateToggle({
    	Name = 'Limit to items',
    	Default = true
    })
    Blacklist = AutoBuilder:CreateTextList({
    	Name = 'Blacklists',
    	Placeholder = 'block',
    	Default = {'cannon', 'wool'}
    })
end)

run(function()
    local AutoCaitlyn
    local Mode
    local Range
    local MinHP

    AutoCaitlyn = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Caitlyn',
    	Function = function(callback)
    		if callback then
    			AutoCaitlyn:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
    				if entitylib.isAlive and damageTable.fromEntity == lplr.Character and (entitylib.character.RootPart.Position - damageTable.entityInstance.HumanoidRootPart.Position).Magnitude <= Range.Value then
    					local state = bedwars.Store:getState()
    					if not state.Kit.activeContract then
    						for _, v in (state.Kit.availableContracts or {}) do
    							if v.target and v.target.Name == damageTable.entityInstance.Name and (Mode.Value == 'On Hit' or damageTable.entityInstance.Humanoid.Health < MinHP.Value) then
    								bedwars.Client:Get('BloodAssassinSelectContract'):SendToServer({
    									contractId = v.id,
    								})
    								break
    							end
    						end
    					end
    				end
    			end))
    		end
    	end,
    	Tooltip = 'Automatically assigns a player\'s contract when a specific action happens'
    })

    Mode = AutoCaitlyn:CreateDropdown({
    	Name = 'Contract mode',
    	List = {'On Hit', 'On Low'},
    	Tooltip = 'On Hit - Contracts them whenever u start hitting them\nOn Low - When they\'re low',
    	Function = function(val)
    		if MinHP then
    			MinHP.Object.Visible = val == 'On Low'
    		end
    	end,
    	Default = 'On Low'
    })
    MinHP = AutoCaitlyn:CreateSlider({
    	Name = 'Minimum Health',
    	Tooltip = 'How low they have to be before contracting',
    	Min = 1,
    	Max = 100,
    	Default = 30,
    	Darker = true
    })
    Range = AutoCaitlyn:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 50,
    	Default = 50,
    	Suffix = function(val)
    		return val <= 1 and 'stud' or 'studs'
    	end
    })
end)

run(function()
    local AutoCobalt -- made by ba0
    local HitboxSize
    local RestoreOnDisable
    
    local originalProperties = {}
    local workspaceConnection
    
    -- Helper function to expand the hitbox of a specific battery model
    local function expandBattery(obj, size)
        if obj.Name == "Open" and obj:IsA("Model") then
            -- Verify it is a Cobalt battery
            if obj:FindFirstChild("Invertedneon") or obj:FindFirstChild("Top") then
                task.wait(0.1)
                -- Stop execution if the module was toggled off during wait
                if not AutoCobalt.Enabled then return end
                
                for _, part in ipairs(obj:GetDescendants()) do
                    if part:IsA("BasePart") then
                        -- Store original properties before modifying them
                        if not originalProperties[part] then
                            originalProperties[part] = {
                                Size = part.Size,
                                CanCollide = part.CanCollide,
                                CanTouch = part.CanTouch
                            }
                        end
                        
                        part.CanCollide = false
                        part.CanTouch = true
                        part.Size = Vector3.new(size, size, size)
                    end
                end
            end
        end
    end
    
    -- Restores all modified parts to their original state
    local function restoreAllProperties()
        for part, props in pairs(originalProperties) do
            pcall(function()
                if part and part.Parent then
                    part.Size = props.Size
                    part.CanCollide = props.CanCollide
                    part.CanTouch = props.CanTouch
                end
            end)
        end
        table.clear(originalProperties)
    end
    
    AutoCobalt = vape.Categories.Kits:CreateModule({
        Name = 'Auto Cobalt',
        Function = function(callback)
            if callback then
                -- Scan existing parts in the workspace
                for _, descendant in ipairs(workspace:GetDescendants()) do
                    task.spawn(expandBattery, descendant, HitboxSize.Value)
                end
    
                -- Monitor for new battery spawns
                workspaceConnection = workspace.DescendantAdded:Connect(function(descendant)
                    task.spawn(expandBattery, descendant, HitboxSize.Value)
                end)
                AutoCobalt:Clean(workspaceConnection)
            else
                -- Disconnect listener on toggle off
                if workspaceConnection then
                    workspaceConnection:Disconnect()
                    workspaceConnection = nil
                end
                
                -- Restore properties if the option is active
                if RestoreOnDisable.Enabled then
                    restoreAllProperties()
                else
                    table.clear(originalProperties)
                end
            end
        end,
        Tooltip = 'Expands the touch detection area of Cobalt batteries to collect them instantly'
    })
    
    HitboxSize = AutoCobalt:CreateSlider({
        Name = 'Hitbox Size',
        Min = 1,
        Max = 1000,
        Default = 1000,
        Suffix = ' studs',
        Tooltip = 'The dimension size applied to the battery components'
    })
    
    RestoreOnDisable = AutoCobalt:CreateToggle({
        Name = 'Restore on disable',
        Default = true,
        Tooltip = 'Reverts the size of active batteries when this feature is turned off'
    })
end)

run(function()
    local AutoDavey
    local Switch
    local Break
    local Jump

    local old

    AutoDavey = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Davey',
    	Function = function(call)
    		if call then
    			old = bedwars.CannonHandController.launchSelf
    			bedwars.CannonHandController.launchSelf = function(...)
    				local res = { old(...) }
    				local block = select(2, ...)

    				if Break.Enabled then
    					if (block.Position - entitylib.character.RootPart.Position).Magnitude <= 30 then
    						task.delay(0.05, function()
    							for i = 1, 2 do
    								task.spawn(bedwars.breakBlock, block, false, nil, true, nil, Switch.Enabled)
    							end
    						end)
    					end
    				end

    				if Jump.Enabled then
    					lplr.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    				end

    				return unpack(res)
    			end
    		else
    			bedwars.CannonHandController.launchSelf = old
    		end
    	end,
    	Tooltip = 'Automatically breaks cannon/jump on launch'
    })

    Jump = AutoDavey:CreateToggle({Name = 'Jump on impact'})
    Break = AutoDavey:CreateToggle({Name = 'Break on impact'})
    Switch = AutoDavey:CreateToggle({Name = 'Legit switch'})
end)

run(function()
    local AutoDrill
    local AutoCollect
    local Notify
    local AutoAttack
    local Legit
    local Range
    local AttackDelay
    local CollectDelay
    local Targets
    local Sort
    local currentDrill
    local attackDebounce = {}
    local collectDebounce = {}

    local function getDrillPart(drill)
    	return drill and (drill.PrimaryPart or drill:FindFirstChild('RootPart') or drill:FindFirstChildWhichIsA('BasePart'))
    end

    local function addDrill(drills, added, drill)
    	if typeof(drill) ~= 'Instance' or added[drill] or drill:GetAttribute('PlacedByUserId') ~= lplr.UserId then
    		return
    	end
    	if getDrillPart(drill) then
    		added[drill] = true
    		table.insert(drills, drill)
    	end
    end

    local function getDrills(tagged)
    	local drills, added = {}, {}
    	for _, drill in tagged do
    		addDrill(drills, added, drill)
    	end

    	for _, drill in (bedwars.DrillTabletController and bedwars.DrillTabletController.drillList or {}) do
    		addDrill(drills, added, drill)
    	end

    	return drills
    end

    local function getResourceAmount(drill)
    	return (drill:GetAttribute('diamond') or 0) + (drill:GetAttribute('emerald') or 0)
    end

    local function collectDrill(drill)
    	local suc = pcall(function()
    		bedwars.Client:Get('ExtractFromDrill'):SendToServer({
    			drill = drill,
    		})
    	end)
    	return suc
    end

    local function useDrill(drill)
    	if currentDrill == drill then
    		return true
    	end

    	local suc, res = pcall(function()
    		return bedwars.Client:Get('PlayerUseDrillController'):CallServer({
    			drill = drill,
    		})
    	end)

    	if suc and res ~= false then
    		currentDrill = drill
    		return true
    	end

    	return false
    end

    local function attackDrill(drill, target)
    	if not useDrill(drill) then
    		return false
    	end

    	local suc = pcall(function()
    		bedwars.Client:Get('DrillAttack'):SendToServer({
    			targetPosition = target.RootPart.Position,
    		})
    	end)
    	return suc
    end

    local function getTarget(position)
    	return entitylib.EntityPosition({
    		Origin = position,
    		Range = Legit.Enabled and 10 or Range.Value,
    		Part = 'RootPart',
    		Players = Targets.Players.Enabled,
    		NPCs = Targets.NPCs.Enabled,
    		Sort = sortmethods[Sort.Value],
    	})
    end

    local function updateAttackControls()
    	pcall(function()
    		local enabled = AutoAttack.Enabled
    		Legit.Object.Visible = enabled
    		Range.Object.Visible = enabled and not Legit.Enabled
    		AttackDelay.Object.Visible = enabled
    		Targets.Object.Visible = enabled
    		Sort.Object.Visible = enabled
    	end)
    end

    AutoDrill = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Drill',
    	Function = function(callback)
    		if callback then
    			local tagged = collection('Drill', AutoDrill)
    			repeat
    				task.wait()
    			until store.matchState ~= 0 and store.equippedKit == 'drill' or not AutoDrill.Enabled

    			repeat
    				if entitylib.isAlive and store.equippedKit == 'drill' then
    					local now = tick()
    					for _, drill in getDrills(tagged) do
    						local part = getDrillPart(drill)
    						if not part then
    							continue
    						end

    						if
    							AutoCollect.Enabled
    							and getResourceAmount(drill) > 0
    							and now > (collectDebounce[drill] or 0)
    						then
    							if collectDrill(drill) and Notify.Enabled then
    								notif('Auto Drill', 'Collected drill resources', 4, 'info')
    							end
    							collectDebounce[drill] = now + CollectDelay.Value
    						end

    						if AutoAttack.Enabled and now > (attackDebounce[drill] or 0) then
    							local target = getTarget(part.Position)
    							if target then
    								targetinfo.Targets[target] = tick() + 1
    								if attackDrill(drill, target) then
    									attackDebounce[drill] = now + AttackDelay.Value
    								end
    							end
    						end
    					end
    				end

    				task.wait(0.1)
    			until not AutoDrill.Enabled
    		else
    			currentDrill = nil
    			table.clear(attackDebounce)
    			table.clear(collectDebounce)
    		end
    	end,
    	Tooltip = 'Automatically collects resources and attacks with placed drills.'
    })
    AutoCollect = AutoDrill:CreateToggle({
    	Name = 'Auto collect',
    	Default = true,
    	Function = function(callback)
    		pcall(function()
    			Notify.Object.Visible = callback
    			CollectDelay.Object.Visible = callback
    		end)
    	end
    })
    Notify = AutoDrill:CreateToggle({
    	Name = 'Notify on collect',
    	Darker = true
    })
    AutoAttack = AutoDrill:CreateToggle({
    	Name = 'Auto attack',
    	Default = true,
    	Function = updateAttackControls
    })
    Range = AutoDrill:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 10,
    	Default = 10,
    	Suffix = function(value)
    		return value == 1 and 'stud' or 'studs'
    	end
    })
    Legit = AutoDrill:CreateToggle({
    	Name = 'Legit Range',
    	Default = true,
    	Function = updateAttackControls
    })
    AttackDelay = AutoDrill:CreateSlider({
    	Name = 'Attack delay',
    	Min = 0.1,
    	Max = 1,
    	Default = 0.3,
    	Decimal = 100,
    	Suffix = function(value)
    		return value == 1 and 'sec' or 'secs'
    	end
    })
    CollectDelay = AutoDrill:CreateSlider({
    	Name = 'Collect delay',
    	Min = 0.1,
    	Max = 3,
    	Default = 0.5,
    	Decimal = 10,
    	Suffix = function(value)
    		return value == 1 and 'sec' or 'secs'
    	end
    })
    Targets = AutoDrill:CreateTargets({
    	Players = true,
    	NPCs = false
    })
    local methods = {'Distance', 'Health', 'Damage'}
    for name in sortmethods do
    	if not table.find(methods, name) then
    		table.insert(methods, name)
    	end
    end
    Sort = AutoDrill:CreateDropdown({
    	Name = 'Sort',
    	List = methods,
    	Default = 'Distance'
    })
    updateAttackControls()
end)

run(function()
    local AutoElder
    local Streamer
    local Range
    local Animation
    local Delay

    AutoElder = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Elder',
    	Function = function(call)
    		if call then
    			AutoElder:Clean(proximityPromptService.PromptShown:Connect(function(prompt)
    				if Streamer.Enabled and prompt.Name == 'treeOrb' then
    					task.delay(0.1, prompt.InputHoldBegin, prompt)
    				end
    			end))

    			repeat
    				if not Streamer.Enabled and entitylib.isAlive then
    					local localPosition = entitylib.character.RootPart.Position
    					for i, v in collectionService:GetTagged('treeOrb') do
    						if tick() > (Delay[v] or 0) and (localPosition - v.Spirit.Position).Magnitude <= Range.Value then
    							if Delay.Value > 0 then
    								task.wait(Delay.Value)
    							end

    							if (localPosition - v.Spirit.Position).Magnitude <= Range.Value then
    								if Animation.Enabled then
    									bedwars.GameAnimationUtil:playAnimation(lplr.Character, bedwars.AnimationType.PUNCH)
    									bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_USE_ITEM)
    									bedwars.SoundManager:playSound(bedwars.SoundList.CROP_HARVEST)
    								end
    								if bedwars.Client:Get(remotes.ConsumeTreeOrb):CallServer({treeOrbSecret = v:GetAttribute('TreeOrbSecret')}) then
    									v:Destroy()
    								end
    								Delay[v] = tick() + 1
    							end
    						end
    					end
    				end
    				task.wait(0.1)
    			until not AutoElder.Enabled
    		end
    	end,
    	Tooltip = 'Automatically collects tree orbs'
    })

    Streamer = AutoElder:CreateToggle({
    	Name = 'Streamer mode',
    	Tooltip = 'Useful for when ur screensharing',
    	Function = function(call)
    		pcall(function()
    			Delay.Object.Visible = not call
    			Range.Object.Visible = not call
    			Animation.Object.Visible = not call
    		end)
    	end
    })
    Animation = AutoElder:CreateToggle({
    	Name = 'Animation',
    	Default = true,
    	Tooltip = 'Plays the collect animation'
    })
    Range = AutoElder:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 20,
    	Default = 12,
    	Suffix = function(val)
    		return val > 1 and 'studs' or 'stud'
    	end
    })
    Delay = AutoElder:CreateSlider({
    	Name = 'Delay',
    	Min = 0,
    	Max = 1,
    	Suffix = function(val)
    		return val > 1 and 'secs' or 'sec'
    	end,
    	Default = 0.2,
    	Decimal = 100
    })
end)

run(function()
    local AutoEmber
    local Targets
    local Range
    local Delay
    local Limit

    AutoEmber = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Ember',
    	Function = function(call)
    		if call then
    			local clock = os.clock()
    			repeat
    				if entitylib.isAlive then
    					local tool = getItem('infernal_saber')
    					if tool and (not Limit.Enabled or store.hand.tool and store.hand.tool == tool) and entitylib.EntityPosition({
    						Range = Range.Value,
    						Players = Targets.Players.Enabled,
    						NPCs = Targets.NPCs.Enabled,
    					}) then
    						if Delay.Value <= 0 or (os.clock() - clock) >= Delay.Value then
    							bedwars.Client:Get('HellBladeRelease'):SendToServer({
    								chargeTime = 1,
    								weapon = tool,
    								player = lplr,
    							})
    							clock = os.clock()
    						end
    					end
    				end
    				task.wait()
    			until not AutoEmber.Enabled
    		end
    	end
    })

    Targets = AutoEmber:CreateTargets({
    	Players = true,
    	NPCs = false
    })
    Delay = AutoEmber:CreateSlider({
    	Name = 'Delay',
    	Min = 0,
    	Max = 1,
    	Default = 0.1,
    	Decimal = 100
    })
    Range = AutoEmber:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 22,
    	Default = 22,
    	Suffix = function(val)
    		return val <= 1 and 'stud' or 'studs'
    	end
    })
    Limit = AutoEmber:CreateToggle({Name = 'Limit to item'})
end)

run(function()
    local AutoGingerbread
    local Range
    local Delay
    local Break
    local Jump
    local Switch
    local OwnOnly
    local SuccessfulOnly

    local old
    local hook

    local function canUseBlock(block)
    	if not entitylib.isAlive or typeof(block) ~= 'Instance' or not block:IsA('BasePart') then
    		return false
    	end

    	if store.equippedKit ~= 'gingerbread_man' then
    		return false
    	end

    	if OwnOnly.Enabled and block:GetAttribute('PlacedByUserId') ~= lplr.UserId then
    		return false
    	end

    	return (block.Position - entitylib.character.RootPart.Position).Magnitude <= Range.Value
    end

    AutoGingerbread = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Gingerbread Man',
    	Function = function(callback)
    		if callback then
    			old = bedwars.LaunchPadController.attemptLaunch
    			hook = function(...)
    				local controller, block = ...
    				local lastLaunch = controller and controller.lastLaunch or 0

    				if not SuccessfulOnly.Enabled or (controller and controller.lastLaunch and (controller.lastLaunch ~= lastLaunch or workspace:GetServerTimeNow() - controller.lastLaunch < 0.5)) then
    					if Break.Enabled and canUseBlock(block) then
    						task.delay(Delay.Value, bedwars.breakBlock, block, false, nil, true, nil, Switch.Enabled)
    					end

    					if Jump.Enabled and entitylib.isAlive then
    						lplr.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    					end
    				end

    				return old(...)
    			end
    			bedwars.LaunchPadController.attemptLaunch = hook
    		elseif old then
    			if bedwars.LaunchPadController.attemptLaunch == hook then
    				bedwars.LaunchPadController.attemptLaunch = old
    			end
    			old = nil
    			hook = nil
    		end
    	end,
    	Tooltip = 'Automatically handles Gingerbread Man launch pads.'
    })

    Break = AutoGingerbread:CreateToggle({
    	Name = 'Break launch pad',
    	Default = true,
    	Function = function(call)
    		pcall(function()
    			Range.Object.Visible = call
    			Delay.Object.Visible = call
    			Switch.Object.Visible = call
    			OwnOnly.Object.Visible = call
    		end)
    	end
    })
    Jump = AutoGingerbread:CreateToggle({Name = 'Jump after launch'})
    Switch = AutoGingerbread:CreateToggle({
    	Name = 'Legit switch',
    	Darker = true
    })
    OwnOnly = AutoGingerbread:CreateToggle({
    	Name = 'Own pads only',
    	Default = true,
    	Darker = true
    })
    SuccessfulOnly = AutoGingerbread:CreateToggle({
    	Name = 'Successful launch only',
    	Default = true
    })
    Range = AutoGingerbread:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 30,
    	Default = 30,
    	Darker = true,
    	Suffix = function(val)
    		return val <= 1 and 'stud' or 'studs'
    	end
    })
    Delay = AutoGingerbread:CreateSlider({
    	Name = 'Break delay',
    	Min = 0,
    	Max = 1,
    	Default = 0.05,
    	Decimal = 100,
    	Darker = true,
    	Suffix = function(val)
    		return val == 1 and 'sec' or 'secs'
    	end
    })
end)

run(function()
    local AutoHannah
    local Range

    AutoHannah = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Hannah',
    	Function = function(callback)
    		if callback then
    			local objs = collection('HannahExecuteInteraction', AutoHannah)
    			repeat
    				if entitylib.isAlive and store.equippedKit == 'hannah' then
    					local localPosition = entitylib.character.RootPart.Position
    					for _, v in objs do
    						if not AutoHannah.Enabled then
    							break
    						end

    						local part = not v:IsA('Model') and v or v.PrimaryPart
    						if part and (part.Position - localPosition).Magnitude <= Range.Value then
    							local billboard = bedwars.Client:Get(remotes.HannahKill):CallServer({
    								user = lplr,
    								victimEntity = v,
    							}) and v:FindFirstChild('Hannah Execution Icon')

    							if billboard then
    								billboard:Destroy()
    							end
    						end
    					end
    				end
    				task.wait(0.1)
    			until not AutoHannah.Enabled
    		end
    	end,
    	Tooltip = 'Automatically executes low health players with Hannah.'
    })

    AutoHannah:CreateTargets({Players = true}) -- cosmetic settings lmao
    Range = AutoHannah:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 30,
    	Default = 30,
    	Suffix = function(val)
    		return val <= 1 and 'stud' or 'studs'
    	end
    })
    local methods = {'Damage', 'Distance'}
    for i in sortmethods do
    	if not table.find(methods, i) then
    		table.insert(methods, i)
    	end
    end
    AutoHannah:CreateDropdown({
    	Name = 'Target mode', 
    	List = methods,
    	Default = 'Health'
    })
    AutoHannah:CreateToggle({
    	Name = 'Only killaura target',
    	Tooltip = 'Only executes targets that are being attacked by killaura'
    })
end)

run(function()
    local AutoKaliyah
    local Range
    local Delay
    local NoSlow

    local function func(v)
    	if NoSlow.Enabled then
    		local modifier = bedwars.SprintController:getMovementStatusModifier()
    		local old = modifier.addModifier
    		modifier.addModifier = function(self, tab)
    			if tab.moveSpeedMultiplier and tab.moveSpeedMultiplier == 0 then
    				tab.moveSpeedMultiplier = 1
    			end
    			return old(self, tab)
    		end
    		task.delay(Delay.Value + 0.1, function()
    			modifier.addModifier = old
    		end)
    	end

    	task.wait(Delay.Value)
    	bedwars.DragonSlayerController:deleteEmblem(v)
    	bedwars.DragonSlayerController:playPunchAnimation(Vector3.zero)

    	bedwars.Client:Get(remotes.KaliyahPunch):SendToServer({
    		target = v
    	})
    end

    AutoKaliyah = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Kaliyah',
    	Function = function(call)
    		if call then
    			local objs = collection('KaliyahPunchInteraction', AutoKaliyah)

    			repeat
    				if entitylib.isAlive then
    					local localPosition = entitylib.character.RootPart.Position
    					for _, v in objs do
    						if not AutoKaliyah.Enabled then
    							break
    						end

    						local part = not v:IsA('Model') and v or v.PrimaryPart
    						if part and (part.Position - localPosition).Magnitude <= Range.Value then
    							func(v)
    						end
    					end
    				end
    				task.wait(0.1)
    			until not AutoKaliyah.Enabled
    		end
    	end,
    	Tooltip = 'Automatically uses the "punch" ability from kaliyah'
    })

    NoSlow = AutoKaliyah:CreateToggle({
    	Name = 'No Slow',
    	Tooltip = 'Prevents you from being slowed down after using the "Punch" ability',
    	Default = true
    })
    Range = AutoKaliyah:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 20,
    	Default = 18,
    	Suffix = function(val)
    		return val <= 1 and 'stud' or 'studs'
    	end
    })
    Delay = AutoKaliyah:CreateSlider({
    	Name = 'Delay',
    	Min = 0,
    	Max = 1,
    	Default = 0.1,
    	Decimal = 100
    })
end)

run(function()
    local AutoKit
    local Legit
    local Toggles = {}
    
    local function kitCollection(id, func, range, specific)
        local objs = type(id) == 'table' and id or collection(id, AutoKit)
        repeat
            if entitylib.isAlive then
                local localPosition = entitylib.character.RootPart.Position
                for _, v in objs do
                    if InfiniteFly.Enabled or not AutoKit.Enabled then break end
                    local part = not v:IsA('Model') and v or v.PrimaryPart
                    if part and (part.Position - localPosition).Magnitude <= (not Legit.Enabled and specific and math.huge or range) then
                        func(v)
                    end
                end
            end
            task.wait(0.1)
        until not AutoKit.Enabled
    end
    
    local AutoKitFunctions = {
        battery = function()
            repeat
                if entitylib.isAlive then
                    local localPosition = entitylib.character.RootPart.Position
                    for i, v in bedwars.BatteryEffectsController.liveBatteries do
                        if (v.position - localPosition).Magnitude <= 10 then
                            local BatteryInfo = bedwars.BatteryEffectsController:getBatteryInfo(i)
                            if not BatteryInfo or BatteryInfo.activateTime >= workspace:GetServerTimeNow() or BatteryInfo.consumeTime + 0.1 >= workspace:GetServerTimeNow() then continue end
                            BatteryInfo.consumeTime = workspace:GetServerTimeNow()
                            bedwars.Client:Get(remotes.ConsumeBattery):SendToServer({batteryId = i})
                        end
                    end
                end
                task.wait(0.1)
            until not AutoKit.Enabled
        end,
        beekeeper = function()
            kitCollection('bee', function(v)
                bedwars.Client:Get(remotes.BeePickup):SendToServer({beeId = v:GetAttribute('BeeId')})
            end, 18, false)
        end,
        bigman = function()
            kitCollection('treeOrb', function(v)
                if bedwars.Client:Get(remotes.ConsumeTreeOrb):CallServer({treeOrbSecret = v:GetAttribute('TreeOrbSecret')}) then
                    v:Destroy()
                end
            end, 12, false)
        end,
        block_kicker = function()
            local old = bedwars.BlockKickerKitController.getKickBlockProjectileOriginPosition
            bedwars.BlockKickerKitController.getKickBlockProjectileOriginPosition = function(...)
                local origin, dir = select(2, ...)
                local plr = entitylib.EntityMouse({
                    Part = 'RootPart',
                    Range = 1000,
                    Origin = origin,
                    Players = true,
                    Wallcheck = true
                })
    
                if plr then
                    local calc = prediction.SolveTrajectory(origin, 100, 20, plr.RootPart.Position, plr.RootPart.Velocity, workspace.Gravity, plr.HipHeight, plr.Jumping and 42.6 or nil)
    
                    if calc then
                        for i, v in debug.getstack(2) do
                            if v == dir then
                                debug.setstack(2, i, CFrame.lookAt(origin, calc).LookVector)
                            end
                        end
                    end
                end
    
                return old(...)
            end
    
            AutoKit:Clean(function()
                bedwars.BlockKickerKitController.getKickBlockProjectileOriginPosition = old
            end)
        end,
        cat = function()
            local old = bedwars.CatController.leap
            bedwars.CatController.leap = function(...)
                vapeEvents.CatPounce:Fire()
                return old(...)
            end
    
            AutoKit:Clean(function()
                bedwars.CatController.leap = old
            end)
        end,
        davey = function()
            local old = bedwars.CannonHandController.launchSelf
            bedwars.CannonHandController.launchSelf = function(...)
                local res = {old(...)}
                local self, block = ...
    
                if block:GetAttribute('PlacedByUserId') == lplr.UserId and (block.Position - entitylib.character.RootPart.Position).Magnitude < 30 then
                    task.spawn(bedwars.breakBlock, block, false, nil, true)
                end
    
                return unpack(res)
            end
    
            AutoKit:Clean(function()
                bedwars.CannonHandController.launchSelf = old
            end)
        end,
        dragon_slayer = function()
            kitCollection('KaliyahPunchInteraction', function(v)
                bedwars.DragonSlayerController:deleteEmblem(v)
                bedwars.DragonSlayerController:playPunchAnimation(Vector3.zero)
                bedwars.Client:Get(remotes.KaliyahPunch):SendToServer({
                    target = v
                })
            end, 18, true)
        end,
        farmer_cletus = function()
            kitCollection('HarvestableCrop', function(v)
                if bedwars.Client:Get(remotes.HarvestCrop):CallServer({position = bedwars.BlockController:getBlockPosition(v.Position)}) then
                    bedwars.GameAnimationUtil:playAnimation(lplr.Character, bedwars.AnimationType.PUNCH)
                    bedwars.SoundManager:playSound(bedwars.SoundList.CROP_HARVEST)
                end
            end, 10, false)
        end,
        fisherman = function()
            local old = bedwars.FishingMinigameController.startMinigame
            bedwars.FishingMinigameController.startMinigame = function(_, _, result)
                result({win = true})
            end
    
            AutoKit:Clean(function()
                bedwars.FishingMinigameController.startMinigame = old
            end)
        end,
        gingerbread_man = function()
            local old = bedwars.LaunchPadController.attemptLaunch
            bedwars.LaunchPadController.attemptLaunch = function(...)
                local res = {old(...)}
                local self, block = ...
    
                if (workspace:GetServerTimeNow() - self.lastLaunch) < 0.4 then
                    if block:GetAttribute('PlacedByUserId') == lplr.UserId and (block.Position - entitylib.character.RootPart.Position).Magnitude < 30 then
                        task.spawn(bedwars.breakBlock, block, false, nil, true)
                    end
                end
    
                return unpack(res)
            end
    
            AutoKit:Clean(function()
                bedwars.LaunchPadController.attemptLaunch = old
            end)
        end,
        hannah = function()
            kitCollection('HannahExecuteInteraction', function(v)
                local billboard = bedwars.Client:Get(remotes.HannahKill):CallServer({
                    user = lplr,
                    victimEntity = v
                }) and v:FindFirstChild('Hannah Execution Icon')
    
                if billboard then
                    billboard:Destroy()
                end
            end, 30, true)
        end,
        jailor = function()
            kitCollection('jailor_soul', function(v)
                bedwars.JailorController:collectEntity(lplr, v, 'JailorSoul')
            end, 20, false)
        end,
        grim_reaper = function()
            kitCollection(bedwars.GrimReaperController.soulsByPosition, function(v)
                if entitylib.isAlive and lplr.Character:GetAttribute('Health') <= (lplr.Character:GetAttribute('MaxHealth') / 4) and (not lplr.Character:GetAttribute('GrimReaperChannel')) then
                    bedwars.Client:Get(remotes.ConsumeSoul):CallServer({
                        secret = v:GetAttribute('GrimReaperSoulSecret')
                    })
                end
            end, 120, false)
        end,
        melody = function()
            repeat
                local mag, hp, ent = 30, math.huge
                if entitylib.isAlive then
                    local localPosition = entitylib.character.RootPart.Position
                    for _, v in entitylib.List do
                        if v.Player and v.Player:GetAttribute('Team') == lplr:GetAttribute('Team') then
                            local newmag = (localPosition - v.RootPart.Position).Magnitude
                            if newmag <= mag and v.Health < hp and v.Health < v.MaxHealth then
                                mag, hp, ent = newmag, v.Health, v
                            end
                        end
                    end
                end
    
                if ent and getItem('guitar') then
                    bedwars.Client:Get(remotes.GuitarHeal):SendToServer({
                        healTarget = ent.Character
                    })
                end
    
                task.wait(0.1)
            until not AutoKit.Enabled
        end,
        metal_detector = function()
            kitCollection('hidden-metal', function(v)
                bedwars.Client:Get(remotes.PickupMetal):SendToServer({
                    id = v:GetAttribute('Id')
                })
            end, 20, false)
        end,
        miner = function()
            kitCollection('petrified-player', function(v)
                bedwars.Client:Get(remotes.MinerDig):SendToServer({
                    petrifyId = v:GetAttribute('PetrifyId')
                })
            end, 6, true)
        end,
        pinata = function()
            kitCollection(lplr.Name..':pinata', function(v)
                if getItem('candy') then
                    bedwars.Client:Get(remotes.DepositPinata):CallServer(v)
                end
            end, 6, true)
        end,
        spirit_assassin = function()
            kitCollection('EvelynnSoul', function(v)
                bedwars.SpiritAssassinController:useSpirit(lplr, v)
            end, 120, true)
        end,
        star_collector = function()
            kitCollection('stars', function(v)
                bedwars.StarCollectorController:collectEntity(lplr, v, v.Name)
            end, 20, false)
        end,
        summoner = function()
            repeat
                local plr = entitylib.EntityPosition({
                    Range = 31,
                    Part = 'RootPart',
                    Players = true,
                    Sort = sortmethods.Health
                })
    
                if plr and (not Legit.Enabled or (lplr.Character:GetAttribute('Health') or 0) > 0) then
                    local localPosition = entitylib.character.RootPart.Position
                    local shootDir = CFrame.lookAt(localPosition, plr.RootPart.Position).LookVector
                    localPosition = localPosition + shootDir * math.max((localPosition - plr.RootPart.Position).Magnitude - 16, 0)
    
                    bedwars.Client:Get(remotes.SummonerClawAttack):SendToServer({
                        position = localPosition,
                        direction = shootDir,
                        clientTime = workspace:GetServerTimeNow()
                    })
                end
    
                task.wait(0.1)
            until not AutoKit.Enabled
        end,
        void_dragon = function()
            local oldflap = bedwars.VoidDragonController.flapWings
            local flapped
    
            bedwars.VoidDragonController.flapWings = function(self)
                if not flapped and bedwars.Client:Get(remotes.DragonFly):CallServer() then
                    local modifier = bedwars.SprintController:getMovementStatusModifier():addModifier({
                        blockSprint = true,
                        constantSpeedMultiplier = 2
                    })
                    self.SpeedMaid:GiveTask(modifier)
                    self.SpeedMaid:GiveTask(function()
                        flapped = false
                    end)
                    flapped = true
                end
            end
    
            AutoKit:Clean(function()
                bedwars.VoidDragonController.flapWings = oldflap
            end)
    
            repeat
                if bedwars.VoidDragonController.inDragonForm then
                    local plr = entitylib.EntityPosition({
                        Range = 30,
                        Part = 'RootPart',
                        Players = true
                    })
    
                    if plr then
                        bedwars.Client:Get(remotes.DragonBreath):SendToServer({
                            player = lplr,
                            targetPoint = plr.RootPart.Position
                        })
                    end
                end
                task.wait(0.1)
            until not AutoKit.Enabled
        end,
        warlock = function()
            local lastTarget
            repeat
                if store.hand.tool and store.hand.tool.Name == 'warlock_staff' then
                    local plr = entitylib.EntityPosition({
                        Range = 30,
                        Part = 'RootPart',
                        Players = true,
                        NPCs = true
                    })
    
                    if plr and plr.Character ~= lastTarget then
                        if not bedwars.Client:Get(remotes.WarlockTarget):CallServer({
                            target = plr.Character
                        }) then
                            plr = nil
                        end
                    end
    
                    lastTarget = plr and plr.Character
                else
                    lastTarget = nil
                end
    
                task.wait(0.1)
            until not AutoKit.Enabled
        end,
        wizard = function()
            repeat
                local ability = lplr:GetAttribute('WizardAbility')
                if ability and bedwars.AbilityController:canUseAbility(ability) then
                    local plr = entitylib.EntityPosition({
                        Range = 50,
                        Part = 'RootPart',
                        Players = true,
                        Sort = sortmethods.Health
                    })
    
                    if plr then
                        bedwars.AbilityController:useAbility(ability, newproxy(true), {target = plr.RootPart.Position})
                    end
                end
    
                task.wait(0.1)
            until not AutoKit.Enabled
        end
    }
    
    AutoKit = vape.Categories.Utility:CreateModule({
        Name = 'Auto Kit',
        Function = function(callback)
            if callback then
                repeat task.wait() until store.equippedKit ~= '' and store.matchState ~= 0 or (not AutoKit.Enabled)
                if AutoKit.Enabled and AutoKitFunctions[store.equippedKit] and Toggles[store.equippedKit].Enabled then
                    AutoKitFunctions[store.equippedKit]()
                end
            end
        end,
        Tooltip = 'Automatically uses kit abilities.'
    })
    Legit = AutoKit:CreateToggle({Name = 'Legit Range'})
    local sortTable = {}
    for i in AutoKitFunctions do
        table.insert(sortTable, i)
    end
    table.sort(sortTable, function(a, b)
        return bedwars.BedwarsKitMeta[a].name < bedwars.BedwarsKitMeta[b].name
    end)
    for _, v in sortTable do
        Toggles[v] = AutoKit:CreateToggle({
            Name = bedwars.BedwarsKitMeta[v].name,
            Default = false
        })
    end
end)

run(function()
    local AutoLani
    local Delay
    local UseEnemy
    local Enemy
    local Player

    local Request = {SendToServer = function(self, ...) end}
    pcall(function()
    	Request = bedwars.Client:Get('PaladinAbilityRequest')
    end)

    AutoLani = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Lani',
    	Function = function(call)
    		if call then
    			local oldstart = 0

    			repeat
    				local start = (lplr:GetAttribute('PaladinStartTime') or 0)
    				if oldstart and oldstart ~= start then
    					local player = UseEnemy.Enabled and playersService:FindFirstChild(Enemy.Value)
    						or not UseEnemy.Enabled and playersService:FindFirstChild(Player.Value)
    						or nil

    					if player then
    						task.delay(Delay.Value, function()
    							Request:SendToServer({target = player})
    						end)
    					end
    				end
    				oldstart = start
    				task.wait(0.1)
    			until not AutoLani.Enabled
    		end
    	end,
    	Tooltip = 'Automatically uses the "scepter of light" ability'
    })

    local friends, enemies = {'None'}, {'None'}

    local function addConnection(plr)
    	if plr:GetAttribute('Team') == lplr:GetAttribute('Team') then
    		table.insert(friends, plr.Name)
    		Player:Change(friends)
    	elseif plr.Team and plr.Team.Name ~= 'Spectators' then
    		table.insert(enemies, plr.Name)
    		Enemy:Change(enemies)
    	end

    	plr:GetAttributeChangedSignal('Team'):Connect(function()
    		if plr:GetAttribute('Team') == lplr:GetAttribute('Team') then
    			table.insert(friends, plr.Name)
    			Player:Change(friends)
    		elseif plr.Team and plr.Team.Name ~= 'Spectators' then
    			table.insert(enemies, plr.Name)
    			Enemy:Change(enemies)
    		end
    	end)
    end

    Player = AutoLani:CreateDropdown({
    	Name = 'Selected Player',
    	List = {},
    	Tooltip = 'Player to use the ability on'
    })
    Enemy = AutoLani:CreateDropdown({
    	Name = 'Selected Enemy',
    	List = {},
    	Tooltip = 'Target to use the ability on',
    	Visible = false
    })
    UseEnemy = AutoLani:CreateToggle({
    	Name = 'Use enemy',
    	Function = function(call)
    		Enemy.Object.Visible = call
    		Player.Object.Visible = not call
    	end,
    	Tooltip = 'Uses the ability on other people instead of your teammates'
    })
    for _, v in playersService:GetPlayers() do
    	addConnection(v)
    end
    playersService.PlayerAdded:Connect(addConnection)
    Delay = AutoLani:CreateSlider({
    	Name = 'Delay',
    	Min = 1,
    	Max = 20,
    	Default = 5,
    	Suffix = function(val)
    		return val <= 1 and 'sec' or 'secs'
    	end,
    	Decimal = 10,
    	Tooltip = 'Delay between triggers'
    })
end)

run(function()
    local AutoLumen
    local Targets
    local Range
    local FullCharge
    local Delay

    local Balance = bedwars.LumenBalance or {MIN_CHARGE_TIME = 0.65, MAX_CHARGE_TIME = 1.25}
    local Sword = 'light_sword'
    local cooldown = 0

    local function getChargeTime()
        local itemmeta = bedwars.ItemMeta[Sword]
        local charged = itemmeta and itemmeta.sword and itemmeta.sword.chargedAttack
        local minimum = charged and charged.minChargeTimeSec or Balance.MIN_CHARGE_TIME
        local maximum = charged and charged.maxChargeTimeSec or Balance.MAX_CHARGE_TIME
        return FullCharge.Enabled and maximum or minimum
    end

    local function chargedSwing()
        local charge = bedwars.SwordChargeController
        if charge:getChargeState() ~= bedwars.ChargeState.Idle then return end

        charge:startCharging(Sword)
        local started = charge:getChargeStartTime()
        if started == 0 then return end

        local target = getChargeTime() + 0.05
        repeat task.wait() until not AutoLumen.Enabled or not entitylib.isAlive or (tick() - started) >= target

        local chargeTime = tick() - started
        charge:stopCharging(Sword)
        if not AutoLumen.Enabled or not entitylib.isAlive then return end

        local tool = store.hand.tool
        if not tool or tool.Name ~= Sword then return end

        local charged = bedwars.ItemMeta[Sword].sword.chargedAttack
        if not (charged.skipSwingDamage and chargeTime > (charged.minChargeTimeSec or Balance.MIN_CHARGE_TIME)) then
            bedwars.SwordController:swingSwordAtMouse(chargeTime)
        end

        bedwars.SyncEvents.SwordChargedSwing:fire(lplr, tool, {chargeTime = chargeTime})
        cooldown = tick() + Delay.Value
    end

    AutoLumen = vape.Categories.Kits:CreateModule({
        Name = 'AutoLumen',
        Function = function(callback)
            if callback then
                cooldown = 0

                repeat
                    if entitylib.isAlive and store.equippedKit == 'lumen' and store.hand.tool and store.hand.tool.Name == Sword and tick() >= cooldown then
                        local target = entitylib.EntityMouse({
                            Origin = entitylib.character.RootPart.Position,
                            Range = Range.Value,
                            Part = 'RootPart',
                            Players = Targets.Players.Enabled,
                            NPCs = Targets.NPCs.Enabled,
                            Wallcheck = Targets.Walls.Enabled
                        })

                        if target then
                            chargedSwing()
                        end
                    end
                    task.wait(0.1)
                until not AutoLumen.Enabled
            end
        end,
        Tooltip = 'Charges the sword of light and releases a wave whenever an enemy is in front of you, Killaura skips this sword because it has a charged attack'
    })
    Targets = AutoLumen:CreateTargets({
        Players = true,
        Walls = true
    })
    Range = AutoLumen:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 120,
        Default = 60,
        Suffix = function(val)
            return val <= 1 and 'stud' or 'studs'
        end
    })
    FullCharge = AutoLumen:CreateToggle({
        Name = 'Full charge',
        Default = true,
        Tooltip = 'Holds the swing to the maximum charge, an upgraded lumen only fires the multi beam at full charge'
    })
    Delay = AutoLumen:CreateSlider({
        Name = 'Delay',
        Min = 0,
        Max = 2,
        Default = 0.1,
        Decimal = 100,
        Suffix = 'seconds'
    })

end)

run(function()
    local AutoMarina
    local Range

    AutoMarina = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Marina',
    	Function = function(call)
    		if call then
    			local jellies = collection('jellyfish', AutoMarina, function(tab, obj)
    				task.delay(0, function()
    					if obj:GetAttribute('PlacedByUserId') == lplr.UserId then
    						table.insert(tab, obj)
    					end
    				end)
    			end)
    			repeat
    				if entitylib.isAlive and bedwars.AbilityController:canUseAbility('electrify_jellyfish') then
    					for _, v in jellies do
    						if v.PrimaryPart then
    							if
    								entitylib.EntityPosition({
    									Origin = v.PrimaryPart.Position,
    									Range = Range.Value,
    									Part = 'RootPart',
    									Players = true,
    								})
    							then
    								bedwars.AbilityController:useAbility('electrify_jellyfish')
    								break
    							end
    						end
    					end
    				end
    				task.wait(0.1)
    			until not AutoMarina.Enabled
    		end
    	end,
    	Tooltip = 'Automatically uses "electrify" ability when enemies are near jellies'
    })

    Range = AutoMarina:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 65,
    	Default = 50,
    	Suffix = function(val)
    		return val <= 1 and 'stud' or 'studs'
    	end,
    })
end)

run(function()
    local AutoMelody
    local Range
    local Interval
    local Angle
    local SelfHeal
    local TeammateHeal

    AutoMelody = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Melody',
    	Function = function(call)
    		if call then
    			repeat
    				local guitarItem = getItem('guitar')
    				local mag, hp, ent = Range.Value, math.huge, nil
    				if entitylib.isAlive then
    					local localPosition = entitylib.character.RootPart.Position
    					local localfacing = (gameCamera.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
    					for _, v in entitylib.List do
    						if v.Player and (SelfHeal.Enabled or v.Player ~= lplr) and (TeammateHeal.Enabled and v.Player:GetAttribute('Team') == lplr:GetAttribute('Team') or not TeammateHeal.Enabled and SelfHeal.Enabled and v.Player == lplr) then
    							local delta = v.RootPart.Position - localPosition
    							if math.acos(localfacing:Dot((delta * Vector3.new(1, 0, 1)).Unit)) > (math.rad(Angle.Value) / 2) then continue end
    							local newmag = delta.Magnitude
    							if newmag <= mag and v.Health < hp and v.Health < v.MaxHealth then
    								mag, hp, ent = newmag, v.Health, v
    							end
    						end
    					end
    				end

    				if ent and guitarItem then
    					local oldtool = store.hand.tool
    					local oldhotbar = store.inventory.hotbarSlot
    					local hotbar = getHotbar(guitarItem.tool)

    					if hotbar then
    						switchItem(guitarItem.tool)
    						hotbarSwitch(hotbar)
    					end

    					task.wait(0.05)

    					bedwars.Client:Get(remotes.GuitarHeal):SendToServer({
    						healTarget = ent.Character
    					})

    					task.spawn(function()
    						task.wait(0.1)
    						hotbarSwitch(oldhotbar)
    						if oldtool and oldtool.Parent then
    							switchItem(oldtool, 0)
    						end
    					end)
    				end

    				task.wait(Interval.Value)
    			until not AutoMelody.Enabled
    		end
    	end,
    	Tooltip = 'Automatically uses the guitar to heal ur teammates/urself'
    })

    SelfHeal = AutoMelody:CreateToggle({
    	Name = 'Self Heal',
    	Default = true
    })
    TeammateHeal = AutoMelody:CreateToggle({
    	Name = 'Teammate Heal',
    	Default = true
    })
    Range = AutoMelody:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 30,
    	Default = 30,
    	Decimal = 4
    })
    Interval = AutoMelody:CreateSlider({
    	Name = 'Interval',
    	Min = 1,
    	Max = 10,
    	Default = 1,
    	Suffix = function(val)
    		return 's'
    	end,
    })
    Angle = AutoMelody:CreateSlider({
    	Name = 'Max angle',
    	Min = 1,
    	Max = 360,
    	Default = 360
    })
end)

run(function()
    local AutoMetal
    local Limit
    local StreamerMode
    local Duration
    local Range
    local Animation

    local Delay = {}

    AutoMetal = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Metal',
    	Function = function(call)
    		if call then
    			AutoMetal:Clean(proximityPromptService.PromptShown:Connect(function(prompt)
    				if StreamerMode.Enabled then
    					if prompt.Name == 'hidden-metal-prompt' and (not Limit.Enabled or store.hand.tool and store.hand.tool.Name == 'metal_detector') then
    						task.wait(0.1)
    						prompt:InputHoldBegin()
    					end
    				end
    			end))

    			repeat
    				if not StreamerMode.Enabled and entitylib.isAlive then
    					local localPosition = entitylib.character.RootPart.Position
    					for i, v in collectionService:GetTagged('hidden-metal') do
    						if tick() > (Delay[v] or 0) and (localPosition - v.Part.Position).Magnitude <= Range.Value and (not Limit.Enabled or store.hand.tool and store.hand.tool.Name == 'metal_detector') then
    							if Duration.Value > 0 then
    								task.wait(Duration.Value)
    							end

    							if (localPosition - v.Part.Position).Magnitude <= Range.Value then
    								if Animation.Enabled then
    									bedwars.GameAnimationUtil:playAnimation(lplr.Character, bedwars.AnimationType.SHOVEL_DIG)
    									bedwars.SoundManager:playSound(bedwars.SoundList.SNAP_TRAP_CONSUME_MARK)
    								end
    								bedwars.Client:Get(remotes.PickupMetal):SendToServer({
    									id = v:GetAttribute('Id')
    								})
    								Delay[v] = tick() + 1
    							end
    						end
    					end
    				end
    				task.wait(0.1)
    			until not AutoMetal.Enabled
    		end
    	end,
    	Tooltip = 'Automatically uses the metal kit'
    })

    Limit = AutoMetal:CreateToggle({Name = 'Limit to item'})
    StreamerMode = AutoMetal:CreateToggle({
    	Name = 'Streamer mode',
    	Function = function(call)
    		pcall(function()
    			Duration.Object.Visible = not call
    			Range.Object.Visible = not call
    			Animation.Object.Visible = not call
    		end)
    	end,
    	Tooltip = 'Actually does the metal prompt thing for you'
    })
    Animation = AutoMetal:CreateToggle({
    	Name = 'Animation',
    	Default = true,
    	Tooltip = 'Plays the metal collect animation'
    })
    Range = AutoMetal:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 20,
    	Default = 12,
    	Suffix = function(val)
    		return val > 1 and 'studs' or 'stud'
    	end
    })
    Duration = AutoMetal:CreateSlider({
    	Name = 'Delay',
    	Min = 0,
    	Max = 1,
    	Suffix = function(val)
    		return val > 1 and 'secs' or 'sec'
    	end,
    	Default = 0.2,
    	Decimal = 5
    })
end)

run(function()
    local AutoNoelle
    local Notify
    local FrostySlime
    local HealSlime
    local StickySlime
    local VoidSlime
    local Limit

    local function getSlimes()
    	local slimes = {}
    	local folder = workspace:FindFirstChild('SlimeModelFolder')
    	for _, v in folder:GetChildren() do
    		local data = v:FindFirstChild('SlimeData')
    		data = data and data.Value or nil

    		if data and data.Tamer.Value == lplr.UserId then
    			table.insert(slimes, {
    				Data = data, 
    				RootPart = v, 
    				Name = v.Name:gsub(`_{lplr.Name}`, ''):gsub('Slime', ' Slime')
    			})
    		end
    	end
    	return slimes
    end

    local function getPlayer(name)
    	for _, v in playersService:GetPlayers() do
    		if (tostring(v.DisplayName)..' ('..tostring(v.Name)..')') == name then
    			return v
    		end
    	end
    	return
    end

    AutoNoelle = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Noelle',
    	Function = function(call)
    		if call then
    			repeat
    				if entitylib.isAlive and (not Limit.Enabled or store.hand.tool and store.hand.tool.Name == 'slime_tamer_flute') then
    					local slimes = getSlimes()

    					for _, v in slimes do
    						local dropdown = AutoNoelle.Options[tostring(v.Name)..' Target']
    						if dropdown then
    							local player = getPlayer(dropdown.Value)
    							if player and v.Data.Following.Value ~= player.UserId then
    								bedwars.Client:Get('RequestMoveSlime'):CallServerAsync({
    									slimeId = v.Data:GetAttribute('Id'),
    									targetPlayerUserId = player.UserId,
    								}):andThen(function(suc)
    									if suc then
    										v.Data.Following.Value = player.UserId
    										if Notify.Enabled then
    											notif('AutoNoelle', 'Directed '..tostring(v.Name)..' to '..tostring(player.DisplayName)..' ('..tostring(player.Name)..')', 5, 'info')
    										end
    									end
    								end)
    							end
    						end
    					end
    				end
    				task.wait(0.5)
    			until not AutoNoelle.Enabled
    		end
    	end,
    	Tooltip = 'Automatically directs the slimes to the selected player\'s'
    })

    local friends = { 'None' }

    local function addConnection(plr)
    	if plr:GetAttribute('Team') == lplr:GetAttribute('Team') then
    		table.insert(friends, tostring(plr.DisplayName)..' ('..tostring(plr.Name)..')')
    		FrostySlime:Change(friends)
    		HealSlime:Change(friends)
    		StickySlime:Change(friends)
    		VoidSlime:Change(friends)
    	end

    	vape:Clean(plr:GetAttributeChangedSignal('Team'):Connect(function()
    		if plr:GetAttribute('Team') == lplr:GetAttribute('Team') then
    			table.insert(friends, tostring(plr.DisplayName)..' ('..tostring(plr.Name)..')')
    			FrostySlime:Change(friends)
    			HealSlime:Change(friends)
    			StickySlime:Change(friends)
    			VoidSlime:Change(friends)
    		end
    	end))
    end

    Notify = AutoNoelle:CreateToggle({ Name = 'Notify on direct' })
    Limit = AutoNoelle:CreateToggle({ Name = 'Limit to item' })
    FrostySlime = AutoNoelle:CreateDropdown({
    	Name = 'Frosty Slime Target',
    	List = {},
    	Tooltip = 'Player to direct frost slimes to',
    })
    HealSlime = AutoNoelle:CreateDropdown({
    	Name = 'Heal Slime Target',
    	List = {},
    	Tooltip = 'Player to direct heal slimes to',
    })
    StickySlime = AutoNoelle:CreateDropdown({
    	Name = 'Sticky Slime Target',
    	List = {},
    	Tooltip = 'Player to direct sticky slimes to',
    })
    VoidSlime = AutoNoelle:CreateDropdown({
    	Name = 'Void Slime Target',
    	List = {},
    	Tooltip = 'Player to direct void slimes to',
    })

    for _, v in playersService:GetPlayers() do
    	addConnection(v)
    end
    vape:Clean(playersService.PlayerAdded:Connect(addConnection))
end)

run(function()
    local AutoNyx
    local Targets

    AutoNyx = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Nyx',
    	Function = function(call)
    		if call then
    			AutoNyx:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
    				if damageTable.damageType == 0 and damageTable.fromEntity and damageTable.fromEntity.Name == lplr.Name and entitylib.EntityPosition({
    					Range = 14.4,
    					Part = 'RootPart',
    					Players = Targets.Players.Enabled,
    					NPCs = Targets.NPCs.Enabled,
    				}) and bedwars.AbilityController:canUseAbility('midnight') then
    					bedwars.AbilityController:useAbility('midnight')
    				end
    			end))
    		end
    	end,
    	Tooltip = 'Automatically uses the "midnight" ability when meleeing a target'
    })

    Targets = AutoNyx:CreateTargets({
    	Players = true,
    	NPCs = false
    })
end)

run(function()
    local AutoPyro

    local list = {'Range', 'Heat', 'Power'}

    AutoPyro = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Pyro',
    	Function = function(call)
    		if call then
    			repeat
    				local flamethrower = getItem('flamethrower')
    				if flamethrower then
    					for _, v in list do
    						if not AutoPyro.Options['Buy ' .. v].Enabled then
    							table.remove(list, table.find(list, v))
    						end
    					end

    					for _, v in list do
    						v = v:lower()
    						local value = flamethrower.tool:GetAttribute(v) or -1
    						if value < 3 then
    							local nextUpgrade = bedwars.PyroUpgradeMeta[v].tiers[value + 2]
    							if nextUpgrade then
    								local currency = getItem(nextUpgrade.currency)
    								if currency and currency.amount >= nextUpgrade.price then
    									bedwars.Client:Get('UpgradeFlamethrower'):CallServer(v)
    									task.wait(0.1)
    								end
    							end
    						end
    					end
    				end
    				task.wait(0.1)
    			until not AutoPyro.Enabled
    		end
    	end,
    	Tooltip = 'Automatically upgrades flamethrower'
    })

    for _, i in list do
    	AutoPyro:CreateToggle({
    		Name = 'Buy ' .. i,
    		Default = true
    	})
    end
end)

run(function()
    local AutoRamil
    local Range
    local Sorts
    local Targets
    local UseTornando
    local TonradoRange

    AutoRamil = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Ramil',
    	Function = function(callback)
    		if callback then
    			repeat
    				if entitylib.isAlive and store.equippedKit == 'airbender' then
    					local localPosition = entitylib.character.RootPart.Position
    					local ent = entitylib.EntityPosition({
    						Origin = localPosition,
    						Range = (UseTornando.Enabled and TonradoRange.Value > Range.Value and TonradoRange.Value or Range.Value),
    						Wallcheck = Targets.Walls.Enabled,
    						Players = Targets.Players.Enabled,
    						NPCs = Targets.NPCs.Enabled,
    						Sort = sortmethods[Sorts.Value],
    					})

    					if ent then
    						if (localPosition - ent.RootPart.Position).Magnitude <= Range.Value and bedwars.AbilityController:canUseAbility('airbender_tornado') then
    							bedwars.AbilityController:useAbility('airbender_tornado')
    						end

    						if UseTornando.Enabled and (localPosition - ent.RootPart.Position).Magnitude <= TonradoRange.Value and bedwars.AbilityController:canUseAbility('airbender_moving_tornado') then
    							bedwars.AbilityController:useAbility('airbender_moving_tornado')
    						end
    					end
    				end
    				task.wait()
    			until not AutoRamil.Enabled
    		end
    	end,
    	Tooltip = 'Automatically uses the ramil kit'
    })

    Targets = AutoRamil:CreateTargets({
    	Players = true,
    	NPCs = false
    })
    local methods = {'Damage', 'Distance'}
    for i in sortmethods do
    	if not table.find(methods, i) then
    		table.insert(methods, i)
    	end
    end
    Sorts = AutoRamil:CreateDropdown({
    	Name = 'Target Mode',
    	List = methods,
    	Default = 'Distance'
    })
    Range = AutoRamil:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 25,
    	Default = 25,
    	Suffix = function(val)
    		return val >= 1 and 'studs' or 'stud'
    	end
    })
    UseTornando = AutoRamil:CreateToggle({
    	Name = 'Use Moving Tornado',
    	Function = function(call)
    		pcall(function()
    			TonradoRange.Object.Visible = call
    		end)
    	end
    })
    TonradoRange = AutoRamil:CreateSlider({
    	Name = 'Tornado Range',
    	Min = 1,
    	Max = 35,
    	Default = 25,
    	Darker = true,
    	Visible = false,
    	Suffix = function(val)
    		return val >= 1 and 'studs' or 'stud'
    	end
    })
end)

run(function()
	local AutoSheep
	local Delay
	local Range
	local Infinite
	
	AutoSheep = vape.Categories.Minigames:CreateModule({
		Name = 'AutoSheepHerder',
		Function = function(callback)
			if callback then
				local tameSheep = bedwars.Client:GetNamespace('SheepHerder'):Get('TameSheep')
	
				repeat
					local model = workspace:FindFirstChild('SheepModel')
					if entitylib.isAlive and model then
						local localPosition = entitylib.character.RootPart.Position
						for _, v in model:GetChildren() do
							if v.PrimaryPart and (Infinite.Enabled or (localPosition - v.PrimaryPart.Position).Magnitude <= Range.Value) then
								if Delay.Value > 0 then
									task.wait(Delay.Value)
								end
								tameSheep:SendToServer(v.SheepData.Value)
							end
						end
					end
					task.wait(0.1)
				until not AutoSheep.Enabled
			end
		end,
		Tooltip = 'Automatically tames sheep within range.'
	})
	Range = AutoSheep:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 200,
		Default = 20,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end
	})
	Infinite = AutoSheep:CreateToggle({
		Name = 'Infinite range',
		Tooltip = 'Tames every sheep on the map, the server may still reject far ones'
	})
	Delay = AutoSheep:CreateSlider({
		Name = 'Delay',
		Min = 0,
		Max = 1,
		Default = 0.1,
		Decimal = 100
	})
end)

run(function()
    local AutoStar
    local Streamer
    local Range
    local Animation
    local Delay

    AutoStar = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Star Collector',
    	Function = function(callback)
    		if callback then
    			AutoStar:Clean(proximityPromptService.PromptShown:Connect(function(prompt)
    				if Streamer.Enabled then
    					if prompt.Name == 'stars_ProximityPrompt' then
    						task.wait(0.1)
    						prompt:InputHoldBegin()
    					end
    				end
    			end))

    			repeat
    				if not Streamer.Enabled and entitylib.isAlive then
    					local localPosition = entitylib.character.RootPart.Position
    					for i, v in collectionService:GetTagged('stars') do
    						if
    							tick() > (Delay[v] or 0)
    							and v.PrimaryPart
    							and (localPosition - v.PrimaryPart.Position).Magnitude <= Range.Value
    						then
    							if Delay.Value > 0 then
    								task.wait(Delay.Value)
    							end

    							if (localPosition - v.PrimaryPart.Position).Magnitude <= Range.Value then
    								if Animation.Enabled then
    									bedwars.GameAnimationUtil:playAnimation(lplr.Character, bedwars.AnimationType.PUNCH)
    									bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_USE_ITEM)
    								end
    								bedwars.StarCollectorController:collectEntity(lplr, v, v.Name)
    								Delay[v] = tick() + 1
    							end
    						end
    					end
    				end
    				task.wait(0.1)
    			until not AutoStar.Enabled
    		end
    	end,
    	Tooltip = 'Automatically collects stars'
    })

    Streamer = AutoStar:CreateToggle({
    	Name = 'Streamer mode',
    	Function = function(call)
    		pcall(function()
    			Delay.Object.Visible = not call
    			Range.Object.Visible = not call
    			Animation.Object.Visible = not call
    		end)
    	end,
    	Tooltip = 'Useful for when ur screensharing'
    })
    Animation = AutoStar:CreateToggle({
    	Name = 'Animation',
    	Default = true,
    	Tooltip = 'Plays the collect animation'
    })
    Range = AutoStar:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 20,
    	Default = 12,
    	Suffix = function(val)
    		return val > 1 and 'studs' or 'stud'
    	end
    })
    Delay = AutoStar:CreateSlider({
    	Name = 'Delay',
    	Min = 0,
    	Max = 1,
    	Suffix = function(val)
    		return val > 1 and 'secs' or 'sec'
    	end,
    	Default = 0.2,
    	Decimal = 100
    })
end)

run(function()
    local AutoTaliyah
    local Emerald
    local Diamond
    local Iron
    local Amount

    local function getShopNPC()
    	local shop, items, upgrades, newid = nil, false, false, nil
    	if entitylib.isAlive then
    		local localPosition = entitylib.character.RootPart.Position
    		for _, v in store.shop do
    			if (v.RootPart.Position - localPosition).Magnitude <= 20 then
    				shop = v.Upgrades or v.Shop or nil
    				upgrades = upgrades or v.Upgrades
    				items = items or v.Shop
    				newid = v.Shop and v.Id or newid
    			end
    		end
    	end
    	return shop, items, upgrades, newid
    end

    AutoTaliyah = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Taliyah',
    	Tooltip = 'Automatically buy chickens when it sells for emerald',
    	Function = function(callback)
    		if callback then
    			repeat
    				local shopNpc, items, __, id = getShopNPC()
    				if shopNpc and items then
    					local chickenData = bedwars.TaliyahUtil:getPrice()
    					if (chickenData.currency == 'emerald' and Emerald.Enabled or chickenData.currency == 'iron' and Iron.Enabled or chickenData.currency == 'diamond' and Diamond.Enabled) and chickenData.price >= Amount.Value then
    						local item = bedwars.Shop.getShopItem('chicken_shop_item', lplr)

    						bedwars.Client:Get('BedwarsPurchaseItem'):CallServerAsync({
    							shopItem = item,
    							shopId = id
    						}):andThen(function(suc)
    							if suc then
    								bedwars.SoundManager:playSound(bedwars.SoundList.BEDWARS_PURCHASE_ITEM)
    								bedwars.Store:dispatch({
    									type = 'BedwarsAddItemPurchased',
    									itemType = item.itemType
    								})
    								bedwars.BedwarsShopController.alreadyPurchasedMap[item.itemType] = true
    							end
    						end)
    					end
    				end
    				task.wait(0.1)
    			until not AutoTaliyah.Enabled
    		end
    	end,
    })

    Iron = AutoTaliyah:CreateToggle({
    	Name = 'Iron',
    	Default = true,
    	Tooltip = 'Sells ur chicken when the currency is iron'
    })
    Emerald = AutoTaliyah:CreateToggle({
    	Name = 'Emerald',
    	Default = true,
    	Tooltip = 'Sells ur chicken when the currency is emerald'
    })
    Diamond = AutoTaliyah:CreateToggle({
    	Name = 'Diamond',
    	Default = true,
    	Tooltip = 'Sells ur chicken when the currency is diamond'
    })
    Amount = AutoTaliyah:CreateSlider({
    	Name = 'Amount',
    	Default = 2,
    	Min = 1,
    	Max = 1000,
    	Tooltip = 'Only sells if the currency is selling for the selected amount'
    })
end)

run(function()
    local AutoTriton
    local Legit
    local Back
    local BackDelay
    local Limit

    local rayCheck = RaycastParams.new()
    rayCheck.RespectCanCollide = true
    rayCheck.FilterType = Enum.RaycastFilterType.Include
    local projectileRemote = {InvokeServer = function(self, ...) end}
    task.spawn(function()
    	projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
    end)

    local function firePearl(pos, spot, item)
    	local hotbar, old = getHotbar(item.tool), store.hand

    	switchItem(item.tool)
    	if Legit.Enabled and hotbar then
    		hotbarSwitch(hotbar)
    	end

    	local meta = bedwars.ProjectileMeta.harpoon_projectile
    	local calc = prediction.SolveTrajectory(pos, meta.launchVelocity, meta.gravitationalAcceleration, spot, Vector3.zero, workspace.Gravity, 0, 0)
    	local landed = false

    	if calc then
    		local dir = CFrame.lookAt(pos, calc).LookVector * meta.launchVelocity
    		local projectile = bedwars.ProjectileController:createLocalProjectile(meta, 'harpoon_projectile', 'harpoon_projectile', pos, nil, dir, {drawDurationSeconds = 1})
    		local res = projectileRemote:InvokeServer(
    			item.tool,
    			'harpoon_projectile',
    			'harpoon_projectile',
    			pos,
    			pos,
    			dir,
    			httpService:GenerateGUID(true),
    			{
                    drawDurationSeconds = 1,
                    shotId = httpService:GenerateGUID(false)
                },
    			workspace:GetServerTimeNow() - 0.045
    		)
    		task.spawn(function()
    			repeat
    				task.wait()
    			until not projectile or not projectile.Parent
    			landed = true
    		end)
    		if res then
    			pcall(function()
    				res.Parent = replicatedStorage
    			end)
    		end
    	end

        repeat
            task.wait()
        until landed
    	if Back.Enabled and old and old.tool then
    		task.wait(BackDelay:GetRandomValue())
    		switchItem(old.tool)
    		if Legit.Enabled and getHotbar(old.tool) then
    			hotbarSwitch(getHotbar(old.tool))
    		end
    	end
    end

    local function findNearGround(origin)
    	for _, v in {Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1)} do
    		for i = 1, 24 do
    			local ray = workspace:Raycast((origin.Position + (Vector3.yAxis * 3)) + (v * i), Vector3.new(0, -60, 0), rayCheck)
    			if ray then
    				return ray.Position
    			end
    		end
    	end
    	return nil
    end

    AutoTriton = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Triton',
    	Function = function(callback)
    		if callback then
    			local check, lasty
    			repeat
    				if entitylib.isAlive and (not Limit.Enabled or store.hand.tool and store.hand.tool.Name == 'harpoon') then
    					local root = entitylib.character.RootPart
    					local pearl = getItem('harpoon')
    					rayCheck.FilterDescendantsInstances = {store.map}
    					rayCheck.CollisionGroup = root.CollisionGroup

    					if entitylib.character.Humanoid.FloorMaterial ~= Enum.Material.Air then
    						lasty = root.CFrame
    					end

    					if pearl and root.Velocity.Y < -60 and not workspace:Raycast(root.Position, Vector3.new(0, -200, 0), rayCheck) then
    						if not check then
    							check = true
    							local ground = findNearGround(root.CFrame + Vector3.new(0, 40, 0)) or findNearGround(lasty and lasty + Vector3.new(0, 5, 0) or root.CFrame)
    							if ground then
    								firePearl(root.Position, ground, pearl)
    							end
    						end
    					else
    						check = false
    					end
    				end
    				task.wait(0.1)
    			until not AutoTriton.Enabled
    		end
    	end,
    	Tooltip = 'Automatically throws triton trident onto nearby ground after\nfalling a certain distance.'
    })

    Legit = AutoTriton:CreateToggle({
    	Name = 'Legit Switch',
    	Tooltip = 'Visualizes the switching clientside',
    	Default = true
    })
    Back = AutoTriton:CreateToggle({
    	Name = 'Switch back',
    	Default = true,
    	Function = function(callback)
    		if BackDelay then
    			BackDelay.Object.Visible = callback
    		end
    	end,
    	Tooltip = 'Switches back to the last slot before pearl'
    })
    BackDelay = AutoTriton:CreateTwoSlider({
    	Name = 'Switch Back Delay',
    	Min = 0,
    	Max = 2,
    	DefaultMin = 0.1,
    	DefaultMax = 0.2,
    	Darker = true
    })
    Limit = AutoTriton:CreateToggle({
    	Name = 'Limit to item',
    	Tooltip = 'Only throws pearl when holding a pearl'
    })
end)

run(function()
    local AutoUma
    local Range
    local Limit
    local Animation
    local AutoSummon
    local HealSpirit
    local AttackSpirit
    local TargetItemDrops
    local Diamond
    local Emerald

    local function getAttackData()
    	if Limit.Enabled then
    		local tool = (store.hand.tool and store.hand.tool.Name == 'spirit_staff') and store.hand.tool or nil
    		return tool, tool and getHotbar(tool) or nil
    	end
    	for i, v in store.inventory.inventory.items do
    		if v.itemType == 'spirit_staff' then
    			switchItem(v, 0)
    			return v, i
    		end
    	end
    	return
    end

    local function getDrops(localPosition, ItemDrops)
    	local drop, lastmag = nil, Range.Value + 1
    	for i, v in ItemDrops do
    		if v.Name == 'emerald' and Emerald.Enabled or v.Name == 'diamond' and Diamond.Enabled then
    			local magnitude = (localPosition - v.Position).Magnitude
    			if magnitude <= lastmag and not entitylib.Wallcheck(localPosition, v.Position, {gameCamera, lplr.Character, v}) then
    				drop, lastmag = v, magnitude
    			end
    		end
    	end
    	return drop
    end

    AutoUma = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Uma',
    	Function = function(call)
    		if call then
    			repeat
    				local items = collection('ItemDrop', AutoUma)
    				local staff = getAttackData()
    				if staff then
    					if TargetItemDrops.Enabled then
    						local attackSpirits = (lplr:GetAttribute('ReadySummonedAttackSpirits') or 0)
    						local healSpirits = (lplr:GetAttribute('ReadySummonedHealSpirits') or 0)

    						if AutoSummon.Enabled then
    							if AttackSpirit.Enabled and attackSpirits < 1 and getItem('summon_stone') then
    								bedwars.AbilityController:useAbility('summon_attack_spirit')
    							end

    							if HealSpirit.Enabled and healSpirits < 1 and getItem('summon_stone') then
    								bedwars.AbilityController:useAbility('summon_heal_spirit')
    							end
    						end

    						if (healSpirits + attackSpirits) > 0 then
    							local localPosition = entitylib.character.RootPart.Position
    							local drop = getDrops(localPosition, items)

    							if drop then
    								local shootpos = localPosition + Vector3.new(0, 2, 0)
    								local dir = CFrame.lookAt(localPosition, drop.Position + Vector3.new(0, (localPosition - drop.Position).Magnitude / 5, 0)).LookVector * 100

    								bedwars.Client:Get(remotes.FireProjectile).instance:InvokeServer(
    									staff,
    									nil,
    									attackSpirits > 0 and 'attack_spirit' or 'heal_spirit',
    									shootpos,
    									localPosition,
    									dir,
    									httpService:GenerateGUID(),
    									{
    										drawDurationSeconds = 1,
    										shotId = httpService:GenerateGUID(false),
    									},
    									workspace:GetServerTimeNow() - 0.045
    								)

    								if Animation.Enabled then
    									bedwars.GameAnimationUtil:playAnimation(lplr.Character, bedwars.AnimationType.WIZARD_BALL_CAST)
    									bedwars.SoundManager:playSound(bedwars.SoundList.SPIRIT_SUMMONER_CHANGE_AFFINITY, {})
    								end

    								task.wait(1.5)
    							end
    						end
    					end
    				end
    				task.wait(0.1)
    			until not AutoUma.Enabled
    		end
    	end,
    	Tooltip = 'Automatically uses uma kit'
    })

    Range = AutoUma:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 80,
    	Default = 50,
    	Decimal = 5,
    	Suffix = function(val)
    		return val >= 2 and 'studs' or 'stud'
    	end
    })
    Animation = AutoUma:CreateToggle({
    	Name = 'Animation',
    	Default = true
    })
    Limit = AutoUma:CreateToggle({
    	Name = 'Limit to item',
    	Default = true
    })
    AutoSummon = AutoUma:CreateToggle({
    	Name = 'Auto Summon',
    	Function = function(call)
    		pcall(function()
    			AttackSpirit.Object.Visible = call
    			HealSpirit.Object.Visible = call
    		end)
    	end,
    	Tooltip = 'Automattically summons spirit for you'
    })
    HealSpirit = AutoUma:CreateToggle({
    	Name = 'Use heal spirit',
    	Default = true,
    	Visible = false,
    	Darker = true
    })
    AttackSpirit = AutoUma:CreateToggle({
    	Name = 'Use attack spirit',
    	Default = true,
    	Visible = false,
    	Darker = true
    })
    TargetItemDrops = AutoUma:CreateToggle({
    	Name = 'Target item drops',
    	Default = true,
    	Function = function(call)
    		pcall(function()
    			Emerald.Object.Visible = call
    			Diamond.Object.Visible = call
    		end)
    	end
    })
    Emerald = AutoUma:CreateToggle({
    	Name = 'Emerald',
    	Darker = true,
    	Default = true
    })
    Diamond = AutoUma:CreateToggle({
    	Name = 'Diamond',
    	Darker = true,
    	Default = true
    })
end)

run(function()
    local AutoWhisper
    local Heal
    local Threshold
    local Fly
    local Level

    AutoWhisper = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Whisper',
    	Function = function(callback)
    		if callback then
    			local lowestpoint = math.huge
    			repeat
    				task.wait()
    			until store.matchState ~= 0 or not AutoWhisper.Enabled
    			if not AutoWhisper.Enabled then
    				return
    			end

    			for _, v in store.blocks do
    				local point = (v.Position.Y - (v.Size.Y / 2)) - 50
    				if point < lowestpoint then
    					lowestpoint = point
    				end
    			end

    			repeat
    				local liftReady = Fly.Enabled and (workspace:GetServerTimeNow() - (lplr:GetAttribute('OwlLiftReadyTime') or 0)) > 0
    				local healReady = Heal.Enabled and (workspace:GetServerTimeNow() - (lplr:GetAttribute('OwlHealReadyTime') or 0)) > 0

    				if liftReady or healReady then
    					for _, v in collectionService:GetTagged('Owl') do
    						if v:GetAttribute('Owner') == lplr.UserId then
    							local plr = playersService:GetPlayerByUserId(v:GetAttribute('Target'))
    							if plr then
    								if liftReady and plr.Character.HumanoidRootPart.Velocity.Y < -10 then
    									if plr.Character.HumanoidRootPart.Position.Y < lowestpoint then
    										bedwars.AbilityController:useAbility('OWL_LIFT')
    									end
    								end
    								if healReady and (Threshold.Value >= 100 or (plr.Character:GetAttribute('Health') / plr.Character:GetAttribute('MaxHealth')) <= (Threshold.Value / 100)) then
    									bedwars.AbilityController:useAbility('OWL_HEAL')
    								end
    							end
    							break
    						end
    					end
    				end
    				task.wait(0.1)
    			until not AutoWhisper.Enabled
    		end
    	end,
    	Tooltip = 'Automatically uses whisper abilities'
    })

    Heal = AutoWhisper:CreateToggle({
    	Name = 'Heal',
    	Default = true,
    	Function = function(call)
    		if Threshold then
    			Threshold.Object.Visible = call
    		end
    	end
    })
    Threshold = AutoWhisper:CreateSlider({
    	Name = 'Health',
    	Min = 1,
    	Max = 100,
    	Default = 99,
    	Suffix = '%',
    	Darker = true
    })
    Fly = AutoWhisper:CreateToggle({
    	Name = 'Fly',
    	Default = true,
    	Function = function(call)
    		if Level then
    			Level.Object.Visible = call
    		end
    	end
    })
    Level = AutoWhisper:CreateSlider({
    	Name = 'Level',
    	Min = 1,
    	Max = 100,
    	Default = 100,
    	Suffix = function(val)
    		return val <= 1 and 'stud' or 'studs'
    	end
    })
end)

run(function()
    local AutoZeno
    local Targets
    local TargetMode
    local Limit
    local AutoShockWave
    local ShockwaveRange
    local UseStrike
    local UseStorm
    local Range
    local Delay

    local function getAttackData()
    	if Limit.Enabled then
    		local tool = (store.hand.tool and store.hand.tool.Name:find('wizard_staff')) and store.hand.tool or nil
    		return tool, tool and getHotbar(tool) or nil, tool and (tonumber(tool.Name:sub(#tool.Name, #tool.Name)) or 1) or nil
    	end

    	for i, v in store.inventory.inventory.items do
    		if v.itemType:find('wizard_staff') then
    			switchItem(v, 0)
    			return v, i, tonumber(v.itemType:sub(#v.itemType, #v.itemType)) or 1
    		end
    	end

    	return
    end

    AutoZeno = vape.Categories.Kits:CreateModule({
    	Name = 'Auto Zeno',
    	Function = function(call)
    		if call then
    			repeat
    				if entitylib.isAlive then
    					local staff, __, level = getAttackData()

    					if staff then
    						local localPosition = entitylib.character.RootPart.Position
    						local ent = entitylib.EntityPosition({
    							Origin = localPosition,
    							Range = (Range.Value < 6 and AutoShockWave.Enabled and 7) or Range.Value,
    							Part = 'RootPart',
    							Players = Targets.Players.Enabled,
    							NPCs = Targets.NPCs.Enabled,
    							Sort = sortmethods[TargetMode.Value],
    						})

    						if ent then
    							if AutoShockWave.Enabled and level > 2 then
    								if
    									bedwars.AbilityController:canUseAbility('SHOCKWAVE')
    									and (localPosition - ent.RootPart.Position).Magnitude <= ShockwaveRange.Value
    								then
    									bedwars.AbilityController:useAbility('SHOCKWAVE', newproxy(true), {
    										target = CFrame.lookAt(localPosition, ent.RootPart.Position).LookVector,
    									})
    									task.wait(Delay.Value)
    								end
    							end

    							if UseStrike.Enabled and bedwars.AbilityController:canUseAbility('LIGHTNING_STRIKE') then
    								bedwars.AbilityController:useAbility('LIGHTNING_STRIKE', newproxy(true), {
    									target = ent.RootPart.Position + ((ent.Humanoid.MoveDirection or Vector3.zero) * (1 + lplr:GetNetworkPing())),
    								})
    								task.wait(Delay.Value)
    							end

    							if UseStorm.Enabled and level > 1 then
    								if bedwars.AbilityController:canUseAbility('LIGHTNING_STORM') then
    									bedwars.AbilityController:useAbility('LIGHTNING_STORM', newproxy(true), {
    										target = ent.RootPart.Position + ((ent.Humanoid.MoveDirection or Vector3.zero) * (1 + lplr:GetNetworkPing())),
    									})
    									task.wait(Delay.Value)
    								end
    							end
    						end
    					end
    				end
    				task.wait(0.1)
    			until not AutoZeno.Enabled
    		end
    	end,
    	Tooltip = 'Automatically uses zeno\'s staff'
    })

    Targets = AutoZeno:CreateTargets({
    	Players = true,
    	NPCs = false,
    })
    local methods = {'Damage', 'Distance'}
    for i in sortmethods do
    	if not table.find(methods, i) then
    		table.insert(methods, i)
    	end
    end
    TargetMode = AutoZeno:CreateDropdown({
    	Name = 'Target Mode',
    	List = methods,
    	Default = 'Distance'
    })
    Limit = AutoZeno:CreateToggle({
    	Name = 'Limit to item',
    	Default = true
    })
    UseStrike = AutoZeno:CreateToggle({
    	Name = 'Use Lightning Strike',
    	Default = true
    })
    UseStorm = AutoZeno:CreateToggle({Name = 'Use Lightning Storm'})
    AutoShockWave = AutoZeno:CreateToggle({
    	Name = 'Auto Shockwave',
    	Function = function(call)
    		pcall(function()
    			ShockwaveRange.Object.Visible = call
    		end)
    	end,
    	Tooltip = 'Automatically uses the shockwave ability when a target is near',
    })
    ShockwaveRange = AutoZeno:CreateSlider({
    	Name = 'Shockwave Range',
    	Visible = false,
    	Darker = true,
    	Min = 1,
    	Max = 12,
    	Suffix = function(val)
    		return val > 1 and 'studs' or 'stud'
    	end,
    	Decimal = 5,
    	Default = 12
    })
    Range = AutoZeno:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 60,
    	Default = 35,
    	Suffix = function(val)
    		return val > 1 and 'studs' or 'stud'
    	end,
    	Decimal = 5
    })
    Delay = AutoZeno:CreateSlider({
    	Name = 'Delay',
    	Min = 0,
    	Max = 10,
    	Default = 0.5,
    	Decimal = 5,
    	Suffix = function(val)
    		return val > 1 and 'secs' or 'sec'
    	end
    })
end)

run(function()
	local DaveyAim
	local Mode
	local Position
	local Range
	local LaunchCannon
	local ShowTarget
	
	local rayCheck = RaycastParams.new()
	rayCheck.RespectCanCollide = true
	
	local function getLaunchVelocity(delta, velocity, time)
		return (delta + Vector3.new(0, workspace.Gravity * time * time * 0.5, 0)) / time - velocity
	end
	
	local function getCannon()
		local cannons = {}
		local localPosition = entitylib.character.RootPart.Position
		for _, v in store.blocks do
			if v.Name == 'cannon' and (localPosition - v.Position).Magnitude <= Range.Value then
				table.insert(cannons, v)
			end
		end
		if #cannons > 1 then
			table.sort(cannons, function(a, b)
				return (localPosition - a.Position).Magnitude < (localPosition - b.Position).Magnitude
			end)
		end
		return cannons[1] or nil
	end
	
	local function isPathBlocked(origin, velocity, time)
		local previous = origin
	
		for i = 1, 11 do
			local elapsed = time * i / 12
			local point = origin + velocity * elapsed - Vector3.new(0, workspace.Gravity * elapsed * elapsed * 0.5, 0)
			if workspace:Spherecast(previous, 2, point - previous, rayCheck) then
				return true
			end
			previous = point
		end
	
		return false
	end
	
	local function getLaunchTime(origin, delta, velocity, ceiling)
		local low, up = 0.0001, 20
	
		for _ = 1, 50 do
			local first, second = low + (up - low) / 3, up - (up - low) / 3
			if getLaunchVelocity(delta, velocity, first).Magnitude < getLaunchVelocity(delta, velocity, second).Magnitude then
				up = second
			else
				low = first
			end
		end
	
		local middle = (low + up) / 2
		if getLaunchVelocity(delta, velocity, middle).Magnitude > ceiling then return end
		if not isPathBlocked(origin, getLaunchVelocity(delta, Vector3.zero, middle), middle) then return middle end
	
		for i = 1, 20 do
			for _, time in {middle * (1 + i * 0.15), middle * (1 - i * 0.045)} do
				if getLaunchVelocity(delta, velocity, time).Magnitude <= ceiling and not isPathBlocked(origin, getLaunchVelocity(delta, Vector3.zero, time), time) then
					return time
				end
			end
		end
	
		return middle
	end
	
	local function makeVisual(target, blockPosition)
		local part = Instance.new('Part')
		part.Size = Vector3.new(3, 3, 3)
		part.CFrame = CFrame.new(blockPosition)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		local selection = Instance.new('SelectionBox')
		selection.Adornee = part
		selection.LineThickness = 0.04
		selection.Color3 = Color3.new(1, 1, 1)
		selection.SurfaceColor3 = Color3.new(1, 1, 1)
		selection.SurfaceTransparency = 0.75
		selection.Parent = part
		local tagSize = getfontsize('Landing (000 studs)', 14, uipallet.Font, Vector2.new(100000, 100000))
		local billboard = Instance.new('BillboardGui')
		billboard.Name = 'Tag'
		billboard.Size = UDim2.fromOffset(tagSize.X + 8, tagSize.Y + 7)
		billboard.StudsOffsetWorldSpace = (target - blockPosition) + Vector3.new(0, 2, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = part
		local tag = Instance.new('TextLabel')
		tag.Size = billboard.Size
		tag.BackgroundColor3 = Color3.new()
		tag.BackgroundTransparency = 0.5
		tag.BorderSizePixel = 0
		tag.RichText = true
		tag.FontFace = uipallet.Font
		tag.TextSize = 14
		tag.TextColor3 = Color3.new(1, 1, 1)
		tag.Parent = billboard
		bedwars.QueryUtil:setQueryIgnored(part, true)
		part.Parent = gameCamera
		return part
	end
	
	local function aimCannon(cannon, direction)
		local blockPosition = bedwars.BlockController:getBlockPosition(cannon.Position)
		local aimed
		local timeout = tick() + 1
	
		repeat
			bedwars.Handler:Get('AimCannon'):Fire('SendToServer', {
				cannonBlockPos = blockPosition,
				lookVector = direction
			})
			task.wait(0.15)
			local look = cannon:GetAttribute('LookVector')
			aimed = look and (look - direction).Magnitude < 0.0001
		until aimed or tick() > timeout or not cannon.Parent
	
		return aimed
	end
	
	DaveyAim = vape.Categories.Minigames:CreateModule({
		Name = 'DaveyAim',
		Function = function(callback)
			if callback then
				DaveyAim:Toggle()
				if not entitylib.isAlive then return end
	
				local cannon = getCannon()
				if not cannon then
					notif('DaveyAim', 'No cannon in range.', 5, 'warning')
					return
				end
	
				local mouseRay = cloneref(lplr:GetMouse()).UnitRay
				local origin = Position.Value == 'Camera' and gameCamera.CFrame.Position or mouseRay.Origin
				local direction = Position.Value == 'Camera' and gameCamera.CFrame.LookVector or mouseRay.Direction
				rayCheck.FilterDescendantsInstances = {lplr.Character, gameCamera, cannon}
				local ray = workspace:Raycast(origin, direction * 10000, rayCheck)
				if not ray then
					notif('DaveyAim', 'No position found.', 5, 'warning')
					return
				end
	
				local localPosition = entitylib.character.RootPart.Position
				local target = ray.Position + Vector3.new(0, entitylib.character.HipHeight, 0)
				local velocity = entitylib.character.RootPart.AssemblyLinearVelocity
				if (target - localPosition).Magnitude > 300 then
					notif('DaveyAim', `Too far away ({math.floor((target - localPosition).Magnitude)} studs away, 300 max).`, 5, 'warning')
					return
				end
	
				local time = getLaunchTime(localPosition, target - localPosition, velocity, math.sqrt(320 * workspace.Gravity))
				if not time then
					notif('DaveyAim', `Out of cannon range ({math.floor((target - localPosition).Magnitude)} studs away, 300 max).`, 5, 'warning')
					return
				end
	
				local launchDirection = getLaunchVelocity(target - localPosition, velocity, time).Unit
				local blockPosition = bedwars.BlockController:getBlockPosition(cannon.Position)
				local visual = ShowTarget.Enabled and makeVisual(target, roundPos(ray.Position - ray.Normal * 1.5)) or nil
				if visual then
					visual.Tag.TextLabel.Text = `Landing ({math.floor((target - localPosition).Magnitude)} studs)`
				end
	
				if Mode.Value == 'Legit' then
					cannon.AimPrompt:InputHoldBegin()
					task.wait(cannon.AimPrompt.HoldDuration)
	
					local timeout = tick() + 0.3
					repeat
						gameCamera.CFrame = gameCamera.CFrame:Lerp(CFrame.lookAt(gameCamera.CFrame.Position, gameCamera.CFrame.Position + launchDirection), 22 * runService.PostSimulation:Wait())
						bedwars.Handler:Get('AimCannon'):Fire('SendToServer', {
							cannonBlockPos = blockPosition,
							lookVector = gameCamera.CFrame.LookVector
						})
					until tick() > timeout
				end
	
				if not aimCannon(cannon, launchDirection) then
					notif('DaveyAim', 'Cannon refused the aim.', 5, 'warning')
					if visual then
						visual:Destroy()
					end
					return
				end
	
				if Mode.Value == 'Legit' then
					cannon.StopAimingPrompt:InputHoldBegin()
				end
				task.wait((cannon.StopAimingPrompt.HoldDuration + (0.2 + store.ping.total)) + runService.PostSimulation:Wait())
	
				if LaunchCannon.Enabled then
					if Mode.Value == 'Legit' then
						cannon.LaunchSelfPrompt:InputHoldBegin()
						task.wait(cannon.LaunchSelfPrompt.HoldDuration + runService.PostSimulation:Wait())
					else
						bedwars.CannonHandController:launchSelf(cannon)
					end
				else
					local launched, aimed = false, true
					local connection = cannon.LaunchSelfPrompt.Triggered:Connect(function(plr)
						if plr == lplr then
							launched = true
						end
					end)
					local timeout = tick() + 30
	
					repeat
						runService.PostSimulation:Wait()
						local look = cannon.Parent and cannon:GetAttribute('LookVector')
						aimed = look and (look - launchDirection).Magnitude < 0.0001
					until launched or not aimed or tick() > timeout or not entitylib.isAlive
	
					connection:Disconnect()
					if not launched then
						if not aimed then
							notif('DaveyAim', 'Cannon was re-aimed before you launched.', 5, 'warning')
						end
						if visual then
							visual:Destroy()
						end
						return
					end
				end
	
				local landing = tick() + time
				local root
				repeat
					runService.PreSimulation:Wait()
					root = entitylib.isAlive and entitylib.character.RootPart
					if root then
						local remaining = landing - tick()
						if remaining > 0.1 then
							root.AssemblyLinearVelocity = getLaunchVelocity(target - root.Position, Vector3.zero, remaining)
						end
						if visual then
							visual.Tag.TextLabel.Text = `Landing ({math.floor((target - root.Position).Magnitude)} studs)`
						end
					end
				until not root or tick() > landing
	
				if visual then
					visual:Destroy()
				end
			end
		end,
		Tooltip = 'Aims a nearby cannon at your cursor and launches you onto it'
	})
	Mode = DaveyAim:CreateDropdown({
		Name = 'Aim Mode',
		List = {'Blatant', 'Legit'},
		Default = 'Blatant'
	})
	Position = DaveyAim:CreateDropdown({
		Name = 'Position Mode',
		List = {'Mouse', 'Camera'},
		Default = 'Mouse'
	})
	Range = DaveyAim:CreateSlider({
		Name = 'Search Range',
		Min = 1,
		Max = 18,
		Default = 10,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end
	})
	LaunchCannon = DaveyAim:CreateToggle({
		Name = 'Launch Cannon',
		Default = true,
		Tooltip = 'Launches you itself, turn this off to aim only and still land on target when you launch yourself'
	})
	ShowTarget = DaveyAim:CreateToggle({
		Name = 'Show Target',
		Default = true,
		Tooltip = 'Highlights the block you are landing on until you land'
	})
end)

run(function()
	local CannonSpeed
	local Value
	
	CannonSpeed = vape.Categories.Blatant:CreateModule({
		Name = 'CannonSpeed',
		Function = function(callback)
			debug.setconstant(bedwars.CannonHandController.launchSelf, 15, callback and Value.Value or 200)
		end,
		Tooltip = 'Makes you go faster with cannon.'
	})
	Value = CannonSpeed:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 400,
		Default = 200,
		Function = function(val)
			if CannonSpeed.Enabled then
				debug.setconstant(bedwars.CannonHandController.launchSelf, 15, val)
			end
		end,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end
	})
	CannonSpeed:CreateButton({
		Name = 'Sync to legit speed',
		Function = function()
			Value:SetValue(200)
		end
	})
end)

run(function()
    local FishermanSpy
    local Teammates

    FishermanSpy = vape.Categories.Kits:CreateModule({
    	Name = 'Fisherman Spy',
    	Function = function(call)
    		if call then
    			FishermanSpy:Clean(bedwars.Client:Get('FishCaught'):Connect(function(data)
    				if data.dropData and data.dropData.drops and data.catchingPlayer then
    					local text = {}
    					for _, v in data.dropData.drops do
    						local itemDisplay = bedwars.ItemMeta[v.itemType] and bedwars.ItemMeta[v.itemType].displayName or v.itemType
    						table.insert(text, tostring(v.amount)..' '..tostring(itemDisplay:lower())..(v.amount >= 2 and 's' or ''))
    					end

    					if #text > 0 and (not Teammates.Enabled or lplr.Team ~= data.catchingPlayer.Team) then
    						notif('FishermanSpy', tostring(data.catchingPlayer.Name)..' caught '..table.concat(text, ', '), 20, 'info')
    					end
    				end
    			end))
    		end
    	end
    })

    Teammates = FishermanSpy:CreateToggle({
    	Name = 'Ignore teammate',
    	Default = true
    })
end)

run(function()
    local old

    vape.Categories.Kits:CreateModule({
    	Name = 'Infinite Krystal',
    	Tooltip = 'Gives you max momentum forever',
    	Function = function(call)
    		if call then
    			old = bedwars.GlacialSkaterController.updateMomentum
    			bedwars.GlacialSkaterController.updateMomentum = function(self, ...)
    				self.momentum = 9e9
    				self.lastMomentumReport = 9e9
    				return old(self, ...)
    			end
    		else
    			bedwars.GlacialSkaterController.updateMomentum = old
    		end
    	end
    })
end)

run(function()
    local SigridExploit
    local Kit, Mount = 'elk_master', bedwars.Client:Get('ElkKitMounted')

    SigridExploit = vape.Categories.Kits:CreateModule({
    	Name = 'Infinite Sigrid',
    	Tooltip = 'Lets you ride in the elk forever',
    	Function = function(call)
    		if call then
    			repeat
    				if entitylib.isAlive then
    					if store.equippedKit == Kit then
    						Mount:SendToServer()
    					end
    				end
    				task.wait()
    			until not SigridExploit.Enabled
    		end
    	end
    })
end)

run(function()
    local AutoPickpocket
    local Targets
    local Range
    
    AutoPickpocket = vape.Categories.Kits:CreateModule({
        Name = 'Auto Pickpocket',
        Function = function(callback)
            if callback then
                repeat
                    if entitylib.isAlive and store.equippedKit == 'mimic' then
                        local localPosition = entitylib.character.RootPart.Position
                        local plrs = entitylib.AllPosition({
                            Range = Range.Value,
                            Origin = localPosition,
                            Wallcheck = Targets.Walls.Enabled or nil,
                            Part = 'RootPart',
                            Players = true,
                            Sort = sortmethods.Distance
                        })
                        for _, v in plrs do
                            if bedwars.Client:Get('MimicBlockPickPocketPlayer'):CallServer(v.Player) then
                                bedwars.SoundManager:playSound(bedwars.SoundList[({bedwars.SoundList.MIMIC_PICKPOCKET_1, bedwars.SoundList.MIMIC_PICKPOCKET_2, bedwars.SoundList.MIMIC_PICKPOCKET_3})[math.random(1, 3)]], {
                                    playbackSpeedMultiplier = 1.27,
                                    position = localPosition
                                })
                            end
                        end
                    end
                    task.wait(0.1)
                until not AutoPickpocket.Enabled
            end
        end,
        Tooltip = 'Automatically pickpockets with milo kit.'
    })
    
    Targets = AutoPickpocket:CreateTargets({Players = true, Walls = true})
    Range = AutoPickpocket:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 30,
        Default = 25,
        Suffix = function(val)
            return val <= 1 and 'stud' or 'studs'
        end
    })
end)

run(function()
    local HephaestusKit
    local AutoRepair
    local Threshold
    local AntiAttackBlock

    local COOLDOWN = 6
    -- Hardcoded candidates covering every known naming convention
    local ABILITY_NAMES = {
        'hephaestus_self_repair', 'tinker_self_repair',
        'hephaestus_repair', 'tinker_repair',
        'HEPHAESTUS_SELF_REPAIR', 'TINKER_SELF_REPAIR',
        'HEPHAESTUS_REPAIR', 'TINKER_REPAIR',
        'self_repair', 'SELF_REPAIR',
        'shield_repair', 'SHIELD_REPAIR',
        'kit_repair', 'KIT_REPAIR',
        'forge_repair', 'FORGE_REPAIR',
    }

    -- Read any Shield_* attributes (potion excluded) from the character
    local function getKitShield(char)
        local total = 0
        for name, val in char:GetAttributes() do
            if name:find('Shield') and type(val) == 'number' and val > 0 and name ~= 'Shield_POTION' then
                total = total + val
            end
        end
        return total
    end

    -- Scan AbilityController's own fields AND method upvalues for any key containing 'repair'
    local function discoverRepairAbilities()
        local found = {}
        pcall(function()
            local ac = bedwars.AbilityController
            -- Direct field scan (Flamework stores state on the object)
            for _, v in next, ac do
                if type(v) ~= 'table' then continue end
                for k in next, v do
                    if type(k) == 'string' and k:lower():find('repair') and not table.find(found, k) then
                        table.insert(found, k)
                    end
                end
            end
            -- Method upvalue scan
            for _, fn in {ac.canUseAbility, ac.useAbility, ac.getAbilityCooldown, ac.registerAbility} do
                if type(fn) ~= 'function' then continue end
                for i = 1, 40 do
                    local ok, _, val = pcall(debug.getupvalue, fn, i)
                    if not ok then break end
                    if type(val) ~= 'table' then continue end
                    for k in next, val do
                        if type(k) == 'string' and k:lower():find('repair') and not table.find(found, k) then
                            table.insert(found, k)
                        end
                    end
                end
            end
        end)
        return found
    end

    -- Also check character/player attributes for ability names (like wizard's 'WizardAbility' attr)
    local function getCharAbilityName()
        local char = lplr.Character
        if char then
            for _, obj in {char, lplr} do
                for attrName, attrVal in obj:GetAttributes() do
                    if type(attrVal) == 'string' and attrVal:lower():find('repair') then
                        return attrVal
                    end
                end
            end
        end
        return nil
    end

    local function fireRepair()
        local ac = bedwars.AbilityController
        local names = discoverRepairAbilities()
        local charAbility = getCharAbilityName()
        if charAbility and not table.find(names, charAbility) then
            table.insert(names, 1, charAbility)
        end
        for _, n in ABILITY_NAMES do
            if not table.find(names, n) then table.insert(names, n) end
        end
        for _, name in names do
            local ok, canUse = pcall(function() return ac:canUseAbility(name) end)
            if ok and canUse then
                pcall(function() ac:useAbility(name) end)
                return true
            end
        end
        return false
    end

    -- Find weapon config (has .Weapon table with respectAttackOverride).
    -- Use pcall + normal field access to handle TypeScript __index-based tables.
    local weaponConfig = nil
    pcall(function()
        local swc = bedwars.SwordController
        for _, fn in {swc.sendServerRequest, swc.swingSwordAtMouse, swc.swingSwordInRegion, swc.isClickingTooFast} do
            if type(fn) ~= 'function' then continue end
            for i = 1, 40 do
                local ok2, weapon, ok3
                local ok, _, val = pcall(debug.getupvalue, fn, i)
                if not ok then break end
                if type(val) ~= 'table' then continue end
                ok2, weapon = pcall(function() return val.Weapon end)
                if not ok2 or type(weapon) ~= 'table' then continue end
                ok3 = pcall(function() return weapon.respectAttackOverride end)
                if ok3 then weaponConfig = val; return end
            end
        end
    end)

    local oldIsClickingTooFast = bedwars.SwordController.isClickingTooFast
    local syncConn = nil
    local stunConn = nil
    local charConn = nil

    local function connectStunClear(char)
        if stunConn then stunConn:Disconnect(); stunConn = nil end
        if not char then return end
        -- Only fires when StunnedUntilTime actually changes, not 60fps spam
        stunConn = char:GetAttributeChangedSignal('StunnedUntilTime'):Connect(function()
            if not AntiAttackBlock or not AntiAttackBlock.Enabled then return end
            local val = char:GetAttribute('StunnedUntilTime')
            if val and val > workspace:GetServerTimeNow() then
                pcall(function() char:SetAttribute('StunnedUntilTime', 0) end)
            end
        end)
    end

    HephaestusKit = vape.Categories.Kits:CreateModule({
        Name = 'Hephaestus Kit',
        Function = function(callback)
            if callback then
                bedwars.SwordController.isClickingTooFast = function(self, ...)
                    if AntiAttackBlock and AntiAttackBlock.Enabled then
                        if weaponConfig then
                            pcall(function() weaponConfig.Weapon.respectAttackOverride = false end)
                        end
                        return false
                    end
                    return oldIsClickingTooFast(self, ...)
                end
                -- React to stun events only (not every frame) to avoid movement freeze
                connectStunClear(lplr.Character)
                charConn = lplr.CharacterAdded:Connect(function(char)
                    connectStunClear(char)
                end)
                -- MartinSpeed pattern: hook SwordSwing sync event at high priority
                pcall(function()
                    local sync = bedwars.ClientSync
                    if sync and type(sync.SwordSwing) == 'table' and type(sync.SwordSwing.setPriority) == 'function' then
                        syncConn = sync.SwordSwing:setPriority(1):Connect(function()
                            if AntiAttackBlock and AntiAttackBlock.Enabled and weaponConfig then
                                pcall(function() weaponConfig.Weapon.respectAttackOverride = false end)
                            end
                        end)
                    end
                end)
            else
                bedwars.SwordController.isClickingTooFast = oldIsClickingTooFast
                if stunConn then stunConn:Disconnect(); stunConn = nil end
                if charConn then charConn:Disconnect(); charConn = nil end
                if syncConn then
                    pcall(function() syncConn:Disconnect() end)
                    syncConn = nil
                end
            end
            if callback then
                local maxShield = 0
                local lastFired = 0

                local frame = Instance.new('Frame')
                frame.Size = UDim2.fromOffset(160, 20)
                frame.Position = UDim2.new(0.5, -80, 1, -56)
                frame.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
                frame.BackgroundTransparency = 0.2
                frame.BorderSizePixel = 0
                frame.Parent = vape.gui
                Instance.new('UICorner', frame).CornerRadius = UDim.new(1, 0)

                local stroke = Instance.new('UIStroke', frame)
                stroke.Color = Color3.fromRGB(100, 200, 255)
                stroke.Thickness = 1

                local dot = Instance.new('Frame')
                dot.Size = UDim2.fromOffset(6, 6)
                dot.Position = UDim2.new(0, 7, 0.5, -3)
                dot.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
                dot.BorderSizePixel = 0
                dot.Parent = frame
                Instance.new('UICorner', dot).CornerRadius = UDim.new(1, 0)

                local label = Instance.new('TextLabel')
                label.Size = UDim2.new(1, -18, 1, 0)
                label.Position = UDim2.fromOffset(18, 0)
                label.BackgroundTransparency = 1
                label.TextColor3 = Color3.new(1, 1, 1)
                label.TextSize = 11
                label.Font = Enum.Font.Gotham
                label.TextXAlignment = Enum.TextXAlignment.Left
                label.Text = 'Ready'
                label.Parent = frame

                local function setState(text, color)
                    label.Text = text
                    label.TextColor3 = color
                    dot.BackgroundColor3 = color
                    stroke.Color = color
                end

                local prevAlive = false  -- sentinel: detect spawn moment to capture true max shield

                repeat
                    local alive, char, current, now, cooldownLeft, needsRepair
                    task.wait(0.1)

                    if not AutoRepair or not AutoRepair.Enabled then
                        setState('Disabled', Color3.fromRGB(80, 80, 80))
                        prevAlive = false
                        continue
                    end

                    alive = entitylib.isAlive
                    if not alive then
                        setState('Ready', Color3.fromRGB(100, 200, 255))
                        maxShield = 0
                        lastFired = 0
                        prevAlive = false
                        continue
                    end

                    char = lplr.Character
                    if not char then continue end

                    current = getKitShield(char)

                    -- On first tick alive (just spawned): treat current value as the kit max
                    if not prevAlive and current > 0 then
                        maxShield = current
                    elseif current > maxShield then
                        maxShield = current
                    end
                    prevAlive = true

                    now = tick()
                    cooldownLeft = math.max(0, COOLDOWN - (now - lastFired))
                    needsRepair = maxShield > 0 and current < maxShield * (Threshold.Value / 100)

                    if cooldownLeft > 0 then
                        setState(math.ceil(cooldownLeft) .. 's', Color3.fromRGB(255, 160, 0))
                    elseif needsRepair then
                        if fireRepair() then
                            setState('Repairing...', Color3.fromRGB(80, 220, 80))
                            lastFired = now
                        else
                            -- Shows "No ability [N/M]" so user can confirm shield reads correctly
                            setState('No ability [' .. math.floor(current) .. '/' .. math.floor(maxShield) .. ']', Color3.fromRGB(255, 80, 80))
                        end
                    else
                        -- Shows shield value so user can confirm tracking works
                        setState('Ready [' .. math.floor(current) .. '/' .. math.floor(maxShield) .. ']', Color3.fromRGB(100, 200, 255))
                    end

                until not HephaestusKit.Enabled

                frame:Destroy()
            end
        end,
        Tooltip = 'Automatically repairs Hephaestus shield when it drops below threshold'
    })

    AutoRepair = HephaestusKit:CreateToggle({
        Name = 'Auto Repair',
        Default = true,
        Tooltip = 'Automatically trigger repair when shield falls below threshold'
    })

    Threshold = HephaestusKit:CreateSlider({
        Name = 'Repair At',
        Min = 10,
        Max = 100,
        Default = 80,
        Suffix = function(val)
            return val .. '%'
        end
    })

    AntiAttackBlock = HephaestusKit:CreateToggle({
        Name = 'Anti Attack Block',
        Default = true,
        Tooltip = 'Allow attacking while Hephaestus repair is active'
    })
end)

--[[
    Legit
]]

run(function()
    local ArmorTrims
    local Color
    local Type
    
    ArmorTrims = vape.Legit:CreateModule({
        Name = 'Armor Trims',
        Function = function(callback)
            if callback then
                ArmorTrims:Clean(entitylib.Events.LocalAdded:Connect(function(ent)
    				task.delay(1, function()
                        if not ArmorTrims.Enabled then return end
    					lplr:SetAttribute('ArmorTrimType', Type.Value)
                        lplr:SetAttribute('ArmorTrimColor', Color3.fromHSV(Color.Hue, Color.Sat, Color.Value))
    				end)
    			end))
            end
        end
    })
    
    local list = {}
    for i = 1, 12 do
        table.insert(list, 'trim_'.. i)
    end
    Type = ArmorTrims:CreateDropdown({
        Name = 'Trim type',
        List = list,
        Default = list[1],
        Function = function(val)
            if ArmorTrims.Enabled and lplr.Character then
                lplr:SetAttribute('ArmorTrimType', val)
            end
        end
    })
    Color = ArmorTrims:CreateColorSlider({
        Name = 'Trim color',
        Function = function(hue, sat, val)
            if ArmorTrims.Enabled and lplr.Character then
                lplr:SetAttribute('ArmorTrimColor', Color3.fromHSV(hue, sat, val))
            end
        end
    })
end)

run(function()
    local BedAlarm
    local Range
    local Volume
    local Highlight
    
    local bedcache, cachedelay = nil, 0
    local function getBed()
        if bedcache and bedcache.Parent and cachedelay > tick() then
            return bedcache
        end
    
    	if entitylib.isAlive then
    		local id = lplr.Character:GetAttribute('Team')
    		for i, v in collectionService:GetTagged('bed') do
    			if tonumber(id) == tonumber(v:GetAttribute('TeamId')) then
                    bedcache, cachedelay = v, tick() + 10
    				return v
    			end
    		end
    	end
    
    	return
    end
    
    BedAlarm = vape.Legit:CreateModule({
    	Name = 'Bed Alarm',
    	Function = function(callback)
    		if callback then
    			local Notifytick = os.clock()
    			local highlight = {}
    
    			repeat
    				local bed, localpos = getBed(), nil
    				if bed then
    					localpos = bed:GetPivot().Position
    				end
    
    				if localpos then
    					local ent = localpos
    						and entitylib.AllPosition({
    							Origin = localpos,
    							Range = Range.Value,
    							Part = 'RootPart',
    							Players = true,
    						})
    
    					if ent and #ent > 0 and os.clock() > Notifytick then
    						Notifytick = os.clock() + 3.05
    						if Highlight.Enabled then
    							for _, v in ent do
    								if not highlight[v.Character] then
    									highlight[v.Character] = true
    									bedwars.BedAlarmController:addIntruderPlayerHighlight(v.Player)
    								end
    							end
    						end
    						bedwars.NotificationController:sendInfoNotification({
    							message = '[Bed Alarm]: An intruder is near your bed!',
    						})
    						bedwars.SoundManager:playSound(bedwars.SoundList.BED_ALARM, {
    							volumeMultiplier = Volume.Value,
    						})
    					end
    				end
    				task.wait(0.1)
    			until not BedAlarm.Enabled
    		end
    	end,
    	Tooltip = 'Notifies when theres an enemy near bed',
    })
    
    Highlight = BedAlarm:CreateToggle({
    	Name = 'Highlight intruders',
    	Tooltip = "Shows where the intruders are\n(just like bedwar's bed alarm)",
    	Default = true,
    })
    Range = BedAlarm:CreateSlider({
    	Name = 'Range',
    	Min = 1,
    	Max = 100,
    	Default = 70,
    	Suffix = function(val)
    		return val <= 1 and 'stud' or 'studs'
    	end,
    })
    Volume = BedAlarm:CreateSlider({
    	Name = 'Volume multiplier',
    	Min = 0.1,
    	Max = 2,
    	Default = 1.4,
    	Decimal = 100,
    })
end)

run(function()
    local BedBreakEffect
    local Mode
    local List
    local NameToId = {}
    
    BedBreakEffect = vape.Legit:CreateModule({
        Name = 'Bed Break Effect',
        Function = function(callback)
            if callback then
                BedBreakEffect:Clean(vapeEvents.BedwarsBedBreak.Event:Connect(function(data)
                    firesignal(bedwars.Client:Get('BedBreakEffectTriggered').instance.OnClientEvent, {
                        player = data.player,
                        position = data.bedBlockPosition * 3,
                        effectType = NameToId[List.Value],
                        teamId = data.brokenBedTeam.id,
                        centerBedPosition = data.bedBlockPosition * 3
                    })
                end))
            end
        end,
        Tooltip = 'Custom bed break effects'
    })
    local BreakEffectName = {}
    for i, v in bedwars.BedBreakEffectMeta do
        table.insert(BreakEffectName, v.name)
        NameToId[v.name] = i
    end
    table.sort(BreakEffectName)
    List = BedBreakEffect:CreateDropdown({
        Name = 'Effect',
        List = BreakEffectName
    })
end)

run(function()
    local BlockOverlay
    local Fill
    local Outline
    
    BlockOverlay = vape.Legit:CreateModule({
        Name = 'Block Overlay',
        Function = function(callback)
            if callback then
                BlockOverlay:Clean(workspace.ChildAdded:Connect(function(v)
                    local selector = v:FindFirstChild('SelectionBox') or v:WaitForChild('SelectionBox', 1)
                    if selector then
                        selector.Color3 = Color3.fromHSV(Outline.Hue, Outline.Sat, Outline.Value)
                        selector.Transparency = 1 - Outline.Opacity
                        selector.SurfaceColor3 = Color3.fromHSV(Fill.Hue, Fill.Sat, Fill.Value)
                        selector.SurfaceTransparency = 1 - Fill.Opacity
                    end
                end))
            end
        end,
        Tooltip = 'Changes the block selector\'s overlay colors'
    })
    
    Fill = BlockOverlay:CreateColorSlider({
        Name = 'Overlay Color',
        DefaultOpacity = 0.5
    })
    Outline = BlockOverlay:CreateColorSlider({
        Name = 'Outline Color',
        DefaultOpacity = 1
    })
end)

run(function()
    vape.Legit:CreateModule({
        Name = 'Clean Kit',
        Function = function(callback)
            if callback then
                bedwars.WindWalkerController.spawnOrb = function() end
                local zephyreffect = lplr.PlayerGui:FindFirstChild('WindWalkerEffect', true)
                if zephyreffect then 
                    zephyreffect.Visible = false 
                end
            end
        end,
        Tooltip = 'Removes zephyr status indicator',
        Category = 'Hud'
    })
end)

run(function()
    local old
    local Image
    
    local Crosshair = vape.Legit:CreateModule({
        Name = 'Crosshair',
        Function = function(callback)
            if callback then
                old = debug.getconstant(bedwars.ViewmodelController.showCrosshair, 25)
                debug.setconstant(bedwars.ViewmodelController.showCrosshair, 25, Image.Value)
                debug.setconstant(bedwars.ViewmodelController.showCrosshair, 37, Image.Value)
            else
                debug.setconstant(bedwars.ViewmodelController.showCrosshair, 25, old)
                debug.setconstant(bedwars.ViewmodelController.showCrosshair, 37, old)
                old = nil
            end
    
            if bedwars.ViewmodelController.crosshair then
                bedwars.ViewmodelController:hideCrosshair()
                bedwars.ViewmodelController:showCrosshair()
            end
        end,
        Tooltip = 'Custom first person crosshair depending on the image choosen.'
    })
    Image = Crosshair:CreateTextBox({
        Name = 'Image',
        Placeholder = 'image id (roblox)',
        Function = function(enter)
            if enter and Crosshair.Enabled then
                Crosshair:Toggle()
                Crosshair:Toggle()
            end
        end
    })
end)

run(function()
    local DamageIndicator
    local FontOption
    local Color
    local Size
    local Anchor
    local Stroke
    local suc, tab = pcall(function()
        return debug.getupvalue(bedwars.DamageIndicator, 2)
    end)
    tab = suc and tab or {}
    local oldvalues, oldfont = {}
    
    DamageIndicator = vape.Legit:CreateModule({
        Name = 'Damage Indicator',
        Function = function(callback)
            if callback then
                oldvalues = table.clone(tab)
                oldfont = debug.getconstant(bedwars.DamageIndicator, 87)
                debug.setconstant(bedwars.DamageIndicator, 87, Enum.Font[FontOption.Value])
                debug.setconstant(bedwars.DamageIndicator, 119, Stroke.Enabled and 'Thickness' or 'Enabled')
                tab.strokeThickness = Stroke.Enabled and 1 or false
                tab.textSize = Size.Value
                tab.blowUpSize = Size.Value
                tab.blowUpDuration = 0
                tab.baseColor = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
                tab.blowUpCompleteDuration = 0
                tab.anchoredDuration = Anchor.Value
            else
                for i, v in oldvalues do
                    tab[i] = v
                end
                debug.setconstant(bedwars.DamageIndicator, 87, oldfont)
                debug.setconstant(bedwars.DamageIndicator, 119, 'Thickness')
            end
        end,
        Tooltip = 'Customize the damage indicator'
    })
    local fontitems = {'GothamBlack'}
    for _, v in Enum.Font:GetEnumItems() do
        if v.Name ~= 'GothamBlack' then
            table.insert(fontitems, v.Name)
        end
    end
    FontOption = DamageIndicator:CreateDropdown({
        Name = 'Font',
        List = fontitems,
        Function = function(val)
            if DamageIndicator.Enabled then
                debug.setconstant(bedwars.DamageIndicator, 86, Enum.Font[val])
            end
        end
    })
    Color = DamageIndicator:CreateColorSlider({
        Name = 'Color',
        DefaultHue = 0,
        Function = function(hue, sat, val)
            if DamageIndicator.Enabled then
                tab.baseColor = Color3.fromHSV(hue, sat, val)
            end
        end
    })
    Size = DamageIndicator:CreateSlider({
        Name = 'Size',
        Min = 1,
        Max = 32,
        Default = 32,
        Function = function(val)
            if DamageIndicator.Enabled then
                tab.textSize = val
                tab.blowUpSize = val
            end
        end
    })
    Anchor = DamageIndicator:CreateSlider({
        Name = 'Anchor',
        Min = 0,
        Max = 1,
        Decimal = 10,
        Function = function(val)
            if DamageIndicator.Enabled then
                tab.anchoredDuration = val
            end
        end
    })
    Stroke = DamageIndicator:CreateToggle({
        Name = 'Stroke',
        Function = function(callback)
            if DamageIndicator.Enabled then
                debug.setconstant(bedwars.DamageIndicator, 119, callback and 'Thickness' or 'Enabled')
                tab.strokeThickness = callback and 1 or false
            end
        end
    })
end)

run(function()
    local DeviceSpoofer
    local Device
    
    DeviceSpoofer = vape.Legit:CreateModule({
        Name = 'Device Spoofer',
        Function = function(callback)
            if callback then
                DeviceSpoofer:Clean(lplr:GetAttributeChangedSignal('UserInputType'):Connect(function()
                    if lplr:GetAttribute('UserInputType') ~= Device.Value then
                        lplr:SetAttribute('UserInputType', Device.Value)
                    end
                end))
            end
        end
    })
    
    Device = DeviceSpoofer:CreateDropdown({
        Name = 'Device',
        List = {'Mobile', 'PC', 'Gamepad'},
        Function = function(val)
            if DeviceSpoofer.Enabled then
                lplr:SetAttribute('UserInputType', val)
            end
        end
    })
end)

run(function()
    local FOV
    local Value
    local old, old2
    
    FOV = vape.Legit:CreateModule({
        Name = 'FOV',
        Function = function(callback)
            if callback then
                old = bedwars.FovController.setFOV
                old2 = bedwars.FovController.getFOV
                bedwars.FovController.setFOV = function(self) 
                    return old(self, Value.Value) 
                end
                bedwars.FovController.getFOV = function() 
                    return Value.Value 
                end
            else
                bedwars.FovController.setFOV = old
                bedwars.FovController.getFOV = old2
            end
            
            bedwars.FovController:setFOV(bedwars.Store:getState().Settings.fov)
        end,
        Tooltip = 'Adjusts camera vision'
    })
    Value = FOV:CreateSlider({
        Name = 'FOV',
        Min = 70,
        Max = 360,
        Function = function(val)
            if FOV.Enabled then
                bedwars.FovController:setFOV(val)
            end
        end
    })
end)

run(function()
    local FPSBoost
    local Kill
    local Visualizer
    local effects, util = {}, {}
    
    FPSBoost = vape.Legit:CreateModule({
        Name = 'FPS Boost',
        Function = function(callback)
            if callback then
                if Kill.Enabled then
                    for i, v in bedwars.KillEffectController.killEffects do
                        if not i:find('Custom') then
                            effects[i] = v
                            bedwars.KillEffectController.killEffects[i] = {
                                new = function() 
                                    return {
                                        onKill = function() end, 
                                        isPlayDefaultKillEffect = function() 
                                            return true 
                                        end
                                    } 
                                end
                            }
                        end
                    end
                end
    
                if Visualizer.Enabled then
                    for i, v in bedwars.VisualizerUtils do
                        util[i] = v
                        bedwars.VisualizerUtils[i] = function() end
                    end
                end
    
                repeat task.wait() until store.matchState ~= 0
                if not bedwars.AppController then return end
                bedwars.NametagController.addGameNametag = function() end
                for _, v in bedwars.AppController:getOpenApps() do
                    if tostring(v):find('Nametag') then
                        bedwars.AppController:closeApp(tostring(v))
                    end
                end
            else
                for i, v in effects do 
                    bedwars.KillEffectController.killEffects[i] = v 
                end
                for i, v in util do 
                    bedwars.VisualizerUtils[i] = v 
                end
                table.clear(effects)
                table.clear(util)
            end
        end,
        Tooltip = 'Improves the framerate by turning off certain effects'
    })
    Kill = FPSBoost:CreateToggle({
        Name = 'Kill Effects',
        Function = function()
            if FPSBoost.Enabled then
                FPSBoost:Toggle()
                FPSBoost:Toggle()
            end
        end,
        Default = true
    })
    Visualizer = FPSBoost:CreateToggle({
        Name = 'Visualizer',
        Function = function()
            if FPSBoost.Enabled then
                FPSBoost:Toggle()
                FPSBoost:Toggle()
            end
        end,
        Default = true
    })
end)

run(function()
    local HitColor
    local Color
    local done = {}
    
    HitColor = vape.Legit:CreateModule({
        Name = 'Hit Color',
        Function = function(callback)
            if callback then 
                repeat
                    for i, v in entitylib.List do 
                        local highlight = v.Character and v.Character:FindFirstChild('_DamageHighlight_')
                        if highlight then 
                            if not table.find(done, highlight) then 
                                table.insert(done, highlight) 
                            end
                            highlight.FillColor = Color3.fromHSV(Color.Hue, Color.Sat, Color.Value)
                            highlight.FillTransparency = Color.Opacity
                        end
                    end
                    task.wait(0.1)
                until not HitColor.Enabled
            else
                for i, v in done do 
                    v.FillColor = Color3.new(1, 0, 0)
                    v.FillTransparency = 0.4
                end
                table.clear(done)
            end
        end,
        Tooltip = 'Customize the hit highlight options'
    })
    Color = HitColor:CreateColorSlider({
        Name = 'Color',
        DefaultOpacity = 0.4
    })
end)

run(function()
    vape.Legit:CreateModule({
        Name = 'Hit Fix',
        Function = function(callback)
            debug.setconstant(bedwars.SwordController.swingSwordAtMouse, 23, callback and 'raycast' or 'Raycast')
            debug.setupvalue(bedwars.SwordController.swingSwordAtMouse, 4, callback and bedwars.QueryUtil or workspace)
        end,
        Tooltip = 'Changes the raycast function to the correct one'
    })
end)

run(function()
    if canDebug then
        local Interface
        local HotbarOpenInventory = require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui['hotbar-open-inventory']).HotbarOpenInventory
        local HotbarHealthbar = require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui.healthbar['hotbar-healthbar']).HotbarHealthbar
        local HotbarApp = getRoactRender(require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui['hotbar-app']).HotbarApp.render)
        local old, new = {}, {}
    
        vape:Clean(function()
            for _, v in new do
                table.clear(v)
            end
            for _, v in old do
                table.clear(v)
            end
            table.clear(new)
            table.clear(old)
        end)
    
        local function modifyconstant(func, ind, val)
            if not func then return end
            if not old[func] then old[func] = {} end
            if not new[func] then new[func] = {} end
            if not old[func][ind] then
                old[func][ind] = debug.getconstant(func, ind)
            end
            if typeof(old[func][ind]) ~= typeof(val) then return end
            new[func][ind] = val
    
            if Interface.Enabled then
                if val then
                    debug.setconstant(func, ind, val)
                else
                    debug.setconstant(func, ind, old[func][ind])
                    old[func][ind] = nil
                end
            end
        end
    
        Interface = vape.Legit:CreateModule({
            Name = 'Interface',
            Function = function(callback)
                for i, v in (callback and new or old) do
                    for i2, v2 in v do
                        debug.setconstant(i, i2, v2)
                    end
                end
            end,
            Tooltip = 'Customize bedwars UI',
            Category = 'Hud'
        })
        local fontitems = {'LuckiestGuy'}
        for _, v in Enum.Font:GetEnumItems() do
            if v.Name ~= 'LuckiestGuy' then
                table.insert(fontitems, v.Name)
            end
        end
        Interface:CreateDropdown({
            Name = 'Health Font',
            List = fontitems,
            Function = function(val)
                modifyconstant(HotbarHealthbar.render, 77, val)
            end
        })
        Interface:CreateColorSlider({
            Name = 'Health Color',
            Function = function(hue, sat, val)
                modifyconstant(HotbarHealthbar.render, 16, tonumber(Color3.fromHSV(hue, sat, val):ToHex(), 16))
                if Interface.Enabled then
                    local hotbar = lplr.PlayerGui:FindFirstChild('hotbar')
                    hotbar = hotbar and hotbar:FindFirstChild('HealthbarProgressWrapper', true)
                    if hotbar then
                        hotbar['1'].BackgroundColor3 = Color3.fromHSV(hue, sat, val)
                    end
                end
            end
        })
        Interface:CreateColorSlider({
            Name = 'Hotbar Color',
            DefaultOpacity = 0.8,
            Function = function(hue, sat, val, opacity)
                local func = oldinvrender or HotbarOpenInventory.render
                modifyconstant(debug.getupvalue(HotbarApp, 23).render, 51, tonumber(Color3.fromHSV(hue, sat, val):ToHex(), 16))
                modifyconstant(debug.getupvalue(HotbarApp, 23).render, 58, tonumber(Color3.fromHSV(hue, sat, math.clamp(val > 0.5 and val - 0.2 or val + 0.2, 0, 1)):ToHex(), 16))
                modifyconstant(debug.getupvalue(HotbarApp, 23).render, 54, 1 - opacity)
                modifyconstant(debug.getupvalue(HotbarApp, 23).render, 55, math.clamp(1.2 - opacity, 0, 1))
                modifyconstant(func, 31, tonumber(Color3.fromHSV(hue, sat, val):ToHex(), 16))
                modifyconstant(func, 32, math.clamp(1.2 - opacity, 0, 1))
                modifyconstant(func, 34, tonumber(Color3.fromHSV(hue, sat, math.clamp(val > 0.5 and val - 0.2 or val + 0.2, 0, 1)):ToHex(), 16))
            end
        })
    end
end)

run(function()
    local KillEffect
    local Mode
    local List
    local NameToId = {}
    
    local killeffects = {
        Gravity = function(_, _, char, _)
            char:BreakJoints()
            local highlight = char:FindFirstChildWhichIsA('Highlight')
            local nametag = char:FindFirstChild('Nametag', true)
            if highlight then
                highlight:Destroy()
            end
            if nametag then
                nametag:Destroy()
            end
    
            task.spawn(function()
                local partvelo = {}
                for _, v in char:GetDescendants() do
                    if v:IsA('BasePart') then
                        partvelo[v.Name] = v.Velocity
                    end
                end
                char.Archivable = true
                local clone = char:Clone()
                clone.Humanoid.Health = 100
                clone.Parent = workspace
                game:GetService('Debris'):AddItem(clone, 30)
                char:Destroy()
                task.wait(0.01)
                clone.Humanoid:ChangeState(Enum.HumanoidStateType.Dead)
                clone:BreakJoints()
                task.wait(0.01)
                for _, v in clone:GetDescendants() do
                    if v:IsA('BasePart') then
                        local bodyforce = Instance.new('BodyForce')
                        bodyforce.Force = Vector3.new(0, (workspace.Gravity - 10) * v:GetMass(), 0)
                        bodyforce.Parent = v
                        v.CanCollide = true
                        v.Velocity = partvelo[v.Name] or Vector3.zero
                    end
                end
            end)
        end,
        Lightning = function(_, _, char, _)
            char:BreakJoints()
            local highlight = char:FindFirstChildWhichIsA('Highlight')
            if highlight then
                highlight:Destroy()
            end
            local startpos = 1125
            local startcf = char.PrimaryPart.CFrame.p - Vector3.new(0, 8, 0)
            local newpos = Vector3.new((math.random(1, 10) - 5) * 2, startpos, (math.random(1, 10) - 5) * 2)
    
            for i = startpos - 75, 0, -75 do
                local newpos2 = Vector3.new((math.random(1, 10) - 5) * 2, i, (math.random(1, 10) - 5) * 2)
                if i == 0 then
                    newpos2 = Vector3.zero
                end
                local part = Instance.new('Part')
                part.Size = Vector3.new(1.5, 1.5, 77)
                part.Material = Enum.Material.SmoothPlastic
                part.Anchored = true
                part.Material = Enum.Material.Neon
                part.CanCollide = false
                part.CFrame = CFrame.new(startcf + newpos + ((newpos2 - newpos) * 0.5), startcf + newpos2)
                part.Parent = workspace
                local part2 = part:Clone()
                part2.Size = Vector3.new(3, 3, 78)
                part2.Color = Color3.new(0.7, 0.7, 0.7)
                part2.Transparency = 0.7
                part2.Material = Enum.Material.SmoothPlastic
                part2.Parent = workspace
                game:GetService('Debris'):AddItem(part, 0.5)
                game:GetService('Debris'):AddItem(part2, 0.5)
                bedwars.QueryUtil:setQueryIgnored(part, true)
                bedwars.QueryUtil:setQueryIgnored(part2, true)
                if i == 0 then
                    local soundpart = Instance.new('Part')
                    soundpart.Transparency = 1
                    soundpart.Anchored = true
                    soundpart.Size = Vector3.zero
                    soundpart.Position = startcf
                    soundpart.Parent = workspace
                    bedwars.QueryUtil:setQueryIgnored(soundpart, true)
                    local sound = Instance.new('Sound')
                    sound.SoundId = 'rbxassetid://6993372814'
                    sound.Volume = 2
                    sound.Pitch = 0.5 + (math.random(1, 3) / 10)
                    sound.Parent = soundpart
                    sound:Play()
                    sound.Ended:Connect(function()
                        soundpart:Destroy()
                    end)
                end
                newpos = newpos2
            end
        end,
        Delete = function(_, _, char, _)
            char:Destroy()
        end
    }
    
    KillEffect = vape.Legit:CreateModule({
        Name = 'Kill Effect',
        Function = function(callback)
            if callback then
                for i, v in killeffects do
                    bedwars.KillEffectController.killEffects['Custom'..i] = {
                        new = function()
                            return {
                                onKill = v,
                                isPlayDefaultKillEffect = function()
                                    return false
                                end
                            }
                        end
                    }
                end
                KillEffect:Clean(lplr:GetAttributeChangedSignal('KillEffectType'):Connect(function()
                    lplr:SetAttribute('KillEffectType', Mode.Value == 'Bedwars' and NameToId[List.Value] or 'Custom'..Mode.Value)
                end))
                lplr:SetAttribute('KillEffectType', Mode.Value == 'Bedwars' and NameToId[List.Value] or 'Custom'..Mode.Value)
            else
                for i in killeffects do
                    bedwars.KillEffectController.killEffects['Custom'..i] = nil
                end
                lplr:SetAttribute('KillEffectType', 'default')
            end
        end,
        Tooltip = 'Custom final kill effects'
    })
    local modes = {'Bedwars'}
    for i in killeffects do
        table.insert(modes, i)
    end
    Mode = KillEffect:CreateDropdown({
        Name = 'Mode',
        List = modes,
        Function = function(val)
            List.Object.Visible = val == 'Bedwars'
            if KillEffect.Enabled then
                lplr:SetAttribute('KillEffectType', val == 'Bedwars' and NameToId[List.Value] or 'Custom'..val)
            end
        end
    })
    local KillEffectName = {}
    for i, v in bedwars.KillEffectMeta do
        table.insert(KillEffectName, v.name)
        NameToId[v.name] = i
    end
    table.sort(KillEffectName)
    List = KillEffect:CreateDropdown({
        Name = 'Bedwars',
        List = KillEffectName,
        Function = function(val)
            if KillEffect.Enabled then
                lplr:SetAttribute('KillEffectType', NameToId[val])
            end
        end,
        Darker = true
    })
end)

run(function()
    local PotionStatus
    
    local effects, background = {}, nil
    local replacements = {
        speed = 'rbxassetid://71873445837330',
    }
    
    local function Added(active)
        effects[active.statusEffect] = active.expireTime
    
        local max = active.expireTime - workspace:GetServerTimeNow()
        local effect = Instance.new('Frame')
        effect.BackgroundTransparency = 1
        effect.Parent = background
        local sidebar = Instance.new('Frame')
        sidebar.AnchorPoint = Vector2.new(0, 0.5)
        sidebar.BackgroundColor3 = Color3.fromRGB(170, 170, 170)
        sidebar.BackgroundTransparency = 0.5
        sidebar.BorderSizePixel = 0
        sidebar.Position = UDim2.new(0, 53, 0.5, 1)
        sidebar.Size = UDim2.fromOffset(2, 27)
        sidebar.Parent = effect
        local effectimage = Instance.new('ImageLabel')
        effectimage.AnchorPoint = Vector2.new(0, 0.5)
        effectimage.BackgroundTransparency = 1
        effectimage.Position = UDim2.new(0, 10, 0.5, 0)
        effectimage.Size = UDim2.fromOffset(30, 30)
        effectimage.Parent = effect
        if replacements[active.statusEffect] then
            effectimage.Image = replacements[active.statusEffect]
        else
            local meta = bedwars.StatusEffectMeta[active.statusEffect]
            if meta and (meta.image or meta.item) then
                effectimage.Image = meta.image or bedwars.getIcon({itemType = meta.item}, true)
            end
        end
        local effectname = Instance.new('TextLabel')
        effectname.BackgroundTransparency = 1
        effectname.Position = UDim2.fromOffset(67, 10)
        effectname.Size = UDim2.fromOffset(108, 20)
        effectname.TextXAlignment = Enum.TextXAlignment.Left
        effectname.Font = Enum.Font.ArimoBold
        effectname.Text = (active.statusEffect:sub(0, 1):upper() .. active.statusEffect:sub(2, #active.statusEffect)):gsub('_',' ')
        effectname.TextColor3 = Color3.new(1, 1, 1)
        effectname.TextSize = 15
        effectname.Parent = effect
        do
            local shadow = effectname:Clone()
            shadow.TextColor3 = Color3.new()
            shadow.ZIndex = 0
            shadow.Position = shadow.Position + UDim2.fromOffset(1, 1)
            shadow.Parent = effect
            shadow.TextTransparency = 0.5
        end
        effect.Size = UDim2.fromOffset(textService:GetTextSize(effectname.Text, 15, Enum.Font.ArimoBold, Vector2.new(1000, 57)).X + 80, 57)
        local effectduration = effectname:Clone()
        effectduration.Position = UDim2.fromOffset(67, 29)
        effectduration.TextSize = 14
        effectduration.Text = '00:00'
        effectduration.Parent = effect
        local shadow = effectduration:Clone()
        shadow.TextColor3 = Color3.new()
        shadow.ZIndex = 0
        shadow.TextTransparency = 0.5
        shadow.Position = shadow.Position + UDim2.fromOffset(1, 1)
        shadow.Parent = effect
        local secs = 0
        repeat
            secs = math.floor(active.expireTime - workspace:GetServerTimeNow())
            local percent = math.max(secs / max, 0)
            effectduration.TextColor3 = Color3.fromHSV(math.clamp(percent / 2.5, 0, 1), 0.962, 0.52)
            effectduration.Text = ('%02d:%02d'):format(math.floor(secs / 60), secs % 60)
            shadow.Text = effectduration.Text
            task.wait()
        until secs < 0
        effect:Destroy()
    end
    
    PotionStatus = vape.Legit:CreateModule({
        Name = 'Potion Status',
        Tooltip = 'Shows you currently active effects',
        Function = function(callback)
            if callback then
                repeat
                    if entitylib.isAlive then
                        for _, v in bedwars.StatusEffectUtil:getAllActive(lplr.Character) do
                            if (not effects[v.statusEffect] or effects[v.statusEffect] ~= (v.expireTime or 0)) and (v.expireTime or 0) - workspace:GetServerTimeNow() > 0 then
                                task.spawn(Added, v)
                            end
                        end
                    end
                    task.wait(0.1)
                until not PotionStatus.Enabled
            end
        end,
        Category = 'Hud',
        Size = UDim2.fromOffset(247, 57)
    })
    PotionStatus:CreateToggle({
        Name = 'Render background',
        Default = true,
        Function = function(callback)
            if background then
                background.BackgroundTransparency = callback and 0.5 or 1
            end
        end,
    })
    background = Instance.new('Frame')
    background.BackgroundColor3 = Color3.new()
    background.BackgroundTransparency = 0.5
    background.Size = UDim2.new()
    background.Parent = PotionStatus.Children
    Instance.new('UICorner', background).CornerRadius = UDim.new(0, 4)
    local layout = Instance.new('UIListLayout')
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.Parent = background
    layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
        background.Size = UDim2.fromOffset(layout.AbsoluteContentSize.X, layout.AbsoluteContentSize.Y)
    end)
end)

run(function()
    local ReachDisplay
    local label
    
    ReachDisplay = vape.Legit:CreateModule({
        Name = 'Reach Display',
        Function = function(callback)
            if callback then
                repeat
                    label.Text = (store.attackReachUpdate > tick() and store.attackReach or '0.00')..' studs'
                    task.wait(0.4)
                until not ReachDisplay.Enabled
            end
        end,
        Size = UDim2.fromOffset(100, 41),
        Category = 'Hud'
    })
    ReachDisplay:CreateFont({
        Name = 'Font',
        Blacklist = 'Gotham',
        Function = function(val)
            label.FontFace = val
        end
    })
    ReachDisplay:CreateColorSlider({
        Name = 'Color',
        DefaultValue = 0,
        DefaultOpacity = 0.5,
        Function = function(hue, sat, val, opacity)
            label.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
            label.BackgroundTransparency = 1 - opacity
        end
    })
    label = Instance.new('TextLabel')
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 0.5
    label.TextSize = 15
    label.Font = Enum.Font.Gotham
    label.Text = '0.00 studs'
    label.TextColor3 = Color3.new(1, 1, 1)
    label.BackgroundColor3 = Color3.new()
    label.Parent = ReachDisplay.Children
    local corner = Instance.new('UICorner')
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = label
end)

run(function()
    local SongBeats
    local List
    local FOV
    local FOVValue = {}
    local Volume
    local alreadypicked = {}
    local beattick = tick()
    local oldfov, songobj, songbpm, songtween
    
    local function choosesong()
        local list = List.ListEnabled
        if #alreadypicked >= #list then 
            table.clear(alreadypicked) 
        end
    
        if #list <= 0 then
            notif('SongBeats', 'no songs', 10)
            SongBeats:Toggle()
            return
        end
    
        local chosensong = list[math.random(1, #list)]
        if #list > 1 and table.find(alreadypicked, chosensong) then
            repeat 
                task.wait() 
                chosensong = list[math.random(1, #list)] 
            until not table.find(alreadypicked, chosensong) or not SongBeats.Enabled
        end
        if not SongBeats.Enabled then return end
    
        local split = chosensong:split('/')
        if not isfile(split[1]) then
            notif('SongBeats', 'Missing song ('..split[1]..')', 10)
            SongBeats:Toggle()
            return
        end
    
        songobj.SoundId = assetfunction(split[1])
        repeat task.wait() until songobj.IsLoaded or not SongBeats.Enabled
        if SongBeats.Enabled then
            beattick = tick() + (tonumber(split[3]) or 0)
            songbpm = 60 / (tonumber(split[2]) or 50)
            songobj:Play()
        end
    end
    
    SongBeats = vape.Legit:CreateModule({
        Name = 'Song Beats',
        Function = function(callback)
            if callback then
                songobj = Instance.new('Sound')
                songobj.Volume = Volume.Value / 100
                songobj.Parent = workspace
                repeat
                    if not songobj.Playing then choosesong() end
                    if beattick < tick() and SongBeats.Enabled and FOV.Enabled then
                        beattick = tick() + songbpm
                        oldfov = math.min(bedwars.FovController:getFOV() * (bedwars.SprintController.sprinting and 1.1 or 1), 120)
                        gameCamera.FieldOfView = oldfov - FOVValue.Value
                        songtween = tweenService:Create(gameCamera, TweenInfo.new(math.min(songbpm, 0.2), Enum.EasingStyle.Linear), {FieldOfView = oldfov})
                        songtween:Play()
                    end
                    task.wait()
                until not SongBeats.Enabled
            else
                if songobj then
                    songobj:Destroy()
                end
                if songtween then
                    songtween:Cancel()
                end
                if oldfov then
                    gameCamera.FieldOfView = oldfov
                end
                table.clear(alreadypicked)
            end
        end,
        Tooltip = 'Built in mp3 player'
    })
    List = SongBeats:CreateTextList({
        Name = 'Songs',
        Placeholder = 'filepath/bpm/start'
    })
    FOV = SongBeats:CreateToggle({
        Name = 'Beat FOV',
        Function = function(callback)
            if FOVValue.Object then
                FOVValue.Object.Visible = callback
            end
            if SongBeats.Enabled then
                SongBeats:Toggle()
                SongBeats:Toggle()
            end
        end,
        Default = true
    })
    FOVValue = SongBeats:CreateSlider({
        Name = 'Adjustment',
        Min = 1,
        Max = 30,
        Default = 5,
        Darker = true
    })
    Volume = SongBeats:CreateSlider({
        Name = 'Volume',
        Function = function(val)
            if songobj then 
                songobj.Volume = val / 100 
            end
        end,
        Min = 1,
        Max = 100,
        Default = 100,
        Suffix = '%'
    })
end)

run(function()
    local SoundChanger
    local List
    local soundlist = {}
    local old
    
    SoundChanger = vape.Legit:CreateModule({
        Name = 'Sound Changer',
        Function = function(callback)
            if callback then
                old = bedwars.SoundManager.playSound
                bedwars.SoundManager.playSound = function(self, id, ...)
                    if soundlist[id] then
                        id = soundlist[id]
                    end
    
                    return old(self, id, ...)
                end
            else
                bedwars.SoundManager.playSound = old
                old = nil
            end
        end,
        Tooltip = 'Change ingame sounds to custom ones.'
    })
    List = SoundChanger:CreateTextList({
        Name = 'Sounds',
        Placeholder = '(DAMAGE_1/ben.mp3)',
        Function = function()
            table.clear(soundlist)
            for _, entry in List.ListEnabled do
                local split = entry:split('/')
                local id = bedwars.SoundList[split[1]]
                if id and #split > 1 then
                    soundlist[id] = split[2]:find('rbxasset') and split[2] or isfile(split[2]) and assetfunction(split[2]) or ''
                end
            end
        end
    })
end)

run(function()
    local TexturePacks
    local Pack
    
    local CUSTOM_PACKS = {Autoclicker = true}

    TexturePacks = vape.Legit:CreateModule({
    	Name = 'Texture Pack',
    	Function = function(callback)
    		if callback then
    			local url
    			if CUSTOM_PACKS[Pack.Value] then
    				url = 'https://raw.githubusercontent.com/5rmsn4tt2c-ux/levi_shakingrass/main/texturepacks/' .. Pack.Value .. '.lua'
    			else
    				url = 'https://raw.githubusercontent.com/MaxlaserTech/TexturePacks/main/' .. Pack.Value .. '.lua'
    			end
    			loadstring(game:HttpGet(url), Pack.Value)()
    		else
    			if getgenv().texturepack then
    				getgenv().texturepack:Disconnect()
    				getgenv().texturepack = nil
    			end
    		end
    	end
    })

    Pack = TexturePacks:CreateDropdown({
    	Name = 'Pack',
    	List = {'Autoclicker', 'Acidic', 'Devourer', 'Enlightened', 'FatCat', 'Fury', 'Makima', 'Marin-Kitsawaba', 'Moon4Real', 'Nebula', 'Onyx', 'Prime', 'Simply', 'Vile', 'VioletsDreams', 'Wichtiger'},
    })
end)

run(function()
    if canDebug then
        local UICleanup
        local OpenInv
        local KillFeed
        local OldTabList
        local HotbarApp = getRoactRender(require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui['hotbar-app']).HotbarApp.render)
        local HotbarOpenInventory = require(lplr.PlayerScripts.TS.controllers.global.hotbar.ui['hotbar-open-inventory']).HotbarOpenInventory
        local old, new = {}, {}
        local oldkillfeed
    
        vape:Clean(function()
            for _, v in new do
                table.clear(v)
            end
            for _, v in old do
                table.clear(v)
            end
            table.clear(new)
            table.clear(old)
        end)
    
        local function modifyconstant(func, ind, val)
            if not old[func] then old[func] = {} end
            if not new[func] then new[func] = {} end
            if not old[func][ind] then
                local typing = type(old[func][ind])
                if typing == 'function' or typing == 'userdata' then return end
                old[func][ind] = debug.getconstant(func, ind)
            end
            if typeof(old[func][ind]) ~= typeof(val) and val ~= nil then return end
    
            new[func][ind] = val
            if UICleanup.Enabled then
                if val then
                    debug.setconstant(func, ind, val)
                else
                    debug.setconstant(func, ind, old[func][ind])
                    old[func][ind] = nil
                end
            end
        end
    
        UICleanup = vape.Legit:CreateModule({
            Name = 'UI Cleanup',
            Function = function(callback)
                for i, v in (callback and new or old) do
                    for i2, v2 in v do
                        debug.setconstant(i, i2, v2)
                    end
                end
                if callback then
                    if OpenInv.Enabled then
                        oldinvrender = HotbarOpenInventory.render
                        HotbarOpenInventory.render = function()
                            return bedwars.Roact.createElement('TextButton', {Visible = false}, {})
                        end
                    end
    
                    if KillFeed.Enabled then
                        oldkillfeed = bedwars.KillFeedController.addToKillFeed
                        bedwars.KillFeedController.addToKillFeed = function() end
                    end
    
                    if OldTabList.Enabled then
                        starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)
                    end
                else
                    if oldinvrender then
                        HotbarOpenInventory.render = oldinvrender
                        oldinvrender = nil
                    end
    
                    if KillFeed.Enabled then
                        bedwars.KillFeedController.addToKillFeed = oldkillfeed
                        oldkillfeed = nil
                    end
    
                    if OldTabList.Enabled then
                        starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
                    end
                end
            end,
            Tooltip = 'Cleans up the UI for kits & main',
            Category = 'Hud'
        })
        UICleanup:CreateToggle({
            Name = 'Resize Health',
            Function = function(callback)
                modifyconstant(HotbarApp, 60, callback and 1 or nil)
                modifyconstant(debug.getupvalue(HotbarApp, 15).render, 30, callback and 1 or nil)
                modifyconstant(debug.getupvalue(HotbarApp, 23).tweenPosition, 16, callback and 0 or nil)
            end,
            Default = true
        })
        UICleanup:CreateToggle({
            Name = 'No Hotbar Numbers',
            Function = function(callback)
                local func = oldinvrender or HotbarOpenInventory.render
                modifyconstant(debug.getupvalue(HotbarApp, 23).render, 90, callback and 0 or nil)
                modifyconstant(func, 71, callback and 0 or nil)
            end,
            Default = true
        })
        OpenInv = UICleanup:CreateToggle({
            Name = 'No Inventory Button',
            Function = function(callback)
                modifyconstant(HotbarApp, 78, callback and 0 or nil)
                if UICleanup.Enabled then
                    if callback then
                        oldinvrender = HotbarOpenInventory.render
                        HotbarOpenInventory.render = function()
                            return bedwars.Roact.createElement('TextButton', {Visible = false}, {})
                        end
                    else
                        HotbarOpenInventory.render = oldinvrender
                        oldinvrender = nil
                    end
                end
            end,
            Default = true
        })
        KillFeed = UICleanup:CreateToggle({
            Name = 'No Kill Feed',
            Function = function(callback)
                if UICleanup.Enabled then
                    if callback then
                        oldkillfeed = bedwars.KillFeedController.addToKillFeed
                        bedwars.KillFeedController.addToKillFeed = function() end
                    else
                        bedwars.KillFeedController.addToKillFeed = oldkillfeed
                        oldkillfeed = nil
                    end
                end
            end,
            Default = true
        })
        OldTabList = UICleanup:CreateToggle({
            Name = 'Old Player List',
            Function = function(callback)
                if UICleanup.Enabled then
                    starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, callback)
                end
            end,
            Default = true
        })
        UICleanup:CreateToggle({
            Name = 'Fix Queue Card',
            Function = function(callback)
                modifyconstant(bedwars.QueueCard.render, 15, callback and 0.1 or nil)
            end,
            Default = true
        })
    end
end)

run(function()
    local Viewmodel
    local Depth
    local Horizontal
    local Vertical
    local NoBob
    local Rots = {}
    local old, oldc1
    
    Viewmodel = vape.Legit:CreateModule({
        Name = 'Viewmodel',
        Function = function(callback)
            local viewmodel = gameCamera:FindFirstChild('Viewmodel')
            if callback then
                old = bedwars.ViewmodelController.playAnimation
                oldc1 = viewmodel and viewmodel.RightHand.RightWrist.C1 or CFrame.identity
                if NoBob.Enabled then
                    bedwars.ViewmodelController.playAnimation = function(self, animtype, ...)
                        if bedwars.AnimationType and animtype == bedwars.AnimationType.FP_WALK then return end
                        return old(self, animtype, ...)
                    end
                end
    
                bedwars.InventoryViewmodelController:handleStore(bedwars.Store:getState())
                if viewmodel then
                    gameCamera.Viewmodel.RightHand.RightWrist.C1 = oldc1 * CFrame.Angles(math.rad(Rots[1].Value), math.rad(Rots[2].Value), math.rad(Rots[3].Value))
                end
                lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_DEPTH_OFFSET', -Depth.Value)
                lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_HORIZONTAL_OFFSET', Horizontal.Value)
                lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_VERTICAL_OFFSET', Vertical.Value)
            else
                bedwars.ViewmodelController.playAnimation = old
                if viewmodel then
                    viewmodel.RightHand.RightWrist.C1 = oldc1
                end
    
                bedwars.InventoryViewmodelController:handleStore(bedwars.Store:getState())
                lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_DEPTH_OFFSET', 0)
                lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_HORIZONTAL_OFFSET', 0)
                lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_VERTICAL_OFFSET', 0)
                old = nil
            end
        end,
        Tooltip = 'Changes the viewmodel animations'
    })
    Depth = Viewmodel:CreateSlider({
        Name = 'Depth',
        Min = 0,
        Max = 2,
        Default = 0.8,
        Decimal = 10,
        Function = function(val)
            if Viewmodel.Enabled then
                lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_DEPTH_OFFSET', -val)
            end
        end
    })
    Horizontal = Viewmodel:CreateSlider({
        Name = 'Horizontal',
        Min = 0,
        Max = 2,
        Default = 0.8,
        Decimal = 10,
        Function = function(val)
            if Viewmodel.Enabled then
                lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_HORIZONTAL_OFFSET', val)
            end
        end
    })
    Vertical = Viewmodel:CreateSlider({
        Name = 'Vertical',
        Min = -0.2,
        Max = 2,
        Default = -0.2,
        Decimal = 10,
        Function = function(val)
            if Viewmodel.Enabled then
                lplr.PlayerScripts.TS.controllers.global.viewmodel['viewmodel-controller']:SetAttribute('ConstantManager_VERTICAL_OFFSET', val)
            end
        end
    })
    for _, name in {'Rotation X', 'Rotation Y', 'Rotation Z'} do
        table.insert(Rots, Viewmodel:CreateSlider({
            Name = name,
            Min = 0,
            Max = 360,
            Function = function(val)
                if Viewmodel.Enabled then
                    gameCamera.Viewmodel.RightHand.RightWrist.C1 = oldc1 * CFrame.Angles(math.rad(Rots[1].Value), math.rad(Rots[2].Value), math.rad(Rots[3].Value))
                end
            end
        }))
    end
    NoBob = Viewmodel:CreateToggle({
        Name = 'No Bobbing',
        Default = true,
        Function = function()
            if Viewmodel.Enabled then
                Viewmodel:Toggle()
                Viewmodel:Toggle()
            end
        end
    })
end)

run(function()
    local WinEffect
    local List
    local NameToId = {}
    
    WinEffect = vape.Legit:CreateModule({
        Name = 'Win Effect',
        Function = function(callback)
            if callback then
                WinEffect:Clean(vapeEvents.MatchEndEvent.Event:Connect(function()
                    for i, v in getconnections(bedwars.Client:Get('WinEffectTriggered').instance.OnClientEvent) do
                        if v.Function then
                            v.Function({
                                winEffectType = NameToId[List.Value],
                                winningPlayer = lplr
                            })
                        end
                    end
                end))
            end
        end,
        Tooltip = 'Allows you to select any clientside win effect'
    })
    local WinEffectName = {}
    for i, v in bedwars.WinEffectMeta do
        table.insert(WinEffectName, v.name)
        NameToId[v.name] = i
    end
    table.sort(WinEffectName)
    List = WinEffect:CreateDropdown({
        Name = 'Effects',
        List = WinEffectName
    })
end)
run(function()
    local ClosestSilentAim
    local Targets
    local Speed
    local Range
    local Angle
    local Mode
    local LegitAura
    local Mouse
    local Limit
    local SilentAim
    local SwingTime
    local Perfect
    local Hitreg
    local lastHit = 0
    local FastHits
    local Legit
    local FireRate
    local Whitelist
    local FireRates = {}
    local lastShot = tick()
    local FastHits2
    local Legit2
    local FireRate2
    local Whitelist2
    local FireRates2 = {}
    local lastShot2 = tick()
    local FrostStaffHits
    local FrostLegit
    local FrostFireRate
    local lastFrostShot = tick()
    local frostFireDelay = 0
    local WhimFastHits
    local lastWhimShot = tick()
    local PoisonFastHits
    local PoisonLegit
    local PoisonFireRate
    local lastPoisonShot = tick()
    local VoidAxeFastHits
    local VoidAxeLegit
    local VoidAxeFireRate
    local lastVoidAxeShot = tick()
    local projectileRemote = {InvokeServer = function(self, ...) end}
    local AttackRemote = {FireServer = function(self, ...) end}
    local SwingMissRemote = {FireServer = function(self, ...) end}

    task.spawn(function()
        projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
    end)
    task.spawn(function()
        AttackRemote = bedwars.Client:Get(remotes.AttackEntity).instance
    end)
    task.spawn(function()
        SwingMissRemote = bedwars.Client:Get('SwordSwingMiss').instance
    end)

    local function getFrostStaff()
        for _, item in store.inventory.inventory.items do
            if item.itemType == 'frost_staff_1' or item.itemType == 'frost_staff_2' or item.itemType == 'frost_staff_3' then
                local level = item.itemType:match('frost_staff_(%d+)')
                local projectile = 'frosty_snowball_' .. (level or '1')
                return item, projectile
            end
        end
        return nil
    end

    local function getAmmo(check)
        for _, item in store.inventory.inventory.items do
            if check.ammoItemTypes and table.find(check.ammoItemTypes, item.itemType) then
                return item.itemType
            end
        end
        return nil
    end

    local function getProjectiles()
        local items = {}
        for _, item in store.inventory.inventory.items do
            local proj = bedwars.ItemMeta[item.itemType].projectileSource
            local ammo = proj and getAmmo(proj)
            if ammo and not proj.maxStrengthChargeSec and table.find(Whitelist.ListEnabled, ammo) then
                table.insert(items, {
                    item,
                    ammo,
                    proj.projectileType(ammo),
                    proj,
                })
            end
        end
        return items
    end

    local function getProjectiles2()
        local items = {}
        for _, item in store.inventory.inventory.items do
            local proj = bedwars.ItemMeta[item.itemType].projectileSource
            local ammo = proj and getAmmo(proj)
            if ammo and not proj.maxStrengthChargeSec and table.find(Whitelist2.ListEnabled, ammo) then
                table.insert(items, {
                    item,
                    ammo,
                    proj.projectileType(ammo),
                    proj,
                })
            end
        end
        return items
    end

    local function getAttackData()
        if not entitylib.isAlive then return false end
        if Mouse.Enabled then
            if not inputService:IsMouseButtonPressed(0) and (tick() - bedwars.SwordController.lastSwing) > 0.3 then
                return false
            end
        end
        if LegitAura.Enabled and (tick() - bedwars.SwordController.lastSwing) > 0.3 then
            return false
        end
        if (lplr.Character:GetAttribute('StunnedUntilTime') or 0) - workspace:GetServerTimeNow() > 0 then
            return false
        end
        if bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then
            return false
        end
        local sword = Limit.Enabled and store.hand or store.tools.sword
        if not sword or not sword.tool then return false end
        local meta = bedwars.ItemMeta[sword.tool.Name]
        if Limit.Enabled then
            if store.hand.toolType ~= 'sword' or bedwars.DaoController.chargingMaid then
                return false
            end
        end
        return sword, meta
    end

    local function ease(t)
        return t < 0.5 and 4 * t * t * t or 1 - math.pow(-2 * t + 2, 3) / 2
    end

    local function findAim(localcframe, ent, fps, started)
        local prog = ease(math.min((tick() - started) / (1 / (Speed.Value * 0.5)), 1))
        local speed = Speed.Value * prog
        return localcframe:Lerp(CFrame.lookAt(localcframe.p, ent.RootPart.Position), speed * fps), speed
    end

    local function fireWhim(ent, pos)
        local book = getItem('mage_spellbook')
        if not book then return end

        local oldtool = store.hand.tool
        local oldhotbar = store.inventory.hotbarSlot
        local hotbar = getHotbar(book.tool)

        if hotbar then
            switchItem(book.tool)
            hotbarSwitch(hotbar)
        end

        task.wait(0.05)

        pcall(function()
            bedwars.Client:Get(remotes.MageSelect):SendToServer({
                target = ent.Character
            })
        end)

        lastWhimShot = tick() + 0.5

        task.spawn(function()
            task.wait(0.1)
            if oldtool then
                switchItem(oldtool)
                hotbarSwitch(oldhotbar)
            end
        end)
    end

    ClosestSilentAim = vape.Categories.Combat:CreateModule({
        Name = 'Closest Silent Aim 2',
        Function = function(callback)
            if callback then
                local lastent, lastfound = nil, 0
                local foundat = tick()

                ClosestSilentAim:Clean(runService.PostSimulation:Connect(function(dt)
                    if entitylib.isAlive and tick() - lastfound < 0.5 then
                        entitylib.character.Humanoid.AutoRotate = not SilentAim.Enabled
                        local cframe, speed = findAim(gameCamera.CFrame, lastent, dt, foundat)
                        if SilentAim.Enabled then
                            entitylib.character.RootPart.CFrame = entitylib.character.RootPart.CFrame:Lerp(CFrame.lookAt(entitylib.character.RootPart.Position, Vector3.new(lastent.RootPart.Position.X, entitylib.character.RootPart.Position.Y, lastent.RootPart.Position.Z)), (speed + 2) * dt)
                        else
                            gameCamera.CFrame = cframe
                        end
                    elseif entitylib.isAlive then
                        entitylib.character.Humanoid.AutoRotate = true
                    end
                end))

                repeat
                    task.wait()
                    -- don't hit while AutoLumen is actively charging the wave
                    if store.equippedKit == 'lumen' then
                        local ok, charging = pcall(function()
                            return bedwars.SwordChargeController:getChargeState() ~= bedwars.ChargeState.Idle
                        end)
                        if ok and charging then continue end
                    end
                    local sword, meta = getAttackData()
                    if sword then
                        local localPosition = entitylib.character.RootPart.Position
                        local ent = entitylib.EntityPosition({
                            Origin = localPosition,
                            Range = bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE + Range.Value,
                            Wallcheck = Targets.Walls.Enabled or nil,
                            Part = 'RootPart',
                            Players = Targets.Players.Enabled,
                            NPCs = Targets.NPCs.Enabled,
                            Limit = 1,
                            Sort = sortmethods[Mode.Value] or sortmethods.Distance,
                        })

                        if ent then
                            if not store.hand or store.hand.tool ~= sword.tool then
                                local hotbar = getHotbar(sword.tool)
                                if hotbar then
                                    hotbarSwitch(hotbar)
                                else
                                    continue
                                end
                            end

                            local localfacing = (inputService.KeyboardEnabled and gameCamera or entitylib.character.RootPart).CFrame.LookVector * Vector3.new(1, 0, 1)
                            local delta = (ent.RootPart.Position - localPosition)
                            local flat = delta * Vector3.new(1, 0, 1)
                            local facingdot = flat.Magnitude > 0 and localfacing.Magnitude > 0 and (localfacing / localfacing.Magnitude):Dot(flat / flat.Magnitude) or 0
                            if facingdot < math.cos(math.rad(Angle.Value) / 2) then
                                continue
                            end

                            if not LegitAura.Enabled and (tick() - bedwars.SwordController.lastSwing) >= (Perfect.Enabled and (meta.sword.attackSpeed or 0.11) or math.max(SwingTime.Value, 0.11)) then
                                bedwars.SwordController:playSwordEffect(meta, false)
                                bedwars.SwordController.lastSwing = tick()
                            end

                            if lastent ~= ent then
                                foundat = tick()
                            end
                            lastent, lastfound = ent, tick()

                            local minInterval = meta.sword.attackSpeed or 0.33
                            local current, delay = tick(), math.max(1 / math.max(Hitreg.Value, 1), minInterval)

                            if delta.Magnitude > bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE then
                                if (current - lastHit) >= delay then
                                    lastHit = current
                                    pcall(SwingMissRemote.FireServer, SwingMissRemote, {chargeRatio = 0, weapon = sword.tool})
                                end
                                continue
                            end

                            if (current - lastHit) >= delay then
                                lastHit = lastHit + delay
                                if current - lastHit > delay then
                                    lastHit = current
                                end
                                local dir = CFrame.lookAt(localPosition, ent.RootPart.Position).LookVector
                                local pos = localPosition + dir * math.max(delta.Magnitude - 14.4, 0)
                                bedwars.SwordController.lastAttack = workspace:GetServerTimeNow()
                                AttackRemote:FireServer({
                                    weapon = sword.tool,
                                    chargedAttack = {chargeRatio = 0},
                                    entityInstance = ent.Character,
                                    validate = {
                                        raycast = {
                                            cameraPosition = {value = pos},
                                            cursorDirection = {value = dir},
                                        },
                                        targetPosition = {value = ent.RootPart.Position},
                                        selfPosition = {value = pos},
                                    },
                                })

                                if WhimFastHits.Enabled and tick() > lastWhimShot then
                                    task.spawn(fireWhim, ent, pos)
                                end

                                if FastHits.Enabled and tick() > lastShot and not entitylib.Wallcheck(localPosition, ent.RootPart.Position, {gameCamera, lplr.Character, ent.Character}) then
                                    local projectiles = getProjectiles()
                                    if #projectiles > 0 then
                                        local item, ammo, projectile, itemMeta = unpack(projectiles[1])
                                        if tick() > (FireRates[item.itemType] or 0) then
                                            local projmeta = bedwars.ProjectileMeta[projectile]
                                            local projSpeed, gravity = projmeta.launchVelocity, projmeta.gravitationalAcceleration or 196.2
                                            local chargeDur = 0
                                            local oldhotbar, oldtool = store.inventory.hotbarSlot, store.hand.tool
                                            local hotbar = getHotbar(item.tool)
                                            if hotbar then
                                                switchItem(item.tool)
                                                if Legit.Enabled then
                                                    hotbarSwitch(hotbar)
                                                end
                                            end

                                            local calc = prediction.SolveTrajectory(localPosition, projSpeed, gravity, ent.RootPart.Position, ent.RootPart.Velocity, workspace.Gravity, ent.HipHeight, ent.Jumping and 42.6 or nil, nil, nil, lplr:GetNetworkPing())
                                            if calc then
                                                local sdir = CFrame.lookAt(localPosition, calc).LookVector
                                                local id = httpService:GenerateGUID(true)
                                                local shootPosition = (CFrame.new(localPosition, calc) * CFrame.new(Vector3.new(-bedwars.BowConstantsTable.RelX, -bedwars.BowConstantsTable.RelY, -bedwars.BowConstantsTable.RelZ))).Position

                                                bedwars.ProjectileController:createLocalProjectile(itemMeta, ammo, projectile, shootPosition, id, sdir * projSpeed, {drawDurationSeconds = chargeDur})
                                                local res = projectileRemote:InvokeServer(
                                                    item.tool,
                                                    ammo,
                                                    projectile,
                                                    shootPosition,
                                                    pos,
                                                    sdir * projSpeed,
                                                    id,
                                                    {
                                                        drawDurationSeconds = chargeDur,
                                                        shotId = httpService:GenerateGUID(false)
                                                    },
                                                    workspace:GetServerTimeNow() - 0.045
                                                )
                                                if res then
                                                    res.Parent = replicatedStorage
                                                    FireRates[item.itemType] = tick() + itemMeta.fireDelaySec
                                                    local shoot = itemMeta.launchSound
                                                    shoot = shoot and shoot[math.random(1, #shoot)] or nil
                                                    if shoot and bedwars.SoundManager then
                                                        pcall(bedwars.SoundManager.playSound, bedwars.SoundManager, shoot)
                                                    end
                                                end
                                                lastShot = tick() + (lplr:GetNetworkPing() + FireRate.Value)
                                            end

                                            task.spawn(function()
                                                task.wait(0.05)
                                                -- Re-look up the sword fresh so we never
                                                -- hit the Parent == nil guard in switchItem
                                                local s = store.tools and store.tools.sword
                                                if s and s.tool then
                                                    switchItem(s.tool, 0)
                                                end
                                                hotbarSwitch(oldhotbar)
                                            end)
                                        end
                                    end
                                end

                                if FastHits2.Enabled and tick() > lastShot2 and not entitylib.Wallcheck(localPosition, ent.RootPart.Position, {gameCamera, lplr.Character, ent.Character}) then
                                    local projectiles = getProjectiles2()
                                    if #projectiles > 0 then
                                        local item, ammo, projectile, itemMeta = unpack(projectiles[1])
                                        if tick() > (FireRates2[item.itemType] or 0) then
                                            local projmeta = bedwars.ProjectileMeta[projectile]
                                            local projSpeed, gravity = projmeta.launchVelocity, projmeta.gravitationalAcceleration or 196.2
                                            local chargeDur = 0
                                            local oldhotbar, oldtool = store.inventory.hotbarSlot, store.hand.tool
                                            local hotbar = getHotbar(item.tool)
                                            if hotbar then
                                                switchItem(item.tool)
                                                if Legit2.Enabled then
                                                    hotbarSwitch(hotbar)
                                                end
                                            end

                                            local calc = prediction.SolveTrajectory(localPosition, projSpeed, gravity, ent.RootPart.Position, ent.RootPart.Velocity, workspace.Gravity, ent.HipHeight, ent.Jumping and 42.6 or nil, nil, nil, lplr:GetNetworkPing())
                                            if calc then
                                                local sdir = CFrame.lookAt(localPosition, calc).LookVector
                                                local id = httpService:GenerateGUID(true)
                                                local shootPosition = (CFrame.new(localPosition, calc) * CFrame.new(Vector3.new(-bedwars.BowConstantsTable.RelX, -bedwars.BowConstantsTable.RelY, -bedwars.BowConstantsTable.RelZ))).Position

                                                bedwars.ProjectileController:createLocalProjectile(itemMeta, ammo, projectile, shootPosition, id, sdir * projSpeed, {drawDurationSeconds = chargeDur})
                                                local res = projectileRemote:InvokeServer(
                                                    item.tool,
                                                    ammo,
                                                    projectile,
                                                    shootPosition,
                                                    pos,
                                                    sdir * projSpeed,
                                                    id,
                                                    {
                                                        drawDurationSeconds = chargeDur,
                                                        shotId = httpService:GenerateGUID(false)
                                                    },
                                                    workspace:GetServerTimeNow() - 0.045
                                                )
                                                if res then
                                                    res.Parent = replicatedStorage
                                                    FireRates2[item.itemType] = tick() + itemMeta.fireDelaySec
                                                    local shoot = itemMeta.launchSound
                                                    shoot = shoot and shoot[math.random(1, #shoot)] or nil
                                                    if shoot and bedwars.SoundManager then
                                                        pcall(bedwars.SoundManager.playSound, bedwars.SoundManager, shoot)
                                                    end
                                                end
                                                lastShot2 = tick() + (lplr:GetNetworkPing() + FireRate2.Value)
                                            end

                                            task.spawn(function()
                                                task.wait(0.05)
                                                local s = store.tools and store.tools.sword
                                                if s and s.tool then switchItem(s.tool, 0) end
                                                hotbarSwitch(oldhotbar)
                                            end)
                                        end
                                    end
                                end

                                if PoisonFastHits.Enabled and tick() > lastPoisonShot and not entitylib.Wallcheck(localPosition, ent.RootPart.Position, {gameCamera, lplr.Character, ent.Character}) then
                                    local poison = getItem('poison_splash_potion')
                                    if poison then
                                        local oldhotbar, oldtool = store.inventory.hotbarSlot, store.hand.tool
                                        local hotbar = getHotbar(poison.tool)
                                        switchItem(poison.tool)
                                        if PoisonLegit.Enabled and hotbar then hotbarSwitch(hotbar) end

                                        local targetPos = ent.RootPart.Position
                                        local projmeta = bedwars.ProjectileMeta.poison_splash_potion
                                        local projSpeed = projmeta and projmeta.launchVelocity or 50
                                        local gravity = projmeta and projmeta.gravitationalAcceleration or 196.2

                                        local calc = prediction.SolveTrajectory(localPosition, projSpeed, gravity, targetPos, ent.RootPart.Velocity, workspace.Gravity, ent.HipHeight, ent.Jumping and 42.6 or nil, nil, nil, lplr:GetNetworkPing())
                                        local aimPos = calc or targetPos
                                        local shootPosition = (CFrame.new(localPosition, aimPos) * CFrame.new(Vector3.new(-bedwars.BowConstantsTable.RelX, -bedwars.BowConstantsTable.RelY, -bedwars.BowConstantsTable.RelZ))).Position

                                        bedwars.Client:Get(remotes.FireProjectile):CallServerAsync(
                                            poison.tool,
                                            'poison_splash_potion',
                                            'poison_splash_potion',
                                            shootPosition,
                                            localPosition,
                                            CFrame.lookAt(localPosition, aimPos).LookVector * projSpeed,
                                            httpService:GenerateGUID(true),
                                            {
                                                drawDurationSeconds = 1,
                                                shotId = httpService:GenerateGUID(false),
                                            },
                                            workspace:GetServerTimeNow() - 0.045
                                        )

                                        lastPoisonShot = tick() + PoisonFireRate.Value

                                        task.spawn(function()
                                            if PoisonLegit.Enabled then
                                                if oldtool then switchItem(oldtool) end
                                                hotbarSwitch(oldhotbar)
                                            end
                                        end)
                                    end
                                end

                                if VoidAxeFastHits.Enabled and tick() > lastVoidAxeShot then
                                    local voidaxe = getItem('void_axe')
                                    if voidaxe and bedwars.AbilityController:canUseAbility('void_axe_jump') then
                                        local oldhotbar, oldtool = store.inventory.hotbarSlot, store.hand.tool
                                        local hotbar = getHotbar(voidaxe.tool)
                                        switchItem(voidaxe.tool)
                                        if VoidAxeLegit.Enabled and hotbar then hotbarSwitch(hotbar) end

                                        bedwars.AbilityController:useAbility('void_axe_jump', newproxy(true), {
                                            target = ent.RootPart.Position,
                                            entityInstance = ent.Character,
                                        })
                                        lastVoidAxeShot = tick() + VoidAxeFireRate.Value

                                        task.spawn(function()
                                            task.wait(0.1)
                                            if VoidAxeLegit.Enabled then
                                                if oldtool then switchItem(oldtool) end
                                                hotbarSwitch(oldhotbar)
                                            end
                                        end)
                                    end
                                end

                                if FrostStaffHits.Enabled and tick() > lastFrostShot and tick() > frostFireDelay and not entitylib.Wallcheck(localPosition, ent.RootPart.Position, {gameCamera, lplr.Character, ent.Character}) then
                                    local staff, projectile = getFrostStaff()
                                    if staff then
                                        local itemMeta = bedwars.ItemMeta[staff.itemType]
                                        local projmeta = bedwars.ProjectileMeta[projectile]
                                        if projmeta then
                                            local drawDurationSec = 0.05
                                            local maxChargeSec = itemMeta.projectileSource.maxStretchChargeSec or 1
                                            local chargeRatio = drawDurationSec / maxChargeSec
                                            local projSpeed = projmeta.launchVelocity * (0.5 + 0.5 * chargeRatio)
                                            local gravity = projmeta.gravitationalAcceleration or 196.2
                                            local oldhotbar, oldtool = store.inventory.hotbarSlot, store.hand.tool
                                            local hotbar = getHotbar(staff.tool)
                                            if hotbar then
                                                switchItem(staff.tool)
                                                if FrostLegit.Enabled then
                                                    hotbarSwitch(hotbar)
                                                end
                                            end
                                            local calc = prediction.SolveTrajectory(localPosition, projSpeed, gravity, ent.RootPart.Position, ent.RootPart.Velocity, workspace.Gravity, ent.HipHeight, ent.Jumping and 42.6 or nil, nil, nil, lplr:GetNetworkPing())
                                            if calc then
                                                local sdir = CFrame.lookAt(localPosition, calc).LookVector
                                                local id = httpService:GenerateGUID(true)
                                                local shootPosition = (CFrame.new(localPosition, calc) * CFrame.new(Vector3.new(-bedwars.BowConstantsTable.RelX, -bedwars.BowConstantsTable.RelY, -bedwars.BowConstantsTable.RelZ))).Position
                                                bedwars.ProjectileController:createLocalProjectile(itemMeta, projectile, projectile, shootPosition, id, sdir * projSpeed, {drawDurationSec = drawDurationSec})
                                                local res = projectileRemote:InvokeServer(
                                                    staff.tool, projectile, projectile,
                                                    shootPosition, pos, sdir * projSpeed,
                                                    id,
                                                    {
                                                        drawDurationSec = drawDurationSec,
                                                        shotId = httpService:GenerateGUID(false),
                                                    },
                                                    workspace:GetServerTimeNow() - 0.045
                                                )
                                                if res then
                                                    pcall(function() res.Parent = replicatedStorage end)
                                                    frostFireDelay = tick() + (itemMeta.projectileSource.fireDelaySec or 1)
                                                    local shoot = itemMeta.projectileSource.launchSound
                                                    shoot = shoot and shoot[math.random(1, #shoot)] or nil
                                                    if shoot and bedwars.SoundManager then pcall(bedwars.SoundManager.playSound, bedwars.SoundManager, shoot) end
                                                end
                                                lastFrostShot = tick() + (lplr:GetNetworkPing() + FrostFireRate.Value)
                                            end
                                            task.spawn(function()
                                                if FrostLegit.Enabled then
                                                    hotbarSwitch(oldhotbar)
                                                    if oldtool then switchItem(oldtool) end
                                                end
                                            end)
                                        end
                                    end
                                end

                            end
                        else
                            lastfound = 0
                        end
                    else
                        lastfound = 0
                    end
                until not ClosestSilentAim.Enabled
            else
                if entitylib.isAlive then
                    entitylib.character.Humanoid.AutoRotate = true
                end
            end
        end,
        Tooltip = 'Silent Aim with Hitreg and triple FastHits',
    })

    Targets = ClosestSilentAim:CreateTargets({Players = true, NPCs = true})
    Speed = ClosestSilentAim:CreateSlider({
        Name = 'Aim speed',
        Min = 1,
        Max = 10,
        Default = 6,
        Decimal = 5,
    })
    SwingTime = ClosestSilentAim:CreateSlider({
        Name = 'Swing time',
        Visible = false,
        Darker = true,
        Min = 0,
        Max = 0.5,
        Default = 0.42,
        Decimal = 100,
    })
    Range = ClosestSilentAim:CreateSlider({
        Name = 'Extra swing distance',
        Min = 0,
        Max = 6,
        Suffix = function(val)
            return val <= 1 and 'stud' or 'studs'
        end,
        Decimal = 5,
        Default = 3,
    })
    Angle = ClosestSilentAim:CreateSlider({
        Name = 'Max angle',
        Min = 1,
        Max = 360,
        Default = 180,
    })
    Hitreg = ClosestSilentAim:CreateSlider({
        Name = 'Hitreg',
        Min = 1,
        Max = 36,
        Default = 36,
        Suffix = 'reg',
    })
    Mode = ClosestSilentAim:CreateDropdown({
        Name = 'Target mode',
        List = {'Distance', 'Health', 'Damage'},
        Default = 'Health',
    })
    Perfect = ClosestSilentAim:CreateToggle({
        Name = 'Perfect Swing',
        Function = function(callback)
            SwingTime.Object.Visible = not callback
        end,
        Default = true,
    })
    Mouse = ClosestSilentAim:CreateToggle({Name = 'Require mouse down'})
    LegitAura = ClosestSilentAim:CreateToggle({Name = 'Swing only'})
    SilentAim = ClosestSilentAim:CreateToggle({
        Name = 'Silent Aim',
        Default = true,
    })
    Limit = ClosestSilentAim:CreateToggle({Name = 'Limit to items'})
    WhimFastHits = ClosestSilentAim:CreateToggle({
        Name = 'Whim Fast Hits',
        Default = false,
    })
    FastHits = ClosestSilentAim:CreateToggle({
        Name = 'Fast Hits',
        Default = false,
        Function = function(callback)
            pcall(function()
                Legit.Object.Visible = callback
                FireRate.Object.Visible = callback
                Whitelist.Object.Visible = callback
            end)
        end
    })
    Whitelist = ClosestSilentAim:CreateTextList({
        Name = 'Projectiles',
        Default = {'arrow'},
        Darker = true,
        Visible = false,
    })
    Legit = ClosestSilentAim:CreateToggle({
        Name = 'Legit Switch',
        Darker = true,
        Visible = false,
    })
    FireRate = ClosestSilentAim:CreateSlider({
        Name = 'Fire rate',
        Suffix = 'seconds',
        Min = 0,
        Max = 2,
        Decimal = 100,
        Darker = true,
        Visible = false,
        Default = 1.2,
    })
    FastHits2 = ClosestSilentAim:CreateToggle({
        Name = 'Fast Hits 2',
        Default = false,
        Function = function(callback)
            pcall(function()
                Legit2.Object.Visible = callback
                FireRate2.Object.Visible = callback
                Whitelist2.Object.Visible = callback
            end)
        end
    })
    Whitelist2 = ClosestSilentAim:CreateTextList({
        Name = 'Projectiles 2',
        Default = {'frosted_snowball'},
        Darker = true,
        Visible = false,
    })
    Legit2 = ClosestSilentAim:CreateToggle({
        Name = 'Legit Switch 2',
        Darker = true,
        Visible = false,
    })
    FireRate2 = ClosestSilentAim:CreateSlider({
        Name = 'Fire rate 2',
        Suffix = 'seconds',
        Min = 0,
        Max = 2,
        Decimal = 100,
        Darker = true,
        Visible = false,
        Default = 0.45,
    })
    FrostStaffHits = ClosestSilentAim:CreateToggle({
        Name = 'Frost Staff Hits',
        Default = false,
        Function = function(callback)
            pcall(function()
                FrostLegit.Object.Visible = callback
                FrostFireRate.Object.Visible = callback
            end)
        end
    })
    FrostLegit = ClosestSilentAim:CreateToggle({
        Name = 'Frost Legit Switch',
        Darker = true,
        Visible = false,
    })
    FrostFireRate = ClosestSilentAim:CreateSlider({
        Name = 'Frost fire rate',
        Suffix = 'seconds',
        Min = 0,
        Max = 2,
        Decimal = 100,
        Darker = true,
        Visible = false,
        Default = 0.45,
    })
    PoisonFastHits = ClosestSilentAim:CreateToggle({
        Name = 'Poison Fast Hits',
        Default = false,
        Function = function(callback)
            pcall(function()
                PoisonLegit.Object.Visible = callback
                PoisonFireRate.Object.Visible = callback
            end)
        end
    })
    PoisonLegit = ClosestSilentAim:CreateToggle({
        Name = 'Poison Legit Switch',
        Darker = true,
        Visible = false,
    })
    PoisonFireRate = ClosestSilentAim:CreateSlider({
        Name = 'Poison fire rate',
        Suffix = 'seconds',
        Min = 0,
        Max = 2,
        Decimal = 100,
        Darker = true,
        Visible = false,
        Default = 1.2,
    })
    VoidAxeFastHits = ClosestSilentAim:CreateToggle({
        Name = 'Void Axe Fast Hits',
        Default = false,
        Function = function(callback)
            pcall(function()
                VoidAxeLegit.Object.Visible = callback
                VoidAxeFireRate.Object.Visible = callback
            end)
        end
    })
    VoidAxeLegit = ClosestSilentAim:CreateToggle({
        Name = 'Void Axe Legit Switch',
        Darker = true,
        Visible = false,
    })
    VoidAxeFireRate = ClosestSilentAim:CreateSlider({
        Name = 'Void Axe fire rate',
        Suffix = 'seconds',
        Min = 0,
        Max = 2,
        Decimal = 100,
        Darker = true,
        Visible = false,
        Default = 1.2,
    })
end)
run(function()
    local WhimAuto
    local Targets
    local Range
    local FireRate
    local Sort
    local Legit
    local SwingOnly
    local Angle
    local lastWhimShot = tick()
    local projectileRemote = {InvokeServer = function(self, ...) end}

    task.spawn(function()
        projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
    end)

    WhimAuto = vape.Categories.Combat:CreateModule({
        Name = 'Whim Fast Hits',
        Function = function(callback)
            if callback then
                repeat
                    local mana, book, localPosition, ent
                    task.wait()
                    if not entitylib.isAlive then continue end
                    if bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then continue end
                    if store.hand.toolType ~= 'sword' then continue end
                    if SwingOnly.Enabled and (tick() - bedwars.SwordController.lastSwing) > 0.3 then continue end
                    if tick() < lastWhimShot then continue end

                    mana = lplr:GetAttribute('Mana') or 0
                    if mana < 20 then continue end

                    book = getItem('mage_spellbook') or getItem('magic_stick')
                    if not book then continue end

                    localPosition = entitylib.character.RootPart.Position
                    ent = entitylib.EntityPosition({
                        Origin = localPosition,
                        Range = Range.Value,
                        Wallcheck = Targets.Walls.Enabled or nil,
                        Part = 'RootPart',
                        Players = Targets.Players.Enabled,
                        NPCs = Targets.NPCs.Enabled,
                        Limit = 1,
                        Sort = sortmethods[Sort.Value] or sortmethods.Distance,
                    })

                    if ent and not entitylib.Wallcheck(localPosition, ent.RootPart.Position, {gameCamera, lplr.Character, ent.Character}) then
                        local delta = (ent.RootPart.Position - localPosition)
                        local flat = delta * Vector3.new(1, 0, 1)
                        local localfacing = (inputService.KeyboardEnabled and gameCamera or entitylib.character.RootPart).CFrame.LookVector * Vector3.new(1, 0, 1)
                        local facingdot = flat.Magnitude > 0 and localfacing.Magnitude > 0 and (localfacing / localfacing.Magnitude):Dot(flat / flat.Magnitude) or 0
                        if facingdot < math.cos(math.rad(Angle.Value) / 2) then continue end

                        targetinfo.Targets[ent] = tick() + 1

                        local projectile = 'mage_spell_base'
                        for _, child in pairs(lplr.Character:GetChildren()) do
                            if child.Name:find('MageHat') then
                                local element = child.Name:gsub('MageHat', ''):lower()
                                local candidate = 'mage_spell_' .. element
                                if bedwars.ProjectileMeta[candidate] then
                                    projectile = candidate
                                    break
                                end
                            end
                        end

                        -- set timer BEFORE firing so it never spams
                        lastWhimShot = tick() + FireRate.Value

                        local projmeta = bedwars.ProjectileMeta[projectile]
                        local projSpeed = projmeta.launchVelocity
                        local gravity = projmeta.gravitationalAcceleration or 196.2
                        local oldhotbar = store.inventory.hotbarSlot
                        local oldtool = store.hand.tool
                        local hotbar = getHotbar(book.tool)

                        if hotbar then
                            switchItem(book.tool)
                            if Legit.Enabled then
                                hotbarSwitch(hotbar)
                            end
                        end

                        local calc = prediction.SolveTrajectory(
                            localPosition, projSpeed, gravity,
                            ent.RootPart.Position, ent.RootPart.Velocity,
                            workspace.Gravity, ent.HipHeight,
                            ent.Jumping and 42.6 or nil,
                            nil, nil, lplr:GetNetworkPing()
                        )

                        if calc then
                            local sdir = CFrame.lookAt(localPosition, calc).LookVector
                            local id = httpService:GenerateGUID(true)
                            local shootPosition = (CFrame.new(localPosition, calc) * CFrame.new(Vector3.new(
                                -bedwars.BowConstantsTable.RelX,
                                -bedwars.BowConstantsTable.RelY,
                                -bedwars.BowConstantsTable.RelZ
                            ))).Position

                            bedwars.ProjectileController:createLocalProjectile(projmeta, projectile, projectile, shootPosition, id, sdir * projSpeed, {drawDurationSeconds = 1})
                            local res = projectileRemote:InvokeServer(
                                book.tool,
                                projectile,
                                projectile,
                                shootPosition,
                                localPosition,
                                sdir * projSpeed,
                                id,
                                {
                                    drawDurationSeconds = 1,
                                    shotId = httpService:GenerateGUID(false)
                                },
                                workspace:GetServerTimeNow() - 0.045
                            )
                            if res then
                                res.Parent = replicatedStorage
                            end
                        end

                        task.spawn(function()
                            task.wait(0.3)
                            if oldtool then
                                switchItem(oldtool)
                                if Legit.Enabled then
                                    hotbarSwitch(oldhotbar)
                                end
                            end
                        end)
                    end
                until not WhimAuto.Enabled
            end
        end,
        Tooltip = 'Fires mage spell alongside sword attacks',
    })

    Targets = WhimAuto:CreateTargets({Players = true, NPCs = true})
    local methods = {'Damage', 'Distance'}
    for i in sortmethods do
        if not table.find(methods, i) then
            table.insert(methods, i)
        end
    end
    Sort = WhimAuto:CreateDropdown({
        Name = 'Target mode',
        List = methods,
        Default = 'Health',
    })
    Range = WhimAuto:CreateSlider({
        Name = 'Range',
        Min = 1,
        Max = 50,
        Default = 30,
        Suffix = function(val)
            return val <= 1 and 'stud' or 'studs'
        end,
    })
    Angle = WhimAuto:CreateSlider({
        Name = 'Max angle',
        Min = 1,
        Max = 360,
        Default = 180,
    })
    FireRate = WhimAuto:CreateSlider({
        Name = 'Fire Rate',
        Min = 0,
        Max = 2,
        Default = 0.66,
        Decimal = 100,
        Suffix = 'seconds',
    })
    SwingOnly = WhimAuto:CreateToggle({
        Name = 'Swing Only',
        Default = true,
        Tooltip = 'Only fires when actively swinging sword',
    })
    Legit = WhimAuto:CreateToggle({
        Name = 'Legit Switch',
        Default = false,
    })
end)
run(function()
    local ItemSuspend
    local FreezeDelay
    local Lifetime
    local FrozenItems = {}

    ItemSuspend = vape.Categories.Utility:CreateModule({
        Name = 'Item Suspend',
        Function = function(callback)
            if callback then
                repeat
                    if entitylib.isAlive then
                        local items = collectionService:GetTagged('ItemDrop')
                        for _, item in items do
                            if item and item.Parent then
                                local dropTime = item:GetAttribute('ClientDropTime') or tick()
                                local timeSinceDrop = tick() - dropTime
                                if not FrozenItems[item] then
                                    FrozenItems[item] = { droppedAt = dropTime, frozenPosition = nil, frozenAt = nil }
                                end
                                local frozen = FrozenItems[item]
                                if timeSinceDrop >= FreezeDelay.Value and not frozen.frozenPosition then
                                    frozen.frozenPosition = item.Position
                                    frozen.frozenAt = tick()
                                end
                                if frozen.frozenPosition then
                                    item.Position = frozen.frozenPosition
                                    for _, part in item:GetDescendants() do
                                        if part:IsA('BasePart') then
                                            part.Velocity = Vector3.new(0, 0, 0)
                                            part.RotVelocity = Vector3.new(0, 0, 0)
                                            part.CanCollide = false
                                        end
                                    end
                                    if tick() - frozen.frozenAt > Lifetime.Value then
                                        FrozenItems[item] = nil
                                    end
                                end
                            end
                        end
                        for item, _ in FrozenItems do
                            if not item or not item.Parent then FrozenItems[item] = nil end
                        end
                    end
                    task.wait(0.05)
                until not ItemSuspend.Enabled
                FrozenItems = {}
            end
        end,
        Tooltip = 'Items fall normally then freeze at a set delay'
    })
    FreezeDelay = ItemSuspend:CreateSlider({
        Name = 'Freeze After', Min = 0, Max = 10, Default = 2, Decimal = 10,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end
    })
    Lifetime = ItemSuspend:CreateSlider({
        Name = 'Stay Frozen', Min = 5, Max = 300, Default = 60,
        Suffix = function(val) return val == 1 and 'second' or 'seconds' end
    })
end)

run(function()
	local AutoZola
	local Mode
	local Range
	local links = {}
	local nextLink = 0
	
	local function isLinked(char)
		local expiry = links[char]
		if expiry and expiry > tick() then
			return true
		end
		links[char] = nil
		return false
	end
	
	local function countLinks()
		local count = 0
		for char in links do
			if isLinked(char) then
				count += 1
			end
		end
		return count
	end
	
	local function attemptLink(char)
		if not char or tick() < nextLink or isLinked(char) then return end
		if countLinks() >= bedwars.SoulBrokerConstants.MAX_SOUL_LINKS then return end
	
		links[char] = tick() + 1
		nextLink = tick() + 1
		bedwars.Handler:Get('AttemptSoulLink'):Fire('CallServerAsync', char)
	end
	
	AutoZola = vape.Categories.Minigames:CreateModule({
		Name = 'AutoZola',
		Function = function(callback)
			if callback then
				AutoZola:Clean(bedwars.Handler:Get('SoulLinkFormed').Remote:Connect(function(linkTable)
					if linkTable.broker == lplr and not linkTable.guard then
						links[linkTable.target] = tick() + bedwars.SoulBrokerConstants.SOUL_LINK_DURATION
					end
				end))
	
				AutoZola:Clean(bedwars.Handler:Get('SoulLinkRemoved').Remote:Connect(function(linkTable)
					if linkTable.broker == lplr and not linkTable.guard then
						links[linkTable.target] = nil
					end
				end))
	
				AutoZola:Clean(vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
					if Mode.Value ~= 'On Hit' or damageTable.fromEntity ~= lplr.Character then return end
					if not entitylib.isAlive or store.equippedKit ~= 'soul_broker' then return end
	
					local target = entitylib.getEntity(damageTable.entityInstance)
					if target and target.Player and target.Targetable and (entitylib.character.RootPart.Position - target.RootPart.Position).Magnitude <= Range.Value then
						attemptLink(target.Character)
					end
				end))
	
				repeat
					if Mode.Value == 'On See' and tick() >= nextLink and entitylib.isAlive and store.equippedKit == 'soul_broker' then
						for _, target in entitylib.AllPosition({
							Range = Range.Value,
							Part = 'RootPart',
							Players = true,
							Wallcheck = true
						}) do
							if not isLinked(target.Character) then
								attemptLink(target.Character)
								break
							end
						end
					end
					task.wait(0.1)
				until not AutoZola.Enabled
			end
		end,
		Tooltip = 'Automatically soul links enemies'
	})
	Mode = AutoZola:CreateDropdown({
		Name = 'Mode',
		List = {'On See', 'On Hit'},
		Tooltip = 'On See - Links enemies as soon as you can see them\nOn Hit - Links enemies whenever you hit them',
		Default = 'On See'
	})
	Range = AutoZola:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 50,
		Default = 30,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end
	})
end)

run(function()
    local AutoWren
    local Rate

    local captured = nil
    local spamConns = {}

    local function autoLearn()
        local learnLog = {}
        local learning = true
        local old

        local ok = pcall(function()
            local mt = getrawmetatable(game)
            old = mt.__namecall
            setreadonly(mt, false)
            mt.__namecall = newcclosure(function(self, ...)
                local method = getnamecallmethod()
                if learning and (method == 'FireServer' or method == 'InvokeServer') then
                    if not (checkcaller and checkcaller()) then
                        local entry = learnLog[self]
                        if entry then
                            entry.count = entry.count + 1
                        else
                            learnLog[self] = {count = 1, method = method, args = {...}}
                        end
                    end
                end
                return old(self, ...)
            end)
            setreadonly(mt, true)
        end)

        if not ok then
            notif('Auto Wren', 'Hook failed — executor lacks support', 5, 'alert')
            return false
        end

        pcall(function() bedwars.AbilityController:useAbility('open_black_market') end)
        task.wait(0.3)

        learning = false
        pcall(function()
            local mt = getrawmetatable(game)
            setreadonly(mt, false)
            mt.__namecall = old
            setreadonly(mt, true)
        end)

        local best, bestCount
        for remote, e in pairs(learnLog) do
            if remote and remote.Parent then
                if not bestCount or e.count < bestCount then
                    best, bestCount = remote, e.count
                end
            end
        end

        if best then
            local e = learnLog[best]
            captured = {remote = best, method = e.method, args = e.args}
            notif('Auto Wren', 'Learned: ' .. best.Name, 3, 'info')
            return true
        end
        notif('Auto Wren', 'Nothing captured — wrong kit?', 5, 'alert')
        return false
    end

    local function fireCaptured()
        if not captured then return end
        local r, m, a = captured.remote, captured.method, captured.args
        if not (r and r.Parent) then return end
        if m == 'InvokeServer' then
            task.spawn(function() pcall(r.InvokeServer, r, unpack(a)) end)
        else
            pcall(r.FireServer, r, unpack(a))
        end
    end

    local function startSpam()
        local function pass()
            if not AutoWren.Enabled then return end
            for _ = 1, Rate.Value do fireCaptured() end
        end
        AutoWren:Clean(runService.Heartbeat:Connect(pass))
        pcall(function() AutoWren:Clean(runService.RenderStepped:Connect(pass)) end)
        pcall(function() AutoWren:Clean(runService.Stepped:Connect(pass)) end)
    end

    AutoWren = vape.Categories.Kits:CreateModule({
        Name = 'Auto Wren',
        Function = function(callback)
            if callback then
                task.spawn(function()
                    repeat task.wait() until store.equippedKit ~= '' and store.matchState ~= 0 or not AutoWren.Enabled
                    if not AutoWren.Enabled then return end
                    if not captured then
                        if not autoLearn() then return end
                    end
                    startSpam()
                end)
            end
        end,
        Tooltip = 'Auto-learns Wren remote on enable, spams on Heartbeat + RenderStepped + Stepped. No button press needed.'
    })

    Rate = AutoWren:CreateSlider({
        Name = 'Rate',
        Min = 1,
        Max = 1000,
        Default = 1000,
        Suffix = '/frame',
        Tooltip = 'Fires per pass. Runs on Heartbeat + RenderStepped + Stepped (3 events per frame).'
    })

    AutoWren:CreateButton({
        Name = 'Re-Learn',
        Tooltip = 'Re-captures the remote if it broke.',
        Function = function()
            task.spawn(autoLearn)
        end
    })
end)

run(function()
    local ViewMatchHistory
    local targetName = lplr.Name

    local matchHistoryApp
    pcall(function()
        local apps = bedwars.AppController:getApps() or bedwars.AppController.apps or bedwars.AppController._apps
        if apps then
            for id, cfg in pairs(apps) do
                if tostring(id):find('MatchHistory') or tostring(id):find('matchHistory') then
                    matchHistoryApp = cfg.app or cfg
                    break
                end
            end
        end
    end)
    if not matchHistoryApp then
        pcall(function()
            local mhc = bedwars.MatchHistroyController
            for k, v in pairs(mhc) do
                if typeof(v) == 'table' and rawget(v, '__componentName') then
                    matchHistoryApp = v
                    break
                end
                if tostring(k):lower():find('app') and v then
                    matchHistoryApp = v
                    break
                end
            end
        end)
    end
    if not matchHistoryApp then
        pcall(function()
            for _, desc in lplr.PlayerScripts:GetDescendants() do
                if desc:IsA('ModuleScript') and desc.Name:find('match') and desc.Name:find('history') and desc.Name:find('app') then
                    local mod = require(desc)
                    matchHistoryApp = mod.MatchHistoryApp or mod.MatchHistroyApp or mod
                    break
                end
            end
        end)
    end

    ViewMatchHistory = vape.Categories.Utility:CreateModule({
        Name = "ViewMatchHistory",
        Function = function(callback)
            if callback then
                ViewMatchHistory:Toggle(false)
                local ok, err = pcall(function()
                    bedwars.MatchHistroyController:requestMatchHistory(targetName):andThen(function(Data)
                        if Data then
                            if matchHistoryApp then
                                bedwars.AppController:openApp({app = matchHistoryApp, appId = "MatchHistoryApp"}, Data)
                            else
                                notif('MatchHistory', 'App component not found. Data: ' .. tostring(#Data) .. ' entries', 5, 'alert')
                            end
                        else
                            notif('MatchHistory', 'No data returned', 3, 'alert')
                        end
                    end)
                end)
                if not ok then
                    notif('MatchHistory', tostring(err), 5, 'alert')
                end
            end
        end,
    })
    ViewMatchHistory:CreateTextBox({
        Name = 'Username',
        Default = lplr.Name,
        Function = function(val)
            targetName = val ~= '' and val or lplr.Name
        end,
    })
end)

-- king ben
run(function()
    -- king ben: compatibility shims for host builds missing these globals
    local getAccountTier = getAccountTier or function() return 0 end
    local isFrozen = isFrozen or function() return false end
    local vapeTargetInfo = vapeTargetInfo or {Targets = {}}
    local GuiLibrary = GuiLibrary
    local VirtualInputManager = VirtualInputManager or game:GetService('VirtualInputManager')
    local cloneRaycast = cloneRaycast or function()
        local r = RaycastParams.new()
        r.FilterType = Enum.RaycastFilterType.Exclude
        r.FilterDescendantsInstances = {entitylib.character and entitylib.character.Character}
        r.RespectCanCollide = false
        return r
    end
    local _losRayParams = RaycastParams.new()
    _losRayParams.FilterType = Enum.RaycastFilterType.Exclude
    _losRayParams.RespectCanCollide = false
    local hasLineOfSight = hasLineOfSight or function(from, to, targetCharacter)
        _losRayParams.FilterDescendantsInstances = {entitylib.character and entitylib.character.Character or workspace, targetCharacter}
        local result = workspace:Raycast(from, to - from, _losRayParams)
        return result == nil
    end
    local leftClick = leftClick or function()
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end)
    end
    local isFirstPerson = isFirstPerson or function()
        if not (lplr.Character and lplr.Character:FindFirstChild("Head")) then
            return false
        end
        return (lplr.Character.Head.Position - gameCamera.CFrame.Position).Magnitude < 2
    end
    -- Attacking is kept module-local so this aura does not clash with other killauras
    local Attacking
    local Killaura
    local Targets
    local Sort
    local SwingRange
    local AttackRange
    local RangeCircle
    local RangeCirclePart
    local UpdateRate
    local AngleSlider
    local MaxTargets
    local Mouse
    local Swing
    local GUI
    local BoxSwingColor
    local BoxAttackColor
    local ParticleTexture
    local ParticleColor1
    local ParticleColor2
    local ParticleSize
    local Face
    local FaceSpeed
    local Animation
    local AnimationMode
    local AnimationSpeed
    local AnimationTween
    local Limit
    local LegitAura
    local SyncHits
    local lastAttackTime = 0
    local lastManualSwing = 0
    local lastSwingServerTime = 0
    local lastSwingServerTimeDelta = 0
    local SophiaCheck
    local KAAuto
    local SwingTime
    local SwingTimeSlider
    local swingCooldown = 0
    local ContinueSwinging
    local ContinueSwingTime
    local lastTargetTime = 0
    local continueSwingCount = 0
    local Particles, Boxes = {}, {}
    local anims, AnimDelay, AnimTween, armC0 = vape.Libraries.auraanims, tick()
    local AttackRemote
    local TargetPriority
    local CustomHitReg
    local CustomHitRegSlider
    local lastCustomHitTime = 0
    local AirHit
    local AirHitsChance
    local FROZEN_THRESHOLD = 10
    local _perTargetNextHit = {}
    local FastHits
    local FastHitsMode
    local LegitSwitch
    local OldShootInterval
    local OldSwitchDelay
    local OldWaitDelay
    local OldFirstPersonCheck
    local lastOldShootTime = 0
    local Legit
    local FireRate
    local projectileRemote = {InvokeServer = function() end}
    local ProjectileDelay = {}
    local lastShot = tick()
    local Usage = 1

    task.spawn(function()
        AttackRemote = bedwars.Client:Get(remotes.AttackEntity)
        projectileRemote = bedwars.Client:Get(remotes.FireProjectile).instance
    end)

    local function canHitWithCustomReg()
        if not CustomHitReg or not CustomHitReg.Enabled then return true end
        if not CustomHitRegSlider then return true end
        local currentTime = tick()
        local delayBetweenHits = 10 / CustomHitRegSlider.Value
        if currentTime - lastCustomHitTime >= delayBetweenHits then
            lastCustomHitTime = lastCustomHitTime + delayBetweenHits
            if currentTime - lastCustomHitTime > delayBetweenHits then
                lastCustomHitTime = currentTime
            end
            return true
        end
        return false
    end

    local _dbgSpeedPrinted = false
    local function canHitTarget(char, meta)
        local now = tick()
        local swordSpeed = (meta and meta.sword and meta.sword.attackSpeed) or 0.42
        local speed = swordSpeed
        if SwingTime and SwingTime.Enabled and SwingTimeSlider then
            speed = math.max(SwingTimeSlider.Value, swordSpeed)
        end
        if not _dbgSpeedPrinted then
            _dbgSpeedPrinted = true
            warn('[LionV5] attackSpeed=' .. tostring(swordSpeed) .. ' speed=' .. tostring(speed))
        end
        -- Cap the interval at 1/35 so we target 35 hits per 10s instead of
        -- flooring conservatively at swordSpeed (which gives 34).
        speed = math.min(speed, 10 / 35)
        local nextHit = _perTargetNextHit[char] or 0
        if now >= nextHit then
            local overshoot = (nextHit > 0) and math.min(now - nextHit, speed) or 0
            _perTargetNextHit[char] = now + speed - overshoot
            return true
        end
        return false
    end

    local _t4HitCount = {}
    local _t4HitTick = {}

    local function FireAttackRemote(attackTable, ...)
        if not AttackRemote then  return end
        if not canHitWithCustomReg() then return end
        local t4ok, t4plr = pcall(function()
            return playersService:GetPlayerFromCharacter(attackTable.entityInstance)
        end)
        if t4ok and t4plr then
            local targetTier = getAccountTier(t4plr)
            if targetTier >= 99 then return end
            if targetTier >= 4 and getAccountTier(lplr) == 0 then
                local uid = t4plr.UserId
                local now = tick()
                if not _t4HitTick[uid] or now - _t4HitTick[uid] >= 1 then
                    _t4HitTick[uid] = now
                    _t4HitCount[uid] = 0
                end
                _t4HitCount[uid] = (_t4HitCount[uid] or 0) + 1
                if _t4HitCount[uid] > 32 then  return end
            end
        end

        local suc, plr = pcall(function()
            return playersService:GetPlayerFromCharacter(attackTable.entityInstance)
        end)

        local selfpos = attackTable.validate.selfPosition.value
        local targetpos = attackTable.validate.targetPosition.value
        local actualDistance = (selfpos - targetpos).Magnitude

        store.attackReach = (actualDistance * 100) // 1 / 100
        store.attackReachUpdate = tick() + 1

        if actualDistance > 13.5 and actualDistance <= 20 then
            local direction = (targetpos - selfpos).Unit
            local pullNeeded = actualDistance - 13.0
            local safePull = math.min(pullNeeded, 3.5)
            local newTarget = targetpos - direction * safePull
            attackTable.validate.targetPosition.value = newTarget
            attackTable.validate.raycast = attackTable.validate.raycast or {}
            local camPos = (
                attackTable.validate.raycast.cameraPosition and
                attackTable.validate.raycast.cameraPosition.value
            ) or (selfpos + Vector3.new(0, 1.5, 0))
            local newDir = (newTarget - camPos).Unit
            attackTable.validate.raycast.cameraPosition = {value = camPos}
            attackTable.validate.raycast.cursorDirection = {value = newDir}
        end

        if suc and plr then
            if not select(2, whitelist:get(plr)) then  return end
        end

        return AttackRemote:SendToServer(attackTable, ...)
    end

    local function createRangeCircle()
        local suc, err = pcall(function()
            if (not shared.CheatEngineMode) then
                RangeCirclePart = Instance.new("MeshPart")
                RangeCirclePart.MeshId = "rbxassetid://3726303797"
                if shared.RiseMode and GuiLibrary.GUICoreColor and GuiLibrary.GUICoreColorChanged then
                    RangeCirclePart.Color = GuiLibrary.GUICoreColor
                    GuiLibrary.GUICoreColorChanged.Event:Connect(function()
                        RangeCirclePart.Color = GuiLibrary.GUICoreColor
                    end)
                else
                    RangeCirclePart.Color = Color3.fromHSV(BoxSwingColor["Hue"], BoxSwingColor["Sat"], BoxSwingColor.Value)
                end
                RangeCirclePart.CanCollide = false
                RangeCirclePart.Anchored = true
                RangeCirclePart.Material = Enum.Material.Neon
                RangeCirclePart.Size = Vector3.new(SwingRange.Value * 0.7, 0.01, SwingRange.Value * 0.7)
                if Killaura.Enabled then
                    RangeCirclePart.Parent = gameCamera
                end
                RangeCirclePart:SetAttribute("gamecore_GameQueryIgnore", true)
            end
        end)
        if (not suc) then
            pcall(function()
                if RangeCirclePart then
                    RangeCirclePart:Destroy()
                    RangeCirclePart = nil
                end
                notif("king ben - Range Visualiser Circle", "There was an error creating the circle. Disabling...", 2)
            end)
        end
    end

    local function getAttackData()
        if SophiaCheck and SophiaCheck.Enabled then
            if isFrozen(nil, FROZEN_THRESHOLD) then
                return false
            end
        end

        if Mouse.Enabled then
            local recentSwing = LegitAura.Enabled and (tick() - bedwars.SwordController.lastSwing) <= 0.2
            if not recentSwing then
                local mousePressed = inputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
                if not mousePressed then 
                    return false 
                end
            end
        end

        if GUI.Enabled then
            if bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then return false end
        end

        local sword = Limit.Enabled and store.hand or store.tools.sword
        if not sword or not sword.tool then return false end

        local meta = bedwars.ItemMeta[sword.tool.Name]
        if Limit.Enabled then
            if store.hand.toolType ~= 'sword' or bedwars.DaoController.chargingMaid then return false end
        end

        if LegitAura.Enabled then
            if (tick() - bedwars.SwordController.lastSwing) > 0.2 then return false end
        end

        if SwingTime.Enabled then
            local swingSpeed = SwingTimeSlider.Value
            return sword, meta, (tick() - lastAttackTime) >= swingSpeed
        else
            return sword, meta, true
        end
    end
    
    local function resetSwordCooldown()
        if bedwars.SwordController then
            bedwars.SwordController.lastAttack = 0
            bedwars.SwordController.lastSwing = 0

            if bedwars.SwordController.lastChargedAttackTimeMap then
                for weaponName, _ in pairs(bedwars.SwordController.lastChargedAttackTimeMap) do
                    bedwars.SwordController.lastChargedAttackTimeMap[weaponName] = 0
                end
            end
        end
    end

    local function shouldContinueSwinging()
        if not ContinueSwinging.Enabled then return false end
        
        if lastTargetTime == 0 then
            return false
        end
        
        local timeSinceLastTarget = tick() - lastTargetTime
        local swingDuration = ContinueSwingTime.Value
        
        if timeSinceLastTarget <= swingDuration then
            return true
        end
        
        return false
    end

    local function getAmmo(check)
        for _, item in store.inventory.inventory.items do
            if check.ammoItemTypes and table.find(check.ammoItemTypes, item.itemType) then
                return item.itemType
            end
        end
        return
    end

    local function getProjectiles()
        local items = {}
        for _, item in store.inventory.inventory.items do
            local proj = bedwars.ItemMeta[item.itemType].projectileSource
            local ammo = proj and getAmmo(proj)
            if ammo and table.find({'arrow'}, ammo) then
                table.insert(items, {
                    item,
                    ammo,
                    proj.projectileType(ammo),
                    proj
                })
            end
        end
        return items
    end

    local function canShoot(proj)
        return tick() > (ProjectileDelay[proj[1].itemType] or 0)
    end

	local function shootFunc(item, ammo, projectile, itemMeta, pos, ent, ign)
			local meta = bedwars.ProjectileMeta[projectile]
			local projSpeed, gravity = meta.launchVelocity, meta.gravitationalAcceleration or 196.2
			local switched
			switched = switchItem(item.tool, 0.05)
			local targetBodyPart = ent.RootPart
			local selfVelocity = entitylib.character.RootPart and entitylib.character.RootPart.Velocity or Vector3.zero
			local targetVelocity = targetBodyPart.Velocity
			local playerGravity = workspace.Gravity
			local balloons = ent.Character and ent.Character:GetAttribute('InflatedBalloons')
			if balloons and balloons > 0 then
				playerGravity = workspace.Gravity * (1 - (balloons >= 4 and 1.2 or balloons >= 3 and 1 or 0.975))
			end
			if ent.Character and ent.Character.PrimaryPart and ent.Character.PrimaryPart:FindFirstChild('rbxassetid://8200754399') then
				playerGravity = 6
			end
			if ent.Player and ent.Player:GetAttribute('IsOwlTarget') then
				for _, owl in ipairs(collectionService:GetTagged('Owl')) do
					if owl:GetAttribute('Target') == ent.Player.UserId and owl:GetAttribute('Status') == 2 then
						playerGravity = 0
						break
					end
				end
			end
			local bowRelX = bedwars.BowConstantsTable.RelX or 0
			local bowRelY = bedwars.BowConstantsTable.RelY or 0
			local bowRelZ = bedwars.BowConstantsTable.RelZ or 0
			local newlook = CFrame.new(pos, targetBodyPart.Position) * CFrame.new(Vector3.new(bowRelX, bowRelY, bowRelZ))
			local calc = prediction.SolveTrajectory(newlook.p, projSpeed, gravity, targetBodyPart.Position, targetVelocity, playerGravity, ent.HipHeight, nil, RaycastParams.new())
			if calc then
				targetinfo.Targets[ent] = tick() + 1
				task.spawn(function()
					local dir, id = CFrame.lookAt(newlook.Position, calc).LookVector, httpService:GenerateGUID(true)
					local shootPosition = (CFrame.new(newlook.Position, calc) * CFrame.new(Vector3.new(-bowRelX, -bowRelY, -bowRelZ))).Position
					bedwars.ProjectileController:createLocalProjectile(meta, ammo, projectile, shootPosition, id, dir * projSpeed, {drawDurationSeconds = 1})
					local res = projectileRemote:InvokeServer(item.tool, ammo, projectile, shootPosition, pos, dir * projSpeed, id, {drawDurationSeconds = 1, shotId = httpService:GenerateGUID(false)}, workspace:GetServerTimeNow() - 0.065)
					if not res then
						ProjectileDelay[item.itemType] = tick() + 0.15
					else
						res.Parent = replicatedStorage
						local shoot = itemMeta.launchSound
						shoot = shoot and shoot[math.random(1, #shoot)] or nil
						if shoot then bedwars.SoundManager:playSound(shoot) end
					end
				end)
				ProjectileDelay[item.itemType] = tick() + itemMeta.fireDelaySec
				if switched and not ign then task.wait(0.05) end
			end
		end

    local function doFastHitsLegitSwitch(ent)
        if not ent or not ent.RootPart then return end
        local pos = entitylib.character.RootPart.Position

        local bowItem, bowAmmo, bowProjectile, bowMeta = nil, nil, nil, nil
        for _, item in store.inventory.inventory.items do
            local _itemMeta = bedwars.ItemMeta[item.itemType]
            local proj = _itemMeta and _itemMeta.projectileSource
            if not proj then continue end
            for _, inv in store.inventory.inventory.items do
                if proj.ammoItemTypes and table.find(proj.ammoItemTypes, inv.itemType) then
                    bowItem = item
                    bowAmmo = inv.itemType
                    bowProjectile = proj.projectileType(inv.itemType)
                    bowMeta = bedwars.ProjectileMeta[bowProjectile]
                    break
                end
            end
            if bowItem then break end
        end

        if not bowItem or not bowMeta then return end
        if (FastHitsFireDelays[bowItem.itemType] or 0) >= tick() then return end

        local bowSlot = nil
        local hotbar = store.inventory.hotbar
        for i = 1, #hotbar do
            local v = hotbar[i]
            if v and v.item and v.item == bowItem then
                bowSlot = i - 1
                break
            end
        end
        if not bowSlot then return end

        local originalSlot = store.inventory.hotbarSlot
        if hotbarSwitch(bowSlot) then task.wait(0.05) end

        local holdingCrossbow = bowItem.itemType:find('crossbow')
        local holdingBow = bowItem.itemType:find('bow') and not holdingCrossbow
        if holdingCrossbow then
            pcall(function() bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_CROSSBOW_FIRE) end)
            bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.CROSSBOW_FIRE)
        elseif holdingBow then
            pcall(function() bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_CROSSBOW_FIRE) end)
            bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.BOW_FIRE)
        else
            local shootAnim = bedwars.ItemMeta[bowItem.tool.Name].thirdPerson and bedwars.ItemMeta[bowItem.tool.Name].thirdPerson.shootAnimation
            if shootAnim then
                bedwars.GameAnimationUtil:playAnimation(lplr, shootAnim)
            end
        end

        local meta = bowMeta
        local projSpeed, gravity = meta.launchVelocity, meta.gravitationalAcceleration or 196.2
        local bowRelX = bedwars.BowConstantsTable.RelX or 0
        local bowRelY = bedwars.BowConstantsTable.RelY or 0
        local bowRelZ = bedwars.BowConstantsTable.RelZ or 0
        local newlook = CFrame.new(pos, ent.RootPart.Position) * CFrame.new(Vector3.new(bowRelX, bowRelY, bowRelZ))
        local playerGravityLS = workspace.Gravity
        local balloonsLS = ent.Character and ent.Character:GetAttribute('InflatedBalloons')
        if balloonsLS and balloonsLS > 0 then
            playerGravityLS = workspace.Gravity * (1 - (balloonsLS >= 4 and 1.2 or balloonsLS >= 3 and 1 or 0.975))
        end
        if ent.Character and ent.Character.PrimaryPart and ent.Character.PrimaryPart:FindFirstChild('rbxassetid://8200754399') then
            playerGravityLS = 6
        end
        if ent.Player and ent.Player:GetAttribute('IsOwlTarget') then
            for _, owl in ipairs(collectionService:GetTagged('Owl')) do
                if owl:GetAttribute('Target') == ent.Player.UserId and owl:GetAttribute('Status') == 2 then
                    playerGravityLS = 0
                    break
                end
            end
        end

        local calc = prediction.SolveTrajectory(newlook.p, projSpeed, gravity, ent.RootPart.Position, ent.RootPart.Velocity, playerGravityLS, ent.HipHeight, ent.Jumping and 42.6 or nil, sharedFastHitsRayParams)

        if calc then
            targetinfo.Targets[ent] = tick() + 1
            task.spawn(function()
                local dir = CFrame.lookAt(newlook.Position, calc).LookVector
                local id = httpService:GenerateGUID(true)
                local shootPosition = (CFrame.new(newlook.Position, calc) * CFrame.new(Vector3.new(-bowRelX, -bowRelY, -bowRelZ))).Position
                bedwars.ProjectileController:createLocalProjectile(meta, bowAmmo, bowProjectile, shootPosition, id, dir * projSpeed, {drawDurationSeconds = 1})
                local res = projectileRemote:InvokeServer(bowItem.tool, bowAmmo, bowProjectile, shootPosition, pos, dir * projSpeed, id, {drawDurationSeconds = 1, shotId = httpService:GenerateGUID(false)}, workspace:GetServerTimeNow() - 0.045)
                if not res then
                    FastHitsFireDelays[bowItem.itemType] = tick()
                else
                    local shoot = bowMeta.launchSound
                    shoot = shoot and shoot[math.random(1, #shoot)] or nil
                    if shoot then bedwars.SoundManager:playSound(shoot) end
                end
            end)
            FastHitsFireDelays[bowItem.itemType] = tick() + AutoShootInterval.Value
        end

        task.wait(0.05)
        hotbarSwitch(originalSlot)
    end

    local function doFastHitsNEW(ent)
        if not ent or not ent.RootPart then return end
        local pos = entitylib.character.RootPart.Position
        local projectiles = getProjectiles()
        NEWFastHitsUsage += 1
        if not projectiles[NEWFastHitsUsage] then NEWFastHitsUsage = 1 end
        if projectiles and projectiles[NEWFastHitsUsage] and canShoot(projectiles[NEWFastHitsUsage]) then
            local item, ammo, projectile, itemMeta = unpack(projectiles[NEWFastHitsUsage])
            shootFunc(item, ammo, projectile, itemMeta, pos, ent)
        end
    end

    local rayCheckFastHits = cloneRaycast()
	local sharedFastHitsRayParams = RaycastParams.new()
    local function doFastHitsProjectileAura(ent)
        if not ent or not ent.RootPart then return end
        local pos = entitylib.character.RootPart.Position

        local bowItem, bowAmmo, bowProjectile, bowMeta = nil, nil, nil, nil
        for _, item in store.inventory.inventory.items do
            local _itemMeta = bedwars.ItemMeta[item.itemType]
            local proj = _itemMeta and _itemMeta.projectileSource
            if not proj then continue end
            for _, inv in store.inventory.inventory.items do
                if proj.ammoItemTypes and table.find(proj.ammoItemTypes, inv.itemType) then
                    bowItem = item
                    bowAmmo = inv.itemType
                    bowProjectile = proj.projectileType(inv.itemType)
                    bowMeta = bedwars.ProjectileMeta[bowProjectile]
                    break
                end
            end
            if bowItem then break end
        end

        if not bowItem or not bowMeta then return end
        if (FastHitsFireDelays[bowItem.itemType] or 0) >= tick() then return end

        local originalSlot = store.inventory.hotbarSlot
        local switched = switchItem(bowItem.tool)
        if switched then task.wait(0.05) end

        local meta = bowMeta
        local projSpeed, gravity = meta.launchVelocity, meta.gravitationalAcceleration or 196.2
        local bowRelX = bedwars.BowConstantsTable.RelX or 0
        local bowRelY = bedwars.BowConstantsTable.RelY or 0
        local bowRelZ = bedwars.BowConstantsTable.RelZ or 0
        local newlook = CFrame.new(pos, ent.RootPart.Position) * CFrame.new(Vector3.new(bowRelX, bowRelY, bowRelZ))
        local playerGravityPA = workspace.Gravity
        local balloonsPA = ent.Character and ent.Character:GetAttribute('InflatedBalloons')
        if balloonsPA and balloonsPA > 0 then
            playerGravityPA = workspace.Gravity * (1 - (balloonsPA >= 4 and 1.2 or balloonsPA >= 3 and 1 or 0.975))
        end
        if ent.Character and ent.Character.PrimaryPart and ent.Character.PrimaryPart:FindFirstChild('rbxassetid://8200754399') then
            playerGravityPA = 6
        end
        if ent.Player and ent.Player:GetAttribute('IsOwlTarget') then
            for _, owl in ipairs(collectionService:GetTagged('Owl')) do
                if owl:GetAttribute('Target') == ent.Player.UserId and owl:GetAttribute('Status') == 2 then
                    playerGravityPA = 0
                    break
                end
            end
        end
        local calc = prediction.SolveTrajectory(newlook.p, projSpeed, gravity, ent.RootPart.Position, ent.RootPart.Velocity, playerGravityPA, ent.HipHeight, ent.Jumping and 42.6 or nil, sharedFastHitsRayParams)

        if calc then
            targetinfo.Targets[ent] = tick() + 1

            task.spawn(function()
                local dir = CFrame.lookAt(newlook.Position, calc).LookVector
                local id = httpService:GenerateGUID(true)
                local shootPosition = (CFrame.new(newlook.Position, calc) * CFrame.new(Vector3.new(-bowRelX, -bowRelY, -bowRelZ))).Position

                local holdingCrossbow = bowItem.itemType:find('crossbow')
                local holdingBow = bowItem.itemType:find('bow') and not holdingCrossbow
                if holdingCrossbow then
                    pcall(function() bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_CROSSBOW_FIRE) end)
                    bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.CROSSBOW_FIRE)
                elseif holdingBow then
                    pcall(function() bedwars.ViewmodelController:playAnimation(bedwars.AnimationType.FP_CROSSBOW_FIRE) end)
                    bedwars.GameAnimationUtil:playAnimation(lplr, bedwars.AnimationType.BOW_FIRE)
                else
                    local shootAnim = bedwars.ItemMeta[bowItem.tool.Name].thirdPerson and bedwars.ItemMeta[bowItem.tool.Name].thirdPerson.shootAnimation
                    if shootAnim then
                        bedwars.GameAnimationUtil:playAnimation(lplr, shootAnim)
                    end
                end

                bedwars.ProjectileController:createLocalProjectile(meta, bowAmmo, bowProjectile, shootPosition, id, dir * projSpeed, {drawDurationSeconds = 1})
                local res = projectileRemote:InvokeServer(bowItem.tool, bowAmmo, bowProjectile, shootPosition, pos, dir * projSpeed, id, {drawDurationSeconds = 1, shotId = httpService:GenerateGUID(false)}, workspace:GetServerTimeNow() - 0.045)
                if not res then
                    FastHitsFireDelays[bowItem.itemType] = tick()
                else
                    local shoot = bowItem.launchSound
                    shoot = shoot and shoot[math.random(1, #shoot)] or nil
                    if shoot then bedwars.SoundManager:playSound(shoot) end
                end
            end)

            FastHitsFireDelays[bowItem.itemType] = tick() + AutoShootInterval.Value
            if switched then
                task.wait(0.05)
                hotbarSwitch(originalSlot)
            end
        end
    end

    local function doFastHitsVirtualInput(ent)
        if not ent or not ent.RootPart then return end
        if not hasArrows() then return end
        if FirstPersonCheck.Enabled and not isFirstPerson() then return end

        local currentTime = tick()
        if (currentTime - lastAutoShootTime) < AutoShootInterval.Value then return end

        local bows = getBows()
        if #bows == 0 then return end
        local bowSlot = bows[1]
        local originalSlot = store.inventory.hotbarSlot

        if hotbarSwitch(bowSlot) then
            task.wait(AutoShootSwitchSpeed.Value)
            local hotbarItem = store.inventory.hotbar[bowSlot + 1]
            if hotbarItem and hotbarItem.item then
                local itemMeta = bedwars.ItemMeta[hotbarItem.item.itemType]
                if itemMeta and itemMeta.projectileSource then
                    local projSource = itemMeta.projectileSource
                    if projSource.ammoItemTypes and #projSource.ammoItemTypes > 0 then
                        local ammo = projSource.ammoItemTypes[1]
                        local projectile = nil
                        if type(projSource.projectileType) == "function" then
                            local success, result = pcall(function() return projSource.projectileType(ammo) end)
                            if success then projectile = result end
                        else
                            projectile = projSource.projectileType
                        end
                        if projectile then
                            local pos = entitylib.character.RootPart.Position
                            if AutoShootWaitDelay.Value > 0 then task.wait(AutoShootWaitDelay.Value) end

                            local meta = bedwars.ProjectileMeta[projectile]
                            local projSpeed, gravity = meta.launchVelocity, meta.gravitationalAcceleration or 196.2
                            local calc = prediction.SolveTrajectory(pos, projSpeed, gravity, ent.RootPart.Position, ent.RootPart.Velocity, workspace.Gravity, ent.HipHeight, ent.Jumping and 42.6 or nil, rayCheckFastHits)

                            if calc then
                                local dir = CFrame.lookAt(pos, calc).LookVector
                                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
                                task.wait(0.05)
                                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
                            else
                                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
                                task.wait(0.05)
                                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
                            end
                        end
                    end
                end
            end
            task.wait(0.05)
        end

        local swordSlot = getSwordSlot()
        if swordSlot then
            hotbarSwitch(swordSlot)
        else
            hotbarSwitch(originalSlot)
        end

        lastAutoShootTime = currentTime  
    end

    local function getEntityFromCharacterFH(char)
        for _, ent in ipairs(entitylib.List) do
            if ent.Character == char then return ent end
        end
        return nil
    end

    local function doOldFastHits()
        if not store.KillauraTarget then return end

        local currentTime = tick()
        if (currentTime - lastOldShootTime) < OldShootInterval.Value then return end

        if OldFirstPersonCheck and OldFirstPersonCheck.Enabled then
            local cf = gameCamera.CFrame
            local char = entitylib.character
            if char and char.RootPart then
                local dist = (cf.Position - char.RootPart.Position).Magnitude
                if dist > 1 then return end
            end
        end

        local arrowItem = getItem('arrow')
        if not arrowItem or arrowItem.amount <= 0 then return end

        local bows = {}
        local swordSlot = nil
        local hotbar = store.inventory.hotbar
        for i = 1, #hotbar do
            local v = hotbar[i]
            if v and v.item and v.item.itemType then
                local itemMeta = bedwars.ItemMeta[v.item.itemType]
                if itemMeta then
                    if itemMeta.projectileSource then
                        local ps = itemMeta.projectileSource
                        if ps.ammoItemTypes and table.find(ps.ammoItemTypes, 'arrow') then
                            table.insert(bows, i - 1)
                        end
                    end
                    if itemMeta.sword and not swordSlot then
                        swordSlot = i - 1
                    end
                end
            end
        end

        if #bows == 0 then return end

        lastOldShootTime = currentTime
        local originalSlot = store.inventory.hotbarSlot

        for i = 1, #bows do
            local bowSlot = bows[i]
            if hotbarSwitch(bowSlot) then
                task.wait(OldSwitchDelay.Value)
                leftClick()
                task.wait(0.05)
            end
        end

        if swordSlot then
            hotbarSwitch(swordSlot)
        else
            hotbarSwitch(originalSlot)
        end
    end

    local function doFastHits()
        if not FastHits.Enabled then return end
        if not Attacking then return end
        if not store.KillauraTarget then return end

        if FastHitsHitsRequiredToggle and FastHitsHitsRequiredToggle.Enabled then
            if not fastHitsActivationReady then return end
            if fastHitsTrackedEntity and fastHitsTrackedEntity ~= store.KillauraTarget then
                fastHitsActivationReady = false
                return
            end
        end

        local ent = store.KillauraTarget
        if not ent or not ent.RootPart then return end

        local selfpos = entitylib.character.RootPart.Position
        local dist = (ent.RootPart.Position - selfpos).Magnitude
        if dist > (AttackRange.Value + 1) then return end

        if FastHitsMode.Value == 'OGFastHits' then
            doFastHitsVirtualInput(ent)
        elseif FastHitsMode.Value == 'NEWFastHits' then
            if LegitSwitch and LegitSwitch.Enabled then
                doFastHitsLegitSwitch(ent)
            else
                doFastHitsNEW(ent)
            end
        end
    end

    local function startAutoShootLoop()
        if autoShootLoop then return end

        fastHitsHitTarget = nil
        fastHitsTrackedEntity = nil
        fastHitsHitCount = 0
        fastHitsActivationReady = false
        fastHitsLastHitTime = 0

        if FastHitsHitsRequiredToggle and FastHitsHitsRequiredToggle.Enabled then
            local hitsRequiredConn
            hitsRequiredConn = vapeEvents.EntityDamageEvent.Event:Connect(function(damageTable)
                if not FastHits.Enabled or not FastHitsHitsRequiredToggle.Enabled then return end
                local attackerChar = damageTable.fromEntity
                local victimChar = damageTable.entityInstance
                if not attackerChar or not victimChar then return end
                local isLocalAttacker = lplr.Character and attackerChar == lplr.Character
                if not isLocalAttacker then
                    local ap = playersService:GetPlayerFromCharacter(attackerChar)
                    if ap == lplr then isLocalAttacker = true end
                end
                if not isLocalAttacker then return end
                local now = tick()
                if now - fastHitsLastHitTime < FASTHITS_HIT_DEBOUNCE then return end
                fastHitsLastHitTime = now
                local victimEnt = getEntityFromCharacterFH(victimChar)
                if not victimEnt then return end
                if fastHitsHitTarget == victimChar then
                    fastHitsHitCount = fastHitsHitCount + 1
                else
                    fastHitsHitTarget = victimChar
                    fastHitsTrackedEntity = victimEnt
                    fastHitsHitCount = 1
                    fastHitsActivationReady = false
                end
                if fastHitsHitCount >= (FastHitsHitsRequiredSlider and FastHitsHitsRequiredSlider.Value or 2) then
                    fastHitsActivationReady = true
                end
			end)
            FastHits:Clean(hitsRequiredConn)
        end

        autoShootLoop = task.spawn(function()
            while Killaura.Enabled and FastHits.Enabled do
                doFastHits()
                task.wait(0.05)  
            end
            autoShootLoop = nil
        end)
    end

    local function stopAutoShootLoop()
        if autoShootLoop then
            task.cancel(autoShootLoop)
            autoShootLoop = nil
        end
        table.clear(FastHitsFireDelays)
        table.clear(NEWFastHitsProjectileDelay)
        NEWFastHitsLastShot = 0
        NEWFastHitsUsage = 1
        fastHitsHitTarget = nil
        fastHitsTrackedEntity = nil
        fastHitsHitCount = 0
        fastHitsActivationReady = false
        fastHitsLastHitTime = 0
    end
    
    Killaura = vape.Categories.Blatant:CreateModule({
        Name = 'bloopybestkav2',
        Function = function(callback)
            if callback then
				local attacked = {}
                lastSwingServerTime = Workspace:GetServerTimeNow()
                lastSwingServerTimeDelta = 0
                lastAttackTime = 0
                swingCooldown = 0
                resetSwordCooldown()
                lastTargetTime = 0
                continueSwingCount = 0
                table.clear(_perTargetNextHit)
                Killaura:Clean(task.spawn(function()
                    while Killaura.Enabled do
                        if KAAuto and KAAuto.Enabled and (tick() - lastTargetTime) < 0.5 then
                            pcall(function()
                                if store.hand and store.hand.toolType == 'sword' and entitylib.isAlive then
                                    bedwars.SwordController:swingSwordAtMouse(0.39)
                                end
                            end)
                        end
                        task.wait(1 / 100)
                    end
                end))
                if Mouse and LegitAura and Mouse.Enabled and LegitAura.Enabled then
                    Mouse:Toggle(false)
                    LegitAura:Toggle(false)
                    notif("bloopybestkav2", "yo u cant have require mouse down AND swing only both on at da same time turned both off 4 u", 5)
                end

                if RangeCircle.Enabled then
                    createRangeCircle()
                end
                if inputService.TouchEnabled and not preserveSwordIcon then
                    pcall(function()
                        lplr.PlayerGui.MobileUI['2'].Visible = Limit.Enabled
                    end)
                end

                if Animation.Enabled and not (identifyexecutor and table.find({'Argon', 'Delta'}, ({identifyexecutor()})[1])) then
                    local fake = {
                        Controllers = {
                            ViewmodelController = {
                                isVisible = function()
                                    return not Attacking
                                end,
                                playAnimation = function(...)
                                    local args = {...}
                                    if not Attacking then
                                        pcall(function()
                                            bedwars.ViewmodelController:playAnimation(select(2, unpack(args)))
                                        end)
                                    end
                                end
                            }
                        }
                    }

                    task.spawn(function()
                        local started = false
                        repeat
                            if Attacking then
                                if not armC0 then
                                    armC0 = gameCamera.Viewmodel.RightHand.RightWrist.C0
                                end
                                local first = not started
                                started = true

                                if AnimationMode.Value == 'Random' then
                                    anims.Random = {{CFrame = CFrame.Angles(math.rad(math.random(1, 360)), math.rad(math.random(1, 360)), math.rad(math.random(1, 360))), Time = 0.12}}
                                end

                                for _, v in anims[AnimationMode.Value] do
                                    AnimTween = tweenService:Create(gameCamera.Viewmodel.RightHand.RightWrist, TweenInfo.new(first and (AnimationTween.Enabled and 0.001 or 0.1) or v.Time / AnimationSpeed.Value, Enum.EasingStyle.Linear), {
                                        C0 = armC0 * v.CFrame
                                    })
                                    AnimTween:Play()
                                    AnimTween.Completed:Wait()
                                    first = false
                                    if (not Killaura.Enabled) or (not Attacking) then break end
                                end
                            elseif started then
                                started = false
                                AnimTween = tweenService:Create(gameCamera.Viewmodel.RightHand.RightWrist, TweenInfo.new(AnimationTween.Enabled and 0.001 or 0.3, Enum.EasingStyle.Exponential), {
                                    C0 = armC0
                                })
                                AnimTween:Play()
                            end

                            if not started then
                                task.wait(1 / UpdateRate.Value)
                            end
                        until (not Killaura.Enabled) or (not Animation.Enabled)
                    end)
                end

				local _gatherSwing = {}
				local _gatherAttack = {}

				local function gatherTargets(selfpos)
					table.clear(_gatherSwing)
					table.clear(_gatherAttack)
					local swingRange = SwingRange.Value
					local attackRange = AttackRange.Value
					local wallcheck = Targets.Walls.Enabled or nil
					local maxTargets = MaxTargets.Value
					local priority = TargetPriority.Value
					local sortFunc = sortmethods[Sort.Value]
					local playersEnabled = Targets.Players.Enabled
					local npcsEnabled = Targets.NPCs.Enabled

					local allEnts = entitylib.List
					for i = 1, #allEnts do
						local ent = allEnts[i]
						if not ent.RootPart then continue end
						if not ent.Targetable then continue end
						if ent.Player and not playersEnabled then continue end
						if ent.NPC and not npcsEnabled then continue end
						local dist = (ent.RootPart.Position - selfpos).Magnitude
						if wallcheck and not hasLineOfSight(selfpos, ent.RootPart.Position, ent.Character) then continue end
						if dist <= swingRange then
							if #_gatherSwing < maxTargets then
								table.insert(_gatherSwing, ent)
							end
						end
						if dist <= attackRange then
							if #_gatherAttack < maxTargets then
								table.insert(_gatherAttack, ent)
							end
						end
					end

					if sortFunc then
						table.sort(_gatherSwing, function(a, b) return sortFunc({Entity=a}, {Entity=b}) end)
						table.sort(_gatherAttack, function(a, b) return sortFunc({Entity=a}, {Entity=b}) end)
					end

					return _gatherSwing, _gatherAttack
				end

                repeat
                    if SophiaCheck and SophiaCheck.Enabled then
                        if isFrozen(nil, FROZEN_THRESHOLD) then
                            Attacking = false
                            store.KillauraTarget = nil
                            task.wait(0.3)
                            continue
                        end
                    end
                    
                    pcall(function()
                        if entitylib.isAlive and entitylib.character.HumanoidRootPart then
                            RangeCirclePart.Position = entitylib.character.HumanoidRootPart.Position - Vector3.new(0, entitylib.character.Humanoid.HipHeight, 0)
                        end
                    end)
					table.clear(attacked)
					local sword, meta, canAttack = getAttackData()
                    Attacking = false
                    store.KillauraTarget = nil
                    pcall(function() vapeTargetInfo.Targets.Killaura = nil end)

                    if sword and canAttack then
                        local isClaw = string.find(string.lower(tostring(sword and sword.itemType or "")), "summoner_claw")
                        
                        local selfpos = entitylib.character.RootPart.Position
                        local localfacing = entitylib.character.RootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
                        local maxAngle = math.rad(AngleSlider.Value) / 2
                        local swingPlrs, attackPlrs = gatherTargets(selfpos)
                        
                        local hasValidSwingTargets = false
                        local hasValidAttackTargets = false
                        
                        for _, v in swingPlrs do
                            local delta = (v.RootPart.Position - selfpos)
                            local angle = math.acos(localfacing:Dot((delta * Vector3.new(1, 0, 1)).Unit))
                            if angle <= maxAngle then
                                hasValidSwingTargets = true
                                break
                            end
                        end
                        
                        for _, v in attackPlrs do
                            local delta = (v.RootPart.Position - selfpos)
                            local angle = math.acos(localfacing:Dot((delta * Vector3.new(1, 0, 1)).Unit))
                            if angle <= maxAngle then  
                                hasValidAttackTargets = true
                                break
                            end
                        end
                        
                        if hasValidSwingTargets or hasValidAttackTargets then
                            lastTargetTime = tick()
                        end
                        
                        local shouldSwing = hasValidSwingTargets or hasValidAttackTargets or shouldContinueSwinging()
                        
                        if shouldSwing then
                            switchItem(sword.tool, 0)
                            
                            if hasValidAttackTargets then
                                for _, v in attackPlrs do
                                    local delta = (v.RootPart.Position - selfpos)
                                    local angle = math.acos(localfacing:Dot((delta * Vector3.new(1, 0, 1)).Unit))
                                    local swingAngle = math.rad(AngleSlider.Value)
                                    if angle > (swingAngle / 2) then continue end

                                    table.insert(attacked, {
                                        Entity = v,
                                        Check = delta.Magnitude > AttackRange.Value and BoxSwingColor or BoxAttackColor
                                    })
                                    targetinfo.Targets[v] = tick() + 1
                                    pcall(function()
                                        local plr = v
                                        vapeTargetInfo.Targets.Killaura = {
                                            Humanoid = {
                                                Health = (plr.Character:GetAttribute("Health") or plr.Humanoid.Health) + getShieldAttribute(plr.Character),
                                                MaxHealth = plr.Character:GetAttribute("MaxHealth") or plr.Humanoid.MaxHealth
                                            },
                                            Player = plr.Player
                                        }
                                    end)
                                    if not Attacking then
                                        Attacking = true
                                        store.KillauraTarget = v
                                        if not isClaw then
                                            local inLegitRange = delta.Magnitude < 14.4
                                            local allowSwingAnim = not Swing.Enabled and AnimDelay <= tick() and (not LegitAura.Enabled or (not LegitAura.Enabled and not Mouse.Enabled) or (inLegitRange and (tick() - swingCooldown) >= math.max(SwingTime.Enabled and SwingTimeSlider.Value or 0.25, 0.11)))
                                            if allowSwingAnim then
                                                local swingSpeed = 0.25
                                                if SwingTime.Enabled then
                                                    swingSpeed = math.max(SwingTimeSlider.Value, 0.11)
                                                elseif meta.sword.respectAttackSpeedForEffects then
                                                    swingSpeed = meta.sword.attackSpeed
                                                end
                                                AnimDelay = tick() + swingSpeed
                                                pcall(function()
                                                    bedwars.SwordController:playSwordEffect(meta, false)
                                                    if meta.displayName:find(' Scythe') then
                                                        bedwars.ScytheController:playLocalAnimation()
                                                    end
                                                end)
                                                if vape.ThreadFix and setthreadidentity then
                                                    pcall(setthreadidentity, 8)
                                                end
                                            end
                                        end
                                    end

                                    local canHit = delta.Magnitude <= AttackRange.Value
                                    local fastHitsRange = delta.Magnitude <= (AttackRange.Value + 1)

                                    if not canHit and not fastHitsRange then continue end

                                    if AirHit and AirHit.Enabled then
                                        local humanoid = v.Character:FindFirstChildOfClass("Humanoid")
                                        if humanoid then
                                            local state = humanoid:GetState()
                                            if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Physics then
                                                if math.random(1, 100) > AirHitsChance.Value then
                                                    continue
                                                end
                                            end
                                        end
                                    end

                                    if SyncHits.Enabled then
                                        local swingSpeed = SwingTime.Enabled and SwingTimeSlider.Value or (meta.sword.respectAttackSpeedForEffects and meta.sword.attackSpeed or 0.42)
                                        local timeSinceLastSwing = tick() - swingCooldown
                                        local requiredDelay = math.max(swingSpeed * 0.4, 0.03)
                                        
                                        if timeSinceLastSwing < requiredDelay then 
                                            continue 
                                        end
                                    end

                                    local actualRoot = v.Character.PrimaryPart
                                    if actualRoot then
                                        local pos = selfpos
                                        local targetPos = actualRoot.Position
                                        local camPos = gameCamera.CFrame.Position
                                        local dir = (targetPos - camPos).Unit

                                        if not SyncHits.Enabled or (tick() - swingCooldown) >= 0.1 then
                                            swingCooldown = tick()
                                        end
                                        lastSwingServerTimeDelta = workspace:GetServerTimeNow() - lastSwingServerTime
                                        lastSwingServerTime = workspace:GetServerTimeNow()

                                        store.attackReach = (delta.Magnitude * 100) // 1 / 100
                                        store.attackReachUpdate = tick() + 1

                                        if SwingTime.Enabled then
                                            lastAttackTime = tick()

                                            if delta.Magnitude < 14.4 and SwingTimeSlider.Value > 0.11 then
                                                AnimDelay = tick()
                                            end
                                        else
                                            lastAttackTime = tick()
                                        end

                                        if isClaw then
                                            KaidaController:request(v.Character)
                                        else
                                            local attackData = {
                                                weapon = sword.tool,
                                                entityInstance = v.Character,
                                                chargedAttack = {chargeRatio = 0},
                                                validate = {
                                                    raycast = {
                                                        cameraPosition = {value = camPos},
                                                        cursorDirection = {value = dir}
                                                    },
                                                    targetPosition = {value = targetPos},
                                                    selfPosition = {value = pos}
                                                }
                                            }
                                            
											if canHit and canHitTarget(v.Character, meta) then
                                                FireAttackRemote(attackData)
                                            end

											if FastHits.Enabled then
												if FastHitsMode.Value == 'NEWFastHits' then
													if (tick() - lastShot) >= (0.2 + lplr:GetNetworkPing() + FireRate.Value) then
														local projectiles = getProjectiles()
														Usage += 1
														if not projectiles[Usage] then Usage = 1 end
														if projectiles and projectiles[Usage] and canShoot(projectiles[Usage]) then
															local item, ammo, projectile, itemMeta = unpack(projectiles[Usage])
															if LegitSwitch and LegitSwitch.Enabled then
																local bowSlot = nil
																local swordSlot = nil
																local originalSlot = store.inventory.hotbarSlot
																local hotbar = store.inventory.hotbar
																for i = 1, #hotbar do
																	local hv = hotbar[i]
																	if hv and hv.item and hv.item.itemType then
																		if hv.item.itemType == item.itemType and not bowSlot then
																			bowSlot = i - 1
																		end
																		local hm = bedwars.ItemMeta[hv.item.itemType]
																		if hm and hm.sword and not swordSlot then
																			swordSlot = i - 1
																		end
																	end
																end
																if bowSlot then
																	bedwars.Store:dispatch({type = 'InventorySelectHotbarSlot', slot = bowSlot})
																	shootFunc(item, ammo, projectile, itemMeta, selfpos, v, false)
																	bedwars.Store:dispatch({type = 'InventorySelectHotbarSlot', slot = swordSlot or originalSlot})
																end
															else
																shootFunc(item, ammo, projectile, itemMeta, selfpos, v, true)
															end
															lastShot = tick()
														end
													end
												elseif FastHitsMode.Value == 'OLDFastHits' then
													doOldFastHits()
												end
											end
                                        end
                                    end
                                end
                            else
                                Attacking = true
                                if not isClaw then
                                    if not Swing.Enabled and AnimDelay <= tick() and not LegitAura.Enabled then
                                        local swingSpeed = 0.25
                                        if SwingTime.Enabled then
                                            swingSpeed = math.max(SwingTimeSlider.Value, 0.11)
                                        elseif meta.sword.respectAttackSpeedForEffects then
                                            swingSpeed = meta.sword.attackSpeed
                                        end
                                        AnimDelay = tick() + swingSpeed
                                        pcall(function()
                                            bedwars.SwordController:playSwordEffect(meta, false)
                                            if meta.displayName:find(' Scythe') then
                                                bedwars.ScytheController:playLocalAnimation()
                                            end
                                        end)
                                        if vape.ThreadFix and setthreadidentity then
                                            pcall(setthreadidentity, 8)
                                        end
                                    end
                                end

                                local currentSwingSpeed = SwingTime.Enabled and SwingTimeSlider.Value or (meta.sword.respectAttackSpeedForEffects and meta.sword.attackSpeed or 0.42)
                                local minSwingDelay = math.max(currentSwingSpeed, 0.05)
                                
                                if not SyncHits.Enabled or (tick() - swingCooldown) >= minSwingDelay then
                                    swingCooldown = tick()
                                end
                            end
                        end
                    end

                    pcall(function()
                        for i, v in Boxes do
                            v.Adornee = attacked[i] and attacked[i].Entity.RootPart or nil
                            if v.Adornee then
                                v.Color3 = Color3.fromHSV(attacked[i].Check.Hue, attacked[i].Check.Sat, attacked[i].Check.Value)
                                v.Transparency = 1 - attacked[i].Check.Opacity
                            end
                        end

                        for i, v in Particles do
                            v.Position = attacked[i] and attacked[i].Entity.RootPart.Position or Vector3.new(9e9, 9e9, 9e9)
                            v.Parent = attacked[i] and gameCamera or nil
                        end
                    end)

                    if Face.Enabled and attacked[1] then
                        if true then
                            local vec = attacked[1].Entity.RootPart.Position * Vector3.new(1, 0, 1)
                            local targetCFrame = CFrame.lookAt(entitylib.character.RootPart.Position, Vector3.new(vec.X, entitylib.character.RootPart.Position.Y + 0.001, vec.Z))
                            local speed = FaceSpeed and FaceSpeed.Value or 15
                            local alpha = math.clamp(speed / 100, 0.01, 1)
                            entitylib.character.RootPart.CFrame = entitylib.character.RootPart.CFrame:Lerp(targetCFrame, alpha)
                        end
                    end
                    pcall(function() if RangeCirclePart ~= nil then RangeCirclePart.Parent = gameCamera end end)

                    task.wait(1 / UpdateRate.Value)
                until not Killaura.Enabled
            else
                table.clear(ProjectileDelay)
                store.KillauraTarget = nil
                for _, v in Boxes do
                    v.Adornee = nil
                end
                for _, v in Particles do
                    v.Parent = nil
                end
                if inputService.TouchEnabled then
                    pcall(function()
                        lplr.PlayerGui.MobileUI['2'].Visible = true
                    end)
                end
                Attacking = false
                if armC0 then
                    AnimTween = tweenService:Create(gameCamera.Viewmodel.RightHand.RightWrist, TweenInfo.new(AnimationTween.Enabled and 0.001 or 0.3, Enum.EasingStyle.Exponential), {
                        C0 = armC0
                    })
                    AnimTween:Play()
                end
                if RangeCirclePart ~= nil then RangeCirclePart:Destroy() end
            end
        end,
        Tooltip = 'Attack players around you\nwithout aiming at them.'
    })

    pcall(function()
        local PSI = Killaura:CreateToggle({
            Name = 'Preserve Sword Icon',
            Function = function(callback)
                preserveSwordIcon = callback
            end,
            Default = true
        })
        PSI.Object.Visible = inputService.TouchEnabled
    end)

    Targets = Killaura:CreateTargets({
        Players = true,
        NPCs = true
    })
    
    TargetPriority = Killaura:CreateDropdown({
        Name = 'Target Priority',
        List = {'Players First', 'NPCs First', 'Distance'},
        Default = 'Players First',
        Tooltip = 'Choose which targets to prioritize'
    })
    
    local methods = {'Damage', 'Distance'}
    for i in sortmethods do
        if not table.find(methods, i) then
            table.insert(methods, i)
        end
    end
    SwingRange = Killaura:CreateSlider({
        Name = 'Swing range',
        Min = 1,
        Max = 40, 
        Default = 22, 
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    AttackRange = Killaura:CreateSlider({
        Name = 'Attack range',
        Min = 1,
        Max = 22,
        Default = 22, 
        Suffix = function(val)
            return val == 1 and 'stud' or 'studs'
        end
    })
    RangeCircle = Killaura:CreateToggle({
        Name = "Range Visualiser",
        Function = function(call)
            if call then
                createRangeCircle()
            else
                if RangeCirclePart then
                    RangeCirclePart:Destroy()
                    RangeCirclePart = nil
                end
            end
        end
    })
    AngleSlider = Killaura:CreateSlider({
        Name = 'Max angle',
        Min = 1,
        Max = 360,
        Default = 360
    })
    UpdateRate = Killaura:CreateSlider({
        Name = 'Update rate',
        Min = 1,
        Max = 120,
        Default = 60,
        Suffix = 'hz'
    })
    MaxTargets = Killaura:CreateSlider({
        Name = 'Max targets',
        Min = 1,
        Max = 5,
        Default = 5
    })
    Sort = Killaura:CreateDropdown({
        Name = 'Target Mode',
        List = methods
    })
    Mouse = Killaura:CreateToggle({
        Name = 'Require mouse down',
        Function = function(callback)
            if callback and LegitAura and LegitAura.Enabled then
                Mouse:Toggle(false)
                LegitAura:Toggle(false)
                notif("king ben", "yo u cant have require mouse down AND swing only on at da same time turned both off 4 u ", 5)
            end
        end
    })
    Swing = Killaura:CreateToggle({Name = 'No Swing'})
    GUI = Killaura:CreateToggle({Name = 'GUI check'})
    SwingTime = Killaura:CreateToggle({
        Name = 'Custom Swing Time',
        Function = function(callback)
            SwingTimeSlider.Object.Visible = callback
        end
    })
    SwingTimeSlider = Killaura:CreateSlider({
        Name = 'Swing Time',
        Min = 0,
        Max = 1,
        Default = 0.42,
        Decimal = 100,
        Visible = false
    })
    ContinueSwinging = Killaura:CreateToggle({
        Name = 'Continue Swinging',
        Tooltip = 'Swing X times after losing target (based on swing speed)',
        Function = function(callback)
            if ContinueSwingTime then
                ContinueSwingTime.Object.Visible = callback
            end
        end
    })
    ContinueSwingTime = Killaura:CreateSlider({
        Name = 'Swing Duration',
        Min = 0,  
        Max = 5,  
        Default = 1,
        Decimal = 10,
        Suffix = 's',
        Visible = false
    })
    CustomHitReg = Killaura:CreateToggle({
        Name = 'Custom Hit Reg',
        Tooltip = 'Limit how many hits per second',
        Function = function(callback)
            if CustomHitRegSlider then
                CustomHitRegSlider.Object.Visible = callback
            end
            if callback then
                lastCustomHitTime = 0
            end
        end
    })
    
    CustomHitRegSlider = Killaura:CreateSlider({
        Name = 'Hits Per Second',
        Min = 1,
        Max = 36,
        Default = 30,
        Tooltip = 'Maximum hits per second',
        Visible = false
    })
    SyncHits = Killaura:CreateToggle({
        Name = 'Sync Hits',
        Tooltip = 'Waits for sword animation before attacking'
    })
    Killaura:CreateToggle({
        Name = 'Show target',
        Function = function(callback)
            BoxSwingColor.Object.Visible = callback
            BoxAttackColor.Object.Visible = callback
            if callback then
                for i = 1, 10 do
                    local box = Instance.new('BoxHandleAdornment')
                    box.Adornee = nil
                    box.AlwaysOnTop = true
                    box.Size = Vector3.new(3, 5, 3)
                    box.CFrame = CFrame.new(0, -0.5, 0)
                    box.ZIndex = 0
                    box.Parent = vape.gui
                    Boxes[i] = box
                end
            else
                for _, v in Boxes do
                    v:Destroy()
                end
                table.clear(Boxes)
            end
        end
    })
    BoxSwingColor = Killaura:CreateColorSlider({
        Name = 'Target Color',
        Darker = true,
        DefaultHue = 0.6,
        DefaultOpacity = 0.5,
        Visible = false,
        Function = function(hue, sat, val)
            if Killaura.Enabled and RangeCirclePart ~= nil then
                RangeCirclePart.Color = Color3.fromHSV(hue, sat, val)
            end
        end
    })
    BoxAttackColor = Killaura:CreateColorSlider({
        Name = 'Attack Color',
        Darker = true,
        DefaultOpacity = 0.5,
        Visible = false
    })
    Killaura:CreateToggle({
        Name = 'Target particles',
        Function = function(callback)
            ParticleTexture.Object.Visible = callback
            ParticleColor1.Object.Visible = callback
            ParticleColor2.Object.Visible = callback
            ParticleSize.Object.Visible = callback
            if callback then
                for i = 1, 10 do
                    local part = Instance.new('Part')
                    part.Size = Vector3.new(2, 4, 2)
                    part.Anchored = true
                    part.CanCollide = false
                    part.Transparency = 1
                    part.CanQuery = false
                    part.Parent = Killaura.Enabled and gameCamera or nil
                    local particles = Instance.new('ParticleEmitter')
                    particles.Brightness = 1.5
                    particles.Size = NumberSequence.new(ParticleSize.Value)
                    particles.Shape = Enum.ParticleEmitterShape.Sphere
                    particles.Texture = ParticleTexture.Value
                    particles.Transparency = NumberSequence.new(0)
                    particles.Lifetime = NumberRange.new(0.4)
                    particles.Speed = NumberRange.new(16)
                    particles.Rate = 128
                    particles.Drag = 16
                    particles.ShapePartial = 1
                    particles.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.fromHSV(ParticleColor1.Hue, ParticleColor1.Sat, ParticleColor1.Value)),
                        ColorSequenceKeypoint.new(1, Color3.fromHSV(ParticleColor2.Hue, ParticleColor2.Sat, ParticleColor2.Value))
                    })
                    particles.Parent = part
                    Particles[i] = part
                end
            else
                for _, v in Particles do
                    v:Destroy()
                end
                table.clear(Particles)
            end
        end
    })
    ParticleTexture = Killaura:CreateTextBox({
        Name = 'Texture',
        Default = 'rbxassetid://14736249347',
        Function = function()
            for _, v in Particles do
                v.ParticleEmitter.Texture = ParticleTexture.Value
            end
        end,
        Darker = true,
        Visible = false
    })
    ParticleColor1 = Killaura:CreateColorSlider({
        Name = 'Color Begin',
        Function = function(hue, sat, val)
            for _, v in Particles do
                v.ParticleEmitter.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHSV(hue, sat, val)),
                    ColorSequenceKeypoint.new(1, Color3.fromHSV(ParticleColor2.Hue, ParticleColor2.Sat, ParticleColor2.Value))
                })
            end
        end,
        Darker = true,
        Visible = false
    })
    ParticleColor2 = Killaura:CreateColorSlider({
        Name = 'Color End',
        Function = function(hue, sat, val)
            for _, v in Particles do
                v.ParticleEmitter.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHSV(ParticleColor1.Hue, ParticleColor1.Sat, ParticleColor1.Value)),
                    ColorSequenceKeypoint.new(1, Color3.fromHSV(hue, sat, val))
                })
            end
        end,
        Darker = true,
        Visible = false
    })
    ParticleSize = Killaura:CreateSlider({
        Name = 'Size',
        Min = 0,
        Max = 1,
        Default = 0.2,
        Decimal = 100,
        Function = function(val)
            for _, v in Particles do
                v.ParticleEmitter.Size = NumberSequence.new(val)
            end
        end,
        Darker = true,
        Visible = false
    })
    Face = Killaura:CreateToggle({
        Name = 'Face target',
        Function = function(callback)
            if FaceSpeed then FaceSpeed.Object.Visible = callback end
        end
    })

    FaceSpeed = Killaura:CreateSlider({
        Name = 'Face Speed',
        Min = 1,
        Max = 100,
        Default = 15,
        Decimal = 10,
        Darker = true,
        Visible = false,
        Tooltip = 'How fast to snap towards target (lower = slower/smoother)'
    })
    Animation = Killaura:CreateToggle({
        Name = 'Custom Animation',
        Function = function(callback)
            AnimationMode.Object.Visible = callback
            AnimationTween.Object.Visible = callback
            AnimationSpeed.Object.Visible = callback
            if Killaura.Enabled then
                Killaura:Toggle()
                Killaura:Toggle()
            end
        end
    })
    local animnames = {}
    for i in anims do
        table.insert(animnames, i)
    end
    AnimationMode = Killaura:CreateDropdown({
        Name = 'Animation Mode',
        List = animnames,
        Darker = true,
        Visible = false
    })
    AnimationSpeed = Killaura:CreateSlider({
        Name = 'Animation Speed',
        Min = 0,
        Max = 2,
        Default = 1,
        Decimal = 10,
        Darker = true,
        Visible = false
    })
    AnimationTween = Killaura:CreateToggle({
        Name = 'No Tween',
        Darker = true,
        Visible = false
    })
    Limit = Killaura:CreateToggle({
        Name = 'Limit to items',
        Function = function(callback)
            if inputService.TouchEnabled and Killaura.Enabled then
                pcall(function()
                    lplr.PlayerGui.MobileUI['2'].Visible = callback
                end)
            end
        end,
        Tooltip = 'Only attacks when the sword is held'
    })
    LegitAura = Killaura:CreateToggle({
        Name = 'Swing only',
        Tooltip = 'Only attacks while swinging manually',
        Function = function(callback)
            if callback and Mouse and Mouse.Enabled then
                LegitAura:Toggle(false)
                Mouse:Toggle(false)
                notif("king ben", "yo u cant have swing only AND require mouse down on at da same time lol turned both off 4 u ", 5)
            end
        end
    })
    AirHit = Killaura:CreateToggle({
        Name = 'Air Hits',
        Default = true,
        Tooltip = 'Control hit chance when target is airborne',
        Function = function(callback)
            if AirHitsChance then
                AirHitsChance.Object.Visible = callback
            end
            if Killaura.Enabled and callback and AirHitsChance and AirHitsChance.Object then
                AirHitsChance.Object.Visible = true
            end
        end
    })
    AirHitsChance = Killaura:CreateSlider({
        Name = 'Air Hits Chance',
        Min = 0,
        Max = 100,
        Default = 100,
        Suffix = '%',
        Decimal = 5,
        Darker = true,
        Visible = false
    })
    SophiaCheck = Killaura:CreateToggle({
        Name = 'Sophia Check',
        Tooltip = 'Stops king ben ONLY when completely frozen (uses global isFrozen)',
        Function = function(callback)
        end,
        Default = false
    })
    KAAuto = Killaura:CreateToggle({
        Name = 'AutoClicker',
        Tooltip = 'Simulates an autoclicker at 100 CPS alongside the killaura',
        Default = false
    })

	FastHits = Killaura:CreateToggle({
        Name = 'Fast Hits',
        Tooltip = 'Deals more damage quicker using projectiles',
        Default = false,
        Function = function(call)
            FastHitsMode.Object.Visible = call
            FireRate.Object.Visible = call and FastHitsMode.Value == 'NEWFastHits'
            if LegitSwitch then LegitSwitch.Object.Visible = call and FastHitsMode.Value == 'NEWFastHits' end
            if OldShootInterval then OldShootInterval.Object.Visible = call and FastHitsMode.Value == 'OLDFastHits' end
            if OldSwitchDelay then OldSwitchDelay.Object.Visible = call and FastHitsMode.Value == 'OLDFastHits' end
            if OldWaitDelay then OldWaitDelay.Object.Visible = call and FastHitsMode.Value == 'OLDFastHits' end
            if OldFirstPersonCheck then OldFirstPersonCheck.Object.Visible = call and FastHitsMode.Value == 'OLDFastHits' end
        end
    })
    FastHitsMode = Killaura:CreateDropdown({
        Name = 'Fast Hits Mode',
        List = {'NEWFastHits', 'OLDFastHits'},
        Default = 'NEWFastHits',
        Darker = true,
        Visible = false,
        Function = function(val)
            FireRate.Object.Visible = val == 'NEWFastHits'
            LegitSwitch.Object.Visible = val == 'NEWFastHits'
            OldShootInterval.Object.Visible = val == 'OLDFastHits'
            OldSwitchDelay.Object.Visible = val == 'OLDFastHits'
            OldWaitDelay.Object.Visible = val == 'OLDFastHits'
            OldFirstPersonCheck.Object.Visible = val == 'OLDFastHits'
        end
    })
    LegitSwitch = Killaura:CreateToggle({
        Name = 'Legit Switch',
        Default = false,
        Darker = true,
        Visible = false,
        Tooltip = 'Uses hotbarSwitch to switch to crossbow before shooting instead of silent switch'
    })
    OldShootInterval = Killaura:CreateSlider({
        Name = 'Shoot Interval',
        Min = 0.1,
        Max = 3,
        Default = 0.5,
        Decimal = 10,
        Suffix = 's',
        Darker = true,
        Visible = false,
        Tooltip = 'How often to shoot bows'
    })
    OldSwitchDelay = Killaura:CreateSlider({
        Name = 'Switch Delay',
        Min = 0,
        Max = 0.2,
        Default = 0.05,
        Decimal = 100,
        Suffix = 's',
        Darker = true,
        Visible = false,
        Tooltip = 'Delay between switching and shooting'
    })
    OldWaitDelay = Killaura:CreateSlider({
        Name = 'Wait Delay',
        Min = 0,
        Max = 1,
        Default = 0,
        Decimal = 100,
        Suffix = 's',
        Darker = true,
        Visible = false,
        Tooltip = 'Delay before shooting'
    })
    OldFirstPersonCheck = Killaura:CreateToggle({
        Name = 'First Person Only',
        Default = false,
        Darker = true,
        Visible = false,
        Tooltip = 'Only works in first person mode'
    })

    FireRate = Killaura:CreateSlider({
        Name = 'Fire rate',
        Suffix = 's',
        Min = 0,
        Max = 2,
        Decimal = 100,
        Darker = true,
        Visible = false,
        Default = 0
    })

    task.defer(function()
        if AirHit and AirHit.Enabled and AirHitsChance and AirHitsChance.Object then
            AirHitsChance.Object.Visible = true
        end
    end)
end)

run(function()
	local HitregAdjuster
	local Hitreg
	local swordSpeed, swingSpeed, swingRestore
	
	HitregAdjuster = vape.Categories.Combat:CreateModule({
		Name = 'HitregAdjuster',
		Function = function(callback)
			if callback then
				swingSpeed = bedwars.SyncEvents.SwordSwing:setPriority(150):connect(function(event)
					swordSpeed = event.attackSpeed
					event.attackSpeed = 10 / math.max(Hitreg.Value - 1, 1)
				end)
				swingRestore = bedwars.SyncEvents.SwordSwing:setPriority(300):connect(function(event)
					event.attackSpeed = swordSpeed
				end)
				HitregAdjuster:Clean(function()
					swingSpeed:Destroy()
					swingRestore:Destroy()
				end)
			end
		end,
		Tooltip = 'Swaps the games attack cooldown for a hit count of your own'
	})
	Hitreg = HitregAdjuster:CreateSlider({
		Name = 'Hitreg',
		Min = 1,
		Max = 36,
		Default = 35,
		Suffix = function(val)
			return val == 1 and 'hit / 10s' or 'hits / 10s'
		end,
		Tooltip = 'Spacing your manual and autoclicker hits fire at, 35 is the killaura spacing'
	})
end)

run(function()
	local DeathAdderAimbot
	local Mode
	local BedRange
	local Targets
	local Sort
	local TargetPart
	local FOV
	
	local old
	
	local function getBed(localPosition)
		local closest, magnitude = nil, BedRange.Value
		for _, bed in collectionService:GetTagged('bed') do
			if not bed:GetAttribute(`Team{lplr:GetAttribute('Team') or -1}NoBreak`) then
				local mag = (localPosition - bed.Position).Magnitude
				if mag <= magnitude then
					closest, magnitude = bed, mag
				end
			end
		end
		return closest
	end
	
	local function getAim(localPosition)
		if Mode.Value == 'Bed' then
			local bed = getBed(localPosition)
			return bed and bed.Position or nil
		end
	
		local ent = entitylib.EntityMouse({
			Range = FOV.Value,
			Part = 'RootPart',
			Wallcheck = Targets.Walls.Enabled,
			Players = Targets.Players.Enabled,
			NPCs = Targets.NPCs.Enabled,
			Origin = localPosition,
			Sort = sortmethods[Sort.Value]
		})
		if not ent then return nil end
	
		targetinfo.Targets[ent] = tick() + 1
		local tierdata = bedwars.SorcererBalance.getSorcererTierData(bedwars.SorcererBalance.getSorcererTier(lplr))
		local aim = ent[TargetPart.Value].Position
		local speed = tierdata and tierdata.projectileVelocity or 70
		return aim + (ent.RootPart.AssemblyLinearVelocity * ((aim - localPosition).Magnitude / speed))
	end
	
	DeathAdderAimbot = vape.Categories.Blatant:CreateModule({
		Name = 'DeathAdderAimbot',
		Function = function(callback)
			if callback then
				old = bedwars.SorcererController.getProjectileDirection
				bedwars.SorcererController.getProjectileDirection = function(self, ...)
					if entitylib.isAlive then
						local localPosition = entitylib.character.RootPart.Position
						local aim = getAim(localPosition)
						if aim and aim ~= localPosition then
							return (aim - localPosition).Unit
						end
					end
	
					return old(self, ...)
				end
			else
				bedwars.SorcererController.getProjectileDirection = old
			end
		end,
		Tooltip = 'Silently aims Death Adder\'s spell at a bed or a player'
	})
	Mode = DeathAdderAimbot:CreateDropdown({
		Name = 'Mode',
		List = {'Player', 'Bed'},
		Function = function(val)
			if BedRange then
				BedRange.Object.Visible = val == 'Bed'
				FOV.Object.Visible = val == 'Player'
				TargetPart.Object.Visible = val == 'Player'
				Sort.Object.Visible = val == 'Player'
			end
		end,
		Tooltip = 'Bed aims at the closest enemy bed, Player leads the closest enemy'
	})
	BedRange = DeathAdderAimbot:CreateSlider({
		Name = 'Bed range',
		Min = 1,
		Max = 60,
		Default = 60,
		Darker = true,
		Visible = false,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	Targets = DeathAdderAimbot:CreateTargets({
		Players = true,
		Walls = true
	})
	local methods = {'Distance', 'Damage'}
	for i in sortmethods do
		if not table.find(methods, i) then
			table.insert(methods, i)
		end
	end
	Sort = DeathAdderAimbot:CreateDropdown({
		Name = 'Target mode',
		List = methods,
		Default = 'Distance',
		Darker = true
	})
	TargetPart = DeathAdderAimbot:CreateDropdown({
		Name = 'Part',
		List = {'RootPart', 'Head'},
		Darker = true
	})
	FOV = DeathAdderAimbot:CreateSlider({
		Name = 'FOV',
		Min = 1,
		Max = 1000,
		Default = 1000,
		Darker = true
	})
end)

run(function()
	local AutoCyber
	local Mode
	local Whitelist
	local Visual
	local Steal
	local Target
	local Limit
	
	local teamCache, cacheExpire = nil, 0
	local function getTeamGenerator()
		if cacheExpire > tick() and teamCache and teamCache.Parent then
			return teamCache
		end
		teamCache, cacheExpire = collectionService:GetTagged(lplr:GetAttribute('Team').. '_TeamOreGenerator')[1], tick() + 5
		return teamCache
	end
	local cache = nil
	local function getDrone()
		if Limit.Enabled and (not store.hand.tool or store.hand.tool.Name ~= 'drone') then
			return nil
		end
		if cache and cache.Parent then
			return cache
		end
		for _, v in collectionService:GetTagged('Drone') do
			if v:GetAttribute('PlayerUserId') == lplr.UserId then
				local Changed = function()
					if v:GetAttribute('HeldItem') then
						repeat
							bedwars.Handler:Get('DropDroneItem'):Fire('SendToServer', {
								direction = Vector3.new(1000, 10, 0),
								position = v.PrimaryPart.Position
							})
							task.wait(0.1)
						until not v:GetAttribute('HeldItem') or not AutoCyber.Enabled
					end
				end
				AutoCyber:Clean(v:GetAttributeChangedSignal('HeldItem'):Connect(Changed))
				AutoCyber:Clean(v:GetAttributeChangedSignal('HeldItemAmount'):Connect(Changed))
				cache = v
				return v
			end
		end
		if getItem('drone') and bedwars.Handler:Get('FireGuidedProjectile'):Fire('CallServer', 'drone') then
			task.wait(0.1)
			return getDrone()
		end
		return nil
	end
	local function getGenerator(drone, item)
		local children = collectionService:GetTagged(item.. '_OreGenerator')
		local pos = drone.PrimaryPart.Position
		table.sort(children, function(a, b)
			return (pos - a.PrimaryPart.Position).Magnitude < (pos - b.PrimaryPart.Position).Magnitude
		end)
		return children[1] and children[1].PrimaryPart or nil
	end
	local blacklist = {}
	local function getItemDrop(drone)
		local generator = getTeamGenerator()
		generator = generator and generator.PrimaryPart.Position or Vector3.zero
		local children = workspace.ItemDrops:GetChildren()
		local pos = drone.PrimaryPart.Position
		table.sort(children, function(a, b)
			return (pos - a.Position).Magnitude < (pos - b.Position).Magnitude
		end)
		for _, v in children do
			if tick() > (blacklist[v] or 0) and table.find(Whitelist.ListEnabled, v.Name) and v.Position.Y > 0 and math.abs(v.Velocity.Y) <= 0 and (not Steal.Enabled or (v.Position - generator).Magnitude > 20) and (not Target.Enabled or not entitylib.EntityPosition({
				Origin = pos,
				Range = 60,
				Part = 'RootPart',
				Players = true
			})) then
				return v
			end
		end
		return nil
	end
	AutoCyber = vape.Categories.Minigames:CreateModule({
		Name = 'AutoCyber',
		Function = function(callback)
			if callback then
				AutoCyber:Clean(workspace.ItemDrops.ChildAdded:Connect(function(v)
					task.wait()
					if v.Velocity.X > 100 then
						blacklist[v] = tick() + 5
						local Amount = v:GetAttribute('Amount')
						local LastParent = v.Parent
						if Mode.Value == 'Player' then
							notif('AutoCyber', 'Collecting '.. tostring(Amount).. ' '.. v.Name, 4, 'info')
							repeat
								v.Velocity = Vector3.zero
								v.CFrame = entitylib.character.RootPart.CFrame - Vector3.new(0, 4, 0)
								task.spawn(function()
									bedwars.Handler:Get('PickupItemDrop'):Fire('CallServerAsync', {
										itemDrop = v
									}):andThen(function(suc)
										if suc and bedwars.SoundList then
											bedwars.AudioManager:playAudio(bedwars.SoundList.PICKUP_ITEM_DROP)
											local sound = bedwars.ItemMeta[v.Name].pickUpOverlaySound
											if sound then
												bedwars.AudioManager:playAudio(sound, {
													position = v.Position,
													volumeMultiplier = 0.9
												})
											end
										end
									end)
								end)
								task.wait(0.02)
							until not v or v.Parent ~= LastParent
	
							notif('AutoCyber', `Collected {Amount} {v.Name}{Amount > 1 and 's' or ''}`, 4, 'info')
						else
							local start = tick()
							local generator = getTeamGenerator()
							if generator then
								repeat
									v.Velocity = Vector3.zero
									v.CFrame = generator.PrimaryPart.CFrame
									task.wait()
								until (tick() - start) >= 1 or not v or v.Parent ~= LastParent
								notif('AutoCyber', 'Dropped '.. tostring(Amount).. ' '.. v.Name, 8, 'info')
							else
								notif('AutoCyber', 'Generator not found', 20, 'alert')
							end
						end
					end
				end))
	
				repeat
					local drone = getDrone()
					if drone then
						local v = getItemDrop(drone)
						if v then
							task.wait(0.3)
							local highlight
							if Visual.Enabled then
								highlight = Instance.new('Highlight')
								highlight.FillColor = Color3.new(1, 1, 1)
								highlight.FillTransparency = 0
								highlight.OutlineTransparency = 0.5
								highlight.OutlineColor = Color3.new()
							end
							drone.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
							drone.PrimaryPart.CFrame = CFrame.new(drone.PrimaryPart.CFrame.X, 10000, drone.PrimaryPart.CFrame.Z)
							local magnitude, lastmag = 0, 9e9
							local pos = v.Position
							repeat
								if drone and drone.Parent then
									pos = v.Position
									local multi = drone:GetAttribute('SpeedBoost')
									multi = multi == 0 or multi == '' or not multi and true or false
									drone.PrimaryPart.CanCollide = false
									drone.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
									drone.PrimaryPart.AssemblyLinearVelocity = CFrame.lookAt(drone.PrimaryPart.Position * Vector3.new(1, 0, 1), pos * Vector3.new(1, 0, 1)).LookVector * 30
									magnitude = ((drone.PrimaryPart.Position * Vector3.new(1, 0, 1)) - (pos * Vector3.new(1, 0, 1))).Magnitude
									if (lastmag - magnitude) >= 25 then
										lastmag = magnitude
										notif('AutoCyber', `Drone is {math.floor(magnitude)} studs away from {v.Name}.`, 1, 'info')
									end
								else
									break
								end
								task.wait()
							until not v or v.Parent ~= workspace.ItemDrops or not AutoCyber.Enabled or magnitude <= 2
							if not AutoCyber.Enabled then
								if highlight and highlight.Parent then
									highlight:Destroy()
								end
								break
							end
	
							if magnitude <= 5 then
								local start = tick()
								if Visual.Enabled then
									notif('AutoCyber', 'Attempting to collect '.. v.Name, 4, 'info')
								end
								repeat
									if drone and drone.Parent then
										drone.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
										drone.PrimaryPart.AssemblyAngularVelocity = Vector3.new(0, -30, 0)
										drone.PrimaryPart.CFrame = CFrame.new(pos - Vector3.new(0, drone.Hitbox.Size.Y, 0))
									end
									task.wait(0.02)
								until (tick() - start) >= 1.25
							elseif Visual.Enabled then
								notif('AutoCyber', `Too far away to collect {v.Name} ({magnitude} studs).`, 8, 'info')
							end
							if highlight and highlight.Parent then
								highlight:Destroy()
							end
						else
							drone.PrimaryPart.CFrame = CFrame.new(drone.PrimaryPart.CFrame.X, 10000, drone.PrimaryPart.CFrame.Z)
							drone.PrimaryPart.Velocity = Vector3.zero
							for _, v2 in Whitelist.ListEnabled do
								local gen = getGenerator(drone, v2)
								if gen then
									local magnitude = 0
									repeat
										if drone and drone.Parent then
											if getItemDrop(drone) then break end
											drone.PrimaryPart.CanCollide = false
											drone.PrimaryPart.AssemblyAngularVelocity = Vector3.zero
											drone.PrimaryPart.AssemblyLinearVelocity = CFrame.lookAt(drone.PrimaryPart.Position * Vector3.new(1, 0, 1), gen.Position * Vector3.new(1, 0, 1)).LookVector * 30
											magnitude = ((drone.PrimaryPart.Position * Vector3.new(1, 0, 1)) - (gen.Position * Vector3.new(1, 0, 1))).Magnitude
										else
											break
										end
										task.wait()
									until not v or v.Parent ~= workspace.ItemDrops or not AutoCyber.Enabled or magnitude <= 5
								end
							end
						end
					end
					task.wait()
				until not AutoCyber.Enabled
			else
				local drone = getDrone()
				if drone then
					drone.PrimaryPart.CFrame = CFrame.new(drone.PrimaryPart.CFrame.X, 500, drone.PrimaryPart.CFrame.Z)
				end
			end
		end,
		Tooltip = 'Allows you to steal other\'s opponent resources via drone.'
	})
	Mode = AutoCyber:CreateDropdown({
		Name = 'Drop mode',
		List = {'Player', 'Generator'},
		Default = 'Player',
		Tooltip = 'Where cyber items gets dropped to.'
	})
	Whitelist = AutoCyber:CreateTextList({
		Name = 'Whitelist',
		Default = {'emerald', 'diamond'}
	})
	Visual = AutoCyber:CreateToggle({
		Name = 'Visualize',
		Default = true,
		Tooltip = 'Shows what item the drone is targeting and updates\non where how far the drone is to the item.'
	})
	Steal = AutoCyber:CreateToggle({
		Name = 'Steal split',
		Default = true,
		Tooltip = 'Steals other opponent team\'s generator split.'
	})
	Target = AutoCyber:CreateToggle({Name = 'Target check'})
	Limit = AutoCyber:CreateToggle({Name = 'Limit to item'})
end)

run(function()
	local AutoWarden
	local Range
	
	local collected = setmetatable({}, {__mode = 'k'})
	
	AutoWarden = vape.Categories.Minigames:CreateModule({
		Name = 'AutoWarden',
		Function = function(callback)
			if callback then
				table.clear(collected)
	
				repeat
					if entitylib.isAlive and store.equippedKit == 'jailor' then
						local origin = entitylib.character.RootPart.Position
						for _, v in collectionService:GetTagged('jailor_soul') do
							if not collected[v] and v.PrimaryPart and (v.PrimaryPart.Position - origin).Magnitude <= Range.Value then
								collected[v] = true
								bedwars.JailorController:collectEntity(lplr, v, v.Name)
							end
						end
					end
					task.wait(0.1)
				until not AutoWarden.Enabled
			end
		end,
		Tooltip = 'Automatically imprisons the souls dropped by enemies you kill'
	})
	Range = AutoWarden:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 60,
		Default = 25,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end
	})
end)

run(function()
	local Headless
	local Hats
	
	local hidden = setmetatable({}, {__mode = 'k'})
	
	local function setHidden(character, hide)
		local head = character:FindFirstChild('Head')
		if not head then return end
	
		head.LocalTransparencyModifier = hide and 1 or 0
		for _, v in head:GetChildren() do
			if v:IsA('Decal') then
				if hide and not hidden[v] then
					hidden[v] = v.Transparency
				end
				v.Transparency = hide and 1 or (hidden[v] or 0)
			end
		end
	
		for _, v in character:GetChildren() do
			if v:IsA('Accessory') and v.Handle and v.Handle:FindFirstChild('HatAttachment') then
				v.Handle.LocalTransparencyModifier = hide and Hats.Enabled and 1 or 0
			end
		end
	end
	
	Headless = vape.Categories.Render:CreateModule({
		Name = 'Headless',
		Function = function(callback)
			if callback then
				Headless:Clean(runService.PreRender:Connect(function()
					if entitylib.isAlive then
						setHidden(lplr.Character, true)
					end
				end))
			elseif entitylib.isAlive then
				setHidden(lplr.Character, false)
			end
		end,
		Tooltip = 'Hides your own head'
	})
	Hats = Headless:CreateToggle({
		Name = 'Hide hats',
		Default = true,
		Tooltip = 'Hides anything worn on your head too'
	})
end)

run(function()
	local AutoNahila
	local Health
	local Range
	local Allies
	
	AutoNahila = vape.Categories.Minigames:CreateModule({
		Name = 'AutoNahila',
		Function = function(callback)
			if callback then
				repeat
					if entitylib.isAlive and store.equippedKit == 'oasis' and bedwars.AbilityController:canUseAbility('oasis_heal_veil', {disableBlockedAbilityAlert = true}) then
						local character = entitylib.character
						local hurt = (character.Health / character.MaxHealth) <= (Health.Value / 100)
	
						if not hurt and Allies.Enabled then
							local origin = character.RootPart.Position
							for _, v in entitylib.List do
								if not v.Targetable and v.Player and v ~= character and (v.RootPart.Position - origin).Magnitude <= Range.Value and (v.Health / v.MaxHealth) <= (Health.Value / 100) then
									hurt = true
									break
								end
							end
						end
	
						if hurt then
							bedwars.AbilityController:useAbility('oasis_heal_veil')
						end
					end
					task.wait(0.1)
				until not AutoNahila.Enabled
			end
		end,
		Tooltip = 'Automatically drops the heal veil when you or a teammate is hurt'
	})
	Health = AutoNahila:CreateSlider({
		Name = 'Health',
		Min = 1,
		Max = 100,
		Default = 60,
		Suffix = function()
			return '%'
		end,
		Tooltip = 'Heals at or below this much health'
	})
	Allies = AutoNahila:CreateToggle({
		Name = 'Heal teammates',
		Default = true
	})
	Range = AutoNahila:CreateSlider({
		Name = 'Ally range',
		Min = 1,
		Max = 60,
		Default = 25,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end
	})
end)

run(function()
	local AutoYeti
	local Range
	local Targets
	
	AutoYeti = vape.Categories.Minigames:CreateModule({
		Name = 'AutoYeti',
		Function = function(callback)
			if callback then
				repeat
					if entitylib.isAlive and store.equippedKit == 'yeti' and bedwars.AbilityController:canUseAbility('yeti_glacial_roar', {disableBlockedAbilityAlert = true}) then
						local origin = entitylib.character.RootPart.Position
						local found = 0
						for _, v in entitylib.List do
							if v.Targetable and (v.RootPart.Position - origin).Magnitude <= Range.Value then
								found += 1
							end
						end
	
						if found >= Targets.Value then
							bedwars.AbilityController:useAbility('yeti_glacial_roar')
						end
					end
					task.wait(0.1)
				until not AutoYeti.Enabled
			end
		end,
		Tooltip = 'Automatically roars once enough enemies are around you'
	})
	Range = AutoYeti:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 60,
		Default = 30,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end
	})
	Targets = AutoYeti:CreateSlider({
		Name = 'Targets',
		Min = 1,
		Max = 8,
		Default = 1,
		Tooltip = 'Enemies in range before roaring'
	})
end)

run(function()
	local AutoFreiya
	local Range
	local Stacks
	
	AutoFreiya = vape.Categories.Minigames:CreateModule({
		Name = 'AutoFreiya',
		Function = function(callback)
			if callback then
				repeat
					if entitylib.isAlive and store.equippedKit == 'ice_queen' and bedwars.AbilityController:canUseAbility('ice_queen', {disableBlockedAbilityAlert = true}) then
						local origin = entitylib.character.RootPart.Position
						for _, v in entitylib.List do
							if v.Targetable and (v.Character:GetAttribute('IceQueenStacks') or 0) >= Stacks.Value and (v.RootPart.Position - origin).Magnitude <= Range.Value then
								bedwars.AbilityController:useAbility('ice_queen')
								break
							end
						end
					end
					task.wait(0.1)
				until not AutoFreiya.Enabled
			end
		end,
		Tooltip = 'Automatically detonates ice stacks once enemies are frozen enough'
	})
	Range = AutoFreiya:CreateSlider({
		Name = 'Range',
		Min = 1,
		Max = 60,
		Default = 40,
		Suffix = function(val)
			return val <= 1 and 'stud' or 'studs'
		end
	})
	Stacks = AutoFreiya:CreateSlider({
		Name = 'Stacks',
		Min = 1,
		Max = 10,
		Default = 3,
		Tooltip = 'Ice stacks an enemy needs before detonating'
	})
end)

run(function()
	local OverlayEditor
	local FillColor
	local OutlineColor
	local Thickness
	local Animate
	local Speed
	local overlay, overlayBox, overlayTween
	local activePart
	
	local isOverlayPart = function(part)
		return part:IsA('BasePart') and part.Anchored and part.Transparency == 1 and part:FindFirstChildOfClass('SelectionBox') ~= nil
	end
	
	local function hideOverlay()
		if overlayTween then
			overlayTween:Cancel()
			overlayTween = nil
		end
		if overlay then
			overlay.Parent = nil
		end
	end
	
	local moveOverlay = function(part)
		if not overlay then return end
	
		if overlayTween then
			overlayTween:Cancel()
			overlayTween = nil
		end
	
		if Animate.Enabled and overlay.Parent == gameCamera then
			overlayTween = tweenService:Create(overlay, TweenInfo.new(Speed.Value, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = part.CFrame, Size = part.Size})
			overlayTween:Play()
		else
			overlay.CFrame = part.CFrame
			overlay.Size = part.Size
			overlay.Parent = gameCamera
		end
	end
	
	local bindPart = function(part)
		if not OverlayEditor.Enabled or not isOverlayPart(part) then return end
	
		part:FindFirstChildOfClass('SelectionBox').Visible = false
		activePart = part
		moveOverlay(part)
	end
	
	OverlayEditor = vape.Categories.Render:CreateModule({
		Name = 'OverlayEditor',
		Function = function(callback)
			if callback then
				overlay = Instance.new('Part')
				overlay.Size = Vector3.one * 3
				overlay.Anchored = true
				overlay.CanCollide = false
				overlay.CanQuery = false
				overlay.CanTouch = false
				overlay.CastShadow = false
				overlay.Transparency = 1
				overlayBox = Instance.new('SelectionBox')
				overlayBox.Adornee = overlay
				overlayBox.LineThickness = Thickness.Value
				overlayBox.Color3 = Color3.fromHSV(OutlineColor.Hue, OutlineColor.Sat, OutlineColor.Value)
				overlayBox.Transparency = 1 - OutlineColor.Opacity
				overlayBox.SurfaceColor3 = Color3.fromHSV(FillColor.Hue, FillColor.Sat, FillColor.Value)
				overlayBox.SurfaceTransparency = 1 - FillColor.Opacity
				overlayBox.Parent = overlay
				bedwars.QueryUtil:setQueryIgnored(overlay, true)
	
				for _, child in workspace:GetChildren() do
					bindPart(child)
				end
	
				OverlayEditor:Clean(workspace.ChildAdded:Connect(function(child)
					task.defer(bindPart, child)
				end))
				OverlayEditor:Clean(workspace.ChildRemoved:Connect(function(child)
					if child ~= activePart then return end
	
					activePart = nil
					task.delay(0.06, function()
						if not activePart and OverlayEditor.Enabled then
							hideOverlay()
						end
					end)
				end))
			else
				if activePart then
					local box = activePart:FindFirstChildOfClass('SelectionBox')
					if box then
						box.Visible = true
					end
					activePart = nil
				end
	
				hideOverlay()
				if overlay then
					overlay:Destroy()
					overlay, overlayBox = nil, nil
				end
			end
		end,
		Tooltip = 'Restyles the outline on the block you are aiming at'
	})
	FillColor = OverlayEditor:CreateColorSlider({
		Name = 'Fill Color',
		DefaultSat = 0,
		DefaultOpacity = 0.25,
		Darker = true,
		Function = function(hue, sat, val, opacity)
			if overlayBox then
				overlayBox.SurfaceColor3 = Color3.fromHSV(hue, sat, val)
				overlayBox.SurfaceTransparency = 1 - opacity
			end
		end
	})
	OutlineColor = OverlayEditor:CreateColorSlider({
		Name = 'Outline Color',
		DefaultSat = 0,
		Darker = true,
		Function = function(hue, sat, val, opacity)
			if overlayBox then
				overlayBox.Color3 = Color3.fromHSV(hue, sat, val)
				overlayBox.Transparency = 1 - opacity
			end
		end
	})
	Thickness = OverlayEditor:CreateSlider({
		Name = 'Thickness',
		Min = 0.01,
		Max = 0.2,
		Default = 0.04,
		Decimal = 100,
		Function = function(value)
			if overlayBox then
				overlayBox.LineThickness = value
			end
		end
	})
	Animate = OverlayEditor:CreateToggle({
		Name = 'Animate',
		Default = true,
		Tooltip = 'Glides the overlay onto the next block instead of snapping to it'
	})
	Speed = OverlayEditor:CreateSlider({
		Name = 'Animation time',
		Min = 0.01,
		Max = 0.5,
		Default = 0.08,
		Decimal = 100,
		Suffix = 's'
	})
end)

run(function()
    local GraySky
    GraySky = vape.Categories.Render:CreateModule({
        Name = 'Gray Sky',
        Function = function(callback)
            -- Applies the DebugSkyGray FastFlag (renders the sky flat gray).
            -- FastFlags are read at engine startup, so this may only take full
            -- effect after a rejoin; it's applied via the executor's fflag setter.
            pcall(function()
                local val = callback and 'true' or 'false'
                if setfflag then
                    setfflag('FFlagDebugSkyGray', val)
                elseif getgenv().setfflag then
                    getgenv().setfflag('FFlagDebugSkyGray', val)
                end
            end)
        end,
        Tooltip = 'FastFlag FFlagDebugSkyGray = true (gray sky). May need a rejoin to fully apply.'
    })
end)

-- HealthDrop debug: scan workspace for the Health Drop object and log everything about it
run(function()
	local HealthDropDebug

	local debugFile = 'levi_shakingrass/healthdrop_debug.txt'

	local function dumpObject(obj, indent)
		indent = indent or ''
		local lines = {}

		-- Basic info
		table.insert(lines, indent .. 'NAME: ' .. tostring(obj.Name))
		table.insert(lines, indent .. 'CLASS: ' .. obj.ClassName)
		pcall(function()
			table.insert(lines, indent .. 'PARENT: ' .. tostring(obj.Parent and obj.Parent.Name) .. ' (' .. tostring(obj.Parent and obj.Parent.ClassName) .. ')')
		end)
		pcall(function()
			if obj:IsA('BasePart') then
				table.insert(lines, indent .. 'POSITION: ' .. tostring(obj.Position))
				table.insert(lines, indent .. 'SIZE: ' .. tostring(obj.Size))
			end
		end)

		-- Attributes
		pcall(function()
			local attrs = obj:GetAttributes()
			for k, v in attrs do
				table.insert(lines, indent .. 'ATTR[' .. tostring(k) .. '] = ' .. tostring(v))
			end
		end)

		-- Collection tags
		pcall(function()
			local tags = collectionService:GetTags(obj)
			if #tags > 0 then
				table.insert(lines, indent .. 'TAGS: ' .. table.concat(tags, ', '))
			end
		end)

		-- ProximityPrompt info
		pcall(function()
			local pp = obj:FindFirstChildOfClass('ProximityPrompt')
			if pp then
				table.insert(lines, indent .. 'PROXPROMPT: ActionText="' .. tostring(pp.ActionText) .. '" ObjectText="' .. tostring(pp.ObjectText) .. '"')
			end
		end)

		-- Children names (1 level deep)
		local children = obj:GetChildren()
		if #children > 0 then
			local childNames = {}
			for _, c in children do
				table.insert(childNames, c.Name .. '(' .. c.ClassName .. ')')
			end
			table.insert(lines, indent .. 'CHILDREN[' .. #children .. ']: ' .. table.concat(childNames, ', '))
		end

		return table.concat(lines, '\n')
	end

	local function scanAndLog()
		local lpos = entitylib.isAlive and entitylib.character.RootPart.Position or Vector3.zero
		local output = '=== HealthDrop Debug — ' .. os.date('%H:%M:%S') .. ' ===\n'
		output = output .. 'Player pos: ' .. tostring(lpos) .. '\n\n'

		-- 1. All ProximityPrompts in workspace
		output = output .. '=== ALL ProximityPrompts in workspace ===\n'
		local ppCount = 0
		for _, pp in workspace:GetDescendants() do
			if pp:IsA('ProximityPrompt') then
				ppCount += 1
				local dist = '?'
				pcall(function()
					local p = pp.Parent and pp.Parent:IsA('BasePart') and pp.Parent.Position
						or pp.Parent and pp.Parent:FindFirstChildOfClass('BasePart') and pp.Parent:FindFirstChildOfClass('BasePart').Position
					if p then dist = string.format('%.1f', (p - lpos).Magnitude) end
				end)
				output = output .. '  [' .. dist .. 'studs] '
					.. 'ActionText="' .. pp.ActionText .. '" ObjectText="' .. pp.ObjectText
					.. '" parent=' .. tostring(pp.Parent and pp.Parent.Name)
					.. ' (' .. tostring(pp.Parent and pp.Parent.ClassName) .. ')'
					.. ' grandparent=' .. tostring(pp.Parent and pp.Parent.Parent and pp.Parent.Parent.Name)
					.. '\n'
				pcall(function()
					for k, v in (pp.Parent or pp):GetAttributes() do
						output = output .. '    ATTR ' .. k .. ' = ' .. tostring(v) .. '\n'
					end
				end)
			end
		end
		if ppCount == 0 then output = output .. '  (none)\n' end

		-- 2. Everything within 20 studs of player
		output = output .. '\n=== Everything within 20 studs of player ===\n'
		local nearCount = 0
		local seen = {}
		for _, obj in workspace:GetDescendants() do
			if seen[obj] then continue end
			local p
			pcall(function()
				p = obj:IsA('BasePart') and obj.Position or nil
			end)
			if p and (p - lpos).Magnitude <= 20 then
				seen[obj] = true
				nearCount += 1
				local dist = string.format('%.1f', (p - lpos).Magnitude)
				output = output .. '  [' .. dist .. 'studs] ' .. obj.Name .. ' (' .. obj.ClassName .. ')'
					.. ' parent=' .. tostring(obj.Parent and obj.Parent.Name) .. '\n'
				pcall(function()
					for k, v in obj:GetAttributes() do
						output = output .. '    ATTR ' .. k .. ' = ' .. tostring(v) .. '\n'
					end
				end)
				pcall(function()
					local tags = collectionService:GetTags(obj)
					if #tags > 0 then
						output = output .. '    TAGS: ' .. table.concat(tags, ', ') .. '\n'
					end
				end)
			end
		end
		if nearCount == 0 then output = output .. '  (none — stand closer and try again)\n' end

		-- 3. All top-level workspace children names
		output = output .. '\n=== Workspace top-level children ===\n'
		for _, obj in workspace:GetChildren() do
			output = output .. '  ' .. obj.Name .. ' (' .. obj.ClassName .. ')\n'
		end

		pcall(function() writefile(debugFile, output) end)
		pcall(function()
			if setclipboard then setclipboard(output) end
		end)
		notif('HealthDrop Debug', ppCount .. ' proxprompts, ' .. nearCount .. ' nearby parts — saved' .. (setclipboard and ' + clipboard' or ''), 8, 'info')
	end

	HealthDropDebug = vape.Categories.Utility:CreateModule({
		Name = 'HealthDrop Debug',
		Function = function(callback)
			if callback then
				scanAndLog()
				HealthDropDebug:Toggle()
			end
		end,
		Tooltip = 'Scans workspace for Health Drop objects and logs name/class/attributes/children to healthdrop_debug.txt'
	})
end)

run(function()
	local AutoHealthDrop
	local Threshold

	local function tryPickup(item)
		task.spawn(function()
			if not item or not item.Parent then return end

			-- Wait for PickupReadyTime (server-side cooldown on the drop)
			local ready = item:GetAttribute('PickupReadyTime') or 0
			local now = workspace:GetServerTimeNow()
			if ready > now then
				task.wait(ready - now + 0.05)
			end

			if not item.Parent or not AutoHealthDrop.Enabled then return end

			-- Check health threshold
			local char = entitylib.isAlive and entitylib.character
			if not char then return end
			local health = char:GetAttribute('Health') or 100
			local maxHealth = char:GetAttribute('MaxHealth') or 100
			if Threshold and (health / maxHealth) * 100 >= Threshold.Value then return end

			local root = char:FindFirstChild('HumanoidRootPart')
			if not root then return end

			-- The server validates the character's position on pickup.
			-- We own our own character, so briefly teleport to the item,
			-- wait one heartbeat for the position to replicate, fire the
			-- remote, then snap back — effectively invisible.
			local savedCFrame = root.CFrame
			root.CFrame = item.CFrame * CFrame.new(0, 3, 0)
			root.AssemblyLinearVelocity = Vector3.zero
			task.wait()  -- one physics frame for server to register new position

			if item.Parent and AutoHealthDrop.Enabled then
				pcall(function()
					bedwars.Client:Get(remotes.PickupItem):CallServerAsync({ itemDrop = item }):andThen(function(suc)
						if suc and bedwars.SoundList then
							bedwars.SoundManager:playSound(bedwars.SoundList.PICKUP_ITEM_DROP)
						end
					end)
				end)
			end

			-- Snap back regardless of whether pickup succeeded
			root.CFrame = savedCFrame
			root.AssemblyLinearVelocity = Vector3.zero
		end)
	end

	AutoHealthDrop = vape.Categories.Utility:CreateModule({
		Name = 'Auto Health Drop',
		Function = function(callback)
			if callback then
				-- Handle drops that are already in the folder when toggled on
				for _, item in workspace.ItemDrops:GetChildren() do
					if item.Name == 'health_drop' then
						tryPickup(item)
					end
				end
				-- Watch for new drops appearing
				AutoHealthDrop:Clean(workspace.ItemDrops.ChildAdded:Connect(function(item)
					if item.Name == 'health_drop' then
						tryPickup(item)
					end
				end))
			end
		end,
		Tooltip = 'Automatically picks up Health Drops when your HP is below the threshold'
	})
	Threshold = AutoHealthDrop:CreateSlider({
		Name = 'Pickup below',
		Min = 1,
		Max = 100,
		Default = 100,
		Suffix = '% HP',
		Tooltip = '100 = always pick up | 50 = only when below half HP'
	})
end)