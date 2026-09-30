--!strict
-- JudgeMan's book (attack object #0x94, `sub_80D7ACC`): it appears on a
-- panel (JudgeMan's sprite, animation 0xA), waits Param1 · 12 + 30 ticks,
-- then flies at the enemy's navi (2.25 pixels a tick, along one axis at a
-- time, turning at panel centers), hitting what it meets (collision self 4,
-- target 5, modifier 1, hit spark 6); a hit on the other side's body or
-- object, reaching its target's panel, or a panel that isn't solid ends
-- it. When it goes (or can't start), it counts itself done in its owner's
-- state (`books_done`: the counter the game points ExtraVars[0] at). It
-- acts while dimmed. See docs/engine/chips.md §3.6.29.

export type State = {
    -- Whose `books_done` it adds to (ExtraVars[0], a pointer to it).
    counter: Object?,
    -- Its target panel (ExtraVars[1] and [2]).
    target_x: number,
    target_y: number,
}

local judge_book = {
    state = { counter = "object", target_x = "u32", target_y = "u32" },
}

-- The state a counter object keeps (JudgeMan's).
type Counter = { books_done: number }

local SPRITE = "08-0F"

-- Its speed (16.16).
local SPEED = 0x2_4000

-- What ends it when hit, by side (`byte_80D7BA8`: the other side's body or
-- object, and neutral ones).
local ENDS = { [0] = 0x0580_0000, 0x0A80_0000 }

-- Where it aims, by side (`off_80D7D44`: an enemy navi's body).
local ENEMY = { [0] = 0x0400_0000, 0x0800_0000 }

-- Count one book done.
local function count(counter: Object?)
    if counter then
        local c = counter.state :: Counter
        c.books_done += 1
    end
end

-- `sub_80D7C7E`: a book on (x, y) with `element`, `params` {order, axis}
-- and the damage word, counting itself done in `counter`'s state (at once
-- if it can't spawn). `z` is the spawner's register that becomes its Z,
-- of which the init keeps the fraction.
function judge_book.spawn(
    owner: Object,
    x: number,
    y: number,
    element: number,
    params: { number },
    damage: number,
    z: number,
    counter: Object
): Object?
    local o = battle.spawn_kind("judge-book", Vec3.new(y, element, z), params)
    if not o then
        count(counter)
        return nil
    end
    o.panel_x, o.panel_y = x, y
    o.element = element
    o.related1 = owner
    o.damage = damage
    o.stamina = bit32.rshift(damage, 16)
    local s = o.state :: State
    s.counter = counter
    o.alliance, o.flip = owner.alliance, owner.flip
    o.run_while_dimmed = true
    return o
end

-- `sub_80D7AF0`: on its panel, on the ground (Z's whole part cleared);
-- collision on (without it, it counts itself done and goes).
local function init(me: Object)
    me:set_coordinates_from_panel()
    local p = me.pos
    me.pos = Vec3.new(p.x, p.y, bit32.band(p.z, 0xFFFF))
    local sprite = me.sprite
    sprite:load(SPRITE)
    sprite.shadow = "ground"
    me.visible = true
    me.anim = 0xA
    me.anim_loaded = 0xA
    sprite:set_animation(0xA)
    sprite.palette = 0
    sprite:set_flip(bit32.bxor(me.alliance, me.flip))
    if not me:create_collision() then
        count((me.state :: State).counter)
        me:free()
        return
    end
    me:setup_collision(4, 5, 1)
    me.collision.hit_effect = 6
    me.collision:present()
    me:set_lifecycle("update")
end

-- `sub_80D7CCC`: its target: the first enemy body along its row from its
-- side's back column; else the first column (from there) with one (its
-- first row with one); else past the far edge in its own row.
local function find_target(me: Object): (number, number)
    local front = me.facing
    local enemy = ENEMY[me.alliance]
    local back = if me.alliance == 0 then 1 else 6
    -- object_getFirstPanelInDirectionFiltered
    local x = back
    while true do
        if field.check(x, me.panel_y, enemy, 0) then
            return x, me.panel_y
        end
        x += front
        if not field.valid(x, me.panel_y) then
            break
        end
    end
    -- object_getPanelsInColumnFiltered, column by column
    x = back
    while true do
        for y = 1, 3 do
            if field.check(x, y, enemy, 0) then
                return x, y
            end
        end
        x += front
        if x < 1 or x > 6 then
            break
        end
    end
    return if me.alliance == 0 then 7 else 0, me.panel_y
end

-- `sub_80D7CB0`: face the way it flies (unchanged when it flies up or
-- down).
local function face(me: Object)
    local vx = me.vel.x
    if vx > 0 then
        me.sprite:set_flip(0)
    elseif vx < 0 then
        me.sprite:set_flip(1)
    end
end

-- `sub_80D7D4C`: its heading toward the target, back on its panel's
-- center: along the other axis than Param2 says it went (x if 1, y if 0)
-- when that one is off, else the same; after two tries, turn back.
local function head(me: Object)
    local s = me.state :: State
    local tries = 0
    local along_x = me:param(2) ~= 0
    while true do
        if tries >= 2 then
            local v = me.vel
            me.vel = Vec3.new(-v.x, -v.y, v.z)
            break
        end
        tries += 1
        if along_x then
            if s.target_x ~= me.panel_x then
                me:set_param(2, 0)
                local vx = if s.target_x > me.panel_x then SPEED else -SPEED
                me.vel = Vec3.new(vx, 0, me.vel.z)
                break
            end
        else
            if s.target_y ~= me.panel_y then
                me:set_param(2, 1)
                local vy = if s.target_y > me.panel_y then SPEED else -SPEED
                me.vel = Vec3.new(0, vy, me.vel.z)
                break
            end
        end
        along_x = not along_x
    end
    me:set_coordinates_from_panel()
    face(me)
end

-- `sub_800E708`: `c` lies between `a` and `b` (either may equal it).
local function between(a: number, b: number, c: number): boolean
    if a == c or b == c then
        return true
    end
    if a <= b then
        return c > a and c <= b
    end
    return c >= b and c <= a
end

-- `sub_800E258`: the panel under a position.
local function panel_at(x: number, y: number): (number, number)
    return int.tdiv(int.asr(x, 16) + 0xA0, 0x28), int.tdiv(int.asr(y, 16) + 0x20, 0x18)
end

-- Region off, and gone (only the lifecycle byte: the action stays).
local function finish(me: Object)
    me.collision.region = 0
    me.lifecycle = "destroy"
end

-- `sub_80D7BB0`: wait Param1 · 12 + 30 ticks (to -1).
local function wait(me: Object)
    if me.phase == 0 then
        me.phase = 4
        battle.play_sound(0x94)
        me.timer = me:param(1) * 0xC + 0x1E
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left < 0 then
        me:set_action(4)
    end
end

-- `sub_80D7BE0`: fly; at each panel center on its axis, it has arrived
-- (its target's panel: it goes) or picks its heading again.
local function fly(me: Object)
    local s = me.state :: State
    if me.phase == 0 then
        me.phase = 4
        me.anim = 0xB
        s.target_x, s.target_y = find_target(me)
        head(me)
    end
    local cx, cy = field.center(me.panel_x, me.panel_y)
    local along_x = me:param(2) == 0
    local center = if along_x then cx else cy
    local p, v = me.pos, me.vel
    local nx, ny = int.i32(p.x + v.x), int.i32(p.y + v.y)
    me.pos = Vec3.new(nx, ny, p.z)
    local old, new = p.y, ny
    if along_x then
        old, new = p.x, nx
    end
    if center ~= old and between(new, old, center) then
        local px, py = panel_at(nx, ny)
        if px == s.target_x and py == s.target_y then
            return finish(me)
        end
        head(me)
    end
    me:set_panel_from_coordinates()
    me:update_collision_panels()
    if not field.solid(me.panel_x, me.panel_y) then
        finish(me)
    end
end

local ACTIONS = { [0] = wait, [4] = fly }

-- `sub_80D7B5C`: resolve the hits (hitting the other side's body or
-- object ends it), act, register again.
local function tick(me: Object)
    local c = me.collision
    c:remove()
    me:hit_spark()
    if battle.over() or bit32.btest(c.hit_flags, ENDS[me.alliance]) then
        return finish(me)
    end
    local f = ACTIONS[me.action]
    if not f then
        error(string.format("JudgeMan's book action %#x reads past its table (off_80D7B9C)", me.action))
    end
    f(me)
    c:present()
end

-- `sub_80D7ACC`.
function judge_book.update(me: Object)
    local l = me.lifecycle
    if l == "init" then
        init(me)
    elseif l == "update" then
        tick(me)
    else
        -- sub_80D7C6E
        count((me.state :: State).counter)
        me:destroy()
    end
    me:update_sprite_while_dimmed()
end

return judge_book
