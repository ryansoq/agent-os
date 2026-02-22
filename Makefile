.PHONY: build run web clean help

help: ## 顯示幫助
	@echo "🤖 Agent OS Builder"
	@echo "===================="
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## 編譯 Agent OS（首次約 30-60 分鐘）
	@bash scripts/build.sh

build-fast: ## 快速編譯（-j8）
	@bash scripts/build.sh 8

run: ## QEMU 開機
	@bash scripts/run-qemu.sh

web: ## 啟動 Web UI (localhost:3001)
	@node server.js

install-deps: ## 安裝依賴
	@echo "[*] 安裝系統依賴..."
	sudo apt-get install -y build-essential gcc g++ make patch \
		libncurses-dev unzip bc cpio rsync wget python3 \
		qemu-system-x86 libelf-dev
	@echo "[*] 安裝 Node.js 依賴..."
	npm install

clean: ## 清除編譯產出
	rm -rf images/bzImage images/rootfs.ext2 images/rootfs.cpio.gz
	@echo "✅ 已清除 images/"
