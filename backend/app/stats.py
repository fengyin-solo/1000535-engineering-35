"""模块统计卡片口径。

每个模块页面顶部有三张卡片，卡片数字必须和列表、运营概览对得上，
所以口径集中在这里定义，路由层统一调用，避免每个模块各写一套。

卡片取值方式：
- {"kind": "total"}                      全表行数（= 列表 total = 概览 created）
- {"kind": "pending"} / {"kind": "abnormal"}  按行上的待处理/异常标记
- {"kind": "status", "value": "已封闭"}  按行上的 status 精确匹配
"""
from __future__ import annotations

from typing import Any

# 每个模块三张卡片的口径；顺序与前端各页面 stats 的三张卡片一致
MODULE_STATS: dict[str, list[dict[str, str]]] = {
    "section": [
        {"kind": "total"},
        {"kind": "status", "value": "限速运行"},
        {"kind": "status", "value": "已封闭"},
    ],
    "signal": [
        {"kind": "status", "value": "运用正常"},
        {"kind": "pending"},
        {"kind": "status", "value": "故障停用"},
    ],
    "switch": [
        {"kind": "status", "value": "运用正常"},
        {"kind": "status", "value": "动作异常"},
        {"kind": "pending"},
    ],
    "track": [
        {"kind": "status", "value": "运用正常"},
        {"kind": "status", "value": "分路不良"},
        {"kind": "pending"},
    ],
    "interlock": [
        {"kind": "status", "value": "运用正常"},
        {"kind": "status", "value": "降级使用"},
        {"kind": "pending"},
    ],
    "atp": [
        {"kind": "status", "value": "防护正常"},
        {"kind": "status", "value": "版本待升级"},
        {"kind": "total"},
    ],
    "plan": [
        {"kind": "status", "value": "待审批"},
        {"kind": "status", "value": "执行中"},
        {"kind": "total"},
    ],
    "task": [
        {"kind": "status", "value": "待开始"},
        {"kind": "status", "value": "检修中"},
        {"kind": "abnormal"},
    ],
    "fault": [
        {"kind": "status", "value": "待定级"},
        {"kind": "status", "value": "处置中"},
        {"kind": "abnormal"},
    ],
    "dispose": [
        {"kind": "status", "value": "待受理"},
        {"kind": "status", "value": "处置中"},
        {"kind": "status", "value": "待验收"},
    ],
    "spare": [
        {"kind": "status", "value": "待审批"},
        {"kind": "total"},
        {"kind": "status", "value": "已退回"},
    ],
    "measure": [
        {"kind": "pending"},
        {"kind": "status", "value": "合格"},
        {"kind": "status", "value": "不合格"},
    ],
    "patrol": [
        {"kind": "status", "value": "待派发"},
        {"kind": "status", "value": "巡视中"},
        {"kind": "abnormal"},
    ],
    "window": [
        {"kind": "status", "value": "待申请"},
        {"kind": "status", "value": "作业中"},
        {"kind": "total"},
    ],
    "alarm": [
        {"kind": "total"},
        {"kind": "status", "value": "待确认"},
        {"kind": "abnormal"},
    ],
    "verify": [
        {"kind": "status", "value": "待验收"},
        {"kind": "status", "value": "已通过"},
        {"kind": "status", "value": "需返工"},
    ],
    "shift": [
        {"kind": "status", "value": "待交接"},
        {"kind": "total"},
        {"kind": "abnormal"},
    ],
    "assess": [
        {"kind": "pending"},
        {"kind": "abnormal"},
        {"kind": "total"},
    ],
}


def compute_stats(module: str, rows: list[dict[str, Any]]) -> list[int] | None:
    """按模块口径从全表行计算三张卡片的数字；未配置口径的模块返回 None。"""
    spec = MODULE_STATS.get(module)
    if spec is None:
        return None
    values: list[int] = []
    for rule in spec:
        kind = rule["kind"]
        if kind == "total":
            values.append(len(rows))
        elif kind == "pending":
            values.append(sum(1 for row in rows if row.get("pending")))
        elif kind == "abnormal":
            values.append(sum(1 for row in rows if row.get("abnormal")))
        else:
            target = rule["value"]
            values.append(sum(1 for row in rows if row.get("status") == target))
    return values
