# tools/

## `fnmac.sh`

Workflow tool for building **FnMacTweak** and running it inside Fortnite on an
Apple Silicon Mac (Fortnite iOS via the iOS-on-Mac runtime, signed with `cider`).

```sh
tools/fnmac.sh <command>
```

| Command | Purpose |
|---|---|
| `build` | Clean-build the tweak with Theos → injectable dylib |
| `clean [-n]` | Remove **all** Fortnite traces (apps, containers, caches, prefs, saved state, crash logs, translocation staging, LaunchServices). `-n` / `--dry-run` previews |
| `install <ipa> [dylib]` | Sign the IPA with cider, inject the tweak, install to this Mac |
| `launch` | Register + launch the installed Fortnite |
| `status` | Installed / running / tweak-loaded / containers / crash-log overview |
| `logs [crash\|list]` | List crash reports, or dump the newest `.ips` |
| `monitor [seconds]` | Watch for a Fortnite crash (default 600s) |
| `redeploy <ipa>` | `build` → `clean` → `install` → `launch` (full iteration cycle) |

### Requirements

- Theos at `$THEOS` (default `~/theos`), `gmake`, `ldid`
- `cider` with a signed-in Apple ID account
- Xcode + the iOS SDK

### Gotchas baked into the tool

- **cider is an interactive TUI** — it is run under a pseudo-tty (`script -q /dev/null`) so it works unattended.
- **cider-installed iOS-on-Mac apps must be `lsregister`'d** before `open` will launch them.
- **The tweak must target a low iOS version (≤ 18).** A high deployment target makes dyld silently skip the weak-linked dylib on the iOS-on-Mac runtime — the tweak then never loads. See `Makefile`'s `TARGET`.
- **Cleanup uses precise bundle-id patterns** (`com.epicgames.FortniteGame*`, `FortniteClient-IOS-Shipping*`) — never a broad `*fortnite*`, which would catch unrelated files.
