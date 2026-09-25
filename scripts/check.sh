#!/usr/bin/env bash
# 自检脚本：检查已经在跑的前后端（或现场拉起后端）——端口、健康检查、
# 各模块列表 total 与 /api/overview 概览数字一致性、前端 /api 代理。
#
# 用法：
#   ./scripts/check.sh                         # 默认检查 8000 / 5173
#   BACKEND_PORT=8011 FRONTEND_PORT=5174 ./scripts/check.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_HOST="127.0.0.1"
FRONTEND_HOST="127.0.0.1"
BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_PORT="${FRONTEND_PORT:-5173}"
BACKEND_BASE="http://$BACKEND_HOST:$BACKEND_PORT"
FRONTEND_BASE="http://$FRONTEND_HOST:$FRONTEND_PORT"
URL_FILE="$ROOT_DIR/.local/backend.url"
VENV_PY="$ROOT_DIR/backend/.venv/bin/python"

c_info() { printf '\033[1;34m▶ %s\033[0m\n' "$*"; }
c_ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; }

# dev.sh 会把真实后端地址写入文件；服务换端口自检时优先用它
if [ -f "$URL_FILE" ] && curl -fsS -o /dev/null "$(cat "$URL_FILE")/api/health" 2>/dev/null; then
  BACKEND_BASE="$(cat "$URL_FILE")"
  c_info "使用 dev.sh 记录的后端地址：$BACKEND_BASE"
fi

if ! curl -fsS -o /dev/null "$BACKEND_BASE/api/health" 2>/dev/null; then
  c_err "后端未在 $BACKEND_BASE 响应，请先 make dev（或 make backend）"
  exit 1
fi
HEALTH_RESP="$(curl -fsS "$BACKEND_BASE/api/health")"
c_ok "后端健康：$BACKEND_BASE/api/health → $HEALTH_RESP"

echo "$HEALTH_RESP" | "${VENV_PY:-python3}" -c 'import json,sys; d=json.load(sys.stdin); assert d["ok"] and d["seeded"] and d["modules"] >= 18, d' \
  && c_ok "示例数据已就绪（$(echo "$HEALTH_RESP" | "${VENV_PY:-python3}" -c 'import json,sys; print(json.load(sys.stdin)["modules"])') 个模块）"

"${VENV_PY:-python3}" - "$BACKEND_BASE" <<'PY'
import json, sys, urllib.request

base = sys.argv[1]

def get(path):
    with urllib.request.urlopen(base + path, timeout=10) as resp:
        return json.load(resp)

overview = get("/api/overview")
by_name = {m["name"]: m for m in overview["modules"]}
failures = []
created_total = pending_total = abnormal_total = 0
for name in sorted(by_name):
    data = get(f"/api/{name}?page=1&size=1")
    total = data["total"]
    expect = by_name[name]["created"]
    if total != expect:
        failures.append(f"{name}: 列表 total={total} 与概览 created={expect} 不一致")
    created_total += by_name[name]["created"]
    pending_total += by_name[name]["pending"]
    abnormal_total += by_name[name]["abnormal"]

cards = {c["label"]: c["value"] for c in overview["cards"]}
checks = [
    ("业务模块", cards.get("业务模块"), len(by_name)),
    ("今日新增", cards.get("今日新增"), created_total),
    ("待处理", cards.get("待处理"), pending_total),
    ("异常量", cards.get("异常量"), abnormal_total),
]
for label, got, want in checks:
    if got != want:
        failures.append(f"卡片 {label}={got} 与模块合计 {want} 不一致")

if failures:
    print("自检发现不一致：", file=sys.stderr)
    for line in failures:
        print("  - " + line, file=sys.stderr)
    sys.exit(1)

print(f"    {len(by_name)} 个模块 · 今日新增 {created_total} · 待处理 {pending_total} · 异常量 {abnormal_total}")
print("    各模块列表 total 与概览卡片全部对得上")
PY
c_ok "数据一致性自检通过"

if curl -fsS -o /dev/null "$FRONTEND_BASE/" 2>/dev/null; then
  c_ok "前端已响应：$FRONTEND_BASE"
  if curl -fsS -o /dev/null "$FRONTEND_BASE/api/health"; then
    c_ok "前端 /api 代理链路正常"
  else
    c_warn "前端在线但 /api 代理未通（检查前端是否以正确的 VITE_PROXY_TARGET 启动）"
    exit 1
  fi
else
  c_warn "前端未在 $FRONTEND_BASE 响应（仅后端自检通过）"
fi
