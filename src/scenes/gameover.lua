-- scenes/gameover.lua
-- Game-over scene.
--
-- Dims the screen and shows the final grade, score and time. Pressing Enter
-- returns to the title scene. Final data is passed in via enter(data).

local Assets = require("src.assets")
local Log = require("src.log")

local function register(SceneManager)
    local gameover = {
        _data = nil,
        _video = nil,
    }

    function gameover:enter(data)
        self._data = data or {}
        -- Keep playing the game video in the background, dimmed.
        -- The game scene leaves this video playing; only start it if needed
        -- (no stop/rewind/play churn on the same object in one frame).
        self._video = Assets.currentVideo
        if self._video and not self._video:isPlaying() then
            self._video:play()
        end
    end

    function gameover:exit()
        -- Only pause the shared game video; no rewind. (rewind is skipped
        -- because the game scene resumes/restarts it itself on a new game.)
        Log.write("gameover:exit begin")
        if self._video then
            self._video:pause()
        end
        Log.write("gameover:exit end")
    end

    function gameover:update(dt)
        if self._video and not self._video:isPlaying() then
            self._video:rewind()
            self._video:play()
        end
    end

    function gameover:draw()
        -- Background: dimmed video, or a plain dark colour if there is none.
        if self._video then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(self._video, 0, 0, 0,
                1280 / self._video:getWidth(), 720 / self._video:getHeight())
        else
            love.graphics.setColor(0.04, 0.05, 0.14, 1)
            love.graphics.rectangle("fill", 0, 0, 1280, 720)
        end
        love.graphics.setColor(0, 0, 0, 0.65)
        love.graphics.rectangle("fill", 0, 0, 1280, 720)
        love.graphics.setColor(1, 1, 1, 1)

        local d = self._data or {}
        local large = Assets.fonts.large
        local medium = Assets.fonts.medium
        local small = Assets.fonts.small

        -- Heading (x = centre; "center" align does the centring).
        love.graphics.setFont(large)
        love.graphics.drawText("GAME OVER", 640, 120, 0, 1, 1, "center")

        -- Grade box.
        local grade = tostring(d.grade or "?")
        local bx, by, bw, bh = 640 - 90, 200, 180, 120
        love.graphics.setColor(0.45, 0.30, 0.10, 1)
        love.graphics.rectangle("fill", bx, by, bw, bh)
        love.graphics.setColor(0.85, 0.65, 0.20, 1)
        love.graphics.rectangle("line", bx, by, bw, bh)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(large)
        love.graphics.drawText(grade, 640, by + (bh - large:getHeight()) / 2, 0, 1, 1, "center")
        love.graphics.setFont(small)
        love.graphics.drawText("GRADE", 640, by + bh + 8, 0, 1, 1, "center")

        -- Score.
        love.graphics.setFont(medium)
        local score = string.format("%08d", d.points or 0)
        love.graphics.drawText("SCORE " .. score, 640, 380, 0, 1, 1, "center")

        -- Level.
        love.graphics.drawText("LEVEL " .. tostring(d.level or 0), 640, 420, 0, 1, 1, "center")

        -- Time.
        local s = d.time or 0
        local totalSec = math.floor(s)
        local ss = totalSec % 60
        local mm = math.floor(totalSec / 60)
        local cc = math.floor((s - totalSec) * 100)
        local tstr = string.format("TIME  %02d:%02d:%02d", mm, ss, cc)
        love.graphics.drawText(tstr, 640, 460, 0, 1, 1, "center")

        -- Return prompt.
        love.graphics.setFont(small)
        love.graphics.drawText("PRESS ENTER TO RETURN", 640, 580, 0, 1, 1, "center")
    end

    function gameover:keypressed(key)
        if key == "return" or key == "kpenter" then
            SceneManager.switch("title")
        end
    end

    SceneManager.register("gameover", gameover)
end

return register
