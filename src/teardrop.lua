-- A teardrop, painted a pixel at a time off a solid one.
--
-- The eye's tears and its fan were two little sprites, and a sprite can face one
-- way: the tear was drawn pointing up so it would "read as falling whatever way
-- it was going", which is true until you watch one fly sideways out of a ball
-- that is plainly round. Next to an eye painted off a real sphere
-- (src/eyeball.lua) a flat sticker going past is the thing that looks wrong. So a
-- drop is the eye's trick at a smaller size: a solid of revolution -- a ball with
-- a cone tangent to it running back to a point -- laid along whichever way the
-- drop is moving *on the screen*, and every pixel inside its outline asked how
-- much of the light it faces. A tear lobbed up and over (Game:throwTear) points
-- up as it rises, tips over at the top and comes down head first, which is the
-- whole of what makes the arc read as an arc rather than a slide.
--
-- Still the rendering rules: whole pixels on the grid in the eight colours, the
-- same screen-fixed light the eye uses so the glint sits on the same side of
-- everything, and an ink outline one pixel out, like every sprite's. Nothing is
-- rotated -- a drop at an angle is plotted at that angle, which is what the rules
-- allow anything `pixelart` draws, and the reason the laser goes down at any
-- angle too. And the outline is the hitbox's size: the body is drawn half a pixel
-- inside the radius the drop hits with, so the art cannot lie about it.

local Palette = require("src.palette")

local Teardrop = {}

local floor, sqrt, abs = math.floor, math.sqrt, math.abs

-- The two fills, light and shaded, keyed by what a drop is. Everything the eye
-- throws is red: red is what is coming at you on this page, and a tear lands as
-- a puddle in the same blush and red, so what is in the air already looks like
-- what it will leave. A tear is told from the fan by being up in the air on an
-- arc with its shadow under it, not by its colour.
Teardrop.inks = {
    red = { Palette.blush, Palette.red },
}

-- The point is this many head radii behind the head's middle. Long enough to
-- read as a drop at five pixels across, short enough that the tail is a pixel or
-- two of colour rather than a line of outline.
local TAIL = 2.8

-- The eye's light (src/eyeball.lua): up, left and in front, fixed on the screen.
local LX, LY, LZ = -0.48, -0.62, 0.62
-- Under SHADE is the dark fill. The glint is one pixel on the head, the one
-- facing the light most squarely, and only if that one faces it well: at five
-- pixels across, a glint of more than one is a white patch rather than a shine.
local SHADE, GLINT = 0.32, 0.9

-- Reused between drops: which pixels of the box are inside.
local grid = {}

-- A drop with its head's middle at (x, y), going (vx, vy) on the screen, `r`
-- the radius it hits with, filled with `Teardrop.inks[ink]`.
function Teardrop.draw(x, y, vx, vy, r, ink)
    local fill = Teardrop.inks[ink] or Teardrop.inks.red
    local light, dark = fill[1], fill[2]
    local len = sqrt(vx * vx + vy * vy)
    local ux, uy = 0, 1
    if len > 1e-6 then ux, uy = vx / len, vy / len end
    local qx, qy = -uy, ux

    local R = math.max(0.8, r - 0.5)
    local D = R * TAIL
    local sinA = R / D
    local cosA = sqrt(1 - sinA * sinA)
    local tanA = sinA / cosA
    local hand = -R * sinA -- where the ball hands over to the cone

    -- How thick the drop is `s` along its axis (+ ahead of the head's middle),
    -- or nil past either end.
    local function radius(s)
        if s > R or s < -D then return nil end
        if s >= hand then return sqrt(R * R - s * s) end
        return (s + D) * tanA
    end

    local ext = floor(D) + 2
    local x0, y0 = floor(x) - ext, floor(y) - ext
    local size = ext * 2 + 1
    for j = 0, size - 1 do
        for i = 0, size - 1 do
            local ox, oy = x0 + i + 0.5 - x, y0 + j + 0.5 - y
            local s, t = ox * ux + oy * uy, ox * qx + oy * qy
            local w = radius(s)
            grid[j * size + i] = (w and abs(t) <= w) and true or false
        end
    end

    local best, bestX, bestY = GLINT, nil, nil
    for j = 0, size - 1 do
        for i = 0, size - 1 do
            local px, py = x0 + i, y0 + j
            if grid[j * size + i] then
                -- The surface's normal here, turned back into the screen's frame.
                local ox, oy = px + 0.5 - x, py + 0.5 - y
                local s, t = ox * ux + oy * uy, ox * qx + oy * qy
                local ns, nt, nz
                if s >= hand then
                    nz = sqrt(math.max(0, R * R - s * s - t * t))
                    ns, nt, nz = s / R, t / R, nz / R
                else
                    local w = (s + D) * tanA
                    local z = sqrt(math.max(0, w * w - t * t))
                    ns, nt, nz = -sinA, cosA * t / w, cosA * z / w
                end
                local nx, ny = ns * ux + nt * qx, ns * uy + nt * qy
                local l = LX * nx + LY * ny + LZ * nz
                if l > best and s >= hand then best, bestX, bestY = l, px, py end
                love.graphics.setColor(l < SHADE and dark or light)
                love.graphics.rectangle("fill", px, py, 1, 1)
            elseif (i > 0 and grid[j * size + i - 1]) or (i < size - 1 and grid[j * size + i + 1])
                or (j > 0 and grid[(j - 1) * size + i]) or (j < size - 1 and grid[(j + 1) * size + i]) then
                love.graphics.setColor(Palette.ink)
                love.graphics.rectangle("fill", px, py, 1, 1)
            end
        end
    end
    if bestX then
        love.graphics.setColor(Palette.paper)
        love.graphics.rectangle("fill", bestX, bestY, 1, 1)
    end
end

-- Its shadow on the page, `high` pixels under it: a smear of graphite that
-- narrows the higher the drop is, so a lobbed tear's shadow is where it is
-- going to come down and how soon.
function Teardrop.shadow(x, y, r, high)
    local w = math.max(1, floor(r * 2 + 1 - high / 6))
    love.graphics.setColor(Palette.graphite)
    love.graphics.rectangle("fill", floor(x) - floor(w / 2), floor(y), w, 1)
end

return Teardrop
