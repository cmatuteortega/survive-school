-- The x2 box: the third box on the two cards a run ends on (src/over.lua,
-- src/win.lua), offered once a run, which plays a rewarded ad (src/ads.lua) and
-- doubles what the run pays into the purse (`Game:doubleRun`).
--
-- One small table of state and the words for each state, kept here so the two
-- cards say the same thing in the same order and neither has to know the other
-- has it. What it does not own is the box itself -- that is on each card's
-- choice, like the other two -- or the money, which is Game's.
--
-- **The box never leaves the card.** Once answered, failed or not, it goes grey
-- and takes no more ink: a strip that lost a box would close up and move the two
-- boxes still being answered, and nothing on a card moves while it is asked.

local I18n = require("src.i18n")
local Font = require("src.font")

local Double = {}

local LINES = {
    ad = "WATCH AN AD FOR X2 COINS",
    free = "X2 COINS FREE WITH THE WHOLE BOOK",
    waiting = "THE AD IS ON",
    doubled = "COINS DOUBLED",
    gone = "NO AD RIGHT NOW",
}

-- The keyboard line once there is a third box to press.
Double.KEYS = "OR PRESS 1 2 OR 3"

-- `offer` is nil (no box: nothing to double, already doubled, or no ad to show),
-- "ad" or "free".
function Double.new(offer)
    return { state = offer and "offered" or nil, free = offer == "free" }
end

function Double.def()
    return { key = "double", label = "X2" }
end

function Double.offered(d) return d.state ~= nil end
function Double.live(d) return d.state == "offered" end
function Double.waiting(d) return d.state == "waiting" end

function Double.line(d)
    if not d.state then return nil end
    if d.state == "offered" then return LINES[d.free and "free" or "ad"] end
    return LINES[d.state]
end

-- Every line it could ever print, so the card is struck off the widest of them.
function Double.width()
    local w = 0
    for _, text in pairs(LINES) do w = math.max(w, Font.width(I18n.t(text))) end
    return w
end

function Double.wait(d) d.state = "waiting" end

-- How the ad ended: paid, or not.
function Double.settle(d, paid)
    d.state = paid and "doubled" or "gone"
end

return Double
