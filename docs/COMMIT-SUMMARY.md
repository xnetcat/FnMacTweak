# FnMacTweak — Session Summary

**Date:** 2026-05-22
**Session:** Post-4.0.0 development / Anti-cheat investigation

---

## Git History

```
b2c6f8e (HEAD -> main) docs: update project documentation and tooling
1e50922 feat: narrow _availability_version_check hook to MKW only
a19c261 fix: macOS 26.4 crash — hook _availability_version_check for iOS 17.4
0ef015a tag: 4.0.0  feat: FnMacTweak v4.0.0 — Controller & Typing Update 🎮⌨️
b5e50a7 tag: 3.0.0  v3.0.0 — Borderless mode, mouse button support...
3feb0f6 tag: 2.0.4  v2.0.4 — Smoother mouse, BUILD mode stuck fire fix
c6acbb8 docs: clarify project authorship and detail major overhaul features
```

---

## Commit Breakdown

### b2c6f8e — Documentation & Tooling Update

**Purpose:** Enhanced project documentation and added utility scripts.

**Files:**
- `docs/handoff-prompt.md` — Rewritten with reverse engineering focus
- `docs/investigation-report.md` — Updated status sections
- `tools/cleanup.sh` — New build artifact cleaner
- `tools/README.md` — Updated tooling documentation
- `docs/PROJECT-STATUS.md` — New quick reference
- `docs/HANDOFF.md` — Quick reference document

**Key Additions:**
- Phase 5: Reverse Engineering (symbol/section analysis)
- Phase 6: Dynamic Analysis (Frida, network capture)
- Phase 9: Cleanup & Project State
- Phase 12: Summary

### 1e50922 — Narrowed Hook Implementation

**Purpose:** Applied the narrowed `_availability_version_check` hook to fix the overly-broad detection.

**Code Change in `src/Tweak.xm`:**

```objc
static bool hooked_availability_version_check(uint32_t count,
                                               dyld_build_version_t versions[]) {
    bool caller_is_mkw = false;
    Dl_info di;
    void *ret = __builtin_return_address(0);
    if (ret && dladdr(ret, &di) && di.dli_fname)
        caller_is_mkw = strstr(di.dli_fname, "MarketplaceKitWrapper") != NULL;

    for (uint32_t i = 0; i < count; i++) {
        if (versions[i].platform != PLATFORM_IOS) continue;
        if (versions[i].version == PACK_VER(17,4,0)) return false;       // crash fix, global
        if (caller_is_mkw && (versions[i].version == PACK_VER(26,0,0) ||
                              versions[i].version == PACK_VER(26,4,0)))
            return false;                                                // MKW only
    }
    return orig_availability_version_check(count, versions);
}
```

**Effect:** The 26.0/26.4 rejection now only applies when called from MarketplaceKitWrapper, not globally.

### a19c261 — macOS 26.4 Crash Fix (v4.0)

**Purpose:** Hook `_availability_version_check` to fix launch crash on macOS 26.4.

**Hook:**
```objc
%hook NSProcessInfo
- (BOOL)isiOSAppOnMac { return NO; }
%end
```

**Effect:** Makes Fortnite behave as on a real iOS device, not a Mac.

---

## Technical Changes

### Makefile

```diff
- TARGET := iphone:clang:latest:26.0
+ TARGET := iphone:clang:latest:17.0
+ FnMacTweak_CFLAGS += -Wno-error=unguarded-availability-new
```

**Reason:** The tweak was built with minimum iOS 26.0, but dyld rejects dylibs
with minos higher than the runtime's iOS version. Since the tweak is loaded via
a `weak` `LC_LOAD_DYLIB`, the rejection was silent — the tweak never loaded.

### src/Tweak.xm

**Extended Hook:**

```diff
 static const struct {
     uint32_t    version;
     const char *reason;
 } kBlockedIOSVersions[] = {
-    { PACK_VER(17, 4, 0), "iOS 17.4 @available -> NULL async continuation SIGSEGV on launch" },
+    { PACK_VER(17, 4, 0), "iOS 17.4 @available -> NULL async continuation SIGSEGV on launch" },
+    { PACK_VER(26, 0, 0), "iOS 26.0 @available -> MarketplaceKitWrapper sideload check" },
+    { PACK_VER(26, 4, 0), "iOS 26.4 @available -> MarketplaceKitWrapper sideload check" },
 };
```

**Hook Logic:**

1. **17.4.0** — Global (crash fix): Affects all `#available(iOS 17.4, *)` checks
2. **26.0.0** — MKW only: Affects only MKW's checks (not Fortnite's own)
3. **26.4.0** — MKW only: Affects only MKW's checks (not Fortnite's own)

---

## Tooling Added

### `tools/fnmac.sh`

Main workflow CLI:

```bash
./fnmac.sh <command>

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

### `tools/cleanup.sh`

Build artifact cleaner:

```bash
./cleanup.sh
```

Removes:
- `.theos/obj/*` — Build objects
- `.theos/dist/*` — Distribution artifacts
- `.theos/tmp/*` — Temporary files
- Git submodule cache

### `tools/patch_ipa.py`

Static IPA patcher (legacy, kept as reference/fallback):

```bash
python3 patch_ipa.py <input.ipa> -o <output.ipa>
```

**Note:** Now superseded by dynamic hooks in `src/Tweak.xm`.

---

## Current State

### Build Status

```bash
# Build
THEOS=/Users/xnetcat/theos gmake

# Verify build
ls .theos/obj/debug/
# Should show: FnMacTweak.dylib (debug)

# Check loaded in game
vmmap <fortnite-pid> | grep FnMacTweak
```

### Test Status

| Test | Expected | Result |
|------|----------|--------|
| Tweak loads | ✅ `vmmap` shows loaded | ✅ Verified |
| Match join | ✅ Reaches ~40s | ✅ Verified |
| Online play | 🔄 ~40s before kick | ✅ Verified |
| Narrow hook test | 🔄 In progress | ⏳ Next step |

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
- **Kick stops** → Confirmed: overly-broad hook caused the issue
- **Still kicks** → Proceed to Phase 2 (reverse engineering)

### Phase 2: Reverse Engineering

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
│   ├── patch_ipa.py          # Static IPA patcher (legacy)
│   ├── cleanup.sh            # Build artifact cleaner
│   └── README.md             # Tooling docs
│
├── docs/
│   ├── PROJECT-STATUS.md     # Quick reference
│   ├── HANDOFF.md            # Quick reference
│   ├── handoff-prompt.md     # Reverse engineering guide
│   ├── investigation-report.md  # Investigation findings
│   └── COMMIT-SUMMARY.md     # This file
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

**Version:** 4.0.1 (development)
**Branch:** main
**Latest Commit:** b2c6f8e
