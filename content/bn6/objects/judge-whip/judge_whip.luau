--!strict
-- JudgeMan's whip (effect object #0x5A, `sub_80E70C8`): his sprite's
-- animation 8 on him, following his position, then animation 9 after 15
-- ticks. JudgeMan's (Param1 1) runs until he takes it off; with Param1 0
-- it goes once its owner leaves action 0xA, and waits out a dimming.
-- Purely visual, but it holds an effect slot. See docs/engine/chips.md
-- §3.6.29.

local judge_whip = {}

local SPRITE = "08-0F"

-- `sub_80E71A0`: a whip on `owner`, with `params` {Param1}.
function judge_whip.spawn(owner: Object, params: { number }): Object?
    local o = battle.spawn_kind("judge-whip", Vec3.zero, params)
    if o then
        o.related1 = owner
        o.alliance, o.flip = owner.alliance, owner.flip
    end
    return o
end

-- `sub_80E71B8`: take the whip off (at its next update).
function judge_whip.take_off(o: Object?)
    if o then
        o:set_lifecycle("destroy")
    end
end

-- `sub_80E70F8`: on its owner.
local function init(me: Object)
    me.pos = (me.related1 :: Object).pos
    local sprite = me.sprite
    sprite:load(SPRITE)
    sprite.shadow = "with_sprite"
    me.visible = true
    me.anim = 8
    me.anim_loaded = 8
    sprite:set_animation(8)
    sprite.palette = 0
    sprite:set_flip(bit32.bxor(me.alliance, me.flip))
    me:set_lifecycle("update")
end

-- `sub_80E717A`: 15 ticks, then animation 9 (action 8 holds).
local function swing(me: Object)
    local a = me.action
    if a == 8 then
        return
    end
    if a ~= 4 then
        me.action = 4
        me.timer = 0xF
    end
    local left = me.timer - 1
    me.timer = left
    if left > 0 then
        return
    end
    me.anim = 9
    me.action = 8
end

-- `sub_80E7142`: follow the owner; with Param1 0, go once he leaves
-- action 0xA, and wait out a dimming.
local function tick(me: Object)
    if battle.over() then
        me:set_lifecycle("destroy")
        return
    end
    local owner = me.related1 :: Object
    me.pos = owner.pos
    if me:param(1) == 0 then
        if owner.action ~= 0xA then
            me:set_lifecycle("destroy")
            return
        end
        if battle.dimmed() then
            return
        end
    end
    swing(me)
end

-- `sub_80E70C8`.
function judge_whip.update(me: Object)
    local l = me.lifecycle
    if l == "init" then
        init(me)
    elseif l == "update" then
        tick(me)
    else
        me:free()
    end
    if me:param(1) == 0 then
        me:update_sprite_while_paused()
    else
        me:update_sprite_while_dimmed()
    end
end

return judge_whip
