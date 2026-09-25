#!/usr/bin/env bash
# 停止 make dev 启动的前后端进程，并清理 .run 里的状态文件。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_DIR="$ROOT/.run"
source "$ROOT/scripts/lib.sh"

stopped=0
for name in backend frontend; do
  pid_file="$RUN_DIR/$name.pid"
  if [ -f "$pid_file" ]; then
    pid="$(cat "$pid_file")"
    if kill -0 "$pid" 2>/dev/null; then
      # 服务以独立进程组启动（setsid），整组收掉，避免 npm/vite 这类父子进程留下孤儿
      kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
      log "已停止 $name（pid $pid）"
      stopped=$((stopped + 1))
    fi
    rm -f "$pid_file"
  fi
  rm -f "$RUN_DIR/$name.port"
done
rm -f "$RUN_DIR/frontend.proxy"

if [ "$stopped" -eq 0 ]; then
  log "没有在运行的本地服务"
else
  log "已停止 $stopped 个服务"
fi
