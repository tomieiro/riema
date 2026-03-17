local fs = require("riema.fs")
local platform = require("riema.platform")

local artifacts = {}

local LUA_LATEST = {
  latest = "5.5.0",
  ["5.5"] = "5.5.0",
  ["5.4"] = "5.4.8",
  ["5.3"] = "5.3.6",
  ["5.2"] = "5.2.4",
  ["5.1"] = "5.1.5",
}

local LUAROCKS_LATEST = {
  latest = "3.13.0",
  ["3.13"] = "3.13.0",
  ["3.12"] = "3.12.2",
}

local function ensure_tool(names)
  for _, name in ipairs(names) do
    local command
    if platform.is_windows then
      command = string.format("where %s >NUL 2>NUL", name)
    else
      command = string.format("command -v %s >/dev/null 2>&1", name)
    end

    local ok = fs.run(command)
    if ok then
      return name
    end
  end

  error("required tool not found: " .. table.concat(names, " or "))
end

local function parse_kernel(kernel)
  local major, minor = kernel:match("^(%d+)%.(%d+)")
  return tonumber(major or "0"), tonumber(minor or "0")
end

local function linux_abi_tag()
  local detected = platform.detect()
  local major, minor = parse_kernel(detected.kernel or "")
  local score = major * 100 + minor

  if score >= 608 then
    return "Linux68_64"
  end
  if score >= 515 then
    return "Linux515_64"
  end
  if score >= 415 then
    return "Linux415_64"
  end
  if score >= 404 then
    return "Linux44_64"
  end

  return "Linux313_64"
end

local function resolve_alias(value, aliases, label)
  value = tostring(value or "latest")
  if aliases[value] then
    return aliases[value]
  end

  if value:match("^%d+%.%d+%.%d+$") or value:match("^%d+%.%d+%.%d+%-[%w%.]+$") then
    return value
  end

  error(string.format("unsupported %s version alias: %s", label, value))
end

local function base_name(path)
  return path:match("([^/\\]+)$")
end

local function download(url, destination)
  local downloader = ensure_tool({ "curl", "wget" })
  local command
  if downloader == "curl" then
    command = string.format("curl -fsSL -o %s %s", fs.shell_quote(destination), fs.shell_quote(url))
  else
    command = string.format("wget -q -O %s %s", fs.shell_quote(destination), fs.shell_quote(url))
  end

  local ok = fs.run(command)
  if not ok then
    error("failed to download " .. url)
  end
end

local function extract(archive, destination)
  fs.mkdir_p(destination)
  if archive:match("%.zip$") then
    ensure_tool({ "unzip" })
    local ok = fs.run(string.format("unzip -oq %s -d %s", fs.shell_quote(archive), fs.shell_quote(destination)))
    if not ok then
      error("failed to extract " .. archive)
    end
    return
  end

  ensure_tool({ "tar" })
  local ok = fs.run(string.format("tar -xzf %s -C %s", fs.shell_quote(archive), fs.shell_quote(destination)))
  if not ok then
    error("failed to extract " .. archive)
  end
end

local function cache_path(cache_dir, url)
  return fs.join(cache_dir, base_name(url:gsub("/download$", "")))
end

local function copy_and_chmod(source, destination)
  local ok, err = fs.copy_file(source, destination)
  if not ok then
    error(string.format("failed to copy %s to %s: %s", source, destination, err))
  end

  fs.chmod_plus_x(destination)
end

local function runtime_store_path(pkgs_dir, runtime_version, abi_tag)
  return fs.join(pkgs_dir, "lua", runtime_version, abi_tag)
end

local function luarocks_store_path(pkgs_dir, version)
  return fs.join(pkgs_dir, "luarocks", version, "linux-x86_64")
end

local function install_runtime_from_store(store_dir, prefix, runtime_version)
  local major, minor = runtime_version:match("^(%d+)%.(%d+)")
  local suffix = tostring(major) .. tostring(minor)
  local versioned_lua = "lua" .. suffix
  local versioned_luac = "luac" .. suffix

  copy_and_chmod(fs.join(store_dir, "bin", versioned_lua), fs.join(prefix, "bin", versioned_lua))
  copy_and_chmod(fs.join(store_dir, "bin", versioned_lua), fs.join(prefix, "bin", "lua"))
  copy_and_chmod(fs.join(store_dir, "bin", versioned_luac), fs.join(prefix, "bin", versioned_luac))
  copy_and_chmod(fs.join(store_dir, "bin", versioned_luac), fs.join(prefix, "bin", "luac"))

  if fs.exists(fs.join(store_dir, "include")) then
    local ok = fs.copy_tree(fs.join(store_dir, "include"), fs.join(prefix, "include"))
    if not ok then
      error("failed to install Lua headers")
    end
  end

  if fs.exists(fs.join(store_dir, "lib")) then
    local ok = fs.copy_tree(fs.join(store_dir, "lib"), fs.join(prefix, "lib"))
    if not ok then
      error("failed to install Lua libraries")
    end
  end
end

local function populate_runtime_store(store_dir, extracted, runtime_version)
  fs.mkdir_p(fs.join(store_dir, "bin"))
  fs.mkdir_p(fs.join(store_dir, "include"))
  fs.mkdir_p(fs.join(store_dir, "lib"))

  local major, minor = runtime_version:match("^(%d+)%.(%d+)")
  local suffix = tostring(major) .. tostring(minor)
  local versioned_lua = "lua" .. suffix
  local versioned_luac = "luac" .. suffix

  copy_and_chmod(fs.join(extracted, versioned_lua), fs.join(store_dir, "bin", versioned_lua))
  copy_and_chmod(fs.join(extracted, versioned_luac), fs.join(store_dir, "bin", versioned_luac))

  local include_dir = fs.join(extracted, "include")
  if fs.exists(include_dir) then
    local ok = fs.copy_tree(include_dir, fs.join(store_dir, "include"))
    if not ok then
      error("failed to stage Lua headers")
    end
  end

  local lib_dir = fs.join(extracted, "lib")
  if fs.exists(lib_dir) then
    local ok = fs.copy_tree(lib_dir, fs.join(store_dir, "lib"))
    if not ok then
      error("failed to stage Lua libraries")
    end
  end

  for _, file_name in ipairs({ "liblua" .. suffix .. ".a", "liblua" .. suffix .. ".so" }) do
    local source = fs.join(extracted, file_name)
    if fs.exists(source) then
      local ok = fs.copy_file(source, fs.join(store_dir, "lib", file_name))
      if not ok then
        error("failed to stage " .. file_name)
      end
    end
  end
end

local function install_luarocks_from_store(store_dir, prefix)
  copy_and_chmod(fs.join(store_dir, "bin", "luarocks"), fs.join(prefix, "bin", "luarocks-real"))
  copy_and_chmod(fs.join(store_dir, "bin", "luarocks-admin"), fs.join(prefix, "bin", "luarocks-admin-real"))
end

local function populate_luarocks_store(store_dir, extracted, version)
  fs.mkdir_p(fs.join(store_dir, "bin"))
  local base = fs.join(extracted, string.format("luarocks-%s-linux-x86_64", version))
  copy_and_chmod(fs.join(base, "luarocks"), fs.join(store_dir, "bin", "luarocks"))
  copy_and_chmod(fs.join(base, "luarocks-admin"), fs.join(store_dir, "bin", "luarocks-admin"))
end

local function install_lua_runtime(prefix, runtime, pkgs_dir, downloads_dir, overrides)
  if runtime.name ~= "lua" then
    error("binary runtime download is currently implemented for Lua releases only")
  end

  if runtime.source.kind ~= "release" then
    error("binary download currently supports official release artifacts only")
  end

  local detected = platform.detect()
  if detected.os ~= "Linux" or detected.arch ~= "x86_64" then
    error("binary Lua download is currently implemented for Linux x86_64")
  end

  local resolved_version = resolve_alias(runtime.version, LUA_LATEST, "Lua")
  local abi_tag = linux_abi_tag()
  local store_dir = runtime_store_path(pkgs_dir, resolved_version, abi_tag)
  local bin_url = overrides.lua_bin_url
    or string.format(
      "https://sourceforge.net/projects/luabinaries/files/%s/Tools%%20Executables/lua-%s_%s_bin.tar.gz/download",
      resolved_version,
      resolved_version,
      abi_tag
    )
  local lib_url = overrides.lua_lib_url
    or string.format(
      "https://sourceforge.net/projects/luabinaries/files/%s/Linux%%20Libraries/lua-%s_%s_lib.tar.gz/download",
      resolved_version,
      resolved_version,
      abi_tag
    )

  if not fs.exists(store_dir) then
    local bin_archive = cache_path(downloads_dir, bin_url)
    local lib_archive = cache_path(downloads_dir, lib_url)
    if not fs.exists(bin_archive) then
      download(bin_url, bin_archive)
    end
    if not fs.exists(lib_archive) then
      download(lib_url, lib_archive)
    end

    local temp_dir = assert(fs.make_temp_dir(downloads_dir))
    local extracted = fs.join(temp_dir, "runtime")
    fs.mkdir_p(extracted)
    extract(bin_archive, extracted)
    extract(lib_archive, extracted)
    populate_runtime_store(store_dir, extracted, resolved_version)
    fs.remove_tree(temp_dir)
  end

  install_runtime_from_store(store_dir, prefix, resolved_version)

  return {
    abi = abi_tag,
    bin_url = bin_url,
    lib_url = lib_url,
    store_path = store_dir,
    version = resolved_version,
  }
end

local function install_luarocks(prefix, requested_version, pkgs_dir, downloads_dir, overrides)
  local detected = platform.detect()
  if detected.os ~= "Linux" or detected.arch ~= "x86_64" then
    error("binary LuaRocks download is currently implemented for Linux x86_64")
  end

  local resolved_version = resolve_alias(requested_version, LUAROCKS_LATEST, "LuaRocks")
  local store_dir = luarocks_store_path(pkgs_dir, resolved_version)
  local url = overrides.luarocks_url
    or string.format(
      "https://luarocks.github.io/luarocks/releases/luarocks-%s-linux-x86_64.zip",
      resolved_version
    )
  if not fs.exists(store_dir) then
    local archive = cache_path(downloads_dir, url)
    if not fs.exists(archive) then
      download(url, archive)
    end

    local temp_dir = assert(fs.make_temp_dir(downloads_dir))
    local extracted = fs.join(temp_dir, "luarocks")
    fs.mkdir_p(extracted)
    extract(archive, extracted)
    populate_luarocks_store(store_dir, extracted, resolved_version)
    fs.remove_tree(temp_dir)
  end

  install_luarocks_from_store(store_dir, prefix)

  return {
    store_path = store_dir,
    url = url,
    version = resolved_version,
  }
end

function artifacts.install(prefix, runtime, luarocks, registry, overrides)
  overrides = overrides or {}
  registry:ensure()

  local installed_runtime = install_lua_runtime(prefix, runtime, registry.pkgs_dir, registry.downloads_dir, overrides)
  local installed_luarocks = install_luarocks(prefix, luarocks.version, registry.pkgs_dir, registry.downloads_dir, overrides)

  runtime.version = installed_runtime.version
  luarocks.version = installed_luarocks.version

  return {
    luarocks = installed_luarocks,
    runtime = installed_runtime,
  }
end

return artifacts
