-- The pop quiz's questions, and the one place in the game that typesets maths.
--
-- A question is written in notation rather than in words, which is the whole
-- reason the quiz could ship in six languages without a line of translation:
-- `7 × 8` is `7 × 8` in all of them. What changes is how hard it is, and that
-- is the course's business (src/course.lua) -- high school is sums and times
-- tables, a bachelor's is fractions and powers, a master's is counting and a
-- first derivative, and a doctorate is integrals. Each rung is a list of
-- generators, a row each, so a harder question is a row and not a branch.
--
-- Every generator returns the question, the right answer and two wrong ones,
-- and the wrong ones are the *mistakes* rather than random numbers: a fraction
-- sum's wrong answer adds the tops and the bottoms, a times table's is one row
-- out, an integral's forgot to divide by the new power. A wrong answer nobody
-- would give is not a choice, it is a gift.
--
-- MATHS sets two boards out of these (src/worksheet.lua): the questions, and a
-- run of numbers with the next one missing (**sequences**, below). SCIENCE,
-- FINANCE and MUSIC set one each out of books of their own (**the other
-- lessons' boards**, below), on the same four rungs and the same rule about
-- wrong answers.
--
-- The typesetting is a handful of marks on top of the 3x5 face (src/font.lua):
-- `^` raises the next glyph or `{group}`, `_` lowers it, an integral or a sigma
-- carries both as limits beside it, and a root draws its bar over what follows.
-- Everything is still the 3x5 face at a whole pixel -- a raised 2 is a 2 three
-- pixels up -- so nothing here bends the rendering rules. The six notes a MUSIC
-- board writes are drawn the integral's way, as rectangles, a dot after one
-- dotting it.

local Font = require("src.font")

local Quiz = {}

local function R(a, b) return love.math.random(a, b) end

local function pick(list) return list[R(1, #list)] end

local function gcd(a, b)
    a, b = math.abs(a), math.abs(b)
    while b ~= 0 do a, b = b, a % b end
    return a
end

-- A fraction in lowest terms, written the way the board writes one. A whole
-- number comes out as a whole number, so 2/4 + 2/4 is 1 and not 4/4.
local function frac(n, d)
    if d < 0 then n, d = -n, -d end
    local g = gcd(n, d)
    if g > 1 then n, d = n / g, d / g end
    if d == 1 then return tostring(n) end
    return n .. "/" .. d
end

local function fact(n)
    local f = 1
    for i = 2, n do f = f * i end
    return f
end

local function choose(n, k)
    local c = 1
    for i = 1, k do c = c * (n - k + i) / i end
    return math.floor(c + 0.5)
end

-- `aX^n` written out: no 1 in front, no ^1 behind, and a constant on its own.
local function mono(a, n)
    local c = (a == 1 and n > 0) and "" or (a == -1 and n > 0 and "-" or tostring(a))
    if n == 0 then return tostring(a) end
    if n == 1 then return c .. "X" end
    return c .. "X^" .. (n < 10 and n or "{" .. n .. "}")
end

--- the four rungs --------------------------------------------------------------

local SCHOOL = {
    function()
        local a, b = R(12, 89), R(12, 89)
        local s = a + b
        return a .. " + " .. b .. " = ?", s, { s + 10, s - 1 }
    end,
    function()
        local a, b = R(40, 99), R(11, 39)
        local s = a - b
        return a .. " - " .. b .. " = ?", s, { s + 10, s + 2 }
    end,
    function()
        local a, b = R(3, 9), R(3, 9)
        return a .. " × " .. b .. " = ?", a * b, { a * b + a, a * b - b }
    end,
    function()
        local b, q = R(2, 9), R(3, 9)
        return (b * q) .. " ÷ " .. b .. " = ?", q, { q + 1, q - 1 }
    end,
    -- The one everybody gets wrong at least once.
    function()
        local a, b, c = R(2, 9), R(2, 9), R(2, 6)
        return a .. " + " .. b .. " × " .. c .. " = ?", a + b * c,
            { (a + b) * c, a + b + c }
    end,
    function()
        local n = R(4, 12)
        return n .. "^2 = ?", n * n, { 2 * n, n * n + n }
    end,
    function()
        local d = R(5, 9)
        local a = R(1, d - 3)
        local b = R(1, d - 1 - a)
        return a .. "/" .. d .. " + " .. b .. "/" .. d .. " = ?", frac(a + b, d),
            { frac(a + b, 2 * d), frac(a * b, d) }
    end,
}

local BACHELOR = {
    -- Fractions on two bottoms. The wrong answer is the famous one: tops added
    -- to tops and bottoms to bottoms.
    function()
        local b, d = R(2, 6), R(2, 6)
        while d == b do d = R(2, 6) end
        local a, c = R(1, b - 1), R(1, d - 1)
        return a .. "/" .. b .. " + " .. c .. "/" .. d .. " = ?",
            frac(a * d + c * b, b * d),
            { frac(a + c, b + d), frac(a * c, b * d) }
    end,
    function()
        local b, d = R(2, 6), R(2, 6)
        while d == b do d = R(2, 6) end
        local a, c = R(1, b - 1), R(1, d - 1)
        if a * d < c * b then a, b, c, d = c, d, a, b end
        if a * d == c * b then return nil end
        return a .. "/" .. b .. " - " .. c .. "/" .. d .. " = ?",
            frac(a * d - c * b, b * d),
            { frac(a - c, math.abs(b - d)), frac(a * d + c * b, b * d) }
    end,
    function()
        local a, b, c, d = R(1, 5), R(2, 7), R(1, 5), R(2, 7)
        return a .. "/" .. b .. " × " .. c .. "/" .. d .. " = ?",
            frac(a * c, b * d), { frac(a * d, b * c), frac(a + c, b + d) }
    end,
    -- Division by a fraction: the wrong answers multiply instead, or flip the
    -- wrong one.
    function()
        local a, b, c, d = R(1, 5), R(2, 7), R(1, 5), R(2, 7)
        return a .. "/" .. b .. " ÷ " .. c .. "/" .. d .. " = ?",
            frac(a * d, b * c), { frac(a * c, b * d), frac(b * c, a * d) }
    end,
    function()
        local base = R(2, 3)
        local e = base == 2 and R(4, 8) or R(3, 5)
        return base .. "^" .. e .. " = ?", base ^ e,
            { base * e, base ^ (e - 1) }
    end,
    function()
        local n = R(6, 15)
        return "√{" .. n * n .. "} = ?", n, { n + 1, n - 1 }
    end,
    function()
        local a, x, b = R(2, 7), R(2, 9), R(1, 15)
        local c = a * x + b
        local wrong = (c + b) % a == 0 and (c + b) / a or x + 1
        return a .. "X + " .. b .. " = " .. c, "X=" .. x,
            { "X=" .. wrong, "X=" .. (c - b) }
    end,
    function()
        local n = R(4, 6)
        return n .. "! = ?", fact(n), { n * (n - 1), fact(n - 1) }
    end,
}

local MASTERS = {
    -- Counting. The wrong answers forget that order does not matter, or that it
    -- does.
    function()
        local n, k = R(5, 10), R(2, 3)
        local c = choose(n, k)
        return "C(" .. n .. "," .. k .. ") = ?", c, { c * fact(k), c + n }
    end,
    function()
        local n = R(5, 9)
        local p = n * (n - 1)
        return "P(" .. n .. ",2) = ?", p, { p / 2, n * n }
    end,
    function()
        local n = R(5, 9)
        return n .. "!/(" .. (n - 2) .. "!) = ?", n * (n - 1),
            { n, n * (n - 1) * (n - 2) }
    end,
    -- A quadratic by its roots, which is the only way to keep both whole.
    function()
        local r1 = R(1, 6)
        local r2 = R(1, 6)
        while r2 == r1 do r2 = R(1, 6) end
        if r1 > r2 then r1, r2 = r2, r1 end
        local s, p = r1 + r2, r1 * r2
        -- Wrong: the signs kept from the equation, or the obvious factor pair.
        local wrong = r1 == 1 and ("X=" .. r2 .. "," .. s) or ("X=1," .. p)
        return "X^2 - " .. s .. "X + " .. p .. " = 0",
            "X=" .. r1 .. "," .. r2,
            { "X=-" .. r1 .. ",-" .. r2, wrong }
    end,
    function()
        local base = R(2, 3)
        local e = base == 2 and R(3, 6) or R(2, 4)
        local v = base ^ e
        return "LOG_" .. base .. " " .. v .. " = ?", e, { v / base, e + 1 }
    end,
    -- The power rule. Wrong: forgetting to bring the power down, or to take one
    -- off it.
    function()
        local a, n = R(2, 5), R(2, 5)
        return "(" .. mono(a, n) .. ")' = ?", mono(a * n, n - 1),
            { mono(a, n - 1), mono(a * n, n) }
    end,
    -- Gauss in the schoolroom.
    function()
        local n = pick({ 10, 20, 50, 100 })
        return "1+2+...+" .. n .. " = ?", n * (n + 1) / 2,
            { n * n / 2, n * (n - 1) / 2 }
    end,
}

local PHD = {
    -- A definite integral of a power, built backwards so the answer is whole:
    -- the coefficient is a multiple of the new power. Wrong: forgetting to
    -- divide by it, or not raising the bound.
    function()
        local n, b, k = R(1, 3), R(1, 3), R(1, 2)
        local a = (n + 1) * k
        return "∫_0^" .. b .. " " .. mono(a, n) .. " DX = ?",
            k * b ^ (n + 1), { a * b ^ (n + 1), k * b ^ n }
    end,
    function()
        return "∫_1^E 1/X DX = ?", 1, { "E", "E-1" }
    end,
    function()
        return "∫_0^π SIN X DX = ?", 2, { 0, 1 }
    end,
    function()
        return "∫ COS X DX = ?", "SIN X+C", { "-SIN X+C", "COS X+C" }
    end,
    function()
        return "E^{Iπ} + 1 = ?", 0, { 1, -1 }
    end,
    function()
        return "LIM_{X→0} SIN X/X", 1, { 0, "π" }
    end,
    -- The chain rule, with the inside's derivative as the thing forgotten.
    function()
        local a = R(2, 5)
        return "(SIN " .. a .. "X)' = ?", a .. "COS " .. a .. "X",
            { "COS " .. a .. "X", "-" .. a .. "COS " .. a .. "X" }
    end,
    function()
        return "(XE^X)' = ?", "(X+1)E^X", { "E^X", "XE^{X-1}" }
    end,
    -- Every row of Pascal's triangle sums to a power of two.
    function()
        local n = R(3, 6)
        return "Σ_{K=0}^" .. n .. " C(" .. n .. ",K) = ?", 2 ^ n,
            { fact(n), n * n }
    end,
}

-- What each course asks. A doctorate is not only integrals: one question in
-- three is a master's, so a PhD board is a mix rather than a wall.
Quiz.byCourse = {
    school   = { { SCHOOL, 1 } },
    bachelor = { { BACHELOR, 1 } },
    masters  = { { MASTERS, 1 } },
    phd      = { { PHD, 2 }, { MASTERS, 1 } },
}

--- sequences -------------------------------------------------------------------

-- The second board MATHS sets: a run of numbers and a gap at the end. Same four
-- rungs, same rule about wrong answers -- they are what you get by reading the
-- pattern one level too shallow. A doubling run's wrong answer adds the last
-- step again, a quadratic's carries on in a straight line, a Catalan's takes the
-- Fibonacci rule because the first five terms look like it might be.
--
-- Most rows roll their own start and step, so a sequence seen once is not a
-- sequence learned by heart; the famous ones (Catalan, Bell, partitions) are
-- the famous ones and are what a doctorate is expected to recognise.

-- `terms` written as the board writes them, the gap last.
local function run(terms)
    local out = {}
    for i, t in ipairs(terms) do out[i] = string.format("%d", t) end
    out[#out + 1] = "?"
    return table.concat(out, ", ")
end

-- The next term if the run were a straight line: the commonest wrong reading.
local function line(t)
    return 2 * t[#t] - t[#t - 1]
end

local PRIMES = { 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47 }

local SEQ_SCHOOL = {
    function()
        local a, d = R(1, 20), R(2, 9)
        local t = { a, a + d, a + 2 * d, a + 3 * d }
        return run(t), a + 4 * d, { a + 5 * d, a + 4 * d + 1 }
    end,
    function()
        local a, d = R(60, 99), R(3, 9)
        local t = { a, a - d, a - 2 * d, a - 3 * d }
        return run(t), a - 4 * d, { a - 5 * d, a - 3 * d }
    end,
    function()
        local a = R(1, 5)
        return run({ a, 2 * a, 4 * a, 8 * a }), 16 * a, { 12 * a, 10 * a }
    end,
    -- Two steps taken in turn.
    function()
        local x, p, q = R(1, 9), R(1, 5), R(6, 9)
        local t = { x, x + p, x + p + q, x + 2 * p + q, x + 2 * p + 2 * q }
        return run(t), x + 3 * p + 2 * q, { x + 2 * p + 3 * q, x + 3 * p + 3 * q }
    end,
}

local SEQ_BACHELOR = {
    function()
        local n = R(1, 5)
        local t = { n * n, (n + 1) ^ 2, (n + 2) ^ 2, (n + 3) ^ 2 }
        return run(t), (n + 4) ^ 2, { line(t), (n + 4) ^ 2 - 1 }
    end,
    -- Triangular numbers, from somewhere along.
    function()
        local k = R(1, 4)
        local t = {}
        for i = k, k + 4 do t[#t + 1] = i * (i + 1) / 2 end
        local n = k + 5
        return run(t), n * (n + 1) / 2, { line(t), n * (n + 1) / 2 + 1 }
    end,
    function()
        local a, r = R(1, 3), R(3, 4)
        local t = { a, a * r, a * r ^ 2, a * r ^ 3 }
        return run(t), a * r ^ 4, { line(t), a * r ^ 3 * (r + 1) }
    end,
    -- Primes: the wrong answers are the odd numbers that look like one.
    function()
        local k = R(1, #PRIMES - 6)
        local t = { PRIMES[k], PRIMES[k + 1], PRIMES[k + 2], PRIMES[k + 3], PRIMES[k + 4] }
        local nxt = PRIMES[k + 5]
        return run(t), nxt, { line(t), nxt + 2 }
    end,
    function()
        local a = R(3, 7) * 32
        return run({ a, a / 2, a / 4, a / 8 }), a / 16, { a / 32, a / 16 + 2 }
    end,
}

local SEQ_MASTERS = {
    -- Fibonacci's rule from a rolled start.
    function()
        local t = { R(1, 4), R(1, 5) }
        for i = 3, 6 do t[i] = t[i - 1] + t[i - 2] end
        local nxt = t[5] + t[6]
        return run(t), nxt, { line(t), t[6] + t[4] }
    end,
    function()
        local n = R(1, 3)
        local t = { n ^ 3, (n + 1) ^ 3, (n + 2) ^ 3, (n + 3) ^ 3 }
        return run(t), (n + 4) ^ 3, { line(t), (n + 4) ^ 2 }
    end,
    function()
        if R(1, 2) == 1 then
            return run({ 1, 2, 6, 24 }), 120, { 48, 96 }
        end
        return run({ 2, 6, 24, 120 }), 720, { 240, 600 }
    end,
    -- One off a power of two, either side.
    function()
        local s = R(1, 2) == 1 and -1 or 1
        local t = {}
        for i = 1, 5 do t[i] = 2 ^ i + s end
        return run(t), 2 ^ 6 + s, { 2 ^ 6, t[5] + 2 ^ 4 }
    end,
    -- A quadratic: constant second differences, which a straight line misses.
    function()
        local a, b, c = R(1, 3), R(-3, 3), R(0, 5)
        local t = {}
        for n = 1, 5 do t[n] = a * n * n + b * n + c end
        return run(t), a * 36 + b * 6 + c, { line(t), a * 36 + b * 6 + c + a }
    end,
    function()
        local a, r = R(1, 3), -R(2, 3)
        local t = { a, a * r, a * r ^ 2, a * r ^ 3, a * r ^ 4 }
        local nxt = a * r ^ 5
        return run(t), nxt, { -nxt, t[5] * -r }
    end,
}

local SEQ_PHD = {
    -- Catalan numbers. The trap is that 1, 1, 2, 5 could be anything.
    function()
        if R(1, 2) == 1 then
            return run({ 1, 1, 2, 5, 14 }), 42, { 28, 43 }
        end
        return run({ 1, 2, 5, 14, 42 }), 132, { 84, 126 }
    end,
    -- Bell numbers, which share Catalan's first four terms.
    function()
        if R(1, 2) == 1 then
            return run({ 1, 1, 2, 5, 15 }), 52, { 42, 45 }
        end
        return run({ 1, 2, 5, 15, 52 }), 203, { 132, 156 }
    end,
    -- Partitions of n, which look like Fibonacci until they do not.
    function()
        return run({ 1, 2, 3, 5, 7, 11 }), 15, { 13, 18 }
    end,
    -- Derangements: n times the last, plus or minus one in turn.
    function()
        return run({ 1, 2, 9, 44 }), 265, { 176, 220 }
    end,
    function()
        return run({ 2, 1, 3, 4, 7, 11 }), 18, { 15, 17 }
    end,
    function()
        return run({ 1, 4, 27, 256 }), 3125, { 1024, 625 }
    end,
    function()
        return run({ 1, 1, 2, 4, 7, 13 }), 24, { 21, 20 }
    end,
    -- Look and say: the one that is not arithmetic at all.
    function()
        return run({ 1, 11, 21, 1211 }), 111221, { 1221, 2211 }
    end,
}

Quiz.sequences = {
    school   = { { SEQ_SCHOOL, 1 } },
    bachelor = { { SEQ_BACHELOR, 1 } },
    masters  = { { SEQ_MASTERS, 1 } },
    phd      = { { SEQ_PHD, 2 }, { SEQ_MASTERS, 1 } },
}

--- the other lessons' boards ---------------------------------------------------

-- SCIENCE, FINANCE and MUSIC each set a board of their own, on the pop quiz's
-- terms: notation rather than words, four rungs that climb with the course, and
-- wrong answers that are the mistakes a student of that subject actually makes.
-- A unit is a symbol and a symbol needs no translating -- `M/S`, `KG`, `Ω`,
-- `HZ`, `$`, `%` -- and an equation is an arrow between formulae, so these
-- shipped in six languages for the same reason the sums did. The face is caps
-- only, which is why NACL is salt and a chemist will forgive it.

-- Money is kept in cents, so a price never picks up a float's tail on its way
-- to the board, and written the way a till writes it: `$7`, `$6.50`.
local function money(c)
    c = math.floor(c + 0.5)
    local sign = c < 0 and "-" or ""
    c = math.abs(c)
    if c % 100 == 0 then return string.format("%s$%d", sign, c / 100) end
    return string.format("%s$%d.%02d", sign, math.floor(c / 100), c % 100)
end

-- A percentage to two places at most, and none when it is whole.
local function pct(v)
    local r = math.floor(v * 100 + 0.5) / 100
    if r == math.floor(r) then return string.format("%d%%", r) end
    return (string.format("%.2f", r):gsub("0$", "")) .. "%"
end

-- A decimal the way a board would round one: up to two places, no trailing 0.
local function dec(v)
    local r = math.floor(v * 100 + 0.5) / 100
    if r == math.floor(r) then return string.format("%d", r) end
    return (string.format("%.2f", r):gsub("0$", ""))
end

--- SCIENCE ---

-- How many of one element a formula holds. The wrong answers are the subscript
-- of the element beside it, and the bracket's multiplier forgotten.
local ATOMS = {
    { "H_2SO_4", "O", 4, 2, 7 },
    { "C_6H_{12}O_6", "H", 12, 6, 24 },
    { "NH_3", "H", 3, 1, 4 },
    { "CA(OH)_2", "H", 2, 1, 3 },
    { "CH_4", "H", 4, 1, 5 },
    { "CO_2", "O", 2, 1, 3 },
}

-- A coefficient missing from an equation that balances with it.
local EQUATIONS = {
    { "?H_2 + O_2 → 2H_2O", 2, 1, 4 },
    { "N_2 + ?H_2 → 2NH_3", 3, 2, 6 },
    { "2NA + CL_2 → ?NACL", 2, 1, 4 },
    { "CH_4 + ?O_2 → CO_2 + 2H_2O", 2, 1, 3 },
    { "4FE + 3O_2 → ?FE_2O_3", 2, 4, 3 },
    { "?AL + 3CL_2 → 2ALCL_3", 2, 3, 6 },
    { "C_3H_8 + ?O_2 → 3CO_2 + 4H_2O", 5, 4, 10 },
}

-- Grams per mole. Wrong: an atom counted once that the formula has twice, or
-- the atomic numbers added up instead of the masses.
local MOLAR = {
    { "H_2O", 18, 17, 10 },
    { "CO_2", 44, 28, 22 },
    { "CH_4", 16, 13, 10 },
    { "NH_3", 17, 15, 10 },
    { "O_2", 32, 16, 64 },
    { "NAOH", 40, 24, 20 },
}

-- Oxidation states, with the peroxide and the ammonia as the traps they are.
local OXIDATION = {
    { "FE_2O_3: FE = ?", "+3", "+2", "+6" },
    { "KMNO_4: MN = ?", "+7", "+4", "+8" },
    { "H_2SO_4: S = ?", "+6", "+4", "+8" },
    { "CO_2: C = ?", "+4", "+2", "-4" },
    { "NH_3: N = ?", "-3", "+3", "0" },
    { "H_2O_2: O = ?", "-1", "-2", "+1" },
}

local SCI_SCHOOL = {
    -- Speed: the wrong answers multiply instead, or take one from the other.
    function()
        local v, t = R(2, 9), R(2, 9)
        local d = v * t
        return "V = " .. d .. "M ÷ " .. t .. "S", v .. "M/S",
            { (d * t) .. "M/S", (d - t) .. "M/S" }
    end,
    -- Newton's second law, and the right number with the wrong unit.
    function()
        local m, a = R(2, 9), R(2, 5)
        return "F = " .. m .. "KG × " .. a .. "M/S^2", (m * a) .. "N",
            { (m + a) .. "N", (m * a) .. "J" }
    end,
    function()
        local i, r = R(2, 6), R(2, 9)
        return "V = " .. i .. "A × " .. r .. "Ω", (i * r) .. "V",
            { (i + r) .. "V", frac(r, i) .. "V" }
    end,
    -- Kelvin: 273 taken away instead of added, or Fahrenheit.
    function()
        local c = pick({ 0, 20, 25, 37, 100 })
        return c .. "°C = ?K", c + 273,
            { c - 273, math.floor(c * 9 / 5 + 32 + 0.5) }
    end,
    function()
        local m = pick(ATOMS)
        return m[1] .. ": " .. m[2] .. " = ?", m[3], { m[4], m[5] }
    end,
}

local SCI_BACHELOR = {
    function()
        local e = pick(EQUATIONS)
        return e[1], e[2], { e[3], e[4] }
    end,
    function()
        local m = pick(MOLAR)
        return m[1] .. " = ?G/MOL", m[2], { m[3], m[4] }
    end,
    -- Kinetic energy: the half forgotten, or the square.
    function()
        local m, v = 2 * R(1, 3), R(2, 5)
        return "E = " .. m .. "KG × (" .. v .. "M/S)^2 ÷ 2",
            (m * v * v / 2) .. "J", { (m * v * v) .. "J", (m * v / 2) .. "J" }
    end,
    -- Resistors in parallel. Wrong: added as if in series, or 1/R left unflipped.
    function()
        local p = pick({ { 6, 3 }, { 12, 6 }, { 4, 4 }, { 20, 5 }, { 10, 15 },
                         { 12, 4 }, { 6, 6 } })
        local a, b = p[1], p[2]
        return "1/R = 1/" .. a .. " + 1/" .. b, "R=" .. (a * b / (a + b)) .. "Ω",
            { "R=" .. (a + b) .. "Ω", "R=" .. frac(a + b, a * b) .. "Ω" }
    end,
    function()
        local v, i = pick({ 3, 6, 9, 12 }), R(2, 5)
        return "P = " .. v .. "V × " .. i .. "A", (v * i) .. "W",
            { (v + i) .. "W", frac(v, i) .. "W" }
    end,
    -- pH: the sign of the logarithm kept, or the pOH given instead.
    function()
        local n = R(2, 12)
        if n == 7 then return nil end
        return "H^+ = 10^{-" .. n .. "} → PH = ?", n, { -n, 14 - n }
    end,
}

local SCI_MASTERS = {
    -- Mass-energy: the square forgotten, or the kilogram taken for a gram.
    function()
        if R(1, 2) == 1 then
            return "E = MC^2, M = 1KG", "9×10^{16}J",
                { "3×10^8J", "9×10^{13}J" }
        end
        return "E = MC^2, M = 2KG", "1.8×10^{17}J",
            { "6×10^8J", "1.8×10^{14}J" }
    end,
    -- Half-life, and the halvings miscounted by one either way.
    function()
        local t, k, n0 = R(2, 5), R(2, 4), pick({ 800, 1600, 640, 960 })
        return "N_0=" .. n0 .. " T_{1/2}=" .. t .. "S → N(" .. (t * k) .. "S)=?",
            n0 / 2 ^ k, { n0 / 2 ^ (k - 1), n0 / 2 ^ (k + 1) }
    end,
    -- The inverse square: halved instead of quartered, or the wrong way up.
    function()
        local k = R(2, 4)
        return "F=GMM/R^2, R → " .. k .. "R", "F/" .. (k * k),
            { "F/" .. k, (k * k) .. "F" }
    end,
    function()
        local k = R(2, 4)
        return "PV=K, P → " .. k .. "P: V → ?", "V/" .. k,
            { k .. "V", "V" }
    end,
    function()
        local i, r = R(2, 5), R(2, 6)
        return "P = I^2R, I = " .. i .. "A, R = " .. r .. "Ω", (i * i * r) .. "W",
            { (i * r) .. "W", (2 * i * r) .. "W" }
    end,
    function()
        local o = pick(OXIDATION)
        return o[1], o[2], { o[3], o[4] }
    end,
}

local SCI_PHD = {
    -- Bohr's hydrogen: the square forgotten, or the binding energy's sign.
    function()
        local n = R(2, 4)
        local e = -13.6 / (n * n)
        return "E_N = -13.6EV/N^2, N = " .. n, dec(e) .. "EV",
            { dec(-13.6 / n) .. "EV", dec(-e) .. "EV" }
    end,
    -- The Lorentz factor: the reciprocal forgotten, or the root.
    function()
        if R(1, 2) == 1 then
            return "(1-V^2/C^2)^{-1/2}, V=0.6C", "1.25", { "0.8", "1.56" }
        end
        return "(1-V^2/C^2)^{-1/2}, V=0.8C", "1.67", { "0.6", "2.78" }
    end,
    -- Fission: the neutron that went in counted, or not.
    function()
        if R(1, 2) == 1 then
            return "^{235}U+N → ^{141}BA+^{92}KR+?N", 3, { 2, 4 }
        end
        return "^{235}U+N → ^{140}XE+^{94}SR+?N", 2, { 1, 3 }
    end,
    function()
        return pick({
            function() return "^{238}U → ^{234}TH + ?", "^4HE", { "^2H", "E^-" } end,
            function() return "^{14}C → ^{14}N + ?", "E^-", { "^4HE", "E^+" } end,
            function() return "^{222}RN → ? + ^4HE", "^{218}PO", { "^{220}PO", "^{218}RN" } end,
        })()
    end,
    -- Stefan-Boltzmann: the fourth power read as a square, or as times four.
    function()
        local k = R(2, 3)
        return "P = KT^4, T → " .. k .. "T", (k ^ 4) .. "P",
            { (k * k) .. "P", (4 * k) .. "P" }
    end,
    -- Which orbitals a shell has: one too many, or counted from one.
    function()
        local n = R(2, 4)
        local function list(a, b)
            local t = {}
            for v = a, b do t[#t + 1] = v end
            return table.concat(t, ",")
        end
        return "N = " .. n .. " → L = ?", list(0, n - 1),
            { list(1, n), list(0, n) }
    end,
    function()
        if R(1, 2) == 1 then
            return "CR_2O_7^{2-}: CR = ?", "+6", { "+7", "+12" }
        end
        return "MNO_4^-: MN = ?", "+7", { "+8", "+6" }
    end,
}

Quiz.science = {
    school   = { { SCI_SCHOOL, 1 } },
    bachelor = { { SCI_BACHELOR, 1 } },
    masters  = { { SCI_MASTERS, 1 } },
    phd      = { { SCI_PHD, 2 }, { SCI_MASTERS, 1 } },
}

--- FINANCE ---

local FIN_SCHOOL = {
    -- A discount: the percentage taken off as dollars, or the discount given as
    -- the price.
    function()
        local p, d = pick({ 20, 40, 50, 60, 80, 120 }), pick({ 10, 20, 25, 50 })
        return "$" .. p .. " - " .. d .. "% = ?", money(p * (100 - d)),
            { money((p - d) * 100), money(p * d) }
    end,
    function()
        local p, d = pick({ 20, 40, 60, 80, 120 }), pick({ 10, 20, 25, 50 })
        return "$" .. p .. " + " .. d .. "% = ?", money(p * (100 + d)),
            { money((p + d) * 100), money(p * d) }
    end,
    -- Change from a note, and the dollar borrowed or not borrowed.
    function()
        local price = R(26, 194) * 10
        local paid = price < 1000 and 1000 or 2000
        local c = paid - price
        return money(paid) .. " - " .. money(price) .. " = ?", money(c),
            { money(c + 100), money(c - 100) }
    end,
    function()
        local a, b = R(21, 99) * 5, R(21, 99) * 5
        return money(a) .. " + " .. money(b) .. " = ?", money(a + b),
            { money(a + b - 100), money(a + b + 10) }
    end,
    -- The unit price: multiplied instead of divided, or a little off.
    function()
        local n, u = R(2, 5), R(4, 18) * 5
        return n .. " = " .. money(n * u) .. " → 1 = ?", money(u),
            { money(n * n * u), money(u + 10) }
    end,
}

local FIN_BACHELOR = {
    -- Simple interest: the total given for the interest, or one year of it.
    function()
        local p, r, n = pick({ 500, 1000, 2000, 5000 }), pick({ 2, 3, 4, 5, 10 }), R(2, 5)
        return "I=PRT: $" .. p .. " " .. r .. "% " .. n,
            money(p * r * n), { money(p * 100 + p * r * n), money(p * r) }
    end,
    -- A markup, and the margin on the selling price taken for it.
    function()
        local c, m = pick({ 40, 60, 80, 120 }), pick({ 20, 25, 50 })
        local s = c * (100 + m) / 100
        return "$" .. c .. " → $" .. s .. " = ?", "+" .. m .. "%",
            { "+" .. pct(100 * (s - c) / s), "+" .. (s - c) .. "%" }
    end,
    -- Down and back up by the same percentage is not where it started.
    function()
        local p, d = pick({ 50, 100, 200 }), pick({ 10, 20, 50 })
        return "$" .. p .. " - " .. d .. "% + " .. d .. "% = ?",
            money(p * (100 - d) * (100 + d) / 100),
            { money(p * 100), money(p * (100 + d * d / 100)) }
    end,
    -- Tax taken back out: the rate taken off the total instead.
    function()
        local v, base = pick({ 10, 20, 25 }), pick({ 80, 100, 120, 200 })
        local total = base * (100 + v) / 100
        return "? + " .. v .. "% = $" .. dec(total), money(base * 100),
            { money(total * (100 - v)), money((total - v) * 100) }
    end,
    -- Two rises compound; they do not add.
    function()
        local a, b = pick({ 10, 20, 50 }), pick({ 10, 20, 50 })
        return "+" .. a .. "%, +" .. b .. "% = ?",
            "+" .. pct((100 + a) * (100 + b) / 100 - 100),
            { "+" .. (a + b) .. "%", "+" .. pct(a * b / 100) }
    end,
}

local FIN_MASTERS = {
    -- Compound interest: simple interest instead, or the interest without the
    -- principal.
    function()
        local p, r, n = pick({ 500, 1000, 2000 }), pick({ 5, 10, 20 }), R(2, 3)
        local fv = p * 100 * (1 + r / 100) ^ n
        return "$" .. p .. " I=" .. r .. "% N=" .. n .. " → ?", money(fv),
            { money(p * (100 + r * n)), money(fv - p * 100) }
    end,
    -- The rule of 72, and the rule of 100 people reach for instead.
    function()
        local r = pick({ 4, 6, 8, 9, 12 })
        return "I = " .. r .. "% → ×2: N = ?", 72 / r,
            { dec(100 / r), 144 / r }
    end,
    -- Fisher: inflation added instead of taken off, or multiplied.
    function()
        local i, p = R(4, 9), R(1, 3)
        return "I = " .. i .. "%, π = " .. p .. "% → R = ?", (i - p) .. "%",
            { (i + p) .. "%", (i * p) .. "%" }
    end,
    -- Break-even: fixed cost over the margin, not over the price or the cost.
    function()
        local f, p = pick({ 600, 1200, 2400 }), pick({ 10, 12, 15 })
        local v = p - pick({ 3, 4, 5, 6 })
        return "F=$" .. f .. " P=$" .. p .. " V=$" .. v .. " → Q=?",
            dec(f / (p - v)), { dec(f / p), dec(f / v) }
    end,
    -- Down and up the other way round: it lands short every time.
    function()
        local d = pick({ 10, 20, 25, 50 })
        return "-" .. d .. "%, +" .. d .. "% = ?", "-" .. pct(d * d / 100),
            { "0%", "+" .. pct(d * d / 100) }
    end,
}

local FIN_PHD = {
    -- Present value: discounted as if it were a loss, or simple discounting.
    function()
        local p, r = pick({ 500, 1000 }), pick({ 10, 20 })
        local fv = p * (1 + r / 100) ^ 2
        return money(fv * 100) .. " I=" .. r .. "% N=2 → PV=?",
            money(p * 100),
            { money(fv * 100 * (1 - r / 100) ^ 2), money(fv * 100 / (1 + 2 * r / 100)) }
    end,
    -- The growing perpetuity: growth ignored, or added to the rate.
    function()
        local c, gap = pick({ 20, 40, 50, 60, 100 }), pick({ 2, 4, 5 })
        local g = R(1, 3)
        local r = g + gap
        return "C=$" .. c .. " I=" .. r .. "% G=" .. g .. "% → PV=?",
            money(c * 10000 / gap), { money(c * 10000 / r), money(c * 10000 / (r + g)) }
    end,
    -- The effective rate of a monthly one: the nominal rate, or a month of it.
    function()
        local apr = pick({ 6, 12, 24 })
        return "(1 + " .. apr .. "%/12)^{12} - 1 = ?",
            pct(((1 + apr / 1200) ^ 12 - 1) * 100),
            { apr .. "%", pct(apr / 12) }
    end,
    -- A bond against its yield.
    function()
        return pick({
            function() return "C = 5%, Y = 5% → P = ?", "100", { "95", "105" } end,
            function() return "C = 5%, Y = 6% → P = ?", "<100", { ">100", "100" } end,
            function() return "C = 6%, Y = 5% → P = ?", ">100", { "<100", "100" } end,
        })()
    end,
    -- Put-call parity at a rate of nothing: the sign of the spread flipped, or
    -- the spread forgotten.
    function()
        local c, s, k = R(8, 15), pick({ 95, 100, 105 }), pick({ 95, 100, 105 })
        local p = c - s + k
        if p <= 0 then return nil end
        return "C=" .. c .. " S=" .. s .. " K=" .. k .. " → P=?", p,
            { c + s - k, c }
    end,
}

Quiz.finance = {
    school   = { { FIN_SCHOOL, 1 } },
    bachelor = { { FIN_BACHELOR, 1 } },
    masters  = { { FIN_MASTERS, 1 } },
    phd      = { { FIN_PHD, 2 }, { FIN_MASTERS, 1 } },
}

--- MUSIC ---

-- The notes the board can draw (Quiz.layout sets them, below), each with how
-- long it lasts in eighths -- the smallest unit any of these boards counts in,
-- so a dotted crotchet is a whole number and 6/8 is six of them. A dot after a
-- note is the dotted note.
local WHOLE, HALF = "\240\157\133\157", "\240\157\133\158"
local QUARTER, EIGHTH = "\226\153\169", "\226\153\170"
local PAIR, SIXTEENTHS = "\226\153\171", "\226\153\172"

local N = {
    W  = { WHOLE, 8 },
    H  = { HALF, 4 },
    Hd = { HALF .. ".", 6 },
    Q  = { QUARTER, 2 },
    Qd = { QUARTER .. ".", 3 },
    E  = { EIGHTH, 1 },
    P  = { PAIR, 2 },
    S  = { SIXTEENTHS, 1 },
}

-- Beats are crotchets, and a board says 1.5 rather than 3/2: that is how a
-- musician counts.
local function beats(e) return dec(e / 2) end

-- A bar with its last note missing. `sigs` are the time signatures it may be
-- in, `fill` the notes it is written in, `gaps` what may be missing and `pool`
-- what the wrong answers are drawn from: notes that do not last what is left.
local function bar(sigs, fill, gaps, pool, most)
    local sig = pick(sigs)
    local top, bottom = sig:match("(%d+)/(%d+)")
    local total = tonumber(top) * 8 / tonumber(bottom)
    local gap = pick(gaps)
    local left = total - gap[2]
    if left < 1 then return nil end

    local notes = {}
    while left > 0 do
        local fits = {}
        for _, n in ipairs(fill) do
            if n[2] <= left then fits[#fits + 1] = n end
        end
        if #fits == 0 or #notes >= (most or 4) then return nil end
        local n = pick(fits)
        notes[#notes + 1] = n[1]
        left = left - n[2]
    end

    local wrong = {}
    for _, n in ipairs(pool) do
        if n[2] ~= gap[2] then wrong[#wrong + 1] = n[1] end
    end
    if #wrong < 2 then return nil end
    local a = R(1, #wrong)
    local b = R(1, #wrong - 1)
    if b >= a then b = b + 1 end
    return sig .. " = " .. table.concat(notes, " ") .. " ?", gap[1],
        { wrong[a], wrong[b] }
end

-- Notes added up. `misread` is what each would be worth to the student making
-- the mistake this rung is about, and is the second wrong answer; the first is
-- always the number of notes, which is counting what is on the page rather
-- than how long it lasts.
local function sum(first, rest, misread)
    local notes = { pick(first) }
    for _ = 1, R(1, 2) do notes[#notes + 1] = pick(rest) end
    local syms, total, wrong = {}, 0, 0
    for i, n in ipairs(notes) do
        syms[i] = n[1]
        total = total + n[2]
        wrong = wrong + (misread[n[1]] or n[2])
    end
    return table.concat(syms, " + ") .. " = ?", beats(total),
        { tostring(#notes), beats(wrong) }
end

local MUS_SCHOOL = {
    -- The commonest mistake in the first lesson: a half note read as half a
    -- beat, and a whole note as one.
    function()
        local any = { N.W, N.H, N.Q }
        return sum({ N.W, N.H }, any, { [WHOLE] = 2, [HALF] = 1 })
    end,
    -- How many of one go into another, and the answer turned upside down.
    function()
        local p = pick({ { N.W, N.Q }, { N.W, N.H }, { N.H, N.Q }, { N.Q, N.E },
                         { N.H, N.E } })
        local n = p[1][2] / p[2][2]
        return p[1][1] .. " = ?" .. p[2][1], n,
            { frac(1, n), n == 2 and 4 or 2 }
    end,
    function()
        return bar({ "2/4", "3/4", "4/4" }, { N.H, N.Q }, { N.Q, N.H },
            { N.W, N.H, N.Q, N.E })
    end,
}

local MUS_BACHELOR = {
    -- Dots: forgotten.
    function()
        return sum({ N.Hd, N.Qd }, { N.H, N.Q, N.E, N.P, N.Qd },
            { [HALF .. "."] = 4, [QUARTER .. "."] = 2 })
    end,
    function()
        return bar({ "2/4", "3/4", "4/4" }, { N.H, N.Q, N.Qd, N.E, N.P },
            { N.E, N.Q, N.Qd, N.H, N.Hd }, { N.W, N.Hd, N.H, N.Qd, N.Q, N.E })
    end,
    -- Seconds at a tempo: the beats taken for seconds, or the tempo read upside
    -- down.
    function()
        local bpm, s = pick({ 90, 120, 150, 180 }), R(2, 6)
        local n = s * bpm / 60
        if n ~= math.floor(n) or n > 16 then return nil end
        return QUARTER .. " = " .. bpm .. ": " .. n .. QUARTER .. " = ?S", s,
            { n, n * bpm / 60 }
    end,
}

local MUS_MASTERS = {
    -- Compound time, where the beat is dotted.
    function()
        return bar({ "3/8", "6/8", "9/8", "12/8" }, { N.Qd, N.Q, N.E, N.Hd },
            { N.E, N.Q, N.Qd, N.H, N.Hd }, { N.Hd, N.H, N.Qd, N.Q, N.E })
    end,
    -- A note's length at a tempo, in seconds: the tempo inverted, or an eighth
    -- taken for a crotchet.
    function()
        local bpm, n = pick({ 75, 80, 90, 100, 120 }), pick({ N.E, N.Q, N.Qd, N.H })
        return QUARTER .. " = " .. bpm .. ": " .. n[1] .. " = ?S",
            frac(60 * n[2], bpm * 2),
            { frac(bpm * 2, 60 * n[2]), frac(60 * n[2], bpm) }
    end,
    -- Sixteenths: a beamed pair of them taken for a beamed pair of eighths.
    function()
        return sum({ N.S, N.Hd, N.Qd }, { N.S, N.E, N.P, N.Qd, N.Q },
            { [SIXTEENTHS] = 2, [HALF .. "."] = 4, [QUARTER .. "."] = 2 })
    end,
    -- The harmonic series is a sum, not a run of octaves.
    function()
        local f, n = pick({ 100, 110, 220 }), R(3, 5)
        return "F_1 = " .. f .. "HZ → F_" .. n .. " = ?", n * f,
            { f * 2 ^ (n - 1), (n - 1) * f }
    end,
    -- Two tones beat at their difference, not at their sum or their middle.
    function()
        local a = pick({ 220, 440 })
        local b = a + R(2, 6)
        return a .. "HZ + " .. b .. "HZ → ?HZ", b - a, { a + b, (a + b) / 2 }
    end,
}

local MUS_PHD = {
    -- Equal temperament: the octave split in a straight line instead of by a
    -- ratio, or a semitone miscounted.
    function()
        local f, n = pick({ 220, 440 }), pick({ 3, 4, 7, 9, 10 })
        return f .. "HZ × 2^{" .. n .. "/12} = ?",
            math.floor(f * 2 ^ (n / 12) + 0.5),
            { math.floor(f * (1 + n / 12) + 0.5),
              math.floor(f * 2 ^ ((n - 1) / 12) + 0.5) }
    end,
    -- A metric modulation: the new X lasts as long as the old Y, so the new
    -- crotchet runs at the old tempo times X over Y. Wrong: Y over X, or no
    -- change at all.
    function()
        local bpm = pick({ 60, 90, 120, 144 })
        local p = pick({ { N.Qd, N.Q }, { N.Q, N.Qd }, { N.E, N.Q }, { N.H, N.Q },
                         { N.Q, N.H } })
        local x, y = p[1], p[2]
        return QUARTER .. " = " .. bpm .. ", " .. x[1] .. " = " .. y[1] ..
            " → " .. QUARTER .. " = ?",
            bpm * x[2] / y[2], { bpm * y[2] / x[2], bpm }
    end,
    -- Odd meters, five notes long.
    function()
        return bar({ "5/8", "7/8", "11/8", "5/4", "7/4" },
            { N.Q, N.Qd, N.E, N.H, N.Hd }, { N.E, N.Q, N.Qd, N.H, N.Hd },
            { N.Hd, N.H, N.Qd, N.Q, N.E }, 5)
    end,
    -- A dotted beat: an eighth is a third of it, not a half.
    function()
        local bpm, n = pick({ 40, 60, 80, 100 }), pick({ N.E, N.Q, N.Hd })
        return QUARTER .. ". = " .. bpm .. ": " .. n[1] .. " = ?S",
            frac(60 * n[2], 3 * bpm),
            { frac(60 * n[2], 2 * bpm), frac(60, bpm) }
    end,
}

Quiz.music = {
    school   = { { MUS_SCHOOL, 1 } },
    bachelor = { { MUS_BACHELOR, 1 } },
    masters  = { { MUS_MASTERS, 1 } },
    phd      = { { MUS_PHD, 2 }, { MUS_MASTERS, 1 } },
}

local function str(v)
    if type(v) == "number" then
        if v == math.floor(v) then return string.format("%d", v) end
        return tostring(v)
    end
    return v
end

-- One question for the course, shuffled into three answers. A generator may
-- refuse its roll (nil) or come back with a wrong answer equal to the right
-- one -- a coincidence of the dice, never a choice -- and either way it simply
-- rolls again. `book` is which set of rungs to draw from: the questions
-- (`Quiz.byCourse`, the default) or the sequences (`Quiz.sequences`).
function Quiz.new(courseKey, book)
    book = book or Quiz.byCourse
    local mix = book[courseKey] or book.school
    local total = 0
    for _, row in ipairs(mix) do total = total + row[2] end

    for _ = 1, 40 do
        local roll, rung = love.math.random() * total, mix[1][1]
        for _, row in ipairs(mix) do
            roll = roll - row[2]
            if roll <= 0 then rung = row[1] break end
        end

        local q, right, wrong = pick(rung)()
        if q then
            local a, b, c = str(right), str(wrong[1]), str(wrong[2])
            if a ~= b and a ~= c and b ~= c then
                local answers = { a, b, c }
                for i = 3, 2, -1 do
                    local j = R(1, i)
                    answers[i], answers[j] = answers[j], answers[i]
                end
                for i, v in ipairs(answers) do
                    if v == a then return { q = q, answers = answers, right = i } end
                end
            end
        end
    end
    return { q = "2 + 2 = ?", answers = { "4", "5", "22" }, right = 1 }
end

--- typesetting ------------------------------------------------------------------

local ADV = Font.advance
local INTEGRAL = "\226\136\171"
local SIGMA = "\206\163"
local ROOT = "\226\136\154"

-- The six notes a MUSIC board writes, drawn here rather than in the face for
-- the integral's reason: a note is a head on the line with a stem three rows
-- above it, taller than any letter. Each is a list of rectangles off its left
-- edge and how wide it is; a head is four pixels by three, filled or hollow, and
-- sits on the bottom three rows so a dot after it lands beside it.
local NOTE_SHAPES = (function()
    local function head(x, hollow, out)
        out[#out + 1] = { x + 1, 2, 3, 1 }
        if hollow then
            out[#out + 1] = { x, 3, 1, 1 }
            out[#out + 1] = { x + 3, 3, 1, 1 }
        else
            out[#out + 1] = { x, 3, 4, 1 }
        end
        out[#out + 1] = { x, 4, 3, 1 }
        return out
    end
    local function stem(x, out)
        out[#out + 1] = { x + 3, -3, 1, 5 }
        return out
    end
    local quarter = stem(0, head(0, false, {}))
    local eighth = stem(0, head(0, false, {}))
    eighth[#eighth + 1] = { 4, -2, 1, 1 }
    eighth[#eighth + 1] = { 5, -1, 1, 2 }
    local pair = stem(6, head(6, false, stem(0, head(0, false, {}))))
    pair[#pair + 1] = { 3, -3, 7, 1 }
    local sixteenths = stem(6, head(6, false, stem(0, head(0, false, {}))))
    sixteenths[#sixteenths + 1] = { 3, -3, 7, 1 }
    sixteenths[#sixteenths + 1] = { 3, -1, 7, 1 }
    return {
        -- The whole note is a wider ring with no stem.
        ["\240\157\133\157"] = { w = 5, { 1, 2, 3, 1 }, { 0, 3, 1, 1 },
                                   { 4, 3, 1, 1 }, { 1, 4, 3, 1 } },
        ["\240\157\133\158"] = { w = 4, unpack(stem(0, head(0, true, {}))) },
        ["\226\153\169"] = { w = 4, unpack(quarter) },
        ["\226\153\170"] = { w = 6, unpack(eighth) },
        ["\226\153\171"] = { w = 10, unpack(pair) },
        ["\226\153\172"] = { w = 10, unpack(sixteenths) },
    }
end)()

local function glyphLen(s, i)
    local b = s:byte(i)
    if b < 0x80 then return 1 end
    if b < 0xE0 then return 2 end
    if b < 0xF0 then return 3 end
    return 4
end

-- The next glyph, or the next `{group}`, and where reading carries on.
local function group(s, i)
    if s:sub(i, i) == "{" then
        local j = s:find("}", i, true) or (#s + 1)
        return s:sub(i + 1, j - 1), j + 1
    end
    local w = glyphLen(s, i)
    return s:sub(i, i + w - 1), i + w
end

local function plainWidth(s)
    return Font.count(s) * ADV
end

-- A string laid out once into what to draw and where: glyph runs at an offset,
-- and the two marks the face cannot hold -- the tall integral and the root's
-- bar -- as rectangles. `top` and `bottom` are how far it reaches above and
-- below the line, which is what the board is sized off.
function Quiz.layout(s)
    local ops, x, top, bottom = {}, 0, 0, Font.height
    local i = 1

    local function text(t, dx, dy)
        ops[#ops + 1] = { t = t, x = dx, y = dy }
        top = math.min(top, dy)
        bottom = math.max(bottom, dy + Font.height)
    end
    local function rect(rx, ry, w, h)
        ops[#ops + 1] = { r = true, x = rx, y = ry, w = w, h = h }
        top = math.min(top, ry)
        bottom = math.max(bottom, ry + h)
    end

    while i <= #s do
        local w = glyphLen(s, i)
        local ch = s:sub(i, i + w - 1)

        if ch == "^" or ch == "_" then
            local g
            g, i = group(s, i + 1)
            text(g, x, ch == "^" and -3 or 2)
            x = x + plainWidth(g)
        elseif ch == INTEGRAL or ch == SIGMA then
            i = i + w
            if ch == INTEGRAL then
                -- Three rows taller than a letter, a hook at each end.
                rect(x + 2, -3, 1, 1)
                rect(x + 1, -3, 1, 10)
                rect(x, 6, 1, 1)
            else
                text(ch, x, 0)
            end
            local lo, hi = "", ""
            for _ = 1, 2 do
                local m = s:sub(i, i)
                if m == "_" then lo, i = group(s, i + 1)
                elseif m == "^" then hi, i = group(s, i + 1) end
            end
            local lx = x + ADV
            if hi ~= "" then text(hi, lx, -5) end
            if lo ~= "" then text(lo, lx, 5) end
            x = lx + math.max(plainWidth(lo), plainWidth(hi))
            if lo ~= "" or hi ~= "" then x = x + 1 end
        elseif NOTE_SHAPES[ch] then
            i = i + w
            local shape = NOTE_SHAPES[ch]
            for _, r in ipairs(shape) do rect(x + r[1], r[2], r[3], r[4]) end
            x = x + shape.w
            -- A dot straight after a note is the note dotted: one pixel beside
            -- the head rather than a full stop's whole advance.
            if s:sub(i, i) == "." then
                rect(x + 1, 3, 1, 1)
                x = x + 2
                i = i + 1
            end
            x = x + 1
        elseif ch == ROOT then
            local g
            g, i = group(s, i + w)
            -- The tick, then a bar over the whole of what is under it.
            rect(x, 2, 1, 1)
            rect(x + 1, 3, 1, 2)
            rect(x + 2, -1, 1, 6)
            rect(x + 2, -2, plainWidth(g) + 2, 1)
            text(g, x + 4, 0)
            x = x + 4 + plainWidth(g)
        else
            i = i + w
            text(ch, x, 0)
            x = x + ADV
        end
    end

    return { ops = ops, w = math.max(0, x - 1), top = top, bottom = bottom }
end

-- Drawn in the current colour, top-left of the line at (x, y).
function Quiz.print(lay, x, y)
    x, y = math.floor(x), math.floor(y)
    for _, op in ipairs(lay.ops) do
        if op.r then
            love.graphics.rectangle("fill", x + op.x, y + op.y, op.w, op.h)
        else
            Font.print(op.t, x + op.x, y + op.y)
        end
    end
end

return Quiz
