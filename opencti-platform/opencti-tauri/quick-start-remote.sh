#!/bin/bash
# Quick start script for OpenCTI Desktop with remote backend

set -e

echo "🚀 Building OpenCTI Desktop for remote backend..."
echo "Backend: http://163.223.58.7:8080"
echo ""

# Step 1: Build frontend
echo "📦 Step 1/2: Building frontend (this takes ~5 minutes)..."
cd /Volumes/Vault/Code/Vx/opencti/opencti-platform/opencti-front

if [ ! -f ".yarnrc.yml" ]; then
    cp ../.yarnrc.yml .yarnrc.yml
fi

if [ ! -d "node_modules" ]; then
    echo "Installing frontend dependencies..."
    yarn install
fi

echo "Building frontend..."
yarn build:standalone

# Step 2: Run Tauri
echo ""
echo "✅ Step 2/2: Starting desktop app..."
cd ../opencti-tauri
yarn dev

echo ""
echo "🎉 Done! The desktop app should open shortly."
echo "It will connect to: http://163.223.58.7:8080"
echo "API Token: ff91eda6-7317-4de3-96a3-5f8b7cc4a01f"
