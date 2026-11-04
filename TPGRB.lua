--==================================================
-- AUTO V1 | EAT THE WORLD
-- Standalone structure
--==================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

--==================================================
-- 1. AUTO FOLDER
--==================================================

local AUTO = {
    Running = false,

    Config = {
        AutoFarm = false,
        AutoCollect = false,
        AutoClaim = false,
        MoveMode = false,
        ShowMap = false,
        AutoEat = false
    },

    Connections = {},
    Remotes = {},
    Character = {}
}

--==================================================
-- 2. CENTRAL REMOTE REGISTRY
--==================================================

local function GetRemote(parent, name)
    if not parent then
        return nil
    end

    local remote = parent:FindFirstChild(name)

    if remote and (
        remote:IsA("RemoteEvent")
        or remote:IsA("RemoteFunction")
    ) then
        return remote
    end

    return nil
end

function AUTO:RefreshRemotes()
    local character = LocalPlayer.Character
    local characterEvents = character
        and character:FindFirstChild("Events")

    local serverEvents =
        ReplicatedStorage:FindFirstChild("Events")

    self.Remotes = {
        Grab = GetRemote(characterEvents, "Grab"),
        Eat = GetRemote(characterEvents, "Eat"),
        Sell = GetRemote(characterEvents, "Sell"),

        SendTrack = GetRemote(character, "SendTrack"),

        SetServerSettings =
            GetRemote(serverEvents, "SetServerSettings"),

        RewardEvent =
            GetRemote(serverEvents, "RewardEvent"),

        SpinEvent =
            GetRemote(serverEvents, "SpinEvent")
    }

    return self.Remotes
end

--==================================================
-- 3. CHARACTER REFERENCES
--==================================================

function AUTO:RefreshCharacter()
    local character = LocalPlayer.Character

    if not character then
        self.Character = {}
        return false
    end

    self.Character = {
        Model = character,
        Humanoid = character:FindFirstChildOfClass("Humanoid"),
        Root = character:FindFirstChild("HumanoidRootPart"),
        Size = character:FindFirstChild("Size"),
        CurrentChunk = character:FindFirstChild("CurrentChunk"),
        Radius = character:FindFirstChild("Radius"),
        LocalChunkManager =
            character:FindFirstChild("LocalChunkManager")
    }

    self:RefreshRemotes()

    return self.Character.Humanoid ~= nil
        and self.Character.Root ~= nil
end

--==================================================
-- 4. REMOTE STATUS
--==================================================

function AUTO:GetRemoteStatus()
    local result = {}

    for name, remote in pairs(self.Remotes) do
        result[name] = remote ~= nil
    end

    return result
end

--==================================================
-- 5. FEATURE REGISTRY
--==================================================

AUTO.Features = {
    AutoFarm = {
        Name = "AUTO FARM",
        Dependencies = {
            "Grab",
            "Eat",
            "Sell",
            "SendTrack",
            "SetServerSettings"
        }
    },

    AutoCollect = {
        Name = "AUTO COLLECT",
        Dependencies = {}
    },

    AutoClaim = {
        Name = "AUTO CLAIM",
        Dependencies = {
            "RewardEvent",
            "SpinEvent"
        }
    },

    MoveMode = {
        Name = "MOVE MODE",
        Dependencies = {
            "Radius"
        }
    },

    ShowMap = {
        Name = "SHOW MAP",
        Dependencies = {
            "Map",
            "Chunks"
        }
    },

    AutoEat = {
        Name = "AUTO EAT",
        Dependencies = {
            "Grab",
            "Eat"
        }
    }
}

--==================================================
-- 6. DEPENDENCY CHECK
--==================================================

function AUTO:CheckFeature(featureName)
    local feature = self.Features[featureName]

    if not feature then
        return false, "Feature tidak ditemukan"
    end

    self:RefreshCharacter()

    for _, dependency in ipairs(feature.Dependencies) do
        if dependency == "Map" or dependency == "Chunks" then
            if not workspace:FindFirstChild(dependency) then
                return false, dependency .. " tidak ditemukan"
            end
        elseif dependency == "Radius" then
            if not self.Character.Radius then
                return false, "Radius tidak ditemukan"
            end
        elseif not self.Remotes[dependency] then
            return false, "Remote " .. dependency .. " tidak ditemukan"
        end
    end

    return true, "Semua dependensi tersedia"
end

--==================================================
-- 7. FEATURE SWITCHES
--==================================================

function AUTO:SetFeature(featureName, enabled)
    if self.Features[featureName] == nil then
        return false, "Nama fitur tidak valid"
    end

    if enabled then
        local valid, message = self:CheckFeature(featureName)

        if not valid then
            return false, message
        end
    end

    self.Config[featureName] = enabled

    return true, enabled and "ON" or "OFF"
end

--==================================================
-- 8. CHARACTER RESPAWN HANDLER
--==================================================

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    AUTO:RefreshCharacter()
end)

--==================================================
-- 9. INITIAL CHECK
--==================================================

AUTO:RefreshCharacter()

print("================================")
print("AUTO V1 INITIALIZED")
print("================================")

for featureName, feature in pairs(AUTO.Features) do
    local valid, message = AUTO:CheckFeature(featureName)

    print(
        feature.Name,
        valid and "READY" or "WAITING",
        message
    )
end

print("================================")
print("AUTO V1 READY")
print("================================")

return AUTO
