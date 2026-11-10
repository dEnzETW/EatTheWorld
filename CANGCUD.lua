local WHITELIST_URL =
    "https://raw.githubusercontent.com/dEnzETW/EatTheWorld/refs/heads/main/WhiteList.lua"
local whitelistOK, whitelistResult = pcall(function()
    local source = game:HttpGet(WHITELIST_URL)
    assert(type(source) == "string" and #source > 0,
        "Whitelist file kosong")
    local chunk, compileError = loadstring(source)
    assert(chunk, compileError or "Whitelist compile gagal")
    return chunk()
end)
if not whitelistOK or whitelistResult ~= true then
    warn("[dEnzCreator] WHITELIST DENIED / LOAD FAILED")
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "dEnzCreator",
            Text = "Whitelist gagal atau akses ditolak.",
            Duration = 5
        })
    end)
    return
end
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
if not player then return end
local CFG = {
    Farm = false,
    AutoSkipAfterSell = true,
    UseMappedSkipRemote = true,
}
local running, lastMap = true, ""
local grabEatPhase = "grab"
local nextGrabEatActionAt = 0
local GRAB_DELAY_BASE = 0.02
local POST_GRAB_DELAY_BASE = 0.02
local DELAY_ACCELERATION = 12
local GRAB_DELAY = GRAB_DELAY_BASE / DELAY_ACCELERATION
local POST_GRAB_DELAY = POST_GRAB_DELAY_BASE / DELAY_ACCELERATION
local lastSellAttempt = 0
local wasFull = false
local skipSentForCycle = false
local lastSize = nil
local lastBarProgress = nil
local pendingLandingMap = nil
local landingConfirmedAt = nil
local lastLandingAttempt = 0
local missingActionSince = nil
local missingActionSkipSent = false
local cycleStartedAt = nil
local completedCycleSeconds = 0
local noFoodSkipSentForMap = false
local noFoodMapKey = ""
local noFoodSince = nil
local noFoodChunksRoot = nil
local chunksReadySince = nil
local lastFoodScanAt = 0
local lastMissingActionMap = ""
local hiddenMapsEnabled = false
local hiddenMapOriginals = setmetatable({}, {__mode = "k"})
local workspaceMapConnection = nil
local characterTransitionEnabled = false
local transitionBoundCharacter = nil
local transitionDisabledScripts = {}
local characterTransitionConnection = nil
local function setCharacterScriptDisabled(scriptObject, disabled)
    if not scriptObject or not scriptObject:IsA("LocalScript") then return end
    if transitionDisabledScripts[scriptObject] == nil then
        transitionDisabledScripts[scriptObject] = scriptObject.Disabled
    end
    pcall(function()
        scriptObject.Disabled = disabled
    end)
end
local function applyCharacterTransitionToCharacter(char, hum)
    if not characterTransitionEnabled or not char then return end
    if transitionBoundCharacter ~= char then
        transitionBoundCharacter = char
    end
    setCharacterScriptDisabled(char:FindFirstChild("LocalChunkManager"), true)
    setCharacterScriptDisabled(char:FindFirstChild("Animate"), true)
end
local function restoreCharacterTransition()
    characterTransitionEnabled = false
    transitionBoundCharacter = nil
    for scriptObject, wasDisabled in pairs(transitionDisabledScripts) do
        if scriptObject then
            pcall(function()
                scriptObject.Disabled = wasDisabled
            end)
        end
    end
    table.clear(transitionDisabledScripts)
end
local function setCharacterTransition(enabled)
    characterTransitionEnabled = enabled and true or false
    if not characterTransitionEnabled then
        restoreCharacterTransition()
        return
    end
    local char, hum = player.Character, nil
    if char then hum = char:FindFirstChildOfClass("Humanoid") end
    applyCharacterTransitionToCharacter(char, hum)
end
local function norm(v)
    return string.lower(tostring(v or "")):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end
local worldRootsDetached = false
local detachedWorldRoots = {Map = {}, Chunks = {}}
local latestDetachedMapRoot = nil
local function detachWorldRoot(root)
    if not root or (root.Name ~= "Map" and root.Name ~= "Chunks") then return end
    local bucket = detachedWorldRoots[root.Name]
    for _, saved in ipairs(bucket) do
        if saved == root then return end
    end
    table.clear(bucket)
    table.insert(bucket, root)
    if root.Name == "Map" then latestDetachedMapRoot = root end
    pcall(function() root.Parent = nil end)
end
local function detachCurrentWorldRoots()
    worldRootsDetached = true
    local mapRoot = Workspace:FindFirstChild("Map")
    local chunksRoot = Workspace:FindFirstChild("Chunks")
    if mapRoot then detachWorldRoot(mapRoot) end
    if chunksRoot then detachWorldRoot(chunksRoot) end
end
local function restoreWorldRoots()
    worldRootsDetached = false
    for _, rootName in ipairs({"Map", "Chunks"}) do
        local bucket = detachedWorldRoots[rootName]
        for _, root in ipairs(bucket) do
            if root then
                pcall(function()
                    if root.Parent == nil then root.Parent = Workspace end
                end)
            end
        end
        table.clear(bucket)
    end
    latestDetachedMapRoot = nil
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
    local map = Workspace:FindFirstChild("Map") or latestDetachedMapRoot
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
local FARM_FLOOR_NAME = "dEnzCreator_FarmFloor"
local FARM_FLOOR_SIZE = Vector3.new(2048, 10, 2048)
local FARM_FLOOR_HALF_HEIGHT = FARM_FLOOR_SIZE.Y / 2
local FARM_LANDING_X = 0
local FARM_LANDING_Z = 100
local FARM_SURFACE_SCAN_INTERVAL = 0.20
local FARM_SURFACE_RAY_TOP = 10000
local FARM_SURFACE_RAY_LENGTH = 20000
local farmFloor = nil
local farmSurfaceMapKey = ""
local farmSurfaceTopY = nil
local lastFarmSurfaceScan = 0
local function lockFarmFloor(floor)
    if not floor or not floor:IsA("BasePart") then return nil end
    if floor.Size ~= FARM_FLOOR_SIZE then
        floor.Size = FARM_FLOOR_SIZE
    end
    if not floor.Anchored then floor.Anchored = true end
    if not floor.CanCollide then floor.CanCollide = true end
    if not floor.CanTouch then floor.CanTouch = true end
    if not floor.CanQuery then floor.CanQuery = true end
    return floor
end
local function ensureFarmFloor()
    if farmFloor and farmFloor.Parent == Workspace then
        return lockFarmFloor(farmFloor)
    end
    local existing = Workspace:FindFirstChild(FARM_FLOOR_NAME)
    if existing and existing:IsA("BasePart") then
        farmFloor = existing
        return lockFarmFloor(farmFloor)
    end
    local floor = Instance.new("Part")
    floor.Name = FARM_FLOOR_NAME
    floor.CastShadow = false
    floor.Color = Color3.fromRGB(5, 5, 7)
    floor.Material = Enum.Material.SmoothPlastic
    floor.TopSurface = Enum.SurfaceType.Studs
    floor.BottomSurface = Enum.SurfaceType.Smooth
    floor.Parent = Workspace
    farmFloor = floor
    return lockFarmFloor(farmFloor)
end
local function detectMapSurfaceTopY()
    local mapRoot = Workspace:FindFirstChild("Map")
    if not mapRoot then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {mapRoot, Workspace.Terrain}
    params.IgnoreWater = true
    local offsets = {
        {0, 0}, {4, 0}, {-4, 0}, {0, 4}, {0, -4},
        {8, 8}, {-8, 8}, {8, -8}, {-8, -8}
    }
    local heights = {}
    for _, offset in ipairs(offsets) do
        local origin = Vector3.new(FARM_LANDING_X + offset[1], FARM_SURFACE_RAY_TOP,
            FARM_LANDING_Z + offset[2])
        local result = Workspace:Raycast(origin,
            Vector3.new(0, -FARM_SURFACE_RAY_LENGTH, 0), params)
        if result and result.Normal.Y >= 0.82 then
            local hit = result.Instance
            local acceptable = hit == Workspace.Terrain
            if hit:IsA("BasePart") then
                acceptable = hit.CanCollide and hit.CanQuery
                    and hit.CFrame.UpVector.Y >= 0.82
                    and hit.Size.X >= 12 and hit.Size.Z >= 12
            end
            if acceptable then table.insert(heights, result.Position.Y) end
        end
    end
    if #heights == 0 then return nil end
    table.sort(heights)
    local middle = math.floor((#heights + 1) / 2)
    if #heights % 2 == 0 then
        return (heights[middle] + heights[middle + 1]) / 2
    end
    return heights[middle]
end
local function positionFarmFloorForMap(mapKey, floor)
    if farmSurfaceMapKey ~= mapKey then
        farmSurfaceMapKey = mapKey
        farmSurfaceTopY = nil
        lastFarmSurfaceScan = 0
    end
    if farmSurfaceTopY ~= nil then return true end
    local now = os.clock()
    if now - lastFarmSurfaceScan < FARM_SURFACE_SCAN_INTERVAL then return false end
    lastFarmSurfaceScan = now
    local mapTopY = detectMapSurfaceTopY()
    if mapTopY == nil then return false end
    farmSurfaceTopY = mapTopY + 0.05
    floor = floor or ensureFarmFloor()
    floor.CFrame = CFrame.new(0, farmSurfaceTopY - FARM_FLOOR_HALF_HEIGHT, 0)
    floor.Anchored = true
    print("[dEnzCreator] Raycast floor matched map surface:", mapKey,
        "topY:", math.floor(farmSurfaceTopY * 100 + 0.5) / 100)
    return true
end
local function removeFarmFloor()
    if farmFloor then
        pcall(function() farmFloor:Destroy() end)
        farmFloor = nil
    end
    farmSurfaceMapKey = ""
    farmSurfaceTopY = nil
    lastFarmSurfaceScan = 0
    local existing = Workspace:FindFirstChild(FARM_FLOOR_NAME)
    if existing then pcall(function() existing:Destroy() end) end
end
local function farmAnchor()
    local char, hum, root = getParts()
    if not char then return false end
    local mapName, key = getMapName()
    local z = FARM_LANDING_Z
    local mapChanged = mapName ~= lastMap
    if mapChanged then
        lastMap = mapName
        pendingLandingMap = mapName
        landingConfirmedAt = nil
        noFoodMapKey = key
        noFoodChunksRoot = nil
        chunksReadySince = nil
        noFoodSince = nil
        noFoodSkipSentForMap = false
        lastFoodScanAt = 0
        lastLandingAttempt = 0
        print("[dEnzCreator] Map transition detected; keeping map Hidden and preparing farm:", mapName)
    end
    local floor = ensureFarmFloor()
    local newSurfaceReady = positionFarmFloorForMap(key, floor)
    if not newSurfaceReady then
        local safeTop = floor.Position.Y + floor.Size.Y / 2
        local safeRootY = safeTop + hum.HipHeight + root.Size.Y / 2 + 0.08
        local p = root.Position
        local horizontalDrift = (Vector3.new(p.X, 0, p.Z)
            - Vector3.new(FARM_LANDING_X, 0, z)).Magnitude
        if horizontalDrift > 2.0 or p.Y < safeRootY - 3.0 or p.Y > safeRootY + 8.0 then
            root.CFrame = CFrame.new(FARM_LANDING_X, safeRootY, z)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            lastLandingAttempt = os.clock()
        end
        return false
    end
    local floorTop = floor.Position.Y + floor.Size.Y / 2
    local targetY = floorTop + hum.HipHeight + root.Size.Y / 2 + 0.08
    local targetCFrame = CFrame.new(FARM_LANDING_X, targetY, z)
    local position = root.Position
    local horizontalDrift = (Vector3.new(position.X, 0, position.Z)
        - Vector3.new(FARM_LANDING_X, 0, z)).Magnitude
    local verticalDrift = math.abs(position.Y - targetY)
    if mapChanged or horizontalDrift > 2.0 or verticalDrift > 0.35 then
        root.CFrame = targetCFrame
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        pcall(function()
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
        lastLandingAttempt = os.clock()
    else
        local velocity = root.AssemblyLinearVelocity
        if math.abs(velocity.Y) > 0.5 then
            root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
        end
        if root.AssemblyAngularVelocity.Magnitude > 0.5 then
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end
    return true
end
local function fire(obj)
    if not obj then return end
    pcall(function()
        if obj:IsA("RemoteEvent") then obj:FireServer()
        elseif obj:IsA("BindableEvent") then obj:Fire() end
    end)
end
local function requestSkip(forceNoEatSkip)
    if (not forceNoEatSkip and not CFG.AutoSkipAfterSell) or not CFG.UseMappedSkipRemote then
        return false
    end
    local folder = ReplicatedStorage:FindFirstChild("Events")
    local remote = folder and folder:FindFirstChild("SetServerSettings")
    if not remote or not remote:IsA("RemoteEvent") then
        warn("[dEnzCreator V3.3.6] SetServerSettings RemoteEvent not found.")
        return false
    end
    local ok, err = pcall(function()
        local args = {{MapTime = -1, Paused = false}}
        remote:FireServer(unpack(args))
    end)
    if ok then
        print("[dEnzCreator V3.3.6] AutoSkip request sent (timer not paused).")
        return true
    end
    warn("[dEnzCreator V3.3.6] AutoSkip error:", err)
    return false
end
local function monitorGrabEatAvailability()
    local char = player.Character
    if not char then return end
    local mapName, key = getMapName()
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
        warn("[dEnzCreator V3.3.6] Grab/Eat missing on", mapName,
            "- requesting automatic map skip.")
        missingActionSkipSent = true
        requestSkip()
    end
end
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
        warn("[dEnzCreator V3.3.6] Character.Events.Sell not found.")
        return false
    end
    if not sell:IsA("RemoteEvent") then
        warn("[dEnzCreator V3.3.6] Sell exists but is not a RemoteEvent:", sell.ClassName)
        return false
    end
    local ok, err = pcall(function()
        sell:FireServer()
    end)
    if not ok then
        warn("[dEnzCreator V3.3.6] AutoSell error:", err)
        return false
    end
    print("[dEnzCreator V3.3.6] AutoSell request sent; waiting for sale confirmation.")
    return true
end
local NO_FOOD_CONFIRM_SECONDS = 3.0
local NO_FOOD_SCAN_INTERVAL = 0.35
local function getActiveChunksRoot()
    local live = Workspace:FindFirstChild("Chunks")
    if live then return live end
    if worldRootsDetached then
        local bucket = detachedWorldRoots.Chunks
        return bucket and bucket[#bucket] or nil
    end
    return nil
end
local lootCoinsCandyEnabled = false
local LOOT_SCAN_DELAY = 0.35
local LOOT_TOUCH_COOLDOWN = 0.8
local lastLootScanAt = 0
local lootTouchWarned = false
local lootTargets = {}
local lootLastTouch = setmetatable({}, {__mode = "k"})
local pendingCandyPickup = setmetatable({}, {__mode = "k"})
local lootAddedConnection
local lootRemovingConnection
local candyEarnedTotal = 0
local farmCycleTotal = 0
local farmCycleTotal = 0
local function isLootPart(obj)
    return obj and obj:IsA("BasePart") and (obj.Name == "Token" or obj.Name == "Candy")
end
local function registerLoot(obj)
    if isLootPart(obj) then lootTargets[obj] = true end
end
local function unregisterLoot(obj)
    if not lootTargets[obj] then return end
    lootTargets[obj] = nil
    lootLastTouch[obj] = nil
    if obj.Name == "Candy" and pendingCandyPickup[obj] then
        pendingCandyPickup[obj] = nil
        candyEarnedTotal = candyEarnedTotal + 1
    end
end
for _, obj in ipairs(Workspace:GetDescendants()) do registerLoot(obj) end
lootAddedConnection = Workspace.DescendantAdded:Connect(registerLoot)
lootRemovingConnection = Workspace.DescendantRemoving:Connect(unregisterLoot)
local function canCollectLoot(item)
    if not item or not item:IsA("BasePart") or not item.Parent then return false end
    if item.Name ~= "Token" and item.Name ~= "Candy" then return false end
    local owner = item:FindFirstChild("Owner")
    local timeLeft = item:FindFirstChild("TimeLeft")
    if owner and owner.Value ~= "" and owner.Value ~= player.Name then
        local remaining = timeLeft and tonumber(timeLeft.Value)
        if remaining and remaining > 0 then return false end
    end
    return true
end
local function lootCoinsCandyStep()
    if not lootCoinsCandyEnabled then return end
    local now = os.clock()
    if now - lastLootScanAt < LOOT_SCAN_DELAY then return end
    lastLootScanAt = now
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    if type(firetouchinterest) ~= "function" then
        if not lootTouchWarned then
            lootTouchWarned = true
            warn("[dEnzCreator] Loot Coin & Candy requires firetouchinterest support in the executor.")
        end
        return
    end
    for item in pairs(lootTargets) do
        if item.Parent and canCollectLoot(item) then
            local previous = lootLastTouch[item] or 0
            if now - previous >= LOOT_TOUCH_COOLDOWN then
                lootLastTouch[item] = now
                local touched = pcall(function()
                    firetouchinterest(root, item, 0)
                    firetouchinterest(root, item, 1)
                end)
                if touched and item.Name == "Candy" then
                    pendingCandyPickup[item] = true
                end
            end
        elseif not item.Parent then
            unregisterLoot(item)
        end
    end
end
local function findNearbyFood(root)
    local chunks = getActiveChunksRoot()
    if not chunks then
        return nil -- nil means map/chunks are not ready; do not start/count timer
    end
    local ok, descendants = pcall(function() return chunks:GetDescendants() end)
    if not ok then return nil end
    for _, obj in ipairs(descendants) do
        if obj:IsA("BasePart") and obj.Parent and obj:IsDescendantOf(chunks) then
            return true
        end
    end
    return false
end
local function monitorLandingEatProgress(hum, root)
    local chunks = getActiveChunksRoot()
    if not chunks then
        noFoodSince = nil
        noFoodChunksRoot = nil
        chunksReadySince = nil
        landingConfirmedAt = nil
        return false
    end
    local mapName, key = getMapName()
    local identity = key ~= "" and ("map:" .. key) or chunks
    local changed = false
    if typeof(identity) == "Instance" then
        changed = noFoodChunksRoot ~= identity
    else
        changed = noFoodMapKey ~= identity
    end
    if changed then
        noFoodMapKey = typeof(identity) == "string" and identity or ""
        noFoodChunksRoot = typeof(identity) == "Instance" and identity or chunks
        chunksReadySince = os.clock()
        noFoodSince = nil
        landingConfirmedAt = nil
        noFoodSkipSentForMap = false
        lastFoodScanAt = 0
        pendingLandingMap = mapName
        print("[dEnzCreator] AutoSkip: Chunks/map changed; waiting for stable map:", mapName)
        return false
    end
    if noFoodSkipSentForMap then
        return false
    end
    local now = os.clock()
    if not chunksReadySince then
        chunksReadySince = now
        return false
    end
    if now - chunksReadySince < 1.5 then
        return false
    end
    if now - lastFoodScanAt < NO_FOOD_SCAN_INTERVAL then
        return false
    end
    lastFoodScanAt = now
    local foodState = findNearbyFood(root)
    if foodState == nil then
        noFoodSince = nil
        return false
    elseif foodState then
        noFoodSince = nil
        pendingLandingMap = nil
        return false
    end
    if not noFoodSince then
        noFoodSince = now
        print("[dEnzCreator] AutoSkip: no food detected; starting 3-second timer:", mapName)
        return false
    end
    if now - noFoodSince >= NO_FOOD_CONFIRM_SECONDS then
        if requestSkip(true) then
            noFoodSkipSentForMap = true
            pendingLandingMap = nil
            warn("[dEnzCreator] AutoSkip: map empty for 3 seconds; skip request sent:", mapName)
        else
            noFoodSince = now
            warn("[dEnzCreator] AutoSkip: request failed; retrying after 3 seconds:", mapName)
        end
    end
    return false
end
local GRAB_ANIMATION_SPEED = 5.0
local EAT_ANIMATION_SPEED = 5.0
local function accelerateActionAnimations(hum)
    if not hum then return end
    local ok, tracks = pcall(function()
        return hum:GetPlayingAnimationTracks()
    end)
    if not ok or type(tracks) ~= "table" then return end
    for _, track in ipairs(tracks) do
        local trackName = string.lower(tostring(track.Name or ""))
        local speed = nil
        if trackName:find("grab", 1, true) then
            speed = GRAB_ANIMATION_SPEED
        elseif trackName:find("eat", 1, true) then
            speed = EAT_ANIMATION_SPEED
        end
        if speed then
            pcall(function()
                track:AdjustSpeed(speed)
            end)
        end
    end
end
local function farmStep()
    local char, hum, root, events = getParts()
    if not char then return end
    applyCharacterTransitionToCharacter(char, hum)
    local surfaceReady = farmAnchor()
    if surfaceReady and CFG.Farm then
        detachCurrentWorldRoots()
    end
    accelerateActionAnimations(hum)
    monitorLandingEatProgress(hum, root)
    if events then
        local now = os.clock()
        local grabEvent = events:FindFirstChild("Grab")
        local eatEvent = events:FindFirstChild("Eat")
        if grabEvent and eatEvent and now >= nextGrabEatActionAt then
            if grabEatPhase == "grab" then
                fire(grabEvent)
                grabEatPhase = "eat"
                nextGrabEatActionAt = now + POST_GRAB_DELAY
            else
                if cycleStartedAt == nil then
                    cycleStartedAt = now
                    completedCycleSeconds = 0
                    print("[dEnzCreator] Season Time started: first Eat action.")
                end
                fire(eatEvent)
                grabEatPhase = "grab"
                nextGrabEatActionAt = now + GRAB_DELAY
            end
        end
    end
    local size, maxSize, numericFull = getCapacityState(char)
    local previousBarProgress = lastBarProgress
    local barProgress = getSellBarProgress()
    lastBarProgress = barProgress
    local full
    local barFull = barProgress ~= nil and barProgress >= 0.985
    if size ~= nil and maxSize ~= nil and maxSize > 0 then
        full = numericFull or (barFull and size >= maxSize * 0.97)
    else
        full = barFull
    end
    if full then
        if not wasFull then
            wasFull = true
            skipSentForCycle = false
            lastSellAttempt = os.clock()
            sendAutoSell(events)
            skipSentForCycle = requestSkip()
            print("[dEnzCreator] FULL detected | Sell sent, then Skip sent with no added delay.")
        elseif os.clock() - lastSellAttempt >= 1.75 then
            lastSellAttempt = os.clock()
            sendAutoSell(events)
        end
    end
    local sizeDropAfterFull = size ~= nil and maxSize ~= nil and lastSize ~= nil
        and lastSize >= maxSize * 0.90 and size < lastSize * 0.50
    local sizeReset = size ~= nil and maxSize ~= nil and size <= maxSize * 0.05
        and lastSize ~= nil and lastSize > size
    local barDropAfterFull = barProgress ~= nil and previousBarProgress ~= nil
        and previousBarProgress >= 0.985 and barProgress < 0.90
    local saleConfirmed = sizeDropAfterFull or sizeReset or barDropAfterFull
    if saleConfirmed then
        if cycleStartedAt ~= nil or wasFull then
            farmCycleTotal = farmCycleTotal + 1
            print("[dEnzCreator] Farm Cycle completed:", farmCycleTotal)
        end
        if cycleStartedAt ~= nil then
            completedCycleSeconds = math.max(0, os.clock() - cycleStartedAt)
            cycleStartedAt = nil
            print("[dEnzCreator] Season Time stopped and saved: sale/reset confirmed (AutoSell or manual Sell).")
        end
        if wasFull then
            print("[dEnzCreator V3.3.6] Sale/reset detected; requesting AutoSkip.")
            if not skipSentForCycle then
                skipSentForCycle = requestSkip()
            end
        end
        wasFull = false
        lastSellAttempt = 0
        print("[dEnzCreator] Sale/reset detected; next Season Time will start on the next Eat action.")
    end
    if size ~= nil then
        lastSize = size
    end
end
local hiddenMapRoot = nil
local hiddenMapAddedConnection = nil
local hiddenMapGeneration = 0
local hiddenChunksRoot = nil
local hiddenChunksAddedConnection = nil
local hiddenChunksGeneration = 0
local HIDDEN_MAP_BATCH_SIZE = 160
local HIDDEN_CHUNKS_BATCH_SIZE = 160
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
    if not hiddenMapsEnabled or not obj or obj == mapRoot then return end
    if isProtectedMapObject(obj, mapRoot) then return end
    pcall(function()
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
        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
            if hiddenMapOriginals[obj] == nil then
                hiddenMapOriginals[obj] = {kind = "effect", value = obj.Enabled}
            end
            obj.Enabled = false
        end
    end)
end
local function hideFoodVisual(obj)
    if not hiddenMapsEnabled or not obj then return end
    pcall(function()
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
        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
            if hiddenMapOriginals[obj] == nil then
                hiddenMapOriginals[obj] = {kind = "effect", value = obj.Enabled}
            end
            obj.Enabled = false
        end
    end)
end
local function scanTreeInBatches(root, isCurrent, hideCallback, batchSize)
    task.spawn(function()
        local stack = {}
        local ok, children = pcall(function() return root:GetChildren() end)
        if ok and children then
            for i = #children, 1, -1 do
                stack[#stack + 1] = children[i]
            end
        end
        local processed = 0
        while #stack > 0 do
            if not isCurrent() then break end
            local obj = stack[#stack]
            stack[#stack] = nil
            if obj and obj.Parent then
                hideCallback(obj)
                local childrenOk, descendants = pcall(function() return obj:GetChildren() end)
                if childrenOk and descendants then
                    for i = #descendants, 1, -1 do
                        stack[#stack + 1] = descendants[i]
                    end
                end
            end
            processed = processed + 1
            if processed >= batchSize then
                processed = 0
                RunService.Heartbeat:Wait()
            end
        end
    end)
end
local function bindHiddenChunks(chunksArg)
    local chunks = chunksArg or Workspace:FindFirstChild("Chunks")
    if not chunks then return false end
    if hiddenChunksRoot == chunks then return true end
    if hiddenChunksAddedConnection then
        pcall(function() hiddenChunksAddedConnection:Disconnect() end)
        hiddenChunksAddedConnection = nil
    end
    hiddenChunksRoot = chunks
    hiddenChunksGeneration = hiddenChunksGeneration + 1
    local generation = hiddenChunksGeneration
    hiddenChunksAddedConnection = chunks.DescendantAdded:Connect(function(obj)
        if hiddenMapsEnabled and hiddenChunksRoot == chunks
            and hiddenChunksGeneration == generation then
            hideFoodVisual(obj)
        end
    end)
    scanTreeInBatches(chunks,
        function()
            return hiddenMapsEnabled and hiddenChunksRoot == chunks
                and hiddenChunksGeneration == generation
        end,
        function(obj)
            hideFoodVisual(obj)
        end,
        HIDDEN_CHUNKS_BATCH_SIZE
    )
    return true
end
local function disconnectHiddenMapRoot()
    if hiddenMapAddedConnection then
        pcall(function() hiddenMapAddedConnection:Disconnect() end)
        hiddenMapAddedConnection = nil
    end
    hiddenMapGeneration = hiddenMapGeneration + 1
    hiddenMapRoot = nil
end
local function disconnectHiddenChunksRoot()
    if hiddenChunksAddedConnection then
        pcall(function() hiddenChunksAddedConnection:Disconnect() end)
        hiddenChunksAddedConnection = nil
    end
    hiddenChunksGeneration = hiddenChunksGeneration + 1
    hiddenChunksRoot = nil
end
local function restoreHiddenMap()
    hiddenMapsEnabled = false
    disconnectHiddenMapRoot()
    disconnectHiddenChunksRoot()
    for obj, saved in pairs(hiddenMapOriginals) do
        if obj then
            pcall(function()
                if saved.kind == "part" then
                    obj.LocalTransparencyModifier = saved.value
                elseif saved.kind == "floor" then
                    obj.LocalTransparencyModifier = saved.transparency
                    obj.Color = saved.color
                    obj.Material = saved.material
                elseif saved.kind == "texture" then
                    obj.Transparency = saved.value
                elseif saved.kind == "effect" then
                    obj.Enabled = saved.value
                end
            end)
        end
    end
    table.clear(hiddenMapOriginals)
end
local function bindHiddenMapRoot(mapRoot)
    if not hiddenMapsEnabled or not mapRoot then return false end
    if hiddenMapRoot == mapRoot then return true end
    disconnectHiddenMapRoot()
    hiddenMapRoot = mapRoot
    hiddenMapGeneration = hiddenMapGeneration + 1
    local generation = hiddenMapGeneration
    hiddenMapAddedConnection = mapRoot.DescendantAdded:Connect(function(obj)
        if hiddenMapsEnabled and hiddenMapRoot == mapRoot
            and hiddenMapGeneration == generation then
            hideMapObject(obj, mapRoot)
        end
    end)
    scanTreeInBatches(mapRoot,
        function()
            return hiddenMapsEnabled and hiddenMapRoot == mapRoot
                and hiddenMapGeneration == generation
        end,
        function(obj)
            hideMapObject(obj, mapRoot)
        end,
        HIDDEN_MAP_BATCH_SIZE
    )
    return true
end
local function applyHiddenMap()
    if not hiddenMapsEnabled then return false end
    local mapRoot = Workspace:FindFirstChild("Map")
    if not mapRoot then return false end
    return bindHiddenMapRoot(mapRoot)
end
local function setHiddenMaps(enabled)
    if enabled then
        hiddenMapsEnabled = true
        applyHiddenMap()
        bindHiddenChunks()
        print("[dEnzCreator STAGE 7] Hidden Maps ON. New map objects are hidden immediately; existing objects are processed in background batches.")
    else
        restoreHiddenMap()
        print("[dEnzCreator STAGE 7] Hidden Maps OFF. Original map/chunk visuals restored.")
    end
end
local gui = Instance.new("ScreenGui")
gui.Name = "dEnzCreator_ETW"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(170, 0)
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
header.Size = UDim2.new(1, 0, 0, 82)
header.BackgroundColor3 = Color3.fromRGB(37, 39, 62)
header.BackgroundTransparency = 0
header.BorderSizePixel = 0
header.Parent = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 7)
local headerStroke = Instance.new("UIStroke", header)
headerStroke.Color = Color3.fromRGB(125, 105, 195)
headerStroke.Thickness = 1
local title = Instance.new("TextLabel")
title.Size = UDim2.fromOffset(64, 23)
title.Position = UDim2.fromOffset(6, 1)
title.BackgroundTransparency = 1
title.Text = "dEnzCreator"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 11
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header
local onlineStatus = Instance.new("TextLabel")
onlineStatus.Name = "OnlineStatus"
onlineStatus.Size = UDim2.fromOffset(42, 20)
onlineStatus.Position = UDim2.fromOffset(72, 2)
onlineStatus.BackgroundTransparency = 1
onlineStatus.Text = "● ONLINE"
onlineStatus.TextColor3 = Color3.fromRGB(80, 220, 145)
onlineStatus.TextSize = 7
onlineStatus.Font = Enum.Font.GothamBold
onlineStatus.TextXAlignment = Enum.TextXAlignment.Left
onlineStatus.Parent = header
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
runtimeBlock.Size = UDim2.new(1, -12, 0, 66)
runtimeBlock.Position = UDim2.fromOffset(6, 25)
runtimeBlock.BackgroundTransparency = 1
runtimeBlock.BorderSizePixel = 0
runtimeBlock.RichText = true
runtimeBlock.Text = '<font size="9">Runtime: 0m 0s</font>\n<font size="9">Season Time: 0m 0s</font>\n<font size="9">Farm Cycle: 0</font>\n<font size="9">Data Candy: 0</font>'
runtimeBlock.TextColor3 = Color3.fromRGB(240, 243, 248)
runtimeBlock.TextSize = 9
runtimeBlock.Font = Enum.Font.GothamMedium
runtimeBlock.TextXAlignment = Enum.TextXAlignment.Left
runtimeBlock.TextYAlignment = Enum.TextYAlignment.Center
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
makeToggle("AutoFarm", 2, Color3.fromRGB(35, 150, 112), CFG.Farm, function(on)
    CFG.Farm = on
    if on then
        ensureFarmFloor()
        setHiddenMaps(true)
        setCharacterTransition(true)
        pendingLandingMap = getMapName()
        landingConfirmedAt = nil
        noFoodMapKey = select(2, getMapName())
        noFoodSkipSentForMap = false
        lastFoodScanAt = 0
        lastLandingAttempt = 0
        pcall(farmStep)
    else
        setCharacterTransition(false)
        restoreWorldRoots()
        setHiddenMaps(false)
        removeFarmFloor()
        pendingLandingMap = nil
        landingConfirmedAt = nil
    end
    print("[dEnzCreator V3.3.6] AutoFarm", on and "ON" or "OFF")
end)
makeToggle("Loot Coin & Candy", 4, Color3.fromRGB(205, 145, 55), false, function(on)
    lootCoinsCandyEnabled = on
    lastLootScanAt = 0
    print("[dEnzCreator] Loot Coin & Candy", on and "ON" or "OFF")
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
    local spinEvent = events:FindFirstChild("SpinEvent")
    if spinEvent and os.clock() - lastSpinRequest >= 10 then
        lastSpinRequest = os.clock()
        pcall(function() spinEvent:FireServer() end)
    end
end
makeToggle("Auto Claim Rewards", 5, Color3.fromRGB(133, 89, 195), false, function(on)
    autoClaimEnabled = on
end)
local minimized = false
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
    lootCoinsCandyEnabled = false
    restoreWorldRoots()
    setHiddenMaps(false)
    removeFarmFloor()
    setCharacterTransition(false)
    gui:Destroy()
end)
local scriptStartedAt = os.clock()
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
local function formatThousands(value)
    local number = math.max(0, math.floor(tonumber(value) or 0))
    local digits = tostring(number)
    local reversed = digits:reverse():gsub("(%d%d%d)", "%1.")
    local formatted = reversed:reverse():gsub("^%.", "")
    return formatted
end
local function updateRuntimeMonitor()
    local now = os.clock()
    local online = player.Parent == Players
    onlineStatus.Text = online and "● ONLINE" or "● OFFLINE"
    onlineStatus.TextColor3 = online and Color3.fromRGB(80, 220, 145) or Color3.fromRGB(235, 90, 90)
    local candyText = formatThousands(candyEarnedTotal)
    runtimeBlock.Text = string.format(
        '<font size="9">Runtime: %s</font>\n<font size="9">Season Time: %s</font>\n<font size="9">Farm Cycle: %s</font>\n<font size="9">Data Candy: %s</font>',
        formatDuration(now - scriptStartedAt),
        formatDuration(cycleStartedAt and (now - cycleStartedAt) or completedCycleSeconds),
        formatThousands(farmCycleTotal), candyText
    )
end
characterTransitionConnection = player.CharacterAdded:Connect(function(char)
    if not characterTransitionEnabled then return end
    task.defer(function()
        if characterTransitionEnabled and player.Character == char then
            local hum = char:WaitForChild("Humanoid", 5)
            applyCharacterTransitionToCharacter(char, hum)
        end
    end)
end)
workspaceMapConnection = Workspace.ChildAdded:Connect(function(child)
    if child.Name ~= "Map" and child.Name ~= "Chunks" then return end
    if hiddenMapsEnabled then
        if child.Name == "Map" then
            bindHiddenMapRoot(child)
        else
            bindHiddenChunks(child)
        end
    end
    if CFG.Farm and worldRootsDetached then
        if child.Name == "Chunks" then
            detachWorldRoot(child)
        end
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
local inputChangedConnection = UserInputService.InputChanged:Connect(function(input)
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
    pcall(lootCoinsCandyStep)
    if CFG.Farm then
        pcall(monitorGrabEatAvailability)
        pcall(farmStep)
    end
end)
gui.AncestryChanged:Connect(function(_, parent)
    if parent == nil then
        running, CFG.Farm = false, false
        autoClaimEnabled = false
        lootCoinsCandyEnabled = false
        if lootAddedConnection then lootAddedConnection:Disconnect(); lootAddedConnection = nil end
        if lootRemovingConnection then lootRemovingConnection:Disconnect(); lootRemovingConnection = nil end
        if timedRewardsCounterConnection then timedRewardsCounterConnection:Disconnect(); timedRewardsCounterConnection = nil end
        if playerChildAddedConnection then playerChildAddedConnection:Disconnect(); playerChildAddedConnection = nil end
        setCharacterTransition(false)
        restoreWorldRoots()
        setHiddenMaps(false)
        removeFarmFloor()
        if workspaceMapConnection then workspaceMapConnection:Disconnect() end
        if characterTransitionConnection then characterTransitionConnection:Disconnect() end
        if inputChangedConnection then inputChangedConnection:Disconnect() end
        connection:Disconnect()
    end
end)
print("[dEnzCreator STAGE 8 RAYCAST FLOOR] LocalChunkManager/Animate transition handling; Raycast detects map surface before Map/Chunks detach; roots restored when AutoFarm turns OFF; Grab/Eat animation 5x; Grab/post-Grab delays 0.02s/12.")
print("[dEnzCreator V3.3.6] Bar/capacity detection loaded. Eat/Grab stay active; AutoSell + AutoSkip enabled.")
