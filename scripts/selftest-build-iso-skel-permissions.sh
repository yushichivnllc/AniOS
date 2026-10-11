#!/usr/bin/env bash
# Regression test for restoring executable modes in the three AniOS skeletons
# after mkarchiso strips file modes from the airootfs copy.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/scripts/list-skel-file-permissions.sh"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-iso.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -x "$HELPER" ]] || fail "skeleton permission helper is missing or not executable"
[[ -s "$BUILD_SCRIPT" ]] || fail "ISO build script is missing"
grep -qF 'list-skel-file-permissions.sh' "$BUILD_SCRIPT" ||
  fail "build-iso.sh does not collect the skeleton executable modes"
grep -qF 'ANIOS_FILE_PERMISSIONS[${#ANIOS_FILE_PERMISSIONS[@]}]="$skeleton_permission"' "$BUILD_SCRIPT" ||
  fail "build-iso.sh does not add skeleton entries to file_permissions"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-skel-permissions-selftest.XXXXXX")"
cleanup() {
  if [[ -n "${ANIOS_SELFTEST_KEEP_SANDBOX:-}" ]]; then
    echo "Sandbox kept at: $SANDBOX" >&2
    return 0
  fi
  rm -rf -- "$SANDBOX"
}
trap cleanup EXIT

AIROOTFS="$SANDBOX/airootfs"
mkdir -p \
  "$AIROOTFS/home/anios/.config/demo" \
  "$AIROOTFS/etc/skel/bin" \
  "$AIROOTFS/usr/share/anios/skel/.config/demo"
printf '#!/bin/sh\nexit 0\n' >"$AIROOTFS/home/anios/.config/demo/home-tool"
printf '#!/bin/sh\nexit 0\n' >"$AIROOTFS/etc/skel/bin/skel-tool"
printf '#!/bin/sh\nexit 0\n' >"$AIROOTFS/usr/share/anios/skel/.config/demo/source-tool"
printf 'not executable\n' >"$AIROOTFS/usr/share/anios/skel/.config/demo/data.txt"
chmod 0750 "$AIROOTFS/home/anios/.config/demo/home-tool"
chmod 0755 "$AIROOTFS/etc/skel/bin/skel-tool"
chmod 0711 "$AIROOTFS/usr/share/anios/skel/.config/demo/source-tool"
ln -s source-tool "$AIROOTFS/usr/share/anios/skel/.config/demo/source-tool-link"

output="$("$HELPER" "$AIROOTFS")"
expected=(
  '/etc/skel/bin/skel-tool:0:0:755'
  '/home/anios/.config/demo/home-tool:0:0:750'
  '/usr/share/anios/skel/.config/demo/source-tool:0:0:711'
)
for entry in "${expected[@]}"; do
  grep -qxF "$entry" <<<"$output" || fail "missing generated file_permissions entry: $entry"
done
[[ "$(wc -l <<<"$output")" -eq "${#expected[@]}" ]] ||
  fail "the helper emitted unexpected entries (including a data file or symlink)"
SKELETON_FILE_PERMISSIONS=()
ANIOS_FILE_PERMISSIONS=()
mapfile -t SKELETON_FILE_PERMISSIONS <<<"$output"
for skeleton_permission in "${SKELETON_FILE_PERMISSIONS[@]}"; do
  ANIOS_FILE_PERMISSIONS[${#ANIOS_FILE_PERMISSIONS[@]}]="$skeleton_permission"
done
[[ "${#ANIOS_FILE_PERMISSIONS[@]}" -eq "${#expected[@]}" ]] ||
  fail "the build's array append step did not preserve all generated permissions"
pass "executable modes from home/anios, etc/skel, and usr/share/anios/skel are collected exactly"

# Fail closed if a build accidentally stops preparing one of the three copies.
MISSING_ROOT="$SANDBOX/missing-root"
mkdir -p "$MISSING_ROOT/home/anios"
if "$HELPER" "$MISSING_ROOT" >"$SANDBOX/missing.out" 2>&1; then
  fail "the helper accepted an airootfs missing skeleton directories"
fi
grep -qF 'Missing skeleton directory:' "$SANDBOX/missing.out" ||
  fail "a missing skeleton directory did not produce a useful error"
pass "a missing skeleton copy stops permission collection"

echo "All skeleton file_permissions self-tests passed."
