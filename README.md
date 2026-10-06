# 🪐 Saturn — Native Browser (C++)

**Saturn is now an actual browser you can use.** Native macOS app built in C++ (Objective-C++) with WKWebView — same engine as Safari. No Electron, no Python required to browse.

> MVP: real window + toolbar + WKWebView. Python/Playwright version kept as `saturn/` (legacy agentic layer, browser-only mode).

## Native Build (C++)

```
src/
  main.mm              — NSApplication entry, --url arg parsing
  SaturnWindow.h/.mm   — NSWindow + WKWebView + toolbar (back/forward/reload/address/Go/progress)
  SaturnAppDelegate.h/.mm — App lifecycle, menu (File/Edit/View/Window), new window, zoom, focus
CMakeLists.txt         — builds Saturn.app (bundle) + saturn-cli (binary)
src/Info.plist.in      — bundle plist
build/saturn.app       — double-clickable app (95K wrapper + system WebKit)
build/saturn-cli       — CLI binary (same)
```

**Engine:** `WKWebView` (`-framework WebKit`) + `Cocoa` — hardware-accelerated, no CEF/Qt deps.

### Build & Run

```bash
# Build (macOS 13+, Xcode CLI tools, CMake 3.20+)
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j4

# Run as app bundle (double-clickable)
open build/saturn.app
open build/saturn.app --args --url https://wikipedia.org
open build/saturn.app --args https://example.com

# Or CLI binary
./build/saturn-cli --help
./build/saturn-cli --url https://example.com
```

**Toolbar:** `‹` Back, `›` Forward, `↻` Reload, address bar (auto `https://` + DuckDuckGo search fallback), `Go` (Enter), 🪐 badge. Menu: `Cmd+N` new window, `Cmd+R` reload, `Cmd+L` focus address `Cmd+[/]` back/forward, `Cmd+0/+/−` zoom.

### Features (MVP)
- Single window (multi-window via `Cmd+N`), WKWebView with back/forward gestures, JS enabled, alerts/confirms native `NSAlert`, `_blank` opens in same view
- Progress bar, title sync, address bar sync on `didCommit/didFinish`, error page on fail
- Dark toolbar (#16161f), 1280×800 window (min 900×600), resizable

---

## Legacy Python (Agentic, Browser-Only Mode)

Kept for automation testing. Now **browser-only by default** (no LLM).

```bash
# Python browser server (Playwright)
pip3 install -r requirements.txt
python3 -m playwright install chromium

# Browser-only (no API key)
# .env already set to SATURN_HEADLESS=true, PORT=8765
python3 -m uvicorn saturn.server:app --port 8765
# → http://localhost:8765  — address bar + click/type/scroll via /api/* (see saturn/server.py:1)

# To re-enable agent: set in .env
# OPENAI_API_KEY=sk-...  OPENAI_BASE_URL=https://api.openai.com/v1  OPENAI_MODEL=gpt-4o-mini
# then POST /api/run {goal: "..."}
```

```
saturn/
  browser.py  — Playwright wrapper
  server.py   — FastAPI + WS, browser controls + optional agent
  config.py   — SATURN_* + optional OPENAI_*
  static/index.html — dark glass UI for python server
```

## Next (C++ roadmap)
- Tabs (`NSTabView`), history, downloads, `WKWebsiteDataStore` persistence, find bar, devtools `WKInspector`, ad-block via `WKContentRuleList`, agentic C++ automation (`evaluateJavaScript`, `snapshot` for LLM) mirroring python tools

## Troubleshooting
- `xcrun: error` → `xcode-select --install`
- Blank window → check Console.app for `[saturn]` logs
- `cmake` missing → `brew install cmake`

## License
MIT

## Updates and releasing

Saturn updates itself from GitHub releases of `Yavqo/Saturn`. A few seconds after launch (and every 6 hours) it checks the latest release; if its version is higher than the installed one, an **Update** button appears in the toolbar. Clicking it downloads the release, checks it, replaces the app and reopens Saturn with your tabs restored. **Saturn ▸ Check for Updates…** does the same on demand.

**To publish a new version**

1. Commit and push your changes to `main`.
2. Tag it and push the tag — GitHub Actions builds and publishes the release automatically:
   ```bash
   git tag v0.2.0 && git push origin v0.2.0
   ```
   Or build and publish from your Mac instead: `scripts/release.sh 0.2.0 --publish --notes "What's new"`
   (without `--publish` it only builds `dist/Saturn-0.2.0.zip`).

Notes: tags with a suffix (`v0.2.0-beta1`) are marked pre-release and are **not** offered as updates. The updater verifies the download's SHA-256, its code signature and that it is a newer Saturn build before installing. Builds are currently ad-hoc signed (no Apple Developer ID), which is fine for in-app updates; first installs of a downloaded copy need right-click ▸ Open once.
