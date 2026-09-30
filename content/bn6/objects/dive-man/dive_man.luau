--!strict
-- DiveMan, the navi of the DiveMan chips (actor object #0xB,
-- `sub_80B99C0`), brought by their navi chip controller. He surfaces,
-- dives (the field shakes), and raises a wave in each row at the front of
-- his side (objects/dive-wave) that washes toward the enemy; then he
-- leaves. See docs/engine/chips.md §3.6.27.
--
-- The chips' script (navi chip subtype 13): `navi_chip` is his spawner,
-- `off_802CD5C[13]`.

local dive_wave = require("../dive-wave/dive_wave")

export type State = {
    -- The controller waiting for him (its pointer sits in his collision
    -- data slot).
    controller: Object?,
}

local dive_man = {
    state = { controller = "object" },
}

local SPRITE = "08-0D"

-- His actor record (the parts it adds: his overlay, `sub_8010F96`).
local ACTOR_TYPE: ActorType = "player"
local AI_INDEX = 0xD

-- Where a wave rises in a row, by side: the panel nearest the front that
-- matches (`byte_80B9BF0`, {require, forbid}: flag 0x20 is the panel's
-- side), if it passes `byte_80B9C04` (solid, nothing's body on it).
local FRONT = { [0] = { 0, 0x20 }, { 0x20, 0 } }
local OPEN = { 0x10, 0x0380_0000 }

-- `sub_80B9B6E`: DiveMan for `user`, reporting to `controller`. (His Z is
-- the spawner's address the controller leaves in r3, of which his init
-- keeps the fraction.)
function dive_man.navi_chip(user: Object, controller: Object, spec: NaviChipSpec): Object?
    local o = battle.spawn_kind("dive-man", Vec3.new(spec.panel_y, spec.element, 0x080B_9B6F), spec.params)
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

-- `sub_80B99E4`: on his panel, on the ground (Z's whole part cleared),
-- with his parts.
local function init(me: Object)
    me:set_coordinates_from_panel()
    local p = me.pos
    me.pos = Vec3.new(p.x, p.y, bit32.band(p.z, 0xFFFF))
    local sprite = me.sprite
    sprite:load(SPRITE)
    sprite.shadow = "ground"
    me.anim = 0
    me.anim_loaded = 0
    sprite:set_animation(0)
    sprite.palette = 0
    sprite:set_flip(bit32.bxor(me.alliance, me.flip))
    me:add_navi_parts(ACTOR_TYPE, AI_INDEX, 1)
    me:set_lifecycle("update")
end

-- Enter the phase with an animation and a timer, or count it down; true
-- once it is 0 or below.
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

-- `sub_80B9A60`: he surfaces (sound 0xE1); 19 ticks. (Timer2 cleared.)
local function surface(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 7
        battle.play_sound(0xE1)
        me.visible = true
        me.timer = 0x13
        me.timer2 = 0
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left <= 0 then
        me:set_action(4)
    end
end

-- `sub_80B9A96`: 30 ticks. (Timer2 cleared.)
local function wait(me: Object)
    if me.phase == 0 then
        me.timer2 = 0
    end
    if countdown(me, nil, 0x1E) then
        me:set_action(8)
    end
end

-- `sub_80B9ABA`: he dives; 30 ticks. (The camera shakes: presentation
-- only.)
local function dive(me: Object)
    if countdown(me, 4, 0x1E) then
        me:set_action(0xC)
    end
end

-- `sub_80B9B94`: a wave in each row at the front of his side.
local function waves(me: Object)
    local damage = bit32.bor(me.damage, bit32.lshift(me.stamina, 16))
    local front = FRONT[me.alliance]
    -- object_getClosestPanelMatchingRowFiltered: from his side's far edge
    -- toward the enemy's.
    local start, step = 6 - 5 * me.alliance, 2 * me.alliance - 1
    for row = 1, 3 do
        local x = start
        while not field.check(x, row, front[1], front[2]) do
            x += step
            if not field.valid(x, row) then
                x = 0
                break
            end
        end
        if x ~= 0 and field.check(x, row, OPEN[1], OPEN[2]) then
            -- r3, left by the check (`_object_getPanelDataOffset`), is the
            -- row minus 1: the wave's Z.
            dive_wave.spawn(me, x, row, me.element, { 4 }, damage, row - 1)
        end
    end
end

-- `sub_80B9AEA`: the waves; 60 ticks (standing again at 20 left). (The
-- camera shakes at 30 left: presentation only.)
local function attack(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 5
        waves(me)
        me.timer = 0x3C
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left == 0x1E then
        return
    end
    if left == 0x14 then
        me.anim = 0
        return
    end
    if left <= 0 then
        me:set_action(0x10)
    end
end

-- `sub_80B9B30`: 14 ticks.
local function wind_down(me: Object)
    if countdown(me, 8, 0xE) then
        me:set_action(0x14)
    end
end

-- `sub_80B9B58`: he goes (his parts with him) and the controller moves on.
local function leave(me: Object)
    me:remove_navi_parts(ACTOR_TYPE, AI_INDEX)
    local controller = (me.state :: State).controller
    if controller then
        navi_chip.navi_left(controller)
    end
    me:set_lifecycle("destroy")
end

local ACTIONS = { [0] = surface, [4] = wait, [8] = dive, [0xC] = attack, [0x10] = wind_down, [0x14] = leave }

-- `sub_80B99C0`.
function dive_man.update(me: Object)
    local l = me.lifecycle
    if l == "init" then
        init(me)
    elseif l == "update" then
        local action = ACTIONS[me.action]
        if not action then
            error(string.format("DiveMan action %#x reads past his table (off_80B9A48)", me.action))
        end
        action(me)
    else
        me:free()
    end
    me:update_sprite_while_dimmed()
end

return dive_man
