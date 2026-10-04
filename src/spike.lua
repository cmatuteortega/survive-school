-- A jack lying on the page: the spiky thing the P.E. whistle throws (`jacks` in
-- src/enemy.lua). It flies as an ordinary piece of enemy fire and becomes one of
-- these where it lands (Game:updateEnemyShots), so the ground round where you
-- were standing fills up with things you must not walk onto.
--
-- It is a puddle with corners, and deliberately so: it hurts by being stood on,
-- rate-limited by the player's own invulnerability window (Player:hurt) exactly
-- as a puddle is, so walking through three is one hit and standing on one is a
-- hit every six tenths of a second. What it is *not* is wet. A puddle is a blot
-- you can see the extent of and that dries away from the edges; a jack is a
-- small hard object with a small hard edge, so it is a sprite and a radius, and
-- it goes by blinking out for its last second rather than by drying.
--
-- Small on purpose -- four pixels -- because there are a lot of them and the
-- room between them is the whole of the counterplay: a scatter of jacks you can
-- thread is a scatter you read, and one you cannot is a wall.

local Sprites = require("src.sprites")

local Spike = {}
Spike.__index = Spike

-- How long before the end it starts blinking, and how fast. Blinking rather
-- than dithering, because what it is saying is "about to be gone", which is a
-- warning about an object rather than a fade on a stain.
local BLINK_FROM = 1.0
local BLINK_RATE = 10

-- `damage` and `reach` are handed in for the puddle's reason: they are the
-- throwing enemy's scaled numbers, and a jack keeps what it was thrown with.
function Spike.new(x, y, def, damage, reach)
    return setmetatable({
        x = math.floor(x), y = math.floor(y),
        r = def.radius * (reach or 1),
        grow = reach or 1,
        damage = damage,
        life = def.life,
        age = 0,
    }, Spike)
end

function Spike:update(dt)
    self.age = self.age + dt
    return self.age < self.life
end

function Spike:covers(x, y, pad)
    local dx, dy = x - self.x, y - self.y
    local r = self.r + (pad or 0)
    return dx * dx + dy * dy <= r * r
end

function Spike:draw()
    local left = self.life - self.age
    if left < BLINK_FROM and math.floor(left * BLINK_RATE) % 2 == 0 then return end
    love.graphics.setColor(1, 1, 1)
    Sprites.jack:draw(self.x, self.y, nil, self.grow)
end

return Spike
