#!/bin/bash

# Setup GitHub Remote and Push
# Replace YOUR_GITHUB_USERNAME with your actual username

GITHUB_USERNAME="Ryandonofrio3"  # ⚠️ EDIT THIS!

echo "🔗 Setting up GitHub remote..."
git remote add origin "https://github.com/$GITHUB_USERNAME/Starling.git"

echo "📤 Pushing to GitHub..."
git push -u origin main

echo "✅ Done! Your code is now on GitHub."
echo "📍 Visit: https://github.com/$GITHUB_USERNAME/Starling"

