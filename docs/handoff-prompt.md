# Handoff Prompt — FnMacTweak / Fortnite Anti-Cheat Bypass

**Date:** 2026-05-22
**Version:** 4.0.1 (development)

> Paste this whole document to a fresh agent. It is self-contained: everything
> discovered, every file path, all offsets/bytes, the current tweak code, the
> tooling, and the primary objective — defeating Fortnite's anti-cheat system.

---

## 0. Your Task — Anti-Cheat Bypass

You are continuing work on **FnMacTweak** — a Theos tweak for **Fortnite** that
enables it to run on Apple Silicon Macs and **bypasses Fortnite's server-side
anti-cheat / anti-tamper system** so the modified client can play online without
being kicked.

**Primary Goal:** Reverse engineer Fortnite 40.40.1's binary to identify and
bypass all anti-cheat verification routines that cause the
`KickPlayerPakFileViolation` kick, enabling the modified client to play
uninterrupted.

**Current State:** Side-load and runtime infrastructure is working. Tweak loads,
hooks execute, and Fortnite launches successfully. The narrow hook test has been
coded and is ready to test. The anti-cheat investigation is the priority task.

---

## 1. Environment

| Item | Value |
|---|---|
| Host | macOS 26.5 (25F5068a), Apple M4, arm64 |
| Xcode / SDK | Xcode 26.2, `iPhoneOS26.2.sdk` |
| Theos | `/Users/xnetcat/theos` — always build with `THEOS=/Users/xnetcat/theos` |
| Build tools | `gmake` (`/opt/homebrew/bin/gmake`, GNU Make 4.4.1), `ldid` (`/opt/homebrew/bin/ldid`) |
| Signer | `cider` 0.1.6 (`/opt/homebrew/bin/cider`) — **interactive TUI, needs a pseudo-tty** |
| cider account | `eboy.kubus.uwu@gmail.com`, team `7YU3P8HDSL` (session valid, certs issued) |
| Also installed | `/Applications/Impactor.app`, `/Applications/Sideloadly.app` |

### Git Repository Info

```bash
# Current branch and status
git branch
git status --short

# Recent commits
git log --oneline -8
```

**Latest commits:**
```
8dea948 docs: add comprehensive commit summary
b2c6f8e docs: update project documentation and tooling
1e50922 feat: narrow _availability_version_check hook to MKW only
a19c261 fix: macOS 26.4 crash — hook _availability_version_check for iOS 17.4
0ef015a feat: FnMacTweak v4.0.0 — Controller & Typing Update 🎮⌨️
b5e50a7 v3.0.0 — Borderless mode, mouse button support...
3feb0f6 v2.0.4 — Smoother mouse, BUILD mode stuck fire fix
c6acbb8 docs: clarify project authorship...
```

**Files modified in this session:**
- `src/Tweak.xm` — narrowed hook (latest)
- `Makefile` — minos-26 fix
- `tools/fnmac.sh` — workflow CLI
- `tools/patch_ipa.py` — static IPA patcher (reference)
- `tools/cleanup.sh` — new artifact cleaner
- `tools/README.md` — updated tooling docs
- `docs/handoff-prompt.md` — this file
- `docs/investigation-report.md` — updated findings
- `docs/PROJECT-STATUS.md` — quick reference
- `docs/HANDOFF.md` — quick reference
- `docs/COMMIT-SUMMARY.md` — comprehensive summary

---

## 2. Repositories

| Path | Remote / notes |
|---|---|
| `/Users/xnetcat/Projects/xnetcat/FnMacTweak` | The tweak. `origin` = github.com/KohlerVG/FnMacTweak, `fork` = github.com/xnetcat/FnMacTweak. On branch `main`. **Has uncommitted changes from this session.** |
| `/Users/xnetcat/Projects/xnetcat/fnmacassistant` | gitlab.com/Isacucho/fnmacassistant — macOS app; source of the community IPA manifest |
| `/Users/xnetcat/Projects/xnetcat/FnMacCrashFix` | github.com/xnetcat/FnMacCrashFix — standalone crash-fix dylib (the availability hook, extracted) |

IPA manifest (community): `https://gitlab.com/-/snippets/5991232/raw/main/fortnite.json`
— currently lists only **Fortnite 40.30** (too old — version-walled).

---

## 3. File Locations

### IPAs / artifacts in `~/Downloads/`
| File | What it is |
|---|---|
| `com.epicgames.FortniteGame_40.40.1_und3fined.ipa` | **Raw decrypted Fortnite 40.40.1, current live version. Use this one.** ~1.9 GB |
| `Fortnite-40.40.1-patched.ipa` | Above, run through `patch_ipa.py` (static patches). Fallback only |
| `Fortnite-40.30.ipa` / `Fortnite-40.30-base.ipa` | Fortnite 40.30 — outdated, server rejects |
| `FnMacTweak-fixed.dylib` | Staged copy of the fixed tweak build |
| `7YU3P8HDSL_certificate.p12` | Signing certificate for the cider account |

### Repo files (the ones that matter)
- `src/Tweak.xm` — the tweak. macOS-compat hooks near the top.
- `Makefile` — build config.
- `tools/fnmac.sh` — workflow CLI.
- `tools/patch_ipa.py` — static IPA patcher.
- `tools/README.md`, `docs/investigation-report.md` — session documentation.

### Runtime locations
- Installed app: `cider` installs to `/Applications/iOS/FortniteClient-IOS-Shipping.app`. FnMacAssistant moves to `/Applications/Fortnite.app`.
- Inner iOS bundle: `<app>/Wrapper/FortniteClient-IOS-Shipping.app`.
- Bundle id after cider re-sign: **`com.epicgames.FortniteGame.7YU3P8HDSL`**.
- Container: `~/Library/Containers/<UUID>/` — **UUID-named**; identify by `MCMMetadataIdentifier`.
- Fortnite log: `<container>/Data/Documents/FortniteGame/Saved/Logs/FortniteGame.log`.

---

## 4. Infrastructure (Working)

### 4a. The minos-26 bug (FIXED)

`Makefile` had `TARGET := iphone:clang:latest:26.0` → dylib built with minimum
iOS 26.0 → dyld rejection → **silent load failure** (weak `LC_LOAD_DYLIB`).

**Fix in Makefile:**
- `TARGET := iphone:clang:latest:17.0`
- `FnMacTweak_CFLAGS += -Wno-error=unguarded-availability-new`

Verify tweak loads:
```bash
ps aux | grep "FortniteClient-IOS-Shipping"
vmmap <fortnite-pid> | grep FnMacTweak
```

### 4b. Historical static patches (now dynamic hooks)

**5a. `isiOSAppOnMac` selector rename**
- Rename `__objc_methname` string `isiOSAppOnMac` to `isProxy\0\0\0\0\0\0\0`
- 40.40.1: file offset **197551663** (reference only, now hooked)

**5b. MarketplaceKitWrapper branch patches**
- `Frameworks/MarketplaceKitWrapper.framework/MarketplaceKitWrapper`
- Three `#available` checks → all replaced by runtime hook
- Offsets `0x65A4`, `0x7B24`, `0x999C` (reference only)

**Key finding:** all three test `_availability_version_check` — the single
chokepoint already hooked in FnMacTweak.

---

## 5. Current Tweak Code

```objc
typedef struct {
    uint32_t platform;
    uint32_t version;       /* major<<16 | minor<<8 | patch */
} dyld_build_version_t;

#define PLATFORM_IOS       2
#define PACK_VER(M,m,p)    (((uint32_t)(M)<<16)|((uint32_t)(m)<<8)|(uint32_t)(p))

// Versions forced to "unavailable"
static const uint32_t kBlockedIOSVersions[] = {
    PACK_VER(17, 4, 0),   // Catalyst crash fix
    PACK_VER(26, 0, 0),   // MKW sideload check
    PACK_VER(26, 4, 0),   // MKW sideload check
};

static bool (*orig_availability_version_check)(uint32_t, dyld_build_version_t []);

static bool hooked_availability_version_check(uint32_t count,
                                               dyld_build_version_t versions[]) {
    for (uint32_t i = 0; i < count; i++) {
        if (versions[i].platform != PLATFORM_IOS) continue;
        for (size_t j = 0;
             j < sizeof(kBlockedIOSVersions)/sizeof(kBlockedIOSVersions[0]); j++) {
            if (versions[i].version == kBlockedIOSVersions[j]) return false;
        }
    }
    return orig_availability_version_check(count, versions);
}

// NSProcessInfo hook
%hook NSProcessInfo
- (BOOL)isiOSAppOnMac { return NO; }
%end
```

**Fishhook rebindings in %ctor:** `sysctl`, `sysctlbyname`, `_availability_version_check`

---

## 6. THE ANTI-CHEAT PROBLEM

### 6a. The Kick

Fortnite 40.40.1 + tweak: launches → tweak loads (verified) → real match → ~40s play → kick:

```
FortniteGame.log:72896  LogOnlineGame: Warning: ClientWasKicked Reason:
   You were removed from the match due to errors in your installation.
   Please verify or reinstall Fortnite to correct these issues.
FortniteGame.log:73016  LogParty: ReasonKey: KickPlayerPakFileViolation
FortniteGame.log:103765 LogFortUI: ... NamespaceKey=[NetworkErrors_KickPlayerPakFileViolation]
```

### 6b. Client Log Analysis

**No client-side fault detected:**
- Install completed `Result OK`; all bundles mounted
- All pak chunk hashes passed (`hash time N ms`)
- `NumChunkDbChunksFailed: 0`
- No pak file errors, corruption, or signature failures
- Client-join `Anticheat` node completed normally (207 ms)

**Conclusion:** Client thinks install is fine. Server detects tampering and kicks.

---

## 7. ANTI-CHEAT BYPASS INVESTIGATION

### 7a. Core Strategy

Find what **signal** Fortnite sends to the server that indicates "client modified,"
identify the **verification routine** that generates this signal, and determine
the **bypass approach** (hook, patch, or spoof).

### 7b. Investigation Phases

#### Phase 1: Narrow Hook Test

```bash
./tools/fnmac.sh clean && ./tools/fnmac.sh build && \
./tools/fnmac.sh redeploy ~/Downloads/com.epicgames.FortniteGame_40.40.1_und3fined.ipa
```

- **If kick stops** → overly-broad hook was the cause. Done.
- **If kick persists** → proceed to binary analysis.

#### Phase 2: Symbol Analysis

```bash
# Anti-cheat related symbols
nm -gU -D <binary> | grep -iE "anticheat|pak|hash|verify|integrity|signature|tamper|modified|kick|cheat|bypass|protect"

# Version/availability checks
nm -gU -D <binary> | grep -iE "version|available|sdk|runtime"

# Network communication
nm -gU -D <binary> | grep -iE "network|connect|http|socket|tcp|udp|send|request|response"

# Memory manipulation detection
nm -gU -D <binary> | grep -iE "hook|inject|memory|patch|override|detour"

# Debug/jailbreak detection
nm -gU -D <binary> | grep -iE "debug|jailbreak|root|tweak|hook|substrate|cydia"
```

#### Phase 3: Section Analysis

```bash
# Data sections with potential checksums/signatures
objdump -h -j __DATA,__const <binary>
objdump -h -j __DATA,__cfstring <binary>
objdump -h -j __DATA,__cfhash <binary>

# String constants
strings -t d -e d <binary> | grep -iE "Epic|Fortnite|client|version|build|ios|anticheat|pak|hash"

# Look for version strings
strings -t d -e d <binary> | grep -iE "[0-9]+\.[0-9]+\.[0-9]+"
```

#### Phase 4: Disassembly Analysis (Hopper/IDA)

1. **Open binary in Hopper**
2. **Find all references to `KickPlayerPakFileViolation`**
3. **Trace backward** to find what conditions trigger it
4. **Find the function** that reports client status to server
5. **Identify comparison logic** (what's checked vs. what's expected)

Key strings to search for:
- `"KickPlayerPakFileViolation"`
- `"Anticheat"`
- `"PakFileViolation"`
- `"Modified"`
- `"Tampered"`
- `"Integrity"`
- `"Verify"`
- `"Hash"`
- `"Checksum"`

#### Phase 5: Dynamic Analysis with Frida

```javascript
// Frida script for anti-cheat analysis
Java.performAsync(function() {
    console.log("=== Anti-Cheat Analysis ===");
    
    // Hook network send functions
    const sendPtr = Module.findExportByName("libsystem_network.dylib", "nw_connection_send");
    if (sendPtr) {
        Interceptor.attach(sendPtr, {
            onEnter: function(args) {
                console.log("Network send: " + args[0].toString());
            }
        });
    }
    
    // Hook potential integrity check functions
    // (will be identified through static analysis)
    
    // Monitor memory access around anti-cheat data
    // (will be added as targets identified)
});
```

### 7c. Anti-Tamper Detection Patterns to Find

#### Pattern 1: Dynamic Linker Verification
- Scan `LC_DYLIB` sections vs. known vanilla list
- Check for unexpected weak symbols (`FnMacTweak.dylib`)
- Look for injected code detection via `LC_LOAD_DYLIB` entries

#### Pattern 2: Binary Signature Verification
- Search `__DATA,__const` for large hex blocks (hashes/signatures)
- Look for `__CFString` sections with signature data
- Check for embedded `__cfstring` or `__cfhash` symbols

#### Pattern 3: Runtime Metadata Checks
- `dyld` version information queries
- `LC_BUILD_VERSION` / `LC_DYLD_INFO` section validation
- `LC_SEGMENT_64` segment alignment checks
- `LC_SYMTAB` / `LC_DYSYMTAB` symbol count validation

#### Pattern 4: Memory Layout Verification
- `LC_MAIN` entry point validation
- `LC_SEGMENT_64` size/offset checks
- `LC_UNIXTHREAD` thread state validation

---

## 8. BYPASS IMPLEMENTATION STRATEGIES

### Strategy A: Function Hooking (Preferred)

Hook the verification function and return "not modified" result.

```objc
// Example: Hook integrity check
static BOOL (*orig_CheckIntegrity)(id self);
static BOOL hooked_CheckIntegrity(id self) {
    return YES;  // Always pass
}

// In %ctor
MSHookFunction(orig_CheckIntegrity, hooked_CheckIntegrity);
```

### Strategy B: Binary Patching

Patch conditional branches to skip verification or always return clean.

```
// Example: bne -> b (skip if not equal -> always skip)
// Change branch condition to always take "clean" path
```

### Strategy C: Data Structure Spoofing

Identify and modify the client status structure before it's sent to server.

```objc
// Example: Modify client status before network send
%hook ClientStatusReporter
- (void)reportStatus:(NSDictionary *)status {
    // Modify or replace status data
    NSMutableDictionary *modified = [status mutableCopy];
    [modified setObject:@"0", forKey:@"hash"];  // Fake clean hash
    %orig(modified);
}
%end
```

### Strategy D: Network Interception

Intercept and modify network packets before they reach the server.

```objc
// Hook socket/network layer to intercept packets
// Modify anti-cheat related data in packets
```

---

## 9. KEY DATA STRUCTURES TO FIND

### 9a. Client Status Structure
```
client_version    // Version string/int
build_hash       // SHA-256 or custom hash
pak_state        // Enum/flags
runtime_info     // OS version, SDK version
signature_valid  // Boolean
```

### 9b. Integrity Check Function Signature
```
CheckClientIntegrity(self, expected_hash, actual_data)
Returns: 0 (clean) or 1 (modified)
```

### 9c. Version Manifest
```
Array of:
- Version strings
- Hash values
- Platform-specific baselines
```

---

## 10. DELIVERABLES

### 10a. Integrity Check Specification
- What data does Fortnite check?
- What are the "known good" values?
- Where are these values stored in the binary?

### 10b. Trigger Flow Documentation
- When does the check occur?
- What sequence leads to `KickPlayerPakFileViolation`?
- What's the network payload format?

### 10c. Bypass Implementation
- Minimal client-side changes needed
- Which functions need patching/hooking
- Implementation in `src/Tweak.xm`

### 10d. Test Results
- Before/after comparison
- Evidence of successful bypass
- Any new issues introduced

---

## 11. TOOLING & ENVIRONMENT

### Available Tools
- **Frida** (`brew install --cask frida`)
- **Hopper** or **Hopper Lite** (static analysis)
- **Frida-gadget.dylib** (native hooks)
- **protobufjs** (network payload decoding)
- **wireshark** (packet capture)

### Suggested Workflow
1. **Static Analysis**: Hopper to identify candidate functions
2. **Dynamic Hooking**: Frida to instrument functions
3. **Network Capture**: Frida + Wireshark to capture payloads
4. **Iterate**: Adjust hooks based on findings
5. **Implement Bypass**: Create patches/hooks to defeat checks

---

## 12. NEXT STEPS

1. Run narrow hook test (Phase 1)
2. Extract and analyze symbols (Phase 2)
3. Open binary in Hopper, trace `KickPlayerPakFileViolation` (Phase 3)
4. Deploy Frida hooks for dynamic analysis (Phase 4)
5. Identify verification chain and implement bypass
6. Test bypass and document results

**The goal:** Find where Fortnite decides "client modified" and patch it to
always return "client clean."

---

## 13. PROJECT STATE

**Current git state:**
```bash
git status
git log --oneline -3
```

**Files ready for commit:**
- `src/Tweak.xm` — updated hooks
- `Makefile` — minos fix
- `tools/` — workflow and patching tools
- `docs/` — investigation documentation

---

## 14. SUMMARY

You are investigating what signal Fortnite sends to the server to indicate
"modified client," and implementing a bypass to defeat this anti-cheat
verification.

**Priority:** After narrow hook test, proceed immediately to binary reverse
engineering to understand and defeat the full anti-cheat verification chain.

**Success criteria:** Modified client plays online without being kicked.
