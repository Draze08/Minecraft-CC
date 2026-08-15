-- ============================================================
-- RuffHouse Lift Commissioning Tool v3.2
--
-- Commissions:
--   1. Floor monitors
--   2. Floor speakers
--   3. Floor arrival/status relays
--
-- The floor monitors provide the local commissioning UI.
--
-- Relay commissioning:
--   Press the requested floor's physical call button.
--   Short relay pulses are treated as passing-floor events.
--   A sustained relay signal is treated as arrival.
--
-- IMPORTANT:
--   A mapped arrival relay may remain HIGH while the lift is
--   parked at that floor. Mapped relays are therefore ignored
--   during subsequent floor commissioning.
--
-- RuffHouse Minecraft-CC
-- ============================================================

local FLOOR_COUNT = 6

local ARRIVAL_HOLD_TIME = 1.0
local POLL_INTERVAL = 0.05

local CONFIG_PATH = "/lift/config.lua"

-- ============================================================
-- TERMINAL HELPERS
-- ============================================================

local function clearTerminal()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end


local function header(title)
    clearTerminal()

    term.setTextColor(colors.yellow)
    print(title)

    term.setTextColor(colors.white)
    print(string.rep("=", #title))
    print()
end


local function waitForEnter()
    term.setTextColor(colors.yellow)
    print()
    print("Press ENTER to continue")

    term.setTextColor(colors.white)

    while true do
        local _, key = os.pullEvent("key")

        if key == keys.enter then
            return
        end
    end
end

-- ============================================================
-- PERIPHERAL DISCOVERY
-- ============================================================

local function getPeripheralsOfType(wantedType)
    local result = {}

    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == wantedType then
            result[#result + 1] = name
        end
    end

    table.sort(result)

    return result
end


local monitors =
    getPeripheralsOfType("monitor")

local speakers =
    getPeripheralsOfType("speaker")

local relays =
    getPeripheralsOfType("redstone_relay")

-- ============================================================
-- MONITOR DRAWING
-- ============================================================

local function prepareMonitor(monitor)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.setTextScale(1)
    monitor.clear()
end


local function centeredText(monitor, y, text, colour)
    local width, height = monitor.getSize()

    if y < 1 then
        y = 1
    elseif y > height then
        y = height
    end

    local x =
        math.floor((width - #text) / 2) + 1

    if x < 1 then
        x = 1
    end

    monitor.setCursorPos(x, y)

    if colour then
        monitor.setTextColor(colour)
    end

    monitor.write(text)
end


local function drawFloorTitle(monitor, floor)
    prepareMonitor(monitor)

    local _, height = monitor.getSize()

    centeredText(
        monitor,
        math.max(1, math.floor(height / 2) - 2),
        "FLOOR " .. floor,
        colors.white
    )
end


local function drawTapToMap(monitor, floor)
    drawFloorTitle(monitor, floor)

    local _, height = monitor.getSize()

    centeredText(
        monitor,
        math.floor(height / 2) + 1,
        "TAP TO MAP",
        colors.orange
    )
end


local function drawMapped(monitor, floor)
    drawFloorTitle(monitor, floor)

    local _, height = monitor.getSize()

    centeredText(
        monitor,
        math.floor(height / 2) + 1,
        "MAPPED",
        colors.lime
    )
end


local function drawSpeakerTest(monitor, floor)
    drawFloorTitle(monitor, floor)

    local width, height = monitor.getSize()

    centeredText(
        monitor,
        math.floor(height / 2),
        "SPEAKER TEST",
        colors.orange
    )

    monitor.setTextColor(colors.red)

    monitor.setCursorPos(
        2,
        math.min(
            height,
            math.floor(height / 2) + 2
        )
    )

    monitor.write("NO")

    local yesText = "YES"

    monitor.setTextColor(colors.lime)

    monitor.setCursorPos(
        math.max(1, width - #yesText),
        math.min(
            height,
            math.floor(height / 2) + 2
        )
    )

    monitor.write(yesText)

    monitor.setTextColor(colors.white)
end


local function drawSpeakerMapped(monitor, floor)
    drawFloorTitle(monitor, floor)

    local _, height = monitor.getSize()

    centeredText(
        monitor,
        math.floor(height / 2) + 1,
        "SPEAKER MAPPED",
        colors.lime
    )
end


local function drawPushCall(monitor, floor)
    drawFloorTitle(monitor, floor)

    local _, height = monitor.getSize()

    centeredText(
        monitor,
        math.floor(height / 2),
        "STATUS TEST",
        colors.orange
    )

    centeredText(
        monitor,
        math.floor(height / 2) + 2,
        "PUSH CALL BUTTON",
        colors.yellow
    )
end


local function drawWaiting(monitor, floor)
    drawFloorTitle(monitor, floor)

    local _, height = monitor.getSize()

    centeredText(
        monitor,
        math.floor(height / 2),
        "STATUS TEST",
        colors.orange
    )

    centeredText(
        monitor,
        math.floor(height / 2) + 2,
        "WAITING...",
        colors.yellow
    )
end


local function drawStatusMapped(monitor, floor)
    drawFloorTitle(monitor, floor)

    local _, height = monitor.getSize()

    centeredText(
        monitor,
        math.floor(height / 2) + 1,
        "STATUS MAPPED",
        colors.lime
    )
end

-- ============================================================
-- HARDWARE CHECK
-- ============================================================

header("RuffHouse Lift Commissioning")

print("Hardware detected:")
print()

print(
    "Monitors: "
    .. #monitors
    .. "/"
    .. FLOOR_COUNT
)

print(
    "Speakers: "
    .. #speakers
    .. "/"
    .. FLOOR_COUNT
)

print(
    "Relays:   "
    .. #relays
    .. "/"
    .. FLOOR_COUNT
)

print()

if #monitors ~= FLOOR_COUNT
or #speakers ~= FLOOR_COUNT
or #relays ~= FLOOR_COUNT then

    term.setTextColor(colors.red)

    print("Hardware check FAILED.")
    print()

    term.setTextColor(colors.white)

    print("Commissioning requires:")
    print("  6 monitors")
    print("  6 speakers")
    print("  6 redstone relays")

    return
end

term.setTextColor(colors.lime)
print("Hardware check OK.")

term.setTextColor(colors.white)

waitForEnter()

-- ============================================================
-- CONFIG
-- ============================================================

local config = {
    shaft = "A",
    arrivalHoldTime = ARRIVAL_HOLD_TIME,
    floors = {}
}

for floor = 1, FLOOR_COUNT do
    config.floors[floor] = {}
end

local assignedMonitors = {}
local assignedSpeakers = {}
local assignedRelays = {}

-- ============================================================
-- MONITOR COMMISSIONING
-- ============================================================

for floor = 1, FLOOR_COUNT do

    header(
        "Floor "
        .. floor
        .. " - Monitor"
    )

    print(
        "Tap the monitor on Floor "
        .. floor
        .. "."
    )

    print()
    print("Waiting for touch...")

    -- Every currently unassigned monitor displays the
    -- floor we're looking for.

    for _, name in ipairs(monitors) do
        if not assignedMonitors[name] then

            local monitor =
                peripheral.wrap(name)

            if monitor then
                drawTapToMap(
                    monitor,
                    floor
                )
            end
        end
    end

    while true do

        local _,
              monitorName =
            os.pullEvent("monitor_touch")

        if peripheral.getType(monitorName)
            == "monitor" then

            if assignedMonitors[monitorName] then

                term.setTextColor(colors.red)

                print()
                print(
                    monitorName
                    .. " is already assigned."
                )

                term.setTextColor(colors.white)

            else

                config.floors[floor].monitor =
                    monitorName

                assignedMonitors[monitorName] =
                    true

                local monitor =
                    peripheral.wrap(monitorName)

                if monitor then
                    drawMapped(
                        monitor,
                        floor
                    )
                end

                term.setTextColor(colors.lime)

                print()
                print(
                    "Floor "
                    .. floor
                    .. " -> "
                    .. monitorName
                )

                term.setTextColor(colors.white)

                sleep(1)

                break
            end
        end
    end
end

-- ============================================================
-- SPEAKER HELPERS
-- ============================================================

local function stopAllSpeakers()

    for _, name in ipairs(speakers) do

        local speaker =
            peripheral.wrap(name)

        if speaker then
            pcall(function()
                speaker.stop()
            end)
        end
    end
end

-- ============================================================
-- SPEAKER COMMISSIONING
-- ============================================================

for floor = 1, FLOOR_COUNT do

    local monitorName =
        config.floors[floor].monitor

    local monitor =
        peripheral.wrap(monitorName)

    local candidates = {}

    for _, name in ipairs(speakers) do

        if not assignedSpeakers[name] then

            candidates[#candidates + 1] =
                name
        end
    end

    local selected = nil

    for _, candidate in ipairs(candidates) do

        header(
            "Floor "
            .. floor
            .. " - Speaker"
        )

        print("Testing:")
        print(candidate)

        print()
        print(
            "Use the Floor "
            .. floor
            .. " monitor."
        )

        if monitor then
            drawSpeakerTest(
                monitor,
                floor
            )
        end

        local speaker =
            peripheral.wrap(candidate)

        local function soundLoop()

            while true do

                if speaker then

                    speaker.playNote(
                        "pling",
                        1,
                        12
                    )
                end

                sleep(0.6)
            end
        end


        local function touchLoop()

            while true do

                local _,
                      touchedMonitor,
                      x =
                    os.pullEvent(
                        "monitor_touch"
                    )

                if touchedMonitor
                    == monitorName then

                    local width, _ =
                        monitor.getSize()

                    -- Left half = NO
                    -- Right half = YES

                    if x <= width / 2 then
                        return false
                    else
                        selected = candidate
                        return true
                    end
                end
            end
        end


        parallel.waitForAny(
            soundLoop,
            touchLoop
        )

        stopAllSpeakers()

        if selected then
            break
        end
    end

    if not selected then

        header(
            "Speaker Commissioning Failed"
        )

        term.setTextColor(colors.red)

        print(
            "No speaker selected for Floor "
            .. floor
            .. "."
        )

        term.setTextColor(colors.white)

        return
    end

    config.floors[floor].speaker =
        selected

    assignedSpeakers[selected] =
        true

    if monitor then
        drawSpeakerMapped(
            monitor,
            floor
        )
    end

    sleep(0.8)
end

-- ============================================================
-- RELAY HELPERS
-- ============================================================

local relaySides = {
    "top",
    "bottom",
    "left",
    "right",
    "front",
    "back"
}


local function relayActive(name)

    local relay =
        peripheral.wrap(name)

    if not relay then
        return false
    end

    for _, side in ipairs(relaySides) do

        local ok,
              value =
            pcall(function()

                return relay.getInput(side)
            end)

        if ok and value then
            return true
        end
    end

    return false
end


-- ============================================================
-- STATUS RELAY COMMISSIONING
-- ============================================================

for floor = 1, FLOOR_COUNT do

    local monitorName =
        config.floors[floor].monitor

    local monitor =
        peripheral.wrap(monitorName)

    header(
        "Floor "
        .. floor
        .. " - Status"
    )

    print(
        "Go to Floor "
        .. floor
        .. "."
    )

    print()

    print(
        "Press its physical call button."
    )

    print()

    print(
        "Pass-by pulses < "
        .. string.format(
            "%.1f",
            ARRIVAL_HOLD_TIME
        )
        .. " sec are ignored."
    )

    if monitor then

        drawPushCall(
            monitor,
            floor
        )
    end

    -- --------------------------------------------------------
    -- We cannot currently read the call-button channels.
    --
    -- Press the call button physically, then press ENTER
    -- here to arm the status detector.
    -- --------------------------------------------------------

    term.setTextColor(colors.yellow)

    print()
    print("Press ENTER after calling lift.")

    term.setTextColor(colors.white)

    while true do

        local _, key =
            os.pullEvent("key")

        if key == keys.enter then
            break
        end
    end

    if monitor then

        drawWaiting(
            monitor,
            floor
        )
    end

    print()
    print("Watching status relays...")
    print()

    -- --------------------------------------------------------
    -- IMPORTANT v3.2 CHANGE
    --
    -- We do NOT wait for every relay to be LOW here.
    --
    -- A relay which was mapped on an earlier floor may still
    -- be held HIGH because the lift is physically parked there.
    --
    -- Assigned relays are ignored entirely.
    --
    -- Any currently-active UNASSIGNED relay is measured from
    -- the moment detection begins. If it remains HIGH for the
    -- threshold, it can still be accepted.
    -- --------------------------------------------------------

    local accepted = nil

    local activeSince = {}

    while not accepted do

        for _, name in ipairs(relays) do

            if not assignedRelays[name] then

                local active =
                    relayActive(name)

                -- ------------------------------------------------
                -- Relay has become active.
                -- ------------------------------------------------

                if active then

                    if not activeSince[name] then

                        activeSince[name] =
                            os.clock()
                    end

                    local duration =
                        os.clock()
                        - activeSince[name]

                    -- ------------------------------------------------
                    -- Sustained signal = arrival / parked here.
                    -- ------------------------------------------------

                    if duration >= ARRIVAL_HOLD_TIME then

                        accepted = name

                        break
                    end

                else

                    -- ------------------------------------------------
                    -- Relay was previously active but released
                    -- before reaching the arrival threshold.
                    --
                    -- Therefore it was a pass-by pulse.
                    -- ------------------------------------------------

                    if activeSince[name] then

                        local duration =
                            os.clock()
                            - activeSince[name]

                        term.setTextColor(
                            colors.lightGray
                        )

                        print(
                            name
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

                        activeSince[name] = nil
                    end
                end
            end
        end

        if not accepted then
            sleep(POLL_INTERVAL)
        end
    end

    -- --------------------------------------------------------
    -- Map the relay immediately.
    --
    -- DO NOT wait for it to release.
    --
    -- The signal may remain HIGH for as long as the lift
    -- remains parked at this floor.
    -- --------------------------------------------------------

    assignedRelays[accepted] = true

    config.floors[floor].statusRelay =
        accepted

    local acceptedDuration =
        os.clock()
        - (
            activeSince[accepted]
            or os.clock()
        )

    term.setTextColor(colors.lime)

    print()
    print("ARRIVAL DETECTED")
    print()

    print(
        "Floor "
        .. floor
        .. " -> "
        .. accepted
    )

    print(
        "Held >= "
        .. string.format(
            "%.2f",
            acceptedDuration
        )
        .. "s"
    )

    term.setTextColor(colors.white)

    if monitor then

        drawStatusMapped(
            monitor,
            floor
        )
    end

    -- --------------------------------------------------------
    -- IMPORTANT:
    --
    -- Advance immediately.
    --
    -- The accepted relay is now in assignedRelays, so it will
    -- be ignored during commissioning of the next floor even
    -- if the lift remains parked here and the relay stays HIGH.
    -- --------------------------------------------------------

    sleep(1)
end

-- ============================================================
-- SAVE CONFIG
-- ============================================================

local function quote(value)

    return string.format(
        "%q",
        value
    )
end


local file =
    fs.open(
        CONFIG_PATH,
        "w"
    )


if not file then

    header("Configuration Error")

    term.setTextColor(colors.red)

    print("Unable to write:")
    print(CONFIG_PATH)

    term.setTextColor(colors.white)

    return
end


file.writeLine("return {")


file.writeLine(
    "    shaft = "
    .. quote(config.shaft)
    .. ","
)


file.writeLine(
    "    arrivalHoldTime = "
    .. tostring(
        config.arrivalHoldTime
    )
    .. ","
)


file.writeLine("")


file.writeLine(
    "    floors = {"
)


for floor = 1, FLOOR_COUNT do

    local data =
        config.floors[floor]

    file.writeLine(
        "        ["
        .. floor
        .. "] = {"
    )

    file.writeLine(
        "            monitor = "
        .. quote(data.monitor)
        .. ","
    )

    file.writeLine(
        "            speaker = "
        .. quote(data.speaker)
        .. ","
    )

    file.writeLine(
        "            statusRelay = "
        .. quote(data.statusRelay)
        .. ","
    )

    file.writeLine(
        "        },"
    )
end


file.writeLine("    }")
file.writeLine("}")

file.close()

-- ============================================================
-- FINISHED MONITOR STATE
-- ============================================================

for floor = 1, FLOOR_COUNT do

    local monitor =
        peripheral.wrap(
            config.floors[floor].monitor
        )

    if monitor then

        drawStatusMapped(
            monitor,
            floor
        )
    end
end

-- ============================================================
-- COMPLETE
-- ============================================================

header("Commissioning Complete")

print("All landing hardware mapped.")
print()


for floor = 1, FLOOR_COUNT do

    local data =
        config.floors[floor]

    term.setTextColor(colors.yellow)

    print(
        "Floor "
        .. floor
    )

    term.setTextColor(colors.white)

    print(
        " M: "
        .. data.monitor
    )

    print(
        " S: "
        .. data.speaker
    )

    print(
        " R: "
        .. data.statusRelay
    )

    print()
end


term.setTextColor(colors.lime)

print("Configuration saved:")

term.setTextColor(colors.white)

print(CONFIG_PATH)
