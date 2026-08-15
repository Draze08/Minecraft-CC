-- ============================================================
-- RuffHouse Minecraft-CC Installer / Updater
-- ============================================================

local BASE_URL =
    "https://raw.githubusercontent.com/Draze08/Minecraft-CC/refs/heads/main/"

local files = {
    {
        remote = "lift/controller.lua",
        localPath = "/lift/controller.lua"
    },
    {
        remote = "lift/tools/commission.lua",
        localPath = "/lift/tools/commission.lua"
    },
    {
        remote = "lift/tools/peripherals.lua",
        localPath = "/lift/tools/peripherals.lua"
    }
}

local directories = {
    "/lift",
    "/lift/tools"
}

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

local function ensureDirectory(path)
    if not fs.exists(path) then
        print("Creating " .. path)
        fs.makeDir(path)
    end
end

local function downloadFile(remote, localPath)
    local url = BASE_URL .. remote

    print("Updating " .. localPath)

    -- Download to temporary file first.
    -- This means a failed download does NOT destroy the
    -- currently working copy.
    local tempPath = localPath .. ".new"

    if fs.exists(tempPath) then
        fs.delete(tempPath)
    end

    local response, err = http.get(url)

    if not response then
        return false, err or "HTTP request failed"
    end

    local contents = response.readAll()
    response.close()

    local file = fs.open(tempPath, "w")

    if not file then
        return false, "Could not open temporary file"
    end

    file.write(contents)
    file.close()

    -- Only replace the old copy after a successful download.
    if fs.exists(localPath) then
        fs.delete(localPath)
    end

    fs.move(tempPath, localPath)

    return true
end

-- ------------------------------------------------------------
-- Header
-- ------------------------------------------------------------

term.clear()
term.setCursorPos(1, 1)

print("RuffHouse Minecraft-CC Updater")
print("==============================")
print()

-- ------------------------------------------------------------
-- Create directory structure
-- ------------------------------------------------------------

for _, directory in ipairs(directories) do
    ensureDirectory(directory)
end

-- ------------------------------------------------------------
-- Download project files
-- ------------------------------------------------------------

local updated = 0
local failed = 0

for _, entry in ipairs(files) do
    local success, err =
        downloadFile(entry.remote, entry.localPath)

    if success then
        print("  OK")
        updated = updated + 1
    else
        print("  FAILED")
        print("  " .. tostring(err))
        failed = failed + 1
    end

    print()
end

-- ------------------------------------------------------------
-- Remove obsolete pre-restructure files
-- ------------------------------------------------------------

local obsolete = {
    "/lift/commission.lua",
    "/lift/peripherals.lua"
}

for _, path in ipairs(obsolete) do
    if fs.exists(path) then
        print("Removing obsolete " .. path)
        fs.delete(path)
    end
end

-- ------------------------------------------------------------
-- IMPORTANT:
-- /lift/config.lua is deliberately NOT touched.
--
-- It contains the locally commissioned peripheral mappings
-- for this particular lift shaft.
-- ------------------------------------------------------------

print()
print("==============================")

if failed == 0 then
    term.setTextColor(colors.lime)
    print("Update complete.")
else
    term.setTextColor(colors.orange)
    print("Update completed with errors.")
end

term.setTextColor(colors.white)

print()
print("Files updated: " .. updated)
print("Files failed:  " .. failed)

if fs.exists("/lift/config.lua") then
    print("Local config:  PRESERVED")
else
    print("Local config:  not yet commissioned")
end

print()
print("Run:")
print("  /lift/controller.lua")
print()
