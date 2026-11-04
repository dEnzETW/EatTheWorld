-- dEnzCreator ETW AUTOFARM V3.2.9 - HIDDEN MAPS
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
    CentralRobloxiaZ = 700,
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
local missingActionSince = nil
local missingActionSkipSent = false
local cycleStartedAt = nil
local completedCycleSeconds = 0
local lastNearbyFoodAt = nil
local noFoodSkipSentForMap = false
local noFoodMapKey = ""
local lastFoodScanAt = 0
local cachedFoodNearby = false
local lastMissingActionMap = ""
local hiddenMapsEnabled = false
local hiddenMapOriginals = {}
local hiddenMapConnections = {}
local workspaceMapConnection = nil

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
    if hum and root then return char, hum, root, events end
end

local function farmAnchor()
    local char, hum, root = getParts()
    if not char then return false end

    local mapName, key = getMapName()
    local isCentral = key == "central robloxia" or key == "robloxia tengah"
        or key == "central robloxia map"
    local isStudville = key == "studville"
    local z = isCentral and CFG.CentralRobloxiaZ
        or (isStudville and CFG.StudvilleZ or CFG.DefaultZ)
    local mapChanged = mapName ~= lastMap

    -- Do not continuously overwrite the character CFrame every Heartbeat.
    -- Wait for actual map floor collision, then teleport once onto that floor.
    if mapChanged then
        lastMap = mapName
        pendingLandingMap = mapName
        lastLandingAttempt = 0
        print("[dEnzCreator V3.2.9] Map changed; searching for floor:", mapName)
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

    print("[dEnzCreator V3.2.9] Landed on map floor:", pendingLandingMap,
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
        warn("[dEnzCreator V3.2.9] SetServerSettings RemoteEvent not found.")
        return false
    end

    -- Keep the mapped skip command, but do not pause the map timer.
    local ok, err = pcall(function()
        local args = {{MapTime = -1, Paused = false}}
        remote:FireServer(unpack(args))
    end)
    if ok then
        print("[dEnzCreator V3.2.9] AutoSkip request sent (timer not paused).")
        return true
    end

    warn("[dEnzCreator V3.2.9] AutoSkip error:", err)
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
        warn("[dEnzCreator V3.2.9] Grab/Eat missing on", mapName,
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
            print("[dEnzCreator V3.2.9] RequestTeleport:", mode, mapName)
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
        warn("[dEnzCreator V3.2.9] Character.Events.Sell not found.")
        return false
    end
    if not sell:IsA("RemoteEvent") then
        warn("[dEnzCreator V3.2.9] Sell exists but is not a RemoteEvent:", sell.ClassName)
        return false
    end

    local ok, err = pcall(function()
        sell:FireServer()
    end)
    if not ok then
        warn("[dEnzCreator V3.2.9] AutoSell error:", err)
        return false
    end

    print("[dEnzCreator V3.2.9] AutoSell request sent.")
    return true
end

-- Detect collectible food/chunks close to the character from live Workspace.Chunks state.
-- No fixed 13-second loading delay: map readiness is inferred from live instances.
-- The Grab/Eat loop is not gated by this detector and continues during transitions.
local NO_FOOD_RADIUS = 100
local NO_FOOD_CONFIRM_SECONDS = nil -- disabled temporarily

local function findNearbyFood(char, root)
    local chunks = Workspace:FindFirstChild("Chunks")
    if not chunks then return false end

    local radiusSquared = NO_FOOD_RADIUS * NO_FOOD_RADIUS
    for _, obj in ipairs(chunks:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Parent and obj:IsDescendantOf(chunks) then
            local delta = obj.Position - root.Position
            if delta:Dot(delta) <= radiusSquared then
                return true
            end
        end
    end
    return false
end

local function monitorNearbyFood(char, root)
    if os.clock() - lastFoodScanAt < 1 then
        return cachedFoodNearby
    end
    lastFoodScanAt = os.clock()
    local _, key = getMapName()
    if key ~= noFoodMapKey then
        noFoodMapKey = key
        lastNearbyFoodAt = nil
        noFoodSkipSentForMap = false
        cachedFoodNearby = false
        lastFoodScanAt = 0
    end

    if findNearbyFood(char, root) then
        cachedFoodNearby = true
        lastNearbyFoodAt = os.clock()
        return true
    end
    cachedFoodNearby = false

    if not lastNearbyFoodAt then
        lastNearbyFoodAt = os.clock()
        return false
    end

    return false
end

-- Conservative 5x animation acceleration.
-- Restore the earlier narrow behavior: only tracks explicitly named Grab/Eat.
-- Do not hook AnimationPlayed, defer repeated speed changes, or affect other actions.
local ACTION_ANIMATION_SPEED = 5.0
local function accelerateActionAnimations(hum)
    if not hum then return end
    local ok, tracks = pcall(function()
        return hum:GetPlayingAnimationTracks()
    end)
    if not ok or type(tracks) ~= "table" then return end

    for _, track in ipairs(tracks) do
        local trackName = string.lower(tostring(track.Name or ""))
        if trackName:find("grab", 1, true) or trackName:find("eat", 1, true) then
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
    accelerateActionAnimations(hum)

    local foodNearby = monitorNearbyFood(char, root)

    -- One Grab followed by three immediate Eat calls per food cycle.
    -- The next cycle begins after the existing 0.04s cadence.
    if events and os.clock() - lastFoodAction >= 0.04 then
        lastFoodAction = os.clock()
        local grabEvent = events:FindFirstChild("Grab")
        local eatEvent = events and events:FindFirstChild("Eat")
        -- Season timer starts when both live Grab/Eat controls are available
        -- and this farm cycle actually begins, not when nearby food is scanned.
        if grabEvent and eatEvent and cycleStartedAt == nil then
            cycleStartedAt = os.clock()
            completedCycleSeconds = 0
            print("[dEnzCreator V3.2.9] Season time started: Grab/Eat menu active.")
        end
        fire(grabEvent)
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
        -- Season timer stops only on the actual visual sell-bar full signal.
        if barFull and cycleStartedAt ~= nil then
            completedCycleSeconds = math.max(0, os.clock() - cycleStartedAt)
            cycleStartedAt = nil
            print("[dEnzCreator V3.2.9] Season time stopped: sell bar detected full.")
        end
        if not wasFull then
            wasFull = true
            skipSentForCycle = false
            lastSellAttempt = 0
            print("[dEnzCreator V3.2.9] FULL detected | Size:", size,
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
            print("[dEnzCreator V3.2.9] Sale/reset detected; requesting AutoSkip.")
            if not skipSentForCycle then
                skipSentForCycle = requestSkip()
            end
            wasFull = false
            lastSellAttempt = 0
            print("[dEnzCreator V3.2.9] AutoSell cycle re-armed.")
        end
    end

    if size ~= nil then
        lastSize = size
    end

    local mapName = getMapName()
    switchModeIfEnabled(mapName)
end


-- HIDDEN MAPS: BLACK WORLD MODE (client-side visuals only)
-- Hide map scenery AND food/chunk visuals for a nearly black world view.
-- All instances remain parented; collision/touch/query and gameplay logic are unchanged.
local function hideMapObject(obj, mapRoot)
    if obj == mapRoot then return end

    if obj:IsA("BasePart") then
        if hiddenMapOriginals[obj] == nil then
            hiddenMapOriginals[obj] = {kind = "part", value = obj.LocalTransparencyModifier}
        end
        obj.LocalTransparencyModifier = 1
    elseif obj:IsA("Decal") or obj:IsA("Texture") then
        if hiddenMapOriginals[obj] == nil then
            hiddenMapOriginals[obj] = {kind = "texture", value = obj.Transparency}
        end
        obj.Transparency = 1
    elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail")
        or obj:IsA("Beam") then
        if hiddenMapOriginals[obj] == nil then
            hiddenMapOriginals[obj] = {kind = "effect", value = obj.Enabled}
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
    local roots = {}
    local mapRoot = Workspace:FindFirstChild("Map")
    local chunksRoot = Workspace:FindFirstChild("Chunks")
    if mapRoot then table.insert(roots, mapRoot) end
    if chunksRoot then table.insert(roots, chunksRoot) end
    if #roots == 0 then
        warn("[dEnzCreator V3.2.9] Map/Chunks not found; Hidden Maps will retry.")
        return false
    end

    for _, root in ipairs(roots) do
        for _, obj in ipairs(root:GetDescendants()) do
            hideMapObject(obj, root)
        end
        table.insert(hiddenMapConnections, root.DescendantAdded:Connect(function(obj)
            if hiddenMapsEnabled then
                task.defer(function()
                    if hiddenMapsEnabled and obj and obj.Parent then
                        hideMapObject(obj, root)
                    end
                end)
            end
        end))
    end

    print("[dEnzCreator V3.2.9] Black World ON. Map + food visuals hidden; collision/gameplay preserved.")
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
        print("[dEnzCreator V3.2.9] Black World OFF. Original visuals restored.")
    end
end

-- dEnzCreator compact mobile panel (140 px wide).
local gui = Instance.new("ScreenGui")
gui.Name = "dEnzCreator_ETW"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(140, 0)
frame.AutomaticSize = Enum.AutomaticSize.Y
frame.Position = UDim2.new(0, 12, 0.42, 0)
frame.BackgroundColor3 = Color3.fromRGB(20, 22, 38)
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
local frameStroke = Instance.new("UIStroke", frame)
frameStroke.Color = Color3.fromRGB(104, 93, 160)
frameStroke.Thickness = 1

local padding = Instance.new("UIPadding", frame)
padding.PaddingTop = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 7)
padding.PaddingLeft = UDim.new(0, 6)
padding.PaddingRight = UDim.new(0, 6)

local layout = Instance.new("UIListLayout", frame)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 5)

local header = Instance.new("Frame")
header.LayoutOrder = 1
header.Size = UDim2.new(1, 0, 0, 64)
header.BackgroundColor3 = Color3.fromRGB(37, 39, 62)
header.BackgroundTransparency = 0
header.BorderSizePixel = 0
header.Parent = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 7)
local headerStroke = Instance.new("UIStroke", header)
headerStroke.Color = Color3.fromRGB(125, 105, 195)
headerStroke.Thickness = 1

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -48, 0, 23)
title.Position = UDim2.fromOffset(6, 1)
title.BackgroundTransparency = 1
title.Text = "dEnzCreator"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 11
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local minimize = Instance.new("TextButton")
minimize.Size = UDim2.fromOffset(20, 20)
minimize.Position = UDim2.new(1, -42, 0, 1)
minimize.Text = "–"
minimize.TextSize = 16
minimize.Font = Enum.Font.GothamBold
minimize.TextColor3 = Color3.new(1, 1, 1)
minimize.BackgroundColor3 = Color3.fromRGB(49, 48, 76)
minimize.Parent = header
Instance.new("UICorner", minimize).CornerRadius = UDim.new(1, 0)

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(20, 20)
close.Position = UDim2.new(1, -21, 0, 1)
close.Text = "×"
close.TextSize = 16
close.Font = Enum.Font.GothamBold
close.TextColor3 = Color3.new(1, 1, 1)
close.BackgroundColor3 = Color3.fromRGB(49, 48, 76)
close.Parent = header
Instance.new("UICorner", close).CornerRadius = UDim.new(1, 0)

local runtimeBlock = Instance.new("TextLabel")
runtimeBlock.Name = "RuntimeBlock"
runtimeBlock.Size = UDim2.new(1, -12, 0, 34)
runtimeBlock.Position = UDim2.fromOffset(6, 27)
runtimeBlock.BackgroundTransparency = 1
runtimeBlock.BorderSizePixel = 0
runtimeBlock.Text = "Runtime: 0m 0s\nSeason time: 0m 0s"
runtimeBlock.TextColor3 = Color3.fromRGB(240, 243, 248)
runtimeBlock.TextSize = 8
runtimeBlock.Font = Enum.Font.GothamMedium
runtimeBlock.TextXAlignment = Enum.TextXAlignment.Left
runtimeBlock.TextYAlignment = Enum.TextYAlignment.Center
-- Important: timer label is parented directly to header and has no background of its own.
runtimeBlock.Parent = header

local function makeToggle(label, order, color, initial, callback)
    local b = Instance.new("TextButton")
    b.LayoutOrder = order
    b.Size = UDim2.new(1, 0, 0, 30)
    b.BackgroundColor3 = initial and color or Color3.fromRGB(54, 52, 76)
    b.BorderSizePixel = 0
    b.Text = label .. (initial and ": ON" or ": OFF")
    b.TextColor3 = Color3.new(1, 1, 1)
    b.TextSize = 9
    b.Font = Enum.Font.GothamSemibold
    b.TextWrapped = true
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
    local enabled = initial
    b.Activated:Connect(function()
        enabled = not enabled
        b.Text = label .. (enabled and ": ON" or ": OFF")
        b.BackgroundColor3 = enabled and color or Color3.fromRGB(54, 52, 76)
        callback(enabled)
    end)
    return b
end

makeToggle("AUTOFARM", 2, Color3.fromRGB(35, 150, 112), CFG.Farm, function(on)
    CFG.Farm = on
    print("[dEnzCreator] AutoFarm", on and "ON" or "OFF")
end)

makeToggle("HIDDEN MAPS", 3, Color3.fromRGB(65, 105, 190), hiddenMapsEnabled, function(on)
    setHiddenMaps(on)
end)

local autoClaimEnabled = false
local lastRewardClaim = 0
local lastSpinRequest = 0
local function claimRewardsStep()
    if not autoClaimEnabled or os.clock() - lastRewardClaim < 1 then return end
    lastRewardClaim = os.clock()

    local events = ReplicatedStorage:FindFirstChild("Events")
    if not events then return end

    local timedRewards = player:FindFirstChild("TimedRewards")
    local rewardEvent = events:FindFirstChild("RewardEvent")
    if timedRewards and rewardEvent then
        for _, reward in ipairs(timedRewards:GetChildren()) do
            local value
            pcall(function() value = tonumber(reward.Value) end)
            if value and value > 0 then
                pcall(function() rewardEvent:FireServer(reward) end)
            end
        end
    end

    -- Spin request is throttled separately to avoid rapid remote firing.
    local spinEvent = events:FindFirstChild("SpinEvent")
    if spinEvent and os.clock() - lastSpinRequest >= 10 then
        lastSpinRequest = os.clock()
        pcall(function() spinEvent:FireServer() end)
    end
end

makeToggle("AUTO CLAIM REWARDS", 4, Color3.fromRGB(133, 89, 195), false, function(on)
    autoClaimEnabled = on
end)

local minimized = false
local hiddenItems = {}
minimize.Activated:Connect(function()
    minimized = not minimized
    for _, child in ipairs(frame:GetChildren()) do
        if child ~= header and child:IsA("GuiObject") then
            child.Visible = not minimized
        end
    end
    minimize.Text = minimized and "+" or "–"
end)
close.Activated:Connect(function()
    running, CFG.Farm = false, false
    autoClaimEnabled = false
    setHiddenMaps(false)
    gui:Destroy()
end)

-- Wall-clock timers: update independently of AutoFarm activity.
-- Runtime is retained across script re-execution if the executor keeps its environment.
-- Same os.clock() timer basis as the first working runtime panel.
local scriptStartedAt = os.clock()
local sessionStartedAt = os.clock()
local function formatDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, secs)
    end
    return string.format("%dm %ds", minutes, secs)
end

local function findCashValue()
    local candidates = {
        player:FindFirstChild("leaderstats"),
        player:FindFirstChild("Data"),
        player:FindFirstChild("Stats")
    }
    for _, folder in ipairs(candidates) do
        if folder then
            for _, obj in ipairs(folder:GetDescendants()) do
                if (obj:IsA("IntValue") or obj:IsA("NumberValue"))
                    and (norm(obj.Name):find("cash", 1, true)
                    or norm(obj.Name):find("coin", 1, true)
                    or norm(obj.Name):find("money", 1, true)
                    or norm(obj.Name):find("gold", 1, true)) then
                    return tonumber(obj.Value)
                end
            end
        end
    end
    return nil
end

local function readMapCountdown()
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return nil end
    for _, obj in ipairs(pg:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local t = tostring(obj.Text or "")
            local mm, ss = t:match("(%d%d?):(%d%d)")
            if mm and ss then
                local total = tonumber(mm) * 60 + tonumber(ss)
                if total >= 0 and total <= 3600 then
                    return total
                end
            end
        end
    end
    return nil
end

local function countChunks()
    local chunks = Workspace:FindFirstChild("Chunks")
    if not chunks then return nil end
    return #chunks:GetChildren()
end

local function updateRuntimeMonitor()
    -- os.time() measures real elapsed wall time, not CPU time or map duration.
    local now = os.clock()
    runtimeBlock.Text = string.format(
        "Runtime: %s\nSeason time: %s",
        formatDuration(now - scriptStartedAt),
        formatDuration(cycleStartedAt and (now - cycleStartedAt) or completedCycleSeconds)
    )
end


-- Re-apply when the game replaces Map or Chunks during map transitions.
workspaceMapConnection = Workspace.ChildAdded:Connect(function(child)
    if (child.Name == "Map" or child.Name == "Chunks") and hiddenMapsEnabled then
        task.defer(function()
            if hiddenMapsEnabled then applyHiddenMap() end
        end)
    end
end)

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
    if not running then return end
    pcall(updateRuntimeMonitor)
    pcall(claimRewardsStep)
    if CFG.Farm then
        pcall(monitorGrabEatAvailability)
        pcall(farmStep)
    end
end)
gui.AncestryChanged:Connect(function(_, parent)
    if parent == nil then
        running, CFG.Farm = false, false
        autoClaimEnabled = false
        setHiddenMaps(false)
        if workspaceMapConnection then workspaceMapConnection:Disconnect() end
        connection:Disconnect()
    end
end)

print("[dEnzCreator V3.2.9] Loaded. Eat/Grab loop resumes whenever character Events are available at 0.04s cadence; 5x named Grab/Eat animation acceleration; landing stabilizer retained.")
print("[dEnzCreator V3.2.9] Bar/capacity detection loaded. Eat/Grab stay active; AutoSell + AutoSkip enabled.")

-- V3.2.9 adds a separate Hidden Maps toggle; V3.0.4 farming logic is retained.

-- V3.2.9: Central Robloxia farm Z set to 700 studs for retest; missing Grab/Eat watchdog requests map skip.

-- V3.2.9 adds a live runtime/statistics panel. Unknown game values display as -- rather than fabricated numbers.


-- V3.2.9: Combined title/timer header (140px), left-aligned title, 5x named Grab/Eat animation acceleration. Remote cadence is unchanged.

-- V3.2.9: Season time starts when map food objects are detected and stops when the sell bar reaches full.
