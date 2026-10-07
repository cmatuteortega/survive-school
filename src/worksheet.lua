-- Worksheets: the little puzzles printed on the page, which pay a run for
-- stopping to solve one while the horde keeps coming (WORKSHEETS.md is the
-- idea list, README **Worksheets on the page** the argument).
--
-- Two today, and each is a row in KINDS:
--
-- - **Tic-tac-toe**, on every page. A game already in play -- red O's, black
--   X's -- with one cell that finishes three X's in a row. Scribble a cross into
--   it and the line is drawn through the three and a coin drops. Scribble into
--   any other cell and the page plays its O where yours should have gone.
-- - **The pop quiz**, on MATHS. A question on a board and three answers ruled
--   out under it (src/quiz.lua). Stand on one until the circle round it has
--   finished drawing: right is a diamond, wrong is a giant walking in off the
--   ring (Spawner:giant) and the right answer circled for next time.
--
-- They are placed the way the fixed pickups are (src/pickup.lua): a pure
-- function of the cell and the run's seed, one in a fraction of a coarser
-- grid, materialising as you come near. Unlike a pickup a worksheet is never
-- dropped when you walk off -- it has state (half a cross, a circle half drawn,
-- an answer given) and a sheet you came back to should be the sheet you left --
-- so the list only grows, by one every few hundred pixels walked, and only the
-- sheets near you are updated.
--
-- Nothing here reads handwriting. A cross is *ground covered* inside a cell,
-- on a 2px grid, the rule src/scribble.lua answers every question in the book
-- by; an answer is a place you stand. Both are things the game already asks
-- you to do with your hands, so a worksheet is a new question, not a new
-- control.

local Palette = require("src.palette")
local Pickup = require("src.pickup")
local Quiz = require("src.quiz")
local Input = require("src.input")
local Camera = require("src.camera")
local Sfx = require("src.sfx")
local pixelart = require("src.pixelart")
local util = require("src.util")

local Worksheet = {}

-- Coarser than the pickups' 260 and sparser: a worksheet is an event you turn
-- for, and a page tiled in them would be a page of homework.
local CELL = 520
local DENSITY = 0.4
local MATERIALIZE = 440
local ACTIVE = 260      -- only sheets this near are updated
local CLEAR_START = 200 -- none on the spot a run begins on
local PAD = 10          -- pickups keep this far off a sheet's footprint

-- What each page prints, by weight. A subject row may carry `worksheets` of
-- its own (src/subjects.lua: MATHS); everything else plays tic-tac-toe.
local DEFAULT_MIX = { tictactoe = 1 }

local function kindFor(mix, roll)
    local keys, total = {}, 0
    for k, w in pairs(mix) do keys[#keys + 1] = k; total = total + w end
    table.sort(keys) -- pairs() has no order, and the layout must not move
    roll = roll * total
    for _, k in ipairs(keys) do
        roll = roll - mix[k]
        if roll <= 0 then return k end
    end
    return keys[1]
end

--- tic-tac-toe -------------------------------------------------------------------

local T = {}
T.__index = T

local SIZE = 14             -- one cell of the grid
local HALF = SIZE * 3 / 2
local COVER_CELL = 2
-- More than src/scribble.lua's six, because this box is on the page you fight
-- on: a stroke aimed at a blob that clips a corner of the grid must not be read
-- as an answer. One pass through a cell covers about six; a cross is two.
local COVER_MIN = 10
local COVER_FORGET = 1      -- seconds without ink before a cell's marks go
local CROSS_TIME = 0.25
local LINE_TIME = 0.4

local LINES = {
    { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },
    { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },
    { 1, 5, 9 }, { 3, 5, 7 },
}

local function three(cells, mark)
    for _, l in ipairs(LINES) do
        if cells[l[1]] == mark and cells[l[2]] == mark and cells[l[3]] == mark then
            return l
        end
    end
end

-- A game in progress, three moves each, X to play and win. Built from the
-- winning line outwards -- two X's on it and its third cell empty -- and the
-- other six dealt three O's, one more X and two blanks, rerolled until the O's
-- have not already won. A blank off the line can win too, now and then; that
-- is a second right answer and is allowed to be.
local function deal()
    for _ = 1, 50 do
        local line = LINES[love.math.random(#LINES)]
        local gap = line[love.math.random(3)]
        local cells = {}
        for _, i in ipairs(line) do
            if i ~= gap then cells[i] = "x" end
        end

        local rest = {}
        for i = 1, 9 do
            if not (i == line[1] or i == line[2] or i == line[3]) then
                rest[#rest + 1] = i
            end
        end
        for i = #rest, 2, -1 do
            local j = love.math.random(i)
            rest[i], rest[j] = rest[j], rest[i]
        end
        cells[rest[1]], cells[rest[2]], cells[rest[3]] = "o", "o", "o"
        cells[rest[4]] = "x"

        if not three(cells, "o") then return cells, gap end
    end
end

function T.new(x, y)
    local cells, gap = deal()
    return setmetatable({
        kind = "tictactoe",
        x = x, y = y,
        hw = HALF, hh = HALF,
        cells = cells, gap = gap,
        cover = {},
        state = "open",
        seed = util.hash01(x, y, 3) * 1000,
    }, T)
end

function T:cellCentre(i)
    local gx, gy = (i - 1) % 3, math.floor((i - 1) / 3)
    return self.x - HALF + (gx + 0.5) * SIZE, self.y - HALF + (gy + 0.5) * SIZE
end

-- Which cell a page point is in, held a pixel in from the rules so a line
-- drawn along one does not count for both sides of it.
function T:cellAt(px, py)
    local lx, ly = px - (self.x - HALF), py - (self.y - HALF)
    if lx < 0 or ly < 0 or lx >= SIZE * 3 or ly >= SIZE * 3 then return end
    local ix, iy = lx % SIZE, ly % SIZE
    if ix < 1 or iy < 1 or ix > SIZE - 1 or iy > SIZE - 1 then return end
    return math.floor(ly / SIZE) * 3 + math.floor(lx / SIZE) + 1
end

function T:ink(px, py)
    local i = self:cellAt(px, py)
    if not i or self.cells[i] then return end

    local key = math.floor(px / COVER_CELL) * 65536 + math.floor(py / COVER_CELL)
    local c = self.cover[i]
    if not c then c = { n = 0, keys = {}, marks = {} }; self.cover[i] = c end
    c.idle = 0
    if c.keys[key] then return end
    c.keys[key] = true
    c.n = c.n + 1
    c.marks[#c.marks + 1] = { x = math.floor(px), y = math.floor(py) }
    if c.n >= COVER_MIN then return i end
end

function T:commit(i, game)
    self.cells[i] = "x"
    self.played = i
    self.cover = {}
    self.t = 0
    self.line = three(self.cells, "x")
    if self.line then
        self.state = "crossing"
        Sfx.play("tick")
    else
        -- The page plays where you should have.
        self.cells[self.gap] = "o"
        self.blocked = self.gap
        self.state = "lost"
        Sfx.play("stamp")
    end
end

function T:update(dt, game, pen)
    if self.state == "open" then
        if pen then
            local x0, y0 = self.penX or pen.x, self.penY or pen.y
            local dx, dy = pen.x - x0, pen.y - y0
            local steps = math.max(1, math.ceil(util.len(dx, dy)))
            for s = 0, steps do
                local hit = self:ink(x0 + dx * s / steps, y0 + dy * s / steps)
                if hit then self:commit(hit, game) break end
            end
            self.penX, self.penY = pen.x, pen.y
        else
            self.penX, self.penY = nil, nil
        end
        -- A cell left alone forgets a cross it never finished: a cross is two
        -- strokes a moment apart, three grazes a minute apart are not one.
        for i, c in pairs(self.cover) do
            c.idle = c.idle + dt
            if c.idle > COVER_FORGET then self.cover[i] = nil end
        end
        return
    end

    self.t = (self.t or 0) + dt
    if self.state == "crossing" and self.t >= CROSS_TIME + LINE_TIME then
        self.state = "won"
        -- Under the grid rather than on it, so the line it paid for stays read.
        local cy = self.y + HALF + 8
        game.pickups[#game.pickups + 1] = Pickup.new("coin", self.x, cy)
        game.particles:burst(self.x, cy, 10, Palette.blush)
        game:say("THREE IN A ROW")
        Sfx.play("accept")
    end
end

local function drawCross(cx, cy, p)
    local a = util.clamp(p * 2, 0, 1)
    local b = util.clamp(p * 2 - 1, 0, 1)
    if a > 0 then
        pixelart.band(cx - 4, cy - 4, cx - 4 + 8 * a, cy - 4 + 8 * a, 2)
    end
    if b > 0 then
        pixelart.band(cx + 4, cy - 4, cx + 4 - 8 * b, cy - 4 + 8 * b, 2)
    end
end

function T:draw()
    local x0, y0 = math.floor(self.x - HALF), math.floor(self.y - HALF)

    -- The rules, a pixel off true here and there the way a ruled-by-hand grid
    -- is, and fixed: this is something you aim at.
    love.graphics.setColor(Palette.slate)
    for k = 1, 2 do
        local o = k * SIZE
        local w = util.hash01(self.seed, k, 1) > 0.5 and 1 or 0
        love.graphics.rectangle("fill", x0 + o + w, y0 - 1, 1, SIZE * 3 + 2)
        love.graphics.rectangle("fill", x0 - 1, y0 + o - w, SIZE * 3 + 2, 1)
    end

    for i = 1, 9 do
        local cx, cy = self:cellCentre(i)
        if self.cells[i] == "o" then
            love.graphics.setColor(Palette.red)
            pixelart.circleOutline(cx, cy, 4)
            if i == self.blocked then pixelart.circleOutline(cx, cy, 3) end
        elseif self.cells[i] == "x" then
            love.graphics.setColor(Palette.ink)
            local p = 1
            if i == self.played then p = util.clamp(self.t / CROSS_TIME, 0, 1) end
            drawCross(cx, cy, p)
        end
    end

    love.graphics.setColor(Palette.graphite)
    for _, c in pairs(self.cover) do
        for _, m in ipairs(c.marks) do
            love.graphics.rectangle("fill", m.x, m.y, 1, 1)
        end
    end

    -- Struck through, end to end and a little past, as fast as a pen would.
    if self.line and self.t and self.t > CROSS_TIME then
        local p = util.clamp((self.t - CROSS_TIME) / LINE_TIME, 0, 1)
        local ax, ay = self:cellCentre(self.line[1])
        local bx, by = self:cellCentre(self.line[3])
        local ux, uy = util.normalize(bx - ax, by - ay)
        ax, ay = ax - ux * 5, ay - uy * 5
        bx, by = bx + ux * 5, by + uy * 5
        love.graphics.setColor(Palette.ink)
        pixelart.band(ax, ay, ax + (bx - ax) * p, ay + (by - ay) * p, 2)
    end
end

--- the pop quiz ------------------------------------------------------------------

local Q = {}
Q.__index = Q

local SPACING = 44      -- between answer centres
local BOARD_UP = 20     -- the board's middle, above the sheet's
local ANSWERS_DOWN = 14 -- the answers' line, below it
local HOLD = 1.5        -- seconds stood on an answer to give it
local DRAIN = 2         -- how much faster a circle undraws than draws
local RY = 7

function Q.new(x, y, courseKey)
    local quiz = Quiz.new(courseKey)
    local q = setmetatable({
        kind = "quiz",
        x = x, y = y,
        quiz = quiz,
        board = Quiz.layout(quiz.q),
        answers = {},
        state = "open",
        seed = util.hash01(x, y, 4) * 1000,
    }, Q)

    for i, a in ipairs(quiz.answers) do
        local lay = Quiz.layout(a)
        q.answers[i] = {
            lay = lay,
            x = x + (i - 2) * SPACING,
            y = y + ANSWERS_DOWN,
            rx = math.max(9, math.floor(lay.w / 2) + 5),
            hold = 0,
        }
    end

    q.bw = math.max(q.board.w + 12, SPACING * 2)
    q.bh = q.board.bottom - q.board.top + 10
    q.hw = math.max(q.bw / 2, SPACING + q.answers[3].rx)
    q.hh = math.max(BOARD_UP + q.bh / 2 + 2, ANSWERS_DOWN + RY + 2)
    return q
end

function Q:standingOn(px, py)
    for i, a in ipairs(self.answers) do
        local dx, dy = (px - a.x) / a.rx, (py - a.y) / RY
        if dx * dx + dy * dy <= 1 then return i end
    end
end

function Q:update(dt, game)
    if self.state ~= "open" then return end

    local on = self:standingOn(game.player.x, game.player.y)
    for i, a in ipairs(self.answers) do
        if i == on then
            a.hold = a.hold + dt / HOLD
        else
            a.hold = math.max(0, a.hold - dt * DRAIN / HOLD)
        end
    end

    if on and self.answers[on].hold >= 1 then
        self.state = "done"
        self.chosen = on
        if on == self.quiz.right then
            -- Just above the answer you are standing on, between it and the
            -- board: a step away, so taking it is a thing you do and the
            -- question it paid for is not hidden under it.
            local dx, dy = self.answers[on].x, self.y - 2
            game.pickups[#game.pickups + 1] = Pickup.new("diamond", dx, dy)
            game.particles:burst(dx, dy, 10, Palette.sky)
            game:say("CORRECT!")
            Sfx.play("accept")
        else
            game.spawner:giant(game)
            game.particles:burst(self.answers[on].x, self.answers[on].y, 10, Palette.red)
            game:say("WRONG ANSWER")
            Sfx.play("stamp")
        end
    end
end

-- A hand-drawn ring round an answer, laid clockwise from twelve o'clock as far
-- as `p` has got: two pixels thick, the second ring a pixel out.
local function ring(cx, cy, rx, ry, p, dotted)
    local n = math.floor(2 * math.pi * math.max(rx, ry) * 1.5)
    local last = math.floor(n * util.clamp(p, 0, 1))
    for k = 0, last - 1 do
        if not dotted or k % 4 == 0 then
            local a = -math.pi / 2 + 2 * math.pi * k / n
            local c, s = math.cos(a), math.sin(a)
            love.graphics.rectangle("fill",
                math.floor(cx + c * rx + 0.5), math.floor(cy + s * ry + 0.5), 1, 1)
            if not dotted then
                love.graphics.rectangle("fill",
                    math.floor(cx + c * (rx + 1) + 0.5),
                    math.floor(cy + s * (ry + 1) + 0.5), 1, 1)
            end
        end
    end
end

function Q:draw()
    -- The board: a box ruled round the question, the question in ink.
    local bx = math.floor(self.x - self.bw / 2)
    local by = math.floor(self.y - BOARD_UP - self.bh / 2)
    love.graphics.setColor(Palette.slate)
    love.graphics.rectangle("fill", bx, by, self.bw, 1)
    love.graphics.rectangle("fill", bx, by + self.bh - 1, self.bw, 1)
    love.graphics.rectangle("fill", bx, by, 1, self.bh)
    love.graphics.rectangle("fill", bx + self.bw - 1, by, 1, self.bh)
    love.graphics.rectangle("fill", bx + 1, by + self.bh, self.bw - 1, 1)

    love.graphics.setColor(Palette.ink)
    Quiz.print(self.board, self.x - self.board.w / 2, by + 5 - self.board.top)

    local right = self.quiz.right
    for i, a in ipairs(self.answers) do
        local lay = a.lay
        local tx = a.x - lay.w / 2
        local ty = a.y - math.floor((lay.bottom + lay.top) / 2)
        love.graphics.setColor(self.chosen and i ~= self.chosen and i ~= right
            and Palette.graphite or Palette.ink)
        Quiz.print(lay, tx, ty)

        if self.state == "open" then
            -- Where to stand, dotted, and how long you have stood there.
            love.graphics.setColor(Palette.graphite)
            ring(a.x, a.y, a.rx, RY, 1, true)
            if a.hold > 0 then
                love.graphics.setColor(Palette.blue)
                ring(a.x, a.y, a.rx, RY, a.hold)
            end
        elseif i == self.chosen and i ~= right then
            -- Yours, circled and struck out.
            love.graphics.setColor(Palette.red)
            ring(a.x, a.y, a.rx, RY, 1)
            pixelart.band(tx - 2, a.y + 2, tx + lay.w + 2, a.y - 2, 1)
        elseif i == right then
            love.graphics.setColor(Palette.blue)
            ring(a.x, a.y, a.rx, RY, 1)
        end
    end
end

--- the page ------------------------------------------------------------------------

local KINDS = {
    tictactoe = function(x, y) return T.new(x, y) end,
    quiz = function(x, y, game) return Q.new(x, y, game.course.key) end,
}

function Worksheet.init(game)
    game.worksheets = {}
    game.worksheetCells = {}
    game.worksheetMix = game.subject.worksheets or DEFAULT_MIX
end

local function fixedAt(cx, cy, seed, mix)
    if util.hash01(cx, cy, seed + 21) >= DENSITY then return end
    return kindFor(mix, util.hash01(cx, cy, seed + 22)),
        (cx + 0.25 + util.hash01(cx, cy, seed + 23) * 0.5) * CELL,
        (cy + 0.25 + util.hash01(cx, cy, seed + 24) * 0.5) * CELL
end

-- Wake the sheets within reach that have not been printed yet. Each cell is
-- looked at once a run: printed, or found empty, it is never asked again.
-- Not during a boss fight -- the box is the fight, and a sheet printed into it
-- would be a prize nobody could stop for.
function Worksheet.materialize(game)
    if game.arena then return end
    local px, py = game.player.x, game.player.y
    for cy = math.floor((py - MATERIALIZE) / CELL),
             math.floor((py + MATERIALIZE) / CELL) do
        for cx = math.floor((px - MATERIALIZE) / CELL),
                 math.floor((px + MATERIALIZE) / CELL) do
            local key = cx * 100000 + cy
            if not game.worksheetCells[key] then
                local kind, x, y = fixedAt(cx, cy, game.pickupSeed, game.worksheetMix)
                if not kind then
                    game.worksheetCells[key] = true
                elseif util.len(x - px, y - py) < MATERIALIZE then
                    game.worksheetCells[key] = true
                    if util.len(x, y) > CLEAR_START then
                        game.worksheets[#game.worksheets + 1] = KINDS[kind](x, y, game)
                    end
                end
            end
        end
    end
end

function Worksheet.update(game, dt)
    Worksheet.materialize(game)

    -- The pen on the page, read the way Game:updateDrawing reads it -- through
    -- the steady camera, never the knocked one.
    local pen
    if Input.pointerDown then
        local left, top = Camera.steady()
        pen = { x = Input.pointerX + left, y = Input.pointerY + top }
    end

    local px, py = game.player.x, game.player.y
    for _, s in ipairs(game.worksheets) do
        if math.abs(s.x - px) < ACTIVE and math.abs(s.y - py) < ACTIVE then
            s:update(dt, game, pen)
        end
    end
end

function Worksheet.draw(game)
    local left, top, w, h = Camera.bounds()
    for _, s in ipairs(game.worksheets) do
        if s.x + s.hw > left - 4 and s.x - s.hw < left + w + 4
            and s.y + s.hh > top - 4 and s.y - s.hh < top + h + 4 then
            s:draw()
        end
    end
end

-- Whether a pickup at this point would land on a sheet, which the scatter
-- and the fixed pickups both ask before they put one down: a heart lying on a
-- tic-tac-toe cell is a prize and a puzzle each saying the other is not there.
function Worksheet.covers(game, x, y)
    if not game.worksheets then return false end
    for _, s in ipairs(game.worksheets) do
        if math.abs(x - s.x) < s.hw + PAD and math.abs(y - s.y) < s.hh + PAD then
            return true
        end
    end
    return false
end

return Worksheet
