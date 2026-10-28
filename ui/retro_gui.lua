-- ui/retro_gui.lua
-- Classic Windows 95/98 menus, recessed scoreboards, sort buttons, status bar, and interactive modals

local Rules    = require("game.rules")
local State    = require("game.state")
local Graphics = require("ui.graphics")

local RetroGUI = {}
RetroGUI.__index = RetroGUI

function RetroGUI.new()
    local self = setmetatable({
        win_w = 1024,
        win_h = 768,
        mx = 0,
        my = 0,
        mouse_down = false,
        active_menu = nil, -- "Game", "Options", "Help", or nil
        active_help_modal = nil, -- "rules", "scoring", "about", or nil
        buttons = {},
        menus = {},
    }, RetroGUI)
    self: build_menus()
    self:update_layout(1024, 768)
    return self
end

function RetroGUI:build_menus()
    self.menus = {
        {
            id = "Game",
            label = "Game",
            x = 6,
            w = 56,
            items = {
                { id = "NEW_PVE",     label = "New 1 vs. AI Match" },
                { id = "NEW_HOTSEAT", label = "New 1 vs. 1 Hotseat Match" },
                { id = "UNDO",        label = "Undo Last Action" },
                { id = "RESTART_RND", label = "Restart Round" },
                { id = "QUIT",        label = "Exit Game" },
            },
        },
        {
            id = "Options",
            label = "Options",
            x = 66,
            w = 68,
            items = {
                { id = "SORT_SUIT",   label = "Sort Hand by Suit" },
                { id = "SORT_VALUE",  label = "Sort Hand by Value" },
                { id = "TARGET_16",   label = "Target Score: 16 (Short)" },
                { id = "TARGET_21",   label = "Target Score: 21 (Standard)" },
                { id = "TARGET_35",   label = "Target Score: 35 (Long)" },
            },
        },
        {
            id = "Help",
            label = "Help",
            x = 138,
            w = 52,
            items = {
                { id = "HELP_RULES",   label = "Card Abilities & Rules..." },
                { id = "HELP_SCORING", label = "Scoring Table Reference..." },
                { id = "HELP_ABOUT",   label = "About Fox in the Forest..." },
            },
        },
    }
end

function RetroGUI:update_layout(w, h)
    self.win_w = w
    self.win_h = h

    -- Persistent tabletop toolbar buttons (bottom-left and bottom-right above status bar)
    local btn_y = h - 68
    self.buttons = {
        sort_suit = {
            id = "SORT_SUIT",
            label = "Sort: Suit",
            x = 16,
            y = btn_y - 34,
            w = 96,
            h = 28,
        },
        sort_value = {
            id = "SORT_VALUE",
            label = "Sort: Value",
            x = 16,
            y = btn_y,
            w = 96,
            h = 28,
        },
        undo = {
            id = "UNDO",
            label = "Undo",
            x = w - 112,
            y = btn_y - 34,
            w = 96,
            h = 28,
        },
        help = {
            id = "HELP_RULES",
            label = "Rules / Help",
            x = w - 112,
            y = btn_y,
            w = 96,
            h = 28,
        },
    }
end

local function point_in_rect(px, py, rx, ry, rw, rh)
    return px >= rx and px <= (rx + rw) and py >= ry and py <= (ry + rh)
end

function RetroGUI:update_mouse(mx, my, is_down)
    self.mx = mx
    self.my = my
    self.mouse_down = is_down
end

-- Computes the modal dialog button geometry for current state
function RetroGUI:get_modal_buttons(s, card_view)
    local cx = math.floor(self.win_w * 0.5)
    local cy = math.floor(self.win_h * 0.46)
    local modal_btns = {}

    if self.active_help_modal then
        modal_btns[#modal_btns + 1] = {
            id = "CLOSE_HELP",
            label = "OK / Close",
            x = cx - 55,
            y = cy + 148,
            w = 110,
            h = 28,
        }
        return modal_btns
    end

    if s.hotseat_hidden then
        modal_btns[#modal_btns + 1] = {
            id = "REVEAL_HOTSEAT",
            label = string.format("Click to Reveal Player %d's Hand", s.active_player),
            x = cx - 130,
            y = cy + 25,
            w = 260,
            h = 34,
        }
        return modal_btns
    end

    local view_p = card_view:get_view_player(s)

    if s.phase == State.PHASES.PENDING_FOX_SWAP and s.active_player == view_p then
        local box_y = cy + 82
        local has_sel = (card_view.selected_index ~= nil)
        modal_btns[#modal_btns + 1] = {
            id = "CONFIRM_FOX_SWAP",
            label = "Swap Selected Card",
            x = cx - 155,
            y = box_y + 42,
            w = 148,
            h = 28,
            disabled = not has_sel,
        }
        modal_btns[#modal_btns + 1] = {
            id = "CONFIRM_FOX_PASS",
            label = "Keep Decree (Pass)",
            x = cx + 7,
            y = box_y + 42,
            w = 148,
            h = 28,
        }
    elseif s.phase == State.PHASES.PENDING_WOODCUTTER_BURY and s.active_player == view_p then
        local box_y = cy + 82
        local has_sel = (card_view.selected_index ~= nil)
        modal_btns[#modal_btns + 1] = {
            id = "CONFIRM_WOODCUTTER_BURY",
            label = "Bury Selected Card to Bottom",
            x = cx - 115,
            y = box_y + 42,
            w = 230,
            h = 28,
            disabled = not has_sel,
        }
    elseif s.phase == State.PHASES.ROUND_OVER then
        modal_btns[#modal_btns + 1] = {
            id = "NEXT_ROUND",
            label = "Deal Next Round",
            x = cx - 80,
            y = cy + 105,
            w = 160,
            h = 32,
        }
    elseif s.phase == State.PHASES.MATCH_OVER then
        modal_btns[#modal_btns + 1] = {
            id = "NEW_MATCH_SAME_MODE",
            label = "Play Another Match",
            x = cx - 85,
            y = cy + 105,
            w = 170,
            h = 32,
        }
    end

    return modal_btns
end

-- Handles mouse press on menus, modals, and toolbar buttons.
-- Returns (consumed, command_table)
function RetroGUI:mousepressed(s, card_view, mx, my, button)
    self.mx = mx
    self.my = my
    self.mouse_down = (button == 1)

    if button ~= 1 then
        self.active_menu = nil
        return false, nil
    end

    -- 1. Check open dropdown menu items first
    if self.active_menu then
        for _, m in ipairs(self.menus) do
            if m.id == self.active_menu then
                local drop_x = m.x
                local drop_y = 24
                local drop_w = 210
                local item_h = 24
                for idx, item in ipairs(m.items) do
                    local iy = drop_y + (idx - 1) * item_h
                    if point_in_rect(mx, my, drop_x, iy, drop_w, item_h) then
                        self.active_menu = nil
                        return true, { cmd = item.id }
                    end
                end
            end
        end
    end

    -- 2. Check top menu bar headers
    if my <= 24 then
        for _, m in ipairs(self.menus) do
            if point_in_rect(mx, my, m.x, 2, m.w, 20) then
                if self.active_menu == m.id then
                    self.active_menu = nil
                else
                    self.active_menu = m.id
                end
                return true, nil
            end
        end
        self.active_menu = nil
        return true, nil
    end

    self.active_menu = nil

    -- 3. Check modal dialog buttons
    local modal_btns = self:get_modal_buttons(s, card_view)
    for _, b in ipairs(modal_btns) do
        if point_in_rect(mx, my, b.x, b.y, b.w, b.h) then
            if b.disabled then
                return true, nil
            end
            return true, { cmd = b.id }
        end
    end

    -- Block clicks beneath full-screen blocking modals
    if self.active_help_modal or s.hotseat_hidden or s.phase == State.PHASES.ROUND_OVER or s.phase == State.PHASES.MATCH_OVER then
        return true, nil
    end

    -- 4. Check persistent toolbar buttons
    for _, b in pairs(self.buttons) do
        if point_in_rect(mx, my, b.x, b.y, b.w, b.h) then
            return true, { cmd = b.id }
        end
    end

    return false, nil
end

function RetroGUI:draw_scoreboard(s)
    -- Right-side recessed Win95 scoreboard & telemetry panel
    local pw = 216
    local ph = 246
    local px = self.win_w - pw - 14
    local py = 46

    Graphics.draw_raised_panel(px, py, pw, ph, Graphics.COLORS.WIN_GRAY)

    -- Navy header bar
    love.graphics.setColor(Graphics.COLORS.WIN_NAVY)
    love.graphics.rectangle("fill", px + 4, py + 4, pw - 8, 20)
    love.graphics.setColor(1, 1, 1, 1)
    local mode_label = (s.mode == State.MODES.PVE) and "1 vs. AI" or "1v1 Hotseat"
    love.graphics.printf(string.format("SCOREBOARD (%s)", mode_label), px + 6, py + 7, pw - 12, "center")

    -- Sunken match telemetry well
    Graphics.draw_sunken_panel(px + 8, py + 28, pw - 16, 38, Graphics.COLORS.WIN_SOFT_LIGHT)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.print(string.format("Round: #%d   Target: %d pts", s.round_number, s.target_score), px + 14, py + 33)
    local trump_str = s.decree and (s.decree.suit .. " (" .. tostring(s.decree.rank) .. ")") or "None"
    love.graphics.print("Trump Suit: " .. trump_str, px + 14, py + 48)

    -- Player 1 & Player 2 / AI Sunken Wells
    for p = 1, 2 do
        local wy = py + 72 + (p - 1) * 70
        local is_turn = (s.active_player == p)
        local bg = is_turn and { 0.98, 0.96, 0.84, 1.0 } or Graphics.COLORS.WIN_SOFT_LIGHT
        Graphics.draw_sunken_panel(px + 8, wy, pw - 16, 64, bg)

        local p_name = (p == 1) and "Player 1" or ((s.mode == State.MODES.PVE) and "Player 2 (AI)" or "Player 2")
        local turn_tag = is_turn and " [ACTIVE]" or ""
        love.graphics.setColor(0, 0, 0.5, 1)
        love.graphics.print(p_name .. turn_tag, px + 14, wy + 5)

        local tricks = s.tricks_won[p] or 0
        local bonus = s.round_bonus[p] or 0
        local _, tier_label = Rules.trick_points(tricks)

        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.print(string.format("Match Score: %d / %d", s.scores[p], s.target_score), px + 14, wy + 23)
        love.graphics.print(string.format("Tricks: %d (%s)  +7s: %d", tricks, tier_label, bonus), px + 14, wy + 41)
    end

    -- Quick Scoring Legend Footer inside Scoreboard
    love.graphics.setColor(0.2, 0.2, 0.2, 1)
    love.graphics.printf("0-3:6p | 4:1p | 5:2p | 6:3p | 7-9:6p | 10+:0p", px + 6, py + ph - 26, pw - 12, "center")
end

function RetroGUI:draw_ability_banner(s, card_view)
    local view_p = card_view:get_view_player(s)
    if s.active_player ~= view_p or s.hotseat_hidden then
        return
    end
    if s.phase ~= State.PHASES.PENDING_FOX_SWAP and s.phase ~= State.PHASES.PENDING_WOODCUTTER_BURY then
        return
    end

    local cx = math.floor(self.win_w * 0.5)
    local cy = math.floor(self.win_h * 0.46)
    local bw = 360
    local bh = 82
    local bx = cx - math.floor(bw * 0.5)
    local by = cy + 78

    local title = (s.phase == State.PHASES.PENDING_FOX_SWAP)
        and "Fox (3) Ability: Swap with Decree?"
        or "Woodcutter (5) Ability: Bury 1 Card"

    Graphics.draw_window_frame(bx, by, bw, bh, title)

    local hand = s.hands[view_p] or {}
    local sel_card = card_view.selected_index and hand[card_view.selected_index] or nil
    local sel_text = sel_card and string.format("Selected: %d of %s", sel_card.rank, sel_card.suit) or "Click a card in your hand below..."

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.printf(sel_text, bx + 10, by + 26, bw - 20, "center")

    local modal_btns = self:get_modal_buttons(s, card_view)
    for _, b in ipairs(modal_btns) do
        local hov = point_in_rect(self.mx, self.my, b.x, b.y, b.w, b.h)
        Graphics.draw_button(b.x, b.y, b.w, b.h, b.label, hov, hov and self.mouse_down, b.disabled)
    end
end

function RetroGUI:draw_blocking_modals(s, card_view)
    local cx = math.floor(self.win_w * 0.5)
    local cy = math.floor(self.win_h * 0.46)

    -- 1. Hotseat Blind Pass-Turn Overlay
    if s.hotseat_hidden then
        love.graphics.setColor(0, 0.22, 0, 0.88)
        love.graphics.rectangle("fill", 0, 24, self.win_w, self.win_h - 48)

        local mw, mh = 420, 160
        local mx = cx - math.floor(mw * 0.5)
        local my = cy - math.floor(mh * 0.5)
        Graphics.draw_window_frame(mx, my, mw, mh, "Hotseat Privacy Shield - Pass Turn")

        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.printf(
            string.format("Pass control to Player %d.\nOther player: please look away from the screen!", s.active_player),
            mx + 20,
            my + 42,
            mw - 40,
            "center"
        )

        local modal_btns = self:get_modal_buttons(s, card_view)
        for _, b in ipairs(modal_btns) do
            local hov = point_in_rect(self.mx, self.my, b.x, b.y, b.w, b.h)
            Graphics.draw_button(b.x, b.y, b.w, b.h, b.label, hov, hov and self.mouse_down, b.disabled)
        end
        return
    end

    -- 2. Round Over / Match Over Summary Dialog
    if s.phase == State.PHASES.ROUND_OVER or s.phase == State.PHASES.MATCH_OVER then
        local mw, mh = 460, 290
        local mx = cx - math.floor(mw * 0.5)
        local my = cy - math.floor(mh * 0.5)
        local title = (s.phase == State.PHASES.MATCH_OVER)
            and string.format("Match Complete - Player %d Wins!", s.winner or 1)
            or string.format("Round %d Scoring Breakdown", s.round_number)

        Graphics.draw_window_frame(mx, my, mw, mh, title)

        local rs = s.last_round_summary
        if rs then
            Graphics.draw_sunken_panel(mx + 16, my + 36, mw - 32, 185, Graphics.COLORS.WIN_SOFT_LIGHT)
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.printf(
                string.format("Round #%d Results", rs.round_number or s.round_number),
                mx + 20,
                my + 44,
                mw - 40,
                "center"
            )

            local p1 = rs.p1
            local p2 = rs.p2
            love.graphics.print(
                string.format("Player 1: %d tricks (%s = +%d pts) + %d Treasure = +%d pts",
                    p1.tricks, p1.tier, p1.trick_points, p1.bonus_points, p1.round_total),
                mx + 28, my + 76
            )
            love.graphics.print(
                string.format("Player 2: %d tricks (%s = +%d pts) + %d Treasure = +%d pts",
                    p2.tricks, p2.tier, p2.trick_points, p2.bonus_points, p2.round_total),
                mx + 28, my + 104
            )

            love.graphics.setColor(0, 0, 0.5, 1)
            love.graphics.print(
                string.format("Cumulative Match Score:   Player 1: %d pts   |   Player 2: %d pts",
                    s.scores[1], s.scores[2]),
                mx + 28, my + 145
            )
            if s.phase == State.PHASES.MATCH_OVER then
                love.graphics.setColor(0.6, 0.05, 0.05, 1)
                love.graphics.printf(
                    string.format("VICTORY: Player %d reached %d points!", s.winner or 1, s.scores[s.winner or 1]),
                    mx + 24, my + 180, mw - 48, "center"
                )
            end
        end

        local modal_btns = self:get_modal_buttons(s, card_view)
        for _, b in ipairs(modal_btns) do
            local hov = point_in_rect(self.mx, self.my, b.x, b.y, b.w, b.h)
            Graphics.draw_button(b.x, b.y, b.w, b.h, b.label, hov, hov and self.mouse_down, b.disabled)
        end
        return
    end

    -- 3. Help / Rules / Scoring Reference Modal
    if self.active_help_modal then
        local mw, mh = 540, 360
        local mx = cx - math.floor(mw * 0.5)
        local my = cy - math.floor(mh * 0.5)
        local title = "The Fox in the Forest - Reference Manual"
        Graphics.draw_window_frame(mx, my, mw, mh, title)
        Graphics.draw_sunken_panel(mx + 14, my + 32, mw - 28, mh - 82, Graphics.COLORS.CARD_FACE)

        love.graphics.setColor(0, 0, 0, 1)
        if self.active_help_modal == "rules" then
            local lines = {
                "CORE TRICK-TAKING RULES (33 Cards: Bells, Keys, Moons 1-11):",
                "• Deal 13 cards each; flip top of remaining 7-card stock as Decree (Trump).",
                "• Follower must follow led suit if able; otherwise may play any card.",
                "",
                "ODD-RANK SPECIAL ABILITIES:",
                "• 1 (Swan): If you play a 1 and lose the trick, you lead the next trick.",
                "• 3 (Fox): When played, you may swap 1 hand card with the Decree card.",
                "• 5 (Woodcutter): Draw top card of stock, then bury 1 hand card at bottom.",
                "• 7 (Treasure): Winner of the trick gains +1 bonus point per 7 in the trick.",
                "• 9 (Witch): Treated as trump suit if ONLY ONE 9 is in the trick.",
                "• 11 (Monarch): When led, follower must play 1 or highest card of that suit.",
            }
            for i = 1, #lines do
                love.graphics.print(lines[i], mx + 24, my + 40 + (i - 1) * 22)
            end
        elseif self.active_help_modal == "scoring" then
            local lines = {
                "END-OF-ROUND SCORING TABLE (Don't Be Too Greedy!):",
                "",
                "• 0 - 3 Tricks Won  -->  6 Points (HUMBLE)",
                "• 4 Tricks Won      -->  1 Point  (MODEST)",
                "• 5 Tricks Won      -->  2 Points (CLEVER)",
                "• 6 Tricks Won      -->  3 Points (SLY)",
                "• 7 - 9 Tricks Won  -->  6 Points (VICTORIOUS)",
                "• 10 - 13 Tricks    -->  0 Points (GREEDY - Punished!)",
                "",
                "• Plus +1 bonus point per 7 (Treasure) won in tricks.",
                "• First player to reach Target Score (21 pts default) wins the match!",
            }
            for i = 1, #lines do
                love.graphics.print(lines[i], mx + 24, my + 40 + (i - 1) * 22)
            end
        else
            local lines = {
                "THE FOX IN THE FOREST - Windows 95 Retro Edition",
                "",
                "• Built with LÖVE2D and a 100% deterministic headless Lua core engine.",
                "• Zero external assets: procedural pixel-art & vector Bells, Keys, Moons.",
                "• Supports 1 vs. AI (Heuristic Trick-Bracket Evaluator) & 1v1 Hotseat.",
                "• Drag-and-drop or click cards to play; use Sort buttons to organize hand.",
                "• See manual.html in the project root for the full 1990s instruction booklet.",
            }
            for i = 1, #lines do
                love.graphics.print(lines[i], mx + 24, my + 45 + (i - 1) * 24)
            end
        end

        local modal_btns = self:get_modal_buttons(s, card_view)
        for _, b in ipairs(modal_btns) do
            local hov = point_in_rect(self.mx, self.my, b.x, b.y, b.w, b.h)
            Graphics.draw_button(b.x, b.y, b.w, b.h, b.label, hov, hov and self.mouse_down, b.disabled)
        end
    end
end

function RetroGUI:draw_menus_and_chrome(s, card_view)
    -- 1. Draw Scoreboard Panel
    self:draw_scoreboard(s)

    -- 2. Draw Persistent Toolbar Buttons (Sort by Suit, Sort by Value, Undo, Rules)
    for _, b in pairs(self.buttons) do
        local hov = point_in_rect(self.mx, self.my, b.x, b.y, b.w, b.h)
        Graphics.draw_button(b.x, b.y, b.w, b.h, b.label, hov, hov and self.mouse_down, false)
    end

    -- 3. Draw Bottom Sunken Status Bar
    local sb_y = self.win_h - 26
    Graphics.draw_raised_panel(0, sb_y, self.win_w, 26, Graphics.COLORS.WIN_GRAY)
    Graphics.draw_sunken_panel(4, sb_y + 3, self.win_w - 190, 20, Graphics.COLORS.WIN_SOFT_LIGHT)
    Graphics.draw_sunken_panel(self.win_w - 182, sb_y + 3, 178, 20, Graphics.COLORS.WIN_SOFT_LIGHT)

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.print(s.status_message or "Ready.", 10, sb_y + 6)
    love.graphics.printf(
        string.format("Phase: %s", s.phase),
        self.win_w - 178,
        sb_y + 6,
        170,
        "center"
    )

    -- 4. Draw Ability Banner (Fox / Woodcutter) or Blocking Modals
    self:draw_ability_banner(s, card_view)
    self:draw_blocking_modals(s, card_view)

    -- 5. Draw Top Win95 Menu Bar & Open Dropdown Menu on Top
    Graphics.draw_raised_panel(0, 0, self.win_w, 24, Graphics.COLORS.WIN_GRAY)
    for _, m in ipairs(self.menus) do
        local is_open = (self.active_menu == m.id)
        local is_hov = point_in_rect(self.mx, self.my, m.x, 2, m.w, 20)
        if is_open then
            Graphics.draw_sunken_panel(m.x, 2, m.w, 20, Graphics.COLORS.WIN_SOFT_LIGHT)
        elseif is_hov then
            Graphics.draw_raised_panel(m.x, 2, m.w, 20, Graphics.COLORS.WIN_SOFT_LIGHT)
        end
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.printf(m.label, m.x, 5, m.w, "center")

        if is_open then
            local drop_x = m.x
            local drop_y = 24
            local drop_w = 210
            local item_h = 24
            local drop_h = #m.items * item_h + 4
            Graphics.draw_raised_panel(drop_x, drop_y, drop_w, drop_h, Graphics.COLORS.WIN_GRAY)
            for idx, item in ipairs(m.items) do
                local iy = drop_y + 2 + (idx - 1) * item_h
                local item_hov = point_in_rect(self.mx, self.my, drop_x + 2, iy, drop_w - 4, item_h)
                if item_hov then
                    love.graphics.setColor(Graphics.COLORS.WIN_NAVY)
                    love.graphics.rectangle("fill", drop_x + 2, iy, drop_w - 4, item_h)
                    love.graphics.setColor(1, 1, 1, 1)
                else
                    love.graphics.setColor(0, 0, 0, 1)
                end
                love.graphics.print(item.label, drop_x + 10, iy + 5)
            end
        end
    end
end

return RetroGUI
