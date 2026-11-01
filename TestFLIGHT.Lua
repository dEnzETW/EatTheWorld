-- GELUT FLIGHT MODE - VERTICAL TELEPORT + HOVER (STANDALONE TEST)
-- ON  : teleport vertikal ke atas, lalu melayang di ketinggian.
-- MOVE: joystick untuk bergerak mendatar.
-- OFF : lepaskan penahan udara agar karakter turun karena gravitasi.
-- Script pengujian terpisah; tidak mengubah GELUT utama.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("GELUT_FLIGHT_TELEPORT_TEST")
if oldGui then
    oldGui:Destroy()
end

local TELEPORT_HEIGHT = 800 -- studs ke atas dari posisi awal (uji)
local HORIZONTAL_SPEED = 600

local enabled = false
local velocity
local gyro
local heartbeatConnection
local savedStartCFrame = nil

local gui = Instance.new("ScreenGui")
gui.Name = "GELUT_FLIGHT_TELEPORT_TEST"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.Parent = playerGui

local button = Instance.new("TextButton")
button.Name = "FlightToggle"
button.Size = UDim2.fromOffset(166, 44)
button.Position = UDim2.new(0.10, -43, 0.48, 0)
button.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Text = "FLIGHT MODE  OFF"
button.TextSize = 13
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

local function stopFlight()
    enabled = false

    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end

    if velocity then
        velocity:Destroy()
        velocity = nil
    end

    if gyro then
        gyro:Destroy()
        gyro = nil
    end

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    -- OFF: teleport kembali ke posisi awal, bukan jatuh perlahan.
    if root and savedStartCFrame then
        root.CFrame = savedStartCFrame
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
    savedStartCFrame = nil

    if humanoid then
        humanoid.PlatformStand = false
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end

    button.Text = "FLIGHT MODE  OFF"
    button.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
end

local function startFlight()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if not root or not humanoid or humanoid.Health <= 0 then
        return
    end

    -- Bersihkan controller lama sebelum mengaktifkan ulang.
    if velocity then velocity:Destroy() velocity = nil end
    if gyro then gyro:Destroy() gyro = nil end
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end

    enabled = true
    savedStartCFrame = root.CFrame
    button.Text = "FLIGHT MODE  ON"
    button.BackgroundColor3 = Color3.fromRGB(95, 25, 25)

    -- Teleport instan ke atas, bukan melompat/naik bertahap.
    root.CFrame = root.CFrame + Vector3.new(0, TELEPORT_HEIGHT, 0)
    root.AssemblyLinearVelocity = Vector3.zero

    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    humanoid.PlatformStand = true

    velocity = Instance.new("BodyVelocity")
    velocity.Name = "GELUT_FlightHoverVelocity"
    velocity.MaxForce = Vector3.new(1e8, 1e8, 1e8)
    velocity.P = 25000
    velocity.Velocity = Vector3.zero
    velocity.Parent = root

    gyro = Instance.new("BodyGyro")
    gyro.Name = "GELUT_FlightHoverGyro"
    gyro.MaxTorque = Vector3.new(1e8, 1e8, 1e8)
    gyro.P = 25000
    gyro.D = 800
    gyro.CFrame = workspace.CurrentCamera and workspace.CurrentCamera.CFrame or root.CFrame
    gyro.Parent = root

    heartbeatConnection = RunService.Heartbeat:Connect(function()
        if not enabled then return end

        local currentCharacter = player.Character
        local currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
        local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")

        if not currentRoot or not currentHumanoid or currentHumanoid.Health <= 0
            or not velocity or not gyro then
            stopFlight()
            return
        end

        -- Joystick menggerakkan karakter mendatar; sumbu Y tetap ditahan.
        local move = currentHumanoid.MoveDirection * HORIZONTAL_SPEED
        velocity.Velocity = Vector3.new(move.X, 0, move.Z)

        local camera = workspace.CurrentCamera
        if camera then
            gyro.CFrame = camera.CFrame
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
        stopFlight()
    end
end)

gui.Destroying:Connect(function()
    stopFlight()
end)
