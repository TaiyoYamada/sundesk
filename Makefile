# よく使う操作をまとめたもの。`make` だけで一覧が出る。

PACKAGE := Packages/SundeskKit
SWIFT_SOURCES := sundesk sundeskTests sundeskUITests $(PACKAGE)/Sources $(PACKAGE)/Tests $(PACKAGE)/Package.swift
DERIVED_DATA := build/DerivedData

# CI では署名なし（ad-hoc 署名）でビルドするために上書きする
XCODEBUILD_FLAGS ?=
XCODEBUILD := xcodebuild -project sundesk.xcodeproj -scheme sundesk -destination 'platform=macOS' \
	-derivedDataPath $(DERIVED_DATA) $(XCODEBUILD_FLAGS)

.DEFAULT_GOAL := help

.PHONY: help
help: ## この一覧を出す
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# MARK: - 準備

.PHONY: bootstrap
bootstrap: ## 開発に必要な道具と依存関係をそろえる
	@command -v swiftlint >/dev/null || brew install swiftlint
	@command -v actionlint >/dev/null || brew install actionlint
	swift package --package-path $(PACKAGE) resolve

# MARK: - 静的チェック

.PHONY: lint lint-swift lint-actions
lint: lint-swift lint-actions ## Swift と GitHub Actions の静的チェック

lint-swift: ## SwiftLint と swift-format で検査する
	swiftlint lint --strict --quiet
	swift format lint --strict --recursive --parallel $(SWIFT_SOURCES)

lint-actions: ## GitHub Actions のワークフローを actionlint で検査する
	actionlint

.PHONY: format
format: ## Swift のコードを自動で整形する
	swift format format --in-place --recursive --parallel $(SWIFT_SOURCES)

# MARK: - テスト

.PHONY: test test-package test-app test-ui coverage
test: test-package test-app ## UI テスト以外のすべてのテスト

test-package: ## Swift パッケージのテスト
	swift test --package-path $(PACKAGE) --enable-code-coverage

test-app: ## アプリのユニットテスト
	$(XCODEBUILD) test -only-testing:sundeskTests

test-ui: ## アプリの UI テスト（画面を実際に操作する）
	$(XCODEBUILD) test -only-testing:sundeskUITests

coverage: test-package ## Swift パッケージのカバレッジをモジュールごとに出す
	scripts/swift-coverage.sh $(PACKAGE)

# MARK: - ビルドと実行

.PHONY: build run install install-cli clean
build: ## アプリをビルドする
	$(XCODEBUILD) build

run: build ## アプリをビルドして起動する
	open $(DERIVED_DATA)/Build/Products/Debug/sundesk.app

APP_ID := com.taiyou.sundesk
INSTALL_DIR ?= /Applications
CLI_DIR ?= $(HOME)/.local/bin

install: install-cli ## 普段使いの設定（Release）でビルドし、アプリケーションフォルダに入れ直して起動する。CLI も入れる
	$(XCODEBUILD) -configuration Release build
	@# 動いていれば終了してもらい、終わるまで待つ
	@osascript -e 'if application id "$(APP_ID)" is running then tell application id "$(APP_ID)" to quit'
	@for i in $$(seq 1 50); do pgrep -xq sundesk || break; sleep 0.2; done
	@if pgrep -xq sundesk; then echo "sundesk が終了しませんでした。終了してから、もう一度実行してください"; exit 1; fi
	rm -rf $(INSTALL_DIR)/sundesk.app
	ditto $(DERIVED_DATA)/Build/Products/Release/sundesk.app $(INSTALL_DIR)/sundesk.app
	open $(INSTALL_DIR)/sundesk.app

install-cli: ## CLI を Release でビルドし、~/.local/bin に sundesk という名前で入れる
	swift build -c release --package-path $(PACKAGE) --product sundesk-cli
	install -d $(CLI_DIR)
	install -m 755 $(PACKAGE)/.build/release/sundesk-cli $(CLI_DIR)/sundesk

clean: ## ビルドの成果物を消す
	rm -rf build $(PACKAGE)/.build
