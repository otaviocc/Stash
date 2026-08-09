# Stash browser extension: common tasks.
# Run from the Extension/ directory.
#
# The extension has no compile step (plain HTML/CSS/JS); "building" means
# packaging the folder into a store-ready zip. These targets need only the tools
# already used elsewhere in the repo (zip, python3, and optionally node)
# with no npm/bundler, matching the extension's no-build-step philosophy.

# Read the version straight from the manifest so the package name tracks it.
VERSION := $(shell grep '"version"' manifest.json | head -1 | sed -E 's/.*"version" *: *"([^"]+)".*/\1/')
PACKAGE := stash-extension-$(VERSION).zip

.DEFAULT_GOAL := help
.PHONY: help icons lint package clean

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

icons: ## Regenerate the PNG icons from icon.svg (needs Pillow)
	cd icons && python3 generate-icons.py

lint: ## Lint the extension (web-ext if installed, else dependency-free checks)
	@if command -v web-ext >/dev/null 2>&1; then \
		web-ext lint --source-dir .; \
	else \
		echo "web-ext not found, running basic checks (install web-ext for full linting)."; \
		python3 -c "import json; json.load(open('manifest.json')); print('manifest.json: valid JSON')"; \
		if command -v node >/dev/null 2>&1; then \
			for f in background.js popup.js options.js; do node --check $$f && echo "$$f: OK"; done; \
		else \
			echo "node not found, skipping JS syntax check."; \
		fi; \
	fi

package: ## Build the store-ready zip into dist/
	@mkdir -p dist
	@rm -f dist/$(PACKAGE)
	zip -r dist/$(PACKAGE) . \
		-x 'dist/*' 'Makefile' 'icons/generate-icons.py' 'icons/icon.svg' \
		   '*.DS_Store' '*/.*'
	@echo "Wrote dist/$(PACKAGE)"

clean: ## Remove build artifacts (dist/)
	rm -rf dist
