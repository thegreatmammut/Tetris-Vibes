-- main.lua
-- Entry point. Wires Love2D callbacks to the scene manager.
--
-- FIX: the old version never called SceneManager.draw() (it only rendered a
-- one-off debug screenshot on frame 2 and then quit), and never forwarded key
-- events, so the title screen was black and Enter did nothing.
--
-- NOTE: the High Scores screen now lives in src/scenes/scores_screen.lua so it
-- can't be confused with the data module src/highscores.lua.

require("src.compat")()
local Log = require("src.log")
local SceneManager = require("src.scenemanager")
local Assets = require("src.assets")
require("src.scenes.title")(SceneManager)
require("src.scenes.game")(SceneManager)
require("src.scenes.versus")(SceneManager)
require("src.scenes.gameover")(SceneManager)
require("src.scenes.scores_screen")(SceneManager)

function love.load()
    Log.reset()
    Log.write("love.load")
    -- Love does not seed math.random for us.
    math.randomseed(os.time())
    math.random(); math.random(); math.random()

    love.graphics.setBackgroundColor(0.02, 0.02, 0.05, 1)
    Assets.init()
    SceneManager.switch("title")
end

function love.update(dt)
    -- Clamp huge dt (window drag, breakpoints) so the fixed-step loop
    -- doesn't try to catch up thousands of ticks.
    if dt > 0.1 then dt = 0.1 end
    SceneManager.update(dt)
end

function love.draw()
    love.graphics.setColor(1, 1, 1, 1)
    SceneManager.draw()

    -- SceneManager swallows scene errors so the game can't hard-crash. Show
    -- the most recent one on screen so a black screen is never a mystery.
    if SceneManager.lastError then
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", 0, 0, 1280, 120)
        love.graphics.setColor(1, 0.3, 0.3, 1)
        if Assets.fonts and Assets.fonts.small then
            love.graphics.setFont(Assets.fonts.small)
        end
        love.graphics.printf("SCENE ERROR: " .. SceneManager.lastError, 20, 20, 1240, "left")
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function love.keypressed(key, scancode, isrepeat)
    SceneManager.keypressed(key, scancode, isrepeat)
end

function love.keyreleased(key, scancode)
    SceneManager.keyreleased(key, scancode)
end

-- Mouse input (used by the ESC menu's slider and song list).
function love.mousepressed(x, y, button, istouch, presses)
    SceneManager.mousepressed(x, y, button, istouch, presses)
end

function love.mousereleased(x, y, button, istouch, presses)
    SceneManager.mousereleased(x, y, button, istouch, presses)
end

function love.mousemoved(x, y, dx, dy, istouch)
    SceneManager.mousemoved(x, y, dx, dy, istouch)
end

function love.wheelmoved(dx, dy)
    SceneManager.wheelmoved(dx, dy)
end

-- Shutdown (window X button / love.event.quit).
-- Closing the window used to crash. The crash happens while Love tears down
-- its native video / audio objects on the way out (even our own cleanup of
-- those objects was not enough), so we skip that teardown entirely: write a
-- log line and end the process straight away. The OS frees everything.
-- If debug.log has "love.quit reached" as its last line, this handler ran.
function love.quit()
    Log.write("love.quit reached - exiting process")
    os.exit(0)
    return false -- not reached; kept so the callback always has a return value
end
