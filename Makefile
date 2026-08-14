.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help build release test test-extension test-karabiner test-packaging test-verbose clean app doctor keymap mapping simulate karabiner check

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

build: ## Debug build
	swift build

release: ## Release build
	swift build -c release

test: ## Run the hardware-free test suite
	swift test

test-extension: ## Test the fail-closed Musixmatch Chrome extension
	node --test extensions/musixmatch-playback/tests/*.test.mjs

test-packaging: ## Test monotonic marketing/build versions for signed candidates
	bash Tests/PackagingTests/test-app-version.sh

karabiner: ## Generate the Karabiner adapter and action catalog
	python3 Scripts/generate-karabiner.py

test-karabiner: ## Validate semantic action sources and generated Karabiner JSON
	python3 Scripts/generate-karabiner.py --check
	python3 -m unittest discover -s Tests/KarabinerGeneratorTests -p 'test_*.py'
	@if [ -x "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli" ]; then \
		"/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli" \
			--lint-complex-modifications Karabiner/generated/agentic-mouse.json; \
		"/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli" \
			--lint-complex-modifications Karabiner/generated/agentic-mouse-runtime.json; \
	else \
		echo "Karabiner CLI not installed; structural generator tests passed"; \
	fi

test-verbose: ## Run tests with full output
	swift test --verbose

check: clean build test test-extension test-karabiner test-packaging ## Clean build followed by the full test suite
	bash -n Scripts/package-app.sh
	bash -n Scripts/update-app-version.sh
	@echo "clean build + tests passed"

clean: ## Remove build products
	swift package clean
	rm -rf .build build

app: ## Package AgenticMouse.app into ./build (installs nothing)
	bash ./Scripts/package-app.sh

install-candidate: ## Package a stable Developer-ID app for guarded installation
	INSTALL_CANDIDATE=1 CODE_SIGN_IDENTITY="Developer ID Application: Ethan Sarif-Kattan (T34G959ZG8)" bash ./Scripts/package-app.sh

doctor: build ## Show the resolved configuration, redacted
	swift run agentic-mouse-doctor config

keymap: build ## Print the multi-tap keymap
	swift run agentic-mouse-doctor keymap

mapping: build ## Print the normal / VS Code iCUE assignments this helper assumes
	swift run agentic-mouse-doctor mapping

simulate: build ## Drive the whole coordinator against fakes, no hardware needed
	swift run agentic-mouse-doctor simulate
