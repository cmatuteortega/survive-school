-- Rewarded ads: the two places in the book a player can choose to watch one, and
-- the only two (ROADMAP.md, README **Ads and the shop**). Watching gets the
-- run back on its feet once (src/chance.lua) or doubles what it paid into the
-- purse once (the x2 box on src/over.lua and src/win.lua). Nothing here is
-- ever shown without being asked for, and nothing a run needs is behind one.
--
-- **The native half is android/love-ads**, built into the APK beside love-iap's
-- store bridge by android/ads.sh: Google's consent form (UMP) and one AdMob
-- rewarded unit. This file reaches it the way src/iap.lua reaches the store --
-- five C functions through LuaJIT's FFI, every answer a tab-separated line on a
-- queue drained once a frame -- so the phone is spoken to one way, not two.
--
-- **An ad is a question with a callback.** `Ads.show(placement, fn)` calls `fn`
-- exactly once: true if the ad was watched to its reward, false if it was
-- closed early, failed, or there was none. The caller decides what either means;
-- this file knows nothing about runs or coins.
--
-- **THE WHOLE BOOK (src/store.lua) turns the ads off**, and that is decided here
-- rather than at either card: `Ads.show` answers true on the spot, so the two
-- offers stay on the page -- once a run each -- with nothing to watch.
--
-- Off a phone there is no SDK and `Ads.ready` is false, so neither offer is made.
-- With the dev row showing (src/dev.lua) a stand-in answers instead: an ad that
-- "plays" for a second and pays, so both cards can be played through on a desktop.

local Dev = require("src.dev")
local Store = require("src.store")

local Ads = {}

local CDEF = [[
    int liads_start(void);
    void liads_show(const char *placement);
    void liads_privacy(void);
    const char *liads_poll(void);
    const char *liads_error(void);
]]

local ffi, native
local mock, mockQueue, mockClock = false, {}, 0

-- Whether an ad is loaded and could be shown this frame.
local loaded = false

-- The one ad that is up, if one is: `{ placement, fn, paid }`.
local showing = nil

-- Whether the consent form says the player must be given a way back to it,
-- which is the PRIVACY row's reason to exist (src/canteen.lua).
Ads.privacyNeeded = false

-- Why there are no ads, for anyone curious (nil while there may be).
Ads.why = "Ads.start has not been called"

local function split(line)
    local f = {}
    for field in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = field end
    return f
end

local function finish(paid)
    local s = showing
    showing = nil
    if s then s.fn(paid) end
end

local handlers = {
    ready = function() loaded = true end,
    none = function() loaded = false end,
    reward = function(f)
        if showing and showing.placement == f[2] then showing.paid = true end
    end,
    -- The reward is only *settled* when the ad is gone: AdMob pays before it
    -- closes, and the card underneath must not move while the ad is still up.
    closed = function(f)
        if showing and showing.placement == f[2] then finish(showing.paid) end
    end,
    failed = function(f)
        if showing and showing.placement == f[2] then finish(false) end
    end,
    privacy = function(f) Ads.privacyNeeded = f[2] == "1" end,
    unavailable = function(f)
        loaded = false
        Ads.why = f[2]
    end,
}

local function dispatch(f)
    local fn = handlers[f[1]]
    if fn then fn(f) end
end

local function connect()
    local ok, mod = pcall(require, "ffi")
    if not ok then return nil, "no FFI" end
    if love.system.getOS() ~= "Android" then
        return nil, "no ads on " .. love.system.getOS()
    end

    local loadedLib, lib = pcall(mod.load, "liads")
    if not loadedLib then return nil, "libliads.so not in the APK" end
    pcall(mod.cdef, CDEF)
    if not pcall(function() return lib.liads_poll, lib.liads_error end) then
        return nil, "the liads_* functions are not linked into this build"
    end
    return lib, mod
end

-- Once, at load. The consent form, if the player's region needs one, comes up
-- over the title on the first launch -- which is Google's rule and not a place
-- this game would choose -- and ads are only asked for once it has been answered.
function Ads.start()
    loaded, showing, mock, mockQueue = false, nil, false, {}

    local lib, second = connect()
    if lib then
        native, ffi = lib, second
        if native.liads_start() == 1 then
            Ads.why = nil
        else
            Ads.why = ffi.string(native.liads_error())
            native = nil
        end
    elseif Dev.showing() then
        mock, Ads.why = true, nil
        mockQueue[#mockQueue + 1] = { at = 0.5, "ready" }
    else
        Ads.why = second
    end
end

-- Every frame, in every state: an ad closes over whatever card asked for it.
function Ads.update(dt)
    if native then
        while true do
            local line = native.liads_poll()
            if line == nil then break end
            dispatch(split(ffi.string(line)))
        end
    elseif mock then
        mockClock = mockClock + (dt or 0)
        local due, keep = {}, {}
        for _, item in ipairs(mockQueue) do
            if item.at <= mockClock then due[#due + 1] = item
            else keep[#keep + 1] = item end
        end
        mockQueue = keep
        for _, item in ipairs(due) do dispatch(item) end
    end
end

-- Whether an offer can be made: the book has bought its way past the ads, or one
-- is loaded and nothing else is showing. Asked before a box is drawn, so an offer
-- is never put on a card that would have to answer it with "no ad".
function Ads.ready()
    if Store.noAds() then return true end
    return loaded and showing == nil
end

-- Whether the next answer will be an ad at all, for the line on a card that says
-- what filling the box costs.
function Ads.free()
    return Store.noAds()
end

function Ads.show(placement, fn)
    if Store.noAds() then
        fn(true)
        return
    end
    if not loaded or showing then
        fn(false)
        return
    end

    showing = { placement = placement, fn = fn, paid = false }
    loaded = false
    if native then
        native.liads_show(placement)
    elseif mock then
        local at = mockClock
        mockQueue[#mockQueue + 1] = { at = at + 1.0, "reward", placement }
        mockQueue[#mockQueue + 1] = { at = at + 1.0, "closed", placement }
        mockQueue[#mockQueue + 1] = { at = at + 1.5, "ready" }
    else
        finish(false)
    end
end

-- Whether an ad is up right now, so the card that asked can say so.
function Ads.busy()
    return showing ~= nil
end

function Ads.privacy()
    if native then native.liads_privacy() end
end

return Ads
