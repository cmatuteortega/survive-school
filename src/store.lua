-- The shop: what the book sells for real money, and the one place that knows.
--
-- **What is sold is pages, and only pages** (ROADMAP.md, README **Ads and the
-- shop**). Every lesson the timetable's ladder holds shut (`Collection.rungs`)
-- can be opened outright, and THE WHOLE BOOK opens all of them and turns the ads
-- off. Nothing here sells coins, perks, heroes or courses: those are what the
-- purse is for (src/purse.lua), and a book whose counter could be skipped with a
-- card would be a book whose afternoons were for sale. The ladder stays exactly
-- as it is, so every page bought here can still be earned by playing.
--
-- **The store itself is love-iap** (src/iap.lua, vendored; its Android half is
-- added to the APK by its own action in .github/workflows/android.yml). It keeps
-- what is owned in `iap.txt` beside the records, answers offline and on the first
-- frame, and syncs with Play at every launch -- which is how a reinstall or a new
-- phone gets its pages back, and how a refund takes one away. This file is the
-- game's words about it: which ids exist, what a bought id opens, and the price
-- made fit to print.
--
-- Prices are read from the store and never written down. Until it has answered
-- a row has no price and no box, and the counter says the shop is closed.
--
-- With the dev row showing (src/dev.lua) and no real store, love-iap's own mock
-- answers instead -- every product at a dollar, every purchase landing at once --
-- so the counter can be played through on a desktop. What the mock "sells" is
-- kept in the same file; delete `iap.txt` to hand it back.

local iap = require("src.iap")
local Subjects = require("src.subjects")
local Font = require("src.font")
local Dev = require("src.dev")

local Store = {}

-- The one product that is not a page.
Store.EVERYTHING = "everything"

-- Lesson key -> product id, for every lesson after the first: the same rule
-- `Collection.rungs` is built on, read off the same list, so a lesson added to
-- src/subjects.lua is on sale without a line here. (The ids are the store's and
-- cannot change once a product is live in the console.)
Store.lessons = {}
Store.ids = {}
for i, sub in ipairs(Subjects.list) do
    if i > 1 then
        local id = "lesson_" .. sub.key
        Store.lessons[#Store.lessons + 1] = { key = sub.key, id = id, sub = sub }
        Store.ids[#Store.ids + 1] = id
    end
end
Store.ids[#Store.ids + 1] = Store.EVERYTHING

-- Ids with a purchase sheet open or a payment still clearing: no box on the row
-- until the store has said how it ended.
Store.pending = {}

function Store.start()
    local products = {}
    for _, id in ipairs(Store.ids) do products[#products + 1] = { id = id } end

    Store.pending = {}
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
    iap.update()
end

-- Whether a real (or mock) store is answering.
function Store.available()
    return iap.available()
end

-- Owned outright, or covered by THE WHOLE BOOK.
function Store.owns(id)
    if iap.owns(id) then return true end
    return id ~= Store.EVERYTHING and iap.owns(Store.EVERYTHING)
end

-- Whether a lesson has been bought open (src/collection.lua asks).
function Store.opens(key)
    return Store.owns("lesson_" .. key)
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

function Store.canBuy(id)
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
