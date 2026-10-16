-- scenemanager.lua
-- A minimal scene manager.
--
-- A "scene" is just a table with any subset of these optional methods:
--   enter(...)  called when the scene becomes current (after exit())
--   exit()      called when the scene stops being current
--   update(dt)  per-frame logic
--   draw()      per-frame rendering
--   keypressed(key, scancode, isrepeat)
--   keyreleased(key, scancode, isrepeat)
--
-- Public API:
--   SceneManager.register(name, scene)
--   SceneManager.switch(name, ...)     -- calls exit() on old, enter() on new
--   SceneManager.update(dt)
--   SceneManager.draw()
--   SceneManager.keypressed(key, ...)
--   SceneManager.keyreleased(key, ...)
--   SceneManager.lastError             -- last scene error string (or nil)

local Log = require("src.log")

local SceneManager = {}

-- name -> scene table
SceneManager.scenes = {}
-- name of the currently active scene
SceneManager.current = nil
-- most recent error raised inside a scene method (shown by main.lua)
SceneManager.lastError = nil

--- Wrap a scene call so a crash in one scene cannot kill the whole game.
--- Errors are no longer silent: they are printed to the console and stored in
--- SceneManager.lastError so they can be shown on screen.
local function call(scene, method, ...)
    if scene and scene[method] then
        local ok, err = pcall(scene[method], scene, ...)
        if not ok then
            SceneManager.lastError = tostring(scene.name or "?") .. ":" .. method .. " -> " .. tostring(err)
            print(SceneManager.lastError)
        end
    end
end

--- Register a scene under a name.
function SceneManager.register(name, scene)
    scene.name = name
    SceneManager.scenes[name] = scene
end

--- Switch to a new scene.
--- Runs exit() on the current scene (if any) then enter(...) on the new one.
--- Extra arguments are forwarded to the new scene's enter().
function SceneManager.switch(name, ...)
    local newScene = SceneManager.scenes[name]
    assert(newScene, "SceneManager: unknown scene '" .. tostring(name) .. "'")

    Log.write("switch -> " .. tostring(name) .. " : exit old scene")
    SceneManager.lastError = nil
    call(SceneManager.current, "exit")
    SceneManager.current = newScene
    Log.write("switch -> " .. tostring(name) .. " : enter new scene")
    call(newScene, "enter", ...)
    Log.write("switch -> " .. tostring(name) .. " : done")
end

--- Forward love.update to the active scene.
function SceneManager.update(dt)
    call(SceneManager.current, "update", dt)
end

--- Forward love.draw to the active scene.
function SceneManager.draw()
    call(SceneManager.current, "draw")
end

--- Forward love.keypressed to the active scene.
function SceneManager.keypressed(key, scancode, isrepeat)
    call(SceneManager.current, "keypressed", key, scancode, isrepeat)
end

--- Forward love.keyreleased to the active scene.
function SceneManager.keyreleased(key, scancode, isrepeat)
    call(SceneManager.current, "keyreleased", key, scancode, isrepeat)
end

--- Mouse events, forwarded to the active scene (used by the ESC menu).
function SceneManager.mousepressed(x, y, button, istouch, presses)
    call(SceneManager.current, "mousepressed", x, y, button, istouch, presses)
end

function SceneManager.mousereleased(x, y, button, istouch, presses)
    call(SceneManager.current, "mousereleased", x, y, button, istouch, presses)
end

function SceneManager.mousemoved(x, y, dx, dy, istouch)
    call(SceneManager.current, "mousemoved", x, y, dx, dy, istouch)
end

function SceneManager.wheelmoved(dx, dy)
    call(SceneManager.current, "wheelmoved", dx, dy)
end

return SceneManager
