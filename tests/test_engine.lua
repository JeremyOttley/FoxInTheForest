-- tests/test_engine.lua
-- Comprehensive unit, edge-case, serialization, and performance test suite for the headless core engine.

local PRNG  = require("game.prng")
local Deck  = require("game.deck")
local Rules = require("game.rules")
local State = require("game.state")
local AI    = require("game.ai")

local passed = 0
local failed = 0

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        failed = failed + 1
        error(string.format("[FAIL] %s: expected %s, got %s", msg or "assertion", tostring(expected), tostring(actual)), 2)
    end
    passed = passed + 1
end

local function assert_true(cond, msg)
    if not cond then
        failed = failed + 1
        error(string.format("[FAIL] %s: expected truthy value", msg or "assertion"), 2)
    end
    passed = passed + 1
end

print("=== Running Headless Core Engine Tests ===")

-- 1. PRNG Determinism & Serialization
do
    local p1 = PRNG.new(987654321)
    local p2 = PRNG.new(987654321)
    for i = 1, 1000 do
        assert_eq(p1:next_u31(), p2:next_u31(), "PRNG sequence match at step " .. i)
    end
    -- Verify specific anchor value for cross-runtime determinism (Lua 5.1 / LuaJIT / Lua 5.5)
    local p_anchor = PRNG.new(12345)
    local first_val = p_anchor:next_u31()
    assert_eq(first_val, 383950165, "Cross-runtime deterministic PRNG anchor check")

    local snap = p1:serialize()
    local p3 = PRNG.deserialize(snap)
    for i = 1, 100 do
        assert_eq(p1:next_int(1, 33), p3:next_int(1, 33), "PRNG deserialized continuation match")
    end
end

-- 2. 33-Card Deck Integrity & Sorting
do
    local d = Deck.create_deck()
    assert_eq(#d, 33, "Deck has exactly 33 cards")

    local suit_counts = { Bells = 0, Keys = 0, Moons = 0 }
    local rank_counts = {}
    for i = 1, #d do
        local c = d[i]
        suit_counts[c.suit] = (suit_counts[c.suit] or 0) + 1
        rank_counts[c.rank] = (rank_counts[c.rank] or 0) + 1
        if c.rank % 2 == 1 then
            assert_true(c.role ~= nil, "Odd card rank " .. c.rank .. " has role metadata")
        else
            assert_eq(c.role, nil, "Even card rank " .. c.rank .. " has nil role")
        end
    end
    assert_eq(suit_counts.Bells, 11, "11 Bells")
    assert_eq(suit_counts.Keys, 11, "11 Keys")
    assert_eq(suit_counts.Moons, 11, "11 Moons")
    for r = 1, 11 do
        assert_eq(rank_counts[r], 3, "3 cards of rank " .. r)
    end

    local prng = PRNG.new(42)
    Deck.shuffle(d, prng)
    Deck.sort_by_value(d)
    assert_eq(d[1].rank, 1, "Sort by value starts at rank 1")
    assert_eq(d[33].rank, 11, "Sort by value ends at rank 11")

    Deck.sort_by_suit(d)
    assert_eq(d[1].suit, "Bells", "Sort by suit starts with Bells")
    assert_eq(d[12].suit, "Keys", "Sort by suit middle is Keys")
    assert_eq(d[23].suit, "Moons", "Sort by suit ends with Moons")
end

-- 3. Special Card Rules & Edge Cases (1, 3, 5, 7, 9, 11)
do
    -- 3a. Monarch (11) constraint
    local hand = {
        Deck.make_card("Bells", 1),
        Deck.make_card("Bells", 4),
        Deck.make_card("Bells", 8),
        Deck.make_card("Keys", 10),
    }
    local lead_monarch = Deck.make_card("Bells", 11)
    local legal_idx, legal_map = Rules.get_legal_indices(hand, lead_monarch)
    assert_eq(#legal_idx, 2, "Monarch (11) allows only 1 (Swan) and highest card (8) of led suit")
    assert_true(legal_map[1] == true, "1 of Bells is legal against 11 of Bells")
    assert_true(legal_map[2] == nil, "4 of Bells is illegal against 11 of Bells")
    assert_true(legal_map[3] == true, "8 of Bells is legal against 11 of Bells")
    assert_true(legal_map[4] == nil, "Off-suit Keys is illegal when holding Bells")

    -- Monarch when follower only holds a single card in led suit
    local single_suit_hand = {
        Deck.make_card("Bells", 5),
        Deck.make_card("Moons", 11),
    }
    local legal_single = Rules.get_legal_indices(single_suit_hand, lead_monarch)
    assert_eq(#legal_single, 1, "Monarch with single card in suit allows that card")
    assert_eq(legal_single[1], 1, "Index 1 is legal")

    -- Monarch when follower is void in led suit
    local void_hand = {
        Deck.make_card("Keys", 2),
        Deck.make_card("Moons", 6),
    }
    local legal_void = Rules.get_legal_indices(void_hand, lead_monarch)
    assert_eq(#legal_void, 2, "Monarch when void in led suit allows any card")

    -- 3b. Witch (9) conditional trump evaluation
    -- Case 1: Only one 9 played -> 9 becomes trump (Keys) and beats 10 of led suit (Bells)
    local res_one_nine = Rules.resolve_trick(
        Deck.make_card("Bells", 10),
        Deck.make_card("Moons", 9),
        1,
        "Keys" -- Decree suit is Keys; Moons 9 acts as Keys (trump)!
    )
    assert_eq(res_one_nine.winner, 2, "Single 9 (Witch) acts as trump and beats non-trump 10")
    assert_true(res_one_nine.witch_triggered, "Witch triggered flag is true for single 9")

    -- Case 2: Single 9 loses to 10 or 11 of actual trump suit
    local res_nine_vs_higher_trump = Rules.resolve_trick(
        Deck.make_card("Moons", 9),
        Deck.make_card("Keys", 10),
        1,
        "Keys"
    )
    assert_eq(res_nine_vs_higher_trump.winner, 2, "10 of trump beats 9 (Witch) acting as trump")

    -- Case 3: TWO 9s played in the same trick -> NEITHER acts as arbitrary trump!
    -- Lead is Bells 9, Follow is Moons 9, Decree is Keys -> neither is trump, so led suit (Bells 9) wins!
    local res_two_nines = Rules.resolve_trick(
        Deck.make_card("Bells", 9),
        Deck.make_card("Moons", 9),
        1,
        "Keys"
    )
    assert_eq(res_two_nines.winner, 1, "When two 9s are played, neither promotes to off-suit trump; led 9 wins")
    assert_true(not res_two_nines.witch_triggered, "Witch triggered is false when two 9s are played")

    -- Case 4: Two 9s where follower's 9 is natural Decree suit (Keys)
    local res_two_nines_natural = Rules.resolve_trick(
        Deck.make_card("Bells", 9),
        Deck.make_card("Keys", 9),
        1,
        "Keys"
    )
    assert_eq(res_two_nines_natural.winner, 2, "Natural trump 9 wins when two 9s are played")

    -- 3c. Swan (1) loser-leads-next-trick & Treasure (7) bonus points
    local res_swan_treasure = Rules.resolve_trick(
        Deck.make_card("Bells", 1),
        Deck.make_card("Bells", 7),
        1,
        "Moons"
    )
    assert_eq(res_swan_treasure.winner, 2, "7 of Bells beats 1 of Bells")
    assert_eq(res_swan_treasure.next_leader, 1, "Player 1 lost with 1 (Swan) and leads next trick")
    assert_true(res_swan_treasure.swan_triggered, "Swan triggered is true")
    assert_eq(res_swan_treasure.bonus_points, 1, "+1 bonus point for 7 (Treasure)")

    -- Double 7s in one trick
    local res_double_seven = Rules.resolve_trick(
        Deck.make_card("Bells", 7),
        Deck.make_card("Moons", 7),
        1,
        "Moons"
    )
    assert_eq(res_double_seven.winner, 2, "Trump 7 beats non-trump 7")
    assert_eq(res_double_seven.bonus_points, 2, "+2 bonus points for two 7s in trick")

    -- 3d. Round Scoring Tiers
    local s_humble_greedy = Rules.score_round(2, 11, 1, 2)
    assert_eq(s_humble_greedy.p1.trick_points, 6, "2 tricks = 6 pts (Humble)")
    assert_eq(s_humble_greedy.p1.round_total, 7, "6 + 1 bonus = 7")
    assert_eq(s_humble_greedy.p2.trick_points, 0, "11 tricks = 0 pts (Greedy)")
    assert_eq(s_humble_greedy.p2.round_total, 2, "0 + 2 bonus = 2")

    local s_mid = Rules.score_round(5, 8, 0, 1)
    assert_eq(s_mid.p1.trick_points, 2, "5 tricks = 2 pts")
    assert_eq(s_mid.p2.trick_points, 6, "8 tricks = 6 pts (Victorious)")
    assert_eq(s_mid.p2.round_total, 7, "6 + 1 bonus = 7")
end

-- 4. State Machine: Fox (3) Swap/Pass & Woodcutter (5) Draw/Bury
do
    local s = State.new_match({ seed = 101, mode = State.MODES.PVE })
    -- Set up explicit hand for Player 1 to test Fox (3) and Woodcutter (5)
    s.hands[1] = {
        Deck.make_card("Bells", 3),
        Deck.make_card("Keys", 5),
        Deck.make_card("Moons", 8),
    }
    s.hands[2] = {
        Deck.make_card("Bells", 4),
        Deck.make_card("Keys", 6),
        Deck.make_card("Moons", 10),
    }
    s.decree = Deck.make_card("Moons", 2)
    s.stock = { Deck.make_card("Bells", 11) }

    -- P1 leads 3 of Bells (Fox)
    local ok = State.apply_action(s, { type = "PLAY_CARD", player = 1, hand_index = 1 })
    assert_true(ok, "Playing 3 (Fox) succeeds")
    assert_eq(s.phase, State.PHASES.PENDING_FOX_SWAP, "Phase enters PENDING_FOX_SWAP")

    -- P1 swaps Moons 8 (now at index 2) with Decree (Moons 2)
    ok = State.apply_action(s, { type = "FOX_SWAP", player = 1, hand_index = 2 })
    assert_true(ok, "FOX_SWAP succeeds")
    assert_eq(s.decree.id, "Moons_8", "Decree is now Moons 8")
    assert_eq(s.hands[1][2].id, "Moons_2", "Hand received Moons 2")
    assert_eq(s.phase, State.PHASES.WAIT_FOLLOW, "Phase advances to WAIT_FOLLOW")
    assert_eq(s.active_player, 2, "Active player is now Player 2")

    -- Test Undo of FOX_SWAP and PLAY_CARD
    assert_true(State.undo(s), "Undo FOX_SWAP")
    assert_eq(s.phase, State.PHASES.PENDING_FOX_SWAP, "Undo restored PENDING_FOX_SWAP")
    assert_eq(s.decree.id, "Moons_2", "Undo restored Decree to Moons 2")

    -- Test FOX_PASS instead
    ok = State.apply_action(s, { type = "FOX_PASS", player = 1 })
    assert_true(ok, "FOX_PASS succeeds")
    assert_eq(s.decree.id, "Moons_2", "Decree remains Moons 2")
    assert_eq(s.phase, State.PHASES.WAIT_FOLLOW, "Phase advances to WAIT_FOLLOW")

    -- P2 follows with Bells 4
    ok = State.apply_action(s, { type = "PLAY_CARD", player = 2, hand_index = 1 })
    assert_true(ok, "P2 follows with Bells 4")
    assert_eq(s.phase, State.PHASES.TRICK_RESOLVE, "Phase enters TRICK_RESOLVE")

    ok = State.apply_action(s, { type = "RESOLVE_TRICK" })
    assert_true(ok, "RESOLVE_TRICK succeeds")
    assert_eq(s.tricks_won[2], 1, "P2 won the trick")
    assert_eq(s.active_player, 2, "P2 leads next trick")

    -- P2 leads Keys 6, P1 follows with Keys 5 (Woodcutter)
    assert_true(State.apply_action(s, { type = "PLAY_CARD", player = 2, hand_index = 1 }), "P2 leads Keys 6")
    assert_true(State.apply_action(s, { type = "PLAY_CARD", player = 1, hand_index = 1 }), "P1 follows Keys 5")
    assert_eq(s.phase, State.PHASES.PENDING_WOODCUTTER_BURY, "P1 enters PENDING_WOODCUTTER_BURY")
    assert_eq(#s.stock, 0, "Top stock card was drawn")
    assert_eq(#s.hands[1], 2, "P1 hand has 2 cards after drawing Bells 11")

    -- P1 buries Moons 8 (index 1) to bottom of stock
    assert_true(State.apply_action(s, { type = "WOODCUTTER_BURY", player = 1, hand_index = 1 }), "P1 buries card")
    assert_eq(#s.stock, 1, "Stock now has 1 buried card")
    assert_eq(s.stock[1].id, "Moons_8", "Buried card is at bottom of stock")
    assert_eq(s.phase, State.PHASES.TRICK_RESOLVE, "Phase enters TRICK_RESOLVE after follower's Woodcutter")
end

-- 5. Full Match Simulation, Replay & JSON Serialization Round-Trip
do
    local s = State.new_match({ seed = 777, mode = State.MODES.PVE, target_score = 21 })
    local step_count = 0
    while s.phase ~= State.PHASES.MATCH_OVER and step_count < 2000 do
        step_count = step_count + 1
        local action = AI.choose_action(s, s.active_player)
        assert_true(action ~= nil, "AI produced an action in phase " .. s.phase)
        local ok, err = State.apply_action(s, action, { no_history = true })
        assert_true(ok, "AI action valid: " .. tostring(err))

        -- Mid-game JSON round-trip check
        if step_count == 25 then
            local json_str = State.to_json(s)
            local restored = State.from_json(json_str)
            assert_eq(State.to_json(restored), json_str, "JSON serialization round-trip is bit-exact")
        end
    end
    assert_eq(s.phase, State.PHASES.MATCH_OVER, "Full AI vs AI match reached MATCH_OVER")
    assert_true(s.winner == 1 or s.winner == 2, "Match declared a valid winner")

    -- Verify deterministic Replay from action_log
    local replayed, rep_err = State.replay(777, { mode = State.MODES.PVE, target_score = 21 }, s.action_log)
    assert_true(replayed ~= nil, "Replay succeeded: " .. tostring(rep_err))
    assert_eq(replayed.scores[1], s.scores[1], "Replayed P1 score matches")
    assert_eq(replayed.scores[2], s.scores[2], "Replayed P2 score matches")
    assert_eq(replayed.winner, s.winner, "Replayed winner matches")
end

-- 6. Performance Benchmark (NFR-PERF-01: < 100 microseconds per state transition)
do
    local t0 = os.clock()
    local total_actions = 0
    for match_idx = 1, 20 do
        local s = State.new_match({ seed = 1000 + match_idx, mode = State.MODES.PVE, target_score = 21 })
        while s.phase ~= State.PHASES.MATCH_OVER do
            local action = AI.choose_action(s, s.active_player)
            local ok = State.apply_action(s, action, { no_history = true })
            assert_true(ok, "Benchmark action valid")
            total_actions = total_actions + 1
        end
    end
    local elapsed = os.clock() - t0
    local us_per_action = (elapsed / total_actions) * 1e6
    print(string.format("[PERF] Executed %d state transitions + AI evaluations in %.4f s (%.2f us / action)",
        total_actions, elapsed, us_per_action))
    assert_true(us_per_action < 100.0, string.format("Mean action time %.2f us must be < 100 us", us_per_action))
end

print(string.format("=== ALL ENGINE TESTS PASSED (%d assertions, %d failures) ===", passed, failed))
