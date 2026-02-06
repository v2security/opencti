#!/bin/bash
# Development helper script for OpenCTI Desktop

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

check_dependencies() {
    print_info "Checking prerequisites..."
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        print_error "Node.js not found. Please install Node.js >= 20.0.0"
        exit 1
    fi
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 20 ]; then
        print_error "Node.js version must be >= 20.0.0 (found: $(node --version))"
        exit 1
    fi
    print_success "Node.js $(node --version)"
    
    # Check Rust
    if ! command -v rustc &> /dev/null; then
        print_error "Rust not found. Install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        exit 1
    fi
    print_success "Rust $(rustc --version)"
    
    # Check Cargo
    if ! command -v cargo &> /dev/null; then
        print_error "Cargo not found. Rust installation may be incomplete."
        exit 1
    fi
    print_success "Cargo $(cargo --version)"
    
    # Platform-specific checks
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if ! pkg-config --exists webkit2gtk-4.1; then
            print_warning "webkit2gtk-4.1 not found. You may need to install it:"
            echo "  sudo apt install libwebkit2gtk-4.1-dev"
        fi
    fi
}

build_frontend() {
    print_info "Building frontend..."
    cd "$PROJECT_ROOT/opencti-front"
    
    if [ ! -f ".yarnrc.yml" ]; then
        print_info "Copying .yarnrc.yml..."
        cp ../.yarnrc.yml .yarnrc.yml
    fi
    
    if [ ! -d "node_modules" ]; then
        print_info "Installing frontend dependencies..."
        yarn install
    fi
    
    print_info "Building frontend (this may take a few minutes)..."
    yarn build:standalone
    print_success "Frontend built successfully"
}

setup_tauri() {
    print_info "Setting up Tauri project..."
    cd "$SCRIPT_DIR"
    
    if [ ! -d "node_modules" ]; then
        print_info "Installing Tauri dependencies..."
        yarn install
    fi
    
    print_success "Tauri project ready"
}

dev_mode() {
    print_info "Starting development mode..."
    print_warning "Make sure the frontend dev server is running on http://localhost:3000"
    print_info "If not, run: cd opencti-platform/opencti-front && yarn start"
    echo ""
    
    cd "$SCRIPT_DIR"
    yarn dev
}

build_app() {
    print_info "Building production application..."
    
    # Build frontend first
    build_frontend
    
    # Build Tauri
    cd "$SCRIPT_DIR"
    print_info "Building Tauri app (this may take several minutes)..."
    yarn build
    
    print_success "Build complete!"
    echo ""
    print_info "Output location:"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  📦 $(ls src-tauri/target/release/bundle/dmg/*.dmg 2>/dev/null || echo 'Check src-tauri/target/release/bundle/')"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "  📦 $(ls src-tauri/target/release/bundle/appimage/*.AppImage 2>/dev/null || echo 'Check src-tauri/target/release/bundle/')"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        echo "  📦 Check src-tauri/target/release/bundle/msi/"
    fi
}

clean_build() {
    print_info "Cleaning build artifacts..."
    cd "$SCRIPT_DIR"
    
    if [ -d "src-tauri/target" ]; then
        print_info "Removing Rust build cache..."
        rm -rf src-tauri/target
    fi
    
    if [ -d "node_modules" ]; then
        print_info "Removing node_modules..."
        rm -rf node_modules
    fi
    
    print_success "Clean complete"
}

print_usage() {
    cat << EOF
${GREEN}OpenCTI Desktop - Development Helper${NC}

Usage: ./dev.sh [command]

Commands:
  ${BLUE}check${NC}       Check prerequisites
  ${BLUE}setup${NC}       Initial setup (install dependencies)
  ${BLUE}dev${NC}         Start development mode
  ${BLUE}build${NC}       Build production app
  ${BLUE}clean${NC}       Clean build artifacts
  ${BLUE}help${NC}        Show this help message

Examples:
  ./dev.sh setup     # First time setup
  ./dev.sh dev       # Start development
  ./dev.sh build     # Build for distribution

EOF
}

# Main script
case "${1:-help}" in
    check)
        check_dependencies
        ;;
    setup)
        check_dependencies
        build_frontend
        setup_tauri
        print_success "Setup complete! Run './dev.sh dev' to start development"
        ;;
    dev)
        check_dependencies
        dev_mode
        ;;
    build)
        check_dependencies
        build_app
        ;;
    clean)
        clean_build
        ;;
    help|--help|-h)
        print_usage
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        print_usage
        exit 1
        ;;
esac
