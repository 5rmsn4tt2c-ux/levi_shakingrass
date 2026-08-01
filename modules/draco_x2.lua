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
end)
