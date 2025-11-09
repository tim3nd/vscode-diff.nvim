# Automatic Library Installation System

This document describes the automatic installation system for the libvscode-diff C library.

## Overview

The automatic installation system downloads pre-built binaries from GitHub releases, eliminating the need for users to have a compiler installed. The system automatically detects the user's platform (OS and architecture) and downloads the appropriate binary.

## Architecture

### Components

1. **`lua/vscode-diff/installer.lua`**
   - Platform detection
   - Download management
   - VERSION file parsing
   - Error handling

2. **`lua/vscode-diff/diff.lua`**
   - Triggers auto-installation before FFI load
   - Provides fallback error messages

3. **`:CodeDiffInstall` command**
   - Manual installation/reinstallation
   - Defined in `lua/vscode-diff/commands.lua`
   - Registered in `plugin/vscode-diff.lua`

### Flow Diagram

```
Plugin Load
    ↓
diff.lua requires installer
    ↓
Check if library exists? → YES → Load with FFI ✓
    ↓ NO
installer.install()
    ↓
Detect OS (Linux/Windows/macOS)
    ↓
Detect Architecture (x64/arm64)
    ↓
Read VERSION file
    ↓
Build download URL:
https://github.com/esmuellert/vscode-diff.nvim/releases/download/v{VERSION}/libvscode_diff_{os}_{arch}_{version}.{ext}
    ↓
Download with: curl → wget → PowerShell
    ↓
Save as: libvscode_diff.{so|dylib|dll}
    ↓
Load with FFI ✓
```

## Platform Detection

### Operating System

Detected using `ffi.os`:
- `Windows` → `"windows"`
- `OSX` → `"macos"`
- Other → `"linux"`

### Architecture

Detected using `vim.loop.os_uname().machine`:
- `x86_64`, `amd64`, `x64` → `"x64"`
- `aarch64`, `arm64` → `"arm64"`

### Library Extensions

- Windows: `.dll`
- macOS: `.dylib`
- Linux: `.so`

## Version Management

The system reads the `VERSION` file in the plugin root to determine which library version to download. This ensures compatibility between the Lua code and C library.

**VERSION file format:**
```
0.8.0
```

**Download URL construction:**
```lua
local url = string.format(
  "https://github.com/esmuellert/vscode-diff.nvim/releases/download/v%s/%s",
  version,  -- e.g., "0.8.0"
  filename  -- e.g., "libvscode_diff_linux_x64_0.8.0.so"
)
```

## Download Methods

The installer tries multiple download methods in order:

1. **curl** (preferred)
   ```lua
   { "curl", "-fsSL", "-o", dest_path, url }
   ```

2. **wget** (fallback)
   ```lua
   { "wget", "-q", "-O", dest_path, url }
   ```

3. **PowerShell** (Windows fallback)
   ```lua
   {
     "powershell", "-NoProfile", "-Command",
     "Invoke-WebRequest -Uri 'url' -OutFile 'dest_path'"
   }
   ```

## Security Considerations

### Command Execution

- **Neovim 0.10+**: Uses `vim.system()` with argument arrays (no shell injection)
- **Older versions**: Falls back to `os.execute()` with proper shell escaping

### Escaping Strategy

For `os.execute()` fallback:
```lua
local escaped = arg:gsub("'", "'\\''")  -- Escape single quotes
local cmd = string.format("'%s'", escaped)
```

### HTTPS Only

All downloads are performed over HTTPS from GitHub's trusted domain:
```
https://github.com/esmuellert/vscode-diff.nvim/releases/download/...
```

## Error Handling

### Missing VERSION File

```
Failed to build download URL: Failed to read VERSION file at: /path/to/VERSION
```

**Solution:** Ensure VERSION file exists in plugin root.

### No Download Tool

```
No download tool found. Please install curl or wget.
```

**Solution:** Install curl or wget (or use PowerShell on Windows).

### Download Failure

```
Download failed: [error details]
```

**Troubleshooting:**
1. Check internet connectivity
2. Verify access to github.com
3. Check if release exists for your platform
4. Try manual install: `:CodeDiff install!`
5. Try building from source

## Automatic Updates

The installer automatically detects version mismatches between the installed library and the VERSION file:

1. On plugin load, it checks if the library version matches the VERSION file
2. If versions don't match, it automatically downloads the correct version
3. A version marker file (`.libvscode_diff_version`) tracks the installed version

**Update Flow:**
```
Plugin loads → Check .libvscode_diff_version → Compare with VERSION file
  ↓
Version mismatch? → Download new version → Update .libvscode_diff_version
  ↓
Version matches? → Use existing library
```

This ensures users always have the correct library version without manual intervention when they update the plugin.

## Manual Installation Commands

### `:CodeDiff install`

Installs or updates the library to match the VERSION file.

**Usage:**
```vim
:CodeDiff install
```

### `:CodeDiff install!`

Forces reinstallation, even if library already exists and version matches.

**Usage:**
```vim
:CodeDiff install!
```

**Use cases:**
- Troubleshooting corrupted library
- Forcing a clean reinstall
- Testing installation process

## Supported Platforms

| OS | Architecture | File Extension | Example Filename |
|----|--------------|----------------|------------------|
| Linux | x64 | .so | `libvscode_diff_linux_x64_0.8.0.so` |
| Linux | arm64 | .so | `libvscode_diff_linux_arm64_0.8.0.so` |
| macOS | x64 | .dylib | `libvscode_diff_macos_x64_0.8.0.dylib` |
| macOS | arm64 | .dylib | `libvscode_diff_macos_arm64_0.8.0.dylib` |
| Windows | x64 | .dll | `libvscode_diff_windows_x64_0.8.0.dll` |
| Windows | arm64 | .dll | `libvscode_diff_windows_arm64_0.8.0.dll` |

## Testing

### Manual Testing

1. Remove existing library:
   ```bash
   rm libvscode_diff.*
   ```

2. Load plugin (triggers auto-install):
   ```vim
   nvim
   :lua require('vscode-diff.diff')
   ```

3. Verify installation:
   ```bash
   ls -lh libvscode_diff.*
   ```

### Automated Testing

See `/tmp/test_install.lua` and `/tmp/comprehensive_test.lua` for test scripts.

## Maintenance

### Updating Supported Versions

1. Update VERSION file:
   ```bash
   echo "0.9.0" > VERSION
   ```

2. Ensure GitHub release exists with all 6 platform binaries

3. Users will automatically download new version on next install

### Adding New Platforms

To add support for a new platform:

1. Update `detect_os()` or `detect_arch()` in `installer.lua`
2. Update `get_lib_ext()` if new extension needed
3. Ensure GitHub Actions builds for new platform
4. Update documentation

## Future Improvements

- [ ] Add checksum verification for downloaded files
- [ ] Cache downloads to avoid re-downloading on reinstall
- [ ] Add progress indicator for large downloads
- [ ] Support proxy configuration
- [ ] Add retry logic for failed downloads
- [ ] Implement version compatibility checking
