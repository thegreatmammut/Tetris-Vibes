-- scenes/title.lua
-- Title screen scene.
--
-- Shows the main-menu picture (assets/pictures/mainmenu.png) with a blinking
-- "PRESS ENTER TO START". If assets/music/title.ogg exists it plays (looping)
-- on this screen. Pressing Enter opens the main menu:
--   New Game        -> start a fresh game
--   Versus          -> opens the Versus menu (Comp / Multiplayer / Back)
--   High Scores     -> show the saved top-10 scores
-- Comp opens a difficulty menu (Easy / Medium / Hard / Unfair / Back).
-- Arrow keys / mouse select, Enter confirms, Escape goes back.

local Assets = require("src.assets")
local Log = require("src.log")

local function register(SceneManager)
    local title = {
        _blinkOn    = true,
        _blinkTimer = 0,
        _menuOpen   = false,  -- false: start prompt, true: a menu is showing
        _sub        = nil,    -- nil: main menu, "versus", or "difficulty"
        _menuIndex  = 1,      -- selected item in whichever menu is showing
        _notice     = nil,    -- short message shown under the menu
        _noticeTimer = 0,
    }

    -- Menu item labels (1280x720 virtual space).
    local MENU_ITEMS   = { "New Game", "Versus", "High Scores" }
    local VERSUS_ITEMS = { "Comp", "Multiplayer", "Back" }
    local DIFF_ITEMS   = { "Easy", "Medium", "Hard", "Unfair", "Back" }

    local function isLeft(button)
        -- Love2D reports the left button as 1 (older code used "l").
        return button == 1 or button == "l"
    end

    -- Convert a Love mouse coordinate into the 1280x720 virtual space.
    local function toVirtual(x, y)
        local ok, s = pcall(function() return love.window.getDPIScale() end)
        if not ok or not s or s <= 0 then return x, y end
        return x / s, y / s
    end

    function title:_items()
        if self._sub == "versus" then return VERSUS_ITEMS end
        if self._sub == "difficulty" then return DIFF_ITEMS end
        return MENU_ITEMS
    end

    -- First item's vertical centre and the gap between items. The difficulty
    -- menu has five entries so it is packed a little tighter.
    function title:_layout()
        if self._sub == "difficulty" then return 300, 58 end
        return 330, 66
    end

    function title:enter()
        self._blinkOn = true
        self._blinkTimer = 0
        self._menuOpen = false
        self._sub = nil
        self._menuIndex = 1
        self._notice = nil
        self._noticeTimer = 0
        local i = Assets.findSong("title")
        Log.write("title:enter title song=" .. tostring(i))
        if i then
            Assets.playMusic(i, true)
        end
    end

    function title:exit()
        Assets.stopMusic()
    end

    function title:update(dt)
        -- Blink timer (0.5s on / 0.5s off), only on the start prompt.
        if not self._menuOpen then
            self._blinkTimer = self._blinkTimer + dt
            if self._blinkTimer >= 0.5 then
                self._blinkTimer = 0
                self._blinkOn = not self._blinkOn
            end
        end
        if self._noticeTimer > 0 then
            self._noticeTimer = self._noticeTimer - dt
            if self._noticeTimer <= 0 then self._notice = nil end
        end
    end

    function title:draw()
        local pic = Assets.pictures and Assets.pictures.mainmenu
        if pic then
            -- Main menu picture: fit to the screen height and center it
            -- horizontally, preserving aspect ratio (no horizontal stretch).
            love.graphics.setColor(1, 1, 1, 1)
            local scale = 720 / pic:getHeight()
            local scaledW = pic:getWidth() * scale
            love.graphics.draw(pic, (1280 - scaledW) / 2, 0, 0, scale, scale)
        else
            love.graphics.setColor(0.04, 0.05, 0.14, 1)
            love.graphics.rectangle("fill", 0, 0, 1280, 720)
        end
        love.graphics.setColor(1, 1, 1, 1)

        if not self._menuOpen then
            -- Blinking start prompt.
            if self._blinkOn then
                love.graphics.setFont(Assets.fonts.medium)
                love.graphics.setColor(1, 1, 1, 0.95)
                love.graphics.drawText("PRESS ENTER TO START", 640, 600, 0, 1, 1, "center")
            end
        else
            local items = self:_items()
            local y0, gap = self:_layout()

            if self._sub == "difficulty" then
                love.graphics.setFont(Assets.fonts.medium)
                love.graphics.setColor(1, 0.85, 0.2, 1)
                love.graphics.drawText("SELECT DIFFICULTY", 640, 230, 0, 1, 1, "center")
            end

            for i = 1, #items do
                local selected = (i == self._menuIndex)
                local y = y0 + (i - 1) * gap
                if selected then
                    love.graphics.setFont(Assets.fonts.large)
                    -- Cursor arrow.
                    love.graphics.setColor(1, 1, 0.45, 1)
                    love.graphics.drawText(">", 440, y, 0, 1.3, 1.3, "center")
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.drawText(items[i], 620, y, 0, 1.25, 1.25, "center")
                else
                    love.graphics.setFont(Assets.fonts.medium)
                    love.graphics.setColor(0.72, 0.72, 0.72, 1)
                    love.graphics.drawText(items[i], 640, y, 0, 1, 1, "center")
                end
            end
            love.graphics.setFont(Assets.fonts.small)
            love.graphics.setColor(0.6, 0.6, 0.6, 1)
            love.graphics.drawText("USE ARROW KEYS / MOUSE - ENTER TO CHOOSE", 640, 610, 0, 1, 1, "center")
            if self._notice then
                love.graphics.setFont(Assets.fonts.medium)
                love.graphics.setColor(1, 0.85, 0.2, 1)
                love.graphics.drawText(self._notice, 640, 560, 0, 1, 1, "center")
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
    end

    function title:_choose()
        if self._sub == "difficulty" then
            local item = DIFF_ITEMS[self._menuIndex]
            if item == "Back" then
                self._sub = "versus"
                self._menuIndex = 1       -- land back on "Comp"
            else
                SceneManager.switch("versus", { mode = "comp", difficulty = item:lower() })
            end
        elseif self._sub == "versus" then
            local item = VERSUS_ITEMS[self._menuIndex]
            if item == "Comp" then
                self._sub = "difficulty"
                self._menuIndex = 2       -- default highlight: Medium
                self._notice = nil
            elseif item == "Multiplayer" then
                -- Not implemented yet.
                self._notice = "MULTIPLAYER COMING SOON"
                self._noticeTimer = 2
            elseif item == "Back" then
                self._sub = nil
                self._menuIndex = 2       -- land back on "Versus"
            end
        else
            local item = MENU_ITEMS[self._menuIndex]
            if item == "New Game" then
                SceneManager.switch("game")
            elseif item == "Versus" then
                self._sub = "versus"
                self._menuIndex = 1
                self._notice = nil
            elseif item == "High Scores" then
                SceneManager.switch("highscores")
            end
        end
    end

    -- Step back one menu level (Escape).
    function title:_back()
        if self._sub == "difficulty" then
            self._sub = "versus"
            self._menuIndex = 1
        elseif self._sub == "versus" then
            self._sub = nil
            self._menuIndex = 2
        else
            -- Return to the start prompt instead of the menu.
            self._menuOpen = false
        end
    end

    function title:keypressed(key)
        if not self._menuOpen then
            if key == "return" or key == "kpenter" then
                Assets.play("coin")
                self._menuOpen = true
                self._sub = nil
                self._menuIndex = 1
            end
        else
            local items = self:_items()
            if key == "up" then
                self._menuIndex = math.max(1, self._menuIndex - 1)
            elseif key == "down" then
                self._menuIndex = math.min(#items, self._menuIndex + 1)
            elseif key == "return" or key == "kpenter" then
                Assets.play("coin")
                self:_choose()
            elseif key == "escape" then
                self:_back()
            end
        end
    end

    function title:mousepressed(x, y, button)
        if not isLeft(button) then return end
        if not self._menuOpen then
            -- Clicking anywhere opens the menu (Enter-equivalent).
            Assets.play("coin")
            self._menuOpen = true
            self._sub = nil
            self._menuIndex = 1
            return
        end
        x, y = toVirtual(x, y)
        local items = self:_items()
        local y0, gap = self:_layout()
        local half = gap / 2 - 2
        for i = 1, #items do
            local my = y0 + (i - 1) * gap
            if y >= my - half and y <= my + half then
                self._menuIndex = i
                Assets.play("coin")
                self:_choose()
                return
            end
        end
    end

    SceneManager.register("title", title)
end

return register
