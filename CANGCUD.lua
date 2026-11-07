-- dEnzCreator ETW AUTOFARM - TRANSITION SAFE FLOOR + NO-FOOD AUTOSKIP
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


-- One persistent anchored farm floor. Its height is matched to the active map's
-- detected walkable surface; Workspace.Chunks is deliberately left untouched.
local FARM_FLOOR_NAME = "dEnzCreator_FarmFloor"
local FARM_FLOOR_SIZE = Vector3.new(2048, 10, 2048)
local FARM_FLOOR_HALF_HEIGHT = FARM_FLOOR_SIZE.Y / 2
local FARM_LANDING_X = 0
local FARM_LANDING_Z = 100
local FARM_SURFACE_RAY_TOP = 5000
local FARM_SURFACE_RAY_LENGTH = 10000
local FARM_SURFACE_SCAN_INTERVAL = 0.20
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

local function ensureFarmFloor()
    if farmFloor and farmFloor.Parent == Workspace then
        return farmFloor
    end

    local existing = Workspace:FindFirstChild(FARM_FLOOR_NAME)
    if existing and existing:IsA("BasePart") then
        farmFloor = existing
        farmFloor.Anchored = true
        farmFloor.CanCollide = true
        farmFloor.CanTouch = true
        farmFloor.CanQuery = true
        return farmFloor
    end

    local floor = Instance.new("Part")
    floor.Name = FARM_FLOOR_NAME
    floor.Size = FARM_FLOOR_SIZE
    floor.CFrame = CFrame.new(0, -FARM_FLOOR_HALF_HEIGHT, 0)
    floor.Anchored = true
    floor.CanCollide = true
    floor.CanTouch = true
    floor.CanQuery = true
    floor.CastShadow = false
    floor.Color = Color3.fromRGB(5, 5, 7)
    floor.Material = Enum.Material.SmoothPlastic
    floor.TopSurface = Enum.SurfaceType.Studs
    floor.BottomSurface = Enum.SurfaceType.Smooth
    floor.Parent = Workspace
    farmFloor = floor
    return floor
end

-- STAGE 5: re-check the new map surface every 0.20s while it streams in.
-- This only shortens local floor-height detection latency; it does not force
-- server map loading or change AutoSell/AutoSkip/Grab-Eat behavior.
-- Find a broad, walkable map surface under the shared X=0, Z=100 landing point.
-- Original map parts are only hidden with LocalTransparencyModifier, so they
-- remain queryable and can still provide their actual height for this scan.
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
        local result = Workspace:Raycast(origin, Vector3.new(0, -FARM_SURFACE_RAY_LENGTH, 0), params)
        if result and result.Normal.Y >= 0.82 then
            local hit = result.Instance
            local acceptable = hit == Workspace.Terrain
            if hit:IsA("BasePart") then
                acceptable = hit.CanCollide and hit.CanQuery
                    and hit.CFrame.UpVector.Y >= 0.82
                    and hit.Size.X >= 12 and hit.Size.Z >= 12
            end
            if acceptable then
                table.insert(heights, result.Position.Y)
            end
        end
    end

    if #heights == 0 then return nil end
    table.sort(heights)
    -- Median rejects isolated raised props while tolerating small terrain variation.
    local middle = math.floor((#heights + 1) / 2)
    if #heights % 2 == 0 then
        return (heights[middle] + heights[middle + 1]) / 2
    end
    return heights[middle]
end

local function positionFarmFloorForMap(mapKey)
    if farmSurfaceMapKey ~= mapKey then
        farmSurfaceMapKey = mapKey
        farmSurfaceTopY = nil
        lastFarmSurfaceScan = 0
    end

    if farmSurfaceTopY then return true end
    local now = os.clock()
    if now - lastFarmSurfaceScan < FARM_SURFACE_SCAN_INTERVAL then
        return false
    end
    lastFarmSurfaceScan = now

    local scanStarted = os.clock()
    local mapTopY = detectMapSurfaceTopY()
    monitorLastSurfaceScanMs = (os.clock() - scanStarted) * 1000
    monitorLastSurfaceScanAt = os.clock()
    if mapTopY == nil then
        monitorLog("SURFACE", "not ready; scan " .. string.format("%.1fms", monitorLastSurfaceScanMs))
        return false
    end
    transitionSurfaceReadyAt = os.clock()
    local surfaceElapsed = transitionStartedAt and (transitionSurfaceReadyAt - transitionStartedAt) or nil
    monitorLog("SURFACE ready", string.format("Y %.2f | scan %.1fms | transition %s",
        mapTopY, monitorLastSurfaceScanMs,
        surfaceElapsed and string.format("%.2fs", surfaceElapsed) or "n/a"))

    -- Keep the black anchored floor just above the actual map surface.
    farmSurfaceTopY = mapTopY + 0.05
    local floor = ensureFarmFloor()
    floor.CFrame = CFrame.new(0, farmSurfaceTopY - FARM_FLOOR_HALF_HEIGHT, 0)
    floor.Anchored = true
    print("[dEnzCreator] Anchored farm floor matched map surface:", mapKey,
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
    local surfaceReady = positionFarmFloorForMap(key)
    if not surfaceReady then
        -- TRANSITION SAFETY: keep the existing anchored floor at its last safe
        -- height while the next map streams. Never leave the character unsupported
        -- just because the next map surface has not replicated yet.
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
        else
            -- Keep the character supported without repeatedly rewriting CFrame.
            local v = root.AssemblyLinearVelocity
            if math.abs(v.Y) > 0.5 then
                root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
            end
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

-- Detect REAL eating progress after a confirmed landing.
-- Sending Grab/Eat remotes is not proof that food was eaten, so this watches
-- the character Size value and sell-bar progress for an actual increase.
-- The 3-second timer starts only after the character is physically on the floor.
local NO_EAT_CONFIRM_SECONDS = 3.0
local NO_EAT_RETRY_INTERVAL = 1.5
local EAT_SIZE_EPSILON = 0.000001
local EAT_BAR_EPSILON = 0.005

local function monitorLandingEatProgress(char, hum, root)
    if not pendingLandingMap or noFoodSkipSentForMap then
        return false
    end

    local mapName, key = getMapName()
    if key ~= noFoodMapKey then
        noFoodMapKey = key
        pendingLandingMap = mapName
        landingConfirmedAt = nil
        lastNoFoodSkipAttemptAt = 0
        landingSizeBaseline = nil
        landingBarBaseline = nil
        noFoodSkipSentForMap = false
    end

    local now = os.clock()
    if not farmSurfaceTopY then
        return false
    end
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
        monitorLastLandingAt = now
        monitorLog("LANDING confirmed", string.format("Y %.1f", root.Position.Y))
        landingSizeBaseline = select(1, getCapacityState(char))
        landingBarBaseline = getSellBarProgress()
        print("[dEnzCreator] Landing confirmed; monitoring actual eating for 3 seconds:", pendingLandingMap)
        return false
    end

    local currentSize = select(1, getCapacityState(char))
    local currentBar = getSellBarProgress()
    local sizeIncreased = currentSize ~= nil and landingSizeBaseline ~= nil
        and currentSize > landingSizeBaseline + EAT_SIZE_EPSILON
    local barIncreased = currentBar ~= nil and landingBarBaseline ~= nil
        and currentBar > landingBarBaseline + EAT_BAR_EPSILON

    if sizeIncreased or barIncreased then
        noFoodSkipSentForMap = true
        pendingLandingMap = nil
        print("[dEnzCreator] Actual eating progress detected; no-food AutoSkip cancelled for this map.",
            sizeIncreased and "Size increased" or "sell bar increased")
        return true
    end

    if now - landingConfirmedAt >= NO_EAT_CONFIRM_SECONDS
        and now - lastNoFoodSkipAttemptAt >= NO_EAT_RETRY_INTERVAL then
        lastNoFoodSkipAttemptAt = now
        if requestSkip(true) then
            -- Keep monitoring/retrying until the map key actually changes.
            -- A successful FireServer call alone does not prove the server skipped.
            print("[dEnzCreator] No actual eating progress 3 seconds after landing; AutoSkip sent, awaiting map change:", pendingLandingMap)
        else
            warn("[dEnzCreator] No-eat AutoSkip request failed; will retry while this map remains active.")
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

    farmAnchor()
    accelerateActionAnimations(hum)

    monitorLandingEatProgress(char, hum, root)
    -- Re-assert the floor lock after food detection, without pausing Grab/Eat.
    farmAnchor()

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
