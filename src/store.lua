-- The shop: what the book sells for real money, and the one place that knows.
--
-- **Two things are sold, one after the other** (ROADMAP.md, README **Ads and
-- the shop**). The book is free to open at SCIENCE and free to read there for as
-- long as you like; every other page, and every line of the library that has to
-- be earned, is the FULL GAME. Bought, the book is the book this whole project
-- describes -- the ladder opens the pages (`Collection.rungs`) and the quests
-- open the lines (`Collection.gates`), exactly as they always have. Then, and
-- only then, THE WHOLE BOOK is on sale: every page and every line opened on the
-- spot, and the ads turned off. It skips the ladder and the quests and nothing
-- else -- the homework (src/challenges.lua) still counts only what was earned.
--
-- Nothing here sells coins, perks, heroes or courses: those are what the purse
-- is for (src/purse.lua), and the canteen's counter is open to a free book
-- exactly as it is to a bought one.
--
-- **The store itself is love-iap** (src/iap.lua, vendored; its Android half is
-- added to the APK by its own action in .github/workflows/android.yml). It keeps
-- what is owned in `iap.txt` beside the records, answers offline and on the first
-- frame, and syncs with Play at every launch -- which is how a reinstall or a new
-- phone gets its book back, and how a refund takes it away. This file is the
-- game's words about it: which ids exist, what a bought id opens, and the price
-- made fit to print.
--
-- Prices are read from the store and never written down. Until it has answered
-- a row has no price and no box, and the counter says the shop is closed.
--
-- **Only a phone has a shop** (`Store.sold`). On a computer the game is bought
-- whole, before it is ever opened, from whoever sells the download: there is
-- nothing left to buy inside it, so the store is never started, the book is the
-- full game from its first launch, and the padlock, the full game's card and the
-- canteen's SHOP section are not on the page at all. It is the full game and not
-- THE WHOLE BOOK -- the ladder and the quests still open the pages and the lines,
-- because they are the game and not a paywall; the whole book only ever sold a
-- way round them. No ads either: there is no SDK off a phone (src/ads.lua), and
-- `noAds` stays false so the two offers are not handed out free in their place.
--
-- On a phone with the dev row showing (src/dev.lua) and no real store, love-iap's
-- own mock answers instead -- every product at a dollar, every purchase landing at
-- once. What the mock "sells" is kept in `iap.txt`; delete it to hand it back.

local iap = require("src.iap")
local Font = require("src.font")
local Dev = require("src.dev")

local Store = {}

-- The two products. The ids are the store's and cannot change once a product is
-- live in the console.
Store.FULL = "full_game"
Store.EVERYTHING = "everything"
Store.ids = { Store.FULL, Store.EVERYTHING }

-- Whether this build sells anything: a phone's. Read once at load, before any
-- screen lays itself out round the shop (src/canteen.lua's sections).
local system = love.system.getOS()
Store.sold = system == "Android" or system == "iOS"

-- Ids with a purchase sheet open or a payment still clearing: no box on the row
-- until the store has said how it ended.
Store.pending = {}

function Store.start()
    Store.pending = {}
    if not Store.sold then return end

    local products = {}
    for _, id in ipairs(Store.ids) do products[#products + 1] = { id = id } end

    iap.init({
        products = products,
        mock = Dev.showing(),
        -- A page is granted by being owned, which love-iap records itself before
        -- it acknowledges the purchase; there is nothing else to save.
        onPurchase = function(id)
            Store.pending[id] = nil
        end,
        onPending = function(id) Store.pending[id] = "pending" end,
        onFail = function(id) Store.pending[id] = nil end,
    })
end

function Store.update()
    if Store.sold then iap.update() end
end

-- Whether a real (or mock) store is answering.
function Store.available()
    return Store.sold and iap.available()
end

-- Owned outright. THE WHOLE BOOK is only ever sold on top of the full game, but
-- a refund of the one and not the other is the store's to decide, so owning it
-- counts as owning the full game too rather than leaving a book with every line
-- open and its pages shut.
function Store.owns(id)
    if iap.owns(id) then return true end
    return id == Store.FULL and iap.owns(Store.EVERYTHING)
end

-- Whether the book is the full game: every page on the ladder and every quest
-- live (src/collection.lua asks). Without it the book is SCIENCE and the lines
-- nobody has to earn. Always, off a phone: the download was the purchase.
function Store.full()
    return not Store.sold or Store.owns(Store.FULL)
end

-- Whether THE WHOLE BOOK is bought: every page and line open outright
-- (src/collection.lua asks).
function Store.everything()
    return iap.owns(Store.EVERYTHING)
end

-- Whether the ads are off (src/ads.lua asks).
function Store.noAds()
    return iap.owns(Store.EVERYTHING)
end

-- The price as the store formatted it, cut down to what the 3x5 face can draw
-- (`Font.clean`), or nil until the store has said.
function Store.price(id)
    local p = iap.price(id)
    if not p or p == "" then return nil end
    return Font.clean(p)
end

-- The widest price on sale, for the canteen's price column -- measured at what
-- could stand in it once the store has answered, never at a guess.
function Store.widestPrice()
    local w = 0
    for _, id in ipairs(Store.ids) do
        local p = Store.price(id)
        if p then w = math.max(w, Font.width(p)) end
    end
    return w
end

-- THE WHOLE BOOK is not for sale to a book that is not the full game yet: it is
-- the second purchase, and the counter does not offer it until the first is made.
function Store.canBuy(id)
    if id == Store.EVERYTHING and not Store.full() then return false end
    return Store.available() and not Store.owns(id) and not Store.pending[id]
        and Store.price(id) ~= nil
end

-- Opens the store's own purchase sheet. Nothing is owned until the store says
-- so, a frame or a minute later; true only means the sheet was asked for.
function Store.buy(id)
    if not Store.canBuy(id) then return false end
    Store.pending[id] = "buying"
    iap.buy(id)
    return true
end

function Store.restore()
    iap.restore()
end

return Store
