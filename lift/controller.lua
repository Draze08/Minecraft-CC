-- ============================================================
-- RuffHouse Lift Controller v3
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
--   EnderIO SAG Mill tumble while moving
--   Two-note bell on destination floor
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

-- Animation speed
local ANIMATION_INTERVAL = 0.25

-- ============================================================
-- AUDIO SETTINGS
-- ============================================================

-- Movement machinery sound
local MOVE_SOUND = "enderio:block.sag_mill.tumble"
local MOVE_VOLUME = 0.5
local MOVE_PITCH = 0.8

-- Initial repeat interval.
-- We can tune this by ear once we hear the SAG Mill sample
-- running through the shaft.
local MOVE_INTERVAL = 1.5

-- Arrival chime
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
                " ",
                "^",
                " "
            }

        elseif frame == 2 then
            return {
                "^",
                "^",
                " "
            }

        else
            return {
                "^",
                " ",
                "^"
            }
        end

    elseif direction == "down" then

        if frame == 1 then
            return {
                " ",
                "v",
                " "
            }

        elseif frame == 2 then
            return {
                " ",
                "v",
                "v"
            }

        else
            return {
                "v",
                " ",
                "v"
            }
        end
    end

    return {
        " ",
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
    -- Horizontal positions
    -- --------------------------------------------------------

    local leftCenter =
        math.max(
            1,
            math.floor(w * 0.28)
        )

    local rightCenter =
        math.max(
            1,
            math.floor(w * 0.72)
        )


    -- --------------------------------------------------------
    -- TRUE vertical centre
    -- --------------------------------------------------------

    local centerY =
        math.max(
            1,
            math.floor((h + 1) / 2)
        )


    -- --------------------------------------------------------
    -- Determine floor-number colour
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

        local topRow =
            centerY - 1

        for i = 1, 3 do

            local row =
                topRow + (i - 1)

            if row >= 1
            and row <= h
            and arrows[i] ~= " " then

                writeCenteredAt(
                    mon,
                    rightCenter,
                    row,
                    arrows[i],
                    colors.orange
                )
            end
        end
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
-- MOVEMENT AUDIO
-- ============================================================

local function playMovementSound()

    for floor = 1, FLOOR_COUNT do

        local speaker =
            getSpeaker(floor)

        if speaker then

            speaker.playSound(
                MOVE_SOUND,
                MOVE_VOLUME,
                MOVE_PITCH
            )
        end
    end
end


-- ============================================================
-- ARRIVAL AUDIO
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

    print("RuffHouse Lift Controller v3")
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


        -- Arrival

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

            playMovementSound()

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
-- RUN
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

print("RuffHouse Lift Controller v3")
print("============================")
print()
print("Controller stopped.")
