import json
import asyncio
import time
from typing import Optional, Callable, Dict, Any, List

from openai import AsyncOpenAI
from rich.console import Console
from rich.panel import Panel

from saturn.config import config
from saturn.browser import SaturnBrowser
from saturn.tools import TOOLS
from saturn.prompts import SYSTEM_PROMPT, OBSERVATION_TEMPLATE

console = Console()

class SaturnAgent:
    def __init__(
        self,
        goal: str,
        browser: SaturnBrowser,
        model: Optional[str] = None,
        max_steps: Optional[int] = None,
        on_step: Optional[Callable] = None,
        dry_run: bool = False,
    ):
        self.goal = goal
        self.browser = browser
        self.model = model or config.openai_model
        self.max_steps = max_steps or config.max_steps
        self.on_step = on_step  # callback(step, thought, action, result) for UI streaming
        self.dry_run = dry_run
        self.client = AsyncOpenAI(
            api_key=config.openai_api_key or "ollama",
            base_url=config.openai_base_url,
            timeout=120.0,
            max_retries=2,
        )
        self.messages: List[Dict[str, Any]] = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": f"Goal: {self.goal}\n\nStart by navigating or inspecting the current page. Call ONE tool per turn."}
        ]
        self.history: List[str] = []
        self.prev_action = "none"
        self.prev_result = "none"

    async def _call_llm(self) -> Any:
        resp = await self.client.chat.completions.create(
            model=self.model,
            messages=self.messages,
            tools=TOOLS,
            tool_choice="required",
            temperature=0.2,
        )
        return resp.choices[0].message

    async def _execute_tool(self, name: str, args: Dict[str, Any]) -> str:
        try:
            if name == "navigate":
                r = await self.browser.navigate(args["url"])
                return json.dumps(r)[:1200]
            elif name == "click":
                r = await self.browser.click(args["selector"], args.get("description",""))
                return json.dumps(r)[:800]
            elif name == "type":
                r = await self.browser.fill(args["selector"], args["text"], args.get("submit", False))
                return json.dumps(r)[:800]
            elif name == "press_key":
                r = await self.browser.press_key(args["key"])
                return json.dumps(r)[:500]
            elif name == "scroll":
                r = await self.browser.scroll(args.get("direction","down"), args.get("amount",500))
                return json.dumps(r)[:500]
            elif name == "wait":
                r = await self.browser.wait(float(args.get("seconds", 2)))
                return json.dumps(r)[:500]
            elif name == "extract_content":
                r = await self.browser.extract_content(args.get("selector",""))
                txt = r.get("text","")[:3000]
                return json.dumps({"ok": r.get("ok"), "url": r.get("url"), "title": r.get("title"), "text": txt, "error": r.get("error")})[:3500]
            elif name == "take_screenshot":
                b64 = await self.browser.screenshot()
                # Don't send huge base64 to LLM; confirm captured
                return f"screenshot captured ({len(b64)} chars base64), viewport is {self.browser.viewport}"
            elif name == "done":
                return f"DONE: {args.get('answer','')} success={args.get('success', True)}"
            else:
                return f"unknown tool {name}"
        except Exception as e:
            return f"tool error: {e}"

    async def run(self) -> Dict[str, Any]:
        console.print(Panel(f"[bold cyan]Saturn[/bold cyan] goal: {self.goal}\nmodel: {self.model}  max_steps: {self.max_steps}", title="🪐 Saturn Started"))
        start = time.time()
        for step in range(1, self.max_steps + 1):
            state = await self.browser.get_state()

            # Build observation
            obs = OBSERVATION_TEMPLATE.format(
                goal=self.goal,
                step=step,
                max_steps=self.max_steps,
                url=state["url"],
                title=state["title"],
                history=" | ".join(self.browser.history[-6:]) or "none",
                snapshot=state["snapshot"][:6000],
                visible_text=state["visible_text"][:2500],
                prev_action=self.prev_action,
                prev_result=self.prev_result[:600],
            )

            # If first step and blank page, nudge
            if step == 1 and state["url"] in ("about:blank", ""):
                obs += "\n\nNote: Browser is blank. You should navigate() to a relevant URL to start."

            self.messages.append({"role": "user", "content": obs})

            if self.dry_run:
                console.print(f"[dim]Step {step} observation built, dry_run skips LLM[/dim]")
                break

            # Call LLM
            try:
                msg = await self._call_llm()
            except Exception as e:
                err = f"LLM error: {e}. Check OPENAI_API_KEY / OPENAI_BASE_URL / model. Set in .env"
                console.print(f"[red]{err}[/red]")
                if self.on_step:
                    await self._emit(step, err, "error", err)
                return {"success": False, "error": err, "steps": step}

            tool_calls = msg.tool_calls
            if not tool_calls:
                # Fallback: treat content as done
                content = msg.content or ""
                console.print(f"[yellow]No tool call, content: {content[:500]}[/yellow]")
                self.messages.append({"role": "assistant", "content": content})
                self.prev_action = "thought"
                self.prev_result = content[:500]
                continue

            tc = tool_calls[0]
            name = tc.function.name
            try:
                args = json.loads(tc.function.arguments or "{}")
            except:
                args = {}

            reason = msg.content or ""
            console.print(f"[bold]Step {step}/{self.max_steps}[/bold] → [cyan]{name}[/cyan] {json.dumps(args)[:200]}")
            if reason:
                console.print(f"  [dim]{reason[:300]}[/dim]")

            self.messages.append({
                "role": "assistant",
                "content": reason,
                "tool_calls": [{"id": tc.id, "type": "function", "function": {"name": name, "arguments": tc.function.arguments}}]
            })

            if name == "done":
                answer = args.get("answer", "")
                success = args.get("success", True)
                console.print(Panel(answer, title="✅ Done" if success else "⚠️ Done (partial)", border_style="green"))
                self.messages.append({"role": "tool", "tool_call_id": tc.id, "content": f"Acknowledged done. Task finished."})
                if self.on_step:
                    await self._emit(step, reason, name, answer, done=True)
                return {
                    "success": success,
                    "answer": answer,
                    "steps": step,
                    "time": round(time.time()-start,1),
                    "final_url": state["url"]
                }

            result = await self._execute_tool(name, args)
            self.messages.append({"role": "tool", "tool_call_id": tc.id, "content": result})
            self.prev_action = f"{name}({json.dumps(args)[:120]})"
            self.prev_result = result[:600]
            self.history.append(f"{step}. {name} -> {result[:120]}")

            if self.on_step:
                await self._emit(step, reason, name, result, state=state)

            # small pause to let UI update
            await asyncio.sleep(0.3)

            # Early exit if browser closed
            if not self.browser.page:
                break

        elapsed = round(time.time() - start, 1)
        msg_final = f"Max steps ({self.max_steps}) reached without done(). Last URL: {self.browser.page.url if self.browser.page else 'closed'}"
        console.print(Panel(msg_final, title="⏱️ Stopped", border_style="yellow"))
        return {"success": False, "answer": msg_final, "steps": self.max_steps, "time": elapsed, "history": self.history}

    async def _emit(self, step, reasoning, action, result, done=False, state=None):
        if not self.on_step:
            return
        try:
            payload = {
                "step": step,
                "reasoning": reasoning,
                "action": action,
                "result": result[:1500] if isinstance(result, str) else str(result)[:1500],
                "done": done,
                "url": state["url"] if state else (self.browser.page.url if self.browser.page else ""),
                "title": state["title"] if state else "",
            }
            if asyncio.iscoroutinefunction(self.on_step):
                await self.on_step(payload)
            else:
                self.on_step(payload)
        except Exception as e:
            console.print(f"[dim]on_step error: {e}[/dim]")
