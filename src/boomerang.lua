-- The boomerang you throw at the nearest thing and catch on the way back.
--
-- The fourteenth passive weapon, and the only one that comes home. Everything
-- else that leaves you -- a shot, a volley of rockets, a beam -- goes and is gone,
-- and everything that stays with you -- a star, the flock, the coffee ring -- never
-- went anywhere. This one goes out at whatever is nearest, slows to a stop at the
-- end of its throw, and then flies back to **where you are now** rather than to
-- where it left you: so the way it comes home is drawn by your feet, through
-- whatever is standing between the two of you, and everything it passed going out
-- it can pass again coming back.
--
-- **The catch is the half you play.** The clock for the next throw does not start
-- until the last one is in your hand, so a run that walks towards its boomerang
-- throws more often than one that waits for it -- the only weapon whose rate of
-- fire is something you do with your feet. The finale takes that to its end:
-- caught, it goes straight back out, and the wait between throws is the flight.
--
-- It is the cool S read through the shot. The S is a line nobody aimed, crossing
-- the whole page once; the shot is a pellet aimed at one thing and spent on it.
-- This is aimed like the shot and cuts like the S -- through everything on its
-- way, out and back, a fresh pass each way -- and it pays for both with distance:
-- it only ever reaches `range` from you.
--
-- **The way out is a throw and the way back is a homing.** Out, it is a straight
-- line slowing at a constant rate to stop exactly `range` away, which is what a
-- thrown thing does and what makes the far end of it a place you can see coming.
-- Back, it steers straight at you and picks up speed to the throw's own, so it
-- always arrives -- you walk at 58 and it comes home at three times that. A
-- boomerang that somehow has not been caught by `LOST` seconds is let go of
-- anyway, for the storm's reason: a weapon with a clock that never restarts is a
-- weapon that quietly stopped.
--
-- Drawn by you on its own board (src/design.lua), and spun rather than pointed:
-- it is kept at the eight headings every turned drawing is (Sprites.turned) and
-- steps round them as it flies, which is a spin made of nothing but the
-- rendering rules -- no sprite is ever drawn at an angle.

local Palette = require("src.palette")
local Sprites = require("src.sprites")
local util = require("src.util")

local Boomerang = {}
Boomerang.__index = Boomerang

-- How far round it hits from its middle, before the enemy's own radius. Half the
-- 9x9 board, so the cut is the size of what you drew the frame round -- the cool
-- S's rule: you can change what it looks like, you cannot draw a bigger one.
local HIT = 4

-- The circle `eachWithin` is asked for: the cut plus the widest thing on the
-- page. One or two of these are in the air at a time, so the whole horde is
-- affordable every frame, the same bargain the cool S makes.
local REACH = HIT + 20

-- Eighths of a turn a second. Three turns a second reads as a spin at eight
-- steps a turn and not as a flicker; any faster and the drawing is a blur of
-- eight drawings rather than one thing going round.
local SPIN = 24

-- How close to your middle counts as caught. Your own half-width and a little,
-- so it is caught at your hand rather than having to fly through your chest.
local CATCH = 9

-- The longest one may be in the air at all. Twice what the longest throw takes,
-- which is never reached by a boomerang that is doing its job.
local LOST = 6

-- How far apart two thrown together leave, in radians. Enough that their far ends
-- are two places rather than one smudge, and not so much that the pair stops
-- being aimed at the thing it was thrown at.
local FAN = 0.45

-- How long to wait before looking again when there is nothing to throw at.
local LOOK = 0.25

function Boomerang.new()
    return setmetatable({
        def = nil,
        cool = 0,   -- 0, so taking the level throws one at once
        live = {},
    }, Boomerang)
end

function Boomerang:configure(def)
    self.def = def
end

--- throwing ------------------------------------------------------------------

-- `count` of them at the nearest thing in reach, fanned either side of the line
-- to it. Returns false when there is nothing to throw at, which holds the clock
-- rather than spending it. Everything a throw needs is copied onto it here, the
-- rocket's rule: a level taken mid-flight changes the next one.
function Boomerang:throw(game)
    local def = self.def
    local player = game.player
    local target = game:nearestEnemy(player.x, player.y, def.range * 1.5)
    if not target then return false end

    local stats = game.loadout.stats
    local damage = def.damage * stats.passiveDamage * stats.damage
    local aim = math.atan2(target.y - player.y, target.x - player.x)

    for i = 1, def.count do
        local a = aim + (i - (def.count + 1) / 2) * FAN
        local dx, dy = math.cos(a), math.sin(a)

        self.live[#self.live + 1] = {
            x = player.x, y = player.y - 1,
            dx = dx, dy = dy,
            speed = def.speed,
            -- What slows it to a stop exactly `range` out: v^2 = 2 a d.
            brake = def.speed * def.speed / (2 * def.range),
            out = true,
            damage = damage,
            back = damage * def.back,
            age = 0,
            spin = love.math.random(8) - 1,
            hit = {},
        }
    end

    return true
end

--- flying --------------------------------------------------------------------

-- Everything it passes, once a way. The list is emptied at the turn, which is
-- the whole of what makes the way back worth anything: a crowd it went through
-- going out is a crowd it goes through again coming home.
function Boomerang:cut(b, game)
    local damage = b.out and b.damage or b.back

    game:eachWithin(b.x, b.y, REACH, function(e)
        if b.hit[e] or e.ghost then return end
        local reach = HIT + e.radius
        local dx, dy = e.x - b.x, e.y - b.y
        if dx * dx + dy * dy >= reach * reach then return end

        b.hit[e] = true
        game.particles:burst(e.x, e.y, 2, Palette.red)
        if e:hurt(damage) then
            game:killEnemyAt(e)
        end
    end)
end

-- One step of one boomerang. Returns true once it is home.
function Boomerang:fly(b, dt, game)
    local player = game.player
    b.age = b.age + dt
    b.spin = (b.spin + SPIN * dt) % 8

    if b.out then
        b.speed = b.speed - b.brake * dt
        if b.speed <= 0 then
            b.speed = 0
            b.out = false
            b.hit = {}
        end
    else
        -- Home is where you are now, asked every frame: that is the weapon.
        local dx, dy, dist = util.normalize(player.x - b.x, player.y - 1 - b.y)
        if dist <= CATCH then return true end
        b.dx, b.dy = dx, dy
        b.speed = math.min(self.def.speed, b.speed + b.brake * dt)
    end

    b.x = b.x + b.dx * b.speed * dt
    b.y = b.y + b.dy * b.speed * dt
    self:cut(b, game)

    return b.age >= LOST
end

function Boomerang:update(dt, game, grid)
    local caught = false

    for i = #self.live, 1, -1 do
        if self:fly(self.live[i], dt, game) then
            table.remove(self.live, i)
            caught = true
        end
    end

    -- The clock runs only with nothing in the air, so it starts from the catch:
    -- meet it halfway and the next throw comes sooner. At the finale a catch
    -- with the rest of the volley home throws again on the spot.
    if #self.live > 0 then return end
    if caught and self.def.catch then self.cool = 0 end

    self.cool = self.cool - dt
    if self.cool <= 0 then
        self.cool = self:throw(game) and self.def.every or LOOK
    end
end

--- drawing -------------------------------------------------------------------

-- Over the crowd, since it is in the air, one of the eight headings at a time.
function Boomerang:draw(game)
    local ring = Sprites.turned.boomerang
    if not ring then return end

    love.graphics.setColor(1, 1, 1)
    for _, b in ipairs(self.live) do
        ring[math.floor(b.spin) + 1]:draw(b.x, b.y)
    end
end

return Boomerang
