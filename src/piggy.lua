-- The piggy bank's body: a pig made of ellipsoids, painted a pixel at a time.
--
-- The eye's method (src/eyeball.lua) stretched, as BOSSIDEAS.md had it: every
-- pixel is a ray fired straight into the page, asked what it meets first, and
-- lit by the eye's own screen-fixed lamp. The eye is one sphere and needs only
-- the sphere's sum; a pig is a handful of solids -- a long ellipsoid for the
-- barrel, a squat one for the snout, two for the ears and four for the legs --
-- so each ray asks all of them and keeps the nearest. Ellipsoids because the
-- question has a closed answer (a quadratic along the ray) and because every
-- part of a piggy bank is a rounded lump of pottery anyway.
--
-- Unlike the eye and the atom, which are looked at straight down, the pig is
-- seen from a little above and in front (`ELEV`): it stands on the page and
-- turns to face where it is going, so the same body is a side view trotting
-- across the box, a snout and two ears coming at you, and a rump going away.
-- That is what the heading is for -- a charge is aimed, and an animal whose
-- nose is pointing at you is the oldest tell there is.
--
-- **Cracks** spread over the barrel as it takes damage, the way the eye's veins
-- do. The barrel is cut into shards the atom's way -- a dozen and a half points
-- on the ball, every pixel belonging to whichever is nearest -- and a seam
-- between two shards is drawn once both of them have been reached. Each shard
-- is reached at a share of hurt ranked by how far it is from one spot on its
-- back, so the cracks start at one place and run out from it rather than
-- appearing all over at once. Once it has **shattered** (src/piggyboss.lua),
-- the shards round that spot are gone and what is under them is the dark
-- inside of an empty bank.
--
-- Drawn the eye's way otherwise: runs of one colour along a row, eight colours,
-- no alpha, an ink rim round the outside and along any edge where one part
-- stands in front of another. The picture is worked out once a frame and kept
-- (`raster`), since the blank under it, a hit's rim and the body itself all
-- want the same pixels.

local Palette = require("src.palette")

local Piggy = {}
Piggy.__index = Piggy

local sqrt, floor, sin, cos, abs = math.sqrt, math.floor, math.sin, math.cos, math.abs
local TAU = math.pi * 2

-- How far above the page it is seen from: 0 would be a side view of every
-- heading, and the eye's straight down would make the pig a pink oval. Half a
-- radian shows the back -- which is where the slot and the cracks are -- and
-- still shows the legs.
local ELEV = 0.5
local CE, SE = cos(ELEV), sin(ELEV)

-- The barrel's three half-lengths: nose to tail, side to side, and top to
-- bottom. 38 long, the eye's 43 with the snout on.
local A, B, H = 19, 13, 12.5

-- How far the drawing sits up off where it is standing: e.y is its feet, as
-- near as a body on four legs has one place to stand.
local LIFT = 3

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
local GLINT = 0.985

-- How many shards the barrel is cut into, and how wide a crack is (as a
-- difference in nearness, as the atom's seam is).
local SHARDS, SEAM = 18, 0.04
-- Where the cracks start, on the barrel's own ball: on top, a little behind the
-- slot and over to one side -- which is where a piggy bank is always dropped.
local SEED = { -0.15, 0.45, 0.88 }
-- How many shards near the seed are gone once it has shattered.
local GONE = 2

-- Past this much depth between two neighbouring pixels it is an edge: the far
-- one is drawn as ink, which outlines an ear against the barrel behind it.
local EDGE = 2.5

local ink, slate, paper, graphite = Palette.ink, Palette.slate, Palette.paper, Palette.graphite
local red, blush = Palette.red, Palette.blush

local function shards()
    local list = {}
    local golden = math.pi * (3 - sqrt(5))
    for i = 0, SHARDS - 1 do
        local y = 1 - (i + 0.5) / SHARDS * 2
        local r = sqrt(1 - y * y)
        local a = i * golden + 0.4
        list[i + 1] = { cos(a) * r, sin(a) * r, y }
    end
    -- Ranked by how far each is from the seed: the nearest cracks first.
    local n = sqrt(SEED[1] ^ 2 + SEED[2] ^ 2 + SEED[3] ^ 2)
    local sx, sy, sz = SEED[1] / n, SEED[2] / n, SEED[3] / n
    local order = {}
    for i, s in ipairs(list) do
        s.near = s[1] * sx + s[2] * sy + s[3] * sz
        order[i] = s
    end
    table.sort(order, function(p, q) return p.near > q.near end)
    for rank, s in ipairs(order) do
        -- Reached at an eighth of its health gone for the first, and the last
        -- of them at nine tenths: the whole of the fight is one spreading web.
        s.at = 0.12 + (rank - 1) / (SHARDS - 1) * 0.78
        s.gone = rank <= GONE
    end
    return list
end

function Piggy.new()
    return setmetatable({
        -- Which way it faces on the page (radians, 0 is right, down the page is
        -- towards you), and which way it wants to.
        yaw = math.pi * 0.5, yawTo = nil,
        -- Nose up (positive) or down, for the rear before it calls its coins
        -- home and the dip before a charge; eased like the heading.
        pitch = 0, pitchTo = 0,
        -- The trot: how far round its stride it is, and how high that has it.
        stride = 0, hop = 0,
        -- Written by the brain: how hurt it is (the cracks), whether it has
        -- shattered, and how hard it is shaking.
        hurt = 0, broken = false, shake = 0, jx = 0,
        lastX = nil, lastY = nil,
        shards = shards(),
        ground = 3,
        hidden = false,
        dirty = true, cache = nil,
    }, Piggy)
end

--- the motion -----------------------------------------------------------------

-- Faced at a heading on the page, at `rate` radians a second (or at once).
function Piggy:face(dx, dy, rate)
    if dx == 0 and dy == 0 then return end
    self.yawTo = math.atan2(dy, dx)
    self.turnRate = rate
end

-- One frame: it turns to where it wants to face, its nose goes up or down to
-- where the brain wants it, and it trots by however far it went -- the stride
-- is paid for in distance rather than in time, so it stands still when it is
-- held and its legs blur when it charges.
function Piggy:update(dt, x, y)
    if dt <= 0 then return end
    if self.yawTo then
        local d = (self.yawTo - self.yaw + math.pi) % TAU - math.pi
        local most = (self.turnRate or 7) * dt
        if self.turnRate == math.huge or abs(d) <= most then
            self.yaw = self.yawTo
        else
            self.yaw = self.yaw + (d > 0 and most or -most)
        end
    end
    self.pitch = self.pitch + (self.pitchTo - self.pitch) * math.min(1, dt * 8)

    local moved = self.lastX and sqrt((x - self.lastX) ^ 2 + (y - self.lastY) ^ 2) or 0
    self.lastX, self.lastY = x, y
    if moved > 0.05 then
        self.stride = (self.stride + moved * 0.32) % TAU
    else
        -- Settles onto four feet when it stops.
        local back = math.pi - (self.stride % math.pi)
        if back < math.pi * 0.5 then
            self.stride = self.stride + math.min(back, dt * 6)
        else
            self.stride = self.stride - math.min(math.pi - back, dt * 6)
        end
    end
    self.hop = floor(abs(sin(self.stride)) * 2 + 0.5)

    self.jx = self.shake > 0
        and floor((love.math.random() - 0.5) * 2 * self.shake + 0.5) or 0
    self.dirty = true
end

--- where things are -------------------------------------------------------------

-- The middle of the barrel on the screen, off where its feet are.
function Piggy:centre(x, y)
    return floor(x) + self.jx + 0.5, floor(y) + 0.5 - LIFT - 8 - self.hop
end

-- The page-to-screen frame the pig stands in: F its nose, S its left, U its
-- back, each a direction on the screen with z towards you.
function Piggy:frame()
    local cy_, sy_ = cos(self.yaw), sin(self.yaw)
    -- Flat on the page first: the nose along the heading, the side across it.
    local Fx, Fy, Fz = cy_, sy_ * SE, sy_ * CE
    local Sx, Sy, Sz = -sy_, cy_ * SE, cy_ * CE
    local Ux, Uy, Uz = 0, -CE, SE
    -- Then the nose tipped up about the side.
    local cp, sp = cos(self.pitch), sin(self.pitch)
    Fx, Fy, Fz, Ux, Uy, Uz =
        Fx * cp + Ux * sp, Fy * cp + Uy * sp, Fz * cp + Uz * sp,
        Ux * cp - Fx * sp, Uy * cp - Fy * sp, Uz * cp - Fz * sp
    return Fx, Fy, Fz, Sx, Sy, Sz, Ux, Uy, Uz
end

-- A point on the body, given in the pig's own frame, out on the screen as an
-- offset from the barrel's middle: where the slot is, for the coins it spits.
function Piggy:point(f, s, u)
    local Fx, Fy, Fz, Sx, Sy, Sz, Ux, Uy, Uz = self:frame()
    return f * Fx + s * Sx + u * Ux, f * Fy + s * Sy + u * Uy, f * Fz + s * Sz + u * Uz
end

-- Where the slot is, on the screen: coins go in and out of here.
function Piggy:slot(x, y)
    local cx, cy = self:centre(x, y)
    local px, py = self:point(-1, 0, H)
    return cx + px, cy + py
end

-- Where the snout is, on the screen: a charge is drawn from here.
function Piggy:snout(x, y)
    local cx, cy = self:centre(x, y)
    local px, py = self:point(A + 3, 0, -1)
    return cx + px, cy + py
end

function Piggy:shadowScale(hop)
    return 1 - (self.hop or 0) * 0.08
end

--- the solids -------------------------------------------------------------------

-- Every part, in the pig's own frame: a middle (f, s, u) and three half-lengths
-- along the same axes. The legs are worked out each frame off the stride, two
-- diagonal pairs a half stride apart, which is what a trot is.
local function parts(self)
    local lift1 = math.max(0, sin(self.stride)) * 3
    local lift2 = math.max(0, -sin(self.stride)) * 3
    local legU = -H * 0.72
    return {
        { name = "body",  0, 0, 0, A, B, H },
        { name = "snout", A * 0.97, 0, -1, 4.2, 5.4, 4.4 },
        { name = "ear",   A * 0.5, B * 0.5, H * 0.86, 2.2, 3.4, 5 },
        { name = "ear",   A * 0.5, -B * 0.5, H * 0.86, 2.2, 3.4, 5 },
        { name = "leg",   A * 0.52, B * 0.55, legU + lift1, 3.4, 3.4, 5.5 },
        { name = "leg",  -A * 0.52, -B * 0.55, legU + lift1, 3.4, 3.4, 5.5 },
        { name = "leg",   A * 0.52, -B * 0.55, legU + lift2, 3.4, 3.4, 5.5 },
        { name = "leg",  -A * 0.52, B * 0.55, legU + lift2, 3.4, 3.4, 5.5 },
        { name = "tail", -A - 0.5, 0, H * 0.25, 2, 2, 2 },
    }
end

--- drawing ----------------------------------------------------------------------

-- How near (bx, by, bz), a direction on the barrel's ball, is to its two
-- nearest shards, and which the nearest is.
local function nearest(list, bx, by, bz)
    local best, next, which, other = -2, -2, nil, nil
    for i = 1, #list do
        local s = list[i]
        local dot = s[1] * bx + s[2] * by + s[3] * bz
        if dot > best then
            best, next, which, other = dot, best, s, which
        elseif dot > next then
            next, other = dot, s
        end
    end
    return best, next, which, other
end

-- The picture, as rows of runs: worked out at most once a frame, relative to
-- the barrel's middle, and handed to all three of the things that draw it.
function Piggy:raster()
    if not self.dirty and self.cache then return self.cache end
    local Fx, Fy, Fz, Sx, Sy, Sz, Ux, Uy, Uz = self:frame()
    local list = parts(self)
    local R = 26
    local hurt, broken = self.hurt, self.broken

    -- Where each solid is on the screen and how far it can reach from there,
    -- so a pixel only asks the two or three it could be on rather than all
    -- nine -- most of the cost of the picture is in asking.
    local i0, i1, j0, j1 = R, -R, R, -R
    for _, p in ipairs(list) do
        p.sx = p[1] * Fx + p[2] * Sx + p[3] * Ux
        p.sy = p[1] * Fy + p[2] * Sy + p[3] * Uy
        local r = math.max(p[4], p[5], p[6]) + 1
        p.r2 = r * r
        i0, i1 = math.min(i0, floor(p.sx - r)), math.max(i1, floor(p.sx + r) + 1)
        j0, j1 = math.min(j0, floor(p.sy - r)), math.max(j1, floor(p.sy + r) + 1)
    end
    i0, i1 = math.max(i0, -R), math.min(i1, R)
    j0, j1 = math.max(j0, -R), math.min(j1, R)

    -- First pass: the nearest solid under every pixel, its depth and its
    -- colour. Indexed by row then column, both relative to the middle.
    local zbuf, cbuf = {}, {}
    for j = j0, j1 do
        local zrow, crow = {}, {}
        zbuf[j], cbuf[j] = zrow, crow
        local v = j
        for i = i0, i1 do
            local u = i
            local bestZ, best, bq1, bq2, bq3
            for k = 1, #list do
                local p = list[k]
                local ex, ey = u - p.sx, v - p.sy
                if ex * ex + ey * ey <= p.r2 then
                    local a, b, h = p[4], p[5], p[6]
                    -- Along the ray, each of the three body coordinates is
                    -- alpha + z * beta: a quadratic in z, and the nearer root.
                    local a1 = (u * Fx + v * Fy - p[1]) / a
                    local b1 = Fz / a
                    local a2 = (u * Sx + v * Sy - p[2]) / b
                    local b2 = Sz / b
                    local a3 = (u * Ux + v * Uy - p[3]) / h
                    local b3 = Uz / h
                    local qa = b1 * b1 + b2 * b2 + b3 * b3
                    local qb = a1 * b1 + a2 * b2 + a3 * b3
                    local qc = a1 * a1 + a2 * a2 + a3 * a3 - 1
                    local disc = qb * qb - qa * qc
                    if disc >= 0 then
                        local z = (-qb + sqrt(disc)) / qa
                        if not bestZ or z > bestZ then
                            bestZ, best = z, p
                            bq1, bq2, bq3 = a1 + z * b1, a2 + z * b2, a3 + z * b3
                        end
                    end
                end
            end
            if best then
                zrow[i] = bestZ
                -- The normal: the gradient of the solid's sum, back out on the
                -- screen, then the eye's light on it.
                local nf, ns, nu = bq1 / best[4], bq2 / best[5], bq3 / best[6]
                local nx = nf * Fx + ns * Sx + nu * Ux
                local ny = nf * Fy + ns * Sy + nu * Uy
                local nz = nf * Fz + ns * Sz + nu * Uz
                local len = sqrt(nx * nx + ny * ny + nz * nz)
                nx, ny, nz = nx / len, ny / len, nz / len
                local light = LX * nx + LY * ny + LZ * nz
                local checker = (i + j) % 2 == 0
                local colour
                if light > 0.3 then
                    colour = blush
                elseif light > 0.08 then
                    colour = checker and red or blush
                elseif light > -0.35 then
                    colour = red
                else
                    colour = checker and slate or red
                end
                if HX * nx + HY * ny + HZ * nz > GLINT then colour = paper end

                local name = best.name
                if name == "snout" then
                    -- The flat of the snout, with its two nostrils.
                    if bq1 > 0.55 then
                        colour = light > -0.1 and blush or red
                        if abs(abs(bq2) - 0.38) < 0.2 and abs(bq3 + 0.05) < 0.3 then
                            colour = ink
                        end
                    end
                elseif name == "body" then
                    -- The slot along its back, the eyes over the snout, and the
                    -- cracks: in that order, each over the last.
                    if bq3 > 0.86 and abs(bq2) < 0.1 and abs(bq1 + 0.05) < 0.3 then
                        colour = ink
                    elseif bq1 > 0.6 and abs(abs(bq2) - 0.42) < 0.09
                        and abs(bq3 - 0.4) < 0.1 then
                        colour = ink
                    end
                    if hurt > 0.1 then
                        -- A little wobble into the ball's direction, so a seam
                        -- is a jagged crack and not an arc of a great circle.
                        local bx = bq1 + 0.05 * sin(bq2 * 11 + bq3 * 7)
                        local by = bq2 + 0.05 * sin(bq3 * 13 + bq1 * 5)
                        local bz = bq3
                        local n = sqrt(bx * bx + by * by + bz * bz)
                        local near, next, s1, s2 = nearest(self.shards, bx / n, by / n, bz / n)
                        if broken and s1.gone then
                            -- The inside of an empty bank.
                            colour = checker and slate or ink
                        elseif near - next < SEAM and s2
                            and math.max(s1.at, s2.at) <= hurt then
                            colour = ink
                        end
                    end
                end
                crow[i] = colour
            end
        end
    end

    -- Second pass: the rim, and the edges where one part stands in front of
    -- another -- the far side of every such edge is ink.
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

-- The silhouette, `pad` out, in whatever colour is set: the blank stamped
-- under it, a hit's rim, the flash.
function Piggy:drawMask(x, y, pad)
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

function Piggy:draw(x, y)
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

-- A coin, as the purse prints it (`coin` in Sprites.icons): ink rim, blush
-- face and a paper 1 -- or, while it is in the air and hurts, red with the
-- figure still in it, the colour of everything that is theirs.
function Piggy.coin(x, y, hot)
    x, y = floor(x) - 4, floor(y) - 4
    love.graphics.setColor(ink)
    love.graphics.rectangle("fill", x + 2, y, 5, 9)
    love.graphics.rectangle("fill", x, y + 2, 9, 5)
    love.graphics.rectangle("fill", x + 1, y + 1, 7, 7)
    love.graphics.setColor(hot and red or blush)
    love.graphics.rectangle("fill", x + 2, y + 1, 5, 7)
    love.graphics.rectangle("fill", x + 1, y + 2, 7, 5)
    love.graphics.setColor(paper)
    love.graphics.rectangle("fill", x + 4, y + 2, 1, 5)
    love.graphics.rectangle("fill", x + 3, y + 3, 1, 1)
    love.graphics.rectangle("fill", x + 3, y + 6, 3, 1)
end

-- The smear under a coin in the air, on the page where it is going to land.
function Piggy.coinShadow(x, y)
    love.graphics.setColor(graphite)
    love.graphics.rectangle("fill", floor(x) - 2, floor(y) + 3, 5, 1)
end

return Piggy
