LUA ?= lua
UNAME_S := $(shell uname -s 2>/dev/null)

ifeq ($(OS),Windows_NT)
  IS_WINDOWS := 1
  PREFIX ?= $(LOCALAPPDATA)\riema
  BINDIR ?= $(PREFIX)\bin
  LIBDIR ?= $(PREFIX)\lib\riema
  DOCDIR ?= $(PREFIX)\share\doc\riema
else
  IS_WINDOWS := 0
  PREFIX ?= /usr/local
  BINDIR ?= $(PREFIX)/bin
  LIBDIR ?= $(PREFIX)/lib/riema
  DOCDIR ?= $(PREFIX)/share/doc/riema
endif

.PHONY: help test install uninstall install-user uninstall-user

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  make test' \
	  '  make install [PREFIX=...] [LUA=lua]' \
	  '  make uninstall [PREFIX=...]' \
	  '  make install-user' \
	  '  make uninstall-user'

test:
	$(LUA) test/test_cli.lua

install-user:
ifeq ($(IS_WINDOWS),1)
	$(MAKE) install PREFIX="$(LOCALAPPDATA)\riema" LUA="$(LUA)"
else
	$(MAKE) install PREFIX="$(HOME)/.local" LUA="$(LUA)"
endif

uninstall-user:
ifeq ($(IS_WINDOWS),1)
	$(MAKE) uninstall PREFIX="$(LOCALAPPDATA)\riema"
else
	$(MAKE) uninstall PREFIX="$(HOME)/.local"
endif

install:
ifeq ($(IS_WINDOWS),1)
	@powershell -NoProfile -Command "$$ErrorActionPreference = 'Stop';" \
	  "$$bindir = '$(BINDIR)'; $$libdir = '$(LIBDIR)'; $$docdir = '$(DOCDIR)';" \
	  "[System.IO.Directory]::CreateDirectory($$bindir) | Out-Null;" \
	  "[System.IO.Directory]::CreateDirectory($$libdir) | Out-Null;" \
	  "[System.IO.Directory]::CreateDirectory($$docdir) | Out-Null;" \
	  "Copy-Item -Recurse -Force 'lua' $$libdir;" \
	  "Copy-Item -Force 'riema' $$libdir;" \
	  "Copy-Item -Force 'README.md' $$docdir;" \
	  "Copy-Item -Force 'LICENSE' $$docdir;" \
	  "Copy-Item -Force 'NOTICE' $$docdir;" \
	  "$$wrapper = @('@echo off', 'set \"RIEMA_ROOT=$(LIBDIR)\"', 'if \"%LUA%\"==\"\" (set \"RIEMA_LUA=$(LUA)\") else (set \"RIEMA_LUA=%LUA%\")', '\"%RIEMA_LUA%\" \"%RIEMA_ROOT%\\riema\" %*');" \
	  "Set-Content -Path ($$bindir + '\riema.cmd') -Value $$wrapper -Encoding ASCII;"
else
	@mkdir -p "$(BINDIR)" "$(LIBDIR)" "$(DOCDIR)"
	@rm -rf "$(LIBDIR)/lua"
	@cp -R lua "$(LIBDIR)/lua"
	@cp riema "$(LIBDIR)/riema"
	@chmod +x "$(LIBDIR)/riema"
	@cp README.md LICENSE NOTICE "$(DOCDIR)/"
	@printf '%s\n' '#!/usr/bin/env sh' 'export RIEMA_ROOT="$(LIBDIR)"' 'exec "$(LUA)" "$$RIEMA_ROOT/riema" "$$@"' > "$(BINDIR)/riema"
	@chmod +x "$(BINDIR)/riema"
endif

uninstall:
ifeq ($(IS_WINDOWS),1)
	@powershell -NoProfile -Command "$$ErrorActionPreference = 'Stop';" \
	  "if (Test-Path '$(BINDIR)\riema.cmd') { Remove-Item -Force '$(BINDIR)\riema.cmd' };" \
	  "if (Test-Path '$(LIBDIR)') { Remove-Item -Recurse -Force '$(LIBDIR)' };" \
	  "if (Test-Path '$(DOCDIR)') { Remove-Item -Recurse -Force '$(DOCDIR)' };"
else
	@rm -f "$(BINDIR)/riema"
	@rm -rf "$(LIBDIR)" "$(DOCDIR)"
endif
