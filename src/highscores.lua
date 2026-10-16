-- highscores.lua
-- Persistent top-10 high score table.
--
-- Stores up to MAX_ENTRIES entries, each { score, grade, level, time }, kept
-- sorted by score descending. Persisted to love.filesystem as a simple
-- pipe-delimited text file (one entry per line) so it works on stock Lua 5.1 /
-- Luajit with no JSON dependency and also when the game runs from a zip.
--
-- FIX: love.filesystem.isInitialized() was removed in Love 11.x, so calling it
-- threw "attempt to call field 'isInitialized' (a nil value)". We now just
-- check that love.filesystem exists.

local HighScores = {}

local MAX_ENTRIES = 10
local SAVE_FILE = "highscores.txt"

-- True if love.filesystem can be used (false in headless tests).
local function fsAvailable()
    return love ~= nil and love.filesystem ~= nil
end

--- Load the saved list from disk into memory (idempotent). Safe to call even
--- when love.filesystem is unavailable (e.g. headless tests).
function HighScores:load()
    local list = {}
    if fsAvailable() then
        local ok, data = pcall(love.filesystem.read, SAVE_FILE)
        if ok and data then
            for line in data:gmatch("[^\r\n]+") do
                local score, grade, level, time =
                    line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
                if score then
                    table.insert(list, {
                        score = tonumber(score) or 0,
                        grade = grade or "?",
                        level = tonumber(level) or 0,
                        time  = tonumber(time) or 0,
                    })
                end
            end
        end
    end
    -- Sort by score descending, keep only the top MAX_ENTRIES.
    table.sort(list, function(a, b) return a.score > b.score end)
    if #list > MAX_ENTRIES then
        table.remove(list, MAX_ENTRIES + 1, #list)
    end
    self._list = list
    return self:get()
end

--- Save the in-memory list to disk.
function HighScores:_save(list)
    local parts = {}
    for i = 1, #list do
        local e = list[i]
        parts[i] = string.format(
            "%d|%s|%d|%d", e.score or 0, tostring(e.grade or "?"),
            e.level or 0, e.time or 0)
    end
    if fsAvailable() then
        pcall(love.filesystem.write, SAVE_FILE, table.concat(parts, "\n"))
    end
end

--- Whether a given score would make the top list.
function HighScores:isTop(score)
    score = tonumber(score) or 0
    if not self._list then self:load() end
    if #self._list < MAX_ENTRIES then return true end
    return score > (self._list[MAX_ENTRIES].score or 0)
end

--- Insert a score entry, keeping only the top MAX_ENTRIES by score.
--- entry = { score = number, grade = string, level = number, time = number }
--- Returns true if the entry made the list.
function HighScores:add(entry)
    if not entry then return false end
    if not self._list then self:load() end
    local score = tonumber(entry.score) or 0

    -- If the list is full and this score is not high enough, ignore it.
    if #self._list >= MAX_ENTRIES and score <= (self._list[MAX_ENTRIES].score or 0) then
        return false
    end

    table.insert(self._list, {
        score  = score,
        grade  = tostring(entry.grade or "?"),
        level  = tonumber(entry.level) or 0,
        time   = tonumber(entry.time) or 0,
    })
    table.sort(self._list, function(a, b) return a.score > b.score end)
    if #self._list > MAX_ENTRIES then
        table.remove(self._list, MAX_ENTRIES + 1, #self._list)
    end
    self:_save(self._list)
    return true
end

--- Return a copy of the current list (top first). Callers can't mutate state.
function HighScores:get()
    local list = self._list or {}
    local out = {}
    for i = 1, #list do
        out[i] = {
            score = list[i].score,
            grade = list[i].grade,
            level = list[i].level,
            time  = list[i].time,
        }
    end
    return out
end

--- Clear the saved list.
function HighScores:reset()
    self._list = {}
    self:_save(self._list)
    return self:get()
end

return HighScores
