# WORKSHEETS.md

Little puzzles printed on the page -- the worksheets a run walks past -- that
pay you for stopping to solve one while the horde keeps coming. This file is the
idea list. What has shipped is ticked, and its argument lives in `README.md`
(**Worksheets on the page**) and its wiring in `DESIGNDOC.md` (**Worksheets**)
like everything else; `src/worksheet.lua` is the code.

It belongs to `ROADMAP.md`'s **Stage hazards / gimmicks**: lessons that differ in
*where* you fight as well as *what* comes, with one puzzle per subject.

## Rules every worksheet keeps

- **The horde never stops.** A sum is easy; a sum with skulls closing in is the
  game. So nothing takes more than ten or fifteen seconds, and nothing needs
  small text -- the face is 3x5, which rules out word searches, crosswords and
  spot-the-difference.
- **It is answered the way the book answers everything: by drawing, or by
  walking.** Nothing reads handwriting. A cell is *scribbled in*
  (ground covered on a 2px grid, `src/scribble.lua`'s rule), an answer is
  *stood on*.
- **It is a place on the page, not a beat on a clock.** Worksheets sit at fixed
  spots hashed off the run's seed, exactly like the fixed pickups
  (`src/pickup.lua`): found, remembered, once each per run.
- **Failure costs something but never ends the run.** A spawned giant or a lost
  prize is a better story than "nothing happens".
- **Eight colours, whole pixels, `I18n.t`.** The puzzles are written in notation
  rather than words wherever possible, because notation needs no translation.

## Built

- [x] **Tic-tac-toe** (every lesson). A 3x3 grid ruled on the page with the game
      already in play: red O's, black X's, and one cell that finishes three X's
      in a row. Scribble a cross into it and the line is drawn through the three
      and a **coin** drops. Scribble into a cell that does not win and the page
      plays its O there instead: no coin, the sheet is spent.
- [x] **Pop quiz on the board** (MATHS). A question on a board and three answers
      ruled out on the page under it. **Stand on an answer until the circle round
      it has finished drawing.** Right is a **diamond**; wrong is a **giant**
      (a random enemy of the minute, at three times the size) walking in from the
      ring, and the right answer circled for next time.
      The questions climb with the course:
  - **HIGH SCHOOL** -- two-digit sums and differences, times tables, exact
    division, order of operations, squares, fractions over one denominator.
  - **BACHELOR** -- fractions added, taken away, multiplied and divided; powers,
    square roots, a linear equation, factorials.
  - **MASTERS** -- combinations and permutations, factorial ratios, a quadratic's
    roots, logarithms, a derivative, Gauss's sum.
  - **PHD** -- definite and indefinite integrals, a limit, Euler's identity, the
    chain and product rules, a binomial sum -- and a masters question now and then.

## Ideas, one per lesson

| Lesson | Puzzle | How you answer | Fail state |
| --- | --- | --- | --- |
| **MATHS** | ~~Sum on the board~~ -- built as the pop quiz | Stand on the answer | A giant |
| **MATHS** (alt) | **Sequence** `2, 4, 6, _`, or a 4x4 mini-sudoku with one cell missing | Stand on / scribble the number | Grid fades |
| **GRAMMAR** | **Hangman**: blanks on the page, letters scattered as pickups | Collect letters; a wrong one adds a limb | Hanged: the hanged man climbs down as a champion |
| **ART** | **Join the dots** (not "dot to dot" -- that is a fusion's name): numbered dots, drawn through in order, reveal a picture | Pencil through the dots in order | The dots wander off |
| **ART** (alt) | **Trace the shape**: a dashed star or heart traced within a tolerance | Pencil | -- |
| **MUSIC** | **Simon says**: four notes on a stave light in order | Tap them back | Wrong note: a sting, and the crowd near you goes into fury |
| **SCIENCE** | **Close the circuit**: battery and bulb with a gap in the wire | A **pen** line across the gap -- pen lines are walls already (`src/walls.lua`) | -- |
| **SCIENCE** (alt) | **Memory pairs**: six face-down cards | Scribble two to flip them | Cards reshuffle |
| **FINANCE** | **Exact change**: a price tag, coins scattered round it | Collect exactly that amount | Overpay and the change is lost |
| **P.E.** | **Hopscotch**: ten squares, 1 to 10 | Step on them in order against a timer | Time runs out |
| any | ~~Tic-tac-toe~~ -- built | Scribble a cell | The page plays its O |
| any | **Maze worksheet**: a little printed maze, the prize in the middle | Pencil from the mouth to the middle without touching a wall | Touch one and start again |
| any | **True or false**: one statement, two boxes | Stand on one | -- |

### Tic-tac-toe twists not built (yet)

- **The horde plays O.** Any monster that walks into a cell claims it, so you
  race to finish your line before the crowd fills the grid -- and a kill inside
  a cell wipes its O.
- **Kills are your X.** A kill standing in a cell marks it X: the grid becomes a
  patch of ground to fight on rather than a menu.
- **A deliberately weak opponent** for a full game: a win is a diamond, a draw a
  heart.

## Rewards, from least to most disruptive

- **The pickups that already exist** -- heart, ink, diamond (a whole level), and
  the coin (`banked`, one into the purse). The built two use the coin and the
  diamond.
- **Coins paid straight into the purse** as a run term -- this touches
  `Game:runWorth`, and README argues for every payout term, so it would want its
  own paragraph.
- **A free reroll or skip** on the next draft.
- **A short buff** -- a gold star: ten seconds of double damage.
- **The book's back pages** -- homework rows ("solve ten worksheets", "finish a
  hangman without a limb"), tally counters, a worksheets shelf in the library:
  rows in `Challenges.sections` and `Collection.gates`.

## Costs to remember

- **Hangman is word lists in six languages**, short, and only in what the 3x5
  face can draw. The most expensive idea per unit of fun. Sums, mazes, circuits
  and Simon need no translation beyond a title.
- **Placement**: fixed spots (findable, worth exploring for) rather than a timed
  pop-quiz event, for the reason the fixed pickups give: a place you found beats
  a beat on a clock.
