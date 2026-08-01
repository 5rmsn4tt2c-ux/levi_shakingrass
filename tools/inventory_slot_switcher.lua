local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local lplr = Players.LocalPlayer
local Store = require(lplr.PlayerScripts.TS.ui.store).ClientStore

local SLOT_A = 0
local SLOT_B = 1
local SWITCH_DELAY = 0.05

local running = false
local toggle = Instance.new('BindableEvent')

local function switchLoop()
    local current = SLOT_A
    while running do
        Store:dispatch({
            type = 'InventorySelectHotbarSlot',
            slot = current
        })
        current = current == SLOT_A and SLOT_B or SLOT_A
        task.wait(SWITCH_DELAY)
    end
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.H then
        running = not running
        if running then
            task.spawn(switchLoop)
        end
    end
end)
