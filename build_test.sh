#!/bin/bash

# Build and Test Script for MacDynamicIsland
# This script validates the project can compile successfully

set -e  # Exit on error

echo "🚀 MacDynamicIsland Build Validation"
echo "=============================="
echo ""

PROJECT_PATH="MacDynamicIsland.xcodeproj"
SCHEME="MacDynamicIsland"
CONFIGURATION="Debug"
DESTINATION="platform=macOS"

echo "📋 Project: $PROJECT_PATH"
echo "📋 Scheme: $SCHEME"
echo "📋 Configuration: $CONFIGURATION"
echo ""

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Error: xcodebuild not found"
    echo "Please install Xcode and Command Line Tools"
    exit 1
fi

echo "✅ Xcode found"
echo ""

# Clean build folder
echo "🧹 Cleaning build folder..."
xcodebuild clean -project "$PROJECT_PATH" -scheme "$SCHEME" -configuration "$CONFIGURATION" > /dev/null 2>&1
echo "✅ Clean complete"
echo ""

# Build project
echo "🔨 Building project..."
echo "This may take a few minutes..."
echo ""

BUILD_LOG=$(mktemp)

if xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    build 2>&1 | tee "$BUILD_LOG"; then
    
    echo ""
    echo "=============================="
    echo "✅ BUILD SUCCESSFUL!"
    echo "=============================="
    echo ""
    
    # Count warnings
    WARNING_COUNT=$(grep -c "warning:" "$BUILD_LOG" || true)
    ERROR_COUNT=$(grep -c "error:" "$BUILD_LOG" || true)
    
    echo "📊 Build Statistics:"
    echo "   - Errors: $ERROR_COUNT"
    echo "   - Warnings: $WARNING_COUNT"
    echo ""
    
    if [ "$WARNING_COUNT" -gt 0 ]; then
        echo "⚠️  Found $WARNING_COUNT warnings"
        echo "Review them in the build log"
    fi
    
    rm -f "$BUILD_LOG"
    exit 0
else
    echo ""
    echo "=============================="
    echo "❌ BUILD FAILED"
    echo "=============================="
    echo ""
    
    # Show last 50 lines of build log
    echo "📋 Last 50 lines of build log:"
    echo ""
    tail -n 50 "$BUILD_LOG"
    
    rm -f "$BUILD_LOG"
    exit 1
fi
