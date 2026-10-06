-- The deodorant's body: a can of body spray, painted a pixel at a time.
--
-- The speaker's method (src/speaker.lua) on a simpler solid, and for a simpler
-- reason: every pixel is a ray fired into the page and asked where it first
-- meets the can, and lit by the eye's own screen-fixed lamp. Three pieces stacked
-- up one axis -- the can (a cylinder), its shoulder (half an ellipsoid sat on top
-- of it) and the button you press (a smaller cylinder through the shoulder) -- so
-- three quadratics a pixel at most, and the nearest one wins.
--
-- It never tips over and never rolls, which is a decision about the fight more
-- than about the drawing: the speaker is the can that rolls, and a second can
-- bowling down a lane would be the speaker's fight in a different tin. So its
-- frame is a heading and nothing else -- `yaw`, the way the nozzle points -- and
-- the brain (src/deodorantboss.lua) turns it to point the nozzle at you.
--
-- What makes it read as *that* can and not as a tin:
--
--  - **It is black.** The one boss in the book drawn in ink, slate and graphite
--    -- metal, lit, with a glint off its shoulder -- because that is what the can
--    in every P.E. bag looks like. What it does is red, as every boss's is.
--  - **The label.** AX3 across its front, in paper, between two red bands -- the
--    can everyone knows, near enough to read as it and not its trademark. It
--    faces you because the nozzle does, so the word is the first thing you read.
--  - **The nozzle**, a dot on the front of the button, which goes red while it is
--    about to spray: the tell for everything it does is where the spray comes out.
--
-- And it **swells**: `swell` widens it, which is a can with its nozzle glued
-- shut and the pressure building in it (src/deodorantboss.lua). Its foot stays on
-- the page while it does.
--
-- Drawn the speaker's way otherwise: runs of one colour along a row, eight
-- colours, no alpha, an ink rim round the outside and along any edge where one
-- part stands in front of another. Worked out at most once a frame and kept.

local Palette = require("src.palette")

local Deodorant = {}
Deodorant.__index = Deodorant

local sqrt, floor, sin, cos, abs, atan2 = math.sqrt, math.floor, math.sin, math.cos, math.abs, math.atan2
local TAU = math.pi * 2

-- Seen from a little above, the speaker's half radian: enough of the shoulder to
-- show the button on it, and enough of the side for the label.
local ELEV = 0.5
local CE, SE = cos(ELEV), sin(ELEV)

-- The can: radius RAD, from FOOT up to NECK along its axis, in units of about a
-- pixel. 16 across and 28 tall -- a body spray is a tall thin can, and anything
-- squatter read as a bin -- then the shoulder DOME high on top of that, and the
-- button BUTTON_R across from BUTTON_LO to BUTTON_HI. 8 is the narrowest the can
-- can be for AX3 to sit on its front without the outside letters turning away
-- round the side.
local RAD, FOOT, NECK, DOME = 8, -17, 11, 4
local BUTTON_R, BUTTON_LO, BUTTON_HI = 3.2, 12, 18
-- Where the nozzle is up the button, and how big the hole is.
local NOZZLE_U, NOZZLE_W = 15.5, 1.3

-- Where e.y is against the drawing: the foot of the can is drawn this far below
-- it, so the hit circle round e.y covers the can rather than its shadow.
local GROUND = 8

-- The eye's lamp: up, left and in front, fixed on the screen.
local LX, LY, LZ = -0.48, -0.62, 0.62
do
    local n = sqrt(LX * LX + LY * LY + LZ * LZ)
    LX, LY, LZ = LX / n, LY / n, LZ / n
end
local HX, HY, HZ = LX, LY, LZ + 1
do
    local n = sqrt(HX * HX + HY * HY + HZ * HZ)
    HX, HY, HZ = HX / n, HY / n, HZ / n
end
local GLINT = 0.975

-- Past this much depth between two neighbouring pixels it is an edge.
local EDGE = 2.5

-- The label, in (across the can's face, up the can) units: AX3, a 3x5 face, one
-- unit a column and ROW_H a row so the letters survive the elevation squashing them.
-- Read off the front, so column 1 is the left of the word as you face it.
local LABEL = {
    ".x..x.x.xxx",
    "x.x.x.x...x",
    "xxx..x...xx",
    "x.x.x.x...x",
    "x.x.x.x.xxx",
}
local LABEL_TOP, ROW_H = 3, 1.3
local LABEL_W = #LABEL[1]
-- And the two red bands either side of the word.
local BAND_HI = { LABEL_TOP + 1.0, LABEL_TOP + 2.2 }
local BAND_LO = { LABEL_TOP - #LABEL * ROW_H - 2.4, LABEL_TOP - #LABEL * ROW_H - 1.2 }

local ink, slate, paper, graphite = Palette.ink, Palette.slate, Palette.paper, Palette.graphite
local red, blush = Palette.red, Palette.blush

function Deodorant.new()
    return setmetatable({
        -- The way the nozzle points, on the page.
        yaw = math.pi / 2,
        -- Written by the brain every frame: how swollen it is (0 to 1), how hard
        -- it is shaking, how high off the page it is hopping, and whether the
        -- nozzle is lit.
        swell = 0, shake = 0, hop = 0, hot = false,
        jx = 0, jy = 0,
        ground = GROUND,
        hidden = false,
        dirty = true, cache = nil,
    }, Deodorant)
end

--- the motion -------------------------------------------------------------------

-- Turned towards a heading, at `rate` radians a second (math.huge for at once).
function Deodorant:face(dx, dy, rate, dt)
    if dx == 0 and dy == 0 then return end
    local d = (atan2(dy, dx) - self.yaw + math.pi) % TAU - math.pi
    local most = rate * dt
    if rate ~= math.huge and abs(d) > most then d = d > 0 and most or -most end
    self.yaw = (self.yaw + d) % TAU
end

-- Spun on the spot by `a`: the leak.
function Deodorant:spin(a)
    self.yaw = (self.yaw + a) % TAU
end

function Deodorant:update(dt)
    local k = self.shake
    self.jx = k > 0 and floor((love.math.random() - 0.5) * 2 * k + 0.5) or 0
    self.jy = k > 1 and floor((love.math.random() - 0.5) * k + 0.5) or 0
    self.dirty = true
end

--- where things are -------------------------------------------------------------

function Deodorant:radius()
    return RAD * (1 + 0.28 * self.swell)
end

-- Where the can's own u = 0 is on the screen, off e.x, e.y.
function Deodorant:centre(x, y)
    return floor(x) + self.jx + 0.5,
        floor(y) + self.jy + 0.5 + GROUND + FOOT * CE - self.hop
end

-- The nozzle: where on the page under it the spray starts (on the ground, for
-- the cloud), and where on the screen it comes out (in the air, for the drawing).
function Deodorant:nozzle(x, y)
    local c, s = cos(self.yaw), sin(self.yaw)
    local r = BUTTON_R + 1
    local px, py = x + c * r, y + s * r
    local cx, cy = self:centre(x, y)
    return px, py, cx + c * r, cy + s * r * SE - NOZZLE_U * CE
end

function Deodorant:shadowScale(hop)
    return 1 + self.swell * 0.3 - (self.hop or 0) * 0.05
end

--- drawing ----------------------------------------------------------------------

-- The front of a ray through the solid, in the speaker's terms: the ray's body
-- coordinates are a + z * b on each axis, and the larger z is the nearer.
local function cylinder(af, bf, as, bs, au, bu, r, lo, hi)
    local best, part
    local qa = bf * bf + bs * bs
    if qa > 1e-6 then
        local qb = af * bf + as * bs
        local qc = af * af + as * as - r * r
        local disc = qb * qb - qa * qc
        if disc >= 0 then
            local z = (-qb + sqrt(disc)) / qa
            local u = au + z * bu
            if u >= lo and u <= hi then best, part = z, "side" end
        end
    end
    if abs(bu) > 1e-6 then
        local z = (hi - au) / bu
        if not best or z > best then
            local f, s = af + z * bf, as + z * bs
            if f * f + s * s <= r * r then best, part = z, "top" end
        end
    end
    return best, part
end

-- The shoulder: the top half of an ellipsoid RAD round and DOME high, sat on
-- the can at NECK.
local function shoulder(af, bf, as, bs, au, bu, r)
    local r2, h2 = r * r, DOME * DOME
    local du = au - NECK
    local A = (bf * bf + bs * bs) / r2 + bu * bu / h2
    local B = 2 * ((af * bf + as * bs) / r2 + du * bu / h2)
    local C = (af * af + as * as) / r2 + du * du / h2 - 1
    local disc = B * B - 4 * A * C
    if disc < 0 then return nil end
    local z = (-B + sqrt(disc)) / (2 * A)
    if au + z * bu < NECK then return nil end
    return z
end

-- A shade off how lit it is: `ladder` is four thresholds and five colours, with
-- a checker between each pair so one shade gives onto the next.
local function shade(light, checker, steps)
    for k = 1, 4 do
        if light > steps[k][1] then return steps[k][2] or (checker and steps[k][3] or steps[k][4]) end
    end
    return steps[5]
end

-- Black metal for the can, a lighter chrome for the shoulder, black plastic for
-- the button.
local CAN = { { 0.72, graphite }, { 0.45, nil, graphite, slate }, { 0.12, slate },
              { -0.25, nil, slate, ink }, ink }
local CHROME = { { 0.62, nil, paper, graphite }, { 0.3, graphite }, { 0.0, nil, graphite, slate },
                 { -0.35, slate }, ink }
local PLASTIC = { { 0.6, slate }, { 0.3, nil, slate, ink }, { -1, ink }, { -2, ink }, ink }

function Deodorant:raster()
    if not self.dirty and self.cache then return self.cache end
    -- Its frame on the page: front F, side S, up U, as the speaker's is.
    local c, s = cos(self.yaw), sin(self.yaw)
    local Fx, Fy, Fz = c, s * SE, s * CE
    local Sx, Sy, Sz = -s, c * SE, c * CE
    local Ux, Uy, Uz = 0, -CE, SE
    local rad = self:radius()
    local hot = self.hot

    local zbuf, cbuf = {}, {}
    local i0, i1, j0, j1 = -14, 14, -26, 24
    for j = j0, j1 do
        local zrow, crow = {}, {}
        zbuf[j], cbuf[j] = zrow, crow
        for i = i0, i1 do
            local af, bf = i * Fx + j * Fy, Fz
            local as, bs = i * Sx + j * Sy, Sz
            local au, bu = i * Ux + j * Uy, Uz

            local best, part = cylinder(af, bf, as, bs, au, bu, rad, FOOT, NECK)
            local z = shoulder(af, bf, as, bs, au, bu, rad)
            if z and (not best or z > best) then best, part = z, "dome" end
            local bz, bp = cylinder(af, bf, as, bs, au, bu, BUTTON_R, BUTTON_LO, BUTTON_HI)
            if bz and (not best or bz > best) then best, part = bz, bp == "top" and "cap" or "button" end

            if best then
                zrow[i] = best
                local f, sd, u = af + best * bf, as + best * bs, au + best * bu
                local checker = (i + j) % 2 == 0
                local nf, ns, nu
                if part == "side" or part == "button" then
                    local r = part == "side" and rad or BUTTON_R
                    nf, ns, nu = f / r, sd / r, 0
                elseif part == "dome" then
                    nf, ns, nu = f / (rad * rad), sd / (rad * rad), (u - NECK) / (DOME * DOME)
                else
                    nf, ns, nu = 0, 0, 1
                end
                local nx = nf * Fx + ns * Sx + nu * Ux
                local ny = nf * Fy + ns * Sy + nu * Uy
                local nz = nf * Fz + ns * Sz + nu * Uz
                local len = sqrt(nx * nx + ny * ny + nz * nz)
                nx, ny, nz = nx / len, ny / len, nz / len
                local light = LX * nx + LY * ny + LZ * nz
                local glint = HX * nx + HY * ny + HZ * nz > GLINT

                local colour
                if part == "side" then
                    colour = shade(light, checker, CAN)
                    -- The rolled rim round its foot.
                    if u < FOOT + 1.4 then colour = light > 0.2 and graphite or slate end
                    -- The label on its front: two red bands and AX3 between.
                    -- Laid out across the can as seen straight on rather than
                    -- round it, so facing you the word sits a letter column to
                    -- a pixel, and it squeezes off round the side as it turns.
                    local x = -sd * RAD / rad
                    if f > 0 then
                        -- The word is printed on a black panel, whatever the lamp
                        -- is doing to the metal round it, so it reads on the lit
                        -- side as well as the dark one.
                        if u < LABEL_TOP + 0.7 and u > LABEL_TOP - #LABEL * ROW_H - 0.4 then
                            colour = light > 0.6 and slate or ink
                        end
                        if (u >= BAND_HI[1] and u < BAND_HI[2]) or (u >= BAND_LO[1] and u < BAND_LO[2]) then
                            colour = light > -0.1 and red or (checker and red or slate)
                        end
                        local col = floor(x + LABEL_W / 2) + 1
                        local row = floor((LABEL_TOP - u) / ROW_H) + 1
                        if col >= 1 and col <= LABEL_W and row >= 1 and row <= #LABEL
                            and LABEL[row]:sub(col, col) == "x" then
                            colour = light > -0.3 and paper or graphite
                        end
                    end
                    if glint then colour = paper end
                elseif part == "dome" then
                    colour = shade(light, checker, CHROME)
                    if glint then colour = paper end
                elseif part == "button" then
                    colour = shade(light, checker, PLASTIC)
                    -- The nozzle, on its front.
                    local around = atan2(sd, f)
                    if abs(around * BUTTON_R) < NOZZLE_W and abs(u - NOZZLE_U) < NOZZLE_W * 0.8 then
                        colour = hot and (checker and red or blush) or ink
                    elseif abs(around * BUTTON_R) < NOZZLE_W + 1 and abs(u - NOZZLE_U) < NOZZLE_W + 0.6 then
                        colour = hot and red or slate
                    end
                else
                    colour = checker and slate or ink
                end
                crow[i] = colour
            end
        end
    end

    -- The rim, and the edges where one part stands in front of another.
    local rows = {}
    for j = j0, j1 do
        local zrow, crow = zbuf[j], cbuf[j]
        local up, down = zbuf[j - 1] or {}, zbuf[j + 1] or {}
        local runs, cur, from = {}, nil, nil
        for i = i0, i1 + 1 do
            local z = zrow[i]
            local colour
            if z then
                local l, r, a, b = zrow[i - 1], zrow[i + 1], up[i], down[i]
                if not (l and r and a and b) then
                    colour = ink
                elseif l - z > EDGE or r - z > EDGE or a - z > EDGE or b - z > EDGE then
                    colour = ink
                else
                    colour = crow[i]
                end
            end
            if colour ~= cur then
                if cur then runs[#runs + 1] = { from, i, cur } end
                cur, from = colour, i
            end
        end
        if #runs > 0 then rows[#rows + 1] = { j = j, runs = runs } end
    end

    self.cache, self.dirty = rows, false
    return rows
end

-- The silhouette, `pad` out, in whatever colour is set: the blank stamped under
-- it, a hit's rim, the flash.
function Deodorant:drawMask(x, y, pad)
    local cx, cy = self:centre(x, y)
    local ox, oy = floor(cx), floor(cy)
    pad = pad or 0
    for _, row in ipairs(self:raster()) do
        for _, run in ipairs(row.runs) do
            love.graphics.rectangle("fill", ox + run[1] - pad, oy + row.j - pad,
                run[2] - run[1] + pad * 2, 1 + pad * 2)
        end
    end
end

function Deodorant:draw(x, y)
    local cx, cy = self:centre(x, y)
    local ox, oy = floor(cx), floor(cy)
    local cur
    for _, row in ipairs(self:raster()) do
        for _, run in ipairs(row.runs) do
            if run[3] ~= cur then
                cur = run[3]
                love.graphics.setColor(cur)
            end
            love.graphics.rectangle("fill", ox + run[1], oy + row.j, run[2] - run[1], 1)
        end
    end
end

return Deodorant
