.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help build release test test-verbose test-karabiner clean app doctor keymap mapping simulate colors karabiner check

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

build: ## Debug build
	swift build

release: ## Release build
	swift build -c release

test: ## Run the hardware-free test suite
	swift test

test-verbose: ## Run tests with full output
	swift test --verbose

check: clean build test test-karabiner ## Clean build followed by the full test suite
	@echo "clean build + tests passed"

clean: ## Remove build products
	swift package clean
	rm -rf .build build

app: ## Package AgenticMouse.app into ./build (installs nothing)
	bash ./Scripts/package-app.sh

doctor: build ## Show the resolved configuration, redacted
	swift run agentic-mouse-doctor config

keymap: build ## Print the multi-tap keymap
	swift run agentic-mouse-doctor keymap

mapping: build ## Print the normal / VS Code iCUE assignments this helper assumes
	swift run agentic-mouse-doctor mapping

simulate: build ## Drive the whole coordinator against fakes, no hardware needed
	swift run agentic-mouse-doctor simulate

colors: build ## Show how Hue readings convert to mouse colours
	swift run agentic-mouse-doctor colors

karabiner: ## Generate Karabiner complex-modification artifacts from named sources
	python3 Scripts/generate-karabiner.py

test-karabiner: ## Validate the Karabiner generator, generated files, and Karabiner syntax
	python3 Scripts/generate-karabiner.py --check
	python3 -m unittest discover -s Tests/KarabinerGeneratorTests -p 'test_*.py'
	@if command -v karabiner_cli >/dev/null 2>&1; then \
		karabiner_cli --lint-complex-modifications Karabiner/generated/agentic-mouse.json; \
	else \
		echo "karabiner_cli not found; skipped installed-CLI syntax validation"; \
	fi
