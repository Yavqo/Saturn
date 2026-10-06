import asyncio
import base64
import time
from typing import Optional, Dict, Any, List

from playwright.async_api import async_playwright, Page, Browser, BrowserContext

class SaturnBrowser:
    """Playwright wrapper optimized for LLM agents."""

    def __init__(self, headless: bool = False, viewport: Dict[str, int] = None, timeout: int = 30000):
        self.headless = headless
        self.viewport = viewport or {"width": 1280, "height": 800}
        self.timeout = timeout
        self._playwright = None
        self._browser: Optional[Browser] = None
        self._context: Optional[BrowserContext] = None
        self.page: Optional[Page] = None
        self.history: List[str] = []

    async def start(self, url: Optional[str] = None):
        self._playwright = await async_playwright().start()
        self._browser = await self._playwright.chromium.launch(
            headless=self.headless,
            args=["--disable-blink-features=AutomationControlled", "--no-sandbox"]
        )
        self._context = await self._browser.new_context(
            viewport=self.viewport,
            user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Saturn/0.1"
        )
        self.page = await self._context.new_page()
        self.page.set_default_timeout(self.timeout)
        if url:
            await self.navigate(url)
        else:
            await self.navigate("about:blank")

    async def stop(self):
        try:
            if self._context:
                await self._context.close()
            if self._browser:
                await self._browser.close()
            if self._playwright:
                await self._playwright.stop()
        except Exception:
            pass

    async def navigate(self, url: str) -> Dict[str, Any]:
        if not url.startswith("http") and not url.startswith("about:"):
            url = "https://" + url
        try:
            resp = await self.page.goto(url, wait_until="domcontentloaded", timeout=self.timeout)
            await self.page.wait_for_timeout(800)
            status = resp.status if resp else 0
            self.history.append(f"navigate({url}) -> {status}")
            return {"ok": True, "url": self.page.url, "status": status, "title": await self.page.title()}
        except Exception as e:
            self.history.append(f"navigate({url}) -> ERROR: {e}")
            return {"ok": False, "error": str(e), "url": self.page.url if self.page else url}

    async def click(self, selector: str, description: str = "") -> Dict[str, Any]:
        try:
            # Try strict selector first, fallback to text search
            locator = self.page.locator(selector).first
            count = await self.page.locator(selector).count()
            if count == 0 and description:
                # try by text
                locator = self.page.get_by_text(description).first
                count = await self.page.get_by_text(description).count()
            if count == 0:
                # try role-based fallback
                locator = self.page.locator(f"text={selector}").first
            await locator.click(timeout=5000)
            await self.page.wait_for_timeout(600)
            self.history.append(f"click({selector})")
            return {"ok": True, "url": self.page.url}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    async def fill(self, selector: str, text: str, submit: bool = False) -> Dict[str, Any]:
        try:
            loc = self.page.locator(selector).first
            if await self.page.locator(selector).count() == 0:
                # fallback: find input by placeholder/label
                loc = self.page.get_by_placeholder(selector).first
                if await loc.count() == 0:
                    loc = self.page.locator("input, textarea").first
            await loc.click(timeout=3000)
            await loc.fill(text, timeout=5000)
            if submit:
                await self.page.keyboard.press("Enter")
                await self.page.wait_for_timeout(800)
            else:
                await self.page.wait_for_timeout(300)
            self.history.append(f"type({selector}, {text[:50]!r}, submit={submit})")
            return {"ok": True, "url": self.page.url}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    async def press_key(self, key: str) -> Dict[str, Any]:
        try:
            await self.page.keyboard.press(key)
            await self.page.wait_for_timeout(400)
            self.history.append(f"press({key})")
            return {"ok": True}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    async def scroll(self, direction: str = "down", amount: int = 500) -> Dict[str, Any]:
        try:
            if direction == "down":
                await self.page.mouse.wheel(0, amount)
            elif direction == "up":
                await self.page.mouse.wheel(0, -amount)
            else:
                await self.page.evaluate(f"window.scrollBy(0, {amount if direction=='down' else -amount})")
            await self.page.wait_for_timeout(400)
            return {"ok": True}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    async def wait(self, seconds: float) -> Dict[str, Any]:
        await self.page.wait_for_timeout(int(seconds * 1000))
        return {"ok": True}

    async def screenshot(self) -> str:
        """Return base64 PNG"""
        try:
            buf = await self.page.screenshot(full_page=False, type="png")
            return base64.b64encode(buf).decode()
        except Exception as e:
            return f"error: {e}"

    async def snapshot(self) -> str:
        """DOM snapshot for LLM — uses JS to avoid removed accessibility API."""
        try:
            # Try native accessibility if present (older Playwright), fallback to JS DOM scan
            if hasattr(self.page, "accessibility") and hasattr(self.page.accessibility, "snapshot"):
                try:
                    snap = await self.page.accessibility.snapshot()
                    if snap:
                        lines = []
                        def walk(node, depth=0):
                            if not node:
                                return
                            role = node.get("role", "")
                            name = node.get("name", "")
                            value = node.get("value", "")
                            line = "  " * depth + f"- {role}"
                            if name:
                                line += f' "{name}"'
                            if value:
                                line += f' value="{value}"'
                            if role in ("button", "link", "textbox", "combobox", "searchbox", "checkbox", "radio", "tab"):
                                lines.append(line + f"  [ref={len(lines)}]")
                            else:
                                if name or role not in ("generic", "StaticText"):
                                    lines.append(line)
                            for child in node.get("children", []) or []:
                                walk(child, depth+1)
                        walk(snap)
                        out = "\n".join(lines[:120])
                        if len(lines) > 120:
                            out += f"\n... ({len(lines)-120} more nodes truncated)"
                        if out.strip():
                            return out
                except Exception:
                    pass
            # Fallback: JS DOM extraction
            data = await self.page.evaluate("""() => {
                const els = Array.from(document.querySelectorAll('a, button, input, textarea, select, [role=button], [role=link], h1, h2, h3'));
                const out = [];
                const seen = new Set();
                for (const el of els.slice(0, 120)) {
                    const tag = el.tagName.toLowerCase();
                    const role = el.getAttribute('role') || tag;
                    const text = (el.innerText || el.textContent || el.value || el.placeholder || el.getAttribute('aria-label') || '').replace(/\\s+/g,' ').trim().slice(0,80);
                    const href = el.href ? ` href=${el.href.slice(0,60)}` : '';
                    const type = el.type ? ` type=${el.type}` : '';
                    const key = role+':'+text;
                    if (!text || seen.has(key)) continue;
                    seen.add(key);
                    let line = `- ${role}`;
                    if (text) line += ` "${text}"`;
                    if (type) line += type;
                    if (href) line += href;
                    // hint selector
                    let sel = tag;
                    if (el.id) sel += '#'+el.id;
                    else if (el.name) sel += '[name='+el.name+']';
                    else if (el.placeholder) sel += '[placeholder*=\"'+el.placeholder.slice(0,15)+'\"]';
                    out.push(line + `  -> ${sel}`);
                }
                if (out.length===0) return '(no interactive elements found, page may be empty)';
                return out.join('\\n');
            }""")
            return data or "(empty snapshot)"
        except Exception as e:
            return f"(snapshot error: {e})"

    async def visible_text(self, max_chars: int = 4000) -> str:
        try:
            text = await self.page.evaluate("""() => {
                const el = document.body;
                if (!el) return "";
                // clone and remove script/style/nav
                let t = el.innerText || el.textContent || "";
                return t.replace(/\\s+/g, ' ').trim().slice(0, 8000);
            }""")
            if len(text) > max_chars:
                return text[:max_chars] + " ...[truncated]"
            return text
        except Exception as e:
            return f"(text error: {e})"

    async def extract_content(self, selector: str = "") -> Dict[str, Any]:
        try:
            if selector:
                loc = self.page.locator(selector).first
                if await loc.count() == 0:
                    return {"ok": False, "error": f"selector not found: {selector}"}
                text = await loc.inner_text()
                html = await loc.inner_html()
            else:
                text = await self.visible_text(max_chars=10000)
                html = ""
            return {"ok": True, "text": text, "html": html[:5000] if html else "", "url": self.page.url, "title": await self.page.title()}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    async def get_state(self) -> Dict[str, Any]:
        try:
            url = self.page.url
            title = await self.page.title()
            snapshot = await self.snapshot()
            visible = await self.visible_text()
            return {
                "url": url,
                "title": title,
                "snapshot": snapshot,
                "visible_text": visible,
            }
        except Exception as e:
            return {"url": "unknown", "title": "", "snapshot": f"error {e}", "visible_text": ""}

    async def evaluate(self, js: str) -> Any:
        try:
            return await self.page.evaluate(js)
        except Exception as e:
            return f"eval error: {e}"
