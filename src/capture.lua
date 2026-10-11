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
-- what a player hears in bursts, the reel would hear as a drone.
local MUTED = { brush1 = true, brush2 = true, brush3 = true,
                brush4 = true, brush5 = true, brush6 = true }

-- And a reel's own, on top: the sun's crowd is fed straight at a hero who is
-- topped up every frame, so he is hit all the time and the hurt would be a
-- second drone under the burn. A boss reel keeps it -- there a hit is the boss
-- landing one, which is half of what is being shown.
local REEL_MUTED = { sun = { hurt = true }, cools = { hurt = true } }

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

-- The lesson's horde, fed in along the line the S is coming down, ahead of it
-- and either side of the hero, so the crowd it cuts is on camera with it. Real
-- arrivals off the spawner (`Spawner:dropAt`), as the sun's are.
local function feedLine(game, s, angle)
    s.fed = (s.fed or 0) - DT
    if s.fed > 0 then return end
    s.fed = FEED_EVERY
    local dx, dy = math.cos(angle), math.sin(angle)
    local along = (love.math.random() * 2 - 1) * 90
    local off = (love.math.random() * 2 - 1) * 24
    game.spawner:dropAt(game, game.player.x + dx * along - dy * off,
        game.player.y + dy * along + dx * off)
end

-- Where to look in a cool S shot filmed close: between the S and the hero,
-- weighted to the S, so it is followed in, through him and out the other side.
local function coolsAim(game)
    local left, top = Camera.steady()
    local p = game.player
    local s = game.loadout.live.cools and game.loadout.live.cools.live[1]
    if not s then return p.x - left, p.y - top end
    return s.x * 0.6 + p.x * 0.4 - left, s.y * 0.6 + p.y * 0.4 - top
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
        setup = function(game) runShot(game) end,
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
                feedLine(game, s, FIRST)
                if t - s.back > 0.9 then s.say = "IT CUTS A LINE THROUGH YOU" end
            end
        end,
        zoom = function(game, t, s)
            return s.back and t - s.back > 0.9 and ZOOM or 1
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
                runShot(game, spec.subject)
                for _ = 1, spec.level do game.loadout:take("cools", game) end
                game.player:applyStats()
            end,
            direct = function(game, t, s)
                if spec.angle then
                    if t >= -spec.lead and not s.sent then
                        s.sent = true
                        sendS(game, spec.angle, spec.back)
                    end
                    feedLine(game, s, spec.angle)
                end
            end,
            zoom = spec.zoom,
            aim = spec.zoom and coolsAim or nil,
        }
    end

    shots[#shots + 1] = coolsShot({ level = 1, angle = -math.pi * 0.62, back = 150,
        lead = 0.6, rec = 2.4, zoom = ZOOM, subject = "science" })
    shots[#shots + 1] = coolsShot({ level = 1, angle = math.pi * 0.4, back = 150,
        lead = 0.6, rec = 2.4, zoom = ZOOM, subject = "art" })
    shots[#shots + 1] = coolsShot({ level = #Upgrades.byId.cools.levels,
        angle = -0.45, back = 0, lead = 2.5, rec = 2.4, subject = "music" })

    shots[#shots + 1] = { kind = "card", rec = 2.2, lines = { "SURVIVE", "SCHOOL" } }
    return shots
end

local REELS = {
    montage = bossMontage,
    sun = sunReel,
    cools = coolsReel,
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
        local quiet = MUTED[ev.name] or (REEL_MUTED[Capture.reel] or {})[ev.name]
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
    if not boss or boss.arrive or burst > 0.75 or game.ink < 0.2 then
        Input.pointerDown = false
        return
    end

    -- A zigzag dragged across the body, in canvas pixels.
    local left, top = Camera.steady()
    local r = math.max(8, boss.radius * 0.8)
    local zig = math.sin(burst * 22) * r
    local drift = (burst / 0.75 - 0.5) * r * 1.6
    Input.pointerDown = true
    Input.pointerX = boss.x - left + drift
    Input.pointerY = boss.y - top + zig * 0.6
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

    if shot.kind == "boss" then
        game:setSubject(shot.subject)
        -- The encore is the second boss, which only a two-boss course sends;
        -- the dev boss test sends the last of the lineup (Game:reset).
        Course.current = Course.get(shot.encore and "masters" or "school")
        Dev.boss = true
        game:reset()
        -- The draft would stop the take; a level is not what is being filmed.
        game.player.addXp = function() end
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
    -- The pointer is the bot's, and a drawn cursor would only say so.
    Input.hover = function() return nil end
    Input.movement = function() return steer(game) end

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
        scribble(game)
    elseif shot.kind == "run" then
        game.player.hp = game.player.maxHp
    end
    if shot.direct then shot.direct(game, shotT - (shot.warm or 0), shot) end
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
