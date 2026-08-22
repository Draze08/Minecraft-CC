# Facility Signage V2

Configurable CC:Tweaked facility signage for one or more attached monitors.

## Test install

On a CC:Tweaked computer with HTTP enabled:

```lua
wget run https://raw.githubusercontent.com/Draze08/Minecraft-CC/signage-v2/signage/install.lua
```

The installer asks for:

- facility / organisation
- division
- room or lab name
- room code
- access/status message
- footer text
- main accent colour
- warning colour
- whether to launch automatically at boot

Every attached monitor displays the same sign. Each monitor calculates its own dimensions, so differently sized monitor arrays remain centred.

The display includes a facility identity rail, room code, division label, animated room locator brackets, pulsing access/status panel, live indicator, and footer rail.

Re-run the installer to change the sign configuration.
