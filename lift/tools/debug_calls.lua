local r = peripheral.wrap("redstone_relay_X")
local last = false

print("Logging Floor 3 call relay...")

while true do
    local active = false

    for _, side in ipairs({
        "top", "bottom", "left",
        "right", "front", "back"
    }) do
        if r.getInput(side) then
            active = true
            break
        end
    end

    if active ~= last then
        print(
            string.format("%.2f", os.clock()),
            active and "HIGH" or "LOW"
        )
        last = active
    end

    sleep(0.02)
end
