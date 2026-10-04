-- The phone buzzing in your hand. One event shakes it today -- something landing
-- on you (Player:hurt) -- and that is deliberate: a buzz is the loudest thing
-- the game can say, louder than any sound, because it is said to the hand
-- rather than to the ear, and a game that buzzes for everything has turned the
-- one signal you cannot miss into a texture you stop noticing. Being hit is the
-- thing you most need to know about and the one the screen is worst at telling
-- you, since your eyes are on whatever is chasing you and not on the bar in the
-- corner.
--
-- It owns its setting the way src/sfx.lua owns the volumes and src/damage.lua
-- owns what the page says about a hit: `Haptics.on` is stepped by the settings
-- page and saved by src/options.lua, and this file is the only one that reads
-- it. Off is a promise, not a hint -- with it off, `pulse` returns before it
-- asks the system for anything.
--
-- On a desktop there is nothing to shake and `love.system.vibrate` does
-- nothing, so this costs a desktop build nothing and needs no guard of its own
-- beyond being asked through `pcall`: a platform that answers the call with an
-- error is a platform without a motor, not a run that should stop.

local Haptics = {}

-- On by default. A phone that buzzes when you are hit is what the genre has
-- taught a player to expect, and the setting is there for the player who does
-- not want it -- not for the one who has to go and find it to get it.
Haptics.on = true

-- The shortest and longest buzz a hit is worth, in seconds. Read against the
-- same share of the bar the page's knock is (Player:hurt), so a graze is a tick
-- and a hit that takes a third of you is a thump -- the knock and the buzz are
-- one event and say the same size. Both are short on purpose: a motor spun up
-- for a tenth of a second is already a long buzz in the hand, and the hit's
-- invulnerability window is the rate limit, so a crowd chewing on you is a
-- stutter rather than a drone.
Haptics.SOFT, Haptics.HARD = 0.025, 0.07

function Haptics.pulse(seconds)
    if not Haptics.on then return end
    if love.system and love.system.vibrate then
        pcall(love.system.vibrate, seconds)
    end
end

-- A hit, sized by how much of the bar it took (0..1).
function Haptics.hit(share)
    Haptics.pulse(Haptics.SOFT + (Haptics.HARD - Haptics.SOFT) * share)
end

return Haptics
