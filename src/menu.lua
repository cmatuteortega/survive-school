-- The title screen.
--
-- Drawn on the page rather than over it. The paper pans underneath as if a
-- camera were following someone, a doodle of the player walks his own lap of it
-- with the same monsters the run spawns strung out behind him, and the title
-- writes itself on in the pencil you play with.
--
-- The choice is made the way everything else in this game is made: by drawing.
-- Scribble inside the YES box and the run starts, scribble inside NO and the
-- book closes. The boxes themselves -- what counts as an answer, and when it is
-- committed -- are src/scribble.lua, which the pause card asks with too.
--
-- Nobody is told that in words. Leave the boxes alone for a few seconds and a
-- hand comes and strikes a dashed line through the YES box (src/coach.lua) -- showing the
-- gesture rather than describing it, and never actually answering for you.
--
-- A third box sits under those two and only some of the time: CONTINUE, for a
-- run there is something to go back to (`Game:canContinue`,
-- `Game:continueRun`). Two things can put it there and this screen is told
-- neither of them apart, on purpose -- from where the player is standing it is
-- one offer, go back to the run you were on. What is behind it is either a run
-- still standing in memory, walked out of through the pause card, or a bookmark
-- the last launch left (src/bookmark.lua). It is a
-- `Scribble.newChoice` of its own rather than a third entry in the strip, which
-- is the timetable's arrangement for its two boxes and for the same three
-- reasons: it is somewhere else on the page, it answers a different question,
-- and arming one must not disarm the other. `self.pending` is what sorts a
-- stroke that has been in both -- the last box drawn in wins, whichever choice
-- it belongs to.
--
-- It comes on with the other two rather than on a beat of its own, so the
-- opening is the same length whether there is a run behind the title or not:
-- all three boxes are the question.
--
-- Two things in the left margin are not drawn on, and both are *pressed* rather
-- than answered -- the timetable's rule for the same pair of corners
-- (src/timetable.lua): the settings button at the top (src/settings.lua) and the
-- language button at the foot. Neither is a question. Both open the settings
-- page, so there is nothing to arm and nothing to lift, and `Menu:mark` drops
-- any ink that lands on either -- a press on a button was taken as a press, not
-- as the start of a line.
--
-- The language button is here rather than only behind the sliders because it is
-- the first thing somebody who cannot read the title needs, and burying it one
-- screen inside a page written in the wrong language is burying it. It used to
-- step the language where it stood, which was right with two of them and wrong
-- with six: a switch you have to press five times to come back round is a switch
-- you get lost in. So it says LANG and opens the settings page with the hand
-- (src/coach.lua) pointing at the language row's arrow, where every language is
-- written in its own name. It is the corner button's own box at the other end of
-- the same margin (`Hud.footBox`), widened to the word.
--
-- And a third, in the top *right* corner and only on a book that is not the full
-- game yet: a padlock in the settings button's own box, mirrored to the other
-- end of the same top edge (`Hud.rightCornerBox`). Pressed, not answered, for the
-- margin's reason -- it opens the card that asks (src/fullgame.lua), and that
-- card is where the answer is scribbled.
--
-- And a fourth that does not ship: BOSS, the LANG button mirrored to the bottom
-- *right*, drawn only while the book has been asked for its dev controls
-- (`Dev.showing`, src/dev.lua). Pressed, it throws the boss test on and opens
-- the timetable, where GO! starts the picked lesson's boss fight rather than its
-- ten minutes of horde. Red while the test is on; YES or CONTINUE throws it off.

local Palette = require("src.palette")
local Sprites = require("src.sprites")
local Font = require("src.font")
local Background = require("src.background")
local Overprint = require("src.overprint")
local Particles = require("src.particles")
local Enemy = require("src.enemy")
local Walls = require("src.walls")
local Tools = require("src.tools")
local Input = require("src.input")
local Scribble = require("src.scribble")
local Hud = require("src.hud")
local Sfx = require("src.sfx")
local I18n = require("src.i18n")
local Coach = require("src.coach")
local Store = require("src.store")
local Dev = require("src.dev")
local util = require("src.util")

local Menu = {}

-- Every mark on this screen is a pencil mark, and fades down the real tool's
-- colour ramp rather than inventing a second way for ink to leave the page.
local PENCIL = Tools.list[1]

-- The two lines of the title, and the one piece of lettering on this screen that
-- is **not** translated (src/i18n.lua): it is the game's name rather than a line
-- of copy, and a name is the same word in every language -- the same reason the
-- switch down in the corner leaves a language's own name for itself alone.
--
-- Which is also what lets the opening below stay a fixed clock. The title writes
-- itself on a letter at a time over a length struck off these two strings, and a
-- title that came out shorter in one language than in another would be an intro
-- that ran at two speeds.
local TITLE_TOP, TITLE_BOTTOM = "SURVIVE", "SCHOOL"
local TITLE_SCALE, LABEL_SCALE = 3, 2

-- The intro writes itself on in order; all of these are seconds from entry.
local WRITE_STEP = 0.05   -- per letter of the title
local T_TITLE = 0.2
local T_RULE = T_TITLE
    + (Font.count(TITLE_TOP) + Font.count(TITLE_BOTTOM)) * WRITE_STEP + 0.08
local RULE_TIME = 0.3
local T_START = T_RULE + RULE_TIME
local T_BOXES = T_START + 0.22
local BOX_TIME = 0.4
local T_HINT = T_BOXES + BOX_TIME
local INTRO_END = T_HINT + 0.2

-- How long the boxes sit unanswered before a hand comes and shows what they are
-- for (src/coach.lua). Long enough that anyone who already knows has answered --
-- the intro is over and a returning player is drawing by now -- and short enough
-- that someone who does not know is still looking at the boxes rather than
-- reaching for the back button.
local COACH_AFTER = 3.5

local CONFIRM_FLASH = 0.3 -- the picked box flashing on its own
local CONFIRM_OUT = 0.6   -- the page leaving, or the book closing

local DRIFT_X, DRIFT_Y = 11, 6 -- the page pans this many pixels a second
local LURE_RATE = 0.34         -- radians a second round its orbit
-- Wide enough that the lap goes round the outside of the title block rather
-- than through the middle of it, and clamped to the canvas so a phone in
-- portrait doesn't send him off the side of the page.
local LURE_RX, LURE_RY = 112, 62
local CRITTER_MAX = 7
local CRITTER_EVERY = 0.7
local CRITTER_START = 4        -- already on the page when the screen opens
local CRITTER_KINDS = { "blob", "blob", "bat", "skull" }

--- setup ---------------------------------------------------------------------

-- `resumable` is whether there is a run to go back to -- `Game:canContinue`, and
-- this screen does not care which of the two kinds it is. Read once, here, rather
-- than every frame: a title screen that grew a box while you were looking at it
-- would move the hint out from under the pointer, and nothing can change the
-- answer while this screen is up anyway.
function Menu:enter(resumable)
    self.t = 0
    self.phase = "intro"  -- intro -> choosing -> confirm
    self.pending = nil    -- drawn in, waiting for the pen to come off the page
    self.chosen = nil
    self.confirmT = 0
    self.dither = 0

    self.scrollX, self.scrollY = 0, 0
    self.driftScale = 1
    self.lureAngle = 0
    self.lure = { x = 0, y = 0 }
    self.lureFlip = false

    self.particles = Particles.new()
    self.walls = Walls.new() -- nothing solid here, but Enemy expects to be asked
    self.critters = {}
    self.critterTimer = CRITTER_EVERY
    self.seeded = false -- the opening handful, dropped once the canvas is known

    self.seed = love.math.random() * 997
    self.marks = Scribble.newMarks(self.seed)
    self.pen = Scribble.newPen()
    self.written = 0      -- letters of the title on the page so far

    -- The hand that strikes a line through the YES box for anyone who has not
    -- worked out that drawing is how this page is answered, and how long the
    -- page has been left alone for it to be worth showing (`COACH_AFTER`). A
    -- single diagonal rather than the scribble: one line through a box is all it
    -- asks, and a hand filling the whole inside taught it wanted colouring in.
    self.coach = Coach.new(self.seed, "slash")
    self.idle = 0

    -- The one-frame latch for the settings button: `update` hands it back the
    -- moment it is hit rather than after a flash, the way the timetable's margin
    -- buttons do. The language button uses the same latch, answering "language"
    -- so the settings page opens pointing at the row it came for.
    self.pressed = nil

    self.choice = Scribble.newChoice({
        { key = "yes", label = "YES" },
        { key = "no", label = "NO" },
    }, LABEL_SCALE)
    self.boxes = self.choice.boxes

    -- Nil when there is nothing to go back to, and every part of this screen
    -- that touches it is guarded on that: the row it takes in the stack, the ink
    -- it is offered, its keyboard letter and the line naming that letter all
    -- come and go together, so the screen without it is the screen it was.
    self.cont = resumable and Scribble.newChoice({
        { key = "continue", label = "CONTINUE" },
    }, LABEL_SCALE) or nil
    self.contBox = self.cont and self.cont.boxes[1]

    -- The bottom-left corner belongs to the thumb stick during a run, but here
    -- it is page like any other: you have to be able to scribble anywhere.
    Input.stickEnabled = false
end

-- Stacked top to bottom, then the whole stack is centred in the safe area, so
-- it lands right whatever shape of screen the canvas ended up being.
function Menu:layout(game)
    local ins = game.inset
    local titleH = Font.height * TITLE_SCALE
    local startH = Font.height * LABEL_SCALE
    local hintH = Input.usingTouch and Font.height or Font.height * 2 + 2

    local lay, y = {}, 0
    lay.titleTop = y;    y = y + titleH + 3
    lay.titleBottom = y; y = y + titleH + 9
    lay.rule = y;        y = y + 3 + 9
    lay.start = y;       y = y + startH + 11
    lay.boxes = y;       y = y + Scribble.BOX_H + 10
    -- Under the strip rather than in it: YES and NO are the two halves of one
    -- question and this is a separate offer, so it gets its own line the way the
    -- timetable's CUSTOM sits off on its own rather than beside GO!.
    if self.cont then
        lay.cont = y;    y = y + Scribble.BOX_H + 10
    end
    lay.hint = y;        y = y + hintH

    local top = math.floor(ins.t + (game.vh - ins.t - ins.b - y) / 2)
    for k, v in pairs(lay) do lay[k] = v + top end

    lay.cx = math.floor(ins.l + (game.vw - ins.l - ins.r) / 2)
    lay.labelY = lay.boxes + math.floor((Scribble.BOX_H - startH) / 2)

    -- YES [] and NO [] laid out as one strip and centred under the title.
    self.choice:layout(lay.cx, lay.boxes)

    -- CONTINUE [] is a strip of one, centred on the same middle, so the three
    -- boxes read as one block rather than as a button parked under a question.
    if self.cont then
        lay.contLabelY = lay.cont + math.floor((Scribble.BOX_H - startH) / 2)
        self.cont:layout(lay.cx, lay.cont)
    end

    self.lay = lay
    return lay
end

--- the page underneath -------------------------------------------------------

function Menu:lurePos(game)
    -- A figure of eight rather than a circle: it reads as someone wandering the
    -- page rather than running a track, and it keeps doubling back through the
    -- horde trailing him.
    local rx = math.min(LURE_RX, game.vw * 0.36)
    local ry = math.min(LURE_RY, game.vh * 0.36)
    return self.scrollX + game.vw / 2 + math.cos(self.lureAngle) * rx,
           self.scrollY + game.vh / 2 + math.sin(self.lureAngle * 1.3) * ry
end

function Menu:spawnCritter(x, y)
    self.critters[#self.critters + 1] =
        Enemy.new(CRITTER_KINDS[love.math.random(#CRITTER_KINDS)], x, y)
end

function Menu:updateChase(dt, game)
    self.scrollX = self.scrollX + DRIFT_X * self.driftScale * dt
    self.scrollY = self.scrollY + DRIFT_Y * self.driftScale * dt
    self.lureAngle = self.lureAngle + LURE_RATE * dt

    self.lure.x, self.lure.y = self:lurePos(game)
    self.lureFlip = math.sin(self.lureAngle) > 0

    local cx = self.scrollX + game.vw / 2
    local cy = self.scrollY + game.vh / 2
    local ring = util.len(game.vw, game.vh) / 2

    -- The first few are already on his heels when the screen opens. Walking
    -- them in from the ring would take most of a minute at blob pace, and the
    -- title screen does not last a minute.
    if not self.seeded then
        self.seeded = true
        for _ = 1, CRITTER_START do
            local a = love.math.random() * math.pi * 2
            local r = 40 + love.math.random() * 70
            self:spawnCritter(self.lure.x + math.cos(a) * r, self.lure.y + math.sin(a) * r)
        end
    end

    self.critterTimer = self.critterTimer - dt
    if self.critterTimer <= 0 and #self.critters < CRITTER_MAX and self.phase ~= "confirm" then
        self.critterTimer = CRITTER_EVERY
        -- After that they come from off the edge of the page, like the
        -- spawner's ring, so nothing appears out of thin air on the title.
        local a = love.math.random() * math.pi * 2
        self:spawnCritter(cx + math.cos(a) * (ring + 16), cy + math.sin(a) * (ring + 16))
    end

    for i = #self.critters, 1, -1 do
        local e = self.critters[i]
        e:update(dt, self.lure, self.walls, nil)
        if util.len(e.x - cx, e.y - cy) > ring + 60 then
            table.remove(self.critters, i)
        end
    end

    -- With seven of them the n^2 pass is free, and without it the whole crowd
    -- converges into what looks like a single sprite.
    for i = 1, #self.critters do
        for j = i + 1, #self.critters do
            local a, b = self.critters[i], self.critters[j]
            local dx, dy = a.x - b.x, a.y - b.y
            local d2 = dx * dx + dy * dy
            local min = a.radius + b.radius
            if d2 > 0 and d2 < min * min then
                local d = math.sqrt(d2)
                local push = (min - d) * 0.5
                a.x, a.y = a.x + dx / d * push, a.y + dy / d * push
                b.x, b.y = b.x - dx / d * push, b.y - dy / d * push
            end
        end
    end
end

-- The word on the language button. Not put through the dictionary, for the
-- reason a language's own name is not (src/i18n.lua): the button is for
-- somebody who cannot read the language the page is in, so it has to say the
-- same thing in every one of them. LANG is where LANGUAGE, LANGUE and LINGUA all
-- start, and it is the word a phone's own settings and most web pages' pickers
-- already wear.
local LANG = "LANG"

-- The dev boss test's button (src/dev.lua). Put through the dictionary like the
-- rest of the dev controls, since unlike LANG it is for someone who can read the
-- page.
local BOSS = "BOSS"

--- the two buttons in the margin --------------------------------------------

-- Both are the corner button's own box, at the two ends of the same left margin,
-- and both are tested through the definitions in src/hud.lua rather than against
-- rectangles measured here: a screen you leave by pressing a corner should be
-- left the way the last one was.
function Menu:settingsAt(game, x, y)
    return Hud.cornerAt(game, x, y)
end

function Menu:langAt(game, x, y)
    return Hud.footAt(game, x, y, LANG)
end

-- Only while the dev controls are (`Dev.showing`): a hidden button that still
-- swallowed presses would be a hole in the page.
function Menu:bossAt(game, x, y)
    return Dev.showing() and Hud.footAt(game, x, y, I18n.t(BOSS), true)
end

-- The padlock, which is only there while there is something for it to sell.
function Menu:shopAt(game, x, y)
    if Store.full() then return false end
    local bx, by = Hud.rightCornerBox(game)
    return Hud.buttonAt(bx, by, x, y)
end

-- Any of the margin's buttons, for the cursor (Game:drawPointer).
function Menu:hot(game, x, y)
    return self:settingsAt(game, x, y) or self:langAt(game, x, y)
        or self:shopAt(game, x, y) or self:bossAt(game, x, y)
end

--- drawing on it -------------------------------------------------------------

-- Ink that lands in a box is the answer and is counted there (see
-- src/scribble.lua); ink that misses is just ink on the page, and fades.
--
-- `quiet` counts the mark without letting the box arm, which is what keeps the
-- keyboard shortcut's scribble on screen for its full length.
--
-- It also answers whether the stamp became ink, which is what the pen's swish is
-- fired off (src/scribble.lua): the two margin buttons swallow what crosses them
-- and a swallowed stamp is not a line.
function Menu:mark(x, y, quiet)
    if self.phase == "choosing" then
        if self.choice:mark(x, y, quiet) then
            self.pending = self.choice.armed
            return true
        end

        -- The offer under the strip, asked the same way and answered the same
        -- way. Setting `pending` off whichever choice the stamp landed in is what
        -- makes "the last box drawn in wins" hold across the two of them, the way
        -- it already holds between YES and NO inside one: a stroke that runs on
        -- out of CONTINUE and up into NO changes its mind, and the choice it left
        -- behind still thinking it is armed is never asked.
        if self.cont and self.cont:mark(x, y, quiet) then
            self.pending = self.cont.armed
            return true
        end
    end

    -- The two margin buttons swallow whatever crosses them rather than being
    -- drawn on, exactly as the timetable's tabs do: a press on one of them was
    -- taken as a press, and a line drawn across one would be a line with a hole
    -- in it anyway, since both are drawn out past the overprint pass.
    if self.game and (self:settingsAt(self.game, x, y)
        or self:langAt(self.game, x, y) or self:shopAt(self.game, x, y)
        or self:bossAt(self.game, x, y)) then
        return false
    end

    self.marks:add(x, y)
    return true
end

function Menu:choose(box)
    if self.phase == "confirm" then return end
    self.phase = "confirm"
    Sfx.play("accept")
    self.chosen = box
    self.confirmT = 0
    self.particles:burst(box.x + box.w / 2, box.y + box.h / 2, 16,
        box.key ~= "no" and Palette.red or Palette.slate)
end

-- The keyboard shortcut fills the box in rather than jumping past it: the box
-- still gets answered the only way a box here gets answered.
function Menu:autoFill(box)
    if self.phase ~= "choosing" then return end
    -- Whichever choice the box belongs to: `autoFill` only sets a clock running
    -- on the box itself, and it is the owning choice's `update` that walks the
    -- scribble across it (see Menu:updateScribble).
    if box == self.contBox then
        self.cont:autoFill(box)
    else
        self.choice:autoFill(box)
    end
end

function Menu:updateScribble(dt)
    self.marks:update(dt)

    local filled = self.choice:update(dt)
    local contFilled = self.cont and self.cont:update(dt)
    if filled or contFilled then self:choose(filled or contFilled) end

    -- Once the answer is in, the page stops taking ink: the screen is on its way
    -- off and a fresh scribble would be drawn onto something already leaving.
    local down = Input.pointerDown
    self.pen:track(dt, down and self.phase ~= "confirm", Input.pointerX, Input.pointerY,
        function(mx, my) return self:mark(mx, my) end,
        function(px, py)
            -- The buttons get first refusal, and a press on one of them is the
            -- whole of what that press does: it does not also skip the intro and
            -- it does not start a line. They are the one part of this page that
            -- is not page.
            if self.game and self:settingsAt(self.game, px, py) then
                self.pressed = "settings"
                return
            end
            if self.game and self:langAt(self.game, px, py) then
                self.pressed = "language"
                return
            end
            if self.game and self:shopAt(self.game, px, py) then
                self.pressed = "fullgame"
                return
            end
            if self.game and self:bossAt(self.game, px, py) then
                self.pressed = "boss"
                return
            end

            -- Any other press skips the intro straight to the boxes, and the
            -- press that skipped it still draws.
            if self.phase == "intro" then self:skip() end
        end)

    -- A box that has been drawn in is only armed, not answered. Nothing is
    -- committed until the pen comes off the page, so a line that carries on
    -- into the other box changes the answer rather than being too late, and
    -- you can see which one you are about to pick before you lift.
    if self.pending and not down then
        self:choose(self.pending)
    end
end

-- The clock the hand waits on only runs while nothing is happening: the boxes
-- are up, nothing is being drawn and nothing is armed. Anything at all -- a
-- press anywhere on the page, a key -- puts it back to zero and sends the hand
-- away mid-line, because the moment someone is trying is the moment to stop
-- showing them; it comes back, from the start of its loop, only if they stop
-- again.
function Menu:updateCoach(dt)
    if self.phase == "choosing" and not Input.pointerDown and not self.pending then
        self.idle = self.idle + dt
    else
        self.idle = 0
        self.coach:reset()
    end

    if self:coaching() then self.coach:update(dt) end
end

function Menu:coaching()
    return self.phase == "choosing" and self.idle >= COACH_AFTER
end

-- A little graphite puffs off each letter as it lands, so the title reads as
-- being written rather than switched on.
function Menu:updateWriting()
    local total = Font.count(TITLE_TOP) + Font.count(TITLE_BOTTOM)
    local target = util.clamp(math.floor((self.t - T_TITLE) / WRITE_STEP), 0, total)
    while self.written < target do
        self.written = self.written + 1
        local x, y = self:letterPos(self.written)
        self.particles:burst(x, y, 2, Palette.graphite)
    end
end

-- Centre of the nth letter of the title, counting straight through both lines.
function Menu:letterPos(n)
    local lay = self.lay
    local topN = Font.count(TITLE_TOP)
    local line, i, y = TITLE_TOP, n, lay.titleTop
    if n > topN then
        line, i, y = TITLE_BOTTOM, n - topN, lay.titleBottom
    end

    local x = lay.cx - Font.width(line) * TITLE_SCALE / 2
    return x + (i - 1) * Font.advance * TITLE_SCALE + TITLE_SCALE,
           y + Font.height * TITLE_SCALE / 2
end

function Menu:skip()
    self.t = math.max(self.t, INTRO_END)
    self.phase = "choosing"
end

--- update --------------------------------------------------------------------

-- Returns "yes", "no" or "continue" on the frame the choice finishes playing
-- out, "settings", "language", "fullgame" or "boss" on the frame a margin
-- button is pressed, and
-- nothing at all otherwise.
function Menu:update(dt, game)
    -- Kept because the press edge and `mark` both have to know where the two
    -- margin buttons are, and neither is handed the game.
    self.game = game

    self:layout(game)
    self.t = self.t + dt

    self:updateChase(dt, game)
    self:updateScribble(dt)
    self:updateCoach(dt)
    self:updateWriting()
    self.particles:update(dt)

    -- Handed back the frame it is hit rather than after a flash: the settings
    -- page is a loop off the side of the title screen, not an answer to it, and a
    -- button that goes somewhere should go there when it is pressed.
    if self.pressed then
        local what = self.pressed
        self.pressed = nil
        return what
    end

    if self.phase == "intro" and self.t >= INTRO_END then
        self.phase = "choosing"
    end

    if self.phase == "confirm" then
        self.confirmT = self.confirmT + dt

        -- The box flashes on its own first, then the whole screen dithers off
        -- the page the way a mark does -- no alpha, so nothing blends into a
        -- ninth colour on the way out.
        local out = util.clamp((self.confirmT - CONFIRM_FLASH) / CONFIRM_OUT, 0, 1)
        self.dither = out
        if self.chosen.key ~= "no" then
            -- Anything that is not closing the book pulls the page away into the
            -- run -- a run being started and a run being gone back to are the
            -- same journey off this screen, so they leave it the same way.
            self.driftScale = 1 + out * out * 34
        end

        if self.confirmT >= CONFIRM_FLASH + CONFIRM_OUT then
            return self.chosen.key
        end
    end
end

function Menu:keypressed(key)
    if self.phase == "confirm" then return end

    self.idle = 0
    self.coach:reset()

    -- The two margin buttons, and neither skips the intro: they are not presses
    -- on the page. O for the options page and L for the language row of it, both
    -- free here -- the timetable spends L on its library tab and this screen has
    -- no tabs.
    if key == "o" then
        self.pressed = "settings"
        return
    end
    if key == "l" then
        self.pressed = "language"
        return
    end
    -- And B for the padlock: buying is the one word for what is behind it.
    if key == "b" and not Store.full() then
        self.pressed = "fullgame"
        return
    end
    -- And X for the dev boss test, which is as dead as its button is hidden.
    if key == "x" and Dev.showing() then
        self.pressed = "boss"
        return
    end

    if self.phase == "intro" then self:skip() end

    -- S answers YES as well as Y, because in Spanish, Italian and Portuguese
    -- the box says SI or SIM, and J does for the German JA. All of them are live
    -- in every language rather than swapping with the dictionary: a shortcut that
    -- moves when the words do is a shortcut you have to look up. French keeps Y,
    -- since O -- the letter OUI would want -- is the settings page's key above.
    if key == "y" or key == "s" or key == "j" or key == "return"
        or key == "kpenter" or key == "space" then
        self:autoFill(self.boxes[1])
    elseif key == "n" then
        self:autoFill(self.boxes[2])
    elseif key == "c" and self.contBox then
        self:autoFill(self.contBox)
    end
end

--- draw ----------------------------------------------------------------------

local function byDepth(a, b)
    return a.y < b.y
end

-- The one-pixel bounce that is the whole of his walk. Its own function because
-- the blank stamped into the page under him has to land on the same pixel he does
-- (Player:footing).
function Menu:lureY()
    return math.floor(self.lure.y) - (math.floor(self.t * 7) % 2)
end

-- The player doodle, walking his own lap of the page. He is not a Player: there
-- is no health, nothing shoots, and the horde behind him never quite arrives.
function Menu:drawLure()
    Sprites.shadow(Sprites.player, math.floor(self.lure.x), math.floor(self.lure.y))

    love.graphics.setColor(1, 1, 1)
    Sprites.player:draw(math.floor(self.lure.x), self:lureY(), self.lureFlip)
end

function Menu:drawChase()
    table.sort(self.critters, byDepth)

    -- The run's own trick, for the run's own reason (Game:draw): a doodle walking
    -- the title page is standing on the ruling rather than printed into it, so the
    -- page is blanked out under the lot of them before any of them is drawn.
    Overprint.beginSolid()
    for _, e in ipairs(self.critters) do e:drawSolid() end
    love.graphics.setColor(Palette.paper)
    Sprites.player:drawMask(math.floor(self.lure.x), self:lureY(), self.lureFlip)
    Overprint.endSolid()

    local pending = true
    for _, e in ipairs(self.critters) do
        if pending and e.y > self.lure.y then
            self:drawLure()
            pending = false
        end
        e:draw()
    end
    if pending then self:drawLure() end
end

-- A label and the box it belongs to. The two in the strip and the one under them
-- are drawn identically -- the same warm-up colour, the same hand-drawn border,
-- the same ink kept inside it -- and only where they sit differs, which is the
-- whole of what makes the third box read as part of the question rather than as a
-- button somebody added.
--
-- The two seeds are the wobble's: one for the border and one for the lettering,
-- passed in rather than derived so each box keeps the hand it has always been
-- drawn in.
function Menu:drawChoiceBox(box, labelY, progress, seed, labelSeed)
    local color = Scribble.boxColor(box, self.chosen, self.confirmT)

    Scribble.printBig(Scribble.label(box), box.labelCx, labelY, LABEL_SCALE, color,
        { wobble = true, t = self.t, seed = labelSeed, dither = self.dither })
    Scribble.drawBox(box, progress, color, seed, self.dither)
    -- Ink inside a box is the answer, and does not fade.
    Scribble.drawMarks(box.marks, PENCIL.ramp[1], self.seed, self.dither)
end

function Menu:draw(game)
    local lay = self:layout(game)
    local left, top = math.floor(self.scrollX), math.floor(self.scrollY)

    -- Menu and all: it is written on the page, not laid over it, so the whole
    -- screen goes through the overprint pass and the ruling shows through the
    -- title the same way it shows through a pencil line drawn mid-run.
    Overprint.beginPage()
    love.graphics.push()
    love.graphics.translate(-left, -top)
    Background.draw(left, top, game.vw, game.vh)
    love.graphics.pop()

    Overprint.beginInk()

    love.graphics.push()
    love.graphics.translate(-left, -top)
    self:drawChase()
    love.graphics.pop()

    -- From here down it is canvas space: the menu is pinned to the screen while
    -- the paper slides underneath it.
    self.marks:draw(self.dither)

    Scribble.printBig(TITLE_TOP, lay.cx, lay.titleTop, TITLE_SCALE, Palette.ink, {
        shadow = Palette.graphite, wobble = true, t = self.t, seed = 1,
        dither = self.dither, count = self.written,
    })
    Scribble.printBig(TITLE_BOTTOM, lay.cx, lay.titleBottom, TITLE_SCALE, Palette.red, {
        shadow = Palette.blush, wobble = true, t = self.t, seed = 2,
        dither = self.dither, count = self.written - Font.count(TITLE_TOP),
    })

    if self.t >= T_RULE then
        local ruleW = Font.width(TITLE_BOTTOM) * TITLE_SCALE
        local n = math.floor(ruleW + 6)
            * util.clamp((self.t - T_RULE) / RULE_TIME, 0, 1)
        local x0 = lay.cx - math.floor(ruleW / 2) - 3
        love.graphics.setColor(Palette.slate)
        for i = 0, math.floor(n) do
            if self.dither == 0 or util.hash01(i, self.seed, 31) > self.dither then
                Scribble.stamp({
                    x = x0 + i,
                    y = lay.rule + math.floor(math.sin(i * 0.07) * 1.5),
                    i = i,
                }, self.seed)
            end
        end
    end

    if self.t >= T_START then
        -- Asking, in a hand that can't keep still.
        local pulse = math.sin(self.t * 3.4) > 0
        Scribble.printBig(I18n.t("START?"), lay.cx, lay.start, LABEL_SCALE,
            pulse and Palette.ink or Palette.slate,
            { wobble = true, t = self.t, seed = 7, dither = self.dither })
    end

    if self.t >= T_BOXES then
        local progress = util.clamp((self.t - T_BOXES) / BOX_TIME, 0, 1)

        for i, box in ipairs(self.boxes) do
            self:drawChoiceBox(box, lay.labelY, progress, 10 + i, 30 + i * 5)
        end

        -- On the same beat as the two above it, so a title screen with a run
        -- behind it opens over exactly as long as one without.
        if self.cont then
            self:drawChoiceBox(self.contBox, lay.contLabelY, progress, 13, 45)
        end
    end

    if self.t >= T_HINT then
        -- Once a box is armed the line underneath says what it is waiting for,
        -- which is the only warning that lifting is what commits it.
        local armed = self.pending ~= nil
        local prompt = "SCRIBBLE IN A BOX"
        if armed then
            prompt = Input.usingTouch and "LIFT TO CONFIRM" or "RELEASE TO CONFIRM"
        end

        Scribble.printBig(I18n.t(prompt), lay.cx, lay.hint, 1,
            armed and Palette.red or Palette.slate,
            { seed = 51, dither = self.dither })
        if not Input.usingTouch and not armed then
            -- The line names the letters the screen actually has, so a title with
            -- no run behind it never mentions a key that does nothing.
            local keys = self.cont and "OR PRESS Y N OR C" or "OR PRESS Y OR N"
            Scribble.printBig(I18n.t(keys), lay.cx,
                lay.hint + Font.height + 2, 1,
                Palette.graphite, { seed = 52, dither = self.dither })
        end
    end

    self.particles:draw()

    Overprint.finish()

    -- The hand, out past the pass for the reason src/coach.lua gives: it is a
    -- picture of a gesture over the page and not a mark on it, and its paper
    -- fill would come out a step darker wherever it crossed a rule. Corner to
    -- corner of the whole YES box and a little past both, the way a line struck
    -- through a box is actually drawn -- kept to the inside it was three dashes
    -- long and read as a stray mark rather than a line through anything. And
    -- only YES: the hint is how to answer, and the answer it shows is the one
    -- that starts the game.
    if self:coaching() then
        local b = self.boxes[1]
        self.coach:draw(b.x - 3, b.y - 2, b.w + 4, b.h + 2)
    end

    -- The two margin buttons, out past the pass with the rest of the game's
    -- furniture: they are boxes filled in paper, and a paper fill does not survive
    -- being paired with the ruling under it -- a border landing on a rule comes out
    -- a step darker and the box reads as a hole cut in the page.
    --
    -- Drawn after the dither rather than through it, so they stay put while the
    -- page leaves. That is right for both of them: neither is part of the answer,
    -- and both are ways off the side of this screen rather than through it.
    Hud.drawCorner(game, "sliders", false)
    Hud.drawFoot(game, LANG, false)
    if Dev.showing() then
        Hud.drawFoot(game, I18n.t(BOSS), Dev.boss, true)
    end
    if not Store.full() then
        local bx, by = Hud.rightCornerBox(game)
        Hud.drawButton(bx, by, Hud.CORNER_SIZE, "lock", false)
    end
end

return Menu
