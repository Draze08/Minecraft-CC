-- ============================================================
-- RuffHouse Peripheral Scanner v2
--
-- Lists every peripheral visible to this computer.
-- Uses paged output because CraftOS terminals do not provide
-- useful scrollback for long peripheral lists.
-- ============================================================

local PAGE_SIZE = 12

-- ============================================================
-- HELPERS
-- ============================================================

local function clearScreen()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function waitForPage()
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

-- ============================================================
-- SCAN
-- ============================================================

local names = peripheral.getNames()

table.sort(names)

local peripherals = {}
local typeCounts = {}

for _, name in ipairs(names) do
    local peripheralType = peripheral.getType(name) or "unknown"

    table.insert(peripherals, {
        name = name,
        type = peripheralType
    })

    typeCounts[peripheralType] =
        (typeCounts[peripheralType] or 0) + 1
end

-- ============================================================
-- PERIPHERAL PAGES
-- ============================================================

local total = #peripherals
local totalPages = math.max(1, math.ceil(total / PAGE_SIZE))

for page = 1, totalPages do
    clearScreen()

    term.setTextColor(colors.yellow)
    print("RuffHouse Peripheral Scanner")
    term.setTextColor(colors.white)
    print("============================")
    print()

    print(
        "Peripherals: "
        .. total
        .. "    Page "
        .. page
        .. "/"
        .. totalPages
    )

    print()

    local first = ((page - 1) * PAGE_SIZE) + 1
    local last = math.min(first + PAGE_SIZE - 1, total)

    if total == 0 then
        term.setTextColor(colors.red)
        print("No peripherals detected.")
        term.setTextColor(colors.white)
    else
        for i = first, last do
            local entry = peripherals[i]

            term.setTextColor(colors.white)
            write(entry.name)

            -- Keep the type visually distinct.
            term.setTextColor(colors.lightGray)
            print("  [" .. entry.type .. "]")
        end
    end

    if page < totalPages then
        if not waitForPage() then
            clearScreen()
            print("Scanner closed.")
            return
        end
    end
end

-- ============================================================
-- TYPE SUMMARY
-- ============================================================

local types = {}

for peripheralType in pairs(typeCounts) do
    table.insert(types, peripheralType)
end

table.sort(types)

-- Give the summary its own page.
clearScreen()

term.setTextColor(colors.yellow)
print("Peripheral Summary")
term.setTextColor(colors.white)
print("==================")
print()

print("Total peripherals: " .. total)
print()

for _, peripheralType in ipairs(types) do
    print(
        peripheralType
        .. ": "
        .. typeCounts[peripheralType]
    )
end

print()

term.setTextColor(colors.lime)
print("Scan complete.")
term.setTextColor(colors.white)
