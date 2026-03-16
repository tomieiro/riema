local fs = require("riema.fs")
local platform = require("riema.platform")
local state = require("riema.state")
local artifacts = require("riema.artifacts")

local environment = {}

local function metadata_path(prefix)
  return fs.join(prefix, "metadata", "env.lua")
end

local function luarocks_config_path(prefix)
  return fs.join(prefix, "etc", "luarocks", "config.lua")
end

local function created_at()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function normalize_version(value, fallback)
  if not value or value == "" then
    return fallback or "latest"
  end

  return value
end

local function contains(list, item)
  for _, value in ipairs(list) do
    if value == item then
      return true
    end
  end

  return false
end

local function quoted_lua_string(value)
  return string.format("%q", value)
end

local function generate_luarocks_config(prefix)
  local bin_dir = fs.join(prefix, "bin")
  local rocks_dir = fs.join(prefix, "rocks")
  local lines = {
    "rocks_trees = {",
    "  {",
    "    name = 'riema',",
    "    root = " .. quoted_lua_string(prefix) .. ",",
    "  },",
    "}",
    "local_by_default = true",
    "variables = {",
    "  LUA_DIR = " .. quoted_lua_string(prefix) .. ",",
    "  LUA_BINDIR = " .. quoted_lua_string(bin_dir) .. ",",
    "  LUA_INCDIR = " .. quoted_lua_string(fs.join(prefix, "include")) .. ",",
    "  LUA_LIBDIR = " .. quoted_lua_string(fs.join(prefix, "lib")) .. ",",
    "}",
    "rocks_dir = " .. quoted_lua_string(rocks_dir),
    "",
  }

  return table.concat(lines, "\n")
end

local function prompt_version(metadata)
  return string.format("%s::%s", metadata.name, metadata.runtime.version)
end

local function generate_posix_activate(metadata)
  local prefix = metadata.prefix
  local config = luarocks_config_path(prefix)
  local prompt = "(" .. prompt_version(metadata) .. ") "
  local lines = {
    "if [ -n \"${RIEMA_ENV_PREFIX:-}\" ] && command -v deactivate-riema >/dev/null 2>&1; then",
    "  deactivate-riema >/dev/null 2>&1 || true",
    "fi",
    "export RIEMA_OLD_PATH=\"${PATH}\"",
    "export RIEMA_OLD_PS1=\"${PS1-}\"",
    "export RIEMA_ENV_NAME=" .. fs.shell_quote(metadata.name),
    "export RIEMA_ENV_PREFIX=" .. fs.shell_quote(prefix),
    "export LUAROCKS_CONFIG=" .. fs.shell_quote(config),
    "export PATH=" .. fs.shell_quote(fs.join(prefix, "bin")) .. ":${PATH}",
    "export PS1=" .. fs.shell_quote(prompt) .. "\"${PS1-}\"",
    "deactivate-riema() {",
    "  if [ -n \"${RIEMA_OLD_PATH:-}\" ]; then",
    "    PATH=\"$RIEMA_OLD_PATH\"",
    "    export PATH",
    "  fi",
    "  if [ \"${RIEMA_OLD_PS1+x}\" = x ]; then",
    "    PS1=\"$RIEMA_OLD_PS1\"",
    "    export PS1",
    "  fi",
    "  unset RIEMA_OLD_PATH RIEMA_OLD_PS1 RIEMA_ENV_NAME RIEMA_ENV_PREFIX LUAROCKS_CONFIG",
    "  unset -f deactivate-riema 2>/dev/null || true",
    "}",
    "",
  }

  return table.concat(lines, "\n")
end

local function generate_fish_activate(metadata)
  local prefix = metadata.prefix
  local config = luarocks_config_path(prefix)
  local prompt = "(" .. prompt_version(metadata) .. ")"
  local lines = {
    "if set -q RIEMA_ENV_PREFIX; and functions -q deactivate-riema",
    "  deactivate-riema >/dev/null 2>/dev/null",
    "end",
    "set -gx RIEMA_OLD_PATH $PATH",
    "set -gx RIEMA_ENV_NAME " .. metadata.name,
    "set -gx RIEMA_ENV_PREFIX " .. prefix,
    "set -gx LUAROCKS_CONFIG " .. config,
    "set -gx RIEMA_PROMPT_PREFIX " .. prompt,
    "set -gx PATH " .. fs.join(prefix, "bin") .. " $PATH",
    "if functions -q fish_prompt",
    "  functions -c fish_prompt riema_old_fish_prompt",
    "end",
    "function fish_prompt",
    "  printf '%s ' \"$RIEMA_PROMPT_PREFIX\"",
    "  if functions -q riema_old_fish_prompt",
    "    riema_old_fish_prompt",
    "  end",
    "end",
    "function deactivate-riema",
    "  if set -q RIEMA_OLD_PATH",
    "    set -gx PATH $RIEMA_OLD_PATH",
    "  end",
    "  if functions -q riema_old_fish_prompt",
    "    functions -e fish_prompt",
    "    functions -c riema_old_fish_prompt fish_prompt",
    "    functions -e riema_old_fish_prompt",
    "  end",
    "  set -e RIEMA_OLD_PATH RIEMA_ENV_NAME RIEMA_ENV_PREFIX LUAROCKS_CONFIG RIEMA_PROMPT_PREFIX",
    "  functions -e deactivate-riema",
    "end",
    "",
  }

  return table.concat(lines, "\n")
end

local function generate_csh_activate(metadata)
  local prefix = metadata.prefix
  local config = luarocks_config_path(prefix)
  local prompt = "(" .. prompt_version(metadata) .. ") "
  local lines = {
    "if ( $?RIEMA_ENV_PREFIX ) then",
    "  deactivate-riema >& /dev/null",
    "endif",
    "setenv RIEMA_OLD_PATH \"$PATH\"",
    "setenv RIEMA_OLD_PROMPT \"$prompt\"",
    "setenv RIEMA_ENV_NAME \"" .. metadata.name .. "\"",
    "setenv RIEMA_ENV_PREFIX \"" .. prefix .. "\"",
    "setenv LUAROCKS_CONFIG \"" .. config .. "\"",
    "setenv PATH \"" .. fs.join(prefix, "bin") .. ":" .. "$PATH\"",
    "set prompt = \"" .. prompt .. "$prompt\"",
    "alias deactivate-riema 'if ( $?RIEMA_OLD_PATH ) setenv PATH \"$RIEMA_OLD_PATH\"; if ( $?RIEMA_OLD_PROMPT ) set prompt=\"$RIEMA_OLD_PROMPT\"; unsetenv RIEMA_OLD_PATH RIEMA_OLD_PROMPT RIEMA_ENV_NAME RIEMA_ENV_PREFIX LUAROCKS_CONFIG; unalias deactivate-riema'",
    "",
  }

  return table.concat(lines, "\n")
end

local function generate_batch_activate(metadata)
  local prefix = metadata.prefix
  local config = luarocks_config_path(prefix)
  local prompt = "(" .. prompt_version(metadata) .. ") $P$G"
  local lines = {
    "@echo off",
    "set \"RIEMA_OLD_PATH=%PATH%\"",
    "set \"RIEMA_OLD_PROMPT=%PROMPT%\"",
    "set \"RIEMA_ENV_NAME=" .. metadata.name .. "\"",
    "set \"RIEMA_ENV_PREFIX=" .. prefix .. "\"",
    "set \"LUAROCKS_CONFIG=" .. config .. "\"",
    "set \"PATH=" .. fs.join(prefix, "bin") .. ";%PATH%\"",
    "prompt " .. prompt,
    "",
  }

  return table.concat(lines, "\r\n")
end

local function generate_batch_deactivate()
  local lines = {
    "@echo off",
    "if not \"%RIEMA_OLD_PATH%\"==\"\" set \"PATH=%RIEMA_OLD_PATH%\"",
    "if not \"%RIEMA_OLD_PROMPT%\"==\"\" prompt %RIEMA_OLD_PROMPT%",
    "set RIEMA_OLD_PATH=",
    "set RIEMA_OLD_PROMPT=",
    "set RIEMA_ENV_NAME=",
    "set RIEMA_ENV_PREFIX=",
    "set LUAROCKS_CONFIG=",
    "",
  }

  return table.concat(lines, "\r\n")
end

local function generate_powershell_activate(metadata)
  local prefix = metadata.prefix
  local config = luarocks_config_path(prefix)
  local prompt = "(" .. prompt_version(metadata) .. ") "
  local lines = {
    "$env:RIEMA_OLD_PATH = $env:PATH",
    "$env:RIEMA_ENV_NAME = '" .. metadata.name .. "'",
    "$env:RIEMA_ENV_PREFIX = '" .. prefix .. "'",
    "$env:LUAROCKS_CONFIG = '" .. config .. "'",
    "$env:PATH = '" .. fs.join(prefix, "bin") .. ";' + $env:PATH",
    "$function:riema_old_prompt = $function:prompt",
    "function prompt {",
    "  '" .. prompt .. "' + (& $function:riema_old_prompt)",
    "}",
    "function Exit-RiemaEnv {",
    "  if ($env:RIEMA_OLD_PATH) { $env:PATH = $env:RIEMA_OLD_PATH }",
    "  Remove-Item Env:RIEMA_OLD_PATH -ErrorAction SilentlyContinue",
    "  Remove-Item Env:RIEMA_ENV_NAME -ErrorAction SilentlyContinue",
    "  Remove-Item Env:RIEMA_ENV_PREFIX -ErrorAction SilentlyContinue",
    "  Remove-Item Env:LUAROCKS_CONFIG -ErrorAction SilentlyContinue",
    "  if ($function:riema_old_prompt) { $function:prompt = $function:riema_old_prompt }",
    "  Remove-Item Function:riema_old_prompt -ErrorAction SilentlyContinue",
    "  Remove-Item Function:Exit-RiemaEnv -ErrorAction SilentlyContinue",
    "}",
    "",
  }

  return table.concat(lines, "\n")
end

local function write_activation_scripts(metadata)
  local bin_dir = fs.join(metadata.prefix, "bin")
  local scripts = {
    [fs.join(bin_dir, "activate")] = generate_posix_activate(metadata),
    [fs.join(bin_dir, "activate.fish")] = generate_fish_activate(metadata),
    [fs.join(bin_dir, "activate.csh")] = generate_csh_activate(metadata),
    [fs.join(bin_dir, "activate.bat")] = generate_batch_activate(metadata),
    [fs.join(bin_dir, "deactivate.bat")] = generate_batch_deactivate(),
    [fs.join(bin_dir, "activate.ps1")] = generate_powershell_activate(metadata),
  }

  for path, content in pairs(scripts) do
    local ok, err = fs.write_file(path, content)
    if not ok then
      error(string.format("failed to write activation script %s: %s", path, err))
    end
  end
end

local function default_prefix(registry, name)
  return fs.join(registry.envs_dir, name)
end

local function registry_entry(metadata)
  return {
    created_at = metadata.created_at,
    luarocks = metadata.luarocks.version,
    name = metadata.name,
    path = metadata.prefix,
    runtime = metadata.runtime.name .. "=" .. metadata.runtime.version,
  }
end

function environment.load(prefix)
  return state.load_table(metadata_path(prefix))
end

function environment.resolve_specs(specs)
  local runtime = {
    name = "lua",
    version = "latest",
    source = {
      kind = "release",
    },
  }
  local luarocks = {
    version = "latest",
  }

  for _, spec in ipairs(specs or {}) do
    local key, value = spec:match("^([^=]+)=(.+)$")
    if key == "lua" then
      runtime.name = "lua"
      runtime.version = normalize_version(value, "latest")
    elseif key == "luajit" then
      runtime.name = "luajit"
      runtime.version = normalize_version(value, "latest")
    elseif key == "luarocks" then
      luarocks.version = normalize_version(value, "latest")
    elseif spec == "git" then
      runtime.source.kind = "git"
    elseif spec:match("^git@") then
      runtime.source.kind = "git"
      runtime.source.ref = spec:sub(5)
    elseif spec:match("^source=") then
      runtime.source.kind = "local"
      runtime.source.path = spec:match("^source=(.+)$")
    end
  end

  return runtime, luarocks
end

function environment.create(registry, options)
  local existing = registry:get(options.name)
  local prefix = options.prefix or default_prefix(registry, options.name)

  if existing and not options.force then
    error("environment already exists: " .. options.name)
  end

  if fs.exists(prefix) and not options.force then
    error("path already exists: " .. prefix)
  end

  if options.force then
    fs.remove_tree(prefix)
  end

  local runtime, luarocks = environment.resolve_specs(options.specs)
  fs.mkdir_p(prefix)
  fs.mkdir_p(fs.join(prefix, "bin"))
  fs.mkdir_p(fs.join(prefix, "etc", "luarocks"))
  fs.mkdir_p(fs.join(prefix, "include"))
  fs.mkdir_p(fs.join(prefix, "lib"))
  fs.mkdir_p(fs.join(prefix, "metadata"))
  fs.mkdir_p(fs.join(prefix, "rocks"))

  local installed = artifacts.install(
    prefix,
    runtime,
    luarocks,
    registry,
    options.artifact_overrides
  )

  local metadata = {
    artifacts = installed,
    created_at = created_at(),
    name = options.name,
    packages = {
      desired = options.packages or {},
      installed = {},
    },
    prefix = prefix,
    runtime = runtime,
    luarocks = luarocks,
    status = {
      activation_ready = true,
      luarocks_bootstrapped = true,
      runtime_installed = true,
    },
  }

  state.save_table(metadata_path(prefix), metadata)
  local ok, err = fs.write_file(luarocks_config_path(prefix), generate_luarocks_config(prefix))
  if not ok then
    error("failed to write LuaRocks config: " .. err)
  end

  write_activation_scripts(metadata)
  registry:upsert(registry_entry(metadata))
  return metadata
end

function environment.remove(registry, name)
  local entry = registry:get(name)
  if not entry then
    error("unknown environment: " .. name)
  end

  fs.remove_tree(entry.path)
  registry:remove(name)
  return entry
end

function environment.activation_command(metadata, shell)
  shell = shell or "bash"

  if shell == "bash" or shell == "zsh" or shell == "sh" then
    return "source " .. fs.shell_quote(fs.join(metadata.prefix, "bin", "activate"))
  end

  if shell == "fish" then
    return "source " .. fs.shell_quote(fs.join(metadata.prefix, "bin", "activate.fish"))
  end

  if shell == "csh" or shell == "tcsh" then
    return "source " .. fs.shell_quote(fs.join(metadata.prefix, "bin", "activate.csh"))
  end

  if shell == "powershell" or shell == "pwsh" then
    return ". " .. fs.shell_quote(fs.join(metadata.prefix, "bin", "activate.ps1"))
  end

  if shell == "cmd" or shell == "batch" then
    return "call " .. fs.shell_quote(fs.join(metadata.prefix, "bin", "activate.bat"))
  end

  error("unsupported shell: " .. shell)
end

function environment.deactivation_command(shell)
  shell = shell or "bash"

  if shell == "bash" or shell == "zsh" or shell == "sh" or shell == "fish" or shell == "csh" or shell == "tcsh" then
    return "deactivate-riema"
  end

  if shell == "powershell" or shell == "pwsh" then
    return "Exit-RiemaEnv"
  end

  if shell == "cmd" or shell == "batch" then
    return "call deactivate.bat"
  end

  error("unsupported shell: " .. shell)
end

local function shell_join(args)
  local rendered = {}
  for _, value in ipairs(args) do
    rendered[#rendered + 1] = fs.shell_quote(value)
  end
  return table.concat(rendered, " ")
end

function environment.run(metadata, argv)
  if #argv == 0 then
    error("run requires a command")
  end

  local env_path = fs.join(metadata.prefix, "bin") .. platform.path_sep .. (os.getenv("PATH") or "")
  local config_path = luarocks_config_path(metadata.prefix)
  local command

  if platform.is_windows then
    command = table.concat({
      "set",
      "RIEMA_ENV_NAME=" .. metadata.name,
      "&& set",
      "RIEMA_ENV_PREFIX=" .. metadata.prefix,
      "&& set",
      "LUAROCKS_CONFIG=" .. config_path,
      "&& set",
      "PATH=" .. env_path,
      "&&",
      shell_join(argv),
    }, " ")
  else
    command = table.concat({
      "env",
      "RIEMA_ENV_NAME=" .. fs.shell_quote(metadata.name),
      "RIEMA_ENV_PREFIX=" .. fs.shell_quote(metadata.prefix),
      "LUAROCKS_CONFIG=" .. fs.shell_quote(config_path),
      "PATH=" .. fs.shell_quote(env_path),
      shell_join(argv),
    }, " ")
  end

  local ok, _, code = os.execute(command)
  if ok == true then
    return 0
  end

  return code or 1
end

function environment.add_packages(metadata, packages)
  for _, package_name in ipairs(packages) do
    if not contains(metadata.packages.desired, package_name) then
      metadata.packages.desired[#metadata.packages.desired + 1] = package_name
    end
  end

  table.sort(metadata.packages.desired)
  state.save_table(metadata_path(metadata.prefix), metadata)
end

function environment.remove_packages(metadata, packages)
  local remove_set = {}
  for _, package_name in ipairs(packages) do
    remove_set[package_name] = true
  end

  local kept = {}
  for _, package_name in ipairs(metadata.packages.desired) do
    if not remove_set[package_name] then
      kept[#kept + 1] = package_name
    end
  end

  metadata.packages.desired = kept
  state.save_table(metadata_path(metadata.prefix), metadata)
end

return environment
