-- The FINANCE boss's mind: an office rubber stamp, and the fight in the book
-- about *cells*.
--
-- The eye is a fight about the ground, the whistle about the air and the
-- metronome about time. This one is about the page itself: the ledger is a grid
-- of cells forty across and twelve down, the stamp's pad is exactly one of them
-- (its model in src/solids.lua), and everything it does it does by coming down
-- on one. A cell
-- it means to hit is outlined on the page before it arrives, so the question
-- every move asks is the same -- which cell are you in, and is it about to be
-- stamped -- and the answer is always to be in a different one.
--
-- **The cells are the printed ones.** The ledger tiles the world (src/background
-- draws the page in world coordinates), so the cell under any point can be
-- worked out from the page's own numbers (`LEDGER` in src/subjects.lua: a ten
-- pixel header column, five cells of forty, an eight pixel header band, ten
-- rows of twelve). A stamp landing in a box lands between the page's own lines,
-- and the mark it leaves fills the box it landed in.
--
-- **It moves the way a stamp is used.** It rocks back on its heel before it
-- goes, pitches forward as it comes down and flattens when it hits, which are
-- the four poses of its body (`poses` on its row in src/solids.lua, eased
-- between, so the rock is a rock and the squash springs back); the brain says
-- which one, through `e.pose`, and how high off the page, through `e.hop`. The
-- rock back is the tell for everything it does, short for a hop and long for
-- the moves below, so a stamp leaning away from you is a stamp about to land.
--
--  - **It hops at you.** Between moves it comes on in short hops, rocking back
--    before each, and every couple of seconds it flicks a blot of ink at you, so
--    standing still is never free.
--  - **The slam.** It rocks back and holds it while the cell you are in blinks
--    under you -- the outline follows you for as long as it is leaning -- then
--    locks the cell and leaps. The answer is to be out of the cell when it comes
--    down, which a cell twelve deep makes easy and the leap's half second makes
--    fair. It lands hard, and then it is stuck where it landed for a second:
--    the window the move paid for. From the second third its landing throws ink.
--  - **The run.** It reads along a row of the ledger, a cell a hop, quicker than
--    you walk, stepping one row towards you with every hop. It cannot be
--    outrun along the row and it follows you up and down, so the answer is to
--    cross its path rather than leave it -- and every cell it hit is wet.
--  - **The audit.** From the second third: every other cell in a block round
--    you is outlined, a chequerboard, and then it stamps through all of them a
--    row at a time. Stand in a blank one. At the last third it audits twice, the
--    second time the *other* colour, once the first lot of ink has dried -- so
--    the cell you hid in is the one cell you cannot stay in.
--
-- **Every stamp leaves a mark**: the word PAID in a box, wet red ink for a
-- moment -- which hurts to stand in, rate limited by your own invulnerability
-- the way a puddle is -- and then dry, a record on the page that does nothing
-- and fades. Wet ink is what turns the run into a wall and the audit's first
-- pass into a board you have to wait on.
--
-- **Glue holds it to the page.** A glued stamp drops whatever it was doing where
-- it is -- out of the air if it was in the air, without stamping -- and stands
-- for the rest of the hold. A considered line drawn across a block is the whole
-- of the FINANCE lesson, and the ruler it hands you is the other answer: the
-- stamp is stuck for a second after every slam, which is the second to aim in.

local Palette = require("src.palette")
local Solids = require("src.solids")
local Camera = require("src.camera")
local Font = require("src.font")
local I18n = require("src.i18n")
local Sfx = require("src.sfx")
local util = require("src.util")

local Stamp = {}
Stamp.__index = Stamp

local function pick(list, phase) return type(list) == "table" and list[phase] or list end

-- How hard a move hits, scaled the way its contact damage was (Enemy.new): the
-- number on the row is the first cycle's.
local function scaled(e, damage) return damage * e.damage / e.def.damage end

--- the ledger -----------------------------------------------------------------

-- The page's numbers (`LEDGER` in src/subjects.lua), which this file has to
-- agree with to the pixel for a stamp to land between its lines. Columns are
-- counted across the whole world, five a tile; rows the same, ten a tile.
local TILE_W, HEAD_W, CELL_W, COLS = 210, 10, 40, 5
local TILE_H, HEAD_H, CELL_H, ROWS = 128, 8, 12, 10

local function colLeft(c) return math.floor(c / COLS) * TILE_W + HEAD_W + (c % COLS) * CELL_W end
local function rowTop(r) return math.floor(r / ROWS) * TILE_H + HEAD_H + (r % ROWS) * CELL_H end

local function colAt(x)
    local t = math.floor(x / TILE_W)
    local c = util.clamp(math.floor((x - t * TILE_W - HEAD_W) / CELL_W), 0, COLS - 1)
    return t * COLS + c
end
local function rowAt(y)
    local t = math.floor(y / TILE_H)
    local r = util.clamp(math.floor((y - t * TILE_H - HEAD_H) / CELL_H), 0, ROWS - 1)
    return t * ROWS + r
end

-- The middle of a cell, which is where the middle of the pad goes.
local function cellMid(c, r) return colLeft(c) + CELL_W / 2, rowTop(r) + CELL_H / 2 end

-- Whether a point is on a cell: its middle inside the box, give or take `pad`.
-- The middle and not the whole body, for the chord's reason in src/metronome.lua:
-- the cell next to a stamped one has to be somewhere you can stand.
--
-- The headers count as the cell after them. They are the thick bands between
-- one tile of cells and the next, and `colAt` / `rowAt` already file a point
-- standing in one under the cell to its right or below it -- so a stamp aimed
-- at you there lands on that cell, and it has to be able to hit you there too,
-- or a header would be a place no move could reach.
local function onCell(x, y, c, r, pad)
    local l, t = colLeft(c), rowTop(r)
    local l0 = c % COLS == 0 and l - HEAD_W or l
    local t0 = r % ROWS == 0 and t - HEAD_H or t
    return x >= l0 - pad and x <= l + CELL_W + pad and y >= t0 - pad and y <= t + CELL_H + pad
end

-- Where the stamp's own origin goes to put its pad on a cell: the pad is
-- `foot` pixels below the origin (src/solids.lua).
local function seat(c, r)
    local x, y = cellMid(c, r)
    return x, y - Solids.stamp.foot
end

--- the brain ------------------------------------------------------------------

function Stamp.new(def)
    local s = def.stamp
    return setmetatable({
        def = s,
        phase = 1,
        state = "idle",
        t = pick(s.cool, 1),
        hopT = pick(s.hop.every, 1) * 0.5,
        blotT = s.blot.every * 0.6,
        jump = nil,         -- the leap it is in the air for, if it is
        targets = nil,      -- cells outlined on the page, still to be stamped
        marks = {},         -- what it has printed, wet and dry
        last = nil, before = nil,
        e = nil,
    }, Stamp)
end

function Stamp:busy()
    return self.state ~= "idle"
end

-- The pose and the height off the page, for Enemy:footing.
function Stamp:pose(e, name, hop)
    e.pose, e.hop = name, hop or 0
end

function Stamp:update(dt, game, e)
    self.e = e
    if dt <= 0 then return end

    -- The marks dry and fade whatever the stamp is doing, glued or not: ink is
    -- on the page, not on the stamp.
    self:inkUpdate(dt, game)

    -- The phase, at the eye's thirds. The second unlocks the audit and says so.
    local share = e.hp / e.maxHp
    local phase = share > 0.66 and 1 or share > 0.33 and 2 or 3
    if phase > self.phase then
        self.phase = phase
        Camera.knock(phase >= 3 and 3 or 2)
        game.particles:burst(e.x, e.y, phase >= 3 and 24 or 14, Palette.red)
        game:say(phase == 2 and "AUDIT!" or "FASTER!")
    end

    -- Stuck to the page: down, and still. A move it was in the middle of is
    -- dropped rather than finished -- a leap comes down where it is, without
    -- stamping -- and what it does when it comes free is start again.
    if e.frozen > 0 then
        if self.state ~= "idle" and self.state ~= "rest" then
            self.jump, self.targets, self.lane = nil, nil, nil
            self.state, self.t = "rest", 0.4
        end
        self:pose(e, "stand", 0)
        e.drive = { hold = true }
        return
    end

    self.t = self.t - dt
    e.drive = { hold = true }
    -- What hurts in a move is the pad on a cell (Stamp:strike), never the body
    -- brushing you on its way between two: a stamp landing in the cell above
    -- yours is close enough to touch, and the audit's blank cells have to be
    -- somewhere you can stand.
    if self.state ~= "idle" and self.state ~= "rest" then
        e.hitCooldown = math.max(e.hitCooldown, 0.1)
    end
    if self.jump then self:fly(dt, game, e) end
    self[self.state](self, dt, game, e)
end

--- leaping --------------------------------------------------------------------

-- A leap from where it stands to (x, y) over `time`, `high` pixels at the top,
-- calling `land` when it comes down. The body is moved here rather than walked:
-- a leap is a line through the air, and nothing on the page bends it.
--
-- Never quicker than LEAP_MOST pixels a second, whatever the move asked for: an
-- audit's first cell or a run's first row can be across the box, and a stamp
-- that crossed the box in a tenth of a second would be a stamp that was not
-- seen to move.
local LEAP_MOST = 500

function Stamp:leap(e, x, y, time, high, land)
    time = math.max(time, util.len(x - e.x, y - e.y) / LEAP_MOST)
    self.jump = { x0 = e.x, y0 = e.y, x1 = x, y1 = y, time = time, t = 0,
                  high = high, land = land }
end

function Stamp:fly(dt, game, e)
    local j = self.jump
    j.t = j.t + dt
    local f = math.min(1, j.t / j.time)
    e.x = j.x0 + (j.x1 - j.x0) * f
    e.y = j.y0 + (j.y1 - j.y0) * f
    e.headX, e.headY = util.normalize(j.x1 - j.x0, j.y1 - j.y0)
    local h = math.floor(4 * j.high * f * (1 - f) + 0.5)
    -- Up straight on the way up, pitched forward on the way down: a stamp is
    -- brought down face first.
    self:pose(e, f < 0.55 and "stand" or "lean", h)
    -- Over your head is not touching you.
    if h > 6 then e.hitCooldown = math.max(e.hitCooldown, 0.1) end
    if f >= 1 then
        self.jump = nil
        self:pose(e, "squash", 0)
        if j.land then j.land(self, game, e) end
    end
end

-- Coming down on a cell: whoever is on it is hit, the cell is inked, the page
-- jumps. `move` is the block on the row the stamp is playing, which says how
-- hard and how long the ink stays wet.
function Stamp:strike(game, e, c, r, move)
    local p = game.player
    if onCell(p.x, p.y, c, r, 2) then
        if p:hurt(scaled(e, move.damage)) then
            game.particles:burst(p.x, p.y, 8, Palette.red)
        end
    end
    self:ink(c, r, move.wet, scaled(e, self.def.ink.damage))
    local x, y = cellMid(c, r)
    game.particles:burst(x, y, 6, Palette.red)
    Camera.knock(move.knock or 1)
    Sfx.play("stamp")
end

-- Facing up or down the page -- whichever way you are -- for a move that
-- stamps: the pad is a cell only seen square on.
function Stamp:square(game, e)
    e.face = game.player.y < e.y and -math.pi / 2 or math.pi / 2
end

--- the marks ------------------------------------------------------------------

function Stamp:ink(c, r, wet, damage)
    -- A cell stamped twice is one mark, wetted again.
    for _, m in ipairs(self.marks) do
        if m.c == c and m.r == r then
            m.wet, m.age, m.damage = wet, 0, damage
            return
        end
    end
    self.marks[#self.marks + 1] = { c = c, r = r, wet = wet, age = 0, damage = damage }
end

function Stamp:inkUpdate(dt, game)
    local p = game.player
    local hit = false
    local dry = self.def.ink.dry
    for i = #self.marks, 1, -1 do
        local m = self.marks[i]
        m.wet = m.wet - dt
        if m.wet <= 0 then m.age = m.age + dt end
        if m.age > dry then
            table.remove(self.marks, i)
        elseif m.wet > 0 and not hit and onCell(p.x, p.y, m.c, m.r, 0) then
            hit = true
            if p:hurt(m.damage) then game.particles:burst(p.x, p.y, 5, Palette.red) end
        end
    end
end

--- walking about --------------------------------------------------------------

function Stamp:idle(dt, game, e)
    local def = self.def
    e.face = nil
    if not self.jump then
        self.hopT = self.hopT - dt
        local rear = def.hop.rear
        if self.hopT <= 0 then
            -- A hop at you: a short leap a little way along the line to you.
            self.hopT = pick(def.hop.every, self.phase)
            local p = game.player
            local dx, dy, d = util.normalize(p.x - e.x, p.y - e.y)
            local step = math.min(def.hop.reach, math.max(0, d - 10))
            local x, y = e.x + dx * step, e.y + dy * step
            if game.arena then x, y = game.arena:clamp(x, y, e.radius + 2) end
            self:leap(e, x, y, def.hop.time, def.hop.high, function(s, g, en)
                s.thud = def.hop.squash
                g.particles:burst(en.x, en.y + Solids.stamp.foot, 3, Palette.slate)
            end)
        elseif self.thud and self.thud > 0 then
            self.thud = self.thud - dt
            self:pose(e, "squash", 0)
        else
            self:pose(e, self.hopT < rear and "rear" or "stand", 0)
        end
    end

    self.blotT = self.blotT - dt
    if self.blotT <= 0 then
        self.blotT = def.blot.every
        self:blot(game, e, math.atan2(game.player.y - e.y, game.player.x - e.x))
    end

    if self.t <= 0 and not self.jump then self:choose(game, e) end
end

-- A blot of ink, flicked off the pad.
function Stamp:blot(game, e, a)
    local b = self.def.blot
    game.shots[#game.shots + 1] = {
        x = e.x, y = e.y + Solids.stamp.foot, dx = math.cos(a), dy = math.sin(a),
        speed = b.speed, damage = scaled(e, b.damage), life = b.life,
        radius = b.hit * e.reach, grow = e.grow,
    }
end

-- The choice, off how far away you are and away from what it just did: the
-- slam for someone near, the run for someone keeping away along the page, the
-- audit -- a whole-block move -- once the second third has unlocked it.
function Stamp:choose(game, e)
    local def = self.def
    local d = util.len(game.player.x - e.x, game.player.y - e.y)
    local w = {
        slam = d < 140 and 1.5 or 0.8,
        run = d > 50 and 1.3 or 0.6,
    }
    if self.phase >= def.audit.from then w.audit = 1.1 end
    if self.last and w[self.last] then w[self.last] = w[self.last] * 0.15 end
    if self.before and w[self.before] then w[self.before] = w[self.before] * 0.6 end

    local total = 0
    for _, v in pairs(w) do total = total + v end
    local roll = love.math.random() * total
    local move = "slam"
    for _, name in ipairs({ "slam", "run", "audit" }) do
        if w[name] then
            roll = roll - w[name]
            if roll <= 0 then move = name break end
        end
    end
    self.before, self.last = self.last, move
    self[move .. "Start"](self, game, e)
end

-- Done with a move: stood where it landed for the window the move paid for.
function Stamp:rest(dt, game, e)
    if self.thud and self.thud > 0 then
        self.thud = self.thud - dt
        self:pose(e, "squash", 0)
    else
        self:pose(e, "stand", 0)
    end
    if self.t <= 0 then
        self.state, self.t = "idle", pick(self.def.cool, self.phase)
        self.targets = nil
        e.face = nil
    end
end

function Stamp:restFor(t)
    self.state, self.t, self.thud = "rest", t, self.def.hop.squash * 2
    self.targets = nil
end

-- The cell nearest (x, y) the stamp can sit on without the box pushing it off:
-- the box is a clamp on the body (Game:updateEnemies), so a cell whose seat is
-- outside it is a cell the pad would land beside.
function Stamp:cellNear(game, x, y)
    local c, r = colAt(x), rowAt(y)
    local box = game.arena
    if not box then return c, r end
    local pad = (self.e and self.e.radius or 12) + 1
    for _ = 1, 8 do
        local sx, sy = seat(c, r)
        local moved = false
        if sx < box.left + pad then c, moved = c + 1, true
        elseif sx > box:right() - pad then c, moved = c - 1, true end
        if sy < box.top + pad then r, moved = r + 1, true
        elseif sy > box:bottom() - pad then r, moved = r - 1, true end
        if not moved then break end
    end
    return c, r
end

function Stamp:fits(game, c, r)
    local box = game.arena
    if not box then return true end
    local pad = (self.e and self.e.radius or 12) + 1
    local sx, sy = seat(c, r)
    return sx >= box.left + pad and sx <= box:right() - pad
        and sy >= box.top + pad and sy <= box:bottom() - pad
end

--- the slam -------------------------------------------------------------------

function Stamp:slamStart(game, e)
    self.state, self.t = "slam", pick(self.def.slam.rear, self.phase)
    self:square(game, e)
    self.targets = {}
end

function Stamp:slam(dt, game, e)
    local s = self.def.slam
    if self.jump then return end
    if self.t > 0 then
        -- Leaning back, with the cell under you blinking: it follows you until
        -- the moment it goes.
        self:pose(e, "rear", 0)
        self:square(game, e)
        local c, r = self:cellNear(game, game.player.x, game.player.y)
        self.targets = { { c = c, r = r } }
        return
    end
    local cell = self.targets[1]
    local x, y = seat(cell.c, cell.r)
    self:leap(e, x, y, s.fly, s.high, function(st, g, en)
        st:strike(g, en, cell.c, cell.r, s)
        -- From the second third the landing throws the ink it pressed out.
        local n = pick(s.splash, st.phase)
        for k = 1, n do st:blot(g, en, (k - 0.5) / n * math.pi * 2) end
        st:restFor(pick(s.rest, st.phase))
    end)
end

--- the run --------------------------------------------------------------------

-- Along the row you are in, from its own side of you, one cell a hop, stepping
-- a row towards you on every hop. The cells are outlined as it goes rather than
-- all at once, because which row the next one is in depends on you.
function Stamp:runStart(game, e)
    local p = game.player
    local dir = p.x >= e.x and 1 or -1
    local c, r = self:cellNear(game, e.x, p.y)
    -- Kept as `lane` because `run` is the state, and the state is a method.
    self.lane = { dir = dir, left = pick(self.def.run.count, self.phase), first = true }
    self.state, self.t = "run", self.def.run.rear
    self:square(game, e)
    self.targets = { { c = c, r = r } }
end

function Stamp:run(dt, game, e)
    local s, run = self.def.run, self.lane
    if self.jump then return end
    if self.t > 0 then
        self:pose(e, "rear", 0)
        return
    end
    if run.left <= 0 then
        self.lane = nil
        self:restFor(s.rest)
        return
    end
    local cell = self.targets[1]
    local x, y = seat(cell.c, cell.r)
    run.left = run.left - 1
    -- The first hop is onto your row from wherever it was standing, which may
    -- be a long way: that one is given the slam's leap rather than a step.
    local time = run.first and self.def.slam.fly or s.step
    run.first = false
    self:leap(e, x, y, time, s.high, function(st, g, en)
        st:strike(g, en, cell.c, cell.r, s)
        -- The next cell: one along, and a row towards you if you are not in
        -- this one. Turned back at the box rather than stamped beside it.
        local pr = rowAt(g.player.y)
        local nr = cell.r + (pr > cell.r and 1 or pr < cell.r and -1 or 0)
        local nc = cell.c + run.dir
        if not st:fits(g, nc, nr) then
            run.dir = -run.dir
            nc = cell.c + run.dir
        end
        if not st:fits(g, nc, nr) then nr = cell.r end
        if not st:fits(g, nc, nr) then run.left = 0 end
        st.targets = { { c = nc, r = nr } }
        st:square(g, en)
        st.thud = 0.06
    end)
end

--- the audit ------------------------------------------------------------------

-- A block of cells round you, every other one, stamped a row at a time and
-- back along the next -- the way a ledger is read. `flip` picks the other
-- colour of the chequerboard.
function Stamp:auditBoard(game, flip)
    local a = self.def.audit
    local p = game.player
    local pc, pr = self:cellNear(game, p.x, p.y)
    local cols, rows = pick(a.cols, self.phase), pick(a.rows, self.phase)
    local c0, r0 = pc - math.floor(cols / 2), pr - math.floor(rows / 2)
    local list = {}
    for j = 0, rows - 1 do
        local r = r0 + j
        for i = 0, cols - 1 do
            local c = (j % 2 == 0) and (c0 + i) or (c0 + cols - 1 - i)
            -- The colour is fixed to the page, not to the block, so that the
            -- second pass is the other colour wherever the block falls.
            if (c + r + (flip and 1 or 0)) % 2 == 0 and self:fits(game, c, r) then
                list[#list + 1] = { c = c, r = r }
            end
        end
    end
    self.board = { pc = pc, pr = pr }
    return list
end

function Stamp:auditStart(game, e)
    local a = self.def.audit
    self.passes = pick(a.passes, self.phase)
    self.flip = love.math.random() < 0.5
    self.targets = self:auditBoard(game, self.flip)
    self.state, self.t = "audit", a.rear
    self:square(game, e)
end

function Stamp:audit(dt, game, e)
    local a = self.def.audit
    if self.jump then return end
    if self.t > 0 then
        self:pose(e, "rear", 0)
        return
    end
    if #self.targets == 0 then
        self.passes = self.passes - 1
        if self.passes > 0 then
            -- The other colour, counted in again. The first pass's ink is left
            -- wet until the count-in is half done, so the cell you have to
            -- move into is wet when the new board appears and dry before it
            -- lands.
            self.flip = not self.flip
            self.targets = self:auditBoard(game, self.flip)
            for _, m in ipairs(self.marks) do
                if m.wet > 0 then m.wet = math.min(m.wet, a.again * 0.5) end
            end
            self.t = a.again
            return
        end
        self:restFor(a.rest)
        return
    end
    local cell = table.remove(self.targets, 1)
    local x, y = seat(cell.c, cell.r)
    self:leap(e, x, y, pick(a.step, self.phase), a.high, function(st, g, en)
        -- Wet until the pass is done and a little after, all of it drying at
        -- once: the board is read as one thing.
        local left = #st.targets * pick(a.step, st.phase) + a.wet
        st:strike(g, en, cell.c, cell.r, { damage = a.damage, wet = left, knock = 1 })
        st.thud = 0.04
    end)
end

--- drawing --------------------------------------------------------------------

-- A cell's outline in dashes, for one that is about to be stamped, and hatched
-- inside. The hatching is what says *which* cells: a chequerboard of outlines
-- also outlines every blank cell between them, since the two share their edges,
-- and without a fill the audit's board reads as the whole block.
local function dashedCell(c, r, colour, shift)
    local l, t = colLeft(c), rowTop(r)
    love.graphics.setColor(colour)
    for j = 2, CELL_H - 2 do
        for i = 2, CELL_W - 2 do
            if (i + j + math.floor(shift / 4)) % 5 == 0 and j % 2 == 0 then
                love.graphics.rectangle("fill", l + i, t + j, 1, 1)
            end
        end
    end
    for i = 0, CELL_W do
        if math.floor((i + shift) / 3) % 2 == 0 then
            love.graphics.rectangle("fill", l + i, t, 1, 1)
            love.graphics.rectangle("fill", l + CELL_W - i, t + CELL_H, 1, 1)
        end
    end
    for i = 0, CELL_H do
        if math.floor((i + shift) / 3) % 2 == 0 then
            love.graphics.rectangle("fill", l + CELL_W, t + i, 1, 1)
            love.graphics.rectangle("fill", l, t + CELL_H - i, 1, 1)
        end
    end
end

-- What a stamp prints: a box and a word in it, inside the cell's own lines.
local function mark(c, r, colour)
    local l, t = colLeft(c), rowTop(r)
    love.graphics.setColor(colour)
    love.graphics.rectangle("fill", l + 2, t + 2, CELL_W - 3, 1)
    love.graphics.rectangle("fill", l + 2, t + CELL_H - 2, CELL_W - 3, 1)
    love.graphics.rectangle("fill", l + 2, t + 2, 1, CELL_H - 3)
    love.graphics.rectangle("fill", l + CELL_W - 2, t + 2, 1, CELL_H - 3)
    Font.printCentered(I18n.t("PAID"), l + CELL_W / 2 + 1, t + 4)
end

-- On the floor: the marks it has left, and the cells it is about to stamp.
function Stamp:drawGround(time)
    local dry = self.def.ink.dry
    for _, m in ipairs(self.marks) do
        if m.wet > 0 then
            mark(m.c, m.r, Palette.red)
        else
            -- Dry: slate, then graphite, then blinking out -- a fade down the
            -- ramp rather than through alpha.
            local left = dry - m.age
            if left > dry * 0.5 then
                mark(m.c, m.r, Palette.slate)
            elseif left > 1 or math.floor(left * 10) % 2 == 0 then
                mark(m.c, m.r, Palette.graphite)
            end
        end
    end
    if self.targets then
        local blink = math.floor(time * 8) % 2 == 0
        local shift = math.floor(time * 20)
        for k, cell in ipairs(self.targets) do
            -- The next one blinks red; the rest of a board waits in slate.
            local colour = (k == 1 and blink) and Palette.red or Palette.slate
            dashedCell(cell.c, cell.r, colour, shift)
        end
    end
end

function Stamp:drawAir() end

-- The ledger's sums, for anything else that wants a cell (and for checking).
Stamp.colAt, Stamp.rowAt, Stamp.colLeft, Stamp.rowTop = colAt, rowAt, colLeft, rowTop

return Stamp
