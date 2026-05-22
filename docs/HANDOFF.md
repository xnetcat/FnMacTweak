# FnMacTweak — Session Handoff

You are picking up work on **FnMacTweak**, a Theos tweak that adds
keyboard / mouse / controller support to **Fortnite (iOS) running on Apple
Silicon Macs** via the iOS-on-Mac runtime. This document is the full state from
the previous session.

## Repo & environment

- **Repo:** `/Users/xnetcat/Projects/xnetcat/FnMacTweak`
  - remotes: `origin` = `github.com/KohlerVG/FnMacTweak`, `fork` = `github.com/xnetcat/FnMacTweak`
  - currently on branch `main`; session changes are **uncommitted**
- **Host:** macOS 26.5 (25F5068a), Apple M4, arm64
- **Toolchain:** Xcode 26.2 + iOS SDK 26.2; Theos at `~/theos`; `gmake`, `ldid` via Homebrew
- **Signing/install:** `cider` 0.1.6. A cider Apple ID account is saved
  (`eboy.kubus.uwu@gmail.com`, team `7YU3P8HDSL`); cert at
  `~/Downloads/7YU3P8HDSL_certificate.p12`. `cider` is an interactive TUI — run
  it under a pseudo-tty (`script -q /dev/null cider …`).
- **IPAs in `~/Downloads`:**
  - `com.epicgames.FortniteGame_40.40.1_und3fined.ipa` — raw decrypted 40.40.1 (current)
  - `Fortnite-40.40.1-patched.ipa` — 40.40.1 with the static IPA patches applied
  - `Fortnite-40.30.ipa`, `Fortnite-40.30-base.ipa` — older; 40.30 is version-walled online

## Critical fix made this session — the tweak now actually loads

The `Makefile` had `TARGET := iphone:clang:latest:26.0`. That built the dylib
with **minimum iOS 26.0**, and the iOS-on-Mac runtime presents an iOS version
**below 26** — so dyld silently skipped the (weak-linked) tweak. **FnMacTweak
was never loading at all.**

- Fixed: `Makefile` `TARGET` → `iphone:clang:latest:17.0`
- Added `-Wno-error=unguarded-availability-new` to `FnMacTweak_CFLAGS`
  (Theos `-Werror` flagged `GCVirtualController.hidden`, an iOS-17 API already
  runtime-guarded with `respondsToSelector:`)
- Verified loaded into the live process with `vmmap`.

**Do not regress `TARGET` back to 26.0.** Everything else in the Fortnite app
has min-iOS ≤ 17; the tweak must too.

## Code changes — `src/Tweak.xm`

- **Crash-fix hook reworked.** `_availability_version_check` is hooked via
  fishhook (registered in the `%ctor` `rebind_symbols` call alongside
  `sysctl`/`sysctlbyname`). It forces exact iOS `@available` versions to
  "unavailable". Now: a `{version, reason}` table, NULL-arg / NULL-orig
  defensive guards, optional `-DFN_CRASHFIX_VERBOSE=1` logging, exact-match
  only (kept intentionally narrow). Currently blocks iOS 17.4.0.
- **`%hook NSProcessInfo`** — `-isiOSAppOnMac` returns `NO`.

## Tooling — `tools/`

- **`fnmac.sh`** — workflow CLI. Subcommands: `build`, `clean`, `install <ipa>`,
  `launch`, `status`, `logs`, `monitor`, `patch <ipa>`, `redeploy <ipa>`.
  Encodes the gotchas: cider needs a PTY; cider-installed apps must be
  `lsregister`-ed before `open` works; build target must stay low.
- **`patch_ipa.py`** — static IPA patcher (selector rename + MarketplaceKitWrapper
  branch patches); finds the selector by `__objc_methname` section scan.
- **`README.md`** — tooling docs.

## docs/

- `investigation-report.md` — full investigation write-up
- `HANDOFF.md` — this file

## Build / install / run

```sh
cd /Users/xnetcat/Projects/xnetcat/FnMacTweak
THEOS=~/theos ./tools/fnmac.sh build              # -> .theos/obj/debug/FnMacTweak.dylib
./tools/fnmac.sh redeploy <ipa>                   # build + clean + install + launch
./tools/fnmac.sh status                           # installed? running? tweak loaded?
./tools/fnmac.sh logs                             # crash reports / system log
```

- cider installs iOS-on-Mac apps under `/Applications/iOS/…`; FnMacAssistant's
  "Apply Patch" moves it to `/Applications/Fortnite.app`.
- Bundle id after cider signing: `com.epicgames.FortniteGame.7YU3P8HDSL`.
- Fortnite's own logs: `~/Library/Containers/<UUID>/Data/Documents/FortniteGame/Saved/Logs/FortniteGame.log`
  (the `<UUID>` container is identified by `MCMMetadataIdentifier` in its
  `.com.apple.containermanagerd.metadata.plist`).

## Current state

Fortnite **40.40.1** + FnMacTweak: **builds, signs, installs, launches, loads
the tweak, and reaches an actual match.** The macOS-26 launch crash and the
client-side sideload checks are handled.

## Known blocker (current state, documented — investigated, not a task)

~40 seconds into a match the **server** kicks the client:
`ClientWasKicked` → `KickPlayerPakFileViolation` → "errors in your installation."

Investigation (full logs + two binary RE passes) concluded:
- It is **server-issued** — `KickPlayerPakFileViolation` is not in the client's
  `EFortKickReason` enum.
- The **client's local state is clean** — install completed, all pak chunk
  hashes pass (`NumChunkDbChunksFailed: 0`), no local signature failures.
- It belongs to Fortnite's **pak-integrity / anti-tamper subsystem**. The
  legacy `isiOSAppOnMac` + MarketplaceKitWrapper patches do **not** prevent it
  on 40.40.1 — Epic strengthened the server-side integrity validation.

## Open items (continuation work)

- Apply the reworked crash-fix hook to the standalone `FnMacCrashFix` repo
  (`github.com/xnetcat/FnMacCrashFix`) for parity.
- Commit the session changes (`Makefile`, `src/Tweak.xm`, `tools/`, `docs/`) to
  a branch and open a PR.
- Bump the tweak version and update `CHANGELOG.md` (note: tweak now loads on
  the iOS-on-Mac runtime; build target corrected to iOS 17).
- FnMacTweak's gameplay features (KBM / controller / gyro / `P`-menu) are
  testable once the app is running.
