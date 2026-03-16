local fs = require("riema.fs")
local serialize = require("riema.serialize")

local state = {}

local function load_table(path, fallback)
  if not fs.exists(path) then
    return fallback
  end

  local chunk, err = loadfile(path, "t", {})
  if not chunk then
    error(string.format("failed to load state file %s: %s", path, err))
  end

  local ok, value = pcall(chunk)
  if not ok then
    error(string.format("failed to execute state file %s: %s", path, value))
  end

  if type(value) ~= "table" then
    error(string.format("state file %s did not return a table", path))
  end

  return value
end

function state.load_table(path, fallback)
  return load_table(path, fallback)
end

function state.save_table(path, value)
  local ok, err = fs.write_file(path, "return " .. serialize.to_lua(value) .. "\n")
  if not ok then
    error(string.format("failed to save state file %s: %s", path, err))
  end
end

return state
