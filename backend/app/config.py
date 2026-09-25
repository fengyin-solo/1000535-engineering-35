"""运行配置：端口、跨域、数据文件位置，全部支持环境变量覆盖。

本地一条链启动时（scripts/dev.sh）会把实际端口通过环境变量传进来，
避免端口号散落在代码、文档和口口相传里。
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _env_list(name: str, default: list[str]) -> list[str]:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    return [item.strip() for item in raw.split(",") if item.strip()]


def _default_data_path() -> str:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.environ.get("APP_DATA_PATH") or os.path.join(here, ".local", "data.json")


@dataclass(frozen=True)
class Settings:
    app_name: str = "轨道交通信号设备检修平台"
    env: str = field(default_factory=lambda: os.environ.get("APP_ENV", "local"))
    host: str = field(default_factory=lambda: os.environ.get("APP_HOST", "127.0.0.1"))
    port: int = field(default_factory=lambda: _env_int("APP_PORT", 8000))
    # 首选端口被占用时，最多向后探测多少个端口
    port_scan_limit: int = field(default_factory=lambda: _env_int("APP_PORT_SCAN_LIMIT", 20))
    data_path: str = field(default_factory=_default_data_path)
    page_size_default: int = 20
    page_size_max: int = 200

    @property
    def allowed_origins(self) -> list[str]:
        """跨域来源：默认覆盖前端常用端口段，额外来源可用 CORS_ALLOWED_ORIGINS 追加。"""
        origins = {
            "http://127.0.0.1:5173",
            "http://localhost:5173",
        }
        # 后端换端口时前端往往也换端口，把 5174-5190 一并放行，避免本地联调被 CORS 卡住
        origins.update(f"http://127.0.0.1:{p}" for p in range(5174, 5191))
        origins.update(f"http://localhost:{p}" for p in range(5174, 5191))
        origins.update(_env_list("CORS_ALLOWED_ORIGINS", []))
        return sorted(origins)


settings = Settings()
