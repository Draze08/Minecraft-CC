# CC:Tweaked Lift Controller

Controller software for the Create elevator system.

## Architecture

Each lift shaft has:

- 1 CC:Tweaked computer
- 6 networked landing monitors
- 6 Create elevator contacts
- EnderIO colour-coded redstone buses
- Separate position/movement sensing

## Display behaviour

- White floor number: lift stopped on another floor
- Green floor number: lift stopped on this floor
- Orange floor number: lift moving
- Up/down indicator: direction of travel

## Floors

| Floor | Call | Arrival |
|---|---|---|
| 1 | Light Blue | Cyan |
| 2 | Magenta | Light Grey |
| 3 | Orange | Grey |
| 4 | White | Pink |
| 5 | Black | Lime Green |
| 6 | Red | Yellow |
