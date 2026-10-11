-- DEV ONLY: this module does not ship (zip it out of a build with the rest of
-- the dev tooling, or leave it -- nothing reaches it without the flag). It turns
-- the game into a camera for short-form video: `love . --capture montage` plays
-- a scripted reel of shots on a fixed clock and writes an upright MP4, picture
-- and sound, for TikTok, Reels and Shorts.
--
-- Upright because the canvas is already the shape of the window it is given
-- (main.lua): a 9:16 window is a 180x320 page with nothing cropped, and that
-- page blown up six times is exactly 1080x1920. So the window is opened small
-- and upright, every frame of the canvas -- not of the window -- is piped to
-- ffmpeg as raw pixels, and ffmpeg does the whole-number blow-up with nearest
-- filtering. The picture is the game's own pixels, never a screen recording.
--
-- A fixed clock (`DT` a frame, whatever the machine manages) is what makes a
-- take a take: the run is simulated exactly as fast as it is filmed, so a slow
-- encode never drops a frame, and `love.timer.getTime` is pointed at the same
-- clock so the sound gaps and wobbles that read the wall clock agree with it.
-- Each shot reseeds the random numbers, so a reel is the same reel every time
-- it is shot -- re-shoot it after the game changes and only the change differs.
--
-- Sound is not recorded off a device -- a headless machine may not have one, and
-- a device would hear the wall clock -- it is mixed. Every `Sfx.play` that
-- actually sounded is logged against the clip's clock with the pitch it was
-- given, every `Sfx.cut` against the voice it fades, and once the reel is shot
-- the log is laid over silence off the same scaled samples the game plays
-- (`Sfx.sample`), at the game's own level. The track goes under it in ffmpeg at
-- the level the settings default to (`Sfx.levels`).
--
-- It writes under its own save identity, so a take sees a fresh book -- English,
-- the starting hero and drawings -- and leaves the real one alone; the shots are
-- dev boss tests (src/dev.lua), which bank nothing anyway.
--
-- A shot is a row in `REELS`: what to set up, how long to let it run unseen
-- before the camera rolls, how long to film, and a caption. New reels are new
-- rows, as everything else here is.

local ffi = require("ffi")

local Camera = require("src.camera")
local Course = require("src.course")
local Design = require("src.design")
local Dev = require("src.dev")
local Enemy = require("src.enemy")
local Font = require("src.font")
local I18n = require("src.i18n")
local Input = require("src.input")
local Library = require("src.library")
local Palette = require("src.palette")
local Scribble = require("src.scribble")
local Sfx = require("src.sfx")
local Sprites = require("src.sprites")
local Studio = require("src.studio")
local Subjects = require("src.subjects")
local Upgrades = require("src.upgrades")
local util = require("src.util")
local Worksheet = require("src.worksheet")

local Capture = {}

Capture.on = false

local FPS = 30
local DT = 1 / FPS
local RATE = 44100      -- the mix's sample rate
local WINDOW_W, WINDOW_H = 360, 640   -- a 180x320 canvas at 2x (main.lua)
local UPSCALE = 6       -- 180x320 -> 1080x1920
local ZOOM = 2          -- how much closer a boss shot is filmed (see `lens`)

-- Sounds left out of the mix. The bot draws nearly all the time, and a brush
-- swish under every frame of a reel is a hiss that buries everything else --
-- what a player hears in bursts, the reel would hear as a drone. A reel played
-- with the cursor (`REEL_CURSOR`) keeps them: there the hand draws in bursts,
-- as a player does, and the gesture is half of what is shown.
local MUTED = { brush1 = true, brush2 = true, brush3 = true,
                brush4 = true, brush5 = true, brush6 = true }

-- And a reel's own, on top: the sun's crowd is fed straight at a hero who is
-- topped up every frame, so he is hit all the time and the hurt would be a
-- second drone under the burn. A boss reel keeps it -- there a hit is the boss
-- landing one, which is half of what is being shown.
local REEL_MUTED = { sun = { hurt = true }, science = { hurt = true },
                     music = { hurt = true }, maths = { hurt = true },
                     art = { hurt = true }, finance = { hurt = true },
                     grammar = { hurt = true }, pe = { hurt = true } }

--- the reels -----------------------------------------------------------------

-- Every boss in the book, each dropped onto its own page: the red ring
-- closing, the thud, the call, and a second or two of the fight, filmed close.
-- A feed decides in the first second whether to keep watching, so the reel
-- opens straight on the boss that looks most like nothing else -- `OPENER`, held
-- a little longer and with the hook written over it -- rather than on a title
-- card, and the rest follow in the library's order. Signed off on the bare page.
local OPENER = "redpen"

local function bossMontage()
    local roster = Subjects.bosses()
    local order = {}
    for _, b in ipairs(roster) do
        if b.kind == OPENER then table.insert(order, 1, b) else order[#order + 1] = b end
    end

    local shots = {}
    for i, b in ipairs(order) do
        shots[#shots + 1] = {
            kind = "boss", subject = b.subject.key, encore = b.encore,
            warm = 0.25, rec = i == 1 and 3.2 or 2.4, zoom = ZOOM,
            tag = string.format("%d/%d", i, #order),
            title = Enemy.types[b.kind].title,
            hook = i == 1 and { #roster .. " BOSSES", "1 NOTEBOOK" } or nil,
        }
    end
    shots[#shots + 1] = { kind = "card", rec = 2.2, lines = { "SURVIVE", "SCHOOL" } }
    return shots
end

-- One weapon's whole life, told on the sun: the hole in the library where it
-- will be and what the book asks for it, the book opening it, the draft dealing
-- it, the board you draw its face on, the sun coming up over a corner filmed
-- close as it burns, and then every level after the first, one shot each with
-- the card's own words under it. A run shot is an ordinary run rather than a
-- boss test -- the horde is the subject -- moved on to `HORDE_AT` so there is a
-- crowd to burn, and marked as a test so it banks nothing.
local HORDE_AT = 240
local SUN_CORNER = 3   -- bottom left: clear of the HUD's top rows when close

-- The face drawn on the board: the game's own (Sprites.SUNFACE), so the sun
-- that comes up is the one a player is handed, drawn back onto a blank board a
-- run of cells at a time, row by row, each run one stroke with the tool its
-- colour belongs to. Read off the art rather than copied out, so it is the
-- baked face whatever the baked face becomes.
local TOOL_OF = { [Design.PENCIL] = "p", [Design.PEN] = "b" }

local function faceStrokes()
    local strokes = {}
    for y, row in ipairs(Sprites.SUNFACE) do
        local x = 1
        while x <= #row do
            local ch = row:sub(x, x)
            if TOOL_OF[ch] then
                local stroke = { tool = TOOL_OF[ch] }
                while x <= #row and row:sub(x, x) == ch do
                    stroke[#stroke + 1] = { x, y }
                    x = x + 1
                end
                strokes[#strokes + 1] = stroke
            else
                x = x + 1
            end
        end
    end
    return strokes
end

local FACE = faceStrokes()
local FACE_STEP = 0.05  -- seconds from one cell of a stroke to the next
local FACE_LIFT = 0.1   -- and between strokes, the pen off the page

-- A run to film a weapon in: the lesson's page at minute four, the draft kept
-- shut, the coaching hand retired, the book left alone.
local function runShot(game, subject)
    game:setSubject(subject or "maths")
    Course.current = Course.get("school")
    Dev.boss = false
    Dev.unlocks = "all"
    game:reset()
    game.bossTest = true
    game.resumable = false
    game.time = HORDE_AT
    game.player.addXp = function() end
    game.drewKill = true
end

-- The sun pinned to its corner for the length of a shot, held below the page
-- while the crowd gathers unseen and sent up on the frame the camera rolls,
-- rather than wherever its cycle happened to be.
local function sunUp(game, t, s)
    local sun = game.loadout.live.sun
    sun.corner = s.corner or SUN_CORNER
    if t < -(s.lead or 0) then
        sun.phase, sun.t = "off", 0
    elseif not s.risen then
        s.risen = true
        sun.phase, sun.t = "rise", 0
    end
end

-- The lesson's own horde, fed in from just off the page behind the lit corner
-- so it walks to the hero through the light. The sun is pinned to the screen
-- and the hero to its middle, and the ordinary horde arrives from all round, so
-- left alone a close shot of one corner is mostly a close shot of paper. Real
-- arrivals off the spawner (`Spawner:dropAt`), just aimed: what kind, how big
-- and whether a champion are the minute's own.
local FEED_EVERY = 0.16
-- How far along either edge from the corner they come in: some under the disc
-- and some past its rim. The disc is solid (src/sun.lua) and hides whatever is
-- under it, so a burn is seen at the rim -- the numbers coming off it -- and in
-- what walks out of the light scorched; the ones fed past the rim are the ones
-- seen burning on their way in.
local FEED_SPREAD = 80

local function feed(game, s, corner)
    s.fed = (s.fed or 0) - DT
    if s.fed > 0 then return end
    s.fed = FEED_EVERY

    local left, top, w, h = Camera.bounds()
    local right = corner == 2 or corner == 4
    local bottom = corner >= 3
    local x = left + (right and w or 0)
    local y = top + (bottom and h or 0)
    local along = love.math.random() * FEED_SPREAD
    if love.math.random() < 0.5 then
        x = x + (right and -along or along)
        y = y + (bottom and 10 or -10)
    else
        y = y + (bottom and -along or along)
        x = x + (right and 10 or -10)
    end
    game.spawner:dropAt(game, x, y)
end

-- Where on the canvas to look for a sun shot filmed close: between the corner
-- it rises in and the hero, weighted to the corner. Numbered as src/sun.lua
-- numbers them: 1 and 2 along the top, 3 and 4 along the bottom.
local function sunAim(corner)
    return function(game)
        local left, top = Camera.steady()
        local px, py = game.player.x - left, game.player.y - top
        local cx = (corner == 2 or corner == 4) and game.vw or 0
        local cy = corner >= 3 and game.vh or 0
        return cx * 0.6 + px * 0.4, cy * 0.6 + py * 0.4
    end
end

-- The face, drawn: where the pointer is `t` seconds into the drawing and
-- whether it is down. Cells are aimed at their middles off the board's own
-- layout, so the bot draws on whatever size of board the studio picked.
local function faceAt(t)
    local lay = Studio.lay
    if not lay or t < 0 then return nil end
    for _, stroke in ipairs(FACE) do
        -- Down for a step at least, or a one-cell stroke is never drawn.
        local span = math.max(1, #stroke - 1) * FACE_STEP
        if t < span + FACE_LIFT then
            if t > span then return nil, stroke.tool end
            local k = t / FACE_STEP
            local i = math.floor(k)
            local f = k - i
            local a = stroke[math.min(i + 1, #stroke)]
            local b = stroke[math.min(i + 2, #stroke)]
            local gx = a[1] + (b[1] - a[1]) * f
            local gy = a[2] + (b[2] - a[2]) * f
            return lay.bx + (gx - 0.5) * lay.zoom, lay.board + (gy - 0.5) * lay.zoom,
                stroke.tool
        end
        t = t - span - FACE_LIFT
    end
    return nil, nil, nil, true
end

local function sunReel()
    local shots = {}

    -- The hole on the weapons page and what it asks for, then the book opening
    -- it: the same entry, written out in full.
    shots[#shots + 1] = {
        kind = "library", warm = 0.1, rec = 4.6,
        hook = { "UNLOCK", "THE SUN" }, hookY = 226,
        setup = function(game)
            Dev.boss = false
            Dev.unlocks = "none"
            game:toLibrary()
        end,
        direct = function(game, t, s)
            -- Turned once the book has been laid out and knows it has pages.
            if t > 0.25 and not s.turned then
                s.turned = true
                Library:step(1)
            end
            local _, want = Library:find("sun")
            if t > 0.9 and Library.index < want and t - (s.walked or 0) > 0.16 then
                s.walked = t
                Library:keypressed("down")
            end
            if t > 2.8 and not s.opened then
                s.opened = true
                Dev.unlocks = "all"
                Sfx.play("accept")
            end
            -- The hook says what to look at until the book opens it, and then
            -- gives the space under the entry to what just happened.
            if s.opened then s.hook, s.say = nil, "UNLOCKED!" end
        end,
    }

    -- Dealt, drawn and up, in one take: the draft lands on the run, the sun's
    -- card is circled, the board comes up with the face drawn on it, and the run
    -- comes back with the sun rising in the corner -- where the camera punches
    -- in to watch it burn.
    shots[#shots + 1] = {
        kind = "run", warm = 2.5, rec = 10,
        setup = function(game) runShot(game) end,
        direct = function(game, t, s)
            if t > 0.3 and not s.dealt then
                s.dealt = true
                game.player.pending = 1
                game.state = "levelup"
                Sfx.play("levelup_enter")
                game:holdRun()
                game.draft:open(game, { Upgrades.byId.star, Upgrades.byId.sun,
                    Upgrades.byId.rocket })
            end
            if game.state == "levelup" then
                if t > 1.4 and not s.picked then
                    s.picked = true
                    game.draft:keypressed("2")
                end
            elseif game.state == "studio" then
                s.say = nil
                local sun = game.loadout.live.sun
                if sun then sun.corner = SUN_CORNER end
                if not s.board then
                    -- A blank board, so the face is drawn rather than edited.
                    s.board = t
                    local d = Design.by.sun
                    for y = 1, d.h do
                        for x = 1, d.w do d.grid[y][x] = Design.BLANK end
                    end
                    d:apply()
                end
                local x, y, tool, done = faceAt(t - s.board - 0.6)
                if tool and tool ~= s.tool then
                    s.tool = tool
                    Studio:keypressed(tool)
                end
                Input.pointerDown = x ~= nil
                if x then Input.pointerX, Input.pointerY = x, y end
                if done and not s.ok then
                    s.ok = true
                    Studio:keypressed("return")
                end
            elseif s.ok then
                Input.pointerDown = false
                if not s.back then s.back = t end
                if t - s.back > 0.5 then feed(game, s, SUN_CORNER) end
                s.say = "IT BURNS A CORNER"
            end
        end,
        zoom = function(game, t, s)
            return s.back and t - s.back > 0.9 and ZOOM or 1
        end,
        aim = sunAim(SUN_CORNER),
    }

    -- Then the sun at the level it was dealt at, burning the crowd in other
    -- corners, close and with nothing written over it: already up when the
    -- camera rolls (`lead`), so every second of it is mobs in the light. The
    -- levels between are left for the run to find -- only the last is shown,
    -- a few seconds of it, wide, as what the corner becomes.
    local function sunShot(spec)
        return {
            kind = "run", warm = 4, rec = spec.rec, corner = spec.corner,
            lead = spec.lead,
            setup = function(game)
                runShot(game, spec.subject)
                for _ = 1, spec.level do game.loadout:take("sun", game) end
                game.player:applyStats()
            end,
            direct = function(game, t, s)
                sunUp(game, t, s)
                -- From the start of the unseen warm, with the sun already up:
                -- crossing the disc takes a slow thing longer than a clip, so
                -- the stream has to be under way before the camera rolls.
                feed(game, s, s.corner)
            end,
            zoom = spec.zoom,
            aim = sunAim(spec.corner),
        }
    end

    shots[#shots + 1] = sunShot({ level = 1, corner = 4, rec = 2.4, lead = 3.5,
        zoom = ZOOM, subject = "science" })
    shots[#shots + 1] = sunShot({ level = 1, corner = 3, rec = 2.4, lead = 3.5,
        zoom = ZOOM, subject = "art" })
    shots[#shots + 1] = sunShot({ level = #Upgrades.byId.sun.levels, corner = 3,
        rec = 2.4, lead = 0.9, subject = "music" })

    shots[#shots + 1] = { kind = "card", rec = 2.2, lines = { "SURVIVE", "SCHOOL" } }
    return shots
end

-- One lesson's teaser, told on SCIENCE, as play rather than as a slideshow: the
-- hero walking the page with the whole class coming at him and the pencil out
-- among them; the lesson's worksheets answered with the crowd still coming; and
-- fast cuts of its two bosses -- each landing, then one move each (the eye's
-- tears, the atom's split) -- before the card. The other lessons are the same
-- reel on their own page (`lessonReel`) with their own sheets and moves.
--
-- Played with the mouse: the cursor is drawn (`REEL_CURSOR`), and everything the
-- hand does -- the scribble, the wire, the answer it points at -- goes through
-- `point`, so the cursor is always where the pen is and glides between strokes
-- rather than jumping, which is what a feed is shown: where and how you write.
local REEL_CURSOR = { science = true, music = true, maths = true,
                      art = true, finance = true, grammar = true, pe = true }

-- The bot's hand: where the pointer is (page pixels, turned into the canvas's
-- here) and whether it is down. The cursor eases after it while it is lifted.
local hoverX, hoverY
local aimX, aimY

local function point(x, y, down)
    local left, top = Camera.steady()
    Input.pointerX, Input.pointerY = x - left, y - top
    Input.pointerDown = down and true or false
    aimX, aimY = Input.pointerX, Input.pointerY
end

-- A scripted hand: nodes { x, y, down, speed } walked in order at `speed` page
-- pixels a second (the leg into a node is drawn if the node is `down`), and
-- { wait = s, down = } held where it is. Answers where the hand is `t` seconds
-- in, whether it is down, and whether it has finished.
local function along(path, t)
    local x, y = path[1][1], path[1][2]
    if t <= 0 then return x, y, false end
    for i = 2, #path do
        local n = path[i]
        if n.wait then
            if t < n.wait then return x, y, n.down end
            t = t - n.wait
        else
            local dur = util.len(n[1] - x, n[2] - y) / (n.speed or 140)
            if t < dur then
                local f = t / dur
                return x + (n[1] - x) * f, y + (n[2] - y) * f, n.down
            end
            t = t - dur
            x, y = n[1], n[2]
        end
    end
    return x, y, false, true
end

-- The class, in the order the minutes bring it (src/spawner.lua's TABLE): the
-- crowd these shots are made of, called in by name rather than by the minute,
-- so every kind is on the page in the first seconds rather than the ninth minute.
local CLASS = { "blob", "bat", "wad", "blot", "skull", "bulb", "eye", "grin", "redeye" }

-- Arrivals off the page, every `every` seconds while there are fewer than `most`,
-- a kind at a time round the class. Dropped a little outside what the shot
-- shows (`zoom`: a close shot is a window round the hero, and arrivals off the
-- whole canvas would never catch up with him into it). `low` keeps them to the
-- lower half of the edges, for a sheet above the hero that feet would rub out.
local function crowd(game, s, every, most, low, zoom)
    s.fedT = (s.fedT or 0) - DT
    if s.fedT > 0 or #game.enemies >= most then return end
    s.fedT = every
    s.next = (s.next or love.math.random(#CLASS)) % #CLASS + 1

    local left, top, w, h = Camera.bounds()
    if zoom then
        w, h = w / zoom, h / zoom
        left, top = game.player.x - w / 2, game.player.y - h / 2
    end
    local x, y
    local side = love.math.random(low and 3 or 4)
    if side == 1 then x, y = left - 12, top + h * (low and 0.5 + love.math.random() * 0.5 or love.math.random())
    elseif side == 2 then x, y = left + w + 12, top + h * (low and 0.5 + love.math.random() * 0.5 or love.math.random())
    elseif side == 3 then x, y = left + love.math.random() * w, top + h + 12
    else x, y = left + love.math.random() * w, top - 12 end
    game:spawnEnemy(CLASS[s.next], x, y)
end

-- The hand at work on the crowd, the way a player fights with the lesson's
-- tool: the nearest monster picked, the gesture that tool is used with made on
-- it, a beat lifted while the cursor glides to the next, and again. `near` is
-- how far from the hero it looks; `boss` aims it at the boss instead.
--
-- One gesture per kind of tool (src/compass.lua lists the four): a brush is
-- dragged across in a zigzag; a pin is tapped, and lands where it was tapped; a
-- compass's needle goes in beside the prey and its leg is dragged out to it, so
-- the circle it swings on release runs through the prey; a ruler is pressed and
-- held on the prey, which aims it through the hero, and let go.
local GESTURES = {
    brush = { every = 0.95, down = 0.5 },
    drop = { every = 0.5, down = 0.1 },
    sweep = { every = 1.25, down = 0.4 },
    snap = { every = 1.0, down = 0.35 },
}

local function gestureOf(game)
    local tool = game.loadout:tool(game.tool)
    if tool and tool.sweep then return "sweep" end
    if tool and tool.drop then return "drop" end
    if tool and tool.snap then return "snap" end
    return "brush"
end

local function hunt(game, s, t, near, boss)
    local p = game.player
    local kind = gestureOf(game)
    local g = GESTURES[kind]
    local burst = t % g.every
    local n = math.floor(t / g.every)
    -- Put down mid-stroke: the hand lifts until the next one, rather than
    -- dragging the line on across the page to whoever is nearest now.
    if s.huntN == n and s.prey and s.prey.hp <= 0 then
        point(s.prey.x + 8, s.prey.y - 6, false)
        return
    end
    if s.huntN ~= n or not s.prey then
        s.huntN = n
        s.prey = nil
        if boss then
            local e = game.boss
            if e and not e.arrive then s.prey = e end
        else
            local best
            for _, e in ipairs(game.enemies) do
                local d = util.len(e.x - p.x, e.y - p.y)
                if not e.def.boss and d < near and (not best or d < best) then
                    s.prey, best = e, d
                end
            end
        end
    end
    local e = s.prey
    if not e then
        point(p.x + 26, p.y + 18, false)
        return
    end

    if kind == "drop" or kind == "snap" then
        -- Over it, and tapped -- or, a ruler, held there while it aims.
        point(e.x, e.y, burst < g.down)
        return
    end

    if kind == "sweep" then
        -- The needle between the hero and the prey, the leg opened out to it.
        local dx, dy, d = util.normalize(p.x - e.x, p.y - e.y)
        if d == 0 then dx, dy = 0, 1 end
        local r = util.clamp(e.radius + 22, 18, 50)
        local cx, cy = e.x + dx * r, e.y + dy * r
        if burst > g.down then
            point(cx, cy, false)
            return
        end
        local f = math.min(1, burst / (g.down * 0.8))
        point(cx + (e.x - cx) * f, cy + (e.y - cy) * f, true)
        return
    end

    local r = math.max(7, e.radius * 1.6)
    if burst > g.down then
        point(e.x - r, e.y - 2, false)
        return
    end
    local f = burst / g.down
    point(e.x + (f - 0.5) * r * 2, e.y + math.sin(f * math.pi * 7) * r * 0.6, true)
end

-- The lesson's own tool in the hand, for a reel that is about the lesson: the
-- one it issues (src/subjects.lua's `tool`) rather than the pencil every run
-- also carries.
local function lessonTool(game)
    for i, slot in ipairs(game.loadout.equipped) do
        local t = slot.tool
        if t and (t.icon == game.subject.tool or t.name:lower() == game.subject.tool) then
            game.tool = i
        end
    end
end

-- A run on the lesson's page with nothing on it but what the shot puts there:
-- no horde of the minute's own, no sheets but the shot's, the hero untouchable
-- (`truce`, as while a boss comes apart: nothing lands and nothing blinks) and
-- the meter kept full by the director.
local function lessonRun(game, subject)
    runShot(game, subject)
    game.time = 20
    game.spawner.update = function() end
    setmetatable(game.worksheetCells, { __index = function() return true end })
    game.player.truce = true
    -- A diamond taken on camera would bank a level, and the draft would stop
    -- the take.
    game.player.levelUp = function() end
    lessonTool(game)
end

-- Walk the hero to a page point and stand.
local function walkTo(game, x, y)
    local dx, dy, d = util.normalize(x - game.player.x, y - game.player.y)
    if d < 1 then return 0, 0 end
    local k = math.min(1, d / 6)
    return dx * k, dy * k
end

-- The sheets are dealt at a master's (the page's course is read by each
-- sheet's constructor, src/worksheet.lua): the harder board is the better
-- picture -- a diode to wire the right way round, a question past school --
-- while the horde round them stays the first year's.
local SHEET_COURSE = "masters"

-- A sheet's prize, given its moment: found on the page the frame it drops, then
-- the camera cuts in close on it (`PRIZE_LOOK` later) and the hero walks over
-- and takes it (`PRIZE_WALK` later) -- a prize taken the instant it lands is a
-- prize nobody saw.
local PRIZE_LOOK, PRIZE_WALK = 0.45, 1.2

-- Asked from the frame the sheet is won: the newest thing on the page is what
-- it paid. Not looked for by kind -- a master's board pays better than its row
-- says (Worksheet.prize turns a heart or a diamond into the course's own).
local function prizeWatch(game, s, t)
    if s.prize then return end
    local k = game.pickups[#game.pickups]
    if k and not k.dead then s.prize, s.prizeT = k, t end
end

local function prizeMove(game, s, t)
    if s.prizeT and t - s.prizeT > PRIZE_WALK then return walkTo(game, s.prize.x, s.prize.y) end
end

local function prizeZoom(game, t, s)
    return s.prizeT and t - s.prizeT > PRIZE_LOOK and ZOOM or 1
end

-- Between the prize and the hero, weighted to the prize: it is the subject, and
-- he is walking in to it.
local function prizeAim(sheet)
    return function(game)
        local left, top = Camera.steady()
        local k, p = sheet.prize, game.player
        if not k then return p.x - left, p.y - top end
        return k.x * 0.7 + p.x * 0.3 - left, k.y * 0.7 + p.y * 0.3 - top
    end
end


-- Playing: the hero walking a long slow curve through the page, the whole class
-- coming at him from every side, and the pencil out among them. Filmed close and
-- following the hero; the crowd is already there when the camera rolls.
local function playShot(subject, hook)
    return {
        kind = "run", warm = 3, rec = 7, zoom = ZOOM, hook = hook,
        aim = function(game)
            local left, top = Camera.steady()
            return game.player.x - left, game.player.y - top
        end,
        setup = function(game) lessonRun(game, subject) end,
        move = function(game, t)
            -- Under half speed, so the crowd keeps up with him in a close shot.
            local a = (t + 3) * 0.5
            return math.cos(a) * 0.45, math.sin(a) * 0.4
        end,
        direct = function(game, t, s)
            game.ink = game.loadout.stats.inkMax
            crowd(game, s, 0.1, 30, false, ZOOM)
            if t > 2.6 then s.hook = nil end
            if t > -0.6 then hunt(game, s, t + 0.6, 40) end
        end,
    }
end

-- The LAB board, the crowd still coming: the hero goes and stands on the right
-- answer while the hand keeps the nearest of them off him.
-- With `fail`, the board got wrong: the hero stands on a wrong answer, and the
-- camera cuts in on WRONG ANSWER and whatever the board charges for it (a giant
-- on the pop quiz and the LAB, a sting on the sequence and the STAVE).
local function labShot(subject, kind, prize, fail)
    local sheet
    sheet = {
        kind = "run", warm = 1.5, rec = fail and 4.2 or 6.2,
        zoom = fail and function(game, t, s)
            return s.failT and t - s.failT > 0.25 and ZOOM or 1
        end or prizeZoom,
        setup = function(game)
            lessonRun(game, subject)
            game.course = Course.get(SHEET_COURSE)
            local p = game.player
            local q = Worksheet._kinds[kind](p.x, p.y - 52, game)
            game.worksheets[#game.worksheets + 1] = q
            game.lab = q
        end,
        move = function(game, t)
            local q = game.lab
            if t < 0.6 then return 0, 0 end
            if q.state == "open" then
                local a = q.answers[q.quiz.right]
                if fail then a = q.answers[q.quiz.right % 3 + 1] end
                return walkTo(game, a.x, a.y)
            end
            -- Stood on the answer while the prize is looked at, then over to it.
            local mx, my = prizeMove(game, sheet, t)
            if mx then return mx, my end
            return 0, 0
        end,
        direct = function(game, t, s)
            game.ink = game.loadout.stats.inkMax
            crowd(game, s, 0.4, 12)
            if t > -0.6 then hunt(game, s, t + 0.6, 50) end
            if game.lab.state ~= "open" then
                if fail then s.failT = s.failT or t else prizeWatch(game, s, t, prize) end
            end
        end,
    }
    sheet.aim = prizeAim(sheet)
    if fail then
        -- On the words, thrown up over the board (src/worksheet.lua's Q:update).
        sheet.aim = function(game)
            local left, top = Camera.steady()
            local q = game.lab
            return q.x - left, q.y - 20 - q.bh / 2 - top
        end
    end
    return sheet
end

-- Simon says: the hand taps the bell, the tune plays while the hero walks over
-- to it (a note cannot be struck while the tune is playing), and then he walks
-- the notes in the order they were played. Every walk between two of the bell
-- and the notes is dealt clear of the rest (src/worksheet.lua's `fair`), so
-- starting from the bell no note is struck that the tune did not ask for.
local function simonShot(subject)
    local sheet
    sheet = {
        kind = "run", warm = 1.5, rec = 9, zoom = prizeZoom,
        setup = function(game)
            lessonRun(game, subject)
            -- A first-year's tune, three notes: at a master's five the walk
            -- between them is most of a minute of a reel.
            game.course = Course.get("school")
            local p = game.player
            local sim
            for k = 0, 20 do
                sim = Worksheet._kinds.simon(p.x, p.y - 70 - k, game)
                if sim then break end
            end
            game.worksheets[#game.worksheets + 1] = sim
            game.lab = sim
        end,
        move = function(game, t)
            local sim = game.lab
            if sim.state == "playing" then return walkTo(game, sim.bell.x, sim.bell.y) end
            if sim.state == "answer" then
                local pad = sim.pads[sim.tune[sim.pos]]
                return walkTo(game, pad.x, pad.y)
            end
            local mx, my = prizeMove(game, sheet, t)
            if mx then return mx, my end
            return 0, 0
        end,
        direct = function(game, t, s)
            game.ink = game.loadout.stats.inkMax
            crowd(game, s, 0.5, 8, true)
            local sim, p = game.lab, game.player
            if sim.state == "idle" then
                -- Over to the bell and tapped (the pen on it rings it).
                s.path = s.path or { { p.x + 30, p.y + 20 }, { wait = 0.2 },
                    { sim.bell.x, sim.bell.y, speed = 150 }, { wait = 0.15, down = true },
                    { sim.bell.x + 24, sim.bell.y + 24, speed = 90 } }
                local x, y, down = along(s.path, t)
                point(x, y, down)
            elseif t > -0.6 then
                hunt(game, s, t + 0.6, 40)
            end
            if sim.state == "won" then prizeWatch(game, s, t, "heart") end
        end,
    }
    sheet.aim = prizeAim(sheet)
    return sheet
end

-- The circuit, the crowd kept below it: the hand drags a wire across the gap,
-- from the battery's side to the bulb's, and the ringed bulb comes on.
-- With `fail`, the same board got wrong: the hand runs its wire from the
-- battery's + side into the return wire's stub, the battery sparks, and the
-- camera cuts in on SHORT CIRCUIT! as the sheet fades -- what a careless line
-- across bare copper costs, shown once before the board is got right.
local function circuitShot(subject, fail)
    local sheet
    sheet = {
        kind = "run", warm = 1.5, rec = fail and 3.4 or 5,
        zoom = fail and function(game, t, s)
            return s.failT and t - s.failT > 0.25 and ZOOM or 1
        end or prizeZoom,
        setup = function(game)
            lessonRun(game, subject)
            game.course = Course.get(SHEET_COURSE)
            local p = game.player
            -- High enough that the clock it drops under itself lands out of
            -- the hero's reach, to be walked to.
            local c = Worksheet._kinds.circuit(p.x, p.y - 80, game)
            game.worksheets[#game.worksheets + 1] = c
            game.lab = c
        end,
        move = function(game, t)
            local mx, my = prizeMove(game, sheet, t)
            if mx then return mx, my end
            return 0, 0
        end,
        direct = function(game, t, s)
            game.ink = game.loadout.stats.inkMax
            crowd(game, s, 0.45, 10, true)
            if game.lab.state == "won" then prizeWatch(game, s, t, "clock") end
            if game.lab.state == "fading" and not s.failT then s.failT = t end
            if t < 0.2 then
                hunt(game, s, t + 1.5, 40)
                return
            end
            local c, p = game.lab, game.player
            if not s.path then
                -- From the battery's + wire to a wire on towards the ringed
                -- bulb: `a`, or `b` where there is one, whichever does not
                -- end on a diode's cathode -- the one dealt backwards (a
                -- master's board) passes nothing. The stub on the return
                -- wire is the short, and never touched.
                local backwards = {}
                for _, part in ipairs(c.parts) do
                    if part.kind == "diode" then backwards[part.b] = true end
                end
                local from, to
                for _, e in ipairs(c.ends) do
                    if e.nets.p then from = e end
                end
                for _, net in ipairs(fail and { "n" } or { "a", "b" }) do
                    for _, e in ipairs(c.ends) do
                        if not to and e.nets[net] and not backwards[net] then to = e end
                    end
                end
                local left, top = Camera.steady()
                s.path = { { (hoverX or 120) + left, (hoverY or 200) + top },
                    { from.x, from.y, speed = 150 }, { wait = 0.12, down = true },
                    { to.x, to.y, down = true, speed = 45 }, { wait = 0.12, down = true },
                    { to.x + 24, to.y + 30, speed = 70 } }
            end
            if c.state ~= "open" and s.path.done then
                hunt(game, s, t, 40)
                return
            end
            local x, y, down, done = along(s.path, t - 0.2)
            s.path.done = done
            point(x, y, down)
        end,
    }
    sheet.aim = prizeAim(sheet)
    if fail then
        -- On the battery and the words thrown up beside it
        -- (src/worksheet.lua's C:judge).
        sheet.aim = function(game)
            local left, top = Camera.steady()
            local c = game.lab
            local bt = c.battery
            return bt.x + (c.mx and -20 or 20) - left, bt.y - 4 - top
        end
    end
    return sheet
end

-- Where a sheet's words go up, for a shot that cuts in on them.
local function failAim(at)
    return function(game)
        local left, top = Camera.steady()
        local x, y = at(game)
        return x - left, y - top
    end
end

local function failZoom(game, t, s)
    return s.failT and t - s.failT > 0.25 and ZOOM or 1
end

-- Join the dots, at a master's: the hand goes to the first dot and draws one
-- line through the rest in order, and the sheet rules the picture in behind it.
local function dotsShot(subject)
    local sheet
    sheet = {
        kind = "run", warm = 1.5, rec = 7.4, zoom = prizeZoom,
        setup = function(game)
            lessonRun(game, subject)
            game.course = Course.get(SHEET_COURSE)
            local p = game.player
            local j = Worksheet._kinds.dots(p.x, p.y - 66, game)
            game.worksheets[#game.worksheets + 1] = j
            game.lab = j
        end,
        move = function(game, t)
            local mx, my = prizeMove(game, sheet, t)
            if mx then return mx, my end
            return 0, 0
        end,
        direct = function(game, t, s)
            game.ink = game.loadout.stats.inkMax
            crowd(game, s, 0.45, 10, true)
            local j, p = game.lab, game.player
            if j.state == "open" or (s.path and not s.path.done) then
                if not s.path then
                    s.path = { { p.x + 30, p.y + 20 }, { wait = 0.2 },
                        { j.dots[1].x, j.dots[1].y, speed = 150 }, { wait = 0.1, down = true } }
                    for k = 2, #j.dots do
                        s.path[#s.path + 1] = { j.dots[k].x, j.dots[k].y, down = true, speed = 95 }
                    end
                    s.path[#s.path + 1] = { wait = 0.1, down = true }
                end
                local x, y, down, done = along(s.path, t)
                s.path.done = done
                point(x, y, down)
            elseif t > -0.6 then
                hunt(game, s, t, 40)
            end
            if j.state == "won" then prizeWatch(game, s, t) end
        end,
    }
    sheet.aim = prizeAim(sheet)
    return sheet
end

-- The portrait: the hero walks onto the chalk cross and sits, the hand keeping
-- the crowd off him while it is painted. Its sitting cut short once it has
-- started -- a master's eight seconds is a long time on a feed. With `fail`, he
-- gets up half way through and the camera cuts in on SMUDGED!.
local SIT_SHOWN = 2.8

local function portraitShot(subject, fail)
    local sheet
    sheet = {
        kind = "run", warm = 1.5, rec = fail and 4.6 or 6.6,
        zoom = fail and failZoom or prizeZoom,
        setup = function(game)
            lessonRun(game, subject)
            game.course = Course.get(SHEET_COURSE)
            local p = game.player
            local pr = Worksheet._kinds.portrait(p.x - 16, p.y - 46, game)
            game.worksheets[#game.worksheets + 1] = pr
            game.lab = pr
        end,
        move = function(game, t, s)
            local pr = game.lab
            if pr.state == "open" and not pr.live then return walkTo(game, pr.mx, pr.my) end
            if pr.live then
                if fail and s.sat and t - s.sat > 1.1 then return 1, 0.3 end
                return 0, 0
            end
            local mx, my = prizeMove(game, sheet, t)
            if mx then return mx, my end
            return 0, 0
        end,
        direct = function(game, t, s)
            game.ink = game.loadout.stats.inkMax
            crowd(game, s, 0.4, 12)
            local pr = game.lab
            if pr.live and not s.sat then
                s.sat = t
                pr.left = math.min(pr.left, SIT_SHOWN)
            end
            if t > -0.6 then hunt(game, s, t + 0.6, 45) end
            if pr.state == "fading" then s.failT = s.failT or t end
            if pr.state == "won" then prizeWatch(game, s, t) end
        end,
    }
    sheet.aim = fail and failAim(function(game)
        local pr = game.lab
        return pr.ex + pr.cw / 2, pr.ey - 4
    end) or prizeAim(sheet)
    return sheet
end

-- The market: the hero walks onto the sheet to open it, waits beside BUY and
-- steps in near the day's low, then waits beside SELL and steps in at a high
-- after it -- picked off the chart the sheet was dealt, so it is a trade that
-- pays -- and the coins it pays out are looked at and walked over. He is given
-- a stake to play with: a reel's run has picked nothing up.
local function marketShot(subject)
    local sheet
    sheet = {
        kind = "run", warm = 1.5, rec = 9, zoom = prizeZoom,
        setup = function(game)
            lessonRun(game, subject)
            game.course = Course.get(SHEET_COURSE)
            game.banked = 20
            local p = game.player
            local k = Worksheet._kinds.stocks(p.x, p.y - 50, game)
            game.worksheets[#game.worksheets + 1] = k
            game.lab = k
            local lo, hi
            for i = 3, 10 do
                if not lo or k.prices[i] < k.prices[lo] then lo = i end
            end
            for i = lo + 4, lo + 14 do
                if not hi or k.prices[i] > k.prices[hi] then hi = i end
            end
            sheet.buyAt, sheet.sellAt = lo, hi
        end,
        move = function(game, t, s)
            local k = game.lab
            if k.state == "open" then
                local f = k.live and k:at() or 0
                local b, sl = k.buy, k.sell
                if not k.held then
                    if f >= sheet.buyAt then return walkTo(game, b.x, b.y) end
                    return walkTo(game, b.x + b.w / 2 + 6, b.y)
                end
                if f >= sheet.sellAt then return walkTo(game, sl.x, sl.y) end
                return walkTo(game, sl.x - sl.w / 2 - 6, sl.y)
            end
            local mx, my = prizeMove(game, sheet, t)
            if mx then return mx, my end
            return 0, 0
        end,
        direct = function(game, t, s)
            game.ink = game.loadout.stats.inkMax
            crowd(game, s, 0.5, 10, true)
            if t > -0.6 then hunt(game, s, t + 0.6, 40) end
            if game.lab.state == "done" then prizeWatch(game, s, t) end
        end,
    }
    sheet.aim = prizeAim(sheet)
    return sheet
end

-- Hangman: the hero stands on the word's three missing letters, nearest first,
-- for SOLVED! and the diamond. With `fail`, on three that are not in it: the man
-- is drawn a piece a letter, the camera cuts in on HANGED!, and he climbs down.
local function hangmanShot(subject, fail)
    local sheet
    sheet = {
        kind = "run", warm = 1.5, rec = fail and 7.6 or 8,
        zoom = fail and failZoom or prizeZoom,
        setup = function(game)
            lessonRun(game, subject)
            game.course = Course.get(SHEET_COURSE)
            local p = game.player
            local g = Worksheet._kinds.hangman(p.x, p.y - 50, game)
            game.worksheets[#game.worksheets + 1] = g
            game.lab = g
            local missing = {}
            for k, ch in ipairs(g.chars) do
                if g.gaps[k] then missing[ch] = true end
            end
            sheet.want = {}
            for i, pad in ipairs(g.pads) do
                if (missing[pad.ch] and true or false) ~= (fail and true or false) then
                    sheet.want[#sheet.want + 1] = i
                end
            end
        end,
        move = function(game, t)
            local g = game.lab
            if t < 0.4 then return 0, 0 end
            if g.state == "open" then
                -- The nearest letter still wanted.
                local p, best, bd = game.player
                for _, i in ipairs(sheet.want) do
                    local pad = g.pads[i]
                    if not pad.given then
                        local d = util.len(pad.x - p.x, pad.y - p.y)
                        if not bd or d < bd then best, bd = pad, d end
                    end
                end
                if best then return walkTo(game, best.x, best.y) end
                return 0, 0
            end
            if fail then return 0, 0 end
            local mx, my = prizeMove(game, sheet, t)
            if mx then return mx, my end
            return 0, 0
        end,
        direct = function(game, t, s)
            game.ink = game.loadout.stats.inkMax
            crowd(game, s, 0.5, 10, true)
            local g = game.lab
            if t > -0.6 then hunt(game, s, t + 0.6, 40) end
            if g.state == "hanging" then s.failT = s.failT or t end
            if g.state == "won" then prizeWatch(game, s, t) end
        end,
    }
    sheet.aim = fail and failAim(function(game)
        local g = game.lab
        return g.x - 14, g.y - 24
    end) or prizeAim(sheet)
    return sheet
end

-- The dodgeball pit: the hero walks in, the whistle goes and the class is
-- thrown at him; he dodges, the hand fastening what it can. Its clock cut short
-- once it has started (a master's fifteen seconds). Lasted, SAFE! and the
-- diamond; with `fail`, he steps over the line and the camera cuts in on OUT!.
local PIT_SHOWN = 3.2

local function dodgeShot(subject, fail)
    local sheet
    sheet = {
        kind = "run", warm = 1.5, rec = fail and 4.4 or 7,
        zoom = fail and failZoom or prizeZoom,
        setup = function(game)
            lessonRun(game, subject)
            game.course = Course.get(SHEET_COURSE)
            local p = game.player
            local d = Worksheet._kinds.dodgeball(p.x, p.y - 64, game)
            game.worksheets[#game.worksheets + 1] = d
            game.lab = d
        end,
        move = function(game, t, s)
            local d, p = game.lab, game.player
            if d.state == "open" and not d.live then return walkTo(game, d.x, d.y + 16) end
            if d.live then
                if fail and s.live and t - s.live > 1.3 then return 0, 1 end
                -- Side to side across the pit: dodging, not standing.
                local a = (t - (s.live or t)) * 2.2
                return walkTo(game, d.x + math.sin(a) * 26, d.y + 16)
            end
            if fail then return 0, 0 end
            local mx, my = prizeMove(game, sheet, t)
            if mx then return mx, my end
            return 0, 0
        end,
        direct = function(game, t, s)
            game.ink = game.loadout.stats.inkMax
            local d = game.lab
            if d.live and not s.live then
                s.live = t
                d.left = math.min(d.left, PIT_SHOWN)
            end
            if t > -0.6 then hunt(game, s, t + 0.6, 50) end
            if d.state == "fading" then
                s.failT = s.failT or t
                s.outX, s.outY = s.outX or game.player.x, s.outY or game.player.y
            end
            if d.state == "won" then prizeWatch(game, s, t) end
        end,
    }
    sheet.aim = fail and failAim(function(game)
        local s, p = sheet, game.player
        return s.outX or p.x, (s.outY or p.y) - 14
    end) or prizeAim(sheet)
    return sheet
end

-- Hopscotch: the first boxes of a path (a feed has no time for the whole
-- walk), hopped in order from the flag to FINISH! and the heart.
local HOPS = 7

local function hopShot(subject)
    local sheet
    sheet = {
        kind = "run", warm = 1.5, rec = 7.6, zoom = prizeZoom,
        setup = function(game)
            lessonRun(game, subject)
            game.course = Course.get("school")
            local p = game.player
            local h
            for k = 0, 20 do
                h = Worksheet._kinds.hopscotch(p.x + k * 3, p.y - 60, game)
                if h then break end
            end
            -- Cut down to its first boxes: the rest of the walk is not printed.
            for k = #h.path, HOPS + 1, -1 do
                local c = table.remove(h.path, k)
                h.index[c.i * 65536 + c.j] = nil
            end
            game.worksheets[#game.worksheets + 1] = h
            game.lab = h
        end,
        move = function(game, t)
            local h = game.lab
            local dd = h.days
            if h.state == "open" then
                local c = h.path[(h.reached or 0) + 1]
                if c then return walkTo(game, c.x + dd.w / 2, c.y + (dd.h + dd.rule) / 2) end
            end
            local mx, my = prizeMove(game, sheet, t)
            if mx then return mx, my end
            return 0, 0
        end,
        direct = function(game, t, s)
            game.ink = game.loadout.stats.inkMax
            crowd(game, s, 0.5, 8, true)
            if t > -0.6 then hunt(game, s, t + 0.6, 40) end
            if game.lab.state == "won" then prizeWatch(game, s, t) end
        end,
    }
    sheet.aim = prizeAim(sheet)
    return sheet
end

-- A boss, cut to: its landing, or a move it is forced into once it is in the
-- box with the hero (`force`, called every frame until it says it is done). No
-- caption -- the game's own call is the caption.
local function bossCut(subject, encore, warm, rec, force)
    if type(warm) == "table" then
        warm, rec, force = warm.warm, warm.rec, warm.force
    end
    return {
        kind = "boss", subject = subject, encore = encore,
        warm = warm, rec = rec, zoom = ZOOM,
        direct = force and function(game, t, s)
            local e = game.boss
            if e and not e.arrive and not s.forced then s.forced = force(game, e, t, s) end
        end,
    }
end

-- The eye's weep: hurt into its second third (which it says with a flinch,
-- unseen), and made to cry once it is free to.
local function eyeWeeps(game, e, t, s)
    if not s.hurt then
        s.hurt = true
        e.hp = math.floor(e.maxHp * 0.6)
    end
    local b = e.brain
    if t > -0.75 and (b.state == "idle" or b.state == "resting") then
        b:weepStart(game, e)
        return true
    end
end

-- The atom past half and let go of whatever it was doing, so it comes apart on
-- the next frame (AtomBoss:update) -- FISSION!, the tell and the two halves
-- flung -- rather than whenever the move it was in lets it.
local function atomSplits(game, e, t)
    if t > -0.4 then
        e.hp = math.floor(e.maxHp * 0.48)
        e.brain:clear(e)
        e.brain.state, e.brain.t = "idle", 1
        return true
    end
end

-- A boss made to play the move it is known for once it is free to: `start` is
-- the brain's own Start for it, and `hurt` the share of its health to knock it
-- down to first where the move waits on a phase.
local function forceMove(start, hurt, states)
    states = states or { idle = true, resting = true }
    return function(game, e, t, s)
        if hurt and not s.hurt then
            s.hurt = true
            e.hp = math.floor(e.maxHp * hurt)
        end
        local b = e.brain
        if t > -0.9 and states[b.state] then
            start(b, game, e)
            return true
        end
    end
end

-- The metronome: a sweep, counted in on the beat like every move it plays --
-- a whole bar of it, four seconds at its first tempo, so it is cued that long
-- before the camera rolls and the cut opens on the beam going hot.
local function metronomeSweeps(game, e, t)
    local b = e.brain
    if t > -4.3 and b.state == "idle" then
        b.move, b.state, b.left = "sweep", "count", b.def.bar
        b:sweepStart(game, e)
        return true
    end
end

-- `sheets` are the lesson's own worksheets, a shot builder each, and `cuts` its
-- two bosses' moments after their landings: { warm, rec, force }, and `enter`
-- the first boss's landing's own warm, where it comes from off the shot.
local function lessonReel(key, sheets, cuts)
    return function()
        local subject = Subjects.get(key)
        local shots = {}
        shots[#shots + 1] = playShot(key, { subject.name })
        for _, sheet in ipairs(sheets) do shots[#shots + 1] = sheet(key) end
        shots[#shots + 1] = bossCut(key, false, cuts[1].enter or 0.25, 1.7)
        shots[#shots + 1] = bossCut(key, false, cuts[1])
        shots[#shots + 1] = bossCut(key, true, 2, 1.4)
        shots[#shots + 1] = bossCut(key, true, cuts[2])
        shots[#shots + 1] = { kind = "card", rec = 2.2, lines = { "SURVIVE", "SCHOOL" } }
        return shots
    end
end

local REELS = {
    montage = bossMontage,
    sun = sunReel,
    science = lessonReel("science", {
        function(key) return labShot(key, "science", "diamond") end,
        function(key) return circuitShot(key, true) end,
        circuitShot,
    }, { { warm = 5, rec = 1.9, force = eyeWeeps },
         { warm = 4, rec = 2.2, force = atomSplits } }),
    music = lessonReel("music", {
        function(key) return labShot(key, "music", "heart") end,
        simonShot,
        function(key) return labShot(key, "music", "heart", true) end,
    }, { { warm = 5.5, rec = 2.4, force = metronomeSweeps },
         { warm = 3, rec = 2.6, force = forceMove(function(b, game, e)
             b:dropStart(game, e, e.speaker) end, nil, { idle = true }) } }),
    maths = lessonReel("maths", {
        function(key) return labShot(key, "quiz", "diamond") end,
        function(key) return labShot(key, "sequence", "heart") end,
        function(key) return labShot(key, "quiz", "diamond", true) end,
    }, { { warm = 2.5, rec = 2.6, enter = 1.1 },
         { warm = 4, rec = 2.6, force = forceMove(function(b, game, e)
             b:foldStart(game, e, e.tesseract) end, 0.6) } }),
    art = lessonReel("art", {
        dotsShot,
        portraitShot,
        function(key) return portraitShot(key, true) end,
    }, { { warm = 3.5, rec = 2.4 }, { warm = 3.5, rec = 2.4 } }),
    finance = lessonReel("finance", {
        function(key) return labShot(key, "finance") end,
        marketShot,
        function(key) return labShot(key, "finance", nil, true) end,
    }, { { warm = 3.5, rec = 2.4 }, { warm = 3.5, rec = 2.4 } }),
    grammar = lessonReel("language", {
        hangmanShot,
        function(key) return hangmanShot(key, true) end,
    }, { { warm = 3.5, rec = 2.4 }, { warm = 3.5, rec = 2.4 } }),
    pe = lessonReel("pe", {
        dodgeShot,
        hopShot,
        function(key) return dodgeShot(key, true) end,
    }, { { warm = 3.5, rec = 2.4 }, { warm = 3.5, rec = 2.4 } }),
}

--- the clock -----------------------------------------------------------------

local shots, shot, index
local shotT = 0
local game

local clock = 0         -- seconds since the camera first rolled, filmed or not
local filmed = 0        -- frames written
local recording = false

local realGetTime

--- sound ---------------------------------------------------------------------

local events = {}       -- { at, name, pitch, cut }
local byVoice = {}      -- voice -> its event, while it may still be cut

local function hookSound()
    local play, cut = Sfx.play, Sfx.cut

    Sfx.play = function(name, pitch)
        local v = play(name, pitch)
        if v and recording then
            local ev = { at = filmed * DT, name = name, pitch = v:getPitch() }
            events[#events + 1] = ev
            byVoice[v] = ev
        end
        return v
    end

    Sfx.cut = function(voice)
        local ev = voice and byVoice[voice]
        if ev and not ev.cut then ev.cut = filmed * DT end
        return cut(voice)
    end
end

-- Lays every logged play over silence, stereo float at RATE. A pitch is a speed
-- change in OpenAL and so it is here: the sample is read that much faster. A
-- cut fades out over the game's own 0.05s (src/sfx.lua).
local function mix(seconds, level)
    local frames = math.ceil(seconds * RATE)
    local out = ffi.new("float[?]", frames * 2)

    for _, ev in ipairs(events) do
        local quiet = (MUTED[ev.name] and not REEL_CURSOR[Capture.reel])
            or (REEL_MUTED[Capture.reel] or {})[ev.name]
        local data = not quiet and Sfx.sample(ev.name)
        if data then
            local channels = data:getChannelCount()
            local count = data:getSampleCount()
            local step = ev.pitch * data:getSampleRate() / RATE
            local start = math.floor(ev.at * RATE)
            local stop = ev.cut and math.floor((ev.cut + 0.05) * RATE) or math.huge
            local fadeFrom = ev.cut and math.floor(ev.cut * RATE) or math.huge

            local k = 0
            while true do
                local o = start + k
                local pos = k * step
                local i = math.floor(pos)
                if o >= frames or o >= stop or i + 1 >= count then break end
                local f = pos - i
                local g = level
                if o > fadeFrom then g = g * (1 - (o - fadeFrom) / (stop - fadeFrom)) end
                for c = 0, 1 do
                    local ch = math.min(c + 1, channels)
                    local a = data:getSample(i, ch)
                    local b = data:getSample(i + 1, ch)
                    out[o * 2 + c] = out[o * 2 + c] + (a + (b - a) * f) * g
                end
                k = k + 1
            end
        end
    end
    return out, frames
end

--- the bot -------------------------------------------------------------------

-- Something to watch: it walks a slow circle round the boss, keeping off it,
-- and scribbles across it in bursts, the way a player fights. It is not trying
-- to win -- the hero is topped up every frame -- only to look like play.
local bot = { t = 0, seed = 0 }

local function steer(game)
    local p, boss = game.player, game.boss
    if not p then return 0, 0 end
    if not boss or boss.arrive then
        -- Before the boss lands: drift, so the hero is not a statue.
        local a = bot.t * 0.9 + bot.seed
        return math.cos(a) * 0.5, math.sin(a) * 0.5
    end

    local dx, dy, d = util.normalize(p.x - boss.x, p.y - boss.y)
    if d == 0 then dx, dy = 0, 1 end
    -- Round it, and out or in toward a ring that clears its body.
    -- Closer when filmed close, or the hero walks out of the shot.
    local want = boss.radius + ((shot and shot.zoom or 1) > 1 and 30 or 46)
    local out = util.clamp((want - d) / 20, -1, 1)
    local tx, ty = -dy, dx
    if bot.seed % 2 < 1 then tx, ty = dy, -dx end
    local mx, my = tx * 0.85 + dx * out, ty * 0.85 + dy * out
    local nx, ny, len = util.normalize(mx, my)
    if len == 0 then return 0, 0 end
    return nx, ny
end

local function scribble(game)
    local boss = game.boss
    local burst = (bot.t + bot.seed) % 1.3
    if not boss or boss.arrive then
        Input.pointerDown = false
        return
    end

    -- A zigzag dragged across the body; between bursts, the lifted hand sits
    -- where the next one starts, so a drawn cursor glides there.
    local r = math.max(8, boss.radius * 0.8)
    if burst > 0.75 or game.ink < 0.2 then
        point(boss.x - r * 0.8, boss.y, false)
        return
    end
    local zig = math.sin(burst * 22) * r
    local drift = (burst / 0.75 - 0.5) * r * 1.6
    point(boss.x + drift, boss.y + zig * 0.6, true)
end

--- the lens --------------------------------------------------------------------

-- Close up is the game's canvas blown up again, `zoom` times, on a second canvas
-- the size of the first: every game pixel becomes a square block of them, so the
-- picture is still whole pixels on the grid -- just fewer, bigger ones -- and the
-- caption drawn over it afterwards stays at the page's own size. The window onto
-- the canvas is aimed between the hero and the boss, weighted to the boss (it
-- lands far from the hero and is the subject), eased so the shot does not judder
-- with the walk, and kept inside the canvas and off the HUD. Aimed at the
-- landing spot during the drop, which is where the ring is closing.
local lensX, lensY
local out

-- Rows of the canvas the HUD lives in, top and bottom, kept out of a close shot:
-- the bars blown up are a picture of the HUD, not of the fight.
local HUD_TOP, HUD_BOTTOM = 34, 22

local function aim()
    local p, boss = game.player, game.boss
    local left, top = Camera.steady()
    local x, y = p.x, p.y
    if boss then x, y = boss.x * 0.6 + p.x * 0.4, boss.y * 0.6 + p.y * 0.4 end
    return x - left, y - top
end

-- A shot's zoom is a number, or a function of the shot's clock for one that
-- punches in partway through; `aim` likewise names where to look, and a shot
-- that is about a weapon rather than a boss may let the HUD into the frame
-- (`hud`), since the weapon's own column is part of what is being shown.
local lastZoom

local function zoomOf()
    local z = shot.zoom or 1
    if type(z) == "function" then z = z(game, shotT - (shot.warm or 0), shot) end
    return z
end

local function lens(canvas)
    local z = zoomOf()
    local w, h = canvas:getDimensions()
    if not out then
        out = love.graphics.newCanvas(w, h)
        out:setFilter("nearest", "nearest")
    end

    love.graphics.setCanvas(out)
    love.graphics.clear(Palette.paper)
    love.graphics.setColor(1, 1, 1)
    -- A punch in is a cut, not a drift: the lens starts on its subject.
    if z ~= lastZoom then lensX, lastZoom = nil, z end
    if z == 1 or (shot.kind ~= "boss" and shot.kind ~= "run") then
        love.graphics.draw(canvas, 0, 0)
        return out
    end

    local tx, ty = (shot.aim or aim)(game)
    if not lensX then lensX, lensY = tx, ty end
    lensX = lensX + (tx - lensX) * math.min(1, DT * 5)
    lensY = lensY + (ty - lensY) * math.min(1, DT * 5)

    local vw, vh = w / z, h / z
    local top, bottom = HUD_TOP, HUD_BOTTOM
    if shot.kind == "run" then top, bottom = 0, 0 end
    local ox = math.floor(util.clamp(lensX - vw / 2, 0, w - vw) + 0.5)
    local oy = math.floor(util.clamp(lensY - vh / 2, top, h - vh - bottom) + 0.5)
    love.graphics.draw(canvas, -ox * z, -oy * z, 0, z, z)
    return out
end

--- shots ---------------------------------------------------------------------


local function begin(i)
    index, shot, shotT = i, shots[i], 0
    if not shot then return end
    print(string.format("capture: shot %d/%d", i, #shots))

    love.math.setRandomSeed(1000 + i)
    bot.t, bot.seed = 0, i * 0.77

    Input.releaseAll()
    Input.pointerDown = false
    lensX = nil
    hoverX, hoverY, aimX, aimY = nil, nil, nil, nil

    if shot.kind == "boss" then
        game:setSubject(shot.subject)
        -- The encore is the second boss, which only a two-boss course sends;
        -- the dev boss test sends the last of the lineup (Game:reset).
        Course.current = Course.get(shot.encore and "masters" or "school")
        Dev.boss = true
        game:reset()
        -- The draft would stop the take; a level is not what is being filmed.
        game.player.addXp = function() end
        if REEL_CURSOR[Capture.reel] then lessonTool(game) end
        -- And the coaching hand (src/coach.lua) is for somebody who has not
        -- drawn on the crowd yet; the bot is about to.
        game.drewKill = true
    elseif shot.setup then
        shot.setup(game)
    end
end

local function shotDone()
    return shotT >= (shot.warm or 0) + shot.rec
end

--- the pipe ------------------------------------------------------------------

local pipe, outDir, videoPath, audioPath, finalPath
local canvasW, canvasH

local function sh(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function openPipe(w, h)
    canvasW, canvasH = w, h
    os.execute("mkdir -p " .. sh(outDir))
    local cmd = string.format(
        "ffmpeg -loglevel error -y -f rawvideo -pix_fmt rgba -s %dx%d -r %d -i - "
            .. "-vf scale=%d:%d:flags=neighbor -c:v libx264 -preset slow -crf 16 "
            .. "-pix_fmt yuv420p %s",
        w, h, FPS, w * UPSCALE, h * UPSCALE, sh(videoPath))
    pipe = io.popen(cmd, "w")
end

local function finish()
    if pipe then pipe:close() end
    pipe = nil

    local seconds = filmed * DT
    local level, musicLevel, music = Sfx.levels()
    local buf, frames = mix(seconds, level)
    local f = io.open(audioPath, "wb")
    f:write(ffi.string(buf, frames * 2 * 4))
    f:close()

    local track = love.filesystem.getSource() .. "/" .. music
    local cmd = string.format(
        "ffmpeg -loglevel error -y -i %s -f f32le -ar %d -ac 2 -i %s -stream_loop -1 -i %s "
            .. "-filter_complex \"[2:a]volume=%.4f[m];[1:a][m]amix=inputs=2:normalize=0:duration=first,"
            .. "loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[a]\" -map 0:v -map \"[a]\" -c:v copy -c:a aac -b:a 192k "
            .. "-t %.3f -movflags +faststart %s",
        sh(videoPath), RATE, sh(audioPath), sh(track), musicLevel, seconds, sh(finalPath))
    local ok = os.execute(cmd)
    os.remove(audioPath)
    if ok == 0 or ok == true then os.remove(videoPath) end
    print(string.format("capture: %d frames, %.1fs, %d sounds -> %s",
        filmed, seconds, #events, finalPath))
    love.event.quit()
end

--- the doors main.lua opens --------------------------------------------------

-- Read off the command line before anything is loaded: whether this is a take
-- at all, and which reel. `love . --capture montage [outdir]`.
function Capture.parse(args)
    for i, a in ipairs(args or {}) do
        if a == "--capture" then
            Capture.on = true
            Capture.reel = args[i + 1] or "montage"
            outDir = args[i + 2] or (love.filesystem.getSource() .. "/capture")
        end
    end
    if not Capture.on then return end
    if not REELS[Capture.reel] then error("capture: no reel named " .. Capture.reel) end

    love.filesystem.setIdentity("notebook-survivors-capture")
    love.window.setMode(WINDOW_W, WINDOW_H, { fullscreen = false, resizable = false, vsync = 0 })
    love.audio.setVolume(0)

    videoPath = outDir .. "/" .. Capture.reel .. ".video.mp4"
    audioPath = outDir .. "/" .. Capture.reel .. ".f32"
    finalPath = outDir .. "/" .. Capture.reel .. ".mp4"

    realGetTime = love.timer.getTime
    love.timer.getTime = function() return clock end
end

-- After Game:load, which has built the scaffolding run behind a title nobody will
-- see.
function Capture.start(g)
    game = g
    hookSound()
    -- The pointer is the bot's, and on most reels a drawn cursor would only say
    -- so; a reel that is about how the page is written on draws it.
    Input.hover = function()
        if REEL_CURSOR[Capture.reel] then return hoverX, hoverY end
    end
    Input.movement = function()
        if shot and shot.move then return shot.move(game, shotT - (shot.warm or 0), shot) end
        return steer(game)
    end

    shots = REELS[Capture.reel]()
    begin(1)
end

-- Every frame's dt, whatever the machine took.
function Capture.dt()
    return DT
end

function Capture.update()
    clock = clock + DT
    if not shot then return end

    shotT = shotT + DT
    bot.t = bot.t + DT
    recording = shotT > (shot.warm or 0)

    if shot.kind == "boss" then
        game.player.hp = game.player.maxHp
        if REEL_CURSOR[Capture.reel] then
            game.ink = game.loadout.stats.inkMax
            -- A pin glues what it lands on (src/pin.lua), and a glued boss drops
            -- whatever it was winding up: the move a cut is there to show. So
            -- the pin is for the escort, and the boss is left to play.
            if gestureOf(game) == "drop" then
                hunt(game, bot, bot.t, 90)
            else
                hunt(game, bot, bot.t, 0, true)
            end
        else
            scribble(game)
        end
    elseif shot.kind == "run" then
        game.player.hp = game.player.maxHp
    end
    if shot.direct then shot.direct(game, shotT - (shot.warm or 0), shot) end

    -- The cursor is on the pen while it is down, and eases after the hand
    -- while it is lifted, so it never jumps between strokes.
    if aimX then
        if Input.pointerDown or not hoverX then
            hoverX, hoverY = aimX, aimY
        else
            local k = math.min(1, DT * 14)
            hoverX = hoverX + (aimX - hoverX) * k
            hoverY = hoverY + (aimY - hoverY) * k
        end
    end
end

-- Drawn on top of the page, inside the canvas, so it is pixels of the same size
-- as everything else and in the palette.
local function caption()
    local w, h = game.vw, game.vh
    if shot.kind == "card" then
        love.graphics.setColor(Palette.paper)
        love.graphics.rectangle("fill", 0, 0, w, h)
        local s = 4
        local lh = (Font.height or 5) * s + 6
        local y = math.floor(h / 2 - #shot.lines * lh / 2)
        for i, line in ipairs(shot.lines) do
            local text = I18n.t(line)
            local n = math.floor(shotT * 18)
            Scribble.printBig(text, w / 2, y + (i - 1) * lh, s,
                i == 1 and Palette.ink or Palette.red,
                { shadow = Palette.graphite, count = n - (i - 1) * 6, wobble = true,
                  t = shotT, seed = i * 7 })
        end
        return
    end

    -- The hook, over the first shot only: what the reel is, said before
    -- anybody has decided whether to watch it.
    if shot.hook then
        for i, line in ipairs(shot.hook) do
            Scribble.printBig(I18n.t(line), w / 2, (shot.hookY or 28) + (i - 1) * 22, 3,
                i == 1 and Palette.ink or Palette.red,
                { shadow = Palette.paper, count = math.floor(shotT * 18) - (i - 1) * 6,
                  wobble = true, t = shotT, seed = i * 7 })
        end
    end

    -- A line said over the shot as it goes (`say`, set by its director), or a
    -- level and the card's own words for it, low on the page.
    if shot.kind ~= "boss" then
        local y = h - 70
        if shot.tag then
            Scribble.printBig(I18n.t(shot.tag), w / 2, y - 16, 2, Palette.red,
                { shadow = Palette.paper, wobble = true, t = shotT, seed = index })
        end
        local text = shot.say or shot.text
        if text then
            for i, line in ipairs(Font.wrap(I18n.t(text), math.floor((w - 16) / 2))) do
                Scribble.printBig(line, w / 2, y + (i - 1) * 14, 2, Palette.ink,
                    { shadow = Palette.paper, wobble = true, t = shotT, seed = index + i })
            end
        end
        return
    end

    -- The boss's name low on the page and its number in the reel above it.
    if not shot.title then return end
    local s = 2
    local y = h - 64
    Scribble.printBig(shot.tag, w / 2, y - 14, 1, Palette.graphite, {})
    Scribble.printBig(I18n.t(shot.title), w / 2, y, s, Palette.ink,
        { shadow = Palette.paper, wobble = true, t = shotT, seed = index })
end

-- Called with the canvas still bound, after the game has drawn: the lens, the
-- caption over it, then the frame read back and down the pipe.
function Capture.frame(canvas)
    if not shot then
        finish()
        return
    end
    local frame = lens(canvas)
    caption()
    love.graphics.setCanvas()

    if recording then
        if not pipe then openPipe(frame:getDimensions()) end
        pipe:write(frame:newImageData():getString())
        filmed = filmed + 1
    end

    if shotDone() then begin(index + 1) end
end

return Capture
