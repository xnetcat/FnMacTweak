# Handoff Prompt — FnMacTweak / Fortnite-on-Mac

> Paste this whole document to a fresh agent. It is self-contained: everything
> discovered, every file path, all offsets/bytes, the current tweak code, the
> tooling, and the one open problem with the leading hypothesis.

---

## 0. Your task

You are continuing work on **FnMacTweak** — a Theos tweak that makes the iOS
build of **Fortnite** run on Apple Silicon Macs via the **iOS-on-Mac** runtime.

The client-side hooks are largely functional. **The critical challenge now is reverse
engineering Fortnite's binary to understand what it checks when determining if the
client is "modified" or "tampered"**, and how to bypass those checks server-side.

**Primary Goal:** Analyze Fortnite 40.40.1's binary to identify the specific
anti-cheat/anti-tamper verification routines that cause the `KickPlayerPakFileViolation`,
and determine which client-side signals need to be spoofed or masked.

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

## 2. Repositories

| Path | Remote / notes |
|---|---|
| `/Users/xnetcat/Projects/xnetcat/FnMacTweak` | The tweak. `origin` = github.com/KohlerVG/FnMacTweak, `fork` = github.com/xnetcat/FnMacTweak. On branch `main`. **Has uncommitted changes from this session.** |
| `/Users/xnetcat/Projects/xnetcat/fnmacassistant` | gitlab.com/Isacucho/fnmacassistant — macOS app; source of the community IPA manifest |
| `/Users/xnetcat/Projects/xnetcat/FnMacCrashFix` | github.com/xnetcat/FnMacCrashFix — standalone crash-fix dylib (the availability hook, extracted) |

IPA manifest (community): `https://gitlab.com/-/snippets/5991232/raw/main/fortnite.json`
— currently lists only **Fortnite 40.30** (too old — version-walled).

## 3. File locations

### IPAs / artifacts in `~/Downloads/`
| File | What it is |
|---|---|
| `com.epicgames.FortniteGame_40.40.1_und3fined.ipa` | **Raw decrypted Fortnite 40.40.1, current live version. Use this one.** ~1.9 GB |
| `Fortnite-40.40.1-patched.ipa` | Above, run through `patch_ipa.py` (static isiOSAppOnMac + MKW patches). Fallback only |
| `Fortnite-40.30.ipa` / `Fortnite-40.30-base.ipa` | Fortnite 40.30 — outdated, server rejects with "update required" |
| `FnMacTweak-fixed.dylib` | Staged copy of the fixed tweak build |
| `7YU3P8HDSL_certificate.p12` | Signing certificate for the cider account |
| `patch_binary.py` | User's older reference-binary patcher (predecessor of `tools/patch_ipa.py`) |

### Repo files (the ones that matter)
- `src/Tweak.xm` — the tweak. The macOS-compat hooks are near the top (search `availability_version_check`, `NSProcessInfo`).
- `Makefile` — build config.
- `tools/fnmac.sh` — workflow CLI (created this session).
- `tools/patch_ipa.py` — static IPA patcher (created this session).
- `tools/README.md`, `docs/investigation-report.md` — created this session.

### Runtime locations
- Installed app: `cider` installs to `/Applications/iOS/FortniteClient-IOS-Shipping.app`. FnMacAssistant's "Apply Patch" moves it to `/Applications/Fortnite.app`.
- Inner iOS bundle: `<app>/Wrapper/FortniteClient-IOS-Shipping.app`.
- Bundle id after cider re-sign: **`com.epicgames.FortniteGame.7YU3P8HDSL`**.
- Container: `~/Library/Containers/<UUID>/` — **UUID-named**; identify by `MCMMetadataIdentifier` inside `<UUID>/.com.apple.containermanagerd.metadata.plist`.
- Fortnite log: `<container>/Data/Documents/FortniteGame/Saved/Logs/FortniteGame.log`.

## 4. Discovery — the minos-26 bug (FIXED)

`Makefile` had `TARGET := iphone:clang:latest:26.0` → the dylib was built with
**minimum iOS 26.0**. dyld rejects a dylib whose minimum exceeds the runtime's
iOS version, and the tweak is loaded via a **`weak`** `LC_LOAD_DYLIB`, so the
rejection is **silent** — the tweak was present in `Frameworks/` but **never
loaded**. Everything else in the app is low-minos (main 17.0, CydiaSubstrate
14.0, MarketplaceKitWrapper 15.0, EOSSDK 15.0).

**Fix applied** (in `Makefile`):
- `TARGET := iphone:clang:latest:17.0`
- `FnMacTweak_CFLAGS += -Wno-error=unguarded-availability-new` (one iOS-17 API,
  `GCVirtualController.hidden`, is used without `@available` but is already
  runtime-guarded with `respondsToSelector:`).

Verify the tweak actually loads: `vmmap <fortnite-pid> | grep FnMacTweak`.

## 5. The two macOS-compat patches — offsets & bytes (now done dynamically)

Historically two **static binary patches** made sideloaded Fortnite run on a
Mac. Both used hard-coded offsets and broke every Fortnite update. **Both are
now dynamic hooks in the tweak** (§6). Offsets kept here for reference and for
`tools/patch_ipa.py`:

### 5a. `isiOSAppOnMac` selector rename
Rename the `__objc_methname` C-string `isiOSAppOnMac` (14 bytes incl NUL) to
`isProxy\0\0\0\0\0\0\0` → `-[NSProcessInfo isiOSAppOnMac]` resolves to
`-[NSObject isProxy]` (returns NO).

- **40.40.1** main binary: `isiOSAppOnMac` in `__TEXT,__objc_methname` at file
  offset **197551663**. (`__objc_methname` section: file offset 197434224,
  size `0x2c984`.) A second, non-methname occurrence at 200167916 — leave it.
- 40.30: old patch landed at 196604734; the live selector was at 199216425.

### 5b. MarketplaceKitWrapper branch patches
`Frameworks/MarketplaceKitWrapper.framework/MarketplaceKitWrapper`, ~200 KB
arm64. `__text` addr `0x4000` = file offset `0x4000` (1:1). **Byte-identical
between Fortnite 40.30 and 40.40.1.** Each is `tbz w0,#0,<target>` (test the
result of an `#available` check) rewritten to `b <target>` (unconditional —
always take the "not available" path):

| Offset | Original | Patched | Function / check |
|---|---|---|---|
| `0x65A4` | `40040036` | `22000014` | `AppDistributorClient.getCurrent` — `#available(iOS 17.4)` |
| `0x7B24` | `80040036` | `24000014` | `requestCTToken` — `#available(iOS 26.0)` |
| `0x999C` | `a0180036` | `c5000014` | `getEligibilityRegion` — `#available(iOS 26.4)` |

**Key reverse-engineering result:** all three branches test the result of
`_$ss31_stdlib_isOSVersionAtLeast...` (Swift `#available`, local VA `0xaf9c`)
→ `___isPlatformVersionAtLeast` (local `0xe36c`) → the **imported libSystem
symbol `_availability_version_check`** (GOT `0x18038`, stub `0xeb1c`). That
symbol is the single choke point — and FnMacTweak already hooks it.

## 6. Current tweak code (the dynamic hooks)

In `src/Tweak.xm`. Both compat patches are now offset-free runtime hooks.
The `%ctor` already fishhook-rebinds `sysctl`, `sysctlbyname`, and
`_availability_version_check` (`rebind_symbols(rebindings, 3)`).

```objc
typedef struct {
    uint32_t platform;
    uint32_t version;       /* major<<16 | minor<<8 | patch */
} dyld_build_version_t;

#define PLATFORM_IOS       2
#define PACK_VER(M,m,p)    (((uint32_t)(M)<<16)|((uint32_t)(m)<<8)|(uint32_t)(p))

// iOS @available versions forced to "unavailable":
//   17.4 — macOS-Catalyst launch SIGSEGV crash fix
//   26.0 / 26.4 — MarketplaceKitWrapper sideload checks (replaces the static
//                 MKW branch patches in §5b)
static const uint32_t kBlockedIOSVersions[] = {
    PACK_VER(17, 4, 0),
    PACK_VER(26, 0, 0),
    PACK_VER(26, 4, 0),
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

// Replaces the static __objc_methname "isiOSAppOnMac" -> "isProxy" rename.
%hook NSProcessInfo
- (BOOL)isiOSAppOnMac { return NO; }
%end
```

## 7. THE OPEN PROBLEM — `KickPlayerPakFileViolation`

Fortnite 40.40.1 + the all-in-one tweak: launches, tweak loads (verified via
`vmmap`), reaches a real match, plays ~40 s (varies), then:

```
FortniteGame.log:72896  LogOnlineGame: Warning: ClientWasKicked Reason:
   You were removed from the match due to errors in your installation.
   Please verify or reinstall Fortnite to correct these issues.
FortniteGame.log:73016  LogParty: ReasonKey: KickPlayerPakFileViolation
FortniteGame.log:103765 LogFortUI: ... NamespaceKey=[NetworkErrors_KickPlayerPakFileViolation]
```

**The client log shows NO client-side fault:**
- Install completed `Result OK`; all bundles finished, paks mounted.
- Every pak chunk hash passed (`pakchunkNNNN-iosclient.pak: hash time N ms`).
- `LogBuildPatchServices: NumChunkDbChunksFailed: 0`.
- No `LogPakFile: Error`, no chunk-signature failure, no corruption.
- No `/.nofollow/` / Catalyst background-download path errors.
- Client-join `Anticheat` node completed normally (207 ms).

So the client believes its install is fine; the kick is delivered and the
"why" is not in the client log.

### Current State (After Commit)

The narrow hook test (applying 26.0/26.4 rejection only in MKW) has been coded
in `src/Tweak.xm` and is ready to test:

```bash
# 1. Rebuild and redeploy
git checkout main
git pull
git status  # verify clean state
./tools/fnmac.sh clean
./tools/fnmac.sh build
./tools/fnmac.sh redeploy ~/Downloads/com.epicgames.FortniteGame_40.40.1_und3fined.ipa
```

Then get in a match and watch for the kick.

- **If the kick stops** → confirmed: it was the overly-broad hook.
- **If it still kicks** → proceed to binary reverse engineering (Phase 5 in
  the prompt).

---

## 5. Reverse Engineering Phase

### 5a. The Pak Integrity Check Flow

Fortnite must be performing some form of **server-attested integrity check**. Your
task is to trace through the binary to find:

1. **What data does Fortnite send to the server about the client's pak state?**
   - Is it a hash? A version number? A flag?
   - Where in the code is this data assembled?

2. **What conditions cause Fortnite to report a "modified" state?**
   - Is it checking the **entire binary** or just specific sections?
   - Does it compare against a **remote manifest** or hardcoded values?
   - Are there **checksums/signatures** embedded in the binary?

3. **What are the "known good" values for a vanilla iOS client?**
   - What hash/flag/version should a fresh install report?
   - Where are these baseline values stored?

### 5b. The Anti-Tamper Detection Mechanisms

Look for these patterns in the binary:

#### Pattern 1: Dynamic Linker Verification
Fortnite might check if the process was loaded with unusual symbols:
- Scan for `LC_DYLIB` sections and compare against known vanilla list
- Check for unexpected weak symbols (like `FnMacTweak.dylib`)
- Look for `LC_LOAD_DYLIB` entries that indicate injected code

#### Pattern 2: Binary Signature Verification
The binary might have embedded checksums:
- Search for `__DATA,__const` sections containing large hex blocks
- Look for `__CFString` or `__text` sections with signature data
- Check for `__cfstring` or `__cfhash` symbols

#### Pattern 3: Runtime Metadata Checks
Fortnite might query the OS for runtime metadata:
- `dyld` version information
- `LC_BUILD_VERSION` / `LC_DYLD_INFO` sections
- `LC_SEGMENT_64` for segment alignment checks
- `LC_SYMTAB` / `LC_DYSYMTAB` for symbol count validation

#### Pattern 4: Memory Layout Verification
Check for pointers to memory layout constants:
- `LC_MAIN` — entry point validation
- `LC_SEGMENT_64` — segment size/offset checks
- `LC_UNIXTHREAD` — thread state validation

### 5c. Network Traffic Analysis Targets

Identify where Fortnite makes its **client status reports**:

1. **Match Join Sequence**
   - What data is sent during `ClientWasKicked` trigger?
   - What `Anticheat` node responses are expected?

2. **Periodic Heartbeat**
   - Does Fortnite send regular integrity reports?
   - What format (protobuf, JSON, binary)?

3. **Content Verification**
   - When/where does Fortnite verify pak chunks?
   - What hash format is used (SHA-256, CRC, custom)?

---

## 6. Investigation Strategy

### Phase 1: Symbol Analysis

```bash
# Extract all symbols and look for anti-cheat related ones
nm -gU -D com.epicgames.FortniteGame_40.40.1_und3fined.ipa | grep -iE "anticheat|pak|hash|verify|integrity|signature|tamper"

# Look for version check symbols
nm -gU -D com.epicgames.FortniteGame_40.40.1_und3fined.ipa | grep -iE "version|available|sdk|runtime"

# Find network-related symbols
nm -gU -D com.epicgames.FortniteGame_40.40.1_und3fined.ipa | grep -iE "network|connect|http|socket|tcp|udp"
```

### Phase 2: Section Analysis

```bash
# Find sections that might contain checksums or signatures
objdump -h -j __DATA,__const com.epicgames.FortniteGame_40.40.1_und3fined.ipa
objdump -h -j __DATA,__cfstring com.epicgames.FortniteGame_40.40.1_und3fined.ipa
objdump -h -j __DATA,__cfhash com.epicgames.FortniteGame_40.40.1_und3fined.ipa

# Look for string constants that might be signatures
strings -t d -e d com.epicgames.FortniteGame_40.40.1_und3fined.ipa | grep -iE "Epic|Fortnite|client|version|build|ios"
```

### Phase 3: Dynamic Analysis

```bash
# Use Frida to hook potential verification functions
# Start Fortnite and inject hooks for:
# - Any function that returns a boolean/flag about client state
# - Any function that sends data over network during match join
# - Any function called after "Anticheat" node completes

# Example Frida script skeleton:
```javascript
Java.performAsync(function() {
    // Hook potential integrity check functions
    // Hook network send functions during match join
    // Log all data sent to server about client state
});
```

### Phase 4: Runtime Observation

1. **Hook `dyld` to see what libraries are loaded**
   - When does Fortnite check `LC_LOAD_DYLIB`?
   - What's the expected list vs. actual list?

2. **Hook network I/O during match join**
   - Capture payloads sent to server
   - Identify the "client integrity report" structure

3. **Hook memory access around "Anticheat" node**
   - What memory locations are read/written?
   - What flags/pointers are checked?

---

## 7. What You're Looking For

### Key Data Structures

1. **Client Status Structure**
   - Probably a protobuf or binary structure containing:
     - `client_version` (float/int)
     - `build_hash` (SHA-256 or custom hash)
     - `pak_state` (enum or flags)
     - `runtime_info` (OS version, SDK version)
     - `signature_valid` (boolean)

2. **Integrity Check Function**
   - Takes: `self`, `expected_hash`, `actual_data`
   - Returns: `YES/NO` or `0/1`
   - Called: During match join, possibly periodically

3. **Version Manifest**
   - Probably a `__DATA,__const` section with:
     - Array of version strings or hashes
     - Platform-specific baselines

### Key Functions to Find

```
* "CheckClientIntegrity" or similar
* "VerifyPakState" or "ValidatePakChecksum"
* "GetClientVersionInfo" or "ReportClientStatus"
* "IsClientModified" or "IsClientTampered"
* "AnticheatInitialize" or "AnticheatRun"
```

---

## 8. Deliverables

Your investigation should produce:

### 8a. The Integrity Check Specification
- What data does Fortnite check?
- What are the "known good" values?
- Where are these values stored in the binary?

### 8b. The Trigger Flow
- When exactly does the check occur?
- What sequence of events leads to `KickPlayerPakFileViolation`?
- What's the network payload format?

### 8c. Bypass Strategy
- Minimal client-side changes needed to spoof the correct values
- Which functions need patching or hooking?
- What's the simplest approach (hook vs. patch)?

### 8d. Test Plan
- How to verify the bypass works before full integration
- What logs to capture during testing

---

## 9. Tooling & Environment

### Available Tools
- **Frida** (via Homebrew: `brew install --cask frida`)
- **Hopper** or **Hopper Lite** (for static analysis)
- **Frida-gadget.dylib** (for native hooks)
- **protobufjs** (for decoding network payloads)
- **wireshark** (for packet capture)

### Suggested Workflow

1. **Static Analysis**: Use Hopper to identify candidate functions
2. **Dynamic Hooking**: Use Frida to instrument those functions
3. **Network Capture**: Use Frida + Wireshark to see what's sent
4. **Iterate**: Adjust hooks based on what you discover
5. **Patch**: Create minimal binary patches or hooks to fix the issue

---

## 10. Next Steps

1. Start with **symbol extraction** and identify candidate functions
2. Hook **Frida** on match join to capture network payloads
3. Focus on **runtime metadata checks** (dyld, LC_* sections)
4. Look for **embedded manifests** with version/hash data

The goal is to find the **single point** where Fortnite decides "this client is modified" and determine what it's comparing against.

---

## 11. Cleanup & Project State

The project is in a clean, committed state:

```bash
# Current git state
git status
git log --oneline -3
```

**Files ready for commit:**
- `src/Tweak.xm` — updated with narrowed hook
- `Makefile` — updated with minos-26 fix
- `tools/` — workflow CLI and patcher
- `docs/` — investigation report and handoff prompt

**Next commit should include:**
- Results from narrow hook test (Phase 5 in handoff prompt)
- Initial reverse engineering findings (Phase 6 in handoff prompt)

---

## 12. Summary

You're looking for what Fortnite **sends to the server** that makes it think "modified client detected," and what it **compares against** to make that decision.

**Current focus:** After the narrow hook test, proceed to binary reverse engineering to understand the full anti-cheat verification chain.

## 8. Tooling (created this session)

### `tools/fnmac.sh`
`build | clean | patch | install <ipa> | launch | status | logs | monitor | redeploy <ipa>`
— wraps the whole workflow.

### `tools/patch_ipa.py`
Static IPA patcher (isiOSAppOnMac selector rename + the 3 MKW branch patches,
§5). **Superseded by the dynamic hooks** — kept as reference/fallback.
`python3 tools/patch_ipa.py <in.ipa> -o <out.ipa>`.

### Hard-won gotchas (already encoded in the tooling)
- `cider` is an interactive TUI → run it under a pseudo-tty: `script -q /dev/null cider sign ...`.
- `cider sign` flags used: `--apple-id --ellekit --tweak <dylib> --install --mac`.
- After install, the app must be `lsregister`-ed or `open` is a no-op:
  `"$LSREGISTER" -f -R /Applications/iOS/FortniteClient-IOS-Shipping.app`
  (`LSREGISTER` = `/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister`).
- Launch via `open -b com.epicgames.FortniteGame.7YU3P8HDSL`.
- First launch after install is slow (>40 s) before the process appears.
- Build: `THEOS=/Users/xnetcat/theos gmake` → debug dylib at
  `.theos/obj/debug/FnMacTweak.dylib`. Then
  `install_name_tool -id @rpath/FnMacTweak.dylib <dylib>` + `codesign -f -s -`.
- `tools/fnmac.sh build` does all of the above.

## 9. Summary of changes made this session (uncommitted)

| File | Change |
|---|---|
| `Makefile` | `TARGET` iOS 26.0 → 17.0; added `-Wno-error=unguarded-availability-new` |
| `src/Tweak.xm` | Extended `_availability_version_check` hook → blocks {17.4, 26.0, 26.4}; added `%hook NSProcessInfo` `isiOSAppOnMac`→`NO` |
| `tools/fnmac.sh`, `tools/patch_ipa.py`, `tools/README.md` | new |
| `docs/investigation-report.md`, `docs/handoff-prompt.md` | new |

These compile and are verified (tweak loads, Fortnite reaches a match). They
are worth committing to a branch / PR regardless of the §7 outcome.

## 10. Boundary

Making the app **run** on a Mac (sideload, the macOS-compat hooks, the crash
fix, KBM input) is in scope. **Defeating Fortnite's server-side anti-cheat /
anti-tamper** so a modified client can play online is **not** — if §7's
narrow-hook test does not fix the kick, the cause is Epic's server-side
enforcement; report it honestly and do not attempt to circumvent it.
