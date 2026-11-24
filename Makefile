# AniOS — Makefile
#
# Mục tiêu: một lệnh cho mọi kiểm tra, để người đóng góp không phải nhớ
# đường dẫn script và để CI gọi đúng những gì máy đã xanh.
#
#   make check     — quality gate đầy đủ (shellcheck + ruff + pytest + selftest)
#   make lint      — chỉ lint (shellcheck + ruff), không chạy test
#   make test      — chỉ pytest của hai app
#   make selftest  — toàn bộ bài tự kiểm tra dạng shell
#   make profile   — kiểm tra đặc tả profile + bộ cài đặt
#   make iso       — dựng ISO (cần Arch Linux + archiso + root)
#   make clean     — dọn file tạm do test sinh ra
#   make help      — liệt kê mục tiêu
#
# Mọi mục tiêu chạy được KHÔNG cần root, trừ `make iso`.
# Xem docs/CONTRIBUTING.md để biết quy trình đóng góp đầy đủ.

SHELL := /usr/bin/env bash
# Phải có `-c` ở cuối: make tự thêm nó khi dùng .SHELLFLAGS mặc định, còn khi
# ta ghi đè thì ta phải chỉ định đầy đủ.
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

ROOT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SCRIPTS_DIR := $(ROOT_DIR)/scripts
APPS_DIR := $(ROOT_DIR)/apps

# Thư mục ảo Python: ưu tiên .venv-dev trong repo, sau đó môi trường ảo đang
# bật, rồi python3 của hệ thống. Đặt PYTHON để ghi đè khi cần.
VENV_DIR := $(ROOT_DIR)/.venv-dev
PYTHON ?= $(if $(wildcard $(VENV_DIR)/bin/python),$(VENV_DIR)/bin/python,python3)
RUFF ?= $(if $(wildcard $(VENV_DIR)/bin/ruff),$(VENV_DIR)/bin/ruff,ruff)
SHELLCHECK ?= $(if $(wildcard $(VENV_DIR)/bin/shellcheck),$(VENV_DIR)/bin/shellcheck,shellcheck)

# LUA: bài kiểm tra Hyprland cần trình dịch Lua. Trên CI biến LUA=lua5.4.
LUA ?= lua

# Tập script shell của repo. `profile/installer/scripts` cũng vào đây: đó là
# các helper chạy trong chroot lúc cài đặt, và chúng cũng phải sạch.
SHELL_TARGETS := $(wildcard $(SCRIPTS_DIR)/*.sh) $(wildcard $(ROOT_DIR)/profile/installer/scripts/*)

SELFTESTS := $(wildcard $(SCRIPTS_DIR)/selftest-*.sh)

# Biến môi trường cho pytest: ngoài màn hình ảo, không tạo cửa sổ thật.
PYTEST_ENV := QT_QPA_PLATFORM=offscreen

.PHONY: help check lint test selftest profile shellcheck ruff pytest hyprland \
        iso iso-anios iso-aniterals iso-anix clean

help:
	@echo "AniOS — các mục tiêu Make:"
	@echo "  make check      quality gate đầy đủ (shellcheck + ruff + pytest + selftest)"
	@echo "  make lint       chỉ lint (shellcheck + ruff)"
	@echo "  make test       pytest cho apps/anios-manga và apps/anios-reddit"
	@echo "  make selftest   toàn bộ bài tự kiểm tra dạng shell"
	@echo "  make profile    kiểm tra đặc tả profile + bộ cài đặt"
	@echo "  make iso        dựng ISO (EDITION=anios|aniterals|anix|all)"
	@echo "  make clean      dọn file tạm"
	@echo ""
	@echo "Biến: EDITION=anios PYTHON=/path/to/python RUFF=/path/to/ruff"

# --- Quality gate -----------------------------------------------------------
# Đây là lệnh duy nhất cần chạy trước khi mở pull request.
check: lint test selftest profile
	@echo ""
	@echo "OK — toàn bộ quality gate của AniOS đã xanh."

lint: shellcheck ruff

shellcheck:
	@echo ">> ShellCheck ($(SHELLCHECK))"
	$(SHELLCHECK) -x -S error $(SHELL_TARGETS)

ruff:
	@echo ">> Ruff ($(RUFF))"
	$(RUFF) check apps/

test: pytest

pytest:
	@echo ">> Pytest ($(PYTHON))"
	@# Hai app có CÙNG tên file test (test_models.py, test_settings.py...), nên
	@# pytest gộp một lần sẽ báo "import file mismatch". Mỗi app phải chạy
	@# riêng để lấy đúng config của chính nó (pyproject.toml riêng).
	@failed=0; \
	for app in anios-manga anios-reddit; do \
	  if $(PYTHON) -m pytest "$(APPS_DIR)/$$app/tests" -q; then \
	    echo "  OK    $$app"; \
	  else \
	    echo "  FAIL  $$app" >&2; \
	    failed=$$((failed + 1)); \
	  fi; \
	done; \
	test "$$failed" -eq 0

selftest:
	@echo ">> Selftest dạng shell"
	@failed=0; \
	for script in $(SELFTESTS); do \
	  if bash "$$script" >/dev/null 2>&1; then \
	    echo "  OK    $$(basename "$$script")"; \
	  else \
	    echo "  FAIL  $$(basename "$$script")" >&2; \
	    failed=$$((failed + 1)); \
	  fi; \
	done; \
	test "$$failed" -eq 0

profile:
	@echo ">> Đặc tả profile + bộ cài đặt"
	LUA=$(LUA) $(SCRIPTS_DIR)/check-profile.sh

# --- Dựng ISO ---------------------------------------------------------------
# Cần Arch Linux + archiso + quyền root; xem profile/editions/README.md.
EDITION ?= anios
iso:
	@echo ">> Dựng ISO edition '$(EDITION)' (cần root + archiso)"
	$(SCRIPTS_DIR)/build-iso.sh --edition $(EDITION)

iso-anios:
	$(MAKE) iso EDITION=anios

iso-aniterals:
	$(MAKE) iso EDITION=aniterals

iso-anix:
	$(MAKE) iso EDITION=anix

clean:
	@echo ">> Dọn file tạm"
	rm -rf -- $(ROOT_DIR)/.pytest_cache $(ROOT_DIR)/.ruff_cache
	find $(APPS_DIR) -type d -name __pycache__ -prune -exec rm -rf -- {} + 2>/dev/null || true
	find $(APPS_DIR) -type d -name .pytest_cache -prune -exec rm -rf -- {} + 2>/dev/null || true
	rm -rf -- $(ROOT_DIR)/out
