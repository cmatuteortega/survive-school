-- The MATHS boss's body: a die, painted a pixel at a time off a real solid.
--
-- This is the eye's method (src/eyeball.lua) on a different shape, and the
-- shape is why it was chosen over the whistle's baked views (3dmethod.md). A
-- baked boss spends its sixteen pictures on *headings*, and a die has no front:
-- what it needs is to tumble, end over end in whichever direction it was thrown,
-- and come to rest on any face at all -- which sixteen fixed pictures cannot do
-- and a body painted fresh every frame does for nothing.
--
-- A die is also the easiest solid there is to paint this way. Every one of the
-- three it turns into is *convex*: a short list of flat faces, each a plane the
-- inside of the die is behind. So a pixel needs no sphere solved for it -- the
-- ray through it is cut by every plane, the near face is the last plane it
-- comes in through, and it is inside the die if it comes in before it goes out.
-- Twenty planes at most, a few hundred pixels across: about what the eye costs.
--
-- And flat faces suit eight colours better than anything round can. Each face
-- is one step of the ramp, lit off its own normal from the same light the eye
-- uses (up, to the left and in front, fixed on the screen), so the die turning
-- under it is faces trading places on the ramp rather than banding sliding over
-- a curve. The edges between faces are ink, found by asking which face the
-- next pixel along is on -- the one thing a flat-shaded solid needs to read as
-- a solid at this size, and the line the whole game is drawn with.
--
-- What *reads* is kept apart from what is solid, which is the whistle's lesson.
-- The d6's pips are round, and a circle on a face stays a readable dot however
-- it is foreshortened, so they are painted on the faces in 3D and come round
-- with the roll. A number does not survive perspective at three pixels by five,
-- so the d10 and the d20 carry theirs flat: the 3x5 face's digits stamped
-- square onto the screen over the middle of whichever face is on top, which
-- while it tumbles is a number flickering through values the way a real die's
-- does, and at rest is the roll.
--
-- The room is tilted, as the whistle's is: the die stands on a floor seen from
-- above and in front, so a die at rest shows its top face square on to the
-- light and one or two of its sides, and "the number on top" is something you
-- can see from where the player is looking rather than a convention.
--
-- Nothing here is a hitbox, the eye's rule again. How high it is in a bounce,
-- which way up it is and which solid it is are drawing; the boss is still
-- `Enemy.x/y/radius` to everything else on the page. How it is thrown, and when
-- it changes shape, is the brain's (src/diceboss.lua) -- the body only rolls
-- where it is pushed, settles when it is told to, and paints.

local Palette = require("src.palette")
local Font = require("src.font")

local Dice = {}
Dice.__index = Dice

local sqrt, floor, abs, cos, sin = math.sqrt, math.floor, math.abs, math.cos, math.sin

local function norm(x, y, z)
    local l = sqrt(x * x + y * y + z * z)
    return x / l, y / l, z / l
end

-- The room's tilt: how far the camera leans off looking straight down. The
-- whistle's number, for the whistle's reason -- enough to see the top and a
-- side, not so much that the near edge stretches away up the screen.
local PITCH = 0.6
local CP, SP = cos(PITCH), sin(PITCH)

-- The light, on the screen, and the eye's exactly: the two bosses that are
-- painted should look lit by the same window.
local LX, LY, LZ = norm(-0.48, -0.62, 0.62)

-- The ramp a face is lit along. Red, because a boss is theirs; blush where it
-- faces the light, slate where it faces away, and a checker of the two
-- between red and slate so a face part way round is a face part way round.
local LIT, MID, DIM = 0.58, 0.22, 0.06

--- the solids -----------------------------------------------------------------

-- A solid is its faces, each a plane `n . p <= h` in the die's own frame
-- (unit normal, the same `h` for every face of these three, which is what makes
-- a die fair), a label, and for the d6 two axes across the face to lay pips
-- out on. `r` is how far the furthest corner is from the middle: the box a
-- frame is painted inside.
local function solid(faces, h, digits)
    -- The corners are wherever three faces meet inside all the rest; the
    -- furthest of them is the box. Found rather than written down, so a solid
    -- retuned by one number cannot be clipped by a box that was not.
    local function det3(a, b, c)
        return a[1] * (b[2] * c[3] - b[3] * c[2])
             - a[2] * (b[1] * c[3] - b[3] * c[1])
             + a[3] * (b[1] * c[2] - b[2] * c[1])
    end
    local r, n, hh = 0, #faces, { h, h, h }
    for a = 1, n - 2 do
        for b = a + 1, n - 1 do
            for c = b + 1, n do
                local A, B, C = faces[a].n, faces[b].n, faces[c].n
                local d = det3(A, B, C)
                if abs(d) > 1e-6 then
                    -- Cramer's rule, with h on all three right-hand sides.
                    local col = function(k)
                        local m = { { A[1], A[2], A[3] }, { B[1], B[2], B[3] }, { C[1], C[2], C[3] } }
                        m[1][k], m[2][k], m[3][k] = hh[1], hh[2], hh[3]
                        return det3(m[1], m[2], m[3]) / d
                    end
                    local x, y, z = col(1), col(2), col(3)
                    local inside = true
                    for _, f in ipairs(faces) do
                        if f.n[1] * x + f.n[2] * y + f.n[3] * z > h + 1e-6 then
                            inside = false
                            break
                        end
                    end
                    if inside then r = math.max(r, sqrt(x * x + y * y + z * z)) end
                end
            end
        end
    end
    return { faces = faces, h = h, r = r, digits = digits }
end

-- The d6. Opposite faces add up to seven, as on every die ever sold; 11 out to
-- each face is a cube 22 across, 34 corner to corner -- a touch smaller than
-- the eye, because a cube turned on its corner is bigger than it looks.
local function d6()
    local f = {}
    local rows = {
        { 0, 0, 1, 1, { 1, 0, 0 }, { 0, 1, 0 } },
        { 0, 0, -1, 6, { 1, 0, 0 }, { 0, 1, 0 } },
        { 1, 0, 0, 3, { 0, 1, 0 }, { 0, 0, 1 } },
        { -1, 0, 0, 4, { 0, 1, 0 }, { 0, 0, 1 } },
        { 0, 1, 0, 2, { 1, 0, 0 }, { 0, 0, 1 } },
        { 0, -1, 0, 5, { 1, 0, 0 }, { 0, 0, 1 } },
    }
    for i, r in ipairs(rows) do
        f[i] = { n = { r[1], r[2], r[3] }, label = r[4], u = r[5], v = r[6] }
    end
    return solid(f, 11, false)
end

-- The d10: a pentagonal trapezohedron, ten kites, five round the top meeting
-- at a point and five round the bottom set half a step round from them. Every
-- face leans `TILT` off the horizontal; that one number is the whole shape --
-- flatter and it is a spinning top, steeper and it is a pencil. Numbered so
-- opposite faces add to eleven, the d10's own rule, and with 10 written as 10
-- rather than 0 because the number is read, not rolled for a percentage.
local function d10()
    local TILT = 0.84
    local f = {}
    local ce, se = cos(TILT), sin(TILT)
    for k = 0, 4 do
        local a = k * math.pi * 2 / 5
        f[#f + 1] = { n = { ce * cos(a), ce * sin(a), se }, label = 1 + k * 2 }
        local b = a + math.pi / 5
        f[#f + 1] = { n = { ce * cos(b), ce * sin(b), -se } }
    end
    -- Each bottom face is opposite a top face; give it what makes eleven.
    for _, face in ipairs(f) do
        if not face.label then
            local best, bd
            for _, other in ipairs(f) do
                if other.label then
                    local d = face.n[1] * other.n[1] + face.n[2] * other.n[2]
                        + face.n[3] * other.n[3]
                    if not bd or d < bd then best, bd = other, d end
                end
            end
            face.label = 11 - best.label
        end
    end
    return solid(f, 12, true)
end

-- The d20: an icosahedron, whose twenty face normals are the corners of a
-- dodecahedron. Opposite faces add to twenty-one. 14 out to each face puts the
-- corners about 17.6 out, the eye's size near enough.
local function d20()
    local p = (1 + sqrt(5)) / 2
    local q = 1 / p
    local raw = {}
    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            for _, sz in ipairs({ -1, 1 }) do raw[#raw + 1] = { sx, sy, sz } end
            raw[#raw + 1] = { 0, sx * q, sy * p }
            raw[#raw + 1] = { sx * q, sy * p, 0 }
            raw[#raw + 1] = { sx * p, 0, sy * q }
        end
    end
    local f = {}
    for _, r in ipairs(raw) do f[#f + 1] = { n = { norm(r[1], r[2], r[3]) } } end
    -- Label in opposite pairs, the first of each pair 1 to 10 in no particular
    -- order the player could learn -- a die whose numbers go round in sequence
    -- would be a die you could read before it stopped.
    local order = { 1, 17, 7, 13, 3, 19, 9, 15, 5, 11 }
    local next = 1
    for _, face in ipairs(f) do
        if not face.label then
            face.label = order[next]
            for _, other in ipairs(f) do
                if other ~= face and not other.label
                    and face.n[1] + other.n[1] == 0 and face.n[2] + other.n[2] == 0
                    and face.n[3] + other.n[3] == 0 then
                    other.label = 21 - face.label
                end
            end
            next = next + 1
        end
    end
    return solid(f, 14, true)
end

Dice.solids = { d6 = d6(), d10 = d10(), d20 = d20() }

-- Where the pips go on a face of the d6, in halves of the face (so 0.5 is half
-- way from the middle to an edge): the layout every die uses.
local PIPS = {
    { { 0, 0 } },
    { { -1, -1 }, { 1, 1 } },
    { { -1, -1 }, { 0, 0 }, { 1, 1 } },
    { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } },
    { { -1, -1 }, { 1, -1 }, { 0, 0 }, { -1, 1 }, { 1, 1 } },
    { { -1, -1 }, { -1, 0 }, { -1, 1 }, { 1, -1 }, { 1, 0 }, { 1, 1 } },
}
Dice.PIPS = PIPS
local PIP_AT, PIP_R = 0.5, 0.2

function Dice.new(shape)
    return setmetatable({
        solid = Dice.solids[shape], shape = shape,
        -- The die's own axes, written in the room (x right, y towards the
        -- bottom of the screen along the floor, z up off it): the columns of
        -- its turn. Started a little off square so the first frame is a die
        -- and not a square.
        ax = { 1, 0, 0 }, ay = { 0, 1, 0 }, az = { 0, 0, 1 },
        hidden = false,
        buf = {}, dirty = true,
    }, Dice):turn(0.4, 0.9, 0.2, 1)
end

-- A new solid, the same way up: the brain's call, when the die changes what it
-- is.
function Dice:become(shape)
    self.solid, self.shape, self.dirty = Dice.solids[shape], shape, true
end

--- turning --------------------------------------------------------------------

-- Turned `angle` about the room axis (kx, ky, kz), which must be unit.
-- Rodrigues on each column; the columns drift off square over a long fight,
-- so every turn squares them up again.
local function rotate(v, kx, ky, kz, c, s)
    local x, y, z = v[1], v[2], v[3]
    local d = (kx * x + ky * y + kz * z) * (1 - c)
    v[1] = x * c + (ky * z - kz * y) * s + kx * d
    v[2] = y * c + (kz * x - kx * z) * s + ky * d
    v[3] = z * c + (kx * y - ky * x) * s + kz * d
end

function Dice:turn(kx, ky, kz, angle)
    kx, ky, kz = norm(kx, ky, kz)
    local c, s = cos(angle), sin(angle)
    rotate(self.ax, kx, ky, kz, c, s)
    rotate(self.ay, kx, ky, kz, c, s)
    rotate(self.az, kx, ky, kz, c, s)
    -- Gram-Schmidt: x stays, y is squared off it, z is what they make.
    local ax, ay = self.ax, self.ay
    ax[1], ax[2], ax[3] = norm(ax[1], ax[2], ax[3])
    local d = ay[1] * ax[1] + ay[2] * ax[2] + ay[3] * ax[3]
    ay[1], ay[2], ay[3] = norm(ay[1] - d * ax[1], ay[2] - d * ax[2], ay[3] - d * ax[3])
    local az = self.az
    az[1] = ax[2] * ay[3] - ax[3] * ay[2]
    az[2] = ax[3] * ay[1] - ax[1] * ay[3]
    az[3] = ax[1] * ay[2] - ax[2] * ay[1]
    self.dirty = true
    return self
end

-- A face's normal in the room.
function Dice:worldNormal(face)
    local n, ax, ay, az = face.n, self.ax, self.ay, self.az
    return ax[1] * n[1] + ay[1] * n[2] + az[1] * n[3],
           ax[2] * n[1] + ay[2] * n[2] + az[2] * n[3],
           ax[3] * n[1] + ay[3] * n[2] + az[3] * n[3]
end

-- Rolled along the floor at (vx, vy) pixels a second for `dt`: turned about the
-- line on the floor square to the way it is going, at the rate that makes its
-- top go forward as fast as it does -- which is what rolling *is*, and what
-- makes a thrown die look thrown rather than spun. `r` is how big it is to
-- roll: the faces' own distance, so a d6 tumbles end over end and a d20, being
-- rounder, rolls.
function Dice:roll(vx, vy, dt)
    local sp = sqrt(vx * vx + vy * vy)
    if sp < 1e-3 then return end
    -- up x v: the axis the top turns forward about.
    self:turn(-vy, vx, 0, sp * dt / self.solid.h)
end

-- The face pointing most nearly up, and how far off up it is.
function Dice:top()
    local best, bz
    for _, face in ipairs(self.solid.faces) do
        local _, _, z = self:worldNormal(face)
        if not bz or z > bz then best, bz = face, z end
    end
    return best, bz
end

function Dice:face(label)
    for _, face in ipairs(self.solid.faces) do
        if face.label == label then return face end
    end
end

-- Coming to rest: whichever face is nearest up tips the rest of the way, at
-- `rate` radians a second. Or a face it was told to land on, however far round
-- that is (the glue's loaded die, src/diceboss.lua) -- which tips over through
-- whatever is in the way, and looks like a die that should not have stopped
-- where it did. Answers the face once it is flat, nil until then.
function Dice:settle(dt, rate, want)
    local face = want and self:face(want) or self:top()
    local x, y, z = self:worldNormal(face)
    local off = math.acos(math.max(-1, math.min(1, z)))
    if off < 1e-3 then return face end
    -- The axis that tips n towards up: n x up. Straight down has no such axis;
    -- any axis on the floor will do.
    local kx, ky = y, -x
    if kx * kx + ky * ky < 1e-8 then kx, ky = 1, 0 end
    self:turn(kx, ky, 0, math.min(off, rate * dt))
    return nil
end

--- painting -------------------------------------------------------------------

-- The room to the screen: x stays, the floor's y is foreshortened by the tilt
-- and height goes up the screen by the rest of it, and what is towards the
-- viewer comes out of the page.
local function toScreen(x, y, z)
    return x, y * CP - z * SP, y * SP + z * CP
end

-- How the die is facing this frame, worked once per solid per turn: each
-- face's normal on the screen, and the die's axes on the screen so a point on a
-- face can be taken back into the die's own frame to find its pips.
function Dice:prepare()
    local sol = self.solid
    local fs = {}
    for i, face in ipairs(sol.faces) do
        local sx, sy, sz = toScreen(self:worldNormal(face))
        fs[i] = { sx, sy, sz }
    end
    self.fs = fs
    self.mx = { toScreen(self.ax[1], self.ax[2], self.ax[3]) }
    self.my = { toScreen(self.ay[1], self.ay[2], self.ay[3]) }
    self.mz = { toScreen(self.az[1], self.az[2], self.az[3]) }
end

-- Every pixel in the box round the middle, asked which face it lands on: 0 for
-- none, else the face's index, and the depth it was met at for the pips. Done
-- once a frame whatever asks -- the blank, the outline and the body all read
-- the one answer, so they cannot disagree about the silhouette by a pixel.
function Dice:raster()
    if not self.dirty then return end
    self.dirty = false
    self:prepare()
    local sol, fs = self.solid, self.fs
    local h = sol.h
    local half = floor(sol.r) + 3
    local size = half * 2 + 1
    -- Written over the last frame's tables rather than into new ones: a
    -- tumbling die re-asks every pixel every frame, and two fresh tables of a
    -- couple of thousand entries a frame is garbage for nothing. A die at rest
    -- does not ask at all -- only a turn marks it dirty.
    local buf, depth = self.buf, self.depth or {}
    local n = #fs
    for j = 0, size - 1 do
        local v = j - half + 0.5
        for i = 0, size - 1 do
            local u = i - half + 0.5
            local near, far, hit = 1e9, -1e9, 0
            for k = 1, n do
                local f = fs[k]
                local c = h - f[1] * u - f[2] * v
                local a = f[3]
                if a > 1e-6 then
                    local zz = c / a
                    if zz < near then near, hit = zz, k end
                elseif a < -1e-6 then
                    local zz = c / a
                    if zz > far then far = zz end
                elseif c < 0 then
                    near = -1e9
                end
            end
            local at = j * size + i + 1
            if near >= far and hit > 0 then
                buf[at], depth[at] = hit, near
            else
                buf[at] = 0
            end
        end
    end
    self.buf, self.depth, self.half, self.size = buf, depth, half, size
end

-- Whether the pixel at (i, j) of the box is body: on a face, or the ring of ink
-- one outside the faces that is the die's rim. `pad` grows that by whole
-- pixels, for the outline and the blank under one.
local function solidAt(self, i, j)
    local size = self.size
    if i < 0 or j < 0 or i >= size or j >= size then return false end
    return self.buf[j * size + i + 1] ~= 0
end

local function bodyAt(self, i, j, pad)
    if solidAt(self, i, j) then return true end
    for d = 1, 1 + (pad or 0) do
        if solidAt(self, i - d, j) or solidAt(self, i + d, j)
            or solidAt(self, i, j - d) or solidAt(self, i, j + d) then
            return true
        end
        if d > 1 and (solidAt(self, i - d + 1, j - 1) or solidAt(self, i + d - 1, j + 1)
            or solidAt(self, i - 1, j + d - 1) or solidAt(self, i + 1, j - d + 1)) then
            return true
        end
    end
    return false
end

-- The silhouette in the current colour, `pad` pixels fat: the blank stamped
-- under it, the red rim of a hit, the flash.
function Dice:drawMask(x, y, pad)
    if self.hidden then return end
    self:raster()
    local ox, oy = floor(x) - self.half, floor(y) - self.half
    for j = -1 - (pad or 0), self.size + (pad or 0) do
        local run
        for i = -2 - (pad or 0), self.size + 1 + (pad or 0) do
            local on = bodyAt(self, i, j, pad)
            if on and not run then run = i end
            if not on and run then
                love.graphics.rectangle("fill", ox + run, oy + j, i - run, 1)
                run = nil
            end
        end
    end
end

local ink, slate, paper, graphite = Palette.ink, Palette.slate, Palette.paper, Palette.graphite
local red, blush = Palette.red, Palette.blush

-- What colour a face is, lit off its normal on the screen. The checker is
-- the ramp's own dither, keyed to the canvas pixel so it does not crawl as the
-- die slides across the page.
local function shade(f, px, py)
    local l = LX * f[1] + LY * f[2] + LZ * f[3]
    if l > LIT then return blush end
    if l > MID then return red end
    if l > DIM then return (px + py) % 2 == 0 and red or slate end
    return slate
end

-- The face on top, its normal on the screen, and how far it is turned towards
-- you: where a d10 or a d20's number is stamped. On top rather than most
-- towards you, though the second is the easier face to read, because the
-- number stamped has to be the number rolled -- in a tilted room the two are
-- different faces, and a die showing a 12 that rolled a 7 is a die that lied.
function Dice:facing()
    self:raster()
    local face = self:top()
    for k, f in ipairs(self.solid.faces) do
        if f == face then return face, self.fs[k], self.fs[k][3] end
    end
end

-- The die, every pixel of it. Top to bottom the questions are: is it the rim
-- (inside, with outside next to it); is it on an edge (the next pixel along is
-- another face); is it a pip; and otherwise what is this face lit to. Then the
-- number, flat on the face nearest you, for the two that have numbers.
function Dice:draw(x, y)
    if self.hidden then return end
    self:raster()
    local sol, fs = self.solid, self.fs
    local buf, depth, size, half = self.buf, self.depth, self.size, self.half
    local ox, oy = floor(x) - half, floor(y) - half
    local mx, my, mz = self.mx, self.my, self.mz
    local h = sol.h

    -- Written as runs of one colour along a row, the eye's economy.
    local cur, runX, runY
    local function flush(px)
        if cur then love.graphics.rectangle("fill", runX, runY, px - runX, 1) end
        cur = nil
    end
    local function put(px, py, colour)
        if colour ~= cur then
            flush(px)
            love.graphics.setColor(colour)
            cur, runX, runY = colour, px, py
        end
    end

    for j = -1, size do
        for i = -2, size + 1 do
            local px, py = ox + i, oy + j
            local k = (i >= 0 and j >= 0 and i < size and j < size) and buf[j * size + i + 1] or 0
            local colour
            if k == 0 then
                if bodyAt(self, i, j, 0) then colour = ink end
            elseif not (solidAt(self, i - 1, j) and solidAt(self, i + 1, j)
                and solidAt(self, i, j - 1) and solidAt(self, i, j + 1)) then
                colour = ink
            else
                local right = buf[j * size + i + 2]
                local below = buf[(j + 1) * size + i + 1]
                if right ~= k or below ~= k then
                    colour = ink
                else
                    local f = fs[k]
                    colour = shade(f, px, py)
                    local face = sol.faces[k]
                    if face.u then
                        -- Back into the die's frame: the point on the screen is
                        -- (u, v, depth), and the die's axes on the screen are
                        -- the rows that take it home.
                        local u, v, w = i - half + 0.5, j - half + 0.5, depth[j * size + i + 1]
                        local bx = mx[1] * u + mx[2] * v + mx[3] * w
                        local by = my[1] * u + my[2] * v + my[3] * w
                        local bz = mz[1] * u + mz[2] * v + mz[3] * w
                        local fu, fv = face.u, face.v
                        local a = (fu[1] * bx + fu[2] * by + fu[3] * bz) / h
                        local b = (fv[1] * bx + fv[2] * by + fv[3] * bz) / h
                        for _, p in ipairs(PIPS[face.label]) do
                            local da, db = a - p[1] * PIP_AT, b - p[2] * PIP_AT
                            if da * da + db * db < PIP_R * PIP_R then
                                -- A pip is a hole in the face, so it is the
                                -- face's opposite: paper on red and on the
                                -- checker, graphite in the shadow, and red on
                                -- a face lit pale enough that paper would not
                                -- show on it.
                                colour = colour == slate and graphite
                                    or colour == blush and red or paper
                                break
                            end
                        end
                    end
                end
            end
            if colour then put(px, py, colour) else flush(px) end
        end
        flush(ox + size + 2)
    end

    -- The number, for the two dice that carry one: stamped square on, over the
    -- middle of the face on top, in whichever of ink and paper the face is not
    -- -- and not while that face is turned so far off you that the middle of
    -- it is round the side.
    if sol.digits then
        local face, f, bz = self:facing()
        if bz > 0.45 then
            local text = tostring(face.label)
            local cx = floor(x) + floor(f[1] * h * 0.9 + 0.5)
            local cy = floor(y) + floor(f[2] * h * 0.9 + 0.5)
            local w = Font.width(text)
            local under = shade(f, cx, cy)
            love.graphics.setColor(under == blush and ink or paper)
            Font.print(text, cx - floor(w / 2), cy - 2)
        end
    end
end

-- How much of a mark it leaves under it, off how high it is: a die in the air
-- throws a smaller shadow, and a d20 sits on a point rather than a face.
function Dice:shadowScale(lift)
    return math.max(0.4, 1 - (lift or 0) / 40)
end

return Dice
