#!/usr/bin/env bash
# 本地运行一条链：装依赖 → 起后端 → 起前端 → 自检端口与示例数据。
#
#   bash scripts/dev.sh
#
# 行为约定：
#   - 服务已在运行时直接复用，不会重复塞入示例数据；
#   - 首选端口（后端 8000 / 前端 5173）被占用时自动落到下一个空闲端口并打印；
#   - 依赖装不上时给出可读说明并自动重试（见 scripts/ensure-*.sh）；
#   - 运行状态（pid、端口、日志）放在 .run/，与构建产物 frontend/dist 互不干扰；
#   - 停止服务用 make stop（或 bash scripts/stop.sh）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_DIR="$ROOT/.run"
mkdir -p "$RUN_DIR"
source "$ROOT/scripts/lib.sh"

BACKEND_BASE_PORT=8000
FRONTEND_BASE_PORT=5173

# ---------- 1) 依赖 ----------
bash "$ROOT/scripts/ensure-backend-deps.sh"
bash "$ROOT/scripts/ensure-frontend-deps.sh"

# ---------- 2) 后端：已在跑就复用，否则选端口启动 ----------
BACKEND_PORT=""
if [ -f "$RUN_DIR/backend.pid" ] && kill -0 "$(cat "$RUN_DIR/backend.pid")" 2>/dev/null; then
  candidate="$(cat "$RUN_DIR/backend.port")"
  if curl -fsS --max-time 2 "http://127.0.0.1:$candidate/api/health" >/dev/null 2>&1; then
    BACKEND_PORT="$candidate"
    log "[后端] 已在运行（http://127.0.0.1:$BACKEND_PORT），直接复用，不重复塞入示例数据"
  else
    warn "[后端] 发现残留进程，先停掉再重启"
    kill -- -"$(cat "$RUN_DIR/backend.pid")" 2>/dev/null || kill "$(cat "$RUN_DIR/backend.pid")" 2>/dev/null || true
    sleep 1
  fi
fi

if [ -z "$BACKEND_PORT" ]; then
  BACKEND_PORT="$(find_free_port "$BACKEND_BASE_PORT")"
  if [ "$BACKEND_PORT" != "$BACKEND_BASE_PORT" ]; then
    warn "[后端] 端口 $BACKEND_BASE_PORT 被占用，落到下一个可用端口：$BACKEND_PORT"
  fi
  (
    cd "$ROOT/backend"
    # setsid 让服务自成一个进程组，停止时能整组收掉，不留下孤儿进程
    setsid nohup .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port "$BACKEND_PORT" \
      >"$RUN_DIR/backend.log" 2>&1 &
    echo $! >"$RUN_DIR/backend.pid"
  )
  echo "$BACKEND_PORT" >"$RUN_DIR/backend.port"
  log "[后端] 启动中（端口 $BACKEND_PORT，日志 .run/backend.log）"
  if ! wait_http_ok "http://127.0.0.1:$BACKEND_PORT/api/health" 30; then
    err "[后端] 30 秒内未就绪，最近日志如下："
    tail -n 20 "$RUN_DIR/backend.log" >&2 || true
    exit 1
  fi
fi

# ---------- 3) 前端：代理目标变了就重启，否则复用 ----------
FRONTEND_PORT=""
if [ -f "$RUN_DIR/frontend.pid" ] && kill -0 "$(cat "$RUN_DIR/frontend.pid")" 2>/dev/null; then
  candidate="$(cat "$RUN_DIR/frontend.port")"
  target="$(cat "$RUN_DIR/frontend.proxy" 2>/dev/null || true)"
  if [ "$target" = "$BACKEND_PORT" ] \
    && curl -fsS -o /dev/null --max-time 2 "http://127.0.0.1:$candidate" 2>/dev/null; then
    FRONTEND_PORT="$candidate"
    log "[前端] 已在运行（http://127.0.0.1:$FRONTEND_PORT），直接复用"
  else
    warn "[前端] 后端端口已变化或进程异常，重启前端"
    kill -- -"$(cat "$RUN_DIR/frontend.pid")" 2>/dev/null || kill "$(cat "$RUN_DIR/frontend.pid")" 2>/dev/null || true
    sleep 1
  fi
fi

if [ -z "$FRONTEND_PORT" ]; then
  FRONTEND_PORT="$(find_free_port "$FRONTEND_BASE_PORT")"
  if [ "$FRONTEND_PORT" != "$FRONTEND_BASE_PORT" ]; then
    warn "[前端] 端口 $FRONTEND_BASE_PORT 被占用，落到下一个可用端口：$FRONTEND_PORT"
  fi
  (
    cd "$ROOT/frontend"
    VITE_PROXY_TARGET="http://127.0.0.1:$BACKEND_PORT" \
      setsid nohup npm run dev -- --port "$FRONTEND_PORT" --strictPort \
      >"$RUN_DIR/frontend.log" 2>&1 &
    echo $! >"$RUN_DIR/frontend.pid"
  )
  echo "$FRONTEND_PORT" >"$RUN_DIR/frontend.port"
  echo "$BACKEND_PORT" >"$RUN_DIR/frontend.proxy"
  log "[前端] 启动中（端口 $FRONTEND_PORT，代理 /api → http://127.0.0.1:$BACKEND_PORT，日志 .run/frontend.log）"
  if ! wait_http_ok "http://127.0.0.1:$FRONTEND_PORT" 60; then
    err "[前端] 60 秒内未就绪，最近日志如下："
    tail -n 20 "$RUN_DIR/frontend.log" >&2 || true
    exit 1
  fi
fi

# ---------- 4) 自检：端口、示例数据、列表与概览数字 ----------
log "[自检] 校验端口连通性、示例数据与概览数字……"
python3 "$ROOT/scripts/selfcheck.py" \
  --backend "http://127.0.0.1:$BACKEND_PORT" \
  --frontend "http://127.0.0.1:$FRONTEND_PORT"

# ---------- 5) 打印访问方式 ----------
cat <<EOF

============================================================
  本地运行已就绪
  前端页面：http://127.0.0.1:$FRONTEND_PORT
  后端接口：http://127.0.0.1:$BACKEND_PORT （接口文档 /docs）
  运行日志：.run/backend.log、.run/frontend.log
  停止服务：make stop
============================================================
EOF
