#!/usr/bin/env bash
# ============================================================================
# 本地一条链：装依赖（缺失时引导）→ 起后端、前端 → 自检端口与示例数据。
#
#   ./scripts/dev.sh            # 依赖没装就先装，然后起前后端并自检
#   ./scripts/dev.sh --no-install   # 跳过依赖安装
#
# 行为约定：
# - 默认端口被占用时自动落到下一个可用端口，最终地址在终端横幅里打印；
# - 示例数据只在后端首次启动时写入 backend/.local/data.json，
#   重复执行本脚本不会重复塞入，运行期改动重启后仍在；
# - 依赖装不上时打印可读的排查说明，并允许选择重试；
# - 退出（Ctrl+C）时会一起停掉前后端。
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"
VENV_DIR="$BACKEND_DIR/.venv"
LOG_DIR="$ROOT_DIR/.local/logs"
STATE_DIR="$ROOT_DIR/.local"
BACKEND_LOG="$LOG_DIR/backend.log"
FRONTEND_LOG="$LOG_DIR/frontend.log"
BACKEND_URL_FILE="$STATE_DIR/backend.url"

PREFERRED_BACKEND_PORT="${BACKEND_PORT:-8000}"
PREFERRED_FRONTEND_PORT="${FRONTEND_PORT:-5173}"

BACKEND_PID=""
FRONTEND_PID=""
STOPPING=""

c_info() { printf '\033[1;34m▶ %s\033[0m\n' "$*"; }
c_ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; }

request_stop() {
  # Ctrl+C：置标志并唤醒 wait（wait 被信号打断后返回非零，循环会看到标志）
  STOPPING=1
}

cleanup() {
  trap - EXIT
  echo
  c_info "正在停止前后端服务…"
  # 前后端与本脚本同属一个进程组，npm 还会再 fork sh/node；
  # 按进程组负 PID 发信号，把子孙进程一并收走。
  kill -INT -"$$" 2>/dev/null || true
  local waited=0
  while [ "$waited" -lt 8 ]; do
    local alive=0
    for pid in "$FRONTEND_PID" "$BACKEND_PID"; do
      [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && alive=1
    done
    [ "$alive" -eq 0 ] && break
    sleep 1
    waited=$((waited + 1))
  done
  for pid in "$FRONTEND_PID" "$BACKEND_PID"; do
    [ -n "$pid" ] || continue
    # 只强杀还活着的业务子进程；本脚本自己不能用负 PID 自杀（会再次进 cleanup）
    kill -KILL "$pid" 2>/dev/null || true
  done
  # 兜底收掉 npm 留下的孙进程
  pkill -KILL -P $$ 2>/dev/null || true
  c_ok "已停止，本地运行数据保留在 backend/.local/data.json，下次启动继续使用"
}
trap cleanup EXIT
trap request_stop INT TERM

# ---------- 环境检查 ----------

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    c_err "未找到命令：$1"
    cat >&2 <<EOF

  $2

EOF
    exit 1
  fi
}

port_in_use() {
  # $1=host $2=port；能连上即视为被占用
  python3 - "$1" "$2" <<'PY'
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.settimeout(0.3)
    sys.exit(0 if s.connect_ex((host, port)) == 0 else 1)
PY
}

find_free_port() {
  # $1=host $2=preferred；从首选端口开始找一个没被占用的
  python3 - "$1" "$2" <<'PY'
import socket, sys
host, port = sys.argv[1], int(sys.argv[2])
for _ in range(100):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind((host, port))
        except OSError:
            port += 1
            continue
    print(port)
    sys.exit(0)
sys.exit(1)
PY
}

c_info "检查本机运行环境…"
require_cmd python3 "请先安装 Python 3.10+ 并确保 python3 在 PATH 中（后端使用，无需系统级 pip）。"
require_cmd node "请先安装 Node.js 18+（前端使用）：https://nodejs.org/"
require_cmd npm "Node.js 自带 npm；如缺失请重新安装 Node.js 18+。"
PY_VER="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
c_ok "python3 $PY_VER · node $(node --version) · npm $(npm --version)"

# ---------- 依赖安装（带可读说明 + 重试） ----------

print_pip_help() {
  cat <<'EOF'
  Python 依赖安装失败，常见原因与处理：
    1) 没有网络 / 公司代理：检查网络，或设置 pip 镜像后重试，例如
       export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
    2) 系统 Python 缺少 venv 模块（Debian/Ubuntu 常见）：
       sudo apt-get install python3-venv
       （脚本已尝试自动引导 pip，仍失败时需要安装该系统包）
    3) 旧的 .venv 是在其他机器/其他 Python 版本上创建的（符号链接失效）：
       删除后重试：rm -rf backend/.venv
    4) Python 版本过低：本项目需要 Python 3.10+。
  日志：.local/logs/ 下可查看 pip 输出。
EOF
}

print_npm_help() {
  cat <<'EOF'
  前端依赖安装失败，常见原因与处理：
    1) 没有网络 / 公司代理：检查网络，或切换 npm 镜像后重试，例如
       npm config set registry https://registry.npmmirror.com
    2) node_modules 残缺（切换分支/中断安装后常见）：
       删除后重试：rm -rf frontend/node_modules frontend/package-lock.json
    3) Node 版本过低：本项目需要 Node.js 18+。
EOF
}

ask_retry() {
  # $1 = 说明；返回 0 表示重试
  local answer
  if [ ! -t 0 ]; then
    c_err "$1（当前不是交互终端，无法询问重试，直接退出）"
    return 1
  fi
  while true; do
    printf '  输入 r 重试，q 退出 [r/q]: '
    read -r answer || return 1
    case "$answer" in
      r|R) return 0 ;;
      qQ|"") return 1 ;;
      *) echo "  请输入 r 或 q" ;;
    esac
  done
}

install_backend() {
  mkdir -p "$LOG_DIR"
  if [ -x "$VENV_DIR/bin/python" ] && "$VENV_DIR/bin/python" -c "import fastapi, uvicorn" >/dev/null 2>&1; then
    c_ok "后端虚拟环境已就绪（$VENV_DIR）"
    return 0
  fi

  c_info "安装后端依赖到 backend/.venv …"
  while true; do
    set +e
    (
      set -e
      # 旧 venv 不可用（比如来自其他系统/其他 Python 版本）时重建
      if [ -e "$VENV_DIR" ] && [ ! -x "$VENV_DIR/bin/python" ]; then
        echo "[install] 发现不可用的 .venv，正在重建…"
        rm -rf "$VENV_DIR"
      fi
      if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR" 2>/dev/null || python3 -m venv --without-pip "$VENV_DIR"
      fi
      # 某些发行版的 venv 默认不带 pip（Debian/Ubuntu 未装 python3-venv 完整版）
      if [ ! -x "$VENV_DIR/bin/pip" ]; then
        echo "[install] venv 中没有 pip，正在从 bootstrap.pypa.io 引导…"
        "$VENV_DIR/bin/python" -m ensurepip --upgrade 2>/dev/null || {
          bootstrap="$(mktemp)"
          curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "$bootstrap"
          "$VENV_DIR/bin/python" "$bootstrap"
          rm -f "$bootstrap"
        }
      fi
      "$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
      "$VENV_DIR/bin/python" -m pip install -r "$BACKEND_DIR/requirements.txt"
    ) >"$LOG_DIR/pip.log" 2>&1
    local code=$?
    set -e
    if [ "$code" -eq 0 ] && "$VENV_DIR/bin/python" -c "import fastapi, uvicorn" >/dev/null 2>&1; then
      c_ok "后端依赖安装完成"
      return 0
    fi
    c_err "后端依赖安装失败（完整日志：$LOG_DIR/pip.log）"
    tail -n 15 "$LOG_DIR/pip.log" 2>/dev/null | sed 's/^/    /' >&2 || true
    print_pip_help >&2
    ask_retry "是否重新安装后端依赖？" || exit 1
  done
}

install_frontend() {
  mkdir -p "$LOG_DIR"
  # 仅看 .bin/vite 不够：跨平台拷来的 node_modules 会缺平台相关可选依赖
  # （典型：@rollup/rollup-linux-* 缺失），真正 import 才能暴露问题
  if [ -x "$FRONTEND_DIR/node_modules/.bin/vite" ] \
      && (cd "$FRONTEND_DIR" && node -e "import('vite').then(()=>process.exit(0)).catch(()=>process.exit(1))" >/dev/null 2>&1); then
    c_ok "前端依赖已就绪（frontend/node_modules）"
    return 0
  fi
  if [ -d "$FRONTEND_DIR/node_modules" ]; then
    c_warn "现有 node_modules 无法加载（可能来自其他系统/架构），删除后重装"
    rm -rf "$FRONTEND_DIR/node_modules"
  fi
  c_info "安装前端依赖（npm install）…"
  while true; do
    set +e
    (cd "$FRONTEND_DIR" && npm install) >"$LOG_DIR/npm.log" 2>&1
    local code=$?
    set -e
    if [ "$code" -eq 0 ] && [ -x "$FRONTEND_DIR/node_modules/.bin/vite" ]; then
      c_ok "前端依赖安装完成"
      return 0
    fi
    c_err "前端依赖安装失败（完整日志：$LOG_DIR/npm.log）"
    tail -n 15 "$LOG_DIR/npm.log" 2>/dev/null | sed 's/^/    /' >&2 || true
    print_npm_help >&2
    ask_retry "是否重新安装前端依赖？" || exit 1
  done
}

if [ "${1:-}" != "--no-install" ]; then
  install_backend
  install_frontend
else
  c_info "已指定 --no-install，跳过依赖安装"
  install_backend  # 只做“已就绪”检查，不触发安装
  if ! (cd "$FRONTEND_DIR" && node -e "import('vite').then(()=>process.exit(0)).catch(()=>process.exit(1))" >/dev/null 2>&1); then
    c_err "前端依赖未安装或无法加载（可能来自其他系统/架构），请去掉 --no-install 或先执行 make install"
    exit 1
  fi
fi

# ---------- 选择端口 ----------

c_info "检查端口占用…"
BACKEND_HOST="127.0.0.1"
FRONTEND_HOST="127.0.0.1"
BACKEND_PORT="$(find_free_port "$BACKEND_HOST" "$PREFERRED_BACKEND_PORT")"
FRONTEND_PORT="$(find_free_port "$FRONTEND_HOST" "$PREFERRED_FRONTEND_PORT")"
if [ "$BACKEND_PORT" != "$PREFERRED_BACKEND_PORT" ]; then
  c_warn "后端端口 $PREFERRED_BACKEND_PORT 已被占用，落到 $BACKEND_PORT"
fi
if [ "$FRONTEND_PORT" != "$PREFERRED_FRONTEND_PORT" ]; then
  c_warn "前端端口 $PREFERRED_FRONTEND_PORT 已被占用，落到 $FRONTEND_PORT"
fi
BACKEND_BASE="http://$BACKEND_HOST:$BACKEND_PORT"
FRONTEND_BASE="http://$FRONTEND_HOST:$FRONTEND_PORT"
c_ok "后端 $BACKEND_BASE · 前端 $FRONTEND_BASE"

mkdir -p "$LOG_DIR" "$STATE_DIR"
: > "$BACKEND_LOG"
: > "$FRONTEND_LOG"

# ---------- 启动后端 ----------

c_info "启动后端…"
# 子进程都留在本脚本的进程组里，Ctrl+C 或退出时 cleanup 用负 PID 整组收掉
(
  cd "$BACKEND_DIR"
  APP_HOST="$BACKEND_HOST" APP_PORT="$BACKEND_PORT" \
    exec "$VENV_DIR/bin/python" run.py
) >"$BACKEND_LOG" 2>&1 &
BACKEND_PID=$!

# 等待后端真正监听（run.py 还会再做一次端口探测做双保险）
deadline=$(( $(date +%s) + 30 ))
while true; do
  if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
    c_err "后端进程提前退出，日志末尾："
    tail -n 30 "$BACKEND_LOG" >&2 || true
    exit 1
  fi
  if port_in_use "$BACKEND_HOST" "$BACKEND_PORT"; then break; fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    c_err "后端 30 秒内未监听 $BACKEND_BASE，日志末尾："
    tail -n 30 "$BACKEND_LOG" >&2 || true
    exit 1
  fi
  sleep 0.5
done

# 从日志解析最终地址（run.py 固定输出这一行）
LISTEN_LINE="$(grep -m1 'listening on' "$BACKEND_LOG" 2>/dev/null || true)"
if [ -n "$LISTEN_LINE" ]; then
  BACKEND_BASE="$(printf '%s' "$LISTEN_LINE" | grep -oE 'http://[0-9.]+:[0-9]+')"
fi
echo "$BACKEND_BASE" > "$BACKEND_URL_FILE"

c_info "后端健康检查：$BACKEND_BASE/api/health"
HEALTH_RESP="$(curl -fsS --retry 5 --retry-connrefused --retry-delay 1 "$BACKEND_BASE/api/health")" || {
  c_err "后端健康检查失败：$HEALTH_RESP"
  exit 1
}
echo "$HEALTH_RESP" | sed 's/^/    /'
echo "$HEALTH_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["ok"] and d["seeded"] and d["modules"] >= 18, d' \
  && c_ok "后端健康且示例数据已就绪"

# ---------- 启动前端 ----------

c_info "启动前端（/api 代理到 $BACKEND_BASE）…"
(
  cd "$FRONTEND_DIR"
  VITE_PORT="$FRONTEND_PORT" VITE_PROXY_TARGET="$BACKEND_BASE" \
    exec npm run dev -- --host "$FRONTEND_HOST"
) >"$FRONTEND_LOG" 2>&1 &
FRONTEND_PID=$!

deadline=$(( $(date +%s) + 60 ))
FRONTEND_READY=""
while true; do
  if ! kill -0 "$FRONTEND_PID" 2>/dev/null; then
    c_err "前端进程提前退出，日志末尾："
    tail -n 30 "$FRONTEND_LOG" >&2 || true
    exit 1
  fi
  if curl -fsS -o /dev/null "$FRONTEND_BASE/" 2>/dev/null; then
    FRONTEND_READY=1
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    c_err "前端 60 秒内未响应，日志末尾："
    tail -n 30 "$FRONTEND_LOG" >&2 || true
    exit 1
  fi
  sleep 0.5
done
c_ok "前端已响应 $FRONTEND_BASE"

# ---------- 数据一致性自检：列表数与概览数对得上 ----------

c_info "自检：各模块列表 total 与 /api/overview 数字一致性…"
"$VENV_DIR/bin/python" - "$BACKEND_BASE" <<'PY'
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
if cards.get("今日新增") != created_total:
    failures.append(f"卡片 今日新增={cards.get('今日新增')} 与模块合计 {created_total} 不一致")
if cards.get("待处理") != pending_total:
    failures.append(f"卡片 待处理={cards.get('待处理')} 与模块合计 {pending_total} 不一致")
if cards.get("异常量") != abnormal_total:
    failures.append(f"卡片 异常量={cards.get('异常量')} 与模块合计 {abnormal_total} 不一致")
if cards.get("业务模块") != len(by_name):
    failures.append(f"卡片 业务模块={cards.get('业务模块')} 与模块数 {len(by_name)} 不一致")

if failures:
    print("自检发现不一致：", file=sys.stderr)
    for line in failures:
        print("  - " + line, file=sys.stderr)
    sys.exit(1)

print(f"    {len(by_name)} 个模块 · 今日新增 {created_total} · 待处理 {pending_total} · 异常量 {abnormal_total}")
print("    各模块列表 total 与概览卡片全部对得上")
PY
c_ok "数据一致性自检通过"

# 通过前端代理再打一次，确认 /api 代理链路也是通的
if curl -fsS -o /dev/null "$FRONTEND_BASE/api/health"; then
  c_ok "前端 /api 代理链路正常"
else
  c_warn "前端代理暂未就绪（可直接访问后端，或稍后刷新页面）"
fi

# ---------- 横幅 ----------

cat <<EOF

$(printf '\033[1;32m%s\033[0m' '────────────────────────────────────────────────────────')
  $(printf '\033[1m%s\033[0m' '本地环境已就绪，一条链全部跑通')
  前端地址：  $FRONTEND_BASE
  后端地址：  $BACKEND_BASE
  健康检查：  $BACKEND_BASE/api/health
  运行日志：  $BACKEND_LOG
              $FRONTEND_LOG
  数据文件：  $BACKEND_DIR/.local/data.json（重启不重复灌入，make reset-data 可重置）
$(printf '\033[1;32m%s\033[0m' '────────────────────────────────────────────────────────')
  按 Ctrl+C 可同时停止前后端。
EOF

# 前台等待两个直接子进程。不用等所有后台任务：
# 子 shell 里 setsid 出的 npm 在 setsid 退出后会被 init 收养，
# 若 wait 它们会一直 do_wait、把 Ctrl+C 的 trap 拖到永远。
# 服务本身由 cleanup 按进程组（PGID=各自的子 PID）统一收掉。
while [ -z "$STOPPING" ] && kill -0 "$BACKEND_PID" 2>/dev/null && kill -0 "$FRONTEND_PID" 2>/dev/null; do
  sleep 1
done
