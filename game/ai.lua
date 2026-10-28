-- game/ai.lua
-- Deterministic heuristic rule-based AI for "The Fox in the Forest"

local Deck  = require("game.deck")
local Rules = require("game.rules")
local State = require("game.state")

local AI = {}

-- Evaluates hand strength and current trick count to determine if AI wants to win or duck tricks.
-- Returns "WIN" or "LOSE"
function AI.evaluate_strategy(s, player_idx)
    local my_tricks = s.tricks_won[player_idx]
    local hand = s.hands[player_idx]
    local remaining = #hand
    local decree_suit = s.decree and s.decree.suit or "Bells"

    -- Critical rule: 10+ tricks = 0 points (Greedy). If at 8 or 9 tricks, strongly prefer ducking!
    if my_tricks >= 9 then
        return "LOSE"
    end
    if my_tricks == 8 and remaining > 2 then
        return "LOSE"
    end

    -- Count high cards and trumps in hand
    local strong_count = 0
    for i = 1, remaining do
        local c = hand[i]
        if c.suit == decree_suit and c.rank >= 6 then
            strong_count = strong_count + 1.2
        elseif c.suit == decree_suit then
            strong_count = strong_count + 0.6
        elseif c.rank >= 9 then
            strong_count = strong_count + 0.9
        elseif c.rank >= 7 then
            strong_count = strong_count + 0.4
        end
    end

    local projected_tricks = my_tricks + strong_count

    -- If early/mid round and projected tricks is <= 3.2 and current tricks <= 2, aim for Humble (0-3 tricks = 6 pts)
    if my_tricks <= 2 and projected_tricks <= 3.2 then
        return "LOSE"
    end

    -- If impossible to reach 7 tricks (even winning all remaining), stay <= 3 if possible
    if my_tricks <= 3 and (my_tricks + remaining) < 7 then
        return "LOSE"
    end

    return "WIN"
end

local function choose_lead_card(s, player_idx, strategy)
    local hand = s.hands[player_idx]
    local decree_suit = s.decree.suit
    local best_idx = 1
    local best_score = -999999

    for i = 1, #hand do
        local c = hand[i]
        local score = 0
        local is_trump = (c.suit == decree_suit)

        if strategy == "LOSE" then
            -- Prefer leading low non-trump cards to lose the trick safely
            score = (12 - c.rank) * 10
            if is_trump then
                score = score - 40
            end
            if c.rank == 7 then
                -- Avoid gifting 7 (Treasure) to opponent when trying to lose, unless forced
                score = score - 60
            elseif c.rank == 1 then
                -- Leading a 1 loses the trick and keeps the lead for controlled ducking
                score = score + 15
            elseif c.rank == 3 or c.rank == 5 then
                -- Fox and Woodcutter help sculpt a Humble hand
                score = score + 25
            end
        else
            -- Strategy == "WIN"
            if c.rank == 11 and not is_trump then
                -- Leading off-suit Monarch (11) forces opponent's 1 or highest card
                score = 85
            elseif c.rank == 3 or c.rank == 5 then
                -- Playing Fox or Woodcutter early improves hand quality
                score = 70 - c.rank
            elseif not is_trump and c.rank >= 8 and c.rank ~= 9 then
                score = 60 + c.rank
            elseif is_trump and c.rank >= 7 and c.rank ~= 9 then
                score = 50 + c.rank
            elseif c.rank == 9 then
                -- Conserve Witch (9) for following unless few cards remain
                score = 20
            elseif c.rank == 7 then
                -- Only lead 7 if likely to win or trump
                score = is_trump and 65 or 15
            else
                score = 35 - c.rank
            end
        end

        if score > best_score then
            best_score = score
            best_idx = i
        end
    end

    return {
        type = "PLAY_CARD",
        player = player_idx,
        hand_index = best_idx,
        card_id = hand[best_idx].id,
    }
end

local function choose_follow_card(s, player_idx, strategy)
    local hand = s.hands[player_idx]
    local lead_card = s.trick.lead_card
    local lead_player = s.trick.lead_player
    local decree_suit = s.decree.suit
    local legal_indices = Rules.get_legal_indices(hand, lead_card)

    local best_idx = legal_indices[1] or 1
    local best_score = -999999

    for k = 1, #legal_indices do
        local idx = legal_indices[k]
        local c = hand[idx]
        local outcome = Rules.resolve_trick(lead_card, c, lead_player, decree_suit)
        local i_win = (outcome.winner == player_idx)
        local is_trump = (c.suit == decree_suit) or (c.rank == 9 and lead_card.rank ~= 9)
        local score = 0

        if strategy == "LOSE" then
            if not i_win then
                -- Great! We lose the trick. Shed our highest safe card so we don't win later!
                score = 100 + c.rank * 8
                if c.rank == 7 then
                    -- Do not give opponent +1 bonus point if avoidable
                    score = score - 90
                end
                if is_trump then
                    -- Shedding a high trump safely under a higher card is huge for Humble/avoid-Greedy
                    score = score + 25
                end
                if c.rank == 1 then
                    -- Losing with Swan forces us to lead next, slightly less desirable than shedding a 10
                    score = score - 10
                end
            else
                -- Forced to win despite wanting to lose: shed highest card to minimize future wins
                score = -100 + c.rank * 5
                if c.rank == 7 or lead_card.rank == 7 then
                    score = score + 20
                end
            end
        else
            -- Strategy == "WIN"
            if i_win then
                -- Win as cheaply as possible
                score = 100 - c.rank * 4
                if outcome.bonus_points > 0 then
                    -- Winning a trick with one or two 7s (Treasure) is high priority!
                    score = score + outcome.bonus_points * 45
                end
                if is_trump and lead_card.suit ~= decree_suit then
                    -- Used trump to ruff: slight penalty so we prefer winning in-suit if possible
                    score = score - 12
                end
                if c.rank == 9 then
                    -- Save Witch (9) if another card can also win
                    score = score - 18
                end
            else
                -- Cannot win with this card: dump lowest useless card or play Swan (1) to take lead
                score = 20 - c.rank * 5
                if c.rank == 1 then
                    -- Losing with 1 (Swan) steals the lead for next trick!
                    score = score + 45
                end
                if c.rank == 7 then
                    -- Avoid giving opponent a free Treasure point!
                    score = score - 85
                end
                if is_trump then
                    score = score - 25
                end
            end
        end

        if score > best_score then
            best_score = score
            best_idx = idx
        end
    end

    return {
        type = "PLAY_CARD",
        player = player_idx,
        hand_index = best_idx,
        card_id = hand[best_idx].id,
    }
end

local function choose_fox_action(s, player_idx, strategy)
    local hand = s.hands[player_idx]
    local decree = s.decree
    if not decree or #hand == 0 then
        return { type = "FOX_PASS", player = player_idx }
    end

    -- Count suit distribution in hand
    local suit_counts = { Bells = 0, Keys = 0, Moons = 0 }
    for i = 1, #hand do
        local st = hand[i].suit
        suit_counts[st] = (suit_counts[st] or 0) + 1
    end

    if strategy == "LOSE" then
        -- If decree is a low card (<= 4), swap our highest dangerous card onto the Decree
        if decree.rank <= 4 then
            local highest_idx = nil
            local highest_rank = 6
            for i = 1, #hand do
                if hand[i].rank > highest_rank then
                    highest_rank = hand[i].rank
                    highest_idx = i
                end
            end
            if highest_idx then
                return {
                    type = "FOX_SWAP",
                    player = player_idx,
                    hand_index = highest_idx,
                    card_id = hand[highest_idx].id,
                }
            end
        end
        return { type = "FOX_PASS", player = player_idx }
    else
        -- Strategy == "WIN": if Decree is a 7 (Treasure) or high card (>= 8) and we can swap a low card of our longest suit
        local best_suit = decree.suit
        local max_cnt = suit_counts[best_suit] or 0
        for _, st in ipairs(Deck.SUITS) do
            if suit_counts[st] > max_cnt then
                max_cnt = suit_counts[st]
                best_suit = st
            end
        end

        if best_suit ~= decree.suit and max_cnt >= 4 then
            -- Find lowest card in best_suit to put onto Decree so best_suit becomes trump
            local low_idx = nil
            local low_rank = 99
            for i = 1, #hand do
                if hand[i].suit == best_suit and hand[i].rank < low_rank and hand[i].rank ~= 7 and hand[i].rank ~= 9 then
                    low_rank = hand[i].rank
                    low_idx = i
                end
            end
            if low_idx and low_rank <= 6 then
                return {
                    type = "FOX_SWAP",
                    player = player_idx,
                    hand_index = low_idx,
                    card_id = hand[low_idx].id,
                }
            end
        end

        -- Or if Decree is same suit and higher rank than a low card of that suit in hand
        if decree.rank >= 8 or decree.rank == 7 then
            for i = 1, #hand do
                if hand[i].suit == decree.suit and hand[i].rank <= 4 and hand[i].rank ~= 1 then
                    return {
                        type = "FOX_SWAP",
                        player = player_idx,
                        hand_index = i,
                        card_id = hand[i].id,
                    }
                end
            end
        end

        return { type = "FOX_PASS", player = player_idx }
    end
end

local function choose_woodcutter_bury(s, player_idx, strategy)
    local hand = s.hands[player_idx]
    local decree_suit = s.decree.suit
    local best_idx = 1
    local best_bury_score = -999999

    for i = 1, #hand do
        local c = hand[i]
        local is_trump = (c.suit == decree_suit)
        local score = 0

        if strategy == "LOSE" then
            -- Bury high cards or dangerous 7s so we don't win unwanted tricks or feed opponent 7s
            score = c.rank * 10
            if is_trump then
                score = score + 25
            end
            if c.rank == 7 then
                score = score + 30
            elseif c.rank == 1 then
                score = score - 40
            end
        else
            -- Strategy == "WIN": bury lowest off-suit non-ability card (2, 4, 6)
            score = (12 - c.rank) * 10
            if is_trump then
                score = score - 50
            end
            if c.rank == 1 or c.rank == 7 or c.rank == 9 or c.rank == 11 then
                score = score - 40
            end
        end

        if score > best_bury_score then
            best_bury_score = score
            best_idx = i
        end
    end

    return {
        type = "WOODCUTTER_BURY",
        player = player_idx,
        hand_index = best_idx,
        card_id = hand[best_idx].id,
    }
end

function AI.choose_action(s, player_idx)
    local p = player_idx or s.active_player
    local strategy = AI.evaluate_strategy(s, p)

    if s.phase == State.PHASES.WAIT_LEAD then
        return choose_lead_card(s, p, strategy)
    elseif s.phase == State.PHASES.WAIT_FOLLOW then
        return choose_follow_card(s, p, strategy)
    elseif s.phase == State.PHASES.PENDING_FOX_SWAP then
        return choose_fox_action(s, p, strategy)
    elseif s.phase == State.PHASES.PENDING_WOODCUTTER_BURY then
        return choose_woodcutter_bury(s, p, strategy)
    elseif s.phase == State.PHASES.TRICK_RESOLVE then
        return { type = "RESOLVE_TRICK" }
    elseif s.phase == State.PHASES.ROUND_OVER then
        return { type = "NEXT_ROUND" }
    end
    return nil
end

return AI
