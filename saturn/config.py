import os
from dataclasses import dataclass
from dotenv import load_dotenv

load_dotenv()

@dataclass
class Config:
    # Browser
    headless: bool = os.getenv("SATURN_HEADLESS", "true").lower() in ("1", "true", "yes")
    max_steps: int = int(os.getenv("SATURN_MAX_STEPS", "30"))
    timeout_ms: int = int(os.getenv("SATURN_TIMEOUT_MS", "30000"))
    viewport_width: int = int(os.getenv("SATURN_VIEWPORT_WIDTH", "1280"))
    viewport_height: int = int(os.getenv("SATURN_VIEWPORT_HEIGHT", "800"))

    # Server
    port: int = int(os.getenv("SATURN_PORT", "8765"))

    # LLM - optional, only needed for agent mode
    openai_api_key: str = os.getenv("OPENAI_API_KEY", "")
    openai_base_url: str = os.getenv("OPENAI_BASE_URL", "")
    openai_model: str = os.getenv("OPENAI_MODEL", "")

    def has_llm(self) -> bool:
        return bool(self.openai_api_key and self.openai_base_url and self.openai_model)

config = Config()
