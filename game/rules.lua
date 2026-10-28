-- game/rules.lua
-- Pure, stateless rule evaluation for "The Fox in the Forest"

local Rules = {}

Rules.SCORING_TABLE = {
    [0]  = { points = 6, label = "Humble" },
    [1]  = { points = 6, label = "Humble" },
    [2]  = { points = 6, label = "Humble" },
    [3]  = { points = 6, label = "Humble" },
    [4]  = { points = 1, label = "Modest" },
    [5]  = { points = 2, label = "Clever" },
    [6]  = { points = 3, label = "Sly" },
    [7]  = { points = 6, label = "Victorious" },
    [8]  = { points = 6, label = "Victorious" },
    [9]  = { points = 6, label = "Victorious" },
    [10] = { points = 0, label = "Greedy" },
    [11] = { points = 0, label = "Greedy" },
    [12] = { points = 0, label = "Greedy" },
    [13] = { points = 0, label = "Greedy" },
}

-- Returns an array of legal 1-based indices into `hand` and a lookup map `{ [idx] = true }`.
function Rules.get_legal_indices(hand, lead_card)
    local indices = {}
    local map = {}
    local n = #hand
    if n == 0 then
        return indices, map
    end

    -- Lead player can play any card in hand
    if not lead_card then
        for i = 1, n do
            indices[i] = i
            map[i] = true
        end
        return indices, map
    end

    local led_suit = lead_card.suit
    local has_led_suit = false
    local max_rank_in_suit = -1

    for i = 1, n do
        local c = hand[i]
        if c.suit == led_suit then
            has_led_suit = true
            if c.rank > max_rank_in_suit then
                max_rank_in_suit = c.rank
            end
        end
    end

    -- If follower has no cards of the led suit, any card is legal
    if not has_led_suit then
        for i = 1, n do
            indices[i] = i
            map[i] = true
        end
        return indices, map
    end

    -- Monarch (11) constraint: follower must play 1 (Swan) of led suit or highest card of led suit
    if lead_card.rank == 11 then
        local count = 0
        for i = 1, n do
            local c = hand[i]
            if c.suit == led_suit and (c.rank == 1 or c.rank == max_rank_in_suit) then
                count = count + 1
                indices[count] = i
                map[i] = true
            end
        end
        return indices, map
    end

    -- Standard suit-following requirement
    local count = 0
    for i = 1, n do
        if hand[i].suit == led_suit then
            count = count + 1
            indices[count] = i
            map[i] = true
        end
    end
    return indices, map
end

function Rules.is_card_legal(hand, card_index, lead_card)
    if not hand or card_index < 1 or card_index > #hand then
        return false
    end
    local _, map = Rules.get_legal_indices(hand, lead_card)
    return map[card_index] == true
end

-- Witch (9) rule: When comparing cards to determine who wins a trick,
-- a 9 is treated as trump if ONLY ONE 9 was played in that trick.
function Rules.effective_suit(card, other_card, decree_suit)
    if not card then
        return nil
    end
    local c1_nine = (card.rank == 9)
    local c2_nine = (other_card and other_card.rank == 9) or false
    if c1_nine and not c2_nine then
        return decree_suit
    end
    return card.suit
end

-- Resolves a completed 2-card trick.
-- Returns table: { winner, loser, next_leader, bonus_points, swan_triggered, witch_triggered, winning_card }
function Rules.resolve_trick(lead_card, follow_card, lead_player, decree_suit)
    assert(lead_card and follow_card, "resolve_trick requires both lead_card and follow_card")
    local follow_player = (lead_player == 1) and 2 or 1

    local eff_lead = Rules.effective_suit(lead_card, follow_card, decree_suit)
    local eff_follow = Rules.effective_suit(follow_card, lead_card, decree_suit)

    local witch_triggered = (lead_card.rank == 9 and follow_card.rank ~= 9)
        or (follow_card.rank == 9 and lead_card.rank ~= 9)

    local lead_is_trump = (eff_lead == decree_suit)
    local follow_is_trump = (eff_follow == decree_suit)

    local follow_wins = false
    if lead_is_trump and follow_is_trump then
        follow_wins = (follow_card.rank > lead_card.rank)
    elseif follow_is_trump and not lead_is_trump then
        follow_wins = true
    elseif lead_is_trump and not follow_is_trump then
        follow_wins = false
    else
        -- Neither card is effective trump; compare against led suit
        if eff_follow == lead_card.suit and follow_card.rank > lead_card.rank then
            follow_wins = true
        else
            follow_wins = false
        end
    end

    local winner = follow_wins and follow_player or lead_player
    local loser = (winner == 1) and 2 or 1
    local winning_card = follow_wins and follow_card or lead_card
    local losing_card = follow_wins and lead_card or follow_card

    -- Swan (1) rule: if you lose the trick with a 1, you lead the next trick
    local swan_triggered = (losing_card.rank == 1)
    local next_leader = swan_triggered and loser or winner

    -- Treasure (7) rule: winner gains +1 point per 7 in the trick
    local bonus_points = 0
    if lead_card.rank == 7 then
        bonus_points = bonus_points + 1
    end
    if follow_card.rank == 7 then
        bonus_points = bonus_points + 1
    end

    return {
        winner = winner,
        loser = loser,
        next_leader = next_leader,
        bonus_points = bonus_points,
        swan_triggered = swan_triggered,
        witch_triggered = witch_triggered,
        winning_card = winning_card,
    }
end

function Rules.trick_points(tricks_won)
    local entry = Rules.SCORING_TABLE[tricks_won]
    if not entry then
        return 0, "Greedy"
    end
    return entry.points, entry.label
end

function Rules.score_round(tricks_p1, tricks_p2, bonus_p1, bonus_p2)
    local b1 = bonus_p1 or 0
    local b2 = bonus_p2 or 0
    local t1_pts, t1_label = Rules.trick_points(tricks_p1)
    local t2_pts, t2_label = Rules.trick_points(tricks_p2)
    return {
        p1 = {
            tricks = tricks_p1,
            trick_points = t1_pts,
            bonus_points = b1,
            round_total = t1_pts + b1,
            tier = t1_label,
        },
        p2 = {
            tricks = tricks_p2,
            trick_points = t2_pts,
            bonus_points = b2,
            round_total = t2_pts + b2,
            tier = t2_label,
        },
    }
end

return Rules
