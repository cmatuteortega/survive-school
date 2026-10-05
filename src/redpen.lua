-- The red pen's body: a teacher's click pen, far too long, painted a pixel at a
-- time.
--
-- The speaker's method (src/speaker.lua) on a solid of revolution: every pixel
-- is a ray fired into the page and asked where it first meets the pen, and the
-- pen is a row of pieces that are each a cone or a cylinder about one axis --
-- the metal tip, the cone in front of the grip, the long body, the push button
-- on its end -- plus two flat discs. A cylinder and a cone are the same sum
-- (`radius = c + m * u` along the axis, m zero for a cylinder), so every piece is
-- one quadratic along the ray and one function solves the lot.
--
-- **It is longer than the screen.** That is the point of it. Stood up writing,
-- its nib is on the page by your feet and the rest of it goes up and out of the
-- top of the view -- the hand holding it is somewhere off the page -- and when it
-- falls over it lies across the whole box. So it is not drawn in a box round its
-- middle like every other body. It is drawn along its own axis, a band round the
-- line from its nib to its button, cut to the rows and columns the camera can
-- see (`Camera.bounds`): a pen that went off the page is not traced off it.
--
-- **It is seen the page's own way.** The speaker is looked at from a little
-- above and its depth is squeezed into the height of the screen; this cannot be,
-- because when it falls the line it lands on is a line *on the page*, and that
-- line has to be where the page says it is, to the pixel, or the strip it warned
-- you about and the strip it hits are two different strips. So the page is drawn
-- one to one, as everything else is, and height goes up the screen at `K` a
-- pixel: an oblique view. The ray for a pixel is the line through the page under
-- it going up and towards you.
--
-- What makes it read as *that* pen:
--
--  - **The barrel** is red, glossy, lit off the eye's lamp, with a chrome band
--    where the grip stops and another under the clip. "0.7" is printed on it
--    along its length, the way the size is on every pen in a pencil case.
--  - **The grip** is ribbed rubber, rings of it, dark: the strongest cue that
--    the thing is round, and the one that shows it turning in its fingers.
--  - **The clip** is a strip of metal down one side near the top. It goes round
--    when the pen is rolled (`roll`), so a pen rolling across the page is seen
--    to roll rather than to slide.
--  - **The tip** clicks. `tip` is how far out the refill is, 0 to 1, and the
--    button on the far end is pushed in by as much as the tip is out -- so glue,
--    which clicks it shut (src/redpenboss.lua), is seen at both ends.
--
-- Its orientation is its axis `U`, a direction on the page (x across, y down
-- it, h up off it) from the nib to the button, set by the brain every frame;
-- `roll` turns it about that axis. `lift` is how high the nib is off the page.
--
-- Drawn the eye's way otherwise: runs of one colour along a row, eight colours,
-- no alpha, an ink rim round the outside and along any edge where one part of
-- it stands in front of another. Worked out at most once a frame and kept
-- (`raster`), and not again until it has moved: it is a lot of rays.

local Palette = require("src.palette")
local Camera = require("src.camera")

local RedPen = {}
RedPen.__index = RedPen

local sqrt, floor, sin, cos, abs, atan2 = math.sqrt, math.floor, math.sin, math.cos, math.abs, math.atan2
local min, max = math.min, math.max

-- How far up the screen a pixel of height is drawn: the oblique view's one
-- number. Under one, so a pen stood up is foreshortened a little, and over a
-- half, so stood up it still goes off the top of the screen.
local K = 0.8
RedPen.K = K

-- The barrel's radius: fourteen across, about a monster's width, so the thing
-- is a pen and not a pole.
local R = 7
RedPen.R = R

-- Lengths along the axis, from the front of the cone (u = 0). The tip sticks
-- out in front of that by up to TIP. The grip runs to GRIP, then a chrome band,
-- then the barrel to the end at LENGTH, where the button is.
local TIP, CONE, GRIP, BAND = 6, 12, 56, 3
local LENGTH = 260
RedPen.LENGTH = LENGTH
RedPen.TIP = TIP
-- The clip, down the side near the top, and the band it is riveted under.
local CLIP_FROM, CLIP_TO, CLIP_HALF, CLIP_AT = LENGTH - 42, LENGTH - 6, 0.3, -1.1
-- The button: narrower than the barrel and pushed in as far as the tip is out.
local BUTTON_R, BUTTON_IN, BUTTON_OUT = 3.4, 2, 5
-- The radius of the refill at the cone's front, and at its very point.
local NECK, POINT = 2.2, 0.8

-- Where the nib's foot is against e.y: below it, so the hit circle round e.y
-- covers the nib and the grip above it rather than the paper under the point.
local NIBY = 10
RedPen.NIBY = NIBY

-- The eye's lamp, as a direction on the page: from the left, a little from the
-- top of the page, and from well above.
local LX, LY, LH = -0.55, -0.35, 0.76
do
    local n = sqrt(LX * LX + LY * LY + LH * LH)
    LX, LY, LH = LX / n, LY / n, LH / n
end
-- Towards whoever is looking: the way the ray goes. And halfway between that and
-- the lamp, for the glint.
local VX, VY, VH = 0, K / sqrt(1 + K * K), 1 / sqrt(1 + K * K)
local HX, HY, HH = LX + VX, LY + VY, LH + VH
do
    local n = sqrt(HX * HX + HY * HY + HH * HH)
    HX, HY, HH = HX / n, HY / n, HH / n
end
local GLINT = 0.975

-- Past this much depth between two neighbouring pixels it is an edge.
local EDGE = 2.5

local ink, slate, paper, graphite = Palette.ink, Palette.slate, Palette.paper, Palette.graphite
local red, blush = Palette.red, Palette.blush

-- "0.7", printed along the barrel: three glyphs of the 3x5 face, a column per
-- couple of units along the pen and a row per unit round it.
local PRINT = {
    { "xxx", "x.x", "x.x", "x.x", "xxx" },
    { "...", "...", "...", "...", ".x." },
    { "xxx", "..x", ".x.", ".x.", ".x." },
}
-- Where the print starts along the barrel, and how long a glyph's pixel is
-- along it (round it, a pixel is a unit).
local PRINT_AT, PRINT_PX = 92, 2

function RedPen.new()
    return setmetatable({
        -- Its axis, nib to button, on the page; stood up to start with.
        U = { 0, 0, 1 },
        -- Written by the brain every frame: how far it is turned in its
        -- fingers, how high the nib is, how far the tip is clicked out, and how
        -- hard it is shaking.
        roll = 0, lift = 0, tip = 0, shake = 0, jx = 0,
        ground = NIBY,
        hidden = false,
        dirty = true, cache = nil, clip = nil,
    }, RedPen)
end

--- the frame --------------------------------------------------------------------

local function norm(x, y, h)
    local n = sqrt(x * x + y * y + h * h)
    if n < 1e-9 then return 0, 0, 1 end
    return x / n, y / n, h / n
end

-- Pointed along (x, y, h), nib to button.
function RedPen:point(x, y, h)
    local U = self.U
    U[1], U[2], U[3] = norm(x, y, h)
    self.dirty = true
end

-- Turned towards (x, y, h) by `k` of the way: what every move steers it with,
-- so nothing it does snaps.
function RedPen:ease(x, y, h, k)
    local U = self.U
    k = min(1, max(0, k))
    x, y, h = norm(x, y, h)
    self:point(U[1] + (x - U[1]) * k, U[2] + (y - U[2]) * k, U[3] + (h - U[3]) * k)
end

-- Its front and side, square to the axis: the front the part of it facing
-- whoever is looking (the ray, back along it, with the axis taken out), turned
-- by `roll` about it -- so unrolled, the print is towards you and the clip is
-- round the top, whichever way it points.
function RedPen:frame()
    local Ux, Uy, Uh = self.U[1], self.U[2], self.U[3]
    local d = VX * Ux + VY * Uy + VH * Uh
    local fx, fy, fh = VX - Ux * d, VY - Uy * d, VH - Uh * d
    local n = sqrt(fx * fx + fy * fy + fh * fh)
    if n < 1e-4 then fx, fy, fh, n = 1, 0, 0, 1 end
    fx, fy, fh = fx / n, fy / n, fh / n
    -- U x F, the third of the three.
    local sx, sy, sh = Uy * fh - Uh * fy, Uh * fx - Ux * fh, Ux * fy - Uy * fx
    local c, s = cos(self.roll), sin(self.roll)
    return fx * c + sx * s, fy * c + sy * s, fh * c + sh * s,
           sx * c - fx * s, sy * c - fy * s, sh * c - fh * s
end

-- Traced again only when something it is drawn from has moved: a pen lying
-- still across the page, or stuck, is the same picture frame after frame, and
-- this is the most expensive picture in the book.
function RedPen:update(dt)
    self.jx = self.shake > 0
        and floor((love.math.random() - 0.5) * 2 * self.shake + 0.5) or 0
    local U, was = self.U, self.was
    if not was then
        was = {}
        self.was = was
    end
    if was[1] ~= U[1] or was[2] ~= U[2] or was[3] ~= U[3] or was[4] ~= self.lift
        or was[5] ~= self.tip or was[6] ~= self.roll then
        was[1], was[2], was[3], was[4], was[5], was[6] = U[1], U[2], U[3], self.lift, self.tip, self.roll
        self.dirty = true
    end
end

--- where things are -------------------------------------------------------------

-- The length of it, tip and button included, as it is clicked now.
function RedPen:reach()
    return TIP * self.tip + LENGTH + BUTTON_IN + (BUTTON_OUT - BUTTON_IN) * (1 - self.tip)
end

-- A point `u` along the axis from the nib, on the page against the nib's foot:
-- across, down the page, and up off it.
function RedPen:along(u)
    local U = self.U
    return U[1] * u, U[2] * u, self.lift + U[3] * u
end

-- And the same point on the screen, against the nib's foot.
function RedPen:screenAt(u)
    local x, y, h = self:along(u)
    return x, y - K * h
end

-- Where the nib's foot is drawn against (x, y), the body's footing.
function RedPen:origin(x, y)
    return floor(x) + self.jx, floor(y) + NIBY
end

function RedPen:shadowScale()
    return 0
end

--- drawing ----------------------------------------------------------------------

-- One piece of the pen, `radius = c + m * u` along the axis from u0 to u1, hit
-- by the ray `A + t B`: the nearest t at which it is met, or nil. `au`, `bu` are A and B along the axis, `AA`, `AB`, `BB` their
-- products. Written out rather than looped: it runs a few thousand times a
-- frame, and a table a call was most of what it cost.
local BB = 1 + K * K
local function piece(c, m, u0, u1, AA, AB, au, bu)
    local cm = c + m * au
    local mb = m * bu
    local qa = BB - bu * bu - mb * mb
    if qa < 1e-9 and qa > -1e-9 then return nil end
    local qb = AB - au * bu - cm * mb
    local disc = qb * qb - qa * (AA - au * au - cm * cm)
    if disc < 0 then return nil end
    local sq = sqrt(disc)
    -- The nearer root first, then the further. (No swap: a parallel assignment
    -- in here is more than the JIT will keep in registers.)
    local ta = (-qb + sq) / qa
    local tb = (-qb - sq) / qa
    local near = max(ta, tb)
    local u = au + near * bu
    if u >= u0 and u <= u1 and c + m * u >= 0 then return near end
    local far = min(ta, tb)
    u = au + far * bu
    if u >= u0 and u <= u1 and c + m * u >= 0 then return far end
    return nil
end

-- Where the ray under the pixel (ax, ay) first meets the pen, `along` the band
-- on the screen: how far up the ray, which piece, and that piece's slope. A
-- function of its own, apart from the walk over the rows, so neither is too
-- big for the JIT to keep in registers.
--
-- A pen across the whole screen is several thousand rays, so each is asked only
-- about the pieces it could meet: the cone and the tip near the nib's end of the
-- band, the button and the flat end near the other, the long body everywhere.
-- Pointed nearly at you, where the band is too short to say which end a pixel
-- is near, every ray is asked about every piece.
local function ray(P, ax, ay, along)
    local ah = P.ah
    local AA = ax * ax + ay * ay + ah * ah
    local AB = K * ay + ah
    local au = ax * P.Ux + ay * P.Uy + ah * P.Uh
    local bu = P.bu
    local best, part, slope = piece(R, 0, CONE, LENGTH, AA, AB, au, bu), "body", 0
    if P.every or along <= P.nearTo then
        local t = piece(NECK, P.coneM, 0, CONE, AA, AB, au, bu)
        if t and (not best or t > best) then best, part, slope = t, "cone", P.coneM end
        local tipM = P.tipM
        if tipM then
            t = piece(NECK, tipM, -P.tipOut, 0, AA, AB, au, bu)
            if t and (not best or t > best) then best, part, slope = t, "tip", tipM end
        end
    end
    if P.every or along >= P.farFrom then
        local top = P.top
        local t = piece(BUTTON_R, 0, LENGTH, top, AA, AB, au, bu)
        if t and (not best or t > best) then best, part, slope = t, "button", 0 end
        -- The two flat ends: the barrel's, round the button, and the button's own.
        if bu > 1e-6 or bu < -1e-6 then
            t = (LENGTH - au) / bu
            if (not best or t > best) and AA + 2 * t * AB + t * t * BB - LENGTH * LENGTH <= R * R then
                best, part, slope = t, "end", 0
            end
            t = (top - au) / bu
            if (not best or t > best)
                and AA + 2 * t * AB + t * t * BB - top * top <= BUTTON_R * BUTTON_R then
                best, part, slope = t, "cap", 0
            end
        end
    end
    return best, part, slope
end

-- The colour where the ray under (ax, ay) met `part` `t` up it.
function RedPen:shade(P, part, t, slope, ax, ay, checker)
    local Ux, Uy, Uh = P.Ux, P.Uy, P.Uh
    local ah = P.ah
    local u = part == "end" and LENGTH or part == "cap" and P.top
        or (ax * Ux + ay * Uy + ah * Uh) + t * P.bu
    -- The point, from the frame's origin, and the part of it square to the axis.
    local rx, ry, rh = ax - Ux * u, ay + K * t - Uy * u, ah + t - Uh * u
    local light, facing
    if part == "end" or part == "cap" then
        light = LX * Ux + LY * Uy + LH * Uh
        facing = HX * Ux + HY * Uy + HH * Uh
    else
        local rl = sqrt(rx * rx + ry * ry + rh * rh)
        if rl < 1e-6 then rl = 1e-6 end
        local gx = rx / rl - slope * Ux
        local gy = ry / rl - slope * Uy
        local gh = rh / rl - slope * Uh
        local n = sqrt(gx * gx + gy * gy + gh * gh)
        light = (LX * gx + LY * gy + LH * gh) / n
        facing = (HX * gx + HY * gy + HH * gh) / n
    end
    local glint = facing > GLINT
    -- Which way round it is, only where something is painted by it: the
    -- barrel's print and its clip.
    local around = 0
    if part == "body" and u > GRIP then
        around = atan2(rx * P.Sx + ry * P.Sy + rh * P.Sh, rx * P.Fx + ry * P.Fy + rh * P.Fh)
    end
    return self:paint(part, u, around, light, glint, checker, P.tipOut)
end

-- The rows of runs, relative to the nib's foot, cut to `view` (x0, y0, x1, y1,
-- relative to the same point): worked out at most once a frame.
function RedPen:raster(vx0, vy0, vx1, vy1)
    local clip = self.clip
    if not self.dirty and self.cache and clip
        and clip[1] == vx0 and clip[2] == vy0 and clip[3] == vx1 and clip[4] == vy1 then
        return self.cache
    end
    self.clip = { vx0, vy0, vx1, vy1 }

    -- This frame's numbers, for `ray` and `shade`.
    local P = self.P or {}
    self.P = P
    local Ux, Uy, Uh = self.U[1], self.U[2], self.U[3]
    P.Ux, P.Uy, P.Uh = Ux, Uy, Uh
    P.Fx, P.Fy, P.Fh, P.Sx, P.Sy, P.Sh = self:frame()
    local tipOut = TIP * self.tip
    local top = LENGTH + BUTTON_IN + (BUTTON_OUT - BUTTON_IN) * (1 - self.tip)
    P.tipOut, P.top = tipOut, top
    -- The frame's origin, the front of the cone, on the page.
    local Ox, Oy, Oh = Ux * tipOut, Uy * tipOut, self.lift + Uh * tipOut
    P.ah = -Oh
    P.bu = K * Uy + Uh
    P.tipM = tipOut > 0.3 and (NECK - POINT) / tipOut or false
    P.coneM = (R - NECK) / CONE

    -- The band the pen can be in on the screen: round the line from the point
    -- to the button, as wide as the barrel can look from here.
    local x0, y0 = self:screenAt(0)
    local x1, y1 = Ox + Ux * top, Oy + Uy * top - K * (Oh + Uh * top)
    local W = R * sqrt(1 + K * K) + 2
    local dx, dy = x1 - x0, y1 - y0
    local len = sqrt(dx * dx + dy * dy)
    local len2 = len * len
    local j0 = floor(max(min(y0, y1) - W, vy0))
    local j1 = floor(min(max(y0, y1) + W, vy1)) + 1
    local ilo = floor(max(min(x0, x1) - W, vx0))
    local ihi = floor(min(max(x0, x1) + W, vx1)) + 1
    local W2 = W * W

    -- Which pieces a pixel that far along the band could be on: the screen
    -- length of a unit of the pen, and where the near end and the far end stop.
    local per = len / (tipOut + top)
    P.every = per < 0.3
    P.nearTo = (tipOut + CONE) * per + W * 1.5
    P.farFrom = (tipOut + LENGTH) * per - W * 1.5

    -- A row's depths and colours are arrays from its own first column (`los`),
    -- false where the ray missed: a table keyed by screen columns, which go
    -- negative, would be a hash, and this is filled a few thousand times a frame.
    local zbuf, cbuf, los, firsts, lasts = {}, {}, {}, {}, {}
    for j = j0, j1 do
        local zrow, crow = {}, {}
        zbuf[j], cbuf[j] = zrow, crow
        local lo, hi = ilo, ihi
        if abs(dy) > 0.5 then
            local xc = x0 + (j + 0.5 - y0) * dx / dy
            local half = W * len / abs(dy)
            lo, hi = max(lo, floor(xc - half)), min(hi, floor(xc + half) + 1)
        end
        los[j] = lo
        local base = lo - 1
        local py = j + 0.5 - y0
        local ay = j + 0.5 - Oy
        for i = lo, hi do
            -- Off the band at the ends: the corners of the row's span.
            local px = i + 0.5 - x0
            local s = len2 > 0 and (px * dx + py * dy) / len2 or 0
            s = s < 0 and 0 or (s > 1 and 1 or s)
            local ex, ey = px - dx * s, py - dy * s
            zrow[i - base] = false
            if ex * ex + ey * ey <= W2 then
                local ax = i + 0.5 - Ox
                local t, part, slope = ray(P, ax, ay, s * len)
                if t then
                    zrow[i - base] = t
                    if not firsts[j] then firsts[j] = i end
                    lasts[j] = i
                    crow[i - base] = self:shade(P, part, t, slope, ax, ay, (i + j) % 2 == 0)
                end
            end
        end
    end

    -- The rim, and the edges where one part stands in front of another.
    local rows = {}
    for j = j0, j1 do
        local first, last = firsts[j], lasts[j]
        if first then
            local zrow, crow, base = zbuf[j], cbuf[j], los[j] - 1
            local up, down = zbuf[j - 1], zbuf[j + 1]
            local ub, db = (los[j - 1] or 0) - 1, (los[j + 1] or 0) - 1
            local runs, cur, from = {}, nil, nil
            for i = first, last + 1 do
                local z = i <= last and zrow[i - base]
                local colour
                if z then
                    local l, r = zrow[i - 1 - base], zrow[i + 1 - base]
                    local a, b = up and up[i - ub], down and down[i - db]
                    if not (l and r and a and b) then
                        colour = ink
                    elseif l - z > EDGE or r - z > EDGE or a - z > EDGE or b - z > EDGE then
                        colour = ink
                    else
                        colour = crow[i - base]
                    end
                end
                if colour ~= cur then
                    if cur then runs[#runs + 1] = { from, i, cur } end
                    cur, from = colour, i
                end
            end
            if #runs > 0 then rows[#rows + 1] = { j = j, runs = runs } end
        end
    end

    self.cache, self.dirty = rows, false
    return rows
end

-- The colour of one point of it: which part, how far along, which way round,
-- and how lit.
function RedPen:paint(part, u, around, light, glint, checker, tipOut)
    if part == "tip" then
        -- The refill's metal point, and the ball at the very end of it.
        if u < -tipOut + 1.4 then return ink end
        if glint or light > 0.7 then return paper end
        if light > 0.2 then return graphite end
        return checker and slate or graphite
    elseif part == "cap" or part == "button" then
        -- The button: chrome.
        if glint then return paper end
        if light > 0.5 then return checker and paper or graphite end
        if light > 0 then return graphite end
        return slate
    elseif part == "end" then
        return light > 0.3 and red or slate
    elseif part == "cone" or u < GRIP then
        -- The grip: dark rubber in rings, and the cone in front of it the same.
        local ring = part == "body" and (u - CONE) % 4 < 1.2
        if ring then return ink end
        if glint then return graphite end
        if light > 0.55 then return checker and graphite or slate end
        if light > 0.1 then return slate end
        return checker and ink or slate
    end

    -- Chrome: the band where the grip stops and the one under the clip.
    if u < GRIP + BAND or (u > CLIP_FROM - 3 and u < CLIP_FROM) then
        if glint or light > 0.6 then return paper end
        if light > 0.1 then return graphite end
        return slate
    end

    -- The clip, down its front near the top: a strip of metal with an ink edge.
    local off = abs((around - CLIP_AT + math.pi) % (2 * math.pi) - math.pi)
    if u > CLIP_FROM and u < CLIP_TO and off < CLIP_HALF then
        if off > CLIP_HALF - 0.1 then return ink end
        if glint or light > 0.5 then return paper end
        if light > 0 then return graphite end
        return slate
    end

    -- The barrel: red, glossy.
    local colour
    if glint then
        colour = paper
    elseif light > 0.72 then
        colour = checker and paper or blush
    elseif light > 0.45 then
        colour = blush
    elseif light > 0.2 then
        colour = checker and blush or red
    elseif light > -0.35 then
        colour = red
    else
        colour = checker and slate or red
    end

    -- A thin ink line round it, a pen's own seam.
    if abs(u - 74) < 0.7 then return ink end

    -- "0.7", along it on the side facing you, in ink.
    local col = floor((u - PRINT_AT) / PRINT_PX)
    local row = floor(around * R + 2.5)
    if col >= 0 and row >= 0 and row < 5 then
        local g = PRINT[floor(col / 4) + 1]
        local gx = col % 4
        if g and gx < 3 and g[row + 1]:sub(gx + 1, gx + 1) == "x" then
            return colour == paper and blush or ink
        end
    end
    return colour
end

-- The view, against the nib's foot drawn at (ox, oy): what the camera sees, a
-- little more so the rim at the edge of the screen is off it, and squared off
-- outwards to a grid -- so a camera following you a pixel at a time is not a
-- new view, and a picture that has not changed is not traced again.
local VIEW_GRID = 32

local function view(ox, oy)
    local left, top, w, h = Camera.bounds()
    local g = VIEW_GRID
    return floor((left - ox - 2) / g) * g, floor((top - oy - 2) / g) * g,
           math.ceil((left + w - ox + 2) / g) * g, math.ceil((top + h - oy + 2) / g) * g
end

-- The silhouette, `pad` out, in whatever colour is set: the blank stamped
-- under it, a hit's rim, the flash.
function RedPen:drawMask(x, y, pad)
    local ox, oy = self:origin(x, y)
    pad = pad or 0
    for _, row in ipairs(self:raster(view(ox, oy))) do
        for _, run in ipairs(row.runs) do
            love.graphics.rectangle("fill", ox + run[1] - pad, oy + row.j - pad,
                run[2] - run[1] + pad * 2, 1 + pad * 2)
        end
    end
end

function RedPen:draw(x, y)
    local ox, oy = self:origin(x, y)
    local cur
    for _, row in ipairs(self:raster(view(ox, oy))) do
        for _, run in ipairs(row.runs) do
            if run[3] ~= cur then
                cur = run[3]
                love.graphics.setColor(cur)
            end
            love.graphics.rectangle("fill", ox + run[1], oy + row.j, run[2] - run[1], 1)
        end
    end
end

return RedPen
