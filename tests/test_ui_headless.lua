-- tests/test_ui_headless.lua
-- Headless LÖVE2D mock harness verifying conf.lua, main.lua, ui/graphics.lua, ui/card_view.lua, and ui/retro_gui.lua

local draw_calls = {
    clear = 0,
    rectangle = 0,
    polygon = 0,
    circle = 0,
    ellipse = 0,
    line = 0,
    points = 0,
    print = 0,
    printf = 0,
}

local mock_mx, mock_my = 512, 384
local mock_mdown = false
local mock_time = 100.0

_G.love = {
    graphics = {
        clear = function() draw_calls.clear = draw_calls.clear + 1 end,
        setColor = function() end,
        setLineWidth = function() end,
        rectangle = function() draw_calls.rectangle = draw_calls.rectangle + 1 end,
        polygon = function() draw_calls.polygon = draw_calls.polygon + 1 end,
        circle = function() draw_calls.circle = draw_calls.circle + 1 end,
        ellipse = function() draw_calls.ellipse = draw_calls.ellipse + 1 end,
        line = function() draw_calls.line = draw_calls.line + 1 end,
        points = function() draw_calls.points = draw_calls.points + 1 end,
        print = function() draw_calls.print = draw_calls.print + 1 end,
        printf = function() draw_calls.printf = draw_calls.printf + 1 end,
        getDimensions = function() return 1024, 768 end,
    },
    mouse = {
        getPosition = function() return mock_mx, mock_my end,
        isDown = function() return mock_mdown end,
    },
    timer = {
        getTime = function() return mock_time end,
    },
    event = {
        quit = function() end,
    },
}

require("conf")
local Deck  = require("game.deck")
local State = require("game.state")
local App   = require("main")

local passed = 0
local function assert_true(cond, msg)
    if not cond then
        error("[FAIL] " .. tostring(msg), 2)
    end
    passed = passed + 1
end

print("=== Running Headless LÖVE2D UI & Presentation Layer Tests ===")

-- 1. Verify love.conf
do
    local cfg = { window = {}, modules = {} }
    love.conf(cfg)
    assert_true(cfg.window.width == 1024 and cfg.window.height == 768, "Window configured to 1024x768")
    assert_true(cfg.window.resizable == true, "Window is resizable")
end

-- 2. Verify love.load, love.draw, love.resize
do
    love.load({})
    assert_true(App.match_state ~= nil, "Match state initialized in love.load")
    love.draw()
    assert_true(draw_calls.clear > 0, "love.graphics.clear called for felt background")
    assert_true(draw_calls.rectangle > 20, "Beveled panels and cards drawn")
    assert_true(draw_calls.polygon > 5, "Procedural suit polygons drawn")
    assert_true(draw_calls.points > 0, "Procedural pixel-art suit pips drawn")

    love.resize(1280, 800)
    assert_true(App.card_view.win_w == 1280 and App.card_view.win_h == 800, "Resize updates CardView")
    love.resize(1024, 768)
end

-- 3. Verify Drag-and-Drop Card Play & Illegal Play Bounce-Back Animation
do
    local s = App.match_state
    -- Give P1 a known hand where P2 led 11 of Bells (Monarch)
    s.phase = State.PHASES.WAIT_FOLLOW
    s.active_player = 1
    s.trick.lead_player = 2
    s.trick.follow_player = 1
    s.trick.lead_card = Deck.make_card("Bells", 11)
    s.hands[1] = {
        Deck.make_card("Bells", 1),  -- Legal (Swan)
        Deck.make_card("Bells", 5),  -- Illegal against Monarch when holding 9 of Bells
        Deck.make_card("Bells", 9),  -- Legal (Highest card of Bells)
    }
    love.draw()

    -- Attempt to drag illegal card #2 (Bells 5) into central drop well -> should bounce back!
    local slot2 = App.card_view.hand_slots[2]
    local start_x, start_y = slot2.x + 20, slot2.y + 20
    love.mousepressed(start_x, start_y, 1)
    assert_true(App.card_view.dragging ~= nil, "Dragging started on card 2")

    local drop_x = App.card_view.zones.lead_slot.x + 20
    local drop_y = App.card_view.zones.lead_slot.y + 20
    love.mousemoved(drop_x, drop_y, drop_x - start_x, drop_y - start_y)
    love.draw() -- Renders dragged card with drop shadow
    love.mousereleased(drop_x, drop_y, 1)

    assert_true(App.card_view.bounce_anims["Bells_5"] ~= nil, "Illegal play triggered smooth bounce-back animation")
    love.update(0.10)
    love.draw()
    love.update(0.20)
    assert_true(App.card_view.bounce_anims["Bells_5"] == nil, "Bounce-back animation completed cleanly")

    -- Now drag legal card #1 (Bells 1 Swan) into central drop well -> plays card!
    local slot1 = App.card_view.hand_slots[1]
    love.mousepressed(slot1.x + 20, slot1.y + 20, 1)
    love.mousemoved(drop_x, drop_y, 50, -200)
    love.mousereleased(drop_x, drop_y, 1)
    assert_true(s.phase == State.PHASES.TRICK_RESOLVE, "Valid drag-and-drop played card and entered TRICK_RESOLVE")

    -- Advance timer to auto-resolve trick
    love.update(0.90)
    assert_true(s.phase == State.PHASES.WAIT_LEAD, "Trick auto-resolved after timer")
    assert_true(s.active_player == 1, "Swan (1) loser-leads-next-trick gave P1 the lead")
end

-- 4. Verify Fox (3) Modal, Woodcutter (5) Modal, Win95 Menus, and Hotseat Blind Overlay
do
    local s = App.match_state
    s.hands[1] = {
        Deck.make_card("Keys", 3),
        Deck.make_card("Moons", 5),
        Deck.make_card("Bells", 7),
    }
    love.draw()

    -- Click card #1 (Keys 3 Fox) to play it
    local slot1 = App.card_view.hand_slots[1]
    mock_time = mock_time + 2.0
    love.mousepressed(slot1.x + 20, slot1.y + 20, 1)
    love.mousereleased(slot1.x + 20, slot1.y + 20, 1)
    assert_true(s.phase == State.PHASES.PENDING_FOX_SWAP, "Entered PENDING_FOX_SWAP")
    love.draw() -- Renders Fox modal dialog

    -- Select card #2 in hand and click "Swap Selected Card" button in Fox modal
    local slot2 = App.card_view.hand_slots[2]
    love.mousepressed(slot2.x + 20, slot2.y + 20, 1)
    love.mousereleased(slot2.x + 20, slot2.y + 20, 1)
    assert_true(App.card_view.selected_index == 2, "Selected card 2 for Fox swap")

    local modal_btns = App.gui:get_modal_buttons(s, App.card_view)
    assert_true(#modal_btns == 2, "Fox modal has Swap and Pass buttons")
    love.mousepressed(modal_btns[1].x + 10, modal_btns[1].y + 10, 1)
    assert_true(s.phase == State.PHASES.WAIT_FOLLOW, "Fox Swap modal button dispatched FOX_SWAP and advanced phase")

    -- Test Top Win95 Menu Bar & Help Modals
    love.mousepressed(150, 10, 1) -- Open Help menu
    assert_true(App.gui.active_menu == "Help", "Help menu opened")
    love.draw()
    love.mousepressed(150, 34, 1) -- Click first item (Card Abilities & Rules)
    assert_true(App.gui.active_help_modal == "rules", "Help Rules modal opened")
    love.draw()
    love.keypressed("escape")
    assert_true(App.gui.active_help_modal == nil, "Escape closed Help modal")

    -- Test switching to 1v1 Hotseat via Game Menu
    love.mousepressed(20, 10, 1) -- Open Game menu
    assert_true(App.gui.active_menu == "Game", "Game menu opened")
    love.mousepressed(40, 58, 1) -- Click "New 1 vs. 1 Hotseat Match"
    assert_true(App.match_state.mode == State.MODES.HOTSEAT, "Switched to 1v1 Hotseat mode")
    assert_true(App.match_state.hotseat_hidden == true, "Hotseat starts with privacy shield active")
    love.draw() -- Renders Hotseat Blind Overlay

    -- Press space to reveal Hotseat hand
    love.keypressed("space")
    assert_true(App.match_state.hotseat_hidden == false, "Space revealed Hotseat hand")
    love.draw()

    -- Test Sort keyboard shortcuts
    love.keypressed("v") -- Sort by Value
    love.keypressed("s") -- Sort by Suit
end

print(string.format("=== ALL HEADLESS UI TESTS PASSED (%d assertions) ===", passed))
