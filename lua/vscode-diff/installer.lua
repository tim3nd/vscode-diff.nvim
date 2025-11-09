-- Automatic installer for libvscode-diff binary
-- Downloads pre-built binaries from GitHub releases

local M = {}

-- Get the plugin root directory
-- Navigates from lua/vscode-diff/installer.lua -> lua/vscode-diff/ -> lua/ -> plugin root
local function get_plugin_root()
  local source = debug.getinfo(1).source:sub(2)
  return vim.fn.fnamemodify(source, ":h:h:h")
end

-- Detect OS
local function detect_os()
  local ffi = require("ffi")
  if ffi.os == "Windows" then
    return "windows"
  elseif ffi.os == "OSX" then
    return "macos"
  else
    return "linux"
  end
end

-- Detect architecture
local function detect_arch()
  local uname = vim.loop.os_uname()
  local machine = uname.machine:lower()
  
  -- Handle different naming conventions
  if machine:match("x86_64") or machine:match("amd64") or machine:match("x64") then
    return "x64"
  elseif machine:match("aarch64") or machine:match("arm64") then
    return "arm64"
  else
    return nil, "Unsupported architecture: " .. machine
  end
end

-- Get library extension for current OS
local function get_lib_ext()
  local ffi = require("ffi")
  if ffi.os == "Windows" then
    return "dll"
  elseif ffi.os == "OSX" then
    return "dylib"
  else
    return "so"
  end
end

-- Get library filename (without version)
local function get_lib_filename()
  return "libvscode_diff." .. get_lib_ext()
end

-- Get the current VERSION from VERSION file
local function get_current_version()
  local version_file = get_plugin_root() .. "/VERSION"
  local f = io.open(version_file, "r")
  if f then
    local content = f:read("*all")
    f:close()
    return content:match("^%s*(.-)%s*$")
  end
  return nil
end

-- Save the installed library version
local function save_installed_version(version)
  local version_marker = get_plugin_root() .. "/.libvscode_diff_version"
  local f = io.open(version_marker, "w")
  if f then
    f:write(version)
    f:close()
    return true
  end
  return false
end

-- Build download URL for GitHub release
local function build_download_url(os, arch)
  local version_file = get_plugin_root() .. "/VERSION"
  local version = nil
  
  -- Read version from VERSION file (required)
  local f = io.open(version_file, "r")
  if f then
    local content = f:read("*all")
    f:close()
    -- Extract version, remove trailing whitespace/newlines
    version = content:match("^%s*(.-)%s*$")
  end
  
  if not version or version == "" then
    return nil, nil, "Failed to read VERSION file at: " .. version_file
  end
  
  local ext = get_lib_ext()
  local filename = string.format("libvscode_diff_%s_%s_%s.%s", os, arch, version, ext)
  local url = string.format(
    "https://github.com/esmuellert/vscode-diff.nvim/releases/download/v%s/%s",
    version,
    filename
  )
  
  return url, filename, nil
end

-- Check if a command exists
local function command_exists(cmd)
  local ffi = require("ffi")
  if ffi.os == "Windows" then
    -- On Windows, use 'where' command instead of 'which'
    local handle = io.popen("where " .. cmd .. " 2>nul")
    if handle then
      local result = handle:read("*a")
      handle:close()
      return result ~= ""
    end
    return false
  else
    local handle = io.popen("which " .. cmd .. " 2>/dev/null")
    if handle then
      local result = handle:read("*a")
      handle:close()
      return result ~= ""
    end
    return false
  end
end

-- Download file using curl, wget, or PowerShell
local function download_file(url, dest_path)
  local ffi = require("ffi")
  local cmd_args
  
  -- Try curl first (most common, best error handling)
  if command_exists("curl") then
    cmd_args = { "curl", "-fsSL", "-o", dest_path, url }
  elseif command_exists("wget") then
    cmd_args = { "wget", "-q", "-O", dest_path, url }
  elseif ffi.os == "Windows" then
    -- On Windows, try PowerShell Invoke-WebRequest
    cmd_args = {
      "powershell",
      "-NoProfile",
      "-Command",
      string.format("Invoke-WebRequest -Uri '%s' -OutFile '%s'", url, dest_path)
    }
  else
    return false, "No download tool found. Please install curl or wget."
  end
  
  -- Use vim.system if available (Neovim 0.10+), fallback to os.execute
  if vim.system then
    local result = vim.system(cmd_args, { text = true }):wait()
    if result.code == 0 then
      return true
    else
      local err_msg = result.stderr or result.stdout or "Unknown error"
      return false, string.format("Download failed: %s", err_msg)
    end
  else
    -- Fallback for older Neovim versions
    local cmd = table.concat(
      vim.tbl_map(function(arg)
        -- Basic escaping for shell
        return string.format("'%s'", arg:gsub("'", "'\\''"))
      end, cmd_args),
      " "
    )
    local exit_code = os.execute(cmd)
    if exit_code == true or exit_code == 0 then
      return true
    else
      return false, string.format("Download failed with exit code: %s", tostring(exit_code))
    end
  end
end

-- Install the library
function M.install(opts)
  opts = opts or {}
  local force = opts.force or false
  
  local plugin_root = get_plugin_root()
  local lib_path = plugin_root .. "/" .. get_lib_filename()
  
  -- Check if library already exists and is up-to-date
  if not force then
    if vim.fn.filereadable(lib_path) == 1 then
      -- Check if version matches
      local current_version = get_current_version()
      local installed_version = M.get_installed_version()
      
      if current_version and installed_version and current_version == installed_version then
        if not opts.silent then
          vim.notify("libvscode-diff already installed at: " .. lib_path, vim.log.levels.INFO)
        end
        return true
      elseif not opts.silent then
        vim.notify(string.format(
          "Updating libvscode-diff from v%s to v%s...",
          installed_version or "unknown",
          current_version or "unknown"
        ), vim.log.levels.INFO)
      end
    end
  end
  
  -- Detect platform
  local os_name = detect_os()
  local arch, arch_err = detect_arch()
  
  if not arch then
    local msg = "Failed to detect architecture: " .. (arch_err or "unknown error")
    vim.notify(msg, vim.log.levels.ERROR)
    return false, msg
  end
  
  if not opts.silent then
    vim.notify(
      string.format("Installing libvscode-diff for %s %s...", os_name, arch),
      vim.log.levels.INFO
    )
  end
  
  -- Build download URL
  local url, filename, url_err = build_download_url(os_name, arch)
  
  if not url then
    local msg = "Failed to build download URL: " .. (url_err or "unknown error")
    vim.notify(msg, vim.log.levels.ERROR)
    return false, msg
  end
  
  if not opts.silent then
    vim.notify("Downloading from: " .. url, vim.log.levels.INFO)
  end
  
  -- Download to temporary location first
  local temp_path = plugin_root .. "/" .. filename .. ".tmp"
  local success, err = download_file(url, temp_path)
  
  if not success then
    local msg = "Failed to download library: " .. (err or "unknown error")
    vim.notify(msg, vim.log.levels.ERROR)
    -- Clean up temp file if it exists
    os.remove(temp_path)
    return false, msg
  end
  
  -- Move to final location
  local ok = os.rename(temp_path, lib_path)
  if not ok then
    local msg = "Failed to move library to final location: " .. lib_path
    vim.notify(msg, vim.log.levels.ERROR)
    os.remove(temp_path)
    return false, msg
  end
  
  -- Save the version marker
  local current_version = get_current_version()
  if current_version then
    save_installed_version(current_version)
  end
  
  if not opts.silent then
    vim.notify("Successfully installed libvscode-diff!", vim.log.levels.INFO)
  end
  
  return true
end

-- Check if library is installed
function M.is_installed()
  local plugin_root = get_plugin_root()
  local lib_path = plugin_root .. "/" .. get_lib_filename()
  return vim.fn.filereadable(lib_path) == 1
end

-- Get library path
function M.get_lib_path()
  local plugin_root = get_plugin_root()
  return plugin_root .. "/" .. get_lib_filename()
end

-- Get the installed library version
function M.get_installed_version()
  local version_marker = get_plugin_root() .. "/.libvscode_diff_version"
  local f = io.open(version_marker, "r")
  if f then
    local version = f:read("*all")
    f:close()
    return version:match("^%s*(.-)%s*$")
  end
  return nil
end

-- Check if library needs update
function M.needs_update()
  if not M.is_installed() then
    return true
  end
  
  local current_version = get_current_version()
  local installed_version = M.get_installed_version()
  
  if not current_version or not installed_version then
    return true
  end
  
  return current_version ~= installed_version
end

return M
