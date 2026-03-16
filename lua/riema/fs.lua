local platform = require("riema.platform")

local fs = {}

local function shell_quote(value)
  if platform.is_windows then
    return '"' .. tostring(value):gsub('"', '\\"') .. '"'
  end

  return "'" .. tostring(value):gsub("'", [['"'"']]) .. "'"
end

function fs.shell_quote(value)
  return shell_quote(value)
end

function fs.join(...)
  local parts = { ... }
  local path = table.remove(parts, 1) or ""

  for _, part in ipairs(parts) do
    if part ~= "" then
      if path == "" or path:sub(-1) == platform.dir_sep then
        path = path .. part
      else
        path = path .. platform.dir_sep .. part
      end
    end
  end

  return path
end

function fs.exists(path)
  local ok = os.rename(path, path)
  if ok then
    return true
  end

  local handle = io.open(path, "rb")
  if handle then
    handle:close()
    return true
  end

  return false
end

function fs.read_file(path)
  local handle, err = io.open(path, "rb")
  if not handle then
    return nil, err
  end

  local content = handle:read("*a")
  handle:close()
  return content
end

function fs.write_file(path, content)
  local handle, err = io.open(path, "wb")
  if not handle then
    return nil, err
  end

  handle:write(content)
  handle:close()
  return true
end

function fs.run(command)
  local ok, _, code = os.execute(command)
  return ok == true or code == 0, code or 1
end

function fs.capture(command)
  local handle = io.popen(command, "r")
  if not handle then
    return nil, "failed to spawn command"
  end

  local output = handle:read("*a")
  local ok, _, code = handle:close()
  if ok == true or code == 0 then
    return output
  end

  return nil, output
end

function fs.mkdir_p(path)
  local command
  if platform.is_windows then
    command = string.format('if not exist %s mkdir %s', shell_quote(path), shell_quote(path))
  else
    command = string.format('mkdir -p %s', shell_quote(path))
  end

  local ok, _, code = os.execute(command)
  return ok == true or code == 0
end

function fs.remove_tree(path)
  if not fs.exists(path) then
    return true
  end

  local command
  if platform.is_windows then
    command = string.format('if exist %s rmdir /S /Q %s', shell_quote(path), shell_quote(path))
  else
    command = string.format('rm -rf %s', shell_quote(path))
  end

  local ok, _, code = os.execute(command)
  return ok == true or code == 0
end

function fs.dirname(path)
  local sep = platform.dir_sep
  local index = path:match("^.*()" .. sep)
  if not index then
    return "."
  end

  local value = path:sub(1, index - 1)
  if value == "" then
    return sep
  end

  return value
end

function fs.copy_file(source, destination)
  local content, err = fs.read_file(source)
  if not content then
    return nil, err
  end

  return fs.write_file(destination, content)
end

function fs.copy_tree(source, destination)
  local command
  if platform.is_windows then
    command = string.format("xcopy %s %s /E /I /Y >NUL", shell_quote(source), shell_quote(destination))
  else
    command = string.format("mkdir -p %s && cp -R %s/. %s", shell_quote(destination), shell_quote(source), shell_quote(destination))
  end

  return fs.run(command)
end

function fs.chmod_plus_x(path)
  if platform.is_windows then
    return true
  end

  return fs.run(string.format("chmod +x %s", shell_quote(path)))
end

function fs.make_temp_dir(parent)
  parent = parent or os.getenv("TMPDIR") or "/tmp"
  local template = fs.join(parent, "riema.XXXXXX")
  local output, err = fs.capture(string.format("mktemp -d %s", shell_quote(template)))
  if not output then
    return nil, err
  end

  return output:gsub("%s+$", "")
end

return fs
