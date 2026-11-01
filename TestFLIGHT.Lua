-- GELUT FLIGHT MODE V9 - 4000 STUDS + DROP RECOVERY (STANDALONE TEST)
-- ON  : simpan posisi awal, lalu PivotTo target ketinggian ke atas.
-- HOVER: tahan ketinggian sambil joystick menggerakkan karakter mendatar.
-- OFF : PivotTo kembali ke posisi awal.
-- Tombol menampilkan ketinggian aktual. Server game dapat mengoreksi atau menolak teleport lokal.
-- Script ini terpisah; tidak mengubah GELUT utama.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("GELUT_FLIGHT_TELEPORT_HOVER_V9")
if oldGui then oldGui:Destroy() end

local TELEPORT_HEIGHT = 4000 -- target uji: 4000 studs
local HORIZONTAL_SPEED = 200 -- gerak mendatar lebih terkendali

local enabled = false
local savedPivot = nil
local savedPosition = nil
local hoverY = nil
local velocity = nil
local heightHold = nil
local gyro = nil
local heartbeatConnection = nil
local lastRecoveryAt = 0
local recoveryTimes = {}

local gui = Instance.new("ScreenGui")
gui.Name = "GELUT_FLIGHT_TELEPORT_HOVER_V9"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "FlightToggle"
button.Size = UDim2.fromOffset(190, 48)
button.Position = UDim2.new(0.5, -95, 0.78, 0)
button.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Text = "FLIGHT MODE  OFF\\nTARGET: 4000 | ACTUAL: --"
button.TextSize = 12
button.TextWrapped = true
button.Font = Enum.Font.GothamBold
button.AutoButtonColor = true
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = button

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(139, 0, 0)
stroke.Thickness = 2
stroke.Parent = button

local function updateFlightButton(stateText, actualHeight)
    if stateText == "ON" then
        button.Text = string.format(
            "FLIGHT MODE  ON\\nTARGET: %d | ACTUAL: %.0f STUDS",
            TELEPORT_HEIGHT,
            actualHeight or 0
        )
        button.BackgroundColor3 = Color3.fromRGB(95, 25, 25)
    else
        button.Text = string.format(
            "FLIGHT MODE  OFF\\nTARGET: %d | ACTUAL: --",
            TELEPORT_HEIGHT
        )
        button.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    end
end

local function clearFlightObjects()
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end
    if velocity then
        velocity:Destroy()
        velocity = nil
    end
    if heightHold then
        heightHold:Destroy()
        heightHold = nil
    end
    if gyro then
        gyro:Destroy()
        gyro = nil
    end
end

local function stopFlight()
    enabled = false
    clearFlightObjects()

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    -- Kembali ke transform awal dengan satu PivotTo.
    if character and savedPivot then
        pcall(function()
            character:PivotTo(savedPivot)
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

    savedPivot = nil
    savedPosition = nil
    hoverY = nil

    updateFlightButton("OFF")
end

local function startFlight()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if not character or not root or not humanoid or humanoid.Health <= 0 then
        return
    end

    clearFlightObjects()

    savedPivot = character:GetPivot()
    savedPosition = root.Position
    hoverY = savedPosition.Y + TELEPORT_HEIGHT

    enabled = true
    updateFlightButton("ON", 0)

    -- Pindahkan seluruh model karakter, bukan hanya root part.
    local targetPivot = savedPivot + Vector3.new(0, TELEPORT_HEIGHT, 0)
    local ok = pcall(function()
        character:PivotTo(targetPivot)
    end)

    if not ok then
        enabled = false
        savedPivot = nil
        hoverY = nil
        updateFlightButton("OFF")
        return
    end

    root = character:FindFirstChild("HumanoidRootPart")
    if not root then
        stopFlight()
        return
    end

    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero

    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    humanoid.PlatformStand = true

    -- Kontrol horizontal dipisah dari penahan ketinggian.
    velocity = Instance.new("BodyVelocity")
    velocity.Name = "GELUT_FlightHorizontalVelocity_V9"
    velocity.MaxForce = Vector3.new(1e8, 0, 1e8)
    velocity.P = 30000
    velocity.Velocity = Vector3.zero
    velocity.Parent = root

    -- BodyPosition menahan sumbu Y pada target hover.
    heightHold = Instance.new("BodyPosition")
    heightHold.Name = "GELUT_FlightAltitudeHold_V9"
    heightHold.MaxForce = Vector3.new(0, 2e9, 0)
    heightHold.P = 18000
    heightHold.D = 9000
    heightHold.Position = Vector3.new(root.Position.X, hoverY, root.Position.Z)
    heightHold.Parent = root

    gyro = Instance.new("BodyGyro")
    gyro.Name = "GELUT_FlightHoverGyro_V8"
    gyro.MaxTorque = Vector3.new(1e8, 1e8, 1e8)
    gyro.P = 25000
    gyro.D = 800
    gyro.CFrame = root.CFrame
    gyro.Parent = root

    heartbeatConnection = RunService.Heartbeat:Connect(function()
        if not enabled then return end

        local currentCharacter = player.Character
        local currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
        local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")

        if not currentRoot or not currentHumanoid or currentHumanoid.Health <= 0
            or not velocity or not heightHold or not gyro then
            stopFlight()
            return
        end

        -- Gerak mendatar dari joystick; koreksi vertikal aktif terus,
        -- termasuk saat joystick digerakkan.
        local move = currentHumanoid.MoveDirection * HORIZONTAL_SPEED

        -- BodyVelocity hanya mengatur gerakan mendatar.
        velocity.Velocity = Vector3.new(move.X, 0, move.Z)

        -- Pulihkan jika perubahan ukuran/physics menjatuhkan karakter jauh
        -- dari target. Percobaan dibatasi agar tidak berulang tanpa henti
        -- bila server terus mengoreksi posisi lokal.
        local heightError = hoverY - currentRoot.Position.Y
        local now = os.clock()
        if math.abs(heightError) > 150 and (now - lastRecoveryAt) >= 1 then
            for i = #recoveryTimes, 1, -1 do
                if now - recoveryTimes[i] > 10 then
                    table.remove(recoveryTimes, i)
                end
            end

            if #recoveryTimes < 5 then
                lastRecoveryAt = now
                table.insert(recoveryTimes, now)

                currentCharacter:PivotTo(
                    currentCharacter:GetPivot() + Vector3.new(0, heightError, 0)
                )
                currentRoot.AssemblyLinearVelocity = Vector3.zero
                currentRoot.AssemblyAngularVelocity = Vector3.zero
            else
                warn("[GELUT FLIGHT V9] Pemulihan dihentikan: server mungkin mengoreksi teleport.")
            end
        end

        -- BodyPosition mempertahankan Y, sementara X/Z mengikuti karakter.
        heightHold.Position = Vector3.new(
            currentRoot.Position.X,
            hoverY,
            currentRoot.Position.Z
        )

        -- Indikator berada DI DALAM tombol utama agar selalu terlihat.
        updateFlightButton("ON", currentRoot.Position.Y - savedPosition.Y)

        local camera = workspace.CurrentCamera
        if camera then
            gyro.CFrame = CFrame.new(currentRoot.Position, currentRoot.Position + camera.CFrame.LookVector)
        end
    end)
end

button.Activated:Connect(function()
    if enabled then
        stopFlight()
    else
        startFlight()
    end
end)

player.CharacterAdded:Connect(function()
    if enabled then
        clearFlightObjects()
        enabled = false
        savedPivot = nil
        savedPosition = nil
        hoverY = nil
        updateFlightButton("OFF")
    end
end)

gui.Destroying:Connect(function()
    enabled = false
    clearFlightObjects()
end)
