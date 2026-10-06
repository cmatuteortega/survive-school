-- The save directory's one door: every file the book keeps is written and read
-- back through here, so two things that matter the day an update lands are
-- done once rather than once a file.
--
-- **Every file carries the version of the game that wrote it.** The first line
-- is `save N`, and `Save.read` hands the module that owns the file the rest of
-- it, run first through whatever `Save.migrate` has for that file between the
-- version it was written at and `Save.VERSION`. Most changes need no step at
-- all -- every reader in this game already skips a line it does not know and
-- clamps a value it has no row for -- so a step is only owed when a line
-- *changes meaning* rather than appears or goes: a value rescaled, a key
-- renamed, one file split in two. A file from before this stamp existed has no
-- header and reads as version 0, which is the shape every file had when the
-- stamp was added, so nothing written by an earlier APK is lost. A file from a
-- *later* version (an older APK sideloaded over a newer one) is handed over
-- unmigrated, and the readers' tolerance does the rest.
--
-- **No file is ever left half-written.** Android kills a backgrounded game
-- without warning, the bookmark is rewritten every five seconds of play, and
-- `love.filesystem` has no rename to swap a finished file in with. So a file is
-- written whole to `<file>.new` first, then over itself, then the copy is
-- removed; and every file ends on an `end` line, which is how a reader tells a
-- finished file from one that was cut off. Killed while writing the copy, the
-- old file is still whole; killed while writing the file, the copy is whole and
-- is read instead. Either way the most that is lost is the one write.
--
-- iap.txt is love-iap's (src/iap.lua is vendored) and stays outside this.

local Save = {}

-- Bump this, and add a step under `Save.migrate`, whenever a file's lines
-- change meaning. A bump with no step is harmless: it only stamps the files.
Save.VERSION = 1

local TRAILER = "end"

-- Save.migrate[file][n] turns the body of `file` as version n-1 wrote it into
-- what version n would have written, and returns it. A file with no step for a
-- version is carried across it unchanged. Empty today: version 1 is version 0
-- with a stamp on it.
Save.migrate = {}

local function tmp(file)
    return file .. ".new"
end

-- The body and the version of a stamped, finished file; nil if it is either
-- unstamped (a version-0 file, handled by the caller) or cut off.
local function unwrap(text)
    local version, rest = text:match("^save%s+(%d+)\r?\n(.*)$")
    if not version then return nil end
    local body = rest:match("^(.-)\r?\n" .. TRAILER .. "%s*$")
    if not body and rest:match("^" .. TRAILER .. "%s*$") then body = "" end
    if not body then return nil end
    return body, tonumber(version)
end

local function stamped(text)
    return text:match("^save%s+%d+") ~= nil
end

local function upgrade(file, body, version)
    local steps = Save.migrate[file]
    if steps then
        for n = version + 1, Save.VERSION do
            if steps[n] then body = steps[n](body) or body end
        end
    end
    return body
end

-- Writes `body` to `file` under the current stamp. Returns what
-- love.filesystem.write does for the file itself, so a caller that reports
-- failure (Design:save) still can.
function Save.write(file, body)
    local text = ("save %d\n%s\n%s"):format(Save.VERSION, body, TRAILER)
    love.filesystem.write(tmp(file), text)
    local ok, err = love.filesystem.write(file, text)
    if ok then love.filesystem.remove(tmp(file)) end
    return ok, err
end

-- The body of `file`, migrated to the current version, or nil if there is
-- nothing usable -- which every caller already reads as a first run.
function Save.read(file)
    local text = love.filesystem.read(file)
    local body, version
    if text then body, version = unwrap(text) end

    -- The file is missing or was cut off mid-write: the copy written just before
    -- it is the newest finished one, if it is there and finished itself.
    if not body then
        local copy = love.filesystem.read(tmp(file))
        if copy then body, version = unwrap(copy) end
    end

    -- An unstamped file is one an APK from before the stamp wrote, whole.
    if not body and text and not stamped(text) then
        body, version = text, 0
    end

    if not body then return nil end
    return upgrade(file, body, version)
end

function Save.remove(file)
    love.filesystem.remove(tmp(file))
    return love.filesystem.remove(file)
end

return Save
