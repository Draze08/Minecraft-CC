-- RuffHouse Labs configurable facility signage
-- CC:Tweaked

local CONFIG_FILE = "signage.cfg"

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then
        error("Missing signage.cfg - run the signage installer first")
    end

    local f = fs.open(CONFIG_FILE, "r")
    local cfg = textutils.unserialize(f.readAll())
    f.close()

    if type(cfg) ~= "table" then
        error("Invalid signage.cfg")
    end

    return cfg
end

local cfg = loadConfig()
local monitors = { peripheral.find("monitor") }

if #monitors == 0 then
    error("No monitors attached")
end

local palette = {
    white = colors.white,
    orange = colors.orange,
    magenta = colors.magenta,
    lightBlue = colors.lightBlue,
    yellow = colors.yellow,
    lime = colors.lime,
    pink = colors.pink,
    gray = colors.gray,
    lightGray = colors.lightGray,
    cyan = colors.cyan,
    purple = colors.purple,
    blue = colors.blue,
    brown = colors.brown,
    green = colors.green,
    red = colors.red,
}

local accent = palette[cfg.accent] or colors.cyan
local warning = palette[cfg.warning] or colors.orange

local function fit(text, width)
    text = tostring(text or "")
    if #text <= width then return text end
    if width <= 3 then return text:sub(1, width) end
    return text:sub(1, width - 3) .. "..."
end

local function draw(mon, phase)
    mon.setTextScale(0.5)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()

    local w, h = mon.getSize()

    local function line(y, bg)
        if y < 1 or y > h then return end
        mon.setBackgroundColor(bg)
        mon.setCursorPos(1, y)
        mon.write(string.rep(" ", w))
    end

    local function center(y, text, fg, bg)
        if y < 1 or y > h then return end
        text = fit(text, w)
        mon.setTextColor(fg or colors.white)
        mon.setBackgroundColor(bg or colors.black)
        local x = math.max(1, math.floor((w - #text) / 2) + 1)
        mon.setCursorPos(x, y)
        mon.write(text)
    end

    local function left(y, x, text, fg, bg)
        if y < 1 or y > h or x > w then return end
        text = fit(text, w - x + 1)
        mon.setTextColor(fg or colors.white)
        mon.setBackgroundColor(bg or colors.black)
        mon.setCursorPos(x, y)
        mon.write(text)
    end

    -- Header / identity rail
    line(1, colors.gray)
    left(1, 2, cfg.facility, colors.white, colors.gray)
    local code = tostring(cfg.code or "")
    if #code > 0 and #code + 2 <= w then
        mon.setCursorPos(w - #code, 1)
        mon.setTextColor(accent)
        mon.setBackgroundColor(colors.gray)
        mon.write(code)
    end

    -- Division
    center(3, cfg.division, colors.lightGray)

    -- Animated locator brackets
    local roomY = math.max(6, math.floor(h * 0.42))
    center(roomY, cfg.room, accent)
    if roomY + 2 <= h then
        local marks = (phase % 2 == 0) and "< < <     > > >" or "  < < < > > >  "
        center(roomY + 2, marks, colors.gray)
    end

    -- Status panel
    local statusY = math.min(h - 4, roomY + 5)
    if statusY > roomY + 2 then
        local statusColor = (phase % 2 == 0) and warning or colors.yellow
        center(statusY, "[ " .. cfg.status .. " ]", statusColor)
    end

    -- Tiny live indicator, intentionally subtle
    if h >= 6 and w >= 12 then
        local live = (phase % 2 == 0) and "* LIVE" or "o LIVE"
        left(h - 2, 2, live, accent)
    end

    -- Footer rail
    line(h, colors.gray)
    center(h, cfg.footer, colors.white, colors.gray)
end

local phase = 0
while true do
    for _, mon in ipairs(monitors) do
        draw(mon, phase)
    end
    phase = phase + 1
    sleep(0.75)
end
