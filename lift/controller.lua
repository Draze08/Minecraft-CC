-- ============================================================
-- RuffHouse Lift Controller
-- MOCK / DISPLAY TEST VERSION
--
-- Tests:
--   - Floor indicators
--   - Movement indicators
--   - Arrival indication
--   - Movement audio
--   - Arrival chime
--
-- Uses:
--   /lift/config.lua
--
-- NO REDSTONE CONTROL YET
-- ============================================================

local CONFIG_FILE = "/lift/config.lua"

local FLOOR_COUNT = 6

-- Display settings
local TEXT_SCALE = 2

-- Movement sound settings
local MOVE_INTERVAL = 0.80
local MOVE_INSTRUMENT = "basedrum"
local MOVE_VOLUME = 0.25
local MOVE_PITCH = 5

-- Arrival sound settings
local ARRIVAL_INSTRUMENT = "bell"
local ARRIVAL_VOLUME = 1
local ARRIVAL_PITCH = 12


-- ============================================================
-- Load configuration
-- ============================================================

if not fs.exists(CONFIG_FILE) then
    error(
        "Lift configuration not found: "
        .. CONFIG_FILE
    )
end

local config = dofile(CONFIG_FILE)

if not config then
    error("Unable to load lift configuration.")
end

if not config.floors then
    error("Configuration contains no floor data.")
end


-- ============================================================
-- State
-- ============================================================

local state = {
    floor = 1,
    direction = "stopped",
    running = true
}


-- ============================================================
-- Utility functions
-- ============================================================

local function clearTerminal()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end


local function getMonitor(floor)
    local floorConfig = config.floors[floor]

    if not floorConfig then
        return nil
    end

    return peripheral.wrap(
        floorConfig.monitor
    )
end


local function getSpeaker(floor)
    local floorConfig = config.floors[floor]

    if not floorConfig then
        return nil
    end

    return peripheral.wrap(
        floorConfig.speaker
    )
end


local function centerText(
    mon,
    text,
    y,
    colour
)

    local w, _ = mon.getSize()

    local x =
        math.floor(
            (w - #text) / 2
        ) + 1

    mon.setTextColor(
        colour or colors.white
    )

    mon.setCursorPos(
        math.max(1, x),
        y
    )

    mon.write(text)
end


-- ============================================================
-- Draw one landing display
-- ============================================================

local function drawDisplay(
    landingFloor
)

    local mon =
        getMonitor(landingFloor)

    if not mon then
        return
    end


    mon.setTextScale(TEXT_SCALE)
    mon.setBackgroundColor(colors.black)
    mon.clear()


    local _, h = mon.getSize()


    -- --------------------------------------------------------
    -- Determine colour
    -- --------------------------------------------------------

    local numberColour

    if state.direction ~= "stopped" then

        -- Lift moving
        numberColour = colors.orange

    elseif state.floor == landingFloor then

        -- Lift stopped here
        numberColour = colors.lime

    else

        -- Lift stopped elsewhere
        numberColour = colors.white

    end


    -- --------------------------------------------------------
    -- Floor number
    -- --------------------------------------------------------

    local numberText =
        tostring(state.floor)

    local numberY =
        math.max(
            1,
            math.floor(h / 2)
        )

    centerText(
        mon,
        numberText,
        numberY,
        numberColour
    )


    -- --------------------------------------------------------
    -- Direction indicator
    -- --------------------------------------------------------

    if state.direction == "up" then

        centerText(
            mon,
            "^",
            math.min(h, numberY + 1),
            colors.orange
        )

    elseif state.direction == "down" then

        centerText(
            mon,
            "v",
            math.min(h, numberY + 1),
            colors.orange
        )

    end
end


-- ============================================================
-- Refresh all landing displays
-- ============================================================

local function refreshDisplays()

    for floor = 1, FLOOR_COUNT do
        drawDisplay(floor)
    end
end


-- ============================================================
-- Arrival chime
-- ============================================================

local function playArrival(floor)

    local speaker =
        getSpeaker(floor)

    if not speaker then
        return
    end

    speaker.playNote(
        ARRIVAL_INSTRUMENT,
        ARRIVAL_VOLUME,
        ARRIVAL_PITCH
    )
end


-- ============================================================
-- Movement sound
-- ============================================================

local function playMovementPulse()

    for floor = 1, FLOOR_COUNT do

        local speaker =
            getSpeaker(floor)

        if speaker then

            speaker.playNote(
                MOVE_INSTRUMENT,
                MOVE_VOLUME,
                MOVE_PITCH
            )

        end
    end
end


-- ============================================================
-- Terminal UI
-- ============================================================

local function drawTerminal()

    clearTerminal()

    print("RuffHouse Lift Controller")
    print("=========================")
    print()

    print(
        "Shaft: "
        .. tostring(config.shaft)
    )

    print()

    print(
        "Current floor: "
        .. state.floor
    )

    print(
        "State: "
        .. string.upper(
            state.direction
        )
    )

    print()
    print("MOCK CONTROLS")
    print("-------------")
    print()
    print("1-6 : Set current floor")
    print("U   : Moving UP")
    print("D   : Moving DOWN")
    print("S   : Stop at current floor")
    print("A   : Arrival test")
    print("Q   : Quit")
    print()
end


-- ============================================================
-- State functions
-- ============================================================

local function setFloor(floor)

    if floor < 1
    or floor > FLOOR_COUNT then
        return
    end

    state.floor = floor

    refreshDisplays()
    drawTerminal()
end


local function setDirection(direction)

    state.direction = direction

    refreshDisplays()
    drawTerminal()
end


local function arrive()

    state.direction = "stopped"

    refreshDisplays()

    playArrival(
        state.floor
    )

    drawTerminal()
end


-- ============================================================
-- Keyboard control loop
-- ============================================================

local function inputLoop()

    while state.running do

        local _, key =
            os.pullEvent("key")

        -- Floors 1-6

        if key == keys.one then
            setFloor(1)

        elseif key == keys.two then
            setFloor(2)

        elseif key == keys.three then
            setFloor(3)

        elseif key == keys.four then
            setFloor(4)

        elseif key == keys.five then
            setFloor(5)

        elseif key == keys.six then
            setFloor(6)


        -- Movement

        elseif key == keys.u then
            setDirection("up")

        elseif key == keys.d then
            setDirection("down")

        elseif key == keys.s then
            setDirection("stopped")


        -- Arrival test

        elseif key == keys.a then
            arrive()


        -- Quit

        elseif key == keys.q then

            state.running = false

            return
        end
    end
end


-- ============================================================
-- Movement audio loop
-- ============================================================

local function movementAudioLoop()

    while state.running do

        if state.direction ~= "stopped" then

            playMovementPulse()

            sleep(MOVE_INTERVAL)

        else

            sleep(0.1)

        end
    end
end


-- ============================================================
-- Startup
-- ============================================================

refreshDisplays()
drawTerminal()


-- ============================================================
-- Run
-- ============================================================

parallel.waitForAny(
    inputLoop,
    movementAudioLoop
)


-- ============================================================
-- Shutdown
-- ============================================================

for floor = 1, FLOOR_COUNT do

    local speaker =
        getSpeaker(floor)

    if speaker then
        speaker.stop()
    end
end


clearTerminal()

print("RuffHouse Lift Controller")
print("=========================")
print()
print("Controller stopped.")
