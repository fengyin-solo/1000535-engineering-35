#!/usr/bin/env bash
# 只对已在运行的服务做自检：端口从 .run 里读，没有记录就用默认端口。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_DIR="$ROOT/.run"

BACKEND_PORT="$(cat "$RUN_DIR/backend.port" 2>/dev/null || echo 8000)"
FRONTEND_PORT="$(cat "$RUN_DIR/frontend.port" 2>/dev/null || echo 5173)"

python3 "$ROOT/scripts/selfcheck.py" \
  --backend "http://127.0.0.1:$BACKEND_PORT" \
  --frontend "http://127.0.0.1:$FRONTEND_PORT"
