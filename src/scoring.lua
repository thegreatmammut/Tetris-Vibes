-- scoring.lua
-- TGM+ scoring, combo, level progression and the grade table.
--
-- Score formula (TGM+):
--   Score = (ceil((Level + Lines) / 4) + Soft) * Lines * Combo * Bravo
--     Level = current level BEFORE the clear
--     Lines = lines cleared by the current piece
--     Soft  = frames the Down button was held during the piece's active time
--             (a manual lock adds 1)
--     Combo = 1 initially; on a clear it becomes prevCombo + 2*Lines - 2, and is
--             reset to 1 after a non-clearing lock.
--     Bravo = 4 for a Perfect Clear (whole field cleared), else 1.
--     ceil is done as floor((a + 3) / 4) so it runs on stock Lua 5.1 too.
--
-- Level progression:
--   * +1 per piece dropped (blocked across 100-level boundaries: 99->100, ...)
--   * +1 per line cleared (crosses boundaries freely)
--   * capped at 999
--
-- Total points advance a grade from a fixed table.

local Scoring = {}
Scoring.__index = Scoring

-- Base points per number of lines cleared.
local BASE_POINTS = { [1] = 100, [2] = 300, [3] = 500, [4] = 800 }

-- Maximum level.
local MAX_LEVEL = 999

-- Grade table: ascending {points, name} entries for grades 9 .. S9. The
-- player's current grade is the highest entry whose points are <= the current
-- total. The top grade, Grand Master (GM), is handled separately: it needs the
-- GM_POINTS score AND the time checkpoints below to be passed. Edit the points
-- here to change the grade progression.
local GRADES = {
    { points = 0,      name = "9"  },
    { points = 400,    name = "8"  },
    { points = 800,    name = "7"  },
    { points = 1400,   name = "6"  },
    { points = 2000,   name = "5"  },
    { points = 3500,   name = "4"  },
    { points = 5500,   name = "3"  },
    { points = 8000,   name = "2"  },
    { points = 12000,  name = "1"  },
    { points = 16000,  name = "S1" },
    { points = 22000,  name = "S2" },
    { points = 30000,  name = "S3" },
    { points = 40000,  name = "S4" },
    { points = 52000,  name = "S5" },
    { points = 66000,  name = "S6" },
    { points = 82000,  name = "S7" },
    { points = 100000, name = "S8" },
    { points = 120000, name = "S9" },
}

-- Grand Master score threshold (points).
local GM_POINTS = 126000

-- GM time checkpoints (seconds from game start): the elapsed time at which the
-- named level must first be reached. Levels are recorded in Scoring.levelTimes.
local TIME_300 = 4 * 3600 + 15 * 60   -- Level 300 in under 4:15:00
local TIME_500 = 7 * 3600 + 30 * 60   -- Level 500 in under 7:30:00
local TIME_999 = 13 * 3600 + 30 * 60  -- Level 999 in under 13:30:00

-- The maximum achievable level (exported for the HUD).
Scoring.MAX_LEVEL = MAX_LEVEL

--- Create a new scoring object.
function Scoring.new()
    local self = setmetatable({}, Scoring)
    self.points      = 0
    self.level       = 0      -- shown alongside max level (0..999)
    self.combo       = 1      -- combo multiplier for the current clear chain
    self.grade       = GRADES[1].name
    self.levelTimes  = {}     -- { [level] = elapsed seconds when first reached };
                             -- used for the GM time checkpoints (300/500/999)
    return self
end

-- The level multiplier: floor(level/4) + 1. (kept as a documented helper.)
function Scoring.multiplier(level)
    return math.floor(level / 4) + 1
end

-- Record the elapsed time at which a GM-milestone level (300/500/999) is first
-- reached. Called after the level is updated each lock; each milestone is
-- recorded only once, on the first crossing.
function Scoring:checkLevelCheckpoints(time)
    time = time or 0
    for _, lvl in ipairs({300, 500, 999}) do
        if self.levelTimes[lvl] == nil and self.level >= lvl then
            self.levelTimes[lvl] = time
        end
    end
end

-- Whether all GM time checkpoints have been passed (reached the level within
-- the allotted time). A milestone not yet reached (nil) fails the check.
function Scoring:checkpointsMet()
    return self.levelTimes[300] ~= nil and self.levelTimes[300] < TIME_300
        and self.levelTimes[500] ~= nil and self.levelTimes[500] < TIME_500
        and self.levelTimes[999] ~= nil and self.levelTimes[999] < TIME_999
end

-- Advance the grade counter. Grades 9..S9 come purely from points; Grand Master
-- additionally requires reaching GM_POINTS AND passing every time checkpoint.
function Scoring:updateGrade()
    local g = GRADES[1].name
    for i = 1, #GRADES do
        if self.points >= GRADES[i].points then
            g = GRADES[i].name
        else
            break
        end
    end
    if self.points >= GM_POINTS and self:checkpointsMet() then
        g = "GM"
    end
    self.grade = g
end

-- The points required to reach the grade immediately above the current one.
-- For the top base grade (S9) the next grade is Grand Master, whose point
-- threshold is GM_POINTS.
function Scoring:nextGradePoints()
    if self.grade == "GM" then
        return GM_POINTS
    end
    for i = 1, #GRADES do
        if GRADES[i].name == self.grade then
            if i < #GRADES then
                return GRADES[i + 1].points
            end
            return GM_POINTS  -- S9 -> GM
        end
    end
    return GRADES[1].points
end

--- Score a piece lock using the TGM+ formula and update level/grade.
---
---   levelBefore : level at the moment of the clear (before this lock's level ups)
---   lines       : lines cleared by this piece (0..4)
---   soft        : soft-drop frame count for this piece (manual locks add 1)
---   perfectClear: true if the whole field is empty after this clear
---
--- Combo advances on a clear (prevCombo + 2*Lines - 2) and resets to 1 otherwise.
--- Level rises one per line cleared (crosses 100-level boundaries freely).
--- Returns the points awarded.
function Scoring:scoreClear(levelBefore, lines, soft, perfectClear)
    lines = math.max(0, math.min(4, lines or 0))
    soft  = math.max(0, soft or 0)

    -- Combo: advance on a clear, reset to 1 after a non-clearing lock.
    if lines > 0 then
        self.combo = self.combo + 2 * lines - 2
    else
        self.combo = 1
    end

    -- Bravo: 4x multiplier for a Perfect Clear.
    local bravo = (lines > 0 and perfectClear) and 4 or 1

    -- TGM+ score (integer ceiling; no math.ceil dependency for Lua 5.1).
    local gain = (math.floor((levelBefore + lines + 3) / 4) + soft)
                 * lines * self.combo * bravo
    self.points = self.points + gain

    -- Level rises one per line cleared, capped at MAX_LEVEL.
    self.level = math.min(MAX_LEVEL, self.level + lines)

    self:updateGrade()
    return gain
end

--- Advance the level by one because a piece landed.
--- A piece drop does NOT cross a 100-level boundary (level % 100 == 99);
--- only a line clear may do that. Capped at MAX_LEVEL.
function Scoring:levelUpFromPiece()
    if self.level >= MAX_LEVEL then return end
    if self.level % 100 == 99 then return end
    self.level = math.min(MAX_LEVEL, self.level + 1)
end

return Scoring
