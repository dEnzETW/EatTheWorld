-- MountEiger dEnzCreator Safety Guard V5 — UPDATED
-- Base: decoded MountEiger_SafetyGuard_V4_OBF_FIXED2.
-- V5 update: Replace Instance; a new execution shuts down the prior registered instance.
-- Header: dEnzCreator with collapse (-) and close (×) controls.
-- Emergency Stop integration is intentionally omitted per user request.
-- Original V2 and V4 source files remain untouched.

-- MountEiger Safety Guard V4 changelog:
-- 1) Reworked AutoFarm lifecycle cleanup into an idempotent cleanup path.
-- 2) Tracks/disconnects Heartbeat, Humanoid.Died, CharacterAdded and CharacterRemoving connections.
-- 3) Uses bounded character-component waits and generation checks to reject stale respawns.
-- 4) Restores the original Enabled states of LocalChunkManager and Animate.
-- 5) Restores Map/Chunks to their original parent references, not an assumed Workspace parent.
-- 6) Protects Heartbeat work and worker cleanup from runtime errors; preserves existing farm logic/timers.
-- 7) Leaves UI, ESP cadence and remote/event behavior from V3 unchanged.
-- Base: MountEiger_SafetyGuard_V3.txt. Original master remains untouched.

-- MountEiger Safety Guard V2 changelog:
-- 1) ESP polling no longer runs permanently while ESP is OFF.
-- 2) Existing ESP ON/OFF toggle starts and invalidates the update loop.
-- 3) Fixed 1.5-second refresh interval while enabled; no randomized timing.
-- 4) Generation token prevents duplicate loops during rapid ON/OFF toggles.
-- 5) ESP cards are disabled immediately when toggled OFF.
-- Base: MountEiger_SafetyGuard_V1.txt. Original master remains untouched.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
-- ===================== Whitelist System =====================
--==================================================
-- dEnzCreator | REMOTE WHITELIST GATE
--==================================================
local WHITELIST_URL =
    "https://raw.githubusercontent.com/dEnzETW/EatTheWorld/refs/heads/main/WhiteList.lua"

local whitelistOK, whitelistResult = pcall(function()
    local source = game:HttpGet(WHITELIST_URL)
    assert(type(source) == "string" and #source > 0, "Whitelist file kosong")
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


-- ================================================================
-- dEnzCreator | REPLACE INSTANCE GUARD
-- A new execution asks the previous V5 instance to shut down first.
-- Legacy V5 instances without a registered shutdown handler are not
-- force-killed: a clean executor restart is required for first upgrade.
-- ================================================================
local executionEnvironment = _G
if type(getgenv) == "function" then
    local envOK, sharedEnv = pcall(getgenv)
    if envOK and type(sharedEnv) == "table" then
        executionEnvironment = sharedEnv
    end
end

local INSTANCE_KEY = "__DENZCREATOR_MOUNTEIGER_V5_ACTIVE_INSTANCE"
local LEGACY_LOCK_KEY = "__DENZCREATOR_MOUNTEIGER_V5_EXECUTION_LOCK"
local previousInstance = executionEnvironment[INSTANCE_KEY]

if type(previousInstance) == "table" then
    if type(previousInstance.shutdown) ~= "function" then
        warn("[dEnzCreator] Previous instance is still starting or has no cleanup handler. Restart the executor once before using Replace Instance.")
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "dEnzCreator",
                Text = "Instance lama belum memiliki cleanup handler. Restart executor sekali untuk migrasi V5.",
                Duration = 6
            })
        end)
        return
    end

    local shutdownOK, shutdownResult = pcall(previousInstance.shutdown)
    if not shutdownOK or shutdownResult ~= true then
        warn("[dEnzCreator] Replace Instance aborted: previous cleanup did not confirm success.")
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "dEnzCreator",
                Text = "Cleanup instance lama gagal. Eksekusi baru dibatalkan.",
                Duration = 6
            })
        end)
        return
    end
    executionEnvironment[INSTANCE_KEY] = nil
    executionEnvironment[LEGACY_LOCK_KEY] = nil
elseif executionEnvironment[LEGACY_LOCK_KEY] == true then
    -- Older V5 used a permanent boolean lock and had no global cleanup
    -- callback. Do not pretend that destroying its GUI stops its workers.
    warn("[dEnzCreator] Legacy V5 instance detected without a cleanup handler. Restart the executor once before upgrading.")
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "dEnzCreator",
            Text = "Versi V5 lama tidak punya cleanup handler. Restart executor sekali untuk upgrade aman.",
            Duration = 6
        })
    end)
    return
end

local currentInstance = { status = "starting", shutdown = nil }
executionEnvironment[INSTANCE_KEY] = currentInstance
executionEnvironment[LEGACY_LOCK_KEY] = true

local Events = ReplicatedStorage:WaitForChild("Events")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
configPath = LocalPlayer.Name .. "_chi_chi_world_config.json"
-- ===================== Configuration Manager =====================
local config = {
    autofarm = false,
    autoCollectingCubes = false,
    autoClaimRewards = false,
    farmMoving = false,
    showMap = false,
    autoeat = false,
    keepUnanchor = false,
    antiFallEnabled = false,
    slippageEliminationEnabled = false,
    gravityLockEnabled = false,
    platformEnabled = false
}
local function saveConfig()
    local HttpService = game:GetService("HttpService")
    local configData = HttpService:JSONEncode(config)
    local configFolder = LocalPlayer.PlayerGui:FindFirstChild("ChiChiWorldConfig")
    if not configFolder then
        configFolder = Instance.new("Folder")
        configFolder.Name = "ChiChiWorldConfig"
        configFolder.Parent = LocalPlayer.PlayerGui
    end
    local configFile = configFolder:FindFirstChild(configPath)
    if not configFile then
        configFile = Instance.new("StringValue")
        configFile.Name = configPath
        configFile.Parent = configFolder
    end
    configFile.Value = configData
    print("[Configuration Manager] Configuration saved")
end
local function loadConfig()
    local HttpService = game:GetService("HttpService")
    local configFolder = LocalPlayer.PlayerGui:FindFirstChild("ChiChiWorldConfig")
    if configFolder then
        local configFile = configFolder:FindFirstChild(configPath)
        if configFile and configFile.Value ~= "" then
            local success, configData = pcall(function()
                return HttpService:JSONDecode(configFile.Value)
            end)
            if success and configData then
                for key, value in pairs(configData) do
                    if config[key] ~= nil then
                        config[key] = value
                    end
                end
                print("[Configuration Manager] Configuration loaded")
                return true
            end
        end
    end
    print("[Configuration Manager] Config file not found; using defaults")
    return false
end
local function autoSaveConfig()
    saveConfig()
end
loadConfig()
local UI = {}
UI.__index = UI

-- Safety Guard V1: keep UI-owned connections in one lifecycle scope.
function UI:TrackConnection(connection)
    if typeof(connection) ~= "RBXScriptConnection" then
        return connection
    end
    if self._destroyed then
        connection:Disconnect()
        return connection
    end
    self._connections = self._connections or {}
    table.insert(self._connections, connection)
    return connection
end

function UI:CleanupConnections()
    if self._destroyed then return end
    self._destroyed = true
    for _, connection in ipairs(self._connections or {}) do
        if connection and connection.Connected then
            pcall(function() connection:Disconnect() end)
        end
    end
    table.clear(self._connections or {})
    pcall(function() UserInputService.MouseIconEnabled = true end)
end

-- CANGCUD visual theme: dark navy surfaces with restrained purple borders.
UI.Theme = {
    Background = Color3.fromRGB(7, 10, 27),
    Header = Color3.fromRGB(7, 10, 27),
    Border = Color3.fromRGB(83, 99, 226),
    BorderBright = Color3.fromRGB(83, 99, 226),
    Text = Color3.fromRGB(245, 247, 255),
    Muted = Color3.fromRGB(190, 197, 220),
    Off = Color3.fromRGB(15, 20, 43),
    Auto = Color3.fromRGB(17, 103, 190),
    Player = Color3.fromRGB(88, 35, 177),
    Other = Color3.fromRGB(48, 66, 103),
    Row = Color3.fromRGB(17, 22, 48)
}
function UI:NewWindow(title)
    local self = setmetatable({}, UI)
    self._connections = {}
    self._destroyed = false
    self.MainGui = Instance.new("ScreenGui")
    self.MainGui.Name = "ChiChiWorldUI"
    self.MainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    self.MainGui.ResetOnSpawn = false
    self.MainGui.Parent = syn and CoreGui or PlayerGui
    self:TrackConnection(self.MainGui.Destroying:Connect(function()
        self:CleanupConnections()
    end))
    self.Window = Instance.new("Frame")
    self.Window.Name = "MainWindow"
    self.Window.Size = UDim2.new(0, 150, 0, 150)
    self.Window.Position = UDim2.new(0.1, 0, 0.1, 0)
    self.Window.BackgroundColor3 = UI.Theme.Background
    self.Window.BackgroundTransparency = 0
    self.Window.BorderSizePixel = 0
    self.Window.ClipsDescendants = true
    self.Window.Parent = self.MainGui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = self.Window
    local windowStroke = Instance.new("UIStroke")
    windowStroke.Color = UI.Theme.Border
    windowStroke.Thickness = 2
    windowStroke.Parent = self.Window
    self.TitleBar = Instance.new("Frame")
    self.TitleBar.Name = "TitleBar"
    self.TitleBar.Size = UDim2.new(1, 0, 0, 40)
    self.TitleBar.BackgroundColor3 = UI.Theme.Header
    self.TitleBar.Parent = self.Window
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 8)
    titleCorner.Parent = self.TitleBar
    self.TitleText = Instance.new("TextLabel")
    self.TitleText.Name = "TitleText"
    self.TitleText.Size = UDim2.new(1, -66, 1, 0)
    self.TitleText.Position = UDim2.new(0, 8, 0, 0)
    self.TitleText.BackgroundTransparency = 1
    self.TitleText.Text = title
    self.TitleText.Font = Enum.Font.GothamBold
    self.TitleText.TextSize = 14
    self.TitleText.TextColor3 = UI.Theme.Text
    self.TitleText.TextXAlignment = Enum.TextXAlignment.Left
    self.TitleText.Parent = self.TitleBar
    self.CollapseBtn = Instance.new("TextButton")
    self.CollapseBtn.Name = "CollapseBtn"
    self.CollapseBtn.Size = UDim2.new(0, 22, 1, 0)
    self.CollapseBtn.Position = UDim2.new(1, -52, 0, 0)
    self.CollapseBtn.BackgroundTransparency = 1
    self.CollapseBtn.Text = "-"
    self.CollapseBtn.Font = Enum.Font.GothamBold
    self.CollapseBtn.TextSize = 16
    self.CollapseBtn.TextColor3 = UI.Theme.Text
    self.CollapseBtn.Parent = self.TitleBar
    self.CloseBtn = Instance.new("TextButton")
    self.CloseBtn.Name = "CloseBtn"
    self.CloseBtn.Size = UDim2.new(0, 22, 1, 0)
    self.CloseBtn.Position = UDim2.new(1, -22, 0, 0)
    self.CloseBtn.BackgroundTransparency = 1
    self.CloseBtn.Text = "×"
    self.CloseBtn.Font = Enum.Font.GothamBold
    self.CloseBtn.TextSize = 18
    self.CloseBtn.TextColor3 = UI.Theme.Text
    self.CloseBtn.Parent = self.TitleBar
    self:TrackConnection(self.CloseBtn.MouseButton1Click:Connect(function()
        if not self._destroyed and self.MainGui then
            self.MainGui:Destroy()
        end
    end))
    self.ContentContainer = Instance.new("Frame")
    self.ContentContainer.Name = "ContentContainer"
    self.ContentContainer.Size = UDim2.new(1, 0, 1, -40)
    self.ContentContainer.Position = UDim2.new(0, 0, 0, 40)
    self.ContentContainer.BackgroundTransparency = 1
    self.ContentContainer.ClipsDescendants = false
    self.ContentContainer.Parent = self.Window
    self.MenuContainer = Instance.new("Frame")
    self.MenuContainer.Size = UDim2.new(1, 0, 1, 0)
    self.MenuContainer.BackgroundTransparency = 1
    self.MenuContainer.ClipsDescendants = false
    self.MenuContainer.Parent = self.ContentContainer
    self:MakeDraggable()
    self.IsCollapsed = false
    self:TrackConnection(self.CollapseBtn.MouseButton1Click:Connect(function()
        if not self._destroyed then self:ToggleCollapse() end
    end))
    self.Sections = {}
    self.CurrentY = 0
    return self
end
function UI:MakeDraggable()
    local dragging = false
    local dragStart = Vector2.new()
    local startPos = UDim2.new()
    self:TrackConnection(self.TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = self.Window.Position
            UserInputService.MouseIconEnabled = false
        end
    end))
    self:TrackConnection(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            self.Window.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end))
    self:TrackConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            UserInputService.MouseIconEnabled = true
        end
    end))
end
function UI:ToggleCollapse()
    self.IsCollapsed = not self.IsCollapsed
    if self.IsCollapsed then
        for _, section in ipairs(self.Sections) do
            if section.IsExpanded then
                section.IsExpanded = false
                section.ToggleBtn.Text = "+"
                TweenService:Create(section.Content, TweenInfo.new(0.2), {
                    Size = UDim2.new(1, 0, 0, 0)
                }):Play()
                self.CurrentY = self.CurrentY - section.ContentY
            end
        end
        TweenService:Create(self.Window, TweenInfo.new(0.2), {
            Size = UDim2.new(0, 150, 0, 40)
        }):Play()
        self.CollapseBtn.Text = "+"
        self.ContentContainer.Visible = false
    else
        self.CurrentY = 0
        local currentOffset = 0
        for _, section in ipairs(self.Sections) do
            section.Frame.Position = UDim2.new(0, 0, 0, currentOffset)
            section.Content.Position = UDim2.new(0, 0, 0, currentOffset + 36)
            currentOffset = currentOffset + 36
            self.CurrentY = self.CurrentY + 36
        end
        local newHeight = math.max(150, 40 + self.CurrentY + 20) -- 40 is the title bar height; 20 is the bottom margin
        TweenService:Create(self.Window, TweenInfo.new(0.2), {
            Size = UDim2.new(0, 150, 0, newHeight)
        }):Play()
        self.CollapseBtn.Text = "-"
        self.MenuContainer.Size = UDim2.new(1, 0, 1, 0)
        self.ContentContainer.Size = UDim2.new(1, 0, 1, -40)
        for _, section in ipairs(self.Sections) do
            section.Frame.Visible = true
            section.Content.Visible = true
        end
        task.wait(0.2)
        self.ContentContainer.Visible = true
    end
end
function UI:NewSection(title)
    local section = {}
    section.Title = title
    section.Frame = Instance.new("Frame")
    section.Frame.Size = UDim2.new(1, 0, 0, 36)
    section.Frame.Position = UDim2.new(0, 0, 0, self.CurrentY)
    local sectionColor = UI.Theme.Other
    if title == "Auto" then
        sectionColor = UI.Theme.Auto
    elseif title == "Character" then
        sectionColor = UI.Theme.Player
    elseif title == "Other" then
        sectionColor = UI.Theme.Other
    end
    section.Frame.BackgroundColor3 = sectionColor
    section.Frame.Parent = self.MenuContainer
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = section.Frame
    section.TitleText = Instance.new("TextLabel")
    section.TitleText.Size = UDim2.new(1, -40, 1, 0)
    section.TitleText.Position = UDim2.new(0, 10, 0, 0)
    section.TitleText.BackgroundTransparency = 1
    section.TitleText.Text = title
    section.TitleText.Font = Enum.Font.GothamBold
    section.TitleText.TextSize = 14
    section.TitleText.TextColor3 = UI.Theme.Text
    section.TitleText.TextXAlignment = Enum.TextXAlignment.Left
    section.TitleText.Parent = section.Frame
    section.TitleText.Active = true

    -- Drag any folder title to move the complete panel; the + / - button remains clickable.
    local sectionDragging = false
    local sectionDragStart = Vector2.new()
    local windowStart = self.Window.Position
    self:TrackConnection(section.TitleText.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sectionDragging = true
            sectionDragStart = input.Position
            windowStart = self.Window.Position
        end
    end))
    self:TrackConnection(UserInputService.InputChanged:Connect(function(input)
        if sectionDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - sectionDragStart
            if math.abs(delta.X) + math.abs(delta.Y) > 4 then
                self.Window.Position = UDim2.new(
                    windowStart.X.Scale,
                    windowStart.X.Offset + delta.X,
                    windowStart.Y.Scale,
                    windowStart.Y.Offset + delta.Y
                )
            end
        end
    end))
    self:TrackConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sectionDragging = false
        end
    end))

    section.ToggleBtn = Instance.new("TextButton")
    section.ToggleBtn.Size = UDim2.new(0, 40, 1, 0)
    section.ToggleBtn.Position = UDim2.new(1, -40, 0, 0)
    section.ToggleBtn.BackgroundTransparency = 1
    section.ToggleBtn.Text = "+"
    section.ToggleBtn.Font = Enum.Font.GothamBold
    section.ToggleBtn.TextSize = 16
    section.ToggleBtn.TextColor3 = UI.Theme.Text
    section.ToggleBtn.Parent = section.Frame
    section.Content = Instance.new("Frame")
    section.Content.Size = UDim2.new(1, 0, 0, 0)
    section.Content.Position = UDim2.new(0, 0, 0, self.CurrentY + 36)
    section.Content.BackgroundTransparency = 1
    section.Content.ClipsDescendants = true
    section.Content.Parent = self.MenuContainer
    section.IsExpanded = false
    section.Buttons = {}
    section.ContentY = 0
    self.CurrentY = self.CurrentY + 36
    self.MenuContainer.Size = UDim2.new(1, 0, 0, self.CurrentY)
    section.Frame.Visible = true
    section.Content.Visible = true
    local newHeight = math.max(150, 40 + self.CurrentY + 20) -- 40 is the title bar height; 20 is the bottom margin
    TweenService:Create(self.Window, TweenInfo.new(0.2), {
        Size = UDim2.new(0, 150, 0, newHeight)
    }):Play()
    self.ContentContainer.Size = UDim2.new(1, 0, 1, -40)
    section.ToggleBtn.MouseButton1Click:Connect(function()
        section.IsExpanded = not section.IsExpanded
        if section.IsExpanded then
            section.ToggleBtn.Text = "-"
            TweenService:Create(section.Content, TweenInfo.new(0.2), {
                Size = UDim2.new(1, 0, 0, section.ContentY)
            }):Play()
            self.CurrentY = self.CurrentY + section.ContentY
        else
            section.ToggleBtn.Text = "+"
            TweenService:Create(section.Content, TweenInfo.new(0.2), {
                Size = UDim2.new(1, 0, 0, 0)
            }):Play()
            self.CurrentY = self.CurrentY - section.ContentY
        end
        local currentOffset = 0
        for i, sec in ipairs(self.Sections) do
            sec.Frame.Position = UDim2.new(0, 0, 0, currentOffset)
            sec.Content.Position = UDim2.new(0, 0, 0, currentOffset + 36)
            currentOffset = currentOffset + 36
            if sec.IsExpanded then
                currentOffset = currentOffset + sec.ContentY
            end
        end
        self.MenuContainer.Size = UDim2.new(1, 0, 1, 0)
        local newHeight = math.max(150, 40 + self.CurrentY + 20) -- 40 is the title bar height; 20 is the bottom margin
        TweenService:Create(self.Window, TweenInfo.new(0.2), {
            Size = UDim2.new(0, 150, 0, newHeight)
        }):Play()
        self.ContentContainer.Size = UDim2.new(1, 0, 1, -40)
        for _, sec in ipairs(self.Sections) do
            sec.Frame.Visible = true
            sec.Content.Visible = true
        end
    end)
    function section:CreateToggle(text, callback)
        local isEven = #section.Buttons % 2 == 0
        local btnSize = UDim2.new(0.50, 0, 0, 31)
        local btnPosition
        if isEven then
            btnPosition = UDim2.new(0.50, 0, 0, section.ContentY)
        else
            btnPosition = UDim2.new(0, 0, 0, section.ContentY)
        end
        local btn = Instance.new("TextButton")
        btn.Name = "ToggleBtn_" .. text
        btn.Size = btnSize
        btn.Position = btnPosition
        btn.BackgroundColor3 = UI.Theme.Off
        btn.BackgroundTransparency = 0
        btn.Parent = section.Content
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 7)
        corner.Parent = btn
        local btnText = Instance.new("TextLabel")
        btnText.Size = UDim2.new(1, 0, 1, 0)
        btnText.Position = UDim2.new(0, 0, 0, 0)
        btnText.BackgroundTransparency = 1
        btnText.Text = text
        btnText.Font = Enum.Font.GothamMedium
        btnText.TextSize = 14
        btnText.TextColor3 = Color3.fromRGB(255, 255, 255)
        btnText.TextXAlignment = Enum.TextXAlignment.Center
        btnText.Parent = btn
        local toggleState = false
        btn.MouseButton1Click:Connect(function()
            toggleState = not toggleState
            btn.BackgroundColor3 = toggleState and UI.Theme.Auto or UI.Theme.Off
            callback(toggleState)
        end)
        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.1), {
                BackgroundColor3 = toggleState and Color3.fromRGB(45, 165, 125) or UI.Theme.Row
            }):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.1), {
                BackgroundColor3 = toggleState and UI.Theme.Auto or UI.Theme.Off
            }):Play()
        end)
        if not isEven then
            section.ContentY = section.ContentY + 31
        end
        table.insert(section.Buttons, btn)
        return btn
    end
    function section:CreateButton(text, callback)
        local isEven = #section.Buttons % 2 == 0
        local btnSize = UDim2.new(0.50, 0, 0, 31)
        local btnPosition
        if isEven then
            btnPosition = UDim2.new(0.50, 0, 0, section.ContentY)
        else
            btnPosition = UDim2.new(0, 0, 0, section.ContentY)
        end
        local btn = Instance.new("TextButton")
        btn.Name = "Button_" .. text
        btn.Size = btnSize
        btn.Position = btnPosition
        btn.BackgroundColor3 = UI.Theme.Off
        btn.BackgroundTransparency = 0
        btn.Text = ""
        btn.Parent = section.Content
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 7)
        corner.Parent = btn
        local btnText = Instance.new("TextLabel")
        btnText.Size = UDim2.new(1, 0, 1, 0)
        btnText.Position = UDim2.new(0, 0, 0, 0)
        btnText.BackgroundTransparency = 1
        btnText.Text = text
        btnText.Font = Enum.Font.GothamMedium
        btnText.TextSize = 14
        btnText.TextColor3 = Color3.fromRGB(255, 255, 255)
        btnText.TextXAlignment = Enum.TextXAlignment.Center
        btnText.Parent = btn
        btn.MouseButton1Click:Connect(function()
            callback()
        end)
        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.1), {
                BackgroundColor3 = Color3.fromRGB(54, 54, 60)
            }):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.1), {
                BackgroundColor3 = Color3.fromRGB(44, 44, 50)
            }):Play()
        end)
        if not isEven then
            section.ContentY = section.ContentY + 31
        end
        table.insert(section.Buttons, btn)
        return btn
    end
    table.insert(self.Sections, section)
    return section
end
function UI:Message(Title, Text, Time)
    local notification = Instance.new("ScreenGui")
    notification.Name = "Notification_" .. math.random(1000, 9999)
    notification.Parent = syn and CoreGui or PlayerGui
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 300, 0, 80)
    frame.Position = UDim2.new(1, -310, 0, 10 + (#notification.Parent:GetChildren() * 90))
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    frame.Parent = notification
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 25)
    title.BackgroundTransparency = 1
    title.Text = Title
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 16
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Parent = frame
    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, 0, 1, -25)
    text.Position = UDim2.new(0, 0, 0, 25)
    text.BackgroundTransparency = 1
    text.Text = Text
    text.Font = Enum.Font.SourceSans
    text.TextSize = 14
    text.TextColor3 = Color3.fromRGB(200, 200, 200)
    text.TextWrapped = true
    text.Parent = frame
    TweenService:Create(frame, TweenInfo.new(0.2), {
        Transparency = 0
    }):Play()
    task.delay(Time or 3, function()
        TweenService:Create(frame, TweenInfo.new(0.3), {
            Transparency = 1
        }):Play()
        task.wait(0.3)
        notification:Destroy()
    end)
end
local autofarm = config.autofarm
local autoCollectingCubes = config.autoCollectingCubes
local autoClaimRewards = config.autoClaimRewards
local antiAnchorEnabled = config.keepUnanchor
local antiAnchorConnection = nil
local antiFallEnabled = config.antiFallEnabled
local antiFallConnection = nil
local farmMoving = config.farmMoving
local showMap = config.showMap
local autoeat = config.autoeat
local slippageEliminationEnabled = config.slippageEliminationEnabled
local slippageConnection = nil
local currentVelocity = Vector3.new(0, 0, 0)
local ACCELERATION = 0.2
local DECELERATION = 0.15
local gravityLockEnabled = config.gravityLockEnabled
local gravityLockConnection = nil
local teleportThrowUI = nil
local teleportGrabUI = nil
local teleportGrabStop = nil
local teleportGrabCleanup = nil
local continuousGrabEnabled = false
local continuousGrabUI = nil
local continuousGrabConnection = nil
local ragdolled = false
local createdAttachments = {}
local createdConstraints = {}
local disabledMotors = {}
local ragdollGUI = nil
local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local characterGeneration = 0

local function getLiveCharacterParts(targetPlayer)
    targetPlayer = targetPlayer or LocalPlayer
    local currentCharacter = targetPlayer.Character
    if not currentCharacter or not currentCharacter.Parent then return nil, nil, nil end
    local humanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
    local rootPart = currentCharacter:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart or humanoid.Health <= 0 then
        return nil, nil, nil
    end
    return currentCharacter, humanoid, rootPart
end

local function waitForLiveCharacter(targetPlayer, timeout)
    targetPlayer = targetPlayer or LocalPlayer
    local deadline = tick() + (timeout or 8)
    repeat
        local currentCharacter, humanoid, rootPart = getLiveCharacterParts(targetPlayer)
        if currentCharacter then return currentCharacter, humanoid, rootPart end
        task.wait(0.1)
    until tick() >= deadline
    return nil, nil, nil
end

if character then
    character:WaitForChild("HumanoidRootPart", 8)
end
LocalPlayer.CharacterAdded:Connect(function(newCharacter)
    characterGeneration += 1
    character = newCharacter
    newCharacter:WaitForChild("HumanoidRootPart", 8)
end)
LocalPlayer.CharacterRemoving:Connect(function(oldCharacter)
    if character == oldCharacter then
        characterGeneration += 1
    end
end)
local function Message(Title, Text, Time)
    if mainUI then
        mainUI:Message(Title, Text, Time)
    else
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = Title,
            Text = Text,
            Duration = Time or 3
        })
    end
end
local function getRespawnPosition()
    local baseplate = Workspace:FindFirstChild("Baseplate")
    if baseplate then
        return baseplate.Position + Vector3.new(0, 40, 0), baseplate.Position.Y
    else
        return Vector3.new(0, 40, 0), 0
    end
end
local function loadCustomEmotes()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Wait!",
        Text = "Please Wait, it just loading the button",
        Duration = 15
    })
    if game:GetService("CoreGui"):FindFirstChild("Emotes") then
        game:GetService("CoreGui"):FindFirstChild("Emotes"):Destroy()
    end
    wait(1)
    local ContextActionService = game:GetService("ContextActionService")
    local HttpService = game:GetService("HttpService")
    local GuiService = game:GetService("GuiService")
    local CoreGui = game:GetService("CoreGui")
    local MarketplaceService = game:GetService("MarketplaceService")
    local Players = game:GetService("Players")
    local StarterGui = game:GetService("StarterGui")
    local UserInputService = game:GetService("UserInputService")
    local LoadedEmotes, Emotes = {}, {}
    local FavoriteOff = "rbxassetid://10651060677"
    local FavoriteOn = "rbxassetid://10651061109"
    local FavoritedEmotes = {}
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "Emotes"
    ScreenGui.DisplayOrder = 2
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Enabled = true
    local BackFrame = Instance.new("Frame")
    BackFrame.Size = UDim2.new(0.9, 0, 0.5, 0)
    BackFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    BackFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    BackFrame.SizeConstraint = Enum.SizeConstraint.RelativeYY
    BackFrame.BackgroundTransparency = 1
    BackFrame.BorderSizePixel = 0
    BackFrame.Parent = ScreenGui
    local Open = Instance.new("TextButton")
    Open.Name = "Open"
    Open.Parent = ScreenGui
    Open.Draggable = true
    Open.Size = UDim2.new(0.05, 0, 0.114, 0)
    Open.Position = UDim2.new(0.05, 0, 0.25, 0)
    Open.Text = "Close"
    Open.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    Open.TextColor3 = Color3.fromRGB(255, 255, 255)
    Open.TextScaled = true
    Open.TextSize = 20
    Open.Visible = true
    Open.BackgroundTransparency = 0.5
    local UICorner = Instance.new("UICorner")
    UICorner.Name = "UICorner"
    UICorner.Parent = Open
    UICorner.CornerRadius = UDim.new(1, 0)
    Open.MouseButton1Up:Connect(function()
        if Open.Text == "Open" then
            Open.Text = "Close"
            BackFrame.Visible = true
        elseif Open.Text == "Close" then
            Open.Text = "Open"
            BackFrame.Visible = false
        end
    end)
    local EmoteName = Instance.new("TextLabel")
    EmoteName.Name = "EmoteName"
    EmoteName.TextScaled = true
    EmoteName.AnchorPoint = Vector2.new(0.5, 0.5)
    EmoteName.Position = UDim2.new(-0.1, 0, 0.5, 0)
    EmoteName.Size = UDim2.new(0.2, 0, 0.2, 0)
    EmoteName.SizeConstraint = Enum.SizeConstraint.RelativeYY
    EmoteName.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    EmoteName.TextColor3 = Color3.new(1, 1, 1)
    EmoteName.BorderSizePixel = 0
    EmoteName.Parent = BackFrame
    local Corner = Instance.new("UICorner")
    Corner.Parent = EmoteName
    local Loading = Instance.new("TextLabel", BackFrame)
    Loading.AnchorPoint = Vector2.new(0.5, 0.5)
    Loading.Text = "Loading.."
    Loading.TextColor3 = Color3.new(1, 1, 1)
    Loading.BackgroundColor3 = Color3.new(0, 0, 0)
    Loading.TextScaled = true
    Loading.BackgroundTransparency = 0.5
    Loading.Size = UDim2.fromScale(0.2, 0.1)
    Loading.Position = UDim2.fromScale(0.5, 0.2)
    Corner:Clone().Parent = Loading
    local Frame = Instance.new("ScrollingFrame")
    Frame.Size = UDim2.new(1, 0, 1, 0)
    Frame.CanvasSize = UDim2.new(0, 0, 0, 0)
    Frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Frame.ScrollingDirection = Enum.ScrollingDirection.Y
    Frame.AnchorPoint = Vector2.new(0.5, 0.5)
    Frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    Frame.BackgroundTransparency = 1
    Frame.ScrollBarThickness = 5
    Frame.BorderSizePixel = 0
    Frame.Parent = BackFrame
    Frame.MouseLeave:Connect(function()
        EmoteName.Text = "Select an Emote"
    end)
    local Grid = Instance.new("UIGridLayout")
    Grid.CellSize = UDim2.new(0.105, 0, 0, 0)
    Grid.CellPadding = UDim2.new(0.006, 0, 0.006, 0)
    Grid.SortOrder = Enum.SortOrder.LayoutOrder
    Grid.Parent = Frame
    local FavoritesFrame = Instance.new("Frame")
    FavoritesFrame.Visible = false
    FavoritesFrame.BorderSizePixel = 0
    FavoritesFrame.Position = UDim2.new(1, 5, -0.125, 0)
    FavoritesFrame.Size = UDim2.new(0.2, 0, 0, 0)
    FavoritesFrame.AutomaticSize = Enum.AutomaticSize.Y
    FavoritesFrame.BackgroundTransparency = 1
    Corner:Clone().Parent = FavoritesFrame
    FavoritesFrame.Parent = BackFrame
    local FavoritesList = Instance.new("UIListLayout")
    FavoritesList.Padding = UDim.new(0.02, 0)
    FavoritesList.HorizontalAlignment = Enum.HorizontalAlignment.Center
    FavoritesList.VerticalAlignment = Enum.VerticalAlignment.Top
    FavoritesList.SortOrder = Enum.SortOrder.LayoutOrder
    FavoritesList.Parent = FavoritesFrame
    local function ToggleFavorites()
        local showFavorites = not FavoritesFrame.Visible
        FavoritesFrame.Visible = showFavorites
        Open.Text = "Open"
        for _, button in pairs(Frame:GetChildren()) do
            if button:IsA("ImageButton") and button.Name ~= "Random" then
                local emoteId = tonumber(button.Name)
                local isFavorited = emoteId and table.find(FavoritedEmotes, emoteId)
                button.Visible = not showFavorites or isFavorited
            end
        end
    end
    local FavoritesButton = Instance.new("TextButton")
    FavoritesButton.BorderSizePixel = 0
    FavoritesButton.AnchorPoint = Vector2.new(0.5, 0.5)
    FavoritesButton.Position = UDim2.new(0.925, -5, -0.075, 0)
    FavoritesButton.Size = UDim2.new(0.15, 0, 0.1, 0)
    FavoritesButton.TextScaled = true
    FavoritesButton.TextColor3 = Color3.new(1, 1, 1)
    FavoritesButton.BackgroundColor3 = Color3.new(0, 0, 0)
    FavoritesButton.BackgroundTransparency = 0.3
    FavoritesButton.Text = "Favorites"
    FavoritesButton.Parent = BackFrame
    Corner:Clone().Parent = FavoritesButton
    FavoritesButton.MouseButton1Click:Connect(ToggleFavorites)
    local CloseButton = Instance.new("TextButton")
    CloseButton.BorderSizePixel = 0
    CloseButton.AnchorPoint = Vector2.new(0.5, 0.5)
    CloseButton.Position = UDim2.new(0.075, 0, -0.075, 0)
    CloseButton.Size = UDim2.new(0.15, 0, 0.1, 0)
    CloseButton.TextScaled = true
    CloseButton.TextColor3 = Color3.new(1, 1, 1)
    CloseButton.BackgroundColor3 = Color3.new(0.5, 0, 0)
    CloseButton.BackgroundTransparency = 0.3
    CloseButton.Text = "Close"
    CloseButton.Parent = BackFrame
    Corner:Clone().Parent = CloseButton
    CloseButton.MouseButton1Click:Connect(function()
        ScreenGui:Destroy()
    end)
    local SearchBar = Instance.new("TextBox")
    SearchBar.BorderSizePixel = 0
    SearchBar.AnchorPoint = Vector2.new(0.5, 0.5)
    SearchBar.Position = UDim2.new(0.5, 0, -0.075, 0)
    SearchBar.Size = UDim2.new(0.55, 0, 0.1, 0)
    SearchBar.TextScaled = true
    SearchBar.PlaceholderText = "Search"
    SearchBar.TextColor3 = Color3.new(1, 1, 1)
    SearchBar.BackgroundColor3 = Color3.new(0, 0, 0)
    SearchBar.BackgroundTransparency = 0.3
    SearchBar.Parent = BackFrame
    Corner:Clone().Parent = SearchBar
    SearchBar:GetPropertyChangedSignal("Text"):Connect(function()
        local text = SearchBar.Text:lower()
        local buttons = Frame:GetChildren()
        if text ~= text:sub(1, 50) then
            SearchBar.Text = SearchBar.Text:sub(1, 50)
            text = SearchBar.Text:lower()
        end
        for _, button in pairs(buttons) do
            if button:IsA("GuiButton") then
                local name = button:GetAttribute("name")
                if name then
                    if text == "" or name:lower():match(text) then
                        button.Visible = true
                    else
                        button.Visible = false
                    end
                end
            end
        end
    end)
    local function openEmotesMenu(name, state, input)
        if state == Enum.UserInputState.Begin then
            BackFrame.Visible = not BackFrame.Visible
            Open.Text = "Open"
        end
    end
    ContextActionService:BindCoreActionAtPriority(
        "Emote Menu",
        openEmotesMenu,
        true,
        2001,
        Enum.KeyCode.Comma
    )
    local inputConnect
    ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if BackFrame.Visible == false then
            EmoteName.Text = "Select an Emote"
            SearchBar.Text = ""
            GuiService:SetEmotesMenuOpen(false)
            inputConnect = UserInputService.InputBegan:Connect(function(input, processed)
                if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
                    BackFrame.Visible = false
                    Open.Text = "Open"
                end
            end)
        else
            if inputConnect then
                inputConnect:Disconnect()
            end
        end
    end)
    GuiService.EmotesMenuOpenChanged:Connect(function(isOpen)
        if isOpen then
            BackFrame.Visible = false
            Open.Text = "Open"
        end
    end)
    GuiService.MenuOpened:Connect(function()
        BackFrame.Visible = false
        Open.Text = "Open"
    end)
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
    local SynV3 = syn and DrawingImmediate
    if (not is_sirhurt_closure) and (not SynV3) and (syn and syn.protect_gui) then
        syn.protect_gui(ScreenGui)
        ScreenGui.Parent = CoreGui
    elseif get_hidden_gui or gethui then
        local hiddenUI = get_hidden_gui or gethui
        ScreenGui.Parent = hiddenUI()
    else
        ScreenGui.Parent = CoreGui
    end
    local function SendNotification(title, text)
        if syn and syn.toast_notification then
            syn.toast_notification({
                Type = ToastType.Error,
                Title = title,
                Content = text
            })
        else
            StarterGui:SetCore("SendNotification", {
                Title = title,
                Text = text
            })
        end
    end
    local LocalPlayer = Players.LocalPlayer
    local function PlayEmote(name, id)
        BackFrame.Visible = false
        Open.Text = "Open"
        SearchBar.Text = ""
        local Character = LocalPlayer.Character
        if not Character then return end
        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        local Description = Humanoid and Humanoid:FindFirstChildOfClass("HumanoidDescription")
        if not Description then
            SendNotification("Error", "HumanoidDescription not found")
            return
        end
        if Humanoid.RigType ~= Enum.HumanoidRigType.R6 then
            local success, err = pcall(function()
                Humanoid:PlayEmoteAndGetAnimTrackById(id)
            end)
            if not success then
                local addSuccess, addErr = pcall(function()
                    Description:AddEmote(name, id)
                    Humanoid:PlayEmoteAndGetAnimTrackById(id)
                end)
                if not addSuccess then
                    SendNotification("Error", "Failed to play emote: " .. tostring(addErr))
                end
            end
        else
            SendNotification("r6? lol", "you gotta be r15 dude")
        end
    end
    local function WaitForChildOfClass(parent, class)
        local child = parent:FindFirstChildOfClass(class)
        while not child or child.ClassName ~= class do
            child = parent.ChildAdded:Wait()
        end
        return child
    end
    local function addEmote(name, id, price, date)
        local months = {
            Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
            Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12
        }
        local function dateToUnix(d)
            local mon, day, year = d:match("(%a+)%s+(%d+),%s*(%d+)")
            if not mon or not day or not year then return os.time() end
            return os.time({
                year = tonumber(year),
                month = months[mon],
                day = tonumber(day),
                hour = 0,
                min = 0,
                sec = 0
            })
        end
        table.insert(Emotes, {
            name = name,
            id = id,
            icon = "rbxthumb://type=Asset&id=" .. id .. "&w=150&h=150",
            price = price or 0,
            lastupdated = dateToUnix(date),
            sort = {}
        })
    end
addEmote("PARROT PARTY DANCE", 121067808279598, 39, "Aug 08, 2025")
addEmote("stretch-like-this", 126017588998166, 39, "Aug 08, 2025")
addEmote("High-Bird-Flight-SMOOTH-READ-DESC", 106894076202843, 39, "Aug 08, 2025")
addEmote("Cry-For-Me-OG", 98263064912190, 39, "Aug 08, 2025")
addEmote("BEST-Chinese-Military-Dance-Pose", 131258378669186, 39, "Aug 08, 2025")
addEmote("Zero-Two-Dance-V2", 95385842020103, 39, "Aug 08, 2025")
addEmote("I-Want-Money", 89114994401113, 39, "Aug 08, 2025")
addEmote("Reze-Dance-Iris-Out", 91032553512904, 39, "Aug 08, 2025")
addEmote("Nya-San", 118688124889191, 39, "Aug 08, 2025")
addEmote("Chinese-Dance-Da-Koto-Nai-BEST", 104539498095025, 39, "Aug 08, 2025")
addEmote("Caramelldansen-Caramell-Kawaii-Dance", 97847706148165, 39, "Aug 08, 2025")
addEmote("Jumping-Spider-Emote", 111427367473754, 39, "Aug 08, 2025")
addEmote("Hornets-Spider-Dance", 74716792202343, 39, "Aug 08, 2025")
addEmote("Cat-Nap", 105016815489641, 39, "Aug 08, 2025")
addEmote("Cute-Sit", 72947568152049, 39, "Aug 08, 2025")
addEmote("cutest-sitting-kitty-idle-pose", 137700239155449, 39, "Aug 08, 2025")
addEmote("Big-Guy-Ice-Spice-x-Spongebob", 107708114415320, 39, "Aug 08, 2025")
addEmote("Pumpkin-King", 105381637724646, 39, "Aug 08, 2025")
addEmote("Ghost-Floating", 75911227509248, 39, "Aug 08, 2025")
addEmote("Kid-tantrum", 121911959295081, 39, "Aug 08, 2025")
addEmote("Peter-Griffins-Death-Pose", 99005087791705, 39, "Aug 08, 2025")
addEmote("intrusive-awkward-wave", 85665834724929, 39, "Aug 08, 2025")
addEmote("Lush-Life", 82727664018494, 39, "Aug 08, 2025")
addEmote("BEST-Its-Gangnam-Style", 104142334418357, 39, "Aug 08, 2025")
addEmote("Casual-Sitting", 113039466758343, 39, "Aug 08, 2025")
addEmote("Cute-Feet-Kicking", 78224683906191, 39, "Aug 08, 2025")
addEmote("pain-and-suffering", 93195109588878, 39, "Aug 08, 2025")
addEmote("hip-sway", 80963950541052, 39, "Aug 08, 2025")
addEmote("Bouncy-Cute-Girl-Anime-Idle", 74193679388896, 39, "Aug 08, 2025")
addEmote("Neck-Roll", 93641632427451, 39, "Aug 08, 2025")
addEmote("cute-sitting-with-legs-out", 139076155588413, 39, "Aug 08, 2025")
addEmote("Bubbly-Sit", 112758073578333, 39, "Aug 08, 2025")
addEmote("MM2-Fake-Dead", 132384701706046, 39, "Aug 08, 2025")
addEmote("Tall-Scary-Creature", 79216795769647, 39, "Aug 08, 2025")
addEmote("Wigglepillar-exe", 73276701013534, 39, "Aug 08, 2025")
addEmote("Relax-Flying-Anime-Floating-Emote", 131950236025472, 39, "Aug 08, 2025")
addEmote("Cute-Kawaii-Posing", 94064805002669, 39, "Aug 08, 2025")
addEmote("Cat-Girl-Cute-Sit", 80706795731202, 39, "Aug 08, 2025")
addEmote("MM2-Fake-Dead-2", 95407766746448, 39, "Aug 08, 2025")
addEmote("Sit-Pose-Forward", 118492862930593, 39, "Aug 08, 2025")
addEmote("Just-be-competent", 124041369408613, 39, "Aug 08, 2025")
addEmote("BEST-Nightmail-jig-crossing-the-border-dance", 136328385086605, 39, "Aug 08, 2025")
addEmote("SHAKE-THAT-THANG", 83128545542582, 39, "Aug 08, 2025")
addEmote("Tornado", 82995540773684, 39, "Aug 08, 2025")
addEmote("WOOF-BARK-WOOF", 88859617281337, 39, "Aug 08, 2025")
addEmote("disco-spin", 93818150150183, 39, "Aug 08, 2025")
addEmote("Be-Tall-Skinwalker-Dog", 81694095869045, 39, "Aug 08, 2025")
addEmote("invisible-me", 94292601332790, 39, "Aug 08, 2025")
addEmote("Swaying-Sit", 120565455646158, 39, "Aug 08, 2025")
addEmote("Floating-Sit", 83475540437708, 39, "Aug 08, 2025")
addEmote("Basketball-Head", 107282826166809, 39, "Aug 08, 2025")
addEmote("Feeling-Cute", 112540347880956, 39, "Aug 08, 2025")
addEmote("Jumpstyle-dance", 133248139921782, 39, "Aug 08, 2025")
addEmote("cute-shy-withdrawn-sit", 81204065393762, 39, "Aug 08, 2025")
addEmote("Car-Pose-Tokyo-Lean", 118859160373597, 39, "Aug 08, 2025")
addEmote("MEGA-POOP-SNIFF-AURA", 82904146092287, 39, "Aug 08, 2025")
addEmote("Helicopter", 140547238892659, 39, "Aug 08, 2025")
addEmote("Accurate-Admin-Fly", 97830214926142, 39, "Aug 08, 2025")
addEmote("Floating-in-Love", 97164262994588, 39, "Aug 08, 2025")
addEmote("Endless-Aura-Floating", 106708015414624, 39, "Aug 08, 2025")
addEmote("Nonchalant-Sit", 85092320680319, 39, "Aug 08, 2025")
addEmote("Get-Sturdy", 127480853388432, 39, "Aug 08, 2025")
addEmote("Floating-Upside-Down", 95999178112240, 39, "Aug 08, 2025")
addEmote("DARE-Gorillaz", 136648387080677, 39, "Aug 08, 2025")
addEmote("Wall-Aura-Farm-Pose", 118853736905967, 39, "Aug 08, 2025")
addEmote("TV-Time-Dance", 75017857395637, 39, "Aug 08, 2025")
addEmote("cute-dancy-dance", 83917238288783, 39, "Aug 08, 2025")
addEmote("Emperor-Of-The-Auraverse-Aura", 133594786690861, 39, "Aug 08, 2025")
addEmote("Flying-Superhero-Emote", 71574925787532, 39, "Aug 08, 2025")
addEmote("Realy-strange-Hornets-Spider", 114530046828576, 39, "Aug 08, 2025")
addEmote("Springtrapped-Face-Animated", 125974779288821, 39, "Aug 08, 2025")
addEmote("MM2-Fake-Dead-3", 79297779614324, 39, "Aug 08, 2025")
addEmote("Original-Gangnam-Style", 116468071022853, 39, "Aug 08, 2025")
addEmote("Hakari-Dance", 122147154162464, 39, "Aug 08, 2025")
addEmote("Cute-Bouncy-Hip-Shake-Dance", 87963462118126, 39, "Aug 08, 2025")
addEmote("Take-The-L", 82405492529515, 39, "Aug 08, 2025")
addEmote("R6-Otsukare-Summer", 82461557511288, 39, "Aug 08, 2025")
addEmote("Sukuna-Aura-Farming", 73532860571147, 39, "Aug 08, 2025")
addEmote("Party-Rocker", 96443347889042, 39, "Aug 08, 2025")
addEmote("Vampire-Pose", 113919169704818, 39, "Aug 08, 2025")
addEmote("Make-You-Mine", 97092824850945, 39, "Aug 08, 2025")
addEmote("Gojo-Floating-Pose-The-Honored-One", 103040723950430, 39, "Aug 08, 2025")
addEmote("Possessed-Glitcher", 106370760824973, 39, "Aug 08, 2025")
addEmote("Cute-Sit", 90244178386698, 39, "Aug 08, 2025")
addEmote("KATSEYE-GNARLY", 133685484220846, 39, "Aug 08, 2025")
addEmote("Yungblud-Happier-Jump", 15610015346, 39, "Aug 08, 2025")
addEmote("Floating", 70615023659736, 39, "Aug 08, 2025")
addEmote("MJ-P-Y-T-Pretty-Young-Thing", 137234266130963, 39, "Aug 08, 2025")
addEmote("Obby-Emote", 76394392186917, 39, "Aug 08, 2025")
addEmote("Effortless-Aura-Pose", 101573394483995, 39, "Aug 08, 2025")
addEmote("Demon-Slayer-Douma-Sit", 96606489351695, 39, "Aug 08, 2025")
addEmote("Michael-Myers-Bounce", 99068367180942, 39, "Aug 08, 2025")
addEmote("curiously-cute-sitting-pose", 76261461321661, 39, "Aug 08, 2025")
addEmote("Spiderman-Hang", 108635834286627, 39, "Aug 08, 2025")
addEmote("Sonic-Adventure-Profile-Pose", 104721659176603, 39, "Aug 08, 2025")
addEmote("Floating-Idle-animation", 117134539591727, 39, "Aug 08, 2025")
addEmote("e-fly", 93511411593120, 39, "Aug 08, 2025")
addEmote("Fairy-sit-floating-anime-girl-pose", 132152702263080, 39, "Aug 08, 2025")
addEmote("MASSIVE-POOP", 83417429144154, 39, "Aug 08, 2025")
addEmote("cute-halloween-magical-witch-idle-pose", 96252923654843, 39, "Aug 08, 2025")
addEmote("Godly-Aura-fly-pose-idle", 76361248833307, 39, "Aug 08, 2025")
addEmote("Floating", 139058906415119, 39, "Aug 08, 2025")
addEmote("MM2-Fake-Dead-Pose", 83548980186247, 39, "Aug 08, 2025")
addEmote("Michael-Myers-Goofy-Shake-Dance", 120627499048953, 39, "Aug 08, 2025")
addEmote("Race-Car", 121936817462716, 39, "Aug 08, 2025")
addEmote("Sweet-Fluffy-Bunny", 96134340818599, 39, "Aug 08, 2025")
addEmote("Stylish-Floating", 88425531063616, 39, "Aug 08, 2025")
addEmote("Ironmouse-Cry-For-Me", 118394958773258, 39, "Aug 08, 2025")
addEmote("Choso", 119042829278898, 39, "Aug 08, 2025")
addEmote("The-Mimic-SPOOKY-SCARY-HALLOWEEN", 71350324794436, 39, "Aug 08, 2025")
addEmote("Cute-kawaii-girly-idle-Profile-pose", 138515241510970, 39, "Aug 08, 2025")
addEmote("Furry-Running", 127131085046464, 39, "Aug 08, 2025")
addEmote("RiRiRi-Happy-Halloween", 98464793617142, 39, "Aug 08, 2025")
addEmote("Hear-Me-Now", 133307355099075, 39, "Aug 08, 2025")
addEmote("Around-the-Head", 114502615688717, 39, "Aug 08, 2025")
addEmote("Trip-Out", 101289807932349, 39, "Aug 08, 2025")
addEmote("kawaii-whimsy-airplane-profile-pose", 122803615354190, 39, "Aug 08, 2025")
addEmote("Take-The-L", 73593666217037, 39, "Aug 08, 2025")
addEmote("Needy-Cartwheel-Split", 91490872407594, 39, "Aug 08, 2025")
addEmote("Hakari-Dance-V2", 77666131363559, 39, "Aug 08, 2025")
addEmote("TYLA-Chanel-Kpop-Trendy-Dance", 80341701361363, 39, "Aug 08, 2025")
addEmote("Courtly-bow", 72613272882226, 39, "Aug 08, 2025")
addEmote("cute-floating-headless-head-aura-emote", 98728517497209, 39, "Aug 08, 2025")
addEmote("SHAKE-THAT-SILLY-THANG", 101532601304772, 39, "Aug 08, 2025")
addEmote("Sit", 132738611207490, 39, "Aug 08, 2025")
addEmote("Reze-Dance-HQ", 87471384477488, 39, "Aug 08, 2025")
addEmote("Sad-Depressed-Crying-Sit-Sitting", 95339652051393, 39, "Aug 08, 2025")
addEmote("Sturdy-Dance-Ice-Spice-CHEAP", 72333659132786, 39, "Aug 08, 2025")
addEmote("Internet-Girl-Katseye-Eat-Zucchini", 120642998230445, 39, "Aug 08, 2025")
addEmote("Sturdy-R6", 92335786854446, 39, "Aug 08, 2025")
addEmote("SpiderMan-Original", 130987133773478, 39, "Aug 08, 2025")
addEmote("Korean-Greeting-Annyeong", 135719167611495, 39, "Aug 08, 2025")
addEmote("Charming-Cute-Look-Pose", 101275066718933, 39, "Aug 08, 2025")
addEmote("Pangya-Dance", 89439360145889, 39, "Aug 08, 2025")
addEmote("Spice-On-Floor", 126837474178236, 39, "Aug 08, 2025")
addEmote("Kawaii-Bouncy-Anime-Girl-Dance", 130855166586798, 39, "Aug 08, 2025")
addEmote("Sukuna-Aura-Farming-Pose", 134893423132417, 39, "Aug 08, 2025")
addEmote("FF-Push-Up", 73630423562709, 39, "Aug 08, 2025")
addEmote("Asian-Squat", 87939646671209, 39, "Aug 08, 2025")
addEmote("Fling-emote-V2", 123929740439299, 39, "Aug 08, 2025")
addEmote("Baby-Queen-Bouncy-Twirl", 14353423348, 39, "Aug 08, 2025")
addEmote("KATSEYE-Gabriela-Megan", 98012296914799, 39, "Aug 08, 2025")
addEmote("Flying-Pose-Emote", 97130179011866, 39, "Aug 08, 2025")
addEmote("unnamed", 4849502101, 39, "Aug 08, 2025")
addEmote("Stranger-Things-Vecna-Kill-Emote", 80981189893654, 39, "Aug 08, 2025")
addEmote("OG-Ishowspeed-Shake-Dance", 138386881919239, 39, "Aug 08, 2025")
addEmote("Hear-Me-Now", 98466571496349, 39, "Aug 08, 2025")
addEmote("Da-Hood-Stomp", 92237689732858, 39, "Aug 08, 2025")
addEmote("Ya-Ya-Ying-Dance", 130850357238599, 39, "Aug 08, 2025")
addEmote("Sweet-Hug-Pose-V2-MATCHING", 79076692213299, 39, "Aug 08, 2025")
addEmote("baby-boo-dance", 78428722915978, 39, "Aug 08, 2025")
addEmote("I-came-to-GROOVE-A-peanut-butter-house-410", 85913265750993, 39, "Aug 08, 2025")
addEmote("Honor-Knight-Kneel-Dark-Souls", 89198573930777, 39, "Aug 08, 2025")
addEmote("Cut-Water-Summer-Dance", 71825767065274, 39, "Aug 08, 2025")
addEmote("griddy", 129149402922241, 39, "Aug 08, 2025")
addEmote("adorable-dolly-pose", 89104845724058, 39, "Aug 08, 2025")
addEmote("Lets-Get-Sturdy", 119341017234649, 39, "Aug 08, 2025")
addEmote("La-Detone-Dance", 103768845612667, 39, "Aug 08, 2025")
addEmote("Blue-Top-Rock", 101572357319427, 39, "Aug 08, 2025")
addEmote("BEST-Dougie-Everybody-Loves-Me", 114756515400742, 39, "Aug 08, 2025")
addEmote("Cute-Pretty-Girly-Girl-Fierce-Slay-Idle-Pose", 135853357333509, 39, "Aug 08, 2025")
addEmote("The-coolest-standing-pose-in-the-world", 110330632237517, 39, "Aug 08, 2025")
addEmote("Spice-Jersey-Bounce", 126529053628312, 39, "Aug 08, 2025")
addEmote("Needy-Stretch", 130329103860361, 39, "Aug 08, 2025")
addEmote("Hear-Me-Now", 113116746603315, 39, "Aug 08, 2025")
addEmote("Will-has-power-STRANGER-THINGS-5", 93772541546815, 39, "Aug 08, 2025")
addEmote("Michael-Myers-Bounce-NEW-VERSION", 139749659598065, 39, "Aug 08, 2025")
addEmote("Relax-Coin-Flip", 128000234046934, 39, "Aug 08, 2025")
addEmote("NO-HANDS", 95664256018756, 39, "Aug 08, 2025")
addEmote("Hype-Boy-NewJeans", 105324347192111, 39, "Aug 08, 2025")
addEmote("beautiful-dance", 104077918384157, 39, "Aug 08, 2025")
addEmote("AY-MI-GATITO-DANCE-cheap", 88373786916619, 39, "Aug 08, 2025")
addEmote("Street-Glide", 137284968787523, 39, "Aug 08, 2025")
addEmote("Heavy-Sword-Stance", 109863797124787, 39, "Aug 08, 2025")
addEmote("Hey-Ya-Move", 104338766814874, 39, "Aug 08, 2025")
addEmote("zesty-sturdy", 117229339270317, 39, "Aug 08, 2025")
addEmote("headless-koblox-kind-of", 110170230382247, 39, "Aug 08, 2025")
addEmote("Money-Hop-Switch", 134222090358172, 39, "Aug 08, 2025")
addEmote("Goku-SSJ-Rage", 73708713364616, 39, "Aug 08, 2025")
addEmote("Brazilian-Funk-Footwork", 88693910954718, 39, "Aug 08, 2025")
addEmote("Kawaii-Groove", 94792423330715, 39, "Aug 08, 2025")
addEmote("Vecna-Stranger-Things-Fly-Animation-Emote-Bone", 90555063826230, 39, "Aug 08, 2025")
addEmote("GNARLY-DANCEBREAK-KATSEYE", 92036309063784, 39, "Aug 08, 2025")
addEmote("Zombie-Run-Lag", 100868777466223, 39, "Aug 08, 2025")
addEmote("Spice-Keep-Bouncing", 121347449465835, 39, "Aug 08, 2025")
addEmote("A-Rose", 91739079549341, 39, "Aug 08, 2025")
addEmote("adidas-aura-farm", 93031389900156, 39, "Aug 08, 2025")
addEmote("Street-Flow-Bounce", 91773089278851, 39, "Aug 08, 2025")
addEmote("Wally-Speedster-Run", 133948663586698, 39, "Aug 08, 2025")
addEmote("Jabba-Switchway", 103538719480738, 39, "Aug 08, 2025")
addEmote("Michael-Myers-Shake", 114873215991554, 39, "Aug 08, 2025")
addEmote("Vem-Ca-N-nem-roblox-dance", 107356594223985, 39, "Aug 08, 2025")
addEmote("Slow-Dembow", 73236219340808, 39, "Aug 08, 2025")
addEmote("Smooth-Rizz-Rose", 83362314681140, 39, "Aug 08, 2025")
addEmote("Jamal-Dance", 72213123467340, 39, "Aug 08, 2025")
addEmote("unnamed", 3360692915, 39, "Aug 08, 2025")
addEmote("unnamed", 3360689775, 39, "Aug 08, 2025")
addEmote("unnamed", 5915779043, 39, "Aug 08, 2025")
addEmote("Popular", 71302743123422, 39, "Aug 08, 2025")
addEmote("Raiden-Punching-Armstrong-Loop", 115203580644128, 39, "Aug 08, 2025")
addEmote("silly-jumping-dog-dance", 119411579938196, 39, "Aug 08, 2025")
addEmote("Feral-Hip-Sway", 117752311882154, 39, "Aug 08, 2025")
addEmote("Brazillian-Vibe", 112528616743393, 39, "Aug 08, 2025")
addEmote("Spicy-Flow-Vibes", 124212021234700, 39, "Aug 08, 2025")
addEmote("OG-BADDIE-BOUNCE", 116938844814178, 39, "Aug 08, 2025")
addEmote("Kissy-Roblox-Profile-Pose", 73398162799786, 39, "Aug 08, 2025")
addEmote("baddie", 125699260461610, 39, "Aug 08, 2025")
addEmote("Dance-All-Night", 97139559228653, 39, "Aug 08, 2025")
addEmote("Trip-Out", 75483681450871, 39, "Aug 08, 2025")
addEmote("Big-Hand-Wave", 105209959441169, 39, "Aug 08, 2025")
addEmote("Sweet-Hug-Pose-V1-MATCHING", 100597438247721, 39, "Aug 08, 2025")
addEmote("Orange-Justice", 110064349530772, 39, "Aug 08, 2025")
addEmote("BEST-Invisiblity", 130371895389423, 39, "Aug 08, 2025")
addEmote("Spice-Spotlight", 123516494450935, 39, "Aug 08, 2025")
addEmote("Stranger-Things-Vecna-Power-Draw", 90431837142164, 39, "Aug 08, 2025")
addEmote("OG-bunny-party-dance", 104922087218459, 39, "Aug 08, 2025")
addEmote("Hug", 88712283515515, 39, "Aug 08, 2025")
addEmote("Baby-Queen-Face-Frame", 14353421343, 39, "Aug 08, 2025")
addEmote("silly-jumping-spider-dance", 89157328525577, 39, "Aug 08, 2025")
addEmote("Jumpstyle-Dance", 89614983665331, 39, "Aug 08, 2025")
addEmote("Gangnam-style", 80923445784018, 39, "Aug 08, 2025")
addEmote("Speed-Mirage", 108946079729323, 39, "Aug 08, 2025")
addEmote("Fake-Lag-Disconnect-TROLL", 97523498583729, 39, "Aug 08, 2025")
addEmote("unnamed", 3576686446, 39, "Aug 08, 2025")
addEmote("unnamed", 3576968026, 39, "Aug 08, 2025")
addEmote("Sturdy-NYC-Dance", 122687759897103, 39, "Aug 08, 2025")
addEmote("Spider-Man-Hanging-2", 139402543978841, 39, "Aug 08, 2025")
addEmote("Russian-Dance", 74608751145756, 39, "Aug 08, 2025")
addEmote("z-sturdy-actual-original", 120702604995324, 39, "Aug 08, 2025")
addEmote("Diva-Aura", 118846519181951, 39, "Aug 08, 2025")
addEmote("ORIGINAL-Electro-Shuffle", 140499299581464, 39, "Aug 08, 2025")
addEmote("I-Like-It-Stray-kids", 84540347604763, 39, "Aug 08, 2025")
addEmote("No-Hands", 106472603343742, 39, "Aug 08, 2025")
addEmote("Spice-N-Slide", 103814076459025, 39, "Aug 08, 2025")
addEmote("Sit", 101743582461626, 39, "Aug 08, 2025")
addEmote("cute-ponpon-dance-og", 114462336086965, 39, "Aug 08, 2025")
addEmote("unnamed", 3360686498, 39, "Aug 08, 2025")
addEmote("Jamals-Passinho-TikTok-dance", 75125571025711, 39, "Aug 08, 2025")
addEmote("Relaxed-Sit", 111231236978253, 39, "Aug 08, 2025")
addEmote("Dougie", 93675237485386, 39, "Aug 08, 2025")
addEmote("Exotic-APEX-Emote-Sols-RNG", 106674068664046, 39, "Aug 08, 2025")
addEmote("Trendy-Nicki-Leg-Pose", 92846015938931, 39, "Aug 08, 2025")
addEmote("apple-store-girl-do-you-want-me", 86591723458333, 39, "Aug 08, 2025")
addEmote("Dance-If-Youre-The-Best-Dia-Delicia-Dance", 117033010486869, 39, "Aug 08, 2025")
addEmote("Moon-Walk", 79127989560307, 39, "Aug 08, 2025")
addEmote("unnamed", 3576823880, 39, "Aug 08, 2025")
addEmote("Spice-Floor-Call", 103399717097173, 39, "Aug 08, 2025")
addEmote("cute-n-timid-idle-profile-pose", 110252467018810, 39, "Aug 08, 2025")
addEmote("KATSEYE-Debut", 134531479515970, 39, "Aug 08, 2025")
addEmote("For-Eman", 86748908374413, 39, "Aug 08, 2025")
addEmote("Red-Carpet-Walk-Fortnite", 108683274449989, 39, "Aug 08, 2025")
addEmote("unnamed", 5104377791, 39, "Aug 08, 2025")
addEmote("KATSEYE-Gabriela", 115661091136535, 39, "Aug 08, 2025")
addEmote("unnamed", 5230661597, 39, "Aug 08, 2025")
addEmote("Victory-Dance", 77727141076962, 39, "Aug 08, 2025")
addEmote("Scary-tall-creature-transformation", 93875137466223, 39, "Aug 08, 2025")
addEmote("67-Emote-Meme", 85409308399700, 39, "Aug 08, 2025")
addEmote("Nope-Finger-emote", 77206866044608, 39, "Aug 08, 2025")
addEmote("feelin-myself-sway", 74941409284905, 39, "Aug 08, 2025")
addEmote("Coffin-Walkout", 117302755748327, 39, "Aug 08, 2025")
addEmote("Scene-Profile-Idle-Pose-Y2K", 125386993330077, 39, "Aug 08, 2025")
addEmote("SpiderMan-Hanging-Pose-Original", 110511723808460, 39, "Aug 08, 2025")
addEmote("Hear-Me-Now-Emote", 91110020647774, 39, "Aug 08, 2025")
addEmote("L-Dance", 114846964045392, 39, "Aug 08, 2025")
addEmote("SUIIIIII", 72049728640815, 39, "Aug 08, 2025")
addEmote("Stray-Kids-Do-It", 95256633886548, 39, "Aug 08, 2025")
addEmote("NewJeans-ETA", 94694691436126, 39, "Aug 08, 2025")
addEmote("Making-Faces", 89535391366809, 39, "Aug 08, 2025")
addEmote("e-dance2", 124072098165199, 39, "Aug 08, 2025")
addEmote("Springlock-animation", 132844034228766, 39, "Aug 08, 2025")
addEmote("Default-Dance-OG", 80877772569772, 39, "Aug 08, 2025")
addEmote("AURA-FARM-YN-Wall-Lean", 71556328869803, 39, "Aug 08, 2025")
addEmote("The-Tylil-Dance-Kai-Cenat-Dance", 107010273569673, 39, "Aug 08, 2025")
addEmote("Elton-John-Heart-Skip", 122501033570482, 39, "Aug 08, 2025")
addEmote("Get-The-Money-Flipping", 73264759706085, 39, "Aug 08, 2025")
addEmote("Vecna-Kill-from-Stranger-Things", 117380845844824, 39, "Aug 08, 2025")
addEmote("Be-tall-creature", 87939300658851, 39, "Aug 08, 2025")
addEmote("Sleeping-Angel", 100885431049593, 39, "Aug 08, 2025")
addEmote("Night-mail-Jig-You-Vs-Homer-Song", 84538571583014, 39, "Aug 08, 2025")
addEmote("Dancing-Like-Crazy", 123143445959707, 39, "Aug 08, 2025")
addEmote("HOT-Spinning-Cat", 75739251269771, 39, "Aug 08, 2025")
addEmote("Helicopter", 110553756436163, 39, "Aug 08, 2025")
addEmote("sharps-aware-of-it", 129802318248541, 39, "Aug 08, 2025")
addEmote("Hotel-Transylvania-macarena-dance", 81808860196321, 39, "Aug 08, 2025")
addEmote("FaSHioN-CORTIS", 118850907110385, 39, "Aug 08, 2025")
addEmote("Pasinho-do-Jamal", 71286446361487, 39, "Aug 08, 2025")
addEmote("STURDY", 120302905807132, 39, "Aug 08, 2025")
addEmote("IShowSpeed-Bounce-Dance", 140269876098643, 39, "Aug 08, 2025")
addEmote("Iconic-Pose", 107391441166760, 39, "Aug 08, 2025")
addEmote("Front-Flip", 116728799092339, 39, "Aug 08, 2025")
addEmote("cute-bouncy-anime-dance", 108845097487486, 39, "Aug 08, 2025")
addEmote("BEST-Keep-The-Money-Flipping", 106656731585855, 39, "Aug 08, 2025")
addEmote("Biblically-Accurate-Angel", 70544785852547, 39, "Aug 08, 2025")
addEmote("Nyan-Nyan", 73796726960568, 39, "Aug 08, 2025")
addEmote("LE-SSERAFIM-Spaghetti", 81216108771843, 39, "Aug 08, 2025")
addEmote("Baby-Boo-Head-Shake", 106259138660626, 39, "Aug 08, 2025")
addEmote("Sukuna-Aura-Farming", 73325949423853, 39, "Aug 08, 2025")
addEmote("Possessed", 102610758906338, 39, "Aug 08, 2025")
addEmote("Halloween-Headless-Floating-Aura", 73723042388431, 39, "Aug 08, 2025")
addEmote("Bruno-Best-Prime", 78395047278790, 39, "Aug 08, 2025")
addEmote("Trim-Boat-Dance", 115215660256998, 39, "Aug 08, 2025")
addEmote("kawai-shy-sit-idle-pose", 105933851371838, 39, "Aug 08, 2025")
addEmote("Headless", 74738520664045, 39, "Aug 08, 2025")
addEmote("Jojo-Torture-Dance", 82910305160190, 39, "Aug 08, 2025")
addEmote("Aura-Gainer", 125717501705233, 39, "Aug 08, 2025")
addEmote("Ice-Spice-Big-Guy-from-The-SpongeBob-Movie", 98380505334463, 39, "Aug 08, 2025")
addEmote("Snoops-Walk", 112458012124991, 39, "Aug 08, 2025")
addEmote("Stateside-PinkPantheress-Zara-Larsson", 85028685451071, 39, "Aug 08, 2025")
addEmote("Baby-Boo", 78477807923302, 39, "Aug 08, 2025")
addEmote("Emote-Loading-Please-Wait-spinning-Robloxian", 84511772437190, 39, "Aug 08, 2025")
addEmote("cutesie-shy-idle", 120389512169914, 39, "Aug 08, 2025")
addEmote("Da-Problem-Solva", 113967765277024, 39, "Aug 08, 2025")
addEmote("BEST-Sukuna-Aura-Farming", 122364140351186, 39, "Aug 08, 2025")
addEmote("L-Lawliet", 139435106875573, 39, "Aug 08, 2025")
addEmote("upside-down-kawaii-dance", 76649288846699, 39, "Aug 08, 2025")
addEmote("Best-All-Might-Victory-Pose-R6", 100416618991324, 39, "Aug 08, 2025")
addEmote("Low-Cortisol-Uma-Musume", 131650813068362, 39, "Aug 08, 2025")
addEmote("NO-NO-PLEASE-SIT-EMOTE", 87936851262558, 39, "Aug 08, 2025")
addEmote("Runny-Dance", 126226506101092, 39, "Aug 08, 2025")
addEmote("Gameboy-Katseye", 117453574553102, 39, "Aug 08, 2025")
addEmote("R6-Peanut-Butter-Jelly-Die-Of-Death", 100267888506831, 39, "Aug 08, 2025")
addEmote("Olivia-Rodrigo-Head-Bop-CHEAP", 79580284786292, 39, "Aug 08, 2025")
addEmote("apple-store-girl-do-you-want-me", 136290878980267, 39, "Aug 08, 2025")
addEmote("Just-Feeling-It", 134842828741769, 39, "Aug 08, 2025")
addEmote("Thank-You-Bow-Ladies-and-Gentlemen", 132566708912466, 39, "Aug 08, 2025")
addEmote("Louisiana-Jigg", 75625820126017, 39, "Aug 08, 2025")
addEmote("SHAKE", 132367660388476, 39, "Aug 08, 2025")
addEmote("Finger-Gun", 138671863009472, 39, "Aug 08, 2025")
addEmote("Rat-Dance-Meme", 79460913196046, 39, "Aug 08, 2025")
addEmote("Dance-If-Youre-The-Best-Dia-Delicia-Dance", 70955237174596, 39, "Aug 08, 2025")
addEmote("Follow-My-Attitude", 121555252693094, 39, "Aug 08, 2025")
addEmote("Fake-R15-Zombie-Run-Lag", 106878897156217, 39, "Aug 08, 2025")
addEmote("Sonic-the-Hedgehog-Super-Smash-Bro-Profile-Pose", 129850521517715, 39, "Aug 08, 2025")
addEmote("Tell-Me-Tell-Me-Wonder-Girls", 112118419325053, 39, "Aug 08, 2025")
addEmote("Baby-boo", 77019604823252, 39, "Aug 08, 2025")
addEmote("sitting-squat-idle-pose", 113960239878969, 39, "Aug 08, 2025")
addEmote("TYLA-CHANEL", 103284570577508, 39, "Aug 08, 2025")
addEmote("Cute-Baddie-Profile-Pose-3-0", 136040668407140, 39, "Aug 08, 2025")
addEmote("Hug-Player-1", 102303622774230, 39, "Aug 08, 2025")
addEmote("Jotaro-Pose-aura", 104330991197585, 39, "Aug 08, 2025")
addEmote("Sassy-Fashion-Twirl", 103924340632445, 39, "Aug 08, 2025")
addEmote("MM2-Dead-Troll-Front", 87240345883758, 39, "Aug 08, 2025")
addEmote("Become-Tall", 74601470677586, 39, "Aug 08, 2025")
addEmote("Louisiana-Jigg-2", 125646873823019, 39, "Aug 08, 2025")
addEmote("Dropkick", 127764273000599, 39, "Aug 08, 2025")
addEmote("Floating-Aura", 79795305221612, 39, "Aug 08, 2025")
addEmote("Cute-Kawaii-Shy-Doll-Stance", 78712622250645, 39, "Aug 08, 2025")
addEmote("Proud-Heel-Stretch", 137746067965316, 39, "Aug 08, 2025")
addEmote("sit", 120512834137418, 39, "Aug 08, 2025")
addEmote("67-Emote-Dynamic", 92707729249136, 39, "Aug 08, 2025")
addEmote("Show-work", 138056642423260, 39, "Aug 08, 2025")
addEmote("Tail-Wag-Happy-Idle", 71980669913244, 39, "Aug 08, 2025")
addEmote("unnamed", 4646306583, 39, "Aug 08, 2025")
addEmote("Vibing-Community-Animation-Aura-Idle", 70508706371253, 39, "Aug 08, 2025")
addEmote("Sukuna-Levitating", 127504816844209, 39, "Aug 08, 2025")
addEmote("Big-Back-Baby-Boo", 122461225964217, 39, "Aug 08, 2025")
addEmote("candy-cookie-chocolate-miku-teto", 121463501824419, 39, "Aug 08, 2025")
addEmote("67", 136415352218982, 39, "Aug 08, 2025")
addEmote("KATSEYE-TOUCH-CHEAP", 75916539353418, 39, "Aug 08, 2025")
addEmote("Gojo-Floating-JJK-The-Honored-One", 91085159191582, 39, "Aug 08, 2025")
addEmote("Aura-RNG-Fly-Idle", 78755795767408, 39, "Aug 08, 2025")
addEmote("super-shy-girly-idle-pose", 132436768198498, 39, "Aug 08, 2025")
addEmote("Hug", 102822553233176, 39, "Aug 08, 2025")
addEmote("Chubibi-Dance", 76881316748390, 39, "Aug 08, 2025")
addEmote("Hear-Me-Now", 78286660563122, 39, "Aug 08, 2025")
addEmote("Little-jumping-spider", 113184956127341, 39, "Aug 08, 2025")
addEmote("Tank", 85076031433488, 39, "Aug 08, 2025")
addEmote("Invisible-Glitch-Under", 83522304666655, 39, "Aug 08, 2025")
addEmote("Ninja-Run", 130349209708136, 39, "Aug 08, 2025")
addEmote("cute-gasp", 132029163919678, 39, "Aug 08, 2025")
addEmote("Fashionable-CHEAP", 93285483814710, 39, "Aug 08, 2025")
addEmote("Liberian-Girl-Dance", 105669548816007, 39, "Aug 08, 2025")
addEmote("Vogue-Crouch-Hop", 134741005624382, 39, "Aug 08, 2025")
addEmote("Spongebob", 123043305808890, 39, "Aug 08, 2025")
addEmote("Michael-Myers-dance", 83430340523948, 39, "Aug 08, 2025")
addEmote("Omni-Mark-Fly-Invincible", 123347895201748, 39, "Aug 08, 2025")
addEmote("Griddy-BEST", 77017926307035, 39, "Aug 08, 2025")
addEmote("unnamed", 4689362868, 39, "Aug 08, 2025")
addEmote("Panic-Run", 79338722896418, 39, "Aug 08, 2025")
addEmote("Lag-Troll", 129699021535316, 39, "Aug 08, 2025")
addEmote("AFK-Aura-Farm", 124573843932871, 39, "Aug 08, 2025")
addEmote("how-did-he-hit-every-beat", 134311528115559, 39, "Aug 08, 2025")
addEmote("Gojo-Pose-Floating", 125866557084286, 39, "Aug 08, 2025")
addEmote("Alibi-TikTok-Dance", 140278625941166, 39, "Aug 08, 2025")
addEmote("L-Sitting-Pose", 140187771377253, 39, "Aug 08, 2025")
addEmote("Sabrina-Carpenter-s-Manchild-Emote", 77684969500159, 39, "Aug 08, 2025")
addEmote("FORSAKEN-John-Doe-Pose", 104072580597361, 39, "Aug 08, 2025")
addEmote("Sweet-Sit-Pose-Ledge-sitting", 103541659586127, 39, "Aug 08, 2025")
addEmote("Headless", 118305672904748, 39, "Aug 08, 2025")
addEmote("R6-Califorina-Girls-Forsaken", 84430246447182, 39, "Aug 08, 2025")
addEmote("Slow-Run", 75638863960888, 39, "Aug 08, 2025")
addEmote("Invisible", 101801833201272, 39, "Aug 08, 2025")
addEmote("Low-Cortisol", 74477507917814, 39, "Aug 08, 2025")
addEmote("Cute-kicking-Feet-Sit", 130253041293561, 39, "Aug 08, 2025")
addEmote("Sleeping-Soundly", 104024961010344, 39, "Aug 08, 2025")
addEmote("Koto-Nai-Meme-Dance", 91927498467600, 39, "Aug 08, 2025")
addEmote("Smooth-Moonwalk", 105106008516273, 39, "Aug 08, 2025")
addEmote("Fake-MM2-Death", 107498554725527, 39, "Aug 08, 2025")
addEmote("Gangster-Delinquent-Crouch", 137201675761037, 39, "Aug 08, 2025")
addEmote("Catwalk-Walk-Emote-FIRST-OG", 138140141577966, 39, "Aug 08, 2025")
addEmote("Jason-Vorhees-Dance", 105465965520487, 39, "Aug 08, 2025")
addEmote("KATSEYE-Better-in-Denim-GAP", 86184456144623, 39, "Aug 08, 2025")
addEmote("Leaning-Against-Wall-Arms-Crossed", 77806145358673, 39, "Aug 08, 2025")
addEmote("Golden-dance-best", 77945789109199, 39, "Aug 08, 2025")
addEmote("Garrys-Dance-GMOD", 129861012882037, 39, "Aug 08, 2025")
addEmote("Cool-Backflip", 117168959477820, 39, "Aug 08, 2025")
addEmote("Car-Transforming", 79360981055415, 39, "Aug 08, 2025")
addEmote("Take-The-L", 112884830175040, 39, "Aug 08, 2025")
addEmote("Signature-Shuffle", 81442470330880, 39, "Aug 08, 2025")
addEmote("MM2-Fake-Dead-1", 103683627346536, 39, "Aug 08, 2025")
addEmote("Number-Groove", 99563926183536, 39, "Aug 08, 2025")
addEmote("Springtrap-Dance", 132007669525235, 39, "Aug 08, 2025")
addEmote("Fake-Dead-MM2-Troll", 80977642444765, 39, "Aug 08, 2025")
addEmote("Money-Hop-Spin", 126821507055878, 39, "Aug 08, 2025")
addEmote("Glitch-through-walls-phase", 132366431744296, 39, "Aug 08, 2025")
addEmote("xaviersobased", 139371349828009, 39, "Aug 08, 2025")
addEmote("Arona-Dance-Meme", 113818946774721, 39, "Aug 08, 2025")
addEmote("soft-elegant-stance", 90478555055303, 39, "Aug 08, 2025")
addEmote("Shuffling", 115925652377890, 39, "Aug 08, 2025")
addEmote("Im-Talm-Bout-Innit-OG", 117301403779781, 39, "Aug 08, 2025")
addEmote("Ketlin-Dance", 120769095541981, 39, "Aug 08, 2025")
addEmote("Logan-Paul-Splits-V2", 95567185677058, 39, "Aug 08, 2025")
addEmote("Macarena", 73946479113094, 39, "Aug 08, 2025")
addEmote("cute-floating-headless-head-aura-emote", 120175769260063, 39, "Aug 08, 2025")
addEmote("Party-Rock-Anthem", 105248382902194, 39, "Aug 08, 2025")
addEmote("Needy-Bouncy-Circle-Shake-Dance", 82054421592571, 39, "Aug 08, 2025")
addEmote("Gerakan-sholat-prayer-movement", 98257825446724, 39, "Aug 08, 2025")
addEmote("Flopping-Fish", 133142324349281, 39, "Aug 08, 2025")
addEmote("KATSEYE-Touch", 139021427684680, 39, "Aug 08, 2025")
addEmote("Funny-Goofy-Wiggle", 74277551575520, 39, "Aug 08, 2025")
addEmote("Sit", 90221568176994, 39, "Aug 08, 2025")
addEmote("Not-Cute-Anymore-Head-Grab", 107309201170195, 39, "Aug 08, 2025")
addEmote("BEST-Not-Cute-Anymore-KPop-Dance-ILLIT", 107753335763254, 39, "Aug 08, 2025")
addEmote("Cozy-Hug-Pose-V2-MATCHING", 135268727910642, 39, "Aug 08, 2025")
addEmote("Catwalk-Walk", 120380776076922, 39, "Aug 08, 2025")
addEmote("Sukuna-Aura-Pose", 138453007205351, 39, "Aug 08, 2025")
addEmote("Floating-on-clouds", 111426928948833, 39, "Aug 08, 2025")
addEmote("Run-R15-Fake-lag", 100297498958164, 39, "Aug 08, 2025")
addEmote("Childish-Tantrum", 130575801528647, 39, "Aug 08, 2025")
addEmote("La-anguila-hip-MEME", 103386082503086, 39, "Aug 08, 2025")
addEmote("Obby-Head-Emote", 122814100170962, 39, "Aug 08, 2025")
addEmote("Piccolo-Aura-Farm", 109174054880976, 39, "Aug 08, 2025")
addEmote("Freak-me", 137894800082618, 39, "Aug 08, 2025")
addEmote("NASA-ATEEZ", 85281009926245, 39, "Aug 08, 2025")
addEmote("PangYa-Dance-3-0", 95926267112611, 39, "Aug 08, 2025")
addEmote("Speed-Glitch", 137006085779408, 39, "Aug 08, 2025")
addEmote("Emergency-Hamburg-Fake-Dead", 117316258600620, 39, "Aug 08, 2025")
addEmote("chiwawa-just-dance", 81562978486917, 39, "Aug 08, 2025")
addEmote("Lush-Life-Zara-Larsson", 86074761718343, 39, "Aug 08, 2025")
addEmote("Belly-Dance", 76700167742736, 39, "Aug 08, 2025")
addEmote("Cry-For-Me", 109431734388411, 39, "Aug 08, 2025")
addEmote("OG-BEST-Missed-and-needy", 74359676673985, 39, "Aug 08, 2025")
addEmote("Throw-it-in-a-circle", 109933662337071, 39, "Aug 08, 2025")
addEmote("Rose-Gift", 132380943956928, 39, "Aug 08, 2025")
addEmote("Golden-Freddy-Pose", 71363859760586, 39, "Aug 08, 2025")
addEmote("Drop-It-Like-Its-Hot", 102620328010077, 39, "Aug 08, 2025")
addEmote("Upside-down-floating-AURA", 89468381929192, 39, "Aug 08, 2025")
addEmote("Rambunctious", 108128682361404, 39, "Aug 08, 2025")
addEmote("BEST-KATSEYE-TOUCH-CHEAP", 89292402527476, 39, "Aug 08, 2025")
addEmote("cute-doll-ballerina-music-box-spin", 111332667359868, 39, "Aug 08, 2025")
addEmote("DARE-Gorillaz", 88840501982686, 39, "Aug 08, 2025")
addEmote("Needy-Circle-Shake", 122412637906665, 39, "Aug 08, 2025")
addEmote("Kick", 108296873775004, 39, "Aug 08, 2025")
addEmote("Xaviersobased-Emote", 131763631172236, 39, "Aug 08, 2025")
addEmote("Sonic-Youre-Too-Slow-Animated-Face", 103737097131582, 39, "Aug 08, 2025")
addEmote("Godly-Aura-floating-Emote", 102392888934746, 39, "Aug 08, 2025")
addEmote("Shyest-Dolly-Wave-Pose", 78547057385680, 39, "Aug 08, 2025")
addEmote("Aura-Fly-Sitting", 72450410210932, 39, "Aug 08, 2025")
addEmote("Guts-Blackpowder-G-B-Soldier-Death-Infection", 140076995437875, 39, "Aug 08, 2025")
addEmote("Side-Sit", 85370173309996, 39, "Aug 08, 2025")
addEmote("Tokyo-Drift", 132117078415509, 39, "Aug 08, 2025")
addEmote("Jump-Spin-Animation", 99410306126683, 39, "Aug 08, 2025")
addEmote("CHROMATIC-Emote-Sols-RNG", 82019787808682, 39, "Aug 08, 2025")
addEmote("sharps-French-Confidence", 113927348020837, 39, "Aug 08, 2025")
addEmote("Needy-Shake-A-lot", 136972355790968, 39, "Aug 08, 2025")
addEmote("Ultra-Needy-Hula-Bouncing", 98265102369819, 39, "Aug 08, 2025")
addEmote("Uzi-What-You-Saying-Top-Rock", 89056890697781, 39, "Aug 08, 2025")
addEmote("Cute-crouch", 120224229260879, 39, "Aug 08, 2025")
addEmote("Biblically-Accurate-Emote", 118314972618293, 39, "Aug 08, 2025")
addEmote("Angel-Idle", 102042356672772, 39, "Aug 08, 2025")
addEmote("Secret-Handshake-Dance", 120642514156293, 39, "Aug 08, 2025")
addEmote("BOO-Emote-MATCHING-Version-1", 137681302976475, 39, "Aug 08, 2025")
addEmote("unnamed", 3716636630, 39, "Aug 08, 2025")
addEmote("Crossed-Arm-Hip-Sway", 122545939134570, 39, "Aug 08, 2025")
addEmote("Shy-Doll-Cute-Standing-Idle-Profile-Pose", 115140876718590, 39, "Aug 08, 2025")
addEmote("Cute-Sit", 82254629180336, 39, "Aug 08, 2025")
addEmote("sharps-No-Hands-dance", 130809010930827, 39, "Aug 08, 2025")
addEmote("Cut-Water-Summer-Dance", 133057926120618, 39, "Aug 08, 2025")
addEmote("Jumpstyle", 92031196891153, 39, "Aug 08, 2025")
addEmote("MM2-fake-dead-troll", 131830337253229, 39, "Aug 08, 2025")
addEmote("I-CAME-TO-GROOVE", 126910355078348, 39, "Aug 08, 2025")
addEmote("Stranger-Things-Vecna-Kill-Animation-Emote-Bone", 127869514812004, 39, "Aug 08, 2025")
addEmote("Golden-freddy-idle", 140677562143416, 39, "Aug 08, 2025")
addEmote("Gangnam-Style", 130998336536045, 39, "Aug 08, 2025")
addEmote("Heart", 84396003438766, 39, "Aug 08, 2025")
addEmote("Baby-Queen-Strut", 14353425085, 39, "Aug 08, 2025")
addEmote("Scene-Pose", 139344101676103, 39, "Aug 08, 2025")
addEmote("Mesmerizer", 92707348383277, 39, "Aug 08, 2025")
addEmote("Victory-Dance", 15506503658, 39, "Aug 08, 2025")
addEmote("Vecna-Ascension", 140009431016962, 39, "Aug 08, 2025")
addEmote("Vecna-Kill-Stranger-Things", 92263625511322, 39, "Aug 08, 2025")
addEmote("Cute-Needy-Shake-Dance", 101044624010591, 39, "Aug 08, 2025")
addEmote("Hide-INVISIBLE", 75549480144700, 39, "Aug 08, 2025")
addEmote("Aura-Float", 114469314321726, 39, "Aug 08, 2025")
addEmote("Inactivity-With-Arms-Crossed", 108771805233715, 39, "Aug 08, 2025")
addEmote("Lush-Life", 138629137053256, 39, "Aug 08, 2025")
addEmote("ORIGINAL-I-Want-Money-What-You-Want-EMOVA", 128258195574116, 39, "Aug 08, 2025")
addEmote("Cute-n-shy-Idle-Emote-Profile-Pose", 135994700702758, 39, "Aug 08, 2025")
addEmote("Parkour-Dance", 107950776282890, 39, "Aug 08, 2025")
addEmote("Very-Honored-One-Gojo-Pose-Emote", 116282660846752, 39, "Aug 08, 2025")
addEmote("Cute-Bouncy-Hip-Shake-Dance", 136548585666220, 39, "Aug 08, 2025")
addEmote("Jiggly-Shake-Dance", 112601777763518, 39, "Aug 08, 2025")
addEmote("Umamusume-Dance", 130838810836830, 39, "Aug 08, 2025")
addEmote("Fashionable-Pretty-Posing", 74039811415098, 39, "Aug 08, 2025")
addEmote("BEST-Rakai-Emote", 88486801093777, 39, "Aug 08, 2025")
addEmote("Street-Walks", 86016661283748, 39, "Aug 08, 2025")
addEmote("Back-Dance-Trend", 80242782087423, 39, "Aug 08, 2025")
addEmote("Hug", 90892690280238, 39, "Aug 08, 2025")
addEmote("Horse-Riding", 139922355534092, 39, "Aug 08, 2025")
addEmote("Head-Pat-High-Matching-Set", 120833029935011, 39, "Aug 08, 2025")
addEmote("Backflip", 91583499354581, 39, "Aug 08, 2025")
addEmote("I-see-Kareem-Groove", 75367995814880, 39, "Aug 08, 2025")
addEmote("cute-knee-sit-idle-pose", 72753598082403, 39, "Aug 08, 2025")
addEmote("V-Pose-Tommy-Hilfiger", 10214418283, 39, "Aug 08, 2025")
addEmote("Sit", 139621472081340, 39, "Aug 08, 2025")
addEmote("Sonic-Waiting-Idle-Foot-Tapping", 111788328933019, 39, "Aug 08, 2025")
addEmote("CUTE-Catwalk-Walk-Girly", 131907146446807, 39, "Aug 08, 2025")
addEmote("Realistic-Fake-Dead", 126053460371393, 39, "Aug 08, 2025")
addEmote("Spice-Happy-Jumping", 133319600812587, 39, "Aug 08, 2025")
addEmote("Vector-Dance-Oh-Yeah", 114992341935228, 39, "Aug 08, 2025")
addEmote("California-Girls", 130248288787333, 39, "Aug 08, 2025")
addEmote("cutesy-leaning-in-pose", 136029517194508, 39, "Aug 08, 2025")
addEmote("KSI-Wake-Up-Call", 107043196201393, 39, "Aug 08, 2025")
addEmote("Shake-That-THANG", 105348176695291, 39, "Aug 08, 2025")
addEmote("Floating-Throne-Aura-Pose", 93443111556634, 39, "Aug 08, 2025")
addEmote("Boogie-Down", 139570238573569, 39, "Aug 08, 2025")
addEmote("e-orbit", 91729309021707, 39, "Aug 08, 2025")
addEmote("cute-kawaii-hugging-and-kicking-feet", 117617643410205, 39, "Aug 08, 2025")
addEmote("invisible-me", 116830785054323, 39, "Aug 08, 2025")
addEmote("Denji-Dance", 126177445687241, 39, "Aug 08, 2025")
addEmote("the-moons-majestic-float", 100291371371, 39, "Aug 08, 2025")
addEmote("Stylish-Sit", 112035743224829, 39, "Aug 08, 2025")
addEmote("Hands-Up", 108894965141226, 39, "Aug 08, 2025")
addEmote("Needy-Balance", 128495402778736, 39, "Aug 08, 2025")
addEmote("True-Heart", 103168660352906, 39, "Aug 08, 2025")
addEmote("Hakari-Dance-FORSAKEN", 98901420955781, 39, "Aug 08, 2025")
addEmote("Needy-Circle-Shake-OG", 120674455567362, 39, "Aug 08, 2025")
addEmote("10K-Full-Masked-Mark-Pose-Day-3-Invincible", 100184686550276, 39, "Aug 08, 2025")
addEmote("Angel-Flying", 102256275785620, 39, "Aug 08, 2025")
addEmote("Agnes-Tachyons-Low-Cortisol-Dance-In-Tempo", 112396548575695, 39, "Aug 08, 2025")
addEmote("Boxing", 117648669357990, 39, "Aug 08, 2025")
addEmote("Arms-Crossed-Arms-Emote", 120083676685180, 39, "Aug 08, 2025")
addEmote("TWICE-The-Feels", 12874468267, 39, "Aug 08, 2025")
addEmote("KATSEYE-Gnarly-Dance-Break", 115663351458368, 39, "Aug 08, 2025")
addEmote("Wall-Lean", 88969192102242, 39, "Aug 08, 2025")
addEmote("Another-Jersey-Dance", 70992911118180, 39, "Aug 08, 2025")
addEmote("New-Jeans-Hype-Boy-Dance", 77813688815637, 39, "Aug 08, 2025")
addEmote("Gojo-Dead", 123470584988273, 39, "Aug 08, 2025")
addEmote("MM2-Dead", 139859849852362, 39, "Aug 08, 2025")
addEmote("unnamed", 3762654854, 39, "Aug 08, 2025")
addEmote("Upside-down-Floating-Aura", 115701544797833, 39, "Aug 08, 2025")
addEmote("unnamed", 5917570207, 39, "Aug 08, 2025")
addEmote("Michael-Myers-Pull-Dont-Hide-SHAKE-THAT-THANG", 116910531688978, 39, "Aug 08, 2025")
addEmote("cutest-doll-alive-idle-pose", 120609908538791, 39, "Aug 08, 2025")
addEmote("Strutting-fashion-catwalk", 96086661098597, 39, "Aug 08, 2025")
addEmote("Reze-Demon-bomb-Irish-Out-dance", 78554908864502, 39, "Aug 08, 2025")
addEmote("Freddy-Fazbear", 77781675717382, 39, "Aug 08, 2025")
addEmote("Katseye-Gnarly-Pop-Dance-Emote", 100829635809504, 39, "Aug 08, 2025")
addEmote("Triple-Roundhouse-Kick", 107652660092239, 39, "Aug 08, 2025")
addEmote("NEW-MM2-Fake-Dead-Emote", 94192417394459, 39, "Aug 08, 2025")
addEmote("unnamed", 3823158750, 39, "Aug 08, 2025")
addEmote("Speakerman-Dance", 116622848811955, 39, "Aug 08, 2025")
addEmote("Rakai-Emote", 135686271244127, 39, "Aug 08, 2025")
addEmote("BIGGEST-TALLEST-Ancient-Robloxian-GLITCH", 137432224827301, 39, "Aug 08, 2025")
addEmote("meow-kitty-cat-pose-3", 79458008243992, 39, "Aug 08, 2025")
addEmote("Gokus-Warmup", 108013663975520, 39, "Aug 08, 2025")
addEmote("Columbina-Banner-Cute-Pose-Genshin", 113128453547919, 39, "Aug 08, 2025")
addEmote("Sleeping-Sideways", 113546798537900, 39, "Aug 08, 2025")
addEmote("Hype-Boy-NewJeans", 122829513155529, 39, "Aug 08, 2025")
addEmote("kawaii-cute-pose", 99820024190123, 39, "Aug 08, 2025")
addEmote("BEST-Cry-for-me-IronMouse-Emote", 107250395265289, 39, "Aug 08, 2025")
addEmote("Cute-Head-Tilt-Idle-Pose", 114854634677146, 39, "Aug 08, 2025")
addEmote("Big-G-Bounce", 70975021709810, 39, "Aug 08, 2025")
addEmote("Coco-Chanel-Dance", 77712734819728, 39, "Aug 08, 2025")
addEmote("Gojo-Aka-Stance", 87282253113789, 39, "Aug 08, 2025")
addEmote("Luffy-Gear-5-Laugh-High-Quality", 106008592717540, 39, "Aug 08, 2025")
addEmote("Electro-Shuffle", 96426537876059, 39, "Aug 08, 2025")
addEmote("Honor-Knight-Kneel", 103663987050338, 39, "Aug 08, 2025")
addEmote("Folks-Drop-Moves", 108148450243742, 39, "Aug 08, 2025")
addEmote("Low-Cortisol-Dance-Pill", 125822752810863, 39, "Aug 08, 2025")
addEmote("e-dance1", 122117255044047, 39, "Aug 08, 2025")
addEmote("Baby-Queen-Face-Frame", 82960976595139, 39, "Aug 08, 2025")
addEmote("Eleven-Stranger-Things-5", 129735512772535, 39, "Aug 08, 2025")
addEmote("cute-nezuko-kicks-in-air", 100382290818719, 39, "Aug 08, 2025")
addEmote("Dare", 105777132167560, 39, "Aug 08, 2025")
addEmote("Sit-Comfy-Idle", 91223337249721, 39, "Aug 08, 2025")
addEmote("R15-Lag-Run-In-Place", 135972207788206, 39, "Aug 08, 2025")
addEmote("Creepy-Ventriloquist-Puppet", 95800106960533, 39, "Aug 08, 2025")
addEmote("withered-animatronic-glitching", 82811393594073, 39, "Aug 08, 2025")
addEmote("Bubbly-Sit-3-0", 82070133181200, 39, "Aug 08, 2025")
addEmote("Jumpstyle-Dance", 75044579039280, 39, "Aug 08, 2025")
addEmote("KATSEYE-TOUCH", 73240117461226, 39, "Aug 08, 2025")
addEmote("Sonic-Adventure-Pose", 134310009143544, 39, "Aug 08, 2025")
addEmote("FNaF-Jumpscare", 114306032029835, 39, "Aug 08, 2025")
addEmote("i-dle-Good-Thing-Miyeon", 79310701050039, 39, "Aug 08, 2025")
addEmote("OG-Military-Dance", 79318911527752, 39, "Aug 08, 2025")
addEmote("Like-Jennie-Dance-from-JENNIE", 92224509275999, 39, "Aug 08, 2025")
addEmote("Toot-it-up-big-boogie", 90195580843776, 39, "Aug 08, 2025")
addEmote("Invisible", 128595337792281, 39, "Aug 08, 2025")
addEmote("cute-bossy-girl-pose", 135078245258688, 39, "Aug 08, 2025")
addEmote("Druski-Dance", 120990801438458, 39, "Aug 08, 2025")
addEmote("Sponge-Dance", 127562928814775, 39, "Aug 08, 2025")
addEmote("murder-drone-gun-shooting", 100945028567309, 39, "Aug 08, 2025")
addEmote("Relaxed-Sit", 99568437064777, 39, "Aug 08, 2025")
addEmote("Druski-Pop-Out", 98405298116702, 39, "Aug 08, 2025")
addEmote("kawaii-plushie-hug-idle-pose", 110116680249979, 39, "Aug 08, 2025")
addEmote("Hands-in-pockets-Idle-pose", 73197645333580, 39, "Aug 08, 2025")
addEmote("Push-Up", 98401523334482, 39, "Aug 08, 2025")
addEmote("Atmosphere-Fortnite-FISHER-Kita-Alexander", 115155833649719, 39, "Aug 08, 2025")
addEmote("Forsaken-Mafiaso-Pose", 121613692928115, 39, "Aug 08, 2025")
addEmote("Hug", 125491951751014, 39, "Aug 08, 2025")
addEmote("Aura-Floating-Anime-BEST", 117275009351711, 39, "Aug 08, 2025")
addEmote("BEST-Big-Guy-Spongebob-Emote", 111199044176736, 39, "Aug 08, 2025")
addEmote("Nicki-Minaj-Boom-Boom-Boom", 104447515130416, 39, "Aug 08, 2025")
addEmote("Deltarune-Tenna-Kick", 111434734435321, 39, "Aug 08, 2025")
addEmote("Frosty-Flair-Tommy-Hilfiger", 10214406616, 39, "Aug 08, 2025")
addEmote("Graceful-idle-stand", 121368094576793, 39, "Aug 08, 2025")
addEmote("Shake-A-lot", 126757061236585, 39, "Aug 08, 2025")
addEmote("Billy-Bounce", 93450937830334, 39, "Aug 08, 2025")
addEmote("Rakai-Dance", 132617851151069, 39, "Aug 08, 2025")
addEmote("RAPID-FIRE-Gun-Morph", 73562814360939, 39, "Aug 08, 2025")
addEmote("Sitting-Sad", 124300863605270, 39, "Aug 08, 2025")
addEmote("flawless-stretch", 108365468911712, 39, "Aug 08, 2025")
addEmote("SPIDERMAN-POSE", 112354510576428, 39, "Aug 08, 2025")
addEmote("Silly-Animals-Dance", 70888470847518, 39, "Aug 08, 2025")
addEmote("Swinging", 103664927117916, 39, "Aug 08, 2025")
addEmote("Dancing-with-your-eyes-closed", 129637389787927, 39, "Aug 08, 2025")
addEmote("Angel-Sleeping-On-Clouds-floating-matching", 73154622529656, 39, "Aug 08, 2025")
addEmote("Ronaldo-Siuuu-Celebration", 107447321843426, 39, "Aug 08, 2025")
addEmote("Confident-Needy-Hip-Shake-Dance", 104185522465141, 39, "Aug 08, 2025")
addEmote("I-See-Kareem-Ice-Cream-Dance", 114627981853628, 39, "Aug 08, 2025")
addEmote("get-in-dea-bow-dance-trend-OG", 111102342306593, 39, "Aug 08, 2025")
addEmote("Head-scratches-Head-pats", 123663633846435, 39, "Aug 08, 2025")
addEmote("head-spin", 140466682449054, 39, "Aug 08, 2025")
addEmote("Waist-Mover", 84963773283176, 39, "Aug 08, 2025")
addEmote("Bang-Head-on-Wall", 90144236147420, 39, "Aug 08, 2025")
addEmote("Hands-Behind-Back", 113307296054375, 39, "Aug 08, 2025")
addEmote("MEGA-POOPING-AURA", 106880906271071, 39, "Aug 08, 2025")
addEmote("Cute-Kneeling-Down-Pose", 111296244825220, 39, "Aug 08, 2025")
addEmote("Make-You-Mine", 104485625389237, 39, "Aug 08, 2025")
addEmote("cute-sit", 131875333242836, 39, "Aug 08, 2025")
addEmote("Honored-Gojo-Idle", 128399543093532, 39, "Aug 08, 2025")
addEmote("Floating-Goddess-Matching-Floating-Adonis", 106454952665088, 39, "Aug 08, 2025")
addEmote("The-Weeknd-Starboy-Strut", 93848080698617, 39, "Aug 08, 2025")
addEmote("e-fling-BEST", 77917153071278, 39, "Aug 08, 2025")
addEmote("Vogue-Dip", 110881393097630, 39, "Aug 08, 2025")
addEmote("Scene-Roblox-Profile-Pose", 108221503648290, 39, "Aug 08, 2025")
addEmote("Needy-Bouncy-Circle-Shake-Dance", 84829262714821, 39, "Aug 08, 2025")
addEmote("OG-shake-dat", 78257055566260, 39, "Aug 08, 2025")
addEmote("Reze-Head-Drop", 106319524593169, 39, "Aug 08, 2025")
addEmote("Needy-Bouncy-Circle-Shake-Dance", 130734690490694, 39, "Aug 08, 2025")
addEmote("Metro-Man-arm-swings", 136271269847411, 39, "Aug 08, 2025")
addEmote("Kawaii-Headless-Holding-Head-Idle-Emote", 101446789686277, 39, "Aug 08, 2025")
addEmote("Obby-Head-Original-Emote", 119008007290744, 39, "Aug 08, 2025")
addEmote("BEST-Chinese-Dance", 97873619254796, 39, "Aug 08, 2025")
addEmote("e-sit", 129668542320076, 39, "Aug 08, 2025")
addEmote("I-See-Kareem-Dance", 100738069927436, 39, "Aug 08, 2025")
addEmote("R6-Happy-Halloween-Junky-Dance", 99824709685353, 39, "Aug 08, 2025")
addEmote("Levitation-Idle-Emote-2", 111499780397123, 39, "Aug 08, 2025")
addEmote("Ya-Ya-Ying-Emote", 112401736043867, 39, "Aug 08, 2025")
addEmote("Real-Drill-Emote", 84358634772535, 39, "Aug 08, 2025")
addEmote("Catwalk-Walk", 90842406727178, 39, "Aug 08, 2025")
addEmote("zesty-sturdy", 136037836393259, 39, "Aug 08, 2025")
addEmote("Happy-Hula", 113863828896103, 39, "Aug 08, 2025")
addEmote("Slow-Mo-Backflip-IShowSpeed-Flip-NEW", 86617727183442, 39, "Aug 08, 2025")
addEmote("Chk-Chk-Boom-Stray-kids", 95574717600502, 39, "Aug 08, 2025")
addEmote("Nagi-Seishiros-Celebration", 94925651501842, 39, "Aug 08, 2025")
addEmote("e-fly", 90385667351403, 39, "Aug 08, 2025")
addEmote("Sturdy-Dance", 85608190427964, 39, "Aug 08, 2025")
addEmote("color-mixing-3-0-OG", 95881746966543, 39, "Aug 08, 2025")
addEmote("Vem-ca-nenem", 114625666693684, 39, "Aug 08, 2025")
addEmote("KAPOW-boxing-fighting-punching", 126475463257664, 39, "Aug 08, 2025")
addEmote("TYLA-CHANEL-TIKTOK-DANCE", 131260558736428, 39, "Aug 08, 2025")
addEmote("Laughing-It-Up-Emote", 122240620529815, 39, "Aug 08, 2025")
addEmote("Halloween-Headless-Effortless-Aura", 94684994062212, 39, "Aug 08, 2025")
addEmote("Uzi-Quickstep-Top-Rock", 89982755945108, 39, "Aug 08, 2025")
addEmote("Iconic-Fashion-Model-Idle-Pose", 80004965633316, 39, "Aug 08, 2025")
addEmote("BEST-Rampage-Dance", 130425635204539, 39, "Aug 08, 2025")
addEmote("Floating-Aura-Pose", 99436360152977, 39, "Aug 08, 2025")
addEmote("Buss-It", 131407261984740, 39, "Aug 08, 2025")
addEmote("Mm2-Fake-Dead", 115791293073752, 39, "Aug 08, 2025")
addEmote("Car-Pose-Crossed-Arms-Lean-1-0", 91750347528761, 39, "Aug 08, 2025")
addEmote("R6-Die-of-Death-Squingle-Emote", 120729591181174, 39, "Aug 08, 2025")
addEmote("Michael-Jackson", 122773107025712, 39, "Aug 08, 2025")
addEmote("No-Head-Aura-Headless", 119380772256211, 39, "Aug 08, 2025")
addEmote("Cute-Needy-Jiggly-Shake-Dance", 94282969676283, 39, "Aug 08, 2025")
addEmote("Bust-A-Move", 80984120283465, 39, "Aug 08, 2025")
addEmote("Otsukare-summer", 111032510525800, 39, "Aug 08, 2025")
addEmote("CHEAP-Baby-Boo-Dance", 102762688954029, 39, "Aug 08, 2025")
addEmote("Absolute-Sadness", 92893440808720, 39, "Aug 08, 2025")
addEmote("CRY-FOR-ME-WA-WA-WA-ironmouse", 137589172925342, 39, "Aug 08, 2025")
addEmote("Tall", 104614476333324, 39, "Aug 08, 2025")
addEmote("KATSEYE-Debut", 87052392132964, 39, "Aug 08, 2025")
addEmote("Miss-The-Quiet-BEST", 136936175263593, 39, "Aug 08, 2025")
addEmote("Matching-Hug-1", 83878498166514, 39, "Aug 08, 2025")
addEmote("Big-G-Rilla-Step", 78512766320761, 39, "Aug 08, 2025")
addEmote("Breaking-News", 86357701927495, 39, "Aug 08, 2025")
addEmote("7-Rings-Dance", 127478024269658, 39, "Aug 08, 2025")
addEmote("FF-LOL-Laugh", 129709531895539, 39, "Aug 08, 2025")
addEmote("Mae-Stephens-Piano-Hands", 16553249658, 39, "Aug 08, 2025")
addEmote("NEW-Runway-Diva", 110724441263151, 39, "Aug 08, 2025")
addEmote("Angry-Idle", 91171596265030, 39, "Aug 08, 2025")
addEmote("67-Six-Seven", 92118471015650, 39, "Aug 08, 2025")
addEmote("Vem-Ca-N-nem-roblox-dance", 95077257202379, 39, "Aug 08, 2025")
addEmote("Popular", 90880350857136, 39, "Aug 08, 2025")
addEmote("Dont-Start-Now-Dua-Lipa", 72150908678645, 39, "Aug 08, 2025")
addEmote("Deep-Handstand", 126841464304530, 39, "Aug 08, 2025")
addEmote("FNAF-Burger-King-BK-Worker-Cringe-Poses", 126292183096601, 39, "Aug 08, 2025")
addEmote("Griddy", 106715239721951, 39, "Aug 08, 2025")
addEmote("MM2-Fake-Dead-8", 112853235929871, 39, "Aug 08, 2025")
addEmote("Spin-Around-with-a-Friend-Matching-Original", 74809337211634, 39, "Aug 08, 2025")
addEmote("Cute-Floating-Fly", 138591023414678, 39, "Aug 08, 2025")
addEmote("Big-Guy-Ice-Spice-Spongebob-Emote", 88312828363279, 39, "Aug 08, 2025")
addEmote("Needy-Circle-Shake-OG", 138909713751559, 39, "Aug 08, 2025")
addEmote("Aura-Idle", 82096188761745, 39, "Aug 08, 2025")
addEmote("Confess-to-Me", 105722319548703, 39, "Aug 08, 2025")
addEmote("Cute-Cat-Pose-Stretching", 83317461794376, 39, "Aug 08, 2025")
addEmote("headless", 72085274202521, 39, "Aug 08, 2025")
addEmote("Go-Mufasa", 94118707925458, 39, "Aug 08, 2025")
addEmote("e-Fly-Admin-Troll", 86509596528246, 39, "Aug 08, 2025")
addEmote("Piggyback-Ride-V1-MATCHING", 123355126614341, 39, "Aug 08, 2025")
addEmote("Voy-todo-de-LV", 135700126407255, 39, "Aug 08, 2025")
addEmote("Sukuna-Aura-Pose", 122409062451923, 39, "Aug 08, 2025")
addEmote("Six-Little-Eggs-Groove", 123988879773845, 39, "Aug 08, 2025")
addEmote("OneyPlays-Dance", 111085939371731, 39, "Aug 08, 2025")
addEmote("Metal-Sonic-Idle-Foot-Tapping", 94335035674143, 39, "Aug 08, 2025")
addEmote("Lightning-kicks", 73314763197767, 39, "Aug 08, 2025")
addEmote("Hugh-Morris-I-feel-a-bit-more-like-myself", 77844281301509, 39, "Aug 08, 2025")
addEmote("JUMPSTYLE-FALL-FROM-THE-SKY", 85528043259864, 39, "Aug 08, 2025")
addEmote("Naruto-Run", 120668080412453, 39, "Aug 08, 2025")
addEmote("Chill-Sit", 79192067640111, 39, "Aug 08, 2025")
addEmote("Ima-sit-back-Baddie-Emote", 74726067041025, 39, "Aug 08, 2025")
addEmote("Cuco-Levitate", 15698511500, 39, "Aug 08, 2025")
addEmote("Skeleton-Banging-Shield-FULL-VER", 84422432225920, 39, "Aug 08, 2025")
addEmote("Rakai-Emote", 116926550255088, 39, "Aug 08, 2025")
addEmote("BEST-Bakugo-Victory-Pose-R6", 73367008285102, 39, "Aug 08, 2025")
addEmote("Worm-Spin-Idle-Endless", 85901237132360, 39, "Aug 08, 2025")
addEmote("kawaii-cute-cat-girl-pose-idle", 138487798883208, 39, "Aug 08, 2025")
addEmote("cute-standing-idle-pose", 82392144297414, 39, "Aug 08, 2025")
addEmote("Michael-Myers-Goofy-Shake-Dance-ORIGINAL", 122090251208106, 39, "Aug 08, 2025")
addEmote("Take-The-L-Meme-Emote", 133545170540942, 39, "Aug 08, 2025")
addEmote("Say-The-Word-On-Beat", 124952219762093, 39, "Aug 08, 2025")
addEmote("Bouncy-anime-shake", 98451334551447, 39, "Aug 08, 2025")
addEmote("LIMITED-Cute-Bubbly-Sit-Kawaii-Love-Sway", 71020762961324, 39, "Aug 08, 2025")
addEmote("Michael-Jackson-Anti-Gravity-Lean", 104974397351883, 39, "Aug 08, 2025")
addEmote("Body-Phone", 107521111297353, 39, "Aug 08, 2025")
addEmote("Logan-Paul-Splits", 135583314999205, 39, "Aug 08, 2025")
addEmote("Eleven-Wipes-Blood", 106321426291108, 39, "Aug 08, 2025")
addEmote("unnamed", 3576717965, 39, "Aug 08, 2025")
addEmote("Stranger-things", 100135446186821, 39, "Aug 08, 2025")
addEmote("Hug-Player-2", 105879715898474, 39, "Aug 08, 2025")
addEmote("Mikus-Mesmerizer", 83716500004313, 39, "Aug 08, 2025")
addEmote("sponge-dance", 76566714680805, 39, "Aug 08, 2025")
addEmote("cute-bossy-sassy-girl-idle-pose", 137909901344953, 39, "Aug 08, 2025")
addEmote("Arthur-Morgan-Coughing", 84293478473291, 39, "Aug 08, 2025")
addEmote("Sit", 127998433031434, 39, "Aug 08, 2025")
addEmote("Michael-Myers", 111606146189778, 39, "Aug 08, 2025")
addEmote("Meow-Meow", 71666111389227, 39, "Aug 08, 2025")
addEmote("e-invisible", 81231476708586, 39, "Aug 08, 2025")
addEmote("OG-brooklyn-pop-kawaii-hip-swing-dance", 104060042886647, 39, "Aug 08, 2025")
addEmote("Billy-Bounce-2-0", 79167827943499, 39, "Aug 08, 2025")
addEmote("MM2-Dead-Troll", 95877955786500, 39, "Aug 08, 2025")
addEmote("I-WANNA-RUN-AWAY", 96361347184349, 39, "Aug 08, 2025")
addEmote("Mannrobics-TF2", 83702306317443, 39, "Aug 08, 2025")
addEmote("MM2-fake-dead-troll", 110508042978165, 39, "Aug 08, 2025")
addEmote("Naoyas-Hair-Flick-Jujutsu-Kaisen", 133934304718353, 39, "Aug 08, 2025")
addEmote("Nonchalant-Aura-Filled-Dance", 80035199697503, 39, "Aug 08, 2025")
addEmote("unnamed", 4849499887, 39, "Aug 08, 2025")
addEmote("walk-LAG", 139238382218654, 39, "Aug 08, 2025")
addEmote("Chinese-Dance", 120605439830304, 39, "Aug 08, 2025")
addEmote("Alo-Yoga-Pose-Lotus-Position", 12507097350, 39, "Aug 08, 2025")
addEmote("True-Heart", 109608096496039, 39, "Aug 08, 2025")
addEmote("Work-It", 127422170075608, 39, "Aug 08, 2025")
addEmote("MM2-Dead-Troll-Back-V2", 98656161779096, 39, "Aug 08, 2025")
addEmote("Cat-Pose", 83894207122751, 39, "Aug 08, 2025")
addEmote("Baby-Queen-Bouncy-Twirl", 105545983526812, 39, "Aug 08, 2025")
addEmote("67", 120007956256550, 39, "Aug 08, 2025")
addEmote("Springlock-Animatronic", 93454485169561, 39, "Aug 08, 2025")
addEmote("unnamed", 7466046574, 39, "Aug 08, 2025")
addEmote("JOJO-Pose-Jotaro", 104929891852793, 39, "Aug 08, 2025")
addEmote("e-Dance2-R6", 114061214009705, 39, "Aug 08, 2025")
addEmote("Forsaken-Guest-666-Furry-Old-Running-Animation", 128650099590921, 39, "Aug 08, 2025")
addEmote("Guts-Blackpowder-G-B-Soldier-Broken-Leg", 139358744018569, 39, "Aug 08, 2025")
addEmote("Yuji-Itadori-vs-Mahito-Skyfall-Walk-Sukuna-Gojo", 107775678918392, 39, "Aug 08, 2025")
addEmote("Forsaken-c00lkidd-Walk", 103108206614856, 39, "Aug 08, 2025")
addEmote("Knife-ENHYPEN", 103137318710787, 39, "Aug 08, 2025")
addEmote("Gnarly-Gang-Gang-Gang-Dance", 79596845539490, 39, "Aug 08, 2025")
addEmote("Cute-Bouncy-Needy-Shake-Dance", 92213847369194, 39, "Aug 08, 2025")
addEmote("R6-Subject-Three-Forsaken", 95568556018445, 39, "Aug 08, 2025")
addEmote("LIMITED-Relaxed-Float-Aura", 110591390100768, 39, "Aug 08, 2025")
addEmote("Stranger-Things", 71912141865439, 39, "Aug 08, 2025")
addEmote("Spicy-Needy-Shake-Dance", 100235448908778, 39, "Aug 08, 2025")
addEmote("Laying-Down-Splits-Pose", 119973148778428, 39, "Aug 08, 2025")
addEmote("Headless-Aura-fly-pose-idle", 89463618231199, 39, "Aug 08, 2025")
addEmote("Halloween-Ghost-Float", 82736455463728, 39, "Aug 08, 2025")
addEmote("Dab-Classic", 10293847566547, 39, "Aug 08, 2025")
    local function EmotesLoaded()
        for _, loaded in pairs(LoadedEmotes) do
            if not loaded then
                return false
            end
        end
        return true
    end
    while not EmotesLoaded() do
        task.wait()
    end
    Loading:Destroy()
    table.sort(Emotes, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    if isfile("FavoritedEmotes.txt") then
        local success, data = pcall(function()
            return HttpService:JSONDecode(readfile("FavoritedEmotes.txt"))
        end)
        if success and data then
            FavoritedEmotes = data
        else
            FavoritedEmotes = {}
        end
    else
        writefile("FavoritedEmotes.txt", HttpService:JSONEncode(FavoritedEmotes))
    end
    local UpdatedFavorites = {}
    for _, id in pairs(FavoritedEmotes) do
        if typeof(id) == "number" then
            table.insert(UpdatedFavorites, id)
        elseif typeof(id) == "string" then
            for _, emote in pairs(Emotes) do
                if emote.name == id then
                    table.insert(UpdatedFavorites, emote.id)
                    break
                end
            end
        end
    end
    if #UpdatedFavorites > 0 then
        FavoritedEmotes = UpdatedFavorites
        writefile("FavoritedEmotes.txt", HttpService:JSONEncode(FavoritedEmotes))
    end
    local function CharacterAdded(Character)
        for _, v in pairs(Frame:GetChildren()) do
            if not v:IsA("UIGridLayout") then
                v:Destroy()
            end
        end
        local Humanoid = WaitForChildOfClass(Character, "Humanoid")
        local Description = Humanoid:WaitForChild("HumanoidDescription", 5) or Instance.new("HumanoidDescription", Humanoid)
        local randomButton = Instance.new("TextButton")
        local ratio = Instance.new("UIAspectRatioConstraint")
        ratio.AspectType = Enum.AspectType.ScaleWithParentSize
        ratio.Parent = randomButton
        randomButton.LayoutOrder = 0
        randomButton.TextColor3 = Color3.new(1, 1, 1)
        randomButton.BorderSizePixel = 0
        randomButton.BackgroundTransparency = 0.5
        randomButton.BackgroundColor3 = Color3.new(0, 0, 0)
        randomButton.TextScaled = true
        randomButton.Text = "Random"
        randomButton:SetAttribute("name", "")
        Corner:Clone().Parent = randomButton
        randomButton.MouseButton1Click:Connect(function()
            if #Emotes > 0 then
                local randomEmote = Emotes[math.random(1, #Emotes)]
                PlayEmote(randomEmote.name, randomEmote.id)
            end
        end)
        randomButton.MouseEnter:Connect(function()
            EmoteName.Text = "Random"
        end)
        randomButton.Parent = Frame
        for i, Emote in pairs(Emotes) do
            pcall(function()
                Description:AddEmote(Emote.name, Emote.id)
            end)
            local EmoteButton = Instance.new("ImageButton")
            local IsFavorited = table.find(FavoritedEmotes, Emote.id)
            EmoteButton.LayoutOrder = i + ((IsFavorited and 0) or #Emotes)
            EmoteButton.Name = tostring(Emote.id)
            EmoteButton:SetAttribute("name", Emote.name)
            Corner:Clone().Parent = EmoteButton
            EmoteButton.Image = Emote.icon
            EmoteButton.BackgroundTransparency = 0.5
            EmoteButton.BackgroundColor3 = Color3.new(0, 0, 0)
            EmoteButton.BorderSizePixel = 0
            ratio:Clone().Parent = EmoteButton
            local EmoteNumber = Instance.new("TextLabel")
            EmoteNumber.Name = "number"
            EmoteNumber.TextScaled = true
            EmoteNumber.BackgroundTransparency = 1
            EmoteNumber.TextColor3 = Color3.new(1, 1, 1)
            EmoteNumber.BorderSizePixel = 0
            EmoteNumber.AnchorPoint = Vector2.new(0.5, 0.5)
            EmoteNumber.Size = UDim2.new(0.2, 0, 0.2, 0)
            EmoteNumber.Position = UDim2.new(0.1, 0, 0.9, 0)
            EmoteNumber.Text = tostring(i)
            EmoteNumber.TextXAlignment = Enum.TextXAlignment.Center
            EmoteNumber.TextYAlignment = Enum.TextYAlignment.Center
            local UIStroke = Instance.new("UIStroke")
            UIStroke.Transparency = 0.5
            UIStroke.Parent = EmoteNumber
            EmoteNumber.Parent = EmoteButton
            EmoteButton.Parent = Frame
            EmoteButton.MouseButton1Click:Connect(function()
                PlayEmote(Emote.name, Emote.id)
            end)
            EmoteButton.MouseEnter:Connect(function()
                EmoteName.Text = Emote.name
            end)
            local Favorite = Instance.new("ImageButton")
            Favorite.Name = "favorite"
            Favorite.Image = IsFavorited and FavoriteOn or FavoriteOff
            Favorite.AnchorPoint = Vector2.new(0.5, 0.5)
            Favorite.Size = UDim2.new(0.4, 0, 0.4, 0)
            Favorite.Position = UDim2.new(0.9, 0, 0.9, 0)
            Favorite.BorderSizePixel = 0
            Favorite.BackgroundTransparency = 1
            Favorite.Parent = EmoteButton
            Favorite.MouseButton1Click:Connect(function()
                local index = table.find(FavoritedEmotes, Emote.id)
                if index then
                    table.remove(FavoritedEmotes, index)
                    Favorite.Image = FavoriteOff
                    EmoteButton.LayoutOrder = i + #Emotes
                else
                    table.insert(FavoritedEmotes, Emote.id)
                    Favorite.Image = FavoriteOn
                    EmoteButton.LayoutOrder = i
                end
                pcall(function()
                    writefile("FavoritedEmotes.txt", HttpService:JSONEncode(FavoritedEmotes))
                end)
                if FavoritesFrame.Visible then
                    EmoteButton.Visible = table.find(FavoritedEmotes, Emote.id) ~= nil
                end
            end)
        end
        for i = 1, 9 do
            local filler = Instance.new("Frame")
            filler.LayoutOrder = 2147483647
            filler.Name = "filler"
            filler.BackgroundTransparency = 1
            filler.BorderSizePixel = 0
            ratio:Clone().Parent = filler
            filler.Visible = true
            filler.Parent = Frame
            filler.MouseEnter:Connect(function()
                EmoteName.Text = "Select an Emote"
            end)
        end
    end
    if LocalPlayer.Character then
        CharacterAdded(LocalPlayer.Character)
    end
    LocalPlayer.CharacterAdded:Connect(CharacterAdded)
    wait(1)
    if game.CoreGui:FindFirstChild("Emotes") then
        game.CoreGui.Emotes.Enabled = true
    end
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Done!",
        Text = "Emotes gui is here!",
        Duration = 10
    })
    pcall(function()
        game.Players.LocalPlayer.PlayerGui.ContextActionGui:Destroy()
    end)
end
do
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        task.wait(2)
    end)
end
local function startAntiFall(character)
    if antiFallConnection and antiFallConnection.Connected then
        antiFallConnection:Disconnect()
    end
    antiFallConnection = RunService.Heartbeat:Connect(function()
        if not antiFallEnabled then return end
        if not character or not character.Parent then return end
        local root = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not root or not humanoid or humanoid.Health <= 0 then return end
        local respawnPos, baseY = getRespawnPosition()
        if root.Position.Y < baseY then
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            character:PivotTo(CFrame.new(respawnPos))
        end
    end)
end
local function stopAntiFall()
    if antiFallConnection and antiFallConnection.Connected then
        antiFallConnection:Disconnect()
        antiFallConnection = nil
    end
end
-- Unanchor
local function cancelAnchored()
    local character = LocalPlayer.Character
    if character then
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") then
                part.Anchored = false
            end
        end
        Message("Unanchor", "All character parts have been unanchored", 2)
    else
        Message("Unanchor", "Character not found", 3)
    end
end
-- View Player Data
local function loadAndRunPlayerDataScript()
    local localization = {
        MaxSize = "MaxSize",
        Speed = "Speed",
        Multiplier = "Multiplier",
        EatSpeed = "EatSpeed",
    }
    local function sizeGrowth(level)
        return math.floor(((level + 0.5) ^ 2 - 0.25) / 2 * 100)
    end
    local function speedGrowth(level)
        return math.floor(level * 2 + 10)
    end
    local function multiplierGrowth(level)
        return math.floor(level)
    end
    local function eatSpeedGrowth(level)
        return math.floor((1 + (level - 1) * 0.2) * 10) / 10
    end
    local function sizePrice(level)
        return math.floor(level ^ 3 / 2) * 20
    end
    local function speedPrice(level)
        return math.floor((level * 3) ^ 3 / 200) * 1000
    end
    local function multiplierPrice(level)
        return math.floor((level * 10) ^ 3 / 200) * 1000
    end
    local function eatSpeedPrice(level)
        return math.floor((level * 10) ^ 3 / 200) * 2000
    end
    local growthFunctions = {
        MaxSize = sizeGrowth,
        Speed = speedGrowth,
        Multiplier = multiplierGrowth,
        EatSpeed = eatSpeedGrowth,
    }
    local priceFunctions = {
        MaxSize = sizePrice,
        Speed = speedPrice,
        Multiplier = multiplierPrice,
        EatSpeed = eatSpeedPrice,
    }
    local function showPlayerData()
        print("=======================================")
        print("Viewing player data")
        print("=======================================")
        for _, player in Players:GetPlayers() do
            print()
            print("playerÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¼ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡" .. player.Name)
            print("=======================================")
            local hasUpgrades = false
            if player.Upgrades then
                for _, upg in player.Upgrades:GetChildren() do
                    hasUpgrades = true
                    local content = "  " .. localization[upg.Name] .. "ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¼ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡"
                    local cost = 0
                    for l = 2, upg.Value do
                        cost += priceFunctions[upg.Name](l)
                    end
                    content = content .. " " .. upg.Value .. "levelÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¼ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Âº"
                    content = content .. " " .. growthFunctions[upg.Name](upg.Value) .. "valueÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¼ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Âº"
                    content = content .. " " .. cost .. "cost"
                    print(content)
                end
            end
            if not hasUpgrades then
                print("  No upgrade data available at the moment")
            end
        end
        print("=======================================")
        print("Data viewing completed")
        print("=======================================")
        pcall(function()
            game.StarterGui:SetCore("DevConsoleVisible", true)
        end)
    end
    showPlayerData()
    Message("View Player Data", "Data loaded successfully", 2)
end
-- No Slip
local function toggleSlippageElimination(enabled)
    if enabled then
        if slippageConnection then
            slippageConnection:Disconnect()
            slippageConnection = nil
        end
        slippageEliminationEnabled = true
        slippageConnection = game:GetService("RunService").RenderStepped:Connect(function()
            if not slippageEliminationEnabled then return end
            local character = LocalPlayer.Character
            if not character then return end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if not humanoid or not rootPart then return end
            local moveDirection = humanoid.MoveDirection
            local maxSpeed = humanoid.WalkSpeed
            local targetVelocity = moveDirection * maxSpeed
            if moveDirection.Magnitude > 0 then
                currentVelocity = currentVelocity:Lerp(targetVelocity, ACCELERATION)
            else
                currentVelocity = currentVelocity:Lerp(Vector3.new(0, 0, 0), DECELERATION)
            end
            local rootVelocity = rootPart.Velocity
            rootPart.Velocity = Vector3.new(currentVelocity.X, rootVelocity.Y, currentVelocity.Z)
        end)
        Message("No Slip", "No Slip enabled", 2)
    else
        -- CloseNo Slip
        slippageEliminationEnabled = false
        if slippageConnection then
            slippageConnection:Disconnect()
            slippageConnection = nil
        end
        Message("No Slip", "No Slip disabled", 2)
    end
end
-- Gravity Lock
local function toggleGravityLock(enabled)
    if enabled then
        if gravityLockConnection then
            task.cancel(gravityLockConnection)
            gravityLockConnection = nil
        end
        gravityLockEnabled = true
        gravityLockConnection = task.spawn(function()
            while gravityLockEnabled do
                workspace.Gravity = 99999999 -- Default gravity
                task.wait(0.1)
            end
        end)
        Message("Gravity Lock", "Gravity Lock enabled", 2)
    else
        -- CloseGravity Lock
        gravityLockEnabled = false
        if gravityLockConnection then
            task.cancel(gravityLockConnection)
            gravityLockConnection = nil
        end
        Message("Gravity Lock", "Gravity Lock disabled", 2)
    end
end
local function grabForwardObject()
    local character = LocalPlayer.Character
    if not character then return end
    local events = character:FindFirstChild("Events")
    if not events then return end
    local grabEvent = events:FindFirstChild("Grab")
    if not grabEvent then return end
    grabEvent:FireServer(false, false, true)
end
local function CreateContinuousGrabUI()
    if continuousGrabUI then
        continuousGrabUI:Destroy()
        continuousGrabUI = nil
    end
    local gui = Instance.new("ScreenGui")
    gui.Name = "ContinuousGrabUI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Enabled = true
    gui.IgnoreGuiInset = true
    pcall(function()
        gui.Parent = CoreGui
    end)
    if gui.Parent ~= CoreGui then
        gui.Parent = PlayerGui
    end
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "mainFrame"
    mainFrame.Parent = gui
    mainFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    mainFrame.BorderSizePixel = 0
    mainFrame.Position = UDim2.new(0.5, -80, 0.85, -60)
    mainFrame.Size = UDim2.new(0, 160, 0, 50)
    mainFrame.Active = true
    mainFrame.Draggable = false
    mainFrame.ClipsDescendants = true
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = mainFrame
    local shadow = Instance.new("UIStroke")
    shadow.Color = Color3.fromRGB(0, 0, 0)
    shadow.Transparency = 0.6
    shadow.Thickness = 5
    shadow.Parent = mainFrame
    local grabButton = Instance.new("TextButton")
    grabButton.Name = "grabButton"
    grabButton.Parent = mainFrame
    grabButton.BackgroundColor3 = Color3.fromRGB(60, 180, 60)
    grabButton.BorderSizePixel = 0
    grabButton.Size = UDim2.new(1, 0, 1, 0)
    grabButton.Position = UDim2.new(0, 0, 0, 0)
    grabButton.Font = Enum.Font.SourceSansBold
    grabButton.Text = "Press F to Grab"
    grabButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    grabButton.TextSize = 18
    grabButton.ZIndex = 2
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 10)
    buttonCorner.Parent = grabButton
    local dragging = false
    local dragStart = Vector2.new()
    local startPos = UDim2.new()
    local clickStarted = false
    local clickStartPos = Vector2.new()
    grabButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            clickStarted = true
            dragStart = input.Position
            clickStartPos = input.Position
            startPos = mainFrame.Position
            UserInputService.MouseIconEnabled = false
        end
    end)
    grabButton.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
    grabButton.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            UserInputService.MouseIconEnabled = true
            if clickStarted then
                local delta = input.Position - clickStartPos
                if delta.Magnitude < 5 then
                    grabForwardObject()
                end
                clickStarted = false
            end
        end
    end)
    grabButton.MouseEnter:Connect(function()
        TweenService:Create(grabButton, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(70, 190, 70),
            Size = UDim2.new(1.02, 0, 1.05, 0),
            Position = UDim2.new(-0.01, 0, -0.025, 0)
        }):Play()
    end)
    grabButton.MouseLeave:Connect(function()
        TweenService:Create(grabButton, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(60, 180, 60),
            Size = UDim2.new(1, 0, 1, 0),
            Position = UDim2.new(0, 0, 0, 0)
        }):Play()
    end)
    continuousGrabUI = gui
    return gui
end
-- Constant Grab
local function toggleContinuousGrab(enabled)
    if enabled then
        continuousGrabEnabled = true
        CreateContinuousGrabUI()
        continuousGrabConnection = UserInputService.InputBegan:Connect(function(input, processed)
            if processed then return end
            if input.KeyCode == Enum.KeyCode.F then
                grabForwardObject()
            end
        end)
        Message("CS Grab", "Constant Grab enabled\nPress F to grab", 2)
    else
        continuousGrabEnabled = false
        if continuousGrabConnection then
            continuousGrabConnection:Disconnect()
            continuousGrabConnection = nil
        end
        if continuousGrabUI then
            continuousGrabUI:Destroy()
            continuousGrabUI = nil
        end
        Message("CS Grab", "Constant Grab disabled", 2)
    end
end
local function getCurrency()
    local currency = 0
    if LocalPlayer:FindFirstChild("leaderstats") then
        local leaderstats = LocalPlayer.leaderstats
        local currencyNames = {"Money", "Cash", "Coins", "Gold", "Currency", "Dollars", "Coins", "Cash", "Dollars", "Credits", "Points", "Tokens", "Gems"}
        for _, name in ipairs(currencyNames) do
            local currencyValue = leaderstats:FindFirstChild(name)
            if currencyValue and (currencyValue:IsA("IntValue") or currencyValue:IsA("NumberValue") or currencyValue:IsA("Int64Value")) then
                currency = currencyValue.Value
                return currency
            end
        end
        for _, child in ipairs(leaderstats:GetChildren()) do
            if child:IsA("IntValue") or child:IsA("NumberValue") or child:IsA("Int64Value") then
                currency = child.Value
                return currency
            end
        end
    end
    if LocalPlayer:FindFirstChild("Currencies") then
        local currencies = LocalPlayer.Currencies
        for _, currencyValue in ipairs(currencies:GetChildren()) do
            if currencyValue:IsA("IntValue") or currencyValue:IsA("NumberValue") or currencyValue:IsA("Int64Value") then
                currency = currencyValue.Value
                return currency
            end
        end
    end
    for _, child in ipairs(LocalPlayer:GetChildren()) do
        if (child:IsA("IntValue") or child:IsA("NumberValue") or child:IsA("Int64Value")) and 
           (string.lower(child.Name):find("money") or string.lower(child.Name):find("cash") or 
            string.lower(child.Name):find("coin") or string.lower(child.Name):find("gold") or
            string.lower(child.Name):find("currency") or string.lower(child.Name):find("dollar") or
            string.lower(child.Name):find("credit") or string.lower(child.Name):find("point") or
            string.lower(child.Name):find("token") or string.lower(child.Name):find("gem")) then
            currency = child.Value
            return currency
        end
    end
    local specialLocations = {
        LocalPlayer:FindFirstChild("Stats"),
        LocalPlayer:FindFirstChild("Data"),
        LocalPlayer:FindFirstChild("PlayerData"),
        LocalPlayer:FindFirstChild("Currency")
    }
    for _, location in ipairs(specialLocations) do
        if location then
            for _, child in ipairs(location:GetChildren()) do
                if child:IsA("IntValue") or child:IsA("NumberValue") or child:IsA("Int64Value") then
                    currency = child.Value
                    return currency
                end
            end
        end
    end
    return currency
end
local function getDistanceByCurrency(currency)
    if currency < 3000 then
        return 0
    elseif currency < 15000 then
        return 6
    elseif currency < 40000 then
        return 10
    elseif currency < 80000 then
        return 20
    elseif currency < 150000 then
        return 30
    elseif currency < 300000 then
        return 40
    elseif currency < 500000 then
        return 50
    elseif currency < 800000 then
        return 60
    elseif currency < 1200000 then
        return 70
    elseif currency < 2000000 then
        return 80
    elseif currency < 3000000 then
        return 90
    elseif currency < 4000000 then
        return 100
    elseif currency < 5500000 then
        return 110
    elseif currency < 6300000 then
        return 120
    elseif currency < 8000000 then
        return 130
    else
        return 210
    end
end
-- TP Grab V19 | menggantikan TP Grab lama
local ToggleTeleportGrabUI
local function CreateTeleportGrabUI()
    if teleportGrabUI then
        teleportGrabUI:Destroy()
        teleportGrabUI = nil
    end
    local FOLLOW_CLEARANCE = 1.0 -- jarak kosong adaptif antar badan
    local GRAB_RETRY_INTERVAL = 0.12 -- uji respons cepat; satu request per interval
    local SAFETY_TIMEOUT = 45
    local RETURN_TO_ORIGIN = true
    local GUI_NAME = "DENZ_TP_GRAB_AUTO_V19"

    pcall(function()
        local old = (gethui and gethui():FindFirstChild(GUI_NAME))
            or CoreGui:FindFirstChild(GUI_NAME)
            or LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild(GUI_NAME)
        if old then old:Destroy() end
    end)

    local gui = Instance.new("ScreenGui")
    gui.Name = GUI_NAME
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    local parented = false
    pcall(function()
        if type(gethui) == "function" then
            local h = gethui()
            if typeof(h) == "Instance" then
                gui.Parent = h
                parented = gui.Parent == h
            end
        end
    end)
    if not parented then
        pcall(function()
            gui.Parent = CoreGui
            parented = gui.Parent == CoreGui
        end)
    end
    if not parented then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(150, 245)
    panel.Position = UDim2.new(0, 18, 0.3, 0)
    panel.BackgroundColor3 = UI.Theme.Background
    panel.BorderSizePixel = 0
    panel.Parent = gui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke")
    stroke.Color = UI.Theme.Border
    stroke.Thickness = 2
    stroke.Parent = panel

    local function makeLabel(text, y, height, size)
        local obj = Instance.new("TextLabel")
        obj.Size = UDim2.new(1, -16, 0, height)
        obj.Position = UDim2.fromOffset(8, y)
        obj.BackgroundTransparency = 1
        obj.Text = text
        obj.TextColor3 = UI.Theme.Text
        obj.TextSize = size or 11
        obj.Font = Enum.Font.Gotham
        obj.TextXAlignment = Enum.TextXAlignment.Left
        obj.TextWrapped = true
        obj.Parent = panel
        return obj
    end

    local title = makeLabel("dEnzCreator | JUMP FOLLOW V19", 8, 20, 9)
    title.Font = Enum.Font.GothamBold

    title.Active = true
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPosition = nil
    local inputChangedConnection = nil
    local inputEndedConnection = nil

    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = panel.Position
            dragInput = input

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    dragInput = nil
                end
            end)
        end
    end)

    title.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    inputChangedConnection = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input == dragInput
            or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = input.Position - dragStart
            panel.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)
    local status = makeLabel("OFF | Pilih target", 32, 30, 10)
    status.TextColor3 = UI.Theme.Muted
    local targetInfo = makeLabel("Target: -", 62, 20, 10)

    local playerList = Instance.new("ScrollingFrame")
    playerList.Size = UDim2.new(1, -16, 0, 112)
    playerList.Position = UDim2.fromOffset(8, 86)
    playerList.BackgroundColor3 = UI.Theme.Row
    playerList.BorderSizePixel = 0
    playerList.ScrollBarThickness = 3
    playerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    playerList.CanvasSize = UDim2.new()
    playerList.Parent = panel
    Instance.new("UICorner", playerList).CornerRadius = UDim.new(0, 6)
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 3)
    layout.Parent = playerList

    local selectedTarget, running, runToken = nil, false, 0
    local followConnection = nil
    local targetButtons = {}
    local NORMAL_ROW_COLOR = UI.Theme.Off
    local ACTIVE_ROW_COLOR = UI.Theme.Auto

    local function updateTargetRowColors()
        for player, button in pairs(targetButtons) do
            if button and button.Parent then
                button.BackgroundColor3 =
                    (running and player == selectedTarget)
                    and ACTIVE_ROW_COLOR or NORMAL_ROW_COLOR
            end
        end
    end
    local cycleState = "OFF"
    local grabSentAt = 0
    local targetYBeforeGrab = nil
    local successPauseUntil = 0
    local GRAB_SUCCESS_RISE = 1.25
    local GRAB_SUCCESS_WINDOW = 0.55
    local SUCCESS_PAUSE = 0.20
    local CYCLE_RETRY_DELAY = GRAB_RETRY_INTERVAL

    local function setStatus(message, color)
        status.Text = message
        status.TextColor3 = color or UI.Theme.Muted
    end

    local function getAliveCharacter(who)
        local character = who and who.Character
        if not character then return nil, nil, nil end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local root = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not root or humanoid.Health <= 0 then return nil, nil, nil end
        return character, humanoid, root
    end

    local function stopFollow()
        if followConnection then
            followConnection:Disconnect()
            followConnection = nil
        end
    end

    local originPivot = nil
    local huntStartedAt = 0

    local function stopRun(reason)
        running = false
        runToken += 1
        stopFollow()
        cycleState = "OFF"
        if RETURN_TO_ORIGIN and originPivot then
            local currentCharacter = LocalPlayer.Character
            if currentCharacter then
                pcall(function()
                    currentCharacter:PivotTo(originPivot)
                end)
            end
        end
        originPivot = nil
        updateTargetRowColors()
        setStatus(reason or "OFF", Color3.fromRGB(255, 180, 90))
    end

    teleportGrabStop = stopRun

    local function sendGrabRequest()
        local replicatedStorage = game:GetService("ReplicatedStorage")
        local localEvents = replicatedStorage:FindFirstChild("LocalEvents")
        local grabEvent = localEvents and localEvents:FindFirstChild("Grab")

        if not grabEvent or not grabEvent:IsA("BindableEvent") then
            return false, "ReplicatedStorage.LocalEvents.Grab (BindableEvent) tidak ditemukan"
        end

        local ok, err = pcall(function()
            grabEvent:Fire()
        end)
        if not ok then return false, tostring(err) end
        return true
    end

    local function beginTarget(target)
        selectedTarget = target
        targetInfo.Text = "Target: @" .. target.Name
        setStatus("Target dipilih | follow aktif", Color3.fromRGB(100, 220, 150))
    end

    local function startHunt()
        local target = selectedTarget
        if not target then
            setStatus("Pilih target dahulu", Color3.fromRGB(255, 180, 90))
            return
        end

        local _, _, myRoot = getAliveCharacter(LocalPlayer)
        local _, _, targetRoot = getAliveCharacter(target)
        if not myRoot or not targetRoot then
            setStatus("Character / target belum siap", Color3.fromRGB(255, 180, 90))
            return
        end

        running = true
        runToken += 1
        local token = runToken
        originPivot = LocalPlayer.Character:GetPivot()
        huntStartedAt = os.clock()
        cycleState = "FOLLOW"
        grabSentAt = 0
        targetYBeforeGrab = nil
        successPauseUntil = 0
        updateTargetRowColors()
        setStatus("ON | memburu @" .. target.Name, Color3.fromRGB(100, 220, 150))

        followConnection = RunService.Heartbeat:Connect(function()
            if not running or token ~= runToken then return end
            if not target or target.Parent ~= Players then
                stopRun("Target keluar | OFF")
                return
            end

            local targetCharacter, targetHumanoid, currentTargetRoot = getAliveCharacter(target)
            local myCharacter, myHumanoid, currentMyRoot = getAliveCharacter(LocalPlayer)
            if not targetCharacter or not targetHumanoid or not currentTargetRoot
                or not myCharacter or not myHumanoid or not currentMyRoot then
                stopRun("Character hilang / mati | OFF")
                return
            end

            local now = os.clock()
            if SAFETY_TIMEOUT > 0 and now - huntStartedAt >= SAFETY_TIMEOUT then
                stopRun("Safety timeout | OFF")
                return
            end

            -- Setelah target terangkat, hentikan follow dan Grab sejenak,
            -- lalu mulai siklus berburu target yang sama selama ON.
            if cycleState == "SUCCESS_PAUSE" then
                if now < successPauseUntil then
                    return
                end
                cycleState = "FOLLOW"
                grabSentAt = 0
                targetYBeforeGrab = nil
                setStatus("ON | berburu ulang @" .. target.Name,
                    Color3.fromRGB(100, 220, 150))
            end

            -- Konfirmasi praktis: target naik setidaknya 1.25 stud
            -- dalam 1.4 detik setelah request Grab. Ini indikator visual,
            -- bukan konfirmasi server resmi.
            if cycleState == "WAIT_RESULT" then
                local rise = currentTargetRoot.Position.Y - targetYBeforeGrab
                if rise >= GRAB_SUCCESS_RISE then
                    cycleState = "SUCCESS_PAUSE"
                    successPauseUntil = now + SUCCESS_PAUSE
                    setStatus("GRAB terdeteksi | lanjut berburu",
                        Color3.fromRGB(100, 220, 150))
                    return
                elseif now - grabSentAt >= GRAB_SUCCESS_WINDOW then
                    cycleState = "FOLLOW"
                    targetYBeforeGrab = nil
                    setStatus("Belum terdeteksi | follow + retry",
                        Color3.fromRGB(255, 180, 90))
                end
                -- Sengaja tidak return: karakter tetap mengikuti target
                -- selama menunggu hasil Grab.
            end

            if cycleState == "FOLLOW" or cycleState == "WAIT_RESULT" then
                -- Jarak adaptif: setengah kedalaman kedua HumanoidRootPart
                -- ditambah clearance 1 stud antar badan.
                local adaptiveDistance =
                    (currentMyRoot.Size.Z * 0.5)
                    + (currentTargetRoot.Size.Z * 0.5)
                    + FOLLOW_CLEARANCE

                -- Prediksi pendek agar posisi follow tidak tertinggal
                -- ketika target sedang bergerak.
                local targetVelocity = currentTargetRoot.AssemblyLinearVelocity
                local predictionTime = 0.10
                local predictedTargetPosition =
                    currentTargetRoot.Position + targetVelocity * predictionTime

                local behindPosition = predictedTargetPosition
                    - currentTargetRoot.CFrame.LookVector * adaptiveDistance

                -- Tanpa Raycast: ikuti ketinggian target secara langsung.
                -- Ini menghindari status tertahan karena ground tidak terdeteksi.
                local targetFootY = currentTargetRoot.Position.Y
                    - targetHumanoid.HipHeight
                    - (currentTargetRoot.Size.Y * 0.5)

                local myStandingHeight = myHumanoid.HipHeight
                    + (currentMyRoot.Size.Y * 0.5)

                local followRootY = targetFootY + myStandingHeight

                local desiredRootPosition = Vector3.new(
                    behindPosition.X,
                    followRootY,
                    behindPosition.Z
                )
                local desiredRootCFrame = CFrame.lookAt(
                    desiredRootPosition,
                    desiredRootPosition + currentTargetRoot.CFrame.LookVector,
                    Vector3.yAxis
                )
                local pivotRelativeToRoot = currentMyRoot.CFrame:ToObjectSpace(myCharacter:GetPivot())
                local desiredPivot = desiredRootCFrame * pivotRelativeToRoot

                local moved = pcall(function()
                    myCharacter:PivotTo(desiredPivot)
                end)
                if not moved then
                    setStatus("PivotTo gagal | Follow tertahan",
                        Color3.fromRGB(255, 180, 90))
                    return
                end

                -- Grab segera setelah posisi follow diperbarui, lalu retry
                -- tiap 0.12 detik. Follow tetap berjalan selama menunggu.
                if grabSentAt == 0 or now - grabSentAt >= GRAB_RETRY_INTERVAL then
                    grabSentAt = now
                    targetYBeforeGrab = currentTargetRoot.Position.Y
                    local sent, reason = sendGrabRequest()
                    if sent then
                        cycleState = "WAIT_RESULT"
                        setStatus("INSTANT GRAB | follow aktif",
                            Color3.fromRGB(100, 220, 150))
                    else
                        setStatus("Remote error: " .. tostring(reason),
                            Color3.fromRGB(255, 120, 100))
                    end
                end
            end
        end)
    end

    local function toggleTarget(target)
        if running and selectedTarget == target then
            stopRun("OFF | @" .. target.Name)
            return
        end

        if running then
            stopRun("Target diganti")
        end

        beginTarget(target)
        startHunt()
    end

    local function refreshPlayers()
        for _, child in ipairs(playerList:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        table.clear(targetButtons)
        local targets = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then table.insert(targets, p) end
        end
        table.sort(targets, function(a, b)
            return string.lower(a.Name) < string.lower(b.Name)
        end)
        for _, target in ipairs(targets) do
            local button = Instance.new("TextButton")
            button.Size = UDim2.new(1, -4, 0, 24)
            button.BackgroundColor3 = NORMAL_ROW_COLOR
            button.BorderSizePixel = 0
            button.Text = target.DisplayName .. "  (@" .. target.Name .. ")"
            button.TextColor3 = UI.Theme.Text
            button.TextSize = 8
            button.Font = Enum.Font.Gotham
            button.Parent = playerList
            targetButtons[target] = button
            Instance.new("UICorner", button).CornerRadius = UDim.new(0, 5)
            button.Activated:Connect(function() toggleTarget(target) end)
        end
    end

    local playerAddedConnection = Players.PlayerAdded:Connect(function()
        task.defer(refreshPlayers)
    end)
    local playerRemovingConnection = Players.PlayerRemoving:Connect(function(leaving)
        if leaving == selectedTarget and running then
            stopRun("Target keluar | posisi dikembalikan")
        end
        task.defer(refreshPlayers)
    end)

    teleportGrabCleanup = function()
        dragging = false
        UserInputService.MouseIconEnabled = true
        if inputChangedConnection then
            inputChangedConnection:Disconnect()
            inputChangedConnection = nil
        end
        if playerAddedConnection then
            playerAddedConnection:Disconnect()
            playerAddedConnection = nil
        end
        if playerRemovingConnection then
            playerRemovingConnection:Disconnect()
            playerRemovingConnection = nil
        end
    end

    refreshPlayers()
    teleportGrabUI = gui
    return gui
end

ToggleTeleportGrabUI = function()
    if not teleportGrabUI then
        CreateTeleportGrabUI()
    else
        if teleportGrabStop then
            teleportGrabStop("OFF | TP Grab ditutup")
        end
        if teleportGrabCleanup then
            teleportGrabCleanup()
        end
        teleportGrabStop = nil
        teleportGrabCleanup = nil
        teleportGrabUI:Destroy()
        teleportGrabUI = nil
    end
end
-- Teleport Slam
local function CreateTeleportThrowUI()
    if teleportThrowUI then
        teleportThrowUI:Destroy()
        teleportThrowUI = nil
    end
    local gui = Instance.new("ScreenGui")
    gui.Name = "TeleportThrowTool"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Enabled = true
    gui.IgnoreGuiInset = true
    pcall(function()
        gui.Parent = CoreGui
    end)
    if gui.Parent ~= CoreGui then
        gui.Parent = PlayerGui
    end
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "mainFrame"
    mainFrame.Parent = gui
    mainFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    mainFrame.BorderSizePixel = 0
    mainFrame.Position = UDim2.new(0, 20, 0, 20)
    mainFrame.Size = UDim2.new(0, 150, 0, 250)
    mainFrame.Active = true
    mainFrame.Draggable = false
    mainFrame.ClipsDescendants = true
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 7)
    corner.Parent = mainFrame
    local shadow = Instance.new("UIStroke")
    shadow.Color = Color3.fromRGB(0, 0, 0)
    shadow.Transparency = 0.5
    shadow.Thickness = 2
    shadow.Parent = mainFrame
    local titleBar = Instance.new("Frame")
    titleBar.Name = "titleBar"
    titleBar.Parent = mainFrame
    titleBar.BackgroundColor3 = Color3.fromRGB(36, 36, 42)
    titleBar.BorderSizePixel = 0
    titleBar.Size = UDim2.new(1, 0, 0, 32)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.Active = true
    titleBar.Draggable = false
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "titleLabel"
    titleLabel.Parent = titleBar
    titleLabel.BackgroundTransparency = 1
    titleLabel.Size = UDim2.new(1, -30, 1, 0)
    titleLabel.Position = UDim2.new(0, 8, 0, 0)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Text = "TP Slam"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 13
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleBar.Active = true
    titleBar.Draggable = false
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "closeButton"
    closeButton.Parent = titleBar
    closeButton.BackgroundTransparency = 1
    closeButton.Position = UDim2.new(1, -30, 0, 0)
    closeButton.Size = UDim2.new(0, 30, 1, 0)
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Text = "ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â"
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.TextSize = 16
    closeButton.MouseButton1Click:Connect(function()
        gui.Enabled = not gui.Enabled
    end)
    local playersScroll = Instance.new("ScrollingFrame")
    playersScroll.Name = "playersScroll"
    playersScroll.Parent = mainFrame
    playersScroll.Active = true
    playersScroll.BackgroundTransparency = 1
    playersScroll.BorderSizePixel = 0
    playersScroll.Position = UDim2.new(0, 6, 0, 37)
    playersScroll.Size = UDim2.new(1, -12, 1, -43)
    playersScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    playersScroll.ScrollBarThickness = 3
    playersScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    local UIListLayout = Instance.new("UIListLayout")
    UIListLayout.Parent = playersScroll
    UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    UIListLayout.Padding = UDim.new(0, 4)
    local function addbtn(parent, plr)
        local playerbutton = Instance.new("TextButton")
        playerbutton.Name = plr.Name
        playerbutton.Parent = parent
        playerbutton.BackgroundColor3 = Color3.fromRGB(44, 44, 50)
        playerbutton.BorderSizePixel = 0
        playerbutton.Size = UDim2.new(1, 0, 0, 29)
        playerbutton.Font = Enum.Font.GothamMedium
        playerbutton.Text = plr.Name
        if plr.Name ~= plr.DisplayName then
            playerbutton.Text = playerbutton.Text .. " (" .. plr.DisplayName .. ")"
        end
        playerbutton.TextColor3 = Color3.fromRGB(255, 255, 255)
        playerbutton.TextSize = 11
        playerbutton.TextXAlignment = Enum.TextXAlignment.Left
        playerbutton.TextYAlignment = Enum.TextYAlignment.Center
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 5)
        corner.Parent = playerbutton
        playerbutton.MouseButton1Click:Connect(function()
            local localPlayer = LocalPlayer
            if not localPlayer or not localPlayer.Character then return end
            local localHumanoidRootPart = localPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not localHumanoidRootPart then return end
            grabForwardObject()
            task.wait(0.4)
            if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
                local playerRootPart = plr.Character.HumanoidRootPart
                local currency = getCurrency()
                local distance = getDistanceByCurrency(currency)
                local behindPosition = playerRootPart.Position - playerRootPart.CFrame.LookVector * distance
                behindPosition = Vector3.new(behindPosition.X, localHumanoidRootPart.Position.Y, behindPosition.Z)
                local direction = (playerRootPart.Position - behindPosition).Unit
                localHumanoidRootPart.CFrame = CFrame.new(behindPosition, behindPosition + Vector3.new(direction.X, 0, direction.Z))
            end
        end)
        playerbutton.MouseEnter:Connect(function()
            TweenService:Create(playerbutton, TweenInfo.new(0.1), {
                BackgroundColor3 = Color3.fromRGB(54, 54, 60)
            }):Play()
        end)
        playerbutton.MouseLeave:Connect(function()
            TweenService:Create(playerbutton, TweenInfo.new(0.1), {
                BackgroundColor3 = Color3.fromRGB(44, 44, 50)
            }):Play()
        end)
    end
    for i, v in pairs(Players:GetPlayers()) do
        addbtn(playersScroll, v)
    end
    local con = nil
    con = Players.PlayerAdded:Connect(function(plr)
        if gui then
            addbtn(playersScroll, plr)
        else
            con:Disconnect()
        end
    end)
    local con = nil
    con = Players.PlayerRemoving:Connect(function(plr)
        if gui then
            local playerbutton = playersScroll:FindFirstChild(plr.Name)
            if playerbutton then
                playerbutton:Destroy()
            end
        else
            con:Disconnect()
        end
    end)
    local dragging = false
    local dragStart = Vector2.new()
    local startPos = UDim2.new()
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            UserInputService.MouseIconEnabled = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            UserInputService.MouseIconEnabled = true
        end
    end)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.Size = UDim2.new(1, 0, 0, 32)
    teleportThrowUI = gui
    return gui
end
local function ToggleTeleportThrowUI()
    if not teleportThrowUI then
        CreateTeleportThrowUI()
    else
        teleportThrowUI:Destroy()
        teleportThrowUI = nil
    end
end
local function ragdollCharacter()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum:ChangeState(Enum.HumanoidStateType.Physics)
        hum.AutoRotate = false
    end
    for _,v in pairs(char:GetDescendants()) do
        if v:IsA("Motor6D") then
            local a0 = Instance.new("Attachment")
            local a1 = Instance.new("Attachment")
            a0.CFrame = v.C0
            a1.CFrame = v.C1
            a0.Parent = v.Part0
            a1.Parent = v.Part1
            local socket = Instance.new("BallSocketConstraint")
            socket.Attachment0 = a0
            socket.Attachment1 = a1
            socket.LimitsEnabled = true
            socket.TwistLimitsEnabled = true
            socket.UpperAngle = 45
            socket.TwistLowerAngle = -45
            socket.TwistUpperAngle = 45
            socket.Parent = v.Part0
            table.insert(createdAttachments,a0)
            table.insert(createdAttachments,a1)
            table.insert(createdConstraints,socket)
            table.insert(disabledMotors,v)
            v.Enabled = false
        end
    end
end
local function unragdollCharacter()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        hum.AutoRotate = true
    end
    for _,v in pairs(createdConstraints) do
        if v then
            v:Destroy()
        end
    end
    for _,v in pairs(createdAttachments) do
        if v then
            v:Destroy()
        end
    end
    for _,v in pairs(disabledMotors) do
        if v then
            v.Enabled = true
        end
    end
    createdAttachments = {}
    createdConstraints = {}
    disabledMotors = {}
end
local function ToggleRagdoll()
    ragdolled = not ragdolled
    if ragdolled then
        ragdollCharacter()
        Message("Ragdoll", "Ragdoll enabled", 2)
    else
        unragdollCharacter()
        Message("Ragdoll", "Ragdoll disabled", 2)
    end
end
local mainUI

-- dEnzCreator PLAYER ESP | V2.2 card integrated into MountEiger Character section
-- Card: 160x65 | Avatar 47x47 | Name 12 | Username 11 | Stats 9
-- No standalone control panel; the existing MountEiger ESP toggle controls this module.
local playerESPEnabled = false
local espObjects = {}

local function readUpgradeLevel(player, upgradeName)
    local upgrades = player:FindFirstChild("Upgrades")
    if not upgrades then return nil end
    local upgrade = upgrades:FindFirstChild(upgradeName)
    if not upgrade then return nil end
    local ok, value = pcall(function() return upgrade.Value end)
    if ok and typeof(value) == "number" then return value end
    return nil
end

local function formatESPNumber(value)
    if value == nil then return "N/A" end
    if math.abs(value - math.floor(value)) < 0.000001 then
        local raw = tostring(math.floor(value))
        local formatted = raw:reverse():gsub("(%d%d%d)", "%1,"):reverse()
        return formatted:gsub("^,", "")
    end
    return string.format("%.1f", value):gsub("%.0$", "")
end

-- Same effective-value formulas used by the standalone V2.2 module.
local function getEffectiveESPValue(upgradeName, level)
    if level == nil then return nil end
    if upgradeName == "MaxSize" then
        return math.floor(((level + 0.5) ^ 2 - 0.25) / 2 * 100)
    elseif upgradeName == "Multiplier" then
        return math.floor(level)
    elseif upgradeName == "Speed" then
        return math.floor(level * 2 + 10)
    elseif upgradeName == "EatSpeed" then
        return math.floor((1 + (level - 1) * 0.2) * 10) / 10
    end
    return nil
end

local function espStatText(player, upgradeName)
    local level = readUpgradeLevel(player, upgradeName)
    if level == nil then return upgradeName .. ": N/A" end
    local effective = getEffectiveESPValue(upgradeName, level)
    if effective == nil then return upgradeName .. ": " .. formatESPNumber(level) end
    return upgradeName .. ": " .. formatESPNumber(effective)
        .. "  (Lv. " .. formatESPNumber(level) .. ")"
end

local function removePlayerStatsESP(targetPlayer)
    local entry = espObjects[targetPlayer]
    if entry then
        if entry.billboard then pcall(function() entry.billboard:Destroy() end) end
        espObjects[targetPlayer] = nil
    end
end

local function createPlayerStatsESP(targetPlayer)
    if targetPlayer == LocalPlayer then return end
    local character = targetPlayer.Character
    if not character then return end
    local adornee = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    if not adornee then return end

    removePlayerStatsESP(targetPlayer)

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "dEnzCreator_PlayerESP_V22"
    billboard.Adornee = adornee
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.Size = UDim2.fromOffset(160, 65)
    billboard.StudsOffset = Vector3.new(0, 3.3, 0)
    billboard.MaxDistance = 10000
    billboard.Enabled = playerESPEnabled
    billboard.Parent = character

    local background = Instance.new("Frame")
    background.Name = "Card"
    background.Size = UDim2.fromScale(1, 1)
    background.BackgroundColor3 = Color3.fromRGB(7, 10, 27)
    background.BackgroundTransparency = 0.32
    background.BorderSizePixel = 0
    background.Parent = billboard
    Instance.new("UICorner", background).CornerRadius = UDim.new(0, 9)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(83, 99, 226)
    stroke.Thickness = 1
    stroke.Transparency = 0.12
    stroke.Parent = background

    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.Size = UDim2.fromOffset(47, 47)
    avatar.Position = UDim2.fromOffset(3, 9)
    avatar.BackgroundColor3 = Color3.fromRGB(17, 22, 48)
    avatar.BackgroundTransparency = 0
    avatar.BorderSizePixel = 0
    avatar.ScaleType = Enum.ScaleType.Crop
    avatar.Parent = background
    Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)
    local avatarStroke = Instance.new("UIStroke")
    avatarStroke.Color = Color3.fromRGB(83, 99, 226)
    avatarStroke.Thickness = 1
    avatarStroke.Parent = avatar

    task.spawn(function()
        local ok, imageUrl = pcall(function()
            return Players:GetUserThumbnailAsync(targetPlayer.UserId,
                Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
        end)
        if ok and avatar.Parent then avatar.Image = imageUrl end
    end)

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "PlayerName"
    nameLabel.Size = UDim2.new(1, -56, 0, 14)
    nameLabel.Position = UDim2.fromOffset(51, 2)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(245, 247, 255)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 12
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = background

    local usernameLabel = Instance.new("TextLabel")
    usernameLabel.Name = "Username"
    usernameLabel.Size = UDim2.new(1, -56, 0, 13)
    usernameLabel.Position = UDim2.fromOffset(51, 15)
    usernameLabel.BackgroundTransparency = 1
    usernameLabel.TextColor3 = Color3.fromRGB(190, 197, 220)
    usernameLabel.Font = Enum.Font.Gotham
    usernameLabel.TextSize = 11
    usernameLabel.TextXAlignment = Enum.TextXAlignment.Left
    usernameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    usernameLabel.Parent = background

    local stats = Instance.new("TextLabel")
    stats.Name = "Stats"
    stats.Size = UDim2.new(1, -53, 0, 37)
    stats.Position = UDim2.fromOffset(51, 27)
    stats.BackgroundTransparency = 1
    stats.TextColor3 = Color3.fromRGB(245, 247, 255)
    stats.TextStrokeTransparency = 0.85
    stats.Font = Enum.Font.Gotham
    stats.TextSize = 9
    stats.TextXAlignment = Enum.TextXAlignment.Left
    stats.TextYAlignment = Enum.TextYAlignment.Top
    stats.TextWrapped = false
    stats.Parent = background

    espObjects[targetPlayer] = {
        billboard = billboard,
        nameLabel = nameLabel,
        usernameLabel = usernameLabel,
        statsLabel = stats,
        character = character
    }
end

local function updatePlayerStatsESP(targetPlayer)
    if targetPlayer == LocalPlayer then return end
    local character = targetPlayer.Character
    if not character then
        removePlayerStatsESP(targetPlayer)
        return
    end
    local entry = espObjects[targetPlayer]
    if not entry or entry.character ~= character or not entry.billboard or not entry.billboard.Parent then
        createPlayerStatsESP(targetPlayer)
        entry = espObjects[targetPlayer]
    end
    if not entry then return end

    entry.nameLabel.Text = targetPlayer.DisplayName
    entry.usernameLabel.Text = "@" .. targetPlayer.Name
    entry.statsLabel.Text = table.concat({
        espStatText(targetPlayer, "MaxSize"),
        espStatText(targetPlayer, "Multiplier"),
        espStatText(targetPlayer, "Speed"),
        espStatText(targetPlayer, "EatSpeed")
    }, "\n")
    entry.billboard.Enabled = playerESPEnabled
end

-- Safety Guard V2: ESP update loop runs only while the existing toggle is ON.
-- A generation token prevents duplicate/stale loops after rapid toggle changes.
local ESP_UPDATE_INTERVAL = 1.5
local espLoopGeneration = 0

local function startPlayerESPUpdateLoop()
    espLoopGeneration = espLoopGeneration + 1
    local thisGeneration = espLoopGeneration

    task.spawn(function()
        while playerESPEnabled and thisGeneration == espLoopGeneration do
            for _, targetPlayer in ipairs(Players:GetPlayers()) do
                if not playerESPEnabled or thisGeneration ~= espLoopGeneration then
                    break
                end
                updatePlayerStatsESP(targetPlayer)
            end
            if playerESPEnabled and thisGeneration == espLoopGeneration then
                task.wait(ESP_UPDATE_INTERVAL)
            end
        end
    end)
end

local function setPlayerESPEnabled(enabled)
    local nextEnabled = enabled == true
    if playerESPEnabled == nextEnabled then return end

    playerESPEnabled = nextEnabled
    if playerESPEnabled then
        for _, targetPlayer in ipairs(Players:GetPlayers()) do
            updatePlayerStatsESP(targetPlayer)
        end
        startPlayerESPUpdateLoop()
    else
        -- Invalidates the active loop immediately; it exits at its next check.
        espLoopGeneration = espLoopGeneration + 1
        for _, entry in pairs(espObjects) do
            if entry.billboard then entry.billboard.Enabled = false end
        end
    end
end

Players.PlayerAdded:Connect(function(targetPlayer)
    targetPlayer.CharacterAdded:Connect(function()
        task.wait(0.5)
        if playerESPEnabled then updatePlayerStatsESP(targetPlayer) end
    end)
    if playerESPEnabled then updatePlayerStatsESP(targetPlayer) end
end)
Players.PlayerRemoving:Connect(removePlayerStatsESP)
for _, targetPlayer in ipairs(Players:GetPlayers()) do
    if targetPlayer ~= LocalPlayer then
        targetPlayer.CharacterAdded:Connect(function()
            task.wait(0.5)
            if playerESPEnabled then updatePlayerStatsESP(targetPlayer) end
        end)
    end
end

-- The ESP loop is started/stopped by setPlayerESPEnabled; no idle polling loop.


mainUI = UI:NewWindow("dEnzCreator")
local autoSection = mainUI:NewSection("Auto")
local candyEarnedTotal = 0

-- Candy Loot tracker adapted from the working CANGCUD collector.
-- Counts a Candy only after it was touched and subsequently leaves Workspace.
local candyLootTargets = {}
local candyLootLastTouch = setmetatable({}, {__mode = "k"})
local pendingCandyPickup = setmetatable({}, {__mode = "k"})
local candyLootScanDelay = 0.35
local candyLootTouchCooldown = 0.8
local lastCandyLootScanAt = 0
local candyLootTouchWarned = false
local candyLootAddedConnection
local candyLootRemovingConnection

local function isCandyLoot(obj)
    return obj and obj:IsA("BasePart") and obj.Name == "Candy"
end

local function registerCandyLoot(obj)
    if isCandyLoot(obj) then
        candyLootTargets[obj] = true
    end
end

local function unregisterCandyLoot(obj)
    if not candyLootTargets[obj] then return end
    candyLootTargets[obj] = nil
    candyLootLastTouch[obj] = nil

    if obj.Name == "Candy" and pendingCandyPickup[obj] then
        pendingCandyPickup[obj] = nil
        candyEarnedTotal = candyEarnedTotal + 1
    end
end

for _, obj in ipairs(Workspace:GetDescendants()) do
    registerCandyLoot(obj)
end
candyLootAddedConnection = Workspace.DescendantAdded:Connect(registerCandyLoot)
candyLootRemovingConnection = Workspace.DescendantRemoving:Connect(unregisterCandyLoot)

local function canCollectCandy(item)
    if not isCandyLoot(item) or not item.Parent then return false end

    local owner = item:FindFirstChild("Owner")
    local timeLeft = item:FindFirstChild("TimeLeft")
    if owner and owner.Value ~= "" and owner.Value ~= LocalPlayer.Name then
        local remaining = timeLeft and tonumber(timeLeft.Value)
        if remaining and remaining > 0 then return false end
    end
    return true
end
autoSection:CreateToggle("Auto Farm", function(enabled)
    autofarm = enabled
    config.autofarm = enabled
    autoSaveConfig()

    if not enabled then
        -- The worker owns its cleanup; OFF is observed by the loop and all
        -- character callbacks are invalidated before restoration.
        return
    end

    coroutine.wrap(function()
        local text
        local bedrock
        local autoConn
        local autoDiedConn
        local charAddConn
        local charRemovingConn
        local hudInputBeganConnection
        local hudInputChangedConnection
        local hudInputEndedConnection
        local activeAutoCharacter
        local autoCharGeneration = 0
        local originalCharacterStates = {}
        local cleaned = false

        local startTime = tick()
        local eatTime = 0
        local lastEatTime = tick()
        local timer = 0
        local grabTimer = 0
        local sellDebounce = false
        local sellCount = 0
        local numChunks = 0

        local map = workspace:FindFirstChild("Map")
        local chunks = workspace:FindFirstChild("Chunks")
        local originalMapParent = map and map.Parent
        local originalChunksParent = chunks and chunks.Parent

        local function safeDisconnect(connection)
            if connection then
                pcall(function()
                    if connection.Connected then connection:Disconnect() end
                end)
            end
        end

        local function disconnectCharacterConnections()
            safeDisconnect(autoConn)
            safeDisconnect(autoDiedConn)
            autoConn = nil
            autoDiedConn = nil
        end

        local function restoreCharacterComponents(char)
            local saved = char and originalCharacterStates[char]
            if not saved then return end

            if saved.localChunkManager and saved.localChunkManager.Parent then
                pcall(function()
                    saved.localChunkManager.Enabled = saved.localChunkManagerEnabled
                end)
            end
            if saved.animate and saved.animate.Parent then
                pcall(function()
                    saved.animate.Enabled = saved.animateEnabled
                end)
            end
            originalCharacterStates[char] = nil
        end

        local function restoreWorldObjects()
            if map and map.Parent ~= originalMapParent then
                pcall(function() map.Parent = originalMapParent end)
            end
            if chunks and chunks.Parent ~= originalChunksParent then
                pcall(function() chunks.Parent = originalChunksParent end)
            end
        end

        local function cleanup()
            if cleaned then return end
            cleaned = true
            autofarm = false
            autoCharGeneration += 1

            safeDisconnect(charAddConn)
            safeDisconnect(charRemovingConn)
            charAddConn = nil
            charRemovingConn = nil
            disconnectCharacterConnections()

            restoreCharacterComponents(activeAutoCharacter)

            local currentCharacter = activeAutoCharacter
            local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
            if currentHumanoid and currentHumanoid.Parent and currentHumanoid.Health > 0 then
                pcall(function()
                    currentHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end)
            end

            restoreWorldObjects()

            if bedrock then
                pcall(function() bedrock:Destroy() end)
                bedrock = nil
            end

            safeDisconnect(hudInputBeganConnection)
            safeDisconnect(hudInputChangedConnection)
            safeDisconnect(hudInputEndedConnection)
            hudInputBeganConnection = nil
            hudInputChangedConnection = nil
            hudInputEndedConnection = nil

            if text then
                pcall(function() text:Remove() end)
                text = nil
            end
            activeAutoCharacter = nil
        end

        local function waitForCharacterChild(parent, childName, generation, ownerCharacter, timeout)
            local deadline = tick() + (timeout or 8)
            repeat
                if not autofarm or cleaned or generation ~= autoCharGeneration
                    or LocalPlayer.Character ~= ownerCharacter
                    or not ownerCharacter.Parent then
                    return nil
                end
                local child = parent:FindFirstChild(childName)
                if child then return child end
                task.wait(0.1)
            until tick() >= deadline
            return nil
        end

        local function pauseServer()
            pcall(function()
                Events.SetServerSettings:FireServer({
                    MapTime = -1,
                    Paused = true
                })
            end)
        end

        local function onCharAdd(char)
            autoCharGeneration += 1
            local thisGeneration = autoCharGeneration

            disconnectCharacterConnections()
            restoreCharacterComponents(activeAutoCharacter)
            activeAutoCharacter = char
            numChunks = 0
            timer = 0
            grabTimer = 0
            sellDebounce = false

            if not char or not autofarm or cleaned then return end

            local hum = waitForCharacterChild(char, "Humanoid", thisGeneration, char, 8)
            local root = waitForCharacterChild(char, "HumanoidRootPart", thisGeneration, char, 8)
            local size = waitForCharacterChild(char, "Size", thisGeneration, char, 8)
            local events = waitForCharacterChild(char, "Events", thisGeneration, char, 8)

            if not hum or not root or not size or not events then
                warn("[MountEiger Safety Guard V4] AutoFarm: character setup timed out; waiting for next character")
                return
            end

            local eat = waitForCharacterChild(events, "Eat", thisGeneration, char, 8)
            local grab = waitForCharacterChild(events, "Grab", thisGeneration, char, 8)
            local sell = waitForCharacterChild(events, "Sell", thisGeneration, char, 8)
            local chunk = waitForCharacterChild(char, "CurrentChunk", thisGeneration, char, 8)
            local sendTrack = waitForCharacterChild(char, "SendTrack", thisGeneration, char, 8)
            local radius = waitForCharacterChild(char, "Radius", thisGeneration, char, 8)

            if not eat or not grab or not sell or not chunk or not sendTrack or not radius
                or hum.Health <= 0 or LocalPlayer.Character ~= char
                or not autofarm or cleaned or thisGeneration ~= autoCharGeneration then
                warn("[MountEiger Safety Guard V4] AutoFarm: incomplete or inactive character; Heartbeat not started")
                return
            end

            local localChunkManager = char:FindFirstChild("LocalChunkManager")
            local animate = char:FindFirstChild("Animate")
            originalCharacterStates[char] = {
                localChunkManager = localChunkManager,
                localChunkManagerEnabled = localChunkManager and localChunkManager.Enabled,
                animate = animate,
                animateEnabled = animate and animate.Enabled
            }

            autoConn = game["Run Service"].Heartbeat:Connect(function(dt)
                if not autofarm or cleaned or thisGeneration ~= autoCharGeneration
                    or LocalPlayer.Character ~= char or not char.Parent
                    or not hum.Parent or not root.Parent or hum.Health <= 0 then
                    safeDisconnect(autoConn)
                    autoConn = nil
                    restoreCharacterComponents(char)
                    return
                end

                local ok, err = pcall(function()
                    local ran = tick() - startTime
                    local hours = math.floor(ran / 3600)
                    local minutes = math.floor(ran / 60)
                    local seconds = math.floor(ran)
                    local eatMinutes = math.floor(eatTime / 60)
                    local eatSeconds = math.floor(eatTime)
                    local y = bedrock.Position.Y + bedrock.Size.Y / 2 + hum.HipHeight + root.Size.Y / 2
                    local sizeAdd = LocalPlayer.Upgrades.Multiplier.Value / 100
                    local addAmount = LocalPlayer.Upgrades.MaxSize.Value / sizeAdd
                    local sellTime = addAmount / 2
                    local sellMinutes = math.floor(sellTime / 60)
                    local sellSeconds = math.floor(sellTime)
                    local secondEarn = math.floor(((LocalPlayer.Upgrades.MaxSize.Value + 0.5) ^ 2 - 0.25) / 2 * 100 / sellTime)
                    local minuteEarn = secondEarn * 60
                    local hourEarn = minuteEarn * 60
                    local dayEarn = hourEarn * 24

                    text.Text = ""
                        .. "\nRun Time: " .. string.format("%ih%im%is", hours, minutes % 60, seconds % 60)
                        .. "\nActual Time: " .. string.format("%im%is", eatMinutes % 60, eatSeconds % 60)
                        .. "\nEstimated Time: " .. string.format("%im%is", sellMinutes % 60, sellSeconds % 60)
                        .. "\nDaily Income: " .. dayEarn
                        .. "\nBlock Count: " .. numChunks
                        .. "\nCandy Count: " .. candyEarnedTotal

                    hum:ChangeState(Enum.HumanoidStateType.Physics)
                    grab:FireServer()
                    root.Anchored = false
                    eat:FireServer()
                    sendTrack:FireServer()

                    if chunk.Value then
                        if timer > 0 then numChunks += 1 end
                        timer = 0
                        grabTimer += dt
                    else
                        timer += dt
                        grabTimer = 0
                    end

                    -- Preserve original timer behavior; this is not an eat-speed control.
                    if timer > 60 then
                        hum.Health = 0
                        timer = 0
                        numChunks = 0
                    end
                    if grabTimer > 15 then
                        size.Value = LocalPlayer.Upgrades.MaxSize.Value
                    end

                    if (size.Value >= LocalPlayer.Upgrades.MaxSize.Value) or timer > 8 then
                        if timer < 8 then
                            sell:FireServer()
                            if not sellDebounce then
                                pauseServer()
                            end
                            sellDebounce = true
                        else
                            pauseServer()
                        end
                        numChunks = 0
                    elseif size.Value == 0 then
                        if sellDebounce then
                            local currentEatTime = tick()
                            eatTime = currentEatTime - lastEatTime
                            lastEatTime = currentEatTime
                            sellCount += 1
                        end
                        sellDebounce = false
                    end

                    if farmMoving then
                        local bound = 300
                        local startPos = CFrame.new(-bound / 2, y, -bound / 2)
                        local r = radius.Value * 1.1
                        local dist = r * numChunks
                        local x = dist % bound
                        local z = math.floor(dist / bound) * r
                        local offset = CFrame.new(x, 0, z + r * 2)
                        if z > bound then
                            pauseServer()
                            numChunks = 0
                        end
                        root.CFrame = startPos * offset
                    else
                        root.CFrame = CFrame.new(0, y, 0)
                    end
                end)

                if not ok then
                    warn("[MountEiger Safety Guard V4] AutoFarm Heartbeat stopped after error: " .. tostring(err))
                    safeDisconnect(autoConn)
                    autoConn = nil
                    restoreCharacterComponents(char)
                    pauseServer()
                end
            end)

            autoDiedConn = hum.Died:Connect(function()
                disconnectCharacterConnections()
                restoreCharacterComponents(char)
                pauseServer()
            end)

            if localChunkManager then
                pcall(function() localChunkManager.Enabled = false end)
            end
            if animate then
                pcall(function() animate.Enabled = false end)
            end
        end

        local ok, err = xpcall(function()
            text = Drawing.new("Text")
            text.Outline = true
            text.OutlineColor = Color3.new(0, 0, 0)
            text.Color = Color3.new(1, 1, 1)
            text.Center = false
            text.Position = Vector2.new(64, 64)
            text.Text = ""
            text.Size = 14
            text.Visible = true

            local hudDragging, hudDragInput = false, nil
            local hudDragStart, hudStartPosition

            hudInputBeganConnection = UserInputService.InputBegan:Connect(function(input)
                local kind = input.UserInputType
                if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then return end
                local pos, bounds = input.Position, text.TextBounds
                local left, top = text.Position.X, text.Position.Y
                if pos.X >= left and pos.X <= left + math.max(bounds.X, 100)
                    and pos.Y >= top and pos.Y <= top + math.max(bounds.Y, 24) then
                    hudDragging, hudDragInput = true, input
                    hudDragStart, hudStartPosition = Vector2.new(pos.X, pos.Y), text.Position
                end
            end)

            hudInputChangedConnection = UserInputService.InputChanged:Connect(function(input)
                if not hudDragging then return end
                local kind = input.UserInputType
                if kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch then
                    local delta = Vector2.new(input.Position.X, input.Position.Y) - hudDragStart
                    text.Position = hudStartPosition + delta
                end
            end)

            hudInputEndedConnection = UserInputService.InputEnded:Connect(function(input)
                if input == hudDragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
                    hudDragging, hudDragInput = false, nil
                end
            end)

            bedrock = Instance.new("Part")
            bedrock.Anchored = true
            bedrock.Size = Vector3.new(2048, 10, 2048)
            bedrock.Position = Vector3.new(0, -5, 0)
            bedrock.BrickColor = BrickColor.Black()
            bedrock.Parent = workspace

            if map and chunks then
                map.Parent, chunks.Parent = nil, nil
            end

            if LocalPlayer.Character then
                task.spawn(onCharAdd, LocalPlayer.Character)
            else
                task.spawn(function()
                    local newCharacter = LocalPlayer.CharacterAdded:Wait()
                    if autofarm and not cleaned then onCharAdd(newCharacter) end
                end)
            end

            charAddConn = LocalPlayer.CharacterAdded:Connect(onCharAdd)
            charRemovingConn = LocalPlayer.CharacterRemoving:Connect(function(oldCharacter)
                if oldCharacter == activeAutoCharacter then
                    autoCharGeneration += 1
                    disconnectCharacterConnections()
                    restoreCharacterComponents(oldCharacter)
                    activeAutoCharacter = nil
                end
            end)

            while autofarm and not cleaned do
                task.wait()
                local loading = workspace:FindFirstChild("Loading")
                if loading then
                    pcall(function() loading:Destroy() end)
                end

                if map and chunks then
                    if showMap then
                        map.Parent, chunks.Parent = originalMapParent, originalChunksParent
                    else
                        map.Parent, chunks.Parent = nil, nil
                    end
                end
            end
        end, debug.traceback)

        cleanup()

        if not ok then
            warn("[MountEiger Safety Guard V4] AutoFarm cleanup completed after worker error: " .. tostring(err))
        end
    end)()
end)
-- CANGCUD-style Auto Collect: original Coin/Token target changed ONLY to "Cube".
-- Candy collector remains separate so its counter behavior is preserved.
local cubeLootTargets = {}
local cubeLootLastTouch = setmetatable({}, {__mode = "k"})
local cubeLootScanDelay = 0.35
local cubeLootTouchCooldown = 0.8
local lastCubeLootScanAt = 0
local cubeLootTouchWarned = false
local cubeLootCollectingEnabled = false
local cubeLootAddedConnection
local cubeLootRemovingConnection
local cubeLootHeartbeatConnection

local function isCubeLoot(obj)
    return obj and obj:IsA("BasePart") and obj.Name == "Cube"
end

local function registerCubeLoot(obj)
    if isCubeLoot(obj) then cubeLootTargets[obj] = true end
end

local function unregisterCubeLoot(obj)
    if not cubeLootTargets[obj] then return end
    cubeLootTargets[obj] = nil
    cubeLootLastTouch[obj] = nil
end

for _, obj in ipairs(Workspace:GetDescendants()) do registerCubeLoot(obj) end
cubeLootAddedConnection = Workspace.DescendantAdded:Connect(registerCubeLoot)
cubeLootRemovingConnection = Workspace.DescendantRemoving:Connect(unregisterCubeLoot)

local function canCollectCube(item)
    if not isCubeLoot(item) or not item.Parent then return false end
    local owner = item:FindFirstChild("Owner")
    local timeLeft = item:FindFirstChild("TimeLeft")
    if owner and owner.Value ~= "" and owner.Value ~= LocalPlayer.Name then
        local remaining = timeLeft and tonumber(timeLeft.Value)
        if remaining and remaining > 0 then return false end
    end
    return true
end

local function collectCubeStep()
    if not cubeLootCollectingEnabled then return end
    local now = os.clock()
    if now - lastCubeLootScanAt < cubeLootScanDelay then return end
    lastCubeLootScanAt = now

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    if type(firetouchinterest) ~= "function" then
        if not cubeLootTouchWarned then
            cubeLootTouchWarned = true
            warn("[dEnzCreator] Cube Auto Collect requires firetouchinterest support in the executor.")
        end
        return
    end

    for item in pairs(cubeLootTargets) do
        if item.Parent and canCollectCube(item) then
            local previous = cubeLootLastTouch[item] or 0
            if now - previous >= cubeLootTouchCooldown then
                cubeLootLastTouch[item] = now
                pcall(function()
                    firetouchinterest(root, item, 0)
                    firetouchinterest(root, item, 1)
                end)
            end
        elseif not item.Parent then
            unregisterCubeLoot(item)
        end
    end
end

autoSection:CreateToggle("Auto Collect", function(enabled)
    autoCollectingCubes = enabled
    cubeLootCollectingEnabled = enabled
    config.autoCollectingCubes = enabled
    autoSaveConfig()

    local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
    local cubeVis = playerScripts and playerScripts:FindFirstChild("CubeVis")
    if cubeVis then cubeVis.Enabled = not enabled end

    if cubeLootHeartbeatConnection then
        cubeLootHeartbeatConnection:Disconnect()
        cubeLootHeartbeatConnection = nil
    end
    lastCubeLootScanAt = 0

    if enabled then
        cubeLootHeartbeatConnection = RunService.Heartbeat:Connect(function()
            pcall(collectCubeStep)
        end)

        -- Existing Candy-only collector retained; no Token/Coin collection.
        coroutine.wrap(function()
            while autoCollectingCubes do
                task.wait(candyLootScanDelay)
                local now = os.clock()
                if now - lastCandyLootScanAt < candyLootScanDelay then continue end
                lastCandyLootScanAt = now

                local character = LocalPlayer.Character
                local root = character and character:FindFirstChild("HumanoidRootPart")
                if not root then continue end
                if type(firetouchinterest) ~= "function" then
                    if not candyLootTouchWarned then
                        candyLootTouchWarned = true
                        warn("[dEnzCreator] Candy collector requires firetouchinterest support in the executor.")
                    end
                    break
                end

                for item in pairs(candyLootTargets) do
                    if item.Parent and canCollectCandy(item) then
                        local previous = candyLootLastTouch[item] or 0
                        if now - previous >= candyLootTouchCooldown then
                            candyLootLastTouch[item] = now
                            local touched = pcall(function()
                                firetouchinterest(root, item, 0)
                                firetouchinterest(root, item, 1)
                            end)
                            if touched then pendingCandyPickup[item] = true end
                        end
                    elseif not item.Parent then
                        unregisterCandyLoot(item)
                    end
                end
            end
        end)()
    end
end)

autoSection:CreateToggle("Auto Claim", function(enabled)
    autoClaimRewards = enabled
    config.autoClaimRewards = enabled
    autoSaveConfig()
    coroutine.wrap(function()
        while autoClaimRewards do
            task.wait(1)
            for _, reward in LocalPlayer.TimedRewards:GetChildren() do
                if reward.Value > 0 then
                    Events.RewardEvent:FireServer(reward)
                end
            end
            Events.SpinEvent:FireServer()
        end
    end)()
end)
autoSection:CreateToggle("Move Mode", function(enabled)
    farmMoving = enabled
    config.farmMoving = enabled
    autoSaveConfig()
end)
autoSection:CreateToggle("Show Map", function(enabled)
    showMap = enabled
    config.showMap = enabled
    autoSaveConfig()
end)
autoSection:CreateToggle("Auto Eat", function(enabled)
    autoeat = enabled
    config.autoeat = enabled
    autoSaveConfig()
    coroutine.wrap(function()
        while autoeat do
            task.wait()
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") and LocalPlayer.Character:FindFirstChild("Size") and LocalPlayer.Character:FindFirstChild("Events") and LocalPlayer.Character.Events:FindFirstChild("Grab") and LocalPlayer.Character.Events:FindFirstChild("Eat") and LocalPlayer.Character:FindFirstChild("CurrentChunk") then
                LocalPlayer.Character.HumanoidRootPart.Anchored = false
                LocalPlayer.Character.Events.Grab:FireServer()
                LocalPlayer.Character.Events.Eat:FireServer()
            end
        end
    end)()
end)
local figureSection = mainUI:NewSection("Character")
figureSection:CreateToggle("No Slip", function(enabled)
    toggleSlippageElimination(enabled)
    config.slippageEliminationEnabled = enabled
    autoSaveConfig()
end)
-- ANTI ANCHOR (GELUT): unanchor every BasePart inside the local character.
-- The RenderStepped connection is explicitly disconnected when switched OFF.
local function setAntiAnchorEnabled(enabled)
    antiAnchorEnabled = enabled
    config.keepUnanchor = enabled
    autoSaveConfig()

    if antiAnchorConnection then
        antiAnchorConnection:Disconnect()
        antiAnchorConnection = nil
    end

    if enabled then
        antiAnchorConnection = RunService.RenderStepped:Connect(function()
            if not mainUI or not mainUI.MainGui or not mainUI.MainGui.Parent
                or not antiAnchorEnabled then
                return
            end

            local character = LocalPlayer.Character
            if not character then return end

            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") and part.Anchored then
                    part.Anchored = false
                end
            end
        end)
    end
end

figureSection:CreateToggle("Anti Anchor", function(enabled)
    setAntiAnchorEnabled(enabled)
end)
figureSection:CreateToggle("Anti Fall", function(enabled)
    antiFallEnabled = enabled
    config.antiFallEnabled = enabled
    autoSaveConfig()
    if enabled then
        local char = LocalPlayer.Character
        if char and char.Parent then
            startAntiFall(char)
        end
    else
        stopAntiFall()
    end
end)

-- GELUT FLIGHT MODE: original movement/force behavior, adapted to MountEiger.
local flightEnabled = false
local flightSpeed = 100
local flyBodyVelocity = nil
local flyBodyGyro = nil

local function clearFlightForces()
    if flyBodyVelocity then
        pcall(function() flyBodyVelocity:Destroy() end)
        flyBodyVelocity = nil
    end
    if flyBodyGyro then
        pcall(function() flyBodyGyro:Destroy() end)
        flyBodyGyro = nil
    end
end

local function setFlightEnabled(enabled)
    flightEnabled = enabled
    if not enabled then
        clearFlightForces()
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.PlatformStand then
            humanoid.PlatformStand = false
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end
end

-- Place Wall Clip beside Anti Fall, then Flight Mode with its speed field.
figureSection:CreateToggle("Wall Clip", function(enabled)
    setWallClipEnabled(enabled)
end)

local flightRowY = figureSection.ContentY
figureSection:CreateToggle("Flight Mode", function(enabled)
    setFlightEnabled(enabled)
end)

local flightSpeedBox = Instance.new("TextBox")
flightSpeedBox.Name = "FlightSpeedValue"
flightSpeedBox.Size = UDim2.new(0.50, -4, 0, 25)
flightSpeedBox.Position = UDim2.new(0, 2, 0, flightRowY + 3)
flightSpeedBox.BackgroundColor3 = UI.Theme.Row
flightSpeedBox.BorderSizePixel = 0
flightSpeedBox.Text = tostring(flightSpeed)
flightSpeedBox.PlaceholderText = "Flight Speed"
flightSpeedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
flightSpeedBox.PlaceholderColor3 = Color3.fromRGB(170, 170, 170)
flightSpeedBox.TextSize = 12
flightSpeedBox.Font = Enum.Font.GothamMedium
flightSpeedBox.ClearTextOnFocus = false
flightSpeedBox.TextXAlignment = Enum.TextXAlignment.Center
flightSpeedBox.Parent = figureSection.Content
local flightSpeedCorner = Instance.new("UICorner")
flightSpeedCorner.CornerRadius = UDim.new(0, 7)
flightSpeedCorner.Parent = flightSpeedBox
flightSpeedBox.FocusLost:Connect(function()
    local entered = tonumber(flightSpeedBox.Text)
    if entered then
        flightSpeed = math.clamp(math.floor(entered), 1, 1000)
    end
    flightSpeedBox.Text = tostring(flightSpeed)
end)

task.spawn(function()
    while mainUI and mainUI.MainGui and mainUI.MainGui.Parent do
        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if flightEnabled and root and humanoid and humanoid.Health > 0 then
            humanoid.PlatformStand = true

            if not flyBodyVelocity or flyBodyVelocity.Parent ~= root then
                clearFlightForces()

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

            local camera = Workspace.CurrentCamera
            local cameraCFrame = camera and camera.CFrame or root.CFrame
            local worldMove = humanoid.MoveDirection
            local targetVelocity = Vector3.zero

            if worldMove.Magnitude > 0.05 then
                targetVelocity = worldMove.Unit * flightSpeed
            end

            if not UserInputService.TouchEnabled then
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                    targetVelocity += Vector3.new(0, flightSpeed, 0)
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
                    or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                    targetVelocity -= Vector3.new(0, flightSpeed, 0)
                end
            elseif humanoid.Jump then
                targetVelocity += Vector3.new(0, flightSpeed * 0.8, 0)
            end

            flyBodyVelocity.Velocity = targetVelocity
            flyBodyGyro.CFrame = cameraCFrame
        else
            clearFlightForces()
            if humanoid and humanoid.PlatformStand then
                humanoid.PlatformStand = false
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
        task.wait()
    end

    clearFlightForces()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid.PlatformStand = false end
end)

-- GELUT WALL CLIP: preserve each part's original CanCollide value and restore it on OFF.
local wallClipEnabled = false
local wallClipConnection = nil
local wallClipOriginal = setmetatable({}, {__mode = "k"})

local function restoreWallClipParts()
    for part, originalValue in pairs(wallClipOriginal) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = originalValue
            end)
        end
        wallClipOriginal[part] = nil
    end
end

local function setWallClipEnabled(enabled)
    wallClipEnabled = enabled

    if wallClipConnection then
        wallClipConnection:Disconnect()
        wallClipConnection = nil
    end

    if not enabled then
        restoreWallClipParts()
        return
    end

    wallClipConnection = RunService.Stepped:Connect(function()
        if not mainUI or not mainUI.MainGui or not mainUI.MainGui.Parent
            or not wallClipEnabled then
            return
        end

        local character = LocalPlayer.Character
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

LocalPlayer.CharacterAdded:Connect(function()
    if wallClipEnabled then
        restoreWallClipParts()
    end
end)
local invisibilityGui = nil
local invisibilityConnections = {}
figureSection:CreateToggle("Invisible", function(enabled)
    if enabled then
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local humanoid = character:WaitForChild("Humanoid")
        local rootPart = character:WaitForChild("HumanoidRootPart")
        local parts = {}
        for _, part in pairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                if part.Transparency == 0 then
                    table.insert(parts, part)
                end
            end
        end
        local isInvisible = false
        local connections = {}
        local gui = Instance.new("ScreenGui")
        gui.Name = "InvisibilityGui"
        gui.ResetOnSpawn = false
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(0, 100, 0, 50)
        button.Position = UDim2.new(0.5, -50, 0.1, 0)
        button.Text = "Gost"
        button.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        button.Parent = gui
        gui.Parent = player:WaitForChild("PlayerGui")
        local dragging = false
        local dragStart = Vector2.new()
        local startPos = button.Position
        button.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPos = button.Position
            end
        end)
        button.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = input.Position - dragStart
                button.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end)
        button.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
        local function toggleInvisibility()
            isInvisible = not isInvisible
            for _, part in pairs(parts) do
                if isInvisible then
                    part.Transparency = 0.5
                else
                    part.Transparency = 0
                end
            end
        end
        button.MouseButton1Click:Connect(toggleInvisibility)
        local mouse = player:GetMouse()
        connections[1] = mouse.KeyDown:Connect(function(key)
            if key == "g" then
                toggleInvisibility()
            end
        end)
        connections[2] = game:GetService("RunService").Heartbeat:Connect(function()
            if isInvisible then
                local cf = rootPart.CFrame
                local offset = CFrame.new(0, -200000, 0)
                local newCf = cf * offset
                local camOffset = newCf:ToObjectSpace(CFrame.new(cf.Position)).Position
                rootPart.CFrame = newCf
                humanoid.CameraOffset = camOffset
                game:GetService("RunService").RenderStepped:Wait()
                rootPart.CFrame = cf
                humanoid.CameraOffset = Vector3.new(0, 0, 0)
            end
        end)
        connections[3] = player.CharacterAdded:Connect(function(newCharacter)
            isInvisible = false
            parts = {}
            local newHumanoid = newCharacter:WaitForChild("Humanoid")
            local newRootPart = newCharacter:WaitForChild("HumanoidRootPart")
            humanoid = newHumanoid
            rootPart = newRootPart
            for _, part in pairs(newCharacter:GetDescendants()) do
                if part:IsA("BasePart") then
                    if part.Transparency == 0 then
                        table.insert(parts, part)
                    end
                end
            end
        end)
        invisibilityGui = gui
        invisibilityConnections = connections
        Message("Invisible", "Feature activated", 2)
    else
        if invisibilityGui then
            invisibilityGui:Destroy()
            invisibilityGui = nil
        end
        for _, connection in pairs(invisibilityConnections) do
            if connection and connection.Connected then
                connection:Disconnect()
            end
        end
        invisibilityConnections = {}
        local player = game.Players.LocalPlayer
        local character = player.Character
        if character then
            for _, part in pairs(character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.Transparency = 0
                end
            end
        end
        Message("Invisible", "Feature disabled", 2)
    end
    for _, btn in ipairs(figureSection.Buttons) do
        if btn.Name == "ToggleBtn_Invisible" then
            local stateLabel = btn:FindFirstChildOfClass("TextLabel")
            if stateLabel then
                stateLabel.Text = "Invisible"
                stateLabel.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            end
            break
        end
    end
end)
figureSection:CreateToggle("Gravity Lock", function(enabled)
    toggleGravityLock(enabled)
    config.gravityLockEnabled = enabled
    autoSaveConfig()
end)
figureSection:CreateToggle("CS Grab", function(enabled)
    toggleContinuousGrab(enabled)
end)
figureSection:CreateToggle("Ragdoll", function(enabled)
    ToggleRagdoll()
    for _, btn in ipairs(figureSection.Buttons) do
        if btn.Name == "ToggleBtn_Ragdoll" then
            local stateLabel = btn:FindFirstChildOfClass("TextLabel")
            if stateLabel then
                stateLabel.Text = "Ragdoll"
                stateLabel.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            end
            break
        end
    end
end)
figureSection:CreateToggle("ESP", function(enabled)
    setPlayerESPEnabled(enabled)
end)
figureSection:CreateToggle("Action Pack", function(enabled)
    loadCustomEmotes()
    for _, btn in ipairs(figureSection.Buttons) do
        if btn.Name == "ToggleBtn_Action Pack" then
            local stateLabel = btn:FindFirstChildOfClass("TextLabel")
            if stateLabel then
                stateLabel.Text = "Action Pack"
                stateLabel.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            end
            break
        end
    end
end)
local map = workspace:FindFirstChild("Map")
local chunks = workspace:FindFirstChild("Chunks")
local bedrock = nil
local mapHidden = false
local function toggleMap()
    if mapHidden then
        if map then
            map.Parent = workspace
        end
        if chunks then
            chunks.Parent = workspace
        end
        if bedrock and bedrock.Parent then
            bedrock:Destroy()
            bedrock = nil
        end
        Message("Notice", "Environment restored; platform removed", 2)
        mapHidden = false
    else
        if map then
            map.Parent = nil
        end
        if chunks then
            chunks.Parent = nil
        end
        bedrock = Instance.new("Part")
        bedrock.Name = "HiddenEnvironmentBedrock"
        bedrock.Anchored = true
        bedrock.Size = Vector3.new(8192, 2, 8192)
        bedrock.Position = Vector3.new(0, 0, 0)
        bedrock.BrickColor = BrickColor.new("grey")
        bedrock.Parent = workspace
        Message("Notice", "Environment hidden; platform created", 2)
        mapHidden = true
    end
end
-- GELUT BIG PLATFORM mechanism, retained under MountEiger's existing Platform toggle.
local bigPlatformPart = nil
local platformEnabled = config.platformEnabled == true

local function createBigPlatform()
    if bigPlatformPart and bigPlatformPart.Parent then return end

    -- Clean up an older copy before creating the platform.
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

local function setPlatformEnabled(enabled, saveState)
    platformEnabled = enabled == true

    if platformEnabled then
        createBigPlatform()
        Message("Platform", "Platform created", 2)
    else
        removeBigPlatform()
        Message("Platform", "Platform removed", 2)
    end

    config.platformEnabled = platformEnabled
    if saveState ~= false then
        autoSaveConfig()
    end
end

-- Restore the saved state and keep the platform available after respawn.
if platformEnabled then
    task.defer(createBigPlatform)
end

LocalPlayer.CharacterAdded:Connect(function()
    if platformEnabled then
        task.defer(createBigPlatform)
    end
end)
-- RUN SPEED (GELUT): original movement logic, integrated into MountEiger Character panel.
-- Default 100; accepts any finite non-negative number; no fixed upper cap.
local runSpeedEnabled = false
local runSpeedValue = 100
local runSpeedConnection = nil

local function setRunSpeedEnabled(enabled)
    runSpeedEnabled = enabled

    if runSpeedConnection then
        runSpeedConnection:Disconnect()
        runSpeedConnection = nil
    end

    if enabled then
        runSpeedConnection = RunService.Heartbeat:Connect(function(delta)
            if not mainUI or not mainUI.MainGui or not mainUI.MainGui.Parent or not runSpeedEnabled then
                return
            end

            local character = LocalPlayer.Character
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

local runSpeedToggle = figureSection:CreateToggle("RUN SPEED", function(enabled)
    setRunSpeedEnabled(enabled)
end)

-- Compact numeric field embedded in the MountEiger toggle, styled from UI.Theme.
local runSpeedBox = Instance.new("TextBox")
runSpeedBox.Name = "RunSpeedValue"
runSpeedBox.Size = UDim2.new(0, 29, 0, 23)
runSpeedBox.Position = UDim2.new(1, -32, 0.5, -11)
runSpeedBox.BackgroundColor3 = UI.Theme.Row
runSpeedBox.BorderSizePixel = 0
runSpeedBox.Text = tostring(runSpeedValue)
runSpeedBox.PlaceholderText = "Speed"
runSpeedBox.TextColor3 = UI.Theme.Text
runSpeedBox.PlaceholderColor3 = UI.Theme.Muted or UI.Theme.Text
runSpeedBox.TextSize = 10
runSpeedBox.Font = Enum.Font.GothamBold
runSpeedBox.ClearTextOnFocus = false
runSpeedBox.MultiLine = false
runSpeedBox.TextXAlignment = Enum.TextXAlignment.Center
runSpeedBox.ZIndex = runSpeedToggle.ZIndex + 1
runSpeedBox.Parent = runSpeedToggle

local runSpeedBoxCorner = Instance.new("UICorner")
runSpeedBoxCorner.CornerRadius = UDim.new(0, 5)
runSpeedBoxCorner.Parent = runSpeedBox

local runSpeedBoxStroke = Instance.new("UIStroke")
runSpeedBoxStroke.Color = UI.Theme.Border
runSpeedBoxStroke.Thickness = 1
runSpeedBoxStroke.Transparency = 0.25
runSpeedBoxStroke.Parent = runSpeedBox

local runSpeedToggleLabel = runSpeedToggle:FindFirstChildOfClass("TextLabel")
if runSpeedToggleLabel then
    runSpeedToggleLabel.Size = UDim2.new(1, -36, 1, 0)
    runSpeedToggleLabel.Position = UDim2.new(0, 5, 0, 0)
    runSpeedToggleLabel.Text = "RUN SPEED"
    runSpeedToggleLabel.TextSize = 11
    runSpeedToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
end

runSpeedBox.FocusLost:Connect(function()
    local entered = tonumber(runSpeedBox.Text)
    if entered and entered >= 0 and entered < math.huge then
        runSpeedValue = entered
    end
    runSpeedBox.Text = tostring(runSpeedValue)
end)

LocalPlayer.CharacterRemoving:Connect(function()
    if runSpeedConnection then
        runSpeedConnection:Disconnect()
        runSpeedConnection = nil
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    if runSpeedEnabled then
        task.wait(0.2)
        setRunSpeedEnabled(true)
    end
end)


-- SKYWALK (GELUT V13): integrated into MountEiger's existing Other section.
-- Keeps the tested GELUT behavior: save origin, teleport +4000 studs,
-- create a transparent 250000 x 10 x 250000 local platform, normal Humanoid movement,
-- and restore the saved pivot when switched OFF.
local SKY_TELEPORT_HEIGHT = 4000
local skyWalkEnabled = false
local skyWalkSavedPivot = nil
local skyWalkSavedPosition = nil
local skyWalkPlatform = nil
local skyWalkHeartbeat = nil

local function skyWalkClearObjects()
    if skyWalkHeartbeat then
        skyWalkHeartbeat:Disconnect()
        skyWalkHeartbeat = nil
    end
    if skyWalkPlatform then
        pcall(function()
            skyWalkPlatform:Destroy()
        end)
        skyWalkPlatform = nil
    end
end

local function skyWalkStop()
    skyWalkEnabled = false
    skyWalkClearObjects()

    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    -- Return to the exact activation transform, matching GELUT V13.
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
end

local function skyWalkStart()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if not character or not root or not humanoid or humanoid.Health <= 0 then
        warn("SKYWALK: character is not ready.")
        return false
    end

    skyWalkClearObjects()
    skyWalkSavedPivot = character:GetPivot()
    skyWalkSavedPosition = root.Position

    local targetPivot = skyWalkSavedPivot + Vector3.new(0, SKY_TELEPORT_HEIGHT, 0)
    local ok = pcall(function()
        character:PivotTo(targetPivot)
    end)

    if not ok then
        skyWalkSavedPivot = nil
        skyWalkSavedPosition = nil
        return false
    end

    root = character:FindFirstChild("HumanoidRootPart")
    humanoid = character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid then
        skyWalkStop()
        return false
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
        root.Position.Z
    )
    skyWalkPlatform.Transparency = 1
    skyWalkPlatform.CanCollide = true
    skyWalkPlatform.CanTouch = false
    skyWalkPlatform.CanQuery = false
    skyWalkPlatform.CastShadow = false
    skyWalkPlatform.Parent = workspace

    -- Keep ordinary Humanoid movement and joystick control; no flight forces.
    humanoid.PlatformStand = false
    humanoid.AutoRotate = true
    humanoid.Sit = false
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero

    skyWalkEnabled = true
    skyWalkHeartbeat = RunService.Heartbeat:Connect(function()
        if not skyWalkEnabled then return end

        local currentCharacter = LocalPlayer.Character
        local currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
        local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")

        if not currentRoot or not currentHumanoid or currentHumanoid.Health <= 0 or not skyWalkPlatform then
            skyWalkStop()
            return
        end
    end)

    return true
end

local function setSkyWalkEnabled(enabled)
    if enabled then
        if not skyWalkStart() then
            skyWalkEnabled = false
        end
    else
        skyWalkStop()
    end
end

-- If the character respawns while SkyWalk is active, clear the old local platform
-- and reset the state, matching the standalone GELUT V13 lifecycle behavior.
LocalPlayer.CharacterAdded:Connect(function()
    if skyWalkEnabled or skyWalkPlatform or skyWalkHeartbeat then
        skyWalkEnabled = false
        skyWalkClearObjects()
        skyWalkSavedPivot = nil
        skyWalkSavedPosition = nil
    end
end)

local otherSection = mainUI:NewSection("Other")
otherSection:CreateToggle("Platform", function(enabled)
    setPlatformEnabled(enabled)
end)
otherSection:CreateToggle("SkyWalk", function(enabled)
    setSkyWalkEnabled(enabled)
end)
otherSection:CreateToggle("Hide Map", function(enabled)
    toggleMap()
    for _, btn in ipairs(otherSection.Buttons) do
        if btn.Name == "ToggleBtn_Hide Map" then
            local stateLabel = btn:FindFirstChildOfClass("TextLabel")
            if stateLabel then
                stateLabel.Text = "Hide Map"
                stateLabel.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            end
            break
        end
    end
end)
otherSection:CreateToggle("View Data", function(enabled)
    if enabled then
        loadAndRunPlayerDataScript()
        for _, btn in ipairs(otherSection.Buttons) do
            if btn.Name == "ToggleBtn_View Data" then
                local stateLabel = btn:FindFirstChildOfClass("TextLabel")
                if stateLabel then
                    stateLabel.Text = "View Data"
                    stateLabel.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
                end
                break
            end
        end
    end
end)
otherSection:CreateToggle("TP Slam", function(enabled)
    ToggleTeleportThrowUI()
    for _, btn in ipairs(otherSection.Buttons) do
        if btn.Name == "ToggleBtn_Teleport Slam" then
            local stateLabel = btn:FindFirstChildOfClass("TextLabel")
            if stateLabel then
                stateLabel.Text = "TP Slam"
                stateLabel.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            end
            break
        end
    end
end)
otherSection:CreateToggle("TP Grab", function(enabled)
    ToggleTeleportGrabUI()
    for _, btn in ipairs(otherSection.Buttons) do
        if btn.Name == "ToggleBtn_Teleport Grab" then
            local stateLabel = btn:FindFirstChildOfClass("TextLabel")
            if stateLabel then
                stateLabel.Text = "TP Grab"
                stateLabel.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            end
            break
        end
    end
end)
LocalPlayer.CharacterAdded:Connect(function(newCharacter)
    task.wait(0.5)
    if antiFallEnabled then
        startAntiFall(newCharacter)
    end
end)
getgenv().FPDH = workspace.FallenPartsDestroyHeight
-- Built-in startup notification removed; dEnzCreator startup UI is used instead.


-- ================================================================
-- dEnzCreator | REPLACE INSTANCE SHUTDOWN REGISTRATION
-- This callback is installed only after the full script has initialized.
-- Each cleanup action is isolated; any failed action blocks replacement.
-- ================================================================
local function dEnzCreatorShutdownPreviousInstance()
    local cleanupSucceeded = true
    local function attempt(label, callback)
        local ok, err = pcall(callback)
        if not ok then
            cleanupSucceeded = false
            warn("[dEnzCreator] Cleanup failed (" .. label .. "): " .. tostring(err))
        end
    end

    -- Stop state-driven workers first so their loops can observe OFF.
    autofarm = false
    autoCollectingCubes = false
    autoClaimRewards = false
    autoeat = false
    farmMoving = false
    continuousGrabEnabled = false
    antiAnchorEnabled = false
    antiFallEnabled = false
    slippageEliminationEnabled = false
    gravityLockEnabled = false
    runSpeedEnabled = false
    wallClipEnabled = false
    flightEnabled = false
    skyWalkEnabled = false
    platformEnabled = false

    config.autofarm = false
    config.autoCollectingCubes = false
    config.autoClaimRewards = false
    config.autoeat = false
    config.farmMoving = false
    config.keepUnanchor = false
    config.antiFallEnabled = false
    config.slippageEliminationEnabled = false
    config.gravityLockEnabled = false
    config.platformEnabled = false

    -- Feature-specific cleanup routines.
    if type(stopAntiFall) == "function" then attempt("Anti Fall", stopAntiFall) end
    if type(toggleSlippageElimination) == "function" then
        attempt("No Slip", function() toggleSlippageElimination(false) end)
    end
    if type(toggleGravityLock) == "function" then
        attempt("Gravity Lock", function() toggleGravityLock(false) end)
    end
    if type(toggleContinuousGrab) == "function" then
        attempt("CS Grab", function() toggleContinuousGrab(false) end)
    end
    if type(teleportGrabStop) == "function" then
        attempt("TP Grab worker", function() teleportGrabStop("REPLACED BY NEW INSTANCE") end)
    end
    if type(setPlayerESPEnabled) == "function" then
        attempt("Player ESP", function() setPlayerESPEnabled(false) end)
    end
    if type(setAntiAnchorEnabled) == "function" then
        attempt("Anti Anchor", function() setAntiAnchorEnabled(false) end)
    end
    if type(setWallClipEnabled) == "function" then
        attempt("Wall Clip", function() setWallClipEnabled(false) end)
    end
    if type(setRunSpeedEnabled) == "function" then
        attempt("Run Speed", function() setRunSpeedEnabled(false) end)
    end
    if type(setFlightEnabled) == "function" then
        attempt("Flight", function() setFlightEnabled(false) end)
    end
    if type(skyWalkStop) == "function" then attempt("SkyWalk", skyWalkStop) end
    if type(removeBigPlatform) == "function" then attempt("Platform", removeBigPlatform) end
    if type(restoreWallClipParts) == "function" then attempt("Wall Clip restore", restoreWallClipParts) end
    if type(clearFlightForces) == "function" then attempt("Flight forces", clearFlightForces) end

    -- Disconnect known long-lived connections owned by this script.
    local ownedConnections = {
        cubeLootHeartbeatConnection, cubeLootAddedConnection, cubeLootRemovingConnection,
        candyLootAddedConnection, candyLootRemovingConnection, antiAnchorConnection,
        antiFallConnection, slippageConnection, gravityLockConnection,
        runSpeedConnection, wallClipConnection, skyWalkHeartbeat, continuousGrabConnection
    }
    for index, connection in ipairs(ownedConnections) do
        if connection and typeof(connection) == "RBXScriptConnection" then
            attempt("owned connection " .. tostring(index), function()
                if connection.Connected then connection:Disconnect() end
            end)
        end
    end

    if teleportThrowUI then
        attempt("TP Slam UI", function() teleportThrowUI:Destroy(); teleportThrowUI = nil end)
    end
    if teleportGrabUI then
        attempt("TP Grab UI", function() teleportGrabUI:Destroy(); teleportGrabUI = nil end)
    end
    if continuousGrabUI then
        attempt("CS Grab UI", function() continuousGrabUI:Destroy(); continuousGrabUI = nil end)
    end
    if invisibilityGui then
        attempt("Invisible UI", function() invisibilityGui:Destroy(); invisibilityGui = nil end)
    end
    if invisibilityConnections then
        for _, connection in pairs(invisibilityConnections) do
            if connection and connection.Connected then
                attempt("Invisible connection", function() connection:Disconnect() end)
            end
        end
        invisibilityConnections = {}
    end

    if ragdolled and type(unragdollCharacter) == "function" then
        attempt("Ragdoll restore", unragdollCharacter)
        ragdolled = false
    end
    if mapHidden and type(toggleMap) == "function" then
        attempt("Map restore", toggleMap)
    end

    -- Give state-driven workers a short opportunity to leave their loops.
    task.wait(0.35)

    if mainUI and mainUI.MainGui then
        attempt("Main UI", function() mainUI.MainGui:Destroy() end)
    end

    if not cleanupSucceeded then
        return false
    end
    return true
end

currentInstance.shutdown = dEnzCreatorShutdownPreviousInstance
currentInstance.status = "active"
