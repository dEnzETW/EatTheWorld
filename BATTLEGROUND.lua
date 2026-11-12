local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local player = Players.LocalPlayer
if not player then
    warn("[GELUT] LocalPlayer tidak ditemukan.")
    return
end
local playerGui = player:WaitForChild("PlayerGui")

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
    warn("[GELUT] WHITELIST DENIED / LOAD FAILED")
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "dEnzCreator",
            Text = "Whitelist gagal atau akses ditolak.",
            Duration = 5
        })
    end)
    return
end

print("[GELUT] REMOTE WHITELIST OK: @" .. player.Name)

local old
pcall(function()
    old = (gethui and gethui():FindFirstChild("GELUT_COMBINED"))
        or CoreGui:FindFirstChild("GELUT_COMBINED")
end)
if not old then old = playerGui:FindFirstChild("GELUT_COMBINED") end
if old then old:Destroy() end
for _, container in ipairs({CoreGui, playerGui}) do
    local legacy = container:FindFirstChild("GELUT_MINI_CONTROL")
    if legacy then legacy:Destroy() end
end
pcall(function()
    if gethui then
        local legacy =
gethui():FindFirstChild("GELUT_MINI_CONTROL")
        if legacy then legacy:Destroy() end
    end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "GELUT_COMBINED"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local parented = false
local hui = nil

if type(gethui) == "function" then
    local ok, result = pcall(function()
        return gethui()
    end)
    if ok and typeof(result) == "Instance" then
        hui = result
    end
end

if hui then
    local ok = pcall(function()
        gui.Parent = hui
    end)
    parented = ok and gui.Parent == hui
end

if not parented then
    local ok = pcall(function()
        gui.Parent = CoreGui
    end)
    parented = ok and gui.Parent == CoreGui
end

if not parented then
    gui.Parent = playerGui
    parented = gui.Parent == playerGui
end

if not parented then
    warn("[GELUT] GUI startup failed: unable to parent ScreenGui")
    return
end

local RED = Color3.fromRGB(190, 32, 54)
local DARK = Color3.fromRGB(15, 14, 19)
local ROW = Color3.fromRGB(38, 37, 43)
local PILL = Color3.fromRGB(69, 68, 75)
local WHITE = Color3.fromRGB(244, 242, 246)
local MUTED = Color3.fromRGB(145, 140, 148)
local ACTIVE = Color3.fromRGB(91, 20, 36)

local function corner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = obj
end

local function label(parent, name, text, size, pos, font, color,
textSize, align)
    local o = Instance.new("TextLabel")
    o.Name = name
    o.BackgroundTransparency = 1
    o.Text = text
    o.Size = size
    o.Position = pos
    o.Font = font or Enum.Font.Gotham
    o.TextColor3 = color or WHITE
    o.TextSize = textSize or 10
    o.TextXAlignment = align or Enum.TextXAlignment.Left
    o.TextYAlignment = Enum.TextYAlignment.Center
    o.Parent = parent
    return o
end

local function smallButton(parent, name, text, size, pos, textSize)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Size = size
    b.Position = pos
    b.BackgroundColor3 = PILL
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = WHITE
    b.TextSize = textSize or 8
    b.Font = Enum.Font.GothamBold
    b.AutoButtonColor = false
    b.Parent = parent
    corner(b, 7)
    return b
end

local panel = Instance.new("Frame")
panel.Name = "MainPanel"
panel.Size = UDim2.fromOffset(150, 290)
panel.Position = UDim2.new(0.08, 0, 0.20, 0)
panel.BackgroundColor3 = DARK
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
corner(panel, 18)
local outline = Instance.new("UIStroke")
outline.Color = RED
outline.Thickness = 2.3
outline.Parent = panel

local minimize = smallButton(panel, "MinimizeMain", "–",
    UDim2.fromOffset(22, 22), UDim2.fromOffset(96, 9), 15)
minimize.BackgroundColor3 = Color3.fromRGB(119, 13, 31)
local close = smallButton(panel, "CloseMain", "×",
    UDim2.fromOffset(22, 22), UDim2.fromOffset(122, 9), 15)
close.BackgroundColor3 = Color3.fromRGB(119, 13, 31)

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, -12, 0, 250)
content.Position = UDim2.fromOffset(6, 40)
content.BackgroundTransparency = 1
content.Parent = panel

local home = Instance.new("Frame")
home.Name = "HomePage"
home.Size = UDim2.fromScale(1, 1)
home.BackgroundTransparency = 1
home.Parent = content

local function statusCard(name, x, y, caption, initialValue, valueColor)
    local card = Instance.new("Frame")
    card.Name = name
    card.Size = UDim2.fromOffset(40, 17)
    card.Position = UDim2.fromOffset(x, y)
    card.BackgroundColor3 = Color3.fromRGB(24, 23, 29)
    card.BorderSizePixel = 0
    card.Parent = panel
    corner(card, 4)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(54, 52, 60)
    stroke.Thickness = 1
    stroke.Parent = card
    label(card, name .. "Label", caption,
        UDim2.fromOffset(36, 6), UDim2.fromOffset(2, 0),
        Enum.Font.GothamMedium, MUTED, 5)
    local value = label(card, name .. "Value", initialValue,
        UDim2.fromOffset(36, 7), UDim2.fromOffset(2, 7),
        Enum.Font.GothamBold, valueColor or WHITE, 6)
    return value
end

local pingValue = statusCard("PingCard", 6, 2, "PING", "-- ms", Color3.fromRGB(45, 220, 95))
local serverValue = statusCard("ServerCard", 49, 2, "SERVER", "Checking", WHITE)
local fpsValue = statusCard("FPSCard", 6, 20, "FPS", "--", Color3.fromRGB(55, 150, 255))
local playerValue = statusCard("PlayerCard", 49, 20, "PEMAIN", "-- / --", WHITE)

local StatsService = game:GetService("Stats")
local frameCount = 0
local measuredFPS = 0
local lastFPSSample = os.clock()
local lastStatusUpdate = 0

RunService.RenderStepped:Connect(function()
    frameCount = frameCount + 1
    local now = os.clock()
    if now - lastFPSSample >= 1 then
        measuredFPS = math.floor(frameCount / (now - lastFPSSample) + 0.5)
        frameCount = 0
        lastFPSSample = now
    end
    if now - lastStatusUpdate >= 1 then
        lastStatusUpdate = now

        local pingMs = nil
        pcall(function()
            local network = StatsService.Network
            local serverStats = network.ServerStatsItem
            local dataPing = serverStats["Data Ping"]
            local raw = dataPing:GetValueString()
            pingMs = tonumber(string.match(raw, "[%d%.]+"))
            if not pingMs then
                pingMs = tonumber(dataPing:GetValue())
            end
        end)

        pingValue.Text = pingMs and (tostring(math.floor(pingMs + 0.5)) .. " ms") or "N/A"
        fpsValue.Text = tostring(measuredFPS)

        local currentPlayers = #Players:GetPlayers()
        local maxPlayers = 0
        pcall(function() maxPlayers = Players.MaxPlayers end)
        if not maxPlayers or maxPlayers <= 0 then maxPlayers = currentPlayers end
        playerValue.Text = tostring(currentPlayers) .. " / " .. tostring(maxPlayers)

        if not pingMs then
            serverValue.Text = "Unknown"
            serverValue.TextColor3 = MUTED
        elseif pingMs <= 180 then
            serverValue.Text = "Normal"
            serverValue.TextColor3 = Color3.fromRGB(45, 220, 95)
        else
            serverValue.Text = "Lag"
            serverValue.TextColor3 = Color3.fromRGB(255, 185, 65)
        end
    end
end)

local attackOpen = smallButton(home, "TPAttackOpen", "⚔️  TP ATTACK     ›",
    UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 0), 9)
attackOpen.TextXAlignment = Enum.TextXAlignment.Left

local featureNames = {
    "◎  TP TARGET", "🧲  AUTO GRAB", "●  ESP PLAYER",
    "⚓  ANTI ANCHOR", "✈  FLIGHT MODE", "▯  RUN SPEED",
    "▯  BIG PLATFORM", "⦿  ANTI VOID", "▦  WALL CLIP"
}
local featureButtons = {}
for i, name in ipairs(featureNames) do
    local y = 22 + (i - 1) * 22
    if i >= 3 then y = y + 22 end
    local b = smallButton(home, "Feature_" .. i, name .. (i <= 2 and "     ›" or "     OFF"),
        UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, y), 9)
    b.TextXAlignment = Enum.TextXAlignment.Left
    featureButtons[i] = b
end

local skyWalkOpen = smallButton(home, "SKYWALK_Open", "☁  SKYWALK     ›",
    UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 66), 9)
skyWalkOpen.TextXAlignment = Enum.TextXAlignment.Left

local footerTitle = label(panel, "FooterTitle", "GELUT",
    UDim2.fromOffset(70, 11), UDim2.new(0.5, -35, 1, -27),
    Enum.Font.GothamBold, WHITE, 9, Enum.TextXAlignment.Center)
local creator = label(panel, "Creator", "dEnzCreator",
    UDim2.fromOffset(100, 10), UDim2.new(0.5, -50, 1, -15),
    Enum.Font.GothamMedium, RED, 7, Enum.TextXAlignment.Center)

local attackPage = Instance.new("Frame")
attackPage.Name = "TPAttackPage"
attackPage.Size = UDim2.fromScale(1, 1)
attackPage.BackgroundTransparency = 1
attackPage.Visible = false
attackPage.Parent = content

local back = smallButton(attackPage, "Back", "‹ BACK",
    UDim2.fromOffset(48, 20), UDim2.fromOffset(0, 0), 8)
local refresh = smallButton(attackPage, "Refresh", "↻",
    UDim2.fromOffset(23, 20), UDim2.new(1, -23, 0, 0), 13)

local playerList = Instance.new("ScrollingFrame")
playerList.Name = "PlayerList"
playerList.Size = UDim2.new(1, 0, 1, -24)
playerList.Position = UDim2.fromOffset(0, 24)
playerList.BackgroundTransparency = 1
playerList.BorderSizePixel = 0
playerList.ScrollBarThickness = 2
playerList.ScrollBarImageColor3 = RED
playerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
playerList.CanvasSize = UDim2.new()
playerList.Parent = attackPage

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 3)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = playerList

local attackEnabled = false
local attackTarget = nil
local attackPhase = "idle"
local followConnection = nil

local function getCharacter()
    local char = player.Character
    if not char then return nil, nil end
    return char, char:FindFirstChild("HumanoidRootPart")
end

local function disconnectFollow()
    if followConnection then
        followConnection:Disconnect()
        followConnection = nil
    end
end

local function stopAttack()
    attackEnabled = false
    attackPhase = "idle"
    disconnectFollow()
end

local function refreshPlayers()
    for _, child in ipairs(playerList:GetChildren()) do
        if child:IsA("TextButton") and child.Name:sub(1, 10) == "PlayerRow_" then
            child:Destroy()
        end
    end

    local targets = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then table.insert(targets, p) end
    end
    table.sort(targets, function(a, b)
        return string.lower(a.DisplayName .. a.Name) < string.lower(b.DisplayName .. b.Name)
    end)

    local slots = math.max(8, #targets)
    for i = 1, slots do
        local target = targets[i]
        local selected = target ~= nil and target == attackTarget and attackEnabled

        local row = Instance.new("TextButton")
        row.Name = "PlayerRow_" .. (target and tostring(target.UserId) or ("Empty" .. i))
        row.LayoutOrder = i
        row.Size = UDim2.new(1, -1, 0, 25)
        row.BackgroundColor3 = selected and ACTIVE or ROW
        row.BackgroundTransparency = target and 0 or 0.48
        row.BorderSizePixel = 0
        row.Text = ""
        row.AutoButtonColor = false
        row.Active = target ~= nil
        row.Parent = playerList
        corner(row, 7)

        local text = target
            and (target.DisplayName .. "  (@" .. target.Name .. ")")
            or "— Slot kosong —"
        local name = label(row, "PlayerName", text,
            UDim2.new(1, -10, 1, 0), UDim2.fromOffset(6, 0),
            Enum.Font.GothamBold, selected and Color3.fromRGB(255, 90, 120)
                or (target and WHITE or MUTED), 7, Enum.TextXAlignment.Left)
        name.TextTruncate = Enum.TextTruncate.AtEnd

        if target then
            local chosen = target
            row.Activated:Connect(function()
                if chosen.Parent ~= Players then
                    refreshPlayers()
                    return
                end
                if attackEnabled and attackTarget == chosen then
                    stopAttack()
                else
                    stopAttack()
                    attackTarget = chosen
                    attackEnabled = true
                end
                refreshPlayers()
            end)
        end
    end
end

attackOpen.Activated:Connect(function()
    home.Visible = false
    attackPage.Visible = true
    refreshPlayers()
end)
back.Activated:Connect(function()
    stopAttack()
    attackPage.Visible = false
    home.Visible = true
end)
refresh.Activated:Connect(refreshPlayers)
Players.PlayerAdded:Connect(function() task.defer(refreshPlayers) end)
Players.PlayerRemoving:Connect(function(leaving)
    if leaving == attackTarget then
        attackTarget = nil
        stopAttack()
    end
    task.defer(refreshPlayers)
end)

task.spawn(function()
    while gui.Parent do
        if attackEnabled and attackPhase == "idle" then
            local char, root = getCharacter()
            if char and root then
                pcall(function()
                    char:PivotTo(CFrame.new(
                        math.random(-140, 140),
                        math.random(10, 50),
                        math.random(-140, 140)
                    ))
                end)
            end
            task.wait(0.3)
        else
            task.wait(0.05)
        end
    end
end)

task.spawn(function()
    while gui.Parent do
        if not attackEnabled then
            task.wait(0.15)
        else
            local target = attackTarget
            local char, root = getCharacter()
            local targetChar = target and target.Character
            local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")

            if target and target.Parent == Players and targetRoot and char and root then
                attackPhase = "prepare"
                task.wait(1.5)
                if not gui.Parent or not attackEnabled then
                    attackPhase = "idle"
                    continue
                end

                char, root = getCharacter()
                local events = char and char:FindFirstChild("Events")
                local grab = events and events:FindFirstChild("Grab")
                if grab then pcall(function() grab:FireServer() end) end

                task.wait(2)
                if not gui.Parent or not attackEnabled then
                    attackPhase = "idle"
                    continue
                end

                target = attackTarget
                targetChar = target and target.Character
                targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
                char, root = getCharacter()
                events = char and char:FindFirstChild("Events")

                local followStarted = false

                if targetRoot and char and root then
                    attackPhase = "follow"
                    followConnection = RunService.Heartbeat:Connect(function()
                        if not gui.Parent or not attackEnabled then return end

                        local currentTarget = attackTarget
                        local currentCharTarget = currentTarget and currentTarget.Character
                        local currentRootTarget = currentCharTarget
                            and currentCharTarget:FindFirstChild("HumanoidRootPart")
                        local currentChar, currentRoot = getCharacter()

                        if currentRootTarget and currentCharTarget and currentChar and currentRoot then
                            local mySize = currentChar:GetExtentsSize().Z
                            local targetSize = currentCharTarget:GetExtentsSize().Z
                            local safeDistance = (mySize / 2) + (targetSize / 2) + 2

                            currentChar:PivotTo(
                                currentRootTarget.CFrame * CFrame.new(0, 0, safeDistance)
                            )
                        end
                    end)
                    followStarted = true
                end

                if followStarted and gui.Parent and attackEnabled then
                    task.wait(0.25)

                    local throwEvent = events and events:FindFirstChild("Throw")
                    if throwEvent then
                        pcall(function()
                            throwEvent:FireServer()
                        end)
                    end

                    task.wait(1.5)
                end

                disconnectFollow()
                attackPhase = "idle"
                task.wait(1)
            else
                attackPhase = "idle"
                task.wait(0.2)
            end
        end
    end
end)

local targetPage = Instance.new("Frame")
targetPage.Name = "TPTargetPage"
targetPage.Size = UDim2.fromScale(1, 1)
targetPage.BackgroundTransparency = 1
targetPage.Visible = false
targetPage.Parent = content

local targetBack = smallButton(targetPage, "Back", "‹ BACK",
    UDim2.fromOffset(48, 20), UDim2.fromOffset(0, 0), 8)
local targetOn = smallButton(targetPage, "ToggleON", "● OFF",
    UDim2.fromOffset(58, 20), UDim2.fromOffset(52, 0), 8)
targetOn.BackgroundColor3 = Color3.fromRGB(119, 13, 31)
local targetRefresh = smallButton(targetPage, "Refresh", "↻",
    UDim2.fromOffset(23, 20), UDim2.new(1, -23, 0, 0), 13)
local targetStatus = label(targetPage, "GrabStatus", "OFF | Klik ON lalu pilih pemain",
    UDim2.new(1, -2, 0, 16), UDim2.fromOffset(0, 23),
    Enum.Font.Gotham, MUTED, 7, Enum.TextXAlignment.Left)

local targetList = Instance.new("ScrollingFrame")
targetList.Name = "TargetPlayerList"
targetList.Size = UDim2.new(1, 0, 1, -43)
targetList.Position = UDim2.fromOffset(0, 42)
targetList.BackgroundTransparency = 1
targetList.BorderSizePixel = 0
targetList.ScrollBarThickness = 2
targetList.ScrollBarImageColor3 = RED
targetList.AutomaticCanvasSize = Enum.AutomaticSize.Y
targetList.CanvasSize = UDim2.new()
targetList.Parent = targetPage

local targetLayout = Instance.new("UIListLayout")
targetLayout.Padding = UDim.new(0, 3)
targetLayout.SortOrder = Enum.SortOrder.LayoutOrder
targetLayout.Parent = targetList

local autoGrabStop
local targetArmed = false
local targetBusy = false
local targetPlayer = nil
local targetToken = 0
local targetOrigin = nil
local targetRows = {}

local TP_GRAB_DISTANCE = 3
local TP_GRAB_SETTLE = 0.15
local TP_GRAB_ATTEMPTS = 2
local TP_GRAB_RETRY = 0.25
local TP_GRAB_RETURN_HOLD = 0.5

local function targetGetCharacter(who)
    local character = who and who.Character
    if not character then return nil, nil, nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then return nil, nil, nil end
    return character, humanoid, root
end

local function targetSetStatus(message, color)
    targetStatus.Text = message
    targetStatus.TextColor3 = color or MUTED
end

local function targetSetArmed(value)
    targetArmed = value
    targetOn.Text = value and "● ON" or "● OFF"
    targetOn.BackgroundColor3 = value and Color3.fromRGB(25, 105, 65)
        or Color3.fromRGB(119, 13, 31)
    if value then
        targetSetStatus(targetBusy and "Menjalankan Grab..." or "ON | Pilih nama pemain",
            Color3.fromRGB(100, 220, 150))
    elseif not targetBusy then
        targetSetStatus("OFF | Klik ON lalu pilih pemain")
    end
end

local function targetSetRowState(chosen, active)
    local row = targetRows[chosen]
    if not row or not row.Parent then return end
    row.BackgroundColor3 = active and ACTIVE or ROW
    local playerLabel = row:FindFirstChild("PlayerName")
    if playerLabel then
        playerLabel.TextColor3 = active and Color3.fromRGB(255, 90, 120) or WHITE
    end
end

local function targetValid(chosen, token)
    return gui.Parent ~= nil and targetArmed and targetBusy
        and targetToken == token and targetPlayer == chosen
        and chosen ~= nil and chosen.Parent == Players
        and targetGetCharacter(chosen) ~= nil
end

local function targetWaitValid(chosen, token, duration)
    local elapsed = 0
    while elapsed < duration do
        if not targetValid(chosen, token) then return false end
        local step = math.min(0.05, duration - elapsed)
        task.wait(step)
        elapsed += step
    end
    return targetValid(chosen, token)
end

local function targetFireGrab()
    local character = player.Character
    local events = character and character:FindFirstChild("Events")
    local grabEvent = events and events:FindFirstChild("Grab")
    if not grabEvent or not grabEvent:IsA("RemoteEvent") then
        return false, "Character.Events.Grab tidak ditemukan"
    end
    local ok, err = pcall(function()
        grabEvent:FireServer(false, false, true)
    end)
    if not ok then return false, "Grab error: " .. tostring(err) end
    return true
end

local function targetStop()
    targetArmed = false
    targetToken += 1
    targetBusy = false
    local previous = targetPlayer
    targetPlayer = nil
    if previous then targetSetRowState(previous, false) end
    targetSetArmed(false)
end

local function targetRunOne(chosen)
    if targetBusy or not targetArmed then return end
    local _, _, myRoot = targetGetCharacter(player)
    local _, _, targetRoot = targetGetCharacter(chosen)
    if not myRoot or not targetRoot then
        targetSetStatus("Character / target belum siap", Color3.fromRGB(255, 170, 80))
        return
    end

    targetBusy = true
    targetPlayer = chosen
    targetToken += 1
    local token = targetToken
    targetOrigin = myRoot.CFrame
    targetSetRowState(chosen, true)
    targetSetStatus("Menuju belakang " .. chosen.Name, Color3.fromRGB(100, 220, 150))

    task.spawn(function()
        local completed, failure = false, nil
        local ok, err = pcall(function()
            local _, _, currentTargetRoot = targetGetCharacter(chosen)
            if not currentTargetRoot then failure = "Target tidak siap"; return end
            local behindPosition = currentTargetRoot.Position
                - currentTargetRoot.CFrame.LookVector * TP_GRAB_DISTANCE
            local behindCFrame = CFrame.lookAt(behindPosition,
                behindPosition + currentTargetRoot.CFrame.LookVector,
                currentTargetRoot.CFrame.UpVector)
            local currentCharacter = player.Character
            if not currentCharacter then failure = "Character sendiri hilang"; return end
            currentCharacter:PivotTo(behindCFrame)

            if not targetWaitValid(chosen, token, TP_GRAB_SETTLE) then
                failure = "Aksi dibatalkan / target tidak valid"; return
            end

            for attempt = 1, TP_GRAB_ATTEMPTS do
                if not targetValid(chosen, token) then
                    failure = "Aksi dibatalkan / target tidak valid"; return
                end
                local sent, reason = targetFireGrab()
                if not sent then failure = reason; return end
                targetSetStatus("Grab " .. attempt .. "/" .. TP_GRAB_ATTEMPTS .. " | tanpa Follow",
                    Color3.fromRGB(100, 220, 150))
                if attempt < TP_GRAB_ATTEMPTS
                    and not targetWaitValid(chosen, token, TP_GRAB_RETRY) then
                    failure = "Aksi dibatalkan / target tidak valid"; return
                end
            end
            completed = true
        end)
        if not ok then failure = tostring(err) end

        if completed and targetArmed and targetToken == token then
            targetSetStatus("Grab selesai | tahan 0,5 detik", Color3.fromRGB(100, 220, 150))
            task.wait(TP_GRAB_RETURN_HOLD)
        end

        if targetToken == token then
            local currentCharacter = player.Character
            if currentCharacter and targetOrigin then
                pcall(function() currentCharacter:PivotTo(targetOrigin) end)
            end
            targetOrigin = nil
            targetSetRowState(chosen, false)
            targetBusy = false
            targetPlayer = nil
            if completed then
                targetSetStatus("Selesai | siap klik target lagi", Color3.fromRGB(100, 220, 150))
            else
                targetSetStatus((failure or "Tidak selesai") .. " | posisi dikembalikan",
                    Color3.fromRGB(255, 170, 80))
            end
        end
    end)
end

function refreshTargetPlayers()
    for _, child in ipairs(targetList:GetChildren()) do
        if child:IsA("TextButton") and child.Name:sub(1, 10) == "TargetRow_" then
            child:Destroy()
        end
    end
    targetRows = {}
    local targets = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then table.insert(targets, p) end
    end
    table.sort(targets, function(a, b)
        return string.lower(a.DisplayName .. a.Name) < string.lower(b.DisplayName .. b.Name)
    end)

    for i = 1, math.max(8, #targets) do
        local chosen = targets[i]
        local row = Instance.new("TextButton")
        row.Name = "TargetRow_" .. (chosen and tostring(chosen.UserId) or ("Empty" .. i))
        row.LayoutOrder = i
        row.Size = UDim2.new(1, -1, 0, 25)
        row.BackgroundColor3 = chosen and chosen == targetPlayer and targetBusy and ACTIVE or ROW
        row.BackgroundTransparency = chosen and 0 or 0.48
        row.BorderSizePixel = 0
        row.Text = ""
        row.AutoButtonColor = false
        row.Active = chosen ~= nil
        row.Parent = targetList
        corner(row, 7)
        local nameText = chosen and (chosen.DisplayName .. "  (@" .. chosen.Name .. ")")
            or "— Slot kosong —"
        local name = label(row, "PlayerName", nameText,
            UDim2.new(1, -10, 1, 0), UDim2.fromOffset(6, 0),
            Enum.Font.GothamBold, chosen and WHITE or MUTED, 7, Enum.TextXAlignment.Left)
        name.TextTruncate = Enum.TextTruncate.AtEnd
        if chosen then
            targetRows[chosen] = row
            local thisTarget = chosen
            row.Activated:Connect(function()
                if thisTarget.Parent ~= Players then refreshTargetPlayers(); return end
                if not targetArmed then
                    targetSetStatus("Klik ON dahulu", Color3.fromRGB(255, 170, 80))
                    return
                end
                if targetBusy then
                    targetSetStatus("Satu aksi sedang berjalan", Color3.fromRGB(255, 170, 80))
                    return
                end
                if autoGrabStop then autoGrabStop() end
                targetRunOne(thisTarget)
            end)
        end
    end
end

targetOn.Activated:Connect(function()
    if targetBusy then
        targetArmed = false
        targetToken += 1
        local previous = targetPlayer
        local currentCharacter = player.Character
        if currentCharacter and targetOrigin then
            pcall(function() currentCharacter:PivotTo(targetOrigin) end)
        end
        targetOrigin = nil
        if previous then targetSetRowState(previous, false) end
        targetPlayer = nil
        targetBusy = false
        targetOn.Text = "● OFF"
        targetOn.BackgroundColor3 = Color3.fromRGB(119, 13, 31)
        targetSetStatus("Dibatalkan | posisi dikembalikan", Color3.fromRGB(255, 170, 80))
        return
    end
    targetSetArmed(not targetArmed)
end)
targetBack.Activated:Connect(function()
    targetStop()
    targetPage.Visible = false
    home.Visible = true
end)
targetRefresh.Activated:Connect(refreshTargetPlayers)
featureButtons[1].Text = "◎  TP GRAB     ›"
featureButtons[1].Activated:Connect(function()
    home.Visible = false
    targetPage.Visible = true
    refreshTargetPlayers()
end)

Players.PlayerAdded:Connect(function()
    task.defer(function()
        if gui.Parent then
            refreshPlayers()
            refreshTargetPlayers()
        end
    end)
end)
Players.PlayerRemoving:Connect(function(leaving)
    if leaving == targetPlayer then
        targetToken += 1
        targetBusy = false
        targetPlayer = nil
        targetOrigin = nil
        targetSetArmed(false)
    end
    task.defer(function()
        if gui.Parent then
            refreshPlayers()
            refreshTargetPlayers()
        end
    end)
end)

task.defer(refreshTargetPlayers)
task.delay(0.75, function()
    if gui.Parent then refreshTargetPlayers() end
end)

local autoGrabPage = Instance.new("Frame")
autoGrabPage.Name = "AutoGrabTargetPage"
autoGrabPage.Size = UDim2.fromScale(1, 1)
autoGrabPage.BackgroundTransparency = 1
autoGrabPage.Visible = false
autoGrabPage.Parent = content

local autoGrabBack = smallButton(autoGrabPage, "Back", "‹ BACK",
    UDim2.fromOffset(48, 20), UDim2.fromOffset(0, 0), 8)
local autoGrabRefresh = smallButton(autoGrabPage, "Refresh", "↻",
    UDim2.fromOffset(23, 20), UDim2.new(1, -23, 0, 0), 13)

local autoGrabList = Instance.new("ScrollingFrame")
autoGrabList.Name = "AutoGrabPlayerList"
autoGrabList.Size = UDim2.new(1, 0, 1, -24)
autoGrabList.Position = UDim2.fromOffset(0, 24)
autoGrabList.BackgroundTransparency = 1
autoGrabList.BorderSizePixel = 0
autoGrabList.ScrollBarThickness = 2
autoGrabList.ScrollBarImageColor3 = RED
autoGrabList.AutomaticCanvasSize = Enum.AutomaticSize.Y
autoGrabList.CanvasSize = UDim2.new()
autoGrabList.Parent = autoGrabPage

local autoGrabLayout = Instance.new("UIListLayout")
autoGrabLayout.Padding = UDim.new(0, 3)
autoGrabLayout.SortOrder = Enum.SortOrder.LayoutOrder
autoGrabLayout.Parent = autoGrabList

local autoGrabEnabled = false
local autoGrabSelectedPlayer = nil
local autoGrabToken = 0
local autoGrabStartCFrame = nil
local autoGrabRows = {}

local AUTO_GRAB_ATTEMPTS = 4
local AUTO_GRAB_ATTEMPT_DELAY = 0.18
local AUTO_GRAB_BEFORE_DELAY = 0.035
local AUTO_GRAB_HOLD_TIME = 1.5
local AUTO_GRAB_RETURN_DELAY = 0.15
local AUTO_GRAB_CYCLE_DELAY = 0.35
local AUTO_GRAB_DROP_RADIUS = 6
local AUTO_GRAB_BEHIND_DISTANCE = 2.5
local AUTO_GRAB_BEHIND_HEIGHT = 0.15
local AUTO_GRAB_LEAD_TIME = 0.10
local AUTO_GRAB_MAX_LEAD = 1.25
local AUTO_GRAB_DROP_NAMES = {
    Cube=true, Token=true, Candy=true, Present=true, Ornament=true, Egg=true
}

local function autoGrabGetCharacter(targetPlayer)
    targetPlayer = targetPlayer or player
    local character = targetPlayer.Character
    if not character then return nil, nil, nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then
        return nil, nil, nil
    end
    return character, humanoid, root
end

local function autoGrabTeleport(cframe)
    local character = player.Character
    if not character or not cframe then return false end
    return pcall(function()
        character:PivotTo(cframe)
    end)
end

local function autoGrabTargetValid(target, token)
    local _, _, root = autoGrabGetCharacter(target)
    return gui.Parent ~= nil and autoGrabEnabled and autoGrabToken == token
        and autoGrabSelectedPlayer == target and target ~= nil
        and target.Parent == Players and root ~= nil
end

local function autoGrabTeleportBehind(targetRoot)
    if not targetRoot or not targetRoot.Parent then return false end
    local velocity = targetRoot.AssemblyLinearVelocity
    local lead = Vector3.new(velocity.X, 0, velocity.Z) * AUTO_GRAB_LEAD_TIME
    if lead.Magnitude > AUTO_GRAB_MAX_LEAD then
        lead = lead.Unit * AUTO_GRAB_MAX_LEAD
    end
    local predictedPosition = targetRoot.Position + lead
    local behindPosition = predictedPosition
        - targetRoot.CFrame.LookVector * AUTO_GRAB_BEHIND_DISTANCE
        + Vector3.new(0, AUTO_GRAB_BEHIND_HEIGHT, 0)
    return autoGrabTeleport(CFrame.lookAt(behindPosition, predictedPosition))
end

local function autoGrabNearbyDrop()
    local _, _, root = autoGrabGetCharacter(player)
    if not root then return true, "character unavailable" end
    local ok, result = pcall(function()
        for _, item in ipairs(workspace:GetDescendants()) do
            if item:IsA("BasePart") and AUTO_GRAB_DROP_NAMES[item.Name] then
                local ancestor = item.Parent
                local belongsToCharacter = false
                while ancestor and ancestor ~= workspace do
                    if ancestor:IsA("Model") and Players:GetPlayerFromCharacter(ancestor) then
                        belongsToCharacter = true
                        break
                    end
                    ancestor = ancestor.Parent
                end
                if not belongsToCharacter
                    and (item.Position - root.Position).Magnitude <= AUTO_GRAB_DROP_RADIUS then
                    return item.Name
                end
            end
        end
        return nil
    end)
    if not ok then return true, "drop scan failed" end
    if result then return true, "nearby drop: " .. tostring(result) end
    return false, nil
end

local function autoGrabFire()
    local replicatedStorage = game:GetService("ReplicatedStorage")
    local localEvents = replicatedStorage:FindFirstChild("LocalEvents")
    local grabEvent = localEvents and localEvents:FindFirstChild("Grab")
    if not grabEvent or not grabEvent:IsA("BindableEvent") then
        return false, "LocalEvents.Grab unavailable"
    end
    local blocked, reason = autoGrabNearbyDrop()
    if blocked then return false, "Grab skipped: " .. tostring(reason) end
    local ok, err = pcall(function()
        grabEvent:Fire()
    end)
    if not ok then return false, "Grab failed: " .. tostring(err) end
    return true, "Grab called"
end

autoGrabStop = function()
    autoGrabEnabled = false
    autoGrabToken += 1
    local previous = autoGrabSelectedPlayer
    autoGrabSelectedPlayer = nil
    autoGrabStartCFrame = nil
    if previous then
        local row = autoGrabRows[previous]
        if row and row.Parent then
            row.BackgroundColor3 = ROW
            local nameLabel = row:FindFirstChild("PlayerName")
            if nameLabel then nameLabel.TextColor3 = WHITE end
        end
    end
end

local function autoGrabSetRowState(target, active)
    local row = autoGrabRows[target]
    if not row or not row.Parent then return end
    row.BackgroundColor3 = active and ACTIVE or ROW
    local nameLabel = row:FindFirstChild("PlayerName")
    if nameLabel then
        nameLabel.TextColor3 = active and Color3.fromRGB(255, 90, 120) or WHITE
    end
end

local function autoGrabRun(target, token, startCFrame)
    while autoGrabTargetValid(target, token) do
        local _, _, targetRoot = autoGrabGetCharacter(target)
        local _, _, myRoot = autoGrabGetCharacter(player)
        if not targetRoot or not myRoot then break end
        if not autoGrabTeleportBehind(targetRoot) then break end
        task.wait(AUTO_GRAB_BEFORE_DELAY)

        local anyGrabCalled = false
        for attempt = 1, AUTO_GRAB_ATTEMPTS do
            if not autoGrabTargetValid(target, token) then break end
            targetRoot = select(3, autoGrabGetCharacter(target))
            if not targetRoot or not autoGrabTeleportBehind(targetRoot) then break end
            task.wait(AUTO_GRAB_BEFORE_DELAY)
            targetRoot = select(3, autoGrabGetCharacter(target))
            if not targetRoot or not autoGrabTeleportBehind(targetRoot) then break end

            local called = autoGrabFire()
            if called then
                anyGrabCalled = true
            else
                break
            end
            if attempt < AUTO_GRAB_ATTEMPTS then
                task.wait(AUTO_GRAB_ATTEMPT_DELAY)
            end
        end

        if anyGrabCalled and autoGrabTargetValid(target, token) then
            local elapsed = 0
            while elapsed < AUTO_GRAB_HOLD_TIME and autoGrabTargetValid(target, token) do
                local step = math.min(0.1, AUTO_GRAB_HOLD_TIME - elapsed)
                task.wait(step)
                elapsed += step
            end
        end

        if not autoGrabEnabled or autoGrabToken ~= token then break end
        if startCFrame then autoGrabTeleport(startCFrame) end
        task.wait(AUTO_GRAB_RETURN_DELAY)
        task.wait(AUTO_GRAB_CYCLE_DELAY)
    end

    if autoGrabToken == token then
        autoGrabStop()
        task.defer(function()
            if gui.Parent then refreshAutoGrabPlayers() end
        end)
    end
end

local function autoGrabToggle(target)
    if autoGrabEnabled and autoGrabSelectedPlayer == target then
        autoGrabStop()
        return
    end

    targetStop()
    autoGrabStop()

    local _, _, myRoot = autoGrabGetCharacter(player)
    local _, _, targetRoot = autoGrabGetCharacter(target)
    if not myRoot or not targetRoot then
        warn("AUTO GRAB: character or target is not ready.")
        return
    end

    autoGrabSelectedPlayer = target
    autoGrabStartCFrame = myRoot.CFrame
    autoGrabEnabled = true
    autoGrabToken += 1
    local token = autoGrabToken
    autoGrabSetRowState(target, true)
    task.spawn(autoGrabRun, target, token, autoGrabStartCFrame)
end

function refreshAutoGrabPlayers()
    for _, child in ipairs(autoGrabList:GetChildren()) do
        if child:IsA("TextButton") and child.Name:sub(1, 18) == "AutoGrabTargetRow_" then
            child:Destroy()
        end
    end
    autoGrabRows = {}

    local targets = {}
    local seenUserIds = {}
    for _, target in ipairs(Players:GetPlayers()) do
        if target ~= player and not seenUserIds[target.UserId] then
            seenUserIds[target.UserId] = true
            table.insert(targets, target)
        end
    end
    table.sort(targets, function(a, b)
        return string.lower(a.DisplayName .. a.Name) < string.lower(b.DisplayName .. b.Name)
    end)

    for i = 1, math.max(8, #targets) do
        local target = targets[i]
        local selected = target ~= nil and target == autoGrabSelectedPlayer and autoGrabEnabled
        local row = Instance.new("TextButton")
        row.Name = "AutoGrabTargetRow_" .. (target and tostring(target.UserId) or ("Empty_" .. tostring(i)))
        row.LayoutOrder = i
        row.Size = UDim2.new(1, -1, 0, 25)
        row.BackgroundColor3 = selected and ACTIVE or ROW
        row.BackgroundTransparency = target and 0 or 0.48
        row.BorderSizePixel = 0
        row.Text = ""
        row.AutoButtonColor = false
        row.Active = target ~= nil
        row.Parent = autoGrabList
        corner(row, 7)

        local nameText = target
            and (target.DisplayName .. "  (@" .. target.Name .. ")")
            or "— Slot kosong —"
        local nameLabel = label(row, "PlayerName", nameText,
            UDim2.new(1, -10, 1, 0), UDim2.fromOffset(6, 0),
            Enum.Font.GothamBold,
            selected and Color3.fromRGB(255, 90, 120) or (target and WHITE or MUTED),
            7, Enum.TextXAlignment.Left)
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

        if target then
            autoGrabRows[target] = row
            local thisTarget = target
            row.Activated:Connect(function()
                if thisTarget.Parent ~= Players then
                    refreshAutoGrabPlayers()
                    return
                end
                autoGrabToggle(thisTarget)
                refreshAutoGrabPlayers()
            end)
        end
    end
end

autoGrabRefresh.Activated:Connect(refreshAutoGrabPlayers)
autoGrabBack.Activated:Connect(function()
    autoGrabStop()
    autoGrabPage.Visible = false
    home.Visible = true
end)
featureButtons[2].Activated:Connect(function()
    home.Visible = false
    autoGrabPage.Visible = true
    refreshAutoGrabPlayers()
end)

Players.PlayerAdded:Connect(function()
    task.defer(function()
        if gui.Parent then refreshAutoGrabPlayers() end
    end)
end)
Players.PlayerRemoving:Connect(function(leaving)
    if leaving == autoGrabSelectedPlayer then autoGrabStop() end
    task.defer(function()
        if gui.Parent then refreshAutoGrabPlayers() end
    end)
end)

task.defer(refreshAutoGrabPlayers)
task.delay(0.75, function()
    if gui.Parent then refreshAutoGrabPlayers() end
end)

local skyWalkFolder = Instance.new("Folder")
skyWalkFolder.Name = "SKYWALK"
skyWalkFolder.Parent = gui

local skyWalkPage = Instance.new("Frame")
skyWalkPage.Name = "SKYWALK_Page"
skyWalkPage.Size = UDim2.fromScale(1, 1)
skyWalkPage.BackgroundTransparency = 1
skyWalkPage.Visible = false
skyWalkPage.Parent = content

local skyWalkBack = smallButton(skyWalkPage, "SKYWALK_Back", "‹ BACK",
    UDim2.fromOffset(48, 20), UDim2.fromOffset(0, 0), 8)
local skyWalkToggle = smallButton(skyWalkPage, "SKYWALK_Toggle", "SKY PLATFORM  OFF",
    UDim2.new(1, 0, 0, 42), UDim2.fromOffset(0, 34), 10)
skyWalkToggle.TextWrapped = true
local skyWalkInfo = label(skyWalkPage, "SKYWALK_Info",
    "TARGET: 4000 STUDS\nPLATFORM: 250000 x 10 x 250000\nMOVE: JOYSTICK NORMAL",
    UDim2.new(1, 0, 0, 48), UDim2.fromOffset(0, 82),
    Enum.Font.GothamMedium, MUTED, 7, Enum.TextXAlignment.Center)
skyWalkInfo.TextWrapped = true

local SKY_TELEPORT_HEIGHT = 4000
local skyWalkEnabled = false
local skyWalkSavedPivot = nil
local skyWalkSavedPosition = nil
local skyWalkPlatform = nil
local skyWalkHeartbeat = nil

local function skyWalkUpdateButton(isOn, actualHeight)
    if isOn then
        skyWalkToggle.Text = string.format(
            "SKY PLATFORM  ON\nTARGET: %d | ACTUAL: %.0f STUDS",
            SKY_TELEPORT_HEIGHT, actualHeight or 0)
        skyWalkToggle.BackgroundColor3 = Color3.fromRGB(95, 25, 25)
    else
        skyWalkToggle.Text = string.format(
            "SKY PLATFORM  OFF\nTARGET: %d | ACTUAL: --",
            SKY_TELEPORT_HEIGHT)
        skyWalkToggle.BackgroundColor3 = PILL
    end
end

local function skyWalkClearObjects()
    if skyWalkHeartbeat then
        skyWalkHeartbeat:Disconnect()
        skyWalkHeartbeat = nil
    end
    if skyWalkPlatform then
        skyWalkPlatform:Destroy()
        skyWalkPlatform = nil
    end
end

local function skyWalkStop()
    skyWalkEnabled = false
    skyWalkClearObjects()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if character and skyWalkSavedPivot then
        pcall(function()
            character:PivotTo(skyWalkSavedPivot)
            local root = character:FindFirstChild("HumanoidRootPart")
            if root then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end)
    end
    if humanoid then
        humanoid.PlatformStand = false
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
    skyWalkSavedPivot = nil
    skyWalkSavedPosition = nil
    skyWalkUpdateButton(false)
end

local function skyWalkStart()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not character or not root or not humanoid or humanoid.Health <= 0 then
        warn("SKYWALK: character is not ready.")
        return
    end

    skyWalkClearObjects()
    skyWalkSavedPivot = character:GetPivot()
    skyWalkSavedPosition = root.Position
    skyWalkEnabled = true

    local ok = pcall(function()
        character:PivotTo(skyWalkSavedPivot + Vector3.new(0, SKY_TELEPORT_HEIGHT, 0))
    end)
    if not ok then
        skyWalkEnabled = false
        skyWalkSavedPivot = nil
        skyWalkSavedPosition = nil
        skyWalkUpdateButton(false)
        return
    end

    root = character:FindFirstChild("HumanoidRootPart")
    humanoid = character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid then
        skyWalkStop()
        return
    end

    local platformThickness = 10
    local footOffset = humanoid.HipHeight + (root.Size.Y * 0.5)
    local platformTopY = root.Position.Y - footOffset
    skyWalkPlatform = Instance.new("Part")
    skyWalkPlatform.Name = "GELUT_SkyWalkPlatform_V13"
    skyWalkPlatform.Anchored = true
    skyWalkPlatform.Size = Vector3.new(250000, 10, 250000)
    skyWalkPlatform.CFrame = CFrame.new(
        root.Position.X,
        platformTopY - (platformThickness * 0.5),
        root.Position.Z)
    skyWalkPlatform.Transparency = 1
    skyWalkPlatform.CanCollide = true
    skyWalkPlatform.CanTouch = false
    skyWalkPlatform.CanQuery = false
    skyWalkPlatform.CastShadow = false
    skyWalkPlatform.Parent = workspace

    humanoid.PlatformStand = false
    humanoid.AutoRotate = true
    humanoid.Sit = false
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    skyWalkUpdateButton(true, 0)

    skyWalkHeartbeat = RunService.Heartbeat:Connect(function()
        if not skyWalkEnabled then return end
        local currentCharacter = player.Character
        local currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
        local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
        if not currentRoot or not currentHumanoid or currentHumanoid.Health <= 0 or not skyWalkPlatform then
            skyWalkStop()
            return
        end
        skyWalkUpdateButton(true, currentRoot.Position.Y - skyWalkSavedPosition.Y)
    end)
end

skyWalkToggle.Activated:Connect(function()
    if skyWalkEnabled then
        skyWalkStop()
    else
        skyWalkStart()
    end
end)

skyWalkOpen.Activated:Connect(function()
    home.Visible = false
    skyWalkPage.Visible = true
end)
skyWalkBack.Activated:Connect(function()
    skyWalkPage.Visible = false
    home.Visible = true
end)

player.CharacterAdded:Connect(function()
    if skyWalkEnabled then
        skyWalkClearObjects()
        skyWalkEnabled = false
        skyWalkSavedPivot = nil
        skyWalkSavedPosition = nil
        skyWalkUpdateButton(false)
    end
end)

gui.Destroying:Connect(function()
    skyWalkEnabled = false
    skyWalkClearObjects()
end)

local playerESPEnabled = false
local espObjects = {}

local function findPlayerStat(targetPlayer, statName)
    local variants = {
        statName,
        string.gsub(statName, " ", ""),
        string.gsub(statName, " ", "_")
    }

    local function checkObject(obj)
        for _, variant in ipairs(variants) do
            if string.lower(obj.Name) == string.lower(variant)
                and (obj:IsA("IntValue") or obj:IsA("NumberValue")) then
                return obj.Value
            end
        end
        return nil
    end

    for _, obj in ipairs(targetPlayer:GetDescendants()) do
        local value = checkObject(obj)
        if value ~= nil then return value end
    end

    for _, variant in ipairs(variants) do
        local value = targetPlayer:GetAttribute(variant)
        if value ~= nil then return value end
        if targetPlayer.Character then
            value = targetPlayer.Character:GetAttribute(variant)
            if value ~= nil then return value end
        end
    end

    local pGui = targetPlayer:FindFirstChild("PlayerGui")
    if pGui then
        for _, obj in ipairs(pGui:GetDescendants()) do
            local value = checkObject(obj)
            if value ~= nil then return value end
        end
    end

    local replicatedStorage = game:GetService("ReplicatedStorage")
    for _, obj in ipairs(replicatedStorage:GetDescendants()) do
        if string.find(string.lower(obj.Name), string.lower(targetPlayer.Name), 1, true) then
            for _, child in ipairs(obj:GetDescendants()) do
                local value = checkObject(child)
                if value ~= nil then return value end
            end
        end
    end
    return "?"
end

local function findStatAny(targetPlayer, names)
    for _, name in ipairs(names) do
        local value = findPlayerStat(targetPlayer, name)
        if value ~= "?" then return value end
    end
    return "?"
end

local function createPlayerStatsESP(targetPlayer)
    if targetPlayer == player or espObjects[targetPlayer] then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "rEmPlayerStatsHighlight"
    highlight.FillColor = Color3.fromRGB(0, 225, 245)
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.65
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "rEmPlayerStatsText"
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0, 190, 0, 76)
    billboard.StudsOffset = Vector3.new(0, 3.2, 0)

    local statsLabel = Instance.new("TextLabel")
    statsLabel.Name = "Stats"
    statsLabel.Parent = billboard
    statsLabel.Size = UDim2.fromScale(1, 1)
    statsLabel.BackgroundTransparency = 1
    statsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    statsLabel.TextStrokeTransparency = 0
    statsLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    statsLabel.Font = Enum.Font.GothamBold
    statsLabel.TextSize = 10
    statsLabel.TextWrapped = true
    statsLabel.TextYAlignment = Enum.TextYAlignment.Bottom

    local playerIndex = 0
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.UserId <= targetPlayer.UserId then
            playerIndex += 1
        end
    end
    billboard.StudsOffset = Vector3.new(0, 3.2 + ((playerIndex % 4) * 0.8), 0)

    espObjects[targetPlayer] = {
        highlight = highlight,
        billboard = billboard,
        label = statsLabel
    }
end

local function removePlayerStatsESP(targetPlayer)
    local entry = espObjects[targetPlayer]
    if not entry then return end
    entry.highlight:Destroy()
    entry.billboard:Destroy()
    espObjects[targetPlayer] = nil
end

local function setPlayerESPEnabled(enabled)
    playerESPEnabled = enabled
    featureButtons[3].Text = "●  ESP PLAYER     " .. (enabled and "ON" or "OFF")
    featureButtons[3].BackgroundColor3 = enabled and ACTIVE or PILL
    if not enabled then
        for _, entry in pairs(espObjects) do
            entry.highlight.Parent = nil
            entry.billboard.Parent = nil
        end
    end
end

for _, targetPlayer in ipairs(Players:GetPlayers()) do
    createPlayerStatsESP(targetPlayer)
end

Players.PlayerAdded:Connect(function(targetPlayer)
    createPlayerStatsESP(targetPlayer)
end)

Players.PlayerRemoving:Connect(function(targetPlayer)
    removePlayerStatsESP(targetPlayer)
end)

featureButtons[3].Activated:Connect(function()
    setPlayerESPEnabled(not playerESPEnabled)
end)

task.spawn(function()
    while gui.Parent do
        for targetPlayer, entry in pairs(espObjects) do
            if targetPlayer.Parent ~= Players then
                removePlayerStatsESP(targetPlayer)
            elseif playerESPEnabled then
                local character = targetPlayer.Character
                local root = character and character:FindFirstChild("HumanoidRootPart")
                if character and root then
                    entry.highlight.Parent = character
                    entry.billboard.Parent = root

                    local sizeVal = findStatAny(targetPlayer, {"Size"})
                    local maxVal = findStatAny(targetPlayer, {"MaxSize", "Max Size", "Max", "Capacity"})
                    local multiVal = findStatAny(targetPlayer, {"Size Multiplier", "Multiplier", "Multi"})
                    local eatVal = findStatAny(targetPlayer, {"eat speed", "eat level"})
                    local hum = character:FindFirstChildOfClass("Humanoid")
                    local walkSpeed = hum and math.floor(hum.WalkSpeed) or 16

                    entry.label.Text = string.format(
                        "[%s]\nSize: %s / %s\nMulti: %s | Eat: %s\nWalkSpeed: %s",
                        targetPlayer.Name,
                        tostring(sizeVal),
                        tostring(maxVal),
                        tostring(multiVal),
                        tostring(eatVal),
                        tostring(walkSpeed)
                    )
                else
                    entry.highlight.Parent = nil
                    entry.billboard.Parent = nil
                end
            else
                entry.highlight.Parent = nil
                entry.billboard.Parent = nil
            end
        end
        task.wait(1)
    end

    for targetPlayer in pairs(espObjects) do
        removePlayerStatsESP(targetPlayer)
    end
end)

local antiAnchorEnabled = false
local antiAnchorConnection = nil

local function setAntiAnchorEnabled(enabled)
    antiAnchorEnabled = enabled
    featureButtons[4].Text = "⚓  ANTI ANCHOR     " .. (enabled and "ON" or "OFF")
    featureButtons[4].BackgroundColor3 = enabled and ACTIVE or PILL

    if antiAnchorConnection then
        antiAnchorConnection:Disconnect()
        antiAnchorConnection = nil
    end

    if enabled then
        antiAnchorConnection = RunService.RenderStepped:Connect(function()
            if not gui.Parent or not antiAnchorEnabled then return end
            local character = player.Character
            if not character then return end

            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") and part.Anchored then
                    part.Anchored = false
                end
            end
        end)
    end
end

featureButtons[4].Activated:Connect(function()
    setAntiAnchorEnabled(not antiAnchorEnabled)
end)

local flightEnabled = false
local flightSpeed = 60
local flyBodyVelocity = nil

featureButtons[5].Size = UDim2.new(1, -42, 0, 20)
featureButtons[5].TextSize = 7
featureButtons[5].Text = "✈  FLIGHT MODE     OFF"

local flightSpeedBox = Instance.new("TextBox")
flightSpeedBox.Name = "FlightSpeedValue"
flightSpeedBox.Size = UDim2.fromOffset(38, 18)
flightSpeedBox.AnchorPoint = Vector2.new(0.5, 0.5)
flightSpeedBox.Position = UDim2.new(
    1, -19,
    featureButtons[5].Position.Y.Scale,
    featureButtons[5].Position.Y.Offset + (featureButtons[5].Size.Y.Offset / 2)
)
flightSpeedBox.BackgroundColor3 = PILL
flightSpeedBox.BorderSizePixel = 0
flightSpeedBox.Text = tostring(flightSpeed)
flightSpeedBox.PlaceholderText = "Speed"
flightSpeedBox.TextColor3 = WHITE
flightSpeedBox.PlaceholderColor3 = MUTED
flightSpeedBox.TextSize = 8
flightSpeedBox.Font = Enum.Font.GothamBold
flightSpeedBox.ClearTextOnFocus = false
flightSpeedBox.MultiLine = false
flightSpeedBox.TextXAlignment = Enum.TextXAlignment.Center
flightSpeedBox.Parent = home
corner(flightSpeedBox, 7)

local flightSpeedStroke = Instance.new("UIStroke")
flightSpeedStroke.Color = RED
flightSpeedStroke.Thickness = 1
flightSpeedStroke.Transparency = 0.35
flightSpeedStroke.Parent = flightSpeedBox

flightSpeedBox.FocusLost:Connect(function()
    local entered = tonumber(flightSpeedBox.Text)
    if entered then
        flightSpeed = math.clamp(math.floor(entered), 1, 1000)
    end
    flightSpeedBox.Text = tostring(flightSpeed)
end)
local flyBodyGyro = nil

local function setFlightEnabled(enabled)
    flightEnabled = enabled
    featureButtons[5].Text = "✈  FLIGHT MODE  " .. (enabled and "ON" or "OFF")
    featureButtons[5].BackgroundColor3 = enabled and ACTIVE or PILL

    if not enabled then
        if flyBodyVelocity then
            pcall(function() flyBodyVelocity:Destroy() end)
            flyBodyVelocity = nil
        end
        if flyBodyGyro then
            pcall(function() flyBodyGyro:Destroy() end)
            flyBodyGyro = nil
        end
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.PlatformStand then
            humanoid.PlatformStand = false
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end
end

featureButtons[5].Activated:Connect(function()
    setFlightEnabled(not flightEnabled)
end)

task.spawn(function()
    while gui.Parent do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if flightEnabled and root and humanoid and humanoid.Health > 0 then
            humanoid.PlatformStand = true

            if not flyBodyVelocity or flyBodyVelocity.Parent ~= root then
                if flyBodyVelocity then pcall(function() flyBodyVelocity:Destroy() end) end
                if flyBodyGyro then pcall(function() flyBodyGyro:Destroy() end) end

                flyBodyVelocity = Instance.new("BodyVelocity")
                flyBodyVelocity.Name = "GELUT_FlightVelocity"
                flyBodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                flyBodyVelocity.Velocity = Vector3.zero
                flyBodyVelocity.Parent = root

                flyBodyGyro = Instance.new("BodyGyro")
                flyBodyGyro.Name = "GELUT_FlightGyro"
                flyBodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
                flyBodyGyro.P = 50000
                flyBodyGyro.D = 500
                flyBodyGyro.CFrame = root.CFrame
                flyBodyGyro.Parent = root
            end

            local camera = workspace.CurrentCamera
            local cameraCFrame = camera and camera.CFrame or root.CFrame
            local worldMove = humanoid.MoveDirection
            local targetVelocity = Vector3.zero

            if worldMove.Magnitude > 0.05 then
                targetVelocity = worldMove.Unit * flightSpeed
            end

            if not UIS.TouchEnabled then
                if UIS:IsKeyDown(Enum.KeyCode.Space) then
                    targetVelocity += Vector3.new(0, flightSpeed, 0)
                end
                if UIS:IsKeyDown(Enum.KeyCode.LeftShift)
                    or UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
                    targetVelocity -= Vector3.new(0, flightSpeed, 0)
                end
            else
                if humanoid.Jump then
                    targetVelocity += Vector3.new(0, flightSpeed * 0.8, 0)
                end
            end

            flyBodyVelocity.Velocity = targetVelocity
            flyBodyGyro.CFrame = cameraCFrame
        else
            if flyBodyVelocity then
                pcall(function() flyBodyVelocity:Destroy() end)
                flyBodyVelocity = nil
            end
            if flyBodyGyro then
                pcall(function() flyBodyGyro:Destroy() end)
                flyBodyGyro = nil
            end
            if humanoid and humanoid.PlatformStand then
                humanoid.PlatformStand = false
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
        task.wait()
    end

    if flyBodyVelocity then pcall(function() flyBodyVelocity:Destroy() end) end
    if flyBodyGyro then pcall(function() flyBodyGyro:Destroy() end) end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid.PlatformStand = false end
end)

local runSpeedEnabled = false
local runSpeedValue = 100
local runSpeedConnection = nil

featureButtons[6].Size = UDim2.new(1, -42, 0, 20)
featureButtons[6].TextSize = 7
featureButtons[6].Text = "▯  RUN SPEED  OFF"

local runSpeedBox = Instance.new("TextBox")
runSpeedBox.Name = "RunSpeedValue"
runSpeedBox.Size = UDim2.fromOffset(38, 18)
runSpeedBox.AnchorPoint = Vector2.new(0.5, 0.5)
runSpeedBox.Position = UDim2.new(
    1, -19,
    featureButtons[6].Position.Y.Scale,
    featureButtons[6].Position.Y.Offset + (featureButtons[6].Size.Y.Offset / 2)
)
runSpeedBox.BackgroundColor3 = PILL
runSpeedBox.BorderSizePixel = 0
runSpeedBox.Text = tostring(runSpeedValue)
runSpeedBox.PlaceholderText = "Speed"
runSpeedBox.TextColor3 = WHITE
runSpeedBox.PlaceholderColor3 = MUTED
runSpeedBox.TextSize = 8
runSpeedBox.Font = Enum.Font.GothamBold
runSpeedBox.ClearTextOnFocus = false
runSpeedBox.MultiLine = false
runSpeedBox.TextXAlignment = Enum.TextXAlignment.Center
runSpeedBox.Parent = home
corner(runSpeedBox, 7)

local runSpeedStroke = Instance.new("UIStroke")
runSpeedStroke.Color = RED
runSpeedStroke.Thickness = 1
runSpeedStroke.Transparency = 0.35
runSpeedStroke.Parent = runSpeedBox

runSpeedBox.FocusLost:Connect(function()
    local entered = tonumber(runSpeedBox.Text)
    if entered and entered >= 0 and entered < math.huge then
        runSpeedValue = entered
    end
    runSpeedBox.Text = tostring(runSpeedValue)
end)

local function setRunSpeedEnabled(enabled)
    runSpeedEnabled = enabled
    featureButtons[6].Text = "▯  RUN SPEED  " .. (enabled and "ON" or "OFF")
    featureButtons[6].BackgroundColor3 = enabled and ACTIVE or PILL

    if runSpeedConnection then
        runSpeedConnection:Disconnect()
        runSpeedConnection = nil
    end

    if enabled then
        runSpeedConnection = RunService.Heartbeat:Connect(function(delta)
            if not gui.Parent or not runSpeedEnabled then return end
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if humanoid and root and humanoid.Health > 0 then
                root.Anchored = false
                local moveDirection = humanoid.MoveDirection
                if moveDirection.Magnitude > 0 then
                    local nextPosition = root.Position + moveDirection * runSpeedValue * delta
                    root.CFrame = CFrame.new(nextPosition, nextPosition + root.CFrame.LookVector)
                end
            end
        end)
    end
end

featureButtons[6].Activated:Connect(function()
    setRunSpeedEnabled(not runSpeedEnabled)
end)

local bigPlatformEnabled = false
local bigPlatformPart = nil

local function createBigPlatform()
    if bigPlatformPart and bigPlatformPart.Parent then return end

    local oldPlatform = workspace:FindFirstChild("ETW_DRAMA_BigPlatform")
    if oldPlatform then
        pcall(function() oldPlatform:Destroy() end)
    end

    local part = Instance.new("Part")
    part.Name = "ETW_DRAMA_BigPlatform"
    part.Size = Vector3.new(180000, 10, 180000)
    part.Anchored = true
    part.CanCollide = true
    part.Transparency = 1
    part.Material = Enum.Material.Fabric
    part.Position = Vector3.new(0, -6, 0)
    part.Parent = workspace
    bigPlatformPart = part
end

local function removeBigPlatform()
    if bigPlatformPart then
        pcall(function() bigPlatformPart:Destroy() end)
        bigPlatformPart = nil
    end
end

local function setBigPlatformEnabled(enabled)
    bigPlatformEnabled = enabled
    featureButtons[7].Text = "□  BIG PLATFORM  " .. (enabled and "ON" or "OFF")
    featureButtons[7].BackgroundColor3 = enabled and ACTIVE or PILL

    if enabled then
        createBigPlatform()
    else
        removeBigPlatform()
    end
end

featureButtons[7].Activated:Connect(function()
    setBigPlatformEnabled(not bigPlatformEnabled)
end)

player.CharacterAdded:Connect(function()
    if bigPlatformEnabled then
        task.defer(createBigPlatform)
    end
end)

local antiVoidEnabled = false
local antiVoidConnection = nil

local function setAntiVoidEnabled(enabled)
    antiVoidEnabled = enabled
    featureButtons[8].Text = "⦿  ANTI VOID  " .. (enabled and "ON" or "OFF")
    featureButtons[8].BackgroundColor3 = enabled and ACTIVE or PILL

    if antiVoidConnection then
        antiVoidConnection:Disconnect()
        antiVoidConnection = nil
    end

    if enabled then
        antiVoidConnection = RunService.Heartbeat:Connect(function()
            if not gui.Parent or not antiVoidEnabled then return end
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if root and humanoid and humanoid.Health > 0 and root.Position.Y < -50 then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                root.CFrame = CFrame.new(0, 50, 0)
            end
        end)
    end
end

featureButtons[8].Activated:Connect(function()
    setAntiVoidEnabled(not antiVoidEnabled)
end)

local wallClipEnabled = false
local wallClipConnection = nil
local wallClipOriginal = setmetatable({}, {__mode = "k"})

local function restoreWallClipParts()
    for part, originalValue in pairs(wallClipOriginal) do
        if part and part.Parent then
            pcall(function() part.CanCollide = originalValue end)
        end
        wallClipOriginal[part] = nil
    end
end

local function setWallClipEnabled(enabled)
    wallClipEnabled = enabled
    featureButtons[9].Text = "▦  WALL CLIP  " .. (enabled and "ON" or "OFF")
    featureButtons[9].BackgroundColor3 = enabled and ACTIVE or PILL

    if wallClipConnection then
        wallClipConnection:Disconnect()
        wallClipConnection = nil
    end

    if not enabled then
        restoreWallClipParts()
        return
    end

    wallClipConnection = RunService.Stepped:Connect(function()
        if not gui.Parent or not wallClipEnabled then return end
        local character = player.Character
        if not character then return end

        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                if wallClipOriginal[part] == nil then
                    wallClipOriginal[part] = part.CanCollide
                end
                if part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end)
end

featureButtons[9].Activated:Connect(function()
    setWallClipEnabled(not wallClipEnabled)
end)

player.CharacterAdded:Connect(function()
    if wallClipEnabled then
        restoreWallClipParts()
    end
end)

local minimized = false
minimize.Activated:Connect(function()
    minimized = not minimized
    content.Visible = not minimized
    footerTitle.Visible = not minimized
    creator.Visible = not minimized
    panel.Size = minimized and UDim2.fromOffset(150, 48) or UDim2.fromOffset(150, 290)
    minimize.Text = minimized and "+" or "–"
end)
close.Activated:Connect(function()
    panel.Visible = false
end)

local dragHandle = Instance.new("TextButton")
dragHandle.Name = "MainPanelDragHandle"
dragHandle.Size = UDim2.new(1, -54, 0, 49)
dragHandle.BackgroundTransparency = 1
dragHandle.Text = ""
dragHandle.AutoButtonColor = false
dragHandle.ZIndex = 5
dragHandle.Parent = panel
minimize.ZIndex = 7
close.ZIndex = 7

local mainDragging, mainInput = false, nil
local mainStart, mainPosition
dragHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        mainDragging = true
        mainInput = input
        mainStart = input.Position
        mainPosition = panel.Position
    end
end)
UIS.InputChanged:Connect(function(input)
    if mainDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - mainStart
        panel.Position = UDim2.new(mainPosition.X.Scale, mainPosition.X.Offset + d.X,
            mainPosition.Y.Scale, mainPosition.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(input)
    if input == mainInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
        mainDragging = false
        mainInput = nil
    end
end)

local cube = Instance.new("Frame")
cube.Name = "dEnzMiniCube"
cube.Size = UDim2.fromOffset(50, 50)
cube.Position = UDim2.new(0, 22, 0.55, 0)
cube.BackgroundColor3 = DARK
cube.BorderSizePixel = 0
cube.Active = true
cube.Visible = true
cube.ZIndex = 10
cube.Parent = gui
corner(cube, 12)

local cubeBorder = Instance.new("UIStroke")
cubeBorder.Name = "PanelMatchingRedBorder"
cubeBorder.Color = RED
cubeBorder.Thickness = 2.3
cubeBorder.Transparency = 0
cubeBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
cubeBorder.Parent = cube

local cubeText = Instance.new("TextLabel")
cubeText.Name = "dEnzSignatureText"
cubeText.Size = UDim2.fromScale(1, 1)
cubeText.Position = UDim2.fromOffset(0, 0)
cubeText.BackgroundTransparency = 1
cubeText.BorderSizePixel = 0
cubeText.Text = "dEnz"
cubeText.TextColor3 = RED
cubeText.TextTransparency = 0
cubeText.TextSize = 14
cubeText.Font = Enum.Font.GothamBlack
cubeText.TextScaled = false
cubeText.TextXAlignment = Enum.TextXAlignment.Center
cubeText.TextYAlignment = Enum.TextYAlignment.Center
cubeText.ZIndex = 12
cubeText.Parent = cube

local cubeClickArea = Instance.new("TextButton")
cubeClickArea.Name = "CubeDragAndTap"
cubeClickArea.Size = UDim2.fromScale(1, 1)
cubeClickArea.BackgroundTransparency = 1
cubeClickArea.Text = ""
cubeClickArea.AutoButtonColor = false
cubeClickArea.Active = true
cubeClickArea.ZIndex = 13
cubeClickArea.Parent = cube

local cubeDragging, cubeInput, cubeMoved = false, nil, false
local cubeStart, cubePosition
cubeClickArea.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        cubeDragging = true
        cubeMoved = false
        cubeInput = input
        cubeStart = input.Position
        cubePosition = cube.Position
    end
end)
UIS.InputChanged:Connect(function(input)
    if cubeDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - cubeStart
        if math.abs(d.X) > 7 or math.abs(d.Y) > 7 then cubeMoved = true end
        if cubeMoved then
            cube.Position = UDim2.new(cubePosition.X.Scale, cubePosition.X.Offset + d.X,
                cubePosition.Y.Scale, cubePosition.Y.Offset + d.Y)
        end
    end
end)
UIS.InputEnded:Connect(function(input)
    if input == cubeInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
        if cubeDragging and not cubeMoved then panel.Visible = not panel.Visible end
        cubeDragging = false
        cubeInput = nil
    end
end)

print("GELUT combined loaded - original main layout preserved, TP ATTACK integrated.")
