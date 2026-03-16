local serialize = {}

local function is_identifier(value)
  return type(value) == "string" and value:match("^[%a_][%w_]*$") ~= nil
end

local function sorted_keys(value)
  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end

  table.sort(keys, function(left, right)
    if type(left) == type(right) then
      return tostring(left) < tostring(right)
    end

    return type(left) < type(right)
  end)

  return keys
end

local function encode(value, depth)
  depth = depth or 0

  if type(value) == "string" then
    return string.format("%q", value)
  end

  if type(value) == "number" or type(value) == "boolean" then
    return tostring(value)
  end

  if value == nil then
    return "nil"
  end

  if type(value) ~= "table" then
    error("cannot serialize value of type " .. type(value))
  end

  local keys = sorted_keys(value)
  if #keys == 0 then
    return "{}"
  end

  local indent = string.rep("  ", depth)
  local child_indent = string.rep("  ", depth + 1)
  local lines = { "{" }

  for _, key in ipairs(keys) do
    local rendered_key
    if is_identifier(key) then
      rendered_key = key
    else
      rendered_key = "[" .. encode(key, depth + 1) .. "]"
    end

    lines[#lines + 1] = string.format(
      "%s%s = %s,",
      child_indent,
      rendered_key,
      encode(value[key], depth + 1)
    )
  end

  lines[#lines + 1] = indent .. "}"
  return table.concat(lines, "\n")
end

function serialize.to_lua(value)
  return encode(value, 0)
end

return serialize
