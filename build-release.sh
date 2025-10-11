#!/bin/bash

# Build Starling for Release
# This creates a Release build and exports the .app

set -e  # Exit on error

echo "🏗️  Building Starling in Release mode..."

# Clean build folder
rm -rf build/

# Build for release
xcodebuild \
  -project Starling.xcodeproj \
  -scheme Starling \
  -configuration Release \
  -derivedDataPath build/ \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

echo "📦 App built successfully!"

# Find the built app
APP_PATH=$(find build -name "Starling.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Could not find Starling.app"
    exit 1
fi

echo "📍 App location: $APP_PATH"

# Copy to a clean location
mkdir -p release
cp -R "$APP_PATH" release/

echo "✅ Release build ready at: release/Starling.app"
echo ""
echo "Next steps:"
echo "1. Test the app: open release/Starling.app"
echo "2. If it works, run: ./package-release.sh"

