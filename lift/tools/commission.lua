-- ============================================================
-- RuffHouse Lift Commissioning Tool - Create / CC:LiftLink
--
-- Create owns landing topology and naming.
-- Commissioning maps each Create landing to one monitor + speaker.
--
-- Durable landing identity:
--   Y coordinate from create_elevator.listFloors()
--
-- Cached presentation metadata:
--   shortName
--   longName
--
-- Preserves the known-good V1.3 interaction workflow:
--   landing monitor -> landing speaker -> next landing
--
-- Saves:
--   /lift/config.lua
-- ============================================================

local CONFIG_DIR = "/lift"
local CONFIG_FILE = "/lift/config.lua"

local TEST_NOTE_INTERVAL = 0.75
local TEST_NOTE_INSTRUMENT = "bell"
local TEST_NOTE_VOLUME = 1
local TEST_NOTE_PITCH = 12

local function clearTerminal()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function centerText(mon, text, y, colour)
    local w, h = mon.getSize()
    local x = math.floor((w - #text) / 2) + 1
    mon.setTextColor(colour or colors.white)
    mon.setCursorPos(math.max(1, x), y or math.ceil(h / 2))
    mon.write(text)
end

local function prepareMonitor(mon)
    mon.setTextScale(1)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
end

local function showCentered(mon, text, colour)
    prepareMonitor(mon)
    local _, h = mon.getSize()
    centerText(mon, text, math.ceil(h / 2), colour)
end

local function drawTwoLineStatusPrompt(mon, floor, line1, line2, colour1, colour2)
    prepareMonitor(mon)
    local _, h = mon.getSize()
    local centre = math.ceil(h / 2)
    centerText(mon, "FLOOR " .. floor, math.max(1, centre - 2), colors.white)
    centerText(mon, line1, centre, colour1 or colors.orange)
    centerText(mon, line2, math.min(h, centre + 2), colour2 or colors.orange)
end

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
        local input = string.upper(read())
        if input == "A" or input == "B" or input == "C" or input == "D" then
            return input
        end
        print()
        print("Invalid shaft.")
        sleep(1.5)
    end
end

local function discoverPeripheralType(targetType)
    local results = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == targetType then
            table.insert(results, name)
        end
    end
    table.sort(results)
    return results
end

local function discoverElevator()
    local names = peripheral.getNames()
    table.sort(names)
    for _, name in ipairs(names) do
        if peripheral.hasType(name, "create_elevator") then
            local elevator = peripheral.wrap(name)
            local ok, floors = pcall(elevator.listFloors)
            if ok and type(floors) == "table" and #floors > 0 then
                return name, elevator
            end
        end
    end
    return nil, nil
end

local function getCreateLandings(elevator)
    local createFloors = elevator.listFloors()
    local landings = {}
    for _, info in ipairs(createFloors) do
        if type(info.y) ~= "number" then
            error("LiftLink landing has no numeric Y coordinate.")
        end
        landings[#landings + 1] = {
            y = info.y,
            shortName = tostring(info.shortName or info.name or ""),
            longName = tostring(info.longName or "")
        }
    end

    -- Commissioning starts at the top landing and proceeds downward,
    -- matching the preserved V1.3 Floor 1 -> Floor N workflow.
    -- Highest Y = commissioning Floor 1, lowest Y = Floor N.
    table.sort(landings, function(a, b)
        return a.y > b.y
    end)

    return landings
end

local function commissionMonitor(floor, shaft, monitorNames, assignedMonitors)
    for _, name in ipairs(monitorNames) do
        if not assignedMonitors[name] then
            local mon = peripheral.wrap(name)
            showCentered(mon, "TOUCH FOR F" .. floor, colors.orange)
        end
    end

    clearTerminal()
    print("RuffHouse Lift Commissioning")
    print("============================")
    print()
    print("Shaft: " .. shaft)
    print("Floor: " .. floor)
    print()
    print("MONITOR SETUP")
    print()
    print("Touch the landing monitor")
    print("on Floor " .. floor .. ".")
    print()

    while true do
        local _, monitorName = os.pullEvent("monitor_touch")
        if not assignedMonitors[monitorName] then
            assignedMonitors[monitorName] = true
            local mon = peripheral.wrap(monitorName)
            showCentered(mon, "F" .. floor .. " MONITOR OK", colors.lime)
            return monitorName
        end
    end
end

local function drawSpeakerTest(mon, floor, speakerName)
    prepareMonitor(mon)
    local w, h = mon.getSize()
    centerText(mon, "FLOOR " .. floor, 2, colors.white)
    centerText(mon, "SPEAKER TEST", 4, colors.orange)
    centerText(mon, speakerName, 6, colors.lightGray)
    mon.setTextColor(colors.red)
    mon.setCursorPos(2, h)
    mon.write("NO")
    local yesText = "YES"
    mon.setTextColor(colors.lime)
    mon.setCursorPos(math.max(1, w - #yesText), h)
    mon.write(yesText)
end

local function testSpeaker(floor, monitorName, speakerName)
    local mon = peripheral.wrap(monitorName)
    local speaker = peripheral.wrap(speakerName)
    drawSpeakerTest(mon, floor, speakerName)
    local decision = nil

    local function soundLoop()
        while decision == nil do
            speaker.playNote(TEST_NOTE_INSTRUMENT, TEST_NOTE_VOLUME, TEST_NOTE_PITCH)
            sleep(TEST_NOTE_INTERVAL)
        end
    end

    local function touchLoop()
        while decision == nil do
            local _, touchedMonitor, x = os.pullEvent("monitor_touch")
            if touchedMonitor == monitorName then
                local w, _ = mon.getSize()
                if x <= math.floor(w / 2) then
                    decision = false
                else
                    decision = true
                end
                return
            end
        end
    end

    parallel.waitForAny(soundLoop, touchLoop)
    speaker.stop()
    return decision
end

local function commissionSpeaker(floor, shaft, monitorName, speakerNames, assignedSpeakers)
    clearTerminal()
    print("RuffHouse Lift Commissioning")
    print("============================")
    print()
    print("Shaft: " .. shaft)
    print("Floor: " .. floor)
    print()
    print("SPEAKER SETUP")
    print()
    print("Stand beside the Floor " .. floor)
    print("monitor.")
    print()
    print("A speaker will repeatedly")
    print("play a test tone.")
    print()
    print("Tap:")
    print("  LEFT  = wrong speaker")
    print("  RIGHT = correct speaker")
    print()

    for _, speakerName in ipairs(speakerNames) do
        if not assignedSpeakers[speakerName] then
            local correct = testSpeaker(floor, monitorName, speakerName)
            if correct then
                assignedSpeakers[speakerName] = true
                local mon = peripheral.wrap(monitorName)
                showCentered(mon, "F" .. floor .. " HARDWARE OK", colors.lime)
                return speakerName
            end
        end
    end

    error("No speaker assigned to Floor " .. floor)
end

local function saveConfig(shaft, elevatorName, floors)
    if not fs.exists(CONFIG_DIR) then
        fs.makeDir(CONFIG_DIR)
    end

    local config = {
        version = 2,
        shaft = shaft,
        elevator = elevatorName,
        floors = floors
    }

    local file = fs.open(CONFIG_FILE, "w")
    if not file then
        error("Unable to open " .. CONFIG_FILE)
    end
    file.write("return " .. textutils.serialize(config))
    file.close()
end

local shaft = selectShaft()
local elevatorName, elevator = discoverElevator()

if not elevator then
    error("No CC:LiftLink create_elevator peripheral found.")
end

local createLandings = getCreateLandings(elevator)
local FLOOR_COUNT = #createLandings
local monitorNames = discoverPeripheralType("monitor")
local speakerNames = discoverPeripheralType("speaker")

clearTerminal()
print("RuffHouse Lift Commissioning")
print("============================")
print()
print("Shaft: " .. shaft)
print("Elevator: " .. elevatorName)
print("Create landings: " .. FLOOR_COUNT)
print()
print("Monitors: " .. #monitorNames .. "/" .. FLOOR_COUNT)
print("Speakers: " .. #speakerNames .. "/" .. FLOOR_COUNT)
print()

if #monitorNames ~= FLOOR_COUNT then
    print("ERROR")
    print()
    print("Expected " .. FLOOR_COUNT .. " monitors.")
    print("Found " .. #monitorNames .. ".")
    return
end

if #speakerNames ~= FLOOR_COUNT then
    print("ERROR")
    print()
    print("Expected " .. FLOOR_COUNT .. " speakers.")
    print("Found " .. #speakerNames .. ".")
    return
end

print("Hardware count OK.")
sleep(1.5)

local floors = {}
local assignedMonitors = {}
local assignedSpeakers = {}

for floor = 1, FLOOR_COUNT do
    local landing = createLandings[floor]
    local monitorName = commissionMonitor(floor, shaft, monitorNames, assignedMonitors)
    local speakerName = commissionSpeaker(floor, shaft, monitorName, speakerNames, assignedSpeakers)

    floors[floor] = {
        y = landing.y,
        shortName = landing.shortName,
        longName = landing.longName,
        monitor = monitorName,
        speaker = speakerName
    }

    local mon = peripheral.wrap(monitorName)
    showCentered(mon, "FLOOR " .. floor .. " OK", colors.lime)
    sleep(1.0)

    if floor < FLOOR_COUNT then
        showCentered(mon, "PROCEED TO F" .. (floor + 1), colors.orange)
    else
        drawTwoLineStatusPrompt(
            mon,
            floor,
            "MON + AUDIO COMPLETE",
            "RETURN TO FLOOR 1",
            colors.lime,
            colors.orange
        )
    end
end

saveConfig(shaft, elevatorName, floors)

for floor = 1, FLOOR_COUNT do
    local mon = peripheral.wrap(floors[floor].monitor)
    showCentered(mon, "FLOOR " .. floor, colors.lime)
end

clearTerminal()
print("Commissioning Complete")
print("======================")
print()
print("Lift Shaft: " .. shaft)
print("Elevator: " .. elevatorName)
print()

for floor = 1, FLOOR_COUNT do
    print("Floor " .. floor)
    print("  Y:       " .. floors[floor].y)
    print("  Name:    " .. floors[floor].shortName .. " | " .. floors[floor].longName)
    print("  Monitor: " .. floors[floor].monitor)
    print("  Speaker: " .. floors[floor].speaker)
end

print()
print("Configuration saved:")
print(CONFIG_FILE)
print()
print("All Create landing monitor/audio hardware mapped.")