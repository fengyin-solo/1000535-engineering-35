#!/usr/bin/env bash
# 后端依赖自检：虚拟环境坏了就重建，缺 pip 引导就手工 bootstrap，
# 依赖装不上时给出可读说明并自动重试。可反复执行。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
cd "$SCRIPT_DIR/../backend"

VENV_DIR=.venv
PYTHON_BIN="$VENV_DIR/bin/python"
RETRY_TIMES=3
TAG="[后端依赖]"

command -v python3 >/dev/null 2>&1 || {
  err "$TAG 未找到 python3，请先安装 Python 3.10 或更高版本"
  exit 1
}

# 1) 已存在的虚拟环境如果是坏的（比如从别的机器、别的系统复制过来的），直接重建
if [ -d "$VENV_DIR" ]; then
  if "$PYTHON_BIN" -c 'pass' 2>/dev/null; then
    log "$TAG 已有虚拟环境可用"
  else
    warn "$TAG 检测到损坏的虚拟环境（常见于从其他系统复制的 .venv），自动重建"
    rm -rf "$VENV_DIR"
  fi
fi

# 2) 创建虚拟环境；系统缺 ensurepip（python3-venv 未装）时退化为手工引导 pip
if [ ! -d "$VENV_DIR" ]; then
  log "$TAG 创建虚拟环境 $VENV_DIR"
  if ! python3 -m venv "$VENV_DIR" 2>/dev/null; then
    warn "$TAG python3 -m venv 失败（常见原因：系统缺少 ensurepip，Debian/Ubuntu 需安装 python3-venv）"
    log "$TAG 改用 --without-pip 创建，再手工引导 pip"
    rm -rf "$VENV_DIR"
    if ! python3 -m venv --without-pip "$VENV_DIR"; then
      err "$TAG 虚拟环境创建失败。请先安装 python3-venv（Debian/Ubuntu：sudo apt install python3-venv）后重试"
      exit 1
    fi
    GET_PIP="${GET_PIP:-/tmp/get-pip.py}"
    if [ ! -f "$GET_PIP" ]; then
      log "$TAG 下载 get-pip.py 引导 pip"
      if ! curl -fsSL --connect-timeout 10 https://bootstrap.pypa.io/get-pip.py -o "$GET_PIP"; then
        err "$TAG pip 引导文件下载失败：请检查网络/代理，或安装 python3-venv 后重试"
        exit 1
      fi
    fi
    "$PYTHON_BIN" "$GET_PIP" >/dev/null
  fi
fi

# 3) 依赖已就绪就跳过安装（重复执行不会重复装）
if "$PYTHON_BIN" -c 'import fastapi, uvicorn, pydantic' 2>/dev/null; then
  log "$TAG fastapi / uvicorn / pydantic 已就绪"
  exit 0
fi

# 4) 安装依赖，失败时自动重试并给出可读的排查说明
attempt=1
while [ "$attempt" -le "$RETRY_TIMES" ]; do
  log "$TAG 安装依赖（第 $attempt/$RETRY_TIMES 次）：pip install -r requirements.txt"
  if "$VENV_DIR/bin/pip" install -r requirements.txt \
    && "$PYTHON_BIN" -c 'import fastapi, uvicorn, pydantic' 2>/dev/null; then
    log "$TAG 依赖安装完成"
    exit 0
  fi
  warn "$TAG 第 $attempt 次安装未成功"
  attempt=$((attempt + 1))
  [ "$attempt" -le "$RETRY_TIMES" ] && sleep 3
done

err "$TAG 依赖多次安装失败，请按下面排查后重新执行 make install："
err "$TAG   1. 网络/代理：确认能访问 pypi.org，必要时设置 HTTP_PROXY / HTTPS_PROXY"
err "$TAG   2. 公司内网：可切换镜像，如 pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple"
err "$TAG   3. 版本冲突：往上看 pip 输出的第一行 ERROR"
exit 1
