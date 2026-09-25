#!/usr/bin/env bash
# 只装依赖、不起服务：后端 .venv（自动引导 pip）+ 前端 node_modules。
# 装不上时给出可读说明并允许重试。供 make install 调用，也可直接运行。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"
VENV_DIR="$BACKEND_DIR/.venv"
LOG_DIR="$ROOT_DIR/.local/logs"

c_info() { printf '\033[1;34m▶ %s\033[0m\n' "$*"; }
c_ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
c_err()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    c_err "未找到命令：$1"
    echo >&2
    echo "  $2" >&2
    echo >&2
    exit 1
  fi
}

ask_retry() {
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
  日志：.local/logs/pip.log
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
  日志：.local/logs/npm.log
EOF
}

c_info "检查本机运行环境…"
require_cmd python3 "请先安装 Python 3.10+ 并确保 python3 在 PATH 中（后端使用，无需系统级 pip）。"
require_cmd node "请先安装 Node.js 18+（前端使用）：https://nodejs.org/"
require_cmd npm "Node.js 自带 npm；如缺失请重新安装 Node.js 18+。"
c_ok "python3 $(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])') · node $(node --version) · npm $(npm --version)"

mkdir -p "$LOG_DIR"

# 仅看 .bin/vite 不够：从其他系统/架构拷来的 node_modules 会缺平台相关的
# 可选依赖（典型：@rollup/rollup-linux-* 缺失），真正 import 才能暴露问题。
frontend_ready() {
  [ -x "$FRONTEND_DIR/node_modules/.bin/vite" ] &&
    (cd "$FRONTEND_DIR" && node -e "import('vite').then(()=>process.exit(0)).catch(()=>process.exit(1))" >/dev/null 2>&1)
}

# ---------- 后端 ----------

if [ -x "$VENV_DIR/bin/python" ] && "$VENV_DIR/bin/python" -c "import fastapi, uvicorn" >/dev/null 2>&1; then
  c_ok "后端虚拟环境已就绪（$VENV_DIR），跳过"
else
  c_info "安装后端依赖到 backend/.venv …"
  while true; do
    set +e
    (
      set -e
      if [ -e "$VENV_DIR" ] && [ ! -x "$VENV_DIR/bin/python" ]; then
        echo "[install] 发现不可用的 .venv（可能来自其他系统/Python 版本），正在重建…"
        rm -rf "$VENV_DIR"
      fi
      if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR" 2>/dev/null || python3 -m venv --without-pip "$VENV_DIR"
      fi
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
    code=$?
    set -e
    if [ "$code" -eq 0 ] && "$VENV_DIR/bin/python" -c "import fastapi, uvicorn" >/dev/null 2>&1; then
      c_ok "后端依赖安装完成"
      break
    fi
    c_err "后端依赖安装失败（完整日志：$LOG_DIR/pip.log）"
    tail -n 15 "$LOG_DIR/pip.log" 2>/dev/null | sed 's/^/    /' >&2 || true
    print_pip_help >&2
    ask_retry "是否重新安装后端依赖？" || exit 1
  done
fi

# ---------- 前端 ----------

if frontend_ready; then
  c_ok "前端依赖已就绪（frontend/node_modules），跳过"
else
  # 跨平台拷来的 node_modules（缺 @rollup/rollup-<平台> 等）先清掉再装
  if [ -d "$FRONTEND_DIR/node_modules" ]; then
    c_info "现有 node_modules 无法加载（可能来自其他系统/架构），重新安装…"
    rm -rf "$FRONTEND_DIR/node_modules"
  fi
  c_info "安装前端依赖（npm install）…"
  while true; do
    set +e
    (cd "$FRONTEND_DIR" && npm install) >"$LOG_DIR/npm.log" 2>&1
    code=$?
    set -e
    if [ "$code" -eq 0 ] && frontend_ready; then
      c_ok "前端依赖安装完成"
      break
    fi
    c_err "前端依赖安装失败（完整日志：$LOG_DIR/npm.log）"
    tail -n 15 "$LOG_DIR/npm.log" 2>/dev/null | sed 's/^/    /' >&2 || true
    print_npm_help >&2
    ask_retry "是否重新安装前端依赖？" || exit 1
  done
fi

c_ok "全部依赖已就绪：make dev 启动本地一条链"
