-- RuffHouse CC:Tweaked Lift Monitor Commissioning Tool
-- Maps six physical landing monitors to floors 1-6 by touch.

local FLOOR_COUNT = 6

-- ============================================================
-- Utility functions
-- ============================================================

local function centerText(mon, text, y, colour)
    local w, h = mon.getSize()

    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colour or colors.white)

    local x = math.floor((w - #text) / 2) + 1
    mon.setCursorPos(math.max(1, x), y or math.ceil(h / 2))
    mon.write(text)
end

local function prepareMonitor(mon, text, colour)
    mon.setTextScale(1)
    mon.setBackgroundColor(colors.black)
    mon.clear()

    local _, h = mon.getSize()
    centerText(mon, text, math.ceil(h / 2), colour)
end

-- ============================================================
-- Discover monitors
-- ============================================================

term.clear()
term.setCursorPos(1, 1)

print("RuffHouse Lift Commissioning")
print("============================")
print()

local monitorNames = {}

for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
        table.insert(monitorNames, name)
    end
end

table.sort(monitorNames)

print("Monitors detected: " .. #monitorNames)

if #monitorNames ~= FLOOR_COUNT then
    print()
    print("ERROR:")
    print("Expected " .. FLOOR_COUNT .. " monitors.")
    print("Found " .. #monitorNames .. ".")
    return
end

print("Monitor count OK.")
print()

-- ============================================================
-- Commissioning
-- ============================================================

local mapping = {}
local assigned = {}

for floor = 1, FLOOR_COUNT do

    -- Tell every unassigned monitor what we're looking for.

    for _, name in ipairs(monitorNames) do
        if not assigned[name] then
            local mon = peripheral.wrap(name)
            prepareMonitor(mon, "TOUCH FOR F" .. floor, colors.orange)
        end
    end

    term.clear()
    term.setCursorPos(1, 1)

    print("RuffHouse Lift Commissioning")
    print("============================")
    print()
    print("Waiting for FLOOR " .. floor)
    print()
    print("Touch the monitor")
    print("physically located on Floor " .. floor .. ".")

    while true do
        local event, monitorName = os.pullEvent("monitor_touch")

        -- Ignore a monitor we've already assigned.

        if assigned[monitorName] then
            print()
            print("That monitor is already assigned.")
        else
            mapping[floor] = monitorName
            assigned[monitorName] = true

            local mon = peripheral.wrap(monitorName)

            mon.setBackgroundColor(colors.black)
            mon.clear()

            local _, h = mon.getSize()

            centerText(
                mon,
                "F" .. floor .. " OK",
                math.ceil(h / 2),
                colors.lime
            )

            break
        end
    end
end

-- ============================================================
-- Results
-- ============================================================

term.clear()
term.setCursorPos(1, 1)

print("Commissioning Complete")
print("======================")
print()

for floor = 1, FLOOR_COUNT do
    print(
        "Floor " .. floor ..
        " -> " ..
        mapping[floor]
    )
end

print()
print("All six monitors mapped.")
print()

-- Leave every monitor showing its assigned floor.

for floor = 1, FLOOR_COUNT do
    local mon = peripheral.wrap(mapping[floor])

    mon.setBackgroundColor(colors.black)
    mon.clear()

    local _, h = mon.getSize()

    centerText(
        mon,
        "FLOOR " .. floor,
        math.ceil(h / 2),
        colors.lime
    )
end
