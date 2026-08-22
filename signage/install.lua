-- RuffHouse Labs signage installer
-- Downloads sign.lua, asks for sign identity, writes config and startup.lua.

local RAW_BASE = "https://raw.githubusercontent.com/Draze08/Minecraft-CC/signage-v2/signage/"

local function ask(prompt, default)
    term.setTextColor(colors.yellow)
    write(prompt)
    if default and default ~= "" then
        term.setTextColor(colors.gray)
        write(" [" .. default .. "]")
    end
    term.setTextColor(colors.white)
    write(": ")
    local value = read()
    if value == "" then return default or "" end
    return value
end

local choices = {
    "white", "orange", "magenta", "lightBlue", "yellow", "lime",
    "pink", "gray", "lightGray", "cyan", "purple", "blue",
    "brown", "green", "red"
}

local function chooseColor(prompt, default)
    print()
    term.setTextColor(colors.yellow)
    print(prompt)
    term.setTextColor(colors.lightGray)
    for i, name in ipairs(choices) do
        write(string.format("%2d %-10s", i, name))
        if i % 3 == 0 then print() else write("  ") end
    end
    if #choices % 3 ~= 0 then print() end

    while true do
        term.setTextColor(colors.white)
        write("Choice [" .. default .. "]: ")
        local value = read()
        if value == "" then return default end
        local n = tonumber(value)
        if n and choices[n] then return choices[n] end
        for _, name in ipairs(choices) do
            if value:lower() == name:lower() then return name end
        end
        term.setTextColor(colors.red)
        print("Pick a number or colour name, you magnificent menace.")
    end
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.cyan)
print("====================================")
print("   RUFFHOUSE FACILITY SIGN SYSTEM")
print("====================================")
term.setTextColor(colors.lightGray)
print("One computer. Every attached monitor.")
print("Configure once, then let it look expensive.")
print()

local cfg = {}
cfg.facility = ask("Facility / organisation", "QUANTUM SYSTEMS")
cfg.division = ask("Division", "DIGITISATION DIVISION")
cfg.room = ask("Room / lab name", "AE2 LAB")
cfg.code = ask("Room code", "QS-AE2-01")
cfg.status = ask("Access/status message", "ACCESS CONTROLLED")
cfg.footer = ask("Footer", "AUTHORIZED PERSONNEL")
cfg.accent = chooseColor("Main accent colour", "cyan")
cfg.warning = chooseColor("Status / warning colour", "orange")

print()
term.setTextColor(colors.yellow)
print("Downloading sign program...")

if fs.exists("sign.lua") then fs.delete("sign.lua") end
local ok, err = http.get(RAW_BASE .. "sign.lua")
if not ok then
    error("Download failed: " .. tostring(err))
end
local body = ok.readAll()
ok.close()
local sf = fs.open("sign.lua", "w")
sf.write(body)
sf.close()

local cf = fs.open("signage.cfg", "w")
cf.write(textutils.serialize(cfg))
cf.close()

local makeStartup = ask("Launch sign automatically on boot? Y/N", "Y")
if makeStartup:lower():sub(1, 1) ~= "n" then
    if fs.exists("startup.lua") then
        local backup = "startup.lua.signage-backup"
        if fs.exists(backup) then fs.delete(backup) end
        fs.copy("startup.lua", backup)
        term.setTextColor(colors.lightGray)
        print("Existing startup.lua backed up to " .. backup)
    end

    local st = fs.open("startup.lua", "w")
    st.writeLine('shell.run("sign.lua")')
    st.close()
end

term.setTextColor(colors.lime)
print()
print("Signage installed.")
term.setTextColor(colors.white)
print("Run: sign.lua")
print("Re-run installer any time to reconfigure.")
