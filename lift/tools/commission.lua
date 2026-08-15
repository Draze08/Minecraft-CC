-- ============================================================
-- RuffHouse Lift Commissioning Tool v3.5
-- CC:Tweaked
--
-- Configures:
--   - Shaft ID
--   - Floor monitor
--   - Floor speaker
--   - Floor arrival/status relay
--
-- Monitor + speaker commissioning is the original known-good
-- Mk1 implementation.
--
-- Status relay commissioning is performed AFTER all six
-- monitor/speaker pairs have been commissioned.
--
-- Saves:
--   /lift/config.lua
-- ============================================================

local FLOOR_COUNT = 6

local CONFIG_DIR = "/lift"
local CONFIG_FILE = "/lift/config.lua"

-- ORIGINAL MK1 SPEAKER SETTINGS
local TEST_NOTE_INTERVAL = 0.75
local TEST_NOTE_INSTRUMENT = "bell"
local TEST_NOTE_VOLUME = 1
local TEST_NOTE_PITCH = 12

-- Status relay detection
local ARRIVAL_HOLD_TIME = 1.0
local RELAY_POLL_INTERVAL = 0.05


-- ============================================================
-- General utilities
-- ============================================================

local function clearTerminal()

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

end


local function centerText(
    mon,
    text,
    y,
    colour
)

    local w, h = mon.getSize()

    local x =
        math.floor(
            (w - #text) / 2
        ) + 1

    mon.setTextColor(
        colour or colors.white
    )

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


local function showCentered(
    mon,
    text,
    colour
)

    prepareMonitor(mon)

    local _, h =
        mon.getSize()

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

        local input =
            string.upper(read())

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

local function discoverPeripheralType(
    targetType
)

    local results = {}

    for _, name
        in ipairs(peripheral.getNames()) do

        if peripheral.getType(name)
            == targetType then

            table.insert(
                results,
                name
            )

        end

    end

    table.sort(results)

    return results

end


-- ============================================================
-- Monitor commissioning
--
-- ORIGINAL MK1
-- ============================================================

local function commissionMonitor(
    floor,
    shaft,
    monitorNames,
    assignedMonitors
)

    -- Display prompt on all currently unassigned monitors

    for _, name
        in ipairs(monitorNames) do

        if not assignedMonitors[name] then

            local mon =
                peripheral.wrap(name)

            showCentered(
                mon,
                "TOUCH FOR F" .. floor,
                colors.orange
            )

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

        local _, monitorName =
            os.pullEvent(
                "monitor_touch"
            )

        if not assignedMonitors[
            monitorName
        ] then

            assignedMonitors[
                monitorName
            ] = true

            local mon =
                peripheral.wrap(
                    monitorName
                )

            showCentered(
                mon,
                "F" .. floor .. " MONITOR OK",
                colors.lime
            )

            return monitorName

        end

    end

end


-- ============================================================
-- Speaker test screen
--
-- ORIGINAL MK1
-- ============================================================

local function drawSpeakerTest(
    mon,
    floor,
    speakerName
)

    prepareMonitor(mon)

    local w, h =
        mon.getSize()

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

    mon.setTextColor(
        colors.red
    )

    mon.setCursorPos(
        2,
        h
    )

    mon.write("NO")

    local yesText = "YES"

    mon.setTextColor(
        colors.lime
    )

    mon.setCursorPos(
        math.max(
            1,
            w - #yesText
        ),
        h
    )

    mon.write(yesText)

end


-- ============================================================
-- Test one speaker
--
-- ORIGINAL MK1
-- ============================================================

local function testSpeaker(
    floor,
    monitorName,
    speakerName
)

    local mon =
        peripheral.wrap(
            monitorName
        )

    local speaker =
        peripheral.wrap(
            speakerName
        )

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

            sleep(
                TEST_NOTE_INTERVAL
            )

        end

    end


    -- Wait for a touch on THIS floor's monitor

    local function touchLoop()

        while decision == nil do

            local _,
                  touchedMonitor,
                  x =
                os.pullEvent(
                    "monitor_touch"
                )

            if touchedMonitor
                == monitorName then

                local w, _ =
                    mon.getSize()

                if x
                    <= math.floor(
                        w / 2
                    ) then

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
--
-- ORIGINAL MK1
-- ============================================================

local function commissionSpeaker(
    floor,
    shaft,
    monitorName,
    speakerNames,
    assignedSpeakers
)

    clearTerminal()

    print("RuffHouse Lift Commissioning")
    print("============================")
    print()

    print("Shaft: " .. shaft)
    print("Floor: " .. floor)
    print()

    print("SPEAKER SETUP")
    print()

    print(
        "Stand beside the Floor "
        .. floor
    )

    print("monitor.")
    print()

    print("A speaker will repeatedly")
    print("play a test tone.")
    print()

    print("Tap:")
    print("  LEFT  = wrong speaker")
    print("  RIGHT = correct speaker")
    print()


    for _, speakerName
        in ipairs(speakerNames) do

        if not assignedSpeakers[
            speakerName
        ] then

            local correct =
                testSpeaker(
                    floor,
                    monitorName,
                    speakerName
                )

            if correct then

                assignedSpeakers[
                    speakerName
                ] = true

                local mon =
                    peripheral.wrap(
                        monitorName
                    )

                showCentered(
                    mon,
                    "F"
                    .. floor
                    .. " HARDWARE OK",
                    colors.lime
                )

                return speakerName

            end

        end

    end


    error(
        "No speaker assigned to Floor "
        .. floor
    )

end


-- ============================================================
-- Status monitor screens
-- ============================================================

local function drawStatusCallPrompt(
    mon,
    floor
)

    prepareMonitor(mon)

    local _, h =
        mon.getSize()

    centerText(
        mon,
        "FLOOR " .. floor,
        math.max(
            1,
            math.floor(h / 2) - 1
        ),
        colors.white
    )

    centerText(
        mon,
        "PUSH CALL BUTTON",
        math.min(
            h,
            math.floor(h / 2) + 1
        ),
        colors.orange
    )

end


local function drawStatusWaiting(
    mon,
    floor
)

    prepareMonitor(mon)

    local _, h =
        mon.getSize()

    centerText(
        mon,
        "FLOOR " .. floor,
        math.max(
            1,
            math.floor(h / 2) - 1
        ),
        colors.white
    )

    centerText(
        mon,
        "WAITING FOR LIFT",
        math.min(
            h,
            math.floor(h / 2) + 1
        ),
        colors.orange
    )

end


local function drawStatusOK(
    mon,
    floor
)

    prepareMonitor(mon)

    local _, h =
        mon.getSize()

    centerText(
        mon,
        "FLOOR " .. floor,
        math.max(
            1,
            math.floor(h / 2) - 1
        ),
        colors.white
    )

    centerText(
        mon,
        "STATUS OK",
        math.min(
            h,
            math.floor(h / 2) + 1
        ),
        colors.lime
    )

end


-- ============================================================
-- Relay helpers
-- ============================================================

local relaySides = {
    "top",
    "bottom",
    "left",
    "right",
    "front",
    "back"
}


local function relayActive(
    relayName
)

    local relay =
        peripheral.wrap(
            relayName
        )

    if not relay then
        return false
    end


    for _, side
        in ipairs(relaySides) do

        local ok,
              value =
            pcall(
                function()

                    return relay.getInput(
                        side
                    )

                end
            )

        if ok and value then
            return true
        end

    end


    return false

end


-- ============================================================
-- Commission one floor's status relay
--
-- IMPORTANT:
--
-- Previously assigned relays are ignored completely.
--
-- A floor relay may remain HIGH while the lift is parked
-- there. Therefore we DO NOT wait for the previous floor's
-- relay to release before advancing.
--
-- An unassigned relay must remain HIGH for at least
-- ARRIVAL_HOLD_TIME before being accepted.
--
-- Shorter signals are treated as pass-by events.
-- ============================================================

local function commissionStatusRelay(
    floor,
    shaft,
    monitorName,
    relayNames,
    assignedRelays
)

    local mon =
        peripheral.wrap(
            monitorName
        )


    clearTerminal()

    print("RuffHouse Lift Commissioning")
    print("============================")
    print()

    print("Shaft: " .. shaft)
    print("Floor: " .. floor)
    print()

    print("STATUS RELAY SETUP")
    print()

    print("At Floor " .. floor .. ":")
    print()

    print(
        "1. Push the physical call button."
    )

    print(
        "2. Press ENTER on this computer."
    )

    print()

    print(
        "Signals shorter than "
        .. string.format(
            "%.1f",
            ARRIVAL_HOLD_TIME
        )
        .. "s are treated as PASS."
    )

    print()

    print("Status detector ready.")


    drawStatusCallPrompt(
        mon,
        floor
    )


    -- --------------------------------------------------------
    -- User physically calls the lift, then arms detection
    -- from the computer.
    -- --------------------------------------------------------

    term.setTextColor(
        colors.yellow
    )

    print()
    print(
        "Press ENTER after calling lift."
    )

    term.setTextColor(
        colors.white
    )


    while true do

        local _, key =
            os.pullEvent("key")

        if key == keys.enter then
            break
        end

    end


    drawStatusWaiting(
        mon,
        floor
    )


    print()
    print("Watching relays...")
    print()


    -- --------------------------------------------------------
    -- Track how long each currently-unassigned relay
    -- remains active.
    -- --------------------------------------------------------

    local activeSince = {}

    local acceptedRelay = nil

    local acceptedDuration = nil


    while acceptedRelay == nil do

        for _, relayName
            in ipairs(relayNames) do

            -- Already-mapped relays are deliberately ignored.

            if not assignedRelays[
                relayName
            ] then

                local active =
                    relayActive(
                        relayName
                    )


                if active then

                    -- First observation of HIGH.

                    if not activeSince[
                        relayName
                    ] then

                        activeSince[
                            relayName
                        ] = os.clock()

                    end


                    local duration =
                        os.clock()
                        - activeSince[
                            relayName
                        ]


                    -- Sustained HIGH = stopped/arrived.

                    if duration
                        >= ARRIVAL_HOLD_TIME then

                        acceptedRelay =
                            relayName

                        acceptedDuration =
                            duration

                        break

                    end


                else

                    -- If it was HIGH but released before the
                    -- threshold, record it as a pass-by.

                    if activeSince[
                        relayName
                    ] then

                        local duration =
                            os.clock()
                            - activeSince[
                                relayName
                            ]

                        term.setTextColor(
                            colors.lightGray
                        )

                        print(
                            relayName
                            .. "  "
                            .. string.format(
                                "%.2f",
                                duration
                            )
                            .. "s  PASS"
                        )

                        term.setTextColor(
                            colors.white
                        )

                        activeSince[
                            relayName
                        ] = nil

                    end

                end

            end

        end


        if acceptedRelay == nil then

            sleep(
                RELAY_POLL_INTERVAL
            )

        end

    end


    -- --------------------------------------------------------
    -- Arrival confirmed.
    --
    -- Mark this relay assigned IMMEDIATELY.
    --
    -- DO NOT wait for it to go LOW.
    --
    -- It may legitimately stay HIGH while the lift remains
    -- parked at this floor.
    -- --------------------------------------------------------

    assignedRelays[
        acceptedRelay
    ] = true


    term.setTextColor(
        colors.lime
    )

    print()
    print("ARRIVAL DETECTED")
    print()

    print(
        acceptedRelay
        .. " >= "
        .. string.format(
            "%.2f",
            acceptedDuration
        )
        .. "s"
    )

    term.setTextColor(
        colors.white
    )


    drawStatusOK(
        mon,
        floor
    )


    sleep(0.8)


    return acceptedRelay

end


-- ============================================================
-- Save configuration
-- ============================================================

local function saveConfig(
    shaft,
    floors
)

    if not fs.exists(
        CONFIG_DIR
    ) then

        fs.makeDir(
            CONFIG_DIR
        )

    end


    local file =
        fs.open(
            CONFIG_FILE,
            "w"
        )


    if not file then

        error(
            "Unable to open "
            .. CONFIG_FILE
        )

    end


    file.writeLine(
        "return {"
    )

    file.writeLine(
        '    shaft = "'
        .. shaft
        .. '",'
    )

    file.writeLine(
        "    arrivalHoldTime = "
        .. tostring(
            ARRIVAL_HOLD_TIME
        )
        .. ","
    )

    file.writeLine("")

    file.writeLine(
        "    floors = {"
    )


    for floor = 1, FLOOR_COUNT do

        file.writeLine(
            "        ["
            .. floor
            .. "] = {"
        )

        file.writeLine(
            '            monitor = "'
            .. floors[
                floor
            ].monitor
            .. '",'
        )

        file.writeLine(
            '            speaker = "'
            .. floors[
                floor
            ].speaker
            .. '",'
        )

        file.writeLine(
            '            statusRelay = "'
            .. floors[
                floor
            ].statusRelay
            .. '",'
        )

        file.writeLine(
            "        },"
        )

    end


    file.writeLine(
        "    }"
    )

    file.writeLine(
        "}"
    )

    file.close()

end


-- ============================================================
-- MAIN
-- ============================================================

local shaft =
    selectShaft()


local monitorNames =
    discoverPeripheralType(
        "monitor"
    )


local speakerNames =
    discoverPeripheralType(
        "speaker"
    )


local relayNames =
    discoverPeripheralType(
        "redstone_relay"
    )


clearTerminal()

print("RuffHouse Lift Commissioning")
print("============================")
print()

print(
    "Shaft: "
    .. shaft
)

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

print(
    "Relays:   "
    .. #relayNames
    .. "/"
    .. FLOOR_COUNT
)

print()


-- ============================================================
-- Hardware validation
-- ============================================================

if #monitorNames
    ~= FLOOR_COUNT then

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


if #speakerNames
    ~= FLOOR_COUNT then

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


if #relayNames
    ~= FLOOR_COUNT then

    print("ERROR")
    print()

    print(
        "Expected "
        .. FLOOR_COUNT
        .. " redstone relays."
    )

    print(
        "Found "
        .. #relayNames
        .. "."
    )

    return

end


print("Hardware count OK.")

sleep(1.5)


-- ============================================================
-- Commission monitor + speaker pairs
--
-- ORIGINAL MK1 ORDER:
--
-- Floor 1 monitor
-- Floor 1 speaker
--
-- Floor 2 monitor
-- Floor 2 speaker
--
-- etc.
-- ============================================================

local floors = {}

local assignedMonitors = {}
local assignedSpeakers = {}


for floor = 1, FLOOR_COUNT do

    -- --------------------------------------------------------
    -- Identify this floor's monitor
    -- --------------------------------------------------------

    local monitorName =
        commissionMonitor(
            floor,
            shaft,
            monitorNames,
            assignedMonitors
        )


    -- --------------------------------------------------------
    -- Identify this floor's speaker
    -- --------------------------------------------------------

    local speakerName =
        commissionSpeaker(
            floor,
            shaft,
            monitorName,
            speakerNames,
            assignedSpeakers
        )


    -- --------------------------------------------------------
    -- Store floor hardware
    -- --------------------------------------------------------

    floors[floor] = {

        monitor =
            monitorName,

        speaker =
            speakerName

    }


    -- --------------------------------------------------------
    -- Confirmation
    -- --------------------------------------------------------

    local mon =
        peripheral.wrap(
            monitorName
        )

    showCentered(
        mon,
        "FLOOR "
        .. floor
        .. " OK",
        colors.lime
    )

    sleep(0.5)

end


-- ============================================================
-- Status relay commissioning
--
-- This begins ONLY after the original monitor/speaker pass
-- has completed successfully for all six floors.
-- ============================================================

local assignedRelays = {}


for floor = 1, FLOOR_COUNT do

    local relayName =
        commissionStatusRelay(
            floor,
            shaft,
            floors[
                floor
            ].monitor,
            relayNames,
            assignedRelays
        )

    floors[
        floor
    ].statusRelay =
        relayName

end


-- ============================================================
-- Save
-- ============================================================

saveConfig(
    shaft,
    floors
)


-- ============================================================
-- Final displays
-- ============================================================

for floor = 1, FLOOR_COUNT do

    local mon =
        peripheral.wrap(
            floors[
                floor
            ].monitor
        )

    showCentered(
        mon,
        "FLOOR "
        .. floor
        .. " OK",
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

print(
    "Lift Shaft: "
    .. shaft
)

print()


for floor = 1, FLOOR_COUNT do

    print(
        "Floor "
        .. floor
    )

    print(
        "  Monitor: "
        .. floors[
            floor
        ].monitor
    )

    print(
        "  Speaker: "
        .. floors[
            floor
        ].speaker
    )

    print(
        "  Status:  "
        .. floors[
            floor
        ].statusRelay
    )

    print()

end


print()

print(
    "Configuration saved:"
)

print(
    CONFIG_FILE
)

print()

print(
    "All landing hardware mapped."
)
