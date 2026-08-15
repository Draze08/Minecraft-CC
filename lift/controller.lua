-- ============================================================
-- RuffHouse Lift Controller v5
-- REAL LIFT STATE / HMI + AUDIO
--
-- Display:
--   LEFT  = current/last observed floor
--   RIGHT = animated direction chevrons
--
-- Colours:
--   WHITE  = lift stopped elsewhere
--   LIME   = lift stopped at this landing
--   ORANGE = lift moving
--
-- Audio:
--   EnderIO SAG Mill tumble while moving
--   All movement audio STOPPED on arrival
--   Two-note bell on destination floor after movement stops
--
-- State input:
--   Floor redstone status relays commissioned in:
--   /lift/config.lua
--
-- Relay behaviour:
--   SHORT activation     = lift passing floor
--   SUSTAINED activation = lift stopped at floor
--
-- The controller NEVER commands the lift.
-- Physical call buttons remain entirely human controlled.
--
-- Uses:
--   /lift/config.lua
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

local MOVE_SOUND =
    "enderio:block.sag_mill.tumble"

local MOVE_VOLUME = 0.5
local MOVE_PITCH = 0.8
local MOVE_INTERVAL = 1.5

local ARRIVAL_INSTRUMENT = "bell"
local ARRIVAL_VOLUME = 3
local ARRIVAL_PITCH = 12


-- ============================================================
-- RELAY SETTINGS
-- ============================================================

local RELAY_POLL_INTERVAL = 0.05

-- Default only.
-- Commissioning V1 writes the actual value into config.lua.

local DEFAULT_ARRIVAL_HOLD_TIME = 1.0


-- ============================================================
-- LOAD CONFIG
-- ============================================================

if not fs.exists(CONFIG_FILE) then
    error(
        "Lift configuration not found: "
        .. CONFIG_FILE
    )
end


local config =
    dofile(CONFIG_FILE)


if not config then
    error(
        "Unable to load lift configuration."
    )
end


if not config.floors then
    error(
        "Configuration contains no floor data."
    )
end


local ARRIVAL_HOLD_TIME =
    config.arrivalHoldTime
    or DEFAULT_ARRIVAL_HOLD_TIME


-- ============================================================
-- VALIDATE CONFIG
-- ============================================================

for floor = 1, FLOOR_COUNT do

    local floorConfig =
        config.floors[floor]

    if not floorConfig then

        error(
            "Missing configuration for Floor "
            .. floor
        )
    end


    if not floorConfig.monitor then

        error(
            "Missing monitor for Floor "
            .. floor
        )
    end


    if not floorConfig.speaker then

        error(
            "Missing speaker for Floor "
            .. floor
        )
    end


    if not floorConfig.statusRelay then

        error(
            "Missing status relay for Floor "
            .. floor
        )
    end
end


-- ============================================================
-- STATE
-- ============================================================

local state = {

    -- Last known / currently observed floor.

    floor = 1,

    -- stopped / up / down

    direction = "stopped",

    animationFrame = 1,

    running = true,

    audioActive = false,
    audioSuccess = 0,

    -- Has the real physical lift position been established?

    positionKnown = false,

    -- Last floor observed through a pass or arrival event.
    --
    -- Used to infer direction.

    lastObservedFloor = nil
}


-- ============================================================
-- PERIPHERAL HELPERS
-- ============================================================

local function getMonitor(floor)

    local floorConfig =
        config.floors[floor]

    if not floorConfig
    or not floorConfig.monitor then
        return nil
    end

    return peripheral.wrap(
        floorConfig.monitor
    )
end


local function getSpeaker(floor)

    local floorConfig =
        config.floors[floor]

    if not floorConfig
    or not floorConfig.speaker then
        return nil
    end

    return peripheral.wrap(
        floorConfig.speaker
    )
end


local function getStatusRelay(floor)

    local floorConfig =
        config.floors[floor]

    if not floorConfig
    or not floorConfig.statusRelay then
        return nil
    end

    return peripheral.wrap(
        floorConfig.statusRelay
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
-- MONITOR HELPERS
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
-- ARROW ANIMATION
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
    -- Preserved from Controller V4.
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


    return
        leftCenter,
        rightCenter,
        numberY
end


-- ============================================================
-- DRAW ONE LANDING
-- ============================================================

local function drawDisplay(landingFloor)

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


    local leftCenter,
          rightCenter,
          numberY =
        getDisplayPositions(w, h)


    -- --------------------------------------------------------
    -- NUMBER COLOUR
    -- --------------------------------------------------------

    local numberColour


    if state.direction ~= "stopped" then

        numberColour =
            colors.orange

    elseif state.positionKnown
    and state.floor == landingFloor then

        numberColour =
            colors.lime

    else

        numberColour =
            colors.white
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

        local speaker =
            getSpeaker(floor)

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

        local speaker =
            getSpeaker(floor)


        if speaker then

            local success =
                speaker.playSound(
                    MOVE_SOUND,
                    MOVE_VOLUME,
                    MOVE_PITCH
                )


            if success then

                successCount =
                    successCount + 1
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


    print(
        "RuffHouse Lift Controller v5"
    )

    print(
        "============================"
    )

    print()


    print(
        "Shaft: "
        .. tostring(config.shaft)
    )


    if state.positionKnown then

        print(
            "Current floor: "
            .. tostring(state.floor)
        )

    else

        print(
            "Current floor: UNKNOWN"
        )
    end


    print(
        "State: "
        .. string.upper(
            state.direction
        )
    )


    print()


    if state.direction ~= "stopped" then

        print(
            "Movement audio: ACTIVE"
        )

        print(
            "Speakers: "
            .. tostring(
                state.audioSuccess
            )
            .. "/"
            .. tostring(
                FLOOR_COUNT
            )
        )

    else

        print(
            "Movement audio: STOPPED"
        )
    end


    print()

    print("Sound:")
    print(MOVE_SOUND)

    print()

    print("REAL STATUS MODE")
    print("----------------")
    print()

    print(
        "Arrival threshold: "
        .. tostring(
            ARRIVAL_HOLD_TIME
        )
        .. "s"
    )

    print()

    print(
        "Lift movement is observed only."
    )

    print(
        "Physical call buttons control lift."
    )

    print()

    print("Q : Quit")
end


-- ============================================================
-- FLOOR POSITION
-- ============================================================

local function setFloor(floor)

    if floor < 1
    or floor > FLOOR_COUNT then
        return
    end


    state.floor = floor
    state.positionKnown = true


    refreshDisplays()
    drawTerminal()
end


-- ============================================================
-- START MOVEMENT
-- ============================================================

local function startMovement(direction)

    -- Do not restart movement state if we're already moving
    -- in the same direction.
    --
    -- This prevents every passing-floor pulse from restarting
    -- the SAG sound.

    if state.direction == direction then
        return
    end


    -- Kill anything left playing from a previous state.

    stopAllSpeakers()


    state.direction = direction
    state.animationFrame = 1


    -- Fire movement audio immediately.
    --
    -- Preserved V4 behaviour.

    playMovementSound()


    refreshDisplays()
    drawTerminal()
end


-- ============================================================
-- STOP MOVEMENT WITHOUT ARRIVAL CHIME
-- ============================================================

local function stopMovement()

    stopAllSpeakers()


    state.direction = "stopped"
    state.animationFrame = 1


    refreshDisplays()
    drawTerminal()
end


-- ============================================================
-- ARRIVAL
-- ============================================================

local function arrive(floor)

    -- --------------------------------------------------------
    -- ORDER IS IMPORTANT
    --
    -- 1. Kill machinery audio.
    -- 2. Update actual floor.
    -- 3. Set stopped state.
    -- 4. Redraw displays.
    -- 5. Play destination chime.
    --
    -- Never stop speakers after playing the bell.
    -- --------------------------------------------------------

    stopAllSpeakers()


    state.floor = floor
    state.positionKnown = true

    state.direction = "stopped"
    state.animationFrame = 1

    state.lastObservedFloor =
        floor


    refreshDisplays()
    drawTerminal()


    playArrival(floor)
end


-- ============================================================
-- RELAY INPUT
-- ============================================================

local RELAY_SIDES = {
    "top",
    "bottom",
    "left",
    "right",
    "front",
    "back"
}


local function relayActive(floor)

    local relay =
        getStatusRelay(floor)


    if not relay then
        return false
    end


    for _, side
        in ipairs(RELAY_SIDES) do

        local ok,
              value =
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


-- ============================================================
-- INFER MOVEMENT DIRECTION
-- ============================================================

local function inferDirection(newFloor)

    local referenceFloor =
        state.lastObservedFloor


    if referenceFloor == nil
    and state.positionKnown then

        referenceFloor =
            state.floor
    end


    if referenceFloor == nil then
        return nil
    end


    if newFloor > referenceFloor then

        return "up"

    elseif newFloor < referenceFloor then

        return "down"
    end


    return nil
end


-- ============================================================
-- PASS EVENT
--
-- Called when a relay activates but releases BEFORE the
-- sustained-arrival threshold.
-- ============================================================

local function handlePass(floor)

    local direction =
        inferDirection(floor)


    -- --------------------------------------------------------
    -- If this is the first floor transition away from a known
    -- stopped floor, this establishes movement direction.
    -- --------------------------------------------------------

    if direction then

        if state.direction ~= direction then

            startMovement(direction)
        end
    end


    -- The floor number follows the latest floor actually
    -- observed by the lift.

    state.floor = floor
    state.positionKnown = true

    state.lastObservedFloor =
        floor


    refreshDisplays()
    drawTerminal()
end


-- ============================================================
-- INITIAL PHYSICAL POSITION
--
-- When the controller starts, the lift may already be parked
-- at a floor.
--
-- That floor's status relay will already be HIGH.
--
-- We use that to establish initial state WITHOUT playing the
-- arrival chime.
-- ============================================================

local function initialisePosition()

    local activeFloors = {}


    for floor = 1, FLOOR_COUNT do

        if relayActive(floor) then

            table.insert(
                activeFloors,
                floor
            )
        end
    end


    if #activeFloors == 1 then

        local floor =
            activeFloors[1]


        state.floor = floor
        state.positionKnown = true

        state.lastObservedFloor =
            floor

        state.direction =
            "stopped"


        return floor
    end


    -- No active relay:
    --
    -- Controller may have started while the lift was moving.
    -- Position will become known from the next observed relay.

    state.positionKnown = false
    state.lastObservedFloor = nil

    return nil
end


-- ============================================================
-- REAL LIFT STATE LOOP
-- ============================================================

local function stateLoop()

    -- --------------------------------------------------------
    -- Per-floor relay state.
    --
    -- activeSince:
    --   Time at which a NEW activation began.
    --
    -- handledArrival:
    --   Prevents a sustained HIGH relay from repeatedly
    --   generating arrival events.
    --
    -- ignoreUntilLow:
    --   Used for the relay which was already HIGH when the
    --   controller started.
    -- --------------------------------------------------------

    local relayState = {}


    for floor = 1, FLOOR_COUNT do

        relayState[floor] = {

            wasActive = false,

            activeSince = nil,

            handledArrival = false,

            ignoreUntilLow = false
        }
    end


    -- --------------------------------------------------------
    -- Establish startup state.
    -- --------------------------------------------------------

    local initialFloor =
        initialisePosition()


    if initialFloor then

        relayState[
            initialFloor
        ].wasActive = true

        relayState[
            initialFloor
        ].ignoreUntilLow = true
    end


    refreshDisplays()
    drawTerminal()


    -- --------------------------------------------------------
    -- Watch all six commissioned status relays.
    -- --------------------------------------------------------

    while state.running do

        for floor = 1, FLOOR_COUNT do

            local rs =
                relayState[floor]


            local active =
                relayActive(floor)


            -- =================================================
            -- RELAY WENT HIGH
            -- =================================================

            if active
            and not rs.wasActive then

                rs.wasActive = true

                rs.activeSince =
                    os.clock()

                rs.handledArrival =
                    false
            end


            -- =================================================
            -- RELAY IS HIGH
            -- =================================================

            if active then

                if rs.ignoreUntilLow then

                    -- This was already HIGH when the
                    -- controller booted.
                    --
                    -- It established our initial parked
                    -- position and must NOT generate a fake
                    -- arrival event.

                elseif rs.activeSince
                and not rs.handledArrival then

                    local duration =
                        os.clock()
                        - rs.activeSince


                    if duration
                        >= ARRIVAL_HOLD_TIME then

                        rs.handledArrival =
                            true


                        -- Was the lift actually moving before
                        -- this sustained signal?
                        --
                        -- Only genuine movement gets an
                        -- arrival chime.

                        local wasMoving =
                            state.direction
                            ~= "stopped"


                        state.floor = floor
                        state.positionKnown = true

                        state.lastObservedFloor =
                            floor


                        if wasMoving then

                            arrive(floor)

                        else

                            -- We discovered a stopped floor
                            -- without previously observing
                            -- movement.
                            --
                            -- Update state quietly.

                            stopAllSpeakers()

                            state.direction =
                                "stopped"

                            state.animationFrame =
                                1

                            refreshDisplays()
                            drawTerminal()
                        end
                    end
                end


            -- =================================================
            -- RELAY IS LOW
            -- =================================================

            else

                if rs.wasActive then

                    -- -----------------------------------------
                    -- Startup parked relay has finally
                    -- released.
                    --
                    -- This is departure from the initial
                    -- floor, NOT a pass event.
                    -- -----------------------------------------

                    if rs.ignoreUntilLow then

                        rs.ignoreUntilLow =
                            false


                    -- -----------------------------------------
                    -- Normal activation released.
                    -- -----------------------------------------

                    elseif rs.activeSince
                    and not rs.handledArrival then

                        local duration =
                            os.clock()
                            - rs.activeSince


                        -- Released before arrival threshold.
                        --
                        -- Therefore this was a pass-by.

                        if duration
                            < ARRIVAL_HOLD_TIME then

                            handlePass(floor)
                        end
                    end


                    rs.wasActive =
                        false

                    rs.activeSince =
                        nil

                    rs.handledArrival =
                        false
                end
            end
        end


        sleep(
            RELAY_POLL_INTERVAL
        )
    end
end


-- ============================================================
-- DISPLAY ANIMATION LOOP
-- ============================================================

local function animationLoop()

    while state.running do

        if state.direction
            ~= "stopped" then


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

        if state.direction
            ~= "stopped" then


            -- The first sound was already fired immediately
            -- by startMovement().
            --
            -- Wait before retriggering.

            sleep(
                MOVE_INTERVAL
            )


            -- State may have changed while sleeping.
            -- CHECK AGAIN before playing anything.

            if state.direction
                ~= "stopped" then

                playMovementSound()

                drawTerminal()
            end


        else

            sleep(0.1)
        end
    end
end


-- ============================================================
-- KEYBOARD LOOP
--
-- No mock lift controls anymore.
--
-- Keyboard exists solely so Q can shut down the controller
-- cleanly.
-- ============================================================

local function keyboardLoop()

    while state.running do

        local _, key =
            os.pullEvent("key")


        if key == keys.q then

            state.running = false

            return
        end
    end
end


-- ============================================================
-- STARTUP
-- ============================================================

stopAllSpeakers()


-- Initial monitor/terminal rendering happens inside stateLoop
-- after the real physical position has been checked.


-- ============================================================
-- RUN
-- ============================================================

parallel.waitForAny(
    stateLoop,
    keyboardLoop,
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


print(
    "RuffHouse Lift Controller v5"
)

print(
    "============================"
)

print()

print(
    "Controller stopped."
)
