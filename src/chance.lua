-- The offer card: the health has run out, the run has no retake left
-- (src/perks.lua), and an ad could stand it back up -- once a run (src/ads.lua).
-- YES plays the ad and, if it was watched to its reward, the run gets up exactly
-- as a bought retake gets up (`Game:openRetake`); NO, or an ad closed early, is
-- the death card that was coming anyway.
--
-- It is a question rather than a clock, unlike the retake card it leads to,
-- because what it costs is thirty seconds of the player's afternoon and that is
-- theirs to spend or not. And it is asked *before* the run is banked or paid --
-- the same moment the retake is asked about -- because until it is answered
-- nobody knows whether this was an ending.
--
-- While the ad is up the card stays where it is, says so, and takes nothing: on
-- a phone the ad covers it and the game is not even running, and on a desktop
-- (the dev stand-in) the boxes must not be answerable twice.

local Palette = require("src.palette")
local I18n = require("src.i18n")
local Font = require("src.font")
local Input = require("src.input")
local Scribble = require("src.scribble")
local Sfx = require("src.sfx")
local util = require("src.util")

local Chance = {}
Chance.__index = Chance

local HEAD, TITLE = "OUT OF HEALTH", "ANOTHER CHANCE?"

-- What filling YES costs, or that it costs nothing: THE WHOLE BOOK turns the ads
-- off, and the offer stays on the page for it.
local COST, FREE = "WATCH AN AD TO GET UP", "FREE WITH THE WHOLE BOOK"
local ONCE = "ONCE A RUN"
local WAIT = "THE AD IS ON"

local ASK = "SCRIBBLE IN A BOX"
local LIFT, RELEASE = "LIFT TO CONFIRM", "RELEASE TO CONFIRM"
local KEYS = "OR PRESS 1 OR 2"

local LABEL_SCALE = 2
local BOX_TIME = 0.25
local CONFIRM = 0.32
local CARD_PAD_X, CARD_PAD_Y = 8, 7

function Chance.new()
    local self = setmetatable({}, Chance)
    self:open(false)
    return self
end

function Chance:open(free)
    self.t = 0
    self.phase = "asking"  -- asking -> confirm -> waiting
    self.chosen = nil
    self.confirmT = 0
    self.free = free
    self.seed = love.math.random() * 997
    self.marks = Scribble.newMarks(self.seed)
    self.pen = Scribble.newPen(Input.pointerDown)
    self.choice = Scribble.newChoice({
        { key = "yes", label = "YES" },
        { key = "no", label = "NO" },
    }, LABEL_SCALE)
end

-- The ad is up: the card holds still and says so until Game hears back.
function Chance:wait()
    self.phase = "waiting"
end

function Chance:cost()
    return self.free and FREE or COST
end

function Chance:prompt()
    if self.phase == "waiting" then return WAIT end
    if self.choice.armed then
        return Input.usingTouch and LIFT or RELEASE
    end
    return ASK
end

-- At the widest it could ever be, either cost line and every prompt included.
function Chance:contentWidth()
    return math.max(
        Font.width(I18n.t(HEAD)),
        Font.width(I18n.t(TITLE)) * LABEL_SCALE,
        Font.width(I18n.t(COST)), Font.width(I18n.t(FREE)),
        Font.width(I18n.t(ONCE)),
        self.choice:stripWidth(),
        Font.width(I18n.t(ASK)), Font.width(I18n.t(LIFT)),
        Font.width(I18n.t(RELEASE)), Font.width(I18n.t(KEYS)),
        Font.width(I18n.t(WAIT)))
end

function Chance:layout(game)
    local ins = game.inset
    local hintH = Input.usingTouch and Font.height or Font.height * 2 + 2

    local lay, y = {}, CARD_PAD_Y
    lay.head = y;  y = y + Font.height + 5
    lay.title = y; y = y + Font.height * LABEL_SCALE + 6
    lay.cost = y;  y = y + Font.height + 2
    lay.once = y;  y = y + Font.height + 8
    lay.boxes = y; y = y + Scribble.BOX_H + 9
    lay.hint = y;  y = y + hintH
    lay.cardH = y + CARD_PAD_Y

    local top = math.floor(ins.t + (game.vh - ins.t - ins.b - lay.cardH) / 2)
    lay.cardY = top
    for _, k in ipairs({ "head", "title", "cost", "once", "boxes", "hint" }) do
        lay[k] = lay[k] + top
    end

    lay.cx = math.floor(ins.l + (game.vw - ins.l - ins.r) / 2)
    lay.labelY = lay.boxes + math.floor((Scribble.BOX_H - Font.height * LABEL_SCALE) / 2)
    lay.cardW = self:contentWidth() + CARD_PAD_X * 2
    lay.cardX = math.floor(lay.cx - lay.cardW / 2)

    self.choice:layout(lay.cx, lay.boxes)
    self.lay = lay
    return lay
end

function Chance:commit(box)
    self.phase = "confirm"
    Sfx.play("accept")
    self.chosen = box
    self.confirmT = 0
end

function Chance:mark(x, y, quiet)
    if self.choice:mark(x, y, quiet) then return true end
    self.marks:add(x, y)
    return true
end

-- Returns "yes" or "no" once, on the frame the answer lands.
function Chance:update(dt, game)
    self:layout(game)
    self.t = self.t + dt
    self.marks:update(dt)

    if self.phase == "waiting" then return end

    if self.phase == "confirm" then
        self.confirmT = self.confirmT + dt
        if self.confirmT >= CONFIRM then
            return self.chosen.key
        end
        return
    end

    local filled = self.choice:update(dt)
    if filled then
        self:commit(filled)
        return
    end

    local down = Input.pointerDown
    self.pen:track(dt, down, Input.pointerX, Input.pointerY,
        function(mx, my) return self:mark(mx, my) end)

    if self.choice.armed and not down then
        self:commit(self.choice.armed)
    end
end

function Chance:keypressed(key)
    if self.phase ~= "asking" then return end
    if key == "1" then
        self.choice:autoFill(self.choice.boxes[1])
    elseif key == "2" then
        self.choice:autoFill(self.choice.boxes[2])
    end
end

function Chance:draw(game)
    local lay = self:layout(game)

    self.marks:draw(0)

    local progress = util.clamp(self.t / BOX_TIME, 0, 1)

    love.graphics.setColor(Palette.paper)
    love.graphics.rectangle("fill", lay.cardX, lay.cardY, lay.cardW, lay.cardH)
    Scribble.drawBox(
        { x = lay.cardX, y = lay.cardY, w = lay.cardW, h = lay.cardH },
        progress, Palette.slate, 7, 0)

    love.graphics.setColor(Palette.slate)
    Font.printCentered(I18n.t(HEAD), lay.cx, lay.head)

    -- Blue, the retake card's own colour for getting up: this is the one card
    -- after a death that is about the run going on.
    Scribble.printBig(I18n.t(TITLE), lay.cx, lay.title, LABEL_SCALE, Palette.blue,
        { shadow = Palette.graphite, wobble = true, t = self.t, seed = 9 })

    love.graphics.setColor(Palette.ink)
    Font.printCentered(I18n.t(self:cost()), lay.cx, lay.cost)
    love.graphics.setColor(Palette.slate)
    Font.printCentered(I18n.t(ONCE), lay.cx, lay.once)

    for i, box in ipairs(self.choice.boxes) do
        local color = Scribble.boxColor(box, self.chosen, self.confirmT)
        Scribble.printBig(Scribble.label(box), box.labelCx, lay.labelY,
            LABEL_SCALE, color,
            { shadow = Palette.paper, wobble = true, t = self.t, seed = 30 + i * 5 })
        Scribble.drawBox(box, progress, color, 10 + i, 0)
        Scribble.drawMarks(box.marks, Palette.ink, self.seed, 0)
    end

    if self.phase ~= "confirm" then
        local armed = self.choice.armed ~= nil
        Scribble.printBig(I18n.t(self:prompt()), lay.cx, lay.hint, 1,
            armed and Palette.red or Palette.slate, { seed = 51 })
        if self.phase == "asking" and not Input.usingTouch and not armed then
            Scribble.printBig(I18n.t(KEYS), lay.cx, lay.hint + Font.height + 2, 1,
                Palette.graphite, { seed = 52 })
        end
    end
end

return Chance
