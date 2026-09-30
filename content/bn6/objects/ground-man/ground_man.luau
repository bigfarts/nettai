--!strict
-- GroundMan, the navi of the GrndMan chips (actor object #0x17,
-- `sub_80BBB98`), brought by their navi chip controller. He appears,
-- backs off a little, then drills forward along his row to the far column
-- (objects/ground-drill on him), hitting each panel he enters; if he gets
-- there, the field shakes and rocks fall on the enemy (objects/
-- falling-rock) for 150 ticks, one every 25; blocked on the way (a panel
-- that isn't solid, or the other side's body or an object on it), he
-- leaves at once. See docs/engine/chips.md §3.6.25.
--
-- The chips' script (navi chip subtype 10): `navi_chip` is his spawner,
-- `off_802CD5C[10]`.

local panels = require("../../lib/panels")
local ground_drill = require("../ground-drill/ground_drill")
local falling_rock = require("../falling-rock/falling_rock")

export type State = {
    -- His drill (ExtraVars[0]).
    drill: Object?,
    -- The last rock's panel (ExtraVars[1] and [2]).
    rock_x: number,
    rock_y: number,
    -- The controller waiting for him (its pointer sits in his collision
    -- data slot).
    controller: Object?,
}

local ground_man = {
    state = { drill = "object", rock_x = "u32", rock_y = "u32", controller = "object" },
}

local SPRITE = "08-09"

-- His actor record (the parts it adds: his overlay, `sub_8010F86`).
local ACTOR_TYPE: ActorType = "player"
local AI_INDEX = 9

-- Panel flags he needs to stay (as one word).
local CAN_STAND = 0x10010

-- How fast he backs off and drills (16.16).
local BACK_SPEED, DRILL_SPEED = 0x8000, 0x8_0000

-- A panel his drill goes on through, by side (`byte_80BBD50`: solid, and
-- no body or object of the other side's, or neutral).
local DRILLABLE = { [0] = { 0x10, 0x0580_0000 }, { 0x10, 0x0A80_0000 } }

-- Where rocks fall, by side: first choice (`off_80BBEE0`) and second
-- (`byte_80BBEF4`), {require, forbid}.
local ROCK_TARGETS = { [0] = { 0x0400_0020, 0 }, { 0x0800_0000, 0x20 } }
local ROCK_FALLBACK = { [0] = { 0x20, 0 }, { 0, 0x20 } }

-- `sub_80BBDE8`: GroundMan for `user`, reporting to `controller`. (His Z
-- is the spawner's address the controller leaves in r3; his init clears
-- it.)
function ground_man.navi_chip(user: Object, controller: Object, spec: NaviChipSpec): Object?
    local o = battle.spawn_kind("ground-man", Vec3.new(spec.panel_y, spec.element, 0x080B_BDE9), spec.params)
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

-- `sub_80BBBBC`: on his panel, on the ground, with his parts.
local function init(me: Object)
    me:set_coordinates_from_panel()
    local p = me.pos
    me.pos = Vec3.new(p.x, p.y, 0)
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

-- Timer and Timer2 together (a word store).
local function set_timers(me: Object, ticks: number)
    me.timer = ticks
    me.timer2 = 0
end

-- `sub_80BBC2C`: he appears; 9 ticks; on, or straight to leaving if his
-- panel can't hold him.
local function appear(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 3
        battle.play_sound(0x94)
        me.visible = true
        set_timers(me, 9)
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

-- `sub_80BBC80`: 40 ticks; half a pixel back a tick from 25 left to 10;
-- the drill comes out at 25 left.
local function back_off(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 0
        me.vel = Vec3.new(-me.facing * BACK_SPEED, me.vel.y, me.vel.z)
        set_timers(me, 0x28)
        return
    end
    local t = me.timer
    if t <= 0x19 and t >= 0xA then
        local p = me.pos
        me.pos = Vec3.new(p.x + me.vel.x, p.y, p.z)
    end
    local left = t - 1
    me.timer = left
    if left == 0x19 then
        me.anim = 0x11
        battle.play_sound(0xE6)
        return
    end
    if left <= 0 then
        me:set_action(8)
    end
end

-- `sub_80BBE3A`: the hit on the panel he enters (a hitbox that runs
-- while dimmed).
local function hit(me: Object)
    local box = battle.hitbox(me, {
        panel_x = me.panel_x,
        panel_y = me.panel_y,
        element = me.element,
        z = 0,
        region = 1,
        hit_effect = 0x0A,
        target = 5,
        self_type = 0x15,
        damage = me.damage,
        stamina = me.stamina,
        hit_mod = 3,
    })
    if box then
        box.run_while_dimmed = true
    end
end

-- `sub_80BBCD8`: drill forward to the far column (`sub_80BBE0E`: 8 pixels
-- a tick, 5 ticks a column), hitting each panel he enters; at the end,
-- the rocks; blocked, he leaves.
local function drill(me: Object)
    local s = me.state :: State
    if me.phase == 0 then
        me.phase = 4
        me.anim = 0x12
        me.vel = Vec3.new(me.facing * DRILL_SPEED, me.vel.y, me.vel.z)
        local far = if me.alliance == 0 then 6 else 1
        me.timer = int.tdiv(math.abs(far - me.panel_x) * 0x28_0000, DRILL_SPEED)
        battle.play_sound(0x1C0)
        s.drill = ground_drill.spawn(me, { 1 })
        return
    end
    local old = me.panel_x
    local p = me.pos
    me.pos = Vec3.new(p.x + me.vel.x, p.y, p.z)
    me:set_panel_from_coordinates()
    if me.panel_x ~= old then
        hit(me)
    end
    local ok = DRILLABLE[me.alliance]
    if not field.check(me.panel_x, me.panel_y, ok[1], ok[2]) then
        me:set_action(0x10)
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left <= 0 then
        me:set_action(0xC)
    end
end

-- `sub_80BBE58`: a rock on an enemy panel other than the last rock's (at
-- random; the second choice if there is none), 10 ticks' warning.
local function drop_rock(me: Object)
    local s = me.state :: State
    -- He stands on the last rock's panel while he looks (so it is left
    -- out).
    local x, y = me.panel_x, me.panel_y
    me.panel_x, me.panel_y = s.rock_x, s.rock_y
    local want = ROCK_TARGETS[me.alliance]
    local found = panels.except(me, want[1], want[2])
    if #found == 0 then
        want = ROCK_FALLBACK[me.alliance]
        found = panels.except(me, want[1], want[2])
    end
    if #found > 0 then
        local i = int.tmod(battle.rng_positive(), #found)
        local rx, ry = panels.unpack(found[i + 1])
        s.rock_x, s.rock_y = rx, ry
        local damage = bit32.bor(me.damage, bit32.lshift(me.stamina, 16))
        falling_rock.spawn(me, rx, ry, me.element, { 0x0A, 1, 1, 0 }, damage, 0)
    end
    me.panel_x, me.panel_y = x, y
end

-- `sub_80BBD60`: 150 ticks of falling rocks, one every 25 from the
-- first. (The camera shakes: presentation only.)
local function rocks(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.timer = 0x96
        me.timer2 = 0
        local s = me.state :: State
        s.rock_x, s.rock_y = 0, 0
        battle.play_sound(0xE5)
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
    drop_rock(me)
    me.timer2 = 0x19
end

-- `sub_80BBDAC`: the drill goes; 4 ticks (to -1), then he goes (his parts
-- with him) and the controller moves on.
local function leave(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 4
        set_timers(me, 4)
        ground_drill.take_off((me.state :: State).drill)
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left >= 0 then
        return
    end
    me:remove_navi_parts(ACTOR_TYPE, AI_INDEX)
    local controller = (me.state :: State).controller
    if controller then
        navi_chip.navi_left(controller)
    end
    me:set_lifecycle("destroy")
end

local ACTIONS = { [0] = appear, [4] = back_off, [8] = drill, [0xC] = rocks, [0x10] = leave }

-- `sub_80BBB98`.
function ground_man.update(me: Object)
    local l = me.lifecycle
    if l == "init" then
        init(me)
    elseif l == "update" then
        local action = ACTIONS[me.action]
        if not action then
            error(string.format("GroundMan action %#x reads past his table (off_80BBC18)", me.action))
        end
        action(me)
    else
        me:free()
    end
    me:update_sprite_while_dimmed()
end

return ground_man
