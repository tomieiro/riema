local environment = require("riema.environment")
local Registry = require("riema.registry")
local yaml = require("riema.yaml")
local doctor = require("riema.doctor")
local fs = require("riema.fs")

local cli = {}

local function fail(message)
  io.stderr:write("riema: " .. message .. "\n")
  return 1
end

local function shift(argv)
  return table.remove(argv, 1)
end

local function copy_args(argv)
  local result = {}
  for index = 1, #argv do
    result[index] = argv[index]
  end
  return result
end

local function registry()
  return Registry.new()
end

local function require_env_entry(name)
  local entry = registry():get(name)
  if not entry then
    error("unknown environment: " .. name)
  end

  return entry
end

local function load_metadata_by_name(name)
  local entry = require_env_entry(name)
  return environment.load(entry.path), entry
end

local function print_help()
  print([[
riema commands:
  create env --name <name> [specs...]
  init [--shell bash] [--persist]
  remove <name>
  list
  info <name>
  activate <name> [--shell bash]
  deactivate [--shell bash]
  run <name> <command ...>
  install <name> <packages ...>
  uninstall <name> <packages ...>
  doctor
  env create -f <file>
  env export <name>
]])
end

local function read_artifact_overrides()
  return {
    lua_bin_url = os.getenv("RIEMA_LUA_BIN_URL"),
    lua_lib_url = os.getenv("RIEMA_LUA_LIB_URL"),
    luarocks_url = os.getenv("RIEMA_LUAROCKS_URL"),
  }
end

local function parse_shell(argv)
  local shell = "bash"
  local kept = {}

  local index = 1
  while index <= #argv do
    local value = argv[index]
    if value == "--shell" then
      shell = argv[index + 1] or shell
      index = index + 2
    else
      kept[#kept + 1] = value
      index = index + 1
    end
  end

  return shell, kept
end

local function invoked_as_path()
  local path = arg and arg[0] or ""
  return path:find("/", 1, true) ~= nil or path:find("\\", 1, true) ~= nil
end

local function executable_path()
  local path = arg and arg[0] or "riema"
  if path:match("^/") or path:match("^[A-Za-z]:[\\/]") then
    return path
  end

  local cwd = assert(fs.capture("pwd")):gsub("%s+$", "")
  return fs.join(cwd, path)
end

local function init_script(exe)
  return string.format([[
riema() {
  local cmd="$1"
  shift || true
  case "$cmd" in
    activate|deactivate)
      eval "$(RIEMA_SHELL_DISPATCH=1 %s "$cmd" "$@")"
      ;;
    *)
      %s "$cmd" "$@"
      ;;
  esac
}
export RIEMA_SHELL_INITIALIZED=1
]], fs.shell_quote(exe), fs.shell_quote(exe))
end

local function parse_init(argv)
  local options = {
    persist = false,
    shell = "bash",
  }

  local index = 1
  while index <= #argv do
    local value = argv[index]
    if value == "--shell" then
      options.shell = argv[index + 1] or options.shell
      index = index + 2
    elseif value == "--persist" then
      options.persist = true
      index = index + 1
    else
      error("unsupported init option: " .. tostring(value))
    end
  end

  return options
end

local function rc_path_for_shell(shell)
  local override = os.getenv("RIEMA_INIT_RC_PATH")
  if override and override ~= "" then
    return override
  end

  local home = os.getenv("HOME")
  if not home or home == "" then
    error("HOME is not set")
  end

  if shell == "bash" then
    return fs.join(home, ".bashrc")
  end

  if shell == "zsh" then
    return fs.join(home, ".zshrc")
  end

  if shell == "sh" then
    return fs.join(home, ".profile")
  end

  error("init currently supports bash, zsh, and sh")
end

local function persist_init(shell, script)
  local rc_path = rc_path_for_shell(shell)
  local start_marker = "# >>> riema initialize >>>"
  local end_marker = "# <<< riema initialize <<<"
  local block = table.concat({
    start_marker,
    script:gsub("%s+$", ""),
    end_marker,
    "",
  }, "\n")

  local current = ""
  if fs.exists(rc_path) then
    current = assert(fs.read_file(rc_path))
  else
    fs.mkdir_p(fs.dirname(rc_path))
  end

  local pattern = start_marker:gsub("(%W)","%%%1") .. ".-\n" .. end_marker:gsub("(%W)","%%%1") .. "\n?"
  if current:match(pattern) then
    current = current:gsub(pattern, "")
    current = current:gsub("%s+$", "")
    if current ~= "" then
      current = current .. "\n\n"
    end
  elseif current ~= "" and not current:match("\n$") then
    current = current .. "\n"
  end

  local ok, err = fs.write_file(rc_path, current .. block)
  if not ok then
    error("failed to persist init hook: " .. err)
  end

  io.stderr:write("riema: persisted shell initialization to " .. rc_path .. "\n")
end

local function parse_create(argv)
  local subject = shift(argv)
  if subject ~= "env" then
    error("create requires the form: riema create env --name <name> ...")
  end

  local options = {
    force = false,
    packages = {},
    specs = {},
    artifact_overrides = read_artifact_overrides(),
  }

  local index = 1
  while index <= #argv do
    local value = argv[index]
    if value == "--name" or value == "-n" then
      options.name = argv[index + 1]
      index = index + 2
    elseif value == "--prefix" then
      options.prefix = argv[index + 1]
      index = index + 2
    elseif value == "--force" then
      options.force = true
      index = index + 1
    elseif value == "--jit" then
      options.specs[#options.specs + 1] = "luajit=latest"
      index = index + 1
    elseif value:match("^%-%-jit=") then
      options.specs[#options.specs + 1] = "luajit=" .. value:match("^%-%-jit=(.+)$")
      index = index + 1
    else
      options.specs[#options.specs + 1] = value
      index = index + 1
    end
  end

  if not options.name or options.name == "" then
    error("create env requires --name <name>")
  end

  return options
end

local function command_create(argv)
  local metadata = environment.create(registry(), parse_create(copy_args(argv)))
  print(string.format("created %s at %s", metadata.name, metadata.prefix))
  return 0
end

local function command_init(argv)
  local options = parse_init(copy_args(argv))
  local exe = executable_path()
  local script = init_script(exe)

  if options.shell == "bash" or options.shell == "zsh" or options.shell == "sh" then
    if options.persist then
      persist_init(options.shell, script)
    end
    io.write(script)
    return 0
  end

  error("init currently supports bash, zsh, and sh")
end

local function command_remove(argv)
  local name = argv[1]
  if not name then
    error("remove requires an environment name")
  end

  environment.remove(registry(), name)
  print("removed " .. name)
  return 0
end

local function command_list()
  local envs = registry():list()
  if #envs == 0 then
    print("no environments")
    return 0
  end

  for _, entry in ipairs(envs) do
    print(string.format("%s\t%s\t%s", entry.name, entry.runtime, entry.path))
  end

  return 0
end

local function command_info(argv)
  local name = argv[1]
  if not name then
    error("info requires an environment name")
  end

  local metadata = load_metadata_by_name(name)
  print("name: " .. metadata.name)
  print("prefix: " .. metadata.prefix)
  print("runtime: " .. metadata.runtime.name .. "=" .. metadata.runtime.version)
  print("luarocks: " .. metadata.luarocks.version)
  if metadata.artifacts and metadata.artifacts.runtime then
    print("runtime_store: " .. tostring(metadata.artifacts.runtime.store_path))
    print("runtime_bin_url: " .. tostring(metadata.artifacts.runtime.bin_url))
    print("runtime_lib_url: " .. tostring(metadata.artifacts.runtime.lib_url))
  end
  if metadata.artifacts and metadata.artifacts.luarocks then
    print("luarocks_store: " .. tostring(metadata.artifacts.luarocks.store_path))
    print("luarocks_url: " .. tostring(metadata.artifacts.luarocks.url))
  end
  print("created_at: " .. metadata.created_at)
  print("packages: " .. table.concat(metadata.packages.desired, ", "))
  print("installed_packages: " .. table.concat(metadata.packages.installed or {}, ", "))
  return 0
end

local function command_activate(argv)
  if os.getenv("RIEMA_SHELL_INITIALIZED") and not os.getenv("RIEMA_SHELL_DISPATCH") and invoked_as_path() then
    error("shell wrapper is initialized; use `riema activate <env>` instead of invoking the executable path directly")
  end

  local shell, kept = parse_shell(copy_args(argv))
  local name = kept[1]
  if not name then
    error("activate requires an environment name")
  end

  local metadata = load_metadata_by_name(name)
  print(environment.activation_command(metadata, shell))
  return 0
end

local function command_deactivate(argv)
  if os.getenv("RIEMA_SHELL_INITIALIZED") and not os.getenv("RIEMA_SHELL_DISPATCH") and invoked_as_path() then
    error("shell wrapper is initialized; use `riema deactivate` instead of invoking the executable path directly")
  end

  local shell = select(1, parse_shell(copy_args(argv)))
  if not os.getenv("RIEMA_ENV_PREFIX") then
    error("no active environment")
  end
  print(environment.deactivation_command(shell))
  return 0
end

local function command_run(argv)
  local name = shift(argv)
  if not name then
    error("run requires an environment name")
  end

  local metadata = load_metadata_by_name(name)
  return environment.run(metadata, argv)
end

local function command_install(argv)
  local name = shift(argv)
  if not name then
    error("install requires an environment name")
  end

  if #argv == 0 then
    error("install requires at least one package name")
  end

  local metadata = load_metadata_by_name(name)
  environment.install_packages(metadata, argv)
  print("installed packages for " .. name)
  return 0
end

local function command_uninstall(argv)
  local name = shift(argv)
  if not name then
    error("uninstall requires an environment name")
  end

  if #argv == 0 then
    error("uninstall requires at least one package name")
  end

  local metadata = load_metadata_by_name(name)
  environment.uninstall_packages(metadata, argv)
  print("removed packages for " .. name)
  return 0
end

local function command_env(argv)
  local subcommand = shift(argv)
  if subcommand == "create" then
    local file_path
    local index = 1
    while index <= #argv do
      if argv[index] == "-f" or argv[index] == "--file" then
        file_path = argv[index + 1]
        break
      end
      index = index + 1
    end

    if not file_path then
      error("env create requires -f <file>")
    end

    local spec = yaml.load_file(file_path)
    local specs = {}
    if spec.lua then
      specs[#specs + 1] = "lua=" .. tostring(spec.lua)
    end
    if spec.luajit then
      specs[#specs + 1] = "luajit=" .. tostring(spec.luajit)
    end
    if spec.luarocks then
      specs[#specs + 1] = "luarocks=" .. tostring(spec.luarocks)
    end

    local metadata = environment.create(registry(), {
      artifact_overrides = read_artifact_overrides(),
      force = false,
      name = spec.name,
      packages = spec.packages or {},
      specs = specs,
    })
    print(string.format("created %s from %s", metadata.name, file_path))
    return 0
  end

  if subcommand == "export" then
    local name = argv[1]
    if not name then
      error("env export requires an environment name")
    end

    local metadata = load_metadata_by_name(name)
    local doc = {
      name = metadata.name,
      luarocks = metadata.luarocks.version,
      packages = metadata.packages.desired,
    }

    if metadata.runtime.name == "luajit" then
      doc.luajit = metadata.runtime.version
    else
      doc.lua = metadata.runtime.version
    end

    io.write(yaml.dump(doc))
    return 0
  end

  error("unsupported env subcommand: " .. tostring(subcommand))
end

function cli.main(argv)
  argv = copy_args(argv or {})
  local command = shift(argv)

  if not command or command == "help" or command == "--help" then
    print_help()
    return 0
  end

  local ok, result = xpcall(function()
    if command == "create" then
      return command_create(argv)
    elseif command == "init" then
      return command_init(argv)
    elseif command == "remove" then
      return command_remove(argv)
    elseif command == "list" then
      return command_list(argv)
    elseif command == "info" then
      return command_info(argv)
    elseif command == "activate" then
      return command_activate(argv)
    elseif command == "deactivate" then
      return command_deactivate(argv)
    elseif command == "run" then
      return command_run(argv)
    elseif command == "install" then
      return command_install(argv)
    elseif command == "uninstall" then
      return command_uninstall(argv)
    elseif command == "doctor" then
      return doctor.run()
    elseif command == "env" then
      return command_env(argv)
    end

    error("unsupported command: " .. tostring(command))
  end, function(err)
    return debug.traceback(err, 1)
  end)

  if ok then
    return result or 0
  end

  local message = result:gsub("\nstack traceback:.*$", "")
  return fail(message)
end

return cli
