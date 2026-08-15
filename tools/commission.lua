-- ============================================================
-- RuffHouse CC:Tweaked Lift Commissioning Tool
--
-- Configures:
--   - Lift shaft ID (A-D)
--   - Six physical landing monitors
--
-- Saves configuration to:
--   /lift/config.lua
-- ============================================================

local FLOOR_COUNT = 6
local CONFIG_DIR = "/lift"
local CONFIG_FILE = "/lift/config.lua"

-- ============================================================
-- Utility functions
-- ============================================================

local function centerText(mon, text, y, colour)
    local w, h = mon.getSize()

    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colour or colors.white)

    local x = math.floor((w - #text) / 2) + 1

    mon.setCursorPos(
        math.max(1, x),
        y or math.ceil(h / 2)
    )

    mon.write(text)
end

local function prepareMonitor(mon, text, colour)
    mon.setTextScale(1)
    mon.setBackgroundColor(colors.black)
    mon.clear()

    local _, h = mon.getSize()

    centerText(
        mon,
        text,
        math.ceil(h / 2),
        colour
    )
end

local function clearTerminal()
    term.clear()
    term.setCursorPos(1, 1)
end

-- ============================================================
-- Shaft selection
-- ============================================================

local function selectShaft()
    while true do
        clearTerminal()

        print("RuffHouse Lift Commissioning")
        print("============================")
        print()
        print("Select lift shaft:")
        print()
        print("  A")
        print("  B")
        print("  C")
        print("  D")
        print()
        write("Shaft: ")

        local input = read()
        input = string.upper(input)

        if input == "A"
        or input == "B"
        or input == "C"
        or input == "D" then
            return input
        end

        print()
        print("Invalid shaft.")
        print("Please enter A, B, C or D.")
        sleep(2)
    end
end

-- ============================================================
-- Discover monitors
-- ============================================================

local function discoverMonitors()
    local monitorNames = {}

    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            table.insert(monitorNames, name)
        end
    end

    table.sort(monitorNames)

    return monitorNames
end

-- ============================================================
-- Save configuration
-- ============================================================

local function saveConfig(shaft, mapping)
    if not fs.exists(CONFIG_DIR) then
        fs.makeDir(CONFIG_DIR)
    end

    local file = fs.open(CONFIG_FILE, "w")

    if not file then
        error("Unable to open " .. CONFIG_FILE)
    end

    file.writeLine("return {")
    file.writeLine('    shaft = "' .. shaft .. '",')
    file.writeLine("")
    file.writeLine("    monitors = {")

    for floor = 1, FLOOR_COUNT do
        file.writeLine(
            "        [" ..
            floor ..
            '] = "' ..
            mapping[floor] ..
            '",'
        )
    end

    file.writeLine("    }")
    file.writeLine("}")

    file.close()
end

-- ============================================================
-- Start
-- ============================================================

local shaft = selectShaft()

clearTerminal()

print("RuffHouse Lift Commissioning")
print("============================")
print()
print("Lift Shaft: " .. shaft)
print()
print("Scanning peripherals...")
print()

local monitorNames = discoverMonitors()

print("Monitors detected: " .. #monitorNames)

if #monitorNames ~= FLOOR_COUNT then
    print()
    print("ERROR")
    print("Expected " .. FLOOR_COUNT .. " monitors.")
    print("Found " .. #monitorNames .. ".")
    print()
    print("Commissioning aborted.")
    return
end

print("Monitor count OK.")
sleep(1)

-- ============================================================
-- Commission monitors
-- ============================================================

local mapping = {}
local assigned = {}

for floor = 1, FLOOR_COUNT do

    -- --------------------------------------------------------
    -- Update all unassigned displays
    -- --------------------------------------------------------

    for _, name in ipairs(monitorNames) do
        if not assigned[name] then
            local mon = peripheral.wrap(name)

            prepareMonitor(
                mon,
                "TOUCH FOR F" .. floor,
                colors.orange
            )
        end
    end

    -- --------------------------------------------------------
    -- Show instruction on computer
    -- --------------------------------------------------------

    clearTerminal()

    print("RuffHouse Lift Commissioning")
    print("============================")
    print()
    print("Lift Shaft: " .. shaft)
    print()
    print("Waiting for FLOOR " .. floor)
    print()
    print("Touch the monitor")
    print("physically located on Floor " .. floor .. ".")
    print()

    -- --------------------------------------------------------
    -- Wait for correct monitor touch
    -- --------------------------------------------------------

    while true do
        local _, monitorName = os.pullEvent("monitor_touch")

        if assigned[monitorName] then
            print(
                "Monitor " ..
                monitorName ..
                " is already assigned."
            )
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
-- Save configuration
-- ============================================================

saveConfig(shaft, mapping)

-- ============================================================
-- Final monitor state
-- ============================================================

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

-- ============================================================
-- Results
-- ============================================================

clearTerminal()

print("Commissioning Complete")
print("======================")
print()
print("Lift Shaft: " .. shaft)
print()

for floor = 1, FLOOR_COUNT do
    print(
        "Floor " ..
        floor ..
        " -> " ..
        mapping[floor]
    )
end

print()
print("Configuration saved to:")
print(CONFIG_FILE)
print()
print("All six monitors mapped.")
