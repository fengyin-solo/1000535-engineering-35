"""本地数据仓库：首次启动落盘示例数据，之后只读写同一份文件。

真实项目里这里会换成数据库访问层；当前实现只依赖标准库：
- 首次启动（数据文件不存在）时把 app/seed.py 的示例数据原子写入文件；
- 之后每次启动都加载这份文件，重复起服务不会重复塞入示例数据；
- 运行期新增/流转的数据由 main 里的中间件在写操作后统一 flush，
  重启后仍在；构建产物（frontend/dist 等）与本地运行数据互不干扰。
"""
from __future__ import annotations

import json
import os
import tempfile
from typing import Any

from app.seed import SEED_ROWS, SEED_VERSION

_dump_kwargs: dict[str, Any] = {"ensure_ascii": False, "indent": 2}


class Store:
    def __init__(self, data_path: str) -> None:
        self.data_path = data_path
        self._tables: dict[str, list[dict[str, Any]]] = {}
        self._seed_version: int = SEED_VERSION
        self._loaded = False
        self.load()

    # ---------- 持久化 ----------

    def load(self) -> None:
        """从数据文件加载；文件不存在时用示例数据初始化并落盘（只执行一次）。"""
        if os.path.exists(self.data_path):
            try:
                with open(self.data_path, "r", encoding="utf-8") as handle:
                    payload = json.load(handle)
                tables = payload.get("tables") if isinstance(payload, dict) else None
                if isinstance(tables, dict):
                    self._tables = {
                        name: [dict(row) for row in rows]
                        for name, rows in tables.items()
                        if isinstance(rows, list)
                    }
                    self._seed_version = int(payload.get("seed_version") or SEED_VERSION)
                    self._loaded = True
                    return
            except (OSError, ValueError):
                # 文件损坏或被截断时不要起不来：退回示例数据并覆盖写回
                print(f"[store] 数据文件 {self.data_path} 无法读取，已用示例数据重建", flush=True)

        self._tables = {
            name: [dict(row) for row in rows] for name, rows in SEED_ROWS.items()
        }
        self._seed_version = SEED_VERSION
        self.flush()
        self._loaded = True

    def flush(self) -> None:
        """把当前数据原子写回文件（临时文件 + rename，写一半宕掉也不会坏）。"""
        directory = os.path.dirname(os.path.abspath(self.data_path))
        os.makedirs(directory, exist_ok=True)
        payload = {
            "seeded": True,
            "seed_version": self._seed_version,
            "tables": self._tables,
        }
        fd, tmp_path = tempfile.mkstemp(prefix=".data-", suffix=".tmp", dir=directory)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, **_dump_kwargs)
            os.replace(tmp_path, self.data_path)
        except BaseException:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise

    def reset_to_seed(self) -> None:
        """清空本地改动并恢复成示例数据（供 make reset-data 使用）。"""
        self._tables = {
            name: [dict(row) for row in rows] for name, rows in SEED_ROWS.items()
        }
        self._seed_version = SEED_VERSION
        self.flush()

    @property
    def seeded(self) -> bool:
        return True

    # ---------- 查询与改动 ----------

    def module_names(self) -> list[str]:
        return sorted(self._tables)

    def rows(self, module: str) -> list[dict[str, Any]]:
        return self._tables.setdefault(module, [])

    def find(self, module: str, entry_id: int) -> dict[str, Any] | None:
        for row in self.rows(module):
            if int(row.get("id", 0)) == entry_id:
                return row
        return None

    def overview(self) -> dict[str, object]:
        modules: list[dict[str, object]] = []
        for name in self.module_names():
            rows = self.rows(name)
            modules.append({
                "name": name,
                "created": len(rows),
                "pending": sum(1 for row in rows if row.get("pending")),
                "abnormal": sum(1 for row in rows if row.get("abnormal")),
            })
        cards = [
            {"label": "业务模块", "value": len(modules)},
            {"label": "今日新增", "value": sum(int(item["created"]) for item in modules)},
            {"label": "待处理", "value": sum(int(item["pending"]) for item in modules)},
            {"label": "异常量", "value": sum(int(item["abnormal"]) for item in modules)},
        ]
        return {"cards": cards, "modules": modules}


# 单例：数据文件路径来自配置，默认 backend/.local/data.json（已被 .gitignore 忽略）
from app.config import settings  # noqa: E402

store = Store(settings.data_path)
