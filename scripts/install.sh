#!/bin/bash
# SoloFan Quick Installation Script
# Usage: curl -fsSL https://raw.githubusercontent.com/mohamadlounnas/ffan/main/scripts/install.sh | bash

set -e

REPO="mohamadlounnas/ffan"
APP_NAME="SoloFan"

echo "🌬️  SoloFan Installation"
echo "========================"
echo ""

LATEST_TAG=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_TAG" ]; then
    echo "❌ Failed to fetch latest version"
    exit 1
fi

VERSION="${LATEST_TAG#v}"
ARCHIVE="solofan-v${VERSION}-macos.zip"

# Private temp dir: fixed names in shared /tmp can be pre-planted by other users.
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "📥 Downloading SoloFan ${LATEST_TAG}..."
curl -fL "https://github.com/${REPO}/releases/download/${LATEST_TAG}/${ARCHIVE}" -o "${WORK_DIR}/${ARCHIVE}"

echo "📦 Extracting..."
unzip -q "${WORK_DIR}/${ARCHIVE}" -d "$WORK_DIR"

echo "🔏 Verifying signature..."
# curl downloads carry no quarantine flag, so Gatekeeper would never check this
# app on launch. Require a valid Developer ID signature and notarization here.
spctl --assess --type execute "${WORK_DIR}/${APP_NAME}.app"

echo "🔄 Installing to /Applications..."
rm -rf "/Applications/${APP_NAME}.app"
mv "${WORK_DIR}/${APP_NAME}.app" /Applications/

echo ""
echo "✅ Installation complete!"
echo "🚀 Launching SoloFan... click \"Install Helper\" in the app to enable fan control."
echo ""

open "/Applications/${APP_NAME}.app"
