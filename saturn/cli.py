import asyncio
import argparse
import os
import sys

from rich.console import Console

from saturn.config import config
from saturn.browser import SaturnBrowser
from saturn.agent import SaturnAgent

console = Console()

def parse_args():
    p = argparse.ArgumentParser(prog="saturn", description="Saturn — Agentic Web Browser (MVP)")
    p.add_argument("task", nargs="*", help="Goal for the agent, e.g. 'Search for Saturn browser on Google and summarize'")
    p.add_argument("--url", help="Starting URL (default: blank, agent will navigate)")
    p.add_argument("--headless", action="store_true", help="Run browser headless")
    p.add_argument("--model", help="Override LLM model")
    p.add_argument("--max-steps", type=int, help="Max agent steps")
    p.add_argument("--port", type=int, help="Server port for UI mode")
    p.add_argument("--server", action="store_true", help="Launch web UI server instead of CLI")
    p.add_argument("--dry-run", action="store_true", help="Start browser only, skip LLM (test browser)")
    return p.parse_args()

async def run_cli(task: str, start_url: str, headless: bool, model: str, max_steps: int, dry_run: bool):
    browser = SaturnBrowser(headless=headless if headless is not None else config.headless, timeout=config.timeout_ms)
    await browser.start(url=start_url)
    try:
        if dry_run:
            console.print(f"[green]Browser started at {browser.page.url} — dry_run, press Ctrl+C to exit[/green]")
            # keep open 5s for smoke test
            await asyncio.sleep(5)
            return {"success": True, "answer": "dry_run ok", "steps": 0}
        agent = SaturnAgent(goal=task, browser=browser, model=model, max_steps=max_steps)
        result = await agent.run()
        console.print(result)
        # keep browser open briefly to inspect
        if not headless:
            console.print("[dim]Keeping browser open 10s — close manually or wait...[/dim]")
            await asyncio.sleep(10)
        return result
    finally:
        await browser.stop()

def main():
    args = parse_args()

    if args.server:
        # launch server
        from saturn.server import run_server
        port = args.port or config.port
        run_server(port=port)
        return

    task = " ".join(args.task).strip()
    if not task and not args.dry_run:
        # interactive prompt
        console.print("[bold cyan]🪐 Saturn — Agentic Browser MVP[/bold cyan]")
        console.print("Enter your goal (e.g. 'Go to wikipedia.org and summarize the Saturn planet article')")
        try:
            task = input("Goal> ").strip()
        except EOFError:
            task = ""
        if not task:
            console.print("[red]No goal provided. Example: saturn \"Search Hacker News for top story\"[/red]")
            console.print("Try: [bold]saturn --dry-run[/bold] to test browser, or [bold]saturn --server[/bold] for UI")
            sys.exit(1)

    headless = args.headless if args.headless else None
    if headless is None and config.headless:
        headless = True

    try:
        asyncio.run(run_cli(
            task=task or "open example.com",
            start_url=args.url,
            headless=headless or False,
            model=args.model,
            max_steps=args.max_steps,
            dry_run=args.dry_run,
        ))
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrupted[/yellow]")

if __name__ == "__main__":
    main()
