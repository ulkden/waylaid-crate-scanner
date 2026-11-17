# Developer tasks. Requires: luacheck, stylua, luajit (macOS: brew install luacheck stylua luajit).

ADDON := WaylaidCrateScanner
# Where `make install` copies the addon. Override for other installs, e.g.
#   make install WOW_ADDONS="/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"
WOW_ADDONS ?= /Applications/World of Warcraft/_forever_/Interface/AddOns
# Cache for Wowhead responses used by `make data`.
DATA_CACHE ?= .cache/wowhead
# Version written into the installed TOC (release builds get the tag from the packager instead).
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

.PHONY: help check lint format format-check test data install hooks

help:
	@echo "make check         lint + format check + tests (what CI runs)"
	@echo "make lint          luacheck"
	@echo "make format        reformat Lua with StyLua"
	@echo "make format-check  verify formatting without changing files"
	@echo "make test          offline logic tests (LuaJIT, stubbed WoW API)"
	@echo "make data          regenerate $(ADDON)/Data.lua from Wowhead's WoW: Forever database"
	@echo "make install       copy the addon into WOW_ADDONS ($(WOW_ADDONS))"
	@echo "make hooks         install a git pre-commit hook that runs 'make check'"

check: lint format-check test

lint:
	luacheck .

format:
	stylua .

format-check:
	stylua --check .

test:
	luajit tools/test_harness.lua $(ADDON)

data:
	python3 -I tools/gen.py $(DATA_CACHE) $(ADDON)/Data.lua
	luacheck $(ADDON)/Data.lua

install:
	rm -rf "$(WOW_ADDONS)/$(ADDON)"
	cp -R $(ADDON) "$(WOW_ADDONS)/"
	sed 's/@project-version@/$(VERSION)/' $(ADDON)/$(ADDON).toc > "$(WOW_ADDONS)/$(ADDON)/$(ADDON).toc"
	@echo "Installed to $(WOW_ADDONS)/$(ADDON) — /reload in game."

hooks:
	printf '#!/bin/sh\nexec make check\n' > .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "pre-commit hook installed (bypass once with: git commit --no-verify)"
