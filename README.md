# QuestiePlus

QuestiePlus is an experimental Classic World of Warcraft quest planning tool. It pairs a standalone HTML quest map/Journey editor with a small companion addon prototype for Questie.

The current web app can visualize Classic quest chains on zone and world maps, filter quests by character context, build Journey batches with prerequisite validation, and replay recorded character events over time.

## Repository Layout

```text
questieplus.html        Generated standalone web app
QuestiePlus/            WoW addon prototype
tools/                  Data generator, map downloader, and verifier scripts
assets/                 Classic map assets used by the web app
Questie/                Questie source checkout used as quest data input
docs/                   Project notes and data format docs
```

`Questie/` is tracked as a git submodule pointing at the upstream Questie repository. The generator reads Questie's Classic databases and emits `questieplus.html`.

## Web App

Open `questieplus.html` directly in a browser. The app is intentionally static so it can eventually ship alongside the addon download.

Main capabilities:

- Classic zone/world quest map views
- Quest catalogue filtering by race, class, level, zone, type, and display options
- Quest chain and prerequisite visualization
- Journey Planner for batching quests, with a Hidden quest pool
- Journey JSON export/import
- Copyable addon import string for the in-game prototype
- Character profile import with local/world map Replay controls

## Addon Prototype

The `QuestiePlus/` folder is a WoW addon prototype. Copy it into the Classic WoW AddOns folder next to Questie.

```text
World of Warcraft\_classic_era_\Interface\AddOns\QuestiePlus
```

The addon currently adds a compact `Questie | Plus` toggle above the Questie tracker. Questie mode leaves the normal tracker alone; Plus mode replaces the tracker content with the current Journey batch and can import/export a web Journey string from the centered QuestiePlus panel. The imported Journey carries assigned batches plus Hidden quests so limited in-game editing can round-trip back to the web app. Per-character profile SavedVariables record completed quests and a compact event stream for the web Replay view.

## Regenerating the Web App

From the repository root:

```powershell
python tools/build_questieplus_webapp.py
```

The generator expects the Questie submodule and map assets to be present.

## Verification

The current browser smoke test uses Playwright with the bundled Codex runtime:

```powershell
node tools/verify_questieplus_webapp.mjs
```

## Privacy

This project is private while the core Journey model, addon integration, and data licensing approach are still being worked out.
