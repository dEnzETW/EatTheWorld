-- dEnzCreator ETW AUTOFARM - STAGE 8 KEDADA-STYLE TRANSITION + FLOOR LOCK FIX 2
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
    DefaultZ = 100,
    MegaMapZ = 100,
    CentralRobloxiaZ = 100,
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
local lastNoFoodSkipAttemptAt = 0
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
local landingSizeBaseline = nil
local landingBarBaseline = nil
local lastMissingActionMap = ""
local hiddenMapsEnabled = false
local hiddenMapOriginals = {}
local hiddenMapConnections = {}
local workspaceMapConnection = nil

-- STAGE 8 KEDADA-STYLE TRANSITION.
-- AutoFarm locally detaches Map/Chunks and uses a fixed bedrock floor.
-- Also disable LocalChunkManager and Animate while farming, and keep the
-- Humanoid in Physics state.
local kedadaTransitionEnabled = false
local kedadaBoundCharacter = nil
local kedadaDisabledScripts = {}
local kedadaCharacterConnection = nil

local function setKedadaScriptDisabled(scriptObject, disabled)
    if not scriptObject or not scriptObject:IsA("LocalScript") then return end
    if kedadaDisabledScripts[scriptObject] == nil then
        kedadaDisabledScripts[scriptObject] = scriptObject.Disabled
    end
    pcall(function()
        scriptObject.Disabled = disabled
    end)
end

local function applyKedadaTransitionToCharacter(char, hum)
    if not kedadaTransitionEnabled or not char then return end
    if kedadaBoundCharacter ~= char then
        kedadaBoundCharacter = char
    end

    setKedadaScriptDisabled(char:FindFirstChild("LocalChunkManager"), true)
    setKedadaScriptDisabled(char:FindFirstChild("Animate"), true)

    -- Physics state is intentionally NOT forced here.
    -- farmAnchor() uses GettingUp after seating the character on FarmFloor;
    -- forcing Physics every Heartbeat would immediately fight that recovery.
end

local function restoreKedadaTransition()
    kedadaTransitionEnabled = false
    kedadaBoundCharacter = nil
    for scriptObject, wasDisabled in pairs(kedadaDisabledScripts) do
        if scriptObject then
            pcall(function()
                scriptObject.Disabled = wasDisabled
            end)
        end
    end
    table.clear(kedadaDisabledScripts)
end

local function setKedadaTransition(enabled)
    kedadaTransitionEnabled = enabled and true or false
    if not kedadaTransitionEnabled then
        restoreKedadaTransition()
        return
    end
    local char, hum = player.Character, nil
    if char then hum = char:FindFirstChildOfClass("Humanoid") end
    applyKedadaTransitionToCharacter(char, hum)
end

local function norm(v)
    return string.lower(tostring(v or "")):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

-- KEDADA-style local detachment: keep references so roots can be restored
-- when AutoFarm is disabled. A list is used because a new map/chunk root can
-- arrive during a transition while an older root is already detached.
local worldRootsDetached = false
local detachedWorldRoots = {Map = {}, Chunks = {}}
local latestDetachedMapRoot = nil

local function detachWorldRoot(root)
    if not root or (root.Name ~= "Map" and root.Name ~= "Chunks") then return end
    local bucket = detachedWorldRoots[root.Name]
    for _, saved in ipairs(bucket) do
        if saved == root then return end
    end
    -- Keep only the newest root of each type for restoration. Older map
    -- instances stay detached instead of being reinserted as duplicate maps.
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


-- Anchored 2048x10 farm floor. Raycast moves it to the detected map surface.
-- Map/Chunks are detached only after the current map surface has been detected.
local FARM_FLOOR_NAME = "dEnzCreator_FarmFloor"
local FARM_FLOOR_SIZE = Vector3.new(2048, 10, 2048)
local FARM_FLOOR_HALF_HEIGHT = FARM_FLOOR_SIZE.Y / 2
local FARM_LANDING_X = 0
local FARM_LANDING_Z = 100
local FARM_FIXED_SURFACE_TOP_Y = 0
local FARM_SURFACE_SCAN_INTERVAL = 0.20
local FARM_SURFACE_RAY_TOP = 10000
local FARM_SURFACE_RAY_LENGTH = 20000
local farmFloor = nil
local farmSurfaceMapKey = ""
local farmSurfaceTopY = nil
local lastFarmSurfaceScan = 0

-- Stage 5 monitor: lightweight client-side timing and transition observations.
local monitorEvents = {}
local monitorEnabled = true
local monitorLastMapName = ""
local monitorLastMapChildren = nil
local monitorLastChunksChildren = nil
local monitorLastGrabAt = nil
local monitorLastEatAt = nil
local monitorLastActionLabel = "waiting"
local monitorLastMaxAt = nil
local monitorLastSellAt = nil
local monitorLastResetAt = nil
local monitorLastLandingAt = nil
local monitorLastSurfaceScanMs = nil
local monitorLastSurfaceScanAt = 0
local monitorLastRefresh = 0
local transitionStartedAt = nil
local transitionMapKey = ""
local transitionSurfaceReadyAt = nil
local transitionFirstActionAt = nil

local function monitorLog(label, detail)
    local stamp = os.date("%H:%M:%S")
    local line = string.format("[%s] %s%s", stamp, tostring(label),
        detail and (" | " .. tostring(detail)) or "")
    table.insert(monitorEvents, 1, line)
    while #monitorEvents > 12 do table.remove(monitorEvents) end
end

-- Re-normalize even an already-existing FarmFloor. Older instances may have
-- been left with a stale size, CFrame, or collision flags by a prior run.
local function lockFarmFloor(floor)
    if not floor or not floor:IsA("BasePart") then return nil end

    -- Keep the floor anchored, but DO NOT force it back to Y=0 here.
    -- Raycast positions this same floor at the detected map surface. Resetting
    -- its CFrame on every farmStep fights that placement and can trap/drop the
    -- character between the farm floor and the actual map surface.
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

-- Raycast surface detection: scan the real map before locally detaching Map/Chunks.
-- LocalTransparencyModifier does not disable CanQuery, so hidden map geometry remains raycastable.
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
    local scanStarted = os.clock()
    local mapTopY = detectMapSurfaceTopY()
    monitorLastSurfaceScanMs = (os.clock() - scanStarted) * 1000
    monitorLastSurfaceScanAt = os.clock()
    if mapTopY == nil then
        monitorLog("SURFACE", "not ready; scan " .. string.format("%.1fms", monitorLastSurfaceScanMs))
        return false
    end

    farmSurfaceTopY = mapTopY + 0.05
    floor = floor or ensureFarmFloor()
    floor.CFrame = CFrame.new(0, farmSurfaceTopY - FARM_FLOOR_HALF_HEIGHT, 0)
    floor.Anchored = true
    transitionSurfaceReadyAt = os.clock()
    local elapsed = transitionStartedAt and (transitionSurfaceReadyAt - transitionStartedAt) or nil
    monitorLog("SURFACE ready", string.format("Y %.2f | scan %.1fms | transition %s",
        farmSurfaceTopY, monitorLastSurfaceScanMs,
        elapsed and string.format("%.2fs", elapsed) or "n/a"))
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
    -- Unified horizontal landing point; the floor height is detected per map.
    local z = FARM_LANDING_Z
    local mapChanged = mapName ~= lastMap

    -- On every map change, immediately re-seat the character on the persistent
    -- farm floor. Keep the transition state until the next map's food is seen.
    if mapChanged then
        lastMap = mapName
        pendingLandingMap = mapName
        landingConfirmedAt = nil
        lastNoFoodSkipAttemptAt = 0
        noFoodMapKey = key
        lastNearbyFoodAt = nil
        noFoodSkipSentForMap = false
        lastFoodScanAt = 0
        cachedFoodNearby = false
        landingSizeBaseline = nil
        landingBarBaseline = nil
        lastLandingAttempt = 0
        monitorLog("MAP transition", mapName)
        transitionStartedAt = os.clock()
        transitionMapKey = key
        transitionSurfaceReadyAt = nil
        transitionFirstActionAt = nil
        print("[dEnzCreator] Map transition detected; keeping map Hidden and preparing farm:", mapName)
    end

    local floor = ensureFarmFloor()
    -- The fixed Y=0 FarmFloor remains available while Map/Chunks are detached.
    -- On map changes, the same floor is reaffirmed without waiting for map geometry.
    local newSurfaceReady = positionFarmFloorForMap(key, floor)
    if not newSurfaceReady then
        -- Hold the previous safe position while the new map streams in.
        -- Do not detach Map/Chunks until Raycast has found a valid surface.
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

    -- Do not let map-transition impulses launch the character above the floor.
    -- Correct only meaningful drift, avoiding needless CFrame writes each frame.
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
        -- Kill upward/downward momentum while leaving the character seated.
        local velocity = root.AssemblyLinearVelocity
        if math.abs(velocity.Y) > 0.5 then
            root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
        end
        if root.AssemblyAngularVelocity.Magnitude > 0.5 then
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end

    -- Keep pendingLandingMap until food is detected by farmStep; this is a
    -- transition marker, not a wait gate for Grab/Eat.
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
    -- No-food landing skip is independent from the AutoSkip-after-Sell toggle.
    if (not forceNoEatSkip and not CFG.AutoSkipAfterSell) or not CFG.UseMappedSkipRemote then
        return false
    end

    local folder = ReplicatedStorage:FindFirstChild("Events")
    local remote = folder and folder:FindFirstChild("SetServerSettings")
    if not remote or not remote:IsA("RemoteEvent") then
        warn("[dEnzCreator V3.3.6] SetServerSettings RemoteEvent not found.")
        return false
    end

    -- Keep the mapped skip command, but do not pause the map timer.
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
        warn("[dEnzCreator V3.3.6] Grab/Eat missing on", mapName,
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
            print("[dEnzCreator V3.3.6] RequestTeleport:", mode, mapName)
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

    print("[dEnzCreator V3.3.6] AutoSell request sent.")
    return true
end

-- KEDADA-style no-object detector.
-- Start the 3-second window only after the new map key is active AND the
-- character has confirmed contact with the farm floor. Map/Chunks are detached
-- locally, so scan the retained detached Chunks root instead of Workspace.
local NO_FOOD_RADIUS = 100
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

local function findNearbyFood(char, root)
    local chunks = getActiveChunksRoot()
    if not chunks then
        return nil -- nil means map/chunks are not ready; do not start/count timer
    end

    local radiusSquared = NO_FOOD_RADIUS * NO_FOOD_RADIUS
    local ok, descendants = pcall(function() return chunks:GetDescendants() end)
    if not ok then return nil end

    for _, obj in ipairs(descendants) do
        if obj:IsA("BasePart") and obj.Parent and obj:IsDescendantOf(chunks) then
            local delta = obj.Position - root.Position
            if delta:Dot(delta) <= radiusSquared then
                return true
            end
        end
    end
    return false
end

local function monitorLandingEatProgress(char, hum, root)
    if not pendingLandingMap or noFoodSkipSentForMap then
        return false
    end

    local mapName, key = getMapName()
    if key == "" then return false end
    if key ~= noFoodMapKey then
        noFoodMapKey = key
        pendingLandingMap = mapName
        landingConfirmedAt = nil
        lastNoFoodSkipAttemptAt = 0
        noFoodSkipSentForMap = false
        lastFoodScanAt = 0
        cachedFoodNearby = false
    end

    local now = os.clock()
    local chunks = getActiveChunksRoot()
    if not chunks then
        -- A missing Chunks root is still part of map loading, not proof of an
        -- empty map. Keep waiting until the new map's chunk container exists.
        landingConfirmedAt = nil
        return false
    end

    if not farmSurfaceTopY then return false end
    if not landingConfirmedAt then
        local floor = ensureFarmFloor()
        local floorTop = floor.Position.Y + floor.Size.Y / 2
        local expectedRootY = floorTop + hum.HipHeight + root.Size.Y / 2 + 0.08
        local onFloor = hum.FloorMaterial ~= Enum.Material.Air
            and math.abs(root.Position.Y - expectedRootY) <= 1.0
        if not onFloor or now - lastLandingAttempt < 0.15 then
            return false
        end

        landingConfirmedAt = now
        lastFoodScanAt = 0
        monitorLastLandingAt = now
        monitorLog("LANDING confirmed", string.format("Y %.1f", root.Position.Y))
        print("[dEnzCreator] Map ready + landing confirmed; starting 3-second nearby-object scan:", mapName)
        return false
    end

    if now - lastFoodScanAt < NO_FOOD_SCAN_INTERVAL then
        return false
    end
    lastFoodScanAt = now

    local foodState = findNearbyFood(char, root)
    if foodState == nil then
        -- Chunk root became unavailable during streaming; pause the window.
        landingConfirmedAt = nil
        return false
    elseif foodState then
        cachedFoodNearby = true
        lastNearbyFoodAt = now
        noFoodSkipSentForMap = true
        pendingLandingMap = nil
        print("[dEnzCreator] Nearby object detected; no-food AutoSkip cancelled for this map:", mapName)
        return true
    end

    cachedFoodNearby = false
    if now - landingConfirmedAt >= NO_FOOD_CONFIRM_SECONDS then
        noFoodSkipSentForMap = true -- one request per map; never spam during transition
        pendingLandingMap = nil
        warn("[dEnzCreator] No nearby object within 3 seconds after map became ready; requesting AutoSkip:", mapName)
        if requestSkip(true) then
            monitorLog("NO-FOOD SKIP", mapName .. " | 3.0s no nearby object")
        else
            warn("[dEnzCreator] No-food AutoSkip request could not be sent for:", mapName)
        end
    end

    return false
end

-- Separate animation speeds: Grab is accelerated to 10x until the
-- pre-Eat standing phase; Eat animation remains at 5x. Other tracks untouched.
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

    -- KEDADA transition controls are re-applied to a replacement character
    -- without waiting for the next map scan.
    applyKedadaTransitionToCharacter(char, hum)

    -- Exactly one floor-lock pass per farmStep cycle; it runs before Grab/Eat.
    local surfaceReady = farmAnchor()
    -- Re-check roots after EVERY successful surface scan, not only the first.
    -- During a map transition, the replacement Map must remain in Workspace
    -- long enough for Raycast; once detected, detach that Map and its Chunks.
    if surfaceReady and CFG.Farm then
        detachCurrentWorldRoots()
    end
    accelerateActionAnimations(hum)

    monitorLandingEatProgress(char, hum, root)

    -- X12 delay tuning: Grab and the post-Grab Eat phase each use 1/12
    -- of the former 0.02s interval. Heartbeat frame rate is the practical
    -- lower bound; this does not spawn a high-frequency remote spam loop.
    if events then
        local now = os.clock()
        local grabEvent = events:FindFirstChild("Grab")
        local eatEvent = events:FindFirstChild("Eat")

        -- Start Season Time only once both controls are present and the first
        -- Grab/Eat sequence is about to be sent.
        if grabEvent and eatEvent and cycleStartedAt == nil then
            cycleStartedAt = now
            completedCycleSeconds = 0
            print("[dEnzCreator V3.3.6] Season time started: Grab/Eat menu active.")
        end

        if grabEvent and eatEvent and now >= nextGrabEatActionAt then
            if grabEatPhase == "grab" then
                fire(grabEvent)
                monitorLastGrabAt = now
                if transitionStartedAt and not transitionFirstActionAt then
                    transitionFirstActionAt = now
                    monitorLog("TRANSITION first action", string.format("Grab %.2fs after map change",
                        now - transitionStartedAt))
                end
                monitorLastActionLabel = "GRAB sent"
                if monitorLastEatAt then
                    monitorLog("GRAB", string.format("since EAT %.0fms",
                        (now - monitorLastEatAt) * 1000))
                else
                    monitorLog("GRAB", "first observed")
                end
                grabEatPhase = "eat"
                nextGrabEatActionAt = now + POST_GRAB_DELAY
            else
                fire(eatEvent)
                fire(eatEvent)
                fire(eatEvent)
                monitorLastEatAt = now
                if transitionStartedAt and not transitionFirstActionAt then
                    transitionFirstActionAt = now
                    monitorLog("TRANSITION first action", string.format("Eat %.2fs after map change",
                        now - transitionStartedAt))
                end
                monitorLastActionLabel = "EAT sent"
                if monitorLastGrabAt then
                    monitorLog("EAT", string.format("since GRAB %.0fms",
                        (now - monitorLastGrabAt) * 1000))
                else
                    monitorLog("EAT", "first observed")
                end
                grabEatPhase = "grab"
                nextGrabEatActionAt = now + GRAB_DELAY
            end
            lastFoodAction = now
        end
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
            print("[dEnzCreator V3.3.6] Season time stopped: sell bar detected full.")
        end
        if not wasFull then
            wasFull = true
            monitorLastMaxAt = os.clock()
            monitorLog("MAX detected", size and string.format("Size %.0f / %s",
                size, maxSize and string.format("%.0f", maxSize) or "?") or "bar full")
            skipSentForCycle = false
            lastSellAttempt = os.clock()

            -- Requested order: detect FULL -> Sell immediately -> Skip
            -- immediately. Do not add a wait between either remote call.
            local sellSent = sendAutoSell(events)
            if sellSent then
                monitorLastSellAt = os.clock()
                monitorLog("SELL sent", monitorLastMaxAt and string.format("MAX→SELL %.0fms",
                    (monitorLastSellAt - monitorLastMaxAt) * 1000) or "sent")
            else
                monitorLog("SELL failed", "remote unavailable")
            end
            skipSentForCycle = requestSkip()
            print("[dEnzCreator] FULL detected | Sell sent, then Skip sent with no added delay.")
        elseif os.clock() - lastSellAttempt >= 1.75 then
            -- Retry Sell if the full state persists; do not repeatedly send
            -- Skip for the same full-bar cycle.
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
            print("[dEnzCreator V3.3.6] Sale/reset detected; requesting AutoSkip.")
            if not skipSentForCycle then
                skipSentForCycle = requestSkip()
            end
            wasFull = false
            lastSellAttempt = 0
            monitorLastResetAt = os.clock()
            monitorLog("RESET observed", size and string.format("Size %.0f", size)
                or (barProgress and string.format("Bar %.0f%%", barProgress * 100) or "bar/size reset"))
            print("[dEnzCreator] Sale/reset detected; continuous Grab/Eat cycle re-armed.")
        end
    end

    if size ~= nil then
        lastSize = size
    end

    local mapName = getMapName()
    switchModeIfEnabled(mapName)
end


-- HIDDEN MAPS: STREAMED-IN HIDDEN PROCESSING / LOW VISUAL LOAD / BLACK FLOOR
-- Important: a client LocalScript cannot delay server-side map creation/replication.
-- This stage hides new map objects immediately, then walks existing descendants
-- in small per-frame batches so one full-map scan does not block a transition.
-- Workspace.Chunks stays interactive: only its visuals are hidden; physics remain.

local hiddenMapRoot = nil
local hiddenMapAddedConnection = nil
local hiddenMapGeneration = 0
local hiddenMapScanRunning = false
local hiddenMapScanProcessed = 0
local hiddenChunksRoot = nil
local hiddenChunksAddedConnection = nil
local hiddenChunksGeneration = 0
local hiddenChunksScanRunning = false
local hiddenChunksScanProcessed = 0
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
    -- Keep CanCollide/CanTouch/CanQuery and scripts unchanged for Grab/Eat.
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

-- Iterative tree walk: avoids the large synchronous GetDescendants() snapshot.
-- Newly arriving objects are hidden by DescendantAdded immediately, while this
-- worker catches up with objects that already existed when the root was bound.
local function scanTreeInBatches(root, isCurrent, hideCallback, batchSize, onFinished)
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

        if isCurrent() and onFinished then
            onFinished()
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

    -- No task.defer here: hide every incoming chunk visual on the event itself.
    hiddenChunksAddedConnection = chunks.DescendantAdded:Connect(function(obj)
        if hiddenMapsEnabled and hiddenChunksRoot == chunks
            and hiddenChunksGeneration == generation then
            hideFoodVisual(obj)
        end
    end)

    hiddenChunksScanRunning = true
    hiddenChunksScanProcessed = 0
    scanTreeInBatches(chunks,
        function()
            return hiddenMapsEnabled and hiddenChunksRoot == chunks
                and hiddenChunksGeneration == generation
        end,
        function(obj)
            hideFoodVisual(obj)
            hiddenChunksScanProcessed = hiddenChunksScanProcessed + 1
        end,
        HIDDEN_CHUNKS_BATCH_SIZE,
        function()
            hiddenChunksScanRunning = false
        end
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
    hiddenMapScanRunning = false
end

local function disconnectHiddenChunksRoot()
    if hiddenChunksAddedConnection then
        pcall(function() hiddenChunksAddedConnection:Disconnect() end)
        hiddenChunksAddedConnection = nil
    end
    hiddenChunksGeneration = hiddenChunksGeneration + 1
    hiddenChunksRoot = nil
    hiddenChunksScanRunning = false
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

local function pruneDestroyedHiddenObjects()
    for obj in pairs(hiddenMapOriginals) do
        local hasParent = false
        pcall(function() hasParent = obj.Parent ~= nil end)
        if not hasParent then
            hiddenMapOriginals[obj] = nil
        end
    end
end

local function bindHiddenMapRoot(mapRoot)
    if not hiddenMapsEnabled or not mapRoot then return false end
    if hiddenMapRoot == mapRoot then return true end

    pruneDestroyedHiddenObjects()
    -- Disconnect only the previous Map listener. Keep the Chunks listener alive.
    disconnectHiddenMapRoot()
    hiddenMapRoot = mapRoot
    hiddenMapGeneration = hiddenMapGeneration + 1
    local generation = hiddenMapGeneration

    -- Connect before walking existing descendants to close the scan race window.
    hiddenMapAddedConnection = mapRoot.DescendantAdded:Connect(function(obj)
        if hiddenMapsEnabled and hiddenMapRoot == mapRoot
            and hiddenMapGeneration == generation then
            hideMapObject(obj, mapRoot)
        end
    end)

    hiddenMapScanRunning = true
    hiddenMapScanProcessed = 0
    scanTreeInBatches(mapRoot,
        function()
            return hiddenMapsEnabled and hiddenMapRoot == mapRoot
                and hiddenMapGeneration == generation
        end,
        function(obj)
            hideMapObject(obj, mapRoot)
            hiddenMapScanProcessed = hiddenMapScanProcessed + 1
        end,
        HIDDEN_MAP_BATCH_SIZE,
        function()
            hiddenMapScanRunning = false
            print("[dEnzCreator STAGE 7] Map hidden in background:", mapRoot.Name,
                "| descendants processed:", hiddenMapScanProcessed)
        end
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

-- Floating Stage 5 Inspector: visible in-game; no executor console required.
local monitorPanel = Instance.new("Frame")
monitorPanel.Name = "Stage5Inspector"
monitorPanel.Size = UDim2.fromOffset(236, 190)
monitorPanel.Position = UDim2.new(1, -244, 0, 90)
monitorPanel.BackgroundColor3 = Color3.fromRGB(13, 15, 22)
monitorPanel.BackgroundTransparency = 0.08
monitorPanel.BorderSizePixel = 0
monitorPanel.Parent = gui
Instance.new("UICorner", monitorPanel).CornerRadius = UDim.new(0, 8)

local monitorTitle = Instance.new("TextLabel")
monitorTitle.Size = UDim2.new(1, -48, 0, 24)
monitorTitle.Position = UDim2.fromOffset(7, 3)
monitorTitle.BackgroundTransparency = 1
monitorTitle.Text = "STAGE 5 INSPECTOR"
monitorTitle.TextColor3 = Color3.fromRGB(120, 220, 180)
monitorTitle.TextSize = 10
monitorTitle.Font = Enum.Font.GothamBold
monitorTitle.TextXAlignment = Enum.TextXAlignment.Left
monitorTitle.Parent = monitorPanel

local monitorToggle = Instance.new("TextButton")
monitorToggle.Size = UDim2.fromOffset(34, 22)
monitorToggle.Position = UDim2.new(1, -40, 0, 3)
monitorToggle.BackgroundColor3 = Color3.fromRGB(55, 75, 105)
monitorToggle.Text = "ON"
monitorToggle.TextColor3 = Color3.new(1,1,1)
monitorToggle.TextSize = 9
monitorToggle.Font = Enum.Font.GothamBold
monitorToggle.Parent = monitorPanel
Instance.new("UICorner", monitorToggle).CornerRadius = UDim.new(0, 5)

local monitorText = Instance.new("TextLabel")
monitorText.Size = UDim2.new(1, -12, 1, -32)
monitorText.Position = UDim2.fromOffset(6, 28)
monitorText.BackgroundTransparency = 1
monitorText.TextColor3 = Color3.fromRGB(225, 230, 240)
monitorText.TextSize = 8
monitorText.Font = Enum.Font.Code
monitorText.TextXAlignment = Enum.TextXAlignment.Left
monitorText.TextYAlignment = Enum.TextYAlignment.Top
monitorText.TextWrapped = true
monitorText.Text = "Waiting for telemetry..."
monitorText.Parent = monitorPanel

monitorToggle.Activated:Connect(function()
    monitorEnabled = not monitorEnabled
    monitorText.Visible = monitorEnabled
    monitorToggle.Text = monitorEnabled and "ON" or "OFF"
end)

local function refreshStage5Inspector()
    if not monitorEnabled or not monitorText then return end
    local map = Workspace:FindFirstChild("Map") or latestDetachedMapRoot
    local chunks = Workspace:FindFirstChild("Chunks")
    if not chunks and worldRootsDetached then
        local bucket = detachedWorldRoots.Chunks
        chunks = bucket[#bucket]
    end
    local mapChildren = map and #map:GetChildren() or 0
    local chunkChildren = chunks and #chunks:GetChildren() or 0
    local mapName = getMapName()
    local char, hum, root = getParts()
    local size, maxSize = getCapacityState(char)
    local bar = getSellBarProgress()
    local floor = Workspace:FindFirstChild(FARM_FLOOR_NAME)
    local now = os.clock()

    if mapName ~= monitorLastMapName then
        if monitorLastMapName ~= "" then monitorLog("MAP name", mapName) end
        monitorLastMapName = mapName
    end
    if monitorLastMapChildren ~= mapChildren then
        monitorLog("MAP children", tostring(mapChildren))
        monitorLastMapChildren = mapChildren
    end
    if monitorLastChunksChildren ~= chunkChildren then
        monitorLog("CHUNKS children", tostring(chunkChildren))
        monitorLastChunksChildren = chunkChildren
    end

    local grabGap = monitorLastGrabAt and (now - monitorLastGrabAt) * 1000 or nil
    local eatGap = monitorLastEatAt and (now - monitorLastEatAt) * 1000 or nil
    local landingGap = monitorLastLandingAt and (now - monitorLastLandingAt) or nil
    local lines = {
        "Farm: " .. (CFG.Farm and "ON" or "OFF") .. " | " .. monitorLastActionLabel,
        "Map: " .. tostring(mapName) .. " | children " .. tostring(mapChildren),
        "Chunks: " .. (chunks and tostring(chunkChildren) or "NOT FOUND"),
        "Size: " .. (size and string.format("%.0f/%s", size, maxSize and string.format("%.0f", maxSize) or "?") or "n/a")
            .. " | Bar: " .. (bar and string.format("%.0f%%", bar * 100) or "n/a"),
        "Grab age: " .. (grabGap and string.format("%.0fms", grabGap) or "n/a")
            .. " | Eat age: " .. (eatGap and string.format("%.0fms", eatGap) or "n/a"),
        "Landing age: " .. (landingGap and string.format("%.1fs", landingGap) or "waiting"),
        "FarmFloor: " .. (floor and "FOUND" or "MISSING")
            .. " | Floor mode: " .. (worldRootsDetached and "FIXED Y=0" or "OFF"),
        "Map mode: " .. (hiddenMapsEnabled and "HIDDEN (persistent)" or "VISIBLE")
            .. " | map batch: " .. (hiddenMapScanRunning and tostring(hiddenMapScanProcessed) or "done")
            .. " | chunks batch: " .. (hiddenChunksScanRunning and tostring(hiddenChunksScanProcessed) or "done"),
        "Transition: " .. (transitionStartedAt and string.format("%.2fs", now - transitionStartedAt) or "waiting")
            .. " | surface: " .. (transitionSurfaceReadyAt and string.format("%.2fs", transitionSurfaceReadyAt - transitionStartedAt) or "pending")
            .. " | first action: " .. (transitionFirstActionAt and string.format("%.2fs", transitionFirstActionAt - transitionStartedAt) or "pending"),
        "Recent events:"
    }
    for i = 1, math.min(#monitorEvents, 7) do
        table.insert(lines, monitorEvents[i])
    end
    monitorText.Text = table.concat(lines, "\n")
end

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
    if on then
        -- Prepare the single floor and remove map visuals in the same activation.
        ensureFarmFloor()
        setHiddenMaps(true)
        setKedadaTransition(true)
        -- Keep Map available for Raycast first. farmStep detaches Map/Chunks
        -- only after a valid walkable surface has been detected.
        pendingLandingMap = getMapName()
        landingConfirmedAt = nil
        noFoodMapKey = select(2, getMapName())
        noFoodSkipSentForMap = false
        lastFoodScanAt = 0
        cachedFoodNearby = false
        lastNoFoodSkipAttemptAt = 0
        lastLandingAttempt = 0
        -- farmStep performs the one initial floor-lock pass before Grab/Eat.
        -- Do not wait for the next Heartbeat before the first Grab/Eat attempt.
        pcall(farmStep)
    else
        setKedadaTransition(false)
        restoreWorldRoots()
        setHiddenMaps(false)
        removeFarmFloor()
        pendingLandingMap = nil
        landingConfirmedAt = nil
    end
    print("[dEnzCreator V3.3.6] AutoFarm", on and "ON" or "OFF")
end)

-- Map hiding is now automatic with AutoFarm; no separate toggle is needed.

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

makeToggle("AUTO CLAIM REWARDS", 5, Color3.fromRGB(133, 89, 195), false, function(on)
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
    restoreWorldRoots()
    setHiddenMaps(false)
    removeFarmFloor()
    setKedadaTransition(false)
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


-- Bind each replacement Map/Chunks root before local detachment.
kedadaCharacterConnection = player.CharacterAdded:Connect(function(char)
    if not kedadaTransitionEnabled then return end
    task.defer(function()
        if kedadaTransitionEnabled and player.Character == char then
            local hum = char:WaitForChild("Humanoid", 5)
            applyKedadaTransitionToCharacter(char, hum)
        end
    end)
end)

workspaceMapConnection = Workspace.ChildAdded:Connect(function(child)
    if child.Name ~= "Map" and child.Name ~= "Chunks" then return end

    if hiddenMapsEnabled then
        if child.Name == "Map" then
            -- Bind before detaching so descendant streaming remains monitored.
            bindHiddenMapRoot(child)
        else
            bindHiddenChunks(child)
        end
    end

    if CFG.Farm and worldRootsDetached then
        -- Chunks can be detached immediately. Keep a replacement Map in
        -- Workspace until farmStep raycasts its surface, then detach both roots.
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
    if monitorEnabled and os.clock() - (monitorLastRefresh or 0) >= 0.5 then
        monitorLastRefresh = os.clock()
        pcall(refreshStage5Inspector)
    end
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
        setKedadaTransition(false)
        restoreWorldRoots()
        setHiddenMaps(false)
        removeFarmFloor()
        if workspaceMapConnection then workspaceMapConnection:Disconnect() end
        if kedadaCharacterConnection then kedadaCharacterConnection:Disconnect() end
        connection:Disconnect()
    end
end)

print("[dEnzCreator STAGE 8 RAYCAST FLOOR] LocalChunkManager/Animate disabled + Humanoid Physics; Raycast detects map surface before Map/Chunks detach; roots restored when AutoFarm turns OFF; Grab/Eat animation 5x; Grab/post-Grab delays 0.02s/12.")
print("[dEnzCreator V3.3.6] Bar/capacity detection loaded. Eat/Grab stay active; AutoSell + AutoSkip enabled.")

-- FLOOR LOCK FIX 2 re-normalizes existing FarmFloor size, Y=0 surface, and collision flags once per farmStep cycle; Grab/Eat behavior is unchanged.

-- V3.3.6: Transition floor lock corrects upward impulses and holds position
-- on the fixed Y=0 FarmFloor while map roots are detached; Grab/Eat continue.
-- AutoSell, AutoSkip, and Grab/Eat timing are retained.

-- V3.3.6 adds a live runtime/statistics panel. Unknown game values display as -- rather than fabricated numbers.


-- V3.3.6: Combined title/timer header (140px), left-aligned title, 5x named Grab/Eat animation acceleration. Grab and post-Grab delays are each divided by 12.

-- V3.3.6: Season time starts when map food objects are detected and stops when the sell bar reaches full.

-- Stage 8 fix: farmAnchor does not wait for map geometry; fixed floor is ready immediately.


-- STAGE 8 REVISION: FULL KEDADA-STYLE LOCAL WORLD DETACH.
-- AutoFarm ON: LocalChunkManager + Animate disabled; Humanoid uses Physics;
-- Workspace.Map and Workspace.Chunks are cached and reparented to nil.
-- New Map/Chunks roots arriving during transitions are detached as well.
-- Raycast detects each map's walkable surface before Map/Chunks are detached;
-- the anchored farm floor follows that detected height at landing X=0, Z=100.
-- AutoFarm OFF / GUI cleanup restores cached Map/Chunks roots and original
-- LocalScript Disabled states. This is a test adaptation; verify floor height
-- on every Mega map because maps with playable surfaces below/above Y=0 may
-- require a later per-map adjustment.
