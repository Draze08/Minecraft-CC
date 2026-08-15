-- ============================================================
-- RuffHouse Lift Commissioning Tool V3
-- CC:Tweaked + CC:LiftLink
--
-- Configures:
--   - Shaft ID
--   - Create landing identity (Y)
--   - Create short/long labels
--   - Landing monitor
--   - Landing speaker
--
-- Monitor + speaker commissioning mechanics are preserved from
-- the known-good V1.3/V2 workflow.
--
-- Create/LiftLink owns landing topology and naming.
-- Physical Y is the durable landing identity.
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


-- ============================================================
-- General utilities
-- ============================================================

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
    mon.setCursorPos(
        math.max(1, x),
        y or math.ceil(h / 2)
    )
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

    centerText(
        mon,
        text,
        math.ceil(h / 2),
        colour
    )
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

        local input = string.upper(read())

        if input == "A"
        or input == "B"
        or input == "C"
        or input == "D" then
            return input
        end

        print()
        print("Invalid shaft.")
        sleep(1.5)
    end
end


-- ============================================================
-- Peripheral discovery
-- ============================================================

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

        if peripheral.hasType(
            name,
            "create_elevator"
        ) then

            local elevator =
                peripheral.wrap(name)

            local ok, floors =
                pcall(elevator.listFloors)

            if ok
            and type(floors) == "table"
            and #floors > 0 then

                return name, elevator
            end
        end
    end

    return nil, nil
end


local function getCreateLandings(elevator)

    local floors =
        elevator.listFloors()

    local landings = {}

    for _, info in ipairs(floors) do

        if type(info.y) ~= "number" then
            error(
                "LiftLink landing has no numeric Y coordinate."
            )
        end

        landings[#landings + 1] = {
            y = info.y,
            shortName = tostring(
                info.shortName
                or info.name
                or ""
            ),
            longName = tostring(
                info.longName
                or ""
            )
        }
    end

    table.sort(
        landings,
        function(a, b)
            return a.y < b.y
        end
    )

    return landings
end


local function landingTitle(index, landing)

    local title =
        landing.shortName

    if title == "" then
        title = "LANDING " .. index
    end

    if landing.longName ~= "" then
        title =
            title
            .. " | "
            .. landing.longName
    end

    return title
end


-- ============================================================
-- Monitor commissioning
-- V1.3 - preserved
-- ============================================================

local function commissionMonitor(
    floor,
    shaft,
    monitorNames,
    assignedMonitors,
    landing
)

    -- Display prompt on all currently unassigned monitors

    for _, name in ipairs(monitorNames) do

        if not assignedMonitors[name] then

            local mon = peripheral.wrap(name)

            showCentered(
                mon,
                "TOUCH " .. landing.shortName,
                colors.orange
            )

        end
    end


    clearTerminal()

    print("RuffHouse Lift Commissioning")
    print("============================")
    print()
    print("Shaft: " .. shaft)
    print("Landing: " .. landingTitle(floor, landing))
    print()
    print("MONITOR SETUP")
    print()
    print("Touch the landing monitor")
    print("for " .. landingTitle(floor, landing) .. ".")
    print()


    while true do

        local _, monitorName =
            os.pullEvent("monitor_touch")

        if not assignedMonitors[monitorName] then

            assignedMonitors[monitorName] = true

            local mon =
                peripheral.wrap(monitorName)

            showCentered(
                mon,
                landing.shortName .. " MONITOR OK",
                colors.lime
            )

            return monitorName

        end
    end
end


-- ============================================================
-- Speaker test screen
-- V1.3 - preserved
-- ============================================================

local function drawSpeakerTest(
    mon,
    floor,
    speakerName
)

    prepareMonitor(mon)

    local w, h = mon.getSize()

    centerText(
        mon,
        "FLOOR " .. floor,
        2,
        colors.white
    )

    centerText(
        mon,
        "SPEAKER TEST",
        4,
        colors.orange
    )

    centerText(
        mon,
        speakerName,
        6,
        colors.lightGray
    )

    -- Bottom controls

    mon.setTextColor(colors.red)
    mon.setCursorPos(2, h)
    mon.write("NO")

    local yesText = "YES"

    mon.setTextColor(colors.lime)
    mon.setCursorPos(
        math.max(1, w - #yesText),
        h
    )
    mon.write(yesText)
end


-- ============================================================
-- Test one speaker
-- V1.3 - preserved
-- ============================================================

local function testSpeaker(
    floor,
    monitorName,
    speakerName
)

    local mon =
        peripheral.wrap(monitorName)

    local speaker =
        peripheral.wrap(speakerName)

    drawSpeakerTest(
        mon,
        floor,
        speakerName
    )


    local decision = nil


    -- Repeatedly play the test tone

    local function soundLoop()

        while decision == nil do

            speaker.playNote(
                TEST_NOTE_INSTRUMENT,
                TEST_NOTE_VOLUME,
                TEST_NOTE_PITCH
            )

            sleep(TEST_NOTE_INTERVAL)

        end
    end


    -- Wait for a touch on THIS floor's monitor

    local function touchLoop()

        while decision == nil do

            local _, touchedMonitor, x =
                os.pullEvent("monitor_touch")

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


    parallel.waitForAny(
        soundLoop,
        touchLoop
    )


    speaker.stop()

    return decision
end


-- ============================================================
-- Speaker commissioning
-- V1.3 - preserved
-- ============================================================

local function commissionSpeaker(
    floor,
    shaft,
    monitorName,
    speakerNames,
    assignedSpeakers,
    landing
)

    clearTerminal()

    print("RuffHouse Lift Commissioning")
    print("============================")
    print()
    print("Shaft: " .. shaft)
    print("Landing: " .. landingTitle(floor, landing))
    print()
    print("SPEAKER SETUP")
    print()
    print("Stand beside the")
    print(landingTitle(floor, landing) .. " monitor.")
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

            local correct =
                testSpeaker(
                    floor,
                    monitorName,
                    speakerName
                )

            if correct then

                assignedSpeakers[speakerName] = true

                local mon =
                    peripheral.wrap(monitorName)

                showCentered(
                    mon,
                    landing.shortName .. " HARDWARE OK",
                    colors.lime
                )

                return speakerName

            end
        end
    end


    error(
        "No speaker assigned to landing "
        .. landingTitle(floor, landing)
    )
end


-- ============================================================
-- Save configuration
-- ============================================================

local function saveConfig(
    shaft,
    elevatorName,
    floors
)

    if not fs.exists(CONFIG_DIR) then
        fs.makeDir(CONFIG_DIR)
    end

    local config = {
        version = 3,
        shaft = shaft,
        elevator = elevatorName,
        floors = floors
    }

    local file =
        fs.open(CONFIG_FILE, "w")

    if not file then
        error(
            "Unable to open "
            .. CONFIG_FILE
        )
    end

    file.write(
        "return "
        .. textutils.serialize(config)
    )

    file.close()
end

-- ============================================================
-- MAIN
-- ============================================================

local shaft = selectShaft()

local elevatorName,
      elevator =
    discoverElevator()

if not elevator then
    error(
        "No CC:LiftLink create_elevator peripheral found."
    )
end

local createLandings =
    getCreateLandings(elevator)

local FLOOR_COUNT =
    #createLandings

local monitorNames =
    discoverPeripheralType("monitor")

local speakerNames =
    discoverPeripheralType("speaker")


clearTerminal()

print("RuffHouse Lift Commissioning")
print("============================")
print()
print("Shaft: " .. shaft)
print("Elevator: " .. elevatorName)
print("Create landings: " .. FLOOR_COUNT)
print()

print(
    "Monitors: "
    .. #monitorNames
    .. "/"
    .. FLOOR_COUNT
)

print(
    "Speakers: "
    .. #speakerNames
    .. "/"
    .. FLOOR_COUNT
)

print()


-- ============================================================
-- Hardware validation
-- ============================================================

if #monitorNames ~= FLOOR_COUNT then

    print("ERROR")
    print()

    print(
        "Expected "
        .. FLOOR_COUNT
        .. " monitors."
    )

    print(
        "Found "
        .. #monitorNames
        .. "."
    )

    return
end


if #speakerNames ~= FLOOR_COUNT then

    print("ERROR")
    print()

    print(
        "Expected "
        .. FLOOR_COUNT
        .. " speakers."
    )

    print(
        "Found "
        .. #speakerNames
        .. "."
    )

    return
end


print("Hardware count OK.")
sleep(1.5)


-- ============================================================
-- Commission floors
--
-- PRESERVED workflow:
--
-- F1 monitor -> F1 speaker
-- F2 monitor -> F2 speaker
-- ...
-- F6 monitor -> F6 speaker
-- ============================================================

local floors = {}

local assignedMonitors = {}
local assignedSpeakers = {}


for floor = 1, FLOOR_COUNT do

    local landing =
        createLandings[floor]

    local monitorName =
        commissionMonitor(
            floor,
            shaft,
            monitorNames,
            assignedMonitors,
            landing
        )

    local speakerName =
        commissionSpeaker(
            floor,
            shaft,
            monitorName,
            speakerNames,
            assignedSpeakers,
            landing
        )

    floors[floor] = {
        y = landing.y,
        shortName = landing.shortName,
        longName = landing.longName,
        monitor = monitorName,
        speaker = speakerName
    }

    local mon =
        peripheral.wrap(monitorName)

    showCentered(
        mon,
        landing.shortName .. " OK",
        colors.lime
    )

    sleep(1.0)

    if floor < FLOOR_COUNT then

        showCentered(
            mon,
            "NEXT: " .. createLandings[floor + 1].shortName,
            colors.orange
        )

    else

        prepareMonitor(mon)

        local _, h = mon.getSize()

        centerText(
            mon,
            "MON + AUDIO COMPLETE",
            math.max(1, math.ceil(h / 2) - 1),
            colors.lime
        )

        centerText(
            mon,
            "RETURN TO " .. createLandings[1].shortName,
            math.min(h, math.ceil(h / 2) + 1),
            colors.orange
        )
    end
end


-- ============================================================
-- Save
-- ============================================================

saveConfig(
    shaft,
    elevatorName,
    floors
)


-- ============================================================
-- Final displays
-- ============================================================

for floor = 1, FLOOR_COUNT do

    local mon =
        peripheral.wrap(
            floors[floor].monitor
        )

    showCentered(
        mon,
        floors[floor].shortName,
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
        "Landing "
        .. floor
        .. ": "
        .. landingTitle(
            floor,
            floors[floor]
        )
    )

    print(
        "  Y: "
        .. floors[floor].y
    )

    print(
        "  Monitor: "
        .. floors[floor].monitor
    )

    print(
        "  Speaker: "
        .. floors[floor].speaker
    )
end

print()
print("Configuration saved:")
print(CONFIG_FILE)
print()
print("All landing HMI hardware mapped.")
