local fs = require("riema.fs")
local state = require("riema.state")

local Registry = {}
Registry.__index = Registry

local function home_dir()
  return os.getenv("RIEMA_HOME")
    or (os.getenv("HOME") and fs.join(os.getenv("HOME"), ".riema"))
    or (os.getenv("USERPROFILE") and fs.join(os.getenv("USERPROFILE"), ".riema"))
    or ".riema"
end

function Registry.new(root)
  local value = {
    root = root or home_dir(),
  }

  value.envs_dir = fs.join(value.root, "envs")
  value.pkgs_dir = fs.join(value.root, "pkgs")
  value.downloads_dir = fs.join(value.pkgs_dir, "downloads")
  value.registry_path = fs.join(value.root, "registry.lua")
  return setmetatable(value, Registry)
end

function Registry:ensure()
  fs.mkdir_p(self.root)
  fs.mkdir_p(self.envs_dir)
  fs.mkdir_p(self.pkgs_dir)
  fs.mkdir_p(self.downloads_dir)

  if not fs.exists(self.registry_path) then
    state.save_table(self.registry_path, {
      version = 1,
      envs = {},
    })
  end
end

function Registry:load()
  self:ensure()
  return state.load_table(self.registry_path, {
    version = 1,
    envs = {},
  })
end

function Registry:save(data)
  self:ensure()
  state.save_table(self.registry_path, data)
end

function Registry:list()
  local data = self:load()
  table.sort(data.envs, function(left, right)
    return left.name < right.name
  end)
  return data.envs
end

function Registry:get(name)
  local data = self:load()
  for _, entry in ipairs(data.envs) do
    if entry.name == name then
      return entry
    end
  end

  return nil
end

function Registry:upsert(entry)
  local data = self:load()
  local replaced = false

  for index, current in ipairs(data.envs) do
    if current.name == entry.name then
      data.envs[index] = entry
      replaced = true
      break
    end
  end

  if not replaced then
    data.envs[#data.envs + 1] = entry
  end

  table.sort(data.envs, function(left, right)
    return left.name < right.name
  end)
  self:save(data)
end

function Registry:remove(name)
  local data = self:load()
  local kept = {}
  local removed

  for _, entry in ipairs(data.envs) do
    if entry.name == name then
      removed = entry
    else
      kept[#kept + 1] = entry
    end
  end

  data.envs = kept
  self:save(data)
  return removed
end

return Registry
