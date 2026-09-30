--!strict
-- JudgeMan, the navi of the JudgeMan chips (actor object #0xF,
-- `sub_80BA708`), brought by their navi chip controller. He appears, lashes
-- the three panels ahead (objects/judge-whip on him, a hit on each), then,
-- for each panel of his side's home the enemy has taken (and nothing
-- stands on), a book there (objects/judge-book, Param1 damage) that flies
-- at the enemy; once they are all done, the taken columns start coming
-- back, and he leaves. See docs/engine/chips.md §3.6.29.
--
-- The chips' script (navi chip subtype 15): `navi_chip` is his spawner,
-- `off_802CD5C[15]`.

local panels = require("../../lib/panels")
local judge_whip = require("../judge-whip/judge_whip")
local judge_book = require("../judge-book/judge_book")

export type State = {
    -- His whip (ExtraVars[0]).
    whip: Object?,
    -- How many books (ExtraVars[1]), the panels they start on (packed,
    -- from object +0x68), and how many are done (ExtraVars[5]: the books
    -- count themselves here).
    books: number,
    book_panels: { number },
    books_done: number,
    -- The controller waiting for him (its pointer sits in his collision
    -- data slot).
    controller: Object?,
}

local judge_man = {
    state = { whip = "object", books = "u32", book_panels = "u8[12]", books_done = "u32", controller = "object" },
}

local SPRITE = "08-0F"

-- Panel flags he needs to stay (as one word).
local CAN_STAND = 0x10010

-- The columns he looks at, by side (`byte_80BA9F8`, `off_80BAA84`).
local COLUMNS = { [0] = { 5, 4, 3, 2 }, { 2, 3, 4, 5 } }

-- A book's panel: solid, nothing on it (`dword_80BAA04`, `dword_80BAA08`).
local BOOK_PANEL = { 0x10, 0x0F88_0080 }

-- `sub_80BA920`: JudgeMan for `user`, reporting to `controller`. (His Z
-- is the spawner's address the controller leaves in r3, of which his init
-- keeps the fraction.)
function judge_man.navi_chip(user: Object, controller: Object, spec: NaviChipSpec): Object?
    local o = battle.spawn_kind("judge-man", Vec3.new(spec.panel_y, spec.element, 0x080B_A921), spec.params)
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

-- `sub_80BA72C`: on his panel, on the ground (Z's whole part cleared).
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

-- Enter the phase with an animation and a timer (a halfword store), or
-- count it down; true once it is 0 or below.
local function countdown(me: Object, anim: number, ticks: number): boolean
    if me.phase == 0 then
        me.phase = 4
        me.anim = anim
        me.timer = ticks
        return false
    end
    local left = me.timer - 1
    me.timer = left
    return left <= 0
end

-- `sub_800D618`: the panel is `side`'s home, and the other side's now.
local function taken(x: number, y: number, side: number): boolean
    local p = field.panel(x, y)
    return p ~= nil and p.home ~= p.alliance and p.home == side
end

-- `sub_80BA7A0`: he appears; 2 ticks; on, or straight to leaving if his
-- panel can't hold him. (Timer2 cleared.)
local function appear(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 3
        battle.play_sound(0x94)
        me.visible = true
        me.timer = 2
        me.timer2 = 0
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left > 0 then
        return
    end
    local stands = bit32.band(field.flags(me.panel_x, me.panel_y), CAN_STAND) == CAN_STAND
    me:set_action(if stands then 4 else 0x18)
end

-- `sub_80BA7F4`: 30 ticks standing. (Timer2 cleared.)
local function stand(me: Object)
    if me.phase == 0 then
        me.timer2 = 0
    end
    if countdown(me, 0, 0x1E) then
        me:set_action(8)
    end
end

-- `sub_80BA81C`: the whip comes out; 15 ticks.
local function raise(me: Object)
    if me.phase == 0 then
        (me.state :: State).whip = judge_whip.spawn(me, { 1 })
    end
    if countdown(me, 6, 0xF) then
        me:set_action(0xC)
    end
end

-- `sub_80BA946`: the lash's hits on the three panels ahead (hitboxes that
-- run while dimmed: status 0x11).
local function lash(me: Object)
    for i = 1, 3 do
        local box = battle.hitbox(me, {
            panel_x = me.panel_x + me.facing * i,
            panel_y = me.panel_y,
            element = me.element,
            z = 0,
            region = 1,
            hit_effect = 3,
            target = 5,
            self_type = 0x19,
            damage = me.damage,
            stamina = me.stamina,
            hit_mod = 1,
            status = 0x11,
        })
        if box then
            box.run_while_dimmed = true
        end
    end
end

-- `sub_80BA9A4`: the panels for books: in his columns, the rows his side
-- lost that stand free. How many.
local function book_panels(me: Object): number
    local s = me.state :: State
    local n = 0
    for _, x in COLUMNS[me.alliance] do
        for y = 1, 3 do
            if taken(x, y, me.alliance) and field.check(x, y, BOOK_PANEL[1], BOOK_PANEL[2]) then
                s.book_panels[n + 1] = bit32.bor(bit32.lshift(y, 4), x)
                n += 1
            end
        end
    end
    return n
end

-- `sub_80BA84C`: the lash (sound 0xBA); 30 ticks; the whip goes, and on
-- to the books if there are panels for them, else he leaves.
local function strike(me: Object)
    local s = me.state :: State
    if me.phase == 0 then
        me.phase = 4
        me.anim = 7
        lash(me)
        battle.play_sound(0xBA)
        me.timer = 0x1E
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left > 0 then
        return
    end
    judge_whip.take_off(s.whip)
    s.books = book_panels(me)
    me:set_action(if s.books ~= 0 then 0x10 else 0x18)
end

-- `sub_80BAA0C`: a book on each panel (Param1 i, Param2 1), dealing his
-- Param1 as damage with his damage word's flags, Null.
local function summon_books(me: Object)
    local s = me.state :: State
    local damage = bit32.bor(bit32.lshift(me.stamina, 16), me:param(1), bit32.band(me.damage, 0xF000))
    local i = 0
    repeat
        local x, y = panels.unpack(s.book_panels[i + 1])
        -- r3 (the damage's flag bits) becomes the book's Z.
        judge_book.spawn(me, x, y, 0, { i, 1 }, damage, bit32.band(me.damage, 0xF000), me)
        i += 1
    until i >= s.books
end

-- `sub_80BA89C`: 30 ticks; the books at 15 left.
local function books(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 5
        me.timer = 0x1E
        return
    end
    local left = me.timer - 1
    me.timer = left
    if left == 0xF then
        summon_books(me)
        return
    end
    if left <= 0 then
        me:set_action(0x14)
    end
end

-- `sub_80BAA4C`: in each of his columns, the first row his side lost
-- starts coming back (its column's timer at 1).
local function give_back(me: Object)
    for _, x in COLUMNS[me.alliance] do
        for y = 1, 3 do
            if taken(x, y, me.alliance) then
                field.set_column_timer(x, 1)
                break
            end
        end
    end
end

-- `sub_80BA8D0`: wait for every book to be done; the columns start coming
-- back.
local function wait_books(me: Object)
    if me.phase == 0 then
        me.phase = 4
        me.anim = 0
    end
    local s = me.state :: State
    if s.books_done ~= s.books then
        return
    end
    give_back(me)
    me:set_action(0x18)
end

-- `sub_80BA8F6`: 2 ticks, then he goes and the controller moves on.
local function leave(me: Object)
    if not countdown(me, 4, 2) then
        return
    end
    local controller = (me.state :: State).controller
    if controller then
        navi_chip.navi_left(controller)
    end
    me:set_lifecycle("destroy")
end

local ACTIONS = { [0] = appear, [4] = stand, [8] = raise, [0xC] = strike, [0x10] = books, [0x14] = wait_books, [0x18] = leave }

-- `sub_80BA708`.
function judge_man.update(me: Object)
    local l = me.lifecycle
    if l == "init" then
        init(me)
    elseif l == "update" then
        local action = ACTIONS[me.action]
        if not action then
            error(string.format("JudgeMan action %#x reads past his table (off_80BA784)", me.action))
        end
        action(me)
    else
        me:free()
    end
    me:update_sprite_while_dimmed()
end

return judge_man
