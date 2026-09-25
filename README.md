# 轨道交通信号设备检修平台

面向轨道交通信号机、转辙机、轨道电路、联锁设备的检修计划、故障处置与验收的一体化检修管理后台。

这是一个前后端分离的管理平台：前端 Vue 3 + Vite + TypeScript，后端 FastAPI（Python）。

## 环境要求

| 依赖 | 版本 | 说明 |
| --- | --- | --- |
| Python | 3.10+（推荐 3.11/3.12） | 后端运行时；不需要系统级 pip，安装脚本会在 venv 里自动引导 |
| Node.js | 18+（推荐 20） | 前端运行时，自带 npm |
| make | 任意版本 | 可选，只是把 `scripts/` 下的脚本包一层；不用 make 也能直接跑脚本 |

> 从其他系统/架构拷来的 `backend/.venv`、`frontend/node_modules` 会被自动识别并重建
> （典型症状：`.venv` 里的符号链接指向不存在的路径、`@rollup/rollup-linux-*` 缺失）。

## 快速开始（一条命令）

```bash
make dev          # 等价于 ./scripts/dev.sh
```

这一条命令会按顺序完成：

1. 检查 `python3 / node / npm` 是否齐全；
2. 依赖没装就装：后端进 `backend/.venv`（venv 没 pip 会自动从 bootstrap.pypa.io 引导），
   前端 `npm install`；装不上会打印可读的排查说明并允许选择 **r 重试 / q 退出**；
3. 检查端口占用：后端默认 `8000`、前端默认 `5173`，被占用就自动落到下一个可用端口，
   并把最终地址打印在终端横幅里；前端 `/api` 代理自动指向实际后端端口；
4. 起前后端并自检：健康检查、前端代理、**18 个模块列表 total 与概览卡片数字一致性**；
5. 自检通过后常驻，`Ctrl+C` 同时停掉前后端（含 npm/vite 孙进程）。

只想装依赖、不起服务：

```bash
make install      # 等价于 ./scripts/install.sh
```

服务已经在跑，只想做一次自检：

```bash
make check        # 等价于 ./scripts/check.sh
```

自定义首选端口：

```bash
BACKEND_PORT=9000 FRONTEND_PORT=6001 make dev
```

## 端口与地址

| 服务 | 默认端口 | 被占用时 |
| --- | --- | --- |
| 后端 FastAPI | `127.0.0.1:8000` | 自动找 `8001`、`8002`… 并打印实际端口 |
| 前端 Vite | `127.0.0.1:5173` | 自动找 `5174`、`5175`… 并打印实际端口 |

- 后端真实地址也会写入 `.local/backend.url`，`make check` 优先读它，所以换端口后自检照常。
- 前端只通过 Vite 的 `/api` 代理访问后端，代理目标由启动脚本用 `VITE_PROXY_TARGET` 注入，
  不需要手动改代码。
- 相关环境变量见 [.env.example](.env.example)：`APP_PORT`、`APP_DATA_PATH`、
  `FRONTEND_PORT`、`VITE_PROXY_TARGET` 等。

## 示例数据

- 示例数据共 **18 个模块 × 3 行**，后端首次启动时写入 `backend/.local/data.json`
  （该目录已被 `.gitignore` 忽略）。
- 之后每次启动都加载同一份文件：**重复起服务不会重复塞入示例数据**；
  在页面上做的状态流转、新登记记录也会落盘，重启后仍在。
- 运营概览卡片（业务模块 / 今日新增 / 待处理 / 异常量）与各模块列表、导出接口同源，
  `make dev` 与 `make check` 都会校验三方数字一致。
- 想恢复出厂示例数据：

  ```bash
  make reset-data
  # 或服务在跑时：curl -X POST http://127.0.0.1:8000/api/admin/reset-seed
  ```

## 单独启动 / 构建

```bash
make backend      # 仅后端：cd backend && ./run.sh（自动选可用端口）
make frontend     # 仅前端：npm run dev（需后端已启动）
make build        # 前端产物输出到 frontend/dist
```

- 构建产物（`frontend/dist`）与本地运行数据（`backend/.local/data.json`、`.local/logs`）
  分目录存放，互不干扰；构建不会清空运行数据，运行也不会影响产物。
- 各服务日志在 `.local/logs/`（`backend.log`、`frontend.log`、`pip.log`、`npm.log`）。

## Docker（另一套入口，数据与端口约定保持一致）

```bash
docker compose up --build
```

- 后端示例数据放在命名卷里，容器重启同样不会重复灌入；
- 前端容器的 `VITE_PROXY_TARGET` 已指向 compose 网络里的 `backend:8000`；
- 端口可在 `docker-compose.yml` 调整。

## 目录结构

```text
.
├── scripts/                  本地一条链：install / dev / check
├── frontend/                 Vue 3 + Vite + TypeScript 前端
│   ├── src/views/            每个业务模块一个页面
│   ├── src/api/              统一请求封装
│   ├── src/stores/           会话与筛选状态
│   └── vite.config.ts        dev server 端口与 /api 代理（支持环境变量覆盖）
├── backend/                  FastAPI（Python） 后端
│   ├── app/routers/          每个业务模块一组接口
│   ├── app/services/         业务规则与状态流转
│   ├── app/store.py          本地数据仓库（首次落盘示例数据，之后只读写文件）
│   ├── app/stats.py          各模块统计卡片口径（与列表、概览同源）
│   ├── app/seed.py           示例数据（SEED_VERSION 记录版本）
│   ├── run.py                端口探测 + uvicorn 启动入口
│   └── run.sh                venv 检查后转 run.py
├── Makefile                  install / dev / check / build / reset-data
├── .env.example              端口与数据文件等环境变量样例
└── docker-compose.yml
```

## 业务模块

| 模块 | 目录 | 业务对象 | 主要字段 |
| --- | --- | --- | --- |
| 线路区段 | `section` | 线路区段 | 区段编码、区段名称、所属线路 |
| 信号机 | `signal` | 信号机 | 设备编号、设备类型、安装位置 |
| 转辙机 | `switch` | 转辙机 | 设备编号、设备型号、安装道岔 |
| 轨道电路 | `track` | 轨道电路 | 设备编号、制式类型、区段长度 |
| 联锁设备 | `interlock` | 联锁设备 | 设备编号、联锁类型、控制范围 |
| 列车防护 | `atp` | 防护设备 | 设备编号、防护等级、覆盖区段 |
| 检修计划 | `plan` | 检修计划 | 计划编号、检修类型、检修对象 |
| 检修任务 | `task` | 检修任务 | 任务编号、关联计划、检修人员 |
| 故障登记 | `fault` | 设备故障 | 故障编号、发生设备、故障现象 |
| 故障处置 | `dispose` | 处置单 | 处置单号、关联故障、处置措施 |
| 器材领用 | `spare` | 器材领用单 | 领用单号、器材名称、器材规格 |
| 电气测试 | `measure` | 测试单 | 测试单号、测试项目、测试设备 |
| 巡视检查 | `patrol` | 巡视单 | 巡视单号、巡视路线、巡视人员 |
| 天窗作业 | `window` | 天窗计划 | 天窗编号、作业类型、作业区段 |
| 监测报警 | `alarm` | 报警事件 | 报警编号、报警类型、报警等级 |
| 验收确认 | `verify` | 验收单 | 验收单号、关联任务、验收项目 |
| 值班交接 | `shift` | 交接记录 | 交接编号、值班班组、值班人员 |
| 状态评估 | `assess` | 评估记录 | 评估编号、评估对象、评估周期 |

## 约定

- 每个模块的前端页面在 `frontend/src/views/<模块>/index.vue`，后端接口在
  `backend/app/routers/<模块>.py`，业务规则在 `backend/app/services/<模块>.py`。
- 列表接口统一返回 `{ items, total, page, size, stats }`
  （`stats` 为模块顶部三张卡片的数字，新增字段不影响老消费方），
  动作接口统一返回 `{ ok, message }`，导出接口为 `/api/<模块>/export`。
- 状态流转只允许在 `app/services` 里改，路由层不做业务判断。
