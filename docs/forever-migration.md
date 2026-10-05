# Questie 12 / Forever migration (2026-10-05)

Questie is pinned at `39e9dfd0`; the separate official QuestieDB submodule is pinned at `a4014864`. Updating dependencies now updates both checkouts, while refusing to overwrite local edits.

## Data generation

The old Questie Database files were replaced by QuestieDB schema-indexed data, registered corrections and derived fields. Dreamway now executes the upstream Lua 5.1 pipeline through Lupa instead of attempting to parse correction functions as text. Questie still supplies runtime policy and DBC inputs. Character-dependent correction policies are not baked into the static catalogue.

Install `tools/requirements-questiedb.txt` into your Python environment (or `tools/.runtime`, which the loader supports), then run `tools/build_dreamway_webapp.py`. Separate packs contain Era 4,256, SoD 5,533, Forever 5,009, TBC 6,474 and Wrath 9,174 quests. Native Forever coordinates are used in both the addon and web app, including Replay. The web app uses a separate, versioned native map set.

## Addon compatibility and performance

Forever is detected by interface 16000–16999 rather than the shared project ID. Canonical client TOC aliases include Forever and Camelot. Modern quest log and item APIs use Questie compatibility functions where available, and modern quest acceptance events support the single quest-ID argument. Cooldowns accept boolean or numeric enable flags. Race IDs 95/96 use exact high-bit masks in Lua and JavaScript.

Initialization waits for Questie database readiness. Restricted combat-log kill recording is disabled on Forever; ordinary quest objectives continue through quest events. Item buttons remain Dreamway-owned and event-driven.

Search hydration, completion checks and colored labels are resolved when building the result model. Scrolling reads cached values and recycles a bounded frame pool. The offline test drives the actual catalogue builder and scroll functions with 9,174 quests, asserts immutable array sharing, forbids database/completion queries on the scroll path, bounds frames to 21, and verifies timer coalescing.

## Validation and remaining beta limits

Run `tools/verify_forever_compat.py`, the generated inline JavaScript syntax check, and `git diff --check`. The verifier also compiles all addon Lua with Lua 5.1 and tests client detection, wide race masks, acceptance events, item cooldowns and catalogue isolation.

Forever data is still incomplete upstream. Native beta artwork is available for 57 maps (world, continents, zones and battlegrounds). Dungeon floor artwork absent from that set remains unavailable. All 57 maps now include every available native exploration overlay, including explored terrain and place names. Live beta combat restrictions, persistence and mouse-wheel behavior remain unverified in game. Validated builds deploy to both Era and G:/World of Warcraft/_classic_beta_.

## Native map import and quest categories

Run tools/download_forever_maps.py --build 1.60.1.70205 to import the client-art mirror from [The Forever Era](https://theforeverera.com/en/map/). It rejects a different manifest build, unexpected asset URLs, duplicate IDs and mismatched image dimensions. assets/forever-maps/manifest.json records the build, source URLs, source hashes, native parent/child rectangles and output crops. Original WebP images are kept for verification. Only artwork and UiMap relationships are imported; quest/NPC/object positions still come from QuestieDB. The importer then runs tools/build_forever_explored_maps.py to compose fully explored artwork from version-pinned native Wago DB2 tables and CASC textures. Metadata, texture hashes and composed-image hashes are recorded in the manifest. Textureless discovery rectangles are recorded separately: they have no native artwork to draw. Composition happens offline, with no additional runtime map processing.

The native UiMap set is cross-checked against QuestieDB's Forever reverse mapping. New maps include Zephras Isle (AreaID 16593), Riverglades (16591), Shen'dralas (16651), Mount Hyjal (616) and Darkspear Islands (16606). Zephras Isle has its own world selector entry; no continent placement is invented. Maps with no known quests remain browsable. Native rectangles place zone points on cropped Forever continents. Era/SoD/TBC/Wrath artwork is unchanged.

Class and profession categories use Questie's current lookupZones.lua Journey groups and lookupQuestCategories.lua names. Eligibility restrictions remain separate from category membership. Craftsman's Writ quests have positive zone/category IDs (Eastern Plaguelands or Merchant's Favor) and no profession requirement or profession sort in the corrected source. They remain outside the profession filter. Camping is listed by Questie under Events. Dreamway's additional gameplay filters (such as escorts, repeatability and city donations) remain distinct from Journey grouping.

Regression checks compare every Era/Forever profession category against upstream membership, cover Writs, verify all 57 source hashes, check new-map coverage and confirm a known Eastern Plaguelands pickup retains native QuestieDB coordinates.


Upstream references: [Questie releases](https://github.com/Questie/Questie/releases/latest), [QuestieDB Forever notes](https://github.com/Questie/QuestieDB/blob/master/docs/forever.md), and [Forever client API source](https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated).
