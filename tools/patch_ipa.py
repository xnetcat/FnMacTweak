#!/usr/bin/env python3
"""
patch_ipa.py — patch a raw Fortnite IPA so it runs sideloaded on Apple Silicon Macs.

Applies the two macOS-compatibility patches the community relies on:

  1. Rename the Objective-C selector  isiOSAppOnMac -> isProxy  inside the main
     binary's __TEXT,__objc_methname section.  Calls to
     -[NSProcessInfo isiOSAppOnMac] then resolve to -[NSObject isProxy] (which
     returns NO), so Fortnite stops taking its broken "running on a Mac" path.

  2. Force MarketplaceKitWrapper's fallback paths by turning three conditional
     branches (TBZ/TBNZ) into unconditional ones — bypasses sideload detection.

Unlike the old offset-hardcoded scripts this locates the selector by scanning
the methname section, so it survives Fortnite updates that shift the binary.
The MarketplaceKitWrapper patch verifies the original bytes before writing and
is a no-op if they no longer match (so it fails loud instead of corrupting).

Patched binaries lose their Apple signature — re-sign the IPA afterwards
(`cider sign` / `fnmac install` does this).

    tools/patch_ipa.py <input.ipa> [-o <output.ipa>]
"""
from __future__ import annotations

import argparse
import struct
import sys
import zipfile
from pathlib import Path

APP_DIR  = "Payload/FortniteClient-IOS-Shipping.app"
MAIN_BIN = f"{APP_DIR}/FortniteClient-IOS-Shipping"
MKW_BIN  = f"{APP_DIR}/Frameworks/MarketplaceKitWrapper.framework/MarketplaceKitWrapper"

# selector rename — both byte strings are 14 bytes (13 chars + NUL)
OLD_SELECTOR = b"isiOSAppOnMac\x00"
NEW_SELECTOR = b"isProxy\x00\x00\x00\x00\x00\x00\x00"

# MarketplaceKitWrapper: file offset -> (expected original word, patched word).
# Each turns a TBZ/TBNZ (opcode family 0x36) into an unconditional B (0x14).
MKW_PATCHES = [
    (0x65A4, bytes.fromhex("40040036"), bytes.fromhex("22000014")),
    (0x7B24, bytes.fromhex("80040036"), bytes.fromhex("24000014")),
    (0x999C, bytes.fromhex("a0180036"), bytes.fromhex("c5000014")),
]

MACHO_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64  = 0x19


def methname_range(data: bytes) -> tuple[int, int] | None:
    """Return (file_offset, size) of __TEXT,__objc_methname, or None."""
    if len(data) < 32 or struct.unpack_from("<I", data, 0)[0] != MACHO_MAGIC_64:
        return None
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == LC_SEGMENT_64:
            segname = data[off + 8:off + 24].rstrip(b"\0")
            nsects = struct.unpack_from("<I", data, off + 64)[0]
            soff = off + 72
            for _ in range(nsects):
                sectname = data[soff:soff + 16].rstrip(b"\0")
                if segname == b"__TEXT" and sectname == b"__objc_methname":
                    size    = struct.unpack_from("<Q", data, soff + 40)[0]
                    foffset = struct.unpack_from("<I", data, soff + 48)[0]
                    return foffset, size
                soff += 80
        off += cmdsize
    return None


def patch_main(data: bytearray) -> int:
    """Rename every isiOSAppOnMac selector inside __objc_methname. Returns count."""
    rng = methname_range(bytes(data))
    if rng is None:
        sys.exit("[!] could not locate __TEXT,__objc_methname — unexpected Mach-O")
    lo, hi = rng[0], rng[0] + rng[1]
    count, i = 0, lo
    while True:
        j = data.find(OLD_SELECTOR, i, hi)
        if j < 0:
            break
        data[j:j + len(NEW_SELECTOR)] = NEW_SELECTOR
        print(f"  main 0x{j:x}: isiOSAppOnMac -> isProxy")
        count += 1
        i = j + len(NEW_SELECTOR)
    return count


def patch_mkw(data: bytearray) -> int:
    """Apply the three MarketplaceKitWrapper branch patches. Returns count applied/ok."""
    ok = 0
    for off, old, new in MKW_PATCHES:
        cur = bytes(data[off:off + 4])
        if cur == new:
            print(f"  mkw  0x{off:x}: already patched")
            ok += 1
        elif cur == old:
            data[off:off + 4] = new
            print(f"  mkw  0x{off:x}: {old.hex()} -> {new.hex()}")
            ok += 1
        else:
            print(f"  mkw  0x{off:x}: UNEXPECTED {cur.hex()} (want {old.hex()}) — SKIPPED")
    return ok


def process(in_ipa: Path, out_ipa: Path) -> None:
    with zipfile.ZipFile(in_ipa) as zin:
        names = set(zin.namelist())
        if MAIN_BIN not in names:
            sys.exit(f"[!] {MAIN_BIN} not found in IPA")

        print(f"[+] patching main binary ({MAIN_BIN})")
        main_data = bytearray(zin.read(MAIN_BIN))
        n = patch_main(main_data)
        print(f"    {n} selector(s) renamed")
        if n == 0:
            print("    (warning: nothing renamed — already patched, or selector moved)")

        mkw_data = None
        if MKW_BIN in names:
            print(f"[+] patching MarketplaceKitWrapper")
            mkw_data = bytearray(zin.read(MKW_BIN))
            patch_mkw(mkw_data)
        else:
            print("[!] MarketplaceKitWrapper not present — skipped")

        print(f"[+] repacking -> {out_ipa}")
        with zipfile.ZipFile(out_ipa, "w") as zout:
            for item in zin.infolist():
                if item.filename == MAIN_BIN:
                    payload = bytes(main_data)
                elif mkw_data is not None and item.filename == MKW_BIN:
                    payload = bytes(mkw_data)
                else:
                    payload = zin.read(item.filename)
                zi = zipfile.ZipInfo(item.filename, date_time=item.date_time)
                zi.compress_type = item.compress_type
                zi.external_attr = item.external_attr
                zi.internal_attr = item.internal_attr
                zi.create_system = item.create_system
                zout.writestr(zi, payload)
    print(f"[+] done: {out_ipa}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Patch a raw Fortnite IPA for sideloaded Mac use.")
    ap.add_argument("ipa", type=Path, help="input .ipa")
    ap.add_argument("-o", "--output", type=Path, help="output .ipa (default: <input>-patched.ipa)")
    args = ap.parse_args()
    in_ipa = args.ipa.resolve()
    if not in_ipa.is_file():
        sys.exit(f"[!] not found: {in_ipa}")
    out_ipa = (args.output or in_ipa.with_name(in_ipa.stem + "-patched.ipa")).resolve()
    if out_ipa == in_ipa:
        sys.exit("[!] output must differ from input")
    process(in_ipa, out_ipa)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
