-- Sword Changer Module (extracted from games/6872274481.lua)
-- Depends on: vape, vapeEvents, lplr, gameCamera, store, bedwars, replicatedStorage

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
