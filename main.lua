-- main.lua
-- LÖVE2D Entrypoint for "The Fox in the Forest" (Windows 95 Retro Edition)

local State    = require("game.state")
local AI       = require("game.ai")
local Graphics = require("ui.graphics")
local CardView = require("ui.card_view")
local RetroGUI = require("ui.retro_gui")

local App = {
    match_state = nil,
    card_view = nil,
    gui = nil,
    seed_counter = 202610,
    ai_timer = 0,
    ai_delay = 0.45,
    trick_timer = 0,
    trick_delay = 0.85,
    smoke_test = false,
    smoke_frames = 0,
}

local function execute_gui_command(cmd_obj)
    if not cmd_obj or not cmd_obj.cmd then
        return
    end
    local cmd = cmd_obj.cmd
    local s = App.match_state
    local view_p = App.card_view:get_view_player(s)

    if cmd == "NEW_PVE" then
        App.seed_counter = App.seed_counter + 17
        App.match_state = State.new_match({
            seed = App.seed_counter,
            mode = State.MODES.PVE,
            target_score = s.target_score,
        })
        App.card_view.selected_index = nil
    elseif cmd == "NEW_HOTSEAT" then
        App.seed_counter = App.seed_counter + 23
        App.match_state = State.new_match({
            seed = App.seed_counter,
            mode = State.MODES.HOTSEAT,
            target_score = s.target_score,
        })
        App.card_view.selected_index = nil
    elseif cmd == "NEW_MATCH_SAME_MODE" then
        App.seed_counter = App.seed_counter + 31
        App.match_state = State.new_match({
            seed = App.seed_counter,
            mode = s.mode,
            target_score = s.target_score,
        })
        App.card_view.selected_index = nil
    elseif cmd == "RESTART_RND" then
        State.start_round(s)
        App.card_view.selected_index = nil
    elseif cmd == "UNDO" then
        -- In 1vAI mode, undo back to the human player's turn
        local ok = State.undo(s)
        if ok and s.mode == State.MODES.PVE then
            while s.active_player == 2 and #s.undo_stack > 0 do
                State.undo(s)
            end
        end
        App.card_view.selected_index = nil
    elseif cmd == "SORT_SUIT" then
        State.apply_action(s, { type = "SORT_HAND", player = view_p, mode = "suit" })
        App.card_view.selected_index = nil
    elseif cmd == "SORT_VALUE" then
        State.apply_action(s, { type = "SORT_HAND", player = view_p, mode = "value" })
        App.card_view.selected_index = nil
    elseif cmd == "TARGET_16" then
        s.target_score = 16
        s.status_message = "Target victory score set to 16 points."
    elseif cmd == "TARGET_21" then
        s.target_score = 21
        s.status_message = "Target victory score set to 21 points."
    elseif cmd == "TARGET_35" then
        s.target_score = 35
        s.status_message = "Target victory score set to 35 points."
    elseif cmd == "HELP_RULES" then
        App.gui.active_help_modal = "rules"
    elseif cmd == "HELP_SCORING" then
        App.gui.active_help_modal = "scoring"
    elseif cmd == "HELP_ABOUT" then
        App.gui.active_help_modal = "about"
    elseif cmd == "CLOSE_HELP" then
        App.gui.active_help_modal = nil
    elseif cmd == "REVEAL_HOTSEAT" then
        State.apply_action(s, { type = "REVEAL_HOTSEAT" })
    elseif cmd == "CONFIRM_FOX_SWAP" then
        local idx = App.card_view.selected_index
        if idx then
            State.apply_action(s, { type = "FOX_SWAP", player = s.active_player, hand_index = idx })
            App.card_view.selected_index = nil
        end
    elseif cmd == "CONFIRM_FOX_PASS" then
        State.apply_action(s, { type = "FOX_PASS", player = s.active_player })
        App.card_view.selected_index = nil
    elseif cmd == "CONFIRM_WOODCUTTER_BURY" then
        local idx = App.card_view.selected_index
        if idx then
            State.apply_action(s, { type = "WOODCUTTER_BURY", player = s.active_player, hand_index = idx })
            App.card_view.selected_index = nil
        end
    elseif cmd == "NEXT_ROUND" then
        State.apply_action(s, { type = "NEXT_ROUND" })
        App.card_view.selected_index = nil
    elseif cmd == "QUIT" then
        if love and love.event then
            love.event.quit()
        end
    end
end

function love.load(args)
    App.card_view = CardView.new()
    App.gui = RetroGUI.new()
    App.match_state = State.new_match({
        seed = App.seed_counter,
        mode = State.MODES.PVE,
        target_score = 21,
    })

    if love.graphics and love.graphics.getDimensions then
        local w, h = love.graphics.getDimensions()
        App.card_view:update_layout(w, h)
        App.gui:update_layout(w, h)
    end

    if type(args) == "table" then
        for i = 1, #args do
            if args[i] == "--smoke-test" then
                App.smoke_test = true
                App.smoke_frames = 0
            end
        end
    end
end

function love.resize(w, h)
    if App.card_view then
        App.card_view:update_layout(w, h)
    end
    if App.gui then
        App.gui:update_layout(w, h)
    end
end

function love.update(dt)
    local s = App.match_state
    if not s then
        return
    end

    local mx, my = 0, 0
    local is_down = false
    if love.mouse then
        mx, my = love.mouse.getPosition()
        is_down = love.mouse.isDown(1)
    end

    App.gui:update_mouse(mx, my, is_down)
    App.card_view:update(dt, s, mx, my)

    if App.gui.active_help_modal or s.hotseat_hidden then
        return
    end

    -- Automatic Trick Resolution pause so both played cards remain visible briefly
    if s.phase == State.PHASES.TRICK_RESOLVE then
        App.trick_timer = App.trick_timer + dt
        if App.trick_timer >= App.trick_delay then
            App.trick_timer = 0
            State.apply_action(s, { type = "RESOLVE_TRICK" })
        end
        return
    else
        App.trick_timer = 0
    end

    -- AI Turn Execution in 1 vs. AI Mode
    if s.mode == State.MODES.PVE and s.active_player == 2 then
        if s.phase == State.PHASES.WAIT_LEAD
            or s.phase == State.PHASES.WAIT_FOLLOW
            or s.phase == State.PHASES.PENDING_FOX_SWAP
            or s.phase == State.PHASES.PENDING_WOODCUTTER_BURY then
            App.ai_timer = App.ai_timer + dt
            if App.ai_timer >= App.ai_delay then
                App.ai_timer = 0
                local ai_action = AI.choose_action(s, 2)
                if ai_action then
                    State.apply_action(s, ai_action)
                end
            end
        end
    else
        App.ai_timer = 0
    end
end

function love.draw()
    local s = App.match_state
    if not s then
        return
    end
    local w, h = App.card_view.win_w, App.card_view.win_h
    Graphics.clear_felt(w, h)
    App.card_view:draw_table_and_hands(s)
    App.gui:draw_menus_and_chrome(s, App.card_view)

    if App.smoke_test then
        App.smoke_frames = App.smoke_frames + 1
        if App.smoke_frames == 2 then
            -- Exercise card play & AI response during live LOVE2D render loop
            local action = AI.choose_action(s, s.active_player)
            if action then
                State.apply_action(s, action)
            end
        elseif App.smoke_frames >= 5 then
            print("[OK] LOVE2D 11.5 live render & gameplay smoke test passed.")
            if love and love.event then
                love.event.quit(0)
            end
        end
    end
end

function love.mousepressed(x, y, button)
    local s = App.match_state
    if not s then
        return
    end

    -- If trick is waiting to resolve, clicking anywhere resolves it immediately
    if s.phase == State.PHASES.TRICK_RESOLVE and not App.gui.active_menu and y > 24 then
        App.trick_timer = 0
        State.apply_action(s, { type = "RESOLVE_TRICK" })
        return
    end

    local consumed, cmd_obj = App.gui:mousepressed(s, App.card_view, x, y, button)
    if consumed then
        if cmd_obj then
            execute_gui_command(cmd_obj)
        end
        return
    end

    App.card_view:mousepressed(s, x, y, button)
end

function love.mousemoved(x, y, dx, dy)
    local s = App.match_state
    if not s then
        return
    end
    App.gui:update_mouse(x, y, love.mouse and love.mouse.isDown(1) or false)
    App.card_view:mousemoved(s, x, y, dx, dy)
end

function love.mousereleased(x, y, button)
    local s = App.match_state
    if not s then
        return
    end
    App.gui:update_mouse(x, y, false)
    local action, feedback = App.card_view:mousereleased(s, x, y, button)
    if action then
        local ok, err = State.apply_action(s, action)
        if not ok and err then
            s.status_message = err
        end
    elseif feedback then
        s.status_message = feedback
    end
end

function love.keypressed(key)
    local s = App.match_state
    if not s then
        return
    end
    if key == "escape" then
        if App.gui.active_help_modal then
            App.gui.active_help_modal = nil
        elseif App.gui.active_menu then
            App.gui.active_menu = nil
        end
    elseif key == "s" then
        execute_gui_command({ cmd = "SORT_SUIT" })
    elseif key == "v" then
        execute_gui_command({ cmd = "SORT_VALUE" })
    elseif key == "z" then
        execute_gui_command({ cmd = "UNDO" })
    elseif key == "f1" then
        execute_gui_command({ cmd = "HELP_RULES" })
    elseif key == "space" or key == "return" then
        if s.hotseat_hidden then
            execute_gui_command({ cmd = "REVEAL_HOTSEAT" })
        elseif s.phase == State.PHASES.TRICK_RESOLVE then
            State.apply_action(s, { type = "RESOLVE_TRICK" })
        elseif s.phase == State.PHASES.ROUND_OVER then
            execute_gui_command({ cmd = "NEXT_ROUND" })
        end
    end
end

return App
