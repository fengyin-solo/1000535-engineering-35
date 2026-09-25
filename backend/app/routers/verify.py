"""验收确认接口：维护验收单，覆盖开始验收、确认通过、下发返工等动作。"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Query

from app.schemas import ActionResult, EntryPayload, PageResult
from app.stats import compute_stats
from app.store import store
from app.services.verify import MODULE as SERVICE_MODULE
from app.services.verify import VerifyService

router = APIRouter(prefix="/api/verify", tags=["验收确认"])

service = VerifyService()

LIST_FIELDS = ["验收单号", "关联任务", "验收项目", "验收标准", "验收结论", "验收人员", "验收日期", "验收状态"]
STATUSES = ["待验收", "验收中", "已通过", "需返工"]

@router.get("", response_model=PageResult[dict])
def list_entries(
    keyword: str | None = Query(default=None, description="按验收单号检索"),
    status: str | None = Query(default=None, description="待验收、验收中、已通过、需返工"),
    page: int = 1,
    size: int = 20,
) -> PageResult[dict]:
    """按验收单号与状态过滤验收确认列表；没有数据时返回空页，不报错。"""
    if size > 200:
        raise HTTPException(status_code=400, detail="每页最多 200 条，请缩小分页范围")
    items, total = service.list_entries(keyword=keyword, status=status, page=page, size=size)
    all_rows = store.rows(SERVICE_MODULE)
    stats = compute_stats(SERVICE_MODULE, all_rows)
    return PageResult(items=items, total=total, page=page, size=size, stats=stats)

@router.get("/export")
def export_entries() -> dict[str, Any]:
    """导出验收确认清单：返回当前过滤条件下的全量数据。"""
    items, total = service.list_entries(page=1, size=10000)
    return {"module": "verify", "total": total, "items": items}

@router.get("/{entry_id}", response_model=dict)
def get_entry(entry_id: int) -> dict:
    """读取单条验收单明细；不存在时给出可读的错误说明。"""
    entry = service.get_entry(entry_id)
    if entry is None:
        raise HTTPException(status_code=404, detail=f"验收单 {entry_id} 不存在或已归档")
    return entry

@router.post("", response_model=ActionResult)
def create_entry(payload: EntryPayload) -> ActionResult:
    """登记一条验收单，缺字段时说明原因而不是静默丢弃。"""
    entry, missing = service.create_entry(payload.values)
    if missing:
        return ActionResult(ok=False, message=f"缺少必填字段：{'、'.join(missing)}")
    return ActionResult(ok=True, message="验收单已登记", entry=entry)

@router.post("/{entry_id}/actions", response_model=ActionResult)
def run_action(entry_id: int, payload: EntryPayload) -> ActionResult:
    """对单条验收单执行开始验收、确认通过、下发返工；不允许的动作会被拦下并说明原因。"""
    # 兼容两种请求体：前端按钮直接发 {"action": "..."}，
    # 老约定发 {"values": {"action": "..."}}，两者都要认
    action = str(payload.action or payload.values.get("action") or "").strip()
    entry, message = service.run_action(entry_id, action)
    if entry is None:
        return ActionResult(ok=False, message=message)
    return ActionResult(ok=True, message=message, entry=entry)
