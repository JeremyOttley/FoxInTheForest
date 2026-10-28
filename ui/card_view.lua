-- ui/card_view.lua
-- Card dimensions, layout calculation, hitboxes, drag-and-drop physics, and bounce-back animations

local Rules    = require("game.rules")
local State    = require("game.state")
local Graphics = require("ui.graphics")

local CardView = {}
CardView.__index = CardView

CardView.CARD_W = 80
CardView.CARD_H = 116

function CardView.new()
    local self = setmetatable({
        win_w = 1024,
        win_h = 768,
        hovered_index = nil,
        selected_index = nil,
        dragging = nil, -- { index, card_id, x, y, off_x, off_y, start_x, start_y, distance }
        bounce_anims = {}, -- { [card_id] = { x, y, start_x, start_y, target_x, target_y, elapsed, duration } }
        last_click_time = 0,
        last_click_index = nil,
        hand_slots = {},
        top_hand_slots = {},
        zones = {},
    }, CardView)
    self:update_layout(1024, 768)
    return self
end

function CardView:update_layout(w, h)
    self.win_w = w
    self.win_h = h

    local cw = CardView.CARD_W
    local ch = CardView.CARD_H
    local center_x = math.floor(w * 0.5)
    local center_y = math.floor(h * 0.46)

    self.zones = {
        -- Stock and Decree on the left of the central play table
        stock = {
            x = center_x - 290,
            y = center_y - math.floor(ch * 0.5),
            w = cw,
            h = ch,
        },
        decree = {
            x = center_x - 185,
            y = center_y - math.floor(ch * 0.5),
            w = cw,
            h = ch,
        },
        -- Central Trick Well (Lead & Follow slots)
        lead_slot = {
            x = center_x - 25,
            y = center_y - math.floor(ch * 0.5),
            w = cw,
            h = ch,
        },
        follow_slot = {
            x = center_x + 80,
            y = center_y - math.floor(ch * 0.5),
            w = cw,
            h = ch,
        },
        -- Generous drop target bounding box around the central trick area
        drop_well = {
            x = center_x - 55,
            y = center_y - math.floor(ch * 0.5) - 28,
            w = 245,
            h = ch + 56,
        },
    }
end

function CardView:compute_hand_slots(count, is_bottom)
    local slots = {}
    if count <= 0 then
        return slots
    end
    local cw = CardView.CARD_W
    local ch = CardView.CARD_H
    local max_span = math.min(self.win_w - 260, 740)
    local step = cw + 6
    if count > 1 then
        step = math.min(cw + 6, math.floor((max_span - cw) / (count - 1)))
    end
    local total_w = cw + step * (count - 1)
    local start_x = math.floor((self.win_w - total_w) * 0.5)
    local base_y = is_bottom and (self.win_h - ch - 46) or 46

    for i = 1, count do
        slots[i] = {
            x = start_x + (i - 1) * step,
            y = base_y,
            w = cw,
            h = ch,
        }
    end
    return slots
end

function CardView:get_view_player(s)
    if s.mode == State.MODES.PVE then
        return 1
    end
    return s.active_player
end

function CardView:get_legal_map_for_view(s)
    local view_p = self:get_view_player(s)
    local hand = s.hands[view_p] or {}

    if s.hotseat_hidden then
        return {}
    end

    -- During ability modals, all cards in active player's hand are selectable for swap/bury
    if (s.phase == State.PHASES.PENDING_FOX_SWAP or s.phase == State.PHASES.PENDING_WOODCUTTER_BURY)
        and s.active_player == view_p then
        local all_map = {}
        for i = 1, #hand do
            all_map[i] = true
        end
        return all_map
    end

    if (s.phase == State.PHASES.WAIT_LEAD or s.phase == State.PHASES.WAIT_FOLLOW)
        and s.active_player == view_p then
        local lead_c = (s.phase == State.PHASES.WAIT_FOLLOW) and s.trick.lead_card or nil
        local _, map = Rules.get_legal_indices(hand, lead_c)
        return map
    end

    return {}
end

function CardView:is_in_drop_zone(x, y)
    local dz = self.zones.drop_well
    return x >= dz.x and x <= (dz.x + dz.w) and y >= dz.y and y <= (dz.y + dz.h)
end

function CardView:get_card_index_at(s, mx, my)
    if s.hotseat_hidden then
        return nil
    end
    local view_p = self:get_view_player(s)
    local hand = s.hands[view_p] or {}
    local slots = self:compute_hand_slots(#hand, true)
    self.hand_slots = slots

    -- Iterate backward from rightmost (topmost) card to leftmost
    for i = #slots, 1, -1 do
        local sl = slots[i]
        local top_y = (self.hovered_index == i or self.selected_index == i) and (sl.y - 12) or sl.y
        if mx >= sl.x and mx <= (sl.x + sl.w) and my >= top_y and my <= (sl.y + sl.h) then
            return i
        end
    end
    return nil
end

function CardView:trigger_bounce(card_id, from_x, from_y, to_x, to_y)
    if not card_id then
        return
    end
    self.bounce_anims[card_id] = {
        start_x = from_x,
        start_y = from_y,
        target_x = to_x,
        target_y = to_y,
        x = from_x,
        y = from_y,
        elapsed = 0,
        duration = 0.22,
    }
end

function CardView:update(dt, s, mx, my)
    -- Update bounce-back animations
    for id, anim in pairs(self.bounce_anims) do
        anim.elapsed = anim.elapsed + dt
        if anim.elapsed >= anim.duration then
            self.bounce_anims[id] = nil
        else
            local t = anim.elapsed / anim.duration
            -- Smooth ease-out cubic curve
            local ease = 1 - ((1 - t) ^ 3)
            anim.x = anim.start_x + (anim.target_x - anim.start_x) * ease
            anim.y = anim.start_y + (anim.target_y - anim.start_y) * ease
        end
    end

    if self.dragging then
        self.hovered_index = self.dragging.index
    elseif mx and my then
        self.hovered_index = self:get_card_index_at(s, mx, my)
    end
end

function CardView:mousepressed(s, mx, my, button)
    if button ~= 1 or s.hotseat_hidden then
        return nil
    end
    local view_p = self:get_view_player(s)
    if s.active_player ~= view_p then
        return nil
    end

    local idx = self:get_card_index_at(s, mx, my)
    if not idx then
        self.selected_index = nil
        return nil
    end

    local hand = s.hands[view_p]
    local card = hand[idx]
    local slot = self.hand_slots[idx]
    if not card or not slot then
        return nil
    end

    self.dragging = {
        index = idx,
        card_id = card.id,
        x = slot.x,
        y = slot.y - 10,
        off_x = mx - slot.x,
        off_y = my - (slot.y - 10),
        start_x = slot.x,
        start_y = slot.y,
        distance = 0,
    }
    return nil
end

function CardView:mousemoved(s, mx, my, dx, dy)
    if self.dragging then
        self.dragging.x = mx - self.dragging.off_x
        self.dragging.y = my - self.dragging.off_y
        local dist = math.sqrt((mx - (self.dragging.start_x + self.dragging.off_x)) ^ 2
                             + (my - (self.dragging.start_y + self.dragging.off_y)) ^ 2)
        if dist > self.dragging.distance then
            self.dragging.distance = dist
        end
    else
        self.hovered_index = self:get_card_index_at(s, mx, my)
    end
end

-- Returns an action table if a card play or modal selection was completed, or nil + optional status feedback
function CardView:mousereleased(s, mx, my, button, now_time)
    if button ~= 1 or not self.dragging then
        return nil
    end

    local drag = self.dragging
    self.dragging = nil

    local view_p = self:get_view_player(s)
    local hand = s.hands[view_p] or {}
    local idx = drag.index
    local card = hand[idx]
    if not card then
        return nil
    end

    local legal_map = self:get_legal_map_for_view(s)
    local is_legal = (legal_map[idx] == true)
    local was_dragged = (drag.distance > 14)
    local card_center_x = drag.x + CardView.CARD_W * 0.5
    local card_center_y = drag.y + CardView.CARD_H * 0.5
    local in_drop = self:is_in_drop_zone(mx, my) or self:is_in_drop_zone(card_center_x, card_center_y)

    -- In ability modals (Fox Swap or Woodcutter Bury), clicking or dragging a card selects it
    if s.phase == State.PHASES.PENDING_FOX_SWAP or s.phase == State.PHASES.PENDING_WOODCUTTER_BURY then
        self.selected_index = idx
        if was_dragged and in_drop then
            if s.phase == State.PHASES.PENDING_FOX_SWAP then
                return { type = "FOX_SWAP", player = view_p, hand_index = idx, card_id = card.id }
            else
                return { type = "WOODCUTTER_BURY", player = view_p, hand_index = idx, card_id = card.id }
            end
        end
        return nil
    end

    -- Normal trick play (WAIT_LEAD or WAIT_FOLLOW)
    if s.phase == State.PHASES.WAIT_LEAD or s.phase == State.PHASES.WAIT_FOLLOW then
        local t_now = now_time or (love and love.timer and love.timer.getTime() or 0)
        local is_double_click = (not was_dragged)
            and (self.last_click_index == idx)
            and ((t_now - self.last_click_time) < 0.45)

        self.last_click_index = idx
        self.last_click_time = t_now

        -- Attempt play if dropped in play well, or clicked when already selected/double-clicked, or single-click play
        local attempt_play = (was_dragged and in_drop) or (not was_dragged)

        if attempt_play then
            if is_legal then
                self.selected_index = nil
                return {
                    type = "PLAY_CARD",
                    player = view_p,
                    hand_index = idx,
                    card_id = card.id,
                }
            else
                -- Illegal card attempted: bounce back smoothly to hand slot!
                self:trigger_bounce(card.id, drag.x, drag.y, drag.start_x, drag.start_y)
                return nil, "Illegal play! You must follow suit (or obey Monarch 11 rules)."
            end
        else
            -- Released outside drop zone: bounce back smoothly to hand slot
            self:trigger_bounce(card.id, drag.x, drag.y, drag.start_x, drag.start_y)
        end
    end

    return nil
end

function CardView:draw_table_and_hands(s)
    local view_p = self:get_view_player(s)
    local opp_p = (view_p == 1) and 2 or 1
    local my_hand = s.hands[view_p] or {}
    local opp_hand = s.hands[opp_p] or {}
    local legal_map = self:get_legal_map_for_view(s)

    -- 1. Draw Top (Opponent) Face-Down Hand
    local top_slots = self:compute_hand_slots(#opp_hand, false)
    self.top_hand_slots = top_slots
    for i = 1, #top_slots do
        local sl = top_slots[i]
        Graphics.draw_card_back(sl.x, sl.y, sl.w, sl.h)
    end

    -- 2. Draw Central Play Area: Stock, Decree, and Trick Drop Wells
    local z = self.zones

    -- Stock Pile
    Graphics.draw_card_slot(z.stock.x - 4, z.stock.y - 4, z.stock.w + 8, z.stock.h + 8, "EMPTY")
    if #s.stock > 0 then
        local layers = math.min(3, #s.stock)
        for l = 1, layers do
            local off = (l - 1) * 2
            Graphics.draw_card_back(z.stock.x - off, z.stock.y - off, z.stock.w, z.stock.h)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(string.format("Stock (%d)", #s.stock), z.stock.x - 10, z.stock.y - 22, z.stock.w + 20, "center")

    -- Decree Card (Trump Suit)
    Graphics.draw_card_slot(z.decree.x - 4, z.decree.y - 4, z.decree.w + 8, z.decree.h + 8, "DECREE")
    if s.decree then
        Graphics.draw_card_face(s.decree, z.decree.x, z.decree.y, z.decree.w, z.decree.h, { shadow = true })
        love.graphics.setColor(1, 0.92, 0.35, 1)
        love.graphics.printf("DECREE (TRUMP)", z.decree.x - 20, z.decree.y - 22, z.decree.w + 40, "center")
        love.graphics.printf(s.decree.suit, z.decree.x - 10, z.decree.y + z.decree.h + 8, z.decree.w + 20, "center")
    end

    -- Central Trick Drop Zone Frame
    local highlight_drop = (self.dragging ~= nil)
    Graphics.draw_sunken_panel(z.drop_well.x, z.drop_well.y, z.drop_well.w, z.drop_well.h, Graphics.COLORS.FELT_DARK)
    love.graphics.setColor(0.85, 0.95, 0.85, 1)
    love.graphics.printf(
        string.format("TRICK #%d PLAY AREA", s.trick and s.trick.number or 1),
        z.drop_well.x,
        z.drop_well.y + 6,
        z.drop_well.w,
        "center"
    )

    -- Lead & Follow Card Slots
    Graphics.draw_card_slot(z.lead_slot.x, z.lead_slot.y, z.lead_slot.w, z.lead_slot.h, "LEAD", highlight_drop and s.phase == State.PHASES.WAIT_LEAD)
    Graphics.draw_card_slot(z.follow_slot.x, z.follow_slot.y, z.follow_slot.w, z.follow_slot.h, "FOLLOW", highlight_drop and s.phase == State.PHASES.WAIT_FOLLOW)

    if s.trick and s.trick.lead_card then
        Graphics.draw_card_face(s.trick.lead_card, z.lead_slot.x, z.lead_slot.y, z.lead_slot.w, z.lead_slot.h, { shadow = true })
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("P" .. tostring(s.trick.lead_player) .. " Lead", z.lead_slot.x, z.lead_slot.y + z.lead_slot.h + 5, z.lead_slot.w, "center")
    end

    if s.trick and s.trick.follow_card then
        Graphics.draw_card_face(s.trick.follow_card, z.follow_slot.x, z.follow_slot.y, z.follow_slot.w, z.follow_slot.h, { shadow = true })
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("P" .. tostring(s.trick.follow_player) .. " Follow", z.follow_slot.x, z.follow_slot.y + z.follow_slot.h + 5, z.follow_slot.w, "center")
    end

    -- 3. Draw Bottom (Active Human Player) Hand
    local bottom_slots = self:compute_hand_slots(#my_hand, true)
    self.hand_slots = bottom_slots

    if s.hotseat_hidden then
        -- In Hotseat blind transition, render active player's hand face-down
        for i = 1, #bottom_slots do
            local sl = bottom_slots[i]
            Graphics.draw_card_back(sl.x, sl.y, sl.w, sl.h)
        end
        return
    end

    local dragged_idx = self.dragging and self.dragging.index or nil

    for i = 1, #my_hand do
        if i ~= dragged_idx then
            local card = my_hand[i]
            local sl = bottom_slots[i]
            local bounce = self.bounce_anims[card.id]
            local is_hov = (self.hovered_index == i)
            local is_sel = (self.selected_index == i)
            local is_legal = (legal_map[i] == true)
            local show_dim = (s.active_player == view_p)
                and (s.phase == State.PHASES.WAIT_LEAD or s.phase == State.PHASES.WAIT_FOLLOW)
                and (not is_legal)

            local draw_x = bounce and bounce.x or sl.x
            local draw_y = bounce and bounce.y or ((is_hov or is_sel) and (sl.y - 12) or sl.y)

            Graphics.draw_card_face(card, draw_x, draw_y, sl.w, sl.h, {
                is_hovered = is_hov,
                is_selected = is_sel,
                is_dimmed = show_dim,
                shadow = is_hov or is_sel or (bounce ~= nil),
            })
        end
    end

    -- 4. Draw Dragged Card on Top with Drop Shadow
    if self.dragging and my_hand[dragged_idx] then
        local d_card = my_hand[dragged_idx]
        local is_legal = (legal_map[dragged_idx] == true)
        Graphics.draw_card_face(d_card, self.dragging.x, self.dragging.y, CardView.CARD_W, CardView.CARD_H, {
            is_dragging = true,
            is_hovered = true,
            is_dimmed = not is_legal,
        })
    end
end

return CardView
