# Dreamway

Dreamway is an experimental Classic World of Warcraft quest planning tool. It pairs a standalone HTML quest map/Journey editor with a small companion addon prototype for Questie.

The current web app can visualize Classic quest chains on zone and world maps, filter quests by character context, build Journey batches with prerequisite validation, and replay recorded character events over time.

## Repository Layout

```text
dreamway.html        Generated standalone web app
dreamway.ico         Multi-resolution Windows shortcut icon
Create a Dreamway Shortcut.txt
                     Windows shortcut setup instructions
DreamwayQuestPlanner/ WoW addon package (`Dreamway Quest Planner` in game)
tools/                  Data generator, map downloader, and verifier scripts
assets/                 Classic map assets used by the web app
Questie/                Questie source checkout used as quest data input
docs/                   Project notes and data format docs
```

`Questie/` is tracked as a git submodule pointing at the upstream Questie repository. The generator reads Questie's Classic databases and emits `dreamway.html`.

### Updating Questie

From the repository root, update the local Questie source to the latest upstream
`master` commit with:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\update_questie.ps1
```

To update Questie and immediately regenerate the Dreamway databases and web
app:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\update_questie.ps1 -RebuildWebApp
```

The updater refuses to overwrite local changes inside `Questie/` and handles the
checkout's Git safe-directory setting without changing your global Git configuration.

## Web App

Open `dreamway.html` directly in a browser. The app is intentionally static so it can eventually ship alongside the addon download.

Main capabilities:

- Classic zone/world quest map views
- Quest catalogue filtering by race, class, level, zone, type, and display options
- Quest chain and prerequisite visualization
- Journey Planner for batching quests, with a Hidden quest pool
- Journey JSON export/import
- Copyable addon import string for the in-game prototype
- Character profile import with local/world map Replay controls

## Addon Prototype

The `DreamwayQuestPlanner/` folder is a WoW addon prototype. Copy it into the Classic WoW AddOns folder next to Questie.

```text
World of Warcraft\_classic_era_\Interface\AddOns\DreamwayQuestPlanner
```

The addon currently adds a compact `Questie | Dreamway` toggle above the Questie tracker. Questie mode leaves the normal tracker alone; Dreamway mode replaces the tracker content with the current Journey batch and can import/export a web Journey string from the centered Dreamway panel. The imported Journey carries assigned batches and Hidden quests so limited in-game editing can round-trip back to the web app. Per-character profile SavedVariables record completed quests and a compact event stream for the web Replay view.

## Regenerating the Web App

From the repository root:

```powershell
python tools/build_dreamway_webapp.py
```

The generator expects the Questie submodule and map assets to be present.

## Verification

The current browser smoke test uses Playwright with the bundled Codex runtime:

```powershell
node tools/verify_dreamway_webapp.mjs
```

## Privacy

This project is private while the core Journey model, addon integration, and data licensing approach are still being worked out.
