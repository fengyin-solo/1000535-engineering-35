"""列车防护业务规则：状态流转、字段校验与筛选口径都收在这里。"""
from __future__ import annotations

from typing import Any

from app.stats import compute_stats
from app.store import store

MODULE = "atp"
REQUIRED_FIELDS = ["设备编号", "防护等级", "覆盖区段"]
STATUS_ORDER = ["待启用", "防护正常", "版本待升级", "已停用"]
ACTION_RULES = {"启用防护": "防护正常", "提交升级": "版本待升级", "停用防护": "已停用"}
NEGATIVE_ACTIONS = ["停用防护"]


STAT_RULES = [
    ('在运防护设备', 'status', '防护正常'),
    ('待升级版本', 'status', '版本待升级'),
    ('覆盖区段数', 'distinct', '覆盖区段'),
]


class AtpService:
    def stats(self) -> list[dict[str, Any]]:
        """页头统计卡片：按本模块口径汇总当前记录。"""
        return compute_stats(store.rows(MODULE), STAT_RULES)

    def list_entries(
        self,
        *,
        keyword: str | None = None,
        status: str | None = None,
        page: int = 1,
        size: int = 20,
    ) -> tuple[list[dict[str, Any]], int]:
        rows = store.rows(MODULE)
        if keyword:
            rows = [row for row in rows if keyword in str(row.get("设备编号", ""))]
        if status:
            rows = [row for row in rows if row.get("status") == status]
        total = len(rows)
        start = max(page - 1, 0) * size
        return rows[start:start + size], total

    def get_entry(self, entry_id: int) -> dict[str, Any] | None:
        return store.find(MODULE, entry_id)

    def create_entry(self, values: dict[str, Any]) -> tuple[dict[str, Any] | None, list[str]]:
        missing = [field for field in REQUIRED_FIELDS if not str(values.get(field) or "").strip()]
        if missing:
            return None, missing
        rows = store.rows(MODULE)
        entry = {"id": max((int(row.get("id", 0)) for row in rows), default=0) + 1}
        entry.update({field: values.get(field) for field in REQUIRED_FIELDS})
        entry["status"] = STATUS_ORDER[0]
        entry["pending"] = True
        entry["abnormal"] = False
        rows.append(entry)
        return entry, []

    def run_action(self, entry_id: int, action: str) -> tuple[dict[str, Any] | None, str]:
        entry = store.find(MODULE, entry_id)
        if entry is None:
            return None, f"防护设备 {entry_id} 不存在或已归档"
        if action not in ACTION_RULES:
            return None, f"动作「{action}」不属于列车防护可执行范围"
        target = ACTION_RULES[action]
        if target not in STATUS_ORDER:
            return None, f"目标状态「{target}」不在允许的状态序列里"
        entry["status"] = target
        entry["pending"] = target != STATUS_ORDER[-1]
        entry["abnormal"] = action in NEGATIVE_ACTIONS
        return entry, f"防护设备已{action}"
