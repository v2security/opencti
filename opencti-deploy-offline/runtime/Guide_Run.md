# Runtime Installation Guide

## Files

| File | Mô tả |
|------|-------|
| `python312.tar.gz` | Python 3.12 compiled runtime (~50MB) |
| `nodejs22.tar.gz` | Node.js 22 pre-built binary (~30MB) |
| `v2_install_python.sh` | Install Python 3.12 → /opt/python312 |
| `v2_install_nodejs.sh` | Install Node.js 22 → /opt/nodejs |

## Usage (First Boot)

```bash
cd /path/to/runtime/

# Install Python 3.12
bash v2_install_python.sh

# Install Node.js 22
bash v2_install_nodejs.sh
```

## Output

### Python 3.12
```
/opt/python312/
├── bin/
│   ├── python3.12
│   ├── pip3.12
│   └── python3
├── lib/
│   ├── libpython3.12.so
│   └── python3.12/
└── include/

Symlinks:
/usr/local/bin/python3.12 → /opt/python312/bin/python3.12
/usr/local/bin/pip3.12 → /opt/python312/bin/pip3.12
```

### Node.js 22
```
/opt/nodejs/
├── bin/
│   ├── node
│   ├── npm
│   └── npx
├── lib/
│   └── node_modules/
└── include/

Symlinks:
/usr/local/bin/node → /opt/nodejs/bin/node
/usr/local/bin/npm → /opt/nodejs/bin/npm
/usr/local/bin/npx → /opt/nodejs/bin/npx
```

## Test

```bash
# Python
/opt/python312/bin/python3.12 --version
/opt/python312/bin/pip3.12 --version

# Node.js
/opt/nodejs/bin/node --version
/opt/nodejs/bin/npm --version
```

## Build (trên máy có internet)

```bash
# Build Python 3.12 (trong Docker)
bash scripts/01-build-python.sh
# Output: files/python312.tar.gz

# Build Node.js 22 (download pre-built)
bash scripts/02-build-nodejs.sh
# Output: files/nodejs22.tar.gz

# Di chuyển vào runtime/
mv files/python312.tar.gz files/nodejs22.tar.gz runtime/
```
