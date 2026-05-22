#!/bin/bash
#
# fnmac.sh — FnMacTweak / Fortnite-on-Mac development workflow tool
#
# Wraps the repetitive operations involved in building FnMacTweak, injecting it
# into a Fortnite IPA, installing it onto this Mac via cider, and then
# inspecting state / collecting logs / cleaning up between runs.
#
#   tools/fnmac.sh <command> [args]
#   tools/fnmac.sh help
#
# Encodes the gotchas discovered the hard way:
#   * cider is an interactive TUI -> must run under a pseudo-tty (script -q)
#   * cider-installed iOS-on-Mac apps must be lsregister'd before `open` works
#   * the tweak must be built with a low deployment target (iOS 17), otherwise
#     dyld silently skips the weak-linked dylib on the iOS-on-Mac runtime
#   * cleanup must use precise bundle-id patterns, never a broad "*fortnite*"
#
set -u

# ─── Configuration ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TWEAK_NAME="FnMacTweak"
: "${THEOS:=$HOME/theos}"

BUNDLE_PREFIX="com.epicgames.FortniteGame"   # Fortnite bundle-id prefix
EXEC_NAME="FortniteClient-IOS-Shipping"      # inner iOS executable / bundle name
INSTALL_DIR="/Applications/iOS"              # where cider installs iOS-on-Mac apps
DIAG="$HOME/Library/Logs/DiagnosticReports"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
STAGED_DYLIB="$REPO_DIR/.theos/obj/debug/$TWEAK_NAME.dylib"

# ─── Output helpers ──────────────────────────────────────────────────────────
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; X=$'\033[0m'
else B=''; G=''; Y=''; R=''; X=''; fi
say()  { printf '%s==>%s %s\n' "$B$G" "$X" "$*"; }
warn() { printf '%s !! %s%s\n' "$Y" "$*" "$X"; }
err()  { printf '%s xx %s%s\n' "$R" "$*" "$X" >&2; }
info() { printf '    %s\n' "$*"; }

# ─── Discovery helpers ───────────────────────────────────────────────────────
fn_app() {        # echo the outer installed .app, or return 1
  local c
  for c in "$INSTALL_DIR/$EXEC_NAME.app" "/Applications/$EXEC_NAME.app" "/Applications/Fortnite.app"; do
    [ -d "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}
fn_inner() {      # echo the inner iOS .app (handles the Wrapper/ layout)
  local app; app="$(fn_app)" || return 1
  if [ -d "$app/Wrapper" ]; then printf '%s\n' "$app/Wrapper/$EXEC_NAME.app"
  else printf '%s\n' "$app"; fi
}
fn_pid() { pgrep -f "$EXEC_NAME" 2>/dev/null | head -1; }
fn_bundle_id() {
  local inner; inner="$(fn_inner 2>/dev/null)"
  if [ -n "$inner" ] && [ -f "$inner/Info.plist" ]; then
    local id; id="$(plutil -extract CFBundleIdentifier raw "$inner/Info.plist" 2>/dev/null)"
    [ -n "$id" ] && { printf '%s\n' "$id"; return 0; }
  fi
  printf '%s\n' "$BUNDLE_PREFIX"
}

# ─── build ───────────────────────────────────────────────────────────────────
cmd_build() {
  [ -d "$THEOS" ] || { err "Theos not found (\$THEOS=$THEOS)"; return 1; }
  command -v gmake >/dev/null || { err "gmake missing — brew install make"; return 1; }
  say "Building $TWEAK_NAME   (THEOS=$THEOS)"
  ( cd "$REPO_DIR" \
      && THEOS="$THEOS" gmake clean >/dev/null 2>&1 \
      && THEOS="$THEOS" gmake "$@" 2>&1 \
         | grep -E 'error:|Linking|Merging|Signing|Error [0-9]' )
  local dyl
  dyl="$(find "$REPO_DIR/.theos/obj" -maxdepth 2 -name "$TWEAK_NAME.dylib" 2>/dev/null | head -1)"
  [ -f "$dyl" ] || { err "build failed — no dylib produced"; return 1; }
  # normalise the install-name so it resolves as @rpath once injected
  install_name_tool -id "@rpath/$TWEAK_NAME.dylib" "$dyl" 2>/dev/null
  codesign -f -s - "$dyl" >/dev/null 2>&1
  local minos
  minos="$(otool -l "$dyl" 2>/dev/null | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')"
  cp "$dyl" "$STAGED_DYLIB" 2>/dev/null
  say "Built: $dyl"
  info "min iOS : ${minos:-?}      arch: $(lipo -archs "$dyl" 2>/dev/null)"
  case "${minos:-0}" in
    2[0-9].*) warn "min iOS $minos is too high — dyld will skip it on iOS-on-Mac (use <= 18)";;
  esac
}

# ─── clean ───────────────────────────────────────────────────────────────────
cmd_clean() {
  local dry=0
  case "${1:-}" in -n|--dry-run) dry=1; say "DRY RUN — nothing will be deleted";; esac
  local RM="rm -rf"; [ "$dry" = 1 ] && RM="echo     would-remove:"

  say "Stopping Fortnite"
  [ "$dry" = 0 ] && { pkill -9 -f "$EXEC_NAME" 2>/dev/null && info "killed running process"; }

  say "Removing app bundles"
  local p
  for p in "$INSTALL_DIR/$EXEC_NAME.app" "/Applications/Fortnite.app" "/Applications/$EXEC_NAME.app"; do
    [ -e "$p" ] && $RM "$p"
  done
  [ "$dry" = 0 ] && rmdir "$INSTALL_DIR" 2>/dev/null

  say "Removing per-app data (containers / caches / prefs / state)"
  local d base f
  for d in Containers "Group Containers" Caches HTTPStorages WebKit \
           "Application Scripts" "Saved Application State" Preferences; do
    base="$HOME/Library/$d"; [ -d "$base" ] || continue
    while IFS= read -r f; do [ -n "$f" ] && $RM "$f"; done < <(
      find "$base" -maxdepth 1 \( -iname "${BUNDLE_PREFIX}*" -o -iname "${EXEC_NAME}*" \) 2>/dev/null )
  done
  # iOS-on-Mac containers are UUID-named — match them via the bundle id in metadata
  for c in "$HOME/Library/Containers"/*/; do
    [ -d "$c" ] || continue
    meta="${c}.com.apple.containermanagerd.metadata.plist"
    if [ -f "$meta" ] && plutil -extract MCMMetadataIdentifier raw "$meta" 2>/dev/null | grep -qi "$BUNDLE_PREFIX"; then
      $RM "$c"
    fi
  done
  # crash-reporter state + recent-document shared file lists (bundle-id scoped)
  while IFS= read -r f; do [ -n "$f" ] && $RM "$f"; done < <(
    find "$HOME/Library/Application Support/CrashReporter" -maxdepth 1 -iname "${EXEC_NAME}*" 2>/dev/null )
  while IFS= read -r f; do [ -n "$f" ] && $RM "$f"; done < <(
    find "$HOME/Library/Application Support/com.apple.sharedfilelist" -iname "${BUNDLE_PREFIX}*" 2>/dev/null )

  say "Removing crash reports"
  while IFS= read -r f; do [ -n "$f" ] && $RM "$f"; done < <(
    find "$DIAG" -maxdepth 1 -iname "${EXEC_NAME}*" 2>/dev/null )

  say "Removing app-translocation staging copies"
  while IFS= read -r f; do
    [ -n "$f" ] && $RM "$(printf '%s' "$f" | sed -E 's#(/X/[^/]+)/.*#\1#')"
  done < <( find /private/var/folders -maxdepth 8 -path "*/X/*/Wrapper/$EXEC_NAME.app" -type d 2>/dev/null )

  if [ "$dry" = 0 ]; then
    killall cfprefsd 2>/dev/null
    "$LSREGISTER" -kill -r -domain local -domain user >/dev/null 2>&1
    say "Clean complete"
  fi
}

# ─── patch ───────────────────────────────────────────────────────────────────
cmd_patch() {
  local ipa="${1:-}" out="${2:-}"
  [ -f "$ipa" ] || { err "usage: fnmac patch <raw.ipa> [output.ipa]"; return 1; }
  command -v python3 >/dev/null || { err "python3 not found"; return 1; }
  [ -n "$out" ] || out="${ipa%.ipa}-patched.ipa"
  say "Patching IPA for sideloaded Mac use (isiOSAppOnMac + MarketplaceKitWrapper)"
  python3 "$SCRIPT_DIR/patch_ipa.py" "$ipa" -o "$out" || { err "patch failed"; return 1; }
  say "Patched IPA ready: $out"
}

# ─── install ─────────────────────────────────────────────────────────────────
cmd_install() {
  local ipa="${1:-}" dyl="${2:-$STAGED_DYLIB}"
  [ -f "$ipa" ] || { err "usage: fnmac install <fortnite.ipa> [tweak.dylib]"; return 1; }
  [ -f "$dyl" ] || { err "tweak dylib missing: $dyl   (run: fnmac build)"; return 1; }
  command -v cider >/dev/null || { err "cider not installed"; return 1; }
  say "Signing IPA + injecting $TWEAK_NAME + installing to Mac"
  info "ipa   : $ipa"
  info "tweak : $dyl"
  # cider is an interactive TUI; a pseudo-tty (script -q) lets it run unattended
  script -q /dev/null cider sign "$ipa" --apple-id --ellekit --tweak "$dyl" --install --mac
  local rc=$?
  [ $rc -ne 0 ] && { err "cider sign failed (rc=$rc)"; return $rc; }
  local app; app="$(fn_app)"
  [ -n "$app" ] && "$LSREGISTER" -f -R "$app" 2>/dev/null && say "Registered with LaunchServices"
  say "Install complete — run: fnmac launch"
}

# ─── launch ──────────────────────────────────────────────────────────────────
cmd_launch() {
  local app; app="$(fn_app)" || { err "Fortnite not installed — run: fnmac install <ipa>"; return 1; }
  "$LSREGISTER" -f -R "$app" 2>/dev/null
  local bid; bid="$(fn_bundle_id)"
  say "Launching $bid"
  open -b "$bid" 2>/dev/null || open "$app"
}

# ─── status ──────────────────────────────────────────────────────────────────
cmd_status() {
  say "Fortnite-on-Mac status"
  local app inner pid
  if app="$(fn_app)"; then info "installed  : $app"; else info "installed  : ${R}NO${X}"; fi
  inner="$(fn_inner 2>/dev/null)"
  if [ -n "$inner" ] && [ -f "$inner/Info.plist" ]; then
    info "version    : $(plutil -extract CFBundleShortVersionString raw "$inner/Info.plist" 2>/dev/null)"
    info "bundle id  : $(fn_bundle_id)"
    if otool -L "$inner/$EXEC_NAME" 2>/dev/null | grep -qi "$TWEAK_NAME"; then
      info "tweak wired: yes (@rpath load command present)"
    else
      info "tweak wired: ${Y}no${X}"
    fi
  fi
  pid="$(fn_pid)"
  if [ -n "$pid" ]; then
    info "running    : yes (pid $pid)"
    if vmmap "$pid" 2>/dev/null | grep -qi "$TWEAK_NAME"; then
      info "tweak live : ${G}LOADED${X}"
    else
      info "tweak live : ${R}NOT loaded${X}"
    fi
  else
    info "running    : no"
  fi
  info "containers : $(find "$HOME/Library/Containers" -maxdepth 1 -iname "${BUNDLE_PREFIX}*" 2>/dev/null | wc -l | tr -d ' ')"
  local n; n="$(ls "$DIAG/${EXEC_NAME}"*.ips 2>/dev/null | wc -l | tr -d ' ')"
  info "crash logs : ${n:-0}"
  [ "${n:-0}" != 0 ] && ls -t "$DIAG/${EXEC_NAME}"*.ips 2>/dev/null | head -3 | sed 's/^/               /'
}

# ─── logs ────────────────────────────────────────────────────────────────────
cmd_logs() {
  local latest
  latest="$(ls -t "$DIAG/${EXEC_NAME}"*.ips 2>/dev/null | head -1)"
  case "${1:-list}" in
    crash|latest|show)
      [ -n "$latest" ] || { warn "no crash report found"; return 1; }
      say "Latest crash report: $latest"
      cat "$latest" ;;
    list|"")
      say "Crash reports in $DIAG"
      ls -t "$DIAG/${EXEC_NAME}"*.ips 2>/dev/null | sed 's/^/    /' || info "(none)"
      say "Recent system log (last 5 min)"
      log show --last 5m --predicate "process == \"$EXEC_NAME\"" --style compact 2>/dev/null | tail -40 ;;
    *) err "usage: fnmac logs [crash|list]"; return 1 ;;
  esac
}

# ─── monitor ─────────────────────────────────────────────────────────────────
cmd_monitor() {
  local timeout="${1:-600}" start; start="$(date +%s)"
  local baseline; baseline="$(ls "$DIAG/${EXEC_NAME}"*.ips 2>/dev/null | sort)"
  say "Monitoring for a Fortnite crash (${timeout}s)…  Ctrl-C to stop"
  while [ $(( $(date +%s) - start )) -lt "$timeout" ]; do
    local new
    new="$(comm -13 <(printf '%s\n' "$baseline") <(ls "$DIAG/${EXEC_NAME}"*.ips 2>/dev/null | sort) | grep -v '^$')"
    if [ -n "$new" ]; then say "CRASH REPORT: $new"; return 0; fi
    if [ -z "$(fn_pid)" ]; then
      warn "Fortnite process exited — waiting 8s for a report…"; sleep 8
      new="$(comm -13 <(printf '%s\n' "$baseline") <(ls "$DIAG/${EXEC_NAME}"*.ips 2>/dev/null | sort) | grep -v '^$')"
      [ -n "$new" ] && say "CRASH REPORT: $new" || warn "process gone, no crash report written"
      return 0
    fi
    sleep 3
  done
  warn "timeout — no crash within ${timeout}s"
}

# ─── redeploy (full cycle) ───────────────────────────────────────────────────
cmd_redeploy() {
  local ipa="${1:-}"
  [ -f "$ipa" ] || { err "usage: fnmac redeploy <fortnite.ipa>"; return 1; }
  cmd_build          || return 1
  cmd_clean          || return 1
  cmd_install "$ipa" || return 1
  cmd_launch
}

# ─── help / dispatch ─────────────────────────────────────────────────────────
cmd_help() {
  cat <<EOF
${B}fnmac.sh${X} — FnMacTweak / Fortnite-on-Mac workflow tool

  ${B}build${X}                  Clean-build FnMacTweak (Theos) -> injectable dylib
  ${B}clean${X} [-n]             Remove every Fortnite trace: app bundles, containers,
                         caches, prefs, saved state, crash logs, translocation
                         staging, LaunchServices.  -n / --dry-run = preview only.
  ${B}patch${X} <ipa> [out]      Apply macOS-compat patches to a raw Fortnite IPA
                         (isiOSAppOnMac selector rename + MarketplaceKitWrapper)
  ${B}install${X} <ipa> [dylib]  Sign the IPA with cider, inject the tweak, install
                         to this Mac.  dylib defaults to the last build.
  ${B}launch${X}                 Register + launch the installed Fortnite
  ${B}status${X}                 Installed? running? tweak loaded? containers? logs?
  ${B}logs${X} [crash|list]      List crash reports, or dump the newest one
  ${B}monitor${X} [seconds]      Watch for a Fortnite crash (default 600s)
  ${B}redeploy${X} <ipa>         build -> clean -> install -> launch  (full cycle)
  ${B}help${X}                   This message

  config:  THEOS=$THEOS
           repo =$REPO_DIR
EOF
}

main() {
  local cmd="${1:-help}"; [ $# -gt 0 ] && shift
  case "$cmd" in
    build)         cmd_build "$@";;
    clean)         cmd_clean "$@";;
    patch)         cmd_patch "$@";;
    install)       cmd_install "$@";;
    launch)        cmd_launch "$@";;
    status)        cmd_status "$@";;
    logs)          cmd_logs "$@";;
    monitor)       cmd_monitor "$@";;
    redeploy)      cmd_redeploy "$@";;
    help|-h|--help) cmd_help;;
    *) err "unknown command: $cmd"; echo; cmd_help; return 1;;
  esac
}
main "$@"
