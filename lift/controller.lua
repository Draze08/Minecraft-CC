-- ============================================================
-- RuffHouse Lift Controller v4
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
--   All movement audio STOPPED on stop/arrival
--   Two-note bell on destination floor after movement stops
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
local ANIMATION_INTERVAL = 0.25

-- ============================================================
-- AUDIO SETTINGS
-- ============================================================

local MOVE_SOUND = "enderio:block.sag_mill.tumble"
local MOVE_VOLUME = 0.5
local MOVE_PITCH = 0.8
local MOVE_INTERVAL = 1.5

local ARRIVAL_INSTRUMENT = "bell"
local ARRIVAL_VOLUME = 3
local ARRIVAL_PITCH = 12

-- ============================================================
-- LOAD CONFIG
-- ============================================================

if not fs.exists(CONFIG_FILE) then
    error("Lift configuration not found: " .. CONFIG_FILE)
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
    running = true,

    audioActive = false,
    audioSuccess = 0
}

-- ============================================================
-- PERIPHERAL HELPERS
-- ============================================================

local function getMonitor(floor)

    local floorConfig = config.floors[floor]

    if not floorConfig or not floorConfig.monitor then
        return nil
    end

    return peripheral.wrap(floorConfig.monitor)
end


local function getSpeaker(floor)

    local floorConfig = config.floors[floor]

    if not floorConfig or not floorConfig.speaker then
        return nil
    end

    return peripheral.wrap(floorConfig.speaker)
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
-- MONITOR HELPERS
-- ============================================================

local function writeCenteredAt(mon, centerX, y, text, colour)

    local x =
        math.floor(centerX - (#text / 2)) + 1

    mon.setTextColor(colour or colors.white)

    mon.setCursorPos(
        math.max(1, x),
        y
    )

    mon.write(text)
end

-- ============================================================
-- ARROW ANIMATION
-- ============================================================

local function getArrowRows(direction, frame)

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
-- DISPLAY POSITIONING
-- ============================================================

local function getDisplayPositions(w, h)

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
    -- VISUAL vertical centre
    --
    -- CC monitor glyphs sit above their baseline, so simply
    -- using the mathematical centre makes the number appear
    -- too high.
    --
    -- Bias the baseline downward by one character row.
    -- --------------------------------------------------------

    local numberY =
        math.floor((h + 1) / 2) + 1

    if numberY > h then
        numberY = h
    end

    return leftCenter, rightCenter, numberY
end

-- ============================================================
-- DRAW ONE LANDING
-- ============================================================

local function drawDisplay(landingFloor)

    local mon = getMonitor(landingFloor)

    if not mon then
        return
    end

    mon.setTextScale(TEXT_SCALE)
    mon.setBackgroundColor(colors.black)
    mon.clear()

    local w, h = mon.getSize()

    local leftCenter,
          rightCenter,
          numberY =
        getDisplayPositions(w, h)

    -- --------------------------------------------------------
    -- NUMBER COLOUR
    -- --------------------------------------------------------

    local numberColour

    if state.direction ~= "stopped" then

        numberColour = colors.orange

    elseif state.floor == landingFloor then

        numberColour = colors.lime

    else

        numberColour = colors.white
    end

    -- --------------------------------------------------------
    -- FLOOR NUMBER
    -- --------------------------------------------------------

    writeCenteredAt(
        mon,
        leftCenter,
        numberY,
        tostring(state.floor),
        numberColour
    )

    -- --------------------------------------------------------
    -- MOVEMENT INDICATOR
    -- --------------------------------------------------------

    if state.direction ~= "stopped" then

        local arrows =
            getArrowRows(
                state.direction,
                state.animationFrame
            )

        local topRow =
            numberY - 1

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
-- STOP ALL SPEAKERS
-- ============================================================

local function stopAllSpeakers()

    for floor = 1, FLOOR_COUNT do

        local speaker = getSpeaker(floor)

        if speaker then
            speaker.stop()
        end
    end

    state.audioActive = false
    state.audioSuccess = 0
end

-- ============================================================
-- PLAY MOVEMENT SOUND
-- ============================================================

local function playMovementSound()

    local successCount = 0

    for floor = 1, FLOOR_COUNT do

        local speaker = getSpeaker(floor)

        if speaker then

            local success =
                speaker.playSound(
                    MOVE_SOUND,
                    MOVE_VOLUME,
                    MOVE_PITCH
                )

            if success then
                successCount = successCount + 1
            end
        end
    end

    state.audioActive = true
    state.audioSuccess = successCount
end

-- ============================================================
-- ARRIVAL CHIME
-- ============================================================

local function playArrival(floor)

    local speaker = getSpeaker(floor)

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

    print("RuffHouse Lift Controller v4")
    print("============================")
    print()

    print(
        "Shaft: "
        .. tostring(config.shaft)
    )

    print(
        "Current floor: "
        .. tostring(state.floor)
    )

    print(
        "State: "
        .. string.upper(state.direction)
    )

    print()

    if state.direction ~= "stopped" then

        print("Movement audio: ACTIVE")

        print(
            "Speakers: "
            .. tostring(state.audioSuccess)
            .. "/"
            .. tostring(FLOOR_COUNT)
        )

    else

        print("Movement audio: STOPPED")
    end

    print()

    print("Sound:")
    print(MOVE_SOUND)

    print()
    print("MOCK CONTROLS")
    print("-------------")
    print()

    print("1-6 : Set current floor")
    print("U   : Moving UP")
    print("D   : Moving DOWN")
    print("S   : Stop immediately")
    print("A   : Arrive + chime")
    print("Q   : Quit")

    print()
end

-- ============================================================
-- FLOOR POSITION
-- ============================================================

local function setFloor(floor)

    if floor < 1 or floor > FLOOR_COUNT then
        return
    end

    state.floor = floor

    refreshDisplays()
    drawTerminal()
end

-- ============================================================
-- START MOVEMENT
-- ============================================================

local function startMovement(direction)

    -- Kill anything left playing from a previous state.
    stopAllSpeakers()

    state.direction = direction
    state.animationFrame = 1

    -- IMPORTANT:
    -- Fire movement audio immediately.
    -- Do not wait for the audio loop to notice the state.
    playMovementSound()

    refreshDisplays()
    drawTerminal()
end

-- ============================================================
-- STOP MOVEMENT WITHOUT ARRIVAL CHIME
-- ============================================================

local function stopMovement()

    -- Audio dies FIRST.
    stopAllSpeakers()

    state.direction = "stopped"
    state.animationFrame = 1

    refreshDisplays()
    drawTerminal()
end

-- ============================================================
-- ARRIVAL
-- ============================================================

local function arrive()

    -- --------------------------------------------------------
    -- ORDER IS IMPORTANT
    --
    -- 1. Kill machinery audio.
    -- 2. Set stopped state.
    -- 3. Redraw displays.
    -- 4. Play destination chime.
    --
    -- Never stop speakers after playing the bell.
    -- --------------------------------------------------------

    stopAllSpeakers()

    state.direction = "stopped"
    state.animationFrame = 1

    refreshDisplays()
    drawTerminal()

    playArrival(state.floor)
end

-- ============================================================
-- INPUT LOOP
-- ============================================================

local function inputLoop()

    while state.running do

        local _, key =
            os.pullEvent("key")

        -- Floors

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
            startMovement("up")

        elseif key == keys.d then
            startMovement("down")

        -- Stop

        elseif key == keys.s then
            stopMovement()

        -- Arrival

        elseif key == keys.a then
            arrive()

        -- Quit

        elseif key == keys.q then

            stopAllSpeakers()

            state.direction = "stopped"
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

            sleep(ANIMATION_INTERVAL)

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

            -- The first sound was already fired immediately
            -- by startMovement().
            --
            -- Wait before retriggering.

            sleep(MOVE_INTERVAL)

            -- State may have changed while sleeping.
            -- CHECK AGAIN before playing anything.

            if state.direction ~= "stopped" then

                playMovementSound()
                drawTerminal()
            end

        else

            sleep(0.1)
        end
    end
end

-- ============================================================
-- STARTUP
-- ============================================================

stopAllSpeakers()

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
state.direction = "stopped"

stopAllSpeakers()

clearTerminal()

print("RuffHouse Lift Controller v4")
print("============================")
print()
print("Controller stopped.")
