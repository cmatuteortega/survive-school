-- How a computer shows the page: over the whole screen or in a window, how big
-- that window is, whether frames wait for the monitor and how many it draws a
-- second -- the settings page's desktop rows on its DEVICE tab, in the place
-- src/orient.lua's SCREEN row and the stick and vibration rows have on a phone.
-- And the one of the phone's rows that is about frames too: the battery saver.
-- Each kind of device is shown the rows it can act on and no others
-- (`Display.MOBILE`, read by src/settings.lua), the way underroot splits its own
-- settings: a window size on a phone and an orientation on a monitor are both
-- rows that say something and do nothing.
--
-- Like src/orient.lua this owns the values and the lists they are read back
-- against (src/options.lua writes them), and `apply` is what puts them to work.
-- The window is never touched on a phone or under a dev take (src/capture.lua),
-- which opens a window of its own.
--
-- Fullscreen is the desktop kind ("desktop", the screen's own resolution) for
-- conf.lua's reason: a mode change would have the zoom picked off a size the
-- monitor is pretending to be. The window sizes are the three 16:9 sizes a
-- 180-pixel page lands on at a whole zoom (x4, x5, x6), clamped to the screen.

local Display = {}

local OS = love.system.getOS()
Display.MOBILE = OS == "Android" or OS == "iOS"

Display.WINDOWS = { "full", "window" }
Display.SIZES = { "1280x720", "1600x900", "1920x1080" }

-- Where a first run starts: conf.lua's own window, over the whole screen.
Display.window = "full"
Display.size = "1280x720"
Display.vsync = true

-- The frame cap: frames a second a computer draws at most, 0 for no cap of its
-- own (vsync, if it is on, is still a cap). And the phone's battery saver, which
-- is the same thing with one number in it: 30, half what a phone draws, which
-- this game's whole-pixel page shows no difference at -- the dt is clamped at a
-- thirtieth already (main.lua), so nothing in a run moves differently at it.
Display.CAPS = { 0, 30, 60, 120 }
Display.cap = 0
Display.saver = false
local SAVER = 30

-- Set by main.lua: refit the canvas to the window. A setMode does not always
-- come back as a resize, so it is asked for here rather than waited on.
Display.fit = nil

-- Off on a phone, and off for a take, whose window is its own.
Display.off = Display.MOBILE

local function refit()
    if Display.fit then Display.fit() end
end

-- The window as the settings have it. Safe to call when nothing changed:
-- fullscreen that is already fullscreen stays, and a window is only rebuilt
-- when it is not already the size asked for -- vsync alone is set in place.
function Display.apply()
    if Display.off then return end

    if Display.window == "full" then
        if not love.window.getFullscreen() then
            love.window.setFullscreen(true, "desktop")
        end
        love.window.setVSync(Display.vsync and 1 or 0)
    else
        local w, h = Display.size:match("(%d+)x(%d+)")
        w, h = tonumber(w), tonumber(h)
        local dw, dh = love.window.getDesktopDimensions()
        if dw and dw > 0 then w, h = math.min(w, dw), math.min(h, dh) end
        local cw, ch, flags = love.window.getMode()
        if not flags.fullscreen and cw == w and ch == h then
            love.window.setVSync(Display.vsync and 1 or 0)
            return
        end
        -- The flags conf.lua opened with, so the window that comes back is the
        -- same window at another size: no DPI scaling, for the whole-pixel rule.
        love.window.setMode(w, h, {
            fullscreen = false, resizable = true,
            minwidth = 320, minheight = 180,
            highdpi = false, usedpiscale = false,
            vsync = Display.vsync and 1 or 0,
        })
    end
    refit()
end

-- What to hold the frame rate to on this device, 0 for nothing. A take keeps
-- its own clock (src/capture.lua) and is never capped.
function Display.fps()
    if Display.MOBILE then return Display.saver and SAVER or 0 end
    if Display.off then return 0 end
    return Display.cap
end

-- F11 / alt+enter (main.lua): the other of the two, and the setting follows,
-- so the page says what the screen is doing and the next launch opens that way.
function Display.toggle()
    if Display.off then return end
    Display.window = love.window.getFullscreen() and "window" or "full"
    Display.apply()
end

return Display
