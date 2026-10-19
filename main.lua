-- Survive School. Everything renders into a low-res canvas blown up by a
-- whole number, so a game pixel is always an exact block of screen pixels. The
-- canvas is not a fixed 320x180: zoom is picked off the SHORT window edge and
-- the canvas made as many game pixels as it takes to cover the window (320x180
-- on 16:9, 400x180 on a 20:9 phone, 180x400 upright; a computer aims a little
-- taller, see `designH`). Nothing is letterboxed or
-- stretched, so a phone may turn (src/orient.lua) and screens lay themselves
-- out against `Game.vw/vh`.

local Capture = require("src.capture")
local Display = require("src.display")
local Game = require("src.game")
local Input = require("src.input")
local Options = require("src.options")
local Orient = require("src.orient")
local Palette = require("src.palette")
local Sfx = require("src.sfx")

local BASE_H = 180  -- design height, in game pixels
local BASE_W = 320  -- ... and the long edge no screen is laid out narrower than
local DESK_H = 216  -- the short edge a computer aims for instead

local canvas
local vw, vh = 320, 180
local scale, offsetX, offsetY = 1, 0, 0

local function isMobile()
    local os = love.system.getOS()
    return os == "Android" or os == "iOS"
end

-- The title bar and taskbar show the cool S, ink on paper, as the launcher
-- icons do (android/icon.py, desktop/icon.py). Set at run time because LÖVE's
-- own window icon is otherwise its heart (or nothing, on Linux) whatever the
-- packaged .exe or AppImage carries; built from the sprite, not a file, so it
-- follows the art. A whole scale for the reason everything here is one.
local function setWindowIcon()
    local Sprites = require("src.sprites")
    local rows, size, scale = Sprites.COOLS, 64, 3
    local ox = math.floor((size - #rows[1] * scale) / 2)
    local oy = math.floor((size - #rows * scale) / 2)
    local paper, ink = Palette.paper, Palette.ink
    local icon = love.image.newImageData(size, size)
    icon:mapPixel(function(x, y)
        local gx, gy = math.floor((x - ox) / scale), math.floor((y - oy) / scale)
        local row = rows[gy + 1]
        if x >= ox and y >= oy and row and gx < #row and row:sub(gx + 1, gx + 1) ~= "." then
            return ink[1], ink[2], ink[3], 1
        end
        return paper[1], paper[2], paper[3], 1
    end)
    love.window.setIcon(icon)
end

-- Notches, punch-holes and gesture bars. Reported in window units, wanted in
-- canvas pixels, as a margin off each edge for the HUD to keep clear of.
local function safeInsets()
    if not love.window.getSafeArea then return 0, 0, 0, 0 end

    local sx, sy, sw, sh = love.window.getSafeArea()
    local left = (sx - offsetX) / scale
    local top = (sy - offsetY) / scale

    return math.max(0, math.floor(left)),
           math.max(0, math.floor(top)),
           math.max(0, math.ceil(vw - (left + sw / scale))),
           math.max(0, math.ceil(vh - (top + sh / scale)))
end

-- 180 game pixels down the short edge is the size everything was drawn at, for
-- a phone in the hand. A laptop is a picture several times the size at much the
-- same distance, and 180 there made every word and card loom -- a TV across the
-- room was the one computer screen it looked right on. So a computer takes the
-- zoom off a fifth more page; the dev take (src/capture.lua) is a phone page
-- however it is filmed, so it keeps the phone's.
local function designH()
    if isMobile() or Capture.on then return BASE_H end
    return DESK_H
end

local function fitToWindow()
    local w, h = love.graphics.getDimensions()

    -- Whole-number zoom off the SHORT edge, never below the design height: a
    -- bigger screen gets more page, not smaller pixels. And never so much that
    -- the LONG edge falls short of 320: off the short edge alone a 16:10 laptop
    -- (1440x900 at 5x) was handed a 288x180 page, narrower than anything here
    -- was laid out for, and the draft stacked its cards down it as if the
    -- laptop were a phone held upright (src/levelup.lua).
    local short, long = math.min(w, h), math.max(w, h)
    scale = math.max(1, math.min(math.floor(short / designH()),
                                 math.floor(long / BASE_W)))

    -- Enough game pixels to cover the window; the leftover fraction is split
    -- between opposite edges, so the canvas always reaches every corner.
    local cw, ch = math.ceil(w / scale), math.ceil(h / scale)
    if cw ~= vw or ch ~= vh or not canvas then
        vw, vh = cw, ch

        -- A dragged window edge lands here every frame: release, don't collect.
        if canvas then canvas:release() end

        canvas = love.graphics.newCanvas(vw, vh)
        canvas:setFilter("nearest", "nearest")
        Game:resize(vw, vh)
    end

    offsetX = math.floor((w - vw * scale) / 2)
    offsetY = math.floor((h - vh * scale) / 2)

    -- Touches report in real screen pixels, the game in window units; identical
    -- unless DPI scaling is on.
    local touchScale = 1
    if love.graphics.getPixelWidth then
        local pw = love.graphics.getPixelWidth()
        if pw and pw > 0 and w > 0 then touchScale = pw / w end
    end

    -- Input reports in canvas pixels, so it needs the same transform.
    Input.setTransform(scale, offsetX, offsetY, vw, vh, touchScale)

    local l, t, r, b = safeInsets()
    Input.setSafeInsets(l, t, r, b)
    Game:setSafeInsets(l, t, r, b)
end

function love.load(args)
    -- A dev take (src/capture.lua) opens its own upright window and save, so
    -- before anything is sized or read.
    Capture.parse(args)

    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")

    if isMobile() then
        -- Whole screen, bars included; the safe insets keep the HUD off notches.
        love.window.setFullscreen(true, "desktop")
        -- No mouse or keyboard on a phone: show the stick from the first frame.
        Input.usingTouch = true
    else
        setWindowIcon()
        -- The cursor is drawn into the canvas instead (Game:drawPointer): the
        -- system's arrow is the one thing on screen at the wrong scale and in
        -- colours off the palette.
        love.mouse.setVisible(false)
    end

    fitToWindow()
    Game:load(vw, vh)

    -- After Game:load, which reads the pinned mode off disk (src/options.lua),
    -- and here because turning the phone is a window call; the turn comes back
    -- a frame or two later as an ordinary resize.
    Orient.apply()

    -- The desktop's twin of that: the window the settings page last left, if it
    -- is not the fullscreen conf.lua opened on (src/display.lua). A take keeps
    -- the window it opened for itself.
    Display.fit = fitToWindow
    if Capture.on then Display.off = true end
    Display.apply()

    if Capture.on then Capture.start(Game) end
end

function love.resize()
    fitToWindow()
end

function love.focus(focused)
    -- Backgrounding swallows touchreleased: the stick jams on, the pen draws on.
    -- And it may be the last frame this process runs: on Android the focus is
    -- lost a moment before the app is paused, and the system can kill a paused
    -- app without another word, so the bookmark is written here as well as on
    -- the way out (Game:closing) and every few seconds of play
    -- (Game:keepBookmark). Whether this arrives before the pause is a race; it
    -- is a cheap write to win when it does.
    if not focused then
        Input.releaseAll()
        Game:closing()
    end
end

-- Out of sight, so silent (src/sfx.lua) and put down -- in that order, or the
-- pause card's sound is started at the last moment and replays as a stutter on
-- the way back in. Deliberately not love.focus: a run you can see you should be
-- able to hear. Android blocks the program while backgrounded, so this lands on
-- the way in and the music is stopped down in the engine -- and why the
-- bookmark is not left to it (Game:keepBookmark). On a desktop it does land
-- going out, so a minimised window leaves one too.
function love.visible(visible)
    if visible then
        Sfx.resume()
    else
        Sfx.silence()
        Game:putDown()
        Game:closing()
    end
end

-- The frame cap the settings ask for (src/display.lua): what is left of the
-- frame's share of the second, slept, the way underroot caps its frames.
local frameAt = 0
local function cap()
    local fps = Display.fps()
    if Capture.on or fps <= 0 then return end
    local wait = frameAt + 1 / fps - love.timer.getTime()
    if wait > 0 then love.timer.sleep(wait) end
    frameAt = love.timer.getTime()
end

function love.update(dt)
    cap()
    if Capture.on then
        dt = Capture.dt()
        Capture.update()
    end
    -- Clamp so a hitched frame can't teleport anything through a collision.
    Game:update(math.min(dt, 1 / 30))
end

function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(Palette.paper)
    Game:draw()
    Game:drawPointer()
    if Capture.on then Capture.frame(canvas) end
    love.graphics.setCanvas()

    -- Darkest ink under the canvas: a stale frame showing through a rounding
    -- gap would read as a flicker along the edge.
    love.graphics.setColor(Palette.ink)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, offsetX, offsetY, 0, scale, scale)
end

function love.keypressed(key)
    if key == "f11" or (key == "return" and love.keyboard.isDown("lalt", "ralt")) then
        -- Through the settings rather than round them, so the SCREEN row says
        -- what the screen is doing and the next launch opens the same way.
        Display.toggle()
        Options.save()
    else
        Game:keypressed(key)
    end
end

function love.wheelmoved(_, dy)
    Game:wheelmoved(dy)
end

-- The close button and the title screen's NO both land here: the last
-- chance to leave a bookmark (src/bookmark.lua). A force quit or crash misses
-- it, and gets the one Game:keepBookmark wrote a few seconds before instead.
function love.quit()
    Game:closing()
end

love.mousepressed = Input.mousepressed
love.mousemoved = Input.mousemoved
love.mousereleased = Input.mousereleased
love.touchpressed = Input.touchpressed
love.touchmoved = Input.touchmoved
love.touchreleased = Input.touchreleased
