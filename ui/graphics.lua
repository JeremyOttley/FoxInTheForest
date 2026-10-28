-- ui/graphics.lua
-- Procedural pixel-art and Windows 95/98 UI chrome rendering for LÖVE2D (Zero External Assets)

local Graphics = {}

Graphics.COLORS = {
    FELT_GREEN      = { 0.00, 0.50, 0.00, 1.0 }, -- #008000 classic FreeCell/Solitaire green
    FELT_DARK       = { 0.00, 0.36, 0.00, 1.0 },
    FELT_LIGHT      = { 0.05, 0.58, 0.05, 1.0 },

    WIN_GRAY        = { 0.753, 0.753, 0.753, 1.0 }, -- #C0C0C0
    WIN_LIGHT       = { 1.000, 1.000, 1.000, 1.0 }, -- #FFFFFF
    WIN_SOFT_LIGHT  = { 0.875, 0.875, 0.875, 1.0 }, -- #DFDFDF
    WIN_DARK        = { 0.502, 0.502, 0.502, 1.0 }, -- #808080
    WIN_BLACK       = { 0.000, 0.000, 0.000, 1.0 }, -- #000000
    WIN_NAVY        = { 0.000, 0.000, 0.502, 1.0 }, -- #000080 classic Win95 titlebar
    WIN_TEAL        = { 0.000, 0.502, 0.502, 1.0 },

    CARD_FACE       = { 0.990, 0.985, 0.965, 1.0 },
    CARD_HOVER      = { 1.000, 1.000, 0.920, 1.0 },
    CARD_BORDER     = { 0.080, 0.080, 0.080, 1.0 },
    CARD_BACK_BASE  = { 0.120, 0.240, 0.560, 1.0 },
    CARD_BACK_GRID  = { 0.280, 0.480, 0.820, 1.0 },
    CARD_DIM        = { 0.000, 0.000, 0.000, 0.42 },
    CARD_SHADOW     = { 0.000, 0.000, 0.000, 0.45 },
    GLOW_GOLD       = { 1.000, 0.880, 0.250, 0.85 },

    -- Suit Palettes
    BELLS_PRIMARY   = { 0.840, 0.560, 0.060, 1.0 }, -- Gold / Amber
    BELLS_HIGHLIGHT = { 0.980, 0.800, 0.220, 1.0 },
    BELLS_OUTLINE   = { 0.480, 0.300, 0.020, 1.0 },

    KEYS_PRIMARY    = { 0.420, 0.460, 0.520, 1.0 }, -- Silver / Cool Grey
    KEYS_HIGHLIGHT  = { 0.720, 0.760, 0.820, 1.0 },
    KEYS_OUTLINE    = { 0.200, 0.230, 0.270, 1.0 },

    MOONS_PRIMARY   = { 0.240, 0.280, 0.720, 1.0 }, -- Night Violet / Soft Blue
    MOONS_HIGHLIGHT = { 0.480, 0.540, 0.920, 1.0 },
    MOONS_OUTLINE   = { 0.120, 0.140, 0.440, 1.0 },
}

-- 11x11 Pixel-Art Matrices for crisp retro icon rendering alongside vector primitives
Graphics.PIXEL_SUITS = {
    Bells = {
        "....###....",
        "....#.#....",
        "...#####...",
        "..#######..",
        "..#######..",
        "..#######..",
        ".#########.",
        ".#########.",
        "###########",
        "....###....",
        ".....#.....",
    },
    Keys = {
        "...#####...",
        "..##...##..",
        "..#.....#..",
        "..##...##..",
        "...#####...",
        ".....#.....",
        ".....###...",
        ".....#.....",
        ".....####..",
        ".....#..#..",
        ".....####..",
    },
    Moons = {
        "....####...",
        "..######...",
        ".#####.....",
        "#####......",
        "####.......",
        "####.......",
        "####.......",
        "#####......",
        ".#####.....",
        "..######...",
        "....####...",
    },
}

local function set_color(c)
    love.graphics.setColor(c[1], c[2], c[3], c[4] or 1.0)
end

function Graphics.clear_felt(w, h)
    local c = Graphics.COLORS.FELT_GREEN
    love.graphics.clear(c[1], c[2], c[3], 1.0)
    -- Subtle classic tabletop inner trim line
    set_color(Graphics.COLORS.FELT_DARK)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", 8, 32, w - 16, h - 40)
    love.graphics.setLineWidth(1)
end

-- Classic Win95 3D Raised Panel
function Graphics.draw_raised_panel(x, y, w, h, fill_color)
    set_color(fill_color or Graphics.COLORS.WIN_GRAY)
    love.graphics.rectangle("fill", x, y, w, h)

    -- Outer top/left white highlight
    set_color(Graphics.COLORS.WIN_LIGHT)
    love.graphics.line(x, y, x + w - 1, y)
    love.graphics.line(x, y, x, y + h - 1)

    -- Inner top/left soft highlight
    set_color(Graphics.COLORS.WIN_SOFT_LIGHT)
    love.graphics.line(x + 1, y + 1, x + w - 2, y + 1)
    love.graphics.line(x + 1, y + 1, x + 1, y + h - 2)

    -- Inner bottom/right dark gray shadow
    set_color(Graphics.COLORS.WIN_DARK)
    love.graphics.line(x + 1, y + h - 2, x + w - 2, y + h - 2)
    love.graphics.line(x + w - 2, y + 1, x + w - 2, y + h - 2)

    -- Outer bottom/right black shadow
    set_color(Graphics.COLORS.WIN_BLACK)
    love.graphics.line(x, y + h - 1, x + w - 1, y + h - 1)
    love.graphics.line(x + w - 1, y, x + w - 1, y + h - 1)
end

-- Classic Win95 3D Sunken Panel / Status Well
function Graphics.draw_sunken_panel(x, y, w, h, fill_color)
    if fill_color then
        set_color(fill_color)
        love.graphics.rectangle("fill", x, y, w, h)
    end

    -- Outer top/left dark gray shadow
    set_color(Graphics.COLORS.WIN_DARK)
    love.graphics.line(x, y, x + w - 1, y)
    love.graphics.line(x, y, x, y + h - 1)

    -- Inner top/left black shadow
    set_color(Graphics.COLORS.WIN_BLACK)
    love.graphics.line(x + 1, y + 1, x + w - 2, y + 1)
    love.graphics.line(x + 1, y + 1, x + 1, y + h - 2)

    -- Inner bottom/right soft light
    set_color(Graphics.COLORS.WIN_SOFT_LIGHT)
    love.graphics.line(x + 1, y + h - 2, x + w - 2, y + h - 2)
    love.graphics.line(x + w - 2, y + 1, x + w - 2, y + h - 2)

    -- Outer bottom/right white highlight
    set_color(Graphics.COLORS.WIN_LIGHT)
    love.graphics.line(x, y + h - 1, x + w - 1, y + h - 1)
    love.graphics.line(x + w - 1, y, x + w - 1, y + h - 1)
end

-- Sunken tabletop card drop slot (like FreeCell foundation/cell slots)
function Graphics.draw_card_slot(x, y, w, h, label, highlight)
    Graphics.draw_sunken_panel(x, y, w, h, Graphics.COLORS.FELT_DARK)
    if highlight then
        set_color(Graphics.COLORS.GLOW_GOLD)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x + 2, y + 2, w - 4, h - 4, 4, 4)
        love.graphics.setLineWidth(1)
    end
    if label then
        set_color(Graphics.COLORS.FELT_LIGHT)
        love.graphics.printf(label, x + 4, y + math.floor(h / 2) - 7, w - 8, "center")
    end
end

-- Win95 Button with hover and pressed states
function Graphics.draw_button(x, y, w, h, label, is_hovered, is_pressed, is_disabled)
    if is_pressed and not is_disabled then
        Graphics.draw_sunken_panel(x, y, w, h, Graphics.COLORS.WIN_GRAY)
    else
        local bg = is_hovered and not is_disabled and Graphics.COLORS.WIN_SOFT_LIGHT or Graphics.COLORS.WIN_GRAY
        Graphics.draw_raised_panel(x, y, w, h, bg)
    end

    local offset = (is_pressed and not is_disabled) and 1 or 0
    if is_disabled then
        set_color(Graphics.COLORS.WIN_LIGHT)
        love.graphics.printf(label, x + 1, y + math.floor((h - 14) / 2) + 1, w, "center")
        set_color(Graphics.COLORS.WIN_DARK)
        love.graphics.printf(label, x, y + math.floor((h - 14) / 2), w, "center")
    else
        set_color(Graphics.COLORS.WIN_BLACK)
        love.graphics.printf(label, x + offset, y + math.floor((h - 14) / 2) + offset, w, "center")
    end
end

-- Win95 Modal Dialog Frame with Navy Titlebar
function Graphics.draw_window_frame(x, y, w, h, title)
    -- Drop shadow
    set_color(Graphics.COLORS.CARD_SHADOW)
    love.graphics.rectangle("fill", x + 6, y + 6, w, h)

    Graphics.draw_raised_panel(x, y, w, h, Graphics.COLORS.WIN_GRAY)

    -- Navy blue title bar
    set_color(Graphics.COLORS.WIN_NAVY)
    love.graphics.rectangle("fill", x + 4, y + 4, w - 8, 22)

    set_color(Graphics.COLORS.WIN_LIGHT)
    love.graphics.print(title or "Dialog", x + 10, y + 8)
end

function Graphics.get_suit_colors(suit)
    if suit == "Bells" then
        return Graphics.COLORS.BELLS_PRIMARY, Graphics.COLORS.BELLS_HIGHLIGHT, Graphics.COLORS.BELLS_OUTLINE
    elseif suit == "Keys" then
        return Graphics.COLORS.KEYS_PRIMARY, Graphics.COLORS.KEYS_HIGHLIGHT, Graphics.COLORS.KEYS_OUTLINE
    else
        return Graphics.COLORS.MOONS_PRIMARY, Graphics.COLORS.MOONS_HIGHLIGHT, Graphics.COLORS.MOONS_OUTLINE
    end
end

-- Renders the 11x11 pixel matrix for small corner pips
function Graphics.draw_pixel_pip(suit, x, y, pixel_size)
    local matrix = Graphics.PIXEL_SUITS[suit] or Graphics.PIXEL_SUITS.Bells
    local primary, _, outline = Graphics.get_suit_colors(suit)
    local ps = pixel_size or 1
    local pts = {}

    set_color(primary)
    for row = 1, #matrix do
        local line = matrix[row]
        for col = 1, #line do
            if line:sub(col, col) == "#" then
                local px = x + (col - 1) * ps
                local py = y + (row - 1) * ps
                if ps <= 1 then
                    pts[#pts + 1] = px
                    pts[#pts + 1] = py
                else
                    love.graphics.rectangle("fill", px, py, ps, ps)
                end
            end
        end
    end
    if ps <= 1 and #pts > 0 then
        love.graphics.points(pts)
    end
    set_color(outline)
end

-- Renders detailed procedural geometric + pixel-art suit emblem at (cx, cy) with radius `r`
function Graphics.draw_suit_icon(suit, cx, cy, r)
    local primary, highlight, outline = Graphics.get_suit_colors(suit)

    if suit == "Bells" then
        -- Symmetrical curved bell silhouette with crown loop and clapper dot at the base
        set_color(outline)
        love.graphics.circle("line", cx, cy - r * 0.78, r * 0.22)

        local bell_poly = {
            cx - r * 0.25, cy - r * 0.65,
            cx + r * 0.25, cy - r * 0.65,
            cx + r * 0.55, cy - r * 0.10,
            cx + r * 0.85, cy + r * 0.50,
            cx - r * 0.85, cy + r * 0.50,
            cx - r * 0.55, cy - r * 0.10,
        }
        set_color(primary)
        love.graphics.polygon("fill", bell_poly)

        -- Bell highlight stripe
        set_color(highlight)
        love.graphics.polygon("fill",
            cx - r * 0.12, cy - r * 0.52,
            cx + r * 0.05, cy - r * 0.52,
            cx - r * 0.20, cy + r * 0.38,
            cx - r * 0.45, cy + r * 0.38
        )

        set_color(outline)
        love.graphics.polygon("line", bell_poly)

        -- Clapper dot at the base
        set_color(outline)
        love.graphics.circle("fill", cx, cy + r * 0.74, r * 0.22)
        set_color(highlight)
        love.graphics.circle("fill", cx - r * 0.04, cy + r * 0.72, r * 0.10)

    elseif suit == "Keys" then
        -- Classic skeleton key silhouette (loop head, slender shaft, two-toothed bit)
        local bow_y = cy - r * 0.45
        local bow_r = r * 0.42

        set_color(primary)
        love.graphics.circle("fill", cx, bow_y, bow_r)
        set_color(Graphics.COLORS.CARD_FACE)
        love.graphics.circle("fill", cx, bow_y, bow_r * 0.48)
        set_color(outline)
        love.graphics.circle("line", cx, bow_y, bow_r)
        love.graphics.circle("line", cx, bow_y, bow_r * 0.48)

        -- Slender shaft
        local shaft_w = math.max(3, r * 0.24)
        local shaft_top = bow_y + bow_r - 1
        local shaft_h = r * 1.25
        set_color(primary)
        love.graphics.rectangle("fill", cx - shaft_w * 0.5, shaft_top, shaft_w, shaft_h)

        -- Two-toothed bit on right side
        local bit_w = r * 0.48
        local tooth_h = math.max(2, r * 0.18)
        local t1_y = shaft_top + shaft_h * 0.48
        local t2_y = shaft_top + shaft_h * 0.78
        love.graphics.rectangle("fill", cx + shaft_w * 0.5 - 1, t1_y, bit_w, tooth_h)
        love.graphics.rectangle("fill", cx + shaft_w * 0.5 - 1, t2_y, bit_w, tooth_h)

        -- Highlight along shaft
        set_color(highlight)
        love.graphics.line(cx - shaft_w * 0.2, shaft_top + 1, cx - shaft_w * 0.2, shaft_top + shaft_h - 1)

        set_color(outline)
        love.graphics.rectangle("line", cx - shaft_w * 0.5, shaft_top, shaft_w, shaft_h)
        love.graphics.rectangle("line", cx + shaft_w * 0.5 - 1, t1_y, bit_w, tooth_h)
        love.graphics.rectangle("line", cx + shaft_w * 0.5 - 1, t2_y, bit_w, tooth_h)

    else
        -- Moons: Clean crescent moon silhouette facing right with inner cutout
        local outer_r = r * 0.78
        local cut_r = r * 0.64
        local cut_x = cx + r * 0.34
        local cut_y = cy - r * 0.08

        -- Build crescent polygon points smoothly
        local poly = {}
        local steps = 12
        for i = 0, steps do
            local ang = (math.pi * 0.30) + (i / steps) * (math.pi * 1.40)
            poly[#poly + 1] = cx + math.cos(ang) * outer_r
            poly[#poly + 1] = cy + math.sin(ang) * outer_r
        end
        for i = steps, 0, -1 do
            local ang = (math.pi * 0.38) + (i / steps) * (math.pi * 1.24)
            poly[#poly + 1] = cut_x + math.cos(ang) * cut_r
            poly[#poly + 1] = cut_y + math.sin(ang) * cut_r
        end

        set_color(primary)
        love.graphics.polygon("fill", poly)
        set_color(outline)
        love.graphics.polygon("line", poly)

        -- Subtle star accent inside crescent opening
        set_color(highlight)
        local sx = cx + r * 0.42
        local sy = cy - r * 0.05
        love.graphics.line(sx - 3, sy, sx + 3, sy)
        love.graphics.line(sx, sy - 3, sx, sy + 3)
    end
end

-- Renders a small role emblem for odd-numbered special cards (1, 3, 5, 7, 9, 11)
function Graphics.draw_role_emblem(rank, cx, cy, suit)
    local primary, highlight, outline = Graphics.get_suit_colors(suit)
    set_color(outline)
    if rank == 1 then
        -- Swan: graceful curved neck and wing silhouette
        love.graphics.ellipse("fill", cx + 2, cy + 4, 8, 5)
        love.graphics.line(cx - 4, cy + 3, cx - 6, cy - 5, cx - 2, cy - 7)
    elseif rank == 3 then
        -- Fox: pointed ears and triangular snout
        love.graphics.polygon("fill", cx - 8, cy - 2, cx + 8, cy - 2, cx, cy + 8)
        love.graphics.polygon("fill", cx - 8, cy - 2, cx - 6, cy - 9, cx - 2, cy - 2)
        love.graphics.polygon("fill", cx + 8, cy - 2, cx + 6, cy - 9, cx + 2, cy - 2)
    elseif rank == 5 then
        -- Woodcutter: axe head + handle
        love.graphics.line(cx - 6, cy + 7, cx + 5, cy - 7)
        set_color(primary)
        love.graphics.polygon("fill", cx, cy - 4, cx + 8, cy - 8, cx + 9, cy + 1, cx + 2, cy)
    elseif rank == 7 then
        -- Treasure:faceted gem / chest
        set_color(highlight)
        love.graphics.polygon("fill", cx, cy - 8, cx + 8, cy, cx, cy + 8, cx - 8, cy)
        set_color(outline)
        love.graphics.polygon("line", cx, cy - 8, cx + 8, cy, cx, cy + 8, cx - 8, cy)
    elseif rank == 9 then
        -- Witch: pointed hat silhouette
        love.graphics.ellipse("fill", cx, cy + 6, 10, 3)
        love.graphics.polygon("fill", cx - 6, cy + 5, cx + 6, cy + 5, cx + 2, cy - 9)
    elseif rank == 11 then
        -- Monarch: 3-pointed crown
        set_color(highlight)
        love.graphics.polygon("fill",
            cx - 9, cy + 6,
            cx - 9, cy - 4,
            cx - 4, cy + 1,
            cx,     cy - 7,
            cx + 4, cy + 1,
            cx + 9, cy - 4,
            cx + 9, cy + 6
        )
        set_color(outline)
        love.graphics.polygon("line",
            cx - 9, cy + 6,
            cx - 9, cy - 4,
            cx - 4, cy + 1,
            cx,     cy - 7,
            cx + 4, cy + 1,
            cx + 9, cy - 4,
            cx + 9, cy + 6
        )
    end
end

-- Renders a face-down card back with classic Win95 crosshatch lattice
function Graphics.draw_card_back(x, y, w, h)
    set_color(Graphics.COLORS.CARD_FACE)
    love.graphics.rectangle("fill", x, y, w, h, 5, 5)

    set_color(Graphics.COLORS.CARD_BACK_BASE)
    love.graphics.rectangle("fill", x + 4, y + 4, w - 8, h - 8, 3, 3)

    -- Crosshatch pattern inside card back
    set_color(Graphics.COLORS.CARD_BACK_GRID)
    local left = x + 6
    local top = y + 6
    local right = x + w - 6
    local bottom = y + h - 6
    for py = top, bottom, 6 do
        love.graphics.line(left, py, right, py)
    end
    for px = left, right, 6 do
        love.graphics.line(px, top, px, bottom)
    end

    -- Center diamond medallion
    local cx = x + w * 0.5
    local cy = y + h * 0.5
    set_color(Graphics.COLORS.CARD_FACE)
    love.graphics.polygon("fill", cx, cy - 14, cx + 10, cy, cx, cy + 14, cx - 10, cy)
    set_color(Graphics.COLORS.CARD_BACK_BASE)
    love.graphics.polygon("fill", cx, cy - 9, cx + 6, cy, cx, cy + 9, cx - 6, cy)

    set_color(Graphics.COLORS.CARD_BORDER)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h, 5, 5)
end

-- Renders a complete face-up card with rank, procedural suit pips, role badge, hover glow, and illegal dimming
function Graphics.draw_card_face(card, x, y, w, h, opts)
    local o = opts or {}

    -- Drop shadow when dragging or elevated
    if o.is_dragging or o.shadow then
        local s_off = o.is_dragging and 6 or 3
        set_color(Graphics.COLORS.CARD_SHADOW)
        love.graphics.rectangle("fill", x + s_off, y + s_off, w, h, 5, 5)
    end

    -- Hover / Selected gold glow
    if o.is_hovered or o.is_selected then
        set_color(Graphics.COLORS.GLOW_GOLD)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x - 2, y - 2, w + 4, h + 4, 6, 6)
        love.graphics.setLineWidth(1)
    end

    -- Crisp white card background
    set_color(o.is_hovered and Graphics.COLORS.CARD_HOVER or Graphics.COLORS.CARD_FACE)
    love.graphics.rectangle("fill", x, y, w, h, 5, 5)

    local primary, _, outline = Graphics.get_suit_colors(card.suit)

    -- Inner decorative frame
    set_color({ primary[1], primary[2], primary[3], 0.28 })
    love.graphics.rectangle("line", x + 4, y + 4, w - 8, h - 8, 3, 3)

    -- Top-left rank & pixel-art suit pip
    set_color(outline)
    love.graphics.print(tostring(card.rank), x + 7, y + 5)
    Graphics.draw_pixel_pip(card.suit, x + 7, y + 20, 1)

    -- Bottom-right rank & suit pip
    local r_str = tostring(card.rank)
    local r_x = x + w - (#r_str * 8) - 7
    set_color(outline)
    love.graphics.print(r_str, r_x, y + h - 19)
    Graphics.draw_pixel_pip(card.suit, x + w - 18, y + h - 32, 1)

    -- Center procedural suit art
    local cx = x + w * 0.5
    local cy = card.role and (y + h * 0.40) or (y + h * 0.48)
    Graphics.draw_suit_icon(card.suit, cx, cy, math.min(w, h) * 0.24)

    -- Odd-numbered card role emblem and banner (Swan, Fox, Woodcutter, Treasure, Witch, Monarch)
    if card.role then
        Graphics.draw_role_emblem(card.rank, cx, y + h * 0.66, card.suit)

        -- Subtle role label ribbon near bottom of card
        set_color({ primary[1], primary[2], primary[3], 0.18 })
        love.graphics.rectangle("fill", x + 5, y + h - 38, w - 10, 15, 2, 2)
        set_color(outline)
        love.graphics.printf(card.role, x + 2, y + h - 37, w - 4, "center")
    end

    -- Crisp 1px black border
    set_color(Graphics.COLORS.CARD_BORDER)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h, 5, 5)

    -- Dimming overlay if card cannot be legally played
    if o.is_dimmed then
        set_color(Graphics.COLORS.CARD_DIM)
        love.graphics.rectangle("fill", x, y, w, h, 5, 5)
    end
end

return Graphics
