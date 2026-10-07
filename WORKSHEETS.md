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
- [x] **Sequence on the board** (MATHS). The pop quiz's board with a run of
      numbers and the next one missing, answered the same way. Right is a
      **heart**; wrong is **20 HP** off the bar. The runs climb with the course:
  - **HIGH SCHOOL** -- counting up or down in steps, doubling, two steps in turn.
  - **BACHELOR** -- squares, triangular numbers, a ratio, primes, halving.
  - **MASTERS** -- Fibonacci from a rolled start, cubes, factorials, one off a
    power of two, a quadratic, a ratio that flips sign.
  - **PHD** -- Catalan, Bell, partitions, derangements, Lucas, `n^n`,
    tribonacci, look-and-say -- and a masters run now and then.

- [x] **Lab board** (SCIENCE). The pop quiz's board asking out of a science
      book (`Quiz.science`): units, formulae and equations, in notation -- `M/S`,
      `Ω`, `H_2O`, an arrow between two sides. Right is a **diamond**; wrong is
      a **giant** -- an experiment gone wrong grows something.
  - **HIGH SCHOOL** -- speed, `F = MA`, Ohm's law, Celsius to Kelvin (with
    Fahrenheit as the trap), counting the atoms in a formula.
  - **BACHELOR** -- a missing coefficient in an equation to balance, molar
    mass, kinetic energy, resistors in parallel, `P = VI`, pH.
  - **MASTERS** -- `E = MC^2`, half-life, the inverse square law, Boyle's law,
    `P = I^2R`, oxidation states (the peroxide and ammonia traps).
  - **PHD** -- Bohr's energy levels, the Lorentz factor, neutrons out of
    fission, alpha and beta decay, Stefan-Boltzmann's fourth power, which `L` a
    shell holds, the oxidation state in a dichromate or permanganate -- and a
    masters question now and then.
- [x] **Till board** (FINANCE). The same board asking out of `Quiz.finance`.
      Right is **three coins** under the answer, into the purse -- the one board
      whose prize outlives the run; wrong is a **giant**.
  - **HIGH SCHOOL** -- a discount, a markup, change from a note, a receipt
    added up, the price of one.
  - **BACHELOR** -- simple interest, a markup against a margin, down and back
    up by the same percent, tax taken back out, two rises compounded.
  - **MASTERS** -- compound interest, the rule of 72, Fisher's real rate,
    break-even, up and down the other way round.
  - **PHD** -- present value, the growing perpetuity, the effective rate of a
    monthly one, a bond against its yield, put-call parity -- and a masters
    question now and then.
- [x] **Stave board** (MUSIC). The same board asking out of `Quiz.music`, with
      six notes drawn on it (whole, half, quarter, eighth, two beamed eighths,
      two beamed sixteenths; a dot dots one). Right is a **heart**; wrong is
      **20 HP** off the bar -- a wrong note stings.
  - **HIGH SCHOOL** -- whole, half and quarter notes added up, how many of one
    go into another, a bar of 2/4, 3/4 or 4/4 with its last note missing.
  - **BACHELOR** -- dotted notes and eighths added up, harder bars, seconds at
    a tempo.
  - **MASTERS** -- compound time (6/8, 9/8, 12/8), one note's length at a tempo,
    sixteenths, the harmonic series, beats between two tones.
  - **PHD** -- equal temperament (`440HZ × 2^{7/12}`), metric modulation
    (`♩ = 120, ♩. = ♩ → ♩ = ?`), odd meters, a dotted beat -- and a masters
    question now and then.

- [x] **Simon says** (MUSIC). A hand bell over four notes, each written on a
      scrap of stave where it sits (D, E, G, A). **Walk onto the bell or draw
      over it** and it plays a tune on the four, each lighting as it sounds;
      then **walk the notes in the same order**. Before the bell is rung the
      notes just play, like an instrument. Right is a **heart**. A wrong note
      sounds sour (a semitone clash) and starts you over; the third
      fades the whole sheet off the page. The tune is 3 notes at HIGH SCHOOL, 4
      at BACHELOR, 5 at MASTERS and 6 at PHD, never one note twice running.
      The notes sit on the corners of a square, the one layout where any note
      can be walked to from any other without crossing a third, and the bell is
      above it, off every line between two. It lights as well as sounds, so it
      can be played on mute.

### What the built seven pay

| Board | Where | Right | Wrong | Stakes |
| --- | --- | --- | --- | --- |
| Tic-tac-toe | every lesson | a coin (into the purse) | the page plays its O; nothing lost | none: a free try |
| Pop quiz | MATHS | a diamond (a whole level) | a giant walks in off the ring | power, against trouble |
| Sequence | MATHS | a heart (+25 HP) | 20 HP off the bar | health, both ways |
| Lab | SCIENCE | a diamond | a giant | power, against trouble |
| Till | FINANCE | three coins (into the purse) | a giant | the purse, against trouble |
| Stave | MUSIC | a heart | 20 HP off the bar | health, both ways |
| Simon | MUSIC | a heart | three wrong notes fade the sheet away | none: a lost prize |

On MATHS the page prints them 2 quiz : 2 sequence : 1 tic-tac-toe, on MUSIC
2 stave : 2 Simon : 1 tic-tac-toe, and on SCIENCE and FINANCE 2 of their board :
1 tic-tac-toe (the `worksheets`
rows in `src/subjects.lua`). GRAMMAR, ART and P.E. print only tic-tac-toe until
they have a puzzle of their own.

## Ideas, one per lesson

| Lesson | Puzzle | How you answer | Fail state |
| --- | --- | --- | --- |
| **MATHS** | ~~Sum on the board~~ -- built as the pop quiz | Stand on the answer | A giant |
| **MATHS** (alt) | ~~Sequence~~ -- built; a 4x4 mini-sudoku with one cell missing is still an idea | Stand on the number | 20 HP |
| **SCIENCE** | ~~Lab board~~ -- built | Stand on the answer | A giant |
| **FINANCE** | ~~Till board~~ -- built | Stand on the answer | A giant |
| **MUSIC** | ~~Stave board~~ -- built | Stand on the answer | 20 HP |
| **GRAMMAR** | **Hangman**: blanks on the page, letters scattered as pickups | Collect letters; a wrong one adds a limb | Hanged: the hanged man climbs down as a champion |
| **ART** | **Join the dots** (not "dot to dot" -- that is a fusion's name): numbered dots, drawn through in order, reveal a picture | Pencil through the dots in order | The dots wander off |
| **ART** (alt) | **Trace the shape**: a dashed star or heart traced within a tolerance | Pencil | -- |
| **MUSIC** | ~~Simon says~~ -- built: a bell plays a tune on four notes | Walk them back in order | Three wrong notes and the sheet fades (the sting and the fury were dropped: a wrong note is already sour, and the stave charges health) |
| **SCIENCE** | **Close the circuit**: battery and bulb with a gap in the wire | A **pen** line across the gap -- pen lines are walls already (`src/walls.lua`) | -- |
| **SCIENCE** (alt) | **Memory pairs**: six face-down cards | Scribble two to flip them | Cards reshuffle |
| **FINANCE** | **Exact change**: a price tag, coins scattered round it | Collect exactly that amount | Overpay and the change is lost |
| **P.E.** | **Hopscotch**: ten squares, 1 to 10 | Step on them in order against a timer | Time runs out |
| any | ~~Tic-tac-toe~~ -- built | Scribble a cell | The page plays its O |
| any | **Maze worksheet**: a little printed maze, the prize in the middle | Pencil from the mouth to the middle without touching a wall | Touch one and start again |
| any | **True or false**: one statement, two boxes | Stand on one | -- |

### More ideas, by which machine they reuse

The three built machines decide how cheap an idea is: **stand on an answer**
(the quiz board -- a new board is rows in `src/quiz.lua`), **scribble a cell**
(the tic-tac-toe grid), and **walk through places in order** (Simon -- a pen
line through the page is still an idea).

| Lesson | Puzzle | Machine | How you answer | Fail state |
| --- | --- | --- | --- | --- |
| **GRAMMAR** | **Red pen**: a row of letters with one printed backwards (Ǝ, ꓘ) | Scribble a cell | Scribble the wrong one out | A giant |
| **GRAMMAR** | **Alphabet run**: letters scattered on the page | Walk | Walk through them in alphabetical order | The letters reshuffle |
| **ART** | **Symmetry**: half of a 4x4 pixel picture filled | Scribble a cell | Scribble in the mirror half | The page smudges the picture |
| **ART** | **Colour mixing**: a target swatch and ink pots, the overprint lookup as the puzzle | Scribble a cell | Scribble the two pots that overprint to the target | -- (check first that the overprint pairs read as mixes) |
| **SCIENCE** | **Bounce the beam**: a lamp, a target, and a mirror you draw | Draw | A pen line as the mirror (the laser beam and pen walls exist) | -- |
| **P.E.** | **Laps**: a ring of cones | Walk | Run round it N times against the clock | The whistle calls in a crowd |
| **P.E.** | **Dodgeball circle**: a chalk ring | Stand | Stay inside it ten seconds while balls are thrown | A hit |
| **FINANCE** | **Balance the ledger**: a column with one cell missing | Stand on an answer | Stand on the figure that makes it sum (a PAID stamp to finish) | A giant |

Hangman's idea above is still the most expensive one; the red pen gives
GRAMMAR a board of its own without a word list.

### More MATHS boards (the stand-on-an-answer board makes each one a row)

- **Mini-sudoku**: a 4x4 grid with one cell missing, three digits to stand on.
- **Odd one out**: four numbers, one is not like the others (not prime, not a
  square, not in the times table). Four answers instead of three.
- **Bigger or smaller**: two expressions, stand on the larger -- `2^10` or `10^3`,
  `7/8` or `8/9`. Two answers, quick, good for high school.
- **Estimate**: `√50 ≈ ?` with 6, 7, 8 -- a question where being close is right.
- **Units and shapes**: the area of a drawn rectangle or triangle, its sides
  ruled on the page in squares.

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
  the coin (`banked`, one into the purse). The built seven use the coin, the
  diamond and the heart -- the sequence was the first to charge health for a
  wrong answer rather than sending something, and the till the first to pay
  more than one coin.
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
  and Simon need no translation beyond a title, and nor did the lab, the till
  or the stave: units, formulae, prices and notes are notation.
- **Placement**: fixed spots (findable, worth exploring for) rather than a timed
  pop-quiz event, for the reason the fixed pickups give: a place you found beats
  a beat on a clock.
