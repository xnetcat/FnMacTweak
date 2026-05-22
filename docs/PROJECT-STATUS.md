# FnMacTweak — Project Status

**Date:** 2026-05-22
**Version:** 4.0.1 (development)

---

## Quick Status

| Component | Status | Notes |
|-----------|--------|-------|
| Build System | ✅ Working | minos-26 bug fixed |
| Tweak Loading | ✅ Verified | `vmmap` shows loaded |
| macOS Compat Hooks | ✅ Dynamic | Offset-free |
| Workflow Tooling | ✅ Complete | `fnmac.sh` CLI |
| Match Join | ✅ Reaches ~40s | No client errors |
| Online Play | 🔄 In Progress | Anti-cheat investigation |
| Reverse Engineering | 🔄 Phase 1 | Symbol extraction |

---

## Current State

### Code Changes (Committed)

```bash
git log --oneline -5
a19c261 fix: macOS 26.4 crash — hook _availability_version_check for iOS 17.4 (#5)
0ef015a feat: FnMacTweak v4.0.0 — Controller & Typing Update 🎮⌨️
```

**Latest commit (in progress):**
```
1e50922 feat: narrow _availability_version_check hook to MarketplaceKitWrapper only
```

### Key Files Modified

1. **`Makefile`** — `TARGET` iOS 26.0 → 17.0
2. **`src/Tweak.xm`** — Extended `_availability_version_check` hook
3. **`tools/fnmac.sh`** — Main workflow CLI
4. **`tools/patch_ipa.py`** — Static IPA patcher (reference)
5. **`docs/handoff-prompt.md`** — Reverse engineering guide
6. **`docs/investigation-report.md`** — Investigation findings

---

## Next Steps

### Phase 1: Narrow Hook Test (Immediate)

```bash
# 1. Verify clean state
git status

# 2. Rebuild and redeploy
./tools/fnmac.sh clean
./tools/fnmac.sh build
./tools/fnmac.sh redeploy ~/Downloads/com.epicgames.FortniteGame_40.40.1_und3fined.ipa

# 3. Launch and test
./tools/fnmac.sh launch

# 4. Monitor for kick
./tools/fnmac.sh monitor
```

**Expected outcome:**
- **Kick stops** → Confirmed: overly-broad hook
- **Still kicks** → Proceed to reverse engineering (Phase 2)

### Phase 2: Reverse Engineering (After narrow hook test)

See `docs/handoff-prompt.md` for detailed guide.

**Quick start:**
```bash
# Extract symbols
nm -gU -D com.epicgames.FortniteGame_40.40.1_und3fined.ipa | grep -iE "anticheat|pak|hash"

# Extract strings
strings -t d -e d com.epicgames.FortniteGame_40.40.1_und3fined.ipa | grep -iE "Epic|Fortnite|client"
```

### Phase 3: Integration

Once the fix is identified:

```bash
# 1. Update Tweak.xm with the fix
# 2. Rebuild
# 3. Test in match
# 4. Commit and push
```

---

## Tooling Summary

### CLI Workflow

```bash
./tools/fnmac.sh <command>

Commands:
  build      — Build tweak
  clean      — Clean artifacts
  patch      — Static IPA patch (legacy)
  install    — Sign and install with cider
  launch     — Launch game
  status     — Check loaded modules
  logs       — Tail game logs
  monitor    — Monitor for kick
  redeploy   — Hot reload tweak
```

### Build Commands

```bash
# Debug build
THEOS=/Users/xnetcat/theos gmake DEBUG=1

# Release build
THEOS=/Users/xnetcat/theos gmake

# Clean
rm -rf .theos/obj/* .theos/dist/* .theos/tmp/*
```

---

## File Structure

```
FnMacTweak/
├── src/
│   ├── Tweak.xm              # Main tweak code (updated)
│   ├── FnOverlayWindow.m
│   ├── views/                # UI components
│   └── lib/
│       └── fishhook.c        # Fishhook library
│
├── tools/
│   ├── fnmac.sh              # Main workflow CLI
│   ├── patch_ipa.py          # Static IPA patcher
│   ├── cleanup.sh            # Build artifact cleaner
│   └── README.md             # Tooling docs
│
├── docs/
│   ├── PROJECT-STATUS.md     # This file
│   ├── HANDOFF.md            # Quick reference
│   ├── handoff-prompt.md     # Reverse engineering guide
│   └── investigation-report.md  # Investigation findings
│
├── Makefile                  # Build config
├── .gitignore
└── .gitmodules               # Submodules (Theos)
```

---

## Repository Info

```bash
# Current branch
git branch

# Remote info
git remote -v

# Latest commit
git log --oneline -1

# Files changed
git status --short
```

---

## Quick Reference

### Check if tweak is loaded

```bash
# Find Fortnite process
ps aux | grep "FortniteClient-IOS-Shipping"

# Check for loaded tweak
vmmap <pid> | grep FnMacTweak
```

### Monitor game logs

```bash
# Tail logs in real-time
cd ~/Library/Containers/$(grep -l "FortniteGame.log" ~/Library/Containers/*/Data/Documents/FortniteGame/Saved/Logs/ 2>/dev/null | head -1 | xargs dirname)/Data/Documents/FortniteGame/Saved/Logs/
tail -f FortniteGame.log
```

### Verify build artifacts

```bash
ls -la .theos/obj/debug/
# Should show: FnMacTweak.dylib (debug)
ls -la .theos/obj/release/
# Should show: FnMacTweak.dylib (release)
```

---

## Support / Discussion

- **GitHub:** https://github.com/KohlerVG/FnMacTweak
- **Issues:** https://github.com/KohlerVG/FnMacTweak/issues

---

*Last updated: 2026-05-22*
