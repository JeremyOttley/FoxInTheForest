-- tests/test_manual.lua
-- Verifies manual.html meets all structural, styling, and offline standards from documentation.md

local fh = assert(io.open("manual.html", "r"), "manual.html must exist")
local html = fh:read("*a")
fh:close()

local passed = 0
local function assert_contains(pattern, desc, plain)
    local found = html:find(pattern, 1, plain ~= false)
    if not found then
        error("[FAIL] manual.html missing required element: " .. tostring(desc) .. " (" .. tostring(pattern) .. ")", 2)
    end
    passed = passed + 1
end

print("=== Running 1990s HTML5 Instruction Manual Verification ===")

assert_contains("<!DOCTYPE html>", "HTML5 doctype")
assert_contains("<style>", "Internal CSS style block")
assert_contains("@media print", "Print-friendly media query")
assert_contains("#f7f4ea", "Off-white paper stock tone #f7f4ea")
assert_contains("#1a2656", "Deep navy accent #1a2656")
assert_contains("#9a1b1b", "Arcade crimson accent #9a1b1b")
assert_contains("#d48b16", "Golden mustard accent #d48b16")
assert_contains("#1b4d2e", "Forest green accent #1b4d2e")
assert_contains("#181818", "Deep charcoal text ink #181818")

-- Verify zero external CDN links (no http:// or https://)
if html:find("https://", 1, true) or html:find("http://", 1, true) then
    error("[FAIL] manual.html must operate 100% offline with zero external http/https CDN dependencies")
end
passed = passed + 1

-- Verify all 8 required manual sections
assert_contains("id=\"front-matter\"", "Section 1: Front Matter & Cover Header")
assert_contains("15-minute break", "Section 1: Safety & Cartridge Handling Warning")
assert_contains("id=\"prologue-lore\"", "Section 2: Prologue / Lore & Objective")
assert_contains("id=\"card-anatomy\"", "Section 3: Component Breakdown & Card Anatomy")
assert_contains("Card Anatomy Pointer Legend", "Section 3: Pure CSS Card Anatomy Diagram & Callout Legend")
assert_contains("id=\"playfield-diagram\"", "Section 4: Playfield / Table Mat Diagram")
assert_contains("id=\"turn-sequence\"", "Section 5: Step-by-Step Turn Sequence")
assert_contains("id=\"keyword-glossary\"", "Section 6: Core Mechanics & Keyword Glossary")
assert_contains("id=\"sample-walkthrough\"", "Section 7: Sample Round Walkthrough")
assert_contains("id=\"back-matter\"", "Section 8: Back Matter / Notes Section")
assert_contains("1-900-555-FOX9", "Section 8: 90s Customer Support Hotline")

print(string.format("=== ALL MANUAL VERIFICATION CHECKS PASSED (%d assertions) ===", passed))
