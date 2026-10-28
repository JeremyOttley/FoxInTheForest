-- game/deck.lua
-- Parameterized 33-card deck definition, shuffling, cloning, and sorting for "The Fox in the Forest"

local Deck = {}

Deck.SUITS = { "Bells", "Keys", "Moons" }

Deck.SUIT_ORDER = {
    Bells = 1,
    Keys  = 2,
    Moons = 3,
}

Deck.ROLES = {
    [1]  = {
        name = "Swan",
        short = "Swan",
        trigger = "ON_TRICK_END",
        description = "If you play this and lose the trick, you lead the next trick.",
    },
    [3]  = {
        name = "Fox",
        short = "Fox",
        trigger = "ON_PLAY",
        description = "When you play this, you may exchange a card in your hand with the Decree card.",
    },
    [5]  = {
        name = "Woodcutter",
        short = "Woodcutter",
        trigger = "ON_PLAY",
        description = "When you play this, draw 1 card, then place any 1 card from your hand at the bottom of the deck.",
    },
    [7]  = {
        name = "Treasure",
        short = "Treasure",
        trigger = "ON_TRICK_SCORE",
        description = "The winner of the trick receives 1 point for each 7 in the trick.",
    },
    [9]  = {
        name = "Witch",
        short = "Witch",
        trigger = "ON_TRICK_COMPARE",
        description = "When determining the winner of a trick with only one 9, treat the 9 as if it were in the trump suit.",
    },
    [11] = {
        name = "Monarch",
        short = "Monarch",
        trigger = "ON_LEAD",
        description = "When you lead this, if your opponent has any cards of this suit, they must play either the 1 or their highest card from this suit.",
    },
}

function Deck.make_card(suit, rank)
    local role_info = Deck.ROLES[rank]
    return {
        id = suit .. "_" .. tostring(rank),
        suit = suit,
        rank = rank,
        role = role_info and role_info.name or nil,
        description = role_info and role_info.description or nil,
    }
end

function Deck.clone_card(card)
    if not card then
        return nil
    end
    return {
        id = card.id,
        suit = card.suit,
        rank = card.rank,
        role = card.role,
        description = card.description,
    }
end

function Deck.clone_cards(list)
    local out = {}
    if not list then
        return out
    end
    for i = 1, #list do
        out[i] = Deck.clone_card(list[i])
    end
    return out
end

function Deck.create_deck(suits, max_rank)
    local active_suits = suits or Deck.SUITS
    local top_rank = max_rank or 11
    local cards = {}
    local idx = 1
    for s = 1, #active_suits do
        local suit = active_suits[s]
        for r = 1, top_rank do
            cards[idx] = Deck.make_card(suit, r)
            idx = idx + 1
        end
    end
    return cards
end

function Deck.shuffle(cards, prng)
    assert(prng and type(prng.shuffle) == "function", "Deck.shuffle requires a deterministic PRNG instance")
    return prng:shuffle(cards)
end

local function compare_by_suit(a, b)
    local sa = Deck.SUIT_ORDER[a.suit] or 99
    local sb = Deck.SUIT_ORDER[b.suit] or 99
    if sa ~= sb then
        return sa < sb
    end
    return a.rank < b.rank
end

local function compare_by_value(a, b)
    if a.rank ~= b.rank then
        return a.rank < b.rank
    end
    local sa = Deck.SUIT_ORDER[a.suit] or 99
    local sb = Deck.SUIT_ORDER[b.suit] or 99
    return sa < sb
end

function Deck.sort_by_suit(hand)
    table.sort(hand, compare_by_suit)
    return hand
end

function Deck.sort_by_value(hand)
    table.sort(hand, compare_by_value)
    return hand
end

function Deck.find_card_index(hand, card_id)
    for i = 1, #hand do
        if hand[i].id == card_id then
            return i
        end
    end
    return nil
end

return Deck
