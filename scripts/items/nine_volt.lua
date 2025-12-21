local game = Game()

return function(mod, utils)
    -- Ensure NINE_VOLT is correctly defined (9 Volt ID: 116)
    local NINE_VOLT = Isaac.GetItemIdByName("9 Volt")
    if NINE_VOLT == -1 or not NINE_VOLT then NINE_VOLT = 116 end

    -- Queue for pending charges to be applied on the next frame
    mod.nineVoltPending = mod.nineVoltPending or {}

    function mod:OnUseItem_NineVolt(itemID, rng, player, flags, slot, varData)
        if not player then return end

        local c = player:GetCollectibleNum(NINE_VOLT)
        if c <= 1 then return end

        -- Use the slot provided by the callback, default to PRIMARY
        local s = slot or ActiveSlot.SLOT_PRIMARY

        -- Guard: Prevent multiple registrations in the same frame for the same player
        local d = player:GetData()
        local f = game:GetFrameCount()
        d.__ninevolt_last_frame = d.__ninevolt_last_frame or -999
        if d.__ninevolt_last_frame == f then
            return
        end
        d.__ninevolt_last_frame = f

        -- Add +1 charge per extra stack (Engine already gives the first +1)
        table.insert(mod.nineVoltPending, {
            player = player,
            slot   = s,
            add    = (c - 1),
            frame  = f + 1, -- Apply on the next frame after engine processing
        })
    end
    mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.OnUseItem_NineVolt)

    function mod:OnUpdate_NineVolt()
        if not mod.nineVoltPending or #mod.nineVoltPending == 0 then return end

        local frame = game:GetFrameCount()
        for i = #mod.nineVoltPending, 1, -1 do
            local info = mod.nineVoltPending[i]
            local p = info.player
            if (not p) or (not p:Exists()) then
                table.remove(mod.nineVoltPending, i)
            else
                if frame >= (info.frame or frame) then
                    utils.AddActiveChargeCompat(p, info.add or 0, info.slot)
                    table.remove(mod.nineVoltPending, i)
                end
            end
        end
    end
    mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnUpdate_NineVolt)
end
