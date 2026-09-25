"""统计卡片口径：从模块记录里算出页头卡片要展示的数字。

规则写成 (标签, 口径, 参数...) 的元组，各业务模块在 services 里声明自己的
STAT_RULES，路由层只负责透传结果，不掺和计算。
"""
from __future__ import annotations

from datetime import date
from typing import Any


def _numbers(rows: list[dict[str, Any]], field: str) -> list[float]:
    values: list[float] = []
    for row in rows:
        raw = row.get(field)
        if isinstance(raw, (int, float)) and not isinstance(raw, bool):
            values.append(float(raw))
    return values


def compute_stats(rows: list[dict[str, Any]], rules: list[tuple[str, str, Any]]) -> list[dict[str, Any]]:
    """按规则逐条算出 {label, value}，顺序与规则声明一致。"""
    today = date.today().isoformat()
    month = today[:7]
    items: list[dict[str, Any]] = []
    for label, kind, *args in rules:
        if kind == "status":
            value = sum(1 for row in rows if row.get("status") == args[0])
        elif kind == "month":
            value = sum(1 for row in rows if str(row.get(args[0]) or "").startswith(month))
        elif kind == "today":
            value = sum(1 for row in rows if str(row.get(args[0]) or "") == today)
        elif kind == "present":
            value = sum(1 for row in rows if str(row.get(args[0]) or "").strip())
        elif kind == "sum":
            value = int(sum(_numbers(rows, args[0])))
        elif kind == "avg":
            nums = _numbers(rows, args[0])
            value = round(sum(nums) / len(nums)) if nums else 0
        elif kind == "distinct":
            value = len({str(row.get(args[0])) for row in rows if str(row.get(args[0]) or "").strip()})
        elif kind == "field_eq":
            value = sum(1 for row in rows if row.get(args[0]) == args[1])
        elif kind == "percent_status":
            hit = sum(1 for row in rows if row.get("status") == args[0])
            value = round(100 * hit / len(rows)) if rows else 0
        elif kind == "status_month":
            value = sum(
                1
                for row in rows
                if row.get("status") == args[0] and str(row.get(args[1]) or "").startswith(month)
            )
        else:
            raise ValueError(f"未知的统计口径：{kind}")
        items.append({"label": label, "value": value})
    return items
