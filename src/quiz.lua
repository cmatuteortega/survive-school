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
-- run of numbers with the next one missing (**sequences**, below).
--
-- The typesetting is a handful of marks on top of the 3x5 face (src/font.lua):
-- `^` raises the next glyph or `{group}`, `_` lowers it, an integral or a sigma
-- carries both as limits beside it, and a root draws its bar over what follows.
-- Everything is still the 3x5 face at a whole pixel -- a raised 2 is a 2 three
-- pixels up -- so nothing here bends the rendering rules.

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
