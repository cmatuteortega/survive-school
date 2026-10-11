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
local Dev = require("src.dev")
local Enemy = require("src.enemy")
local Font = require("src.font")
local I18n = require("src.i18n")
local Input = require("src.input")
local Palette = require("src.palette")
local Scribble = require("src.scribble")
local Sfx = require("src.sfx")
local Subjects = require("src.subjects")
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

local REELS = {
    montage = bossMontage,
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
        local data = not MUTED[ev.name] and Sfx.sample(ev.name)
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

local function lens(canvas)
    local z = shot.zoom or 1
    local w, h = canvas:getDimensions()
    if not out then
        out = love.graphics.newCanvas(w, h)
        out:setFilter("nearest", "nearest")
    end

    love.graphics.setCanvas(out)
    love.graphics.clear(Palette.paper)
    love.graphics.setColor(1, 1, 1)
    if z == 1 or shot.kind ~= "boss" then
        love.graphics.draw(canvas, 0, 0)
        return out
    end

    local tx, ty = aim()
    if not lensX then lensX, lensY = tx, ty end
    lensX = lensX + (tx - lensX) * math.min(1, DT * 5)
    lensY = lensY + (ty - lensY) * math.min(1, DT * 5)

    local vw, vh = w / z, h / z
    local ox = math.floor(util.clamp(lensX - vw / 2, 0, w - vw) + 0.5)
    local oy = math.floor(util.clamp(lensY - vh / 2, HUD_TOP, h - vh - HUD_BOTTOM) + 0.5)
    love.graphics.draw(canvas, -ox * z, -oy * z, 0, z, z)
    return out
end

--- shots ---------------------------------------------------------------------


local function begin(i)
    index, shot, shotT = i, shots[i], 0
    if not shot then return end

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
            Scribble.printBig(I18n.t(line), w / 2, 28 + (i - 1) * 22, 3,
                i == 1 and Palette.ink or Palette.red,
                { shadow = Palette.paper, count = math.floor(shotT * 18) - (i - 1) * 6,
                  wobble = true, t = shotT, seed = i * 7 })
        end
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
