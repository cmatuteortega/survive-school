-- The settings page's COMFORT tab, apart from the damage numbers (which are
-- src/damage.lua's): whether a knock shakes the page, and whether things blink
-- fast. Both default on, since the shake and the blinks are how this game says
-- a thing hit you or is about to, and both are for the player they hurt.
--
-- **The shake** is one flag `Camera` reads where it works out the knock, so a
-- knock still happens -- it still runs out its time, the alarm clock still rings
-- for as long -- and the page simply does not move. Things that shake *on* the
-- page (a boss winding up, a wreck coming apart) are left alone: they are small,
-- they are the thing being told, and the page staying still under them is what
-- this row is for.
--
-- **The flashing** is every blink in the game going through `Comfort.rate` or
-- `Comfort.period` -- a blink's steps a second, or its seconds a step -- which with
-- the row on hold it to `CALM_RATE`. Four steps a second is two flashes a second,
-- under the three a second the photosensitivity guidelines draw the line at, and
-- still quick enough to read as a warning rather than as a colour. Nothing is
-- taken out: a warning that blinked still blinks, only slower, so the row costs a
-- player who needs it no information at all. A blink is anything that turns a
-- colour or a sprite on and off over and over; a single flash on a hit is not one
-- and is left alone, and so is a jiggle, which moves rather than flashes.

local Comfort = {}

Comfort.shake = true
Comfort.calm = false

local CALM_RATE = 4

-- Steps a second, slowed to CALM_RATE with the row on: `floor(t * rate) % 2`.
function Comfort.rate(rate)
    if Comfort.calm and rate > CALM_RATE then return CALM_RATE end
    return rate
end

-- The same thing for a blink kept as seconds a step.
function Comfort.period(period)
    if Comfort.calm and period < 1 / CALM_RATE then return 1 / CALM_RATE end
    return period
end

return Comfort
