-- ============================================================
-- RuffHouse Lift Controller v6
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
--   Floor call + status relays commissioned in:
--   /lift/config.lua
--
--   CALL relay   = requested destination / movement intent
--   STATUS relay = observed physical lift position
--
-- Status relay behaviour:
--   SHORT activation     = lift passing floor
--   SUSTAINED activation = lift stopped at floor
--
-- Call relay behaviour:
--   Activation selects destination immediately.
--   Direction is derived from current/last known floor to destination.
--
-- Shaft orientation:
--   1 -> 6 = DOWN
--   6 -> 1 = UP
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


    if not floorConfig.callRelay then

        error(
            "Missing call relay for Floor "
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

    -- Destination selected by a physical call button.

    destination = nil,

    animationFrame = 1,

    running = true,

    audioActive = false,
    audioSuccess = 0,

    -- Has the real physical lift position been established?

    positionKnown = false,

    -- Last floor observed through a pass or arrival event.

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


local function getCallRelay(floor)

    local floorConfig =
        config.floors[floor]

    if not floorConfig
    or not floorConfig.callRelay then
        return nil
    end

    return peripheral.wrap(
        floorConfig.callRelay
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
        "RuffHouse Lift Controller v6"
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

    if state.destination then

        print(
            "Destination: "
            .. tostring(state.destination)
        )

    else

        print("Destination: NONE")
    end


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

    print("CALL + STATUS MODE")
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
        "Call relays provide destination intent."
    )

    print(
        "Status relays provide physical position."
    )

    print(
        "Controller observes only; buttons control lift."
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
    -- This prevents duplicate call events from restarting
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
    state.destination = nil
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


local function peripheralRelayActive(relay)

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


local function statusRelayActive(floor)

    return peripheralRelayActive(
        getStatusRelay(floor)
    )
end


local function callRelayActive(floor)

    return peripheralRelayActive(
        getCallRelay(floor)
    )
end


-- ============================================================
-- MOVEMENT DIRECTION FROM DESTINATION INTENT
--
-- IMPORTANT:
-- Shaft numbering is physically inverted relative to the words:
--
--   1 -> 6 = DOWN
--   6 -> 1 = UP
--
-- Direction is therefore established immediately from the
-- current/last known physical floor and the call destination.
-- ============================================================

local function directionToDestination(destination)

    local referenceFloor = nil


    if state.positionKnown then

        referenceFloor =
            state.floor

    elseif state.lastObservedFloor then

        referenceFloor =
            state.lastObservedFloor
    end


    if referenceFloor == nil then
        return nil
    end


    if destination > referenceFloor then

        return "down"

    elseif destination < referenceFloor then

        return "up"
    end


    return nil
end


-- ============================================================
-- CALL EVENT
--
-- A physical landing button has selected a destination.
-- This is intent only. The controller does NOT command the lift.
-- ============================================================

local function handleCall(destination)

    if destination < 1
    or destination > FLOOR_COUNT then
        return
    end


    state.destination =
        destination


    local direction =
        directionToDestination(
            destination
        )


    if direction then

        startMovement(direction)

    else

        -- Same-floor call, or position not yet known.
        --
        -- If position is unknown we retain the destination and
        -- let status observations establish physical position.

        refreshDisplays()
        drawTerminal()
    end
end


-- ============================================================
-- PASS EVENT
--
-- Status relay released before the sustained-arrival threshold.
--
-- Direction is NOT inferred here anymore. Call relays already
-- gave us destination intent before movement began.
--
-- Passing status relays only update actual observed position.
-- ============================================================

local function handlePass(floor)

    state.floor = floor
    state.positionKnown = true

    state.lastObservedFloor =
        floor


    -- If the controller started with unknown position but a call
    -- destination was already captured, the first observed status
    -- floor now gives us enough information to establish direction.

    if state.direction == "stopped"
    and state.destination then

        local direction =
            directionToDestination(
                state.destination
            )

        if direction then
            startMovement(direction)
            return
        end
    end


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

        if statusRelayActive(floor) then

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
    -- Per-floor STATUS relay state.
    -- --------------------------------------------------------

    local statusState = {}


    for floor = 1, FLOOR_COUNT do

        statusState[floor] = {

            wasActive = false,

            activeSince = nil,

            handledArrival = false,

            ignoreUntilLow = false
        }
    end


    -- --------------------------------------------------------
    -- Per-floor CALL relay edge state.
    --
    -- Calls are handled on their rising edge only.
    -- --------------------------------------------------------

    local callState = {}


    for floor = 1, FLOOR_COUNT do

        callState[floor] = {

            wasActive =
                callRelayActive(floor)
        }
    end


    -- --------------------------------------------------------
    -- Establish startup physical position from STATUS only.
    -- --------------------------------------------------------

    local initialFloor =
        initialisePosition()


    if initialFloor then

        statusState[
            initialFloor
        ].wasActive = true

        statusState[
            initialFloor
        ].ignoreUntilLow = true
    end


    refreshDisplays()
    drawTerminal()


    -- --------------------------------------------------------
    -- Watch both commissioned relay banks.
    -- --------------------------------------------------------

    while state.running do

        -- ====================================================
        -- CALL RELAYS
        -- ====================================================

        for floor = 1, FLOOR_COUNT do

            local cs =
                callState[floor]

            local active =
                callRelayActive(floor)


            if active
            and not cs.wasActive then

                cs.wasActive = true

                handleCall(floor)


            elseif not active
            and cs.wasActive then

                cs.wasActive = false
            end
        end


        -- ====================================================
        -- STATUS RELAYS
        -- ====================================================

        for floor = 1, FLOOR_COUNT do

            local rs =
                statusState[floor]


            local active =
                statusRelayActive(floor)


            -- =================================================
            -- STATUS RELAY WENT HIGH
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
            -- STATUS RELAY IS HIGH
            -- =================================================

            if active then

                if rs.ignoreUntilLow then

                    -- Startup parked-floor relay.
                    -- It established initial position and must
                    -- not generate a fake arrival.

                elseif rs.activeSince
                and not rs.handledArrival then

                    local duration =
                        os.clock()
                        - rs.activeSince


                    if duration
                        >= ARRIVAL_HOLD_TIME then

                        rs.handledArrival =
                            true


                        local wasMoving =
                            state.direction
                            ~= "stopped"


                        state.floor = floor
                        state.positionKnown = true

                        state.lastObservedFloor =
                            floor


                        -- A sustained status signal is authoritative
                        -- physical arrival. If we had a destination,
                        -- it is now complete.

                        if wasMoving then

                            arrive(floor)

                        else

                            stopAllSpeakers()

                            state.direction =
                                "stopped"

                            state.destination =
                                nil

                            state.animationFrame =
                                1

                            refreshDisplays()
                            drawTerminal()
                        end
                    end
                end


            -- =================================================
            -- STATUS RELAY IS LOW
            -- =================================================

            else

                if rs.wasActive then

                    if rs.ignoreUntilLow then

                        rs.ignoreUntilLow =
                            false


                    elseif rs.activeSince
                    and not rs.handledArrival then

                        local duration =
                            os.clock()
                            - rs.activeSince


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
    "RuffHouse Lift Controller v6"
)

print(
    "============================"
)

print()

print(
    "Controller stopped."
)
