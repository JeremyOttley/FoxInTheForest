-- conf.lua
-- LÖVE2D configuration for "The Fox in the Forest - Windows 95 Retro Edition"

function love.conf(t)
    t.identity = "fox_in_the_forest_win95"
    t.version = "11.5"
    t.console = false

    t.window.title = "The Fox in the Forest - Windows 95 Edition"
    t.window.width = 1024
    t.window.height = 768
    t.window.resizable = true
    t.window.minwidth = 800
    t.window.minheight = 600
    t.window.vsync = 1

    t.modules.audio = true
    t.modules.event = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.joystick = false
    t.modules.keyboard = true
    t.modules.math = true
    t.modules.mouse = true
    t.modules.physics = false
    t.modules.sound = true
    t.modules.system = true
    t.modules.timer = true
    t.modules.touch = false
    t.modules.video = false
    t.modules.window = true
end
