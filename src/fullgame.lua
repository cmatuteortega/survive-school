-- The offer card for the full game (src/store.lua): opened by the padlock in the
-- top corner of the title and of the timetable, laid over whichever of the two
-- it was opened from, and handed straight back to it.
--
-- It is the revive offer's card (src/chance.lua) asking a different question in
-- the same way: a heading, the question, what it costs, and YES and NO to
-- scribble in. YES opens the store's own purchase sheet and the card holds still
-- saying so until the store answers -- bought, and the card is gone with the
-- book open behind it; cancelled or failed, and the question is asked again.
-- Nothing is owned until the store says so, the same rule the canteen's counter
-- is under, and the canteen is where the other purchase (THE WHOLE BOOK) and
-- RESTORE live: this card sells one thing, to a book that does not have it.
--
-- Where there is no store answering, or it has not said a price yet, YES has no
-- box and the price line says the shop is closed: a box you can fill and cannot
-- answer is worse than no box, which is the timetable's rule for a shut page's GO!.

local Palette = require("src.palette")
local I18n = require("src.i18n")
local Font = require("src.font")
local Input = require("src.input")
local Scribble = require("src.scribble")
local Store = require("src.store")
local Sfx = require("src.sfx")
local util = require("src.util")

local FullGame = {}
FullGame.__index = FullGame

local HEAD, TITLE = "SCIENCE IS ALWAYS FREE", "FULL GAME?"
local WHAT = "EVERY LESSON AND EVERY TOOL"
local CLOSED = "THE SHOP IS CLOSED"
local WAIT = "WAITING FOR THE STORE"

local ASK = "SCRIBBLE IN A BOX"
local LIFT, RELEASE = "LIFT TO CONFIRM", "RELEASE TO CONFIRM"
local KEYS = "OR PRESS 1 OR 2"

local LABEL_SCALE = 2
local BOX_TIME = 0.25
local CONFIRM = 0.32
local CARD_PAD_X, CARD_PAD_Y = 8, 7

function FullGame.new()
    local self = setmetatable({}, FullGame)
    self:open()
    return self
end

function FullGame:open()
    self.t = 0
    self.phase = "asking"  -- asking -> confirm -> waiting
    self.chosen = nil
    self.confirmT = 0
    self.back = false
    self.seed = love.math.random() * 997
    self.marks = Scribble.newMarks(self.seed)
    self.pen = Scribble.newPen(Input.pointerDown)
    self.choice = Scribble.newChoice({
        { key = "yes", label = "YES" },
        { key = "no", label = "NO" },
    }, LABEL_SCALE)
end

-- Whether YES can be answered at all: a store answering, a price from it, and no
-- purchase of this already in the air.
function FullGame:buyable()
    return Store.canBuy(Store.FULL)
end

-- The line under the question: the price as the store wrote it, or why there is
-- none. The store's own words are printed as they came, untranslated, the
-- canteen's rule for a price.
function FullGame:priceLine()
    if self.phase == "waiting" or Store.pending[Store.FULL] then
        return I18n.t(WAIT), Palette.slate
    end
    local price = Store.available() and Store.price(Store.FULL)
    if not price then return I18n.t(CLOSED), Palette.slate end
    return price, Palette.ink
end

function FullGame:prompt()
    if self.choice.armed then
        return Input.usingTouch and LIFT or RELEASE
    end
    return ASK
end

-- At the widest it could ever be, every price line and every prompt included,
-- so the card does not move when the store answers.
function FullGame:contentWidth()
    return math.max(
        Font.width(I18n.t(HEAD)),
        Font.width(I18n.t(TITLE)) * LABEL_SCALE,
        Font.width(I18n.t(WHAT)),
        Font.width(I18n.t(CLOSED)), Font.width(I18n.t(WAIT)),
        Store.widestPrice(),
        self.choice:stripWidth(),
        Font.width(I18n.t(ASK)), Font.width(I18n.t(LIFT)),
        Font.width(I18n.t(RELEASE)), Font.width(I18n.t(KEYS)))
end

function FullGame:layout(game)
    local ins = game.inset
    local hintH = Input.usingTouch and Font.height or Font.height * 2 + 2

    local lay, y = {}, CARD_PAD_Y
    lay.head = y;  y = y + Font.height + 5
    lay.title = y; y = y + Font.height * LABEL_SCALE + 6
    lay.what = y;  y = y + Font.height + 2
    lay.price = y; y = y + Font.height + 8
    lay.boxes = y; y = y + Scribble.BOX_H + 9
    lay.hint = y;  y = y + hintH
    lay.cardH = y + CARD_PAD_Y

    local top = math.floor(ins.t + (game.vh - ins.t - ins.b - lay.cardH) / 2)
    lay.cardY = top
    for _, k in ipairs({ "head", "title", "what", "price", "boxes", "hint" }) do
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

function FullGame:commit(box)
    self.phase = "confirm"
    Sfx.play("accept")
    self.chosen = box
    self.confirmT = 0
end

-- YES takes no ink where it has no box: what lands there is ink on the page.
function FullGame:mark(x, y, quiet)
    local box = self.choice:boxAt(x, y)
    if box and (box.key ~= "yes" or self:buyable())
        and self.choice:mark(x, y, quiet) then
        return true
    end
    self.marks:add(x, y)
    return true
end

-- Returns "back" once, on the frame the card is done: answered NO, bought, or
-- left by the keyboard.
function FullGame:update(dt, game)
    self:layout(game)
    self.t = self.t + dt
    self.marks:update(dt)

    if self.back or Store.full() then return "back" end

    if self.phase == "waiting" then
        -- Still deciding, or come back without the book: cancelled, failed,
        -- declined. Then the question is asked again from a clean card.
        if not Store.pending[Store.FULL] then self:open() end
        -- Or accepted and waiting on a payment that clears later (cash at a
        -- shop, a parent's approval): nothing more for the card to do, and the
        -- book opens whenever the store says so.
        if Store.pending[Store.FULL] == "pending" then return "back" end
        return
    end

    if self.phase == "confirm" then
        self.confirmT = self.confirmT + dt
        if self.confirmT < CONFIRM then return end

        if self.chosen.key == "yes" and Store.buy(Store.FULL) then
            self.phase = "waiting"
            return
        end
        return "back"
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

function FullGame:keypressed(key)
    if key == "backspace" then
        self.back = true
        return
    end
    if self.phase ~= "asking" then return end
    if key == "1" and self:buyable() then
        self.choice:autoFill(self.choice.boxes[1])
    elseif key == "2" then
        self.choice:autoFill(self.choice.boxes[2])
    end
end

function FullGame:draw(game)
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

    -- Red, the canteen's heading: this is the counter, come out to meet you.
    Scribble.printBig(I18n.t(TITLE), lay.cx, lay.title, LABEL_SCALE, Palette.red,
        { shadow = Palette.blush, wobble = true, t = self.t, seed = 9 })

    love.graphics.setColor(Palette.ink)
    Font.printCentered(I18n.t(WHAT), lay.cx, lay.what)
    local price, color = self:priceLine()
    love.graphics.setColor(color)
    Font.printCentered(price, lay.cx, lay.price)

    local buyable = self:buyable() or self.chosen == self.choice.boxes[1]
    for i, box in ipairs(self.choice.boxes) do
        local open = i ~= 1 or buyable
        local color = open and Scribble.boxColor(box, self.chosen, self.confirmT)
            or Palette.graphite
        Scribble.printBig(Scribble.label(box), box.labelCx, lay.labelY,
            LABEL_SCALE, color,
            { shadow = Palette.paper, wobble = true, t = self.t, seed = 30 + i * 5 })
        if open then
            Scribble.drawBox(box, progress, color, 10 + i, 0)
            Scribble.drawMarks(box.marks, Palette.ink, self.seed, 0)
        end
    end

    if self.phase == "asking" then
        local armed = self.choice.armed ~= nil
        Scribble.printBig(I18n.t(self:prompt()), lay.cx, lay.hint, 1,
            armed and Palette.red or Palette.slate, { seed = 51 })
        if not Input.usingTouch and not armed then
            Scribble.printBig(I18n.t(KEYS), lay.cx, lay.hint + Font.height + 2, 1,
                Palette.graphite, { seed = 52 })
        end
    end
end

return FullGame
