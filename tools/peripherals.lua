-- RuffHouse CC:Tweaked Peripheral Scanner
-- Lists every peripheral visible to this computer.

term.clear()
term.setCursorPos(1, 1)

print("RuffHouse Peripheral Scanner")
print("============================")
print()

local names = peripheral.getNames()

if #names == 0 then
    print("No peripherals detected.")
    return
end

table.sort(names)

local monitorCount = 0

for _, name in ipairs(names) do
    local pType = peripheral.getType(name)

    if pType == "monitor" then
        monitorCount = monitorCount + 1
    end

    print(name .. "  [" .. tostring(pType) .. "]")
end

print()
print("----------------------------")
print("Total peripherals: " .. #names)
print("Monitors detected: " .. monitorCount)
