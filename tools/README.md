# FnMacTweak Tooling

## Overview

This directory contains workflow automation and static patching tools for FnMacTweak.

## Tooling

### `fnmac.sh` — Workflow CLI

Main entry point for the entire development workflow.

```bash
# Build
./fnmac.sh build

# Clean
./fnmac.sh clean

# Rebuild
./fnmac.sh rebuild

# Install IPA
./fnmac.sh install <path/to/ipa.ipa>

# Deploy to running game (hot-reload)
./fnmac.sh redeploy <path/to/ipa.ipa>

# Launch game
./fnmac.sh launch

# Monitor game state
./fnmac.sh monitor

# Check loaded modules
./fnmac.sh status
```

### `patch_ipa.py` — Static IPA Patcher

Applies known binary patches directly into the IPA before installation.

```bash
python3 patch_ipa.py <input.ipa> -o <output.ipa>

# Examples
python3 patch_ipa.py com.epicgames.FortniteGame_40.40.1_und3fined.ipa -o Fortnite-40.40.1-patched.ipa
```

**Note:** This is now superseded by dynamic hooks in `src/Tweak.xm`, but kept
as a reference/fallback.

### `cleanup.sh` — Build Artifacts Cleaner

```bash
./cleanup.sh
```

Removes Theos build artifacts, temporary files, and stale cache.

## Quick Start

```bash
# 1. Build the tweak
THEOS=/Users/xnetcat/theos gmake

# 2. Verify build succeeded
ls .theos/obj/debug/

# 3. Deploy to running game
./fnmac.sh redeploy ~/Downloads/com.epicgames.FortniteGame_40.40.1_und3fined.ipa

# 4. Monitor
./fnmac.sh monitor
```

## Common Operations

### Full Rebuild

```bash
./fnmac.sh clean
THEOS=/Users/xnetcat/theos gmake
./fnmac.sh build
```

### Hot Reload (No Reinstall)

```bash
# 1. Build new tweak
THEOS=/Users/xnetcat/theos gmake

# 2. Hot reload into running game
./fnmac.sh redeploy ~/Downloads/com.epicgames.FortniteGame_40.40.1_und3fined.ipa

# 3. Verify load
vmmap <fortnite-pid> | grep FnMacTweak
```

### Debug Build

```bash
# Enable debug symbols
make TARGET=iphone:clang:latest:17.0 DEBUG=1

# This produces: .theos/obj/debug/FnMacTweak.dylib (debug)
#              .theos/obj/release/FnMacTweak.dylib (release)
```

## Architecture

```
tools/
├── fnmac.sh          # Main workflow CLI
├── patch_ipa.py      # Static IPA patcher (legacy)
├── cleanup.sh        # Build artifact cleaner
└── README.md         # This file
```

## Integration with cider

```bash
# After building, sign and install:
script -q /dev/null cider sign \
    --apple-id \
    --ellekit \
    --tweak .theos/obj/debug/FnMacTweak.dylib \
    --install \
    --mac

# Then lsregister:
"$LSREGISTER" -f -R /Applications/iOS/FortniteClient-IOS-Shipping.app

# Finally launch:
open -b com.epicgames.FortniteGame.7YU3P8HDSL
```

## Troubleshooting

### Tweak not loading?

```bash
# Check if minos matches
nm -gU .theos/obj/debug/FnMacTweak.dylib | grep -i "minos\|sdk\|runtime"

# Verify it's in the game process
vmmap <fortnite-pid> | grep FnMacTweak
```

### Hot reload not working?

```bash
# Ensure game is running
ps aux | grep "FortniteClient-IOS-Shipping"

# Check for zombie processes
lsof -p <fortnite-pid> | grep FnMacTweak
```

### Build artifacts not cleaning?

```bash
# Force clean
rm -rf .theos/obj/* .theos/dist/* .theos/tmp/*
```
