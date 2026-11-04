--[[
    AUTO GRAB PLAYER - TEST V3.1
    - Select one player.
    - Stay behind the selected player.
    - Reposition if target movement causes a miss (client-side positioning only).
    - Fire Character.Events.Grab ONCE.
    - Hold the attempt for 1.5 seconds.
    - Return to the saved starting position.
    - No auto Eat, Throw, Candy scan, coin scan, or object targeting.

    IMPORTANT:
    The 6-stud value is a client-side correction/proximity threshold.
    It does NOT enlarge the game's server-side Grab hitbox/range.
    Successful carrying must be confirmed in-game.
]]

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GUI_NAME = "AUTO_GRAB_PLAYER_TEST"
local BEHIND_DISTANCE = 2.0
local GRAB_WAIT = 1.5
local CORRECTION_RADIUS = 3
local TRACK_INTERVAL = 0.10

-- Remove only this test's previous UI.
local oldGui
pcall(function()
    if gethui then oldGui = gethui():FindFirstChild(GUI_NAME) end
end)
if not oldGui then oldGui = CoreGui:FindFirstChild(GUI_NAME) end
if not oldGui then oldGui = PlayerGui:FindFirstChild(GUI_NAME) end
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local parented = false
pcall(function()
    if gethui then gui.Parent = gethui(); parented = true end
end)
if not parented then
    pcall(function() gui.Parent = CoreGui; parented = true end)
end
if not parented then gui.Parent = PlayerGui end

local C = {
    bg = Color3.fromRGB(17, 17, 21),
    panel = Color3.fromRGB(29, 28, 34),
    row = Color3.fromRGB(43, 42, 49),
    red = Color3.fromRGB(190, 32, 54),
    white = Color3.fromRGB(245, 243, 247),
    muted = Color3.fromRGB(155, 150, 160),
    green = Color3.fromRGB(80, 190, 120),
    yellow = Color3.fromRGB(235, 190, 75),
}

local function round(obj, radius)
    local u = Instance.new("UICorner")
    u.CornerRadius = UDim.new(0, radius)
    u.Parent = obj
end

local function makeLabel(parent, text, size, pos, textSize, color, font)
    local x = Instance.new("TextLabel")
    x.BackgroundTransparency = 1
    x.Size = size
    x.Position = pos
    x.Text = text
    x.TextColor3 = color or C.white
    x.TextSize = textSize or 10
    x.Font = font or Enum.Font.Gotham
    x.TextXAlignment = Enum.TextXAlignment.Left
    x.TextYAlignment = Enum.TextYAlignment.Center
    x.Parent = parent
    return x
end

local panel = Instance.new("Frame")
panel.Name = "TestPanel"
panel.Size = UDim2.fromOffset(205, 285)
panel.Position = UDim2.new(0.06, 0, 0.22, 0)
panel.BackgroundColor3 = C.bg
panel.BorderSizePixel = 0
panel.Parent = gui
round(panel, 13)

local stroke = Instance.new("UIStroke")
stroke.Color = C.red
stroke.Thickness = 1.5
stroke.Parent = panel

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 31)
header.BackgroundColor3 = C.panel
header.BorderSizePixel = 0
header.Parent = panel
round(header, 12)

makeLabel(
    header, "AUTO GRAB PLAYER  •  TEST V3.1",
    UDim2.new(1, -38, 1, 0), UDim2.fromOffset(9, 0),
    9, C.white, Enum.Font.GothamBold
)

local status = makeLabel(
    panel, "Pilih player untuk satu kali percobaan.",
    UDim2.new(1, -16, 0, 28), UDim2.fromOffset(9, 35),
    8, C.muted
)
status.TextWrapped = true

local busy = false
local attemptId = 0

local function setStatus(message, color)
    if status and status.Parent then
        status.Text = message
        status.TextColor3 = color or C.muted
    end
end

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(23, 22)
close.Position = UDim2.new(1, -28, 0, 4)
close.BackgroundColor3 = C.red
close.BorderSizePixel = 0
close.Text = "×"
close.TextColor3 = C.white
close.TextSize = 16
close.Font = Enum.Font.GothamBold
close.Parent = header
round(close, 6)

close.Activated:Connect(function()
    if busy then
        setStatus("Percobaan sedang berjalan; tunggu sampai selesai.", C.yellow)
        return
    end
    gui:Destroy()
end)

-- Drag panel from header.
do
    local dragging, dragInput, dragStart, startPos

    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = panel.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    header.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input == dragInput
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart

            panel.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local list = Instance.new("ScrollingFrame")
list.Name = "PlayerList"
list.Size = UDim2.new(1, -14, 1, -91)
list.Position = UDim2.fromOffset(7, 65)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 2
list.ScrollBarImageColor3 = C.red
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local refresh = Instance.new("TextButton")
refresh.Size = UDim2.new(1, -14, 0, 21)
refresh.Position = UDim2.new(0, 7, 1, -25)
refresh.BackgroundColor3 = C.panel
refresh.BorderSizePixel = 0
refresh.Text = "REFRESH PLAYER LIST"
refresh.TextColor3 = C.white
refresh.TextSize = 8
refresh.Font = Enum.Font.GothamBold
refresh.Parent = panel
round(refresh, 6)

local function getRoot(plr)
    local char = plr and plr.Character
    if not char then return nil, nil end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")

    if not hum or hum.Health <= 0 or not root then
        return nil, nil
    end

    return char, root
end

local function behindCFrame(targetRoot)
    local pos = targetRoot.Position
        - targetRoot.CFrame.LookVector * BEHIND_DISTANCE

    return CFrame.lookAt(pos, targetRoot.Position)
end

local function moveBehindTarget(target)
    local _, targetRoot = getRoot(target)
    local myChar = LocalPlayer.Character

    if not targetRoot or not myChar then return false end

    local destination = behindCFrame(targetRoot)

    local ok = pcall(function()
        myChar:PivotTo(destination)
    end)

    return ok
end

local function doGrabTest(target)
    if busy then
        setStatus("Satu percobaan masih berjalan.", C.yellow)
        return
    end

    if not target or target == LocalPlayer or target.Parent ~= Players then
        setStatus("Target tidak valid.", C.yellow)
        return
    end

    local myChar, myRoot = getRoot(LocalPlayer)
    local targetChar, targetRoot = getRoot(target)

    if not myChar or not myRoot or not targetChar or not targetRoot then
        setStatus("Karakter kamu atau target belum siap.", C.yellow)
        return
    end

    local startCFrame = myRoot.CFrame

    busy = true
    attemptId += 1

    local thisAttempt = attemptId

    task.spawn(function()
        local function stillCurrent()
            return gui.Parent ~= nil
                and busy
                and attemptId == thisAttempt
                and target.Parent == Players
        end

        setStatus("Mendekati belakang " .. target.DisplayName .. "...", C.yellow)

        if not moveBehindTarget(target) then
            setStatus("Gagal berpindah ke belakang target.", C.yellow)
            busy = false
            return
        end

        task.wait(0.12)

        if not stillCurrent() then
            busy = false
            return
        end

        local replicatedStorage = game:GetService("ReplicatedStorage")
        local localEvents = replicatedStorage:FindFirstChild("LocalEvents")
        local grabEvent = localEvents and localEvents:FindFirstChild("Grab")

        if not grabEvent or not grabEvent:IsA("BindableEvent") then
            pcall(function()
                local c = LocalPlayer.Character
                if c then c:PivotTo(startCFrame) end
            end)

            setStatus("ReplicatedStorage.LocalEvents.Grab BindableEvent tidak ditemukan.", C.yellow)
            busy = false
            return
        end

        local fired, fireErr = pcall(function()
            grabEvent:Fire()
        end)

        if not fired then
            pcall(function()
                local c = LocalPlayer.Character
                if c then c:PivotTo(startCFrame) end
            end)

            setStatus("Grab gagal dipanggil: " .. tostring(fireErr), C.yellow)
            busy = false
            return
        end

        setStatus("Grab dipanggil. Menjaga posisi belakang selama 1,5 detik...", C.yellow)

        local elapsed = 0
        local lastTargetPosition = targetRoot.Position

        while elapsed < GRAB_WAIT and stillCurrent() do
            task.wait(TRACK_INTERVAL)
            elapsed += TRACK_INTERVAL

            local _, latestTargetRoot = getRoot(target)
            if not latestTargetRoot then break end

            local movedDistance = (latestTargetRoot.Position - lastTargetPosition).Magnitude

            if movedDistance >= CORRECTION_RADIUS then
                moveBehindTarget(target)
                lastTargetPosition = latestTargetRoot.Position
            end
        end

        if stillCurrent() then
            setStatus("Waktu Grab selesai. Kembali ke posisi awal...", C.yellow)

            pcall(function()
                local c = LocalPlayer.Character
                if c then c:PivotTo(startCFrame) end
            end)

            task.wait(0.35)

            local _, myRootAfter = getRoot(LocalPlayer)
            local _, targetRootAfter = getRoot(target)

            if myRootAfter and targetRootAfter then
                local distance = (myRootAfter.Position - targetRootAfter.Position).Magnitude

                if distance <= CORRECTION_RADIUS then
                    setStatus(
                        "Jarak setelah kembali kurang dari 3 studs. Periksa apakah target ikut terbawa.",
                        C.green
                    )
                else
                    setStatus(
                        "Grab dipanggil, tetapi target belum terkonfirmasi ikut terbawa. Jarak: "
                            .. math.floor(distance) .. " studs.",
                        C.yellow
                    )
                end
            else
                setStatus("Grab dipanggil; status target belum bisa diperiksa.", C.yellow)
            end
        end

        busy = false
    end)
end

local function refreshPlayers()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    local targets = {}

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            table.insert(targets, plr)
        end
    end

    table.sort(targets, function(a, b)
        return string.lower(a.DisplayName .. a.Name)
            < string.lower(b.DisplayName .. b.Name)
    end)

    for index, target in ipairs(targets) do
        local row = Instance.new("TextButton")
        row.Name = "Target_" .. tostring(target.UserId)
        row.LayoutOrder = index
        row.Size = UDim2.new(1, -2, 0, 27)
        row.BackgroundColor3 = C.row
        row.BorderSizePixel = 0
        row.AutoButtonColor = false
        row.Text = target.DisplayName .. "  (@" .. target.Name .. ")"
        row.TextColor3 = C.white
        row.TextSize = 8
        row.Font = Enum.Font.GothamBold
        row.TextXAlignment = Enum.TextXAlignment.Left
        row.Parent = list

        round(row, 6)

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 7)
        pad.PaddingRight = UDim.new(0, 5)
        pad.Parent = row

        row.Activated:Connect(function()
            doGrabTest(target)
        end)
    end

    if #targets == 0 then
        setStatus("Belum ada player lain di server.")
    else
        setStatus("Ketuk nama player. Satu klik = satu percobaan Grab.")
    end
end

refresh.Activated:Connect(refreshPlayers)

Players.PlayerAdded:Connect(function()
    task.defer(refreshPlayers)
end)

Players.PlayerRemoving:Connect(function()
    task.defer(refreshPlayers)
end)

refreshPlayers()
