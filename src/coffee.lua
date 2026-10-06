-- The ring a mug of coffee leaves on the page, spreading under your feet.
--
-- The thirteenth passive weapon, and the only one that pays you for standing
-- still. Every other one either does not care where your feet are -- a star turns
-- where it turns, a cloud rolls in -- or wants them going somewhere: the beam
-- fires down the line you walk, the skate's trail is the line you walked, the
-- bomb is a hole in the ground you are leaving. This is the other end of that
-- question. A ring under you that grows while you stay put and dries back in
-- while you walk, so what the line asks is whether you will plant yourself in
-- front of the crowd and let it come.
--
-- Which is what a run spends a lot of time doing anyway, and that is the point
-- of it: drawing is done standing still more often than not, and this is the
-- weapon that is working hardest while your hands are busy with the pencil.
--
-- **It is an aura, and the only one.** The stars go round you and the flock wheels
-- about you, but both are things that pass and come back; this is ground, under
-- you all the time, and the size of it is the whole of what you are playing. It
-- never goes below `least` -- a ring small enough to take what is touching you --
-- so the weapon is never off, it is only small.
--
-- The levels sell the ring getting worse to stand in (deeper, then sticky) and
-- the ring getting bigger faster, and the finale is the mug going over: walk off
-- a ring that has spread all the way and it splashes outwards in a wave that
-- hits and shoves everything it reaches, and the ring starts again from a drip.
-- That turns the line's one rule round on itself -- stand still to build it,
-- move to spend it -- which is the decision the whole weapon is about, made
-- twice a fight instead of never.
--
-- **It has no board**, the third weapon without one (the laser beam and the
-- spirals are the others): a ring is a radius, which is arithmetic, and a drawing
-- is a fixed grid of pixels. It goes down in the ground pass (`drawGround`), under
-- the crowd, because it is a stain on the paper and what is standing in it has to
-- be legible on top of it.
--
-- No alpha, as everywhere: the stain is a rim, two pixels of it like a real coffee
-- ring, slate while it is wet and spreading and graphite once you have walked
-- and it is drying back in. The overprint pass does the rest -- a ring laid over
-- the ruling darkens it a step, which is what coffee does to a page.

local Palette = require("src.palette")
local pixelart = require("src.pixelart")
local util = require("src.util")

local Coffee = {}
Coffee.__index = Coffee

-- How long the splash takes to reach the edge of what it can reach. Short, since
-- it is a splash rather than a wave anybody watches roll: a quarter of a second
-- is long enough to see it go out and short enough that it reads as one event.
local SPLASH_TIME = 0.25

-- How far past the ring the splash goes, as a multiple of the ring it came out
-- of. The mug going over throws its coffee well past the stain it had been
-- sitting in, and a splash that stopped at the rim would be the ring blinking.
local SPLASH_REACH = 1.6

-- How full the ring has to be before walking off it tips the mug. A hair under
-- full, so a ring that has stopped growing because it reached `most` and a ring
-- one frame short of it are the same ring to the player, which they are.
local FULL = 0.95

-- How long a thing keeps the ring's grip after it has stepped out of it: the
-- skate's `CARRY` and for its reason. The weapons are stepped after the crowd has
-- moved, so a slow read straight off the ring would always land a frame late.
local CARRY = 0.12

function Coffee.new()
    return setmetatable({
        def = nil,
        r = nil,      -- how far the ring has spread, set on the first configure
        tick = 0,
        wet = true,   -- spreading rather than drying, for the colour of the rim
        splash = nil,
    }, Coffee)
end

function Coffee:configure(def)
    self.def = def
    -- A fresh ring starts as a drip and a level taken mid-run leaves the ring as
    -- it was -- only clamped, since a level that lowered `most` would otherwise
    -- leave a ring bigger than it is allowed to be.
    self.r = util.clamp(self.r or def.least, def.least, def.most)
end

--- spreading -------------------------------------------------------------------

-- The ring as a function of your feet: out at `grow` a second while you stand,
-- back in at `shrink` while you walk. Two rates rather than one because they are
-- two different promises -- how long a stand takes to pay, and how long a
-- walk costs you -- and the line only ever sells the first.
function Coffee:spread(dt, player)
    local def = self.def
    local before = self.r

    if player.moving then
        self.r = math.max(def.least, self.r - def.shrink * dt)
    else
        self.r = math.min(def.most, self.r + def.grow * dt)
    end
    self.wet = not player.moving

    -- The mug going over: the first frame of walking off a ring that was full.
    -- Asked on the edge from standing to walking rather than of every frame
    -- spent walking, so it goes once per stand however long the walk is.
    if def.spill and player.moving and not self.splash
        and before >= def.most * FULL and self.r < before then
        self:tip(player)
    end
end

--- burning ---------------------------------------------------------------------

-- Everything standing in the ring, on a tick. `eachWithin` for the sun's reason:
-- at the top of the line the ring is far wider than the nine 12px cells
-- `eachNear` looks in. The damage is read here rather than kept, since the ring
-- carries nothing away -- it is always where you are, at today's numbers.
function Coffee:burn(dt, game, player)
    local def = self.def

    self.tick = self.tick - dt
    if self.tick > 0 then return end
    self.tick = def.tick

    local stats = game.loadout.stats
    local damage = def.damage * stats.passiveDamage * stats.damage

    game:eachWithin(player.x, player.y, self.r, function(e)
        if def.slow < 1 then
            e.chill, e.chillT = def.slow, math.max(e.chillT, def.tick + CARRY)
        end
        if e:hurt(damage) then
            game:killEnemyAt(e)
        end
    end)
end

--- the mug going over ---------------------------------------------------------

-- A wave out from where you were standing, hitting everything it passes once and
-- shoving it outwards. A shove through `knockback` for the reason the spiral's
-- old push was one: it decays, so what the splash buys is room, and `knock` on a
-- boss's row already says how little room a boss gives. The ring goes back to a
-- drip -- the coffee is on the page now, not in the mug.
function Coffee:tip(player)
    local def = self.def
    self.splash = {
        x = player.x, y = player.y,
        from = self.r,
        reach = self.r * SPLASH_REACH,
        t = 0,
        hit = {},
    }
    self.r = def.least
end

function Coffee:wave(dt, game)
    local sp = self.splash
    local def = self.def.spill
    sp.t = sp.t + dt

    local front = sp.from + (sp.reach - sp.from) * math.min(1, sp.t / SPLASH_TIME)
    local stats = game.loadout.stats
    local damage = def.damage * stats.passiveDamage * stats.damage

    game:eachWithin(sp.x, sp.y, front, function(e)
        if sp.hit[e] then return end
        sp.hit[e] = true

        local nx, ny = util.normalize(e.x - sp.x, e.y - sp.y)
        if nx ~= 0 or ny ~= 0 then
            e:knockback(nx, ny, def.force * stats.knock)
        end
        game.particles:burst(e.x, e.y, 2, Palette.slate)
        if e:hurt(damage) then
            game:killEnemyAt(e)
        end
    end)

    sp.front = front
    if sp.t >= SPLASH_TIME then self.splash = nil end
end

function Coffee:update(dt, game, grid)
    local player = game.player

    self:spread(dt, player)
    self:burn(dt, game, player)
    if self.splash then self:wave(dt, game) end

    -- Kept for the draw, which may only read: it is round the player this frame.
    self.x, self.y = player.x, player.y
end

--- drawing -------------------------------------------------------------------

-- Down on the page under the crowd. Two pixels of rim, the outer one the darker,
-- which is what a coffee ring is -- the coffee runs to the edge as it dries -- and
-- the colour says which way it is going: slate while you stand and it spreads,
-- graphite while you walk and it dries back in.
--
-- Guarded on having been placed, for the spiral's old reason: the level is taken
-- while the run is held under the draft's cards, and the first thing that
-- happens to the ring is being drawn a frame before anything told it where the
-- player is.
function Coffee:drawGround(game)
    if not self.x then return end
    local x, y, r = math.floor(self.x), math.floor(self.y), math.floor(self.r)

    love.graphics.setColor(self.wet and Palette.slate or Palette.graphite)
    pixelart.circleOutline(x, y, r)
    love.graphics.setColor(Palette.graphite)
    pixelart.circleOutline(x, y, r - 1)

    -- The splash: one ring going out, slate, and gone once it has arrived.
    local sp = self.splash
    if sp and sp.front then
        love.graphics.setColor(Palette.slate)
        pixelart.circleOutline(math.floor(sp.x), math.floor(sp.y), math.floor(sp.front))
    end
end

return Coffee
