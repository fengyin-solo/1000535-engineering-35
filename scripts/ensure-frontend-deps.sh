#!/usr/bin/env bash
# 前端依赖自检：node_modules 坏了就重装，npm 装不上时给出可读说明并自动重试。
# 可反复执行。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
cd "$SCRIPT_DIR/../frontend"

RETRY_TIMES=3
TAG="[前端依赖]"

for cmd in node npm; do
  command -v "$cmd" >/dev/null 2>&1 || {
    err "$TAG 未找到 $cmd，请先安装 Node.js 18 或更高版本（https://nodejs.org）"
    exit 1
  }
done

# 1) node_modules 已存在且 vite 能跑，就跳过安装
if [ -d node_modules ]; then
  if [ -x node_modules/.bin/vite ] && node_modules/.bin/vite --version >/dev/null 2>&1; then
    log "$TAG node_modules 可用（vite $(node_modules/.bin/vite --version)）"
    exit 0
  fi
  warn "$TAG node_modules 损坏或不完整（常见于从其他系统复制、安装被中断），重新安装"
  rm -rf node_modules
fi

# 2) 安装依赖，失败时自动重试并给出可读的排查说明
attempt=1
while [ "$attempt" -le "$RETRY_TIMES" ]; do
  log "$TAG 安装依赖（第 $attempt/$RETRY_TIMES 次）：npm install"
  if npm install && node_modules/.bin/vite --version >/dev/null 2>&1; then
    log "$TAG 依赖安装完成"
    exit 0
  fi
  warn "$TAG 第 $attempt 次安装未成功"
  rm -rf node_modules
  attempt=$((attempt + 1))
  [ "$attempt" -le "$RETRY_TIMES" ] && sleep 3
done

err "$TAG 依赖多次安装失败，请按下面排查后重新执行 make install："
err "$TAG   1. 网络/代理：确认能访问 registry.npmjs.org，必要时设置 HTTP_PROXY / HTTPS_PROXY"
err "$TAG   2. 公司内网：可切换镜像，如 npm config set registry https://registry.npmmirror.com"
err "$TAG   3. 缓存损坏：执行 npm cache clean --force 后重试"
exit 1
