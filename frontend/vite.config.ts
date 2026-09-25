import { fileURLToPath, URL } from 'node:url'
import { defineConfig, type PluginOption } from 'vite'
import vue from '@vitejs/plugin-vue'

// 后端地址与前端端口都可以用环境变量覆盖：
// scripts/dev.sh 在发现默认端口被占用、后端落到新端口后，会把真实地址
// 通过 VITE_PROXY_TARGET / VITE_PORT 传进来，前端无需改代码。
const proxyTarget = process.env.VITE_PROXY_TARGET ?? 'http://127.0.0.1:8000'
const preferredPort = Number(process.env.VITE_PORT ?? 5173)

// 以固定格式打印最终监听地址与代理目标，供 scripts/dev.sh 解析与自检
function printUrls(): PluginOption {
  return {
    name: 'print-listening-url',
    apply: 'serve',
    configureServer(server) {
      server.httpServer?.once('listening', () => {
        const address = server.httpServer?.address()
        if (address && typeof address === 'object') {
          const port = address.port
          // eslint-disable-next-line no-console
          console.log(`[frontend] listening on http://127.0.0.1:${port}`)
          // eslint-disable-next-line no-console
          console.log(`[frontend] proxy /api -> ${proxyTarget}`)
        }
      })
    },
  }
}

export default defineConfig({
  plugins: [vue(), printUrls()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: {
    host: '127.0.0.1',
    port: preferredPort,
    // 关掉自动打开页面：起服务时只打印地址，不拉起浏览器
    open: false,
    // 默认端口被占用时自动落到下一个可用端口，由脚本与日志统一告知
    strictPort: false,
    proxy: {
      '/api': {
        target: proxyTarget,
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: false,
  },
})
