-- The tesseract boss's body: a cube of cubes, turned in four dimensions and
-- shown on the page as lines.
--
-- A tesseract is sixteen corners, every one of them (+-1, +-1, +-1, +-1), and
-- thirty-two edges, one between every two corners that differ in one place.
-- Each frame the corners are turned in two of the planes that use the fourth
-- axis -- x with w, and z with w -- and then seen in perspective down w, the
-- way a cube is seen in perspective down z: a corner with more w is nearer the
-- eye that sees four dimensions, and drawn bigger. That is the whole of why it
-- looks like a cube inside a cube. Turn x into w and the inner cube flows out
-- through the faces of the outer one and becomes it, which is the picture
-- everybody knows and the move the brain is named after (src/tesseractboss.lua's
-- inside-out: it asks for half a turn more, quickly, through `flip`).
--
-- What comes out of that is an ordinary solid in three dimensions, and from
-- there it is shown the way every body here is: turned slowly about the upright
-- and looked down on from a little above, so the top of it is in view.
--
-- Drawn as lines, as BOSSIDEAS.md allows, because a tesseract has no faces you
-- could paint that would still let the inner cube be seen -- and lines at any
-- angle are what `pixelart.line` is for. The edges are put down back to front,
-- the far ones slate and the near ones ink, and the eight struts that run along
-- w (from a corner of one cube to the same corner of the other) are red: they
-- are the part of it no cube has, so they are the part that is the enemy's
-- colour. Inside the silhouette, the cube that started out further along w is
-- dithered blush, a heart you can watch being turned inside out.
--
-- The silhouette is the convex hull of the sixteen corners, filled a row at a
-- time (`pixelart.fillPolygon`): the blank under it, the hit's rim and the
-- flash are all that one shape, so a hit lights the whole of what you see.
--
-- Nothing here is a hitbox; the brain hurts things off the page, and the body
-- is hit on its round `radius` like any other.

local Palette = require("src.palette")
local pixelart = require("src.pixelart")

local Tesseract = {}
Tesseract.__index = Tesseract

local floor, sin, cos, sqrt, max, min = math.floor, math.sin, math.cos, math.sqrt, math.max, math.min
local TAU = math.pi * 2

-- How high it floats over its shadow, and the bob on top. It hovers for the
-- atom's reason: nothing about a four-dimensional thing stands on anything.
local HOVER, BOB = 6, 1.5

-- The four-dimensional eye's distance down w. Nearer makes the inner cube
-- smaller against the outer one: 3 puts it at half, which reads as a cube
-- inside a cube without the inner one shrinking to a knot.
local DEPTH = 3

-- How far the view looks down, radians, so the top of the solid is in sight.
local TILT = 0.42

-- Pixels per unit. A corner sits about 1.7 units out and is drawn up to about
-- half as far again by the perspective, so this is a body about 40 across.
local SCALE = 11

local ink, slate, paper, graphite = Palette.ink, Palette.slate, Palette.paper, Palette.graphite
local red, blush = Palette.red, Palette.blush

-- The sixteen corners, and the thirty-two edges as pairs of them with the axis
-- they run along (4 is w: a strut).
local CORNERS, EDGES = {}, {}
for i = 0, 15 do
    CORNERS[i + 1] = { i % 2 * 2 - 1, floor(i / 2) % 2 * 2 - 1,
                       floor(i / 4) % 2 * 2 - 1, floor(i / 8) % 2 * 2 - 1 }
end
for i = 0, 15 do
    for b = 0, 3 do
        local bit = 2 ^ b
        if floor(i / bit) % 2 == 0 then
            EDGES[#EDGES + 1] = { i + 1, i + bit + 1, axis = b + 1 }
        end
    end
end
Tesseract.CORNERS = CORNERS

function Tesseract.new()
    local self = setmetatable({
        t = love.math.random() * 10,
        -- The two four-dimensional turns, and the ordinary one about the
        -- upright. `flip` is extra x-into-w turn the brain asks for.
        xw = love.math.random() * TAU, zw = love.math.random() * TAU,
        yaw = love.math.random() * TAU, flip = 0,
        -- Written by the brain: how hurt it is (which spins it faster), how
        -- hard it shivers, how much of it is left in our three dimensions
        -- (`fold`, 0 when it has turned clean out of the page), and which
        -- corners are blinking red because they are about to be thrown.
        hurt = 0, shake = 0, jx = 0, fold = 1, spin = 1, hot = nil,
        hidden = false,
        -- Where the shadow goes (Enemy:draw).
        ground = 17,
        -- The projected corners, offsets from the middle: x, y and depth.
        px = {}, py = {}, pz = {},
        hull = {},
        glitch = nil,
    }, Tesseract)
    self:project()
    return self
end

--- the motion -----------------------------------------------------------------

-- One frame: it turns, faster the more it is hurt (and faster still when the
-- brain winds `spin` up), and the projection is worked out once for the three
-- things that draw it this frame.
function Tesseract:update(dt)
    if dt <= 0 then return end
    self.t = self.t + dt
    local w = (1 + self.hurt * 1.4) * self.spin
    self.xw = (self.xw + 0.55 * w * dt) % TAU
    self.zw = (self.zw + 0.31 * w * dt) % TAU
    self.yaw = (self.yaw + 0.4 * w * dt) % TAU
    self.jx = self.shake > 0
        and floor((love.math.random() - 0.5) * 2 * self.shake + 0.5) or 0
    -- Badly hurt, it stops being quite in step with itself: now and then one
    -- edge is drawn a pixel or two off where it is, for a frame or three.
    if self.hurt > 0.6 and love.math.random() < dt * 6 then
        self.glitch = { edge = love.math.random(1, #EDGES),
                        dx = love.math.random(-2, 2), dy = love.math.random(-1, 1),
                        t = 0.05 + love.math.random() * 0.06 }
    elseif self.glitch then
        self.glitch.t = self.glitch.t - dt
        if self.glitch.t <= 0 then self.glitch = nil end
    end
    self:project()
end

function Tesseract:project()
    local c1, s1 = cos(self.xw + self.flip), sin(self.xw + self.flip)
    local c2, s2 = cos(self.zw), sin(self.zw)
    local cy, sy = cos(self.yaw), sin(self.yaw)
    local ct, st = cos(TILT), sin(TILT)
    local scale = SCALE * self.fold
    for i, v in ipairs(CORNERS) do
        local x, y, z, w = v[1], v[2], v[3], v[4]
        x, w = x * c1 - w * s1, x * s1 + w * c1
        z, w = z * c2 - w * s2, z * s2 + w * c2
        local k = DEPTH / (DEPTH - w)
        x, y, z = x * k, y * k, z * k
        x, z = x * cy + z * sy, z * cy - x * sy
        self.px[i] = x * scale
        self.py[i] = -(y * ct - z * st) * scale
        self.pz[i] = z * ct + y * st
    end
    self.hull = Tesseract.hullOf(self.px, self.py)
end

-- The convex hull of the points, as flat pairs (pixelart.fillPolygon's shape):
-- the monotone chain, which for sixteen points is nothing.
function Tesseract.hullOf(xs, ys, only)
    local idx = {}
    for i = 1, #xs do
        if not only or only[i] then idx[#idx + 1] = i end
    end
    table.sort(idx, function(a, b)
        if xs[a] ~= xs[b] then return xs[a] < xs[b] end
        return ys[a] < ys[b]
    end)
    local function cross(o, a, b)
        return (xs[a] - xs[o]) * (ys[b] - ys[o]) - (ys[a] - ys[o]) * (xs[b] - xs[o])
    end
    local lower, upper = {}, {}
    for _, i in ipairs(idx) do
        while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], i) <= 0 do
            lower[#lower] = nil
        end
        lower[#lower + 1] = i
    end
    for n = #idx, 1, -1 do
        local i = idx[n]
        while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], i) <= 0 do
            upper[#upper] = nil
        end
        upper[#upper + 1] = i
    end
    local poly = {}
    for n = 1, #lower - 1 do
        poly[#poly + 1] = xs[lower[n]]
        poly[#poly + 1] = ys[lower[n]]
    end
    for n = 1, #upper - 1 do
        poly[#poly + 1] = xs[upper[n]]
        poly[#poly + 1] = ys[upper[n]]
    end
    return poly
end

--- where things are -------------------------------------------------------------

-- The middle of it on the screen, off where the body is standing: up off its
-- shadow by the hover and the bob.
function Tesseract:centre(x, y)
    return floor(x) + self.jx + 0.5,
        floor(y) + 0.5 - HOVER - floor(BOB * sin(self.t * 2.1) + 0.5)
end

-- Corner `i` on the screen, and how near you it is.
function Tesseract:corner(i, x, y)
    local cx, cy = self:centre(x, y)
    return cx + self.px[i], cy + self.py[i], self.pz[i]
end

-- How far out a corner is from the middle on the page, as a share of the
-- furthest: the brain throws the outer corners faster than the inner ones.
function Tesseract:reachOf(i)
    local far = 1e-6
    for k = 1, #CORNERS do
        far = max(far, self.px[k] * self.px[k] + self.py[k] * self.py[k])
    end
    return sqrt((self.px[i] * self.px[i] + self.py[i] * self.py[i]) / far)
end

function Tesseract:shadowScale()
    return self.fold
end

--- drawing ----------------------------------------------------------------------

-- Every span of the silhouette, moved by (ox, oy).
local function fillHull(poly, cx, cy, ox, oy)
    if #poly < 6 then return end
    local moved = {}
    local y0, y1 = math.huge, -math.huge
    for n = 1, #poly, 2 do
        moved[n] = poly[n] + cx + ox
        moved[n + 1] = poly[n + 1] + cy + oy
        y0, y1 = min(y0, moved[n + 1]), max(y1, moved[n + 1])
    end
    pixelart.fillPolygon(moved, y0, y1, function(x, y, w)
        love.graphics.rectangle("fill", x, y, w, 1)
    end)
end

-- The silhouette, `pad` out, in whatever colour is set: the blank stamped under
-- it, a hit's rim, the flash.
function Tesseract:drawMask(x, y, pad)
    if self.hidden or self.fold < 0.05 then return end
    local cx, cy = self:centre(x, y)
    pad = pad or 0
    fillHull(self.hull, cx, cy, 0, 0)
    if pad > 0 then
        fillHull(self.hull, cx, cy, -pad, 0)
        fillHull(self.hull, cx, cy, pad, 0)
        fillHull(self.hull, cx, cy, 0, -pad)
        fillHull(self.hull, cx, cy, 0, pad)
    end
end

-- The heart: the cube that started furthest along w, dithered in.
local HEART = {}
for i, v in ipairs(CORNERS) do HEART[i] = v[4] > 0 end

local order = {}

function Tesseract:draw(x, y)
    if self.hidden or self.fold < 0.05 then return end
    local cx, cy = self:centre(x, y)
    local px, py, pz = self.px, self.py, self.pz

    -- The heart, every other pixel, blush and then red as it is hurt.
    local heart = Tesseract.hullOf(px, py, HEART)
    if #heart >= 6 then
        local moved = {}
        local y0, y1 = math.huge, -math.huge
        for n = 1, #heart, 2 do
            moved[n], moved[n + 1] = heart[n] + cx, heart[n + 1] + cy
            y0, y1 = min(y0, moved[n + 1]), max(y1, moved[n + 1])
        end
        love.graphics.setColor(self.hurt > 0.66 and red or blush)
        local every = self.hurt > 0.33 and 2 or 3
        pixelart.fillPolygon(moved, y0, y1, function(sx, sy, w)
            for px0 = sx, sx + w - 1 do
                if (px0 + sy) % every == 0 then love.graphics.rectangle("fill", px0, sy, 1, 1) end
            end
        end)
    end

    -- The silhouette's rim, so it reads as a thing over the page and not a
    -- drawing on it.
    love.graphics.setColor(ink)
    local hull = self.hull
    for n = 1, #hull, 2 do
        local m = n + 2 > #hull and 1 or n + 2
        pixelart.line(cx + hull[n], cy + hull[n + 1], cx + hull[m], cy + hull[m + 1])
    end

    -- The edges, back to front.
    for k = 1, #EDGES do order[k] = k end
    for k = #EDGES + 1, #order do order[k] = nil end
    table.sort(order, function(a, b)
        local ea, eb = EDGES[a], EDGES[b]
        return pz[ea[1]] + pz[ea[2]] < pz[eb[1]] + pz[eb[2]]
    end)
    local g = self.glitch
    for _, k in ipairs(order) do
        local e = EDGES[k]
        local i, j = e[1], e[2]
        local front = pz[i] + pz[j] >= 0
        local colour
        if e.axis == 4 then
            colour = front and red or blush
        else
            colour = front and ink or slate
        end
        local ox, oy = 0, 0
        if g and g.edge == k then ox, oy, colour = g.dx, g.dy, red end
        love.graphics.setColor(colour)
        pixelart.line(cx + px[i] + ox, cy + py[i] + oy, cx + px[j] + ox, cy + py[j] + oy)
    end

    -- The corners: a bead each, the near ones bigger. A corner the brain is
    -- about to throw blinks red (`hot`).
    local blink = floor(self.t * 12) % 2 == 0
    for i = 1, #CORNERS do
        local sx, sy = floor(cx + px[i]), floor(cy + py[i])
        local hot = self.hot and self.hot[i]
        if hot then
            Tesseract.vertex(sx, sy, blink)
        elseif pz[i] >= 0 then
            love.graphics.setColor(ink)
            love.graphics.rectangle("fill", sx - 1, sy - 1, 3, 3)
            love.graphics.setColor(paper)
            love.graphics.rectangle("fill", sx, sy, 1, 1)
        else
            love.graphics.setColor(graphite)
            love.graphics.rectangle("fill", sx, sy, 2, 2)
        end
    end
end

-- A corner about to leave: a red diamond in an ink rim, the same drawing as
-- the corner in the air (Sprites.vertex), so what is thrown is what blinked.
function Tesseract.vertex(x, y, on)
    x, y = floor(x), floor(y)
    love.graphics.setColor(ink)
    love.graphics.rectangle("fill", x - 1, y - 2, 3, 5)
    love.graphics.rectangle("fill", x - 2, y - 1, 5, 3)
    love.graphics.setColor(on and red or blush)
    love.graphics.rectangle("fill", x - 1, y - 1, 3, 3)
    love.graphics.setColor(on and blush or paper)
    love.graphics.rectangle("fill", x, y, 1, 1)
end

return Tesseract
