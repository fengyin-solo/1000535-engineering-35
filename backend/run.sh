#!/usr/bin/env bash
# 后端独立启动入口：自检依赖 → 选可用端口 → 起 uvicorn。
# 被 make backend 调用，也可以直接执行：cd backend && ./run.sh
set -euo pipefail
cd "$(dirname "$0")"

# 依赖自检与修复（和 make install 同一套逻辑）
bash ../scripts/ensure-backend-deps.sh

# 端口：PORT 环境变量优先，否则从 8000 起找第一个空闲端口
source ../scripts/lib.sh
BASE_PORT="${PORT:-8000}"
PORT="$(find_free_port "$BASE_PORT")"
if [ "$PORT" != "$BASE_PORT" ]; then
  warn "端口 $BASE_PORT 被占用，落到下一个可用端口：$PORT"
fi

log "后端监听：http://127.0.0.1:$PORT （接口文档 http://127.0.0.1:$PORT/docs）"
exec .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port "$PORT"
