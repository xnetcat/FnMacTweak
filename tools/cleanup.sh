#!/bin/bash
# FnMacTweak Cleanup Script
# Cleans up build artifacts and temporary files

set -e

THEOS="${THEOS:-/Users/xnetcat/theos}"
OBJ_DIR=".theos/obj"
DIST_DIR=".theos/dist"
TMP_DIR=".theos/tmp"

echo "=== FnMacTweak Cleanup ==="
echo "THEOS: $THEOS"
echo ""

# Clean Theos build artifacts
echo "Cleaning Theos build artifacts..."
if [ -d "$OBJ_DIR" ]; then
    rm -rf "$OBJ_DIR"/*
    echo "  ✓ Cleared $OBJ_DIR"
fi

if [ -d "$DIST_DIR" ]; then
    rm -rf "$DIST_DIR"/*
    echo "  ✓ Cleared $DIST_DIR"
fi

if [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"/*
    echo "  ✓ Cleared $TMP_DIR"
fi

# Clean git submodules if needed
echo ""
echo "Cleaning git submodules..."
if [ -d ".git/modules" ]; then
    # Remove stale submodule objects
    find .git/modules -name "*.cache" -type f -exec rm -rf {} \; 2>/dev/null || true
    find .git/modules -name "*.lock" -type f -delete 2>/dev/null || true
    echo "  ✓ Cleaned submodule cache"
fi

# Clean node modules if present
echo ""
echo "Cleaning node modules..."
if [ -d "node_modules" ]; then
    echo "  ✓ Found node_modules (remove manually if needed)"
    echo "  Run: rm -rf node_modules"
fi

# Show disk space reclaimed
echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "To rebuild:"
echo "  THEOS=$THEOS gmake"
echo ""
echo "To clean from scratch:"
echo "  rm -rf .theos/obj/* .theos/dist/* .theos/tmp/*"
