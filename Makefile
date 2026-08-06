.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help build release test test-verbose clean app doctor keymap mapping simulate colors check

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

check: clean build test ## Clean build followed by the full test suite
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
