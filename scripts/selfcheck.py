#!/usr/bin/env python3
"""启动自检：确认端口能通、示例数据已生成、各模块列表与概览数字对得上。

只依赖标准库，用法：
    python3 scripts/selfcheck.py --backend http://127.0.0.1:8000 --frontend http://127.0.0.1:5173

任何一项不达标都会以非零码退出，并打印可读的原因。
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request

FAILURES: list[str] = []


def check(ok: bool, label: str, detail: str = "") -> None:
    mark = "✓" if ok else "✗"
    line = f"  {mark} {label}"
    if detail:
        line += f"（{detail}）"
    print(line)
    if not ok:
        FAILURES.append(label)


def fetch_json(url: str, timeout: int = 5) -> dict:
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description="本地运行自检")
    parser.add_argument("--backend", default="http://127.0.0.1:8000")
    parser.add_argument("--frontend", default="http://127.0.0.1:5173")
    args = parser.parse_args()
    backend = args.backend.rstrip("/")
    frontend = args.frontend.rstrip("/")

    # 1) 后端健康检查：不通就没有继续的意义
    try:
        health = fetch_json(f"{backend}/api/health")
    except (urllib.error.URLError, OSError) as exc:
        check(False, "后端健康检查", f"{backend}/api/health 不可达：{exc}")
        print("\n自检未通过：后端都连不上，请先确认后端已启动（make dev 或 make backend）")
        return 1
    check(health.get("ok") is True, "后端健康检查", f"{backend}/api/health")
    check(
        isinstance(health.get("modules"), int) and health["modules"] > 0,
        "示例数据已就绪",
        f"{health.get('modules')} 个业务模块",
    )

    # 2) 概览卡片与模块明细内部一致
    overview = fetch_json(f"{backend}/api/overview")
    cards = {card["label"]: card["value"] for card in overview.get("cards", [])}
    modules = overview.get("modules", [])
    check(cards.get("业务模块") == len(modules), "概览卡片：业务模块数与模块清单一致", f"{len(modules)} 个")
    check(
        cards.get("今日新增") == sum(int(m["created"]) for m in modules),
        "概览卡片：今日新增 = 各模块记录数之和",
        f"{cards.get('今日新增')} 条",
    )
    check(
        cards.get("待处理") == sum(int(m["pending"]) for m in modules),
        "概览卡片：待处理 = 各模块待处理之和",
        f"{cards.get('待处理')} 条",
    )
    check(
        cards.get("异常量") == sum(int(m["abnormal"]) for m in modules),
        "概览卡片：异常量 = 各模块异常之和",
        f"{cards.get('异常量')} 条",
    )
    check(
        all(int(m["created"]) > 0 for m in modules),
        "每个模块都有示例记录",
        "没有全为零的模块" if modules else "模块清单为空",
    )

    # 3) 每个模块：列表总数对得上概览，统计卡片已生成
    for module in modules:
        name = module["name"]
        try:
            page = fetch_json(f"{backend}/api/{name}?page=1&size=1")
            check(
                page.get("total") == module["created"],
                f"模块 {name}：列表 total 对得上概览",
                f"total={page.get('total')} / 概览={module['created']}",
            )
        except (urllib.error.URLError, OSError) as exc:
            check(False, f"模块 {name}：列表接口", str(exc))
            continue
        try:
            stats = fetch_json(f"{backend}/api/{name}/stats")
            items = stats.get("items") or []
            check(
                len(items) > 0 and all("label" in item and "value" in item for item in items),
                f"模块 {name}：统计卡片已生成",
                "、".join(f"{item['label']}={item['value']}" for item in items),
            )
        except (urllib.error.URLError, OSError) as exc:
            check(False, f"模块 {name}：统计卡片接口", str(exc))

    # 4) 前端页面能打开
    try:
        with urllib.request.urlopen(frontend, timeout=5) as resp:
            body = resp.read().decode("utf-8", "ignore")
            status = resp.status
        check(
            status == 200 and "轨道交通信号设备检修平台" in body,
            "前端页面可访问",
            frontend,
        )
    except (urllib.error.URLError, OSError) as exc:
        check(False, "前端页面可访问", f"{frontend} 不可达：{exc}")

    if FAILURES:
        print(f"\n自检未通过：{len(FAILURES)} 项不达标")
        return 1
    print(f"\n自检通过：{len(modules)} 个模块的列表、统计卡片与概览数字全部对得上")
    return 0


if __name__ == "__main__":
    sys.exit(main())
