import { createRequire } from "module";
import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
const { chromium } = require("C:/Users/Dan/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/.pnpm/playwright-core@1.61.1/node_modules/playwright-core");

const root = resolve(import.meta.dirname, "..");
const htmlPath = resolve(root, "questieplus.html");
const screenshotPath = resolve(root, "artifacts", "questieplus_duskwood.png");
const worldScreenshotPath = resolve(root, "artifacts", "questieplus_world.png");

await mkdir(resolve(root, "artifacts"), { recursive: true });

const browser = await chromium.launch({
  headless: true,
  executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe",
});
const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
const pageErrors = [];
page.on("pageerror", (error) => pageErrors.push(error.message));
await page.goto(pathToFileURL(htmlPath).href, { waitUntil: "networkidle" });
try {
  await page.waitForSelector(".quest-icon", { timeout: 10000 });
} catch (error) {
  console.log(JSON.stringify({ pageErrors, waitError: error.message }, null, 2));
  throw error;
}

const worldView = await page.evaluate(() => ({
  inventoryIcons: document.querySelectorAll(".quest-icon").length,
  chainRows: document.querySelectorAll(".chain-row").length,
  mapMarkers: document.querySelectorAll(".map-marker").length,
  continentMaps: document.querySelectorAll(".continent-map").length,
  zoneHitboxButtons: document.querySelectorAll(".world-zone-hitbox").length,
  continentHitGrids: DATA.continents.filter((continent) => continent.zoneHitGrid?.rows?.length).length,
  barrensHitGridPresent: DATA.continents.some((continent) => continent.zoneHitGrid?.zones?.includes(17)),
  markerLayerZIndex: Number(getComputedStyle(document.querySelector("#map-marker-layer")).zIndex),
  worldMapTitleHidden: document.querySelector("#map-title")?.hidden,
  worldMapTitleText: document.querySelector("#map-title")?.textContent?.trim(),
  toolbarSeparators: document.querySelectorAll(".toolbar-separator").length,
  firstSeparatorPrevious: document.querySelector(".toolbar-separator")?.previousElementSibling?.id,
  firstSeparatorNext: document.querySelector(".toolbar-separator")?.nextElementSibling?.id,
  secondSeparatorPrevious: document.querySelectorAll(".toolbar-separator")[1]?.previousElementSibling?.id,
  secondSeparatorNext: document.querySelectorAll(".toolbar-separator")[1]?.nextElementSibling?.id,
  continentBoxes: [...document.querySelectorAll(".continent")].map((continent) => {
    const rect = continent.getBoundingClientRect();
    const image = continent.querySelector(".continent-map");
    return {
      label: continent.querySelector(".continent-label")?.textContent?.trim(),
      width: rect.width,
      height: rect.height,
      ratio: rect.width / rect.height,
      naturalWidth: image?.naturalWidth,
      naturalHeight: image?.naturalHeight,
      objectFit: getComputedStyle(image).objectFit,
      objectPosition: getComputedStyle(image).objectPosition,
    };
  }),
  detailsPresent: Boolean(document.querySelector("#details")),
  mapRatio: (() => {
    const rect = document.querySelector("#map").getBoundingClientRect();
    return rect.width / rect.height;
  })(),
  mapHeight: document.querySelector("#map").getBoundingClientRect().height,
  mapFrameHeight: document.querySelector(".map-frame").getBoundingClientRect().height,
  inventoryHeight: document.querySelector(".inventory").getBoundingClientRect().height,
  zoneOptions: document.querySelectorAll("#zone-select option").length,
  raceOptions: document.querySelectorAll("#race-filter option").length,
  classOptions: document.querySelectorAll("#class-filter option").length,
  levelOptions: document.querySelectorAll("#level-filter option").length,
  questTypeOptions: document.querySelectorAll("#quest-filter-menu input").length,
  zoneFilterOptions: document.querySelectorAll("#zone-filter-menu input").length,
  displayOptions: document.querySelectorAll("#display-filter-menu input").length,
  displayOptionValues: [...document.querySelectorAll("#display-filter-menu input")].map((input) => input.value),
  displayOptionLabels: [...document.querySelectorAll("#display-filter-menu .quest-type-option")].map((item) => item.textContent.trim().replace(/\s+/g, " ")),
  searchPresent: Boolean(document.querySelector("#quest-search")),
  searchClearPresent: Boolean(document.querySelector("#quest-search-clear")),
  inventoryTitlePresent: Boolean(document.querySelector("#inventory-title")),
  inventorySubtitlePresent: Boolean(document.querySelector("#inventory-subtitle")),
  collapseAllPresent: Boolean(document.querySelector("#collapse-all-chains")),
  expandAllPresent: Boolean(document.querySelector("#expand-all-chains")),
  catalogueActionText: [...document.querySelectorAll(".inventory-action")].map((button) => button.textContent.trim()).join(""),
  checkedDisplayOptions: [...document.querySelectorAll("#display-filter-menu input:checked")].map((input) => input.value),
  displayFilterCount: document.querySelector("#display-filter-count")?.textContent?.trim(),
  checkedQuestTypes: [...document.querySelectorAll("#quest-filter-menu input:checked")].map((input) => input.value),
  questFilterCount: document.querySelector("#quest-filter-count")?.textContent?.trim(),
  categorySamples: {
    attack: DATA.quests.find((quest) => quest.id === 434)?.typeIds || [],
    breadcrumbs: DATA.quests.filter((quest) => quest.typeIds?.includes("breadcrumb")).length,
    escorts: DATA.quests.filter((quest) => quest.typeIds?.includes("escort")).length,
  },
  checkedZoneFilters: [...document.querySelectorAll("#zone-filter-menu input:checked")].map((input) => input.value),
  zoneFilterCount: document.querySelector("#zone-filter-count")?.textContent?.trim(),
  woolDonationVisibleByDefault: Boolean(document.querySelector('.quest-icon[data-quest-id="7791"]')),
  zoneOptionPreview: [...document.querySelectorAll("#zone-select option")].slice(0, 8).map((option) => option.textContent.trim()),
  stranglethornOption: [...document.querySelectorAll("#zone-select option")].find((option) => option.textContent.includes("Stranglethorn Vale"))?.textContent.trim(),
  title: document.querySelector("h1")?.textContent?.trim(),
  continentImagesLoaded: [...document.querySelectorAll(".continent-map")].every((img) => img.complete && img.naturalWidth > 0),
}));
if (worldView.detailsPresent) {
  throw new Error("Details bottom bar should not be rendered.");
}
if (!worldView.searchPresent) {
  throw new Error("Quest catalogue search input should be rendered.");
}
if (!worldView.searchClearPresent || worldView.inventoryTitlePresent) {
  throw new Error(`Expected search in the catalogue header with no title, got ${JSON.stringify(worldView)}.`);
}
if (
  worldView.displayOptions !== 3 ||
  !["available-pickups", "quest-objectives", "quest-handins"].every((value) => worldView.displayOptionValues.includes(value)) ||
  !worldView.checkedDisplayOptions.includes("available-pickups") ||
  worldView.checkedDisplayOptions.includes("quest-objectives") ||
  worldView.checkedDisplayOptions.includes("quest-handins") ||
  worldView.mapMarkers <= 0
) {
  throw new Error(`Expected available pickup markers to be enabled by default, got ${JSON.stringify(worldView)}.`);
}
if (!["elite", "dungeon", "class", "escort", "breadcrumb"].every((typeId) => worldView.checkedQuestTypes.includes(typeId)) || worldView.questFilterCount !== "6") {
  throw new Error(`Expected elite, dungeon, class, escort, and breadcrumb quests enabled by default with six default type filters, got ${JSON.stringify(worldView)}.`);
}
if (worldView.categorySamples.attack.includes("seasonal") || worldView.categorySamples.breadcrumbs <= 0 || worldView.categorySamples.escorts <= 0) {
  throw new Error(`Expected populated breadcrumb/escort categories and The Attack! not to be seasonal, got ${JSON.stringify(worldView.categorySamples)}.`);
}
if (worldView.zoneFilterOptions <= 0 || worldView.checkedZoneFilters.length !== worldView.zoneFilterOptions || worldView.zoneFilterCount !== String(worldView.zoneFilterOptions)) {
  throw new Error(`Expected all zone filters checked by default, got ${JSON.stringify(worldView)}.`);
}
if (worldView.stranglethornOption !== "Stranglethorn Vale [30-45]" || /\(\d+\)/.test(worldView.stranglethornOption) || /\[\d+\]/.test(worldView.stranglethornOption.replace("[30-45]", ""))) {
  throw new Error(`Expected cleaned Stranglethorn label with curated range, got ${worldView.stranglethornOption}.`);
}
if (worldView.inventorySubtitlePresent || !worldView.collapseAllPresent || !worldView.expandAllPresent || worldView.catalogueActionText !== "-+") {
  throw new Error(`Expected catalogue header to show -/+ controls instead of row text, got ${JSON.stringify(worldView)}.`);
}
if (!worldView.worldMapTitleHidden || worldView.worldMapTitleText || worldView.toolbarSeparators !== 2 || worldView.firstSeparatorPrevious !== "zone-select" || worldView.firstSeparatorNext !== "race-filter" || worldView.secondSeparatorPrevious !== "level-filter" || worldView.secondSeparatorNext !== "quest-filter-wrap") {
  throw new Error(`Expected hidden world map title and toolbar separators at requested positions, got ${JSON.stringify(worldView)}.`);
}
if (Math.abs(worldView.mapRatio - 1.5) > 0.01) {
  throw new Error(`Expected map aspect ratio to be 3:2, got ${worldView.mapRatio}.`);
}
if (worldView.continentBoxes.length !== 2) {
  throw new Error(`Expected two world continent panels, got ${worldView.continentBoxes.length}.`);
}
if (worldView.zoneHitboxButtons !== 0 || worldView.continentHitGrids !== 2 || !worldView.barrensHitGridPresent) {
  throw new Error(`Expected grid-driven world zone hit testing without rectangular buttons, got ${JSON.stringify(worldView)}.`);
}
const [firstContinent, secondContinent] = worldView.continentBoxes;
if (Math.abs(firstContinent.width - secondContinent.width) > 1 || Math.abs(firstContinent.height - secondContinent.height) > 1) {
  throw new Error(`Expected equal-sized world panels, got ${JSON.stringify(worldView.continentBoxes)}.`);
}
if (Math.abs(firstContinent.ratio - (410 / 668)) > 0.01 || Math.abs(secondContinent.ratio - (410 / 668)) > 0.01) {
  throw new Error(`Expected world panels to use the 410:668 crop ratio, got ${JSON.stringify(worldView.continentBoxes)}.`);
}
if (Math.abs(firstContinent.height - worldView.mapHeight) > 4) {
  throw new Error(`Expected world panels to use full map height, got panel ${firstContinent.height} vs map ${worldView.mapHeight}.`);
}

const barrensHitPoint = await page.evaluate(() => {
  const mapRect = document.querySelector("#map").getBoundingClientRect();
  const markers = [...document.querySelectorAll(".map-marker")].map((marker) => {
    const rect = marker.getBoundingClientRect();
    return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
  });
  const continent = DATA.continents.find((item) => item.zoneHitGrid?.zones?.includes(17));
  const grid = continent?.zoneHitGrid;
  if (!continent || !grid) return null;
  const targetIndex = grid.zones.indexOf(17);
  let best = null;
  for (let row = 0; row < grid.height; row += 1) {
    for (let col = 0; col < grid.width; col += 1) {
      if (grid.alphabet.indexOf(grid.rows[row][col]) !== targetIndex) continue;
      const localX = (col + 0.5) / grid.width * 100;
      const localY = (row + 0.5) / grid.height * 100;
      const mapXPercent = continent.x + localX * continent.width / 100;
      const mapYPercent = continent.y + localY * continent.height / 100;
      const x = mapRect.left + mapXPercent / 100 * mapRect.width;
      const y = mapRect.top + mapYPercent / 100 * mapRect.height;
      const markerDistance = markers.length
        ? Math.min(...markers.map((marker) => Math.hypot(marker.x - x, marker.y - y)))
        : 999;
      const centerDistance = Math.hypot(localX - 50, localY - 45);
      const score = markerDistance - centerDistance * 0.03;
      if (!best || score > best.score) best = { x, y, localX, localY, markerDistance, score };
    }
  }
  return best;
});
if (!barrensHitPoint || barrensHitPoint.markerDistance < 24) {
  throw new Error(`Expected to find a Barrens hit-grid point away from quest markers, got ${JSON.stringify(barrensHitPoint)}.`);
}
await page.mouse.move(barrensHitPoint.x, barrensHitPoint.y);
await page.waitForTimeout(180);
const barrensZoneTooltip = await page.evaluate(() => ({
  visible: !document.querySelector("#world-zone-tooltip").hidden,
  text: document.querySelector("#world-zone-tooltip")?.textContent?.trim(),
  background: getComputedStyle(document.querySelector("#world-zone-tooltip")).backgroundColor,
  borderRadius: getComputedStyle(document.querySelector("#world-zone-tooltip")).borderRadius,
}));
if (!barrensZoneTooltip.visible || barrensZoneTooltip.text !== "The Barrens") {
  throw new Error(`Expected world-zone tooltip for The Barrens, got ${JSON.stringify(barrensZoneTooltip)}.`);
}
await page.mouse.click(barrensHitPoint.x, barrensHitPoint.y);
await page.waitForTimeout(300);
const barrensHitboxClick = await page.evaluate(() => ({
  mapTitle: document.querySelector("#map-title")?.textContent?.trim(),
  zoneSelectValue: document.querySelector("#zone-select")?.value,
  worldLayerDisplay: getComputedStyle(document.querySelector("#world-layer")).display,
  zoneImageLoaded: document.querySelector("#zone-image")?.complete && document.querySelector("#zone-image")?.naturalWidth > 0,
}));
if (barrensHitboxClick.mapTitle !== "The Barrens" || barrensHitboxClick.zoneSelectValue !== "17" || barrensHitboxClick.worldLayerDisplay !== "none" || !barrensHitboxClick.zoneImageLoaded) {
  throw new Error(`Expected clicking The Barrens world hitbox to open its zone map, got ${JSON.stringify(barrensHitboxClick)}.`);
}
await page.click("#world-button");
await page.waitForTimeout(300);

await page.click("#expand-all-chains");
await page.waitForTimeout(250);
const expandedAllCatalogue = await page.evaluate(() => ({
  rows: document.querySelectorAll(".chain-row").length,
  expandedRows: document.querySelectorAll(".chain-row.expanded").length,
  expandedItems: document.querySelectorAll(".chain-quest-item").length,
}));
if (expandedAllCatalogue.rows <= 0 || expandedAllCatalogue.expandedRows !== expandedAllCatalogue.rows || expandedAllCatalogue.expandedItems <= 0) {
  throw new Error(`Expected + button to expand every visible catalogue chain, got ${JSON.stringify(expandedAllCatalogue)}.`);
}
await page.click("#collapse-all-chains");
await page.waitForTimeout(250);
const collapsedAllCatalogue = await page.evaluate(() => ({
  rows: document.querySelectorAll(".chain-row").length,
  expandedRows: document.querySelectorAll(".chain-row.expanded").length,
  expandedItems: document.querySelectorAll(".chain-quest-item").length,
}));
if (collapsedAllCatalogue.rows !== expandedAllCatalogue.rows || collapsedAllCatalogue.expandedRows !== 0 || collapsedAllCatalogue.expandedItems !== 0) {
  throw new Error(`Expected - button to collapse every visible catalogue chain, got ${JSON.stringify(collapsedAllCatalogue)}.`);
}

await page.click("#quest-filter-button");
const questFilterMenu = await page.evaluate(() => ({
  visible: !document.querySelector("#quest-filter-menu").hidden,
  labels: [...document.querySelectorAll(".quest-type-option")].slice(0, 5).map((item) => item.textContent.trim().replace(/\s+/g, " ")),
}));
if (!questFilterMenu.labels[0]?.startsWith("General progression") || !questFilterMenu.labels[1]?.startsWith("Elite / group") || !questFilterMenu.labels[2]?.startsWith("Dungeon")) {
  throw new Error(`Expected Elite / group to appear between General progression and Dungeon, got ${JSON.stringify(questFilterMenu)}.`);
}
await page.keyboard.press("Escape");
await page.click("#zone-filter-button");
const zoneFilterMenu = await page.evaluate(() => ({
  visible: !document.querySelector("#zone-filter-menu").hidden,
  actionLabels: [...document.querySelectorAll("#zone-filter-menu .filter-actions button")].map((button) => button.textContent.trim()),
  labels: [...document.querySelectorAll("#zone-filter-menu .quest-type-option")].slice(0, 8).map((item) => item.textContent.trim().replace(/\s+/g, " ")),
  checkedCount: document.querySelectorAll("#zone-filter-menu input:checked").length,
  totalCount: document.querySelectorAll("#zone-filter-menu input").length,
  buttonCount: document.querySelector("#zone-filter-count")?.textContent?.trim(),
  stranglethornLabel: [...document.querySelectorAll("#zone-filter-menu .quest-type-option")]
    .map((item) => item.textContent.trim().replace(/\s+/g, " "))
    .find((label) => label.includes("Stranglethorn Vale")),
}));
if (!zoneFilterMenu.visible || zoneFilterMenu.actionLabels.join("|") !== "Check all|Uncheck all" || zoneFilterMenu.checkedCount !== zoneFilterMenu.totalCount || zoneFilterMenu.buttonCount !== String(zoneFilterMenu.totalCount)) {
  throw new Error(`Expected zone filter menu with all zones checked and actions, got ${JSON.stringify(zoneFilterMenu)}.`);
}
if (zoneFilterMenu.stranglethornLabel !== "Stranglethorn Vale [30-45]") {
  throw new Error(`Expected zone filter to mirror the curated Stranglethorn picker label, got ${JSON.stringify(zoneFilterMenu)}.`);
}
await page.click('#zone-filter-menu [data-zone-action="uncheck-all"]');
await page.waitForTimeout(200);
const allZonesUnchecked = await page.evaluate(() => ({
  rows: document.querySelectorAll(".chain-row").length,
  markers: document.querySelectorAll(".map-marker").length,
  checkedCount: document.querySelectorAll("#zone-filter-menu input:checked").length,
  buttonCount: document.querySelector("#zone-filter-count")?.textContent?.trim(),
}));
if (allZonesUnchecked.rows !== 0 || allZonesUnchecked.markers !== 0 || allZonesUnchecked.checkedCount !== 0 || allZonesUnchecked.buttonCount !== "0") {
  throw new Error(`Expected unchecking all zones to hide all catalogue rows and pickups, got ${JSON.stringify(allZonesUnchecked)}.`);
}
await page.check('#zone-filter-menu input[value="10"]');
await page.waitForTimeout(300);
const duskwoodOnlyFilter = await page.evaluate(() => ({
  rows: document.querySelectorAll(".chain-row").length,
  markers: document.querySelectorAll(".map-marker").length,
  checkedValues: [...document.querySelectorAll("#zone-filter-menu input:checked")].map((input) => input.value),
  buttonCount: document.querySelector("#zone-filter-count")?.textContent?.trim(),
  hasDuskwoodQuest: Boolean(document.querySelector('.quest-icon[data-quest-id="173"]')),
  hasTigerMastery: Boolean(document.querySelector('.quest-icon[data-quest-id="185"]')),
  summaries: [...document.querySelectorAll(".chain-zone-summary")].slice(0, 40).map((item) => item.textContent.trim()),
}));
if (
  duskwoodOnlyFilter.rows <= 0 ||
  duskwoodOnlyFilter.markers <= 0 ||
  duskwoodOnlyFilter.checkedValues.join(",") !== "10" ||
  duskwoodOnlyFilter.buttonCount !== "1" ||
  !duskwoodOnlyFilter.hasDuskwoodQuest ||
  duskwoodOnlyFilter.hasTigerMastery ||
  duskwoodOnlyFilter.summaries.some((summary) => !summary.includes("Duskwood"))
) {
  throw new Error(`Expected Duskwood-only zone filter to show only chains involving Duskwood, got ${JSON.stringify(duskwoodOnlyFilter)}.`);
}
await page.click('#zone-filter-menu [data-zone-action="check-all"]');
await page.keyboard.press("Escape");
await page.click("#display-filter-button");
const displayFilterMenu = await page.evaluate(() => ({
  visible: !document.querySelector("#display-filter-menu").hidden,
  labels: [...document.querySelectorAll("#display-filter-menu .quest-type-option")].map((item) => item.textContent.trim().replace(/\s+/g, " ")),
}));
if (
  !displayFilterMenu.visible ||
  !displayFilterMenu.labels.includes("Available quest pickups") ||
  !displayFilterMenu.labels.includes("All quest objectives") ||
  !displayFilterMenu.labels.includes("All quest hand-ins")
) {
  throw new Error(`Expected Display filter to expose pickup, objective, and hand-in overlays, got ${JSON.stringify(displayFilterMenu)}.`);
}
await page.keyboard.press("Escape");
await page.screenshot({ path: worldScreenshotPath, fullPage: true });

await page.selectOption("#race-filter", "1");
await page.selectOption("#class-filter", "1");
await page.selectOption("#level-filter", "24");
await page.waitForTimeout(300);
const filteredWorldView = await page.evaluate(() => ({
  inventoryIcons: document.querySelectorAll(".quest-icon").length,
  chainRows: document.querySelectorAll(".chain-row").length,
  mapMarkers: document.querySelectorAll(".map-marker").length,
  selectedRaceColor: getComputedStyle(document.querySelector("#race-filter")).color,
  selectedClassColor: getComputedStyle(document.querySelector("#class-filter")).color,
}));

await page.selectOption("#level-filter", "40");
await page.waitForTimeout(300);
const nesingwaryAt40 = await page.evaluate(() => ({
  tigerChainVisible: Boolean(document.querySelector('.quest-icon[data-quest-id="185"]')),
  pantherChainVisible: Boolean(document.querySelector('.quest-icon[data-quest-id="190"]')),
  raptorChainVisible: Boolean(document.querySelector('.quest-icon[data-quest-id="194"]')),
  tigerFinalVisible: Boolean(document.querySelector('.quest-icon[data-quest-id="188"]')),
  pantherFinalVisible: Boolean(document.querySelector('.quest-icon[data-quest-id="193"]')),
  raptorLateVisible: Boolean(document.querySelector('.quest-icon[data-quest-id="196"]')),
  rows: document.querySelectorAll(".chain-row").length,
}));
if (!nesingwaryAt40.tigerChainVisible || !nesingwaryAt40.pantherChainVisible || !nesingwaryAt40.raptorChainVisible) {
  throw new Error(`Expected Nesingwary mastery chains to stay visible at level 40, got ${JSON.stringify(nesingwaryAt40)}.`);
}

await page.selectOption("#level-filter", "all");
await page.waitForTimeout(300);
const allLevelWorldCatalogue = await page.evaluate(() => ({
  inventoryTitle: document.querySelector("#inventory-title")?.textContent?.trim(),
  inventoryIcons: document.querySelectorAll(".quest-icon").length,
  chainRows: document.querySelectorAll(".chain-row").length,
}));
await page.evaluate((catalogue) => {
  window.__allLevelWorldIcons = catalogue.inventoryIcons;
  window.__allLevelWorldRows = catalogue.chainRows;
}, allLevelWorldCatalogue);
await page.selectOption("#zone-select", "10");
await page.waitForTimeout(300);
const duskwoodView = await page.evaluate(() => ({
  mapTitle: document.querySelector("#map-title")?.textContent?.trim(),
  inventoryTitle: document.querySelector("#inventory-title")?.textContent?.trim(),
  inventoryIcons: document.querySelectorAll(".quest-icon").length,
  chainRows: document.querySelectorAll(".chain-row").length,
  catalogueStableFromWorld: (
    document.querySelectorAll(".quest-icon").length === window.__allLevelWorldIcons &&
    document.querySelectorAll(".chain-row").length === window.__allLevelWorldRows
  ),
  mapMarkers: document.querySelectorAll(".map-marker").length,
  zoneImageLoaded: document.querySelector("#zone-image")?.complete,
  hasWorgenQuest: Boolean(document.querySelector('.quest-icon[data-quest-id="173"]')),
  dungeonQuestVisibleByDefault: Boolean(document.querySelector('.quest-icon[data-quest-id="377"]')),
  woolDonationVisibleByDefault: Boolean(document.querySelector('.quest-icon[data-quest-id="7791"]')),
  visibleQuestTypes: [...new Set([...document.querySelectorAll(".quest-icon")].flatMap((icon) => {
    const quest = DATA.quests.find((item) => item.id === Number(icon.dataset.questId));
    return quest?.typeIds || [];
  }))].sort(),
}));
await page.selectOption("#class-filter", "128");
await page.waitForTimeout(300);
await page.click('.quest-icon[data-quest-id="1939"]');
await page.waitForTimeout(200);
const objectiveZoneCatalogue = await page.evaluate(() => {
  const row = document.querySelector('.chain-row[data-chain-id="501"]');
  const pristine = DATA.quests.find((quest) => quest.id === 1940);
  return {
    pristineRoleZones: {
      start: pristine?.startZoneIds,
      objective: pristine?.objectiveZoneIds,
      end: pristine?.endZoneIds,
      involved: pristine?.zones,
    },
    chainSummary: row?.querySelector(".chain-zone-summary")?.textContent?.trim(),
    unselectedSummary: row?.querySelector('.chain-quest-item[data-quest-id="1940"] .quest-zone-summary')?.textContent?.trim(),
  };
});
if (
  objectiveZoneCatalogue.unselectedSummary !== "[Stormwind City -> Duskwood -> Stormwind City]" ||
  !objectiveZoneCatalogue.chainSummary?.includes("Duskwood") ||
  !objectiveZoneCatalogue.pristineRoleZones.objective?.includes(10)
) {
  throw new Error(`Expected objective zone to participate in catalogue summaries, got ${JSON.stringify(objectiveZoneCatalogue)}.`);
}
await page.click('.chain-quest-item[data-quest-id="1940"]');
await page.waitForTimeout(200);
const selectedObjectiveZone = await page.evaluate(() => {
  const detail = document.querySelector('.chain-quest-item[data-quest-id="1940"] .catalogue-objectives');
  const lastObjective = detail?.querySelector("li:last-child");
  const link = lastObjective?.querySelector(".zone-link");
  return {
    hasSeparateObjectiveZoneLine: Boolean(document.querySelector('.chain-quest-item[data-quest-id="1940"] .catalogue-objective-zone')),
    text: lastObjective?.textContent?.trim().replace(/\s+/g, " "),
    linkText: link?.textContent?.trim(),
    zoneId: link?.dataset.zoneId,
  };
});
if (
  selectedObjectiveZone.hasSeparateObjectiveZoneLine ||
  !selectedObjectiveZone.text?.endsWith("[Duskwood]") ||
  selectedObjectiveZone.linkText !== "Duskwood" ||
  selectedObjectiveZone.zoneId !== "10"
) {
  throw new Error(`Expected selected quest objective zone to be an inline suffix, got ${JSON.stringify(selectedObjectiveZone)}.`);
}
await page.selectOption("#class-filter", "1");
await page.waitForTimeout(300);
const typeBadgeView = await page.evaluate(() => {
  const visibleQuestIds = [...document.querySelectorAll(".quest-icon")]
    .map((icon) => Number(icon.dataset.questId))
    .filter(Number.isFinite);
  const dungeonQuest = visibleQuestIds
    .map((id) => DATA.quests.find((quest) => quest.id === id))
    .find((quest) => quest?.typeIds?.includes("dungeon"));
  const eliteQuest = visibleQuestIds
    .map((id) => DATA.quests.find((quest) => quest.id === id))
    .find((quest) => quest?.typeIds?.includes("elite"));
  const expandAndInspect = (quest) => {
    if (!quest) return null;
    const icon = document.querySelector(`.quest-icon[data-quest-id="${quest.id}"]`);
    icon?.click();
    const item = document.querySelector(`.chain-quest-item[data-quest-id="${quest.id}"]`);
    return {
      questId: quest.id,
      typeIds: quest.typeIds,
      collapsedDungeonBadge: Boolean(icon?.querySelector(".quest-type-badge.dungeon")),
      collapsedEliteBadge: Boolean(icon?.querySelector(".quest-type-badge.elite")),
      expandedDungeonBadge: Boolean(item?.querySelector(".chain-quest-step .quest-type-badge.dungeon")),
      expandedEliteBadge: Boolean(item?.querySelector(".chain-quest-step .quest-type-badge.elite")),
      titleBadges: [...(item?.querySelectorAll(".chain-quest-title-row .quest-type-text-badge") || [])].map((badge) => badge.textContent.trim()),
    };
  };
  return {
    dungeon: expandAndInspect(dungeonQuest),
    elite: expandAndInspect(eliteQuest),
  };
});
if (!typeBadgeView.dungeon?.collapsedDungeonBadge || !typeBadgeView.dungeon?.expandedDungeonBadge || !typeBadgeView.dungeon?.titleBadges.includes("[D]")) {
  throw new Error(`Expected dungeon badges in collapsed and expanded catalogue views, got ${JSON.stringify(typeBadgeView)}.`);
}
if (!typeBadgeView.elite?.collapsedEliteBadge || !typeBadgeView.elite?.expandedEliteBadge || !typeBadgeView.elite?.titleBadges.includes("[E]")) {
  throw new Error(`Expected elite badges in collapsed and expanded catalogue views, got ${JSON.stringify(typeBadgeView)}.`);
}

await page.selectOption("#level-filter", "24");
await page.waitForTimeout(300);

await page.hover('.quest-icon[data-quest-id="173"]');
await page.waitForTimeout(200);

const afterHover = await page.evaluate(() => {
  const activeQuestId = Number(document.querySelector(".chain-quest-item.active, .quest-icon.active")?.dataset.questId);
  const activeQuest = DATA.quests.find((quest) => quest.id === activeQuestId);
  return {
    activeName: activeQuest ? `${activeQuest.name} #${activeQuest.id}` : null,
    activeIcon: document.querySelector('.quest-icon[data-quest-id="173"]')?.classList.contains("active"),
    pickupPins: document.querySelectorAll(".quest-pin.pickup").length,
    turninPins: document.querySelectorAll(".quest-pin.turnin").length,
    objectiveDots: document.querySelectorAll(".objective-dot").length,
    objectiveAreas: document.querySelectorAll(".objective-area").length,
  };
});
if (
  afterHover.activeName ||
  afterHover.activeIcon ||
  afterHover.pickupPins ||
  afterHover.turninPins ||
  afterHover.objectiveDots ||
  afterHover.objectiveAreas
) {
  throw new Error(`Hovering a quest should not preview map details, got ${JSON.stringify(afterHover)}.`);
}

const worgenChainId = await page.getAttribute('.quest-icon[data-quest-id="173"]', "data-chain-id");
await page.click('.quest-icon[data-quest-id="173"]');
await page.waitForTimeout(200);
const chainExpansion = await page.evaluate((chainId) => {
  const row = document.querySelector(`.chain-row[data-chain-id="${chainId}"]`);
  const list = document.querySelector("#chain-list");
  return {
    expanded: row?.classList.contains("expanded"),
    ariaExpanded: row?.getAttribute("aria-expanded"),
    verticalQuestItems: row?.querySelectorAll(".chain-quest-item").length ?? 0,
    trackDisplay: row ? getComputedStyle(row.querySelector(".chain-track")).display : null,
    chainTopOffset: row && list ? row.getBoundingClientRect().top - list.getBoundingClientRect().top : null,
    chainZoneSummary: row?.querySelector(".chain-zone-summary")?.textContent?.trim(),
    unselectedQuestZoneSummaries: row ? [...row.querySelectorAll(".chain-quest-item:not(.selected) .quest-zone-summary")].map((item) => item.textContent.trim()) : [],
    selectedInlineZoneSummary: row?.querySelector(".chain-quest-item.selected .quest-zone-summary")?.textContent?.trim() || null,
    chainTitleDifficulty: row?.querySelector(".chain-name-text")?.dataset.difficulty,
    chainTitleColor: row?.querySelector(".chain-name-text") ? getComputedStyle(row.querySelector(".chain-name-text")).color : null,
    selectedQuestDifficulty: row?.querySelector(".chain-quest-item.selected .chain-quest-title")?.dataset.difficulty,
    selectedQuestColor: row?.querySelector(".chain-quest-item.selected .chain-quest-title") ? getComputedStyle(row.querySelector(".chain-quest-item.selected .chain-quest-title")).color : null,
    wowheadLinks: row ? [...row.querySelectorAll(".chain-quest-item .quest-wowhead-link")].map((link) => ({
      questId: Number(link.closest(".chain-quest-item")?.dataset.questId),
      href: link.getAttribute("href"),
      target: link.getAttribute("target"),
      rel: link.getAttribute("rel"),
      hasSvg: Boolean(link.querySelector("svg")),
      previousClass: link.previousElementSibling?.className,
      inTitleRow: Boolean(link.closest(".chain-quest-title-row")),
      verticalDeltaFromMeta: (() => {
        const meta = link.previousElementSibling;
        if (!meta) return null;
        const linkRect = link.getBoundingClientRect();
        const metaRect = meta.getBoundingClientRect();
        return Math.abs((linkRect.top + linkRect.height / 2) - (metaRect.top + metaRect.height / 2));
      })(),
    })) : [],
    bigGameHunterUrl: questWowheadUrl(DATA.quests.find((quest) => quest.id === 208)),
    collapsedIconDifficulty: row?.querySelector('.quest-icon[data-quest-id="173"]')?.dataset.difficulty,
    collapsedIconBorderColor: row?.querySelector('.quest-icon[data-quest-id="173"]') ? getComputedStyle(row.querySelector('.quest-icon[data-quest-id="173"]')).borderColor : null,
    unselectedQuestDifficulties: row ? [...row.querySelectorAll(".chain-quest-item:not(.selected) .chain-quest-title")].map((item) => item.dataset.difficulty) : [],
    chainLevelText: row?.querySelector(".chain-level")?.textContent?.trim(),
    questMetas: row ? [...row.querySelectorAll(".chain-quest-meta")].map((item) => item.textContent.trim()) : [],
  };
}, worgenChainId);
if (!chainExpansion.expanded || chainExpansion.verticalQuestItems < 4 || chainExpansion.trackDisplay !== "none") {
  throw new Error(`Expected clicked quest chain to expand vertically, got ${JSON.stringify(chainExpansion)}.`);
}
if (!chainExpansion.chainZoneSummary?.includes("Duskwood")) {
  throw new Error(`Expected chain zone summary to include Duskwood, got ${JSON.stringify(chainExpansion)}.`);
}
if (!chainExpansion.unselectedQuestZoneSummaries.some((summary) => summary.includes("Duskwood"))) {
  throw new Error(`Expected unselected expanded quests to show zone summaries, got ${JSON.stringify(chainExpansion)}.`);
}
if (chainExpansion.selectedInlineZoneSummary) {
  throw new Error(`Selected quest should use the detail block instead of inline zone summary, got ${JSON.stringify(chainExpansion)}.`);
}
if (chainExpansion.chainTitleDifficulty !== "orange" || chainExpansion.selectedQuestDifficulty !== "orange") {
  throw new Error(`Expected level 28 Worgen quest to be orange for a level 24 character, got ${JSON.stringify(chainExpansion)}.`);
}
if (!chainExpansion.selectedQuestColor?.includes("255, 128, 64")) {
  throw new Error(`Expected selected Worgen quest title to render orange, got ${JSON.stringify(chainExpansion)}.`);
}
if (chainExpansion.collapsedIconDifficulty !== "orange" || !chainExpansion.collapsedIconBorderColor?.includes("255, 128, 64")) {
  throw new Error(`Expected collapsed Worgen quest icon ring to render orange, got ${JSON.stringify(chainExpansion)}.`);
}
if (chainExpansion.chainLevelText?.includes("Req") || chainExpansion.questMetas.some((item) => /\bReq\b|\/\s*Q\b/.test(item))) {
  throw new Error(`Expected compact level text without Req/Q labels, got ${JSON.stringify(chainExpansion)}.`);
}
const worgenWowheadLink = chainExpansion.wowheadLinks.find((link) => link.questId === 173);
if (
  chainExpansion.wowheadLinks.length !== chainExpansion.verticalQuestItems ||
  !worgenWowheadLink ||
  worgenWowheadLink.href !== "https://www.wowhead.com/classic/quest=173/worgen-in-the-woods" ||
  worgenWowheadLink.target !== "_blank" ||
  !worgenWowheadLink.rel?.includes("noopener") ||
  !worgenWowheadLink.rel?.includes("noreferrer") ||
  !worgenWowheadLink.hasSvg ||
  worgenWowheadLink.previousClass !== "chain-quest-meta" ||
  worgenWowheadLink.inTitleRow ||
  worgenWowheadLink.verticalDeltaFromMeta > 1.5 ||
  chainExpansion.bigGameHunterUrl !== "https://www.wowhead.com/classic/quest=208/big-game-hunter"
) {
  throw new Error(`Expected expanded catalogue quests to include Wowhead external links, got ${JSON.stringify(chainExpansion)}.`);
}

const keyboardNavExpected = await page.evaluate(() => {
  const order = currentChains().flatMap((chain) => chain.visibleQuests.map((quest) => ({
    id: quest.id,
    chainId: quest.chainId,
    name: quest.name,
  })));
  const firstWorgenIndex = order.findIndex((quest) => quest.id === 173);
  const lastWorgenIndex = order.findIndex((quest) => quest.id === 223);
  return {
    firstWorgenNext: order[firstWorgenIndex + 1] || null,
    lastWorgenNext: order[lastWorgenIndex + 1] || null,
  };
});
await page.keyboard.press("ArrowDown");
await page.waitForTimeout(150);
const keyboardAfterDown = await page.evaluate(() => ({
  selectedId: Number(document.querySelector(".chain-quest-item.selected")?.dataset.questId),
  activeId: Number(document.querySelector(".chain-quest-item.active")?.dataset.questId),
  focusedId: Number(document.activeElement?.closest(".chain-quest-item, .quest-icon")?.dataset.questId),
}));
await page.keyboard.press("ArrowUp");
await page.waitForTimeout(150);
const keyboardAfterUp = await page.evaluate(() => ({
  selectedId: Number(document.querySelector(".chain-quest-item.selected")?.dataset.questId),
  activeId: Number(document.querySelector(".chain-quest-item.active")?.dataset.questId),
}));
await page.click('.chain-quest-item[data-quest-id="223"]');
await page.waitForTimeout(150);
await page.keyboard.press("ArrowDown");
await page.waitForTimeout(150);
const keyboardAfterChainBoundary = await page.evaluate(() => {
  const selected = document.querySelector(".chain-quest-item.selected");
  const row = selected?.closest(".chain-row");
  const list = document.querySelector("#chain-list");
  const selectedRect = selected?.getBoundingClientRect();
  const listRect = list?.getBoundingClientRect();
  return {
    selectedId: Number(selected?.dataset.questId),
    selectedChainId: Number(selected?.dataset.chainId),
    selectedRowExpanded: row?.classList.contains("expanded"),
    visibleInCatalogue: Boolean(selectedRect && listRect && selectedRect.bottom >= listRect.top && selectedRect.top <= listRect.bottom),
  };
});
const catalogueKeyboardNav = {
  expected: keyboardNavExpected,
  afterDown: keyboardAfterDown,
  afterUp: keyboardAfterUp,
  afterChainBoundary: keyboardAfterChainBoundary,
};
if (
  keyboardAfterDown.selectedId !== keyboardNavExpected.firstWorgenNext?.id ||
  keyboardAfterDown.activeId !== keyboardNavExpected.firstWorgenNext?.id ||
  keyboardAfterDown.focusedId !== keyboardNavExpected.firstWorgenNext?.id
) {
  throw new Error(`Expected ArrowDown to select the next quest in the catalogue, got ${JSON.stringify(catalogueKeyboardNav)}.`);
}
if (keyboardAfterUp.selectedId !== 173 || keyboardAfterUp.activeId !== 173) {
  throw new Error(`Expected ArrowUp to return to the previous quest, got ${JSON.stringify(catalogueKeyboardNav)}.`);
}
if (
  !keyboardNavExpected.lastWorgenNext ||
  keyboardNavExpected.lastWorgenNext.chainId === Number(worgenChainId) ||
  keyboardAfterChainBoundary.selectedId !== keyboardNavExpected.lastWorgenNext.id ||
  keyboardAfterChainBoundary.selectedChainId !== keyboardNavExpected.lastWorgenNext.chainId ||
  !keyboardAfterChainBoundary.selectedRowExpanded ||
  !keyboardAfterChainBoundary.visibleInCatalogue
) {
  throw new Error(`Expected ArrowDown at the end of a chain to continue into the next chain, got ${JSON.stringify(catalogueKeyboardNav)}.`);
}
await page.click('.chain-quest-item[data-quest-id="173"]');
await page.waitForTimeout(200);

const afterPinnedClick = await page.evaluate(() => ({
  activeName: (() => {
    const activeQuestId = Number(document.querySelector(".chain-quest-item.active, .quest-icon.active")?.dataset.questId);
    const activeQuest = DATA.quests.find((quest) => quest.id === activeQuestId);
    return activeQuest ? `${activeQuest.name} #${activeQuest.id}` : null;
  })(),
  selectedIcon: document.querySelector('.quest-icon[data-quest-id="173"]')?.classList.contains("selected"),
  selectedExpandedItem: document.querySelector('.chain-quest-item[data-quest-id="173"]')?.classList.contains("selected"),
  catalogueDetailVisible: Boolean(document.querySelector('.chain-quest-item[data-quest-id="173"] .chain-quest-detail')),
  catalogueDetailText: document.querySelector('.chain-quest-item[data-quest-id="173"] .chain-quest-detail')?.textContent?.replace(/\s+/g, " ").trim(),
  catalogueZoneLinks: [...document.querySelectorAll('.chain-quest-item[data-quest-id="173"] .zone-link')].map((link) => ({
    zoneId: link.dataset.zoneId,
    text: link.textContent.trim(),
  })),
  selectedObjectiveColor: document.querySelector("#highlight-layer")?.style.getPropertyValue("--chain-color"),
  expectedObjectiveColor: questObjectiveColor(DATA.quests.find((quest) => quest.id === 173)),
  selectedQuestChainColor: DATA.quests.find((quest) => quest.id === 173)?.chainColor,
}));
if (!afterPinnedClick.catalogueDetailText?.includes("Prerequisites")) {
  throw new Error(`Expected selected quest details to include prerequisites, got ${JSON.stringify(afterPinnedClick)}.`);
}
if (
  afterPinnedClick.selectedObjectiveColor !== afterPinnedClick.expectedObjectiveColor ||
  afterPinnedClick.selectedObjectiveColor === afterPinnedClick.selectedQuestChainColor
) {
  throw new Error(`Expected selected quest objective overlays to use quest-specific color, got ${JSON.stringify(afterPinnedClick)}.`);
}

await page.hover('.quest-icon[data-quest-id="377"]');
await page.waitForTimeout(200);
const afterPinnedHover = await page.evaluate(() => ({
  activeName: (() => {
    const activeQuestId = Number(document.querySelector(".chain-quest-item.active, .quest-icon.active")?.dataset.questId);
    const activeQuest = DATA.quests.find((quest) => quest.id === activeQuestId);
    return activeQuest ? `${activeQuest.name} #${activeQuest.id}` : null;
  })(),
  worgenStillActive: document.querySelector('.chain-quest-item[data-quest-id="173"]')?.classList.contains("active"),
  crimeNotActive: document.querySelector('.quest-icon[data-quest-id="377"]')?.classList.contains("active"),
}));

await page.click("#world-button");
await page.waitForTimeout(200);
await page.click('.chain-quest-item[data-quest-id="173"] .zone-link[data-zone-id="10"]');
await page.waitForTimeout(300);
const afterZoneLink = await page.evaluate(() => ({
  mapTitle: document.querySelector("#map-title")?.textContent?.trim(),
  zoneSelectValue: document.querySelector("#zone-select")?.value,
  inventoryIcons: document.querySelectorAll(".quest-icon").length,
  chainRows: document.querySelectorAll(".chain-row").length,
  selectedStillPinned: document.querySelector('.chain-quest-item[data-quest-id="173"]')?.classList.contains("selected"),
}));

const catalogueClickScroll = await page.evaluate(() => {
  const list = document.querySelector("#chain-list");
  const icon = document.querySelector('.quest-icon[data-quest-id="377"]') || document.querySelector('.quest-icon:not([data-quest-id="173"])');
  if (!list || !icon) return { tested: false };
  list.scrollTop = Math.min(220, Math.max(0, list.scrollHeight - list.clientHeight));
  const before = list.scrollTop;
  icon.click();
  const after = list.scrollTop;
  return {
    tested: true,
    questId: icon.dataset.questId,
    before,
    after,
    delta: after - before,
  };
});
if (!catalogueClickScroll.tested || Math.abs(catalogueClickScroll.delta) > 2) {
  throw new Error(`Expected catalogue-origin quest selection to preserve scroll position, got ${JSON.stringify(catalogueClickScroll)}.`);
}

await page.click("#display-filter-button");
await page.check('#display-filter-menu input[value="available-pickups"]');
await page.waitForTimeout(300);
const displayPickupView = await page.evaluate(() => {
  const markers = [...document.querySelectorAll(".map-marker.available-pickup")];
  const centers = markers.map((marker) => {
    const rect = marker.getBoundingClientRect();
    return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
  });
  let minPickupCenterDistance = null;
  for (let i = 0; i < centers.length; i += 1) {
    for (let j = i + 1; j < centers.length; j += 1) {
      const distance = Math.hypot(centers[i].x - centers[j].x, centers[i].y - centers[j].y);
      minPickupCenterDistance = minPickupCenterDistance === null ? distance : Math.min(minPickupCenterDistance, distance);
    }
  }
  const worgenMarker = markers.find((marker) => marker.dataset.questIds?.includes("|173|"));
  const singleMarker = markers.find((marker) => !marker.querySelector(".pickup-count") && marker.dataset.difficulty && marker.dataset.difficulty !== "none");
  return {
    checkedDisplayOptions: [...document.querySelectorAll("#display-filter-menu input:checked")].map((input) => input.value),
    displayFilterCount: document.querySelector("#display-filter-count")?.textContent?.trim(),
    pickupMarkers: markers.length,
    multiPickupMarkers: markers.filter((marker) => marker.querySelector(".pickup-count")).length,
    minPickupCenterDistance,
    worgenMarkerCount: worgenMarker?.querySelector(".pickup-count")?.textContent?.trim() || "1",
    worgenMarkerQuestIds: worgenMarker?.dataset.questIds,
    worgenMarkerDifficulty: worgenMarker?.dataset.difficulty,
    worgenMarkerRing: worgenMarker?.dataset.ring,
    worgenMarkerRingStyle: worgenMarker?.style.getPropertyValue("--pickup-ring") || null,
    worgenMarkerBackground: worgenMarker ? getComputedStyle(worgenMarker).backgroundImage : null,
    singleMarkerDifficulty: singleMarker?.dataset.difficulty,
    singleMarkerRing: singleMarker?.dataset.ring,
    singleMarkerRingStyle: singleMarker?.style.getPropertyValue("--pickup-ring") || null,
    singleMarkerBackground: singleMarker ? getComputedStyle(singleMarker).backgroundImage : null,
    dungeonBadgeMarkers: markers.filter((marker) => marker.querySelector(".quest-type-badge.dungeon")).length,
    eliteBadgeMarkers: markers.filter((marker) => marker.querySelector(".quest-type-badge.elite")).length,
  };
});
if (displayPickupView.minPickupCenterDistance !== null && displayPickupView.minPickupCenterDistance < 28) {
  throw new Error(`Pickup markers are still overlapping; minimum center distance was ${displayPickupView.minPickupCenterDistance.toFixed(1)}px.`);
}
if (displayPickupView.worgenMarkerDifficulty !== "multi" || displayPickupView.worgenMarkerRing !== "difficulty" || !displayPickupView.worgenMarkerRingStyle?.includes("conic-gradient")) {
  throw new Error(`Expected multi-quest pickup marker ring to use a difficulty gradient, got ${JSON.stringify(displayPickupView)}.`);
}
if (!displayPickupView.singleMarkerDifficulty || displayPickupView.singleMarkerRing !== "difficulty" || !displayPickupView.singleMarkerRingStyle) {
  throw new Error(`Expected single pickup marker ring to use a difficulty color, got ${JSON.stringify(displayPickupView)}.`);
}
if (!displayPickupView.dungeonBadgeMarkers || !displayPickupView.eliteBadgeMarkers) {
  throw new Error(`Expected dungeon and elite badges on visible map pickup markers, got ${JSON.stringify(displayPickupView)}.`);
}
await page.check('#display-filter-menu input[value="quest-objectives"]');
await page.check('#display-filter-menu input[value="quest-handins"]');
await page.waitForTimeout(300);
const displayLocationMarkers = await page.evaluate(() => ({
  checkedDisplayOptions: [...document.querySelectorAll("#display-filter-menu input:checked")].map((input) => input.value),
  displayFilterCount: document.querySelector("#display-filter-count")?.textContent?.trim(),
  pickupMarkers: document.querySelectorAll(".map-marker.available-pickup").length,
  objectiveMarkers: document.querySelectorAll(".map-marker.available-objective").length,
  handinMarkers: document.querySelectorAll(".map-marker.available-handin").length,
  objectiveCountBadges: document.querySelectorAll(".map-marker.available-objective .pickup-count").length,
  objectiveTypeBadges: document.querySelectorAll(".map-marker.available-objective .quest-type-badge").length,
  handinTypeBadges: document.querySelectorAll(".map-marker.available-handin .quest-type-badge").length,
  objectiveMarkerTitle: document.querySelector(".map-marker.available-objective")?.getAttribute("title"),
  handinMarkerTitle: document.querySelector(".map-marker.available-handin")?.getAttribute("title"),
  sameChainObjectiveColors: [173, 221, 222, 223]
    .map((questId) => document.querySelector(`.map-marker.available-objective[data-quest-id="${questId}"]`)?.style.getPropertyValue("--chain-color"))
    .filter(Boolean),
  objectiveStyle: (() => {
    const marker = document.querySelector(".map-marker.available-objective");
    if (!marker) return null;
    const styles = getComputedStyle(marker);
    return {
      width: styles.width,
      height: styles.height,
      backgroundColor: styles.backgroundColor,
      questId: Number(marker.dataset.questId),
      chainColor: marker.style.getPropertyValue("--chain-color"),
      expectedObjectiveColor: questObjectiveColor(DATA.quests.find((quest) => quest.id === Number(marker.dataset.questId))),
      questChainColor: DATA.quests.find((quest) => quest.id === Number(marker.dataset.questId))?.chainColor,
      glyphDisplay: marker.querySelector(".display-marker-glyph") ? getComputedStyle(marker.querySelector(".display-marker-glyph")).display : null,
    };
  })(),
}));
if (
  displayLocationMarkers.displayFilterCount !== "3" ||
  !displayLocationMarkers.checkedDisplayOptions.includes("quest-objectives") ||
  !displayLocationMarkers.checkedDisplayOptions.includes("quest-handins") ||
  displayLocationMarkers.objectiveMarkers <= 0 ||
  displayLocationMarkers.handinMarkers <= 0 ||
  displayLocationMarkers.objectiveCountBadges !== 0 ||
  displayLocationMarkers.objectiveTypeBadges !== 0 ||
  displayLocationMarkers.handinTypeBadges !== 0 ||
  displayLocationMarkers.objectiveMarkerTitle !== null ||
  displayLocationMarkers.handinMarkerTitle !== null ||
  displayLocationMarkers.objectiveStyle?.width !== "8px" ||
  displayLocationMarkers.objectiveStyle?.height !== "8px" ||
  !displayLocationMarkers.objectiveStyle?.chainColor ||
  displayLocationMarkers.objectiveStyle?.chainColor !== displayLocationMarkers.objectiveStyle?.expectedObjectiveColor ||
  displayLocationMarkers.objectiveStyle?.chainColor === displayLocationMarkers.objectiveStyle?.questChainColor ||
  new Set(displayLocationMarkers.sameChainObjectiveColors).size <= 1 ||
  displayLocationMarkers.objectiveStyle?.glyphDisplay !== "none"
) {
  throw new Error(`Expected plain quest-colored objective dots and unbadged hand-in markers, got ${JSON.stringify(displayLocationMarkers)}.`);
}
await page.keyboard.press("Escape");
const objectiveDisplayTooltip = await page.evaluate(() => {
  const marker = document.querySelector(".map-marker.available-objective");
  marker?.dispatchEvent(new MouseEvent("mouseenter", { bubbles: true }));
  const popover = document.querySelector(".pickup-choice-popover");
  return {
    visible: Boolean(popover),
    title: document.querySelector(".pickup-choice-title")?.textContent?.trim(),
    note: document.querySelector(".pickup-choice-note")?.textContent?.trim(),
    itemCount: document.querySelectorAll(".pickup-choice-item").length,
    popoverZIndex: popover ? Number(getComputedStyle(popover).zIndex) : null,
    markerZIndex: marker ? Number(getComputedStyle(marker).zIndex) || 0 : null,
  };
});
if (
  !objectiveDisplayTooltip.visible ||
  !objectiveDisplayTooltip.title?.startsWith("Quest objective") ||
  !objectiveDisplayTooltip.note?.includes("Objective location") ||
  objectiveDisplayTooltip.itemCount <= 0 ||
  objectiveDisplayTooltip.popoverZIndex <= objectiveDisplayTooltip.markerZIndex
) {
  throw new Error(`Expected hovering an objective marker to show an explanatory tooltip above markers, got ${JSON.stringify(objectiveDisplayTooltip)}.`);
}
const handinDisplayTooltip = await page.evaluate(() => {
  const marker = document.querySelector(".map-marker.available-handin");
  marker?.dispatchEvent(new MouseEvent("mouseenter", { bubbles: true }));
  const popover = document.querySelector(".pickup-choice-popover");
  return {
    visible: Boolean(popover),
    title: document.querySelector(".pickup-choice-title")?.textContent?.trim(),
    note: document.querySelector(".pickup-choice-note")?.textContent?.trim(),
    itemCount: document.querySelectorAll(".pickup-choice-item").length,
  };
});
if (
  !handinDisplayTooltip.visible ||
  !handinDisplayTooltip.title?.startsWith("Quest hand-in") ||
  !handinDisplayTooltip.note?.includes("Turn-in location") ||
  handinDisplayTooltip.itemCount <= 0
) {
  throw new Error(`Expected hovering a hand-in marker to show an explanatory tooltip, got ${JSON.stringify(handinDisplayTooltip)}.`);
}
await page.click("#display-filter-button");
await page.uncheck('#display-filter-menu input[value="quest-objectives"]');
await page.uncheck('#display-filter-menu input[value="quest-handins"]');
await page.waitForTimeout(300);
const typedPickupPicker = await page.evaluate(() => {
  const marker = [...document.querySelectorAll(".map-marker.available-pickup")]
    .find((item) => item.querySelector(".quest-type-badge.dungeon, .quest-type-badge.elite"));
  if (!marker) return { visible: false };
  marker.dispatchEvent(new MouseEvent("mouseenter", { bubbles: true }));
  const popover = document.querySelector(".pickup-choice-popover");
  return {
    visible: Boolean(popover),
    markerHasDungeonBadge: Boolean(marker.querySelector(".quest-type-badge.dungeon")),
    markerHasEliteBadge: Boolean(marker.querySelector(".quest-type-badge.elite")),
    pickerTextBadges: [...document.querySelectorAll(".pickup-choice-item .quest-type-text-badge")].map((badge) => badge.textContent.trim()),
  };
});
if (!typedPickupPicker.visible || (typedPickupPicker.markerHasDungeonBadge && !typedPickupPicker.pickerTextBadges.includes("[D]")) || (typedPickupPicker.markerHasEliteBadge && !typedPickupPicker.pickerTextBadges.includes("[E]"))) {
  throw new Error(`Expected picker quest names to show dungeon/elite text badges matching marker badges, got ${JSON.stringify(typedPickupPicker)}.`);
}
await page.keyboard.press("Escape");
await page.keyboard.press("Escape");
await page.hover('.map-marker.available-pickup[data-quest-ids*="|173|"]');
await page.waitForTimeout(200);
const hoverPickupPicker = await page.evaluate(() => {
  const marker = document.querySelector('.map-marker.available-pickup[data-quest-ids*="|173|"]');
  const popover = document.querySelector(".pickup-choice-popover");
  return {
    visible: Boolean(popover),
    markerTitle: marker?.getAttribute("title"),
    itemCount: document.querySelectorAll(".pickup-choice-item").length,
    title: document.querySelector(".pickup-choice-title")?.textContent?.trim(),
  };
});
if (!hoverPickupPicker.visible || hoverPickupPicker.markerTitle !== null || hoverPickupPicker.itemCount < 2) {
  throw new Error(`Expected hovering a multi-quest pickup to show picker without native title tooltip, got ${JSON.stringify(hoverPickupPicker)}.`);
}
const hoverBox = await page.locator(".pickup-choice-popover").boundingBox();
if (hoverBox) {
  await page.mouse.move(hoverBox.x + Math.min(12, hoverBox.width / 2), hoverBox.y + Math.min(12, hoverBox.height / 2));
}
await page.waitForTimeout(260);
const hoverPopoverPersisted = await page.evaluate(() => Boolean(document.querySelector(".pickup-choice-popover")));
if (!hoverPopoverPersisted) {
  throw new Error("Expected pickup picker to remain visible while the mouse is over the picker.");
}
await page.mouse.move(4, 4);
await page.waitForTimeout(320);
const hoverPopoverClosed = await page.evaluate(() => !document.querySelector(".pickup-choice-popover"));
if (!hoverPopoverClosed) {
  throw new Error("Expected pickup picker to close after leaving both marker and picker.");
}

await page.hover('.map-marker.available-pickup:not(:has(.pickup-count))');
await page.waitForTimeout(200);
const singleHoverPicker = await page.evaluate(() => ({
  visible: Boolean(document.querySelector(".pickup-choice-popover")),
  itemCount: document.querySelectorAll(".pickup-choice-item").length,
}));
if (!singleHoverPicker.visible || singleHoverPicker.itemCount !== 1) {
  throw new Error(`Expected hovering a single-quest pickup to show a one-quest picker, got ${JSON.stringify(singleHoverPicker)}.`);
}
await page.mouse.move(4, 4);
await page.waitForTimeout(320);

let pickupChainDivider = null;
const dividerMarkerCount = await page.locator(".map-marker.available-pickup").count();
for (let index = 0; index < dividerMarkerCount; index += 1) {
  await page.locator(".map-marker.available-pickup").nth(index).hover();
  await page.waitForTimeout(80);
  const probe = await page.evaluate(() => {
    const popover = document.querySelector(".pickup-choice-popover");
    if (!popover) return { visible: false };
    const sections = [...popover.querySelectorAll(".pickup-choice-section")].map((section) => {
      const chains = [...section.querySelectorAll(".pickup-choice-meta")].map((meta) => meta.textContent.split(" - ").slice(1).join(" - "));
      return {
        chainCount: new Set(chains).size,
        itemCount: section.querySelectorAll(".pickup-choice-item").length,
        dividerCount: section.querySelectorAll(".pickup-choice-chain-break").length,
        chains,
      };
    });
    const matchingSection = sections.find((section) => section.chainCount > 1);
    return {
      visible: true,
      dividerCount: popover.querySelectorAll(".pickup-choice-chain-break").length,
      matchingSection,
    };
  });
  if (probe.matchingSection) {
    pickupChainDivider = probe;
    break;
  }
}
await page.mouse.move(4, 4);
await page.waitForTimeout(320);
if (!pickupChainDivider?.matchingSection || pickupChainDivider.matchingSection.dividerCount <= 0) {
  throw new Error(`Expected a same-source multi-chain pickup picker to show chain dividers, got ${JSON.stringify(pickupChainDivider)}.`);
}

const searchCandidate = await page.evaluate(() => {
  const stopWords = new Set(["the", "and", "for", "from", "with", "into", "your", "you", "that", "this", "return"]);
  const rows = [...document.querySelectorAll(".chain-row")];
  for (const row of rows) {
    const quests = [...row.querySelectorAll(".quest-icon")]
      .map((icon) => DATA.quests.find((quest) => quest.id === Number(icon.dataset.questId)))
      .filter(Boolean);
    if (quests.length < 2) continue;
    const hasVisiblePickup = quests.some((quest) => (
      currentView.type === "world" ||
      quest.startPoints?.some((point) => point.zoneId === currentView.zoneId)
    ));
    if (!hasVisiblePickup) continue;
    const tokens = [...new Set(quests.flatMap((quest) => quest.name.toLowerCase().match(/[a-z][a-z0-9']{3,}/g) || []))]
      .filter((token) => !stopWords.has(token));
    for (const term of tokens) {
      const matching = quests.filter((quest) => quest.name.toLowerCase().includes(term));
      const nonmatching = quests.filter((quest) => !quest.name.toLowerCase().includes(term));
      if (matching.length && nonmatching.length) {
        return {
          term,
          chainId: row.dataset.chainId,
          matchingQuestId: matching[0].id,
          nonmatchingQuestId: nonmatching[0].id,
        };
      }
    }
  }
  return null;
});
if (!searchCandidate) {
  throw new Error("Expected to find a visible multi-quest chain suitable for search testing.");
}
await page.fill("#quest-search", searchCandidate.term);
await page.waitForTimeout(250);
const searchView = await page.evaluate((candidate) => {
  const questIdsFromMarkers = [...document.querySelectorAll(".map-marker.available-pickup")]
    .flatMap((marker) => (marker.dataset.questIds || "")
      .split("|")
      .filter(Boolean)
      .map((id) => Number(id))
      .filter(Number.isFinite));
  const visibleRows = [...document.querySelectorAll(".chain-row")].map((row) => {
    const quests = [...row.querySelectorAll(".quest-icon")]
      .map((icon) => DATA.quests.find((quest) => quest.id === Number(icon.dataset.questId)))
      .filter(Boolean);
    return {
      chainId: row.dataset.chainId,
      questIds: quests.map((quest) => quest.id),
      names: quests.map((quest) => quest.name),
    };
  });
  const visibleChainIds = new Set(visibleRows.map((row) => row.chainId));
  const candidateRow = visibleRows.find((row) => row.chainId === candidate.chainId);
  return {
    searchValue: document.querySelector("#quest-search")?.value,
    chainRows: document.querySelectorAll(".chain-row").length,
    pickupMarkers: document.querySelectorAll(".map-marker.available-pickup").length,
    candidate,
    candidateRowVisible: Boolean(candidateRow),
    candidateMatchingQuestVisible: Boolean(candidateRow?.questIds.includes(candidate.matchingQuestId)),
    candidateNonmatchingQuestVisible: Boolean(candidateRow?.questIds.includes(candidate.nonmatchingQuestId)),
    catalogueChainsAllHaveMatch: visibleRows.length > 0 && visibleRows.every((row) => row.names.some((name) => name.toLowerCase().includes(candidate.term))),
    pickupMarkersStayWithinVisibleChains: questIdsFromMarkers.length > 0 && questIdsFromMarkers.every((id) => {
      const quest = DATA.quests.find((item) => item.id === id);
      return quest && visibleChainIds.has(String(quest.chainId));
    }),
  };
}, searchCandidate);
if (
  !searchView.candidateRowVisible ||
  !searchView.candidateMatchingQuestVisible ||
  !searchView.candidateNonmatchingQuestVisible ||
  !searchView.catalogueChainsAllHaveMatch ||
  !searchView.pickupMarkers ||
  !searchView.pickupMarkersStayWithinVisibleChains
) {
  throw new Error(`Expected quest search to show whole matching chains and their pickup markers, got ${JSON.stringify(searchView)}.`);
}
const clearSearchView = await page.evaluate(() => {
  const clear = document.querySelector("#quest-search-clear");
  const beforeRows = document.querySelectorAll(".chain-row").length;
  clear?.click();
  return {
    clearPresent: Boolean(clear),
    clearHidden: clear?.hidden,
    searchValue: document.querySelector("#quest-search")?.value,
    beforeRows,
    afterRows: document.querySelectorAll(".chain-row").length,
  };
});
if (!clearSearchView.clearPresent || clearSearchView.searchValue || clearSearchView.afterRows <= clearSearchView.beforeRows) {
  throw new Error(`Expected search clear button to reset the filter, got ${JSON.stringify(clearSearchView)}.`);
}
await page.waitForTimeout(250);

await page.selectOption("#level-filter", "all");
await page.fill("#quest-search", "Tiger Mastery");
await page.waitForTimeout(250);
await page.click('.quest-icon[data-quest-id="185"]');
await page.waitForTimeout(200);
const tigerGrouping = await page.evaluate(() => {
  const icon = document.querySelector('.quest-icon[data-quest-id="185"]');
  const row = icon?.closest(".chain-row");
  const expanded = row?.querySelector(".chain-expanded");
  const groups = [];
  let current = [];
  [...(expanded?.children || [])].forEach((child) => {
    if (child.classList.contains("chain-group-break")) {
      if (current.length) groups.push(current);
      current = [];
      return;
    }
    if (child.classList.contains("chain-quest-item")) {
      const quest = DATA.quests.find((item) => item.id === Number(child.dataset.questId));
      current.push({
        id: Number(child.dataset.questId),
        name: quest?.name,
        groupId: quest?.chainGroupId,
        step: quest?.chainStep,
      });
    }
  });
  if (current.length) groups.push(current);
  return {
    expanded: row?.classList.contains("expanded"),
    breakCount: row?.querySelectorAll(".chain-group-break").length || 0,
    groups,
    visibleRows: document.querySelectorAll(".chain-row").length,
  };
});
const tigerExpectedGroups = [
  [583],
  [185, 186, 187, 188],
  [190, 191, 192, 193],
  [194, 195, 196, 197],
  [338, 339, 340, 341, 342],
  [208],
];
if (
  !tigerGrouping.expanded ||
  tigerGrouping.breakCount !== tigerExpectedGroups.length - 1 ||
  JSON.stringify(tigerGrouping.groups.map((group) => group.map((quest) => quest.id))) !== JSON.stringify(tigerExpectedGroups)
) {
  throw new Error(`Expected Nesingwary chain to be split into display groups, got ${JSON.stringify(tigerGrouping)}.`);
}
await page.fill("#quest-search", "");
await page.selectOption("#level-filter", "24");
await page.waitForTimeout(250);

await page.evaluate(() => {
  const marker = [...document.querySelectorAll(".map-marker.available-pickup")]
    .filter((item) => item.querySelector(".pickup-count"))
    .sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top)[0];
  marker?.click();
});
await page.waitForTimeout(200);
const topEdgePicker = await page.evaluate(() => {
  const popover = document.querySelector(".pickup-choice-popover");
  const map = document.querySelector("#map");
  const popoverRect = popover?.getBoundingClientRect();
  const mapRect = map?.getBoundingClientRect();
  return {
    visible: Boolean(popover),
    popoverTop: popoverRect?.top,
    popoverBottom: popoverRect?.bottom,
    mapTop: mapRect?.top,
    mapBottom: mapRect?.bottom,
  };
});
if (!topEdgePicker.visible || topEdgePicker.popoverTop < topEdgePicker.mapTop - 1 || topEdgePicker.popoverBottom > topEdgePicker.mapBottom + 1) {
  throw new Error(`Expected top-edge pickup picker to stay inside map bounds, got ${JSON.stringify(topEdgePicker)}.`);
}

await page.click('.map-marker.available-pickup[data-quest-ids*="|173|"]');
await page.waitForTimeout(200);
const pickupChoice = await page.evaluate(() => {
  const popover = document.querySelector(".pickup-choice-popover");
  return {
    visible: Boolean(popover),
    itemCount: document.querySelectorAll(".pickup-choice-item").length,
    questIds: [...document.querySelectorAll(".pickup-choice-item")].map((item) => item.dataset.questId),
    title: document.querySelector(".pickup-choice-title")?.textContent?.trim(),
    headings: [...document.querySelectorAll(".pickup-choice-heading")].map((item) => item.textContent.trim()),
    maxHeight: popover ? getComputedStyle(popover).maxHeight : null,
    popoverZIndex: popover ? Number(getComputedStyle(popover).zIndex) : null,
    markerLayerZIndex: Number(getComputedStyle(document.querySelector("#map-marker-layer")).zIndex),
    highlightLayerZIndex: Number(getComputedStyle(document.querySelector("#highlight-layer")).zIndex),
    metas: [...document.querySelectorAll(".pickup-choice-meta")].map((item) => item.textContent.trim()),
    nameDifficulties: [...document.querySelectorAll(".pickup-choice-item")].map((item) => ({
      questId: item.dataset.questId,
      difficulty: item.querySelector(".pickup-choice-name")?.dataset.difficulty,
      color: getComputedStyle(item.querySelector(".pickup-choice-name")).color,
    })),
  };
});
if (pickupChoice.title !== "Calor" || pickupChoice.headings.length !== 0) {
  throw new Error(`Expected grouped Worgen pickup to include Calor, got title ${pickupChoice.title} and headings ${pickupChoice.headings.join(", ")}.`);
}
if (parseFloat(pickupChoice.maxHeight) < 500) {
  throw new Error(`Expected taller pickup picker max-height, got ${pickupChoice.maxHeight}.`);
}
if (pickupChoice.markerLayerZIndex <= pickupChoice.highlightLayerZIndex || pickupChoice.popoverZIndex < 80) {
  throw new Error(`Expected pickup picker to render above objective overlays, got ${JSON.stringify(pickupChoice)}.`);
}
const worgenPickerName = pickupChoice.nameDifficulties.find((item) => item.questId === "173");
if (worgenPickerName?.difficulty !== "orange" || !worgenPickerName.color?.includes("255, 128, 64")) {
  throw new Error(`Expected Worgen quest picker name to render orange, got ${JSON.stringify(pickupChoice)}.`);
}
if (pickupChoice.metas.some((item) => /\bReq\b|\/\s*Q\b/.test(item))) {
  throw new Error(`Expected compact quest picker level text without Req/Q labels, got ${JSON.stringify(pickupChoice)}.`);
}
const pickupChoiceQuestId = await page.evaluate(() => {
  const items = [...document.querySelectorAll(".pickup-choice-item")];
  return (items.find((item) => item.dataset.questId !== "173") || items[0])?.dataset.questId || null;
});
if (pickupChoiceQuestId) {
  await page.click(`.pickup-choice-item[data-quest-id="${pickupChoiceQuestId}"]`);
}
await page.waitForTimeout(200);
const afterPickupChoiceSelect = await page.evaluate((questId) => ({
  selectedQuestId: questId,
  activeName: (() => {
    const activeQuestId = Number(document.querySelector(".chain-quest-item.active, .quest-icon.active")?.dataset.questId);
    const activeQuest = DATA.quests.find((quest) => quest.id === activeQuestId);
    return activeQuest ? `${activeQuest.name} #${activeQuest.id}` : null;
  })(),
  selectedCatalogueQuest: Boolean(document.querySelector(`.chain-quest-item[data-quest-id="${questId}"].selected`)),
  pickupPopoverClosed: !document.querySelector(".pickup-choice-popover"),
  catalogueDetailText: document.querySelector(`.chain-quest-item[data-quest-id="${questId}"] .chain-quest-detail`)?.textContent?.replace(/\s+/g, " ").trim(),
  separatePickupPins: document.querySelectorAll(".quest-pin.pickup").length,
  turninPins: document.querySelectorAll(".quest-pin.turnin").length,
  objectiveOverlaysVisible: document.querySelectorAll(".objective-dot, .objective-area").length > 0,
  chainTopOffset: (() => {
    const row = document.querySelector(`.chain-quest-item[data-quest-id="${questId}"]`)?.closest(".chain-row");
    const list = document.querySelector("#chain-list");
    return row && list ? row.getBoundingClientRect().top - list.getBoundingClientRect().top : null;
  })(),
}), pickupChoiceQuestId);
if (afterPickupChoiceSelect.separatePickupPins !== 0) {
  throw new Error(`Selecting a displayed pickup rendered ${afterPickupChoiceSelect.separatePickupPins} separate pickup pin(s).`);
}
if (afterPickupChoiceSelect.catalogueDetailText?.includes("Any one of: Worgen in the Woods (#173)") || afterPickupChoiceSelect.catalogueDetailText?.includes("Requires: Worgen in the Woods (#173)") || !afterPickupChoiceSelect.catalogueDetailText?.includes("Prerequisites Worgen in the Woods (#173)")) {
  throw new Error(`Expected single prerequisite wording to list the quest without an extra prefix, got ${JSON.stringify(afterPickupChoiceSelect)}.`);
}
if (afterPickupChoiceSelect.chainTopOffset === null || Math.abs(afterPickupChoiceSelect.chainTopOffset - 8) > 12) {
  throw new Error(`Expected map-selected quest chain near catalogue top, got ${JSON.stringify(afterPickupChoiceSelect)}.`);
}
await page.screenshot({ path: screenshotPath, fullPage: true });

await page.selectOption("#zone-select", "148");
await page.waitForTimeout(300);
const powersBelowDefault = await page.evaluate(() => {
  const quest = DATA.quests.find((item) => item.id === 968);
  const markers = [...document.querySelectorAll(".map-marker.available-pickup")]
    .filter((marker) => marker.dataset.questIds?.includes("|968|"));
  return {
    markerCount: markers.length,
    totalStartPoints: quest?.startPoints?.length || 0,
    startPointsHaveSourceNames: Boolean(quest?.startPoints?.some((point) => point.sourceName)),
    markerTitle: markers[0]?.getAttribute("title"),
  };
});
if (powersBelowDefault.markerCount !== 1) {
  throw new Error(`Expected The Powers Below to have one default pickup marker, got ${powersBelowDefault.markerCount}.`);
}
if (!powersBelowDefault.startPointsHaveSourceNames) {
  throw new Error("Expected generated start points to include source names.");
}
if (powersBelowDefault.markerTitle !== null && powersBelowDefault.markerTitle !== undefined) {
  throw new Error(`Expected map pickup marker to avoid native title tooltip, got ${JSON.stringify(powersBelowDefault)}.`);
}
await page.click('.map-marker.available-pickup[data-quest-ids*="|968|"]');
await page.waitForTimeout(150);
if (await page.locator('.pickup-choice-item[data-quest-id="968"]').count()) {
  await page.click('.pickup-choice-item[data-quest-id="968"]');
}
await page.waitForTimeout(200);
const powersBelowSelected = await page.evaluate(() => {
  const quest = DATA.quests.find((item) => item.id === 968);
  const activeQuestId = Number(document.querySelector(".chain-quest-item.active, .quest-icon.active")?.dataset.questId);
  const activeQuest = DATA.quests.find((item) => item.id === activeQuestId);
  return {
    activeName: activeQuest ? `${activeQuest.name} #${activeQuest.id}` : null,
    pickupPins: document.querySelectorAll(".quest-pin.pickup").length,
    pickupDots: document.querySelectorAll(".pickup-dot").length,
    firstDotSize: (() => {
      const dot = document.querySelector(".pickup-dot");
      const style = dot ? getComputedStyle(dot) : null;
      return style ? { width: style.width, height: style.height, background: style.backgroundColor } : null;
    })(),
    visibleStartPoints: quest.startPoints.filter((point) => point.zoneId === 148).length,
    selectedCatalogueQuest: Boolean(document.querySelector('.chain-quest-item[data-quest-id="968"].selected')),
  };
});
if (
  powersBelowSelected.pickupPins !== 0 ||
  powersBelowSelected.pickupDots < Math.min(2, powersBelowSelected.visibleStartPoints) ||
  powersBelowSelected.firstDotSize?.width !== "10px" ||
  !powersBelowSelected.firstDotSize?.background?.includes("255, 211, 79")
) {
  throw new Error(`Expected The Powers Below to expand alternate pickups as passive dots; got ${JSON.stringify(powersBelowSelected)}.`);
}

await page.click("#world-button");
await page.waitForTimeout(300);
const worldPickupLayout = await page.evaluate(() => {
  const mapRect = document.querySelector("#map").getBoundingClientRect();
  const markers = [...document.querySelectorAll(".map-marker.available-pickup")];
  const drifts = markers.map((marker) => {
    const originX = Number(marker.dataset.originX);
    const originY = Number(marker.dataset.originY);
    const displayX = Number(marker.dataset.displayX);
    const displayY = Number(marker.dataset.displayY);
    return Math.hypot((displayX - originX) * mapRect.width / 100, (displayY - originY) * mapRect.height / 100);
  }).filter(Number.isFinite);
  return {
    markerCount: markers.length,
    clusteredMarkers: markers.filter((marker) => Number(marker.dataset.pickupGroupCount || 1) > 1).length,
    maxPickupGroupCount: Math.max(...markers.map((marker) => Number(marker.dataset.pickupGroupCount || 1)), 0),
    maxPixelDrift: drifts.length ? Math.max(...drifts) : 0,
    sectionedClusterCount: markers.filter((marker) => Number(marker.dataset.pickupGroupCount || 1) > 1 && marker.querySelector(".pickup-count")).length,
  };
});
if (worldPickupLayout.clusteredMarkers === 0) {
  throw new Error("Expected at least one world-map pickup marker to merge nearby pickup points.");
}
if (worldPickupLayout.maxPixelDrift > 56) {
  throw new Error(`World pickup marker drift is still too high: ${worldPickupLayout.maxPixelDrift.toFixed(1)}px.`);
}
await page.screenshot({ path: worldScreenshotPath, fullPage: true });
await page.evaluate(() => {
  const marker = [...document.querySelectorAll(".map-marker.available-pickup")]
    .sort((a, b) => Number(b.dataset.pickupGroupCount || 1) - Number(a.dataset.pickupGroupCount || 1))[0];
  marker?.click();
});
await page.waitForTimeout(200);
const worldClusterPicker = await page.evaluate(() => ({
  visible: Boolean(document.querySelector(".pickup-choice-popover")),
  title: document.querySelector(".pickup-choice-title")?.textContent?.trim(),
  headingCount: document.querySelectorAll(".pickup-choice-heading").length,
  headings: [...document.querySelectorAll(".pickup-choice-heading")].slice(0, 8).map((item) => item.textContent.trim()),
  itemCount: document.querySelectorAll(".pickup-choice-item").length,
  sections: [...document.querySelectorAll(".pickup-choice-section")].map((section) => ({
    heading: section.querySelector(".pickup-choice-heading")?.textContent?.trim(),
    minRequiredLevel: Math.min(...[...section.querySelectorAll(".pickup-choice-item")].map((item) => {
      const quest = DATA.quests.find((entry) => entry.id === Number(item.dataset.questId));
      return quest?.requiredLevel ?? 0;
    })),
  })),
}));
if (!worldClusterPicker.visible || worldClusterPicker.title !== "Nearby quest pickups" || worldClusterPicker.headingCount < 2) {
  throw new Error(`Expected a sectioned world pickup picker, got ${JSON.stringify(worldClusterPicker)}.`);
}
if (worldClusterPicker.sections.some((section, index, sections) => index > 0 && section.minRequiredLevel < sections[index - 1].minRequiredLevel)) {
  throw new Error(`Expected world pickup picker sections sorted by lowest quest level, got ${JSON.stringify(worldClusterPicker)}.`);
}

await page.click("#quest-filter-button");
await page.check('#quest-filter-menu input[value="city-donation"]');
await page.waitForTimeout(300);
const afterDonationFilter = await page.evaluate(() => ({
  checkedQuestTypes: [...document.querySelectorAll("#quest-filter-menu input:checked")].map((input) => input.value),
  inventoryIcons: document.querySelectorAll(".quest-icon").length,
  chainRows: document.querySelectorAll(".chain-row").length,
  dungeonQuestVisible: Boolean(document.querySelector('.quest-icon[data-quest-id="377"]')),
  woolDonationVisible: Boolean(document.querySelector('.quest-icon[data-quest-id="7791"]')),
}));

await browser.close();

console.log(JSON.stringify({ pageErrors, worldView, barrensHitPoint, barrensZoneTooltip, barrensHitboxClick, expandedAllCatalogue, collapsedAllCatalogue, questFilterMenu, zoneFilterMenu, allZonesUnchecked, duskwoodOnlyFilter, displayFilterMenu, filteredWorldView, nesingwaryAt40, allLevelWorldCatalogue, duskwoodView, typeBadgeView, afterHover, chainExpansion, catalogueKeyboardNav, afterPinnedClick, afterPinnedHover, afterZoneLink, catalogueClickScroll, displayPickupView, displayLocationMarkers, objectiveDisplayTooltip, handinDisplayTooltip, typedPickupPicker, hoverPickupPicker, singleHoverPicker, pickupChainDivider, searchView, clearSearchView, tigerGrouping, topEdgePicker, pickupChoice, afterPickupChoiceSelect, powersBelowDefault, powersBelowSelected, worldPickupLayout, worldClusterPicker, afterDonationFilter, screenshotPath, worldScreenshotPath }, null, 2));
