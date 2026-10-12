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
local Hud = require("src.hud")
local I18n = require("src.i18n")
local Input = require("src.input")
local Library = require("src.library")
local Palette = require("src.palette")
local Pickup = require("src.pickup")
local Scribble = require("src.scribble")
local Sfx = require("src.sfx")
local Sprites = require("src.sprites")
local Studio = require("src.studio")
local Subjects = require("src.subjects")
local Tools = require("src.tools")
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
-- And how loud a reel's sounds are laid over the track, where not the game's
-- own level: the pickup reels are a sound on every grab and every kill round a
-- hand that never stops, and at full level they bury the music.
local REEL_SFX = { pickups = 0.45, heart = 0.45, ink = 0.45, diamond = 0.45,
                   clock = 0.45, alarm = 0.45, star = 0.45, coin = 0.45 }

local REEL_MUTED = { sun = { hurt = true }, cools = { hurt = true },
                     storm = { hurt = true }, science = { hurt = true },
                     music = { hurt = true }, maths = { hurt = true },
                     art = { hurt = true }, finance = { hurt = true },
                     grammar = { hurt = true }, pe = { hurt = true },
                     halo = { hurt = true }, trench = { hurt = true },
                     snag = { hurt = true }, punch = { hurt = true }, guillotine = { hurt = true }, tearline = { hurt = true }, parting = { hurt = true }, underline = { hurt = true }, corral = { hurt = true }, spindle = { hurt = true }, crater = { hurt = true }, dots = { hurt = true },
                     heart = { hurt = true }, ink = { hurt = true }, diamond = { hurt = true },
                     clock = { hurt = true }, alarm = { hurt = true },
                     star = { hurt = true }, coin = { hurt = true },
                     pickups = { hurt = true } }

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

local function faceStrokes(art)
    local strokes = {}
    for y, row in ipairs(art) do
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

local FACE = faceStrokes(Sprites.SUNFACE)
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
-- layout, so the bot draws on whatever size of board the studio picked. Any
-- other design drawn in rows (`faceStrokes`) is drawn by the same hand.
local function faceAt(t, strokes)
    local lay = Studio.lay
    if not lay or t < 0 then return nil end
    for _, stroke in ipairs(strokes or FACE) do
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
local wrapUp

local REEL_CURSOR = { science = true, music = true, maths = true,
                      art = true, finance = true, grammar = true, pe = true,
                      halo = true, trench = true, snag = true, punch = true, guillotine = true, tearline = true, parting = true, underline = true, corral = true, spindle = true, crater = true, dots = true,
                      heart = true, ink = true, diamond = true, clock = true,
                      alarm = true, star = true, coin = true, pickups = true }

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
    cut = { every = 1.0, down = 0.43 },
}

local function gestureOf(game)
    local tool = game.loadout:tool(game.tool)
    if tool and tool.sweep then return "sweep" end
    if tool and tool.drop then return "drop" end
    if tool and tool.snap then return "snap" end
    if tool and tool.cut then return "cut" end
    return "brush"
end

-- The share of a compass's reach between its smallest and widest circle that
-- each swing of a fusion reel opens to (`vary` on the shot), in turn.
local VARY = { 0.15, 0.6, 1, 0.35, 0.8 }

local function hunt(game, s, t, near, boss)
    local p = game.player
    local kind = gestureOf(game)
    local g = GESTURES[kind]
    local burst = t % g.every
    local n = math.floor(t / g.every)
    -- Put down mid-stroke: the hand lifts until the next one, rather than
    -- dragging the line on across the page to whoever is nearest now.
    if kind ~= "cut" and s.huntN == n and s.prey and s.prey.hp <= 0 then
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

    if kind == "cut" then
        -- Scissors: tapped once just short of the prey and once just past it,
        -- along the line to whoever stands nearest it, so the cut runs through
        -- both. The second tap always comes, dead prey or not -- an anchor
        -- left open would turn the next cycle's first tap into a cut.
        if s.cutN ~= n then
            s.cutN = n
            local o, od
            for _, f in ipairs(game.enemies) do
                local d = util.len(f.x - e.x, f.y - e.y)
                if f ~= e and not f.def.boss and d < 40 and (not od or d < od) then o, od = f, d end
            end
            local dx, dy, d = 0, 0, 0
            if o then dx, dy, d = util.normalize(o.x - e.x, o.y - e.y) end
            if d == 0 then dx, dy = util.normalize(e.x - p.x, e.y - p.y) end
            s.cutDx, s.cutDy = dx, dy
        end
        local dx, dy = s.cutDx, s.cutDy
        if burst < 0.35 then
            point(e.x - dx * 16, e.y - dy * 16, burst < 0.08)
        else
            point(e.x + dx * 24, e.y + dy * 24, burst < g.down)
        end
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
        if s.vary then
            -- A fusion reel shows the compass's range rather than its habit:
            -- every circle a different size, small to the tool's full reach.
            local sw = game.loadout:tool(game.tool).sweep
            local f = VARY[n % #VARY + 1]
            r = sw.minR + (sw.maxR - sw.minR) * f
        end
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

-- A sheet shot ends on its moment rather than running its length out: a beat
-- after the last of the prize is taken, or a second and a bit after the words
-- of a failure are up. A prize paid in several (the till's coins, the market's)
-- is walked over one after another before that, the next being whatever is
-- lying nearest where the last one was.
local PRIZE_NEAR = 36

function wrapUp(game, s, t)
    if s.wrapped then return end
    if s.failT then
        s.wrapped = true
        s.rec = math.min(s.rec, s.failT + 1.9)
        return
    end
    local k = s.prize
    if not k or not k.dead then return end
    local best, bd
    for _, o in ipairs(game.pickups) do
        local d = util.len(o.x - k.x, o.y - k.y)
        if not o.dead and d < PRIZE_NEAR and (not bd or d < bd) then best, bd = o, d end
    end
    if best then
        s.prize = best
        return
    end
    s.wrapped = true
    -- Unless the shot has something still to show after the take (`hold`, a
    -- pickup reel's effect).
    s.rec = math.max(math.min(s.rec, t + 0.7), s.hold or 0)
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
-- `course` deals it at another rung than a master's: a heart or a diamond is
-- only what the board pays below one (Worksheet.prize).
local function labShot(subject, kind, prize, fail, course)
    local sheet
    sheet = {
        kind = "run", warm = 1.5, rec = fail and 4.2 or 6.2,
        zoom = fail and function(game, t, s)
            return s.failT and t - s.failT > 0.25 and ZOOM or 1
        end or prizeZoom,
        setup = function(game)
            lessonRun(game, subject)
            game.course = Course.get(course or SHEET_COURSE)
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
local PIT_SHOWN = 4

local function dodgeShot(subject, fail)
    local sheet
    sheet = {
        kind = "run", warm = 1.5, rec = fail and 4.4 or 8,
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
                -- And thrown at twice as often, so the shortened drill is
                -- still mostly balls in the air.
                d.every, d.throwT = d.every / 2, 0.4
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

-- The cool S, told the sun's way (DESIGNDOC.md's "A weapon or tool highlight"),
-- with the one change its line forces: nothing in the book holds the S back
-- (it has no row in `Collection.gates`), so there is no hole in the library to
-- open, and the first shot is the entry walked to and shown as it is rather
-- than an UNLOCKED! the game never says.
--
-- The board is drawn the sun's way too, off the baked art (Sprites.COOLS), but
-- not in runs along a row: the S is six thin diagonals, so a row of it is mostly
-- single cells and the face's run-by-run strokes would spend six seconds on it.
-- It is traced instead, cell to touching cell, in the order a hand goes round
-- it, and each cell is put down as a dab -- pen down for a frame, up for a frame
-- -- rather than dragged to the next. Dragged, a step along an up-right or
-- down-left diagonal passes over the corner the two cells share, and the board
-- reads that corner as the cell beside them (Studio:cellAt floors both axes), so
-- a dragged S comes out with a stair in every other line. The cursor is not drawn
-- (`Input.hover`), so a dab is only ever seen as the cell appearing.
local function trace(art)
    local ink, left = {}, 0
    for y, row in ipairs(art) do
        for x = 1, #row do
            local tool = TOOL_OF[row:sub(x, x)]
            if tool then
                ink[y * 64 + x] = tool
                left = left + 1
            end
        end
    end
    local function free(x, y) return ink[y * 64 + x] end
    local function degree(x, y)
        local n = 0
        for dy = -1, 1 do
            for dx = -1, 1 do
                if (dx ~= 0 or dy ~= 0) and free(x + dx, y + dy) then n = n + 1 end
            end
        end
        return n
    end

    local cells = {}
    while left > 0 do
        -- Start each line at an end of it where there is one (the S's two
        -- points are), the topmost first, so it is drawn from the top down.
        local sx, sy, best
        for y = 1, #art do
            for x = 1, #art[y] do
                if free(x, y) then
                    local d = degree(x, y)
                    if not best or d < best then sx, sy, best = x, y, d end
                end
            end
        end
        local x, y, hx, hy = sx, sy, 0, 1
        while x do
            cells[#cells + 1] = { x, y, tool = free(x, y) }
            ink[y * 64 + x] = nil
            left = left - 1
            -- On to the touching cell nearest straight on, so the hand keeps
            -- going through the crossing rather than turning off at it.
            local nx, ny, score
            for dy = -1, 1 do
                for dx = -1, 1 do
                    if (dx ~= 0 or dy ~= 0) and free(x + dx, y + dy) then
                        local s = dx * hx + dy * hy
                        if not score or s > score then nx, ny, score = x + dx, y + dy, s end
                    end
                end
            end
            if nx then hx, hy = nx - x, ny - y end
            x, y = nx, ny
        end
    end
    return cells
end

local COOLS = trace(Sprites.COOLS)
local DAB = 2 * DT      -- one cell of the S: a frame down, a frame up

-- The S, drawn: where to dab `t` seconds in, whether the pen is down, the tool,
-- and whether the drawing is finished.
local function coolsAt(t)
    local lay = Studio.lay
    if not lay or t < 0 then return nil end
    local i = math.floor(t / DAB) + 1
    local cell = COOLS[i]
    if not cell then return nil, nil, nil, true end
    if t - (i - 1) * DAB >= DT then return nil, nil, cell.tool end
    return lay.bx + (cell[1] - 0.5) * lay.zoom, lay.board + (cell[2] - 0.5) * lay.zoom,
        cell.tool
end

-- One S sent across the shot rather than whenever the clock next sends one, so
-- every clip has it crossing on camera: `back` pixels behind the hero along
-- `angle` (radians, screen-wise: 0 is from the left, pi/2 from the top), heading
-- straight through where he stands, and the weapon's own clock held so it is the
-- only one up. Sent through `launch`, so its damage and bounces are the level's.
local function sendS(game, angle, back)
    local cools = game.loadout.live.cools
    cools.live = {}
    cools:launch(game)
    local s = cools.live[1]
    s.dx, s.dy = math.cos(angle), math.sin(angle)
    s.x = game.player.x - s.dx * back
    s.y = game.player.y - s.dy * back
    s.arrived = false
    cools.cool = math.huge
end

-- The lesson's horde, packed onto the line just ahead of the S, so what is on
-- camera with it is a pile for it to go through rather than a few strays. Real
-- arrivals off the spawner (`Spawner:dropAt`), as the sun's are -- the minute's
-- own kinds, health and champions, just stood where the S is about to be. Never
-- on top of the hero: an arrival dropped at his feet is a crowd stood on him, a
-- lump the line is lost in.
local LINE_EVERY = 0.05
local LINE_AHEAD = 110  -- how far in front of the S the pile reaches
local LINE_WIDE = 10    -- and how far either side of its line

local function feedLine(game, s)
    local cools = game.loadout.live.cools
    local S = cools and cools.live[1]
    if not S then return end
    s.fed = (s.fed or 0) - DT
    if s.fed > 0 then return end
    s.fed = LINE_EVERY
    local along = 12 + love.math.random() * LINE_AHEAD
    local off = (love.math.random() * 2 - 1) * LINE_WIDE
    local x = S.x + S.dx * along - S.dy * off
    local y = S.y + S.dy * along + S.dx * off
    if util.len(x - game.player.x, y - game.player.y) < 24 then return end
    game.spawner:dropAt(game, x, y)
end

-- How close the S is filmed: closer than a boss, since the S is the size of the
-- hero and what it is doing -- the pile coming apart, the numbers going up -- is
-- a few pixels a body.
local CLOSE = 3

-- Where to look in a cool S shot filmed close: on the S, a little toward the
-- hero, so the camera rides it through the pile.
local function coolsAim(game)
    local left, top = Camera.steady()
    local p = game.player
    local s = game.loadout.live.cools and game.loadout.live.cools.live[1]
    if not s then return p.x - left, p.y - top end
    return s.x * 0.85 + p.x * 0.15 - left, s.y * 0.85 + p.y * 0.15 - top
end

-- A run to film a weapon in: `runShot`, with the hero out of harm's way. The horde
-- still comes at him, but a hit is a knock of the whole page and a flash, and
-- the minute's crowd hits a hero who stands still for it all the time -- a
-- shaking frame is a frame the weapon cannot be followed across. The truce is the
-- one the eye's fall uses (Player:hurt), so nothing lands: no knock, no cry.
local function safeRun(game, subject)
    runShot(game, subject)
    game.player.truce = true
end

local function coolsReel()
    local shots = {}

    -- The entry on the weapons page, walked to and shown in full. Turned once
    -- the book has been laid out, and walked down a line at a time.
    shots[#shots + 1] = {
        kind = "library", warm = 0.1, rec = 3.4,
        hook = { "DRAW", "THE COOL S" }, hookY = 226,
        setup = function(game)
            Dev.boss = false
            Dev.unlocks = "none"
            game:toLibrary()
        end,
        direct = function(game, t, s)
            local at, want = Library:find("cools")
            s.turned = s.turned or 0
            if t > 0.25 and s.turned < at - 1 and t - (s.turnAt or 0) > 0.3 then
                s.turned, s.turnAt = s.turned + 1, t
                Library:step(1)
            end
            if s.turned == at - 1 and t > 0.9 and Library.index < want
                and t - (s.walked or 0) > 0.16 then
                s.walked = t
                Library:keypressed("down")
            end
        end,
    }

    -- Dealt, drawn and sent, in one take: the draft lands on the run, the S's
    -- card is circled, the board comes up blank and the S is drawn back onto it,
    -- and the run comes back with the first one floating in down the page,
    -- through the hero and the crowd round him -- where the camera punches in.
    local FIRST = math.pi / 2   -- from the top: down the long side of the frame
    shots[#shots + 1] = {
        kind = "run", warm = 2.5, rec = 11,
        setup = function(game) safeRun(game) end,
        direct = function(game, t, s)
            if t > 0.3 and not s.dealt then
                s.dealt = true
                game.player.pending = 1
                game.state = "levelup"
                Sfx.play("levelup_enter")
                game:holdRun()
                game.draft:open(game, { Upgrades.byId.star, Upgrades.byId.cools,
                    Upgrades.byId.rocket })
            end
            if game.state == "levelup" then
                if t > 1.4 and not s.picked then
                    s.picked = true
                    game.draft:keypressed("2")
                end
            elseif game.state == "studio" then
                if not s.board then
                    -- A blank board, so the S is drawn rather than edited.
                    s.board = t
                    local d = Design.by.cools
                    for y = 1, d.h do
                        for x = 1, d.w do d.grid[y][x] = Design.BLANK end
                    end
                    d:apply()
                end
                local x, y, tool, done = coolsAt(t - s.board - 0.6)
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
                if not s.back then
                    s.back = t
                    sendS(game, FIRST, 190)
                end
                feedLine(game, s)
                if t - s.back > 0.9 then s.say = "IT CUTS A LINE THROUGH YOU" end
            end
        end,
        zoom = function(game, t, s)
            return s.back and t - s.back > 0.9 and CLOSE or 1
        end,
        aim = coolsAim,
    }

    -- Then the S at the level it was dealt at, cutting the crowd on other pages
    -- and down other lines, close and with nothing written over it: already on
    -- its way when the camera rolls (`lead`), so the clip opens with it coming.
    -- The levels between are the run's to find -- only the last is shown, wide,
    -- the one S that never leaves the page.
    local function coolsShot(spec)
        return {
            kind = "run", warm = 3, rec = spec.rec,
            setup = function(game)
                safeRun(game, spec.subject)
                for _ = 1, spec.level do game.loadout:take("cools", game) end
                game.player:applyStats()
            end,
            direct = function(game, t, s)
                if spec.angle then
                    if t >= -spec.lead and not s.sent then
                        s.sent = true
                        sendS(game, spec.angle, spec.back)
                    end
                    feedLine(game, s)
                end
            end,
            zoom = spec.zoom,
            aim = spec.zoom and coolsAim or nil,
        }
    end

    shots[#shots + 1] = coolsShot({ level = 1, angle = -math.pi * 0.62, back = 205,
        lead = 1.5, rec = 2.4, zoom = CLOSE, subject = "science" })
    shots[#shots + 1] = coolsShot({ level = 1, angle = math.pi * 0.4, back = 205,
        lead = 1.5, rec = 2.4, zoom = CLOSE, subject = "art" })
    shots[#shots + 1] = coolsShot({ level = #Upgrades.byId.cools.levels,
        angle = -0.45, back = 0, lead = 2.5, rec = 2.4, subject = "music" })

    shots[#shots + 1] = { kind = "card", rec = 2.2, lines = { "SURVIVE", "SCHOOL" } }
    return shots
end

-- The storm, told the sun's way, unlock and all: it is held back by the book
-- (beating seven bosses), so the first shot is the sun's -- the shelf walked to
-- the hole, the demand, and the book opening it. Its board is drawn in rows off
-- the baked bolt (Sprites.LIGHTNING, `faceStrokes`): a thick bolt is runs of
-- three, so the row-by-row hand draws it without the cool S's stairs.
local BOLT = faceStrokes(Sprites.LIGHTNING)

-- Where the strike is staged, from the hero: a little up and to one side, so
-- the crowd the cloud comes for is its own, not the one round his feet.
local PILE_X, PILE_Y = 18, -34
local PILE_EVERY = 0.13
local PILE_WIDE = 16    -- a little over the base bolt's 12px circle

-- A crowd stood where the bolt will fall: the minute's own arrivals
-- (`Spawner:dropAt`) dropped round a point off the hero, and then walking in on
-- him through it. The storm parks over one enemy at random anywhere on the page,
-- so left alone the bolt that comes on camera hits a straggler; a crowd and a
-- cloud sent to it (`sendCloud`) is the weapon on what it is named for. Thin:
-- a dozen bodies, so each one the bolt takes is seen going.
local function pile(game, s, ox, oy, wide, every)
    s.fed = (s.fed or 0) - DT
    if s.fed > 0 then return end
    s.fed = every or PILE_EVERY
    local a = love.math.random() * math.pi * 2
    local r = math.sqrt(love.math.random()) * (wide or PILE_WIDE)
    game.spawner:dropAt(game, game.player.x + (ox or PILE_X) + math.cos(a) * r,
        game.player.y + (oy or PILE_Y) + math.sin(a) * r)
end

-- The thickest part of the crowd within a pile's width of a point: the enemy
-- with most others inside the bolt's circle, nearer the point breaking ties.
-- Not whoever is nearest the point -- that is the arrival dropped there last,
-- while the ones before it have walked off toward the hero.
local function densest(game, px, py, radius, reach)
    local near = game:nearestEnemies(px, py, reach or 45, 60)
    local best, most = nil, -math.huge
    for _, e in ipairs(near) do
        if not e.gone then
            local n = -util.len(e.x - px, e.y - py) / 15
            for _, o in ipairs(near) do
                if util.len(o.x - e.x, o.y - e.y) <= radius then n = n + 1 end
            end
            if n > most then best, most = e, n end
        end
    end
    return best
end

-- One cloud sent onto the crowd rather than over whoever the page picked:
-- through `launch`, so its damage, circle and bolts are the level's, then
-- marked on the thickest of the crowd round a point off the hero, and started
-- just off the edge of the page on the heading `angle`, so it is seen rolling
-- in. It leaves on the same heading (Storm:step), so a level heading keeps the
-- whole visit short: half a page in, half a page out. The weapon's own clock
-- is held, so the only clouds are these.
local function sendCloud(game, ox, oy, angle)
    local storm = game.loadout.live.storm
    storm.cool = math.huge
    -- Room made for it: a cloud of ours on its way out has done what it came
    -- for, and one the clock sent before it was held is still off the page.
    for i = #storm.live, 1, -1 do
        local c = storm.live[i]
        if not c.ours or c.state == "out" then table.remove(storm.live, i) end
    end
    if not storm:launch(game) then return end
    local c = storm.live[#storm.live]
    c.ours = true
    c.target = densest(game, game.player.x + ox, game.player.y + oy, c.radius)
        or c.target
    -- And should the hero's own weapon kill its mark before the bolt, it picks
    -- again here rather than at random across the page (Storm:remark), which
    -- sends the cloud off over bare paper with the camera after it.
    if not storm.held then
        storm.held = true
        local remark = storm.remark
        storm.remark = function(self, cloud, g)
            local e = cloud.ours and densest(g, cloud.target.x, cloud.target.y, cloud.radius)
            if e then cloud.target = e return true end
            return remark(self, cloud, g)
        end
    end
    -- Back along the heading from its station until it is past the page's
    -- edge, a cloud's width clear.
    local tx, ty = c.target.x, c.target.y - 25
    c.dx, c.dy = math.cos(angle), math.sin(angle)
    local left, top, w, h = Camera.bounds()
    local back = 0
    while back < 400 do
        local x, y = tx - c.dx * back, ty - c.dy * back
        if x < left - Sprites.cloud.w or x > left + w + Sprites.cloud.w
            or y < top - Sprites.cloud.h or y > top + h + Sprites.cloud.h then break end
        back = back + 2
    end
    c.x, c.y = tx - c.dx * back, ty - c.dy * back
end

-- The newest of our clouds, and whether it has struck yet. The crowd is fed
-- only until it has: one the bolt has just been through should be seen
-- thinning, not topped up.
local function ourCloud(game)
    local storm = game.loadout.live.storm
    local c = storm and storm.live[#storm.live]
    if c and c.ours then return c, c.state == "strike" or c.state == "out" end
end

-- Where to look in a storm shot: on the cloud, in and out -- the weapon is the
-- subject and the hero is only somewhere in the crowd. A little below it, so
-- the bolt and what it lands on are in the frame with it. The lens stops at
-- the edge of the page, so a cloud arriving is seen coming over the edge and
-- one leaving is seen going off it. Held where it last was once the cloud has
-- gone, rather than swinging back to the hero.
local stormLast

local function stormAim(game)
    local left, top = Camera.steady()
    local c = ourCloud(game)
    if c then stormLast = { c.x, c.y + 22 }
    elseif not stormLast then
        stormLast = { game.player.x + PILE_X, game.player.y + PILE_Y }
    end
    return stormLast[1] - left, stormLast[2] - top
end

local function stormReel()
    local shots = {}

    -- The hole on the weapons page and what it asks for, then the book opening
    -- it: the same entry, written out in full.
    shots[#shots + 1] = {
        kind = "library", warm = 0.1, rec = 4.6,
        hook = { "UNLOCK", "THE STORM" }, hookY = 226,
        setup = function(game)
            Dev.boss = false
            Dev.unlocks = "none"
            game:toLibrary()
        end,
        direct = function(game, t, s)
            local at, want = Library:find("storm")
            s.turned = s.turned or 0
            if t > 0.25 and s.turned < at - 1 and t - (s.turnAt or 0) > 0.3 then
                s.turned, s.turnAt = s.turned + 1, t
                Library:step(1)
            end
            if s.turned == at - 1 and t > 0.9 and Library.index < want
                and t - (s.walked or 0) > 0.16 then
                s.walked = t
                Library:keypressed("down")
            end
            if t > 2.8 and not s.opened then
                s.opened = true
                Dev.unlocks = "all"
                Sfx.play("accept")
            end
            if s.opened then s.hook, s.say = nil, "UNLOCKED!" end
        end,
    }

    -- Dealt, drawn and sent, in one take: the draft lands on the run, the
    -- storm's card is circled, the board comes up blank and the bolt is drawn
    -- back onto it, and the run comes back with a cloud rolling in over the
    -- edge of the page -- the camera punching in on it -- onto the crowd,
    -- striking, and rolling off the other side.
    shots[#shots + 1] = {
        kind = "run", warm = 2.5, rec = 10,
        setup = function(game)
            stormLast = nil
            safeRun(game)
        end,
        direct = function(game, t, s)
            if t > 0.3 and not s.dealt then
                s.dealt = true
                game.player.pending = 1
                game.state = "levelup"
                Sfx.play("levelup_enter")
                game:holdRun()
                game.draft:open(game, { Upgrades.byId.star, Upgrades.byId.storm,
                    Upgrades.byId.rocket })
            end
            if game.state == "levelup" then
                if t > 1.4 and not s.picked then
                    s.picked = true
                    game.draft:keypressed("2")
                end
            elseif game.state == "studio" then
                if not s.board then
                    -- A blank board, so the bolt is drawn rather than edited.
                    s.board = t
                    local d = Design.by.lightning
                    for y = 1, d.h do
                        for x = 1, d.w do d.grid[y][x] = Design.BLANK end
                    end
                    d:apply()
                end
                local x, y, tool, done = faceAt(t - s.board - 0.6, BOLT)
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
                local storm = game.loadout.live.storm
                if storm and not s.back then
                    s.back = t
                    storm.cool = math.huge
                end
                if s.back then
                    local k = t - s.back
                    local _, struck = ourCloud(game)
                    if not s.sent then
                        -- The crowd gathers for a beat before the cloud is
                        -- sent, so it has something to come for.
                        pile(game, s)
                        if k > 0.6 then
                            s.sent = true
                            sendCloud(game, PILE_X, PILE_Y, 0)
                        end
                    elseif not struck then
                        pile(game, s)
                    end
                    if k > 0.7 then s.say = "IT STRIKES THE CROWD" end
                end
            end
        end,
        zoom = function(game, t, s)
            return s.sent and ZOOM or 1
        end,
        aim = stormAim,
    }

    -- Then the storm at the level it was dealt at, on other pages, followed in
    -- over one edge and off the other with nothing written over it: the crowd
    -- gathered unseen, the cloud already coming when the camera rolls.
    local function stormShot(spec)
        return {
            kind = "run", warm = 2, rec = spec.rec,
            setup = function(game)
                stormLast = nil
                safeRun(game, spec.subject)
                if spec.minute then game.time = spec.minute * 60 end
                for _ = 1, spec.level do game.loadout:take("storm", game) end
                game.player:applyStats()
                game.loadout.live.storm.cool = math.huge
            end,
            direct = function(game, t, s)
                local _, struck = ourCloud(game)
                if struck then s.struck = true end
                if t > -1.6 and not s.struck then
                    pile(game, s, spec.ox, spec.oy, spec.wide, spec.every)
                end
                if t >= -(spec.lead or 0.2) and not s.sent then
                    s.sent = true
                    sendCloud(game, spec.ox, spec.oy, spec.angle)
                end
            end,
            zoom = ZOOM,
            aim = stormAim,
        }
    end

    shots[#shots + 1] = stormShot({ level = 1, ox = PILE_X, oy = PILE_Y, angle = 0,
        rec = 3.4, subject = "language" })
    shots[#shots + 1] = stormShot({ level = 1, ox = -PILE_X, oy = PILE_Y, angle = math.pi,
        rec = 3.4, subject = "art" })

    -- The end: the last level on a whole crowd, followed in and out. A wide
    -- crowd and a later minute, since the chain runs along the *living* (src/
    -- storm.lua) -- at minute four the bolt kills its circle outright and the
    -- zap has nobody to be passed on by -- and minute eight is where a run that
    -- has finished the line is anyway. It stays for its three bolts, each one
    -- going through the crowd from wherever it lands.
    shots[#shots + 1] = stormShot({ level = #Upgrades.byId.storm.levels,
        minute = 6, ox = 0, oy = -40, wide = 45, every = 0.08, angle = 0,
        rec = 5.6, subject = "music" })

    shots[#shots + 1] = { kind = "card", rec = 2.2, lines = { "SURVIVE", "SCHOOL" } }
    return shots
end

-- A fusion, told as the road to it: the two tools it is made of, each at its
-- first level on the crowd and then each finished; the draft dealing the
-- catalyst's last level and, the moment it is circled, the fusion's card; and
-- the fused tool on the page. The levels are the subject here, so unlike the
-- sun's reel each clip says which one it is (`tag`), and the tool's name (`say`).
--
-- The strip is built rather than drafted (`fusionStrip`, through
-- `Loadout:restore`): only the lines the shot is about, at the levels it names,
-- and no hero's weapon -- anything that dies on camera died to the tool in the
-- hand. The page is a lesson's run with the class called in round the hero
-- (`lessonRun`), played with the mouse, as the teasers are, and filmed at the
-- page's own size: the hero kites the class round the page (`kite`) rather
-- than standing in it, and a close shot would lose the pack he is leading.
local function fusionStrip(game, lines)
    local set = {}
    for _, line in ipairs(lines) do
        local up = Upgrades.byId[line[1]]
        local level = line[2] == "max" and Upgrades.levelsIn(up) or line[2]
        set[#set + 1] = { id = up.id, level = level }
    end
    game.loadout:restore(set, game.vw, game.vh)
    game.player:applyStats()
end

-- The tool in the hand, by its line.
local function hold(game, id)
    for i, slot in ipairs(game.loadout.equipped) do
        if slot.up.id == id then game.tool = i end
    end
end

-- Kiting: the hero runs a wide ring round a point on the page, and the class,
-- called in from beyond that point (`kiteCrowd`), clumps in the middle of it
-- chasing him -- so the pack is always to one side of him and the tool is
-- worked on its edge, never on a hero stood in the thick of it. Anyone who
-- gets close is stepped away from, which bends the ring out round them.
local KITE_R = 62       -- the ring's radius
local KITE_PACE = 0.62  -- of his speed: a little under, so the pack keeps up
local KITE_SHY = 24     -- how close a body gets before he steps out of its way

local function kite(game, t, s)
    local p = game.player
    if not s.cx then s.cx, s.cy = p.x + KITE_R, p.y end
    local dx, dy, d = util.normalize(p.x - s.cx, p.y - s.cy)
    if d == 0 then dx, dy = -1, 0 end
    local mx = -dy + dx * util.clamp((KITE_R - d) / 20, -1, 1)
    local my = dx + dy * util.clamp((KITE_R - d) / 20, -1, 1)
    for _, e in ipairs(game.enemies) do
        local ex, ey, ed = util.normalize(p.x - e.x, p.y - e.y)
        if ed > 0 and ed < KITE_SHY + e.radius then
            local w = (KITE_SHY + e.radius - ed) / KITE_SHY * 1.6
            mx, my = mx + ex * w, my + ey * w
        end
    end
    local nx, ny, len = util.normalize(mx, my)
    if len == 0 then return 0, 0 end
    return nx * KITE_PACE, ny * KITE_PACE
end

-- The class, a kind at a time, dropped beyond the ring's middle on the far
-- side from the hero, off what the shot shows, so it walks in and joins the
-- pack rather than arriving across his path.
local function kiteCrowd(game, s, every, most)
    s.fedT = (s.fedT or 0) - DT
    if s.fedT > 0 or #game.enemies >= most or not s.cx then return end
    s.fedT = every
    s.next = (s.next or love.math.random(#CLASS)) % #CLASS + 1
    local p = game.player
    local dx, dy, d = util.normalize(s.cx - p.x, s.cy - p.y)
    if d == 0 then dx, dy = 1, 0 end
    local back = 150 + love.math.random() * 40
    local off = (love.math.random() * 2 - 1) * 70
    game:spawnEnemy(CLASS[s.next], s.cx + dx * back - dy * off, s.cy + dy * back + dx * off)
end

-- The SNAG's two gestures in the one hand: three taps a quarter of a second
-- apart, a staple in each of the three nearest, and then the rub dragged back
-- across them, the last stapled first, to rip the staples back out.
local SNAG_CYCLE = 1.9

local function snagHunt(game, s, t, near)
    local p = game.player
    local n = math.floor(t / SNAG_CYCLE)
    local k = t % SNAG_CYCLE
    if s.snagN ~= n then
        s.snagN = n
        local list = {}
        for _, e in ipairs(game.enemies) do
            local d = util.len(e.x - p.x, e.y - p.y)
            if not e.def.boss and d < near then list[#list + 1] = { e = e, d = d } end
        end
        table.sort(list, function(a, b) return a.d < b.d end)
        s.marks = {}
        for i = 1, math.min(3, #list) do s.marks[i] = list[i].e end
    end
    local m = s.marks
    if #m == 0 then
        point(p.x + 26, p.y + 18, false)
        return
    end
    if k < 0.75 then
        local i = math.floor(k / 0.25) + 1
        local e = m[i] or m[#m]
        point(e.x, e.y, m[i] ~= nil and k % 0.25 < 0.08)
        return
    end
    -- Back across them: a path through where they stand, last to first, run
    -- past either end so a lone one is still rubbed over.
    local pts = {}
    for i = #m, 1, -1 do pts[#pts + 1] = { m[i].x, m[i].y } end
    local a, b = pts[1], pts[#pts]
    local dx, dy, d = util.normalize(b[1] - a[1], b[2] - a[2])
    if d == 0 then dx, dy = 1, 0 end
    table.insert(pts, 1, { a[1] - dx * 10, a[2] - dy * 10 })
    pts[#pts + 1] = { b[1] + dx * 10, b[2] + dy * 10 }
    if k < 0.9 then
        point(pts[1][1], pts[1][2], false)
        return
    end
    if k < 1.5 then
        local f = (k - 0.9) / 0.6 * (#pts - 1)
        local i = math.min(#pts - 1, math.floor(f) + 1)
        local g = f - (i - 1)
        local x = pts[i][1] + (pts[i + 1][1] - pts[i][1]) * g
        local y = pts[i][2] + (pts[i + 1][2] - pts[i][2]) * g
        local zig = math.sin(k * 40) * 5
        point(x - dy * zig, y + dx * zig, true)
        return
    end
    point(pts[#pts][1] + 8, pts[#pts][2] - 6, false)
end

-- The pack: the middle of everything chasing the hero within `reach`, and how
-- far out from that middle it stands (a little past the average).
local function pack(game, reach)
    local p, n, sx, sy = game.player, 0, 0, 0
    for _, e in ipairs(game.enemies) do
        if not e.def.boss and e.hp > 0 and util.len(e.x - p.x, e.y - p.y) < (reach or 110) then
            n, sx, sy = n + 1, sx + e.x, sy + e.y
        end
    end
    if n == 0 then return end
    local cx, cy = sx / n, sy / n
    local spread = 0
    for _, e in ipairs(game.enemies) do
        if not e.def.boss and e.hp > 0 and util.len(e.x - p.x, e.y - p.y) < (reach or 110) then
            spread = spread + util.len(e.x - cx, e.y - cy)
        end
    end
    return cx, cy, spread / n
end

-- Each fusion's moment, a hand of its own on the pack rather than on whoever
-- is nearest -- what the fused tool is *for*, shown on the crowd it is for.
-- All take (game, s, t, near) as `hunt` does, and lift between gestures.

-- A compass ring planted on the middle of the pack and opened out round it:
-- the PUNCH lifts the whole pack out of the page, the CORRAL fences it in, the
-- SPINDLE drags it round and pins it. Kept off the hero, who is ahead of it.
local function ringPack(period)
    return function(game, s, t)
        local k = t % period
        local n = math.floor(t / period)
        if s.ringN ~= n then
            s.ringN = n
            local cx, cy, spread = pack(game)
            local sw = game.loadout:tool(game.tool).sweep
            if cx then
                local p = game.player
                local away = util.len(p.x - cx, p.y - cy)
                -- Never round the hero as well: a ring that took him in would
                -- be the PUNCH lifting the page out from under him. Too close
                -- for the smallest ring, and this swing is sat out.
                local r = math.min(spread + 10, sw.maxR, away - 12)
                s.ring = r >= sw.minR and { cx, cy, r } or nil
            else
                s.ring = nil
            end
        end
        local r = s.ring
        if not r then
            point(game.player.x + 26, game.player.y + 18, false)
            return
        end
        if k < 0.1 then point(r[1], r[2], false) return end
        if k < 0.6 then
            local f = math.min(1, (k - 0.1) / 0.35)
            point(r[1] + r[3] * f, r[2], true)
            return
        end
        point(r[1] + r[3], r[2], false)
    end
end

-- Pins tapped down either side of the pack, square across the way it is
-- chasing, so the TEAR LINE threaded between them runs edge to edge through it.
local function pinPair(game, s, t)
    local k = t % 1.6
    local n = math.floor(t / 1.6)
    if s.pairN ~= n then
        s.pairN = n
        local cx, cy = pack(game)
        s.pair = nil
        if cx then
            local p = game.player
            local dx, dy, d = util.normalize(cx - p.x, cy - p.y)
            if d == 0 then dx, dy = 1, 0 end
            s.pair = { { cx - dy * 38, cy + dx * 38 }, { cx + dy * 38, cy - dx * 38 } }
        end
    end
    if not s.pair then point(game.player.x + 26, game.player.y + 18, false) return end
    local i = k < 0.3 and 1 or 2
    point(s.pair[i][1], s.pair[i][2], (k < 0.3 and k < 0.08) or (k >= 0.3 and k < 0.38))
end

-- Three pins round the pack, a triangle the DOT TO DOT joins in pencil and
-- cuts everything inside.
local function pinShape(game, s, t)
    local k = t % 1.8
    local n = math.floor(t / 1.8)
    if s.shapeN ~= n then
        s.shapeN = n
        local cx, cy, spread = pack(game)
        s.shape = nil
        if cx then
            local r = util.clamp(spread + 12, 24, 48)
            local a = n * 0.7
            s.shape = {}
            for i = 0, 2 do
                local b = a + i * math.pi * 2 / 3
                s.shape[#s.shape + 1] = { cx + math.cos(b) * r, cy + math.sin(b) * r }
            end
        end
    end
    if not s.shape then point(game.player.x + 26, game.player.y + 18, false) return end
    local i = math.min(3, math.floor(k / 0.28) + 1)
    point(s.shape[i][1], s.shape[i][2], k < 0.84 and k % 0.28 < 0.08)
end

-- A pin on the thickest knot of the pack, every so often: the CRATER's blast
-- is a shove out of the middle, so it wants a middle.
local function pinDense(game, s, t)
    local k = t % 0.8
    local n = math.floor(t / 0.8)
    if s.denseN ~= n then
        s.denseN = n
        local cx, cy = pack(game)
        local e = cx and densest(game, cx, cy, 25, 60)
        s.dense = e and { e.x, e.y } or nil
    end
    if not s.dense then point(game.player.x + 26, game.player.y + 18, false) return end
    point(s.dense[1], s.dense[2], k < 0.08)
end

-- One tool on the crowd: `lines` the strip ({ id, level or "max" }), `hold` the
-- one in the hand. Already at work when the camera rolls.
local function toolShot(spec)
    return {
        kind = "run", warm = spec.warm or 4, rec = spec.rec or 2.8, vary = true,
        hook = spec.hook, tag = spec.tag, say = spec.say,
        setup = function(game)
            lessonRun(game, spec.subject)
            fusionStrip(game, spec.lines)
            hold(game, spec.hold)
        end,
        move = kite,
        direct = function(game, t, s)
            game.ink = game.loadout.stats.inkMax
            kiteCrowd(game, s, spec.every or 0.12, spec.most or 24)
            if t > 2.4 then s.hook = nil end
            if t > -1.6 then (spec.hunt or hunt)(game, s, t + 1.6, spec.near or 60) end
        end,
    }
end

-- The draft and what it makes, in one take: both tools finished and the
-- catalyst one level short, the draft lands with the catalyst's last level on
-- it, that card is circled, the next draft has the fusion on it -- dealt off the
-- run's own `roll`, held to that deal for the shot -- and that is circled too,
-- and the run comes back holding the fused tool, still kiting.
local function fuseShot(spec)
    local up = function(id) return Upgrades.byId[id] end
    return {
        kind = "run", warm = 4, rec = 14, vary = true,
        setup = function(game)
            lessonRun(game, spec.subject)
            local cat = up(spec.catalyst)
            fusionStrip(game, { { spec.parents[1], "max" }, { spec.parents[2], "max" },
                { cat.id, Upgrades.levelsIn(cat) - 1 } })
            hold(game, spec.parents[1])
            game.loadout.roll = function()
                return { up(spec.decoys[3]), up(spec.fusion), up(spec.decoys[4]) }
            end
        end,
        move = kite,
        direct = function(game, t, s)
            game.ink = game.loadout.stats.inkMax
            kiteCrowd(game, s, spec.every or 0.1, spec.most or 30)
            if t > 0.5 and not s.dealt then
                s.dealt = true
                Input.pointerDown = false
                game.player.pending = 2
                game.state = "levelup"
                Sfx.play("levelup_enter")
                game:holdRun()
                game.draft:open(game, { up(spec.decoys[1]), up(spec.catalyst), up(spec.decoys[2]) })
            end
            if game.state == "levelup" then
                Input.pointerDown = false
                if game.draft.offer ~= s.offer then s.offer, s.openT = game.draft.offer, t end
                if t - s.openT > 1.3 and s.picked ~= s.offer then
                    s.picked = s.offer
                    game.draft:keypressed("2")
                end
            elseif s.dealt then
                if not s.back then
                    s.back = t
                    s.rec = t + (spec.after or 3.6)
                end
                if t - s.back > 0.5 then
                    s.tag, s.say = "FUSED!", up(spec.fusion).name
                end
                (spec.hunt or hunt)(game, s, t - s.back + 0.2, spec.near or 60)
            else
                -- The hand rests until the draft: a finished pair of scissors
                -- trims half the page away, and the fused tool should come back
                -- to a whole page and a pack to use it on.
                point(game.player.x + 26, game.player.y + 18, false)
            end
        end,
    }
end

-- Every fusion reel is the same seven shots; a row names the parents, the
-- catalyst, the fusion, the four decoy cards and the pages.
local function fusionReel(spec)
    return function()
        local a, b = spec.parents[1], spec.parents[2]
        local name = function(id) return Upgrades.byId[id].name end
        local both = function(la, lb) return { { a, la }, { b, lb } } end
        local shots = {}
        shots[#shots + 1] = toolShot({ subject = spec.pages[1], lines = both(1, 1), hold = a,
            hook = { name(a), "+ " .. name(b), "= ?" }, tag = "LEVEL 1", say = name(a),
            hunt = spec.hunts and spec.hunts[a] })
        shots[#shots + 1] = toolShot({ subject = spec.pages[2], lines = both(1, 1), hold = b,
            tag = "LEVEL 1", say = name(b), hunt = spec.hunts and spec.hunts[b] })
        shots[#shots + 1] = toolShot({ subject = spec.pages[3], lines = both("max", "max"), hold = a,
            tag = "MAX LEVEL", say = name(a), every = 0.08, most = 32,
            hunt = spec.hunts and spec.hunts[a] })
        shots[#shots + 1] = toolShot({ subject = spec.pages[4], lines = both("max", "max"), hold = b,
            tag = "MAX LEVEL", say = name(b), every = 0.08, most = 32,
            hunt = spec.hunts and spec.hunts[b] })
        shots[#shots + 1] = fuseShot({ subject = spec.pages[5], parents = spec.parents,
            catalyst = spec.catalyst, fusion = spec.fusion, decoys = spec.decoys,
            every = 0.08, most = 32,
            hunt = spec.hunts and spec.hunts[spec.fusion] })
        shots[#shots + 1] = toolShot({ subject = spec.pages[6], warm = 4, rec = 4,
            say = Upgrades.byId[spec.fusion].levels[1].text,
            lines = { { a, "max" }, { b, "max" }, { spec.catalyst, "max" }, { spec.fusion, 1 } },
            hold = spec.fusion, every = 0.08, most = 36, near = 70,
            hunt = spec.hunts and spec.hunts[spec.fusion] })
        shots[#shots + 1] = { kind = "card", rec = 2.2, lines = { "SURVIVE", "SCHOOL" } }
        return shots
    end
end

-- One pickup's highlight: what it is, found and taken, and what it does, told
-- in two takes -- one lying on the page and walked to, and one won off a
-- worksheet -- since those are the two ways the page hands it over. Each take
-- is the same shape: the hero walks in, the page slows as he reaches it and the
-- lens punches in on it turning (`GRAB_SLOW`, `GRAB_LOOK`), and the moment it is
-- taken the reel cuts to whatever it changed -- the bar it filled, the crowd it
-- stopped, the numbers it raised -- in a row of `beats`, each a zoom, a place to
-- look and a line, cut between rather than panned.
--
-- The page is a lesson's run with nothing on it but what the take puts there
-- (`lessonRun`), and no pickup but the one being filmed: the fixed layer is
-- marked taken and the scatter clock never comes round (`bare`), so the turning
-- thing on camera is the one the reel is about.
--
-- Built inside a function of its own: the file's main chunk is at the 200
-- locals Lua allows one function, and these are only read through
-- `PICKUP_REELS`.
local PICKUP_REELS = (function()
local GRAB_NEAR = 22    -- how far off it, past his own radius, the page slows
local GRAB_SLOW = 0.3   -- and to what share of its speed
local GRAB_LOOK = 3     -- the lens on the pickup while it does
local HUD_LOOK = 3      -- and on a readout, after

-- A first beat marked `preview` is cut to a moment before the touch rather than
-- on it, so the readout is seen while it still says the old figure and the
-- jump happens on camera: this many pixels short of it, on the page's slowed
-- walk and on a sheet's full-speed one.
local PREVIEW_PAGE, PREVIEW_SHEET = 4, 12

local function bare(game)
    game.pickupTaken = setmetatable({}, { __index = function() return true end })
    game.pickupTimer = math.huge
end

-- Where a readout is on the canvas, read off src/hud.lua's layout: the health
-- bar and its figure top left, the ink bar and its figure top right with the
-- run's coins under it, the level along the foot. Measured as Hud.draw measures
-- the bars (its `barWidth`), so a close shot of one sits on it.
local function hudAt(game, which)
    local ins, vw, vh = game.inset, game.vw, game.vh
    local top = ins.t + 4
    local left = ins.l + 4 + Hud.CORNER_SIZE + 6
    local right = vw - ins.r - 4
    local centre = ins.l + (vw - ins.l - ins.r) / 2
    local clockW = Font.width("00:00")
    local clockL = math.floor(centre - clockW / 2)
    local figure = Font.width("000")
    local keep = 8 + figure
    local barW = util.clamp(math.min(clockL - left - keep, right - (clockL + clockW) - keep), 24, 60)
    if which == "hp" then return left + (barW + 4 + figure) / 2, top + 6 end
    if which == "ink" or which == "purse" then return right - (barW + 4 + figure) / 2, top + 10 end
    return centre, vh - ins.b - 4
end

-- A beat's `aim`: a readout by name, the hero, the pickup, or a function of
-- the game answering canvas pixels.
local function aimAt(game, s, at)
    if type(at) == "function" then return at(game, s) end
    if at == "hero" or at == "item" then
        local left, top = Camera.steady()
        local k = at == "item" and s.item or game.player
        return k.x - left, k.y - top
    end
    return hudAt(game, at)
end

-- The beat `t` seconds after the take, and how far into it.
local function beatAt(beats, t)
    for i, b in ipairs(beats) do
        if t < b.len then return b, t, i end
        t = t - b.len
    end
end

local function beatsLong(beats)
    local n = 0
    for _, b in ipairs(beats) do n = n + b.len end
    return n
end

-- One frame of the beats: which is on, a cut on the frame it changes, its line,
-- and its hand. `s.takenT` is when the pickup was taken.
local function beatStep(game, s, t, beats)
    if not s.takenT then return end
    local b, bt, i = beatAt(beats, t - s.takenT)
    if i ~= s.beatN then
        s.beatN, s.cut = i, true
    end
    s.beat = b
    if not b then return end
    s.say, s.tag = b.say, b.tag
    if b.hand then b.hand(game, s, bt) end
    if b.direct then b.direct(game, s, bt) end
end

-- Whether the first beat is being shown early (`preview`), and if so it. Marked
-- as already on, so the take itself is not a second cut to the same place.
local function previewing(game, s, item, beats, near)
    local b = beats[1]
    if s.takenT or not (b and b.preview) or not item or item.dead then return end
    local p = game.player
    if util.len(p.x - item.x, p.y - item.y) >= p.radius + 4 + near then return end
    if not s.previewed then s.previewed, s.cut, s.beatN = true, true, 1 end
    return b
end

-- Hands for a beat. The lesson's tool on the nearest, as a player fights; and
-- the pen never lifted, swept back and forth across the crowd round the hero in
-- one long zigzag -- what free ink is for.
local function fighting(game, s, t) hunt(game, s, t + 0.6, 50) end

-- And the hero walked slowly round, so the crowd strings out behind him
-- rather than piling on, and the line has bodies to go through.
local function stroll(game, t)
    return math.cos(t * 0.9) * 0.45, math.sin(t * 0.9) * 0.45
end

-- Lifted for a frame now and then all the same: whether a press may draw is
-- asked as it lands (Game:updateDrawing), so a pen still held from before the
-- drop, pressed on an empty well, would draw nothing however long it stayed down.
local FRENZY_LIFT = 1.6

local function frenzy(game, s, t)
    local p = game.player
    local x = p.x + math.sin(t * 2.3) * 34 + math.sin(t * 19) * 6
    local y = p.y + math.sin(t * 1.4 + 0.6) * 44 + math.cos(t * 23) * 5
    point(x, y, t % FRENZY_LIFT > 1.5 * DT)
end

-- What is lying nearest the hero: a pickup of a kind, or a gem.
local function nearestOf(game, kind)
    local p, best, bd = game.player
    local list = kind == "gem" and game.gems or game.pickups
    for _, k in ipairs(list) do
        if not k.dead and (kind == "gem" or k.kind == kind) then
            local d = util.len(k.x - p.x, k.y - p.y)
            if not bd or d < bd then best, bd = k, d end
        end
    end
    return best
end

-- A beat's `move`: walk over to whatever of a kind is lying nearest.
local function gather(kind)
    return function(game)
        local k = nearestOf(game, kind)
        if k then return walkTo(game, k.x, k.y) end
        return 0, 0
    end
end

-- A level that lands without stopping the run for the draft: the bar wraps and
-- the number goes up, as it would, and nothing is offered. The alarm's gems are
-- the subject, not the cards.
local function quietLevels(game)
    local p = game.player
    p.addXp, p.levelUp = nil, nil
    local real = p.levelUp
    p.levelUp = function(self)
        real(self)
        self.pending = self.pending - 1
    end
end

-- And one that does stop it: the diamond's level is the draft, so the draft
-- opens -- the diamond's level and no other, the gems still banking nothing --
-- dealt cards with no board behind them (a board would take the take
-- off the page), and the director circles the middle one.
local DIAMOND_DEAL = { "magnet", "bandaid", "inkwell" }

local function realLevels(game)
    -- The level only: a gem banked on the way over would open the draft first.
    game.player.levelUp = nil
    game.loadout.roll = function()
        local deal = {}
        for i, id in ipairs(DIAMOND_DEAL) do deal[i] = Upgrades.byId[id] end
        return deal
    end
end

local function pickCard(game, s, t)
    if game.state == "levelup" and t > 1.3 and not s.carded then
        s.carded = true
        game.draft:keypressed("2")
    end
end

-- The take on the page: `kind` lying `at` off the hero, walked to at `pace`,
-- and `beats` after it. An `intro` is a beat before the walk (the bar it is
-- about to fill, close), and the hook is over it; with none, the hook is over
-- the first of the walk (`HOOK_FOR`). `say` is said on the rest of the walk;
-- `feed` is the crowd ({ every, most, zoom }, or false) and `hold` keeps it
-- coming after the take.
local HOOK_FOR = 2.2

local function grabShot(spec)
    local sh
    local intro = spec.intro and spec.intro.len or 0
    local hookFor = spec.intro and intro or HOOK_FOR
    sh = {
        kind = "run", warm = spec.warm or 2, rec = 30, keepHp = spec.keepHp,
        hook = spec.hook, hookY = spec.hookY,
        speed = function(game, t, s)
            return s.slow and not s.takenT and GRAB_SLOW or 1
        end,
        setup = function(game)
            lessonRun(game, spec.subject)
            bare(game)
            if spec.setup then spec.setup(game, sh) end
            local p = game.player
            sh.item = Pickup.new(spec.kind, p.x + spec.at[1], p.y + spec.at[2])
            game.pickups[#game.pickups + 1] = sh.item
        end,
        move = function(game, t, s)
            if not s.takenT then
                if t < intro + (spec.wait or 0.3) then return 0, 0 end
                local mx, my = walkTo(game, s.item.x, s.item.y)
                local pace = spec.pace or 0.75
                return mx * pace, my * pace
            end
            local b = s.beat
            if b and b.move then return b.move(game, t, s) end
            return 0, 0
        end,
        direct = function(game, t, s)
            local p = game.player
            if not s.takenT then
                if s.item.dead then
                    s.takenT = t
                    s.rec = t + beatsLong(spec.beats)
                    s.say, s.hook = nil, nil
                else
                    s.slow = util.len(p.x - s.item.x, p.y - s.item.y) < GRAB_NEAR + p.radius
                    if t > hookFor or s.slow then s.hook = nil end
                    if t > intro then
                        s.say = not s.hook and not s.slow and spec.say or nil
                    end
                end
            end
            local feed = spec.feed
            if feed ~= false and (not s.takenT or spec.hold) then
                feed = feed or {}
                crowd(game, s, feed[1] or 0.14, feed[2] or 20, false, feed[3] or spec.zoom)
            end
            if spec.each then spec.each(game, s, t) end
            if s.takenT then
                beatStep(game, s, t, spec.beats)
                if not (s.beat and s.beat.hand) then fighting(game, s, t) end
            elseif t > -0.6 and not s.slow then
                fighting(game, s, t)
            elseif s.slow then
                -- The hand lifted out of the frame for the grab.
                point(p.x + 40, p.y + 60, false)
            end
        end,
        zoom = function(game, t, s)
            if not s.takenT then
                if spec.intro and t < intro then return spec.intro.zoom end
                local pv = previewing(game, s, s.item, spec.beats, PREVIEW_PAGE)
                if pv then return pv.zoom end
                if s.slow then return GRAB_LOOK end
                return spec.zoom or 1
            end
            return s.beat and s.beat.zoom or 1
        end,
        aim = function(game)
            local s = sh
            if not s.takenT then
                if s.introOn then return aimAt(game, s, spec.intro.aim) end
                local pv = previewing(game, s, s.item, spec.beats, PREVIEW_PAGE)
                if pv then return aimAt(game, s, pv.aim) end
                if s.slow then return aimAt(game, s, "item") end
                return aimAt(game, s, "hero")
            end
            if s.beat and s.beat.aim then return aimAt(game, s, s.beat.aim) end
        end,
    }
    if spec.intro then
        local direct = sh.direct
        sh.direct = function(game, t, s)
            s.introOn = t < intro
            if s.introOn then s.say = spec.intro.say end
            direct(game, t, s)
        end
    end
    return sh
end

-- The take off a worksheet: one of the lesson reels' sheet shots, played as it
-- is, with the line that says this is the other way to get one over its start,
-- and the same beats from the moment the first of its prize is taken. A prize
-- paid in several (the till's coins) goes on being walked over under them.
local SHEET_SAY = 2.4

local function sheetFx(build, fx)
    return function(key)
        local sh = build(key)
        local setup, direct, zoom, aim, move = sh.setup, sh.direct, sh.zoom, sh.aim, sh.move
        sh.keepHp = fx.keepHp
        sh.setup = function(game)
            setup(game)
            bare(game)
            if fx.setup then fx.setup(game, sh) end
        end
        sh.direct = function(game, t, s)
            direct(game, t, s)
            if fx.feed and not s.takenT then
                s.more = s.more or {}
                crowd(game, s.more, fx.feed[1], fx.feed[2], fx.feed[4], fx.feed[3])
            end
            s.say = t < SHEET_SAY and (fx.say or "OR WIN ONE ON A SHEET") or nil
            if not s.takenT and s.prize and s.prize.dead then
                s.takenT = t
                s.hold = t + beatsLong(fx.beats)
                s.rec = math.max(s.rec, s.hold)
            end
            beatStep(game, s, t, fx.beats)
        end
        sh.zoom = function(game, t, s)
            if s.takenT and s.beat then return s.beat.zoom or 1 end
            local pv = previewing(game, s, s.prize, fx.beats, PREVIEW_SHEET)
            if pv then return pv.zoom end
            if type(zoom) == "function" then return zoom(game, t, s) end
            return zoom or 1
        end
        sh.aim = function(game)
            local b = sh.takenT and sh.beat
            if b then
                if b.aim then return aimAt(game, sh, b.aim) end
                return aimAt(game, sh, "hero")
            end
            local pv = previewing(game, sh, sh.prize, fx.beats, PREVIEW_SHEET)
            if pv then return aimAt(game, sh, pv.aim) end
            if aim then return aim(game) end
        end
        sh.move = function(game, t, s)
            local b = s.takenT and s.beat
            if b and b.move then return b.move(game, t, s) end
            return move(game, t, s)
        end
        return sh
    end
end

-- The piggy bank broken open on camera: FINANCE's encore, knocked down past its
-- shatter as it lands so the first thing it does is crack, say BANKRUPT! and
-- throw its savings across the box in rings -- and the hero, once they are
-- down, walks over them, the camera cut in on the run's coins counting up.
-- `say` is said over it until the coins are taken, and `short` trims the
-- walk over them for the reel of every pickup.
local function piggyShot(hook, say, short)
    local sh
    local beats = {
        { len = short and 0.7 or 1.2, zoom = 1, move = gather("coin") },
        { len = short and 1.6 or 2.6, zoom = HUD_LOOK, aim = "purse", say = "+1 COIN EACH",
          move = gather("coin") },
    }
    sh = {
        kind = "boss", subject = "finance", encore = true, warm = 2.5, rec = 30,
        -- Close on it cracking, wide for the rings going out across the box.
        zoom = function(game, t, s)
            if s.takenT then return s.beat and s.beat.zoom or 1 end
            return s.burst and 1 or ZOOM
        end,
        hud = true, hook = hook,
        aim = function(game)
            local b = sh.takenT and sh.beat
            if b and b.aim then return aimAt(game, sh, b.aim) end
        end,
        move = function(game, t, s)
            if s.gather then return gather("coin")(game) end
        end,
        direct = function(game, t, s)
            local e = game.boss
            -- Knocked past its shatter and set cracking straight away, out of
            -- whatever it was doing (PiggyBoss:update waits for it to be free).
            if e and not e.arrive and not s.hurt and t > 0.2 then
                s.hurt = true
                e.hp = math.floor(e.maxHp * e.brain.def.shatter.at)
                e.brain:calm(e)
                e.brain.state, e.brain.t = "crack", e.brain.def.shatter.time
            end
            if t > 2.6 or s.takenT then s.hook = nil end
            if not s.takenT then s.say = not s.hook and say or nil end
            local b = e and e.brain
            if b and b.state == "burst" then s.burst = true end
            -- Down to the floor once the rings have stopped coming.
            if s.burst and b and b.state ~= "burst" then s.gather = true end
            -- Counted from the savings, not from any bait it spat before.
            s.banked = s.banked or game.banked or 0
            if not s.gather then s.banked = game.banked or 0 end
            if not s.takenT and s.gather and (game.banked or 0) > s.banked then
                s.takenT = t
                s.rec = t + beatsLong(beats)
            end
            beatStep(game, s, t, beats)
        end,
    }
    return sh
end

-- The gold stars counted up: the same page, the same tool and the same crowd,
-- jumped ahead to a run that has walked to `n` of them, filmed close on the
-- numbers coming off the crowd. Tough kinds only, so a body takes a few hits
-- and the figure is seen more than once.
local STAR_CROWD = { "grin", "skull", "grin", "eye", "grin", "blot" }
local STAR_TOOL = { { "ruler", "max" } }

local function starStrip(game, n)
    fusionStrip(game, STAR_TOOL)
    hold(game, "ruler")
    game.loadout.stars = n
    game.loadout:rebuild(game.vw, game.vh)
end

local function toughCrowd(game, s, every, most)
    s.fedT = (s.fedT or 0) - DT
    if s.fedT > 0 or #game.enemies >= most then return end
    s.fedT = every
    local a = love.math.random() * math.pi * 2
    local r = 70 + love.math.random() * 20
    s.next = (s.next or 0) % #STAR_CROWD + 1
    game:spawnEnemy(STAR_CROWD[s.next], game.player.x + math.cos(a) * r,
        game.player.y + math.sin(a) * r)
end

local function starsLater(n, subject, rec)
    return {
        kind = "run", warm = 3, rec = rec or 2.2, zoom = ZOOM,
        tag = n .. " STARS", say = string.format("+%d%% DAMAGE", math.floor(n * Pickup.STAR * 100 + 0.5)),
        setup = function(game)
            lessonRun(game, subject)
            bare(game)
            starStrip(game, n)
        end,
        direct = function(game, t, s)
            game.ink = game.loadout.stats.inkMax
            toughCrowd(game, s, 0.07, 26)
            if t > -2 then hunt(game, s, t + 2, 50) end
        end,
    }
end

-- Every pickup reel is the page's take, the sheet's take and the card; the
-- star's goes on to the run that has kept on picking them up.
local function pickupReel(page, sheet, after)
    return function()
        local shots = { page() }
        if sheet then shots[#shots + 1] = sheet() end
        for _, shot in ipairs(after or {}) do shots[#shots + 1] = shot() end
        shots[#shots + 1] = { kind = "card", rec = 2.2, lines = { "SURVIVE", "SCHOOL" } }
        return shots
    end
end

local function lowHp(game) game.player.hp = 30 end
-- Under what it takes to start a stroke (Tools.MIN_INK), so the hand's
-- gestures draw nothing until the drop: out of ink, as a well left alone to
-- run dry is.
local function lowInk(game) game.ink = math.min(game.ink, Tools.MIN_INK * 0.6) end

-- After a clock: the class stood where it was, close on the hero and the hand
-- taking them apart while they cannot move.
local FROZEN = {
    { len = 1.0, zoom = ZOOM, aim = "hero", say = "THE CLASS FREEZES",
      hand = function(game, s) point(game.player.x + 30, game.player.y + 50, false) end },
    { len = 1.9, zoom = ZOOM, aim = "hero", say = "THE CLASS FREEZES" },
    { len = 0.8, zoom = 1 },
}

-- After an alarm: the bang, wide; the hero over the gems it left; the level bar
-- close as they come in.
local CLEARED = {
    { len = 1.3, zoom = 1, say = "IT CLEARS THE PAGE", hand = function() end },
    { len = 1.0, zoom = 1, move = gather("gem"), hand = function() end },
    { len = 2.0, zoom = HUD_LOOK, aim = "xp", say = "+XP", move = gather("gem"),
      hand = function() end },
}

local DRAFTED = {
    { len = 2.4, zoom = 1, say = "A WHOLE LEVEL", direct = pickCard },
    { len = 0.6, zoom = 1 },
}

-- Every pickup in one reel, shortened: the page takes only, one after another,
-- with no readout shown first (the bar is in the HUD anyway) and the beats after
-- each take cut down to the one that says what it did. Each one is closer to
-- the hero and walked to briskly, so the reel is mostly grabs and effects.
local QUICK = { at = 70, pace = 0.95, wait = 0 }

local function quick(spec)
    spec.at = { spec.side * 12, -QUICK.at }
    spec.pace, spec.wait = QUICK.pace, QUICK.wait
    return grabShot(spec)
end

local function allPickups()
    return {
        quick({ kind = "heart", subject = "science", side = 1, keepHp = true, setup = lowHp,
            hook = { "EVERY", "PICKUP" }, say = "HEART",
            beats = { { len = 1.5, zoom = HUD_LOOK, aim = "hp", say = "+25 HEALTH",
                        preview = true } } }),
        quick({ kind = "ink", subject = "science", side = -1, setup = lowInk, say = "INK DROP",
            each = function(game, s) if not s.takenT then lowInk(game) end end,
            hold = true, feed = { 0.1, 22, ZOOM },
            beats = { { len = 0.9, zoom = HUD_LOOK, aim = "ink", say = "FREE INK", hand = frenzy,
                        preview = true },
                      { len = 1.7, zoom = ZOOM, aim = "hero", say = "DRAW WITHOUT STOPPING",
                        hand = frenzy, move = stroll } } }),
        quick({ kind = "diamond", subject = "maths", side = 1, setup = realLevels,
            say = "DIAMOND", beats = { { len = 1.9, zoom = 1, say = "A WHOLE LEVEL",
                                         direct = pickCard } } }),
        quick({ kind = "clock", subject = "maths", side = -1, say = "WALL CLOCK",
            feed = { 0.05, 36, ZOOM },
            beats = { FROZEN[1], { len = 1.2, zoom = ZOOM, aim = "hero",
                                   say = "THE CLASS FREEZES" } } }),
        quick({ kind = "alarm", subject = "pe", side = 1, setup = quietLevels, say = "ALARM CLOCK",
            feed = { 0.05, 40, 1.4 },
            beats = { { len = 0.9, zoom = 1, say = "IT CLEARS THE PAGE", hand = function() end },
                      { len = 1.6, zoom = HUD_LOOK, aim = "xp", say = "+XP", move = gather("gem"),
                        hand = function() end } } }),
        quick({ kind = "star", subject = "finance", side = -1, say = "GOLD STAR",
            setup = function(game) starStrip(game, 0) end, feed = false, hold = true,
            each = function(game, s) toughCrowd(game, s, 0.18, 14) end,
            beats = { { len = 1.4, zoom = ZOOM, aim = "hero", tag = "1 STAR",
                        say = "+2% DAMAGE" } } }),
        starsLater(50, "music", 1.6),
        piggyShot(nil, "COINS", true),
        { kind = "card", rec = 2.2, lines = { "SURVIVE", "SCHOOL" } },
    }
end

return {
    pickups = allPickups,

    heart = pickupReel(
        function() return grabShot({ kind = "heart", subject = "science", at = { 14, -96 },
            keepHp = true, setup = lowHp, hook = { "LOW ON", "HEALTH?" }, hookY = 120,
            intro = { len = 1.4, zoom = HUD_LOOK, aim = "hp" },
            say = "GRAB A HEART",
            beats = { { len = 1.8, zoom = HUD_LOOK, aim = "hp", say = "+25 HEALTH", preview = true },
                      { len = 0.8, zoom = 1 } } }) end,
        function() return sheetFx(function(key)
            return labShot(key, "sequence", "heart", false, "school") end,
            { keepHp = true, setup = lowHp,
              beats = { { len = 1.8, zoom = HUD_LOOK, aim = "hp", say = "+25 HEALTH", preview = true } } })("maths") end),

    ink = pickupReel(
        -- SCIENCE, for its pencil: a line left on the page is what free ink buys.
        function() return grabShot({ kind = "ink", subject = "science", at = { -14, -96 },
            setup = lowInk, hook = { "OUT OF", "INK?" }, hookY = 120,
            intro = { len = 1.4, zoom = HUD_LOOK, aim = "ink" },
            say = "GRAB AN INK DROP",
            each = function(game, s)
                -- Held dry until the drop, and left alone after: the drop is
                -- what keeps it full.
                if not s.takenT then lowInk(game) end
            end,
            hold = true, feed = { 0.1, 22, ZOOM },
            beats = { { len = 1.3, zoom = HUD_LOOK, aim = "ink", say = "FREE INK", hand = frenzy,
                        preview = true },
                      { len = 2.9, zoom = ZOOM, aim = "hero", say = "DRAW WITHOUT STOPPING",
                        hand = frenzy, move = stroll } } }) end),

    diamond = pickupReel(
        function() return grabShot({ kind = "diamond", subject = "maths", at = { 12, -96 },
            setup = realLevels, hook = { "A FREE", "LEVEL" }, hookY = 120,
            intro = { len = 1.2, zoom = HUD_LOOK, aim = "xp" },
            say = "GRAB A DIAMOND", beats = DRAFTED }) end,
        function() return sheetFx(function(key)
            return labShot(key, "quiz", "diamond", false, "school") end,
            { setup = realLevels, beats = DRAFTED })("maths") end),

    clock = pickupReel(
        -- Not MUSIC, whose pins glue what they land on: the clock's stop
        -- should be the only one on the page.
        function() return grabShot({ kind = "clock", subject = "maths", at = { -10, -96 },
            hook = { "TOO MANY", "OF THEM?" }, say = "GRAB A CLOCK",
            feed = { 0.05, 36, ZOOM }, beats = FROZEN }) end,
        function() return sheetFx(circuitShot, { feed = { 0.08, 26, ZOOM, true }, beats = FROZEN })("science") end),

    alarm = pickupReel(
        function() return grabShot({ kind = "alarm", subject = "pe", at = { 10, -96 },
            setup = quietLevels, hook = { "SURROUNDED?" }, say = "GRAB AN ALARM",
            feed = { 0.05, 40, 1.4 }, beats = CLEARED }) end,
        function() return sheetFx(portraitShot, { setup = quietLevels, feed = { 0.1, 30 },
            beats = CLEARED })("art") end),

    star = pickupReel(
        function() return grabShot({ kind = "star", subject = "finance", at = { -12, -96 },
            setup = function(game)
                starStrip(game, 0)
                game.spawner.update = function() end
            end,
            hook = { "GOLD", "STARS" }, say = "GRAB A STAR", feed = false, hold = true,
            each = function(game, s) toughCrowd(game, s, 0.18, 14) end,
            beats = { { len = 2.2, zoom = ZOOM, aim = "hero", tag = "1 STAR", say = "+2% DAMAGE" } } }) end,
        function() return sheetFx(dotsShot, { beats = {
            { len = 1.4, zoom = ZOOM, aim = "hero", say = "+2% DAMAGE" } } })("art") end,
        { function() return starsLater(20, "science") end,
          function() return starsLater(50, "music") end }),

    coin = pickupReel(
        function() return piggyShot({ "BREAK THE", "BANK" }) end,
        function() return sheetFx(function(key) return labShot(key, "finance") end,
            { beats = { { len = 2.6, zoom = HUD_LOOK, aim = "purse", say = "+1 COIN EACH",
                preview = true } } })("finance") end),
}
end)()

local REELS = {
    montage = bossMontage,
    sun = sunReel,
    cools = coolsReel,
    storm = stormReel,
    halo = fusionReel({ parents = { "compass", "highlighter" }, catalyst = "fixative",
        fusion = "halo", decoys = { "magnet", "laminate", "cartridge", "bandaid" },
        pages = { "maths", "language", "art", "science", "music", "finance" } }),
    trench = fusionReel({ parents = { "ruler", "gluestick" }, catalyst = "tape",
        fusion = "trench", decoys = { "blotter", "plane", "bandaid", "metronome" },
        pages = { "finance", "science", "maths", "art", "language", "pe" } }),
    snag = fusionReel({ parents = { "rubber", "stapler" }, catalyst = "inkwell",
        fusion = "snag", decoys = { "page", "topmarks", "magnet", "fixative" },
        pages = { "art", "pe", "music", "maths", "science", "language" },
        hunts = { snag = snagHunt } }),
    punch = fusionReel({ parents = { "scissors", "compass" }, catalyst = "topmarks",
        fusion = "punch", decoys = { "magnet", "plane", "inkwell", "bandaid" },
        pages = { "science", "maths", "art", "music", "language", "finance" },
        hunts = { punch = ringPack(1.7) } }),
    guillotine = fusionReel({ parents = { "scissors", "ruler" }, catalyst = "topmarks",
        fusion = "guillotine", decoys = { "laminate", "page", "cartridge", "metronome" },
        pages = { "art", "finance", "pe", "science", "maths", "music" } }),
    tearline = fusionReel({ parents = { "scissors", "pushpin" }, catalyst = "cartridge",
        fusion = "tearline", decoys = { "blotter", "bandaid", "magnet", "plane" },
        pages = { "language", "music", "finance", "pe", "art", "science" },
        hunts = { tearline = pinPair } }),
    parting = fusionReel({ parents = { "rubber", "ruler" }, catalyst = "magnet",
        fusion = "parting", decoys = { "inkwell", "laminate", "tape", "page" },
        pages = { "art", "finance", "music", "language", "pe", "maths" } }),
    underline = fusionReel({ parents = { "highlighter", "ruler" }, catalyst = "fixative",
        fusion = "underline", decoys = { "metronome", "tape", "blotter", "bandaid" },
        pages = { "language", "finance", "science", "art", "maths", "pe" } }),
    corral = fusionReel({ parents = { "pen", "compass" }, catalyst = "tape",
        fusion = "corral", decoys = { "cartridge", "plane", "fixative", "magnet" },
        pages = { "music", "maths", "pe", "finance", "science", "art" },
        hunts = { corral = ringPack(2.2) } }),
    spindle = fusionReel({ parents = { "pushpin", "compass" }, catalyst = "fixative",
        fusion = "spindle", decoys = { "topmarks", "page", "inkwell", "laminate" },
        pages = { "music", "maths", "language", "science", "finance", "pe" },
        hunts = { spindle = ringPack(1.8) } }),
    crater = fusionReel({ parents = { "rubber", "pushpin" }, catalyst = "magnet",
        fusion = "crater", decoys = { "bandaid", "blotter", "plane", "tape" },
        pages = { "art", "music", "science", "pe", "maths", "language" },
        hunts = { crater = pinDense } }),
    dots = fusionReel({ parents = { "pencil", "pushpin" }, catalyst = "cartridge",
        fusion = "dots", decoys = { "laminate", "metronome", "fixative", "page" },
        pages = { "science", "music", "pe", "finance", "art", "maths" },
        hunts = { dots = pinShape } }),
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

for key, reel in pairs(PICKUP_REELS) do REELS[key] = reel end

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
    local z = shot and shot.zoom or 1
    if type(z) == "function" then z = z(game, shotT - (shot.warm or 0), shot) end
    local want = boss.radius + (z > 1 and 30 or 46)
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
    -- A punch in is a cut, not a drift: the lens starts on its subject. So is a
    -- jump from one subject to another at the same zoom (`cut`, set by a pickup
    -- reel's beat), which would otherwise be a slow pan across the page.
    if z ~= lastZoom or shot.cut then lensX, lastZoom, shot.cut = nil, z, nil end
    if z == 1 or (shot.kind ~= "boss" and shot.kind ~= "run") then
        love.graphics.draw(canvas, 0, 0)
        return out
    end

    -- A shot's own aim may pass (nil), for the boss and hero in between.
    local tx, ty
    if shot.aim then tx, ty = shot.aim(game) end
    if not tx then tx, ty = aim(game) end
    if not lensX then lensX, lensY = tx, ty end
    lensX = lensX + (tx - lensX) * math.min(1, DT * 5)
    lensY = lensY + (ty - lensY) * math.min(1, DT * 5)

    local vw, vh = w / z, h / z
    local top, bottom = HUD_TOP, HUD_BOTTOM
    if shot.kind == "run" or shot.hud then top, bottom = 0, 0 end
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
    local buf, frames = mix(seconds, level * (REEL_SFX[Capture.reel] or 1))
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

    -- A take that errors says so and stops, rather than standing on LOVE's
    -- error screen until the timeout with nobody there to read it.
    love.errorhandler = function(msg)
        print(debug.traceback("capture: " .. tostring(msg), 2))
        io.stdout:flush()
        os.exit(1)
    end

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
        if shot and shot.move then
            local mx, my = shot.move(game, shotT - (shot.warm or 0), shot)
            if mx then return mx, my end
        end
        return steer(game)
    end

    shots = REELS[Capture.reel]()
    begin(1)
end

-- Every frame's dt, whatever the machine took -- or a share of it, for a shot
-- that slows the page down (`speed`, a function of the shot's clock: a pickup
-- reel's grab). The film's own clock runs on at DT a frame either way, so a
-- slowed second is still a second of the reel.
function Capture.dt()
    local k = shot and shot.speed
    if type(k) == "function" then k = k(game, shotT - (shot.warm or 0), shot) end
    return DT * (k or 1)
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
    elseif shot.kind == "run" and not shot.keepHp then
        game.player.hp = game.player.maxHp
    end
    if shot.direct then shot.direct(game, shotT - (shot.warm or 0), shot) end
    if shot.kind == "run" then wrapUp(game, shot, shotT - (shot.warm or 0)) end

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
    if shot.kind ~= "boss" or shot.say then
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
