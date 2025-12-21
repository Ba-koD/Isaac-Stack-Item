local game = Game()

return function(mod, utils)
    -- Safe detection of EYESORE ID
    local EYESORE = CollectibleType.COLLECTIBLE_EYE_SORE or Isaac.GetItemIdByName("Eye Sore")
    if EYESORE == -1 or not EYESORE then EYESORE = 710 end
    
    -- Force debug print on load to verify script is running
    print("[Stackable Items] Eye Sore module loaded. ID: " .. tostring(EYESORE))

    local FIXED_PROC = 0.50 -- 50% chance per extra item stack

    -- Guard to prevent recursive procs
    local _inEyeSore = false

    -- Eye Sore proc logic
    local function TryProcEyeSore(player, pType, sourceEntity)
        if _inEyeSore then return end
        if not (player and player:Exists()) then return end

        local count = player:GetCollectibleNum(EYESORE)
        
        -- DEBUG: Verify script is active
        -- print("[Stackable Items] Eye Sore TryProc: " .. pType .. " | Items: " .. tostring(count))

        -- Stacking: We only add extra shots if count > 1
        if count <= 1 then return end

        local frame = game:GetFrameCount()
        local d     = player:GetData()
        
        -- Prevent multi-proc in the same frame for the same player
        d.__eyesore_last_fire_frame = d.__eyesore_last_fire_frame or -1
        if d.__eyesore_last_fire_frame == frame then 
            return 
        end
        
        -- Determine Weapon Type
        local wType = 1
        if player.GetWeaponType then
            wType = player:GetWeaponType()
        end

        -- Calculate extra shots based on stacks
        local rng = player:GetCollectibleRNG(EYESORE)
        local extraShots = 0
        for i = 1, count - 1 do
            extraShots = extraShots + 2 + rng:RandomInt(3)
        end

        d.__eyesore_last_fire_frame = frame
        _inEyeSore = true -- Start recursion guard

        local damage = player.Damage
        local flags  = player.TearFlags
        local pos    = player.Position
        local headOffset = Vector(0, -35)

        for _ = 1, extraShots do
            local angle = rng:RandomFloat() * 360.0
            local vel   = Vector.FromAngle(angle):Resized(player.ShotSpeed * 10)

            if pType == "laser" and sourceEntity then
                local laser   = sourceEntity:ToLaser()
                local variant = sourceEntity.Variant or (laser and laser.Variant) or 1
                local timeout = (laser and laser.Timeout > 0) and laser.Timeout or 20
                
                local l
                -- Precision detection: WeaponType.WEAPON_TECH_X (9) or LaserVariant.LASER_RING (2)
                if wType == 9 or variant == 2 or variant == LaserVariant.LASER_RING then
                    local radius = (laser and laser.Radius and laser.Radius > 0) and laser.Radius or 30
                    -- Documentation signature: FireTechXLaser(Pos, Velocity, Radius, Source, DamageMultiplier)
                    l = player:FireTechXLaser(pos, vel, radius, player, 1.0)
                    if l then
                        l:GetData().__is_moving_laser = true
                    end
                elseif wType == 3 or variant == 1 or variant == LaserVariant.THIN_RED then
                    -- Technology Laser: Use FireTechLaser
                    -- Signature: FireTechLaser(Pos, Angle, Timeout, Source, DamageMultiplier)
                    l = player:FireTechLaser(pos, angle, timeout, player, 1.0)
                else
                    -- Fallback for other lasers (Brimstone, etc.)
                    l = Isaac.Spawn(EntityType.ENTITY_LASER, variant, 0, pos, vel, player):ToLaser()
                    if l then
                        l.AngleDegrees = angle
                        l.Timeout = timeout
                    end
                end

                if l then
                    l.SpawnerEntity = player
                    l.Parent = player
                    l.CollisionDamage = (variant == LaserVariant.BRIMSTONE) and (damage * 0.5) or damage
                    l.TearFlags = l.TearFlags | flags
                    
                    local ld = l:GetData()
                    ld.__is_eyesore_extra = true
                    ld.__parent_laser = sourceEntity
                    ld.__eye_offset = headOffset
                    
                    -- Re-apply height and sync properties
                    l.PositionOffset = headOffset
                    if laser then
                        l.Color = laser.Color
                        l.OneHit = laser.OneHit
                    end
                end
            elseif pType == "bomb" and sourceEntity then
                local b = player:FireBomb(pos, vel)
                if b then
                    b.CollisionDamage = damage
                    local bd = b:GetData()
                    bd.__is_eyesore_extra = true
                    if sourceEntity and sourceEntity.ToBomb then
                        b.RadiusMultiplier = sourceEntity:ToBomb().RadiusMultiplier
                    end
                end
            elseif pType == "knife" and sourceEntity then
                local k = Isaac.Spawn(EntityType.ENTITY_KNIFE, 0, 0, pos, vel, player):ToKnife()
                if k then
                    k.CollisionDamage = damage * 2
                    local kd = k:GetData()
                    kd.__is_eyesore_extra = true
                    k.State = 1
                    k.Velocity = vel
                    k.Rotation = vel:GetAngleDegrees()
                end
            else
                local t = player:FireTear(pos, vel, false, false, false)
                if t then           
                    t.CollisionDamage = damage
                    t.TearFlags = t.TearFlags | flags
                end
            end
        end

        _inEyeSore = false -- End recursion guard
    end

    -- Tear Callback
    function mod:OnTear_EyeSore(tear)
        if _inEyeSore then return end
        local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
        if player then
            TryProcEyeSore(player, "tear", tear)
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, mod.OnTear_EyeSore)

    -- Laser Callback
    function mod:OnLaserUpdate_EyeSore(laser)
        local player = laser.SpawnerEntity and laser.SpawnerEntity:ToPlayer()
        if not player then return end

        local ld = laser:GetData()

        -- Trigger: New laser from player (only once per laser entity)
        if not ld.__eyesore_proced and not ld.__is_eyesore_extra and not _inEyeSore then
            ld.__eyesore_proced = true
            TryProcEyeSore(player, "laser", laser)
        end
        
        -- Sync: Keep extra lasers attached to player/parent
        if ld.__is_eyesore_extra then
            -- CRITICAL: Re-apply height offset EVERY frame
            local offset = ld.__eye_offset or Vector(0, -35)
            laser.PositionOffset = offset

            if ld.__parent_laser then
                if ld.__parent_laser:Exists() and not ld.__parent_laser:IsDead() then
                    laser.Timeout = math.max(laser.Timeout, ld.__parent_laser.Timeout)
                    
                    -- Non-moving lasers (Technology, Brimstone)
                    if laser.Variant ~= 2 and laser.Variant ~= LaserVariant.LASER_RING and not ld.__is_moving_laser then
                        laser.Position = player.Position
                    end
                else
                    if laser.Timeout > 2 then laser.Timeout = 2 end
                end
            end
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, mod.OnLaserUpdate_EyeSore)

    -- Bomb Callback (Dr. Fetus)
    function mod:OnBombInit_EyeSore(bomb)
        local player = bomb.SpawnerEntity and bomb.SpawnerEntity:ToPlayer()
        if not player then return end
        
        -- Safe weapon type check
        local pWeapon = 1
        if player.GetWeaponType then
            pWeapon = player:GetWeaponType()
        end

        -- Improved detection using IsFetus and WeaponType
        local isFetusBomb = bomb.IsFetus or (pWeapon == 5) -- 5 is WeaponType.WEAPON_BOMBS
        if not isFetusBomb then return end

        local bd = bomb:GetData()
        -- Use __eyesore_proced to ensure it only procs once per bomb
        if not bd.__eyesore_proced and not bd.__is_eyesore_extra and not _inEyeSore then
            bd.__eyesore_proced = true
            TryProcEyeSore(player, "bomb", bomb)
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_BOMB_INIT, mod.OnBombInit_EyeSore)

    -- Knife Callback (Mom's Knife)
    function mod:OnKnifeInit_EyeSore(knife)
        local player = knife.SpawnerEntity and knife.SpawnerEntity:ToPlayer()
        if not player then return end
        
        local pWeapon = 1
        if player.GetWeaponType then
            pWeapon = player:GetWeaponType()
        end

        -- Improved detection using WeaponType
        local isKnife = (knife.Variant == 0) or (pWeapon == 4) -- 4 is WeaponType.WEAPON_KNIFE
        if not isKnife then return end

        local kd = knife:GetData()
        -- Only proc for the main knife and use __eyesore_proced
        if not kd.__eyesore_proced and not kd.__is_eyesore_extra and not _inEyeSore then
            kd.__eyesore_proced = true
            TryProcEyeSore(player, "knife", knife)
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_KNIFE_INIT, mod.OnKnifeInit_EyeSore)
end
