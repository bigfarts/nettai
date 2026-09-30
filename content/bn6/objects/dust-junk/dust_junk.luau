--!strict
-- DustMan's junk (attack object #0xB3, `sub_80DBB40`): a field object he
-- sucked up, thrown back: it shows as the object did (by its NameID,
-- `data.objects.name_looks`, as `sub_800F26C` gives it; one with no look
-- isn't thrown), flies forward from in front of his panel, 6 pixels a
-- tick, to the far edge, hitting (collision self 6, target 5, modifier
-- 3, hit spark 0xA) until it hits something. It acts while dimmed. See
-- docs/engine/chips.md §3.6.26.

export type State = {
    -- The NameID of the object it was (ExtraVars[0]).
    name_id: number,
}

local dust_junk = {
    state = { name_id = "u32" },
}

-- How far in front of its panel's center it starts, and how fast it
-- flies (16.16); its height, in whole pixels.
local AHEAD, SPEED, HEIGHT = 0x12_0000, 0x6_0000, 0x10

-- `sub_80DBC90`: junk that was `name_id`, thrown by `owner` from (x, y)
-- with `element` and the damage word. `z` is the spawner's register that
-- becomes its Z, of which the init keeps the fraction (DustMan's: the
-- object loop's, `battle.loop_register`).
function dust_junk.spawn(
    owner: Object,
    x: number,
    y: number,
    element: number,
    damage: number,
    name_id: number,
    z: number
): Object?
    local o = battle.spawn_kind("dust-junk", Vec3.new(y, element, z), { 0, 0, 0, 0 })
    if o then
        o.panel_x, o.panel_y = x, y
        o.element = element
        o.related1 = owner
        o.damage = damage
        o.stamina = bit32.rshift(damage, 16)
        local s = o.state :: State
        s.name_id = name_id
        o.alliance, o.flip = owner.alliance, owner.flip
        o.run_while_dimmed = true
    end
    return o
end

-- `sub_800F26C`: the look of NameID `name_id` (nil: none).
local function look(name_id: number): NameLook?
    if name_id - 0xCD > 0x32 or name_id < 0xCD then
        -- enemy_getStruct1: an actor's sprite (a virus's, a navi's); no
        -- field object has such a NameID, and the pack doesn't have it.
        error(string.format("DustMan's junk: NameID %#x has no look in the pack (enemy_getStruct1)", name_id))
    end
    local l = data.objects.name_looks[name_id]
    if not l or not l.sprite then
        return nil
    end
    return l
end

-- `sub_80DBB64`: the object's look, in front of its panel, collision on;
-- gone at once if it has none (or collision can't be had).
local function init(me: Object)
    local s = me.state :: State
    local l = look(s.name_id)
    if not l then
        me:free()
        return
    end
    local sprite = me.sprite
    sprite:load(l.sprite :: SpriteId)
    me.visible = true
    sprite.shadow = if l.shadow then "ground" else "with_sprite"
    me.anim = l.anim
    me.anim_loaded = l.anim
    sprite:set_animation(l.anim)
    sprite.palette = l.palette
    if s.name_id == 0xD8 or s.name_id == 0xD9 then
        -- sub_8002EAC: a sprite attribute bit (presentation, which the
        -- engine's look doesn't keep); the flip is left alone.
    else
        sprite:set_flip(me.alliance)
    end
    me:set_coordinates_from_panel()
    local p = me.pos
    me.pos = Vec3.new(p.x + me.facing * AHEAD, p.y, bit32.bor(bit32.lshift(HEIGHT, 16), bit32.band(p.z, 0xFFFF)))
    if not me:create_collision() then
        me:free()
        return
    end
    me:setup_collision(6, 5, 3)
    me.collision.hit_effect = 0xA
    me.collision:present()
    me:set_lifecycle("update")
end

-- Region off, and gone.
local function finish(me: Object)
    me.collision.region = 0
    me:set_lifecycle("destroy")
end

-- `sub_80DBC48`: fly to the far edge (`sub_80DBCBA` times it from its
-- first tick); off the field, its region goes.
local function fly(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.vel = Vec3.new(me.facing * SPEED, me.vel.y, me.vel.z)
        local far = if me.alliance == 0 then 7 else 0
        local x = field.center(far, 1)
        me.timer = int.tdiv(math.abs(int.i32(x - me.pos.x)), SPEED)
    end
    local left = me.timer - 1
    me.timer = left
    if left <= 0 then
        return finish(me)
    end
    local p = me.pos
    me.pos = Vec3.new(p.x + me.vel.x, p.y, p.z)
    me:set_panel_from_coordinates()
    me:update_collision_panels()
    if me.collision.hit_flags ~= 0 then
        return finish(me)
    end
    if not field.valid(me.panel_x, me.panel_y) then
        me.collision.region = 0
    end
end

-- `sub_80DBC0A`: resolve the hits (a hit ends it), fly, register again.
local function tick(me: Object)
    local c = me.collision
    c:remove()
    me:hit_spark()
    if battle.over() or c.hit_flags ~= 0 then
        return finish(me)
    end
    if me.action ~= 0 then
        error(string.format("DustMan's junk action %#x reads past its table (off_80DBC44)", me.action))
    end
    fly(me)
    c:present()
end

-- `sub_80DBB40`.
function dust_junk.update(me: Object)
    local l = me.lifecycle
    if l == "init" then
        init(me)
    elseif l == "update" then
        tick(me)
    else
        me:destroy()
    end
    me:update_sprite_while_dimmed()
end

return dust_junk
