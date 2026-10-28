-- game/state.lua
-- Deterministic headless state machine, deep cloning, undo/replay history, and JSON serialization
-- Zero dependencies on love.* or external libraries.

local PRNG  = require("game.prng")
local Deck  = require("game.deck")
local Rules = require("game.rules")

local State = {}

State.PHASES = {
    WAIT_LEAD               = "WAIT_LEAD",
    WAIT_FOLLOW             = "WAIT_FOLLOW",
    PENDING_FOX_SWAP        = "PENDING_FOX_SWAP",
    PENDING_WOODCUTTER_BURY = "PENDING_WOODCUTTER_BURY",
    TRICK_RESOLVE           = "TRICK_RESOLVE",
    ROUND_OVER              = "ROUND_OVER",
    MATCH_OVER              = "MATCH_OVER",
}

State.MODES = {
    PVE     = "1vAI",
    HOTSEAT = "1v1",
}

local function clone_trick(t)
    if not t then
        return nil
    end
    return {
        number = t.number,
        lead_player = t.lead_player,
        follow_player = t.follow_player,
        lead_card = Deck.clone_card(t.lead_card),
        follow_card = Deck.clone_card(t.follow_card),
        pending_after_ability = t.pending_after_ability,
        last_result = t.last_result and {
            winner = t.last_result.winner,
            loser = t.last_result.loser,
            next_leader = t.last_result.next_leader,
            bonus_points = t.last_result.bonus_points,
            swan_triggered = t.last_result.swan_triggered,
            witch_triggered = t.last_result.witch_triggered,
            winning_card = Deck.clone_card(t.last_result.winning_card),
            lead_card = Deck.clone_card(t.last_result.lead_card),
            follow_card = Deck.clone_card(t.last_result.follow_card),
        } or nil,
    }
end

local function clone_round_summary(rs)
    if not rs then
        return nil
    end
    return {
        round_number = rs.round_number,
        p1 = {
            tricks = rs.p1.tricks,
            trick_points = rs.p1.trick_points,
            bonus_points = rs.p1.bonus_points,
            round_total = rs.p1.round_total,
            tier = rs.p1.tier,
        },
        p2 = {
            tricks = rs.p2.tricks,
            trick_points = rs.p2.trick_points,
            bonus_points = rs.p2.bonus_points,
            round_total = rs.p2.round_total,
            tier = rs.p2.tier,
        },
    }
end

local function clone_action(a)
    if type(a) ~= "table" then
        return a
    end
    local copy = {}
    for k, v in pairs(a) do
        copy[k] = v
    end
    return copy
end

-- Deep-copies match state without copying undo_stack recursively
function State.clone(s, include_logs)
    local copy = {
        seed = s.seed,
        mode = s.mode,
        target_score = s.target_score,
        round_number = s.round_number,
        dealer = s.dealer,
        phase = s.phase,
        active_player = s.active_player,
        hotseat_hidden = s.hotseat_hidden,
        winner = s.winner,
        status_message = s.status_message,
        last_drawn_card = Deck.clone_card(s.last_drawn_card),
        decree = Deck.clone_card(s.decree),
        stock = Deck.clone_cards(s.stock),
        hands = {
            [1] = Deck.clone_cards(s.hands[1]),
            [2] = Deck.clone_cards(s.hands[2]),
        },
        tricks_won = {
            [1] = s.tricks_won[1],
            [2] = s.tricks_won[2],
        },
        round_bonus = {
            [1] = s.round_bonus[1],
            [2] = s.round_bonus[2],
        },
        scores = {
            [1] = s.scores[1],
            [2] = s.scores[2],
        },
        trick = clone_trick(s.trick),
        last_round_summary = clone_round_summary(s.last_round_summary),
        prng = s.prng:clone(),
        action_log = {},
        undo_stack = {},
    }
    if include_logs and s.action_log then
        for i = 1, #s.action_log do
            copy.action_log[i] = clone_action(s.action_log[i])
        end
    end
    return copy
end

function State.start_round(s)
    local deck = Deck.create_deck()
    Deck.shuffle(deck, s.prng)

    local hand1 = {}
    local hand2 = {}
    local stock = {}

    -- Deal 13 cards to each player
    for i = 1, 13 do
        hand1[i] = deck[i]
        hand2[i] = deck[i + 13]
    end
    -- Remaining 7 cards form the draw pile (stock)
    for i = 27, 33 do
        stock[#stock + 1] = deck[i]
    end

    -- Top card of draw pile is flipped face-up as the Decree card (6 remain face-down in stock)
    local decree = table.remove(stock, 1)

    Deck.sort_by_suit(hand1)
    Deck.sort_by_suit(hand2)

    s.hands = { [1] = hand1, [2] = hand2 }
    s.stock = stock
    s.decree = decree
    s.tricks_won = { [1] = 0, [2] = 0 }
    s.round_bonus = { [1] = 0, [2] = 0 }
    s.last_drawn_card = nil

    local first_leader = (s.dealer == 1) and 2 or 1
    local first_follower = (first_leader == 1) and 2 or 1

    s.trick = {
        number = 1,
        lead_player = first_leader,
        follow_player = first_follower,
        lead_card = nil,
        follow_card = nil,
        pending_after_ability = nil,
        last_result = nil,
    }

    s.phase = State.PHASES.WAIT_LEAD
    s.active_player = first_leader
    s.hotseat_hidden = (s.mode == State.MODES.HOTSEAT)
    s.status_message = string.format(
        "Round %d started. Decree is %d of %s (%s trump). Player %d leads.",
        s.round_number,
        decree.rank,
        decree.suit,
        decree.suit,
        first_leader
    )
    return s
end

function State.new_match(config)
    local cfg = config or {}
    local seed = tonumber(cfg.seed) or 424242
    local mode = cfg.mode or State.MODES.PVE
    local target_score = tonumber(cfg.target_score) or 21
    local prng = PRNG.new(seed)

    local s = {
        seed = seed,
        mode = mode,
        target_score = target_score,
        round_number = 1,
        dealer = 2, -- So Player 1 leads Round 1
        phase = State.PHASES.WAIT_LEAD,
        active_player = 1,
        hotseat_hidden = false,
        winner = nil,
        status_message = "",
        last_drawn_card = nil,
        decree = nil,
        stock = {},
        hands = { [1] = {}, [2] = {} },
        tricks_won = { [1] = 0, [2] = 0 },
        round_bonus = { [1] = 0, [2] = 0 },
        scores = { [1] = 0, [2] = 0 },
        trick = nil,
        last_round_summary = nil,
        prng = prng,
        action_log = {},
        undo_stack = {},
    }

    State.start_round(s)
    return s
end

local function push_undo_snapshot(s, opts)
    if opts and opts.no_history then
        return
    end
    local snap = State.clone(s, true)
    s.undo_stack[#s.undo_stack + 1] = snap
    -- Cap undo stack at 64 snapshots to bound memory
    if #s.undo_stack > 64 then
        table.remove(s.undo_stack, 1)
    end
end

local function transition_after_card_play(s, played_card, next_phase_after_ability)
    -- Fox (3): prompt active player to swap a card from hand with Decree or pass
    if played_card.rank == 3 and #s.hands[s.active_player] > 0 and s.decree then
        s.trick.pending_after_ability = next_phase_after_ability
        s.phase = State.PHASES.PENDING_FOX_SWAP
        s.status_message = string.format(
            "Player %d played 3 (Fox): Choose a card from hand to swap with the Decree card, or Pass.",
            s.active_player
        )
        return
    end

    -- Woodcutter (5): draw top card of stock (if available), then bury 1 card to bottom of stock
    if played_card.rank == 5 then
        if #s.stock > 0 then
            local drawn = table.remove(s.stock, 1)
            local hand = s.hands[s.active_player]
            hand[#hand + 1] = drawn
            s.last_drawn_card = Deck.clone_card(drawn)
            s.trick.pending_after_ability = next_phase_after_ability
            s.phase = State.PHASES.PENDING_WOODCUTTER_BURY
            s.status_message = string.format(
                "Player %d played 5 (Woodcutter) and drew a card: Choose 1 card from hand to place at the bottom of the deck.",
                s.active_player
            )
            return
        elseif #s.hands[s.active_player] > 0 then
            -- Even if stock was empty (rare), allow/require burying or advance cleanly
            s.last_drawn_card = nil
        end
    end

    -- No pending modal ability: advance directly to next phase
    if next_phase_after_ability == State.PHASES.WAIT_FOLLOW then
        s.phase = State.PHASES.WAIT_FOLLOW
        local prev_player = s.active_player
        s.active_player = s.trick.follow_player
        if s.mode == State.MODES.HOTSEAT and prev_player ~= s.active_player then
            s.hotseat_hidden = true
        end
        if played_card.rank == 11 then
            s.status_message = string.format(
                "Player %d led 11 (Monarch) of %s! Player %d must follow with 1 or highest %s.",
                prev_player,
                played_card.suit,
                s.active_player,
                played_card.suit
            )
        else
            s.status_message = string.format(
                "Player %d led %d of %s. Player %d to follow.",
                prev_player,
                played_card.rank,
                played_card.suit,
                s.active_player
            )
        end
    else
        s.phase = State.PHASES.TRICK_RESOLVE
        s.status_message = string.format(
            "Player %d followed with %d of %s. Resolving trick #%d...",
            s.active_player,
            played_card.rank,
            played_card.suit,
            s.trick.number
        )
    end
end

local function finish_pending_ability(s)
    local next_phase = s.trick.pending_after_ability or State.PHASES.WAIT_FOLLOW
    s.trick.pending_after_ability = nil
    s.last_drawn_card = nil

    if next_phase == State.PHASES.WAIT_FOLLOW then
        local prev_player = s.active_player
        s.phase = State.PHASES.WAIT_FOLLOW
        s.active_player = s.trick.follow_player
        if s.mode == State.MODES.HOTSEAT and prev_player ~= s.active_player then
            s.hotseat_hidden = true
        end
        local lead_c = s.trick.lead_card
        s.status_message = string.format(
            "Ability resolved. Lead is %d of %s (Trump: %s). Player %d to follow.",
            lead_c.rank,
            lead_c.suit,
            s.decree.suit,
            s.active_player
        )
    else
        s.phase = State.PHASES.TRICK_RESOLVE
        s.status_message = string.format("Ability resolved. Ready to resolve trick #%d.", s.trick.number)
    end
end

local function resolve_card_index(hand, action)
    if action.hand_index and hand[action.hand_index] then
        return action.hand_index
    end
    if action.card_id then
        return Deck.find_card_index(hand, action.card_id)
    end
    return nil
end

function State.apply_action(s, action, opts)
    if type(action) ~= "table" or not action.type then
        return false, "Invalid action format"
    end

    local atype = action.type

    -- Hotseat reveal action
    if atype == "REVEAL_HOTSEAT" then
        s.hotseat_hidden = false
        return true, { type = "REVEAL_HOTSEAT" }
    end

    -- Hand sorting action (presentation/convenience, valid anytime for a player)
    if atype == "SORT_HAND" then
        local p = action.player or s.active_player
        local hand = s.hands[p]
        if not hand then
            return false, "Invalid player for SORT_HAND"
        end
        if action.mode == "value" then
            Deck.sort_by_value(hand)
        else
            Deck.sort_by_suit(hand)
        end
        return true, { type = "SORT_HAND", player = p, mode = action.mode or "suit" }
    end

    -- Play a card from hand
    if atype == "PLAY_CARD" then
        if s.phase ~= State.PHASES.WAIT_LEAD and s.phase ~= State.PHASES.WAIT_FOLLOW then
            return false, "Cannot PLAY_CARD in phase " .. tostring(s.phase)
        end
        local player = action.player or s.active_player
        if player ~= s.active_player then
            return false, "Not Player " .. tostring(player) .. "'s turn"
        end

        local hand = s.hands[player]
        local idx = resolve_card_index(hand, action)
        if not idx then
            return false, "Card not found in hand"
        end

        local lead_card = (s.phase == State.PHASES.WAIT_FOLLOW) and s.trick.lead_card or nil
        if not Rules.is_card_legal(hand, idx, lead_card) then
            if lead_card and lead_card.rank == 11 then
                return false, "Illegal play: Monarch (11) requires playing the 1 (Swan) or your highest card of " .. lead_card.suit
            elseif lead_card then
                return false, "Illegal play: Must follow led suit (" .. lead_card.suit .. ")"
            end
            return false, "Illegal card play"
        end

        push_undo_snapshot(s, opts)

        local played_card = table.remove(hand, idx)
        s.action_log[#s.action_log + 1] = {
            type = "PLAY_CARD",
            player = player,
            card_id = played_card.id,
        }

        if s.phase == State.PHASES.WAIT_LEAD then
            s.trick.lead_card = played_card
            transition_after_card_play(s, played_card, State.PHASES.WAIT_FOLLOW)
        else
            s.trick.follow_card = played_card
            transition_after_card_play(s, played_card, State.PHASES.TRICK_RESOLVE)
        end
        return true, { played_card = played_card, phase = s.phase }
    end

    -- Fox (3) ability: swap card from hand with Decree or pass
    if atype == "FOX_SWAP" then
        if s.phase ~= State.PHASES.PENDING_FOX_SWAP then
            return false, "Not in PENDING_FOX_SWAP phase"
        end
        local hand = s.hands[s.active_player]
        local idx = resolve_card_index(hand, action)
        if not idx then
            return false, "Card to swap not found in hand"
        end

        push_undo_snapshot(s, opts)

        local chosen_card = hand[idx]
        local old_decree = s.decree
        hand[idx] = old_decree
        s.decree = chosen_card

        s.action_log[#s.action_log + 1] = {
            type = "FOX_SWAP",
            player = s.active_player,
            card_id = chosen_card.id,
        }

        finish_pending_ability(s)
        s.status_message = string.format(
            "Player %d swapped Decree to %d of %s (%s is now trump).",
            s.active_player,
            s.decree.rank,
            s.decree.suit,
            s.decree.suit
        )
        return true, { new_decree = s.decree, received_card = old_decree }
    end

    if atype == "FOX_PASS" then
        if s.phase ~= State.PHASES.PENDING_FOX_SWAP then
            return false, "Not in PENDING_FOX_SWAP phase"
        end
        push_undo_snapshot(s, opts)

        s.action_log[#s.action_log + 1] = {
            type = "FOX_PASS",
            player = s.active_player,
        }
        local p = s.active_player
        finish_pending_ability(s)
        s.status_message = string.format(
            "Player %d kept the Decree as %d of %s.",
            p,
            s.decree.rank,
            s.decree.suit
        )
        return true, { kept_decree = s.decree }
    end

    -- Woodcutter (5) ability: bury 1 card from hand to bottom of stock
    if atype == "WOODCUTTER_BURY" then
        if s.phase ~= State.PHASES.PENDING_WOODCUTTER_BURY then
            return false, "Not in PENDING_WOODCUTTER_BURY phase"
        end
        local hand = s.hands[s.active_player]
        local idx = resolve_card_index(hand, action)
        if not idx then
            return false, "Card to bury not found in hand"
        end

        push_undo_snapshot(s, opts)

        local buried_card = table.remove(hand, idx)
        s.stock[#s.stock + 1] = buried_card

        s.action_log[#s.action_log + 1] = {
            type = "WOODCUTTER_BURY",
            player = s.active_player,
            card_id = buried_card.id,
        }
        local p = s.active_player
        finish_pending_ability(s)
        s.status_message = string.format(
            "Player %d buried a card to the bottom of the deck.",
            p
        )
        return true, { buried_card = buried_card }
    end

    -- Resolve completed 2-card trick
    if atype == "RESOLVE_TRICK" then
        if s.phase ~= State.PHASES.TRICK_RESOLVE then
            return false, "Not in TRICK_RESOLVE phase"
        end
        push_undo_snapshot(s, opts)

        local lead_c = s.trick.lead_card
        local follow_c = s.trick.follow_card
        local res = Rules.resolve_trick(lead_c, follow_c, s.trick.lead_player, s.decree.suit)

        s.tricks_won[res.winner] = s.tricks_won[res.winner] + 1
        s.round_bonus[res.winner] = s.round_bonus[res.winner] + res.bonus_points

        res.lead_card = Deck.clone_card(lead_c)
        res.follow_card = Deck.clone_card(follow_c)
        s.trick.last_result = res

        s.action_log[#s.action_log + 1] = {
            type = "RESOLVE_TRICK",
            trick_number = s.trick.number,
        }

        -- Check if all 13 tricks have been played
        if s.trick.number >= 13 or (#s.hands[1] == 0 and #s.hands[2] == 0) then
            local round_scores = Rules.score_round(
                s.tricks_won[1],
                s.tricks_won[2],
                s.round_bonus[1],
                s.round_bonus[2]
            )
            round_scores.round_number = s.round_number
            s.last_round_summary = round_scores
            s.scores[1] = s.scores[1] + round_scores.p1.round_total
            s.scores[2] = s.scores[2] + round_scores.p2.round_total

            -- Check match end condition (default 21 points)
            if s.scores[1] >= s.target_score or s.scores[2] >= s.target_score then
                if s.scores[1] > s.scores[2] then
                    s.winner = 1
                elseif s.scores[2] > s.scores[1] then
                    s.winner = 2
                else
                    -- Tiebreaker: player who earned more points in the final round wins, or Player 1 if still tied
                    s.winner = (round_scores.p1.round_total >= round_scores.p2.round_total) and 1 or 2
                end
                s.phase = State.PHASES.MATCH_OVER
                s.status_message = string.format(
                    "Match Over! Player %d wins (%d to %d)!",
                    s.winner,
                    s.scores[1],
                    s.scores[2]
                )
            else
                s.phase = State.PHASES.ROUND_OVER
                s.status_message = string.format(
                    "Round %d Complete! P1: +%d (%s) | P2: +%d (%s).",
                    s.round_number,
                    round_scores.p1.round_total,
                    round_scores.p1.tier,
                    round_scores.p2.round_total,
                    round_scores.p2.tier
                )
            end
            return true, { trick_result = res, round_summary = round_scores }
        end

        -- Advance to next trick
        local next_num = s.trick.number + 1
        local next_lead = res.next_leader
        local next_follow = (next_lead == 1) and 2 or 1
        local prev_active = s.active_player

        s.trick = {
            number = next_num,
            lead_player = next_lead,
            follow_player = next_follow,
            lead_card = nil,
            follow_card = nil,
            pending_after_ability = nil,
            last_result = res,
        }
        s.phase = State.PHASES.WAIT_LEAD
        s.active_player = next_lead
        if s.mode == State.MODES.HOTSEAT and prev_active ~= next_lead then
            s.hotseat_hidden = true
        end

        local extra = ""
        if res.swan_triggered then
            extra = string.format(" (Swan 1 triggered: Player %d leads!)", next_lead)
        elseif res.witch_triggered then
            extra = " (Witch 9 acted as trump!)"
        end
        if res.bonus_points > 0 then
            extra = extra .. string.format(" (+%d Treasure pts)", res.bonus_points)
        end

        s.status_message = string.format(
            "Player %d won trick #%d%s. Player %d leads trick #%d.",
            res.winner,
            next_num - 1,
            extra,
            next_lead,
            next_num
        )
        return true, { trick_result = res }
    end

    -- Start next round after ROUND_OVER
    if atype == "NEXT_ROUND" then
        if s.phase ~= State.PHASES.ROUND_OVER then
            return false, "Cannot start NEXT_ROUND in phase " .. tostring(s.phase)
        end
        push_undo_snapshot(s, opts)

        s.round_number = s.round_number + 1
        s.dealer = (s.dealer == 1) and 2 or 1
        s.action_log[#s.action_log + 1] = {
            type = "NEXT_ROUND",
            round_number = s.round_number,
        }
        State.start_round(s)
        return true, { round_number = s.round_number }
    end

    return false, "Unknown action type: " .. tostring(atype)
end

function State.undo(s)
    if not s.undo_stack or #s.undo_stack == 0 then
        return false, "Nothing to undo"
    end
    local prev = table.remove(s.undo_stack)
    local remaining_stack = s.undo_stack
    for k, _ in pairs(s) do
        s[k] = nil
    end
    for k, v in pairs(prev) do
        s[k] = v
    end
    s.undo_stack = remaining_stack
    return true
end

function State.replay(seed, config, action_log)
    local cfg = {}
    if type(config) == "table" then
        for k, v in pairs(config) do
            cfg[k] = v
        end
    end
    cfg.seed = seed
    local s = State.new_match(cfg)
    for i = 1, #(action_log or {}) do
        local ok, err = State.apply_action(s, action_log[i], { no_history = true })
        if not ok then
            return nil, string.format("Replay failed at step %d: %s", i, tostring(err))
        end
    end
    return s
end

-- Plain table serialization (excludes undo_stack for compact representation)
function State.to_table(s)
    local plain = State.clone(s, true)
    plain.prng = s.prng:serialize()
    plain.undo_stack = nil
    return plain
end

function State.from_table(t)
    assert(type(t) == "table", "State.from_table expects a table")
    local copy = {
        seed = t.seed,
        mode = t.mode,
        target_score = t.target_score,
        round_number = t.round_number,
        dealer = t.dealer,
        phase = t.phase,
        active_player = t.active_player,
        hotseat_hidden = t.hotseat_hidden,
        winner = t.winner,
        status_message = t.status_message,
        last_drawn_card = Deck.clone_card(t.last_drawn_card),
        decree = Deck.clone_card(t.decree),
        stock = Deck.clone_cards(t.stock),
        hands = {
            [1] = Deck.clone_cards(t.hands and (t.hands[1] or t.hands["1"]) or {}),
            [2] = Deck.clone_cards(t.hands and (t.hands[2] or t.hands["2"]) or {}),
        },
        tricks_won = {
            [1] = t.tricks_won and (t.tricks_won[1] or t.tricks_won["1"]) or 0,
            [2] = t.tricks_won and (t.tricks_won[2] or t.tricks_won["2"]) or 0,
        },
        round_bonus = {
            [1] = t.round_bonus and (t.round_bonus[1] or t.round_bonus["1"]) or 0,
            [2] = t.round_bonus and (t.round_bonus[2] or t.round_bonus["2"]) or 0,
        },
        scores = {
            [1] = t.scores and (t.scores[1] or t.scores["1"]) or 0,
            [2] = t.scores and (t.scores[2] or t.scores["2"]) or 0,
        },
        trick = clone_trick(t.trick),
        last_round_summary = clone_round_summary(t.last_round_summary),
        prng = PRNG.deserialize(t.prng),
        action_log = {},
        undo_stack = {},
    }
    if t.action_log then
        for i = 1, #t.action_log do
            copy.action_log[i] = clone_action(t.action_log[i])
        end
    end
    return copy
end

-- Deterministic pure-Lua JSON serializer & parser for match state persistence
local function escape_json_str(str)
    return (str:gsub("\\", "\\\\")
               :gsub('"', '\\"')
               :gsub("\n", "\\n")
               :gsub("\r", "\\r")
               :gsub("\t", "\\t"))
end

local function is_array(t)
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
            return false, 0
        end
        count = count + 1
    end
    for i = 1, count do
        if t[i] == nil then
            return false, 0
        end
    end
    return true, count
end

local function encode_json_value(v)
    local tv = type(v)
    if tv == "nil" then
        return "null"
    elseif tv == "boolean" then
        return v and "true" or "false"
    elseif tv == "number" then
        return tostring(v)
    elseif tv == "string" then
        return '"' .. escape_json_str(v) .. '"'
    elseif tv == "table" then
        local arr, n = is_array(v)
        if arr then
            local parts = {}
            for i = 1, n do
                parts[i] = encode_json_value(v[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local keys = {}
            for k, _ in pairs(v) do
                keys[#keys + 1] = k
            end
            table.sort(keys, function(a, b)
                return tostring(a) < tostring(b)
            end)
            local parts = {}
            for i = 1, #keys do
                local k = keys[i]
                parts[i] = '"' .. escape_json_str(tostring(k)) .. '":' .. encode_json_value(v[k])
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    error("Unsupported JSON type: " .. tv)
end

local function decode_json(str)
    local pos = 1
    local len = #str

    local function skip_ws()
        while pos <= len do
            local b = str:byte(pos)
            if b == 32 or b == 9 or b == 10 or b == 13 then
                pos = pos + 1
            else
                break
            end
        end
    end

    local parse_value

    local function parse_string()
        pos = pos + 1 -- skip opening quote
        local out = {}
        while pos <= len do
            local ch = str:sub(pos, pos)
            if ch == '"' then
                pos = pos + 1
                return table.concat(out)
            elseif ch == "\\" then
                pos = pos + 1
                local esc = str:sub(pos, pos)
                if esc == "n" then out[#out + 1] = "\n"
                elseif esc == "r" then out[#out + 1] = "\r"
                elseif esc == "t" then out[#out + 1] = "\t"
                else out[#out + 1] = esc end
                pos = pos + 1
            else
                out[#out + 1] = ch
                pos = pos + 1
            end
        end
        error("Unterminated JSON string")
    end

    local function parse_number()
        local start_p = pos
        while pos <= len and str:sub(pos, pos):match("[0-9%+%-%.eE]") do
            pos = pos + 1
        end
        local num = tonumber(str:sub(start_p, pos - 1))
        if not num then
            error("Invalid JSON number at " .. tostring(start_p))
        end
        return num
    end

    local function parse_array()
        pos = pos + 1 -- skip '['
        local arr = {}
        skip_ws()
        if str:sub(pos, pos) == "]" then
            pos = pos + 1
            return arr
        end
        local idx = 1
        while pos <= len do
            arr[idx] = parse_value()
            idx = idx + 1
            skip_ws()
            local ch = str:sub(pos, pos)
            if ch == "]" then
                pos = pos + 1
                return arr
            elseif ch == "," then
                pos = pos + 1
            else
                error("Expected ',' or ']' in JSON array at " .. tostring(pos))
            end
        end
        error("Unterminated JSON array")
    end

    local function parse_object()
        pos = pos + 1 -- skip '{'
        local obj = {}
        skip_ws()
        if str:sub(pos, pos) == "}" then
            pos = pos + 1
            return obj
        end
        while pos <= len do
            skip_ws()
            local key = parse_string()
            skip_ws()
            if str:sub(pos, pos) ~= ":" then
                error("Expected ':' in JSON object at " .. tostring(pos))
            end
            pos = pos + 1
            local val = parse_value()
            obj[key] = val
            skip_ws()
            local ch = str:sub(pos, pos)
            if ch == "}" then
                pos = pos + 1
                return obj
            elseif ch == "," then
                pos = pos + 1
            else
                error("Expected ',' or '}' in JSON object at " .. tostring(pos))
            end
        end
        error("Unterminated JSON object")
    end

    parse_value = function()
        skip_ws()
        local ch = str:sub(pos, pos)
        if ch == '"' then
            return parse_string()
        elseif ch == "{" then
            return parse_object()
        elseif ch == "[" then
            return parse_array()
        elseif ch == "t" and str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif ch == "f" and str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif ch == "n" and str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            return parse_number()
        end
    end

    return parse_value()
end

function State.to_json(s)
    return encode_json_value(State.to_table(s))
end

function State.from_json(json_str)
    local decoded = decode_json(json_str)
    return State.from_table(decoded)
end

return State
