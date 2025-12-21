-- =========================================================
-- Stackable Items RepPlus — Modular Loader
-- =========================================================
local mod = RegisterMod("Stackable Items RepPlus", 1)

-- 1. Load Utilities
local utils = require("scripts.utils")

-- 2. Define Item Modules to Load
local itemModules = {
    "scripts.items.habit",
    "scripts.items.godhead",
    "scripts.items.chocolate_milk_mip",
    "scripts.items.nine_volt",
    "scripts.items.hive_mind_bffs",
    "scripts.items.dead_bird",
    "scripts.items.spear_of_destiny",
    "scripts.items.tech5",
    "scripts.items.mini_pack",
    "scripts.items.eye_sore",
    "scripts.items.holy_light",
}

-- 3. Initialize Modules
for _, modulePath in ipairs(itemModules) do
    local ok, moduleFunc = pcall(require, modulePath)
    if ok and type(moduleFunc) == "function" then
        moduleFunc(mod, utils)
    else
        local err = moduleFunc or "Unknown error"
        print("[Stackable Items] Failed to load module: " .. modulePath .. " - Error: " .. tostring(err))
    end
end

print("[Stackable Items] Modular refactor loaded successfully.")
