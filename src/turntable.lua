-- A boss on a turntable: its body, taken out of the fight and turned round once
-- every few seconds so the library can show all of it (src/library.lua).
--
-- **It is the fight's own body and not a picture of one.** Every boss here is
-- already a thing that can be seen from any side -- the eye, the die, the atom,
-- the pig and the rest are painted a pixel at a time off a frame that turns, and
-- the whistle, the metronome, the stamp, the dictionary and the marble were
-- ray-traced into a ring of views ahead of time (3dmethod.md) -- so a turntable is
-- nothing more than that frame turned at a steady rate with no brain behind it.
-- Drawing them from anything else would be the library keeping a second copy of
-- fourteen drawings that could quietly stop matching the page they come from.
--
-- **Which kind of body is read off the row** (src/enemy.lua), the way `Enemy.new`
-- reads it: `pupil` is the eye, `dice` the die, `still` the still life, `turns` a
-- ring of baked views, and so on. So a new boss built on one of these bodies is
-- on the turntable by being one, and a new *kind* of body is one more line in
-- `make` below -- the same place it is one more line in `Enemy.new`.
--
-- **How each is turned** is the body's own idea of turning, because they do not
-- share one. A sphere, a die and a table of plaster turn about the upright; the
-- pig, the can and the speaker turn on the spot the way they turn to face you;
-- the atom and the tesseract are already turning and are simply let run; the red
-- pen, which is longer than the page, is stood up and turned in its fingers, so
-- what goes round is the clip and the print -- and the top of it goes off the top
-- of the box, which is the point of it.
--
-- **And it can be drawn as a silhouette**: the body's own mask in one colour,
-- which is how the library shows a boss it has not seen go down. The same mask the
-- game stamps under a body and flashes it with, so the shape the silhouette has is
-- the shape the boss has, to the pixel, from whichever side it is facing.
--
-- Everything is drawn standing on a floor line, with the shadow the fight gives it
-- (Enemy:draw's own expression), so fourteen things of different heights all read
-- as standing on the same page.

local Palette = require("src.palette")
local Sprites = require("src.sprites")
local Enemy = require("src.enemy")
local Overprint = require("src.overprint")
local Eyeball = require("src.eyeball")
local Dice = require("src.dice")
local Plaster = require("src.plaster")
local StillLife = require("src.stilllife")
local Atom = require("src.atom")
local Piggy = require("src.piggy")
local Tesseract = require("src.tesseract")
local Speaker = require("src.speaker")
local RedPen = require("src.redpen")
local Deodorant = require("src.deodorant")
local Metronome = require("src.metronome")

local Turntable = {}
Turntable.__index = Turntable

local TAU = math.pi * 2
local floor, sin, cos = math.floor, math.sin, math.cos

-- One turn every this many seconds. Slow enough that a ring of sixteen baked
-- views reads as a turn rather than a flicker -- a view a third of a second --
-- and quick enough that you see the back of a thing before you have looked away.
local PERIOD = 6
local SPIN = TAU / PERIOD

-- How far the red pen is clicked out on the turntable: all the way, so the tip
-- that it writes with is on show.
local PEN_TIP = 1

--- what it is ----------------------------------------------------------------

-- The body a row is drawn as, and how it turns: `turn(self, dt)` moves it on,
-- and the rest of this file draws it. `painted` is a body with the painted
-- bodies' shared shape -- `draw(x, y)`, `drawMask(x, y, pad)`, `shadowScale` and
-- an optional `ground` (Enemy:draw) -- and `views` a ring of baked sprites.
local function make(self, def)
    if def.pupil then
        local eye = Eyeball.new()
        self.eye = eye
        -- Turned about the screen's own upright, so the iris goes round the
        -- side of the ball and comes back the other: the eye looked at from all
        -- the way round.
        eye.wy = SPIN
        self.turn = function(_, dt) eye:spin(dt) end
    elseif def.dice then
        local die = Dice.new(def.dice.shapes[1])
        self.painted = die
        self.turn = function(_, dt) die:turn(0, 0, 1, SPIN * dt) end
    elseif def.still then
        -- The whole table turned about its middle: every piece round the
        -- upright, and the cube on its own as well, so it keeps its face to the
        -- table rather than sliding round it. The lamp stays where it is, so
        -- the light goes round the pieces as they turn.
        local body = StillLife.body()
        self.painted = body
        self.turn = function(_, dt)
            local a = SPIN * dt
            local c, s = cos(a), sin(a)
            for _, p in ipairs(body.pieces) do
                if p.kind == "cone" then
                    local apex = p.apex
                    apex[1], apex[2] = apex[1] * c - apex[2] * s, apex[1] * s + apex[2] * c
                else
                    p.x, p.y = p.x * c - p.y * s, p.x * s + p.y * c
                    if p.kind == "cube" then Plaster.turn(p, 0, 0, 1, a) end
                end
            end
            body:touch()
        end
    elseif def.atom then
        local a = def.atom
        local atom = Atom.new(a.size, a.rings, a.first, a.step)
        self.painted = atom
        self.turn = function(_, dt) atom:update(dt) end
    elseif def.piggy then
        local pig = Piggy.new()
        self.painted = pig
        self.turn = function(_, dt)
            pig.yaw = (pig.yaw + SPIN * dt) % TAU
            pig.dirty = true
        end
    elseif def.tesseract then
        local cube = Tesseract.new()
        self.painted = cube
        self.turn = function(_, dt) cube:update(dt) end
    elseif def.speaker then
        local can = Speaker.new()
        self.painted = can
        self.turn = function(_, dt)
            can:spin(SPIN * dt)
            can:update(dt)
        end
    elseif def.redpen then
        local pen = RedPen.new()
        pen.tip = PEN_TIP
        self.pen = pen
        self.turn = function(_, dt)
            pen.roll = (pen.roll + SPIN * dt) % TAU
            pen.dirty = true
        end
    elseif def.deodorant then
        local can = Deodorant.new()
        self.painted = can
        self.turn = function(_, dt)
            can:spin(SPIN * dt)
            can:update(dt)
        end
    elseif def.turns then
        -- A ring of baked views (3dmethod.md): the turn is which of them is up.
        -- Read off the row's `turns`, which is the ring the fight turns through
        -- -- the stamp standing, the dictionary shut, the marble a block.
        self.views = Sprites[def.turns]
        self.turn = function() end
        -- The metronome's pendulum is plotted live rather than baked, so it is
        -- swung here on a clock of its own, at the slowest tempo the fight
        -- plays at: the brain it is borrowed from reads only that and a state.
        if def.metronome then
            self.arm = setmetatable({ def = def.metronome, clock = 0, state = "walk" },
                Metronome)
        end
    else
        -- Anything else is its sprite and does not turn: a boss drawn as one
        -- flat picture is the same from every side.
        self.flat = Sprites.enemies[def.sprite]
        self.turn = function() end
    end
end

function Turntable.new(kind)
    local def = Enemy.types[kind]
    local self = setmetatable({ kind = kind, def = def, t = 0, angle = 0 }, Turntable)
    make(self, def)
    return self
end

function Turntable:update(dt)
    if dt <= 0 then return end
    self.t = self.t + dt
    self.angle = (self.angle + SPIN * dt) % TAU
    if self.arm then
        local beat = 60 / self.def.metronome.tempo[1]
        self.arm.clock = self.t / beat
    end
    self:turn(dt)
end

--- where it stands -----------------------------------------------------------

-- Which view of a ring is up: the one the turn has reached.
function Turntable:view()
    local n = #self.views
    return floor(self.angle / TAU * n + 0.5) % n + 1
end

-- The sprite a body is drawn from, where it is drawn from one.
function Turntable:sprite()
    if self.views then return self.views[self:view()] end
    return self.flat or Sprites.enemies[self.def.sprite]
end

-- How far below the point a body is drawn at its feet are: Enemy:draw's own
-- expression for where the shadow goes, so the body stands where the fight would
-- stand it. The pen's nib is `NIBY` below its point, which is that body's word for
-- the same thing.
function Turntable:ground()
    if self.pen then return RedPen.NIBY end
    local painted = self.painted
    if painted and painted.ground then return painted.ground end
    if self.def.ground then return self.def.ground end
    local sprite = self:sprite()
    return sprite.h - sprite.oy
end

-- The pen, cut to the rows and columns between `top` and `bottom` on the
-- canvas: the box it is shown in. Its own drawing cuts it to the camera instead,
-- and there is no camera here.
local function penRows(pen, x, y, top, bottom, left, right)
    local ox, oy = floor(x), floor(y) + RedPen.NIBY
    return pen:raster(left - ox, top - oy, right - ox, bottom - oy), ox, oy
end

local function drawRuns(rows, ox, oy, colour)
    local cur
    for _, row in ipairs(rows) do
        for _, run in ipairs(row.runs) do
            local c = colour or run[3]
            if c ~= cur then
                cur = c
                love.graphics.setColor(c)
            end
            love.graphics.rectangle("fill", ox + run[1], oy + row.j, run[2] - run[1], 1)
        end
    end
end

-- The atom's orbits, dotted in one colour: they are not part of its mask (the
-- fight keeps the ruling under them), and an atom's silhouette without them is a
-- ball.
local function orbits(atom, x, y)
    local cx, cy = atom:centre(x, y)
    for _, ring in ipairs(atom.rings) do
        local n = Atom.steps(ring.r)
        for i = 0, n - 1, 3 do
            local px, py = Atom.point(ring, i / n * TAU)
            love.graphics.rectangle("fill", floor(cx + px), floor(cy + py), 1, 1)
        end
    end
end

-- The mask, in whatever colour is set.
function Turntable:drawMask(x, y, clip)
    if self.eye then
        self.eye:drawMask(x, y, 0)
    elseif self.painted then
        self.painted:drawMask(x, y, 0)
    elseif self.pen then
        local rows, ox, oy = penRows(self.pen, x, y, clip[2], clip[4], clip[1], clip[3])
        local r, g, b = love.graphics.getColor()
        drawRuns(rows, ox, oy, { r, g, b })
    else
        self:sprite():drawMask(x, y)
        if self.arm then
            self.arm:drawArm({ view = self:view() }, x, y, { love.graphics.getColor() })
        end
    end
end

--- drawing -------------------------------------------------------------------

-- Standing with its feet on `floorY`, its middle at `cx`, cut to the box
-- (x0, y0, x1, y1) on the canvas. `seen` is whether it is drawn as itself; nil
-- draws it as its silhouette in `shape`.
--
-- Inside the ink pass of an overprint page (src/overprint.lua), and it stamps its
-- own blank into the page under it first, the way every body in a fight does:
-- the ruling stops where the body starts, so it comes out in the colours it was
-- drawn in -- and the silhouette comes out as one flat colour rather than as a
-- colour with lines through it.
function Turntable:draw(cx, floorY, box, seen, shape)
    local x = floor(cx)
    local y = floor(floorY) - self:ground() + 1
    local clip = box

    local sx, sy, sw, sh = love.graphics.getScissor()
    love.graphics.setScissor(box[1], box[2], box[3] - box[1], box[4] - box[2])

    -- The shadow, as the fight puts it down: graphite, as wide as the row says
    -- and as much of it as the body would leave. Not under a silhouette, which is
    -- all one colour on purpose.
    if seen then
        local scale = 1
        if self.eye then scale = self.eye:shadowScale() end
        if self.painted then scale = self.painted:shadowScale(0, false) end
        if self.pen then scale = self.pen:shadowScale() end
        local w = floor((self.def.shadow or 0) * scale + 0.5)
        if w > 0 then
            love.graphics.setColor(Palette.graphite)
            love.graphics.rectangle("fill", x - floor(w / 2), floor(floorY), w, 1)
        end
    end

    Overprint.beginSolid()
    love.graphics.setColor(Palette.paper)
    self:drawMask(x, y, clip)
    Overprint.endSolid()

    if not seen then
        love.graphics.setColor(shape or Palette.graphite)
        self:drawMask(x, y, clip)
        if self.def.atom then orbits(self.painted, x, y) end
    elseif self.eye then
        self.eye:draw(x, y)
    elseif self.painted then
        self.painted:draw(x, y)
    elseif self.pen then
        drawRuns(penRows(self.pen, x, y, clip[2], clip[4], clip[1], clip[3]))
    else
        local front = self.arm and Metronome.armInFront(self:view())
        if self.arm and not front then self.arm:drawArm({ view = self:view() }, x, y) end
        love.graphics.setColor(1, 1, 1)
        self:sprite():draw(x, y)
        if front then self.arm:drawArm({ view = self:view() }, x, y) end
    end

    if sx then
        love.graphics.setScissor(sx, sy, sw, sh)
    else
        love.graphics.setScissor()
    end
end

return Turntable
