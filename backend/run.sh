#!/usr/bin/env bash
# 后端本地启动入口：确保虚拟环境可用（依赖由 scripts/dev.sh / make install 安装），
# 然后交给 run.py 选端口、起服务。
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -x .venv/bin/python ]; then
  echo "[backend] 未找到 .venv，请先在仓库根目录执行：make install" >&2
  exit 1
fi

exec .venv/bin/python run.py
