-- ============================================================
-- RuffHouse Lift Controller v2
-- MOCK / DISPLAY + AUDIO TEST
--
-- Display:
--   LEFT  = current floor
--   RIGHT = animated direction chevrons
--
-- Colours:
--   WHITE  = lift stopped elsewhere
--   LIME   = lift stopped at this landing
--   ORANGE = lift moving
--
-- Audio:
--   Movement pulse on ALL floors
--   Arrival chime on destination floor only
--
-- Uses:
--   /lift/config.lua
--
-- NO REAL REDSTONE CONTROL YET
-- ============================================================

local CONFIG_FILE = "/lift/config.lua"
local FLOOR_COUNT = 6

-- ============================================================
-- DISPLAY SETTINGS
-- ============================================================

local TEXT_SCALE = 2

-- Animation speed in seconds
local ANIMATION_INTERVAL = 0.25

-- ============================================================
-- AUDIO SETTINGS
-- ============================================================

-- Movement sound
local MOVE_INTERVAL = 0.75
local MOVE_INSTRUMENT = "basedrum"
local MOVE_VOLUME = 1
local MOVE_PITCH = 6

-- Arrival sound
local ARRIVAL_INSTRUMENT = "bell"
local ARRIVAL_VOLUME = 3
local ARRIVAL_PITCH = 12


-- ============================================================
-- LOAD CONFIGURATION
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
-- STATE
-- ============================================================

local state = {
    floor = 1,
    direction = "stopped",
    animationFrame = 1,
    running = true
}


-- ============================================================
-- PERIPHERAL HELPERS
-- ============================================================

local function getMonitor(floor)

    local floorConfig = config.floors[floor]

    if not floorConfig then
        return nil
    end

    if not floorConfig.monitor then
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

    if not floorConfig.speaker then
        return nil
    end

    return peripheral.wrap(
        floorConfig.speaker
    )
end


-- ============================================================
-- TERMINAL HELPERS
-- ============================================================

local function clearTerminal()

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)

    term.clear()
    term.setCursorPos(1, 1)
end


-- ============================================================
-- MONITOR DRAWING HELPERS
-- ============================================================

local function writeCenteredAt(
    mon,
    centerX,
    y,
    text,
    colour
)

    local x =
        math.floor(
            centerX - (#text / 2)
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
-- DIRECTION ANIMATION
-- ============================================================

local function getArrowRows(
    direction,
    frame
)

    if direction == "up" then

        if frame == 1 then
            return {
                "^",
                " "
            }

        elseif frame == 2 then
            return {
                "^",
                "^"
            }

        else
            return {
                " ",
                "^"
            }
        end

    elseif direction == "down" then

        if frame == 1 then
            return {
                "v",
                " "
            }

        elseif frame == 2 then
            return {
                "v",
                "v"
            }

        else
            return {
                " ",
                "v"
            }
        end
    end

    return {
        " ",
        " "
    }
end


-- ============================================================
-- DRAW ONE LANDING DISPLAY
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


    local w, h =
        mon.getSize()


    -- --------------------------------------------------------
    -- Split monitor into left/right regions
    -- --------------------------------------------------------

    local leftCenter =
        math.floor(w * 0.28)

    local rightCenter =
        math.floor(w * 0.72)


    -- --------------------------------------------------------
    -- Vertical centre
    -- --------------------------------------------------------

    local centerY =
        math.max(
            1,
            math.ceil(h / 2)
        )


    -- --------------------------------------------------------
    -- Determine floor number colour
    -- --------------------------------------------------------

    local numberColour

    if state.direction ~= "stopped" then

        numberColour =
            colors.orange

    elseif state.floor == landingFloor then

        numberColour =
            colors.lime

    else

        numberColour =
            colors.white

    end


    -- --------------------------------------------------------
    -- Floor number
    -- --------------------------------------------------------

    writeCenteredAt(
        mon,
        leftCenter,
        centerY,
        tostring(state.floor),
        numberColour
    )


    -- --------------------------------------------------------
    -- Animated movement indicator
    -- --------------------------------------------------------

    if state.direction ~= "stopped" then

        local arrows =
            getArrowRows(
                state.direction,
                state.animationFrame
            )

        local firstRow =
            math.max(
                1,
                centerY - 1
            )

        local secondRow =
            math.min(
                h,
                centerY + 1
            )


        writeCenteredAt(
            mon,
            rightCenter,
            firstRow,
            arrows[1],
            colors.orange
        )


        writeCenteredAt(
            mon,
            rightCenter,
            secondRow,
            arrows[2],
            colors.orange
        )
    end
end


-- ============================================================
-- REFRESH ALL DISPLAYS
-- ============================================================

local function refreshDisplays()

    for floor = 1, FLOOR_COUNT do
        drawDisplay(floor)
    end
end


-- ============================================================
-- AUDIO
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


local function playArrival(floor)

    local speaker =
        getSpeaker(floor)

    if not speaker then
        return
    end


    -- Two-note lift chime

    speaker.playNote(
        ARRIVAL_INSTRUMENT,
        ARRIVAL_VOLUME,
        ARRIVAL_PITCH
    )

    sleep(0.15)

    speaker.playNote(
        ARRIVAL_INSTRUMENT,
        ARRIVAL_VOLUME,
        ARRIVAL_PITCH + 4
    )
end


-- ============================================================
-- TERMINAL UI
-- ============================================================

local function drawTerminal()

    clearTerminal()

    print("RuffHouse Lift Controller v2")
    print("============================")
    print()

    print(
        "Shaft: "
        .. tostring(config.shaft)
    )

    print()

    print(
        "Current floor: "
        .. tostring(state.floor)
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
    print("S   : Stop (no chime)")
    print("A   : Arrive + chime")
    print("Q   : Quit")

    print()
end


-- ============================================================
-- STATE CONTROL
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

    state.animationFrame = 1

    refreshDisplays()
    drawTerminal()
end


local function arrive()

    state.direction = "stopped"
    state.animationFrame = 1

    refreshDisplays()
    drawTerminal()

    playArrival(
        state.floor
    )
end


-- ============================================================
-- KEYBOARD INPUT LOOP
-- ============================================================

local function inputLoop()

    while state.running do

        local _, key =
            os.pullEvent("key")


        -- ----------------------------------------------------
        -- FLOOR POSITION TEST
        -- ----------------------------------------------------

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


        -- ----------------------------------------------------
        -- MOVEMENT TEST
        -- ----------------------------------------------------

        elseif key == keys.u then
            setDirection("up")

        elseif key == keys.d then
            setDirection("down")

        elseif key == keys.s then
            setDirection("stopped")


        -- ----------------------------------------------------
        -- ARRIVAL TEST
        -- ----------------------------------------------------

        elseif key == keys.a then
            arrive()


        -- ----------------------------------------------------
        -- QUIT
        -- ----------------------------------------------------

        elseif key == keys.q then

            state.running = false
            return
        end
    end
end


-- ============================================================
-- DISPLAY ANIMATION LOOP
-- ============================================================

local function animationLoop()

    while state.running do

        if state.direction ~= "stopped" then

            state.animationFrame =
                state.animationFrame + 1

            if state.animationFrame > 3 then
                state.animationFrame = 1
            end

            refreshDisplays()

            sleep(
                ANIMATION_INTERVAL
            )

        else

            sleep(0.1)
        end
    end
end


-- ============================================================
-- MOVEMENT AUDIO LOOP
-- ============================================================

local function movementAudioLoop()

    while state.running do

        if state.direction ~= "stopped" then

            playMovementPulse()

            sleep(
                MOVE_INTERVAL
            )

        else

            sleep(0.1)
        end
    end
end


-- ============================================================
-- STARTUP
-- ============================================================

refreshDisplays()
drawTerminal()


-- ============================================================
-- RUN CONTROLLER
-- ============================================================

parallel.waitForAny(
    inputLoop,
    animationLoop,
    movementAudioLoop
)


-- ============================================================
-- SHUTDOWN
-- ============================================================

state.running = false

for floor = 1, FLOOR_COUNT do

    local speaker =
        getSpeaker(floor)

    if speaker then
        speaker.stop()
    end
end


clearTerminal()

print("RuffHouse Lift Controller v2")
print("============================")
print()
print("Controller stopped.")
