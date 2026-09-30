--!strict
-- CircusMan, the navi of the CrcusMan chips (actor object #0xE,
-- `sub_80BA364`), brought by their navi chip controller. He appears,
-- leaps three panels forward and drops from above; if an enemy is there,
-- he catches it and squeezes it (a hit on his panel every 12 ticks for 72
-- ticks, with sparkles); then he leaps away and leaves. See
-- docs/engine/chips.md §3.6.28.
--
-- The chips' script (navi chip subtype 14): `navi_chip` is his spawner,
-- `off_802CD5C[14]`.

export type State = {
    -- His second overlay (ExtraVars[0], `sub_8010FD8`'s).
    extra: Object?,
    -- The controller waiting for him (its pointer sits in his collision
    -- data slot).
    controller: Object?,
}

local circus_man = {
    state = { extra = "object", controller = "object" },
}

local SPRITE = "08-0E"

-- His actor record (the parts it adds: two overlays, `sub_8010FD8`).
local ACTOR_TYPE: ActorType = "player"
local AI_INDEX = 0xE

-- Panel flags he needs to stay (as one word).
local CAN_STAND = 0x10010

-- What he lands on to catch, by side (`off_80BA520`: an enemy navi's
-- body).
local ENEMY = { [0] = 0x0400_0000, 0x0800_0000 }

-- `sub_80BA660`: CircusMan for `user`, reporting to `controller`. (His Z
-- is the spawner's address the controller leaves in r3, of which his init
-- keeps the fraction.)
function circus_man.navi_chip(user: Object, controller: Object, spec: NaviChipSpec): Object?
    local o = battle.spawn_kind("circus-man", Vec3.new(spec.panel_y, spec.element, 0x080B_A661), spec.params)
    if not o then
        return nil
    end
    o.panel_x, o.panel_y = spec.panel_x, spec.panel_y
    o.element = spec.element
    o.related1 = user
    o.alliance, o.flip = user.alliance, user.flip
    o.damage = spec.damage
    o.stamina = bit32.rshift(spec.damage, 16)
    local s = o.state :: State
    s.controller = controller
    return o
end

-- Add `d` to Z's whole part (a halfword store: the fraction stays).
local function add_height(me: Object, d: number)
    local p = me.pos
    local whole = bit32.band(bit32.rshift(p.z, 16) + d, 0xFFFF)
    me.pos = Vec3.new(p.x, p.y, bit32.bor(bit32.lshift(whole, 16), bit32.band(p.z, 0xFFFF)))
end

-- `sub_80BA388`: on his panel, on the ground (Z's whole part cleared),
-- with his parts (the second kept in his state).
local function init(me: Object)
    me:set_coordinates_from_panel()
    local p = me.pos
    me.pos = Vec3.new(p.x, p.y, bit32.band(p.z, 0xFFFF))
    local sprite = me.sprite
    sprite:load(SPRITE)
    sprite.shadow = "with_sprite"
    me.anim = 0
    me.anim_loaded = 0
    sprite:set_animation(0)
    sprite.palette = 0
    sprite:set_flip(bit32.bxor(me.alliance, me.flip))
    local s = me.state :: State
    s.extra = me:add_navi_parts(ACTOR_TYPE, AI_INDEX, 1)
    me:set_lifecycle("update")
end

-- Enter the phase with an animation and a timer (a halfword store), or
-- count it down; true once it is 0 or below.
local function countdown(me: Object, anim: number?, ticks: number): boolean
    if me.phase == 0 then
        me.phase = 4
        if anim then
            me.anim = anim
        end
        me.timer = ticks
        return false
    end
    local left = me.timer - 1
    me.timer = left
    return left <= 0
end

-- `sub_80BA414`: he appears; 10 ticks; on, or straight to leaving if his
-- panel can't hold him. (Timer2 cleared.)
local function appear(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 0x13
        battle.play_sound(0x94)
        me.visible = true
        me.timer = 0xA
        me.timer2 = 0
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left > 0 then
        return
    end
    local stands = bit32.band(field.flags(me.panel_x, me.panel_y), CAN_STAND) == CAN_STAND
    me:set_action(if stands then 4 else 0x24)
end

-- `sub_80BA468`: 30 ticks standing. (Timer2 cleared.)
local function stand(me: Object)
    if me.phase == 0 then
        me.timer2 = 0
    end
    if countdown(me, 0, 0x1E) then
        me:set_action(8)
    end
end

-- `sub_80BA490`: 19 ticks crouching.
local function crouch(me: Object)
    if countdown(me, 0xD, 0x13) then
        me:set_action(0xC)
    end
end

-- `sub_80BA4BA`: three panels forward, from 30 pixels up, falling 6 a
-- tick for 5 ticks; an enemy there, he catches it, else he leaves.
local function drop(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.panel_x = me.panel_x + me.facing * 3
        me:set_coordinates_from_panel()
        local p = me.pos
        me.pos = Vec3.new(p.x, p.y, bit32.bor(bit32.lshift(0x1E, 16), bit32.band(p.z, 0xFFFF)))
        me.anim = 0xE
        me.timer = 5
        me.timer2 = 0
        return
    end
    add_height(me, -6)
    local left = me.timer - 1
    me.timer = left
    if left > 0 then
        return
    end
    if bit32.btest(field.flags(me.panel_x, me.panel_y), ENEMY[me.alliance]) then
        me:set_action(0x10)
    else
        me:set_action(0x1C)
    end
end

-- `sub_80BA528`: the catch (a pixel lower and higher, `sub_80BA6A4`);
-- 46 ticks.
local function catch(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 0xF
        local p = me.pos
        local y = bit32.bor(bit32.lshift(bit32.band(bit32.rshift(p.y, 16) + 1, 0xFFFF), 16), bit32.band(p.y, 0xFFFF))
        me.pos = Vec3.new(p.x, y, p.z)
        add_height(me, 1)
        battle.play_sound(0x1AA)
        me.timer = 0x2E
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left == 0x15 then
        battle.play_sound(0x114)
        return
    end
    if left <= 0 then
        me:set_action(0x14)
    end
end

-- `sub_80BA686`: the squeeze's hit on his panel (a hitbox that runs while
-- dimmed).
local function hit(me: Object)
    local box = battle.hitbox(me, {
        panel_x = me.panel_x,
        panel_y = me.panel_y,
        element = me.element,
        z = 0,
        region = 1,
        hit_effect = 0xFF,
        target = 5,
        self_type = 0x16,
        damage = me.damage,
        stamina = me.stamina,
        hit_mod = 3,
    })
    if box then
        box.run_while_dimmed = true
    end
end

-- `sub_80BA6B6`: a sparkle (effect 0x21) near his panel, up to 31 pixels
-- either way and 15 up or down (two RNG draws).
local function sparkle(me: Object)
    local cx, cy = field.center(me.panel_x, me.panel_y)
    local r = battle.rng_positive()
    local dx = bit32.lshift(bit32.band(r, 0x1F), 16)
    if not bit32.btest(r, 1) then
        dx = -dx
    end
    r = battle.rng_positive()
    local dz = bit32.lshift(bit32.band(r, 0xF), 16)
    if not bit32.btest(r, 1) then
        dz = -dz
    end
    battle.effect(Vec3.new(cx + dx, cy + 0x10_0000, 0x14_0000 + dz + 0x10_0000), 0x21)
end

-- `sub_80BA56C`: 72 ticks squeezing: a hit and a sparkle every 12 ticks
-- from the first.
local function squeeze(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 0x10
        me.timer = 0x48
        me.timer2 = 0
    end
    local left = me.timer2 - 1
    me.timer2 = left
    if left <= 0 then
        hit(me)
        me.timer2 = 0xC
        sparkle(me)
    end
    left = me.timer - 1
    me.timer = left
    if left <= 0 then
        me:set_action(0x18)
    end
end

-- `sub_80BA5AA`: 7 ticks letting go.
local function let_go(me: Object)
    if countdown(me, 0x11, 7) then
        me:set_action(0x20)
    end
end

-- `sub_80BA5D2`: 20 ticks (nobody to catch).
local function missed(me: Object)
    if countdown(me, nil, 0x14) then
        me:set_action(0x20)
    end
end

-- He goes (his parts with him) and the controller moves on.
local function go(me: Object)
    local s = me.state :: State
    me:remove_navi_parts(ACTOR_TYPE, AI_INDEX, s.extra)
    s.extra = nil
    local controller = s.controller
    if controller then
        navi_chip.navi_left(controller)
    end
    me:set_lifecycle("destroy")
end

-- `sub_80BA5F6`: he leaps off, 6 pixels up a tick for 5 ticks, and goes.
local function leap_off(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 0x12
        me.timer = 5
        return
    end
    add_height(me, 6)
    local left = me.timer - 1
    me.timer = left
    if left <= 0 then
        go(me)
    end
end

-- `sub_80BA62E`: 19 ticks, and he goes (his panel couldn't hold him).
local function leave(me: Object)
    if countdown(me, 0xD, 0x13) then
        go(me)
    end
end

local ACTIONS = {
    [0] = appear,
    [4] = stand,
    [8] = crouch,
    [0xC] = drop,
    [0x10] = catch,
    [0x14] = squeeze,
    [0x18] = let_go,
    [0x1C] = missed,
    [0x20] = leap_off,
    [0x24] = leave,
}

-- `sub_80BA364`.
function circus_man.update(me: Object)
    local l = me.lifecycle
    if l == "init" then
        init(me)
    elseif l == "update" then
        local action = ACTIONS[me.action]
        if not action then
            error(string.format("CircusMan action %#x reads past his table (off_80BA3EC)", me.action))
        end
        action(me)
    else
        me:free()
    end
    me:update_sprite_while_dimmed()
end

return circus_man
