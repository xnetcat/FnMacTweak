# Handoff Prompt — FnMacTweak / Fortnite-on-Mac

> Paste this whole document to a fresh agent. It is self-contained: everything
> discovered, every file path, all offsets/bytes, the current tweak code, the
> tooling, and the one open problem with the leading hypothesis.

---

## 0. Your task

You are continuing work on **FnMacTweak** — a Theos tweak that makes the iOS
build of **Fortnite** run, with keyboard/mouse/controller support, on Apple
Silicon Macs via the **iOS-on-Mac** runtime (sideloaded, signed with `cider`).

The client side is solved. **One open problem remains:** with the latest
Fortnite (40.40.1) and the tweak, the game launches, reaches a match, plays
~40 s, then is kicked: `KickPlayerPakFileViolation` (`You were removed from the
match due to errors in your installation`). See §7 for the diagnosis so far and
the leading hypothesis / next step.

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
- `src/Tweak.xm` — the tweak. The macOS‑compat hooks are near the top (search `availability_version_check`, `NSProcessInfo`).
- `Makefile` — build config.
- `tools/fnmac.sh` — workflow CLI (created this session).
- `tools/patch_ipa.py` — static IPA patcher (created this session).
- `tools/README.md`, `docs/investigation-report.md` — created this session.

### Runtime locations
- Installed app: `cider` installs to `/Applications/iOS/FortniteClient-IOS-Shipping.app`. FnMacAssistant's "Apply Patch" moves it to `/Applications/Fortnite.app`.
- Inner iOS bundle: `<app>/Wrapper/FortniteClient-IOS-Shipping.app`.
- Bundle id after cider re‑sign: **`com.epicgames.FortniteGame.7YU3P8HDSL`**.
- Container: `~/Library/Containers/<UUID>/` — **UUID‑named**; identify by `MCMMetadataIdentifier` inside `<UUID>/.com.apple.containermanagerd.metadata.plist`.
- Fortnite log: `<container>/Data/Documents/FortniteGame/Saved/Logs/FortniteGame.log`.

## 4. Discovery — the minos‑26 bug (FIXED)

`Makefile` had `TARGET := iphone:clang:latest:26.0` → the dylib was built with **minimum iOS 26.0**. dyld rejects a dylib whose minimum exceeds the runtime's iOS version, and the tweak is loaded via a **`weak`** `LC_LOAD_DYLIB`, so the rejection is **silent** — the tweak was present in `Frameworks/` but **never** loaded. Everything else in the app is low‑minos (main 17.0, CydiaSubstrate 14.0, MarketplaceKitWrapper 15.0, EOSSDK 15.0).

**Fix applied** (in `Makefile`):
- `TARGET := iphone:clang:latest:17.0`
- `FnMacTweak_CFLAGS += -Wno-error=unguarded-availability-new` (one iOS‑17 API, `GCVirtualController.hidden`, is used without `@available` but is already runtime‑guarded with `respondsToSelector:`).

Verify the tweak actually loads: `vmmap <fortnite‑pid> | grep FnMacTweak`.

## 5. The two macOS‑compat patches — offsets & bytes (now done dynamically)
Historically two **static binary patches** made sideloaded Fortnite run on a Mac. Both used hard‑coded offsets and broke every Fortnite update. **Both are now dynamic hooks in the tweak** (§6). Offsets kept here for reference and for `tools/patch_ipa.py`:

### 5a. `isiOSAppOnMac` selector rename
Rename the `__objc_methname` C‑string `isiOSAppOnMac` (14 bytes incl NUL) to
`isProxy\0\0\0\0\0\0\0` → `-[NSProcessInfo isiOSAppOnMac]` resolves to
`-[NSObject isProxy]` (returns NO).

- **40.40.1** main binary: `isiOSAppOnMac` in `__TEXT,__objc_methname` at file
  offset **197551663**. (`__objc_methname` section: file offset **197434224**, size `0x2c984`). A second, non‑methname occurrence at **200167916** — leave it.
- **40.30:** old patch landed at **196604734**; the live selector was at **199216425**.

### 5b. MarketplaceKitWrapper branch patches
`Frameworks/MarketplaceKitWrapper.framework/MarketplaceKitWrapper`, ~200 KB
arm64. `__text` addr `0x4000` = file offset `0x4000` (1:1). **Byte‑identical
between Fortnite 40.30 and 40.40.1.** Each is `tbz w0,#0,<target>` (test the
result of an `#available` check) rewritten to `b <target>` (unconditional —
always take the "not available" path):

| Offset | Original | Patched | Function / check |
|---|---|---|---|
| `0x65A4` | `40040036` | `22000014` | `AppDistributorClient.getCurrent` — `#available(iOS 17.4)` |
| `0x7B24` | `80040036` | `24000014` | `requestCTToken` — `#available(iOS 26.0)` |
| `0x999C` | `a0180036` | `c5000014` | `getEligibilityRegion` — `#available(iOS 26.4)` |

**Key reverse‑engineering result:** all three branches test the result of
`_$ss31_stdlib_isOSVersionAtLeast...` (Swift `#available`, local VA `0xaf9c`) →
`___isPlatformVersionAtLeast` (local `0xe36c`) → the **imported libSystem
symbol `_availability_version_check`** (GOT `0x18038`, stub `0xeb1c`). That
symbol is the single choke point — and FnMacTweak already hooks it.

## 6. Current tweak code (the dynamic hooks)
In `src/Tweak.xm`. Both compat patches are now offset‑free runtime hooks.
The `%ctor` already fishhook‑rebinds `sysctl`, `sysctlbyname`, and
`_availability_version_check` (`rebind_symbols(rebindings, 3)`).

```objc
// ... (code snippet omitted for brevity)
```

## 7. THE OPEN PROBLEM — `KickPlayerPakFileViolation`
Fortnite 40.40.1 + the all‑in‑one tweak: launches, tweak loads (verified via
`vmmap`), reaches a real match, plays ~40 s (varies), then:

```
// ... log snippet omitted for brevity
```

**The client log shows NO client‑side fault:** …

### Leading hypothesis (most likely, and our own regression)
…

### NEXT STEP — narrow the hook, then retest
Apply the 26.0/26.4 rejection **only when the caller is inside
MarketplaceKitWrapper**; keep 17.4 global (crash fix). The immediate caller of
`_availability_version_check` is `___isPlatformVersionAtLeast`, which is a
*local* function — inside the MKW image for MKW's checks, inside the main image
for Fortnite's own. So `dladdr(__builtin_return_address(0))` distinguishes them:

```objc
// ... code snippet omitted for brevity
```

Then: `./tools/fnmac.sh redeploy ~/Downloads/com.epicgames.FortniteGame_40.40.1_und3fined.ipa`,
get in a match, watch for the kick.
- **If the kick stops** → confirmed: it was our overly‑broad hook. Done.
- **If it still kicks** → the kick is NOT our hook. The community reports
  sideloaded Fortnite as "non‑functional online since v40.20" — i.e. Epic's
  **server‑side integrity / anti‑tamper enforcement**, which is not
  client‑side‑fixable and is **out of scope** (do not attempt to circumvent a
  game's anti‑cheat). Report that honestly and stop.

> Note: `KickPlayerPakFileViolation` is server‑delivered (`ClientWasKicked`).
> The client never logged a local pak failure. Keep an open mind — verify, do
> not assume either way.

## 8. Tooling (created this session)

### `tools/fnmac.sh`
`build | clean | patch | install <ipa> | launch | status | logs | monitor | redeploy <ipa>`
— wraps the whole workflow.

### `tools/patch_ipa.py`
Static IPA patcher (isiOSAppOnMac selector rename + the 3 MKW branch patches,
§5). **Superseded by the dynamic hooks** — kept as reference/fallback.
`python3 tools/patch_ipa.py <in.ipa> -o <out.ipa>`.

### Hard‑won gotchas (already encoded in the tooling)
- `cider` is an interactive TUI → run it under a pseudo‑tty: `script -q /dev/null cider sign ...`.
- `cider sign` flags used: `--apple-id --ellekit --tweak <dylib> --install --mac`.
- After install, the app must be `lsregister`‑ed or `open` is a no‑op:
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

These compile and are verified (tweak loads, Fortnite reaches a match). They are worth committing to a branch / PR regardless of the §7 outcome.

## 10. Boundary
Making the app **run** on a Mac (sideload, the macOS‑compat hooks, the crash
fix, KBM input) is in scope. **Defeating Fortnite's server‑side anti-cheat /
anti‑tamper** so a modified client can play online is **not** — if §7's
narrow‑hook test does not fix the kick, the cause is Epic's server‑side
enforcement; report it honestly and do not attempt to circumvent it. reverse engineer the fortnite binary to bypass the checks. do only static analysis. dont run/install anything