#!/bin/bash

echo "🧹 Cleaning up all Starling app state..."

# Kill any running instances
echo "1. Killing any running Starling instances..."
killall Starling 2>/dev/null && echo "   ✓ Killed running app" || echo "   ✓ No running instances"

# Clear preferences (onboarding state)
echo "2. Clearing app preferences..."
defaults delete com.starling.app 2>/dev/null && echo "   ✓ Preferences cleared" || echo "   ✓ No preferences found"

# Clear app caches
echo "3. Clearing app cache..."
rm -rf ~/Library/Caches/com.starling.app 2>/dev/null && echo "   ✓ App cache cleared" || echo "   ✓ No app cache"

# Clear FluidAudio model cache (to test model download)
echo "4. Clearing FluidAudio model cache..."
read -p "   ⚠️  Clear 2.5GB FluidAudio cache? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf ~/Library/Caches/FluidAudio 2>/dev/null && echo "   ✓ FluidAudio cache cleared" || echo "   ✓ No FluidAudio cache"
else
    echo "   ⏭️  Skipped FluidAudio cache (will test with existing model)"
fi

echo ""
echo "✅ Fresh user setup complete!"
echo ""
echo "🚀 Now launching the app..."
echo "   Watch for:"
echo "   • Onboarding window should appear"
echo "   • NO microphone permission loops"
echo "   • NO model loading during onboarding"
echo "   • Model should only warm up AFTER onboarding"
echo ""

sleep 2
open release/Starling.app

echo ""
echo "👀 Monitoring app logs (press Ctrl+C to stop)..."
sleep 1
log stream --predicate 'subsystem == "com.starling.app"' --level debug

