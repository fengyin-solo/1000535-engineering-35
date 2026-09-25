# 启动链路的公共函数：日志、找空闲端口、等 HTTP 就绪。
# 用法：source "$(dirname "$0")/lib.sh"

log()  { printf '\033[36m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }

# 从指定端口起找第一个空闲端口并打印；100 个内找不到就报错退出。
# 探测时设置 SO_REUSEADDR，与 uvicorn / vite 实际监听时的行为一致，
# 避免服务刚停止、连接还在 TIME_WAIT 时被误判为“端口被占用”。
find_free_port() {
  python3 - "$1" <<'PY'
import socket
import sys

start = int(sys.argv[1])
for port in range(start, start + 100):
    with socket.socket() as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            continue
        print(port)
        break
else:
    sys.exit(f"从 {start} 起连续 100 个端口都被占用，请手工指定端口")
PY
}

# 轮询等待某个 URL 返回 2xx；超时返回非零。
# 用法：wait_http_ok <url> <超时秒数>
wait_http_ok() {
  local url="$1" timeout="${2:-30}" elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    if curl -fsS -o /dev/null --max-time 2 "$url" 2>/dev/null; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}
