@echo off
REM Development helper script for OpenCTI Desktop (Windows)

setlocal enabledelayedexpansion

REM Colors (limited support in cmd)
set "INFO=[INFO]"
set "SUCCESS=[OK]"
set "ERROR=[ERROR]"
set "WARNING=[WARN]"

:check_dependencies
echo %INFO% Checking prerequisites...

where node >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo %ERROR% Node.js not found. Please install Node.js ^>= 20.0.0
    exit /b 1
)
echo %SUCCESS% Node.js found

where rustc >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo %ERROR% Rust not found. Install from: https://rustup.rs/
    exit /b 1
)
echo %SUCCESS% Rust found

where cargo >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo %ERROR% Cargo not found. Rust installation may be incomplete.
    exit /b 1
)
echo %SUCCESS% Cargo found

goto :eof

:build_frontend
echo %INFO% Building frontend...
cd ..\opencti-front

if not exist ".yarnrc.yml" (
    echo %INFO% Copying .yarnrc.yml...
    copy ..\.yarnrc.yml .yarnrc.yml
)

if not exist "node_modules" (
    echo %INFO% Installing frontend dependencies...
    call yarn install
)

echo %INFO% Building frontend...
call yarn build:standalone
echo %SUCCESS% Frontend built successfully
cd ..\opencti-tauri
goto :eof

:setup_tauri
echo %INFO% Setting up Tauri project...

if not exist "node_modules" (
    echo %INFO% Installing Tauri dependencies...
    call yarn install
)

echo %SUCCESS% Tauri project ready
goto :eof

:dev_mode
echo %INFO% Starting development mode...
echo %WARNING% Make sure the frontend dev server is running on http://localhost:3000
echo %INFO% If not, run: cd opencti-platform\opencti-front ^&^& yarn start
echo.
call yarn dev
goto :eof

:build_app
echo %INFO% Building production application...

call :build_frontend

echo %INFO% Building Tauri app...
call yarn build

echo %SUCCESS% Build complete!
echo.
echo %INFO% Output location:
dir /b src-tauri\target\release\bundle\msi\*.msi 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo Check src-tauri\target\release\bundle\
)
goto :eof

:clean_build
echo %INFO% Cleaning build artifacts...

if exist "src-tauri\target" (
    echo %INFO% Removing Rust build cache...
    rmdir /s /q src-tauri\target
)

if exist "node_modules" (
    echo %INFO% Removing node_modules...
    rmdir /s /q node_modules
)

echo %SUCCESS% Clean complete
goto :eof

:print_usage
echo.
echo OpenCTI Desktop - Development Helper
echo.
echo Usage: dev.bat [command]
echo.
echo Commands:
echo   check       Check prerequisites
echo   setup       Initial setup (install dependencies)
echo   dev         Start development mode
echo   build       Build production app
echo   clean       Clean build artifacts
echo   help        Show this help message
echo.
echo Examples:
echo   dev.bat setup     # First time setup
echo   dev.bat dev       # Start development
echo   dev.bat build     # Build for distribution
echo.
goto :eof

REM Main script
set "COMMAND=%~1"
if "%COMMAND%"=="" set "COMMAND=help"

if "%COMMAND%"=="check" (
    call :check_dependencies
) else if "%COMMAND%"=="setup" (
    call :check_dependencies
    if !ERRORLEVEL! EQU 0 (
        call :build_frontend
        call :setup_tauri
        echo %SUCCESS% Setup complete! Run 'dev.bat dev' to start development
    )
) else if "%COMMAND%"=="dev" (
    call :check_dependencies
    if !ERRORLEVEL! EQU 0 call :dev_mode
) else if "%COMMAND%"=="build" (
    call :check_dependencies
    if !ERRORLEVEL! EQU 0 call :build_app
) else if "%COMMAND%"=="clean" (
    call :clean_build
) else if "%COMMAND%"=="help" (
    call :print_usage
) else (
    echo %ERROR% Unknown command: %COMMAND%
    echo.
    call :print_usage
    exit /b 1
)
