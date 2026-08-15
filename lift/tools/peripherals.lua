-- ============================================================
-- RuffHouse Peripheral Scanner v2
--
-- General-purpose CC:Tweaked peripheral scanner.
--
-- Features:
--   - Detects every visible peripheral
--   - Shows peripheral name and reported type
--   - Paginates output for CraftOS terminals
--   - Displays a type summary after the final page
--
-- RuffHouse Minecraft-CC
-- ============================================================

-- Number of peripherals displayed on each page.
-- Kept deliberately conservative so this works comfortably
-- on the Advanced Computer terminal.
local PAGE_SIZE = 10

-- ============================================================
-- TERMINAL HELPERS
-- ============================================================

local function clearScreen()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end


local function waitForNextPage()
    term.setTextColor(colors.yellow)

    print()
    print("ENTER = next page   Q = quit")

    term.setTextColor(colors.white)

    while true do
        local _, key = os.pullEvent("key")

        if key == keys.enter then
            return true
        elseif key == keys.q then
            return false
        end
    end
end


local function waitForSummary()
    term.setTextColor(colors.yellow)

    print()
    print("ENTER = summary   Q = quit")

    term.setTextColor(colors.white)

    while true do
        local _, key = os.pullEvent("key")

        if key == keys.enter then
            return true
        elseif key == keys.q then
            return false
        end
    end
end

-- ============================================================
-- SCAN PERIPHERALS
-- ============================================================

local names = peripheral.getNames()

table.sort(names)

local detected = {}
local typeCounts = {}

for _, name in ipairs(names) do

    local peripheralType =
        peripheral.getType(name) or "unknown"

    detected[#detected + 1] = {
        name = name,
        type = peripheralType
    }

    typeCounts[peripheralType] =
        (typeCounts[peripheralType] or 0) + 1
end

-- ============================================================
-- PAGE CALCULATION
-- ============================================================

local total = #detected

local totalPages =
    math.max(
        1,
        math.ceil(total / PAGE_SIZE)
    )

-- ============================================================
-- DISPLAY PERIPHERAL PAGES
-- ============================================================

for page = 1, totalPages do

    clearScreen()

    term.setTextColor(colors.yellow)
    print("RuffHouse Peripheral Scanner")

    term.setTextColor(colors.white)
    print("============================")
    print()

    print(
        "Peripherals: "
        .. tostring(total)
        .. "   Page "
        .. tostring(page)
        .. "/"
        .. tostring(totalPages)
    )

    print()

    -- --------------------------------------------------------
    -- Determine which entries belong on this page.
    -- --------------------------------------------------------

    local first =
        ((page - 1) * PAGE_SIZE) + 1

    local last =
        math.min(
            first + PAGE_SIZE - 1,
            total
        )

    -- --------------------------------------------------------
    -- No peripherals
    -- --------------------------------------------------------

    if total == 0 then

        term.setTextColor(colors.red)
        print("No peripherals detected.")

        term.setTextColor(colors.white)

    else

        -- ----------------------------------------------------
        -- Display entries
        -- ----------------------------------------------------

        for i = first, last do

            local entry = detected[i]

            term.setTextColor(colors.white)
            write(entry.name)

            term.setTextColor(colors.lightGray)
            print("  [" .. entry.type .. "]")
        end
    end

    -- --------------------------------------------------------
    -- Navigation
    -- --------------------------------------------------------

    if page < totalPages then

        local continue =
            waitForNextPage()

        if not continue then

            clearScreen()

            term.setTextColor(colors.white)
            print("Scanner closed.")

            return
        end

    else

        -- Last peripheral page.
        -- Give the user a chance to inspect it before replacing
        -- the screen with the summary.

        local continue =
            waitForSummary()

        if not continue then

            clearScreen()

            term.setTextColor(colors.white)
            print("Scanner closed.")

            return
        end
    end
end

-- ============================================================
-- BUILD SORTED TYPE LIST
-- ============================================================

local types = {}

for peripheralType in pairs(typeCounts) do
    types[#types + 1] = peripheralType
end

table.sort(types)

-- ============================================================
-- SUMMARY PAGE
-- ============================================================

clearScreen()

term.setTextColor(colors.yellow)
print("RuffHouse Peripheral Summary")

term.setTextColor(colors.white)
print("============================")
print()

print("Total peripherals: " .. tostring(total))
print()

if #types == 0 then

    term.setTextColor(colors.red)
    print("No peripheral types detected.")

else

    for _, peripheralType in ipairs(types) do

        term.setTextColor(colors.white)

        print(
            peripheralType
            .. ": "
            .. tostring(typeCounts[peripheralType])
        )
    end
end

term.setTextColor(colors.white)

print()
print("----------------------------")

term.setTextColor(colors.lime)
print("Scan complete.")

term.setTextColor(colors.white)
