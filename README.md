# 轨道交通信号设备检修平台

面向轨道交通信号机、转辙机、轨道电路、联锁设备的检修计划、故障处置与验收的一体化检修管理后台。

这是一个前后端分离的管理平台：前端 Vue 3 + Vite + TypeScript，后端 FastAPI（Python）。
两边各自独立启动，前端 dev server 已关掉自动打开页面，启动后按终端打印的地址手工打开。

## 一条命令跑起来

```bash
make dev
```

这一条命令会按顺序做完下面的事，任何一步失败都会打印可读的原因：

1. **装依赖**：后端建虚拟环境装 `requirements.txt`，前端 `npm install`。
   依赖版本已锁定（`backend/requirements.txt` 精确版本、`frontend/package-lock.json`），
   不再靠口头约定。装不上时自动重试 3 次，并给出网络/代理/镜像的排查建议；
   修好环境后重新执行 `make install` 即可。
2. **起服务**：先后端（FastAPI）再前端（Vite）。首选端口是后端 8000、前端 5173；
   **端口被占用时自动落到下一个可用端口并打印出来**，前端代理目标跟着实际后端端口走。
3. **自检**：确认两个端口能连通、示例数据已生成、18 个模块的列表总数、
   页头统计卡片与运营概览的数字全部对得上，然后打印访问地址。

启动后访问终端打印的前端地址（默认 `http://127.0.0.1:5173`）。

常用命令：

| 命令 | 作用 |
| --- | --- |
| `make dev` | 一条命令：装依赖 → 起前后端 → 自检 |
| `make install` | 只装/修复依赖（虚拟环境或 node_modules 损坏会自动重建） |
| `make check` | 只对已在运行的服务再做一次自检 |
| `make stop` | 停止 `make dev` 启动的服务（整组进程一起收，不留孤儿） |
| `make build` | 构建产物：`frontend/dist` + 后端语法检查，不影响正在运行的服务 |
| `make clean` | 清理构建产物与运行状态（不动已装的依赖） |
| `make backend` / `make frontend` | 单独起后端 / 前端 |

### 关于示例数据

- 示例数据只有一份来源：`backend/app/seed.py`。所有启动入口
  （`make dev`、`make backend`、`backend/run.sh`、docker-compose、Dockerfile）
  起的都是同一个应用，演示数据天然同步。
- 塞数是**幂等**的：服务反复启动、`make dev` 重复执行，都不会把示例数据塞重；
  已经在跑的服务会被直接复用，而不是再起一个。
- 日期字段按“今天”相对生成，所以无论哪天克隆仓库，
  概览的“今日新增”和各模块的“今日 / 本月”统计都能对上。
- 想核对示例数据清单：`cd backend && python3 -m app.seed`。

### 运行状态与构建产物

- 运行期的 pid、端口、日志都在 `.run/`（已 gitignore），与构建产物 `frontend/dist/` 互不干扰。
- 本地依赖（`.venv/`、`node_modules/`）通过 `.dockerignore` 隔离，不会被复制进镜像。

## 目录结构

```text
.
├── frontend/                 Vue 3 + Vite + TypeScript 前端
│   ├── src/views/            每个业务模块一个页面
│   ├── src/api/              统一请求封装
│   ├── src/stores/           会话与筛选状态
│   └── vite.config.ts        dev server 配置（open: false）
├── backend/                  FastAPI（Python） 后端
│   ├── app/routers/          每个业务模块一组接口
│   ├── app/services/         业务规则与状态流转
│   ├── app/seed.py           示例数据（唯一来源）
│   └── app/store.py          内存数据仓库（幂等塞数）
├── scripts/                  本地运行链路（装依赖、起服务、自检）
├── .run/                     运行期状态（pid、端口、日志，gitignore）
└── docker-compose.yml
```

## 手工启动（不推荐，仅作兜底）

### 后端

```bash
cd backend
./run.sh        # 自动建虚拟环境、装依赖、选可用端口并打印
```

健康检查：`curl http://127.0.0.1:8000/api/health`

### 前端

```bash
cd frontend
npm install
npm run dev     # 默认代理 /api 到 127.0.0.1:8000，可用 VITE_PROXY_TARGET 覆盖
```

前端默认监听 `http://127.0.0.1:5173/`，dev server 不会自动打开浏览器，
需要自己访问。

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
- 列表接口统一返回 `{ items, total, page, size }`，动作接口统一返回 `{ ok, message }`。
- 每个模块另有 `GET /api/<模块>/stats` 返回 `{ module, items: [{label, value}] }`，
  给列表页头的统计卡片用；统计口径声明在 `services/<模块>.py` 的 `STAT_RULES`。
- 状态流转只允许在 `app/services` 里改，路由层不做业务判断。
