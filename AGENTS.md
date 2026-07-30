# Dreamway Codex Notes

## Addon Deployment

After changing any files under `DreamwayQuestPlanner/`, automatically update the live WoW AddOns copy as part of the same task. Do this before the final response, after validation/regeneration, so the next in-game `/reload` uses the latest addon.

The live AddOns folder is outside the workspace, so copying there may require sandbox escalation. If escalation is required, request it directly rather than skipping deployment. Copy the whole `Dreamway` addon folder, preserving the folder name and replacing changed files in the live AddOns copy.

Use wildcard expansion with `Copy-Item -Path`, not `Copy-Item -LiteralPath`, when copying folder contents:

```powershell
$source = "C:\Users\Dan\Documents\WoW Quest Mapping\DreamwayQuestPlanner"
$target = "C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns\DreamwayQuestPlanner"
Copy-Item -Path (Join-Path $source "*") -Destination $target -Recurse -Force
```

After copying, read back `Dreamway.lua` from the live AddOns folder and confirm its size/content matches the workspace copy.

## Previewing The Web App

When testing `dreamway.html`, do not try to open it with a `file://` URL in the in-app browser. Browser policy blocks local file URLs. Also avoid relying on external Playwright from the shell here; the bundled environment may not have `playwright-core` available.

Use the in-app browser through the browser skill and serve the workspace over `localhost` from the Node REPL. This has worked reliably:

1. Regenerate the app after editing the generator:

   ```powershell
   & "C:\Users\Dan\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" "tools\build_dreamway_webapp.py"
   ```

2. Start a localhost preview server from `mcp__node_repl.js`:

   ```js
   const http = await import("node:http");
   const fs = await import("node:fs/promises");
   const path = await import("node:path");
   const baseDir = "C:/Users/Dan/Documents/WoW Quest Mapping";

   if (globalThis.dreamwayPreviewServer) {
     await new Promise((resolve) => globalThis.dreamwayPreviewServer.close(resolve));
   }

   const mime = new Map([
     [".html", "text/html; charset=utf-8"],
     [".css", "text/css; charset=utf-8"],
     [".js", "text/javascript; charset=utf-8"],
     [".json", "application/json; charset=utf-8"],
     [".jpg", "image/jpeg"],
     [".jpeg", "image/jpeg"],
     [".png", "image/png"],
     [".webp", "image/webp"],
     [".svg", "image/svg+xml"],
   ]);

   globalThis.dreamwayPreviewServer = http.createServer(async (req, res) => {
     try {
       const url = new URL(req.url, "http://127.0.0.1:8767");
       const relative = decodeURIComponent(url.pathname === "/" ? "/dreamway.html" : url.pathname).replace(/^\/+/, "");
       const resolved = path.resolve(baseDir, relative);
       if (!resolved.startsWith(path.resolve(baseDir))) {
         res.writeHead(403);
         res.end("Forbidden");
         return;
       }
       const data = await fs.readFile(resolved);
       res.writeHead(200, { "Content-Type": mime.get(path.extname(resolved).toLowerCase()) || "application/octet-stream" });
       res.end(data);
     } catch {
       res.writeHead(404);
       res.end("Not found");
     }
   });

   await new Promise((resolve) => globalThis.dreamwayPreviewServer.listen(8767, "127.0.0.1", resolve));
   ```

3. Open and inspect it with the in-app browser:

   ```js
   if (globalThis.agent?.browsers == null) {
     const { setupBrowserRuntime } = await import("C:/Users/Dan/.codex/plugins/cache/openai-bundled/browser/26.623.141536/scripts/browser-client.mjs");
     await setupBrowserRuntime({ globals: globalThis });
   }
   globalThis.browser = globalThis.browser || await agent.browsers.get("iab");
   const tab = await browser.tabs.new();
   await tab.goto("http://127.0.0.1:8767/dreamway.html");
   await tab.playwright.waitForLoadState({ state: "load", timeoutMs: 30000 });
   ```

4. Use `tab.playwright.evaluate(...)` for targeted DOM checks, and `await tab.screenshot({ fullPage: false })` plus `nodeRepl.emitImage(...)` when the user asks to see the result.

5. Clean up when done:

   ```js
   if (globalThis.dreamwayPreviewServer) {
     await new Promise((resolve) => globalThis.dreamwayPreviewServer.close(resolve));
     globalThis.dreamwayPreviewServer = null;
   }
   ```

## Validation

After web app changes, run:

```powershell
$node = "C:\Users\Dan\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
$html = [System.IO.File]::ReadAllText("dreamway.html")
$match = [regex]::Match($html, "<script>([\s\S]*)</script>")
$tmp = Join-Path $env:TEMP "dreamway-inline-check.js"
[System.IO.File]::WriteAllText($tmp, $match.Groups[1].Value, [System.Text.UTF8Encoding]::new($false))
& $node --check $tmp
git -c safe.directory="C:/Users/Dan/Documents/WoW Quest Mapping" diff --check -- tools/build_dreamway_webapp.py dreamway.html DreamwayQuestPlanner/DreamwayQuestZones.lua
```

## Addon Quest Search Performance

Quest Search can contain thousands of rows. Preserve its virtualized rendering whenever changing search, chain grouping, filters, completion state, or drag behavior:

- Keep only the visible rows plus a small overscan pool as live draggable frames. Reuse that pool while scrolling; never create a frame for every result.
- `OnVerticalScroll` must only schedule/coalesce `UpdatePanelSearchVisibleRows`. It must not rebuild results or call `RefreshPanelSearchResults`.
- Do not perform Questie database hydration, quest-completion API calls, prerequisite traversal, sorting, or filtering from the scrolling/rendering hot path. Resolve those when the result model is built and cache lightweight display values used by recycled rows.
- Invalidate targeted caches only when their underlying state changes, such as player level, quest completion, Journey edits, game version, or filters.
- Before deploying search-related changes, test an empty search with the largest practical result set and confirm mouse-wheel scrolling remains responsive while row frames remain bounded to the visible pool.
