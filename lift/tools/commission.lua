-- ============================================================
-- RuffHouse Lift Commissioning Tool v3
--
-- Commissions:
--   1. Floor monitors
--   2. Floor speakers
--   3. Floor arrival/status relays
--
-- Relay commissioning:
--   Press the requested floor's physical call button.
--   Short relay pulses are treated as the lift passing a floor.
--   A sustained relay signal is treated as arrival.
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

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function header(title)
    clear()

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

local function waitForMonitorTouch()
    while true do
        local event, side = os.pullEvent()

        if event == "monitor_touch" then
            return side
        end
    end
end

-- ============================================================
-- DISCOVERY
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

local monitors = getPeripheralsOfType("monitor")
local speakers = getPeripheralsOfType("speaker")
local relays = getPeripheralsOfType("redstone_relay")

-- ============================================================
-- HARDWARE CHECK
-- ============================================================

header("RuffHouse Lift Commissioning")

print("Hardware detected:")
print()

print("Monitors: " .. #monitors .. "/" .. FLOOR_COUNT)
print("Speakers: " .. #speakers .. "/" .. FLOOR_COUNT)
print("Relays:   " .. #relays .. "/" .. FLOOR_COUNT)

print()

if #monitors ~= FLOOR_COUNT
or #speakers ~= FLOOR_COUNT
or #relays ~= FLOOR_COUNT then

    term.setTextColor(colors.red)
    print("Hardware check FAILED.")
    print()

    term.setTextColor(colors.white)
    print("Commissioning requires exactly:")
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
-- CONFIG DATA
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

    header("Floor " .. floor .. " - Monitor")

    print("Tap the monitor located")
    print("on Floor " .. floor .. ".")
    print()
    print("Waiting for touch...")

    while true do
        local name = waitForMonitorTouch()

        if peripheral.getType(name) == "monitor" then

            if assignedMonitors[name] then
                term.setTextColor(colors.red)
                print()
                print(name .. " is already assigned.")
                print("Tap the correct monitor.")

                term.setTextColor(colors.white)

            else
                config.floors[floor].monitor = name
                assignedMonitors[name] = true

                term.setTextColor(colors.lime)
                print()
                print("Detected: " .. name)

                term.setTextColor(colors.white)

                sleep(0.7)
                break
            end
        end
    end
end

-- ============================================================
-- SPEAKER HELPERS
-- ============================================================

local function stopAllSpeakerSounds()
    for _, name in ipairs(speakers) do
        local speaker = peripheral.wrap(name)

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

    local candidates = {}

    for _, name in ipairs(speakers) do
        if not assignedSpeakers[name] then
            candidates[#candidates + 1] = name
        end
    end

    local selected = nil

    for _, candidate in ipairs(candidates) do

        header("Floor " .. floor .. " - Speaker")

        print("Testing:")
        print(candidate)
        print()
        print("Do you hear this sound")
        print("on Floor " .. floor .. "?")
        print()

        term.setTextColor(colors.red)
        print("[ N ] NO")

        term.setTextColor(colors.lime)
        print("[ Y ] YES")

        term.setTextColor(colors.white)

        local speaker = peripheral.wrap(candidate)

        local function soundLoop()
            while true do
                if speaker then
                    speaker.playNote("pling", 1, 12)
                end

                sleep(0.6)
            end
        end

        local function inputLoop()
            while true do
                local _, key = os.pullEvent("key")

                if key == keys.y then
                    selected = candidate
                    return
                elseif key == keys.n then
                    return
                end
            end
        end

        parallel.waitForAny(soundLoop, inputLoop)

        stopAllSpeakerSounds()

        if selected then
            break
        end
    end

    if not selected then
        header("Speaker Commissioning Failed")

        term.setTextColor(colors.red)
        print("No speaker selected for Floor " .. floor .. ".")

        term.setTextColor(colors.white)
        return
    end

    config.floors[floor].speaker = selected
    assignedSpeakers[selected] = true
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
    local relay = peripheral.wrap(name)

    if not relay then
        return false
    end

    -- Any powered side means this relay is active.
    for _, side in ipairs(relaySides) do
        local ok, value = pcall(function()
            return relay.getInput(side)
        end)

        if ok and value then
            return true
        end
    end

    return false
end

local function allRelaysReleased()
    for _, name in ipairs(relays) do
        if relayActive(name) then
            return false
        end
    end

    return true
end

local function waitForAllRelaysReleased()
    while not allRelaysReleased() do
        sleep(POLL_INTERVAL)
    end
end

-- ============================================================
-- RELAY COMMISSIONING
-- ============================================================

for floor = 1, FLOOR_COUNT do

    header("Floor " .. floor .. " - Status")

    print("Push the FLOOR " .. floor)
    print("physical call button.")
    print()
    print("Short pass-by signals")
    print("will be ignored.")
    print()

    print(
        "Arrival threshold: "
        .. string.format("%.1f", ARRIVAL_HOLD_TIME)
        .. " sec"
    )

    print()

    term.setTextColor(colors.yellow)
    print("Waiting for lift...")

    term.setTextColor(colors.white)

    -- Make sure we begin from a released state.
    waitForAllRelaysReleased()

    local accepted = nil
    local previous = {}

    for _, name in ipairs(relays) do
        previous[name] = false
    end

    while not accepted do

        for _, name in ipairs(relays) do

            if not assignedRelays[name] then

                local active = relayActive(name)

                -- Detect rising edge.
                if active and not previous[name] then

                    local started = os.clock()

                    while relayActive(name) do

                        local duration =
                            os.clock() - started

                        if duration >= ARRIVAL_HOLD_TIME then
                            accepted = name
                            break
                        end

                        sleep(POLL_INTERVAL)
                    end

                    if not accepted then

                        local duration =
                            os.clock() - started

                        term.setTextColor(colors.lightGray)

                        print(
                            name
                            .. "  "
                            .. string.format("%.2f", duration)
                            .. "s  ignored"
                        )

                        term.setTextColor(colors.white)
                    end
                end

                previous[name] = relayActive(name)
            end
        end

        sleep(POLL_INTERVAL)
    end

    assignedRelays[accepted] = true
    config.floors[floor].statusRelay = accepted

    term.setTextColor(colors.lime)
    print()
    print("ARRIVAL DETECTED")
    print()
    print("Floor " .. floor)
    print("-> " .. accepted)

    term.setTextColor(colors.white)

    -- Wait for signal release before commissioning next floor.
    while relayActive(accepted) do
        sleep(POLL_INTERVAL)
    end

    waitForEnter()
end

-- ============================================================
-- SAVE CONFIG
-- ============================================================

local function quote(value)
    return string.format("%q", value)
end

local file = fs.open(CONFIG_PATH, "w")

if not file then
    header("Configuration Error")

    term.setTextColor(colors.red)
    print("Unable to write:")
    print(CONFIG_PATH)

    term.setTextColor(colors.white)
    return
end

file.writeLine("return {")
file.writeLine("    shaft = " .. quote(config.shaft) .. ",")
file.writeLine(
    "    arrivalHoldTime = "
    .. tostring(config.arrivalHoldTime)
    .. ","
)
file.writeLine("")
file.writeLine("    floors = {")

for floor = 1, FLOOR_COUNT do

    local data = config.floors[floor]

    file.writeLine("        [" .. floor .. "] = {")

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

    file.writeLine("        },")
end

file.writeLine("    }")
file.writeLine("}")

file.close()

-- ============================================================
-- COMPLETE
-- ============================================================

header("Commissioning Complete")

for floor = 1, FLOOR_COUNT do

    local data = config.floors[floor]

    term.setTextColor(colors.yellow)
    print("Floor " .. floor)

    term.setTextColor(colors.white)
    print(" M: " .. data.monitor)
    print(" S: " .. data.speaker)
    print(" R: " .. data.statusRelay)

    print()
end

term.setTextColor(colors.lime)
print("Configuration saved.")

term.setTextColor(colors.white)
print(CONFIG_PATH)
