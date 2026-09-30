--!strict
-- DustMan, the navi of the DustMan chips (actor object #0x18,
-- `sub_80BBF0C`), brought by their navi chip controller. He appears and
-- sucks up every field object he may (the field-object registry, all but
-- NameIDs 0xD3, 0xDA, 0xE9, 0xEA: the chip removes them), rolls a ball of
-- junk forward (objects/dust-ball), then throws each object he took back
-- at the enemy, 20 ticks apart (objects/dust-junk), and leaves. See
-- docs/engine/chips.md §3.6.26.
--
-- The chips' script (navi chip subtype 11): `navi_chip` is his spawner,
-- `off_802CD5C[11]`.

local dust_ball = require("../dust-ball/dust_ball")
local dust_junk = require("../dust-junk/dust_junk")

export type State = {
    -- The NameIDs of the objects he took (ExtraVars[0..7], words).
    taken: { number },
    -- The controller waiting for him (its pointer sits in his collision
    -- data slot).
    controller: Object?,
}

local dust_man = {
    state = { taken = "u32[8]", controller = "object" },
}

local SPRITE = "08-0A"

-- Panel flags he needs to stay (as one word).
local CAN_STAND = 0x10010

-- The field-object registry's slots (BattleState+0xA0, eight words).
local SLOTS = 8

-- NameIDs he leaves (`sub_800F486`).
local KEPT = { [0xD3] = true, [0xDA] = true, [0xE9] = true, [0xEA] = true }

-- `sub_80BC0DA`: DustMan for `user`, reporting to `controller`. (His Z
-- is the spawner's address the controller leaves in r3, of which his init
-- keeps the fraction.)
function dust_man.navi_chip(user: Object, controller: Object, spec: NaviChipSpec): Object?
    local o = battle.spawn_kind("dust-man", Vec3.new(spec.panel_y, spec.element, 0x080B_C0DB), spec.params)
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

-- `sub_80BBF30`: on his panel, on the ground (Z's whole part cleared).
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
    me:set_lifecycle("update")
end

-- Timer and Timer2 together (a word store).
local function set_timers(me: Object, ticks: number)
    me.timer = ticks
    me.timer2 = 0
end

-- `sub_80BBF94`: he appears; 10 ticks; on, or straight to leaving if his
-- panel can't hold him.
local function appear(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 3
        battle.play_sound(0x94)
        me.visible = true
        set_timers(me, 0xA)
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left > 0 then
        return
    end
    local stands = bit32.band(field.flags(me.panel_x, me.panel_y), CAN_STAND) == CAN_STAND
    me:set_action(if stands then 4 else 0x10)
end

-- `sub_80BC100`: take every field object he may (the chip removes it),
-- keeping its NameID; how many (into Param1).
local function suck_up(me: Object): number
    local s = me.state :: State
    local n = 0
    for slot = 0, SLOTS - 1 do
        local o = battle.field_object(slot)
        if o then
            local name_id = o.name_id
            if not KEPT[name_id] then
                s.taken[n + 1] = name_id
                n += 1
                battle.remove_obstacle(o)
            end
        end
    end
    return n
end

-- `sub_80BBFE8`: 20 ticks; with 10 left he sucks up the field's objects.
local function suck(me: Object)
    if me.phase == 0 then
        me.phase = 4
        set_timers(me, 0x14)
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left == 0xA then
        local n = suck_up(me)
        me:set_param(1, n)
        if n ~= 0 then
            battle.play_sound(0xAD)
        end
        return
    end
    if left <= 0 then
        me:set_action(8)
    end
end

-- `sub_80BC024`: 34 ticks of winding up (anim 0x11 at 9 left).
local function wind_up(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 0xF
        set_timers(me, 0x22)
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left == 9 then
        me.anim = 0x11
        return
    end
    if left <= 0 then
        me:set_action(0xC)
    end
end

-- `sub_80BC058`: the ball of junk (`sub_80BC13E`), then an object he took
-- every 20 ticks (`sub_80BC160`; Param2 counts), (Param1 + 1) · 20 ticks
-- in all.
local function throw(me: Object)
    local damage = bit32.bor(me.damage, bit32.lshift(me.stamina, 16))
    if me.phase == 0 then
        me.phase = 4
        dust_ball.spawn(me, me.panel_x, me.panel_y, me.element, damage, { 1 })
        battle.play_sound(0xFF)
        me:set_param(2, 0)
        me.timer = (me:param(1) + 1) * 0x14
        me.timer2 = 0x14
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left <= 0 then
        me:set_action(0x10)
        return
    end
    left = me.timer2 - 1
    me.timer2 = left
    if left > 0 then
        return
    end
    local n = me:param(2)
    local taken = (me.state :: State).taken
    if n >= #taken then
        error(string.format("DustMan throws object %d, past his ExtraVars", n))
    end
    -- r3, which nothing on the way sets, is the object loop's.
    dust_junk.spawn(me, me.panel_x, me.panel_y, me.element, damage, taken[n + 1], battle.loop_register())
    battle.play_sound(0xFF)
    me:set_param(2, n + 1)
    me.timer2 = 0x14
end

-- `sub_80BC0B0`: 4 ticks (to -1), then he goes and the controller moves
-- on.
local function leave(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 4
        set_timers(me, 4)
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left >= 0 then
        return
    end
    local controller = (me.state :: State).controller
    if controller then
        navi_chip.navi_left(controller)
    end
    me:set_lifecycle("destroy")
end

local ACTIONS = { [0] = appear, [4] = suck, [8] = wind_up, [0xC] = throw, [0x10] = leave }

-- `sub_80BBF0C`.
function dust_man.update(me: Object)
    local l = me.lifecycle
    if l == "init" then
        init(me)
    elseif l == "update" then
        local action = ACTIONS[me.action]
        if not action then
            error(string.format("DustMan action %#x reads past his table (off_80BBF80)", me.action))
        end
        action(me)
    else
        me:free()
    end
    me:update_sprite_while_dimmed()
end

return dust_man
