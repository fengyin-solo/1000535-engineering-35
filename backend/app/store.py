"""内存数据仓库：给每个业务模块准备一份可筛选、可流转的示例数据。

真实项目里这里会换成数据库访问层；当前实现只依赖标准库，保证克隆下来就能起。
示例数据的塞入是幂等的：ensure_seeded() 只往空表里补数据，重复调用、
重复起服务都不会把同一条示例记录塞两遍。
"""
from __future__ import annotations

from typing import Any

from app.seed import SEED_ROWS


class Store:
    def __init__(self) -> None:
        self._tables: dict[str, list[dict[str, Any]]] = {}
        self.ensure_seeded()

    def ensure_seeded(self) -> dict[str, int]:
        """把示例数据补进空表，返回本次新塞入的行数（按模块）。

        已经有数据的模块原样保留：服务反复启动、启动脚本重复触发塞数，
        各模块的记录数都不会翻倍。
        """
        added: dict[str, int] = {}
        for name, rows in SEED_ROWS.items():
            table = self._tables.setdefault(name, [])
            if table:
                continue
            table.extend(dict(row) for row in rows)
            added[name] = len(rows)
        return added

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


store = Store()
