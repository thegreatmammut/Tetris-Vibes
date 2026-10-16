-- scenes/scores_screen.lua
-- High Scores screen (renamed from scenes/highscores.lua to avoid being
-- confused with the data module src/highscores.lua).
--
-- Displays the top saved scores (rank, score, grade, level, time). Press
-- Enter or Escape to return to the title screen. Loads the list from disk on
-- entry via the HighScores module.

local Assets = require("src.assets")
local HighScores = require("src.highscores")

local function register(SceneManager)
    local hs = {
        _scores = {},
    }

    -- 1280x720 virtual-space layout.
    local ROW_H = 54
    local FIRST_Y = 210
    local COL_RANK = 320
    local COL_SCORE = 600
    local COL_GRADE = 820
    local COL_LEVEL = 1000
    local COL_TIME = 1160

    function hs:enter()
        self._scores = HighScores:load()
    end

    function hs:update(dt)
    end

    function hs:draw()
        -- Background: dimmed dark-blue, matching the game-over look.
        love.graphics.setColor(0.04, 0.05, 0.14, 1)
        love.graphics.rectangle("fill", 0, 0, 1280, 720)
        love.graphics.setColor(1, 1, 1, 1)

        local large = Assets.fonts.large
        local medium = Assets.fonts.medium
        local small = Assets.fonts.small

        love.graphics.setFont(large)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.drawText("HIGH SCORES", 640, 80, 0, 1, 1, "center")

        local scores = self._scores
        if #scores == 0 then
            love.graphics.setFont(medium)
            love.graphics.setColor(0.75, 0.75, 0.75, 1)
            love.graphics.drawText("NO SCORES YET", 640, 320, 0, 1, 1, "center")
            love.graphics.setFont(small)
            love.graphics.setColor(0.65, 0.65, 0.65, 1)
            love.graphics.drawText("PRESS ENTER OR ESCAPE TO RETURN", 640, 640, 0, 1, 1, "center")
            return
        end

        -- Column headers.
        love.graphics.setFont(small)
        love.graphics.setColor(0.65, 0.65, 0.65, 1)
        love.graphics.drawText("RANK",    COL_RANK,    150, 0, 1, 1, "center")
        love.graphics.drawText("SCORE",   COL_SCORE,   150, 0, 1, 1, "center")
        love.graphics.drawText("GRADE",   COL_GRADE,   150, 0, 1, 1, "center")
        love.graphics.drawText("LVL",     COL_LEVEL,   150, 0, 1, 1, "center")
        love.graphics.drawText("TIME",    COL_TIME,    150, 0, 1, 1, "center")

        -- Entries.
        for i = 1, #scores do
            local e = scores[i]
            local y = FIRST_Y + (i - 1) * ROW_H

            -- Alternate row shading.
            if i % 2 == 0 then
                love.graphics.setColor(0.10, 0.12, 0.22, 0.5)
                love.graphics.rectangle("fill", 250, y - 18, 840, ROW_H - 6)
            end
            love.graphics.setColor(1, 1, 1, 1)

            love.graphics.setFont(large)
            love.graphics.drawText(tostring(i),         COL_RANK,    y, 0, 1, 1, "center")

            love.graphics.setFont(medium)
            love.graphics.drawText(string.format("%08d", e.score or 0), COL_SCORE, y, 0, 1, 1, "center")

            love.graphics.setFont(large)
            love.graphics.drawText(tostring(e.grade or "?"), COL_GRADE, y, 0, 1, 1, "center")

            love.graphics.setFont(medium)
            love.graphics.drawText(tostring(e.level or 0), COL_LEVEL, y, 0, 1, 1, "center")

            -- Time as H:M:S.cc -> display as HH:MM:SS.
            local sec = math.floor(e.time or 0)
            local ss = sec % 60
            local mm = math.floor(sec / 60) % 60
            local hh = math.floor(sec / 3600)
            local tstr = string.format("%02d:%02d:%02d", hh, mm, ss)
            love.graphics.setFont(small)
            love.graphics.drawText(tstr, COL_TIME, y, 0, 1, 1, "center")
        end

        -- Return prompt.
        love.graphics.setFont(small)
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        love.graphics.drawText("PRESS ENTER OR ESCAPE TO RETURN", 640, 680, 0, 1, 1, "center")
    end

    function hs:keypressed(key)
        if key == "return" or key == "kpenter" or key == "escape" then
            SceneManager.switch("title")
        end
    end

    SceneManager.register("highscores", hs)
end

return register
