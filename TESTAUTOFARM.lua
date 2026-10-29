-- ETW Continuous Grind Test v1
-- Standalone prototype. Does NOT modify ETW.DRAMA master.
-- Tests continuous Grab/Eat + optional auto-sell while the game handles map transitions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if not player then
    warn("[ETW Grind Test] LocalPlayer unavailable.")
    return
end

local running = true
local autoFarm = false
local autoSell = true
local fullFlag = false
local lastSellAt = 0
local sellDebounce = 0.8
local connections = {}

local function getCharacterEvents()
    local character = player.Character
    if not character then return nil, nil end
    local folder = character:FindFirstChild("Events")
    if not folder then return character, nil end

    return character, {
        Grab = folder:FindFirstChild("Grab"),
        Eat = folder:FindFirstChild("Eat"),
        Sell = folder:FindFirstChild("Sell"),
    }
end

local function bindFullFlag(character)
    fullFlag = false
    local folder = character and character:FindFirstChild("Events")
    local eat = folder and folder:FindFirstChild("Eat")
    if eat and eat:IsA("RemoteEvent") then
        local connection = eat.OnClientEvent:Connect(function()
            fullFlag = true
        end)
        table.insert(connections, connection)
    end
end

local function isInventoryFull()
    if fullFlag then return true end

    local gui = player:FindFirstChild("PlayerGui")
    local screen = gui and gui:FindFirstChild("ScreenGui")
    local sellGui = screen and screen:FindFirstChild("Sell")
    if not sellGui then return false end

    local warning = sellGui:FindFirstChild("WarningText")
    if warning and warning.Visible and (warning.TextTransparency or 0) < 0.5 then
        return true
    end

    local sellText = sellGui:FindFirstChild("SellText")
    if sellText and sellText.Visible then return true end

    local bar = sellGui:FindFirstChild("ProgressBar")
    if bar and bar:IsA("GuiObject") and bar.Size.X.Scale >= 0.98 then
        return true
    end

    return false
end

local function sellNow()
    local _, events = getCharacterEvents()
    if events and events.Sell then
        pcall(function() events.Sell:FireServer() end)
    end

    -- Optional UI fallback if the executor exposes firesignal.
    local gui = player:FindFirstChild("PlayerGui")
    local screen = gui and gui:FindFirstChild("ScreenGui")
    local sellGui = screen and screen:FindFirstChild("Sell")
    local button = sellGui and sellGui:FindFirstChild("SellButton")
    if button and typeof(firesignal) == "function" then
        pcall(function()
            firesignal(button.Activated)
            firesignal(button.MouseButton1Click)
        end)
    end

    fullFlag = false
    print("[ETW Grind Test] Sell requested.")
end

-- Minimal separate control panel; does not touch the master UI.
local playerGui = player:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("ETW_ContinuousGrindTest")
if oldGui then oldGui:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ETW_ContinuousGrindTest"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromOffset(230, 132)
frame.Position = UDim2.new(0, 18, 0.42, 0)
frame.BackgroundColor3 = Color3.fromRGB(8, 18, 25)
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(0, 220, 245)
stroke.Thickness = 1.2
stroke.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 26)
title.Position = UDim2.fromOffset(8, 5)
title.BackgroundTransparency = 1
title.Text = "ETW CONTINUOUS GRIND TEST"
title.TextColor3 = Color3.fromRGB(150, 245, 255)
title.TextSize = 12
title.Font = Enum.Font.GothamBold
title.Parent = frame

local function makeButton(name, y, initialText)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Size = UDim2.new(1, -16, 0, 34)
    button.Position = UDim2.fromOffset(8, y)
    button.BackgroundColor3 = Color3.fromRGB(12, 42, 52)
    button.BorderSizePixel = 0
    button.Text = initialText
    button.TextColor3 = Color3.fromRGB(225, 250, 255)
    button.TextSize = 12
    button.Font = Enum.Font.GothamSemibold
    button.Parent = frame
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 7)
    c.Parent = button
    return button
end

local farmButton = makeButton("AutoFarmButton", 35, "AutoFarm: OFF")
local sellButton = makeButton("AutoSellButton", 75, "AutoSell: ON")

farmButton.Activated:Connect(function()
    autoFarm = not autoFarm
    farmButton.Text = "AutoFarm: " .. (autoFarm and "ON" or "OFF")
    farmButton.BackgroundColor3 = autoFarm
        and Color3.fromRGB(0, 100, 112)
        or Color3.fromRGB(12, 42, 52)
    print("[ETW Grind Test] AutoFarm", autoFarm and "ON" or "OFF")
end)

sellButton.Activated:Connect(function()
    autoSell = not autoSell
    sellButton.Text = "AutoSell: " .. (autoSell and "ON" or "OFF")
    sellButton.BackgroundColor3 = autoSell
        and Color3.fromRGB(0, 100, 112)
        or Color3.fromRGB(12, 42, 52)
    print("[ETW Grind Test] AutoSell", autoSell and "ON" or "OFF")
end)

bindFullFlag(player.Character)
table.insert(connections, player.CharacterAdded:Connect(function(character)
    -- Rebind the full-inventory signal for the new character without stopping the loop.
    task.defer(function()
        bindFullFlag(character)
    end)
end))

-- Continuous loop: reacquire character/remotes each pass so respawn/map transitions
-- don't permanently leave stale character/event references behind.
task.spawn(function()
    while running do
        if autoFarm then
            local character, events = getCharacterEvents()

            local localEvents = ReplicatedStorage:FindFirstChild("LocalEvents")
            local localGrab = localEvents and localEvents:FindFirstChild("Grab")
            local localEat = localEvents and localEvents:FindFirstChild("Eat")

            if character and events then
                pcall(function()
                    if localGrab and localGrab:IsA("BindableEvent") then
                        localGrab:Fire()
                    elseif events.Grab and events.Grab:IsA("RemoteEvent") then
                        events.Grab:FireServer(false, false, false)
                    end

                    if localEat and localEat:IsA("BindableEvent") then
                        localEat:Fire()
                    elseif events.Eat and events.Eat:IsA("RemoteEvent") then
                        events.Eat:FireServer()
                    end
                end)

                if autoSell and isInventoryFull() and (os.clock() - lastSellAt) >= sellDebounce then
                    lastSellAt = os.clock()
                    pcall(sellNow)
                end
            end
            task.wait()
        else
            task.wait(0.1)
        end
    end
end)

-- Cleanup if this GUI is removed manually.
screenGui.AncestryChanged:Connect(function(_, parent)
    if parent == nil then
        running = false
        for _, connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
        end
    end
end)

print("[ETW Grind Test] Loaded. Toggle AutoFarm ON to test continuous Grab/Eat + auto-sell.")
print("[ETW Grind Test] This prototype does not force map skips; it observes the game's normal transition.")
