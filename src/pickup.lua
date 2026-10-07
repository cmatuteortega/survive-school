-- What the page scatters for you to walk to. Six kinds -- a heart that heals,
-- a droplet that makes drawing free for a moment, a diamond worth a whole
-- level, a wall clock that stops the horde where it stands, an alarm clock that
-- goes off and takes the screen with it, and a gold star that makes everything
-- hit a little harder for the rest of the run -- and all
-- of them land out of view, because the reward is the walk: a gem is thrown at
-- your feet by a kill you already made, and these are the opposite half of that
-- idea, something out there that pays a run for moving instead of standing in
-- one spot grinding the horde. That is also why the magnet ignores them and
-- there is no pull at all -- touched means touched.
--
-- They arrive two ways. A scatter clock drops one just past the screen edge
-- every few seconds, so there is always something a few steps from view -- and
-- underneath that, the page itself has pickups at fixed spots, a pure function
-- of the cell coordinates like the ruling and everything else about the page
-- (see src/background.lua on determinism). A fixed spot materialises when you
-- come near, is still there if you leave and come back, and once taken is gone
-- for the run: it is a place on the page, not a beat on a clock, and knowing
-- where one is is worth something.
--
-- And a fourth that is never scattered and never on the fixed layer: the coin
-- the piggy bank puts on the page (src/piggyboss.lua), as bait in its charge
-- lanes and as what bursts out of it. It is here rather than in its brain
-- because it is the same thing as the other three -- touched means taken, and
-- it stays on the page when the fight is over.

local Trinket = require("src.trinket")
local Camera = require("src.camera")
local Palette = require("src.palette")
local Sfx = require("src.sfx")
local util = require("src.util")

local Pickup = {}
Pickup.__index = Pickup

-- The scatter, on a slow clock, and never many lying around: a page carpeted
-- in prizes is a page where none of them is worth turning for.
Pickup.EVERY = 5
Pickup.MAX = 8

-- How far past the screen edge a scattered one lands. The enemy ring is no
-- good here: it clears the *corner* of the screen, which up or down -- where
-- the view is half as tall as it is wide -- is a hundred pixels of blind
-- walking, and a pickup nobody ever sees promotes nothing. These sit close
-- enough that a few steps in any direction bring one into view.
local CLEARANCE = 24
local SPREAD = 70

local DESPAWN = 480  -- wider than the enemies' 420, so one you saw and turned
                     -- away from is still there if you come back for it
local TOUCH = 4      -- on top of the player's radius
local MIN_APART = 30 -- no two pickups closer than this: two on one spot read
                     -- as one, and the second is a prize nobody knows they won

-- The fixed layer. One spot in roughly every third cell, held away from the
-- cell borders so no two neighbours can land inside MIN_APART of each other.
-- MATERIALIZE sits under DESPAWN so a spot on the boundary does not flicker
-- in and out as you shuffle.
local CELL = 260
local DENSITY = 0.35
local MATERIALIZE = 440

local HEAL = 25      -- a quarter of the base bar
-- The droplet does not pour ink into the well: it makes the pen free for a few
-- seconds (`Game.inkFree`, read by Game:spendInk). A refill was worth most when
-- the well was empty and nothing when it was full, so a droplet walked into
-- between strokes was a prize you could not tell you had won; a window of free
-- ink is worth the same whenever you take it, and what it asks is that you
-- spend it -- the walk out there pays off in the frantic drawing after.
local INK_FREE = 4

-- The wall clock: everything on the page stops for this long. A boss shrugs
-- most of it off through its own `hold` (Enemy:freeze), exactly as it shrugs off
-- glue -- a boss stood still for five seconds is a boss that is not a fight.
local FREEZE = 5

-- When the stopped clock says how long it has left: a tick-tock on each of the
-- first whole seconds, then a tick every half second climbing in pitch over the
-- last two, so the thaw is something you hear coming without looking away from
-- the page -- and the page is where you want to be looking while it is stopped.
local CUES = {
    { at = 4, pitch = 1.0 }, { at = 3, pitch = 0.8 }, { at = 2, pitch = 1.0 },
    { at = 1.5, pitch = 1.25 }, { at = 1, pitch = 1.4 }, { at = 0.5, pitch = 1.6 },
}

-- The gold star: this much more damage on everything, for every star the run has
-- picked up, until the run ends (`Loadout.stars`, read in Loadout:rebuild). Two
-- percent is small on purpose. It is the one pickup whose worth keeps adding up,
-- and a run that has walked to twenty of them should feel it without the stars
-- becoming the build.
Pickup.STAR = 0.02

-- The rare ones are rare because each is an event: the diamond is a draft in
-- disguise -- a free level is worth more than anything else on this table -- the
-- wall clock and the alarm clock are each a way out of a crowd that had you, and
-- the star is a permanent stat. Rarity is what keeps spotting one an event rather
-- than an errand. Together they are as common as a heart.
local KINDS = {
    { kind = "heart",   weight = 4 },
    { kind = "ink",     weight = 4 },
    { kind = "diamond", weight = 1 },
    { kind = "clock",   weight = 1 },
    { kind = "alarm",   weight = 1 },
    { kind = "star",    weight = 1 },
}

-- What the wall clock stops and the alarm clock goes off on: the horde, but not
-- a boss's stand-ins (`stand`, src/redpenboss.lua and src/stilllife.lua), which
-- are the boss and are kept where it put them, and not one still dropping onto
-- the page (`arrive`), which is not in the fight yet.
local function bystander(e)
    return not (e.stand or e.ghost or e.arrive)
end

-- Always consumed, even by a bar with no room for it: a heart that refused a
-- full bar hung around holding one of the MAX slots, quietly throttling the
-- scatter clock for as long as you stayed healthy -- and a run walking past a
-- heart it cannot use right now still reads "taken" more honestly than a heart
-- that bounces off. The diamond banks its level, and the run stops to spend it
-- the same way an earned one is spent (Game:update).
local TAKE = {
    heart = function(game, x, y)
        local p = game.player
        -- Guarded at zero for `Player:mend`'s reason: this runs
        -- (Game:updatePickups) before the frame's death check, so walking onto
        -- a heart the instant something else lands the killing blow must not
        -- be the thing that quietly cancels it.
        if p.hp > 0 then
            p.hp = math.min(p.maxHp, p.hp + HEAL)
        end
        game.particles:burst(x, y, 6, Palette.red)
    end,
    -- Topped up and held there rather than added to: a second droplet inside
    -- the window starts the four seconds again instead of stacking them, the
    -- way a heart on a full bar is spent on nothing.
    ink = function(game, x, y)
        game.inkFree = INK_FREE
        game.ink = game.loadout.stats.inkMax
        game.particles:burst(x, y, 6, Palette.blue)
    end,
    diamond = function(game, x, y)
        game.player:levelUp()
        game.particles:burst(x, y, 8, Palette.sky)
    end,
    -- A coin the piggy bank put on the page (src/piggyboss.lua): never
    -- scattered, only spat, burst or spilled out of it. One coin in the purse at
    -- the end of the run (`banked`, Game:runWorth), which is the whole of why
    -- it is worth walking into a charge lane for.
    coin = function(game, x, y)
        game.banked = (game.banked or 0) + 1
        game.particles:burst(x, y, 6, Palette.blush)
    end,
    -- Everything already on the page is stopped, and a second clock inside the
    -- window starts the five seconds again rather than stacking them -- the
    -- droplet's rule. What walks on while it is stopped walks on: the clock
    -- stopped the horde that was there, not the afternoon. Frozen is glued
    -- (Enemy:freeze), so a stopped monster still hurts to walk into, and is
    -- still there to be hit.
    clock = function(game, x, y)
        for _, e in ipairs(game.enemies) do
            if bystander(e) then e:freeze(FREEZE) end
        end
        game.stopped = FREEZE
        game.particles:burst(x, y, 8, Palette.slate)
    end,
    -- Everything in view goes off at once, through the one door every kill
    -- comes through (Game:killEnemy), so each leaves its gem where it stood and
    -- whatever it does on dying it still does -- a blot still bursts into drops
    -- and a bulb still goes off, which is what a page that went up in your face
    -- should cost. Bosses are not on it: the alarm clears the room the boss
    -- walked into, and leaves the boss.
    alarm = function(game, x, y)
        local left, top, w, h = Camera.bounds()
        local enemies = game.enemies
        for i = #enemies, 1, -1 do
            local e = enemies[i]
            if e and bystander(e) and not e.def.boss
                and e.x >= left and e.x <= left + w
                and e.y >= top and e.y <= top + h then
                game.particles:burst(e.x, e.y, 5, Palette.red)
                game:killEnemy(i)
            end
        end
        game.particles:burst(x, y, 16, Palette.red)
        Camera.knock(3)
        Sfx.play("alarm")
    end,
    star = function(game, x, y)
        local loadout = game.loadout
        loadout.stars = loadout.stars + 1
        loadout:rebuild(game.vw, game.vh)
        game.particles:burst(x, y, 4, Palette.red)
        game.particles:burst(x, y, 4, Palette.blue)
    end,
}

-- The stopped clock running down (`Game.stopped`), from Game:updatePickups: it
-- holds no enemy itself -- each carries its own `frozen` -- and is only here to
-- say out loud how long is left, and to ring when it is over.
function Pickup.tickStopped(game, dt)
    local was = game.stopped
    if was <= 0 then return end
    local now = math.max(0, was - dt)
    game.stopped = now
    for _, cue in ipairs(CUES) do
        if was > cue.at and now <= cue.at then Sfx.play("tick", cue.pitch) end
    end
    if now <= 0 then Sfx.play("note", 0.5) end
end

-- One weighted table serves both layers: the scatter rolls the dice, a fixed
-- spot hashes its cell, and either way the roll lands in [0,1).
local function kindFor(roll)
    local total = 0
    for _, row in ipairs(KINDS) do total = total + row.weight end

    roll = roll * total
    for _, row in ipairs(KINDS) do
        roll = roll - row.weight
        if roll <= 0 then return row.kind end
    end
    return KINDS[1].kind
end

-- And never on a worksheet (src/worksheet.lua), required here rather than at
-- the top because the worksheet is what pays out pickups: it requires this file.
local function clearOf(pickups, x, y, game)
    for _, p in ipairs(pickups) do
        if util.len(p.x - x, p.y - y) < MIN_APART then return false end
    end
    return not (game and require("src.worksheet").covers(game, x, y))
end

function Pickup.new(kind, x, y)
    return setmetatable({
        kind = kind,
        x = x, y = y,
        -- How far through its turn and its bob it is: set off a different
        -- way for every spot, so a few lying near each other do not turn in
        -- step like a row of shop-window ornaments.
        t = util.hash01(x, y, 5) * 10,
        dead = false,
    }, Pickup)
end

-- A candidate spot just past a random edge of the screen -- never in view,
-- always a short walk from being in view. The side is rolled in proportion to
-- its length, so the scatter is even along the whole rim of the screen rather
-- than piling up on the short sides.
local function pastEdge(game)
    local hw, hh = game.vw / 2, game.vh / 2
    local out = CLEARANCE + love.math.random() * SPREAD

    local r = love.math.random() * (game.vw + game.vh) * 2
    if r < game.vw then                     -- above
        return game.player.x + love.math.random() * game.vw - hw,
            game.player.y - (hh + out)
    elseif r < game.vw * 2 then             -- below
        return game.player.x + love.math.random() * game.vw - hw,
            game.player.y + hh + out
    elseif r < game.vw * 2 + game.vh then   -- left
        return game.player.x - (hw + out),
            game.player.y + love.math.random() * game.vh - hh
    else                                    -- right
        return game.player.x + hw + out,
            game.player.y + love.math.random() * game.vh - hh
    end
end

-- One scattered pickup, or nil when every roll landed on top of something
-- already out there -- the clock simply tries again on its next beat.
function Pickup.scatter(game)
    for _ = 1, 8 do
        local x, y = pastEdge(game)
        if clearOf(game.pickups, x, y, game) then
            return Pickup.new(kindFor(love.math.random()), x, y)
        end
    end
end

-- What the fixed layer holds at one cell, if anything. Seeded per run rather
-- than truly global, because every run starts at (0, 0): a layout shared by
-- all runs would hand every one of them the same opening pickups -- the same
-- diamond a hundred pixels from the start, every time -- and an opening you
-- can memorise is an opening, not a discovery. Within the run it never moves.
local function fixedAt(cx, cy, seed)
    if util.hash01(cx, cy, seed + 7) >= DENSITY then return end

    return kindFor(util.hash01(cx, cy, seed + 8)),
        (cx + 0.2 + util.hash01(cx, cy, seed + 9) * 0.6) * CELL,
        (cy + 0.2 + util.hash01(cx, cy, seed + 10) * 0.6) * CELL
end

-- Walk the fixed cells within reach and wake any spot that should be standing
-- and is not: not taken this run, not already awake, and not inside MIN_APART
-- of something else (a scattered pickup can sit on a fixed spot; the spot
-- waits its turn). A woken pickup that is later walked away from dies off the
-- list like any other -- what brings it back is this, on the way back in.
function Pickup.materialize(game)
    local px, py = game.player.x, game.player.y

    local awake = {}
    for _, p in ipairs(game.pickups) do
        if p.cell then awake[p.cell] = true end
    end

    for cy = math.floor((py - MATERIALIZE) / CELL),
             math.floor((py + MATERIALIZE) / CELL) do
        for cx = math.floor((px - MATERIALIZE) / CELL),
                 math.floor((px + MATERIALIZE) / CELL) do
            local key = cx * 100000 + cy
            if not game.pickupTaken[key] and not awake[key] then
                local kind, x, y = fixedAt(cx, cy, game.pickupSeed)
                if kind and util.len(x - px, y - py) < MATERIALIZE
                    and clearOf(game.pickups, x, y, game) then
                    local p = Pickup.new(kind, x, y)
                    p.cell = key
                    game.pickups[#game.pickups + 1] = p
                end
            end
        end
    end
end

function Pickup:update(dt, game)
    -- Already gone: a coin the piggy bank called home this frame
    -- (src/piggyboss.lua) is in the air now, and is not still here to be taken.
    if self.dead then return end
    local player = game.player
    local dist = util.len(player.x - self.x, player.y - self.y)

    if dist < player.radius + TOUCH then
        TAKE[self.kind](game, self.x, self.y)
        -- One sound for all of them, here rather than over and over in TAKE:
        -- what they have in common is the thing the sound is about -- you
        -- walked out there and it was worth it -- and which of them it was is
        -- what the body and the burst are for. The alarm clock's ring is on top
        -- of this, because what it did is not a prize but a bang.
        Sfx.play("item")

        -- A fixed spot is spent for the run; a scattered one just dies.
        if self.cell then game.pickupTaken[self.cell] = true end
        self.dead = true
        return
    end

    -- Abandoned rather than hoarded: a run that walks off leaves it behind --
    -- a scattered one for good, a fixed one until the next visit.
    if dist > DESPAWN then
        self.dead = true
        return
    end

    self.t = self.t + dt
end

-- Turning in the air over its own shadow (src/trinket.lua). The shadow is on the
-- paper and goes on darkening over a rule like every other mark; the body is
-- standing proud of it, and blanks the page under itself (Pickup:drawSolid).
function Pickup:draw()
    Trinket.drawShadow(self.kind, self.x, self.y, self.t)
    Trinket.draw(self.kind, self.x, self.y, self.t)
end

-- The blank stamped into the page under it, from inside Overprint.beginSolid and
-- for Enemy:drawSolid's reason: a thing turning over the page is standing on it,
-- not printed into it, and the ruling coming through a heart made it a sticker.
function Pickup:drawSolid()
    love.graphics.setColor(Palette.paper)
    Trinket.drawMask(self.kind, self.x, self.y, self.t)
end

return Pickup
