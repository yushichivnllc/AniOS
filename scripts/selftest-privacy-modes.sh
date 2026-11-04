#!/usr/bin/env bash
# Offline tests for fail-closed AniTails browser launch and privacy policy assets.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
AIROOTFS="$ROOT_DIR/profile/airootfs"
TAILS="$AIROOTFS/usr/local/bin/anios-tails"
ANIX="$AIROOTFS/usr/local/bin/anix"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-privacy-selftest.XXXXXX")"
trap 'rm -rf -- "$SANDBOX"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

for script in "$TAILS" "$ANIX" \
  "$AIROOTFS/usr/local/lib/anios/anios-tails-firewall" \
  "$AIROOTFS/usr/local/lib/anios/anios-tails-network-guard" \
  "$AIROOTFS/usr/local/lib/anios/anix-isolation-firewall"; do
  [[ -x "$script" ]] || fail "privacy helper is not executable: ${script#"$ROOT_DIR/"}"
  bash -n "$script" || fail "shell syntax error: ${script#"$ROOT_DIR/"}"
done

BIN="$SANDBOX/bin"
RUNTIME="$SANDBOX/runtime"
mkdir -p "$BIN" "$RUNTIME"
cat >"$BIN/systemctl" <<'FAKE'
#!/usr/bin/env bash
[[ "${1:-}" == is-active && "${2:-}" == --quiet ]] || exit 90
case "${3:-}" in
  anios-tails-firewall.service) [[ "${ANIOS_TEST_FIREWALL:-active}" == active ]] ;;
  anios-tor.service) [[ "${ANIOS_TEST_TOR:-active}" == active ]] ;;
  *) exit 91 ;;
esac
FAKE
cat >"$BIN/firefox" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${ANIOS_TEST_FIREFOX_LOG:?}"
FAKE
cat >"$BIN/nft" <<'FAKE'
#!/usr/bin/env bash
[[ "${ANIOS_TEST_NFT:-active}" == active ]]
FAKE
chmod 0755 "$BIN/systemctl" "$BIN/firefox" "$BIN/nft"
printf 'BOOT_IMAGE=test anios_mode=anitails\n' >"$SANDBOX/cmdline"
printf 'BOOT_IMAGE=test\n' >"$SANDBOX/normal-cmdline"

set +e
env PATH="$BIN:$PATH" ANIOS_PROC_CMDLINE="$SANDBOX/not-anitails" \
  "$TAILS" >"$SANDBOX/no-mode.out" 2>&1
status=$?
set -e
[[ $status -eq 2 ]] || fail "AniTails browser must refuse to start outside AniTails mode (status=$status)"
[[ ! -e "$SANDBOX/firefox.log" ]] || fail "Firefox started outside AniTails mode"
pass "browser refuses normal AniOS sessions"

# NetworkManager must refuse an uplink if booted in AniTails mode but the
# system-wide nftables kill-switch failed to load.
if env PATH="$BIN:$PATH" ANIOS_PROC_CMDLINE="$SANDBOX/normal-cmdline" \
  ANIOS_NFT_BIN="$BIN/nft" ANIOS_TEST_NFT=inactive \
  "$AIROOTFS/usr/local/lib/anios/anios-tails-network-guard"; then
  :
else
  fail "normal AniOS should not require the AniTails firewall"
fi
set +e
env PATH="$BIN:$PATH" ANIOS_PROC_CMDLINE="$SANDBOX/cmdline" \
  ANIOS_NFT_BIN="$BIN/nft" ANIOS_TEST_NFT=inactive \
  "$AIROOTFS/usr/local/lib/anios/anios-tails-network-guard" >"$SANDBOX/guard.out" 2>&1
status=$?
set -e
[[ $status -eq 1 ]] || fail "NetworkManager guard must fail when the AniTails firewall is absent"
env PATH="$BIN:$PATH" ANIOS_PROC_CMDLINE="$SANDBOX/cmdline" \
  ANIOS_NFT_BIN="$BIN/nft" ANIOS_TEST_NFT=active \
  "$AIROOTFS/usr/local/lib/anios/anios-tails-network-guard" ||
  fail "NetworkManager guard rejected an installed AniTails firewall"
pass "NetworkManager cannot start in AniTails if the firewall failed"

set +e
env PATH="$BIN:$PATH" ANIOS_PROC_CMDLINE="$SANDBOX/cmdline" \
  ANIOS_TEST_FIREWALL=inactive ANIOS_TEST_FIREFOX_LOG="$SANDBOX/firefox.log" \
  "$TAILS" >"$SANDBOX/no-firewall.out" 2>&1
status=$?
set -e
[[ $status -eq 3 ]] || fail "AniTails browser must fail closed without firewall (status=$status)"
[[ ! -e "$SANDBOX/firefox.log" ]] || fail "Firefox started without the kill switch"
pass "browser refuses to start without the kill switch"

set +e
env PATH="$BIN:$PATH" ANIOS_PROC_CMDLINE="$SANDBOX/cmdline" \
  ANIOS_TEST_FIREWALL=active ANIOS_TEST_TOR=inactive ANIOS_TEST_FIREFOX_LOG="$SANDBOX/firefox.log" \
  "$TAILS" >"$SANDBOX/no-tor.out" 2>&1
status=$?
set -e
[[ $status -eq 4 ]] || fail "AniTails browser must fail closed without Tor (status=$status)"
[[ ! -e "$SANDBOX/firefox.log" ]] || fail "Firefox started without Tor"
pass "browser refuses to start without Tor"

env PATH="$BIN:$PATH" ANIOS_PROC_CMDLINE="$SANDBOX/cmdline" \
  ANIOS_TEST_FIREWALL=active ANIOS_TEST_TOR=active \
  ANIOS_TEST_FIREFOX_LOG="$SANDBOX/firefox.log" XDG_RUNTIME_DIR="$RUNTIME" \
  "$TAILS"
grep -q -- '--no-remote' "$SANDBOX/firefox.log" || fail "Tor Firefox must use an isolated browser process"
profile="$(awk 'previous == "--profile" { print; exit } { previous=$0 }' "$SANDBOX/firefox.log")"
[[ "$profile" == "$RUNTIME/anios-tails-firefox" ]] || fail "Firefox profile must be stored in the volatile runtime directory"
for pref in \
  'network.proxy.socks_port", 9050' \
  'network.proxy.socks_remote_dns", true' \
  'network.proxy.failover_direct", false' \
  'media.peerconnection.enabled", false' \
  'browser.privatebrowsing.autostart", true'; do
  grep -qF "$pref" "$profile/user.js" || fail "temporary Firefox profile is missing $pref"
done
pass "Firefox proxy profile is temporary and forbids direct fallback"

python3 - "$AIROOTFS/etc/nftables/anios-tails.nft" "$AIROOTFS/etc/nftables/anix-isolation.nft" <<'PY'
from pathlib import Path
import sys

tor = Path(sys.argv[1]).read_text()
for required in (
    'type filter hook input priority filter; policy drop;',
    'type filter hook output priority filter; policy drop;',
    'udp dport 53 redirect to :5353',
    'tcp dport 53 redirect to :5353',
    'meta l4proto tcp redirect to :9040',
    'meta skuid "tor" accept',
):
    assert required in tor, f"AniTails firewall misses {required}"
anix = Path(sys.argv[2]).read_text()
assert 'iifname "virbr-anix" oifname != "virbr-anix" counter drop' in anix
PY
pass "Tor egress kill-switch and Anix host-forward guard rules are present"

DOMAIN_HELPER="$AIROOTFS/usr/local/lib/anios/anix-domain-interfaces.py"
cat >"$SANDBOX/domain.xml" <<'XML'
<domain type='kvm'>
  <name>sample</name>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <disk type='file'><source file='/tmp/sample.qcow2'/></disk>
    <interface type='network'>
      <mac address='52:54:00:aa:bb:01'/>
      <source network='default'/>
      <target dev='vnet0'/>
      <model type='virtio'/>
      <address type='pci' slot='0x03'/>
    </interface>
    <interface type='network'><mac address='52:54:00:aa:bb:02'/><source network='default'/></interface>
    <graphics type='spice'/>
  </devices>
</domain>
XML
python3 "$DOMAIN_HELPER" rewrite "$SANDBOX/domain.xml" "$SANDBOX/gateway.xml" gateway
python3 "$DOMAIN_HELPER" verify "$SANDBOX/gateway.xml" gateway || fail "Gateway did not get exactly WAN + internal NICs"
python3 "$DOMAIN_HELPER" rewrite "$SANDBOX/domain.xml" "$SANDBOX/workstation.xml" workstation
python3 "$DOMAIN_HELPER" verify "$SANDBOX/workstation.xml" workstation || fail "Workstation did not get only its internal NIC"
python3 - "$SANDBOX/gateway.xml" "$SANDBOX/workstation.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

gateway, workstation = (ET.parse(path).getroot() for path in sys.argv[1:])
gateway_devices = gateway.find("devices")
interfaces = gateway_devices.findall("interface")
assert [node.find("source").get("network") for node in interfaces] == ["anix-wan", "anix-internal"]
assert interfaces[0].find("mac").get("address") == "52:54:00:aa:bb:01"
assert interfaces[0].find("address").get("slot") == "0x03"
assert [node.tag for node in gateway_devices].index("interface") < [node.tag for node in gateway_devices].index("graphics")
workstation_interfaces = workstation.findall("./devices/interface")
assert len(workstation_interfaces) == 1
assert workstation_interfaces[0].find("source").get("network") == "anix-internal"
PY
cp "$SANDBOX/workstation.xml" "$SANDBOX/unsafe.xml"
python3 - "$SANDBOX/unsafe.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
iface = ET.SubElement(root.find("devices"), "interface", {"type": "network"})
ET.SubElement(iface, "source", {"network": "anix-wan"})
ET.ElementTree(root).write(sys.argv[1])
PY
if python3 "$DOMAIN_HELPER" verify "$SANDBOX/unsafe.xml" workstation >/dev/null 2>&1; then
  fail "Anix verifier accepted a Workstation with an extra WAN NIC"
fi
pass "Anix rewrites and verifies Gateway/Workstation NIC separation, preserving guest MACs"
