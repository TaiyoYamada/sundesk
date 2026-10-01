# よく使う操作をまとめたもの。`make` だけで一覧が出る。

PACKAGE := Packages/SundeskKit
ENGINE := engine
LOG := tools/sundesk-log
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
	@command -v uv >/dev/null || brew install uv
	@command -v actionlint >/dev/null || brew install actionlint
	swift package --package-path $(PACKAGE) resolve
	cd $(ENGINE) && uv sync
	cd $(LOG) && uv sync

# MARK: - 静的チェック

.PHONY: lint lint-swift lint-python lint-log lint-actions
lint: lint-swift lint-python lint-log lint-actions ## Swift、Python、GitHub Actions の静的チェック

lint-swift: ## SwiftLint と swift-format で検査する
	swiftlint lint --strict --quiet
	swift format lint --strict --recursive --parallel $(SWIFT_SOURCES)

lint-python: ## ruff と pyright で検査する
	cd $(ENGINE) && uv run ruff check . && uv run ruff format --check . && uv run pyright

lint-log: ## 記録用ライブラリ（tools/sundesk-log）を ruff と pyright で検査する
	cd $(LOG) && uv run ruff check . && uv run ruff format --check . && uv run pyright

lint-actions: ## GitHub Actions のワークフローを actionlint で検査する
	actionlint

.PHONY: format
format: ## Swift と Python のコードを自動で整形する
	swift format format --in-place --recursive --parallel $(SWIFT_SOURCES)
	cd $(ENGINE) && uv run ruff check --fix . && uv run ruff format .
	cd $(LOG) && uv run ruff check --fix . && uv run ruff format .

# MARK: - テスト

.PHONY: test test-package test-integration test-models test-app test-ui test-python test-log coverage
test: test-package test-app test-python test-log ## UI テスト以外のすべてのテスト

test-package: ## Swift パッケージのテスト
	swift test --package-path $(PACKAGE) --enable-code-coverage

test-integration: ## 本物の Python エンジンを起動する結合テスト
	SUNDESK_INTEGRATION=1 swift test --package-path $(PACKAGE) --filter EngineProcessTests

test-models: ## 本物のモデルで、知識、チャット、実験室、工房を端から端まで確かめる（約 1GB をダウンロードする）
	SUNDESK_MODELS=1 swift test --package-path $(PACKAGE) --filter EngineEndToEndTests

test-app: ## アプリのユニットテスト
	$(XCODEBUILD) test -only-testing:sundeskTests

test-ui: ## アプリの UI テスト（画面を実際に操作する）
	$(XCODEBUILD) test -only-testing:sundeskUITests

test-python: ## Python エンジンのテスト
	cd $(ENGINE) && uv run pytest --cov

test-log: ## 記録用ライブラリ（tools/sundesk-log）のテスト
	cd $(LOG) && uv run pytest --cov

coverage: test-package ## Swift パッケージのカバレッジをモジュールごとに出す
	scripts/swift-coverage.sh $(PACKAGE)

# MARK: - ビルドと実行

.PHONY: build run install engine clean
build: ## アプリをビルドする
	$(XCODEBUILD) build

run: build ## アプリをビルドして起動する
	open $(DERIVED_DATA)/Build/Products/Debug/sundesk.app

APP_ID := com.taiyou.sundesk
INSTALL_DIR ?= /Applications

install: ## 普段使いの設定（Release）でビルドし、アプリケーションフォルダに入れ直して起動する
	$(XCODEBUILD) -configuration Release build
	@# 動いていれば終了してもらい、終わるまで待つ（編集中のノートは終了するときに保存される）
	@osascript -e 'if application id "$(APP_ID)" is running then tell application id "$(APP_ID)" to quit'
	@for i in $$(seq 1 50); do pgrep -xq sundesk || break; sleep 0.2; done
	@if pgrep -xq sundesk; then echo "sundesk が終了しませんでした。終了してから、もう一度実行してください"; exit 1; fi
	rm -rf $(INSTALL_DIR)/sundesk.app
	ditto $(DERIVED_DATA)/Build/Products/Release/sundesk.app $(INSTALL_DIR)/sundesk.app
	open $(INSTALL_DIR)/sundesk.app

engine: ## Python エンジンだけを単独で起動する（http://127.0.0.1:8765）
	cd $(ENGINE) && uv run sundesk-engine --log-level debug

clean: ## ビルドの成果物を消す
	rm -rf build $(PACKAGE)/.build
