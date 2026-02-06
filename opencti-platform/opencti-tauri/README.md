# OpenCTI Desktop (Tauri)

Desktop application version of OpenCTI built with Tauri. This wraps the OpenCTI frontend and connects to an existing OpenCTI backend server.

## Architecture

```
┌─────────────────────────┐
│   OpenCTI Desktop       │  ← Tauri App (This Project)
│   (Rust + React)        │
└───────────┬─────────────┘
            │ HTTP/WebSocket
            ↓
┌─────────────────────────┐
│  OpenCTI Backend        │  ← Existing Server
│  (GraphQL API)          │
└─────────────────────────┘
```

## Prerequisites

- **Node.js** ≥ 20.0.0
- **Rust** (install via: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`)
- **System Dependencies**:
  - **macOS**: Xcode Command Line Tools
  - **Windows**: Microsoft C++ Build Tools
  - **Linux**: `libwebkit2gtk-4.1-dev`, `build-essential`, `libssl-dev`, `libayatana-appindicator3-dev`

### Linux Dependencies
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install libwebkit2gtk-4.1-dev build-essential curl wget file libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev

# Fedora
sudo dnf install webkit2gtk4.1-devel openssl-devel curl wget file libappindicator-gtk3-devel librsvg2-devel
sudo dnf group install "C Development Tools and Libraries"

# Arch
sudo pacman -Syu webkit2gtk-4.1 base-devel curl wget file openssl appmenu-gtk-module gtk3 libappindicator-gtk3 librsvg
```

## Development

### 1. Build the Frontend
```bash
cd opencti-platform/opencti-front
cp ../.yarnrc.yml .yarnrc.yml
yarn install
yarn build:standalone
```

### 2. Run Desktop App in Dev Mode
```bash
cd opencti-platform/opencti-tauri
yarn install
yarn dev
```

This will:
- Start the Tauri development window
- Load the frontend from `http://localhost:3000` (if opencti-front dev server is running)
- OR load from the built frontend in `../opencti-front/builder/prod/build`

**Note**: For dev mode with hot reload, run both:
```bash
# Terminal 1 - Frontend dev server
cd opencti-platform/opencti-front
yarn start

# Terminal 2 - Tauri dev mode
cd opencti-platform/opencti-tauri
yarn dev
```

## Building for Production

### Build for Current Platform
```bash
cd opencti-platform/opencti-tauri
yarn build
```

Output locations:
- **macOS**: `src-tauri/target/release/bundle/dmg/OpenCTI_*.dmg`
- **Windows**: `src-tauri/target/release/bundle/msi/OpenCTI_*.msi`
- **Linux**: `src-tauri/target/release/bundle/appimage/opencti-desktop_*.AppImage`

### Build for Specific Platforms

```bash
# macOS (DMG + App Bundle)
yarn tauri build --target universal-apple-darwin

# Windows (MSI)
yarn tauri build --target x86_64-pc-windows-msvc

# Linux (AppImage + DEB)
yarn tauri build --target x86_64-unknown-linux-gnu
```

### Debug Build (Faster)
```bash
yarn build:debug
```

## Configuration

### Server URL

The app will prompt for the OpenCTI server URL on first launch. You can also configure it via:

**Development**:
Edit `src-tauri/tauri.conf.json`:
```json
{
  "build": {
    "devUrl": "http://localhost:4000"  // Your backend URL
  }
}
```

**Production**:
Users configure via Settings → Server URL in the app.

### App Icons

Replace icons in `src-tauri/icons/`:
- `icon.icns` (macOS)
- `icon.ico` (Windows)
- `32x32.png`, `128x128.png`, `128x128@2x.png` (Linux)

Generate from a 1024x1024 PNG:
```bash
yarn tauri icon path/to/icon.png
```

## Features

### Desktop-Specific Features

- **Native File Dialogs**: Save/open files with OS dialogs
- **System Notifications**: Native desktop notifications
- **System Tray**: Quick access from menu bar/system tray
- **Auto Updates**: Built-in updater for new versions
- **Secure Storage**: Platform keychain integration
- **Offline Mode**: Local caching support

### Available Commands (from Frontend)

```typescript
import { invoke } from '@tauri-apps/api/core';

// Save export with native dialog
await invoke('save_export', {
  filename: 'report.pdf',
  content: [...] // Uint8Array
});

// Open file picker
const [filename, content] = await invoke('open_file');

// Show notification
await invoke('show_notification', {
  title: 'Alert',
  body: 'New threat detected'
});

// Get platform info
const info = await invoke('get_platform_info');
```

## Project Structure

```
opencti-tauri/
├── src-tauri/              # Rust backend
│   ├── src/
│   │   └── main.rs         # Entry point + IPC commands
│   ├── Cargo.toml          # Rust dependencies
│   ├── tauri.conf.json     # App configuration
│   ├── build.rs            # Build script
│   └── icons/              # App icons
├── package.json            # Node.js dependencies
└── README.md               # This file
```

## Troubleshooting

### "Failed to bundle project"
- Ensure Rust is installed: `rustc --version`
- Update Rust: `rustup update`
- Clean and rebuild: `cd src-tauri && cargo clean && cd .. && yarn build`

### "Webkit not found" (Linux)
```bash
sudo apt install libwebkit2gtk-4.1-dev
```

### App won't connect to backend
- Check backend URL in Settings
- Ensure backend is running and accessible
- Check CORS settings on backend allow desktop origin

### "Code signing failed" (macOS)
```bash
# For local testing, use:
yarn tauri build -- --target universal-apple-darwin -- --skip-code-sign
```

## Distribution

### macOS
1. Sign with Apple Developer certificate
2. Notarize the app: `xcrun notarytool submit`
3. Distribute DMG file

### Windows
1. Sign with code signing certificate (optional but recommended)
2. Distribute MSI installer

### Linux
- **AppImage**: No installation needed, portable
- **DEB**: For Debian/Ubuntu via `apt`
- **RPM**: For Fedora/RedHat via `dnf`

## Environment Variables

```bash
# Enable debug mode
TAURI_DEBUG=1 yarn dev

# Skip frontend build
TAURI_SKIP_DEVSERVER_CHECK=true yarn dev

# Custom frontend dist path
TAURI_FRONTEND_DIST=/path/to/dist yarn build
```

## Learn More

- [Tauri Documentation](https://tauri.app/)
- [Tauri API Reference](https://tauri.app/v2/reference/javascript/api/)
- [OpenCTI Documentation](https://docs.opencti.io/)

## License

Same as OpenCTI - See main repository LICENSE file.
