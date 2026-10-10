-- A pushpin, driven into the page.
--
-- Every other tool is a brush: you hold the pointer down and a line grows under
-- it. This one is not drawn, it is *placed*. Tap the page and a pin drops on
-- that spot, and the landing punches a circle out of the horde -- one hit, big
-- enough to kill anything but the toughest thing in the game, and whatever
-- lives through it is pinned to the paper until the pin comes back out.
--
-- The fall is not a delay for its own sake. It is what turns the ring on the
-- page into a promise rather than a report: you can see where it is going to
-- land before it lands, and so can the blob walking out of it. A quarter of a
-- second is about eleven pixels of bat, which is what stops a tap on a moving
-- target from being a certainty.
--
-- **One row buys it off** (`instant` below, the VOLLEY in src/tools.lua), and it
-- is the only thing in the game that does. What it fuses in is a stapler, whose
-- entire cast is that there is nothing to wait out -- so the promise stops being
-- a promise and the crater becomes a report after all. The shock ring is then the
-- whole of the event rather than the end of it, which is why that ring exists
-- separately from the falling one and always did.
--
-- It lands once. There is no second tick, nothing to stand on and nothing to
-- walk into afterwards -- the pin is spent the moment it arrives, and what is
-- left on the page is a marker for how long the things around it stay still.
--
-- And then it comes back out. Once its hold is over a pin stands in the page for
-- a couple of seconds more and is pulled: it lifts off the paper the way it fell
-- onto it, run backwards, and breaks up on the way (`Pin:wither`). The clock is
-- the one its fused marks fade on -- a thread or a pool strung off a pin starts
-- ageing the frame the pin stops holding and is gone `tool.life` later
-- (Game:unstring) -- so the pin leaves the page with whatever it was holding up,
-- rather than standing on after its rails have faded as a post with nothing on it.
-- A pin with nothing strung off it keeps `STAND` instead, the same couple of
-- seconds. A long run's page used to keep every pin it was ever given; it read as
-- clutter long before it read as a record.
--
-- A pin that came down where the page already has one punches its crater and is
-- not kept at all (`FOOTPRINT` below, Game:dropCrowded): two pins inside each
-- other record one spot twice while reading as neither.

local Palette = require("src.palette")
local Sprites = require("src.sprites")
local pixelart = require("src.pixelart")
local util = require("src.util")

local Pin = {}
Pin.__index = Pin

local FALL = 0.28   -- seconds from the tap to the landing
local LIFT = 30     -- how far above the page it starts, in pixels
local SHOCK = 0.18  -- how long the ring stays inked after the landing
local STAND = 2     -- seconds a spent pin stays in the page when nothing was
                    -- strung off it to time its going by
local PULL = 0.35   -- the last stretch of that, spent coming back out
local POINT = 2     -- slack, in pixels, on landing the point itself on a body:
                    -- the window is the enemy plus this, which through a
                    -- quarter-second fall is a shot you have to mean

-- How near another one already in the page is too near (Game:dropCrowded). A pin
-- driven inside this of one already there punches its crater and is then not
-- kept: the page has a pin at that spot and does not need two drawings of it.
--
-- Five, against a head seven across sitting seven pixels up its own shaft
-- (Sprites.pin) -- so two pins the width of a head apart both stay, and two
-- close enough for the heads to be one shape do not. Smaller than the staple's,
-- which is the shape of the two drawings rather than anything about the tools:
-- a crown is wide and flat and a pin is a dot on a stick.
Pin.FOOTPRINT = 5

-- `driven` is a pin that was not tapped: it arrives already through the paper,
-- carried there on the end of a compass leg (the SPINDLE, src/tools.lua). There
-- is no fall, because there was nothing to aim -- the arm went where it went and
-- the point was in front of it the whole way -- and there is no landing either,
-- so `land` is never called and no second crater is punched out of a page the rim
-- has already swept. What is left is the half of this file that was always about
-- afterwards: a pin standing in the page for as long as it holds, and then for a
-- couple of seconds more.
--
-- It also never shows the shock ring, which is the one thing that would have read
-- `def.radius` -- the crater's width. A driven pin has no crater, so the fused
-- row does not write a radius down and nothing here goes looking for one.
--
-- **`def.instant` is the other half of that idea and not the same half.** A driven
-- pin was never tapped and never lands; an instant one is tapped like any other
-- and lands like any other, it just has nothing to fall. So `landed` stays false
-- here and the landing happens the ordinary way one frame -- in fact zero frames
-- -- later: Game:updateDrawing runs immediately before Game:updateDrops, so a pin
-- tapped with no fall punches its crater inside the same `Game:update` that
-- created it, and there is never a frame on which it is drawn in the air. Which
-- means the two branches below that divide by FALL are unreachable for it, and
-- would give t = 1 -- a pin at rest on the page -- if they ever were reached.
function Pin.new(def, x, y, driven)
    return setmetatable({
        def = def,
        x = x, y = y,
        fall = (driven or def.instant) and 0 or FALL,
        age = 0,
        shock = 0,
        landed = driven or false,
    }, Pin)
end

-- Everything inside the circle at once: one hit each, and one chance to stick.
-- Backwards, because a kill takes an enemy out of the list underneath us.
function Pin:land(game)
    local def = self.def

    -- Paper fibres off the puncture, then whatever the circle caught.
    game.particles:burst(self.x, self.y, 9, Palette.graphite)

    -- The point bites first -- an upgrade. Not the nearest thing in the
    -- crater: the one body the point itself came down on, which is what makes
    -- it a level about aim rather than a bigger number.
    local pointTarget
    if def.point then
        local best
        for _, e in ipairs(game.enemies) do
            local dx, dy = e.x - self.x, e.y - self.y
            local d = dx * dx + dy * dy
            local reach = e.radius + POINT
            if d < reach * reach and (not best or d < best) then
                best, pointTarget = d, e
            end
        end
    end

    local caught, kills = 0, 0
    local survivors = {}
    for i = #game.enemies, 1, -1 do
        local e = game.enemies[i]
        local dx, dy = e.x - self.x, e.y - self.y
        local reach = def.radius + e.radius

        if dx * dx + dy * dy < reach * reach then
            caught = caught + 1
            game.particles:burst(e.x, e.y, 2, Palette.red)
            local hit = def.damage
            if e == pointTarget then
                -- Announced like the pencil's crit, and for its reason: a big
                -- number nobody saw land is indistinguishable from a bug.
                hit = hit * def.point
                game.particles:crit(e.x, e.y)
            end
            if e:hurt(hit) then
                kills = kills + 1
                game:killEnemy(i)
            else
                survivors[#survivors + 1] = e
                if e:freeze(def.freeze) then
                    -- Only the ones still standing get held, and only the
                    -- first time each -- the same splash of blue the
                    -- gluestick spends.
                    game.particles:burst(e.x, e.y, 3, Palette.sky)
                end
            end
        end
    end

    -- What the crater killed drives the point deeper -- the last level. The
    -- landing is the game's one instantaneous area hit, so it is the one
    -- place a crowd can be converted into depth: every kill under the circle
    -- is weight behind the point, and the survivors take it as a second hit.
    -- A pin dropped on a lone skull changes nothing at all -- the exception
    -- to "the tank walks out" has to be earned through the crowd around it.
    if def.drive and kills > 0 then
        local extra = kills * def.drive
        for _, e in ipairs(survivors) do
            game.particles:burst(e.x, e.y, 2, Palette.red)
            if e:hurt(extra) then
                -- By identity: the walk above already reshuffled the list.
                game:killEnemyAt(e)
            end
        end
    end

    -- A crater caught full gives a slice of its price back -- an upgrade.
    -- Paid on how many were under the circle, not how many died, and off the
    -- price this pin actually cost (Game:dropOne stamps it): the reward is
    -- for waiting until the crowd had bunched, and a panic pin into two bats
    -- pays full fare.
    if def.refund and caught >= def.refund.count and self.price then
        game.ink = math.min(game.loadout.stats.inkMax,
            game.ink + self.price * def.refund.frac)
        game.particles:burst(self.x, self.y, 4, Palette.blue)
    end
end

-- Returns false once it has finished holding. It is not thrown away then --
-- the game moves it to the spent pile, where only `wither` is asked of it -- so
-- this is "I hold nothing any more" rather than "remove me".
function Pin:update(dt, game)
    if not self.landed then
        self.fall = self.fall - dt
        if self.fall <= 0 then
            self.landed = true
            self.shock = SHOCK
            self:land(game)
            -- Only ever set by Game:dropOne, on the one path this file cannot
            -- see the gesture that placed it (src/multikill.lua).
            if self.heldMultikill then game.multikill:release() end
        end
        return true
    end

    self.age = self.age + dt
    self.shock = math.max(0, self.shock - dt)
    return self.age < self.def.life
end

-- How long a spent pin stays in the page, pull included. Off the row when the row
-- strings (Game:dropOne stamps `tool` only then), because its threads and pools
-- fade on that row's `life` from this same frame and the pin should go with them;
-- never shorter than the pull itself, because the CRATER's rubber pool has a life
-- of nothing and a pin still has to be seen coming out.
function Pin:stays()
    local life = self.tool and self.tool.life or STAND
    return math.max(PULL, life)
end

-- The spent pile's clock (Game:updateDrops). Returns false once the pin is out of
-- the paper and can be thrown away.
function Pin:wither(dt)
    self.gone = (self.gone or 0) + dt
    return self.gone < self:stays()
end

-- How far through being pulled it is, 0 standing to 1 out.
function Pin:pulled()
    if not self.gone then return 0 end
    local p = (self.gone - (self:stays() - PULL)) / PULL
    return math.max(0, math.min(1, p))
end

-- The ring and the shadow belong to the page, so they are drawn with the ink
-- and under everything standing on it -- a shadow painted over the top of the
-- crowd it is falling into would be a shadow on the crowd. The ring starts as
-- the pencil circle the pin is aimed at, and the landing inks it and throws it
-- outwards.
--
-- Named for what it is rather than what it looks like, because the stapler
-- answers the same call with a crease instead of a ring: both are things that
-- were tapped onto the page, and the game draws them from one list.
function Pin:drawMark()
    if not self.landed then
        local t = 1 - self.fall / FALL

        love.graphics.setColor(Palette.graphite)
        pixelart.circleOutline(self.x, self.y, self.def.radius)

        -- Closing up under the pin: the pin's own height off the page cannot
        -- say how far there is left to fall on its own.
        local w = 1 + math.floor(t * 4)
        love.graphics.rectangle("fill",
            math.floor(self.x) - math.floor(w / 2), math.floor(self.y), w, 1)
    elseif self.shock > 0 then
        local out = math.floor((1 - self.shock / SHOCK) * 3)
        love.graphics.setColor(Palette.slate)
        pixelart.circleOutline(self.x, self.y, self.def.radius + out)
    elseif self:pulled() > 0 then
        -- The fall's dash, run backwards: it opens back up under the pin as the
        -- point leaves the paper, and is gone with it.
        local w = 1 + math.floor((1 - self:pulled()) * 4)
        love.graphics.setColor(Palette.graphite)
        love.graphics.rectangle("fill",
            math.floor(self.x) - math.floor(w / 2), math.floor(self.y), w, 1)
    end
end

-- The pin itself is an object above the paper rather than a mark on it, so it
-- is drawn with the things that stand on the page.
function Pin:draw()
    local y = self.y

    if not self.landed then
        -- Squared, so it gathers speed on the way down instead of drifting in.
        local t = 1 - self.fall / FALL
        y = self.y - LIFT * (1 - t * t)
    end

    -- Pulled back out at the end of its stay: up off the page, squared like the
    -- fall so it comes free slowly and then goes, and dropping out frame by frame as
    -- it goes -- the dither every mark leaves by, a whole sprite at a time, since
    -- there is no alpha to fade it with. Keyed on the pin's own spot as well as the
    -- clock, so a row of pins pulled together does not blink in step.
    local p = self:pulled()
    if p > 0 then
        y = y - math.floor(LIFT * 0.4 * p * p)
        if util.hash01(math.floor(self.gone * 24), self.x + self.y * 0.37, 53) < p then
            return
        end
    end

    -- Until then it does not fade as its hold runs out: a mark on paper fades, and
    -- this is not a mark -- it is a thing stuck through the page. What the hold is
    -- doing is read off the enemy instead, which stops moving and grows a blue
    -- shadow.
    love.graphics.setColor(1, 1, 1)
    Sprites.pin:draw(self.x, y)
end

return Pin
