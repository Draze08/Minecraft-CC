-- ============================================================
-- RuffHouse Lift Controller v7.4
-- REAL LIFT STATE / HMI + AUDIO
-- ============================================================

local CONFIG_FILE = "/lift/config.lua"
local MOVE_LOG_FILE = "/lift/move.log"

local TEXT_SCALE = 2
local ANIMATION_INTERVAL = 0.25
local MOVE_SOUND = "enderio:block.sag_mill.tumble"
local MOVE_VOLUME = 0.5
local MOVE_PITCH = 0.8
local MOVE_INTERVAL = 1.5
local ARRIVAL_INSTRUMENT = "bell"
local ARRIVAL_VOLUME = 3
local ARRIVAL_PITCH = 12
local LIFTLINK_POLL_INTERVAL = 0.05

if not fs.exists(CONFIG_FILE) then error("Lift configuration not found: " .. CONFIG_FILE) end
local config = dofile(CONFIG_FILE)
if not config then error("Unable to load lift configuration.") end
if not config.floors then error("Configuration contains no floor data.") end
local FLOOR_COUNT = #config.floors
if FLOOR_COUNT < 1 then error("Configuration contains no commissioned landings.") end
for floor = 1, FLOOR_COUNT do
    local floorConfig = config.floors[floor]
    if not floorConfig then error("Missing configuration for landing " .. floor) end
    if type(floorConfig.y) ~= "number" then error("Missing Create Y for landing " .. floor) end
    if not floorConfig.monitor then error("Missing monitor for landing " .. floor) end
    if not floorConfig.speaker then error("Missing speaker for landing " .. floor) end
end

local elevatorName, elevator, createFloorByY = nil, nil, nil
local state = { floor=1, direction="stopped", destination=nil, animationFrame=1, running=true, audioActive=false, audioSuccess=0, elevatorName=nil, createShortName=nil, createLongName=nil, positionKnown=false, lastObservedFloor=nil }

local function getMonitor(floor) local f=config.floors[floor]; if not f or not f.monitor then return nil end; return peripheral.wrap(f.monitor) end
local function getSpeaker(floor) local f=config.floors[floor]; if not f or not f.speaker then return nil end; return peripheral.wrap(f.speaker) end
local function clearTerminal() term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1) end
local function writeLeftAt(mon,x,y,text,colour) text=tostring(text or ""); mon.setTextColor(colour or colors.white); mon.setCursorPos(math.max(1,x),y); mon.write(text) end
local function writeRightAt(mon,rightX,y,text,colour) text=tostring(text or ""); local x=rightX-#text+1; mon.setTextColor(colour or colors.white); mon.setCursorPos(math.max(1,x),y); mon.write(text) end
local function getFloorShortName(floor) local f=config.floors[floor]; if not f then return "" end; return tostring(f.shortName or "") end
local function getFloorLongName(floor) local f=config.floors[floor]; if not f then return "" end; return tostring(f.longName or "") end

local function getArrowRows(direction, frame)
    if direction == "up" then
        if frame == 1 then return {" ","v"," "} elseif frame == 2 then return {" ","v","v"} else return {"v"," ","v"} end
    elseif direction == "down" then
        if frame == 1 then return {" ","^"," "} elseif frame == 2 then return {"^","^"," "} else return {"^"," ","^"} end
    end
    return {" "," "," "}
end

local function getDisplayPositions(w,h)
    local leftX=1
    local rightX=w
    local numberY=math.floor((h+1)/2)+1
    if numberY>h then numberY=h end
    return leftX,rightX,numberY
end

local function drawDisplay(landingFloor)
    local mon=getMonitor(landingFloor); if not mon then return end
    mon.setTextScale(TEXT_SCALE); mon.setBackgroundColor(colors.black); mon.clear()
    local w,h=mon.getSize(); local leftX,rightX,numberY=getDisplayPositions(w,h); local numberColour
    if state.direction~="stopped" then numberColour=colors.orange elseif state.positionKnown and state.floor==landingFloor then numberColour=colors.lime else numberColour=colors.white end
    local displayFloor=state.positionKnown and state.floor or nil
    local shortName=displayFloor and getFloorShortName(displayFloor) or ""
    local longName=displayFloor and getFloorLongName(displayFloor) or ""
    writeLeftAt(mon,leftX,numberY,shortName,numberColour)
    local longNameY=math.max(1,numberY-2)
    writeLeftAt(mon,leftX,longNameY,longName,numberColour)
    if state.direction~="stopped" then
        local arrows=getArrowRows(state.direction,state.animationFrame); local topRow=numberY-1
        for i=1,3 do local row=topRow+(i-1); if row>=1 and row<=h and arrows[i]~=" " then writeRightAt(mon,rightX,row,arrows[i],colors.orange) end end
    end
end

local function refreshDisplays() for floor=1,FLOOR_COUNT do drawDisplay(floor) end end
local function stopAllSpeakers() for floor=1,FLOOR_COUNT do local s=getSpeaker(floor); if s then s.stop() end end; state.audioActive=false; state.audioSuccess=0 end
local function playMovementSound() local c=0; for floor=1,FLOOR_COUNT do local s=getSpeaker(floor); if s then local ok=s.playSound(MOVE_SOUND,MOVE_VOLUME,MOVE_PITCH); if ok then c=c+1 end end end; state.audioActive=true; state.audioSuccess=c end
local function playArrival(floor) local s=getSpeaker(floor); if not s then return end; s.playNote(ARRIVAL_INSTRUMENT,ARRIVAL_VOLUME,ARRIVAL_PITCH); sleep(0.15); s.playNote(ARRIVAL_INSTRUMENT,ARRIVAL_VOLUME,ARRIVAL_PITCH+4) end

local function drawTerminal()
    clearTerminal(); print("RuffHouse Lift Controller v7.4"); print("============================"); print(); print("Shaft: "..tostring(config.shaft))
    if state.positionKnown then print("Current floor: "..getFloorShortName(state.floor)) else print("Current floor: UNKNOWN") end
    print("State: "..string.upper(state.direction)); if state.destination then print("Destination: "..getFloorShortName(state.destination)) else print("Destination: NONE") end
    print(); if state.direction~="stopped" then print("Movement audio: ACTIVE"); print("Speakers: "..tostring(state.audioSuccess).."/"..tostring(FLOOR_COUNT)) else print("Movement audio: STOPPED") end
    print(); print("Sound:"); print(MOVE_SOUND); print(); print("CREATE LIFTLINK MODE"); print("--------------------"); print(); print("Peripheral: "..tostring(state.elevatorName or "UNKNOWN")); print("Create label: "..tostring(state.createShortName or "").." | "..tostring(state.createLongName or "")); print(); print("Create owns movement and call buttons."); print("Controller observes only."); print(); print("Q : Quit")
end

local function startMovement(direction) if state.direction==direction then return end; stopAllSpeakers(); state.direction=direction; state.animationFrame=1; playMovementSound(); refreshDisplays(); drawTerminal() end
local function stopMovement() stopAllSpeakers(); state.direction="stopped"; state.animationFrame=1; refreshDisplays(); drawTerminal() end
local function arrive(floor) stopAllSpeakers(); state.floor=floor; state.positionKnown=true; state.direction="stopped"; state.destination=nil; state.animationFrame=1; state.lastObservedFloor=floor; refreshDisplays(); drawTerminal(); playArrival(floor) end

local function discoverElevator()
    if config.elevator and peripheral.isPresent(config.elevator) and peripheral.hasType(config.elevator,"create_elevator") then local c=peripheral.wrap(config.elevator); local ok,f=pcall(c.listFloors); if ok and type(f)=="table" then return config.elevator,c end end
    local names=peripheral.getNames(); table.sort(names); for _,name in ipairs(names) do if peripheral.hasType(name,"create_elevator") then local c=peripheral.wrap(name); local ok,f=pcall(c.listFloors); if ok and type(f)=="table" then return name,c end end end; return nil,nil
end
local function buildFloorMap() local byY={}; for floor=1,FLOOR_COUNT do local y=config.floors[floor].y; if byY[y] then error("Duplicate commissioned Create Y: "..tostring(y)) end; byY[y]=floor end; return byY end
local function floorFromY(y) if type(y)~="number" then return nil end; return createFloorByY[y] end
local function configSummary(floor) if not floor then return "nil" end; local e=config.floors[floor]; if not e then return "index="..tostring(floor).." CONFIG_MISSING" end; return "index="..tostring(floor).." y="..tostring(e.y).." short="..tostring(e.shortName or "").." long="..tostring(e.longName or "").." monitor="..tostring(e.monitor or "").." speaker="..tostring(e.speaker or "") end
local function writeMoveLog(mode,text) local f=fs.open(MOVE_LOG_FILE,mode); if not f then return end; f.writeLine(text); f.close() end
local function beginMoveLog(info) writeMoveLog("w","=== MOVE START ==="); writeMoveLog("a","shaft="..tostring(config.shaft).." elevator="..tostring(state.elevatorName)); writeMoveLog("a","state current: "..configSummary(state.positionKnown and state.floor or nil)); writeMoveLog("a","state destination: "..configSummary(state.destination)); writeMoveLog("a","raw moving="..tostring(info.moving).." speed="..tostring(info.speed)) end
local function appendMovePoll(info) local currentY=info.currentInfo and info.currentInfo.y or nil; local targetY=info.targetInfo and info.targetInfo.y or nil; writeMoveLog("a","--- POLL ---"); writeMoveLog("a","moving="..tostring(info.moving).." speed="..tostring(info.speed)); writeMoveLog("a","Create currentY="..tostring(currentY).." short="..tostring(info.currentInfo and (info.currentInfo.shortName or info.currentInfo.name) or "").." -> "..configSummary(info.currentFloor)); writeMoveLog("a","Create targetY="..tostring(targetY).." short="..tostring(info.targetInfo and (info.targetInfo.shortName or info.targetInfo.name) or "").." -> "..configSummary(info.targetFloor)); writeMoveLog("a","controller stateFloor="..tostring(state.floor).." destination="..tostring(state.destination).." direction="..tostring(state.direction)) end
local function appendArrivalLog(info,arrivalFloor) writeMoveLog("a","=== ARRIVAL DECISION ==="); writeMoveLog("a","moving="..tostring(info.moving).." speed="..tostring(info.speed)); writeMoveLog("a","info.currentFloor: "..configSummary(info.currentFloor)); writeMoveLog("a","info.targetFloor: "..configSummary(info.targetFloor)); writeMoveLog("a","retained destination: "..configSummary(state.destination)); writeMoveLog("a","chosen arrival: "..configSummary(arrivalFloor)); local e=arrivalFloor and config.floors[arrivalFloor] or nil; writeMoveLog("a","ding speaker="..tostring(e and e.speaker or "nil")); writeMoveLog("a","=== MOVE END ===") end
local function saveConfig() local f=fs.open(CONFIG_FILE,"w"); if not f then return false end; f.write("return "..textutils.serialize(config)); f.close(); return true end
local function syncCreateMetadata(createFloors) local changed=false; for _,info in ipairs(createFloors) do local floor=floorFromY(info.y); if floor then local fc=config.floors[floor]; local sn=tostring(info.shortName or info.name or ""); local ln=tostring(info.longName or ""); if fc.shortName~=sn then fc.shortName=sn; changed=true end; if fc.longName~=ln then fc.longName=ln; changed=true end end end; if changed then saveConfig(); refreshDisplays() end end
local function readLiftLink() local floors=elevator.listFloors(); local cf,tf,ci,ti=nil,nil,nil,nil; for _,info in ipairs(floors) do if info.isCurrent then cf=floorFromY(info.y); ci=info end; if info.isTarget then tf=floorFromY(info.y); ti=info end end; return {floors=floors,currentFloor=cf,targetFloor=tf,currentInfo=ci,targetInfo=ti,moving=elevator.isMoving(),speed=elevator.getSpeed()} end

local function stateLoop()
    local wasMoving=false; local lastCurrentFloor=nil; local initial=readLiftLink()
    if initial.currentFloor then state.floor=initial.currentFloor; state.positionKnown=true; state.lastObservedFloor=initial.currentFloor; lastCurrentFloor=initial.currentFloor end
    if initial.currentInfo then state.createShortName=initial.currentInfo.shortName or initial.currentInfo.name or ""; state.createLongName=initial.currentInfo.longName or "" end
    state.destination=initial.targetFloor; refreshDisplays(); drawTerminal()
    while state.running do
        local ok,info=pcall(readLiftLink)
        if ok and info then
            if info.currentFloor then state.floor=info.currentFloor; state.positionKnown=true; state.lastObservedFloor=info.currentFloor; lastCurrentFloor=info.currentFloor end
            if info.currentInfo then state.createShortName=info.currentInfo.shortName or info.currentInfo.name or ""; state.createLongName=info.currentInfo.longName or "" end
            if info.targetFloor then state.destination=info.targetFloor end
            if info.moving then
                if not wasMoving then syncCreateMetadata(info.floors); beginMoveLog(info) end
                local direction=nil
                if type(info.speed)=="number" and info.speed~=0 then if info.speed>0 then direction="up" else direction="down" end end
                if not direction and state.destination and state.positionKnown then if state.destination>state.floor then direction="up" elseif state.destination<state.floor then direction="down" end end
                if direction and (not wasMoving or state.direction~=direction) then startMovement(direction) end
                appendMovePoll(info); wasMoving=true
            else
                if wasMoving then syncCreateMetadata(info.floors); local arrivalFloor=state.destination or info.currentFloor or lastCurrentFloor; appendMovePoll(info); appendArrivalLog(info,arrivalFloor); if arrivalFloor then arrive(arrivalFloor) else stopMovement() end elseif state.direction~="stopped" then stopMovement() end
                wasMoving=false; state.destination=nil
            end
            refreshDisplays(); drawTerminal()
        end
        sleep(LIFTLINK_POLL_INTERVAL)
    end
end
local function animationLoop() while state.running do if state.direction~="stopped" then state.animationFrame=state.animationFrame+1; if state.animationFrame>3 then state.animationFrame=1 end; refreshDisplays(); sleep(ANIMATION_INTERVAL) else sleep(0.1) end end end
local function movementAudioLoop() while state.running do if state.direction~="stopped" then sleep(MOVE_INTERVAL); if state.direction~="stopped" then playMovementSound(); drawTerminal() end else sleep(0.1) end end end
local function keyboardLoop() while state.running do local _,key=os.pullEvent("key"); if key==keys.q then state.running=false; return end end end

elevatorName,elevator=discoverElevator(); if not elevator then error("No CC:LiftLink create_elevator peripheral found.") end; state.elevatorName=elevatorName; createFloorByY=buildFloorMap()
local startupFloors=elevator.listFloors(); local foundY={}; for _,info in ipairs(startupFloors) do if type(info.y)=="number" then foundY[info.y]=true end end; for floor=1,FLOOR_COUNT do local y=config.floors[floor].y; if not foundY[y] then error("Commissioned Create landing missing at Y "..tostring(y)) end end
stopAllSpeakers(); parallel.waitForAny(stateLoop,keyboardLoop,animationLoop,movementAudioLoop)
state.running=false; state.direction="stopped"; stopAllSpeakers(); clearTerminal(); print("RuffHouse Lift Controller v7.4"); print("============================"); print(); print("Controller stopped.")