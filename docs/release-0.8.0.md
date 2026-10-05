# Dreamway 0.8.0

Initial WoW Forever beta baseline, with updated Questie support for the web planner and companion addon.

- Uses Questie's current QuestieDB schemas, corrections and derived data, with separate Era, Season of Discovery, Forever, TBC and Wrath databases.
- Follows Questie's current Journey class and profession categories.
- Supports Forever client detection and updated quest and item APIs; fixes the startup `tonumber` error.
- Adds 57 native Forever map images with all available exploration overlays, including the new zones and native quest coordinates.
- Matches the Forever game version selector styling to the other versions.
- Preserves recycled search and planner rows and event-driven tracker item updates.

The ZIP includes the `DreamwayQuestPlanner` addon and its companion `WebApp`. Questie is required and is installed separately. Open `WebApp/dreamway.html` in a browser, keeping its data and assets folders alongside it.

Forever support is a beta baseline. Some upstream quest data and dungeon artwork remain incomplete. Live combat restrictions and persistence still need further in-game testing.

Validation: all addon files compile under Lua 5.1; compatibility, database isolation, Questie category matching, map hashes and native coordinates pass; search virtualization checks pass; generated JavaScript syntax and whitespace checks pass.
