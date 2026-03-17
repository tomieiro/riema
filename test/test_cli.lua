package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  package.path,
}, ";")

local fs = require("riema.fs")
local Registry = require("riema.registry")
local environment = require("riema.environment")
local yaml = require("riema.yaml")

local function assert_equal(actual, expected, context)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", context or "assert_equal", tostring(expected), tostring(actual)))
  end
end

local function assert_truthy(value, context)
  if not value then
    error(context or "expected truthy value")
  end
end

local function run_capture(command)
  local handle = assert(io.popen(command .. " 2>&1", "r"))
  local output = handle:read("*a")
  local ok, _, code = handle:close()
  return ok == true or code == 0, output
end

local function rimraf(path)
  fs.remove_tree(path)
end

local function sh(command)
  local ok, output = run_capture(command)
  if not ok then
    error(output)
  end
end

local function make_fixtures(root)
  local fixture_root = fs.join(root, "fixtures")
  local build_root = fs.join(fixture_root, "build")
  local cache_root = fs.join(fixture_root, "archives")
  fs.mkdir_p(build_root)
  fs.mkdir_p(cache_root)

  local runtime_root = fs.join(build_root, "runtime")
  fs.mkdir_p(runtime_root)
  assert_truthy(fs.write_file(fs.join(runtime_root, "lua54"), [[#!/bin/sh
if [ "$1" = "-e" ] && printf '%s' "$2" | grep -q 'require("inspect")'; then
  if [ -f "$RIEMA_ENV_PREFIX/share/lua/5.4/inspect.lua" ] && [ -n "$LUA_PATH" ] && [ -n "$LUA_CPATH" ]; then
    printf 'inspect-ok'
    exit 0
  fi
  printf 'inspect-missing' >&2
  exit 1
fi
printf '%s' "${RIEMA_ENV_NAME}|${LUAROCKS_CONFIG}|${LUA_PATH}|${LUA_CPATH}"
]]), "write fake lua")
  assert_truthy(fs.write_file(fs.join(runtime_root, "luac54"), [[#!/bin/sh
printf 'luac'
]]), "write fake luac")
  fs.chmod_plus_x(fs.join(runtime_root, "lua54"))
  fs.chmod_plus_x(fs.join(runtime_root, "luac54"))

  local libs_root = fs.join(build_root, "libs")
  fs.mkdir_p(fs.join(libs_root, "include"))
  fs.mkdir_p(fs.join(libs_root, "lib"))
  assert_truthy(fs.write_file(fs.join(libs_root, "liblua54.a"), "archive"), "write liblua a")
  assert_truthy(fs.write_file(fs.join(libs_root, "liblua54.so"), "shared"), "write liblua so")
  assert_truthy(fs.write_file(fs.join(libs_root, "include", "lua.h"), "/* lua */"), "write lua.h")
  assert_truthy(fs.write_file(fs.join(libs_root, "include", "lauxlib.h"), "/* lauxlib */"), "write lauxlib.h")
  assert_truthy(fs.write_file(fs.join(libs_root, "include", "lualib.h"), "/* lualib */"), "write lualib.h")
  assert_truthy(fs.write_file(fs.join(libs_root, "include", "luaconf.h"), "/* luaconf */"), "write luaconf.h")
  assert_truthy(fs.write_file(fs.join(libs_root, "include", "lua.hpp"), "// lua.hpp"), "write lua.hpp")

  local rocks_root = fs.join(build_root, "luarocks-3.12.2-linux-x86_64")
  fs.mkdir_p(rocks_root)
  assert_truthy(fs.write_file(fs.join(rocks_root, "luarocks"), [[#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in
    --*)
      shift
      ;;
    *)
      break
      ;;
  esac
done
cmd="$1"
shift
prefix=$(CDPATH= cd "$(dirname "$LUAROCKS_CONFIG")/../.." && pwd)
log="$prefix/metadata/luarocks.log"
installed="$prefix/metadata/installed-rocks.txt"
mkdir -p "$prefix/metadata"
case "$cmd" in
  install)
    mkdir -p "$prefix/share/lua/5.4" "$prefix/lib/lua/5.4" "$prefix/lib/luarocks/rocks-5.4"
    for pkg in "$@"; do
      printf 'install %s\n' "$pkg" >> "$log"
      printf '%s\n' "$pkg" >> "$installed"
      printf 'return { name = "%s" }\n' "$pkg" > "$prefix/share/lua/5.4/$pkg.lua"
    done
    ;;
  remove)
    for pkg in "$@"; do
      printf 'remove %s\n' "$pkg" >> "$log"
      if [ -f "$installed" ]; then
        tmp="$installed.tmp"
        grep -vx "$pkg" "$installed" > "$tmp" || true
        mv "$tmp" "$installed"
      fi
      rm -f "$prefix/share/lua/5.4/$pkg.lua" "$prefix/lib/lua/5.4/$pkg.so"
    done
    ;;
  list)
    if [ -f "$installed" ]; then
      cat "$installed"
    fi
    ;;
  *)
    printf '%s\n' "$cmd" >> "$log"
    ;;
esac
]]), "write fake luarocks")
  assert_truthy(fs.write_file(fs.join(rocks_root, "luarocks-admin"), [[#!/bin/sh
printf 'luarocks-admin'
]]), "write fake luarocks-admin")
  fs.chmod_plus_x(fs.join(rocks_root, "luarocks"))
  fs.chmod_plus_x(fs.join(rocks_root, "luarocks-admin"))

  local runtime_archive = fs.join(cache_root, "lua-bin.tar.gz")
  local libs_archive = fs.join(cache_root, "lua-lib.tar.gz")
  local rocks_archive = fs.join(cache_root, "luarocks.zip")

  sh(string.format("cd %s && tar -czf %s lua54 luac54", fs.shell_quote(runtime_root), fs.shell_quote(runtime_archive)))
  sh(string.format("cd %s && tar -czf %s include liblua54.a liblua54.so", fs.shell_quote(libs_root), fs.shell_quote(libs_archive)))
  sh(string.format("cd %s && zip -qr %s luarocks-3.12.2-linux-x86_64", fs.shell_quote(build_root), fs.shell_quote(rocks_archive)))

  return {
    lua_bin_url = "file://" .. runtime_archive,
    lua_lib_url = "file://" .. libs_archive,
    luarocks_url = "file://" .. rocks_archive,
  }
end

local ok_pwd, pwd_output = run_capture("pwd")
assert_truthy(ok_pwd, pwd_output)
local cwd = pwd_output:gsub("%s+$", "")
local root = fs.join(cwd, ".riema-test")
rimraf(root)
assert_truthy(fs.mkdir_p(root), "mkdir test root")
local overrides = make_fixtures(root)

local registry = Registry.new(root)
local metadata = environment.create(registry, {
  artifact_overrides = overrides,
  name = "dev",
  specs = { "lua=5.4", "luarocks=3.12" },
  packages = { "busted", "luasocket" },
})

assert_equal(metadata.name, "dev", "env name")
assert_equal(metadata.runtime.version, "5.4.8", "lua version")
assert_equal(metadata.luarocks.version, "3.12.2", "luarocks version")
assert_truthy(fs.exists(fs.join(metadata.prefix, "bin", "activate")), "activate script exists")
assert_truthy(fs.exists(fs.join(metadata.prefix, "bin", "lua")), "lua binary exists")
assert_truthy(fs.exists(fs.join(metadata.prefix, "bin", "luarocks")), "luarocks binary exists")
assert_truthy(fs.exists(fs.join(metadata.prefix, "etc", "luarocks", "config.lua")), "luarocks config exists")
assert_truthy(fs.exists(fs.join(root, "pkgs", "lua", "5.4.8", "Linux68_64")), "global runtime store exists")
assert_truthy(fs.exists(fs.join(root, "pkgs", "luarocks", "3.12.2", "linux-x86_64")), "global luarocks store exists")
local activate_script = assert(fs.read_file(fs.join(metadata.prefix, "bin", "activate")))
assert_truthy(activate_script:match("%(dev::5%.4%.8%)"), "activate prefixes prompt")
assert_truthy(activate_script:match("RIEMA_OLD_PS1"), "activate stores previous prompt")
assert_truthy(activate_script:match("LUA_PATH"), "activate exports LUA_PATH")
assert_truthy(activate_script:match("LUA_CPATH"), "activate exports LUA_CPATH")

local loaded = environment.load(metadata.prefix)
assert_equal(loaded.luarocks.version, "3.12.2", "stored luarocks version")
assert_equal(#registry:list(), 1, "registry entry count")
assert_equal(loaded.packages.installed[1], "busted", "create installs first package")
assert_equal(loaded.packages.installed[2], "luasocket", "create installs second package")
local install_log = assert(fs.read_file(fs.join(metadata.prefix, "metadata", "luarocks.log")))
assert_truthy(install_log:match("install busted"), "luarocks installs busted")
assert_truthy(install_log:match("install luasocket"), "luarocks installs luasocket")

environment.install_packages(loaded, { "inspect" })
local updated = environment.load(metadata.prefix)
assert_truthy(updated.packages.desired[2] == "inspect" or updated.packages.desired[3] == "inspect", "package recorded")
assert_truthy(updated.packages.installed[2] == "inspect" or updated.packages.installed[3] == "inspect", "package installed")

local exported = yaml.dump({
  name = "dev",
  lua = "5.4.8",
  luarocks = "3.12.2",
  packages = { "busted", "luasocket" },
})
local parsed = yaml.parse(exported)
assert_equal(parsed.name, "dev", "yaml name")
assert_equal(parsed.lua, "5.4.8", "yaml lua")
assert_equal(parsed.packages[2], "luasocket", "yaml package")

local env_file = fs.join(root, "env.yml")
assert_truthy(fs.write_file(env_file, [[
name: file-env
lua: "5.4"
luarocks: "3.12"
packages:
  - inspect
  - penlight
]]), "write env file")

local env_prefix = string.format(
  "RIEMA_HOME=%s RIEMA_LUA_BIN_URL=%s RIEMA_LUA_LIB_URL=%s RIEMA_LUAROCKS_URL=%s",
  fs.shell_quote(root),
  fs.shell_quote(overrides.lua_bin_url),
  fs.shell_quote(overrides.lua_lib_url),
  fs.shell_quote(overrides.luarocks_url)
)

local ok_create, create_output = run_capture(string.format("%s ./riema env create -f %s", env_prefix, fs.shell_quote(env_file)))
assert_truthy(ok_create, create_output)
assert_truthy(create_output:match("created file%-env from"), "env create output")
local file_env = environment.load(fs.join(root, "envs", "file-env"))
assert_equal(file_env.packages.installed[1], "inspect", "yaml create installs inspect")
assert_equal(file_env.packages.installed[2], "penlight", "yaml create installs penlight")

local ok_cli_create, cli_create_output = run_capture(string.format(
  "%s ./riema create env --name cli-env lua=5.4 luarocks=3.12",
  env_prefix
))
assert_truthy(ok_cli_create, cli_create_output)
assert_truthy(cli_create_output:match("created cli%-env"), "create env output")

local ok_list, list_output = run_capture(string.format("%s ./riema list", env_prefix))
assert_truthy(ok_list, list_output)
assert_truthy(list_output:match("dev"), "list includes dev")
assert_truthy(list_output:match("file%-env"), "list includes file-env")
assert_truthy(list_output:match("cli%-env"), "list includes cli-env")

local ok_activate, activate_output = run_capture(string.format("%s ./riema activate dev --shell bash", env_prefix))
assert_truthy(ok_activate, activate_output)
assert_truthy(activate_output:match("^source "), "activate emits source command")

local ok_init, init_output = run_capture(string.format("%s ./riema init --shell bash", env_prefix))
assert_truthy(ok_init, init_output)
assert_truthy(init_output:match("riema%(%)"), "init emits shell wrapper")
assert_truthy(init_output:match("RIEMA_SHELL_INITIALIZED"), "init marks shell initialization")

local persist_home = fs.join(root, "persist-home")
local persist_rc = fs.join(persist_home, ".bashrc")
assert_truthy(fs.mkdir_p(persist_home), "mkdir persist home")
local ok_persist, persist_output = run_capture(string.format(
  "%s HOME=%s RIEMA_INIT_RC_PATH=%s ./riema init --shell bash --persist",
  env_prefix,
  fs.shell_quote(persist_home),
  fs.shell_quote(persist_rc)
))
assert_truthy(ok_persist, persist_output)
local persisted = assert(fs.read_file(persist_rc))
assert_truthy(persisted:match(">>> riema initialize >>>"), "persist writes start marker")
assert_truthy(persisted:match("RIEMA_SHELL_INITIALIZED=1"), "persist writes hook")

local ok_persist_again, persist_again_output = run_capture(string.format(
  "%s HOME=%s RIEMA_INIT_RC_PATH=%s ./riema init --shell bash --persist",
  env_prefix,
  fs.shell_quote(persist_home),
  fs.shell_quote(persist_rc)
))
assert_truthy(ok_persist_again, persist_again_output)
local persisted_again = assert(fs.read_file(persist_rc))
local marker_count = 0
for _ in persisted_again:gmatch(">>> riema initialize >>>") do
  marker_count = marker_count + 1
end
assert_equal(marker_count, 1, "persist is idempotent")

local ok_path_activate, path_activate_output = run_capture(string.format(
  "%s bash -lc 'eval \"$(%s init --shell bash)\"; %s activate dev'",
  env_prefix,
  fs.shell_quote(fs.join(cwd, "riema")),
  fs.shell_quote(fs.join(cwd, "riema"))
))
assert_truthy(not ok_path_activate, "path-based activate should fail after init")
assert_truthy(path_activate_output:match("use `riema activate <env>`"), "path activate guidance")

local ok_bash_activate, bash_activate_output = run_capture(string.format(
  "%s bash -lc 'eval \"$(%s init --shell bash)\"; riema activate dev; printf \"PS1=%%s\\n\" \"$PS1\"; lua'",
  env_prefix,
  fs.shell_quote(fs.join(cwd, "riema"))
))
assert_truthy(ok_bash_activate, bash_activate_output)
assert_truthy(bash_activate_output:match("PS1=%(dev::5%.4%.8%)"), "init wrapper updates PS1")
assert_truthy(bash_activate_output:match("dev|"), "init wrapper activates env lua")
assert_truthy(bash_activate_output:match("/share/lua/5%.4/%?%.lua"), "init wrapper exports LUA_PATH")
assert_truthy(bash_activate_output:match("/lib/lua/5%.4/%?%.so"), "init wrapper exports LUA_CPATH")

local ok_deactivate_fail, deactivate_fail_output = run_capture(string.format("%s ./riema deactivate", env_prefix))
assert_truthy(not ok_deactivate_fail, "deactivate should fail when no env is active")
assert_truthy(deactivate_fail_output:match("no active environment"), "deactivate error message")

local ok_deactivate, deactivate_output = run_capture(string.format(
  "%s RIEMA_ENV_PREFIX=%s RIEMA_ENV_NAME=dev ./riema deactivate",
  env_prefix,
  fs.shell_quote(metadata.prefix)
))
assert_truthy(ok_deactivate, deactivate_output)
assert_truthy(deactivate_output:match("deactivate%-riema"), "deactivate emits shell command")

local ok_install, install_output = run_capture(string.format("%s ./riema install dev penlight", env_prefix))
assert_truthy(ok_install, install_output)
assert_truthy(install_output:match("installed packages for dev"), "install command output")
local after_install = environment.load(metadata.prefix)
assert_truthy(after_install.packages.installed[3] == "penlight" or after_install.packages.installed[4] == "penlight", "install command installs package")

local ok_run, run_output = run_capture(string.format(
  "%s ./riema run dev lua -e ignored",
  env_prefix
))
assert_truthy(ok_run, run_output)
assert_truthy(run_output:match("^dev|"), "run exports environment")
assert_truthy(run_output:match("/share/lua/5%.4/%?%.lua"), "run exports LUA_PATH")
assert_truthy(run_output:match("/lib/lua/5%.4/%?%.so"), "run exports LUA_CPATH")

local ok_run_require, run_require_output = run_capture(string.format(
  "%s ./riema run dev lua -e 'require(\"inspect\")'",
  env_prefix
))
assert_truthy(ok_run_require, run_require_output)
assert_truthy(run_require_output:match("inspect%-ok"), "run resolves installed LuaRocks package")

local ok_run_luarocks, run_luarocks_output = run_capture(string.format(
  "%s ./riema run dev luarocks list",
  env_prefix
))
assert_truthy(ok_run_luarocks, run_luarocks_output)
assert_truthy(run_luarocks_output:match("inspect"), "run luarocks list works inside env")

local ok_export, export_output = run_capture(string.format("%s ./riema env export file-env", env_prefix))
assert_truthy(ok_export, export_output)
assert_truthy(export_output:match('lua: "5%.4%.8"'), "exported lua version")

local ok_info, info_output = run_capture(string.format("%s ./riema info dev", env_prefix))
assert_truthy(ok_info, info_output)
assert_truthy(info_output:match("runtime_store: "), "info shows runtime store")
assert_truthy(info_output:match("luarocks_store: "), "info shows luarocks store")
assert_truthy(info_output:match("installed_packages: "), "info shows installed packages")

environment.remove(registry, "dev")
assert_equal(#registry:list(), 2, "registry count after remove")

rimraf(root)
print("ok")
