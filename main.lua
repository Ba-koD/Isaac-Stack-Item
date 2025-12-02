-- =========================================================
-- Stackable Items RepPlus — Stabilized (Optimized Layout)
--  - 단일 mod / 단일 game 인스턴스
--  - 공통 유틸 한 번만 정의
--  - 상수 이름 충돌 제거
-- =========================================================
local mod  = RegisterMod("Stackable Items RepPlus", 1)
local game = Game()
local itemConfig = Isaac.GetItemConfig()

-- =========================================================
-- 공통 유틸
-- =========================================================
local function pHash(e)
    if GetPtrHash then
        return GetPtrHash(e)
    end
    return tostring(e)
end

-- Laser ShootAngle 호환 래퍼
local function ShootAngleCompat(variant, angle, timeout, pos, owner)
    local ok, laser = pcall(EntityLaser.ShootAngle, variant, angle, timeout, pos, owner, owner)
    if ok and laser then return laser end

    ok, laser = pcall(EntityLaser.ShootAngle, variant, angle, timeout, pos, owner)
    if ok and laser then return laser end

    ok, laser = pcall(EntityLaser.ShootAngle, variant, angle, timeout, pos)
    if ok and laser then return laser end

    ok, laser = pcall(EntityLaser.ShootAngle, variant, pos, angle, timeout, owner)
    if ok and laser then return laser end

    ok, laser = pcall(EntityLaser.ShootAngle, variant, pos, angle, timeout, owner, owner)
    if ok and laser then return laser end

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
local function RaycastMaxDistance(pos, deg, fallback)
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

-- =========================================================
-- Active Charge Helper (Rep+ / 구버전 호환)
-- =========================================================
local function AddActiveChargeCompat(player, amount, slot)
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

-- =====================================================================
-- Habit (Nun's Habit, ID 156) — Battery 포함 오버차지 총량 보정
-- =====================================================================
local HABIT = 156
mod.extraCharge = nil

function mod:OnPlayerDamage_Habit(entity, amount, flags, source, countdown)
    if entity.Type ~= EntityType.ENTITY_PLAYER then return end
    local player = entity:ToPlayer()
    if not player then return end

    local count = player:GetCollectibleNum(HABIT)
    if count <= 0 then return end

    local slot
    if player:GetActiveItem(ActiveSlot.SLOT_PRIMARY) ~= 0 then
        slot = ActiveSlot.SLOT_PRIMARY
    elseif player:GetActiveItem(ActiveSlot.SLOT_SECONDARY) ~= 0 then
        slot = ActiveSlot.SLOT_SECONDARY
    else
        return
    end

    local main0 = player:GetActiveCharge(slot)
    local bat0  = player.GetBatteryCharge and player:GetBatteryCharge(slot) or 0

    mod.extraCharge = {
        index  = player.ControllerIndex,
        slot   = slot,
        stacks = count,
        main0  = main0,
        bat0   = bat0,
    }
end
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnPlayerDamage_Habit)

function mod:OnUpdate_Habit()
    local ec = mod.extraCharge
    if not ec then return end
    mod.extraCharge = nil

    local player = Isaac.GetPlayer(ec.index)
    if not (player and player:Exists()) then return end

    local slot   = ec.slot
    local stacks = ec.stacks

    local activeItem = player:GetActiveItem(slot)
    if activeItem == 0 then return end

    local cfg        = itemConfig:GetCollectible(activeItem)
    local maxCharges = (cfg and cfg.MaxCharges) or 6
    local maxTotal   = maxCharges * 2

    local extraStacks = math.max(0, stacks - 1)
    local desiredGain = 1 + extraStacks

    local main1  = player:GetActiveCharge(slot)
    local bat1   = player.GetBatteryCharge and player:GetBatteryCharge(slot) or 0
    local total1 = main1 + bat1

    local desiredTotal = ec.main0 + ec.bat0 + desiredGain
    if desiredTotal > maxTotal then
        desiredTotal = maxTotal
    end

    if total1 >= desiredTotal then
        return
    end

    local finalMain = math.min(desiredTotal, maxCharges)
    local finalBat  = math.max(0, desiredTotal - finalMain)

    player:SetActiveCharge(finalMain, slot)
    if player.SetBatteryCharge then
        player:SetBatteryCharge(finalBat)
    end
end
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnUpdate_Habit)

-- =====================================================================
-- Godhead (ID 331)
-- =====================================================================
local GODHEAD = 331
local _godheadGuard = false

function mod:OnEntityDamage_Godhead(entity, amount, flags, source, countdown)
    if _godheadGuard then return end
    if not (entity and entity:IsVulnerableEnemy()) then return end
    if not (source and source.Entity) then return end

    local tear = source.Entity:ToTear()
    if not tear then return end
    if (tear.TearFlags & TearFlags.TEAR_GLOW) == 0 then return end

    local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
    if not player then return end

    local count = player:GetCollectibleNum(GODHEAD)
    if count <= 1 then return end

    local dmg = 2 + (count - 1) * 2
    _godheadGuard = true
    entity:TakeDamage(dmg, flags, source, countdown)
    _godheadGuard = false
    return false
end
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnEntityDamage_Godhead)

-- =====================================================================
-- Chocolate Milk (69) + Money = Power (109)
-- =====================================================================
local CHOCOLATE_MILK = 69
local MONEY_IS_POWER = 109

function mod:OnEvaluateCache_All(player, cacheFlag)
    if cacheFlag ~= CacheFlag.CACHE_DAMAGE then return end

    local mip = player:GetCollectibleNum(MONEY_IS_POWER)
    if mip > 0 then
        player.Damage = player.Damage + (player:GetNumCoins() * 0.04 * mip)
    end

    local ch = player:GetCollectibleNum(CHOCOLATE_MILK)
    local d  = player:GetData()
    if ch > 0 then
        d.ChocoMin = 0.25 * ch
        d.ChocoMax = 2.0 + (ch - 1) * 1.0
    else
        d.ChocoMin, d.ChocoMax = nil, nil
    end
end
mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, mod.OnEvaluateCache_All)

function mod:OnTearInit_Choco(tear)
    local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
    if not player then return end
    if player:GetCollectibleNum(CHOCOLATE_MILK) <= 0 then return end

    local d       = player:GetData()
    local minMult = d.ChocoMin or 0.25
    local maxMult = d.ChocoMax or 2.0
    local charge  = math.min(1.0, tear.Charge or 1.0)

    tear.CollisionDamage = tear.CollisionDamage * (minMult + (maxMult - minMult) * charge)
end
mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, mod.OnTearInit_Choco)

-- =====================================================================
-- 9 Volt (ID 116)
-- =====================================================================
local NINE_VOLT = 116

function mod:OnUseItem_NineVolt(itemID, rng, player, flags, slot, varData)
    local c = player:GetCollectibleNum(NINE_VOLT)
    if c <= 1 then return end

    local s      = slot or ActiveSlot.SLOT_PRIMARY
    local amount = c - 1
    AddActiveChargeCompat(player, amount, s)
end
mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.OnUseItem_NineVolt)

-- =====================================================================
-- Hive Mind & BFFs (Additive stacking)
-- =====================================================================
local ADD_PER_STACK_BFF = 0.50
local BFF_SCALE_PER_STACK = 0.05
local HM_SCALE_PER_STACK  = 0.05

local HIVEMIND = 248
local BFFS     = 247

local BLUE_FLY    = FamiliarVariant.BLUE_FLY
local BLUE_SPIDER = FamiliarVariant.BLUE_SPIDER
local INCUBUS     = FamiliarVariant.INCUBUS
local SUCCUBUS    = FamiliarVariant.SUCCUBUS

local function isFlyOrSpiderFam(fam)
    return fam and (fam.Variant == BLUE_FLY or fam.Variant == BLUE_SPIDER)
end

local function stackMultAdditive(stacks)
    if stacks <= 0 then return 1 end
    return 2 + ADD_PER_STACK_BFF * (stacks - 1)
end

local function bffStackMult(bff)
    return stackMultAdditive(bff)
end

local function bffExtraMultForEngineBuffed(fam)
    if not fam or isFlyOrSpiderFam(fam) then return 1 end
    local p = fam.Player
    if not p then return 1 end
    local bff = p:GetCollectibleNum(BFFS)
    if bff <= 0 then return 1 end
    return 1 + (ADD_PER_STACK_BFF * 0.5) * (bff - 1)
end

local function nearestIncubusForPlayer(posEntity, ownerPlayer, radiusPx)
    local pos = posEntity.Position
    local nearest, bestD2 = nil, (radiusPx * radiusPx)
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, -1, -1, false, false)) do
        local f = e:ToFamiliar()
        if f and f.Variant == INCUBUS and f.Player and ownerPlayer and f.Player.InitSeed == ownerPlayer.InitSeed then
            local d2 = (f.Position - pos):LengthSquared()
            if d2 < bestD2 then nearest, bestD2 = f, d2 end
        end
    end
    return nearest
end

local function incuFiredThisTear(tear, incu)
    if not (tear and incu) then return false end
    local v = tear.Velocity
    if not v or v:LengthSquared() < 1e-4 then return false end

    local dpos = tear.Position - incu.Position
    local dir  = v:Normalized()
    local t    = dpos:Dot(dir)
    if t <= -2 then return false end
    local perp = (dpos - dir * t):Length()
    return (dpos:LengthSquared() <= (48*48)) and (perp <= 10)
end

local function applyBffProjectileOnce(ent, mult, baseGetter, baseSetter, tag)
    if mult == 1 then return end
    local d = ent:GetData()
    if d[tag .. "_applied"] then return end

    d[tag .. "_applied"]      = true
    d[tag .. "_frames_left"]  = 2
    local base                = baseGetter(ent)
    d[tag .. "_base"]         = base
    d[tag .. "_mult"]         = mult
    baseSetter(ent, base * mult)
end

local function tickReassertProjectile(ent, baseGetter, baseSetter, tag)
    local d    = ent:GetData()
    local left = d[tag .. "_frames_left"]
    if not left or left <= 0 then return end

    local base = d[tag .. "_base"]
    local mult = d[tag .. "_mult"] or 1
    if base and mult ~= 1 then
        baseSetter(ent, base * mult)
    end
    d[tag .. "_frames_left"] = left - 1
end

function mod:OnFamiliarUpdate_HiveMindOnly(fam)
    local player = fam.Player
    if not player then return end

    local v = fam.Variant
    if v ~= BLUE_FLY and v ~= BLUE_SPIDER then return end

    local hive = player:GetCollectibleNum(HIVEMIND)
    if hive <= 0 then return end

    local d = fam:GetData()
    if not d.__hive_base_init then
        d.__hive_base_damage = fam.CollisionDamage
        d.__hive_base_scale  = fam.SpriteScale or Vector(1, 1)
        d.__hive_base_size   = fam.Size or 10
        d.__hive_base_init   = true
    end

    local dmg_mult = stackMultAdditive(hive)
    fam.CollisionDamage = (d.__hive_base_damage or fam.CollisionDamage) * dmg_mult

    if HM_SCALE_PER_STACK ~= 0 then
        local scale_mult = 1 + HM_SCALE_PER_STACK * (hive - 1)
        fam.SpriteScale  = Vector(
            d.__hive_base_scale.X * scale_mult,
            d.__hive_base_scale.Y * scale_mult
        )
        fam.Size         = (d.__hive_base_size or fam.Size) * scale_mult
    end
end
mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, mod.OnFamiliarUpdate_HiveMindOnly)

local function applyBffToFamiliarBody(fam)
    local player = fam.Player
    if not player or isFlyOrSpiderFam(fam) then return end

    local bff = player:GetCollectibleNum(BFFS)
    if bff <= 0 then return end

    local d = fam:GetData()
    if not d.__bff_base_init then
        d.__bff_base_damage = fam.CollisionDamage
        d.__bff_base_scale  = fam.SpriteScale or Vector(1,1)
        d.__bff_base_size   = fam.Size or 10
        d.__bff_base_init   = true
    end

    local dmg_mult   = bffStackMult(bff)
    local scale_mult = 1 + BFF_SCALE_PER_STACK * (bff - 1)

    fam.CollisionDamage = (d.__bff_base_damage or fam.CollisionDamage) * dmg_mult
    fam.SpriteScale     = Vector(d.__bff_base_scale.X * scale_mult, d.__bff_base_scale.Y * scale_mult)
    fam.Size            = (d.__bff_base_size or fam.Size) * scale_mult
end

function mod:OnFamiliarUpdate_BFF(fam)
    applyBffToFamiliarBody(fam)
end
mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, mod.OnFamiliarUpdate_BFF)

function mod:OnTearInit_BFF(tear)
    local td = tear:GetData()
    if td.__bff_any_applied then return end

    local fam = (tear.Parent and tear.Parent:ToFamiliar()) or (tear.SpawnerEntity and tear.SpawnerEntity:ToFamiliar())
    if fam then
        if isFlyOrSpiderFam(fam) then return end

        if fam.Variant == INCUBUS then
            td.__bff_incu_wait   = true
            td.__bff_incu_owner  = fam.Player and fam.Player.InitSeed or nil
            td.__bff_any_applied = true
            return
        else
            local mult = bffExtraMultForEngineBuffed(fam)
            applyBffProjectileOnce(
                tear, mult,
                function(t) return (t.CollisionDamage and t.CollisionDamage > 0) and t.CollisionDamage or 3.5 end,
                function(t, v) t.CollisionDamage = v end,
                "__bff_tear"
            )
            td.__bff_any_applied = true
            return
        end
    end

    local ownerP = (tear.Parent and tear.Parent:ToPlayer()) or (tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer())
    if ownerP then
        local incu = nearestIncubusForPlayer(tear, ownerP, 48)
        if incu and incuFiredThisTear(tear, incu) then
            td.__bff_incu_wait   = true
            td.__bff_incu_owner  = ownerP.InitSeed
            td.__bff_any_applied = true
        end
        return
    end
end
mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, mod.OnTearInit_BFF)

function mod:OnTearUpdate_BFF(tear)
    local td = tear:GetData()

    if td.__bff_incu_wait and not td.__bff_incu_done then
        if tear.CollisionDamage and tear.CollisionDamage > 0 then
            local ownerP = Isaac.GetPlayer(0)
            if td.__bff_incu_owner and ownerP and ownerP.InitSeed ~= td.__bff_incu_owner then
                -- TODO: 멀티플레이 대응
            end
            local incu = nearestIncubusForPlayer(tear, ownerP, 56)
            local mult = 1
            if incu then
                mult = bffExtraMultForEngineBuffed(incu)
            end
            if mult ~= 1 then
                applyBffProjectileOnce(
                    tear, mult,
                    function(t) return t.CollisionDamage end,
                    function(t, v) t.CollisionDamage = v end,
                    "__bff_tear"
                )
            end
            td.__bff_incu_done = true
            td.__bff_incu_wait = false
        end
    end

    tickReassertProjectile(
        tear,
        function(t) return t.CollisionDamage end,
        function(t, v) t.CollisionDamage = v end,
        "__bff_tear"
    )
end
mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, mod.OnTearUpdate_BFF)

function mod:OnLaserInit_BFF(laser)
    local ld = laser:GetData()
    if ld.__bff_lz_marked then return end
    ld.__bff_lz_marked = true
    ld.__bff_lz_done   = false
end
mod:AddCallback(ModCallbacks.MC_POST_LASER_INIT, mod.OnLaserInit_BFF)

function mod:OnLaserUpdate_BFF(laser)
    local ld = laser:GetData()
    if not ld.__bff_lz_marked or ld.__bff_lz_done then return end

    local fam = (laser.Parent and laser.Parent:ToFamiliar()) or (laser.SpawnerEntity and laser.SpawnerEntity:ToFamiliar())
    if not fam or isFlyOrSpiderFam(fam) then ld.__bff_lz_done = true; return end

    local mult = bffExtraMultForEngineBuffed(fam)
    if mult == 1 then ld.__bff_lz_done = true; return end

    if laser.CollisionDamage and laser.CollisionDamage > 0 then
        local base = laser.CollisionDamage
        laser.CollisionDamage = base * mult
        ld.__bff_lz_done = true
    end
end
mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, mod.OnLaserUpdate_BFF)

function mod:OnEntityTakeDamage_BFF(entity, amount, flags, source, countdown)
    if amount <= 0 then return end
    if not source or not source.Entity then return end

    local fam = source.Entity:ToFamiliar()
    if fam and fam.Variant == SUCCUBUS and fam.Player then
        local bff  = fam.Player:GetCollectibleNum(BFFS)
        local mult = bffStackMult(bff)
        if mult == 1 then return end

        local fd = fam:GetData()
        if fd.__bff_succ_guard then
            return
        end

        fd.__bff_succ_guard = true
        entity:TakeDamage(amount * mult, flags, source, countdown)
        fd.__bff_succ_guard = false
        return true
    end
end
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnEntityTakeDamage_BFF)

-- =====================================================================
-- Dead Bird (ID 117)
-- =====================================================================
local DEAD_BIRD = 117
local spawn_dead_bird = {true, true, true, true, true, true, true, true}

function mod:OnPlayerDamage_DeadBird(entity, amount, flags, source, countdown)
    if entity.Type ~= EntityType.ENTITY_PLAYER then return end
    local player = entity:ToPlayer()
    if not (player and player:HasCollectible(DEAD_BIRD)) then return end

    local extra = player:GetCollectibleNum(DEAD_BIRD) - 1
    if extra <= 0 then return end

    local idx = player.Index + 1
    if not spawn_dead_bird[idx] then return end

    for _ = 1, extra do
        Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.DEAD_BIRD, 0, player.Position, Vector.Zero, player)
    end
    spawn_dead_bird[idx] = false
end
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnPlayerDamage_DeadBird)

function mod:OnNewRoom_DeadBird()
    spawn_dead_bird = {true, true, true, true, true, true, true, true}
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom_DeadBird)

-- =====================================================================
-- Spear of Destiny (ID 400) — Additive stacking
-- =====================================================================
local SPEAR_OF_DESTINY = 400
local spearVariant, spearGuard = nil, false
local spearHitCD = {}
local ADD_PER_STACK_SPEAR = 0.10

local SPEAR_XSCALE_PER_STACK      = 0.15
local SPEAR_ADD_LEN_PER_STACK     = 12
local SPEAR_TIP_BACK_PAD          = 6
local SPEAR_BASE_HALF_WIDTH       = 10
local SPEAR_EXTRA_WIDTH_PER_STACK = 2
local SPEAR_COOLDOWN_FRAMES       = 3

local function spear_total_mult(stacks)
    if stacks <= 1 then return 1 end
    return 1 + ADD_PER_STACK_SPEAR * (stacks - 1)
end

function mod:OnGameStart_Spear()
    spearVariant, spearGuard = nil, false
    spearHitCD = {}
end
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStart_Spear)

function mod:OnNewRoom_Spear()
    spearHitCD = {}
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom_Spear)

function mod:OnEntityDamage_SpearOnly(entity, amount, flags, source, countdown)
    if spearGuard then return end
    if not (entity and entity:IsVulnerableEnemy()) then return end
    if not (source and source.Entity) then return end

    local src = source.Entity
    if src.Type ~= EntityType.ENTITY_EFFECT then return end
    local eff = src:ToEffect()
    if not eff then return end

    if not spearVariant then
        local owner = src.SpawnerEntity and src.SpawnerEntity:ToPlayer() or nil
        if owner and owner:HasCollectible(SPEAR_OF_DESTINY) then
            spearVariant = eff.Variant
        end
    end
    if spearVariant and eff.Variant ~= spearVariant then return end

    local player = src.SpawnerEntity and src.SpawnerEntity:ToPlayer() or nil
    if not player then return end

    local stacks = player:GetCollectibleNum(SPEAR_OF_DESTINY)
    if stacks <= 1 then return end

    local mult = spear_total_mult(stacks)

    spearGuard = true
    entity:TakeDamage((amount or 0) * mult, flags or 0, source, countdown or 0)
    spearGuard = false

    return false
end
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnEntityDamage_SpearOnly)

function mod:OnEffectUpdate_SpearLength(effect)
    if effect.Type ~= EntityType.ENTITY_EFFECT then return end
    local eff = effect:ToEffect()
    if not eff then return end

    local player = effect.SpawnerEntity and effect.SpawnerEntity:ToPlayer() or nil
    if not player then return end

    local stacks = player:GetCollectibleNum(SPEAR_OF_DESTINY)
    if stacks <= 1 then return end
    local extra = stacks - 1

    if not spearVariant then spearVariant = eff.Variant end
    if spearVariant and eff.Variant ~= spearVariant then return end

    if SPEAR_XSCALE_PER_STACK ~= 0 then
        effect.SpriteScale = Vector(
            1 + SPEAR_XSCALE_PER_STACK * extra,
            effect.SpriteScale.Y
        )
    end

    local dir = effect.Position - player.Position
    local dlen = dir:Length()
    if dlen < 0.1 then return end
    dir = dir / dlen

    local addLen = SPEAR_ADD_LEN_PER_STACK * extra
    if addLen <= 0 then return end

    local tipStart = effect.Position - dir * SPEAR_TIP_BACK_PAD
    local halfW    = SPEAR_BASE_HALF_WIDTH + (SPEAR_EXTRA_WIDTH_PER_STACK * extra)

    local dmgMult     = spear_total_mult(stacks)
    local spearDamage = (player.Damage or 0) * 2 * dmgMult

    local frame = game:GetFrameCount()
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        if e:IsVulnerableEnemy() and not e:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) and not e:IsDead() then
            local rel = e.Position - tipStart
            local t   = rel:Dot(dir)
            if t >= 0 and t <= (SPEAR_TIP_BACK_PAD + addLen) then
                local perp = rel - dir * t
                if perp:Length() <= halfW then
                    local key = pHash(e)
                    if (spearHitCD[key] or 0) <= frame then
                        spearHitCD[key] = frame + SPEAR_COOLDOWN_FRAMES
                        spearGuard = true
                        e:TakeDamage(spearDamage, 0, EntityRef(effect), 0)
                        spearGuard = false
                    end
                end
            end
        end
    end
end
mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, mod.OnEffectUpdate_SpearLength)

-- =====================================================================
-- Tech.5 (ID 244) — stack-aware extras that stop at walls
-- =====================================================================
local TECH5 = 244
local TECH5_SPREAD_DEG = 5

local function markExtraT5(l)    l:GetData().t5_extra   = true end
local function isExtraT5(l)      return l:GetData().t5_extra   == true end
local function handledT5(l)      return l:GetData().t5_handled == true end
local function setHandledT5(l)   l:GetData().t5_handled = true end

local EXCLUDE_VARIANTS_T5 = {
    [LaserVariant.LASER_BRIMSTONE or -1] = true,
    [LaserVariant.LASER_TECH2    or -1] = true,
    [LaserVariant.LIGHT_RING     or -1] = true,
}

local function looksLikeTech5(l)
    if not (l.SpawnerEntity and l.SpawnerEntity:ToPlayer()) then return false end
    local t = l.Timeout or 0
    if t <= 0 or t > 30 then return false end
    if EXCLUDE_VARIANTS_T5[l.Variant or -1] then return false end
    return true
end

local t5_origins, t5_extras = {}, {}

function mod:OnLaserUpdate_Tech5(laser)
    if isExtraT5(laser) or handledT5(laser) then return end
    local player = laser.SpawnerEntity and laser.SpawnerEntity:ToPlayer()
    if not player or not player:HasCollectible(TECH5) then return end

    setHandledT5(laser)
    if not looksLikeTech5(laser) then return end

    local count = player:GetCollectibleNum(TECH5)
    local extra = count - 1
    if extra <= 0 then
        markExtraT5(laser)
        return
    end

    local baseVariant = laser.Variant
    local baseAngle   = laser.AngleDegrees or 0
    local baseTimeout = laser.Timeout or 12
    local baseDamage  = laser.CollisionDamage or player.Damage
    local baseMaxDist = laser.GetMaxDistance and laser:GetMaxDistance() or nil

    local originHash = pHash(laser)
    t5_origins[originHash] = laser
    markExtraT5(laser)

    local half = (extra - 1) * 0.5
    for i = 0, extra - 1 do
        local ang = baseAngle + ((i - half) * TECH5_SPREAD_DEG)
        local spawnPos = laser.Position
        local new = ShootAngleCompat(baseVariant, ang, baseTimeout, spawnPos, player)
        if new then
            new.Position        = spawnPos
            new.SpawnerEntity   = player
            new.Parent          = player
            new.CollisionDamage = baseDamage

            local dist = baseMaxDist
            if (not dist) or dist <= 0 then
                dist = RaycastMaxDistance(spawnPos, ang, 240)
            end
            if new.SetMaxDistance then new:SetMaxDistance(dist) end

            if laser.TearFlags then new.TearFlags = laser.TearFlags end
            if (new.GridCollisionClass ~= nil) and (laser.GridCollisionClass ~= nil) then
                new.GridCollisionClass = laser.GridCollisionClass
            end

            new.Color       = laser.Color
            new.DepthOffset = laser.DepthOffset
            new:Update()

            local d = new:GetData()
            d.t5_extra, d.t5_handled, d.t5_followHash = true, true, originHash
            table.insert(t5_extras, new)
        end
    end
end
mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, mod.OnLaserUpdate_Tech5)

function mod:OnPostUpdate_Tech5Snap()
    for i = #t5_extras, 1, -1 do
        local l = t5_extras[i]
        if (not l) or (not l:Exists()) then
            table.remove(t5_extras, i)
        else
            local hash   = l:GetData() and l:GetData().t5_followHash
            local origin = hash and t5_origins[hash] or nil
            if origin and origin:Exists() then
                l.Position = origin.Position
            else
                if hash then t5_origins[hash] = nil end
            end
        end
    end
end
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnPostUpdate_Tech5Snap)

function mod:OnNewRoom_Tech5()
    t5_origins, t5_extras = {}, {}
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom_Tech5)

function mod:OnGameStart_Tech5()
    t5_origins, t5_extras = {}, {}
end
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStart_Tech5)

-- =====================================================================
-- Mini Pack (ID 204)
-- =====================================================================
local MINIPACK = 204

local ALLOWED_VARIANTS = {
    PickupVariant.PICKUP_COIN,
    PickupVariant.PICKUP_HEART,
    PickupVariant.PICKUP_KEY,
    PickupVariant.PICKUP_BOMB,
    PickupVariant.PICKUP_BATTERY
}

local function spawnAllowedPickup(rng, player)
    local room = game:GetRoom()
    local pos  = room:FindFreePickupSpawnPosition(player.Position, 0, true)
    local idx  = rng:RandomInt(#ALLOWED_VARIANTS) + 1
    local variant = ALLOWED_VARIANTS[idx]
    Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, 0, pos, Vector.Zero, player)
end

function mod:OnEntityTakeDamage_MiniPack(ent, amount, flags, source, countdown)
    local player = ent:ToPlayer()
    if not player or not player:HasCollectible(MINIPACK) then return end

    local count = player:GetCollectibleNum(MINIPACK)
    if count <= 0 then return end

    local rng = player:GetCollectibleRNG(MINIPACK)
    for _ = 1, count do
        if rng:RandomFloat() < 0.5 then
            spawnAllowedPickup(rng, player)
        end
    end
end
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnEntityTakeDamage_MiniPack)

-- =====================================================================
-- Eye Sore (ID 558)
-- =====================================================================
local EYESORE    = 558
local FIXED_PROC = 0.30

function mod:OnTear_EyeSore(tear)
    local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
    if not player or not player:HasCollectible(EYESORE) then return end

    local c = player:GetCollectibleNum(EYESORE)
    if c <= 0 then return end

    local frame = game:GetFrameCount()
    local d     = player:GetData()
    d.__eyesore_last_fire_frame = d.__eyesore_last_fire_frame or -1

    if d.__eyesore_last_fire_frame == frame then return end

    local rng = player:GetCollectibleRNG(EYESORE)
    if rng:RandomFloat() >= FIXED_PROC then
        return
    end

    d.__eyesore_last_fire_frame = frame
    local extraMin, extraMax = c, c + 2
    local extra = rng:RandomInt(extraMax - extraMin + 1) + extraMin

    local speed = 10 / (player.MaxFireDelay / 10 + 1)
    for _ = 1, extra do
        local angle = rng:RandomFloat() * 360.0
        local vel   = Vector.FromAngle(angle):Resized(speed)
        local t     = player:FireTear(player.Position, vel, false, false, false)
        if t then
            t.CollisionDamage = player.Damage
        end
    end
end
mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, mod.OnTear_EyeSore)

-- =====================================================================
-- Holy Light — stackable damage + size + AoE pulse
-- =====================================================================
local HOLY_LIGHT = CollectibleType.COLLECTIBLE_HOLY_LIGHT
local V_CRACK    = EffectVariant.CRACK_THE_SKY

local function hlDmgMult(count)
    return (count <= 0) and 1.0 or (3.0 * (1.2 ^ (count - 1)))
end
local function hlVisMult(count)
    return (count <= 0) and 1.0 or (1.0 + 0.03 * (count - 1))
end

local function hlEnsureBase(eff)
    local d = eff:GetData()
    if d.__hl_base_saved then return end
    d.__hl_base_saved = true
    d.__hl_base_scale = eff.SpriteScale or Vector(1,1)
    d.__hl_base_size  = eff.Size or 1
end

local VISUAL_R0    = 11.5
local INNER_RATIO  = 0.85
local MAX_RADIUS   = 120.0
local MIN_RADIUS   = 6.0
local PULSE_FRAMES = {1,2,3}
local DMG_FLAGS    = (DamageFlag.DAMAGE_NO_PENALTIES or 0)

local function hlFrameIn(tbl, f)
    for _, v in ipairs(tbl) do
        if v == f then return true end
    end
    return false
end

local function hlIsEnemy(ent)
    local npc = ent and ent:ToNPC()
    if not npc then return false end
    if not npc:IsVulnerableEnemy() then return false end
    if npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return false end
    return true
end

local function hlApplyMainPillar(eff)
    hlEnsureBase(eff)
    local d = eff:GetData()

    local p = eff.SpawnerEntity and eff.SpawnerEntity:ToPlayer()
    if not p then
        local nearest, best = nil, 1e12
        for i = 0, game:GetNumPlayers() - 1 do
            local pl   = Isaac.GetPlayer(i)
            local dist = (pl.Position - eff.Position):LengthSquared()
            if dist < best then best, nearest = dist, pl end
        end
        p = nearest
    end
    local count = p and p:GetCollectibleNum(HOLY_LIGHT) or 0

    local sMul = hlVisMult(count)
    eff.SpriteScale = Vector(d.__hl_base_scale.X * sMul, d.__hl_base_scale.Y * sMul)

    if p then
        eff.CollisionDamage = p.Damage * hlDmgMult(count)
    end

    return p, count
end

local function hlApplyAoePulse(eff, player, count)
    if not player then return end
    local f = eff.FrameCount
    if not hlFrameIn(PULSE_FRAMES, f) then return end

    local d = eff:GetData()
    if d.__hl_pulse_tag ~= f then
        d.__hl_pulse_tag = f
        d.__hl_hit = {}
    end

    local baseS = d.__hl_base_scale.X ~= 0 and d.__hl_base_scale.X or 1
    local curS  = eff.SpriteScale.X
    local sVis  = curS / baseS
    local radius = math.max(MIN_RADIUS,
                    math.min(VISUAL_R0 * sVis * INNER_RATIO, MAX_RADIUS))

    local desiredDmg = player.Damage * hlDmgMult(count)
    local ents = Isaac.FindInRadius(eff.Position, radius, EntityPartition.ENEMY)

    for _, e in ipairs(ents) do
        if hlIsEnemy(e) then
            local id = pHash(e)
            if not d.__hl_hit[id] then
                e:TakeDamage(desiredDmg, DMG_FLAGS, EntityRef(player), 0)
                d.__hl_hit[id] = true
            end
        end
    end
end

function mod:OnCrackInit(eff)
    if eff.Variant ~= V_CRACK then return end
    local p, count = hlApplyMainPillar(eff)
    hlApplyAoePulse(eff, p, count)
end
mod:AddCallback(ModCallbacks.MC_POST_EFFECT_INIT, mod.OnCrackInit)

function mod:OnCrackUpdate(eff)
    if eff.Variant ~= V_CRACK then return end
    local p, count = hlApplyMainPillar(eff)
    hlApplyAoePulse(eff, p, count)
end
mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, mod.OnCrackUpdate)
