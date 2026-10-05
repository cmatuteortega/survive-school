local Palette = require("src.palette")
local Sprites = require("src.sprites")
local Walls = require("src.walls")
local Sfx = require("src.sfx")
local Eyeball = require("src.eyeball")
local EyeBoss = require("src.eyeboss")
local Metronome = require("src.metronome")
local Stamp = require("src.stamp")
local Dictionary = require("src.dictionary")
local Dice = require("src.dice")
local DiceBoss = require("src.diceboss")
local StillLife = require("src.stilllife")
local Atom = require("src.atom")
local AtomBoss = require("src.atomboss")
local Piggy = require("src.piggy")
local PiggyBoss = require("src.piggyboss")
local Tesseract = require("src.tesseract")
local TesseractBoss = require("src.tesseractboss")
local pixelart = require("src.pixelart")
local util = require("src.util")

local Enemy = {}
Enemy.__index = Enemy

-- Every point of damage that has ever gone through Enemy:hurt, added up. It
-- belongs to the module and not to a monster -- nothing on an enemy reads it --
-- and there is exactly one thing in the game that wants it: the bandaid takes a
-- cut of what the run's own weapons dealt, and the honest way to know that number
-- is to read this either side of the passes that are the run's fire (Game:update,
-- Loadout:mend). Which works because every hit in the game arrives through one
-- door, so there is one place to count and nothing to keep in step.
Enemy.dealt = 0

local WALL_LOOK = 7  -- how far outside its clearance a wall starts to be felt
local SLIDE_HOLD = 0.9 -- how long a chosen way round a wall is kept to
local SLIP_CARRY = 0.5 -- how long footing stays lost after leaving the wax

-- What a hit looks like on the thing that took it. Two things happen at once
-- and they are one effect: the body blows out to paper and drops back through
-- blush, wearing a red rim for the whole of it, and it kicks a few pixels
-- backwards and slides home again.
--
-- Neither of them is worth a number on the row (Enemy.types). A hit on a paper
-- clip and a hit on the boss are the same event -- something landed -- and a
-- boss that flinched less would read as a boss that was not hit rather than as
-- a boss that is heavy. What says how much it was worth is the number the page
-- throws (src/damage.lua); this says *that* it happened, and it says it the
-- same way every time so it can be read out of the corner of an eye in a crowd
-- of two hundred.
--
-- The whole thing is over in about a tenth of a second, which is the point: at
-- the rate this game hands out hits, anything longer and a thing under sustained
-- fire never comes back off the ramp, and a permanent white monster with a red
-- edge is not a hit -- it is a palette swap.
local HIT_FLASH = 0.14      -- how long the silhouette is lit for
local HIT_WHITE = 0.06      -- of which this much is the blown-out paper stage
local HIT_BUMP = 3          -- how far back it is knocked, in pixels
local HIT_BUMP_TIME = 0.12  -- and how long it takes to slide home

-- How long out of the sun before what it has already soaked up is forgotten.
-- Comfortably longer than the sun's own burn tick, so a thing standing under
-- the disc goes on adding up between one burn and the next, and shorter than a
-- walk across the page, so crossing a lit corner twice in a run is not the same
-- as standing in one.
local SOAK_COOL = 1.2

-- How long a `turns` body takes to swing one view (a sixteenth of a turn) round
-- towards you. Stepped through the views in between rather than snapped, so a
-- whistle you run round turns to follow you instead of jumping, and quickly
-- enough that half a turn is under a third of a second.
local TURN_STEP = 0.02

-- The sound a whistle makes, drawn: two rings going out from it over BLARE_TIME,
-- from the body's own radius to BLARE_REACH past it. A mark rather than a hit --
-- what hurts is the notes it throws (Game:updateWhistle) -- so it is red for
-- "theirs" and is gone before the notes have got anywhere.
local BLARE_TIME = 0.35
Enemy.BLARE_TIME = BLARE_TIME
local BLARE_REACH = 34

-- Add a row here to add a monster; the spawner picks from this table by name.
-- Every row walks at the player, and every block below is a way of not *only*
-- doing that. None of them is a special case anywhere else in the game: each is
-- read in one place, and a row without it is the row this game shipped with.
--
-- **`name`** is the one field on a row that nothing in a run ever reads. It is
-- what the *book* calls the thing, for the one screen that names monsters out
-- loud (src/challenges.lua, where a row is one body count a homework list is
-- kept of) -- so a new monster brings its own line of homework with it and there
-- is no second list of what the horde is made of to keep in step. Written here
-- in English, like every other string in the game, and translated at the draw
-- (src/i18n.lua).
--
-- **`shot`** makes it a shooter. It still walks at the player like the rest, but
-- every `every` seconds, if the player is within `range`, it spits a pellet
-- (Game:updateEnemyShots) that flies at `speed` and hits for `damage`. `spread`
-- and `arc` make it a volley: `spread` pellets fanned across `arc` radians
-- instead of the one straight down the line.
--
-- **`keep`** stops it walking all the way in. Past `at` it closes like anything
-- else; inside `at` it circles; inside `back` it retreats. Only a shooter has any
-- use for one, and what it buys is the difference between a shooter you meet
-- because it came to you and a shooter you have to go and get (Enemy:update).
--
-- **`charge`** makes it commit. Every `every` seconds, with the player inside
-- `range`, it stands still for `wind` seconds wearing a red outline, then runs
-- `time` seconds down the heading it locked *at the start of the wind* at
-- `speed`, then stands `rest` seconds getting its breath. The heading is stale
-- on purpose: the whole attack is dodgeable by stepping aside during the wind,
-- and it is the only thing in the game that asks for a decision inside half a
-- second rather than over several.
--
-- **`split`** makes it two problems. When it dies it leaves `count` of `into`
-- thrown `spread` pixels out (Game:splitEnemy), carrying the parent's own
-- difficulty scale rather than the run's current one -- what came off a monster
-- is as hard as the monster was. `blown` is the one exception and is optional:
-- what a *blow-up* of the row leaves instead, at the run's own scale rather than
-- the parent's, because a child scaled up three times over stops being the thing
-- the row named.
--
-- **`burst`** makes killing it cost something. Where it died, everything inside
-- `radius` takes `damage` -- which is the player and nobody else, since a burst
-- that thinned the crowd would make these a *reward* -- and `puddle` is left
-- lying on the page (src/puddle.lua), so the ground the fight was on stops being
-- ground. Same bargain the boss's tear makes: it hits on the way and wets where
-- it stops.
--
-- **`knock`** and **`hold`** are what a shove and a glueing are worth against
-- it, both 1 for everything ordinary. They went in for the boss -- one that can
-- be bowled across the page by a pin is one you never have to look at -- and the
-- grin is the horde-sized version of the same idea: something the crowd-control
-- half of a build cannot fully answer.
--
-- A handful more fields turn a row into a boss: `boss` (never despawns, never
-- shoved out of the way by the crowd, and ends the run when it dies), `title`
-- (its name under the HUD's bar), `call` (the line the page says as it walks
-- on), `pupil` (an eye that watches you: the body is a ball painted a pixel at a
-- time and turned to face the player, with a gait of its own --
-- src/eyeball.lua), `turns` (a body drawn from a ring of baked views, the one
-- facing you -- 3dmethod.md), `trail` (a wet blot dropped behind it as it
-- walks), `tears` (the same wet thrown rather than walked, three ways --
-- Game:updateTears), `attacks` (the moves it picks between, read by its brain
-- and nowhere else -- src/eyeboss.lua), `whistle` (the P.E. boss's four
-- calls -- Game:updateWhistle), `metronome` (the MUSIC boss's tempo and the
-- three moves it plays on it -- src/metronome.lua, which is its brain the way
-- src/eyeboss.lua is the eye's), `dice` (the MATHS boss: a die painted a
-- pixel at a time like the eye, src/dice.lua, thrown and read by its brain,
-- src/diceboss.lua), `stamp` (the FINANCE boss's leaps and the three moves it
-- stamps the ledger with -- src/stamp.lua, a brain in the same socket),
-- `dictionary` (the GRAMMAR boss's hops and the three moves it makes off the
-- paired ruling -- src/dictionary.lua, the same socket again), `still` (the
-- ART boss: three plaster solids painted a pixel at a time and lit by a lamp
-- that moves, src/plaster.lua, with its brain in the same socket,
-- src/stilllife.lua) and
-- `poses` (a `turns` body baked in more than one pose, each a ring of views,
-- the brain saying which through `pose` -- art/stamp.py). Every one of them but
-- `boss` is optional and
-- read in one place, so a second boss is a row that picks which of them it is
-- made of.
--
-- The box the fight happens in is not one of them, and deliberately: an arena is
-- a fact about the *fight* rather than about the monster, so the spawner opens it
-- when it sends the boss (src/arena.lua) and nothing in this table knows.
--
-- Every *distance* written in a block above -- a burst radius, a pellet's `hit`,
-- a puddle's radius, a `spread` -- is the number for an ordinary arrival and is
-- multiplied by `reach` for a champion or a blow-up (Spawner:scale, Enemy.new).
-- Every *time* and every *range* is the number on the row for all three: a giant
-- eye fires a bigger pellet from the same distance on the same beat.
Enemy.types = {
    blob  = { name = "BLOB", sprite = "blob",  hp = 4,  speed = 20, radius = 4, damage = 6,  xp = 1, shadow = 6 },
    bat   = { name = "BAT", sprite = "bat",   hp = 2,  speed = 38, radius = 4, damage = 4,  xp = 1, shadow = 7 },
    skull = { name = "SKULL", sprite = "skull", hp = 12, speed = 15, radius = 5, damage = 12, xp = 3, shadow = 8 },
    -- The wad: the one thing on the page that arrives all at once.
    --
    -- Everything else in this table is answered by *position over seconds* --
    -- you walk away from a skull, you put damage in front of a crowd, you step
    -- out of a lane of tears. That is the whole game and it is a good game, and
    -- it means nothing here has ever asked the player to react. The wad does,
    -- once every three seconds or so, and half a second is all it gives you.
    --
    -- The numbers are all one bargain: it is slower than a blob while walking
    -- (18) so it is never a chase, and nearly three times the player while
    -- dashing (165) so the dash is never a chase either -- it is a line drawn
    -- across the page that you are either standing on or not. 10 damage is
    -- deliberately just under the skull's 12: getting hit by one is the worst
    -- thing an ordinary monster does to you short of a skull walking into you,
    -- and it should be, because it is the only one you could have avoided.
    --
    -- 6hp so that the answer to a wad you *saw* coming is often just to kill it
    -- during the half second it is standing still telegraphing.
    wad = { name = "WAD", sprite = "wad", hp = 6, speed = 18, radius = 4, damage = 10, xp = 3, shadow = 7,
            charge = { range = 96, every = 2.9, wind = 0.5, speed = 165,
                       time = 0.42, rest = 0.8 } },
    -- The blot: a blob that is two fights.
    --
    -- Almost everything a build in this game buys is *area* -- the sword arc,
    -- the bomb, the sun, the storm, the beam -- so area is not really a choice,
    -- it is the default, and nothing on the page had ever made the player feel
    -- that. A blot killed by a stroke that also caught its three drops is a
    -- blot that cost one swing; a blot killed by a single pellet is three more
    -- things walking at you. That is the entire design.
    --
    -- 11hp and 16 speed puts it between a skull and a blob to fight and slower
    -- than either to arrive, because the drops are the real bill and it should
    -- not also be quick. It pays 1xp itself and lets the drops carry the rest,
    -- so ignoring one is not a way to be paid for it.
    -- `split.blown` is what a *blow-up* of it leaves instead, and a blot is the
    -- only row that has ever wanted one. Three times the size, the drops it would
    -- otherwise leave come off at three times the size too -- and a drop that
    -- wide is not a drop any more, it is a body wider than a grin with 2 health,
    -- which reads as debris rather than as three more fights.
    --
    -- What a giant blot leaves instead is three *blots*, ordinary ones, which then
    -- do what a blot does. So the row says the same sentence at both sizes -- this
    -- thing is two fights -- and the enormous one says it twice: one giant becomes
    -- three blots becomes nine drops, and the area you needed the first time you
    -- had to answer this is the area you need three times over.
    --
    -- It cannot run away with itself, and that is the whole reason the field names
    -- what a *blow-up* leaves rather than what a blot leaves: the children arrive
    -- at the ordinary scale, so Enemy:isBlown is false on every one of them and
    -- the second generation takes the plain `into`. Three levels, never four.
    blot = { name = "BLOT", sprite = "blot", hp = 11, speed = 16, radius = 5, damage = 8, xp = 1, shadow = 9,
             split = { into = "drop", count = 3, spread = 6, blown = "blot" } },
    -- The drop: never spawned, only fallen off. Two health, so anything at all
    -- clears one, and 30 speed so the three of them are a spread rather than a
    -- second blot -- they get *past* you, which is what makes a blot killed in
    -- the wrong place a mistake you are still living with a moment later.
    drop = { name = "DROP", sprite = "drop", hp = 2, speed = 30, radius = 3, damage = 4, xp = 1, shadow = 5 },
    -- The bulb: the only enemy whose death is worse than its life.
    --
    -- Every build in this game ends up killing the crowd at arm's length --
    -- that is what an aura, an orbit and a swing all are -- and until now there
    -- was no cost to it whatsoever. A bulb makes *where* you clear the crowd a
    -- decision: 14 damage is the hardest single hit anything short of the boss
    -- lands, and 26 is comfortably wider than any melee radius in the game, so
    -- one that dies at your feet is a hit you take.
    --
    -- It bursts when it *dies*, not on a fuse of its own, and that is the whole
    -- rule -- one door (Game:killEnemy), no second timer to read, and a chain
    -- when one takes another with it. The player's invulnerability window is
    -- what keeps a chain from being fatal (Player:hurt): four going off together
    -- is one hit, exactly as wading through four puddles is.
    --
    -- 26 speed, quicker than a blob, because a bulb that never reaches you is a
    -- bulb you only ever kill at range, and then it is not a decision. 8hp so it
    -- is easy to kill early and easy to kill by accident late, which is the joke.
    bulb = { name = "BULB", sprite = "bulb", hp = 8, speed = 26, radius = 5, damage = 5, xp = 2, shadow = 8,
             burst = { radius = 26, damage = 14,
                       puddle = { radius = 11, life = 4.5, damage = 5 } } },
    -- The grin: the one the crowd control cannot answer.
    --
    -- Half of what a built run does to the horde is *move* it -- the pushpin
    -- and the ruler shove, the spiral lures, the gluestick and the staple hold,
    -- the rubber launches -- and against everything in this table those tools
    -- have always worked completely. `knock` and `hold` were written for the
    -- boss for exactly that reason; this is the horde-sized version, and it is
    -- the only row here that is a *fact about the player's build* rather than
    -- about a monster's own attack.
    --
    -- 0.25 and 0.45 rather than 0 either way, for the boss's reason: a tool
    -- that visibly does nothing is worse than one that does a little, and every
    -- level of the gluestick line should still buy something against it.
    --
    -- 34hp is nearly three skulls and 11 speed is the slowest thing in the game,
    -- which is the trade the whole row is built on: it can always be walked away
    -- from, and it can never be walked away from *cheaply*, because the page it
    -- is standing on is page you have given up. 16 damage is the hardest contact
    -- hit in the table -- the one thing you must not do is let the slow one
    -- catch you -- and 8xp is what three skulls' worth of work is owed.
    --
    -- Fourteen across and a 7px radius, which makes it the only enemy allowed to
    -- be bigger than the eye. Size is doing real work here: nothing about being
    -- unshovable can be *seen*, so the silhouette has to promise it before the
    -- first pushpin bounces off, and half a second of watching a build fail to
    -- move something is the worst possible way to learn a rule.
    grin = { name = "GRIN", sprite = "grin", hp = 34, speed = 11, radius = 7, damage = 16, xp = 8, shadow = 13,
             knock = 0.25, hold = 0.45 },
    eye   = { name = "EYE", sprite = "eye",   hp = 14, speed = 9,  radius = 6, damage = 10, xp = 4, shadow = 9,
              shot = { range = 100, every = 2.4, speed = 40, damage = 8 } },
    -- The bloodshot eye is the same body with the pupil gone red, and it is the
    -- one enemy that will not come to you.
    --
    -- It was an eye that walked in faster and fired more often, which made it a
    -- harder eye and not a different one: anything that clears its own melee
    -- radius -- which is most of what a build sells -- never had to think about
    -- either of them, because both delivered themselves into it. `keep` is the
    -- fix and it costs nothing but a heading (Enemy:update). It closes to 80,
    -- circles there, and backs off inside 56, so the pellets keep coming from a
    -- distance you have to *choose* to cross.
    --
    -- Which is why it is quick now -- 34, twice what it was. It is still well
    -- under the player's 58, so walking one down always works and always costs
    -- you the walk; that price is the whole design. The fire rate stayed where
    -- it was rather than rising with the range, because a shooter you are
    -- crossing a page to reach is already firing for longer.
    redeye = { name = "RED EYE", sprite = "redeye", hp = 14, speed = 34, radius = 6, damage = 10, xp = 6, shadow = 9,
              shot = { range = 110, every = 1.6, speed = 40, damage = 8 },
              keep = { at = 80, back = 56 } },
    -- The eye boss, which is the eye at four times across and the same idea
    -- taken seriously: it walks at you slower than you can walk away, it fires
    -- a fan rather than a pellet, and it wets the page behind itself so the
    -- ground you retreated over stops being ground. Every one of those is a
    -- thing you answer by moving, which is why it is slow -- a boss you cannot
    -- outrun would just be a big blob.
    --
    -- The hp is the one number here set by measurement rather than by design.
    -- A run holding every passive weapon at its last level puts about 30 damage
    -- a second into a *single* target -- far less than it does into a crowd,
    -- since most of what a build sells is area -- so 900, scaled to 1260 by the
    -- time the first one walks on (Game:enemyScale), is a fight of half a minute
    -- for a strong run and rather longer for one that drafted wide. That is the
    -- number to move if the fight is the wrong length; everything else about the
    -- boss is a design decision.
    --
    -- It is also why the eye is the one row the horde's health curve does not
    -- touch: that curve compounds by the minute and would have handed the first
    -- eye something over three thousand health, which is not a length anybody
    -- measured. `boss` on this row is what buys the exemption -- the spawner
    -- prices an eye per cycle instead (BOSS_HP_PER_CYCLE, src/spawner.lua), so
    -- the 1260 above is still the fight, and the second eye is 40% past it.
    bosseye = { name = "BOSS EYE", sprite = "bosseye", hp = 900, speed = 26, radius = 20, damage = 20,
              xp = 250, shadow = 34, boss = true, pupil = true, knock = 0.06, hold = 0.3,
              title = "THE EYE", call = "THE EYE IS OPEN",
              shot = { range = 190, every = 2.6, speed = 46, damage = 12, hit = 4,
                       spread = 5, arc = 1.05, drop = "red" },
              trail = { every = 0.5, gap = 9, radius = 12, life = 7, damage = 6 },
              -- The eye cries, and where a tear lands the page is wet.
              --
              -- The trail above is the boss denying you the ground it walked
              -- over, which is ground you chose to give it. The tears are the
              -- half of the same idea it does not have to walk to: they land
              -- where it is not, so the arena fills up from the middle as well
              -- as behind it, and a corner you were saving stops being a plan.
              --
              -- Three deliveries off one projectile, which is what keeps the
              -- fight varied without teaching three separate things. A tear is a
              -- tear wherever it came from -- it hurts if it lands on you and it
              -- puddles where it lands -- so all any of these change is
              -- *where* a handful of them land.
              --
              -- The puddle a tear leaves is deliberately smaller and shorter
              -- than the one the boss drags behind it: the trail is the price of
              -- letting it walk, and should be worse than weather.
              --
              -- And a tear is *thrown*, not fired: it goes up and comes down
              -- (`high` pixels over the page, plus `rise` for every pixel it
              -- travels), with its shadow on the floor the whole way, and it
              -- hurts only where it lands (Game:updateEnemyShots). In the air
              -- it is over your head. The red fan is the thing that hurts on
              -- the way; a tear is the thing that hurts where it stops.
              tears = { speed = 74, damage = 8, hit = 3, drop = "red",
                        high = 8, rise = 0.2,
                        puddle = { radius = 10, life = 5.5, damage = 6 },
                        -- The weather. A few at a time, anywhere in the box,
                        -- landing near or far -- the one attack that is not
                        -- aimed at you at all, so it is the one that makes
                        -- standing still bad on its own account.
                        scatter = { every = 3.2, count = 3, near = 34, far = 130 },
                        -- The lane. Fired straight down the line to the player
                        -- and landing at rising distances, so what it draws is a
                        -- wall across the way you were about to go rather than a
                        -- shot at where you are. Aimed, but at the ground.
                        lane = { every = 7.5, count = 5, from = 26, step = 24 },
                        -- The two turns. Fired once each as the fight passes two
                        -- thirds and one third of the eye's health, a full ring
                        -- of tears thrown out around it -- so the moment the bar
                        -- says the fight is going your way, the floor answers.
                        -- Thresholds rather than a clock, because what they are
                        -- for is marking progress you earned.
                        ring = { at = { 0.66, 0.33 }, count = 14, radius = 50,
                                 -- And it cries out eyes at each: two of the
                                 -- small ones at the first turn and two of the
                                 -- bloodshot ones at the second, so the escort
                                 -- is the fight getting worse rather than
                                 -- something that was always there.
                                 brood = { "eye", "redeye" }, broodCount = 2 } },
              -- The moves (src/eyeboss.lua), each read in that file and nowhere
              -- else. A list of three is a number per phase -- above two thirds
              -- of its health, above one third, and the last third -- and the
              -- whole of how the fight gets meaner is in those lists.
              --
              -- Every number below that is a *time* is a tell, and none of them
              -- is under half a second: the promise of this fight is that it is
              -- answered by reading and moving, never by reflex. Damage is the
              -- first cycle's and scales with the contact damage (EyeBoss).
              attacks = {
                  -- Seconds of walking between moves, plus up to 0.6 more.
                  cool = { 2.6, 2.0, 1.5 },
                  -- The beam. `turn` is how fast the line swings onto you while
                  -- it aims, radians a second; then it stops turning and holds
                  -- the line for `lock` before it fires, which is the step you
                  -- get to take off it -- tracking you right up to the shot was
                  -- a hit nobody could dodge. `sweep` is how fast it keeps
                  -- going once it fires. 0.55 at 100px is ~55px a second, just
                  -- under your 58: outwalkable, barely, by walking against it.
                  stare = { aim = { 0.85, 0.75, 0.65 }, lock = { 0.5, 0.42, 0.36 },
                            fire = { 0.45, 0.55, 0.65 },
                            sweep = { 0, 0.35, 0.55 }, turn = 2.4, width = 5,
                            damage = 14, length = 260, rest = 0.6 },
                  -- The roll. 104 is well over your speed, which is the wad's
                  -- bargain: you cannot outrun the line, you step off it.
                  bowl = { wind = { 0.75, 0.65, 0.55 }, lead = 0.3, speed = 104,
                           time = 1.7, bounces = { 0, 1, 2 }, rest = 0.9 },
                  -- The leap. The ring it lands in reaches `shock`; from where
                  -- it was aimed, crouch plus air is ~1.2s, which at 58 is ~70px
                  -- of walking -- more than the widest ring, so standing still
                  -- is the only way to be in it.
                  slam = { crouch = 0.4, air = 0.85, high = 46, reach = 150,
                           shock = { 48, 54, 60 }, damage = 12, leaps = { 1, 1, 2 },
                           ring = { 0, 8, 10 }, tearReach = 44, rest = 0.7 },
                  -- Under and up again, from the second phase. `near`/`far`
                  -- is how far from you it is willing to come up.
                  sink = { from = 2, down = 0.45, under = 0.4, up = 0.35,
                           near = 45, far = 140, ring = { 0, 0, 8 }, tearReach = 40,
                           rest = 0.5 },
                  -- The weep, also from the second phase: it looks up, a tear
                  -- wells, and it throws `volleys` rings of `count` tears, each
                  -- ring `step` further out than the last and turned half a gap
                  -- from it, `gap` seconds apart. Every ring has holes and no
                  -- two holes line up, so the way out is a zigzag you walk
                  -- while the shadows come down -- and the floor it leaves is
                  -- the sink's next way up.
                  weep = { from = 2, well = 0.7, volleys = { 0, 3, 4 },
                           count = { 0, 8, 10 }, near = 38, step = 30, gap = 0.35,
                           rest = 0.7 },
              } },
    -- SCIENCE's encore (`encore` in src/subjects.lua): the atom, which walks on
    -- ten minutes after the eye goes down at a master's and a doctorate
    -- (`bosses` in src/course.lua), and the fight about the space round a body
    -- rather than the ground under it. The moves and why they are these moves
    -- are src/atomboss.lua; the body is src/atom.lua.
    --
    -- The eye's numbers where the fight is the same fight -- 900 health for the
    -- measured half minute, the knock, the hold, 20 on contact -- and the
    -- spawner prices it a cycle on from the eye (BOSS_HP_PER_CYCLE), since it
    -- walks on at the end of the second ten minutes. Slower than the eye,
    -- because what it reaches you with is its orbits and not its body; the hit
    -- circle is the nucleus alone, so a shot through the rings is a shot that
    -- missed.
    atom = { name = "ATOM", sprite = "atom", hp = 900, speed = 22, radius = 12, damage = 20,
             xp = 250, shadow = 24, boss = true, knock = 0.06, hold = 0.3,
             title = "THE ATOM", call = "THE ATOM IS UNSTABLE",
             atom = {
                 -- The whole: a nucleus 27 across with three orbits round it,
                 -- 22, 28 and 34 out -- inside your reach of it with a short
                 -- weapon, so going in for damage is going in among them.
                 size = 13, rings = 3, first = 22, step = 6,
                 -- What each orbit's electron hits for, and how big it is.
                 orbit = { damage = 8, hit = 2 },
                 -- Seconds of walking between moves, plus up to 0.6 more: by
                 -- phase, which is whole, split, and the last fifth of the two.
                 cool = { 2.4, 2.0, 1.5 },
                 -- The sweep. `reach` is how far the orbit swells (the box is
                 -- 480 by 270, so 90 is a third of its width either side), the
                 -- dashed ring is up for `tell`, it takes `out` to swell and as
                 -- long to fall back, and is out for `hold` in all. `tilts`
                 -- are the three lies it may sweep at -- near face on (a wall
                 -- round it), tipped (an ellipse going round) and near edge on
                 -- (a turning bar) -- and `swing` how fast it goes round,
                 -- radians a second: 0.55 at 90 is ~50px a second at the tip,
                 -- just under your 58. `count` orbits at once, by phase.
                 sweep = { reach = { 90, 72, 72 }, tell = { 0.95, 0.85, 0.7 },
                           out = 0.3, hold = 2.6, tilts = { 0.25, 0.95, 1.4 },
                           swing = { 0.5, 0.55, 0.65 }, count = { 1, 1, 2 },
                           width = 3, damage = 14, rest = { 0.9, 0.8, 0.6 } },
                 -- The throw. Slower than you (44 to your 58) and slow to turn
                 -- (1.7 radians a second is a turn 26px across), so it is
                 -- stepped round rather than outrun; gone after `life`. Its
                 -- orbit stays empty for `empty`.
                 throw = { tell = { 0.65, 0.55, 0.5 }, count = { 1, 1, 2 },
                           speed = 44, turn = 1.7, life = 5, damage = 9, hit = 3,
                           empty = 3, rest = { 0.6, 0.5, 0.4 } },
                 -- Fission, at half its health: `time` of shuddering, then two
                 -- halves flung apart at `speed` for `fling`.
                 fission = { at = 0.5, time = 1.1, fling = 0.45, speed = 110 },
                 -- A half: a nucleus 19 across with two orbits, circling you
                 -- `keep` out, aiming `turn` radians further round than it
                 -- stands, the other half on the far side of you.
                 halves = { size = 9, radius = 8, rings = 2, first = 16, step = 6,
                            keep = 64, turn = 0.6 },
             } },
    -- FINANCE's encore (`encore` in src/subjects.lua): the piggy bank, which
    -- trots on ten minutes after the stamp goes down at a master's and a
    -- doctorate, and the fight about whether to go for the money. The moves and
    -- why they are these moves are src/piggyboss.lua; the body is src/piggy.lua.
    --
    -- The eye's numbers where the fight is the same fight -- 900 health, the
    -- knock, the hold, 20 on contact -- priced a cycle on by the spawner like
    -- the atom. Trots a little faster than the eye walks, because its threat is
    -- its body: every move but the recall is it running at you.
    piggy = { name = "PIGGY BANK", sprite = "piggy", hp = 900, speed = 30, radius = 14,
              damage = 20, xp = 250, shadow = 30, boss = true, knock = 0.06, hold = 0.3,
              title = "THE PIGGY BANK", call = "THE PIGGY BANK IS FULL",
              piggy = {
                  -- The second phase, as a share of its health left.
                  second = 0.65,
                  -- Seconds of trotting between moves, plus up to 0.6 more: by
                  -- phase, which is whole, past `second`, and broken.
                  cool = { 2.2, 1.8, 1.2 },
                  -- A coin: how big it is to be hit by, and the lob the bait is
                  -- spat on.
                  coin = { hit = 3, arc = { time = 0.45, high = 18 } },
                  -- The charge. 140 is well over your 58 -- the wad's bargain, you
                  -- step off the lane rather than outrun it. The arrow on the
                  -- floor is `tell` long. `count` charges in a row, the later
                  -- ones wound for `again`; `bait` coins spat into the lane on
                  -- the first wind, from `near` out at `step` apart -- inside the
                  -- arrow, so the money is where the danger is.
                  charge = { wind = { 0.9, 0.8, 0.65 }, again = 0.45, count = { 1, 2, 3 },
                             bait = { 3, 4, 0 }, near = 34, step = 22, speed = 140,
                             time = 1.5, bounces = { 0, 1, 1 }, rest = { 1.0, 0.85, 0.7 },
                             tell = 90 },
                  -- Savings: at least `least` coins on the floor of the box for
                  -- it to bother, the tell, and how fast they come home and what
                  -- each hits for on the way. Out after `hold` whatever is left.
                  recall = { least = 3, tell = { 1.0, 0.85, 0.85 }, speed = { 105, 120, 120 },
                             damage = 8, hold = 3, rest = { 0.6, 0.5, 0.5 } },
                  -- The shatter, at under `at` of its health: `time` of shaking,
                  -- then `volleys` rings of `count` coins `gap` apart, each with
                  -- a hole `hole` coins wide, flying `near` to `far` out at
                  -- `speed` and landing there. 85 is ~1.5 times you, so a ring
                  -- is stepped through rather than run from.
                  shatter = { at = 0.3, time = 1.1, volleys = 3, count = 14, hole = 2,
                              gap = 0.4, speed = 85, near = 60, far = 110, damage = 9,
                              rest = 1.0 },
                  -- And what spills out of it when it goes down.
                  spill = 6,
              } },
    -- MATHS's encore (`encore` in src/subjects.lua): the tesseract, which turns
    -- into the page ten minutes after the die goes down at a master's and a
    -- doctorate, and the fight about which side of a shape you are on when the
    -- shape turns into something else. The moves and why they are these moves
    -- are src/tesseractboss.lua; the body is src/tesseract.lua.
    --
    -- The eye's numbers where the fight is the same fight -- 900 health, the
    -- knock, the hold, 20 on contact -- priced a cycle on by the spawner like
    -- the atom. It drifts at you slower than anything else walks, because it
    -- does not need to come to you: from the second phase it turns out of the
    -- page and back into it wherever you are. The hit circle is a little inside
    -- the outer cube's corners.
    tesseract = { name = "TESSERACT", sprite = "tesseract", hp = 900, speed = 20, radius = 15,
                  damage = 20, xp = 250, shadow = 28, boss = true, knock = 0.06, hold = 0.3,
                  title = "THE TESSERACT", call = "THE FOURTH DIMENSION",
                  tesseract = {
                      -- Seconds of drifting between moves, plus up to 0.6 more:
                      -- by phase (the eye's thirds).
                      cool = { 2.3, 1.9, 1.5 },
                      -- Inside-out. The inner square is `inner` out (half its
                      -- width) -- ten pixels outside where its body would touch
                      -- you, so hugging it is a real place to stand -- and the
                      -- outer `outer`; the band between goes off for `hot` after
                      -- `tell`. From the second phase the other way follows,
                      -- counted in for `again`: the middle and a rim `rim` wide
                      -- outside the outer square. A count-in of 1.1s is 64px of
                      -- walking at your 58, more than the widest walk out of the
                      -- band. `turn` is how far the squares turn while they go,
                      -- the last third only; `fling` is the shove the crowd
                      -- caught between them gets.
                      flip = { inner = 30, outer = { 84, 92, 100 }, rim = 36,
                               tell = { 1.1, 0.95, 0.85 }, again = 0.75, hot = 0.45,
                               turn = { 0, 0, 0.6 }, damage = 14, fling = 260,
                               rest = { 0.9, 0.8, 0.6 } },
                      -- The corners: the outer eight, then all sixteen, thrown
                      -- straight out the way they stick out -- the furthest at
                      -- `speed`, the nearest at `slow` of it, so one volley is
                      -- two rings, 40 and 80 against your 58. `volleys` by phase,
                      -- the second spun on for `gap` and aimed for `again`.
                      corners = { count = { 8, 16, 16 }, volleys = { 1, 1, 2 },
                                  tell = { 0.8, 0.7, 0.6 }, again = 0.45, gap = 0.35,
                                  speed = 80, slow = 0.5, hit = 3, life = 4, damage = 9,
                                  rest = { 0.7, 0.6, 0.5 } },
                      -- The net: eight cubes `cell` across -- three of the page's
                      -- squares, half a second of walking -- opened out over
                      -- `open`, the first going off `lead` after that and one
                      -- more every `step`, each hot for `hot`. A little longer
                      -- than the step, so the wave down the net is unbroken.
                      net = { cell = 30, open = 0.5, lead = 0.7, step = { 0.42, 0.36, 0.3 },
                              hot = 0.5, fold = 0.3, damage = 14, rest = { 0.9, 0.8, 0.6 } },
                      -- Through the fourth dimension, from the second phase and
                      -- only when you are `far` off: out of the page over `out`,
                      -- the square on where you stood for `aim`, back in over
                      -- `back` with a square shock `shock` out. Out and aim are
                      -- 1.6s, ninety pixels of walking against a square of 34.
                      fold = { far = 110, out = 0.5, aim = { 1.1, 1.0, 0.9 }, back = 0.2,
                               shock = 34, damage = 14, rest = { 0.9, 0.8, 0.7 } },
                  } },
    -- The P.E. boss: the coach's whistle, and the one fight in the book that is
    -- a bullet hell. The eye is a fight about *ground* -- everything it does is
    -- wet you have to stop standing on -- and this is the other half of the
    -- same box: a fight about what is in the air, and about the class it calls
    -- in. A P.E. teacher does not fight you. They blow the whistle and make
    -- everybody else do it.
    --
    -- The body is the eye's numbers where the fight is the same fight -- 900
    -- health for the eye's reason (the measured half minute), the same knock
    -- and hold, the same 20 on contact -- and a narrower radius because it is
    -- a narrower thing: the barrel is 27 across, and the hit circle is that
    -- drum (the sprite's origin is its middle, src/sprites.lua), with the
    -- mouthpiece left outside it as the thin thing it is. It walks a touch
    -- slower than the eye because it has something faster to do instead.
    --
    -- **It lunges.** The wad's `charge`, at the boss's size: it stands still
    -- winding up, outlined in red, and then throws itself down the line it
    -- locked. The rule the wad's numbers keep is kept here too -- 140 for 0.6s
    -- is 84px against a 150 trigger, so it closes on you and never crosses the
    -- range in one go -- and the box is what makes it a threat: the far end of
    -- the line is a wall, not open page.
    --
    -- **It spits.** Three peas down the line on a short beat, the least of what
    -- it does and the thing that is always happening, so standing still is
    -- never free even between the calls below.
    whistle = { name = "WHISTLE", sprite = "whistle", hp = 900, speed = 22, radius = 13, damage = 20,
                xp = 250, shadow = 26, boss = true, turns = "whistleViews", knock = 0.06, hold = 0.3,
                title = "THE WHISTLE", call = "THE WHISTLE BLOWS",
                shot = { range = 200, every = 1.9, speed = 58, damage = 9, hit = 3,
                         spread = 3, arc = 0.42, sprite = "pea" },
                charge = { range = 150, every = 7, wind = 0.85, speed = 140,
                           time = 0.6, rest = 1.4 },
                -- The four calls (Game:updateWhistle). Three clocks and a set of
                -- thresholds, for the tears' reason: the clocks are a rhythm you
                -- learn, and the thresholds are the fight answering you for
                -- winning it.
                whistle = {
                    -- The blast. It stops, flashes red for `wind` seconds -- the
                    -- one tell, and the same tell the lunge uses, because both
                    -- are "it is about to do something big" -- and then blows a
                    -- ring of notes out in every direction with a hole `gap`
                    -- notes wide in it, twice, the second ring set half a note
                    -- round from the first. The hole is the answer and it is in
                    -- the same place both times; everywhere else, the half-step
                    -- closes the room the first ring left. So the blast is not
                    -- dodged by standing still and is not dodged by guessing --
                    -- it is dodged by finding the hole and getting into it.
                    blast = { every = 6, wind = 0.9, rings = 2, apart = 0.3,
                              count = 22, gap = 4, speed = 55, damage = 10,
                              hit = 3, life = 4.5, sprite = "note" },
                    -- The jacks: the spiky things. Lobbed rather than thrown --
                    -- over your head, harmless in the air, with their shadow on
                    -- the page where each will come down -- to land in a
                    -- scatter round where you are *standing*, and then lie there
                    -- for `lie.life` seconds hurting whoever walks on them
                    -- (src/spike.lua). Aimed at the ground round you rather than
                    -- at you, so what it takes away is the room you were about
                    -- to dodge the next blast into.
                    jacks = { every = 4.6, count = 6, spread = 50, flight = 0.9,
                              damage = 8, sprite = "jack",
                              lie = { radius = 4, life = 7 } },
                    -- Fall in. A short wall of one kind marched across the box
                    -- from one of its edges (Spawner:squad), on top of the
                    -- ordinary escort: the troops the whistle commands, and the
                    -- P.E. page's own favourite drill turned on you. The kinds
                    -- are dealt in turn so the squads are different problems --
                    -- a wall of skulls is a wall, a wall of wads is a volley
                    -- -- and `most` is the crowd it will not call into, so a
                    -- squad never arrives into a box that is already full.
                    squad = { every = 12, count = 6, gap = 18, most = 28,
                              of = { "skull", "wad", "blob", "bat" } },
                    -- Grow. At three quarters, half and a quarter of its health
                    -- it blows a long note and the `count` nearest of its class
                    -- within `range` come up as champions (Game:pumpEnemy) --
                    -- twice the size, the champion's own health and damage, the
                    -- same monster. Whoever it could not find nearby it calls in
                    -- beside itself. Thresholds rather than a clock for the
                    -- eye's rings' reason: the moment the bar says the fight is
                    -- going your way, the class gets bigger.
                    pump = { at = { 0.75, 0.5, 0.25 }, count = 3, range = 170 },
                } },

    -- The MUSIC boss: a metronome, and the fight in the book about *time*. The
    -- eye is about the ground and the whistle about the air; this is about
    -- when. Everything it does lands on its own tick -- the tick you hear, and
    -- the arm you can see reaching the end of its swing -- and every move is
    -- counted in for a full bar first, at the tempo it is about to be played at.
    -- The three moves and how it picks between them are src/metronome.lua.
    --
    -- The body keeps the eye's numbers where the fight is the same fight: 900
    -- health for the measured half minute, the same knock, hold and 20 on
    -- contact. The radius is the pyramid's bulk round the middle of it, with
    -- the plinth's corners and the arm left outside. It walks on the beat --
    -- hopping for `step` of each beat and standing for the rest -- so the 50
    -- on the row is a stride, and what it covers on average is 25, about the
    -- eye's 26 and still well under your 58.
    metronome = { name = "METRONOME", sprite = "metronome", hp = 900, speed = 50, radius = 12,
                  damage = 20, xp = 250, shadow = 30, boss = true, turns = "metronomeViews",
                  knock = 0.06, hold = 0.3,
                  title = "THE METRONOME", call = "THE METRONOME TICKS",
                  metronome = {
                      -- Beats a minute, by phase (the eye's thirds), and how
                      -- many to the bar. Every move is counted in for a bar and
                      -- starts on a downbeat, so at 60 the tell is four
                      -- seconds and at 100 it is two and a half.
                      tempo = { 60, 80, 100 }, bar = 4,
                      -- How far the arm swings either side of upright, in
                      -- radians; and the share of each beat it walks for.
                      swing = 0.45, step = 0.5,
                      -- How it roams: circling you about `keep` out (it cuts the
                      -- corner, so it settles nearer seventy) -- inside the
                      -- sweep's 150, so a sweep is always on the cards -- aiming
                      -- `turn` radians further round than it stands, swapping
                      -- which way round every `swap` bars, and `hop` pixels
                      -- off the ground at the top of each step.
                      roam = { keep = 85, turn = 0.6, swap = 3, hop = 3 },
                      -- Bars walking between moves, by phase, and bars stood
                      -- still after one -- the window the move paid for.
                      cool = { 2, 1, 1 }, rest = 1,
                      -- While it walks, a note at you every `every` beats: the
                      -- least of what it does, so standing still is never free.
                      tick = { every = 2, speed = 62, damage = 9, hit = 3, life = 4,
                               sprite = "note" },
                      -- The sweep: a beam across a fan of `fan` radians either
                      -- side of you, swinging with the arm, for `bars` bars. At
                      -- a hundred pixels it crosses the fan at over twice your
                      -- speed, which is the point: you leave the fan rather
                      -- than outrun the beam.
                      sweep = { length = 150, fan = 0.8, width = 5, damage = 14,
                                bars = { 1, 1, 2 } },
                      -- The chord: rings `width` across at these radii, struck
                      -- from the inside out, one a beat. Thirty six apart, so
                      -- the room between two of them is wider than the room
                      -- the bands take -- somewhere to stand on every beat.
                      chord = { rings = { 30, 66, 102, 138 }, count = { 3, 3, 4 },
                                width = 12, damage = 14, flash = 0.2, bars = 1 },
                      -- The scale: notes `gap` apart across the whole box with a
                      -- hole `hole` notes wide, marched across it in `beats`
                      -- steps while the hole climbs a note a beat. Held back
                      -- until the second phase: it is a whole-box move, and the
                      -- first third is for learning the other two. Three is
                      -- the narrowest the hole can be and stay fair: at three,
                      -- the middle of the hole is still clear of every note one
                      -- climb later; at two, the note that jumps the hole lands
                      -- on whoever is standing in the middle of it.
                      scale = { gap = 16, hole = 3, beats = 8, slide = 0.18,
                                damage = 10, hit = 3, sprite = "note", bars = 2,
                                from = 2 },
                  } },

    -- The FINANCE boss: an office rubber stamp, and the fight in the book about
    -- *cells*. Its pad is one cell of the ledger and everything it does is come
    -- down on one, outlined on the page first; the moves and how it picks
    -- between them are src/stamp.lua, and why it is baked in four poses rather
    -- than one is art/stamp.py.
    --
    -- The body keeps the eye's numbers where the fight is the same fight: 900
    -- health for the measured half minute, the same knock, hold and 20 on
    -- contact. The radius is the mount round the middle of it, with the long
    -- ends of the pad outside. It never walks: `speed` is never read, because
    -- every step it takes is a leap the brain draws, and its hops at you cover
    -- about 25 a second between moves -- the eye's pace, in jumps.
    -- `ground` is the front edge of the pad, where the shadow goes: the bottom
    -- of the cell it is standing on (`foot` in Sprites.STAMP, and six more).
    stamp = { name = "STAMP", sprite = "stamp", hp = 900, speed = 26, radius = 13,
              damage = 20, xp = 250, shadow = 40, ground = 13, boss = true, turns = "stampViews",
              poses = "stampPoses", knock = 0.06, hold = 0.3,
              title = "THE STAMP", call = "THE STAMP COMES DOWN",
              stamp = {
                  -- Seconds hopping at you between moves, by phase (the eye's
                  -- thirds).
                  cool = { 2.2, 1.7, 1.3 },
                  -- The hop: every `every` seconds, up to `reach` pixels at you
                  -- in a leap `time` long and `high` up, rocked back for `rear`
                  -- before it and flattened for `squash` after. 30 every 1.2s
                  -- is the eye's 26 a second, near enough, in jumps.
                  hop = { every = { 1.2, 1.0, 0.85 }, reach = 30, time = 0.34,
                          high = 7, rear = 0.18, squash = 0.1 },
                  -- A blot of ink at you every `every` seconds while it hops:
                  -- the least of what it does.
                  blot = { every = 2.6, speed = 62, damage = 9, hit = 3, life = 4 },
                  -- What it prints: wet for as long as the move says, hurting
                  -- for `damage` to stand in, then dry -- harmless, fading --
                  -- for `dry` seconds.
                  ink = { damage = 6, dry = 6 },
                  -- The slam: rocked back for `rear` with your cell blinking,
                  -- then a leap of `fly` seconds onto it. Half a second in the
                  -- air is twenty nine pixels at your speed against a cell six
                  -- deep either side of you: always room, never room to dither.
                  -- Stuck for `rest` after, and from the second third the
                  -- landing throws `splash` blots in a ring.
                  slam = { rear = { 1.0, 0.85, 0.7 }, fly = 0.55, high = 34,
                           damage = 16, wet = 2.4, knock = 2, rest = { 1.1, 1.0, 0.85 },
                           splash = { 0, 6, 8 } },
                  -- The run: rocked back for `rear`, then `count` hops along a
                  -- row a cell (40px) every `step` -- 180 a second, three times
                  -- your speed -- stepping a row towards you on each.
                  run = { rear = 0.7, count = { 5, 6, 8 }, step = 0.22, high = 9,
                          damage = 12, wet = 1.8, rest = 0.9 },
                  -- The audit: from the second third, every other cell of a
                  -- block `cols` by `rows` round you, counted in for `rear`,
                  -- stamped a `step` apart and all wet until `wet` after the
                  -- last. At the last third it does it `passes` times, the
                  -- second the other colour, counted in for `again`.
                  audit = { from = 2, cols = { 5, 5, 5 }, rows = { 9, 9, 11 },
                            passes = { 1, 1, 2 }, rear = 1.3, again = 1.2,
                            step = { 0.14, 0.14, 0.12 }, high = 10, damage = 12,
                            wet = 0.6, rest = 1.2 },
              } },

    -- The GRAMMAR boss: a fat dictionary, and the fight in the book about
    -- *lines*. Its pages are whole groups of the paired ruling deep and what it
    -- writes it writes on the lines; the moves and how it picks between them are
    -- src/dictionary.lua, and why it is baked in three poses is art/dictionary.py.
    --
    -- The body keeps the eye's numbers where the fight is the same fight: 900
    -- health for the measured half minute, the same knock, hold and 20 on
    -- contact. The radius is the closed book round the middle of it. It never
    -- walks -- every step is a hop the brain draws, about 25 a second between
    -- moves, the eye's pace and the stamp's. `ground` is the near edge of the
    -- book on the page, where the shadow goes: the floor under its middle
    -- (`foot` in Sprites.DICTIONARY) and half the book's depth seen from above.
    dictionary = { name = "DICTIONARY", sprite = "dictionary", hp = 900, speed = 0, radius = 14,
                   damage = 20, xp = 250, shadow = 40, ground = 16, boss = true,
                   turns = "dictionaryViews", poses = "dictionaryPoses", knock = 0.06, hold = 0.3,
                   title = "THE DICTIONARY", call = "THE DICTIONARY OPENS",
                   dictionary = {
                       -- Seconds hopping at you between moves, by phase (the
                       -- eye's thirds).
                       cool = { 2.2, 1.7, 1.3 },
                       -- The hop: every `every` seconds, up to `reach` pixels at
                       -- you in a leap `time` long and `high` up, mouth open for
                       -- `rear` before it. The stamp's numbers: the eye's pace.
                       hop = { every = { 1.2, 1.0, 0.85 }, reach = 30, time = 0.34,
                               high = 7, rear = 0.22 },
                       -- A page torn out and flicked at you every `every`
                       -- seconds while it hops: the least of what it does.
                       leaf = { every = 2.6, speed = 62, damage = 9, hit = 3, life = 4 },
                       -- The clap: mouth open for `rear` with the pages following
                       -- you, a leap of `fly` onto the spine, open for `hold`,
                       -- then both fore-edges in to the spine over `close`. The
                       -- spine is put half a page short of you, so from
                       -- the lock to the pages moving is `fly` and `hold` --
                       -- over a second, sixty pixels of walking -- against at
                       -- most half of `lines` groups to the head or the tail.
                       -- Stuck for `rest` after, and from the second third the
                       -- shut throws `splash` leaves out in a ring.
                       clap = { rear = { 1.0, 0.85, 0.7 }, fly = 0.5, high = 30,
                                hold = { 0.55, 0.45, 0.35 }, close = 0.3,
                                reach = { 80, 90, 100 }, lines = { 2, 2, 3 },
                                damage = 16, knock = 2, rest = { 1.2, 1.0, 0.9 },
                                splash = { 0, 6, 8 } },
                       -- The riffle: mouth open for `rear`, then `turns` pages a
                       -- fan of `leaves` each, `every` apart, the fan `spread`
                       -- radians between leaves and shifted half that on every
                       -- other turn. 0.3 is twenty four pixels at eighty out: a
                       -- body (twelve) and a leaf (six) with room to spare.
                       riffle = { rear = 0.8, turns = { 5, 6, 8 }, every = { 0.42, 0.38, 0.34 },
                                  leaves = { 5, 7, 7 }, spread = 0.3, rest = 0.9 },
                       -- The definition: from the second third, the lines of
                       -- every group within `rows` of yours, outlined for `rear`
                       -- and written left to right at `speed` -- over twice your
                       -- pace, so it is stepped out of rather than outrun -- each
                       -- line `lag` behind the one above it, wet until `wet`
                       -- after the last letter and dry for `dry` after that. At
                       -- the last third it writes `passes` times, the second time
                       -- between the lines, counted in for `again`.
                       definition = { from = 2, rows = { 2, 2, 3 }, passes = { 1, 1, 2 },
                                      rear = 1.3, again = 1.2, lag = 0.2, speed = 180,
                                      damage = 12, wet = 0.8, dry = 5, rest = 1.2 },
                   } },

    -- The MATHS boss: a die, and the fight in the book about *number*. The eye
    -- is about the ground, the whistle the air, the metronome time; this one is
    -- about reading what a roll says before it happens. It is thrown rather
    -- than walked -- a locked line, a tumble down it, a stop -- and where it
    -- stops it lands on a face, and the face is the move. A d6, then a d10 at
    -- two thirds, then a d20 at one third. The moves, the rolls and how glue
    -- loads it are src/diceboss.lua; the body is painted live (src/dice.lua).
    --
    -- The body keeps the eye's numbers where the fight is the same fight: 900
    -- health for the measured half minute, the same knock, hold and 20 on
    -- contact. The radius is the die's bulk, a little inside its corners. No
    -- walking speed, because it never walks: everything it covers it covers
    -- in a throw, 97 pixels a cycle of throw, roll, strike and rest in the
    -- first third and 108 in the last -- about 18 a second rising to 23,
    -- under the eye's 26 -- and all of it down a line you can step off.
    die = { name = "DIE", sprite = "die", hp = 900, speed = 0, radius = 14, damage = 20,
            xp = 250, shadow = 28, boss = true, knock = 0.06, hold = 0.3,
            title = "THE DIE", call = "THE DIE IS CAST",
            dice = {
                -- What it is, by phase (the eye's thirds).
                shapes = { "d6", "d10", "d20" },
                -- The throw: a red wind-up with the line drawn, then a run
                -- down it from `speed` to nothing over `time` -- half of the
                -- two multiplied is where it stops, 97 to 108 pixels off, and
                -- a peak of nearly three times your 58 is why you step off the
                -- line rather than outrun it. `spread` is how far off your
                -- middle it may aim; `hops` and `high` the clatter on the way;
                -- `twist` the most spin about the upright it is thrown with,
                -- radians a second, which is what makes the roll a roll;
                -- `settle` how quick it tips the rest of the way onto a face.
                throw = { wind = { 0.75, 0.65, 0.55 }, speed = { 150, 165, 180 },
                          time = { 1.3, 1.25, 1.2 }, spread = 0.3, hops = 3, high = 9,
                          twist = 9, settle = 7 },
                -- Stood still after a move: the window it paid for.
                rest = { 1.5, 1.3, 1.1 },
                -- The d6's face stamped round you, three by three cells of
                -- `cell` -- three of the page's squares each -- with the pips'
                -- cells going off. A cell is about half a second of walking,
                -- so the 1.2 count-in is a read and a step, never a sprint.
                stamp = { cell = 30, tell = 1.2, hot = 0.35, damage = 14 },
                -- The d10's odds and evens: the whole box in cells of two
                -- squares, the half matching the roll going off. A safe cell
                -- is never more than one cell away, wherever you stand.
                checker = { cell = 20, tell = 1.1, hot = 0.35, damage = 12 },
                -- The d20's spokes: that many lines out from it, swinging
                -- `turn` of a gap round while hot. A third and not a half,
                -- so the trailing side of every gap stays clear: you move
                -- with the swing, not away from it.
                spokes = { tell = 1.0, hot = 0.6, width = 5, length = 260, turn = 0.35,
                           damage = 12 },
                -- The pips after a roll: a fan of that many off the d6
                -- (`arc` apart), a ring of that many off the d10.
                pips = { speed = 66, damage = 9, hit = 3, life = 4, arc = 0.22,
                         sprite = "pip" },
                -- Unfolding into the d10: a shudder, then the net -- a cross of
                -- six faces `cell` across round where it stood -- counted in,
                -- hot, and folded back up.
                net = { shake = 0.5, cell = 40, tell = 1.0, hot = 0.4, fold = 0.3,
                        damage = 14 },
                -- Recast into the d20: up off the page, its shadow on where you
                -- were standing for `aim`, then down with a ring `shock` wide.
                -- Up and aim are 1.55s, which at 58 is ninety pixels of
                -- walking against a ring of 56: standing still is the only way
                -- to be under it.
                recast = { up = 0.45, aim = 1.1, down = 0.25, high = 220, shock = 56,
                           damage = 14 },
                -- A natural 1: on its side for `time`, taking `soften` times
                -- whatever hits it. A natural 20: the spokes, then odds, then
                -- evens, each counted in for one of `tell`.
                fumble = { time = 3, soften = 1.5 },
                crit = { tell = { 1.0, 0.8, 0.6 } },
            } },

    -- The ART boss: a still life, and the fight in the book about *light*. A
    -- plaster cube, sphere and cone under a lamp, the first thing an art class
    -- draws, painted a pixel at a time (src/plaster.lua) so the lit side of
    -- every solid follows the lamp round. It never walks: the lamp moves, the
    -- shadows the solids throw are what hurt, and the pieces leave the table
    -- to come at you -- the cube dropped, the sphere bowled, the cone spun on
    -- its point -- more of them at once the lower it gets, and hittable while
    -- they are out (`stillpiece`, below). The moves are src/stilllife.lua.
    --
    -- The eye's numbers where the fight is the same fight: 900 health, the
    -- same knock, hold and 20 on contact. The radius is the group's bulk, the
    -- three solids standing together. No speed, because a still life holds
    -- still; when you get far from it, the table is lifted and put down nearer.
    stilllife = { name = "STILL LIFE", sprite = "stilllife", hp = 900, speed = 0, radius = 16,
                  damage = 20, xp = 250, shadow = 30, boss = true, knock = 0.06, hold = 0.3,
                  title = "THE STILL LIFE", call = "DRAW WHAT YOU SEE",
                  still = {
                      -- Between one move starting and the next, by phase (the
                      -- eye's thirds), and how many may be going at once: one,
                      -- then two (the cube coming down while the sphere rolls),
                      -- then three. Each piece does one thing at a time, and
                      -- there is one shade at a time.
                      cool = { 2.0, 1.6, 1.3 },
                      together = { 1, 2, 3 },
                      -- What it picks between, by phase: a piece joins the
                      -- fight each third.
                      moves = { { "shade", "drop" }, { "shade", "drop", "roll" },
                                { "shade", "drop", "roll", "top" } },
                      -- The lamp: `ring` out from the group, `high` off the
                      -- floor (low, so the light rakes and the shading turns
                      -- hard as it goes round), drifting `drift` radians a
                      -- second when nothing else has it.
                      lamp = { ring = 80, high = 26, drift = 0.35 },
                      -- Lifted and put down nearer, once you are `far` off:
                      -- up to `reach`, never closer than `near`.
                      move = { far = 90, near = 50, reach = 60, time = 0.45, high = 10 },
                      -- The shade: the lamp swings to the far side of the
                      -- group from you, give or take `spread`, over the first
                      -- part of `tell`, the shadows growing from `short` to
                      -- `length` as it goes; then hot for `hot`, the lamp going
                      -- `swing` further round. A swing of 0.3 over 1.3 seconds
                      -- moves a shadow's edge 46 pixels a second at 200 out
                      -- from the lamp -- under your 58, so you can walk with a
                      -- gap -- and nothing at all between the lamp and the
                      -- group, which is the light you can always stand in.
                      -- The second lamp of the last third is `apart` round.
                      shade = { tell = { 1.4, 1.25, 1.1 }, hot = { 0.9, 1.3, 1.5 }, fade = 0.3,
                                swing = { 0, 0.3, 0.3 }, spread = 0.35, apart = 2.0,
                                short = 14, length = 320, damage = 12 },
                      -- The cube: up for `up`, its shadow on where you were
                      -- for `aim`, down in `down` with a ring `shock` wide,
                      -- sitting there for `sit` and home in `back`. Up and
                      -- aim are 1.5 seconds: eighty pixels of walking against
                      -- a ring of 24.
                      drop = { up = 0.4, aim = 1.1, down = 0.22, high = 200, shock = 24,
                               damage = 14, sit = 1.4, back = 0.5, hop = 14 },
                      -- The sphere: a line to you and a shudder for `wind`,
                      -- out at `speed` to the edge of the box (or `length`)
                      -- and back at `back` of it. Three times your pace: a
                      -- line you step off, the eye's bowl.
                      roll = { wind = 0.75, speed = 170, back = 0.8, length = 260, damage = 14 },
                      -- The cone: over in `flip`, then on its point for
                      -- `time`, leaning `lean` and going round `whirl` radians
                      -- a second, wandering after you at `speed` -- under your
                      -- pace, so it is walked away from -- with a chip off it
                      -- every `every`, each `turn` further round: a spiral.
                      -- Then over in `fall`, and home in `back`.
                      top = { flip = 0.45, time = { 2.6, 2.6, 3.2 }, lean = 0.3, whirl = 10,
                              wobble = 0.6, speed = 46, every = 0.16, turn = 2.4, damage = 12,
                              fall = 0.35, back = 0.55,
                              chip = { speed = 60, damage = 9, hit = 3, life = 3.5,
                                       sprite = "pip" } },
                  } },

    -- A piece of the still life while it is off the table: the body that
    -- stands for it on the page so everything in the game can find it, aim at
    -- it and hurt it (src/stilllife.lua puts it down, moves it and takes it
    -- away). It is never sent and never killed. What it takes goes to the boss
    -- it stands for (`stand`, Enemy:hurt), and its own health is only there
    -- because every body has some. `boss` keeps it out of the crowd's way and
    -- the crowd out of its way, keeps it on the page however far off you are,
    -- and off the homework list; no knock and no hold, because where it is is
    -- wherever its piece is. Its `damage` is set by the move that lifted it.
    stillpiece = { sprite = "stilllife", hp = 1e9, speed = 0, radius = 8, damage = 14,
                   xp = 0, shadow = 0, boss = true, knock = 0, hold = 0 },
}

-- `scale` is how much harder the run has got since it started (Game:enemyScale)
-- and it is baked in *here*, once, rather than read off the run wherever damage
-- is dealt. That is what makes a monster keep the numbers it walked on with: the
-- horde standing on the page when a cycle ends is the horde that cycle spawned,
-- and nothing already alive gets tougher because the clock rolled over. It is
-- also why hp, damage, xp and the radius live on the enemy while everything else
-- stays on the shared `def` -- those four are the only ones a scale touches, and
-- the radius is the newest and the odd one out: it is the first thing a scale has
-- ever changed that is not a number on a health bar but a fact about how much of
-- the page the thing is standing on (`grow`, below).
-- Health is rounded to a whole number and damage is not, and that asymmetry is
-- the one place a scale is allowed to be inexact.
--
-- What a player actually learns about a monster is *how many hits it takes*, and
-- with health this small -- a bat is 2 -- an unrounded multiplier turns that
-- into a fraction they cannot see and can only lose to. A blob on 4.14 health
-- takes two swings of a pencil that deals 4, and nothing on screen says why; on
-- 4 it takes one, which is the game's most basic sentence and worth protecting
-- for the minute the ramp leaves alone (HP_GRACE in src/spawner.lua). Rounding
-- to nearest rather than down, so the curve is not quietly discounted -- a bat
-- floored would spend most of a cycle on the 2 it was written with.
--
-- Damage is left fractional because the reading is the other way round: nobody
-- counts how many blobs it takes to kill *them*, they read a health bar, and a
-- bar is happy with a fraction. Rounding it would also snap the 18%-a-cycle
-- damage curve into jumps on the low numbers, where 4 to 5 is a quarter.
local function wholeHp(base, mul)
    return math.max(1, math.floor(base * mul + 0.5))
end

function Enemy.new(kind, x, y, scale)
    local def = Enemy.types[kind]
    local hpMul = scale and scale.hp or 1
    local dmgMul = scale and scale.damage or 1
    local grow = scale and scale.grow or 1
    -- The course's legs (src/course.lua), and the one multiplier on an arrival
    -- that is *not* about how long it takes to kill. Left fractional for the
    -- damage curve's reason: nobody counts pixels a second, and 20 to 22 is a
    -- thing you feel rather than a thing you read.
    local spdMul = scale and scale.speed or 1
    -- How big what it throws is (Spawner:scale). Equal to `grow` today and read
    -- separately from it everywhere, because what it multiplies is a distance and
    -- what `grow` multiplies is a drawing.
    local reach = scale and scale.reach or 1
    local hp = wholeHp(def.hp, hpMul)

    return setmetatable({
        kind = kind,
        def = def,
        x = x, y = y,
        hp = hp,
        maxHp = hp,
        damage = def.damage * dmgMul,
        shotDamage = def.shot and def.shot.damage * dmgMul or nil,
        trailDamage = def.trail and def.trail.damage * dmgMul or nil,
        -- A tear hits for less than a pellet does and puddles for what a puddle
        -- is worth, and both are scaled here with everything else -- so the
        -- three numbers stay three numbers. Reading the fan's damage for a tear
        -- would have worked today (the trail and a tear's puddle happen to both
        -- be 6) and quietly stopped working the moment anyone tuned one of them.
        tearDamage = def.tears and def.tears.damage * dmgMul or nil,
        tearWet = def.tears and def.tears.puddle.damage * dmgMul or nil,
        -- And the whistle's two throws, for the same reason: a note and a jack
        -- are two numbers, and a cycle that sharpens one sharpens both.
        blastDamage = def.whistle and def.whistle.blast.damage * dmgMul or nil,
        jackDamage = def.whistle and def.whistle.jacks.damage * dmgMul or nil,
        -- And the bulb's dose, both halves of it, for the same reason: what a
        -- burst hits for and what the blot of ink it leaves hurts for are two
        -- numbers, and a cycle that sharpens one sharpens both (Game:burstEnemy).
        burstDamage = def.burst and def.burst.damage * dmgMul or nil,
        wetDamage = def.burst and def.burst.puddle.damage * dmgMul or nil,
        -- How wide the blast is, which is the one number on an attack that a
        -- standout arrival moves (`reach`, above). Baked here with the damages
        -- rather than read at the death, so a bulb that walked on enormous goes
        -- off enormous however long it stood around first -- the same rule every
        -- other number on an arrival keeps.
        burstRadius = def.burst and def.burst.radius * reach or nil,
        -- And the multiplier itself, for the three attacks whose size is worked
        -- out somewhere else: a pellet and a tear are built at the moment they
        -- are fired (Game:fireEnemyShot, Game:throwTear) and a puddle is built
        -- where it lands (Puddle.new), so those read this and scale themselves.
        reach = reach,
        -- The scale it walked on with, kept whole so it can be handed on. Only
        -- one thing wants it -- a `split` gives its children the parent's own
        -- scale rather than the run's current one (Game:killEnemy) -- and that
        -- is the same principle the three numbers above are baked for, one step
        -- further out: what came off a monster is as hard as the monster was,
        -- however long it has been standing on the page.
        scale = scale,
        -- A champion: the same row at several times the health, worth several
        -- times the xp because xp rides the hp multiplier, and drawn at twice the
        -- size so you can pick it out of a crowd (`grow`, below). It is a fact
        -- about the *spawn* rather than about the kind, which is why it arrives on
        -- the scale and not as a row of its own -- an elite anything is one line
        -- in the spawner and no new art at all (src/spawner.lua).
        --
        -- It used to be what picked the rim of heavier ink out of
        -- Enemy:outlineColour and it is now read in one place, Enemy:isBlown --
        -- which is the only question anything in the game asks about *which* of
        -- the two standouts an arrival was, and it asks it because a blow-up that
        -- splits leaves something different (`split.blown`, above).
        elite = (scale and scale.elite) or false,
        -- Enraged: the same row at the same size on the same health, quicker on
        -- its legs and hitting for half again, drawn in two colours so that all
        -- three of those are one thing you read rather than three things you find
        -- out (Spawner:fury, Sprites.enraged). The multipliers are already spent
        -- by the time this arrives -- they are on `speed` and `damage` above like
        -- every other number an arrival walked on with -- so what the flag is for
        -- is the drawing, and Enemy:footing is the one place that reads it.
        --
        -- It is the third fact about an *arrival* and the first that is not a
        -- size, which is why it sits beside `elite` rather than anywhere near
        -- `grow`: the two standouts are exclusive because they are both bodies,
        -- and this stacks with either because it is a colour.
        fury = (scale and scale.fury) or false,
        -- Worth what it costs to kill, which is why this rides the *hp*
        -- multiplier and not the damage one. A cycle-two blob takes 40% longer
        -- to put down, so a run clears 40% fewer of them a minute; paying the
        -- written 1xp for it would mean the horde quietly paid less every cycle
        -- while the xp ladder went on asking for more (`XP_RISE` in
        -- src/player.lua), and a long run would stop levelling somewhere in
        -- cycle two however well it was going. Tying the two together makes xp a
        -- second a flat thing across a cycle boundary rather than a falling one:
        -- the ladder still slows down as it climbs, which it should, but it
        -- slows down because levels cost more and never because the page has
        -- quietly stopped paying.
        --
        -- It leaves the value fractional, which nothing minds -- xp is only ever
        -- read as a fraction of the next level (Player:addXp) and is never
        -- written down for anyone to see.
        xp = def.xp * hpMul,
        -- How fast it walks, and until the courses went in this was read straight
        -- off the row every frame. It is baked here now for the reason every
        -- other number on an arrival is: what walked on at a doctorate in cycle
        -- three goes on being that, and nothing already standing on the page
        -- changes because the class did or because a minute went by. Which is
        -- also what makes the ramp behind this legible (SPEED_MOST in
        -- src/spawner.lua) -- the page you are looking at is a record of the
        -- minutes it arrived over rather than one number applied to all of it.
        --
        -- Two numbers rather than one because a wad has two speeds and they are
        -- different kinds of thing -- what it walks at and what it *falls
        -- forward* at (`charge` in Enemy.types). Scaling only the first would be
        -- a run that made the horde quicker and left the one enemy whose whole
        -- point is a sudden closing of distance exactly where it was. The lunge
        -- is 69px of a 96px trigger range at the row's own speed and 92 at the
        -- top of everything, so what the multiplier buys it is a shorter walk
        -- afterwards and never a charge that reaches from the edge of its range.
        speed = def.speed * spdMul,
        dashSpeed = def.charge and def.charge.speed * spdMul or nil,
        -- How many times over it was drawn: 1 for the ordinary horde, 2 for a
        -- champion (Spawner:elite) and 3 for a blow-up (Spawner:blown) -- the same
        -- monster, the same art, the same behaviour, bigger. It is a whole number
        -- because it is a sprite scale before it is anything else (Enemy:draw,
        -- Sprite:draw), which is also what bounds the idea at three: the standouts
        -- can only ever be whole multiples of the row, so there is no room between
        -- 2 and 3 to put a third one in. It is on the scale rather than on the row
        -- for the champion's reason: it is a fact about one arrival, so every kind
        -- that ever gets added can be blown up the day it lands.
        grow = grow,
        -- And the body grows with the drawing, which is the whole of what makes
        -- it fair. Every hit radius, every separation pass, the box, the pen
        -- lines and both spatial hashes read this field off the instance and
        -- never `def.radius` -- so a thing twice the size is twice as hard to
        -- miss and twice as hard to squeeze past, without a single weapon
        -- knowing the idea exists.
        radius = def.radius * grow,
        flash = 0,
        -- The recoil: which way it is being shoved, and how much of the shove
        -- is left. Purely a drawing offset -- see Enemy:footing -- which is why
        -- it lives beside `flash` and nowhere near `pushX/pushY`, the shove
        -- that really does move things.
        bumpX = 0, bumpY = 0, bumpT = 0,
        hitCooldown = 0,
        -- What it has taken since the page last said so, and the moment that
        -- reading opened (Game:spendHits). Kept here rather than at the dozen
        -- places that deal damage for the same reason the glue's multiplier is:
        -- everything arrives through Enemy:hurt, so there is exactly one place
        -- that has to count. `tookAt` is 0 for "nothing pending" -- the sweep
        -- stamps it the first frame it finds something, off the run clock, which
        -- is a clock Enemy:hurt has no business being handed.
        took = 0, tookAt = 0,
        pushX = 0, pushY = 0,
        frozen = 0,
        burnT = 0, burnTick = 0, -- on fire: see Enemy:ignite / Game:updateBurning
        bob = util.hash01(x, y, 9) * 2, -- desync the walk cycles
        -- Which way it prefers to round an obstacle, so a crowd meeting a wall
        -- head-on splits and goes both ways instead of filing along it.
        side = util.hash01(x, y, 13) < 0.5 and -1 or 1,
        slideX = 0, slideY = 0, slideT = 0,
        -- Shooters spawn mid-beat, half to one-and-a-half periods from firing,
        -- so a ring of them arriving together doesn't volley in sync.
        shotT = def.shot and def.shot.every * (0.5 + util.hash01(x, y, 17)) or nil,
        -- The charger's clock and where it has got to. `chargePhase` is nil for
        -- "walking like everything else" and otherwise one of wind / dash /
        -- rest, with `phaseT` counting down whichever it is in; `dashX,dashY`
        -- is the heading it locked when the wind started and rides out to the
        -- end whatever the player does about it. Seeded off the spawn point like
        -- the shot clock and for the same reason: a ring of wads arriving
        -- together must not wind up in unison.
        chargeT = def.charge and def.charge.every * (0.4 + util.hash01(x, y, 23)) or nil,
        chargePhase = nil,
        phaseT = 0,
        dashX = 0, dashY = 0,
        -- The trail clock, and where the last blot went: a boss standing still
        -- drops one puddle and stops, since the clock only pays out once it has
        -- walked clear of what it last put down (Game:updateEnemies).
        trailT = def.trail and def.trail.every or nil,
        -- The two tear clocks, and how many of the health thresholds have been
        -- passed. `rings` counts rather than flags because the thresholds are
        -- taken in order and never come back -- healing is not a thing in this
        -- game, so "how many have gone" is the whole state a ring needs.
        scatterT = def.tears and def.tears.scatter.every or nil,
        laneT = def.tears and def.tears.lane.every or nil,
        rings = 0,
        -- The whistle's clocks (Game:updateWhistle), and the same "how many of
        -- the thresholds have gone" count the rings keep, for the same reason.
        -- `blowT` is the wind-up in front of a blast, which it stands still for
        -- (Enemy:update); `volleys` is how many rings of the blast are still to
        -- come and `volleyT` how long until the next; `blareT` is how long the
        -- sound it just made is still drawn going out (Enemy:draw).
        blastT = def.whistle and def.whistle.blast.every * 0.6 or nil,
        jackT = def.whistle and def.whistle.jacks.every * 0.5 or nil,
        squadT = def.whistle and def.whistle.squad.every * 0.5 or nil,
        squads = 0, pumps = 0,
        blowT = 0, volleys = 0, volleyT = 0, gapA = 0, blareT = 0,
        -- Which of its views a `turns` body is showing (1-based, nil until it has
        -- first looked at you), and how long until it may step to the next.
        view = nil, viewT = 0,
        headX = 0, headY = 0, -- the way it is actually going, vs the way it wants to
        -- The ball an eye boss is drawn as, and how it gets about
        -- (src/eyeball.lua). nil on everything that is a sprite.
        eyeball = def.pupil and Eyeball.new() or nil,
        -- The die the MATHS boss is drawn as (src/dice.lua), painted the eye's
        -- way: nil on everything else.
        dice = def.dice and Dice.new(def.dice.shapes[1]) or nil,
        -- And the still life the ART boss is drawn as (src/plaster.lua), the
        -- same way again.
        plaster = def.still and StillLife.body() or nil,
        -- And the atom SCIENCE ends on at a master's (src/atom.lua): a nucleus
        -- painted the eye's way, with its orbits round it.
        nucleus = def.atom and Atom.new(def.atom.size, def.atom.rings,
            def.atom.first, def.atom.step) or nil,
        -- And the piggy bank FINANCE ends on at a master's (src/piggy.lua): a
        -- pig of ellipsoids painted the eye's way, facing where it goes.
        piggy = def.piggy and Piggy.new() or nil,
        -- And the tesseract MATHS ends on at a master's (src/tesseract.lua): a
        -- cube of cubes turned through four dimensions and drawn as lines.
        tesseract = def.tesseract and Tesseract.new() or nil,
        -- And what it decides to do (src/eyeboss.lua): the moves a row with
        -- `attacks` makes between walking at you. The brain steers through
        -- `drive` -- nil to chase like anything else, `hold` to stand, `seek` to
        -- walk at a point other than you, `dash` to run a locked line -- and
        -- takes it off the page entirely with `ghost` while it is underground or
        -- still falling onto it.
        -- The metronome's is the same socket with a different mind in it
        -- (src/metronome.lua): it keeps time rather than choosing moves off a
        -- rest, but steers through the same `drive`.
        -- The stamp's is the same socket again (src/stamp.lua): it leaps from
        -- cell to cell of the ledger and moves the body itself while it does.
        -- So is the dictionary's (src/dictionary.lua), which hops the same way.
        -- And the die's (src/diceboss.lua), which throws it rather than
        -- walking it: it holds `drive` and moves the body itself.
        -- And the still life's (src/stilllife.lua), which never walks at all:
        -- it holds, and lifts the whole table somewhere nearer when it must.
        -- And the atom's (src/atomboss.lua), which walks like the eye and
        -- splits itself in two.
        -- And the piggy bank's (src/piggyboss.lua), which trots and charges
        -- like a wad and throws its coins about.
        -- And the tesseract's (src/tesseractboss.lua), which drifts like the
        -- atom and turns out of the page to get about.
        brain = def.attacks and EyeBoss.new(def)
            or def.metronome and Metronome.new(def)
            or def.stamp and Stamp.new(def)
            or def.dictionary and Dictionary.new(def)
            or def.dice and DiceBoss.new(def)
            or def.still and StillLife.new(def)
            or def.atom and AtomBoss.new(def)
            or def.piggy and PiggyBoss.new(def)
            or def.tesseract and TesseractBoss.new(def) or nil,
        drive = nil, ghost = false,
        -- A heading for a `turns` body to face instead of you, while a brain
        -- wants it planted facing one way (the metronome's sweep); and how
        -- many pixels a brain has it off the ground (its hop on the beat).
        -- And which of its poses a body baked in several is in (`poses`, the
        -- stamp's stand / rear / lean / squash, the dictionary's shut / ajar /
        -- open), nil for the first.
        face = nil, hop = 0, pose = nil,
        slipT = 0, slipTurn = 0,
        -- Somewhere else to walk to, and how long it goes on being somewhere else
        -- (src/spiral.lua). Handed over rather than read off the page for the
        -- chill's reason below -- the weapons are stepped after the crowd has
        -- moved, so what a spiral said this frame is spent on the next one -- and
        -- it is a *lure* rather than a shove because being drawn into something
        -- has to be a thing this decides to do: it keeps walking, keeps jostling
        -- its neighbours and keeps hurting whoever is standing where it is going.
        lureX = 0, lureY = 0, lureT = 0,
        -- Slowed down by standing on the trail a skate left (src/skate.lua).
        -- Carried for a moment rather than read off the page, because the
        -- weapons are stepped after the crowd has moved -- so what is here is
        -- what the trail said last frame, which is the wax's `slipT` doing the
        -- same job for the same reason.
        chill = 1, chillT = 0,
        -- How long it goes on wearing the blue outline a bolt left on it
        -- (src/storm.lua). A readout and nothing else -- nothing reads it back
        -- -- but it is the only thing the storm says about *who* it hit: the
        -- strike itself is a third of a second of flash on a page full of marks,
        -- and a thing that walks out of it still lit is a thing you can follow.
        shockT = 0,
        -- Off the page: killed, or walked far enough behind you to be forgotten
        -- (Game:killEnemy, Game:updateEnemies). Nothing in the game held onto an
        -- enemy across frames until the storm did -- a cloud spends a couple of
        -- seconds arriving over the one it has marked -- and this is how the one
        -- thing that does can tell that what it is following is no longer there.
        gone = false,
        -- Time stood under the sun, when it was last stood there, and whether
        -- it has had enough of it: see Enemy:sunburn.
        soak = 0, soakAt = 0, bleached = false,
    }, Enemy)
end

-- Steers along a wall rather than into it. Not real pathfinding, but it reads
-- as the same thing from outside: an enemy that meets a pen line slides along
-- it and rounds the end, and it costs one grid lookup instead of a search.
function Enemy:avoidWalls(dx, dy, walls)
    local near, clearance, nx, ny
    walls:each(self.x, self.y, function(seg)
        local cx, cy, d = Walls.closest(seg, self.x, self.y)
        local clear = seg.r + self.radius
        if d < clear + WALL_LOOK and (near == nil or d < near) then
            near, clearance = d, clear
            nx, ny = Walls.normalOut(seg, self.x - cx, self.y - cy)
        end
    end)
    if not near then return dx, dy end

    -- Walking along it, or away from it, is nobody's problem.
    local into = -(dx * nx + dy * ny)
    if into <= 0 then return dx, dy end

    local tx, ty = -ny, nx
    if self.slideT > 0 then
        -- Already going round: keep going that way. Re-deciding every frame
        -- would park it at the point on the wall nearest the player, sliding a
        -- pixel one way and a pixel back, and it would never reach an end.
        if tx * self.slideX + ty * self.slideY < 0 then tx, ty = -tx, -ty end
    else
        local along = dx * tx + dy * ty
        if math.abs(along) <= 0.05 then
            if self.side < 0 then tx, ty = -tx, -ty end
        elseif along < 0 then
            tx, ty = -tx, -ty
        end
    end
    self.slideX, self.slideY, self.slideT = tx, ty, SLIDE_HOLD

    -- Turn harder the closer it is and the more squarely it is heading in, so
    -- a glancing approach barely bends and a head-on one turns to a slide.
    local blend = into * util.clamp((clearance + WALL_LOOK - near) / WALL_LOOK, 0, 1)
    local rx, ry = util.normalize(dx + (tx - dx) * blend, dy + (ty - dy) * blend)
    if rx == 0 and ry == 0 then return tx, ty end
    return rx, ry
end

-- Steering alone is only a suggestion: the horde behind would shove enemies
-- straight through the line. This is the part that makes ink solid.
function Enemy:resolveWalls(walls)
    if self.frozen > 0 then return end
    walls:each(self.x, self.y, function(seg)
        local cx, cy, d = Walls.closest(seg, self.x, self.y)
        local clear = seg.r + self.radius
        if d < clear then
            local nx, ny = Walls.normalOut(seg, self.x - cx, self.y - cy)
            self.x, self.y = cx + nx * clear, cy + ny * clear
        end
    end)
end

-- One beat of the wad's attack (`charge` in Enemy.types), and the only thing in
-- this file that takes the walk away from an enemy rather than bending it.
--
-- Returns whether it has the movement this frame. Standing still counts: a wad
-- winding up and a wad getting its breath back are both *doing* something, and
-- both of them are doing it instead of walking at you.
--
-- Three phases and one clock between them, which is what keeps this readable
-- from outside: `chargePhase` is nil for "walking like everything else", and
-- `phaseT` is however long is left of whichever of the three it is in.
function Enemy:charge(dt, player)
    local charge = self.def.charge

    -- A tool that moves the crowd wins, exactly as it does over the stand-off's
    -- circling: something told to walk into a spiral walks into the spiral, and
    -- a wind-up it was half way through is dropped rather than banked.
    if self.lureT > 0 then
        self.chargePhase = nil
        return false
    end

    if self.chargePhase == nil then
        self.chargeT = self.chargeT - dt
        if self.chargeT > 0 then return false end

        -- The beat is spent whether or not the player was in reach, the way a
        -- shooter's is (Game:updateEnemies): a clock that only ran in range
        -- would mean every wad that walked into 96 pixels dashed on the frame
        -- it arrived, and a telegraph you meet already lit is not a telegraph.
        self.chargeT = charge.every

        local dx, dy, dist = util.normalize(player.x - self.x, player.y - self.y)
        if dist > 0 and dist < charge.range then
            -- The heading is locked *here*, at the top of the wind, and never
            -- looked at again. Half a second later it is stale by however far
            -- the player has walked, and that gap is the whole attack: the red
            -- outline is not saying "I am about to hit you", it is saying where
            -- the line is going to be.
            self.chargePhase, self.phaseT = "wind", charge.wind
            self.dashX, self.dashY = dx, dy
        end
        return false
    end

    self.phaseT = self.phaseT - dt

    if self.chargePhase == "wind" then
        if self.phaseT <= 0 then
            self.chargePhase, self.phaseT = "dash", charge.time
        end
        return true
    end

    if self.chargePhase == "dash" then
        -- No wall steering, no lost footing, no chill: it is not walking, it is
        -- falling forward, and none of the three things that bend a walk have
        -- anything to bend. It still cannot end up *inside* a pen line --
        -- Enemy:resolveWalls gets the last word after the crowd has moved -- so
        -- a dash into ink is a dash that stops dead against it, which is the
        -- right thing to happen and costs nothing here to say.
        --
        -- The heading is written to `headX,headY` anyway, so that a wad coming
        -- off a dash onto wax carries the line it was on rather than snapping.
        self.headX, self.headY = self.dashX, self.dashY
        self.x = self.x + self.dashX * self.dashSpeed * dt
        self.y = self.y + self.dashY * self.dashSpeed * dt
        if self.phaseT <= 0 then
            self.chargePhase, self.phaseT = "rest", charge.rest
        end
        return true
    end

    -- Getting its breath, which is when it is worth killing: the clock for the
    -- next one has already been reset, so a wad that has just missed is a wad
    -- you have most of two seconds with, standing still, at arm's length.
    if self.phaseT <= 0 then self.chargePhase = nil end
    return true
end

function Enemy:update(dt, player, walls, slick)
    -- The eye follows you whatever else is happening to it -- glued, frozen,
    -- stood still -- because that is the one thing an eye does. Its gait
    -- answers a share of its speed (hopping, rolling, sat dizzy) which averages
    -- out to the row's own, so the speed on the row is still the fight.
    local gait = 1
    if self.eyeball then
        gait = self.eyeball:update(dt, self.x, self.y, player, self.frozen > 0)
    end

    -- And a body drawn from a ring of views turns to the one pointing at you,
    -- a view at a time (TURN_STEP), the short way round. Not while glued, for
    -- the pupil's reason inverted: a whistle stuck to the page is stuck the
    -- way it was pointing.
    if self.def.turns and self.frozen <= 0 then
        local n = #Sprites[self.def.turns]
        local a = self.face or math.atan2(player.y - self.y, player.x - self.x)
        local want = math.floor(a / (math.pi * 2) * n + 0.5) % n + 1
        if not self.view then
            self.view = want
        else
            self.viewT = self.viewT - dt
            if self.view ~= want and self.viewT <= 0 then
                local d = (want - self.view) % n
                self.view = (self.view - 1 + (d <= n / 2 and 1 or -1)) % n + 1
                self.viewT = TURN_STEP
            end
        end
    end
    self.blareT = math.max(0, self.blareT - dt)

    -- Glued: no chase, no drift, and any knockback it was carrying is dropped
    -- so it doesn't lurch the moment it comes unstuck. It can still be hit, and
    -- it still hurts the player who walks into it.
    if self.frozen > 0 then
        self.frozen = self.frozen - dt
        self.pushX, self.pushY = 0, 0
        self.flash = math.max(0, self.flash - dt)
        -- The recoil runs down while stuck too. It is a drawing and not a
        -- shove, so it is not the thing the line above drops -- a glued monster
        -- being shot still flinches, it just doesn't go anywhere.
        self.bumpT = math.max(0, self.bumpT - dt)
        self.hitCooldown = math.max(0, self.hitCooldown - dt)
        self.shockT = math.max(0, self.shockT - dt)
        -- Run down while stuck, unlike the chill and the lost footing above: a
        -- multiplier on a speed nothing is using costs nothing to keep, but a
        -- glued thing let go of two seconds later should not set off towards a
        -- spiral that is no longer on the page.
        self.lureT = math.max(0, self.lureT - dt)
        -- And a wind-up it was half way through, for the knockback's reason: a
        -- wad let go of four seconds later should not spend a heading it picked
        -- before it was stuck. Dropped rather than paused -- what it does when
        -- it comes free is wind up again, in front of you, at where you are now.
        self.chargePhase = nil
        return
    end

    self.slideT = math.max(0, self.slideT - dt)

    -- Either it is walking, or it is committed to a line it picked half a second
    -- ago (`charge`). The two are exclusive and nothing below this cares which:
    -- a shove still rides on top of a dash, and a dashing wad still bobs.
    local drive = self.drive
    if drive and drive.dash then
        -- Down a line the brain locked, at the brain's speed: the bowl. Nothing
        -- here steers it -- a pen line stops it in the wall pass and the box
        -- turns it round (EyeBoss:bowlRoll) -- which is what makes it a line.
        self.headX, self.headY = drive.dx, drive.dy
        self.x = self.x + drive.dx * drive.speed * dt
        self.y = self.y + drive.dy * drive.speed * dt
    elseif drive and drive.hold then
        -- Stood where the brain wants it, for a tell or a rest.
    elseif self.blowT > 0 then
        -- A whistle drawing breath for a blast stands where it is
        -- (Game:updateWhistle owns the clock), which is half of the tell: the
        -- red outline says something is coming and the stopping says it is not
        -- the lunge, which moves.
        self.headX, self.headY = 0, 0
    elseif not (self.def.charge and self:charge(dt, player)) then
        -- What it is walking at, which is the player unless something has
        -- offered it somewhere better. Everything after this -- the walls, the
        -- wax, the heading it keeps -- is untouched by the swap, so a lured
        -- thing rounds a pen line and skids on a crayon lane exactly as it
        -- would on its way to you.
        local tx, ty = player.x, player.y
        if drive and drive.seek then tx, ty = drive.x, drive.y end
        if self.lureT > 0 then
            self.lureT = self.lureT - dt
            tx, ty = self.lureX, self.lureY
        end

        -- Standing on the lure is standing still: normalize answers 0,0 for no
        -- distance at all, which is what makes a spiral a place a crowd gathers
        -- rather than a place it mills around the edge of.
        local dx, dy, dist = util.normalize(tx - self.x, ty - self.y)

        -- The stand-off (`keep`): close, circle, or back away. It reads the
        -- same heading everything else does and only turns it, so a shooter
        -- holding its distance still rounds a pen line, still skids on wax and
        -- still keeps a heading through a shove -- there is no second way of
        -- walking in here.
        --
        -- Deliberately below the lure rather than above it: something told to
        -- walk into a spiral walks into the spiral. Holding a range is what it
        -- does when nothing else has been decided for it, and a tool that
        -- overrules the crowd should overrule this exactly as it overrules a
        -- chase.
        local keep = self.def.keep
        if keep and self.lureT <= 0 and dist > 0 then
            if dist < keep.back then
                dx, dy = -dx, -dy
            elseif dist < keep.at then
                -- Round rather than away, so backing off is a retreat and
                -- holding station is a circle. `side` is the way it already
                -- prefers to round an obstacle, so a pair of them at the same
                -- range orbit opposite ways instead of shadowing each other.
                dx, dy = -dy * self.side, dx * self.side
            end
        end
        if walls.count > 0 then
            dx, dy = self:avoidWalls(dx, dy, walls)
        end

        -- On wax it can't get purchase to change direction: the heading it
        -- arrived with wins, and it only bends towards where it wants to go.
        -- The footing stays lost for a moment after it leaves the band, so a
        -- thing that skids off the end carries on skidding instead of turning
        -- on a pixel -- without that, a 13px band crossed at speed would be
        -- over too fast to feel. Anywhere else the heading snaps, exactly as it
        -- always has.
        if slick then
            self.slipT, self.slipTurn = SLIP_CARRY, slick.turn
        elseif self.slipT > 0 then
            self.slipT = self.slipT - dt
        end

        if self.slipT > 0 then
            local k = 1 - math.exp(-self.slipTurn * dt)
            local hx = self.headX + (dx - self.headX) * k
            local hy = self.headY + (dy - self.headY) * k
            local nx, ny = util.normalize(hx, hy)
            if nx ~= 0 or ny ~= 0 then dx, dy = nx, ny end
        end
        self.headX, self.headY = dx, dy

        -- Sky underfoot: the line a skate left behind the player, which takes
        -- a fraction of the legs off whatever is following him down it. A
        -- multiplier rather than a stop -- being glued is the gluestick's, and
        -- a crowd strung out along a line is what this is for.
        local speed = self.speed * gait
        if self.chillT > 0 then
            self.chillT = self.chillT - dt
            speed = speed * self.chill
        end

        self.x = self.x + dx * speed * dt
        self.y = self.y + dy * speed * dt
    end

    -- Knockback rides on top of the chase and bleeds off exponentially.
    if self.pushX ~= 0 or self.pushY ~= 0 then
        self.x = self.x + self.pushX * dt
        self.y = self.y + self.pushY * dt
        local decay = math.exp(-9 * dt)
        self.pushX, self.pushY = self.pushX * decay, self.pushY * decay
        if math.abs(self.pushX) + math.abs(self.pushY) < 1 then
            self.pushX, self.pushY = 0, 0
        end
    end

    self.bob = (self.bob + dt * 7) % 2
    self.flash = math.max(0, self.flash - dt)
    self.bumpT = math.max(0, self.bumpT - dt)
    self.hitCooldown = math.max(0, self.hitCooldown - dt)
    self.shockT = math.max(0, self.shockT - dt)
end

function Enemy:hurt(amount)
    -- Glue-stuck things take deeper cuts -- a gluestick level. Everything that
    -- deals damage arrives through this one door, so the multiplier rides on
    -- the enemy rather than being known to any of the dozen things that hit.
    -- Underground, or still falling onto the page: not there to be hit.
    if self.ghost then return false end
    -- A piece of the still life off its table (`stillpiece`): the hit is the
    -- boss's, softened and counted as the boss's, but lit and numbered here
    -- where it landed -- so the boss's own flash and recoil are put back as
    -- they were. Never answers that it died: the piece is not what dies, and
    -- the boss notices its own end on its own turn (src/stilllife.lua).
    if self.stand then
        local boss = self.stand
        local took, flash, bumpT = boss.took, boss.flash, boss.bumpT
        boss:hurt(amount)
        self.took = self.took + (boss.took - took)
        boss.took, boss.flash, boss.bumpT = took, flash, bumpT
        self.flash = HIT_FLASH
        return false
    end
    if self.glue and self.frozen > 0 and self.glue.soften then
        amount = amount * self.glue.soften
    end
    -- And a brain that has left it open (the die's fumble, src/diceboss.lua).
    if self.brain and self.brain.soften then amount = amount * self.brain:soften() end
    self.hp = self.hp - amount
    self.flash = HIT_FLASH
    -- The third piece of the same feedback as the two lines either side of it:
    -- the thing is lit, it is knocked back, and it is heard. Here for the reason
    -- all of that is here -- thirty things in the game deal damage and every one
    -- of them arrives through this door -- and that is also what makes the sound
    -- affordable. A built run lands four passives, a mark and a tool on twenty
    -- bodies a second, so a hit sound needs thinning out; one door means one
    -- place to thin it, which is the gap on its row (src/sfx.lua) rather than a
    -- clock kept here or a rule any of the thirty callers has to know.
    Sfx.play("gethit")

    -- Which way it flinches. Nothing that deals damage is handed to this door --
    -- there are thirty of them and they arrive with a number and nothing else --
    -- so the direction is taken off the thing that was hit rather than off the
    -- thing that hit it: backwards along the way it was walking. It is walking
    -- at you, so backwards is away from the hit for nearly every hit on the
    -- page, and it costs the thirty callers nothing to be right about it.
    --
    -- Something with no heading at all -- gathered on a spiral, or hit on the
    -- frame it walked on -- jolts downwards instead, because a hit that moves
    -- nothing at all reads as a hit that missed.
    local bx, by = -self.headX, -self.headY
    if bx == 0 and by == 0 then bx, by = 0, 1 end
    self.bumpX, self.bumpY, self.bumpT = bx, by, HIT_BUMP_TIME
    if self.eyeball then self.eyeball:jolt(amount / self.maxHp) end
    -- Counted after the softening and not before it, so what is added up is what
    -- was actually taken off the thing.
    Enemy.dealt = Enemy.dealt + amount
    -- Added up rather than announced. Two weapons landing on the same enemy in
    -- the same frame are one thing that happened to it, and the page says so
    -- with one number; Game:spendHits is what decides when the total has stood
    -- still long enough to be worth reading.
    self.took = self.took + amount
    return self.hp <= 0
end

-- `knock` on the row is what a shove is worth against this thing, and it exists
-- for exactly one reason: a boss that can be bowled across the page by a pin is
-- a boss you never have to look at. It rides here rather than at the dozen
-- places that shove, the same way the glue's damage multiplier rides on
-- Enemy:hurt.
function Enemy:knockback(nx, ny, force)
    force = force * (self.def.knock or 1)
    self.pushX = self.pushX + nx * force
    self.pushY = self.pushY + ny * force
end

-- Given somewhere else to walk to for a while (src/spiral.lua). Set rather than
-- added to: a thing standing in two spirals is being pulled into whichever spoke
-- to it last, which is the only answer that does not need a rule of its own.
function Enemy:lure(x, y, hold)
    self.lureX, self.lureY, self.lureT = x, y, hold
end

-- Sent flying hard enough to matter -- the rubber's last level. A launch gets
-- a fresh hit list, so an enemy rubbed at again can bowl over the same thing
-- again; what counts as still flying is Game:updateRams' threshold on the push
-- speed, which is also what quietly ends the state -- a glued enemy drops its
-- push and stops being a projectile the same frame.
function Enemy:launch(ram)
    self.ram = { damage = ram.damage, hit = {} }
end

-- Set alight -- the highlighter's last level (src/upgrades.lua). Touching the
-- ink again refreshes the burn rather than stacking it, so standing on the band
-- holds it at full and leaving starts the clock. The first tick lands at once:
-- catching fire is felt the moment it happens, not a beat later. The block is
-- kept by reference, the way a rocket keeps the numbers it was fired with --
-- an upgrade mid-burn changes the next fire, not this one.
function Enemy:ignite(burn)
    if self.burnT <= 0 then self.burnTick = 0 end
    self.burnT = math.max(self.burnT, burn.time)
    self.burn = burn
end

-- Left out in the sun (src/sun.lua). Exposure is *counted* rather than timed
-- from a start: a thing that walks in and out of the disc is judged on the total
-- it has stood under it, and what it soaked up is forgotten again once it has
-- been out of the light for SOAK_COOL. That is what makes this "stayed under too
-- long" rather than "was under it once", and it is why the sun does not need to
-- keep a list of who is in it.
--
-- Past the limit it is bleached for good and carries a grey ghost of its own
-- outline for the rest of its life (Enemy:draw) -- the mark is the only thing
-- the sun tells you about what it did, since nothing under a solid disc can be
-- seen while it is happening. Returns true the one time it crosses, so the
-- caller can spend a splat on the moment.
function Enemy:sunburn(amount, limit, now)
    if now - self.soakAt > SOAK_COOL then self.soak = 0 end
    self.soakAt = now
    if self.bleached then return false end

    self.soak = self.soak + amount
    self.bleached = self.soak >= limit
    return self.bleached
end

-- Struck by lightning (src/storm.lua), and all that means here is the outline it
-- wears afterwards. The damage landed in the same breath through Enemy:hurt like
-- everything else in the game; this is the second the bolt is still on it.
--
-- Held at the longest rather than added to, the way a burn is: two bolts into the
-- same thing is one thing lit for a second, not one lit for two.
function Enemy:shock(duration)
    self.shockT = math.max(self.shockT, duration)
end

-- Returns true only the first time, so the caller can spend a splat on it.
-- `glue` is the tool doing the sticking, when a tool is: the enemy carries it
-- for as long as it is held, which is how the gluestick's upper levels --
-- deeper cuts while stuck (Enemy:hurt), the tear on the way loose
-- (Game:updateGlue) -- know their victim without the tool keeping a list.
-- A pin's or a staple's hold passes nothing and grants nothing, with one
-- exception: a staple with paste on it (`tacky`, the CLINCH) hands over its own
-- *block*, which is the one thing here that is not a whole tool. Nothing minds --
-- what is read off this afterwards is `soften` and `tear` by name, and a block may
-- carry either.
function Enemy:freeze(duration, glue)
    local wasFree = self.frozen <= 0
    -- `hold` is the same bargain `knock` makes: a boss glued for the full four
    -- seconds is a boss that is not a fight, so it shrugs most of it off. It is
    -- never zero -- a tool that visibly does nothing is worse than one that does
    -- a little -- and it is scaled rather than capped, so every level of the
    -- gluestick line still buys something against it.
    self.frozen = math.max(self.frozen, duration * (self.def.hold or 1))
    if glue then self.glue = glue end
    return wasFree
end

-- The four offset masks every outline on an enemy is made of: its own
-- silhouette one pixel out in every direction, drawn *under* the body rather
-- than over it, so what it says is "that one" about something that still reads
-- as what it was. Four masks rather than authored art because the thing being
-- outlined may be any sprite in the game, including a page's own reskin of it.
--
-- Four things wear one and only one of them is ever seen, since all four are the
-- same four masks in different colours. Enemy:outlineColour is where they are
-- ranked, in the order they are worth.
-- The rim stays one pixel whatever size the body is: `s` scales the silhouette
-- and never the offsets. A blow-up's rim scaled with it would be a two-pixel
-- band, which is a different mark on the page -- and the rim is a *word* rather
-- than a decoration, so it has to look the same on a bat as on a grin twice the
-- size of one.
local function outline(sprite, x, y, colour, s)
    love.graphics.setColor(colour)
    sprite:drawMask(x - 1, y, nil, s)
    sprite:drawMask(x + 1, y, nil, s)
    sprite:drawMask(x, y - 1, nil, s)
    sprite:drawMask(x, y + 1, nil, s)
end

-- Which sprite it is and where it is standing this frame. Two callers -- the
-- thing itself and the blank it stamps into the page under it -- and they have to
-- agree to the pixel: a blank a pixel off the body would print a paper rim along
-- one edge of the bob and nowhere else.
function Enemy:footing()
    -- Stuck things stop bobbing, and an eye boss has a gait of its own instead
    -- (src/eyeball.lua) that a one-pixel jog on top of would only blur.
    local bob = self.frozen <= 0 and self.bob >= 1 and not self.eyeball and not self.dice
        and not self.plaster and not self.nucleus and not self.piggy and not self.tesseract
    local y = bob and self.y - 1 or self.y
    -- And a body a brain has hopping (the metronome's walk on the beat), lifted
    -- off its shadow: drawing only, for the recoil's reason below.
    if self.hop and self.hop > 0 then y = y - self.hop end

    -- An enraged arrival is its own art in two colours, and it is swapped in
    -- here rather than at the draw so that both callers get the same answer: the
    -- twin is the same shape at the same origin, so the blank stamped under it is
    -- the blank the ordinary body would have had, and asking twice in two places
    -- would be two chances for that to stop being true.
    local sprite = Sprites.enemy(self.def.sprite)
    if self.fury then sprite = Sprites.enraged(sprite) end
    -- A body drawn from a ring of views is whichever one it has turned to, so
    -- the blank under it is that view's too.
    -- And one baked in poses is that view of whichever pose the brain has it in.
    if self.def.turns and self.view then
        local ring = Sprites[self.def.turns]
        if self.def.poses and self.pose then ring = Sprites[self.def.poses][self.pose] or ring end
        sprite = ring[self.view]
    end

    -- The recoil is folded in here and never into x/y, for both of the reasons
    -- this function exists. Where a thing is *standing* is what every hit
    -- radius, every separation pass and both spatial hashes are reading, and
    -- three pixels of flinch is not worth lying to them about -- a monster you
    -- could miss by shooting it would be the one unfair thing on the page. And
    -- the blank stamped under the body comes out of this same answer, so a body
    -- that jolted without its blank would drag the ruling through itself for a
    -- tenth of a second on every hit.
    --
    -- It slides home linearly, which on a whole-pixel grid is what makes it read
    -- as a recoil rather than as a wobble: 3, 2, 1, 0 is four held frames going
    -- one way, and an eased curve would spend most of them at the same pixel.
    --
    -- And a whistle drawing breath shudders a pixel side to side, which is the
    -- other half of its tell and belongs here for the recoil's reason.
    local x = self.x
    if self.blowT > 0 then x = x + (math.floor(self.blowT * 24) % 2 == 0 and 1 or -1) end
    if self.bumpT > 0 then
        local k = HIT_BUMP * (self.bumpT / HIT_BUMP_TIME)
        return sprite, x + self.bumpX * k, y + self.bumpY * k
    end
    return sprite, x, y
end

-- Which outline it is wearing this frame, or nil for none: the four ranked, most
-- urgent first. All four are things happening *to* it or being done *by* it, which
-- they were not always -- the champion used to sit at the bottom of this list in
-- ink, and it was the one entry that was neither. It says itself with the page now
-- (ELITE_GROW, src/spawner.lua), and what that leaves behind is a ranking where
-- every rim is temporary and none of them is a fact about how the thing arrived. Answering it once rather than laying four masks over each other
-- also makes this the single place that knows whether there is an outline at all,
-- which Enemy:drawSolid needs -- a wind-up blinking one frame out of step between
-- the body and the blank under it would leave a paper rim round the sprite.
--
-- Just hit, in red, and top of the ranking because it is the only one of the
-- four that is about this exact instant rather than about a state the thing is
-- in -- for a tenth of a second, what it is doing matters less than what just
-- happened to it. Red because red is the spark that comes off anything taking a
-- hit everywhere else in the game (src/palette.lua), and because the rim is
-- what keeps the paper stage of the flash from reading as the monster
-- vanishing: the rim is the shape, and the hole inside it is the impact.
--
-- Winding up, or already coming (Enemy:charge), in red: theirs, and the one
-- outline here that is a *warning* rather than a record of something that has
-- already happened to it. The wind-up blinks and the dash does not, which is the
-- whole of the tell -- a flashing wad is a line about to be drawn and there is
-- still time to step off it, a solid one is the line. Blinked off the phase clock
-- rather than off the run's, so every wad on the page flashes to its own beat; a
-- rank of them pulsing in unison would read as one thing. The blink falls through
-- to whatever is underneath rather than to nothing, because a sunburnt wad halfway
-- through a wind-up is still sunburnt on the frames the red is out.
--
-- Just struck, in blue rather than red because the bolt is yours and red is
-- theirs. It is the one outline here that goes away again: a sunburn is what a
-- thing carries for the rest of its life, this is what it is wearing now.
--
-- Sun-bleached, in graphite: it has been stood in the sun, and the one rim here
-- that is a record rather than an instant or a warning.
--
-- Deliberately never more than the one pixel out. Every hit radius in the
-- game is the number on the row (Enemy.types) and a silhouette that lied about it
-- by four pixels would be the one unfair thing on the page -- the same bargain a
-- page's reskin makes (Sprites.enemySkins), for the same reason.
function Enemy:outlineColour()
    if self.flash > 0 then return Palette.red end
    if self.chargePhase == "dash" then return Palette.red end
    if self.chargePhase == "wind" and math.floor(self.phaseT * 14) % 2 == 0 then
        return Palette.red
    end
    -- A whistle drawing breath for a blast blinks the same red the wind-up does
    -- and for the same reason: it is a warning, and there is one way to say one.
    if self.blowT > 0 and math.floor(self.blowT * 14) % 2 == 0 then
        return Palette.red
    end
    if self.shockT > 0 then return Palette.blue end
    if self.bleached then return Palette.graphite end
end

-- Whether this arrival is a blow-up rather than a champion or an ordinary body.
-- Both standouts carry a `grow`, and `elite` is the only thing that tells them
-- apart -- which is what that field is for now that neither of them wears a rim.
--
-- Exactly one thing asks: a blow-up that splits leaves something different from
-- what a champion or an ordinary one leaves (`split.blown` in Enemy.types,
-- Game:splitEnemy). Nothing else in the game needs to know which roll produced a
-- monster, and nothing else should -- the point of both standouts is that they
-- are the same monster.
function Enemy:isBlown()
    return self.grow > 1 and not self.elite
end

-- The blank stamped into the page under it, from inside Overprint.beginSolid:
-- exactly the pixels the body is about to cover and not one more, so the ruling
-- and whatever else the page is printed with stop where the thing standing on
-- them starts. One pixel more when it is wearing an outline, the outline being
-- part of the silhouette rather than a mark on the paper.
--
-- Not the shadow, which is the one thing here that really is on the paper: a
-- smear of graphite goes on darkening over a rule like every other mark.
function Enemy:drawSolid()
    -- A still life's piece off the table is painted by its brain, where it is.
    if self.stand then return end
    local sprite, x, y = self:footing()

    if self.eyeball then
        love.graphics.setColor(Palette.paper)
        self.eyeball:drawMask(x, y, self:outlineColour() and 1 or 0)
        return
    end
    local painted = self.dice or self.plaster or self.nucleus or self.piggy
        or self.tesseract
    if painted then
        love.graphics.setColor(Palette.paper)
        painted:drawMask(x, y, self:outlineColour() and 1 or 0)
        return
    end

    love.graphics.setColor(Palette.paper)
    if self:outlineColour() then outline(sprite, x, y, Palette.paper, self.grow) end
    sprite:drawMask(x, y, nil, self.grow)
    -- The metronome's arm, which stands off the body and so needs its own blank.
    if self.def.metronome then self.brain:drawArm(self, x, y, Palette.paper) end
end

function Enemy:draw()
    if self.stand then return end
    local sprite, x, y = self:footing()
    local stuck = self.frozen > 0

    -- Which colour the body is wearing this frame, or nil for its own art. Two
    -- steps down the ramp rather than one: blown out to paper for the first
    -- couple of frames and dropping back through blush on the way out, which is
    -- how every other fade in the game is done and is what makes this read as a
    -- flash going off rather than as a light being switched on and off. Paper is
    -- the page's own colour, so what that first step actually draws is a hole in
    -- the shape of the thing, inside the red rim Enemy:outlineColour puts round
    -- it -- the two are one effect and neither works alone.
    local lit
    if self.flash > 0 then
        lit = self.flash > HIT_FLASH - HIT_WHITE and Palette.paper or Palette.blush
    end

    -- Stuck: the shadow turns into a smear of glue. It is also the one thing
    -- here that does not move with the recoil: the shadow is on the paper and
    -- the body is what was hit, so the body kicking off its own shadow is most
    -- of what sells the flinch as a flinch.
    love.graphics.setColor(stuck and Palette.sky or Palette.graphite)
    -- Wider *and* thicker on a blow-up, both off the same `grow`: what is on the
    -- paper under a body twice the size is a mark twice the size, and a big thing
    -- standing on a one-pixel line would read as hovering over the page. The
    -- glue's own two pixels are scaled with it for the same reason -- a smear is
    -- as wide as the foot that is stuck in it.
    local grow = self.grow
    local shadow = (self.def.shadow + (stuck and 2 or 0)) * grow
    -- A ball in the air leaves less of a mark under it, and a squashed one more.
    if self.eyeball then
        shadow = math.floor(shadow * self.eyeball:shadowScale() + 0.5)
    end
    -- And a die off the page altogether (opened out into its net, or up out of
    -- sight in its leap, where the brain draws the shadow coming down itself)
    -- leaves none; one in the air leaves less of one the higher it is.
    -- The still life leaves none of its own: its shadows are thrown by its
    -- lamp, and drawn by its brain (src/stilllife.lua).
    local painted = self.dice or self.plaster or self.nucleus or self.piggy
        or self.tesseract
    if painted then
        if painted.hidden then return end
        shadow = math.floor(shadow * painted:shadowScale(self.hop, stuck) + 0.5)
    end
    -- Struck off the bottom edge of the sprite -- `h - oy` -- rather than off
    -- half its height, which is Sprites.shadow's own expression and makes it the
    -- one rule in the game for where a thing stands. Half the height was the
    -- same number for every enemy authored at its own centre, and stops being
    -- one the moment a skin is drawn taller than the enemy it replaces
    -- (Sprites.enemySkins): the headroom it grows into is on the top of the
    -- grid, so `h` moves and `h - oy` does not, and the feet stay where they
    -- were. It also puts the shadow under the odd-height enemies rather than one
    -- pixel inside them, which is what half the height was quietly doing.
    --
    -- `ground` on the row says where the feet are instead, for a body whose box
    -- is not its footprint: the stamp's poses share one box (art/stamp.py), and
    -- the bottom of it is the bottom of the lowest pose rather than the edge of
    -- the pad it stands on.
    love.graphics.rectangle("fill",
        math.floor(self.x) - math.floor(shadow / 2),
        math.floor(self.y) + ((painted and painted.ground) or self.def.ground
            or (sprite.h - sprite.oy)) * grow - 1,
        shadow, (stuck and 2 or 1) * grow)

    local ring = self:outlineColour()

    -- The eye boss is painted rather than stamped (src/eyeball.lua), but wears
    -- the same rim and the same flash as everything else: a silhouette one out,
    -- then the body blown out to the flash colour, pupil and all -- a white body
    -- with a pupil still in it would read as the hit landing on something else.
    if self.eyeball then
        if ring then
            love.graphics.setColor(ring)
            self.eyeball:drawMask(x, y, 1)
        end
        if lit then
            love.graphics.setColor(lit)
            self.eyeball:drawMask(x, y, 0)
        else
            self.eyeball:draw(x, y)
        end
        return
    end
    -- The die the same way, off its own painter (src/dice.lua), and the still
    -- life off its (src/plaster.lua).
    if painted then
        if ring then
            love.graphics.setColor(ring)
            painted:drawMask(x, y, 1)
        end
        if lit then
            love.graphics.setColor(lit)
            painted:drawMask(x, y, 0)
        else
            painted:draw(x, y)
        end
        return
    end

    if ring then outline(sprite, x, y, ring, grow) end

    -- The metronome's arm is plotted live (src/metronome.lua), behind the body
    -- when the panel it swings in front of is turned away from you and in front
    -- of it otherwise -- so from behind, all you see of it is the tip going
    -- over the top.
    local arm = self.def.metronome and self.brain
    local armFront = arm and Metronome.armInFront(self.view or 1)
    if arm and not armFront then arm:drawArm(self, x, y, lit) end

    if lit then
        love.graphics.setColor(lit)
        sprite:drawMask(x, y, nil, grow)
    else
        love.graphics.setColor(1, 1, 1)
        sprite:draw(x, y, nil, grow)
    end
    if armFront then arm:drawArm(self, x, y, lit) end

    -- The blast going out (`blareT`, set by Game:updateWhistle). Two rings a
    -- third of the reach apart, plotted a pixel at a time like every circle in
    -- the game.
    if self.blareT > 0 then
        local f = 1 - self.blareT / BLARE_TIME
        love.graphics.setColor(Palette.red)
        for k = 0, 1 do
            local r = self.radius + (f - k / 3) * BLARE_REACH
            if r > self.radius then
                pixelart.circleOutline(math.floor(self.x), math.floor(self.y), math.floor(r))
            end
        end
    end

end

return Enemy
