local config = dofile("/lift/config.lua")

local floor = 3
local relayName = config.floors[floor].callRelay
local r = peripheral.wrap(relayName)

if not r then
    error("Could not wrap " .. tostring(relayName))
end

print("Logging Floor " .. floor .. " call relay")
print("Peripheral: " .. relayName)
print()
print("Ride lift and select Floor " .. floor)
print("internally.")
print()
print("Ctrl+T when finished.")
print()

local sides = {
    "top",
    "bottom",
    "left",
    "right",
    "front",
    "back"
}

local last = false

while true do

    local active = false

    for _, side in ipairs(sides) do

        local ok, value =
            pcall(
                r.getInput,
                side
            )

        if ok and value then
            active = true
            break
        end
    end

    if active ~= last then

        print(
            string.format(
                "%.2f  %s",
                os.clock(),
                active and "HIGH" or "LOW"
            )
        )

        last = active
    end

    sleep(0.02)
end
