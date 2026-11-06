# GYM Paper · iOS
# Requires Xcode 26+ and XcodeGen (brew install xcodegen).

.PHONY: help bootstrap project open test clean

help: ## Show available commands
	@grep -E '^[a-z]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  make %-10s %s\n", $$1, $$2}'

bootstrap: ## Install XcodeGen and create local signing config
	@command -v xcodegen >/dev/null || brew install xcodegen
	@test -f Config/Signing.local.xcconfig || cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
	@echo "→ Set DEVELOPMENT_TEAM in Config/Signing.local.xcconfig, then run: make open"

project: ## Generate Balli.xcodeproj from project.yml
	xcodegen generate

open: project ## Generate and open the project in Xcode
	open Balli.xcodeproj

test: ## Run BalliKit unit tests
	swift test --package-path BalliKit

clean: ## Remove generated project and build products
	rm -rf Balli.xcodeproj BalliKit/.build DerivedData
