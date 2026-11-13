--[[
    dEnzCreator - Remote Whitelist
    Username matching uses LocalPlayer.Name, not DisplayName.
    This is client-side filtering; it is not tamper-proof.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

local WhitelistedUsers = {
    "hanssaputra15",
    "L0rdDarkShad0w",
    "chibhothax",
    "kkiktto",
    "Mount2702Blanc",
    "ibrak4dabra",
    "chimicaramel",
    "miskalagi",
    "STREZTBTMTVAY",
    "Carlydemul",
    "ChickenMcNuggetsBG",
    "orewaoreda9",
    "bubbleblob1926",
    "XxMystic_ShowxX",
    "yakitoritakoyaki319",
    "Nervozka163",
    "Xiao_raa0",
    "nrkb99",
    "tkz_ht",
    "mummy77776",
    "TOBI03310",
    "ZloyIzumrudikYT",
    "Papaangs",
    "bbomibbomiya",
    "Guru_Shaoilin"
}

local function notify(title, message, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = message,
            Duration = duration or 5
        })
    end)
end

if not LocalPlayer then
    warn("[dEnzCreator] Whitelist check failed: LocalPlayer unavailable.")
    return false
end

if not table.find(WhitelistedUsers, LocalPlayer.Name) then
    notify("dEnzCreator", "ACCESS DENIED - Username tidak terdaftar.", 5)
    warn("[dEnzCreator] ACCESS DENIED: " .. LocalPlayer.Name)
    return false
end

notify("dEnzCreator", "ACCESS GRANTED - Welcome, " .. LocalPlayer.Name .. "!", 5)
return true
