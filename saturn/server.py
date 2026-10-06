import asyncio
import json
from typing import List, Optional
from pathlib import Path
import base64

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, JSONResponse
import uvicorn

from saturn.config import config
from saturn.browser import SaturnBrowser

app = FastAPI(title="Saturn Browser")
clients: List[WebSocket] = []
browser: Optional[SaturnBrowser] = None
agent_task: Optional[asyncio.Task] = None

HTML = Path(__file__).parent / "static" / "index.html"

# --- helpers ---
async def ensure_browser(url: str = None) -> SaturnBrowser:
    global browser
    if browser and browser.page:
        if url:
            await browser.navigate(url)
        return browser
    browser = SaturnBrowser(
        headless=config.headless,
        viewport={"width": config.viewport_width, "height": config.viewport_height},
        timeout=config.timeout_ms,
    )
    await browser.start(url=url or "https://example.com")
    return browser

async def broadcast(obj: dict):
    for ws in clients[:]:
        try:
            await ws.send_json(obj)
        except:
            pass

# --- pages ---
@app.get("/", response_class=HTMLResponse)
async def index():
    if HTML.exists():
        return HTML.read_text()
    return HTMLResponse("<h1>Saturn — static/index.html missing</h1>", status_code=500)

@app.get("/api/state")
async def state():
    if browser and browser.page:
        s = await browser.get_state()
        try:
            b64 = await browser.screenshot()
            s["screenshot"] = b64[:140] + "..."
            s["has_browser"] = True
        except:
            s["has_browser"] = True
        s["screenshot_full"] = None
        return s
    return {"has_browser": False, "url": "", "title": "", "snapshot": "", "visible_text": ""}

@app.get("/api/screenshot")
async def screenshot():
    if browser and browser.page:
        b64 = await browser.screenshot()
        return JSONResponse({"b64": b64, "url": browser.page.url})
    return JSONResponse({"b64": "", "url": ""})

# --- browser controls (no LLM) ---
@app.post("/api/navigate")
async def navigate(payload: dict):
    b = await ensure_browser()
    url = payload.get("url", "").strip()
    if not url:
        return JSONResponse({"error": "url required"}, status_code=400)
    r = await b.navigate(url)
    if b.page:
        b64 = await b.screenshot()
        await broadcast({"type": "screenshot", "b64": b64, "url": b.page.url})
        await broadcast({"type": "nav", "url": b.page.url, "title": await b.page.title()})
    return JSONResponse(r)

@app.post("/api/click")
async def click(payload: dict):
    b = await ensure_browser()
    sel = payload.get("selector", "").strip()
    if not sel:
        return JSONResponse({"error": "selector required"}, status_code=400)
    r = await b.click(sel, payload.get("description",""))
    b64 = await b.screenshot() if b.page else ""
    if b64:
        await broadcast({"type": "screenshot", "b64": b64, "url": b.page.url})
    return JSONResponse({**r, "url": b.page.url if b.page else ""})

@app.post("/api/type")
async def type_text(payload: dict):
    b = await ensure_browser()
    sel = payload.get("selector", "").strip()
    text = payload.get("text", "")
    submit = bool(payload.get("submit", False))
    if not sel:
        return JSONResponse({"error": "selector required"}, status_code=400)
    r = await b.fill(sel, text, submit)
    b64 = await b.screenshot() if b.page else ""
    if b64:
        await broadcast({"type": "screenshot", "b64": b64, "url": b.page.url})
    return JSONResponse({**r, "url": b.page.url if b.page else ""})

@app.post("/api/press")
async def press(payload: dict):
    b = await ensure_browser()
    key = payload.get("key", "Enter")
    r = await b.press_key(key)
    b64 = await b.screenshot() if b.page else ""
    if b64:
        await broadcast({"type": "screenshot", "b64": b64, "url": b.page.url})
    return JSONResponse(r)

@app.post("/api/scroll")
async def scroll(payload: dict):
    b = await ensure_browser()
    direction = payload.get("direction", "down")
    amount = int(payload.get("amount", 500))
    r = await b.scroll(direction, amount)
    b64 = await b.screenshot() if b.page else ""
    if b64:
        await broadcast({"type": "screenshot", "b64": b64, "url": b.page.url})
    return JSONResponse(r)

@app.post("/api/back")
async def go_back():
    b = await ensure_browser()
    try:
        await b.page.go_back(wait_until="domcontentloaded")
        await b.page.wait_for_timeout(500)
    except Exception as e:
        return JSONResponse({"ok": False, "error": str(e)})
    b64 = await b.screenshot()
    await broadcast({"type": "screenshot", "b64": b64, "url": b.page.url})
    return JSONResponse({"ok": True, "url": b.page.url})

@app.post("/api/extract")
async def extract(payload: dict):
    b = await ensure_browser()
    sel = payload.get("selector", "")
    r = await b.extract_content(sel)
    return JSONResponse(r)

# --- agent (optional, only if LLM configured) ---
@app.post("/api/run")
async def run_task(payload: dict):
    # keep stub so old UI doesn't crash, but explain LLM disabled
    if not config.has_llm():
        return JSONResponse({"error": "Agent disabled — no LLM configured. Use browser controls directly. Set OPENAI_API_KEY/BASE_URL/MODEL in .env to enable agent."}, status_code=400)
    # lazy import to avoid requiring openai when not used
    from saturn.agent import SaturnAgent
    global agent_task
    goal = payload.get("goal", "").strip()
    start_url = payload.get("url") or None
    model = payload.get("model") or None
    if not goal:
        return JSONResponse({"error": "goal required"}, status_code=400)
    if agent_task and not agent_task.done():
        return JSONResponse({"error": "agent already running"}, status_code=409)

    async def on_step(data):
        for ws in clients[:]:
            try:
                await ws.send_json({"type": "step", "data": data})
                if data["step"] % 2 == 1 and browser and browser.page:
                    try:
                        b64 = await browser.screenshot()
                        await ws.send_json({"type": "screenshot", "b64": b64, "url": browser.page.url})
                    except: pass
            except: pass

    b = await ensure_browser(start_url)
    agent = SaturnAgent(goal=goal, browser=b, model=model, on_step=on_step)
    async def runner():
        result = await agent.run()
        for ws in clients[:]:
            try:
                await ws.send_json({"type": "done", "result": result})
                if browser and browser.page:
                    b64 = await browser.screenshot()
                    await ws.send_json({"type": "screenshot", "b64": b64, "url": browser.page.url})
            except: pass
        return result
    agent_task = asyncio.create_task(runner())
    return {"ok": True, "goal": goal}

@app.post("/api/stop")
async def stop():
    global agent_task
    if agent_task and not agent_task.done():
        agent_task.cancel()
        return {"ok": True, "stopped": True}
    return {"ok": True, "stopped": False}

@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    clients.append(ws)
    try:
        await ws.send_json({"type": "connected", "msg": "Saturn connected"})
        while True:
            msg = await ws.receive_text()
            try:
                data = json.loads(msg)
                if data.get("type") == "ping":
                    await ws.send_json({"type": "pong"})
            except:
                pass
    except WebSocketDisconnect:
        pass
    finally:
        if ws in clients:
            clients.remove(ws)

@app.on_event("startup")
async def startup():
    # Autostart browser so tester sees immediate result — no LLM needed
    try:
        await ensure_browser("https://example.com")
        print(f"[saturn] Browser ready at {(browser.page.url if browser and browser.page else 'unknown')}")
    except Exception as e:
        print(f"[saturn] Browser autostart failed: {e}")

@app.on_event("shutdown")
async def shutdown():
    global browser
    if browser:
        await browser.stop()

def run_server(port: int = None):
    port = port or config.port
    mode = "agent+ browser" if config.has_llm() else "browser-only (LLM disabled)"
    print(f"🪐 Saturn {mode} starting at http://localhost:{port}")
    print(f"   headless={config.headless}  viewport={config.viewport_width}x{config.viewport_height}")
    uvicorn.run("saturn.server:app", host="0.0.0.0", port=port, reload=False)

if __name__ == "__main__":
    run_server()
