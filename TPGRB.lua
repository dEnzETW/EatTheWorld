-- KEDADA ETW AUTOFARM V3.0.7 - HIDDEN MAPS
-- Reconstructed from the previously mapped Auto.txt behavior.
-- Separate test file. Does not overwrite the original source/loader.
-- Timer fix: Sell is sent first; map skip waits for inventory size to decrease.
-- Skip request uses Paused=false. No fixed map countdowns or artificial waits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
if not player then return end

local CFG = {
    Farm = false,
    DefaultZ = 0,
    CentralRobloxiaZ = 350,
    StudvilleZ = 100,
    AutoSkipAfterSell = true,
    UseMappedSkipRemote = true,
    AutoMapModeSwitch = false,
    SmallMaps = {
        ["raven rock"]=true, ["glass houses"]=true, ["courtyard"]=true,
        ["blox city"]=true, ["jungle"]=true, ["community construction"]=true,
        ["candy land"]=true, ["ninja temple"]=true, ["forest peak"]=true,
        ["mini baseplate"]=true, ["martian madness"]=true, ["chaos canyon"]=true,
        ["zombie town"]=true, ["winter workshop"]=true, ["crossroads"]=true,
        ["castle playground"]=true, ["twister"]=true, ["battle zone"]=true,
        ["christmas coast"]=true, ["grid city"]=true,
        ["yorick's resting place"]=true, ["headquarters"]=true,
        ["haunted mansion"]=true, ["snow land"]=true
    }
}

local running, lastMap, lastMode = true, "", ""
local lastFoodAction = 0
local lastSellAttempt = 0
local wasFull = false
local skipSentForCycle = false
local lastSize = nil
local lastBarProgress = nil
local pendingLandingMap = nil
local lastLandingAttempt = 0
local lastAnimationBoost = 0
local missingActionSince = nil
local missingActionSkipSent = false
local lastMissingActionMap = ""
local ACTION_ANIMATION_SPEED = 10.0
local hiddenMapsEnabled = false
local hiddenMapOriginals = {}
local hiddenMapConnections = {}

local function norm(v)
    return string.lower(tostring(v or "")):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

local function getMapName()
    local candidates = {}
    local settings = ReplicatedStorage:FindFirstChild("ServerSettings")
    if settings then
        for _, key in ipairs({"MapName", "CurrentMap"}) do
            local obj = settings:FindFirstChild(key)
            if obj then pcall(function() table.insert(candidates, obj.Value) end) end
        end
    end
    local map = Workspace:FindFirstChild("Map")
    if map then
        table.insert(candidates, map.Name)
        local value = map:FindFirstChild("MapName")
        if value and value:IsA("ValueBase") then table.insert(candidates, value.Value) end
    end
    local playerMap = player:FindFirstChild("CurrentMap")
    if playerMap then pcall(function() table.insert(candidates, playerMap.Value) end) end
    for _, value in ipairs(candidates) do
        if norm(value) ~= "" and norm(value) ~= "map" then
            return tostring(value), norm(value)
        end
    end
    return "Unknown", ""
end

local function getParts()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    local events = char:FindFirstChild("Events")
    if hum and root and events then return char, hum, root, events end
end

local function farmAnchor()
    local char, hum, root = getParts()
    if not char then return false end

    local mapName, key = getMapName()
    local z = key == "central robloxia" and CFG.CentralRobloxiaZ
        or (key == "studville" and CFG.StudvilleZ or CFG.DefaultZ)
    local mapChanged = mapName ~= lastMap

    -- Do not continuously overwrite the character CFrame every Heartbeat.
    -- Wait for actual map floor collision, then teleport once onto that floor.
    if mapChanged then
        lastMap = mapName
        pendingLandingMap = mapName
        lastLandingAttempt = 0
        print("[KEDADA V3.0.7] Map changed; searching for floor:", mapName)
    end

    if not pendingLandingMap then
        return true
    end

    -- Retry only while the destination floor is not available; no fixed wait.
    if os.clock() - lastLandingAttempt < 0.10 then
        return false
    end
    lastLandingAttempt = os.clock()

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    params.IgnoreWater = true

    local origin = Vector3.new(0, 5000, z)
    local result = Workspace:Raycast(origin, Vector3.new(0, -10000, 0), params)

    -- Ignore the script's own artificial bedrock if present.
    local bedrock = Workspace:FindFirstChild("bedrock")
    if result and bedrock and result.Instance == bedrock then
        params.FilterDescendantsInstances = {char, bedrock}
        result = Workspace:Raycast(origin, Vector3.new(0, -10000, 0), params)
    end

    if not result then
        return false
    end

    local targetY = result.Position.Y + hum.HipHeight + root.Size.Y / 2 + 0.15
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    root.CFrame = CFrame.new(0, targetY, z)
    pcall(function()
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    end)

    print("[KEDADA V3.0.7] Landed on map floor:", pendingLandingMap,
        "| X=0 Y=", targetY, "Z=", z)
    pendingLandingMap = nil
    return true
end

local function fire(obj)
    if not obj then return end
    pcall(function()
        if obj:IsA("RemoteEvent") then obj:FireServer()
        elseif obj:IsA("BindableEvent") then obj:Fire() end
    end)
end

local function requestSkip()
    if not CFG.AutoSkipAfterSell or not CFG.UseMappedSkipRemote then return false end

    local folder = ReplicatedStorage:FindFirstChild("Events")
    local remote = folder and folder:FindFirstChild("SetServerSettings")
    if not remote or not remote:IsA("RemoteEvent") then
        warn("[KEDADA V3.0.7] SetServerSettings RemoteEvent not found.")
        return false
    end

    -- Keep the mapped skip command, but do not pause the map timer.
    local ok, err = pcall(function()
        local args = {{MapTime = -1, Paused = false}}
        remote:FireServer(unpack(args))
    end)
    if ok then
        print("[KEDADA V3.0.7] AutoSkip request sent (timer not paused).")
        return true
    end

    warn("[KEDADA V3.0.7] AutoSkip error:", err)
    return false
end

-- If this map/character does not expose both Grab and Eat, request a map
-- transition after a short confirmation window. This avoids reacting to a
-- brief character respawn or map-loading gap.
local function monitorGrabEatAvailability()
    local char = player.Character
    if not char then return end

    local mapName = getMapName()
    local _, key = getMapName()
    if key ~= lastMissingActionMap then
        lastMissingActionMap = key
        missingActionSince = nil
        missingActionSkipSent = false
    end

    local events = char:FindFirstChild("Events")
    local grab = events and events:FindFirstChild("Grab")
    local eat = events and events:FindFirstChild("Eat")
    local ready = grab ~= nil and eat ~= nil

    if ready then
        missingActionSince = nil
        missingActionSkipSent = false
        return
    end

    if not missingActionSince then
        missingActionSince = os.clock()
        return
    end

    if not missingActionSkipSent and os.clock() - missingActionSince >= 3.0 then
        warn("[KEDADA V3.0.7] Grab/Eat missing on", mapName,
            "- requesting automatic map skip.")
        missingActionSkipSent = true
        requestSkip()
    end
end

local function switchModeIfEnabled(mapName)
    if not CFG.AutoMapModeSwitch then return end
    local key = norm(mapName)
    if key == "" or key == lastMode then return end
    local folder = ReplicatedStorage:FindFirstChild("Events")
    local remote = folder and folder:FindFirstChild("RequestTeleport")
    if remote and remote:IsA("RemoteEvent") then
        local mode = CFG.SmallMaps[key] and "Mega" or "Normal"
        if pcall(function() remote:FireServer(mode) end) then
            lastMode = key
            print("[KEDADA V3.0.7] RequestTeleport:", mode, mapName)
        end
    end
end

-- Visual bar detector: locate the "Klik untuk menjual" label and inspect
-- green fill elements near that label. No fixed size/upgrade number is used.
local function getSellBarProgress()
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end

    local label
    for _, obj in ipairs(pg:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) then
            if norm(obj.Text):find("klik untuk menjual", 1, true) then
                label = obj
                break
            end
        end
    end
    if not label then return nil end

    local labelY = label.AbsolutePosition.Y + label.AbsoluteSize.Y / 2
    local ancestor = label.Parent

    -- Search several parent levels because the bar hierarchy differs by UI version.
    for _ = 1, 7 do
        if not ancestor then break end
        if ancestor:IsA("GuiObject") and ancestor.AbsoluteSize.X >= 250 then
            local trackWidth = ancestor.AbsoluteSize.X
            local bestRatio = nil

            for _, obj in ipairs(ancestor:GetDescendants()) do
                if obj:IsA("GuiObject") and obj.Visible
                    and obj.AbsoluteSize.X >= 80 and obj.AbsoluteSize.Y >= 8 then

                    local centerY = obj.AbsolutePosition.Y + obj.AbsoluteSize.Y / 2
                    local nearBar = math.abs(centerY - labelY) <= 90
                    local c = obj.BackgroundColor3
                    local green = c.G > c.R * 1.15 and c.G > c.B * 1.08

                    if nearBar and green then
                        local ratio = math.clamp(obj.AbsoluteSize.X / trackWidth, 0, 1)
                        if not bestRatio or ratio > bestRatio then
                            bestRatio = ratio
                        end
                    end
                end
            end

            if bestRatio then
                return bestRatio
            end
        end
        ancestor = ancestor.Parent
    end

    return nil
end

local function getCapacityState(char)
    local sizeObj = char and char:FindFirstChild("Size")
    local upgrades = player:FindFirstChild("Upgrades")
    local maxObj = upgrades and upgrades:FindFirstChild("MaxSize")

    local size = sizeObj and tonumber(sizeObj.Value) or nil
    local maxSize = maxObj and tonumber(maxObj.Value) or nil
    local numericFull = size ~= nil and maxSize ~= nil and maxSize > 0
        and size >= maxSize

    return size, maxSize, numericFull
end

local function sendAutoSell(events)
    local sell = events and events:FindFirstChild("Sell")
    if not sell then
        warn("[KEDADA V3.0.7] Character.Events.Sell not found.")
        return false
    end
    if not sell:IsA("RemoteEvent") then
        warn("[KEDADA V3.0.7] Sell exists but is not a RemoteEvent:", sell.ClassName)
        return false
    end

    local ok, err = pcall(function()
        sell:FireServer()
    end)
    if not ok then
        warn("[KEDADA V3.0.7] AutoSell error:", err)
        return false
    end

    print("[KEDADA V3.0.7] AutoSell request sent.")
    return true
end

-- Speed up action-priority animations (eating/bending/standing actions)
-- without accelerating normal idle, walk, or run locomotion animations.
local function speedUpActionAnimations(char)
    if os.clock() - lastAnimationBoost < 0.10 then return end
    lastAnimationBoost = os.clock()

    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then return end

    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local priority = track.Priority
        if priority == Enum.AnimationPriority.Action
            or priority == Enum.AnimationPriority.Action2
            or priority == Enum.AnimationPriority.Action3
            or priority == Enum.AnimationPriority.Action4 then
            pcall(function()
                track:AdjustSpeed(ACTION_ANIMATION_SPEED)
            end)
        end
    end
end

local function farmStep()
    local char, hum, root, events = getParts()
    if not char then return end

    farmAnchor()
    speedUpActionAnimations(char)

    -- One Grab followed by three immediate Eat calls per food cycle.
    -- The next cycle begins after the existing 0.04s cadence.
    if os.clock() - lastFoodAction >= 0.04 then
        lastFoodAction = os.clock()
        fire(events:FindFirstChild("Grab"))
        local eatEvent = events:FindFirstChild("Eat")
        fire(eatEvent)
        fire(eatEvent)
        fire(eatEvent)
    end

    local size, maxSize, numericFull = getCapacityState(char)
    local previousBarProgress = lastBarProgress
    local barProgress = getSellBarProgress()
    lastBarProgress = barProgress

    -- Use the actual changing upgrade limit when available. The bar is the
    -- fallback when the game does not expose Size/MaxSize to this client.
    local full
    local barFull = barProgress ~= nil and barProgress >= 0.985
    if size ~= nil and maxSize ~= nil and maxSize > 0 then
        -- Live MaxSize follows upgrades; the bar is an additional visual signal.
        full = numericFull or (barFull and size >= maxSize * 0.97)
    else
        full = barFull
    end

    if full then
        if not wasFull then
            wasFull = true
            skipSentForCycle = false
            lastSellAttempt = 0
            print("[KEDADA V3.0.7] FULL detected | Size:", size,
                "| Live MaxSize:", maxSize, "| Bar:", barProgress)
        end
        -- Retry at a measured interval if the server has not processed a sale.
        if os.clock() - lastSellAttempt >= 1.75 then
            lastSellAttempt = os.clock()
            sendAutoSell(events)
        end
    elseif wasFull then
        -- A drop after a full bar confirms either AutoSell or a manual sale.
        -- Prefer the Size reset/change signal; the bar drop is the fallback.
        local sizeDrop = size ~= nil and lastSize ~= nil and size < lastSize
        local barDrop = barProgress ~= nil and previousBarProgress ~= nil
            and previousBarProgress >= 0.985 and barProgress < 0.90
        local sold = (size ~= nil and maxSize ~= nil and size <= maxSize * 0.05)
            or sizeDrop or barDrop

        if sold then
            print("[KEDADA V3.0.7] Sale/reset detected; requesting AutoSkip.")
            if not skipSentForCycle then
                skipSentForCycle = requestSkip()
            end
            wasFull = false
            lastSellAttempt = 0
            print("[KEDADA V3.0.7] AutoSell cycle re-armed.")
        end
    end

    if size ~= nil then
        lastSize = size
    end

    local mapName = getMapName()
    switchModeIfEnabled(mapName)
end


-- HIDDEN MAPS (client-side visual mode)
-- Only changes local visual transparency. It does NOT unparent/destroy objects,
-- and does not change CanCollide, CanTouch, CanQuery, or food/chunk instances.
local function isProtectedMapObject(obj, mapRoot)
    local current = obj
    while current and current ~= mapRoot do
        local n = norm(current.Name)
        if n:find("food", 1, true)
            or n:find("collect", 1, true)
            or n:find("fruit", 1, true)
            or n:find("snack", 1, true)
            or n:find("eat", 1, true)
            or n == "chunks" or n == "chunk" then
            return true
        end
        current = current.Parent
    end
    return false
end

local function hideMapObject(obj, mapRoot)
    if isProtectedMapObject(obj, mapRoot) then return end

    if obj:IsA("BasePart") then
        if hiddenMapOriginals[obj] == nil then
            hiddenMapOriginals[obj] = {
                kind = "part",
                value = obj.LocalTransparencyModifier
            }
        end
        obj.LocalTransparencyModifier = 1
    elseif obj:IsA("Decal") or obj:IsA("Texture") then
        if hiddenMapOriginals[obj] == nil then
            hiddenMapOriginals[obj] = {
                kind = "texture",
                value = obj.Transparency
            }
        end
        obj.Transparency = 1
    elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail")
        or obj:IsA("Beam") then
        if hiddenMapOriginals[obj] == nil then
            hiddenMapOriginals[obj] = {
                kind = "effect",
                value = obj.Enabled
            }
        end
        obj.Enabled = false
    end
end

local function restoreHiddenMap()
    for obj, saved in pairs(hiddenMapOriginals) do
        if obj and obj.Parent then
            pcall(function()
                if saved.kind == "part" then
                    obj.LocalTransparencyModifier = saved.value
                elseif saved.kind == "texture" then
                    obj.Transparency = saved.value
                elseif saved.kind == "effect" then
                    obj.Enabled = saved.value
                end
            end)
        end
    end
    table.clear(hiddenMapOriginals)

    for _, connection in ipairs(hiddenMapConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(hiddenMapConnections)
end

local function applyHiddenMap()
    local mapRoot = Workspace:FindFirstChild("Map")
    if not mapRoot then
        warn("[KEDADA V3.0.7] Workspace.Map not found; Hidden Maps will retry.")
        return false
    end

    -- Keep the map root and all instances in Workspace.Chunks untouched.
    for _, obj in ipairs(mapRoot:GetDescendants()) do
        hideMapObject(obj, mapRoot)
    end

    table.insert(hiddenMapConnections, mapRoot.DescendantAdded:Connect(function(obj)
        if hiddenMapsEnabled then
            task.defer(function()
                if hiddenMapsEnabled and obj and obj.Parent then
                    hideMapObject(obj, mapRoot)
                end
            end)
        end
    end))

    print("[KEDADA V3.0.7] Hidden Maps ON. Food/chunks and collision are preserved.")
    return true
end

local function setHiddenMaps(enabled)
    hiddenMapsEnabled = enabled
    if enabled then
        restoreHiddenMap()
        hiddenMapsEnabled = true
        applyHiddenMap()
    else
        restoreHiddenMap()
        hiddenMapsEnabled = false
        print("[KEDADA V3.0.7] Hidden Maps OFF. Original local visuals restored.")
    end
end

-- Small draggable mobile panel.
local gui = Instance.new("ScreenGui")
gui.Name = "KEDADA_V304_TEST"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(184, 119)
frame.Position = UDim2.new(0, 12, 0.42, 0)
frame.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 9)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -12, 0, 22)
title.Position = UDim2.fromOffset(6, 3)
title.BackgroundTransparency = 1
title.Text = "KEDADA AUTOFARM V3.0.7"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 11
title.Font = Enum.Font.GothamBold
title.Parent = frame

local button = Instance.new("TextButton")
button.Size = UDim2.new(1, -12, 0, 34)
button.Position = UDim2.fromOffset(6, 29)
button.BackgroundColor3 = Color3.fromRGB(75, 45, 45)
button.BorderSizePixel = 0
button.Text = "AUTOFARM: OFF"
button.TextColor3 = Color3.new(1, 1, 1)
button.TextSize = 12
button.Font = Enum.Font.GothamSemibold
button.Parent = frame
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)

button.Activated:Connect(function()
    CFG.Farm = not CFG.Farm
    button.Text = CFG.Farm and "AUTOFARM: ON" or "AUTOFARM: OFF"
    button.BackgroundColor3 = CFG.Farm and Color3.fromRGB(35, 105, 70) or Color3.fromRGB(75, 45, 45)
    print("[KEDADA V3.0.7] AutoFarm", CFG.Farm and "ON" or "OFF")
end)

local hiddenButton = Instance.new("TextButton")
hiddenButton.Size = UDim2.new(1, -12, 0, 34)
hiddenButton.Position = UDim2.fromOffset(6, 72)
hiddenButton.BackgroundColor3 = Color3.fromRGB(75, 45, 45)
hiddenButton.BorderSizePixel = 0
hiddenButton.Text = "HIDDEN MAPS: OFF"
hiddenButton.TextColor3 = Color3.new(1, 1, 1)
hiddenButton.TextSize = 12
hiddenButton.Font = Enum.Font.GothamSemibold
hiddenButton.Parent = frame
Instance.new("UICorner", hiddenButton).CornerRadius = UDim.new(0, 7)

hiddenButton.Activated:Connect(function()
    setHiddenMaps(not hiddenMapsEnabled)
    hiddenButton.Text = hiddenMapsEnabled and "HIDDEN MAPS: ON" or "HIDDEN MAPS: OFF"
    hiddenButton.BackgroundColor3 = hiddenMapsEnabled
        and Color3.fromRGB(35, 85, 105) or Color3.fromRGB(75, 45, 45)
end)

-- Re-apply when the game replaces Workspace.Map during a map transition.
table.insert(hiddenMapConnections, Workspace.ChildAdded:Connect(function(child)
    if child.Name == "Map" and hiddenMapsEnabled then
        task.defer(function()
            if hiddenMapsEnabled then
                applyHiddenMap()
            end
        end)
    end
end))

local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPos = true, input.Position, frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
frame.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

local connection = RunService.Heartbeat:Connect(function()
    if running and CFG.Farm then
        pcall(monitorGrabEatAvailability)
        pcall(farmStep)
    end
end)
gui.AncestryChanged:Connect(function(_, parent)
    if parent == nil then
        running, CFG.Farm = false, false
        setHiddenMaps(false)
        connection:Disconnect()
    end
end)

print("[KEDADA V3.0.7] Loaded. Eat/Grab=0.04s; action animations boosted to 10x; landing stabilizer retained.")
print("[KEDADA V3.0.7] Bar/capacity detection loaded. Eat/Grab stay active; AutoSell + AutoSkip enabled.")

-- V3.0.7 adds a separate Hidden Maps toggle; V3.0.4 farming logic is retained.

-- V3.0.7: Central Robloxia farm Z adjusted to 350 studs; missing Grab/Eat watchdog requests map skip.

-- V3.0.7 TEST: Action-priority animation speed raised to 10x; Eat cadence remains 0.04s.
