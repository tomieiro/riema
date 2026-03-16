local platform = require("riema.platform")

local doctor = {}

local function tool_exists(command)
  local probe
  if platform.is_windows then
    probe = string.format("where %s >NUL 2>NUL", command)
  else
    probe = string.format("command -v %s >/dev/null 2>&1", command)
  end

  local ok, _, code = os.execute(probe)
  return ok == true or code == 0
end

function doctor.run()
  local tools = {
    "git",
    "make",
    "gcc",
    "clang",
    "curl",
    "wget",
    "tar",
    "unzip",
  }

  local missing = {}
  for _, tool in ipairs(tools) do
    if not tool_exists(tool) then
      missing[#missing + 1] = tool
    end
  end

  if #missing == 0 then
    print("doctor: toolchain looks usable")
    return 0
  end

  io.stderr:write("doctor: missing tools: " .. table.concat(missing, ", ") .. "\n")
  return 1
end

return doctor
