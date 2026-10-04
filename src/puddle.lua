-- A blot of ground that has stopped being neutral: the eye boss's wet trail,
-- dropped on a clock as it moves (Game:updateEnemies), and a bomb's burn
-- (src/bomb.lua). Who it hurts is the owner's business, not this module's: the
-- boss's hurts the player (Game:updatePuddles), a bomb's the crowd. The two
-- colours come off the spec so a burn of yours is the same blot in the other
-- half of the palette. Nothing is stored per pixel -- the ragged rim and the
-- speckle are `util.hash01` of the offset and the seed, so a puddle is five
-- numbers however many pixels it covers.
--
-- The boss's blot hurts by standing in it, rate-limited by the player's own
-- invulnerability window (Player:hurt), so living in one is a hit every 0.6s. A
-- bomb's burn needs a clock of its own: nothing in the crowd has that window.

local Palette = require("src.palette")
local util = require("src.util")

local Puddle = {}
Puddle.__index = Puddle

local RIPPLE = 0.45    -- how long a ring takes to cross it
local GLINT_TILL = 0.4 -- of its life it shines for, while it is still wet
local DROPS_DRY = 0.35 -- of its life the thrown droplets last: they are thin
local FILL = 0.24      -- of the inside is left dry, so it reads as spatter
local DRY_FROM = 0.55  -- of its life at full wet; after that it dithers away
local RIM_DRY = 0.75   -- and the pooled rim gives its darker colour up at

-- `damage` and `reach` are handed in rather than read off `def`: they are the
-- dropping enemy's scaled numbers (`reach` in Enemy.new), and the puddle keeps
-- what it was dropped with. `reach` defaults because most callers -- a bomb's
-- burn, an ordinary bulb -- have no opinion; `def.fill`/`def.rim` default to
-- the boss's colours.
--
-- Three optional fields on `def` shape it, all of them the eye boss's
-- (src/eyeball.lua): `stretch` with a direction `dx, dy` draws it long along the
-- way the thing was going -- the streak a roll leaves -- and `drops` throws that
-- many droplets round the outside, which is what makes a landing a splat rather
-- than a spill. Droplets are drawing and never hurt: the blot is the hitbox.
function Puddle.new(x, y, def, damage, seed, reach)
    local r = def.radius * (reach or 1)
    local stretch = def.stretch or 1
    local ux, uy = def.dx or 1, def.dy or 0
    if ux == 0 and uy == 0 then ux = 1 end
    local self = setmetatable({
        x = math.floor(x), y = math.floor(y),
        r = r,
        -- The two half-axes: `a` along (ux, uy), `b` across it.
        a = r * stretch, b = r, ux = ux, uy = uy,
        rippleT = 0,
        -- Only the wet ones shine. A bomb's burn is the same blot in your colours
        -- (src/bomb.lua) and a crater does not glint.
        shine = def.fill == nil,
        damage = damage,
        fill = def.fill or Palette.blush,
        rim = def.rim or Palette.red,
        life = def.life,
        age = 0,
        seed = seed,
    }, Puddle)

    -- How tall it is, and the row coefficients of the tilted ellipse that the
    -- spans are read off (Puddle:span) -- worked out once, since a puddle never
    -- changes shape, only dries.
    local ia, ib = 1 / (self.a * self.a), 1 / (self.b * self.b)
    self.qa = ux * ux * ia + uy * uy * ib
    self.qb = 2 * ux * uy * (ia - ib)
    self.qc = uy * uy * ia + ux * ux * ib
    self.tall = math.floor(math.sqrt(self.a * self.a * uy * uy + self.b * self.b * ux * ux))

    self.drops = {}
    for i = 1, def.drops or 0 do
        local ang = util.hash01(i, seed, 21) * math.pi * 2
        local out = 2 + util.hash01(i, seed, 22) * 6
        local c, sn = math.cos(ang), math.sin(ang)
        -- Out to the rim along that bearing, then a little further.
        local rim = 1 / math.sqrt(self.qa * c * c + self.qb * c * sn + self.qc * sn * sn)
        self.drops[i] = {
            x = math.floor(c * (rim + out) + 0.5), y = math.floor(sn * (rim + out) + 0.5),
            big = util.hash01(i, seed, 23) < 0.4,
        }
    end
    return self
end

-- Something landed in it, or near it: a ring crosses it.
function Puddle:ripple()
    self.rippleT = RIPPLE
end

function Puddle:update(dt)
    self.age = self.age + dt
    self.rippleT = math.max(0, self.rippleT - dt)
    return self.age < self.life
end

function Puddle:covers(x, y)
    local dx, dy = x - self.x, y - self.y
    return self.qa * dx * dx + self.qb * dx * dy + self.qc * dy * dy <= 1
end

-- Where the blot starts and how wide it is on one row, rim included, or nil:
-- the tilted ellipse cut by the row, then jittered per row off the seed, so a
-- puddle is a blot rather than a disc. A round one comes out exactly as the
-- disc this used to be, centred and symmetric.
function Puddle:span(dy)
    local A, B, C = self.qa, self.qb * dy, self.qc * dy * dy - 1
    local disc = B * B - 4 * A * C
    if disc < 0 then return end
    local half = math.sqrt(disc) / (2 * A)
    local mid = math.floor(-B / (2 * A) + 0.5)
    local w = math.floor(half + util.hash01(dy, self.seed, 5) * 1.8 - 0.4)
    if w < 0 then return end
    return mid - w, mid + w
end

function Puddle:draw()
    local dried = self.age / self.life
    -- Dithering out rather than fading: alpha would blend paper and ink into a
    -- ninth colour and break the overprint lookup.
    local drop = dried > DRY_FROM and (dried - DRY_FROM) / (1 - DRY_FROM) or 0

    love.graphics.setColor(self.fill)
    for dy = -self.tall, self.tall do
        local x0, x1 = self:span(dy)
        if x0 then
            for dx = x0, x1 do
                local h = util.hash01(dx, dy, self.seed)
                if h > FILL + (1 - FILL) * drop then
                    love.graphics.rectangle("fill", self.x + dx, self.y + dy, 1, 1)
                end
            end
        end
    end

    -- The rim, where a spill pools and dries darkest, makes the edge readable,
    -- so it is the last thing to go: darker colour for three quarters of the
    -- life, then it steps down to the fill.
    love.graphics.setColor(dried < RIM_DRY and self.rim or self.fill)
    for dy = -self.tall, self.tall do
        local x0, x1 = self:span(dy)
        if x0 and util.hash01(dy, self.seed, 11) > drop then
            love.graphics.rectangle("fill", self.x + x0, self.y + dy, 1, 1)
            love.graphics.rectangle("fill", self.x + x1, self.y + dy, 1, 1)
        end
    end

    -- The droplets a splat threw, in the rim colour, and gone first: a drop that
    -- size dries before the pool it came out of.
    if dried < DROPS_DRY then
        for _, d in ipairs(self.drops) do
            love.graphics.rectangle("fill", self.x + d.x, self.y + d.y,
                d.big and 2 or 1, d.big and 2 or 1)
        end
    end

    -- A ring crossing it from the middle out, when something has landed in or
    -- beside it. In the rim colour and every other pixel, so it reads as the
    -- surface moving rather than as a second, smaller puddle.
    if self.rippleT > 0 then
        local rr = math.floor(self.r * (1 - self.rippleT / RIPPLE)) + 1
        for k = 0, 23 do
            if k % 2 == 0 then
                local ang = k / 24 * math.pi * 2
                local px = math.floor(math.cos(ang) * rr * self.a / self.r + 0.5)
                local py = math.floor(math.sin(ang) * rr + 0.5)
                love.graphics.rectangle("fill", self.x + px, self.y + py, 1, 1)
            end
        end
    end

    -- Wet: a glint of paper up and to the left, the same light the eye is lit
    -- from (src/eyeball.lua), for as long as it is fresh. What says a blot is
    -- still something to step round, before the dither says it is going.
    if self.shine and dried < GLINT_TILL and self.r >= 7 then
        love.graphics.setColor(Palette.paper)
        local gx = self.x - math.floor(self.r * 0.35)
        local gy = self.y - math.floor(self.r * 0.35)
        love.graphics.rectangle("fill", gx, gy, 2, 1)
        love.graphics.rectangle("fill", gx - 1, gy + 1, 1, 1)
    end
end

return Puddle
