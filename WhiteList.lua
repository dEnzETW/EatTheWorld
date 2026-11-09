dEnzCreator — REMOTE WHITELIST INTEGRATION
==========================================

PENTING:
Pisahkan kode ini menjadi DUA file.
Jangan menempelkan isi WhiteList.lua ke dalam CANGCUD.lua.

--------------------------------------------------
FILE 1: WhiteList.lua
--------------------------------------------------

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
    warn("[dEnzCreator] ACCESS DENIED: " .. LocalPlayer.Name)
    return false
end

notify("dEnzCreator", "ACCESS GRANTED - Welcome, " .. LocalPlayer.Name .. "!", 5)
return true


--------------------------------------------------
FILE 2: GATE UNTUK BARIS PALING ATAS CANGCUD.lua
--------------------------------------------------

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
-- Tempel kode asli CANGCUD.lua tepat di bawah baris ini.
-- Jangan menambahkan isi WhiteList.lua di sini.
--==================================================


--------------------------------------------------
CARA MEMASANG
--------------------------------------------------

1. Simpan bagian FILE 1 sebagai WhiteList.lua.
2. Upload/commit WhiteList.lua ke:
   dEnzETW/EatTheWorld
   branch: main
   path: WhiteList.lua

3. Buka CANGCUD.lua.
4. Tempel bagian FILE 2 di baris paling atas.
5. Biarkan seluruh kode asli CANGCUD.lua berada tepat di bawah gate.
6. Pastikan WhiteList.lua sudah tersedia di URL raw sebelum menjalankan CANGCUD.lua.

CATATAN
-------
- Daftar di atas berisi 25 username yang ada pada kode yang dikirim di percakapan ini.
- Jika ada username tambahan yang sudah kamu masukkan sendiri ke GitHub, pertahankan/tambahkan juga pada file WhiteList.lua sebelum commit.
- Gate ini memerlukan executor yang mendukung game:HttpGet dan loadstring.
- Ini adalah pemeriksaan client-side; pengguna yang dapat mengubah script lokal berpotensi melewatinya.
- File ini berisi blok integrasi whitelist, bukan salinan lengkap CANGCUD.lua.
