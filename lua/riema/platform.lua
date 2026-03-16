local is_windows = package.config:sub(1, 1) == "\\"

local platform = {
  is_windows = is_windows,
  dir_sep = is_windows and "\\" or "/",
  path_sep = is_windows and ";" or ":",
}

local cached

local function capture(command)
  local handle = io.popen(command, "r")
  if not handle then
    return nil
  end

  local output = handle:read("*a")
  handle:close()
  return output and output:gsub("%s+$", "") or nil
end

function platform.detect()
  if cached then
    return cached
  end

  if is_windows then
    cached = {
      arch = os.getenv("PROCESSOR_ARCHITECTURE") or "unknown",
      kernel = nil,
      os = "Windows",
    }
    return cached
  end

  cached = {
    arch = capture("uname -m") or "unknown",
    kernel = capture("uname -r") or "",
    os = capture("uname -s") or "unknown",
  }
  return cached
end

return platform
