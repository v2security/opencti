# 🚀 OpenCTI Desktop - Quick Start Guide

## Step-by-Step Setup

### 1. Install Prerequisites

#### macOS
```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Install Xcode Command Line Tools (if not already)
xcode-select --install
```

#### Linux (Ubuntu/Debian)
```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Install system dependencies
sudo apt update
sudo apt install -y libwebkit2gtk-4.1-dev \
    build-essential \
    curl \
    wget \
    file \
    libssl-dev \
    libayatana-appindicator3-dev \
    librsvg2-dev
```

#### Windows
```powershell
# Install Rust
# Download from: https://rustup.rs/

# Install Microsoft C++ Build Tools
# Download from: https://visualstudio.microsoft.com/visual-cpp-build-tools/
# Select "Desktop development with C++" workload

# Install WebView2 (usually pre-installed on Windows 11)
# Download from: https://developer.microsoft.com/en-us/microsoft-edge/webview2/
```

### 2. Verify Installation

```bash
# Check Node.js
node --version  # Should be >= 20.0.0

# Check Rust
rustc --version  # Should show Rust version

# Check Cargo
cargo --version  # Should show Cargo version
```

### 3. First Time Build

```bash
# From repository root
cd opencti-platform

# Build the frontend first
cd opencti-front
cp ../.yarnrc.yml .yarnrc.yml
yarn install
yarn build:standalone

# Setup Tauri project
cd ../opencti-tauri
yarn install
```

### 4. Development Mode

#### Option A: With Frontend Hot Reload (Recommended for UI development)

```bash
# Terminal 1: Start frontend dev server
cd opencti-platform/opencti-front
yarn start

# Terminal 2: Start Tauri in dev mode
cd opencti-platform/opencti-tauri
yarn dev
```

This gives you hot reload - any changes to frontend code will automatically refresh!

#### Option B: Without Hot Reload (Faster startup)

```bash
cd opencti-platform/opencti-tauri
yarn dev
```

This loads the pre-built frontend from `../opencti-front/builder/prod/build`.

### 5. Build Production App

```bash
cd opencti-platform/opencti-tauri

# Make sure frontend is built
yarn prebuild

# Build for your current platform
yarn build
```

**Output locations:**
- **macOS**: `src-tauri/target/release/bundle/dmg/OpenCTI_6.9.16_universal.dmg`
- **Windows**: `src-tauri/target/release/bundle/msi/OpenCTI_6.9.16_x64_en-US.msi`
- **Linux**: `src-tauri/target/release/bundle/appimage/opencti-desktop_6.9.16_amd64.AppImage`

### 6. Test the App

After building, you can test by:

```bash
# macOS
open src-tauri/target/release/bundle/dmg/

# Windows
explorer src-tauri\target\release\bundle\msi\

# Linux
cd src-tauri/target/release/bundle/appimage/
./opencti-desktop_*.AppImage
```

## Common Issues & Solutions

### "Rust not found"
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

### "webkit2gtk not found" (Linux)
```bash
sudo apt install libwebkit2gtk-4.1-dev
```

### "Failed to resolve package"
```bash
cd opencti-platform/opencti-tauri
rm -rf node_modules yarn.lock
yarn install
```

### "Build failed" - Clean and retry
```bash
cd opencti-platform/opencti-tauri/src-tauri
cargo clean
cd ..
yarn build
```

### Frontend not loading in dev mode
Make sure the frontend dev server is running on `http://localhost:3000`:
```bash
cd opencti-platform/opencti-front
yarn start
```

## Using the Desktop App

### First Launch

1. Launch the application
2. Enter your OpenCTI server URL (e.g., `https://opencti.yourdomain.com`)
3. Login with your credentials
4. Enjoy the desktop experience!

### Desktop Features

- **Native File Dialogs**: Export/import uses system file dialogs
- **Notifications**: Native OS notifications for alerts
- **Offline Mode**: Data cached locally for offline access
- **Faster**: No browser overhead
- **Secure**: Encrypted local storage for tokens

### Keyboard Shortcuts

Same as web version, plus:
- **Cmd/Ctrl + Q**: Quit application
- **Cmd/Ctrl + W**: Close window
- **Cmd/Ctrl + M**: Minimize
- **Cmd/Ctrl + ,**: Open settings (coming soon)

## Development Tips

### Auto-reload on Rust changes
Tauri automatically recompiles Rust code when you save changes to `src-tauri/src/*.rs`

### Debug DevTools
In development mode, DevTools open automatically. In production:
- **macOS/Linux**: Right-click → "Inspect Element" (if enabled)
- **Windows**: Same as above

### Add new Rust commands

1. Add function in `src-tauri/src/main.rs`:
```rust
#[tauri::command]
fn my_command(arg: String) -> String {
    format!("Got: {}", arg)
}
```

2. Register in `invoke_handler!`:
```rust
.invoke_handler(tauri::generate_handler![
    // ... existing commands
    my_command
])
```

3. Call from frontend:
```typescript
import { invoke } from '@tauri-apps/api/core';
const result = await invoke('my_command', { arg: 'test' });
```

### Use platform utilities in frontend

```typescript
import { usePlatform } from '@/utils/platform';

function MyComponent() {
  const { isTauri, saveFile } = usePlatform();
  
  const handleExport = async () => {
    await saveFile('report.pdf', pdfData);
  };
  
  return isTauri ? <DesktopUI /> : <WebUI />;
}
```

## Next Steps

- [ ] Customize app icons (see Icon Guide below)
- [ ] Configure auto-updates
- [ ] Add code signing for distribution
- [ ] Create CI/CD pipeline for automated builds
- [ ] Test on all target platforms

## Icon Guide

### Generate Icons

Place a 1024x1024 PNG icon at `src-tauri/icon.png`, then run:

```bash
cd opencti-platform/opencti-tauri
yarn tauri icon icon.png
```

This generates all required icon sizes automatically!

### Manual Icon Setup

Replace these files in `src-tauri/icons/`:
- `icon.icns` - macOS icon (1024x1024)
- `icon.ico` - Windows icon (256x256)
- PNG files for Linux

## Distribution Checklist

Before distributing to users:

- [ ] Update version in `package.json` and `src-tauri/Cargo.toml`
- [ ] Test on target platforms
- [ ] Configure auto-updater endpoint
- [ ] Sign the application (macOS: Apple cert, Windows: Code signing cert)
- [ ] Test installation process
- [ ] Document server URL configuration for users
- [ ] Create release notes

## Getting Help

- **Tauri Docs**: https://tauri.app/
- **OpenCTI Docs**: https://docs.opencti.io/
- **Issues**: https://github.com/OpenCTI-Platform/opencti/issues

---

**Happy coding! 🎉**
