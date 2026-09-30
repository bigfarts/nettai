--!strict
-- DiveMan's wave (attack object #0x39, `sub_80CB0DC`): a wave rising on its
-- panel (DiveMan's sprite, animation 0x14) that washes toward the enemy:
-- a hit region there for 32 ticks, on the next two panels for 13 ticks
-- from 19 in, splashes at 25 and 32 in (effect 0x2B), then it's gone.
-- Param1 4 (DiveMan's): it acts and steps its sprite while dimmed. See
-- docs/engine/chips.md §3.6.27.

local dive_wave = {}

local SPRITE = "08-0D"
local ANIM = 0x14

-- The hit (`sub_80CB208`'s): region 1, hit spark 2, target 5, self 0xA,
-- modifier 3; it runs while dimmed.
local function hit(me: Object, ahead: number, ticks: number)
    local x, y = me.panel_x + (1 - 2 * me.alliance) * ahead, me.panel_y
    if not field.valid(x, y) then
        return
    end
    local box = battle.hitbox(me, {
        panel_x = x,
        panel_y = y,
        element = me.element,
        z = 0,
        region = 1,
        hit_effect = 2,
        target = 5,
        self_type = 0x0A,
        damage = me.damage,
        stamina = me.stamina,
        hit_mod = 3,
    })
    if box then
        box.run_while_dimmed = true
        box.timer = ticks
    end
end

-- `sub_80CB248`: a splash (effect 0x2B) on the panel `ahead` toward the
-- enemy.
local function splash(me: Object, ahead: number)
    local x, y = me.panel_x + (1 - 2 * me.alliance) * ahead, me.panel_y
    if not field.valid(x, y) then
        return
    end
    local cx, cy = field.center(x, y)
    battle.effect(Vec3.new(cx, cy, 0), 0x2B, bit32.bxor(me.alliance, me.flip))
end

-- `sub_80CB1E2`: a wave on (x, y) with `element`, `params` and the damage
-- word. `z` is the spawner's register that becomes its Z, of which the
-- init keeps the fraction.
function dive_wave.spawn(
    owner: Object,
    x: number,
    y: number,
    element: number,
    params: { number },
    damage: number,
    z: number
): Object?
    local o = battle.spawn_kind("dive-wave", Vec3.new(y, element, z), params)
    if o then
        o.panel_x, o.panel_y = x, y
        o.element = element
        o.damage = damage
        o.stamina = bit32.rshift(damage, 16)
        o.alliance, o.flip = owner.alliance, owner.flip
        o.run_while_dimmed = true
    end
    return o
end

-- `sub_80CB10C`: on its panel, on the ground (Z's whole part cleared).
local function init(me: Object)
    me:set_coordinates_from_panel()
    local p = me.pos
    me.pos = Vec3.new(p.x, p.y, bit32.band(p.z, 0xFFFF))
    local sprite = me.sprite
    sprite:load(SPRITE)
    sprite.shadow = "with_sprite"
    me.visible = true
    me.anim = ANIM
    me.anim_loaded = ANIM
    sprite:set_animation(ANIM)
    sprite.palette = 0
    sprite:set_flip(bit32.bxor(me.alliance, me.flip))
    battle.play_sound(0xA7)
    me:set_lifecycle("update")
end

-- `sub_80CB184`.
local function wash(me: Object)
    if me.phase == 0 then
        me.phase = 4
        hit(me, 0, 0x20)
        me.timer = 0x20
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left == 0xD then
        hit(me, 1, 0xD)
        hit(me, 2, 0xD)
    elseif left == 7 then
        splash(me, 2)
    elseif left <= 0 then
        splash(me, 1)
        me:set_lifecycle("destroy")
        me.timer2 = 0
    end
end

-- `sub_80CB154`: gone once the battle is over; outside a dimming unless
-- Param1 is 4.
local function tick(me: Object)
    if battle.over() then
        me:set_lifecycle("destroy")
        return
    end
    if me:param(1) ~= 4 and battle.dimmed() then
        return
    end
    if me.action ~= 0 then
        error(string.format("DiveMan's wave action %#x reads past its table (off_80CB180)", me.action))
    end
    wash(me)
end

-- `sub_80CB0DC`.
function dive_wave.update(me: Object)
    local l = me.lifecycle
    if l == "init" then
        init(me)
    elseif l == "update" then
        tick(me)
    else
        me:destroy()
    end
    if me:param(1) == 4 then
        me:update_sprite_while_dimmed()
    else
        me:update_sprite_while_paused()
    end
end

return dive_wave
