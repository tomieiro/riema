local yaml = {}

local function trim(value)
  return value:match("^%s*(.-)%s*$")
end

local function decode_scalar(value)
  value = trim(value)

  if value == "" then
    return ""
  end

  local quoted = value:match('^"(.*)"$') or value:match("^'(.*)'$")
  if quoted then
    return quoted
  end

  if value == "true" then
    return true
  end

  if value == "false" then
    return false
  end

  local number = tonumber(value)
  if number then
    return number
  end

  return value
end

function yaml.parse(text)
  local result = {}
  local current_list

  for raw_line in text:gmatch("[^\r\n]+") do
    local line = raw_line:gsub("#.*$", "")
    if line:match("^%s*$") then
      current_list = current_list
    else
      local key = line:match("^([%w_%-]+):%s*$")
      if key then
        result[key] = {}
        current_list = key
      else
        local pair_key, value = line:match("^([%w_%-]+):%s*(.+)$")
        if pair_key then
          result[pair_key] = decode_scalar(value)
          current_list = nil
        else
          local item = line:match("^%s*%-%s+(.+)$")
          if item and current_list then
            result[current_list][#result[current_list] + 1] = decode_scalar(item)
          else
            error("unsupported YAML shape: " .. raw_line)
          end
        end
      end
    end
  end

  return result
end

function yaml.load_file(path)
  local handle, err = io.open(path, "rb")
  if not handle then
    error("failed to open YAML file: " .. err)
  end

  local content = handle:read("*a")
  handle:close()
  return yaml.parse(content)
end

function yaml.dump(data)
  local lines = {}
  local ordered_keys = {
    "name",
    "lua",
    "luajit",
    "luarocks",
    "packages",
  }

  for _, key in ipairs(ordered_keys) do
    local value = data[key]
    if value ~= nil then
      if type(value) == "table" then
        lines[#lines + 1] = key .. ":"
        for _, item in ipairs(value) do
          lines[#lines + 1] = "  - " .. tostring(item)
        end
      elseif type(value) == "string" then
        lines[#lines + 1] = string.format('%s: "%s"', key, value)
      else
        lines[#lines + 1] = key .. ": " .. tostring(value)
      end
    end
  end

  return table.concat(lines, "\n") .. "\n"
end

return yaml
