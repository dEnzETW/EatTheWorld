--==================================================
-- dEnzCreator | REMOTE WHITELIST GATE
--==================================================

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

--==================================================
-- ORIGINAL CANGCUD.LUA STARTS BELOW
--==================================================--[[
    dEnzCreator - Whitelist
    Standalone Lua section for integration into the main script.

    Username matching uses LocalPlayer.Name, not DisplayName.
    This is client-side filtering; obfuscation does not make it tamper-proof.
    Place this check at the start of dEnzCreator, before UI/features initialize.
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
    "syunako52",
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
    return false
end

notify("dEnzCreator", "ACCESS GRANTED - Welcome, " .. LocalPlayer.Name .. "!", 5)

-- Whitelist passed. Continue with the main dEnzCreator script below this point.
return true
