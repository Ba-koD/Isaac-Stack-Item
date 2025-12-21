local game = Game()
local itemConfig = Isaac.GetItemConfig()

local utils = {}

-- =========================================================
-- 공통 유틸
-- =========================================================
function utils.pHash(e)
    if GetPtrHash then
        return GetPtrHash(e)
    end
    return tostring(e)
end

-- Laser ShootAngle compatibility wrapper
function utils.ShootAngleCompat(variant, pos, angle, timeout, owner)
    -- Standard Repentance signature: (Variant, Position, Angle, Timeout, Spawner)
    local ok, laser = pcall(EntityLaser.ShootAngle, variant, pos, angle, timeout, owner)
    if ok and laser then 
        laser.Position = pos
        return laser 
    end

    -- Fallback 1: (Variant, Angle, Timeout, Position, Spawner)
    ok, laser = pcall(EntityLaser.ShootAngle, variant, angle, timeout, pos, owner)
    if ok and laser then 
        laser.Position = pos
        return laser 
    end

    -- Fallback 2: Manual spawn if API call fails
    local ent = Isaac.Spawn(EntityType.ENTITY_LASER, variant, 0, pos, Vector.Zero, owner)
    local l = ent:ToLaser()
    if l then
        l.AngleDegrees  = angle
        l.Timeout       = timeout
        l.SpawnerEntity = owner
        l.Parent        = owner
        return l
    end
    return nil
end

-- 방 안에서 Raycast 기반 최대 거리 추정
function utils.RaycastMaxDistance(pos, deg, fallback)
    local room = game:GetRoom()
    local FAR  = 2000
    local dir  = Vector.FromAngle(deg):Resized(FAR)

    local rc = room.Raycast or room.RayCast
    if rc then
        local ok, hit = pcall(function() return rc(room, pos, dir, 0, nil, false, false) end)
        if ok and hit and hit.X then
            return pos:Distance(hit)
        end
        ok, hit = pcall(function() return rc(room, pos, dir, 0, nil) end)
        if ok and hit and hit.X then
            return pos:Distance(hit)
        end
    end

    if room.CheckLine then
        local low, high = 0, FAR
        for _ = 1, 12 do
            local mid    = (low + high) * 0.5
            local target = pos + dir:Resized(mid)
            local clear  = false
            local ok, res = pcall(function() return room:CheckLine(pos, target, 0, 0, false, false) end)
            if ok and res then clear = true end
            if clear then low = mid else high = mid end
        end
        return math.max(24, high - 2)
    end

    return fallback or 240
end

-- Active Charge Helper (Rep+ / 구버전 호환)
function utils.AddActiveChargeCompat(player, amount, slot)
    if not player or amount == 0 then return end
    slot = slot or ActiveSlot.SLOT_PRIMARY

    if player.AddActiveCharge then
        player:AddActiveCharge(amount, slot)
        return
    end

    local activeItem = player:GetActiveItem(slot)
    if activeItem == 0 then return end

    local cfg        = itemConfig:GetCollectible(activeItem)
    local maxCharges = (cfg and cfg.MaxCharges) or 6

    local main    = player:GetActiveCharge(slot)
    local battery = player.GetBatteryCharge and player:GetBatteryCharge(slot) or 0

    local total = main + battery + amount
    if total < 0 then total = 0 end
    if total > maxCharges * 2 then
        total = maxCharges * 2
    end

    local newMain    = math.min(total, maxCharges)
    local newBattery = math.max(0, total - newMain)

    player:SetActiveCharge(newMain, slot)
    if player.SetBatteryCharge then
        player:SetBatteryCharge(newBattery, slot)
    end
end

return utils
