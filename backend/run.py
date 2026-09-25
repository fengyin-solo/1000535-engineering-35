#!/usr/bin/env python3
"""本地启动入口：选一个可用端口，打印最终地址，再起 uvicorn。

用法：
    python run.py                # 从 APP_PORT 或 8000 开始找可用端口
    python run.py --port 9000    # 指定首选端口
首选端口被占用时自动落到下一个可用端口（最多扫 APP_PORT_SCAN_LIMIT 个），
最终端口会打印成固定格式，scripts/dev.sh 据此把地址传给前端代理。
"""
from __future__ import annotations

import os
import socket
import sys

import uvicorn

from app.config import settings


def is_free(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            probe.bind((host, port))
        except OSError:
            return False
    return True


def pick_port(host: str, preferred: int, scan_limit: int) -> int:
    for offset in range(max(scan_limit, 1)):
        candidate = preferred + offset
        if is_free(host, candidate):
            if offset:
                print(
                    f"[backend] 端口 {preferred} 已被占用，改用 {candidate}",
                    flush=True,
                )
            return candidate
    raise SystemExit(
        f"[backend] 从 {preferred} 起连续 {scan_limit} 个端口都被占用，请释放端口或用 APP_PORT 指定其他端口"
    )


def main() -> None:
    host = settings.host
    preferred = settings.port
    if "--port" in sys.argv:
        index = sys.argv.index("--port")
        if index + 1 < len(sys.argv):
            preferred = int(sys.argv[index + 1])
    scan_limit = settings.port_scan_limit

    port = pick_port(host, preferred, scan_limit)

    # 固定格式输出，scripts/dev.sh 用这一行解析后端真实地址并配置前端代理
    print(f"[backend] listening on http://{host}:{port}", flush=True)
    print(f"[backend] health:  http://{host}:{port}/api/health", flush=True)

    # 数据文件位置也打出来，方便排查示例数据写到了哪里
    print(f"[backend] data:    {settings.data_path}", flush=True)

    uvicorn.run(
        "app.main:app",
        host=host,
        port=port,
        log_level=os.environ.get("APP_LOG_LEVEL", "info"),
    )


if __name__ == "__main__":
    main()
