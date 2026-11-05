-- dEnzCreator ETW AUTOFARM V3.3.24 - CENTRAL Z150 + 2S ACTION ANIMATION + TIGHT HEADER (NO DYNAMIC COLLISION)
-- Reconstructed from the previously mapped Auto.txt behavior.
-- Separate test file. Does not overwrite the original source/loader.
-- Sell and SkipMaps are requested together at full capacity; Sell retries continue until reset.
-- HiddenMaps follows KEDADA: hide non-food Map visuals; keep Chunks and food visuals.
-- Chunks and food visuals remain protected; Grab/Eat never pause during map transition.

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
    CentralRobloxiaZ = 150,
    StudvilleZ = 100,
    AutoSkipAfterSell = true,
    UseMappedSkipRemote = true,
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
local eatCallsRemaining = 0
local nextGrabEatActionAt = 0
local GRAB_DELAY_BASE = 0.04
local POST_GRAB_DELAY_BASE = 0.03 -- requested shorter pause between Grab and Eat
local DELAY_ACCELERATION = 12
local GRAB_DELAY = GRAB_DELAY_BASE / DELAY_ACCELERATION
local POST_GRAB_DELAY = POST_GRAB_DELAY_BASE
local EAT_TOTAL_WINDOW = 0.02 -- spread all 3 Eat calls across 20 ms total
local EAT_CALL_INTERVAL = EAT_TOTAL_WINDOW / 2 -- 10 ms between call 1->2 and 2->3
local lastSellAttempt = 0
local wasFull = false
local skipSentForCycle = false
local sellPending = false
local sellBaselineSize = nil
local sellBaselineBar = nil
local sellAttempts = 0
local skipRequestPending = false
local lastSkipRetry = 0
local lastObservedSize = nil
local lastObservedBar = nil
local SELL_RETRY_INTERVAL = 0.05 -- requested fast Sell retry cadence
local SELL_MAX_ATTEMPTS = math.huge -- continue while full; stop after sale is confirmed
local SELL_RESET_EPSILON = 0.01
local lastSize = nil
local lastBarProgress = nil
local SKIP_THRESHOLD = 0.9999
local SELL_TRIGGER_THRESHOLD = 0.9999
local pendingLandingMap = nil
local lastLandingAttempt = 0
local missingActionSince = nil
local missingActionSkipSent = false
local cycleStartedAt = nil
local completedCycleSeconds = 0
local lastNearbyFoodAt = nil
local lastMissingActionMap = ""
local hiddenMapsEnabled = false
local hiddenMapOriginals = {}
local hiddenMapConnections = {}
local workspaceMapConnection = nil

-- Fast map-card picker: the leftmost card is Robloxia Tengah and must be avoided.
local mapPickArmed = false
local mapPickDeadline = 0
local mapPickNextScan = 0
local mapPickCompleted = false
local MAP_PICK_TIMEOUT = 20
local MAP_PICK_SCAN_INTERVAL = 0.05

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
    local compactKey = key:gsub("[^%w]", "")
    local isCentral = (key:find("central", 1, true) and key:find("robloxia", 1, true))
        or (key:find("robloxia", 1, true) and key:find("tengah", 1, true))
        or compactKey:find("centralrobloxia", 1, true)
        or compactKey:find("robloxiatengah", 1, true)
    local isStudville = key:find("studville", 1, true) ~= nil
    local mapChanged = mapName ~= lastMap

    if mapChanged then
        lastMap = mapName
        pendingLandingMap = mapName
        lastLandingAttempt = 0
        mapPickArmed = false
        mapPickCompleted = false
        mapPickNextScan = 0
        skipSentForCycle = false
        skipRequestPending = false
        sellPending = false
        sellAttempts = 0
        print("[dEnzCreator V3.3.24] Map changed:", mapName, "| Central:", isCentral and "yes" or "no")
    end
    if not pendingLandingMap then return true end
    if os.clock() - lastLandingAttempt < 0.10 then return false end
    lastLandingAttempt = os.clock()

    local destinationXZ
    if isCentral then
        -- Robloxia Tengah: never land at the empty map center. Select a live
        -- collectible part from Chunks and stand a short distance beside it.
        local chunks = Workspace:FindFirstChild("Chunks")
        if not chunks then return false end
        local nearest, nearestDist = nil, math.huge
        for _, obj in ipairs(chunks:GetDescendants()) do
            if obj:IsA("BasePart") and obj.Parent and obj:IsDescendantOf(chunks) then
                local delta = Vector3.new(obj.Position.X - root.Position.X, 0, obj.Position.Z - root.Position.Z)
                local d2 = delta:Dot(delta)
                if d2 < nearestDist then nearest, nearestDist = obj, d2 end
            end
        end
        if not nearest then return false end
        local foodPos = nearest.Position
        local away = Vector3.new(root.Position.X - foodPos.X, 0, root.Position.Z - foodPos.Z)
        if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
        destinationXZ = Vector3.new(foodPos.X, 0, foodPos.Z) + away.Unit * 3
    else
        local z = isStudville and CFG.StudvilleZ or CFG.DefaultZ
        destinationXZ = Vector3.new(0, 0, z)
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    local chunksRoot = Workspace:FindFirstChild("Chunks")
    if isCentral and chunksRoot then params.FilterDescendantsInstances = {char, chunksRoot} end
    params.IgnoreWater = true
    local origin = Vector3.new(destinationXZ.X, 5000, destinationXZ.Z)
    local result = Workspace:Raycast(origin, Vector3.new(0, -10000, 0), params)
    local bedrock = Workspace:FindFirstChild("bedrock")
    if result and bedrock and result.Instance == bedrock then
        local exclusions = {char, bedrock}
        if isCentral and chunksRoot then table.insert(exclusions, chunksRoot) end
        params.FilterDescendantsInstances = exclusions
        result = Workspace:Raycast(origin, Vector3.new(0, -10000, 0), params)
    end
    if not result then return false end

    local targetY = result.Position.Y + hum.HipHeight + root.Size.Y / 2 + 0.15
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    root.CFrame = CFrame.new(destinationXZ.X, targetY, destinationXZ.Z)
    pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    print("[dEnzCreator V3.3.24] Landing:", pendingLandingMap,
        "| food-target:", isCentral and "yes" or "no",
        "| X=", destinationXZ.X, "Y=", targetY, "Z=", destinationXZ.Z)
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
        warn("[dEnzCreator V3.3.15] SetServerSettings RemoteEvent not found.")
        return false
    end

    -- Keep the mapped skip command, but do not pause the map timer.
    local ok, err = pcall(function()
        local args = {{MapTime = -1, Paused = false}}
        remote:FireServer(unpack(args))
    end)
    if ok then
        if not mapPickArmed and not mapPickCompleted then
            mapPickArmed = true
            mapPickDeadline = os.clock() + MAP_PICK_TIMEOUT
            mapPickNextScan = 0
        end
        print("[dEnzCreator V3.3.24] AutoSkip request sent; verified non-central map selection armed.")
        return true
    end

    warn("[dEnzCreator V3.3.15] AutoSkip error:", err)
    return false
end


local function isGuiTreeVisible(obj)
    local node = obj
    while node do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("LayerCollector") and not node.Enabled then return false end
        node = node.Parent
    end
    return true
end

local function findNextMapPrompt(pg)
    for _, obj in ipairs(pg:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and isGuiTreeVisible(obj) then
            local txt = norm(obj.Text)
            if txt:find("pilih peta berikutnya", 1, true) then
                return obj
            end
        end
    end
    return nil
end

local function collectMapCardButtons(pg, prompt)
    local promptY = prompt.AbsolutePosition.Y + prompt.AbsoluteSize.Y * 0.5
    local raw = {}
    for _, obj in ipairs(pg:GetDescendants()) do
        if obj:IsA("GuiButton") and isGuiTreeVisible(obj) then
            local size = obj.AbsoluteSize
            local pos = obj.AbsolutePosition
            local cx = pos.X + size.X * 0.5
            local cy = pos.Y + size.Y * 0.5
            -- Map cards are the large horizontal buttons above the prompt.
            -- This excludes the lower Skip button and small HUD controls.
            if size.X >= 130 and size.X <= 600
                and size.Y >= 80 and size.Y <= 380
                and cy < promptY - 4 and cy > promptY - 500 then
                table.insert(raw, {button = obj, x = cx, y = cy, area = size.X * size.Y})
            end
        end
    end

    -- Collapse nested/overlapping GuiButtons belonging to the same card.
    table.sort(raw, function(a, b) return a.area > b.area end)
    local cards = {}
    for _, item in ipairs(raw) do
        local duplicate = false
        for _, kept in ipairs(cards) do
            if math.abs(item.x - kept.x) < 90 and math.abs(item.y - kept.y) < 90 then
                duplicate = true
                break
            end
        end
        if not duplicate then table.insert(cards, item) end
    end
    table.sort(cards, function(a, b) return a.x < b.x end)
    return cards
end

local function getCardTitle(pg, card)
    local b = card.button
    local bp, bs = b.AbsolutePosition, b.AbsoluteSize
    local best, bestScore = "", -math.huge
    for _, obj in ipairs(pg:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and isGuiTreeVisible(obj) then
            local txt = norm(obj.Text)
            if txt ~= "" and not txt:find("pilih peta berikutnya", 1, true) then
                local p, z = obj.AbsolutePosition, obj.AbsoluteSize
                local cx, cy = p.X + z.X * 0.5, p.Y + z.Y * 0.5
                local inside = cx >= bp.X - 4 and cx <= bp.X + bs.X + 4
                    and cy >= bp.Y - 4 and cy <= bp.Y + bs.Y + 4
                if inside then
                    -- Prefer the larger, prominent title text on the card.
                    local score = math.min(z.X * z.Y, 1000000) + (#txt * 100)
                    if score > bestScore then best, bestScore = txt, score end
                end
            end
        end
    end
    return best
end

local function isCentralMapTitle(title)
    local t = norm(title)
    local compact = t:gsub("[^%w]", "")
    return (t:find("middle robloxia", 1, true) ~= nil)
        or (t:find("robloxia tengah", 1, true) ~= nil)
        or (t:find("central robloxia", 1, true) ~= nil)
        or compact:find("middlerobloxia", 1, true) ~= nil
        or compact:find("robloxiatengah", 1, true) ~= nil
        or compact:find("centralrobloxia", 1, true) ~= nil
end

local function selectNonCentralMapStep()
    if not mapPickArmed or mapPickCompleted then return end
    local now = os.clock()
    if now > mapPickDeadline then
        mapPickArmed = false
        warn("[dEnzCreator V3.3.15] Map picker timed out; no verified non-central card was activated.")
        return
    end
    if now < mapPickNextScan then return end
    mapPickNextScan = now + MAP_PICK_SCAN_INTERVAL

    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local prompt = findNextMapPrompt(pg)
    if not prompt then return end

    local cards = collectMapCardButtons(pg, prompt)
    if #cards < 2 then return end

    -- Do not blindly activate card #2. Read the visible title associated with
    -- each card, reject Middle/Robloxia Tengah, and choose the leftmost verified
    -- alternative. If a title cannot be read, wait rather than risk a wrong map.
    for i = 1, #cards do
        local title = getCardTitle(pg, cards[i])
        local cardHasCentralText = false
        local b = cards[i].button
        local bp, bs = b.AbsolutePosition, b.AbsoluteSize
        for _, obj in ipairs(pg:GetDescendants()) do
            if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and isGuiTreeVisible(obj) then
                local p, z = obj.AbsolutePosition, obj.AbsoluteSize
                local cx, cy = p.X + z.X * 0.5, p.Y + z.Y * 0.5
                local inside = cx >= bp.X - 4 and cx <= bp.X + bs.X + 4
                    and cy >= bp.Y - 4 and cy <= bp.Y + bs.Y + 4
                if inside and isCentralMapTitle(obj.Text) then
                    cardHasCentralText = true
                    break
                end
            end
        end
        if title ~= "" and not cardHasCentralText and not isCentralMapTitle(title) then
            local target = cards[i].button
            local ok, err = pcall(function() target:Activate() end)
            if not ok and type(firesignal) == "function" then
                ok, err = pcall(firesignal, target.Activated)
            end
            if ok then
                mapPickCompleted = true
                mapPickArmed = false
                print("[dEnzCreator V3.3.24] Selected verified non-central map:", title)
                return
            else
                warn("[dEnzCreator V3.3.15] Map card activation failed:", err)
            end
        end
    end
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
        warn("[dEnzCreator V3.3.15] Grab/Eat missing on", mapName,
            "- requesting automatic map skip.")
        missingActionSkipSent = true
        requestSkip()
    end
end

-- Optional RequestTeleport mode-switch remote removed in this stabilization build.

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

-- Sell/transition state machine.
-- Full is detected from either live Size/MaxSize ratio or the visible green bar.
-- After sending Sell (or noticing a manual sell), wait for a real reset before
-- requesting the next map. This prevents the previous bug: sending skip while
-- the inventory is still full, or never sending skip after a manual sale.
local function monitorSellAndSkip(char, events)
    local now = os.clock()
    local size, maxSize, numericFull = getCapacityState(char)
    local bar = getSellBarProgress()

    local numericRatio = nil
    if size ~= nil and maxSize ~= nil and maxSize > 0 then
        numericRatio = math.clamp(size / maxSize, 0, 1.5)
    end

    -- 99.99% trigger. Prefer live Size/MaxSize; use the visual bar only
    -- when numeric capacity values are unavailable.
    local ratio = numericRatio
    if ratio == nil then ratio = bar end
    local isFull = (ratio ~= nil and ratio >= 0.9999) or numericFull == true

    -- A sale can be performed by AutoSell or manually. Detect the actual
    -- inventory/bar reset, then request the next map exactly once.
    if sellPending then
        local sizeReset = sellBaselineSize ~= nil and size ~= nil
            and size < sellBaselineSize - math.max(1, sellBaselineSize * 0.005)
        local barReset = sellBaselineBar ~= nil and bar ~= nil
            and (bar <= 0.10 or bar < sellBaselineBar - 0.15)
        local numericReset = numericRatio ~= nil and numericRatio < 0.10

        if sizeReset or barReset or numericReset then
            print("[dEnzCreator V3.3.24] SELL CONFIRMED",
                "| Size:", size, "| MaxSize:", maxSize,
                "| Ratio:", ratio, "| Bar:", bar)
            sellPending = false
            wasFull = false
            sellAttempts = 0
            lastSellAttempt = 0
            sellBaselineSize = nil
            sellBaselineBar = nil
            cycleStartedAt = nil
            completedCycleSeconds = 0

            -- SkipMaps was requested concurrently when the bar first became full.
            -- Do not send a second map request after the sale confirmation.
            lastObservedSize = size
            lastObservedBar = bar
            return
        end
    end

    if isFull then
        if not wasFull then
            wasFull = true
            sellPending = true
            sellBaselineSize = size
            sellBaselineBar = bar
            sellAttempts = 0
            lastSellAttempt = 0
            print("[dEnzCreator V3.3.24] FULL DETECTED",
                "| Size:", size, "| MaxSize:", maxSize,
                "| Ratio:", ratio, "| Bar:", bar,
                "| Sell remote:", events and events:FindFirstChild("Sell") ~= nil)
            -- KEDADA-like overlap: request next map immediately; do not wait for Sell reset.
            if not skipSentForCycle then
                if requestSkip() then
                    skipSentForCycle = true
                    print("[dEnzCreator V3.3.24] SkipMaps sent concurrently with Sell.")
                else
                    skipRequestPending = true
                    lastSkipRetry = 0
                    warn("[dEnzCreator V3.3.24] SkipMaps queued for retry while Sell continues.")
                end
            end
        end

        -- Keep retrying Sell every 0.05s while capacity remains full.
        -- A successful local FireServer call is NOT treated as a confirmed sale.
        if now - lastSellAttempt >= SELL_RETRY_INTERVAL then
            lastSellAttempt = now
            sellAttempts = sellAttempts + 1
            local sell = events and events:FindFirstChild("Sell")
            if not sell then
                warn("[dEnzCreator V3.3.24] SELL ATTEMPT", sellAttempts,
                    "FAILED: Character.Events.Sell missing.")
            elseif not sell:IsA("RemoteEvent") then
                warn("[dEnzCreator V3.3.24] SELL ATTEMPT", sellAttempts,
                    "FAILED: Sell is", sell.ClassName, "not RemoteEvent.")
            else
                local ok, err = pcall(function()
                    sell:FireServer()
                end)
                if ok then
                    print("[dEnzCreator V3.3.24] SELL ATTEMPT", sellAttempts,
                        "sent | Size:", size, "| MaxSize:", maxSize,
                        "| Ratio:", ratio, "| Bar:", bar)
                else
                    warn("[dEnzCreator V3.3.24] SELL ATTEMPT", sellAttempts,
                        "ERROR:", err)
                end
            end
        end
    elseif not sellPending then
        wasFull = false
    end

    -- Keep queued SkipMaps requests retrying independently of AutoSell.
    if skipRequestPending and now - lastSkipRetry >= 1.0 then
        lastSkipRetry = now
        if requestSkip() then
            skipSentForCycle = true
            skipRequestPending = false
            print("[dEnzCreator V3.3.24] SkipMaps retry sent.")
        end
    end

    lastObservedSize = size
    lastObservedBar = bar
end

-- Food polling removed: Grab/Eat runs continuously like KEDADA; no undefined scanner gate.

-- Target: reduce the observed 3.5s Grab/Eat body animation to about 2.0s.
-- Existing 5x setting is scaled by 3.5/2 = 1.75, giving 8.75x.
-- Only tracks explicitly named Grab/Eat are affected.
-- Do not hook AnimationPlayed or affect other actions.
local ACTION_ANIMATION_SPEED = 8.75
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

    -- Map picker may suppress anchoring/movement only. Grab/Eat cadence NEVER pauses.
    local pickerActive = mapPickArmed
    if not pickerActive then
        local pg = player:FindFirstChildOfClass("PlayerGui")
        pickerActive = pg ~= nil and findNextMapPrompt(pg) ~= nil
    end

    -- During map transition, do NOT move/anchor the character, but keep
    -- scanning newly streamed food immediately. Grab/Eat remotes below remain
    -- active regardless of picker state.
    if not pickerActive then
        farmAnchor()
    end
    accelerateActionAnimations(hum)

    -- AutoSell/AutoSkip monitoring remains active while the map picker is open.
    monitorSellAndSkip(char, events)

    if events then
        local now = os.clock()
        local grabEvent = events:FindFirstChild("Grab")
        local eatEvent = events:FindFirstChild("Eat")

        if grabEvent and eatEvent and cycleStartedAt == nil then
            cycleStartedAt = now
            completedCycleSeconds = 0
            print("[dEnzCreator V3.3.24] Season time started: Grab/Eat menu active.")
        end

        if grabEvent and eatEvent and now >= nextGrabEatActionAt then
            if grabEatPhase == "grab" then
                fire(grabEvent)
                grabEatPhase = "eat"
                eatCallsRemaining = 3
                nextGrabEatActionAt = now + POST_GRAB_DELAY
            elseif grabEatPhase == "eat" then
                fire(eatEvent)
                eatCallsRemaining = eatCallsRemaining - 1
                lastFoodAction = now
                if eatCallsRemaining > 0 then
                    nextGrabEatActionAt = now + EAT_CALL_INTERVAL
                else
                    grabEatPhase = "grab"
                    nextGrabEatActionAt = now + GRAB_DELAY
                end
            end
        end
    end
end

-- HIDDEN MAPS: KEDADA-STYLE SELECTIVE VISUALS
-- Only Workspace.Map is scanned. Workspace.Chunks is deliberately untouched.
-- Food/collectible and floor/ground descendants are protected by name/ancestor.
-- Visual-only: never changes CanCollide/CanTouch/CanQuery, never reparents/deletes.
local function isProtectedMapObject(obj, mapRoot)
    local current = obj
    while current and current ~= mapRoot do
        local n = norm(current.Name)
        if n:find("food", 1, true)
            or n:find("collect", 1, true)
            or n:find("fruit", 1, true)
            or n:find("snack", 1, true)
            or n:find("eat", 1, true)
            or n:find("floor", 1, true)
            or n:find("ground", 1, true)
            or n:find("baseplate", 1, true)
            or n == "chunks" or n == "chunk" then
            return true
        end
        current = current.Parent
    end
    return false
end

local function isFloorMapObject(obj, mapRoot)
    local current = obj
    while current and current ~= mapRoot do
        local n = norm(current.Name)
        if n:find("floor", 1, true)
            or n:find("ground", 1, true)
            or n:find("baseplate", 1, true)
            or n == "terrain" then
            return true
        end
        current = current.Parent
    end
    return false
end

local function hideMapObject(obj, mapRoot)
    if not hiddenMapsEnabled or not obj or not mapRoot then return end
    if isProtectedMapObject(obj, mapRoot) then
        if obj:IsA("BasePart") and isFloorMapObject(obj, mapRoot) then
            if hiddenMapOriginals[obj] == nil then
                hiddenMapOriginals[obj] = {
                    kind = "floor",
                    transparency = obj.LocalTransparencyModifier,
                    color = obj.Color
                }
            end
            obj.LocalTransparencyModifier = 0
            obj.Color = Color3.new(0, 0, 0)
        end
        return
    end

    -- Match KEDADA V3.0.8: hide local visuals only. Keep the instance and
    -- every physics/query property intact so gameplay interactions continue.
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
    elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
        if hiddenMapOriginals[obj] == nil then
            hiddenMapOriginals[obj] = {
                kind = "effect",
                value = obj.Enabled
            }
        end
        obj.Enabled = false
    end
end

local hiddenMapRoot = nil
local hiddenMapGeneration = 0
local hiddenMapScanRunning = false

local function disconnectHiddenMapListeners()
    for _, connection in ipairs(hiddenMapConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(hiddenMapConnections)
end

local function restoreHiddenMap()
    hiddenMapGeneration = hiddenMapGeneration + 1
    hiddenMapScanRunning = false
    disconnectHiddenMapListeners()
    for obj, saved in pairs(hiddenMapOriginals) do
        if obj and obj.Parent then
            pcall(function()
                if saved.kind == "part" then
                    obj.LocalTransparencyModifier = saved.value
                elseif saved.kind == "floor" then
                    obj.LocalTransparencyModifier = saved.transparency
                    obj.Color = saved.color
                elseif saved.kind == "texture" then
                    obj.Transparency = saved.value
                elseif saved.kind == "effect" then
                    obj.Enabled = saved.value
                end
            end)
        end
    end
    table.clear(hiddenMapOriginals)
    hiddenMapRoot = nil
end

local function bindSelectiveMap(mapRoot)
    if not hiddenMapsEnabled or not mapRoot then return false end
    if hiddenMapRoot == mapRoot then return true end

    disconnectHiddenMapListeners()
    -- Invalidate any scan for the previous Map root. Its task exits on the
    -- generation check and cannot block the new root's scan.
    hiddenMapGeneration = hiddenMapGeneration + 1
    hiddenMapScanRunning = false
    hiddenMapRoot = mapRoot
    local generation = hiddenMapGeneration

    -- Attach first, so objects arriving while the initial scan runs are not missed.
    table.insert(hiddenMapConnections, mapRoot.DescendantAdded:Connect(function(obj)
        if not hiddenMapsEnabled or hiddenMapRoot ~= mapRoot then return end
        task.defer(function()
            if hiddenMapsEnabled and hiddenMapRoot == mapRoot
                and obj and obj.Parent and obj:IsDescendantOf(mapRoot) then
                hideMapObject(obj, mapRoot)
            end
        end)
    end))

    hiddenMapScanRunning = true
    task.spawn(function()
        local descendants = mapRoot:GetDescendants()
        local processed = 0
        for i = 1, #descendants do
            if not hiddenMapsEnabled or hiddenMapRoot ~= mapRoot
                or hiddenMapGeneration ~= generation then
                break
            end
            local obj = descendants[i]
            if obj and obj.Parent then hideMapObject(obj, mapRoot) end
            processed = processed + 1
            if processed % 120 == 0 then
                RunService.Heartbeat:Wait()
            end
        end
        if hiddenMapGeneration == generation then
            hiddenMapScanRunning = false
            print("[dEnzCreator V3.3.24] KEDADA selective Map ready | checked:", processed,
                "| Chunks untouched | food/floor protected")
        end
    end)
    return true
end

local function applyHiddenMap()
    if not hiddenMapsEnabled then return false end
    local mapRoot = Workspace:FindFirstChild("Map")
    if not mapRoot then return false end
    return bindSelectiveMap(mapRoot)
end

local function setHiddenMaps(enabled)
    if enabled then
        hiddenMapsEnabled = true
        applyHiddenMap()
        print("[dEnzCreator V3.3.24] Hidden Maps ON | KEDADA selective transparency; Chunks untouched")
    else
        hiddenMapsEnabled = false
        restoreHiddenMap()
        print("[dEnzCreator V3.3.24] Show Model ON | original Map visuals restored")
    end
end

-- dEnzCreator compact mobile panel (120 px wide), anchored at the top-right.
local gui = Instance.new("ScreenGui")
gui.Name = "dEnzCreator_ETW"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(120, 0)
frame.AutomaticSize = Enum.AutomaticSize.Y
frame.Position = UDim2.new(1, -132, 0, 8)
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
layout.Padding = UDim.new(0, 3)

local header = Instance.new("Frame")
header.LayoutOrder = 1
header.Size = UDim2.new(1, 0, 0, 43)
header.BackgroundColor3 = Color3.fromRGB(37, 39, 62)
header.BackgroundTransparency = 0
header.BorderSizePixel = 0
header.Parent = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 7)
local headerStroke = Instance.new("UIStroke", header)
headerStroke.Color = Color3.fromRGB(125, 105, 195)
headerStroke.Thickness = 1

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 66, 0, 17)
title.Position = UDim2.fromOffset(6, 1)
title.BackgroundTransparency = 1
title.Text = "dEnzCreator"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 10
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
runtimeBlock.Size = UDim2.new(0, 88, 0, 19)
runtimeBlock.Position = UDim2.fromOffset(5, 21)
runtimeBlock.BackgroundTransparency = 1
runtimeBlock.BorderSizePixel = 0
runtimeBlock.Text = "Runtime: 0m 0s\nSeason time: 0m 0s"
runtimeBlock.TextColor3 = Color3.fromRGB(240, 243, 248)
runtimeBlock.TextSize = 6
runtimeBlock.Font = Enum.Font.GothamMedium
runtimeBlock.TextXAlignment = Enum.TextXAlignment.Left
runtimeBlock.TextYAlignment = Enum.TextYAlignment.Center
-- Important: timer label is parented directly to header and has no background of its own.
runtimeBlock.Parent = header

local function makeToggle(label, order, color, initial, callback)
    local b = Instance.new("TextButton")
    b.LayoutOrder = order
    b.Size = UDim2.new(1, 0, 0, 24)
    b.BackgroundColor3 = initial and color or Color3.fromRGB(54, 52, 76)
    b.BorderSizePixel = 0
    b.Text = label .. (initial and ": ON" or ": OFF")
    b.TextColor3 = Color3.new(1, 1, 1)
    b.TextSize = 8
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

makeToggle("SHOW MODEL", 3, Color3.fromRGB(65, 105, 190), not hiddenMapsEnabled, function(showModel)
    setHiddenMaps(not showModel)
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


-- Re-apply only when the game replaces Workspace.Map; Chunks are not scanned.
workspaceMapConnection = Workspace.ChildAdded:Connect(function(child)
    if child.Name == "Map" and hiddenMapsEnabled then
        task.defer(function()
            if hiddenMapsEnabled then
                -- Do not rescan the still-existing root when only one root is replaced.
                applyHiddenMap()
            end
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
    pcall(selectNonCentralMapStep)
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

print("[dEnzCreator V3.3.24] Loaded. Grab/Eat continuous during transitions; broken food scanner removed; Sell retry 0.05s; SkipMaps and HiddenMaps retained.")
print("[dEnzCreator V3.3.24] 99.8% threshold loaded. AutoSell triggers at 99.99%; Sell runs at full during transition; default-map Z=0.")

-- V3.3.24: Removed undefined nearby-food scanner and unused RequestTeleport mode-switch path. Required Grab/Eat, Sell, and SetServerSettings remotes retained. KEDADA selective Map visuals; Chunks untouched.

-- V3.3.8: Default maps use Z=0; Studville uses Z=100; Central Robloxia uses Z=150. Grab/Eat body animation target is ~2.0s (8.75x adjustment); three Eat calls are spread across 0.02s total. Landing anchor remains X=0.

-- V3.3.3 retains the live runtime/statistics panel. Unknown game values display as -- rather than fabricated numbers.


-- V3.3.8: Combined title/timer header (140px), left-aligned title, 5x named Grab/Eat animation acceleration. Grab and post-Grab delays are each divided by 12.

-- V3.3.8: Season time starts when map food objects are detected and stops when the sell bar reaches full.


-- V3.3.8 changes: Central Robloxia name matching accepts English/Indonesian word orders;
-- post-Grab pause is 0.03s; title and runtime text blocks are narrower while panel remains top-right.

-- V3.3.10: Robloxia Tengah landing targets a live Chunks food part instead of the empty map-center anchor. Header/runtime spacing tightened.


-- V3.3.15 transition update: at the Skip menu, activate the second visible card
-- from the left, avoiding the known leftmost Robloxia Tengah card. Selection is
-- attempted immediately at 0.10s scan intervals; no fixed post-Skip wait is added.
-- Grab/Eat/Chunk timing, 99.8% threshold, and map landing coordinates are unchanged.

-- V3.3.24 revision: use the same selective visual hiding method as KEDADA V3.0.8.
-- Non-food descendants of Workspace.Map are hidden with local transparency;
-- food/collectible-named descendants are protected and Workspace.Chunks is untouched.
-- No collision, touch, query, parenting, or deletion changes. Grab/Eat remains active.
