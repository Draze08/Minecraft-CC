-- Saves:
--   /lift/config.lua
-- ============================================================

local FLOOR_COUNT = 6

local CONFIG_DIR = "/lift"
local CONFIG_FILE = "/lift/config.lua"

local TEST_NOTE_INTERVAL = 0.75
local TEST_NOTE_INSTRUMENT = "bell"
local TEST_NOTE_VOLUME = 1
local TEST_NOTE_PITCH = 12

-- Added for redstone commissioning
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

-- ============================================================
-- Monitor commissioning
-- V1.3 - preserved
-- ============================================================

local function commissionMonitor(
floor,
shaft,
monitorNames,
assignedMonitors
)

-- Display prompt on all currently unassigned monitors

for _, name in ipairs(monitorNames) do

    if not assignedMonitors[name] then

        local mon = peripheral.wrap(name)

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
        os.pullEvent("monitor_touch")

    if not assignedMonitors[monitorName] then

        assignedMonitors[monitorName] = true

        local mon =
            peripheral.wrap(monitorName)

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
                "F" .. floor .. " HARDWARE OK",
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

-- One physical floor-button press commissions BOTH:

-- Relays already HIGH when a floor test begins are ignored
-- until they first return LOW. This prevents the lift's
-- current parked-floor status relay being mistaken for either
-- the call relay or the destination status relay.
-- ============================================================

local RELAY_SIDES = {
"top",
"bottom",
"left",
"right",
"front",
"back"
}

local function relayActive(relayName)

local relay = peripheral.wrap(relayName)

if not relay then
    return false
end

for _, side in ipairs(RELAY_SIDES) do

    local ok, value =
        pcall(
            relay.getInput,
            side
        )

    if ok and value then
        return true
    end
end

return false

end

local function drawStatusPrompt(
mon,
floor,
message,
colour
)

prepareMonitor(mon)

local _, h = mon.getSize()

centerText(
    mon,
    "FLOOR " .. floor,
    math.max(
        1,
        math.ceil(h / 2) - 1
    ),
    colors.white
)

centerText(
    mon,
    message,
    math.min(
        h,
        math.ceil(h / 2) + 1
    ),
    colour or colors.orange
)

end

local function drawTwoLineStatusPrompt(
mon,
floor,
line1,
line2,
colour1,
colour2
)

prepareMonitor(mon)

local _, h = mon.getSize()
local centre = math.ceil(h / 2)

centerText(
    mon,
    "FLOOR " .. floor,
    math.max(1, centre - 2),
    colors.white
)

centerText(
    mon,
    line1,
    centre,
    colour1 or colors.orange
)

centerText(
    mon,
    line2,
    math.min(h, centre + 2),
    colour2 or colors.orange
)

end

local function commissionFloorRelays(
floor,
shaft,
monitorName,
relayNames,
assignedRelays
)

local mon =
    peripheral.wrap(monitorName)


clearTerminal()

print("RuffHouse Lift Commissioning")
print("============================")
print()
print("Shaft: " .. shaft)
print("Floor: " .. floor)
print()
print("CALL + STATUS RELAY SETUP")
print()
print("Push the physical Floor " .. floor)
print("call button.")
print()
print(
    "Status signals under "
    .. ARRIVAL_HOLD_TIME
    .. "s are treated as PASS."
)
print()


-- --------------------------------------------------------
-- Snapshot relays which are already HIGH.
--
-- The lift may be parked at a floor when this phase starts.
-- Those signals are ignored until they return LOW.
-- --------------------------------------------------------

local ignoreUntilLow = {}

for _, relayName in ipairs(relayNames) do

    if not assignedRelays[relayName]
    and relayActive(relayName) then

        ignoreUntilLow[relayName] = true
    end
end


-- Detection is live BEFORE the prompt is shown.

local callRelay = nil
local statusRelay = nil
local statusDuration = nil

local activeSince = {}
local wasActive = {}


drawStatusPrompt(
    mon,
    floor,
    "PUSH CALL BUTTON",
    colors.orange
)


print("Watching call + status relays...")
print()


while statusRelay == nil do

    for _, relayName in ipairs(relayNames) do

        if not assignedRelays[relayName] then

            local active =
                relayActive(relayName)


            -- ------------------------------------------------
            -- Relay was already HIGH when this floor test began.
            -- Ignore it completely until it first returns LOW.
            -- ------------------------------------------------

            if ignoreUntilLow[relayName] then

                if not active then

                    ignoreUntilLow[relayName] = nil
                    wasActive[relayName] = false
                    activeSince[relayName] = nil
                end


            else

                -- ---------------------------------------------
                -- NEW rising edge
                -- ---------------------------------------------

                if active
                and not wasActive[relayName] then

                    wasActive[relayName] = true
                    activeSince[relayName] = os.clock()


                    -- The first NEW relay activation after the
                    -- prompt is the physical call-button signal.

                    if callRelay == nil then

                        callRelay = relayName

                        term.setTextColor(colors.lime)
                        print(
                            "CALL DETECTED: "
                            .. callRelay
                        )
                        term.setTextColor(colors.white)


                        drawTwoLineStatusPrompt(
                            mon,
                            floor,
                            "CALL OK",
                            "WAITING FOR LIFT",
                            colors.lime,
                            colors.orange
                        )
                    end
                end


                -- ---------------------------------------------
                -- Active status candidate
                --
                -- The call relay is excluded from status
                -- detection after it has been identified.
                -- ---------------------------------------------

                if active
                and relayName ~= callRelay
                and activeSince[relayName] then

                    local duration =
                        os.clock()
                        - activeSince[relayName]


                    if duration >= ARRIVAL_HOLD_TIME then

                        statusRelay = relayName
                        statusDuration = duration
                        break
                    end
                end


                -- ---------------------------------------------
                -- Falling edge
                -- ---------------------------------------------

                if not active
                and wasActive[relayName] then

                    local duration = 0

                    if activeSince[relayName] then

                        duration =
                            os.clock()
                            - activeSince[relayName]
                    end


                    if relayName ~= callRelay
                    and duration < ARRIVAL_HOLD_TIME then

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
                    end


                    wasActive[relayName] = false
                    activeSince[relayName] = nil
                end
            end
        end
    end


    if statusRelay == nil then

        sleep(
            RELAY_POLL_INTERVAL
        )
    end
end


-- --------------------------------------------------------
-- Both mappings must exist and must be different.
-- --------------------------------------------------------

if callRelay == nil then

    error(
        "Status detected for Floor "
        .. floor
        .. " before a call relay was captured."
    )
end


if callRelay == statusRelay then

    error(
        "Call and status relay resolved to the same peripheral "
        .. callRelay
    )
end


assignedRelays[callRelay] = true
assignedRelays[statusRelay] = true


term.setTextColor(colors.lime)

print()
print("CALL + STATUS DETECTED")
print()
print("Call:   " .. callRelay)

print(
    "Status: "
    .. statusRelay
    .. " >= "
    .. string.format(
        "%.2f",
        statusDuration
    )
    .. "s"
)

term.setTextColor(colors.white)


drawStatusPrompt(
    mon,
    floor,
    "CALL + STATUS OK",
    colors.lime
)


-- Let the success state remain visible.

sleep(1.5)


-- --------------------------------------------------------
-- Human navigation prompt.
-- --------------------------------------------------------

if floor < FLOOR_COUNT then

    drawTwoLineStatusPrompt(
        mon,
        floor,
        "FLOOR COMPLETE",
        "PROCEED TO F" .. (floor + 1),
        colors.lime,
        colors.orange
    )

else

    drawTwoLineStatusPrompt(
        mon,
        floor,
        "FLOOR COMPLETE",
        "COMMISSIONING COMPLETE",
        colors.lime,
        colors.lime
    )
end


return callRelay, statusRelay

end

-- ============================================================
-- Save configuration
-- V1.3 structure + callRelay + statusRelay
-- ============================================================

local function saveConfig(
shaft,
floors
)

if not fs.exists(CONFIG_DIR) then
    fs.makeDir(CONFIG_DIR)
end


local file =
    fs.open(CONFIG_FILE, "w")

if not file then
    error(
        "Unable to open "
        .. CONFIG_FILE
    )
end


file.writeLine("return {")

file.writeLine(
    '    shaft = "' .. shaft .. '",'
)

file.writeLine(
    "    arrivalHoldTime = "
    .. tostring(ARRIVAL_HOLD_TIME)
    .. ","
)

file.writeLine("")
file.writeLine("    floors = {")


for floor = 1, FLOOR_COUNT do

    file.writeLine(
        "        [" .. floor .. "] = {"
    )

    file.writeLine(
        '            monitor = "'
        .. floors[floor].monitor
        .. '",'
    )

    file.writeLine(
        '            speaker = "'
        .. floors[floor].speaker
        .. '",'
    )

    file.writeLine(
        '            callRelay = "'
        .. floors[floor].callRelay
        .. '",'
    )

    file.writeLine(
        '            statusRelay = "'
        .. floors[floor].statusRelay
        .. '",'
    )

    file.writeLine(
        "        },"
    )

end


file.writeLine("    }")
file.writeLine("}")

file.close()

end

-- ============================================================
-- MAIN
-- ============================================================

local shaft = selectShaft()

local monitorNames =
discoverPeripheralType("monitor")

local speakerNames =
discoverPeripheralType("speaker")

local relayNames =
discoverPeripheralType("redstone_relay")

clearTerminal()

print("RuffHouse Lift Commissioning")
print("============================")
print()
print("Shaft: " .. shaft)
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
.. (FLOOR_COUNT * 2)
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

if #relayNames ~= (FLOOR_COUNT * 2) then

print("ERROR")
print()

print(
    "Expected "
    .. (FLOOR_COUNT * 2)
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

-- V1.3 workflow preserved:

-- F1 monitor -> F1 speaker
-- F2 monitor -> F2 speaker
-- ...
-- F6 monitor -> F6 speaker
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

    monitor = monitorName,
    speaker = speakerName

}


-- --------------------------------------------------------
-- Confirmation
-- --------------------------------------------------------

local mon =
    peripheral.wrap(monitorName)

showCentered(
    mon,
    "FLOOR " .. floor .. " OK",
    colors.lime
)

sleep(1.0)


-- --------------------------------------------------------
-- Human navigation prompt.
--
-- Monitor + speaker for THIS floor are now complete.
-- Do not interrupt the monitor -> speaker sequence above.
-- --------------------------------------------------------

if floor < FLOOR_COUNT then

    showCentered(
        mon,
        "PROCEED TO F" .. (floor + 1),
        colors.orange
    )

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

-- Runs only AFTER the known-good V1.3 monitor/speaker pass.

-- The same physical call-button press maps:
--   - callRelay immediately
--   - statusRelay when the lift arrives
-- ============================================================

local assignedRelays = {}

for floor = 1, FLOOR_COUNT do

local callRelayName,
      statusRelayName =
    commissionFloorRelays(
        floor,
        shaft,
        floors[floor].monitor,
        relayNames,
        assignedRelays
    )


floors[floor].callRelay =
    callRelayName

floors[floor].statusRelay =
    statusRelayName

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
        floors[floor].monitor
    )

showCentered(
    mon,
    "FLOOR " .. floor,
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

print("Floor " .. floor)

print(
    "  Monitor: "
    .. floors[floor].monitor
)

print(
    "  Speaker: "
    .. floors[floor].speaker
)

print(
    "  Call:    "
    .. floors[floor].callRelay
)

print(
    "  Status:  "
    .. floors[floor].statusRelay
)

end

print()
print("Configuration saved:")
print(CONFIG_FILE)
print()
print("All landing hardware mapped.")
