-- src/log.lua
-- Tiny breadcrumb logger. Appends one line per call to debug.log in the game
-- folder (the directory the game is launched from) and closes the file every
-- time, so the last line survives even a hard native crash. If the game
-- crashes, the last line in debug.log shows the last step that was reached.

local Log = {}

local PATH = "debug.log"

function Log.reset()
    pcall(function()
        local f = io.open(PATH, "w")
        if f then f:write("-- debug.log --\n"); f:close() end
    end)
end

function Log.write(msg)
    pcall(function()
        local f = io.open(PATH, "a")
        if f then
            f:write(string.format("%.3f  %s\n", love.timer.getTime(), tostring(msg)))
            f:close()
        end
    end)
end

return Log
