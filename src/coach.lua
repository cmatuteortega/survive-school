-- The hand that shows you how. A pointing finger slides in, draws a dashed
-- scribble across something, lifts away, and does it again -- the whole of the
-- game's tutorial, because the whole of the game's input is one gesture
-- (README **Asking by drawing**) and the gesture is the thing that has to be
-- taught. Two screens use it, and both for the same lesson: the title shows it
-- scribbling the YES box (src/menu.lua), and the opening seconds of a run show
-- it scribbling across a monster (Game:updateCoach) -- the box is how you
-- answer, the monster is how you fight, and it is the same scribble both times
-- on purpose.
--
-- **It never draws anything.** The line it lays is dashed, and it is dashed so
-- that it cannot be mistaken for ink: a solid line would be a mark the page had
-- made for you, and a box that a hint had half filled in would be a box the
-- player had not answered. Nothing here is fed to a box or a stroke; it is a
-- picture of a gesture, drawn out past the overprint pass with the rest of the
-- game's furniture, and the screen underneath it never knows it was there.
--
-- It is told nothing about what it is drawing over. The caller hands it a
-- rectangle every frame, and the scribble is laid across that rectangle *as it
-- is now* -- so a hint drawn across a monster that is walking keeps to the
-- monster rather than to where the monster was when the loop began.

local Palette = require("src.palette")
local Sprites = require("src.sprites")
local util = require("src.util")

local Coach = {}
Coach.__index = Coach

-- One loop, in seconds: the hand comes in, draws, holds still on the finished
-- line long enough for it to be read, lifts away while the line drops out a
-- stamp at a time (the dither every fade in this game is made of), and rests.
local APPROACH = 0.5
local DRAW = 1.0
local HOLD = 0.35
local LIFT = 0.45
local REST = 0.55
local CYCLE = APPROACH + DRAW + HOLD + LIFT + REST

-- Sweeps across the rectangle: the zigzag the keyboard's scribble lays in a box
-- (src/scribble.lua), at half its six sweeps. A dashed line is a third gaps, and
-- six passes of it across a box twenty pixels high run together into a grey
-- smudge; three are three strokes you can follow.
local ROWS = 3

-- The dashes, in stamps: so many on, so many off, along the path. A stamp is
-- the answering nib's 2px square (Scribble.stamp's core), which is what makes a
-- dash read as the same pen at a glance.
local DASH, GAP = 3, 3

-- Where the hand comes in from and goes back to, off the start of the line: down
-- and to the right, which is where a hand holding a pen actually is.
local REACH_X, REACH_Y = 16, 14

local function ease(f)
    return f * f * (3 - 2 * f)
end

-- A point on the zigzag for u in 0..1, as an offset into a w x h rectangle.
local function zig(u, w, h)
    local p = u * ROWS
    local row = math.floor(p)
    local f = p - row
    if row % 2 == 1 then f = 1 - f end
    return f * w, u * h
end

function Coach.new(seed)
    return setmetatable({ t = 0, seed = seed or 0 }, Coach)
end

-- Back to the start of a loop, so the next time it is shown it comes in from
-- the side rather than appearing mid-line.
function Coach:reset()
    self.t = 0
end

function Coach:update(dt)
    self.t = (self.t + dt) % CYCLE
end

-- Draws the loop across the rectangle (x, y, w, h) in canvas space -- or world
-- space, if the caller has the camera attached; nothing here cares which.
function Coach:draw(x, y, w, h)
    local c = self.t
    local u, dither, slide = 0, 0, 0
    local pressed = false

    if c < APPROACH then
        slide = 1 - ease(c / APPROACH)
    elseif c < APPROACH + DRAW then
        u = (c - APPROACH) / DRAW
        pressed = true
    elseif c < APPROACH + DRAW + HOLD then
        u = 1
        pressed = true
    elseif c < APPROACH + DRAW + HOLD + LIFT then
        u = 1
        local f = (c - APPROACH - DRAW - HOLD) / LIFT
        dither = f
        slide = ease(f)
    else
        return
    end

    -- The dashed line, laid a stamp a pixel along the path the way the
    -- keyboard's scribble is, so the dashes are evenly spaced whatever shape of
    -- rectangle it is drawn across.
    local length = math.max(1, math.floor(ROWS * w + h))
    local n = math.floor(length * u)
    love.graphics.setColor(Palette.slate)
    for s = 0, n do
        if s % (DASH + GAP) < DASH
            and (dither == 0 or util.hash01(s, self.seed, 31) > dither) then
            local dx, dy = zig(s / length, w, h)
            love.graphics.rectangle("fill", math.floor(x + dx), math.floor(y + dy), 2, 2)
        end
    end

    -- The hand, its fingertip on the head of the line. Coming in and going out
    -- it is off towards its own wrist; while it is drawing it sits a pixel lower,
    -- which is all a press is at this size.
    local hx, hy
    if c < APPROACH then
        hx, hy = x, y
    else
        local dx, dy = zig(u, w, h)
        hx, hy = x + dx, y + dy
    end
    hx = hx + REACH_X * slide
    hy = hy + REACH_Y * slide + (pressed and 1 or 0)

    -- Thrown down rather than slid in the last stretch of the lift, so it does
    -- not sit there in full while the line under it has already gone.
    if dither > 0.7 then return end

    -- No shadow under it, unlike everything standing on the page: it is not
    -- standing on the page, it is hovering over it.
    love.graphics.setColor(1, 1, 1)
    Sprites.hand:draw(math.floor(hx), math.floor(hy))
end

return Coach
