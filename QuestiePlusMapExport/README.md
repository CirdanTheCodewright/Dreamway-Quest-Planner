# QuestiePlus Map Export

Temporary diagnostic addon for exporting Blizzard's own clickable map data from the
Classic Era Kalimdor and Eastern Kingdoms continent maps.

## Use

1. Log into Classic Era.
2. Run `/qphit scan`.
3. Wait for both continents to reach 100%.
4. Run `/reload` or log out so WoW writes SavedVariables to disk.
5. Retrieve:

   `WTF/Account/<account>/SavedVariables/QuestiePlusMapExport.lua`

The export deliberately scans only UI map IDs `1414` (Kalimdor) and `1415`
(Eastern Kingdoms), not world map `947`. It includes descendant zones and cities,
their `C_Map.GetMapRectOnMap` rectangles, sampled `C_Map.GetMapInfoAtPosition`
hit grids, and `C_Map.GetMapHighlightInfoAtPosition` texture placement values.

Grid rows use compact run-length encoding. Each comma-separated run is
`uiMapID:length`; `0` means Blizzard returned no zone or city at that position.

## Commands

- `/qphit scan` starts a fresh export.
- `/qphit status` reports progress.
- `/qphit clear` cancels the scan and clears saved export data.
