.PHONY: install dev backend frontend stop check build clean

install: ## 安装前后端依赖（损坏会自动修复，可重复执行）
	@bash scripts/ensure-backend-deps.sh
	@bash scripts/ensure-frontend-deps.sh

dev: ## 一条命令：装依赖 → 起前后端 → 自检端口与示例数据
	@bash scripts/dev.sh

backend: ## 只起后端（自动选可用端口并打印）
	@cd backend && ./run.sh

frontend: ## 只起前端（默认代理到 127.0.0.1:8000，可用 VITE_PROXY_TARGET 覆盖）
	@cd frontend && npm run dev

stop: ## 停止 make dev 启动的服务
	@bash scripts/stop.sh

check: ## 对已在运行的服务做自检（端口、示例数据、概览数字）
	@bash scripts/check.sh

build: ## 构建产物：frontend/dist + 后端语法检查，不影响本地运行
	@bash scripts/ensure-backend-deps.sh >/dev/null
	@bash scripts/ensure-frontend-deps.sh >/dev/null
	cd frontend && npm run build
	cd backend && .venv/bin/python -m compileall -q app && echo "后端语法检查通过"
	@echo "构建产物在 frontend/dist/，与本地运行（.run/）互不干扰"

clean: ## 清理构建产物与运行状态（不动已装的依赖）
	rm -rf frontend/dist .run
