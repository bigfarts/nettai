--!strict
-- GroundMan's drill (effect object #0x61, `sub_80E7788`): a sprite on its
-- owner that follows his position, visibility, palette, look and facing.
-- GroundMan's (Param1 1) stays until he takes it off (`sub_80E78AE`, the
-- `take_off` below); with Param1 0 it goes once its owner's action is no
-- longer Param2. Purely visual, but it holds an effect slot. See
-- docs/engine/chips.md §3.6.25.

local ground_drill = {}

local SPRITE = "10-4F"

-- `sub_80E7896`: a drill on `owner`, with `params` {Param1, Param2}.
function ground_drill.spawn(owner: Object, params: { number }): Object?
    local o = battle.spawn_kind("ground-drill", Vec3.zero, params)
    if o then
        o.related1 = owner
        o.alliance, o.flip = owner.alliance, owner.flip
    end
    return o
end

-- `sub_80E78AE`: take the drill off (at its next update).
function ground_drill.take_off(o: Object?)
    if o then
        o:set_lifecycle("destroy")
    end
end

-- `sub_80E77B8`: on its owner, as visible as he is.
local function init(me: Object)
    local owner = me.related1 :: Object
    me.pos = owner.pos
    local sprite = me.sprite
    sprite:load(SPRITE)
    sprite.shadow = "with_sprite"
    me.visible = true
    me.anim = 0
    me.anim_loaded = 0
    sprite:set_animation(0)
    sprite.palette = 0
    sprite:set_flip(bit32.bxor(me.alliance, me.flip))
    me.visible = owner.visible
    me:set_lifecycle("update")
end

-- `sub_80E7816`: follow the owner; with Param1 0, go once his action
-- isn't Param2 any more.
local function tick(me: Object)
    if battle.over() then
        me:set_lifecycle("destroy")
        return
    end
    local owner = me.related1 :: Object
    me.pos = owner.pos
    me.visible = owner.visible
    local sprite, look = me.sprite, owner.sprite
    sprite.palette = look.palette
    sprite.color_shader = look.color_shader
    sprite.white = look.white
    sprite.mosaic = look.mosaic
    me.flip = owner.flip
    sprite:set_flip(bit32.bxor(me.alliance, me.flip))
    sprite.alpha = look.alpha
    if me:param(1) == 0 and owner.action ~= me:param(2) then
        me:set_lifecycle("destroy")
    end
end

-- `sub_80E7788`.
function ground_drill.update(me: Object)
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

return ground_drill
