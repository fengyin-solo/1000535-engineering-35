.PHONY: help install dev check reset-data backend frontend build clean

help: ## 列出常用命令
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

install: ## 一条命令装好前后端依赖（装不上会说明原因并允许重试）
	./scripts/install.sh

dev: ## 装依赖（缺失时）+ 起前后端 + 端口与示例数据自检
	./scripts/dev.sh

check: ## 只做自检：前后端端口、健康检查、列表与概览数字一致性
	./scripts/check.sh

reset-data: ## 把本地运行数据恢复成示例数据（不影响构建产物）
	cd backend && .venv/bin/python -c "from app.store import store; store.reset_to_seed(); print('示例数据已重置:', store.data_path)"

backend: ## 仅启动后端（自动选可用端口）
	cd backend && ./run.sh

frontend: ## 仅启动前端（需要后端已启动，自动选可用端口）
	cd frontend && npm run dev

build: ## 构建前端产物到 frontend/dist，与本地运行数据互不干扰
	cd frontend && npm run build

clean: ## 删除依赖目录与本地运行数据（构建产物需另行在 frontend 下清理）
	rm -rf backend/.venv backend/.local .local frontend/node_modules
