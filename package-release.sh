#!/bin/bash

# Package Starling for Distribution
# Creates a zip file and calculates SHA256 hash

set -e

VERSION="0.1.0-alpha"

if [ ! -d "release/Starling.app" ]; then
    echo "❌ release/Starling.app not found. Run ./build-release.sh first!"
    exit 1
fi

echo "📦 Packaging Starling v$VERSION..."

# Create zip in release folder
cd release
zip -r "Starling-v${VERSION}.zip" Starling.app -x "*.DS_Store"
cd ..

ZIP_FILE="release/Starling-v${VERSION}.zip"

echo "✅ Created: $ZIP_FILE"
echo ""
echo "📊 File info:"
ls -lh "$ZIP_FILE"
echo ""
echo "🔐 SHA256 Hash (for Homebrew):"
shasum -a 256 "$ZIP_FILE"
echo ""
echo "📤 Next steps:"
echo "1. Test the app works: unzip and open it"
echo "2. Upload $ZIP_FILE to GitHub Releases"
echo "3. Share the download link with your alpha users!"

