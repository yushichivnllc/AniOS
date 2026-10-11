#!/usr/bin/env bash
# Tự kiểm tra scripts/../profile/airootfs/usr/local/bin/anios-netcheck mà không
# cần root, không cần mạng và không cần Arch Linux.
#
# anios-netcheck chỉ được chạy thật trong phiên live, nhưng toàn bộ logic của nó
# (đọc glibc qua `getent`, đo IPv4/IPv6 bằng `curl`, đọc DNS đang dùng qua
# `resolvectl`, sửa `/etc/resolv.conf` và `/etc/gai.conf`) đều đi qua những lệnh
# ngoài — nên ở đây thay chúng bằng lệnh giả có ghi nhật ký, rồi chạy đúng script
# thật với ANIOS_NETCHECK_ROOT trỏ vào một cây /etc giả.
#
# Các kịch bản được kiểm tra:
#   1. mạng tốt                       → exit 0, không báo lỗi
#   2. DNS chết hoàn toàn             → báo lỗi, --fix ghi lại /etc/resolv.conf
#   3. DNS chỉ hỏng với tên Valve      → phân biệt được với DNS chết, gợi ý --fix-dns
#   4. IPv6 nửa sống                  → báo lỗi, --fix thêm ưu tiên IPv4 vào gai.conf
#   5. captive portal trả HTML        → nhận ra portal thay vì "mạng hỏng"
#   6. --quiet cho unit               → không in báo cáo từng bước
#   7. --fix-dns                      → ghi DNS công cộng và chặn NetworkManager ghi đè
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKER="$ROOT_DIR/profile/airootfs/usr/local/bin/anios-netcheck"

[[ -x "$CHECKER" ]] || { echo "FAIL: thiếu hoặc không chạy được $CHECKER" >&2; exit 1; }
bash -n "$CHECKER" || { echo "FAIL: lỗi cú pháp bash trong $CHECKER" >&2; exit 1; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-netcheck-selftest.XXXXXX")"
cleanup() { rm -rf -- "$SANDBOX"; }
trap cleanup EXIT

FAKE_BIN="$SANDBOX/bin"
FAKE_ROOT="$SANDBOX/root"
mkdir -p -- "$FAKE_BIN" "$FAKE_ROOT/etc/NetworkManager/conf.d"

failures=0
report_ok() { echo "  OK    $*"; }
report_fail() {
  echo "  FAIL  $*" >&2
  sed 's/^/        /' "$SANDBOX/out.txt" >&2
  failures=$((failures + 1))
}

# --- lệnh giả ---------------------------------------------------------------
cat >"$FAKE_BIN/getent" <<'FAKE'
#!/usr/bin/env bash
# getent ahosts <tên>: in ra địa chỉ theo kịch bản.
[[ "${1:-}" == "ahosts" ]] || exit 2
host="${2:?}"
case "$host" in
  *steam*|*valve*)
    case "${FAKE_DNS_STEAM:-ok}" in
      ok) ;;
      fail) exit 2 ;;
    esac
    ;;
  *)
    case "${FAKE_DNS_OTHER:-ok}" in
      ok) ;;
      fail) exit 2 ;;
    esac
    ;;
esac
printf '%s  STREAM %s\n' "${FAKE_V4:-93.184.216.34}" "$host"
if [[ "${FAKE_V6:-1}" == 1 ]]; then
  printf '%s  STREAM %s\n' "2606:2800:220:1:248:1893:25c8:1946" "$host"
fi
FAKE
chmod +x "$FAKE_BIN/getent"

cat >"$FAKE_BIN/curl" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
out=""
format="%{http_code}"
args=()
while (($#)); do
  case "$1" in
    -o) out="${2:?}"; shift 2 ;;
    -w) format="${2:?}"; shift 2 ;;
    -4 | -6) args+=("$1"); shift ;;
    --connect-timeout | --max-time) shift 2 ;;
    -sS | -s | -S) shift ;;
    http*|https*) url="$1"; shift ;;
    *) shift ;;
  esac
done
want_v6=0
for arg in ${args[@]+"${args[@]}"}; do [[ "$arg" == "-6" ]] && want_v6=1; done

code=200
ctype=application/octet-stream
body='"ubuntu12"
{"version" "1"}
'
case "$url" in
  "http://1.1.1.1/") code="${FAKE_IPV4_CODE:-200}" ;;
  "http://[2606:4700:4700::1111]/") code="${FAKE_IPV6_CODE:-200}" ;;
  *)
    code="${FAKE_STEAM_CODE:-200}"
    if [[ "${FAKE_STEAM_HTML:-0}" == 1 ]]; then
      ctype=text/html
      body='<html><body>Wi-Fi login</body></html>
'
    fi
    ;;
esac
if [[ -n "$out" && "$out" != "/dev/null" ]]; then
  printf '%s' "$body" >"$out"
fi
# curl thật in ra trường -w NGAY CẢ KHI kết nối thất bại (http_code = 000)
# rồi mới thoát bằng mã lỗi 7. Lệnh giả phải bắt chước đúng như vậy, nếu không
# thì lỗi "000 nối thành 000000" trong anios-netcheck sẽ không bao giờ lộ ra.
if [[ "$format" == *content_type* ]]; then
  printf '%s %s' "$code" "$ctype"
else
  printf '%s' "$code"
fi
if [[ "$code" == "000" ]]; then
  exit 7
fi
exit 0
FAKE
chmod +x "$FAKE_BIN/curl"

cat >"$FAKE_BIN/ip" <<'FAKE'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "-4 route") echo "default via 192.168.1.1 dev eth0 proto dhcp src 192.168.1.20 metric 100" ;;
  "-6 addr")
    if [[ -n "${FAKE_IPV6_ADDR:-}" ]]; then
      echo "    inet6 ${FAKE_IPV6_ADDR}/64 scope global dynamic"
    fi
    ;;
esac
exit 0
FAKE
chmod +x "$FAKE_BIN/ip"

cat >"$FAKE_BIN/nmcli" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  *"device status"*) echo "eth0:ethernet:connected" ;;
  *"-f CONNECTIVITY g"*) echo "full" ;;
esac
exit 0
FAKE
chmod +x "$FAKE_BIN/nmcli"

cat >"$FAKE_BIN/resolvectl" <<'FAKE'
#!/usr/bin/env bash
if [[ "${FAKE_NO_DNS_SERVERS:-0}" != 1 ]]; then
  echo "      Current DNS Server: 192.168.1.1"
fi
exit 0
FAKE
chmod +x "$FAKE_BIN/resolvectl"

cat >"$FAKE_BIN/timedatectl" <<'FAKE'
#!/usr/bin/env bash
echo "${FAKE_NTP:-yes}"
FAKE
chmod +x "$FAKE_BIN/timedatectl"

cat >"$FAKE_BIN/systemctl" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
chmod +x "$FAKE_BIN/systemctl"

# --- khung chạy -------------------------------------------------------------
reset_root() {
  rm -rf -- "$FAKE_ROOT"
  mkdir -p -- "$FAKE_ROOT/etc/NetworkManager/conf.d"
  printf 'nameserver 192.168.1.1\n' >"$FAKE_ROOT/etc/resolv.conf"
}

run_checker() {
  local -a envs=("ANIOS_NETCHECK_ROOT=$FAKE_ROOT" "PATH=$FAKE_BIN:$PATH")
  local name
  while (($#)); do
    name="$1"
    shift
    envs+=("$name")
  done
  set +e
  env "${envs[@]}" "$CHECKER" ${EXTRA_ARGS:-} >"$SANDBOX/out.txt" 2>&1
  status=$?
  set -e
  return 0
}

expect_status() {
  if [[ "$status" != "$1" ]]; then
    report_fail "$2 (exit=$status, mong đợi $1)"
  fi
}
has() { grep -qF -- "$1" "$SANDBOX/out.txt"; }
expect_out() { has "$1" && report_ok "$2" || report_fail "$2 (thiếu: $1)"; }
reject_out() { ! has "$1" && report_ok "$2" || report_fail "$2 (không mong đợi: $1)"; }

echo "--- 1. mạng tốt ---"
reset_root
EXTRA_ARGS="--wait 0"
run_checker "FAKE_DNS_STEAM=ok" "FAKE_IPV4_CODE=200" "FAKE_IPV6_CODE=200" "FAKE_STEAM_CODE=200"
expect_status 0 "mạng tốt thì exit 0"
expect_out "nội dung manifest hợp lệ" "tải được manifest client của Steam"
reject_out "Phát hiện" "không báo vấn đề nào"

echo "--- 2. DNS chết hoàn toàn ---"
reset_root
run_checker "FAKE_DNS_STEAM=fail" "FAKE_DNS_OTHER=fail" "FAKE_IPV4_CODE=200"
expect_status 1 "DNS chết thì exit 1"
expect_out "KHÔNG phân giải được" "báo đúng tên Valve không phân giải được"
expect_out "example.com cũng không phân giải được" "phân biệt DNS chết hoàn toàn"
expect_out "--fix" "gợi ý cách sửa"
# --fix phải thay /etc/resolv.conf sau khi đã thử khởi động lại resolved.
reset_root
EXTRA_ARGS="--wait 0 --fix"
run_checker "FAKE_DNS_STEAM=fail" "FAKE_DNS_OTHER=fail" "FAKE_IPV4_CODE=200"
if grep -q '^nameserver 1.1.1.1$' "$FAKE_ROOT/etc/resolv.conf"; then
  report_ok "--fix ghi lại /etc/resolv.conf với DNS công cộng"
else
  report_fail "--fix không ghi lại /etc/resolv.conf"
  sed 's/^/        /' "$FAKE_ROOT/etc/resolv.conf" >&2 || true
fi
[[ -e "$FAKE_ROOT/run/anios-netcheck/resolv.conf.bak" ]] &&
  report_ok "--fix sao lưu resolv.conf cũ" ||
  report_fail "--fix không sao lưu resolv.conf cũ"

echo "--- 3. DNS chỉ hỏng với tên Valve (nhà mạng chặn) ---"
reset_root
EXTRA_ARGS="--wait 0"
run_checker "FAKE_DNS_STEAM=fail" "FAKE_DNS_OTHER=ok" "FAKE_IPV4_CODE=200"
expect_status 1 "DNS hỏng một phần thì exit 1"
expect_out "example.com phân giải được" "nhận ra DNS vẫn sống, chỉ tên Valve bị chặn/đầu độc"
expect_out "anios-netcheck --fix-dns" "gợi ý --fix-dns cho trường hợp nhà mạng chặn DNS"

echo "--- 4. IPv6 nửa sống ---"
reset_root
run_checker "FAKE_DNS_STEAM=ok" "FAKE_IPV4_CODE=200" "FAKE_IPV6_CODE=000" \
  "FAKE_IPV6_ADDR=2001:ee0:4f1a:7c00:1234:5678:9abc:def0" "FAKE_STEAM_CODE=200"
expect_status 1 "IPv6 nửa sống thì exit 1"
expect_out "IPv6 nửa sống" "gọi đúng tên vấn đề IPv6 nửa sống"
expect_out "anios-netcheck --fix" "gợi ý cách sửa"
reset_root
EXTRA_ARGS="--wait 0 --fix"
run_checker "FAKE_DNS_STEAM=ok" "FAKE_IPV4_CODE=200" "FAKE_IPV6_CODE=000" \
  "FAKE_IPV6_ADDR=2001:ee0:4f1a:7c00:1234:5678:9abc:def0" "FAKE_STEAM_CODE=200"
if grep -Eq '^precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100$' "$FAKE_ROOT/etc/gai.conf"; then
  report_ok "--fix thêm ưu tiên IPv4 vào /etc/gai.conf"
else
  report_fail "--fix không ghi /etc/gai.conf"
fi

# Dòng mặc định có dấu # không được coi là cấu hình đang bật; sau khi thêm rule,
# chạy lại --fix phải nhận ra rule đó và không nhân đôi.
reset_root
printf '%s\n' '#precedence ::ffff:0:0/96  100' >"$FAKE_ROOT/etc/gai.conf"
EXTRA_ARGS="--wait 0 --fix"
run_checker "FAKE_DNS_STEAM=ok" "FAKE_IPV4_CODE=200" "FAKE_IPV6_CODE=000" \
  "FAKE_IPV6_ADDR=2001:ee0:4f1a:7c00:1234:5678:9abc:def0" "FAKE_STEAM_CODE=200"
active_precedence="$(grep -Ec '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100([[:space:]]|$)' \
  "$FAKE_ROOT/etc/gai.conf" || true)"
[[ "$active_precedence" == 1 ]] &&
  report_ok "dòng precedence bị comment không chặn việc thêm rule đang bật" ||
  report_fail "dòng comment bị hiểu nhầm là rule đang bật"

run_checker "FAKE_DNS_STEAM=ok" "FAKE_IPV4_CODE=200" "FAKE_IPV6_CODE=000" \
  "FAKE_IPV6_ADDR=2001:ee0:4f1a:7c00:1234:5678:9abc:def0" "FAKE_STEAM_CODE=200"
active_precedence="$(grep -Ec '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100([[:space:]]|$)' \
  "$FAKE_ROOT/etc/gai.conf" || true)"
[[ "$active_precedence" == 1 ]] &&
  report_ok "--fix lặp lại không nhân đôi rule ưu tiên IPv4" ||
  report_fail "--fix lặp lại đã nhân đôi rule ưu tiên IPv4"

echo "--- 5. captive portal trả HTML ---"
reset_root
EXTRA_ARGS="--wait 0"
run_checker "FAKE_DNS_STEAM=ok" "FAKE_IPV4_CODE=200" "FAKE_STEAM_HTML=1"
expect_status 1 "captive portal thì exit 1"
expect_out "captive portal" "nhận ra captive portal thay vì 'mạng hỏng'"

echo "--- 6. --quiet cho unit ---"
reset_root
EXTRA_ARGS="--quiet --wait 0"
run_checker "FAKE_DNS_STEAM=ok" "FAKE_IPV4_CODE=200" "FAKE_IPV6_CODE=200" "FAKE_STEAM_CODE=200"
expect_status 0 "--quiet với mạng tốt thì exit 0"
reject_out "1/6" "--quiet không in báo cáo từng bước"
EXTRA_ARGS="--quiet --wait 0"
run_checker "FAKE_DNS_STEAM=fail" "FAKE_DNS_OTHER=fail" "FAKE_IPV4_CODE=200"
expect_status 1 "--quiet vẫn trả exit 1 khi có lỗi"
expect_out "KHÔNG phân giải được" "--quiet vẫn in cảnh báo lỗi"

echo "--- 7. --fix-dns (người dùng chủ động) ---"
reset_root
EXTRA_ARGS="--wait 0 --fix-dns"
run_checker "FAKE_DNS_STEAM=ok" "FAKE_IPV4_CODE=200" "FAKE_STEAM_CODE=200"
grep -q '^nameserver 1.1.1.1$' "$FAKE_ROOT/etc/resolv.conf" &&
  report_ok "--fix-dns ghi DNS công cộng" ||
  report_fail "--fix-dns không ghi DNS công cộng"
grep -qxF 'dns=none' "$FAKE_ROOT/etc/NetworkManager/conf.d/99-anios-netcheck.conf" &&
  report_ok "--fix-dns chặn NetworkManager ghi đè resolv.conf" ||
  report_fail "--fix-dns không tạo drop-in cho NetworkManager"

echo "--- 8. thiếu máy chủ DNS ---"
reset_root
rm -f -- "$FAKE_ROOT/etc/resolv.conf"
EXTRA_ARGS="--wait 0"
run_checker "FAKE_NO_DNS_SERVERS=1" "FAKE_DNS_STEAM=fail" "FAKE_DNS_OTHER=fail" "FAKE_IPV4_CODE=200"
expect_status 1 "không có DNS nào thì exit 1"
expect_out "Không tìm thấy máy chủ DNS nào" "báo đúng khi không có nameserver"

echo "--- 9. tham số sai ---"
reset_root
EXTRA_ARGS="--khong-co"
run_checker "FAKE_DNS_STEAM=ok"
expect_status 2 "tham số không hợp lệ thì exit 2"

if ((failures)); then
  echo "FAIL: $failures trường hợp sai trong bài tự kiểm tra" >&2
  exit 1
fi
echo "PASS: anios-netcheck chẩn đoán đúng DNS, IPv6, captive portal và các bước --fix"
