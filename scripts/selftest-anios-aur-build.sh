#!/usr/bin/env bash
# Tự kiểm tra scripts/anios-aur-build.sh mà không cần Arch Linux, không cần mạng
# và không cần quyền root thật.
#
# Script dựng gói AUR chỉ chạy bên trong chroot airootfs lúc dựng ISO, nên mỗi lần
# muốn kiểm chứng thật phải chờ một lượt dựng ISO hàng chục phút. Bài này thay
# toàn bộ công cụ Arch (pacman, makepkg, git, curl, install, runuser, setpriv,
# useradd...) bằng bản giả có ghi nhật ký lời gọi, rồi chạy đúng script đó trên một
# airootfs giả. Nhờ vậy những lỗi sau bị bắt trong vài giây:
#
#   * đọc sai manifest (comment, khoảng trắng, ràng buộc "=phiên bản", tên gói lạ);
#   * đọc phụ thuộc sai từ .SRCINFO (biến thể theo kiến trúc, "go>=1.24");
#   * cài lại phụ thuộc ảnh đã có, hoặc đem cài dep "ảo" (java-runtime);
#   * chạy makepkg bằng root (makepkg thật từ chối) hoặc quên hạ quyền;
#   * quên pacman -U gói đã dựng, nên ảnh live không có gói AUR;
#   * dọn mồ côi làm mất gói của ảnh live, hoặc để lại makedepend chỉ cần lúc dựng;
#   * một gói dựng hỏng mà script vẫn trả exit 0 → ISO thiếu gói nhưng CI xanh;
#   * cấp sudo/NOPASSWD cho tài khoản dựng gói (không được phép tồn tại);
#   * để sót thư mục dựng gói / tài khoản tạm trong ảnh.
#
# Chạy: ./scripts/selftest-anios-aur-build.sh
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER="$ROOT_DIR/scripts/anios-aur-build.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

[[ -x "$BUILDER" ]] || fail "thiếu hoặc không chạy được $BUILDER"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/anios-aur-selftest.XXXXXX")"
cleanup() {
  # ANIOS_SELFTEST_KEEP_SANDBOX=1 giữ lại sandbox để mổ xẻ khi bài kiểm tra hỏng.
  if [[ -n "${ANIOS_SELFTEST_KEEP_SANDBOX:-}" ]]; then
    echo "Sandbox giữ lại tại: $SANDBOX" >&2
    return 0
  fi
  rm -rf -- "$SANDBOX"
}
trap cleanup EXIT

FAKE_BIN="$SANDBOX/bin"
FIXTURES="$SANDBOX/aur"
mkdir -p -- "$FAKE_BIN" "$FIXTURES"

# --- AUR giả: mỗi package base là một thư mục có PKGBUILD và .SRCINFO ------
# Số liệu lấy từ AUR thật (rpc/v5/info) để bài kiểm tra bám sát thực tế:
#   yay                    depends pacman>6.1, git; makedepends go>=1.24
#   coccoc-browser-stable  depends qt5-base, ttf-liberation, libx11, glibc...
#   legacy-launcher        depends java-runtime (dep "ảo": pacman -Sp không tìm
#                          thấy gói cùng tên, chỉ jre-openjdk thoả mãn được)
make_fixture() {
  local pkg="$1" srcinfo="$2"
  mkdir -p -- "$FIXTURES/$pkg"
  printf '%s\n' "pkgname = $pkg" >"$FIXTURES/$pkg/PKGBUILD"
  printf '%s\n' "$srcinfo" >"$FIXTURES/$pkg/.SRCINFO"
}

make_fixture yay 'pkgbase = yay
	pkgdesc = Yet another yogurt. Pacman wrapper and AUR helper written in go.
	depends = pacman>6.1
	depends = git
	makedepends = go>=1.24
	pkgname = yay'

make_fixture coccoc-browser-stable 'pkgbase = coccoc-browser-stable
	pkgdesc = The web browser from Coc Coc.
	depends = qt5-base
	depends = ttf-liberation
	depends = libx11
	depends = glibc>=2.38
	depends_x86_64 = lib32-fake-arch-dep
	depends_i686 = unavailable-i686-library
	checkdepends = unavailable-test-tool
	checkdepends_x86_64 = unavailable-arch-test-tool
	optdepends = pipewire
	pkgname = coccoc-browser-stable'

make_fixture legacy-launcher 'pkgbase = legacy-launcher
	pkgdesc = Stable, fast and simple Minecraft Launcher.
	depends = java-runtime
	pkgname = legacy-launcher'

make_fixture calamares 'pkgbase = calamares
	pkgdesc = Distribution-independent installer framework.
	depends = qt5-base
	pkgname = calamares'
cat >"$FIXTURES/calamares/PKGBUILD" <<'EOF'
build() {
  local _skip_modules=(
    packagechooser
    packagechooserq
  )
}
EOF

# Gói luôn dựng hỏng, để kiểm tra đường lỗi.
make_fixture broken-package 'pkgbase = broken-package
	depends = git
	pkgname = broken-package'

# --- pacman giả ------------------------------------------------------------
# Trạng thái: $FAKE_PACMAN_STATE/installed, mỗi dòng "<tên>\t<phiên bản>\t<reason>"
#             (reason: explicit = người dùng/manifest cài, depend = --asdeps)
# Nhật ký:    $FAKE_PACMAN_STATE/calls — mọi lời gọi, để bài kiểm tra đối chiếu.
cat >"$FAKE_BIN/pacman" <<'FAKE'
#!/usr/bin/env bash
set -uo pipefail
state="${FAKE_PACMAN_STATE:?}"
printf 'pacman %s\n' "$*" >>"$state/calls"
touch "$state/installed"

is_installed() { cut -f1 "$state/installed" | grep -qxF -- "$1"; }
mark() { # $1 tên, $2 phiên bản, $3 reason
  awk -F'\t' -v n="$1" '$1 != n' "$state/installed" >"$state/installed.tmp"
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$state/installed.tmp"
  mv -- "$state/installed.tmp" "$state/installed"
}
unmark() {
  awk -F'\t' -v n="$1" '$1 != n' "$state/installed" >"$state/i.tmp"
  mv -- "$state/i.tmp" "$state/installed"
}

op="${1:-}"; shift || true
targets=()
has_flag() { printf '%s\n' "$@" | grep -qxF -- "$1"; }
all_args=("$op" "$@")
while (($#)); do
  case "$1" in
    --) ;;
    -*) ;;
    *) targets+=("$1") ;;
  esac
  shift
done

# Kho chính thức giả: pacman -Sp chỉ tìm được những gói này.
repo_version() {
  case "$1" in
    base-devel | git | go | pacman | qt5-base | ttf-liberation | libx11) ;;
    glibc | jre-openjdk | archlinux-keyring | lib32-fake-arch-dep) ;;
    dkms | libglvnd | jansson | libxext | zlib) ;;
    *) return 1 ;;
  esac
  echo 1
}

case "$op" in
  -T | --deptest)
    # pacman -T in ra những phụ thuộc CHƯA được thoả. java-runtime không có gói
    # cùng tên nhưng đã được jre-openjdk cung cấp — mô phỏng đúng hành vi đó.
    for dep in ${targets[@]+"${targets[@]}"}; do
      name="${dep%%[<>=]*}"
      if is_installed "$name"; then continue; fi
      if [[ "$name" == java-runtime ]] && is_installed jre-openjdk; then continue; fi
      # nvidia-580xx-utils có provides=(nvidia-utils): khi nó đã cài thì
      # phụ thuộc nvidia-utils của nvidia-580xx-settings được thoả.
      if [[ "$name" == nvidia-utils ]] && is_installed nvidia-580xx-utils; then continue; fi
      printf '%s\n' "$dep"
    done
    exit 0
    ;;
  -Sp)
    for dep in ${targets[@]+"${targets[@]}"}; do
      repo_version "${dep%%[<>=]*}" >/dev/null || exit 1
    done
    exit 0
    ;;
  -S*)
    # -Sy đơn thuần (refresh DB) không có target thì không làm gì.
    ((${#targets[@]})) || exit 0
    for dep in "${targets[@]}"; do
      name="${dep%%[<>=]*}"
      repo_version "$name" >/dev/null || {
        echo "error: target not found: $name" >&2
        exit 1
      }
      if has_flag --asdeps "${all_args[@]}"; then
        mark "$name" 1.0-1 depend
      else
        mark "$name" 1.0-1 explicit
      fi
    done
    exit 0
    ;;
  -U*)
    for file in "${targets[@]}"; do
      [[ -e "$file" ]] || { echo "error: '$file' does not exist" >&2; exit 1; }
      base="$(basename -- "$file")"
      name="$(sed -E 's/-[^-]+-[^-]+-[^-]+\.pkg\.tar.*$//' <<<"$base")"
      if has_flag --asexplicit "${all_args[@]}"; then
        mark "$name" 13.0.1-1 explicit
      else
        mark "$name" 13.0.1-1 depend
      fi
    done
    exit 0
    ;;
  -R*)
    for dep in ${targets[@]+"${targets[@]}"}; do unmark "$dep"; done
    exit 0
    ;;
  -Qdtq)
    awk -F'\t' '$3 == "depend" {print $1}' "$state/installed"
    exit 0
    ;;
  -Qq)
    cut -f1 "$state/installed"
    exit 0
    ;;
  -Q*)
    ((${#targets[@]})) || exit 0
    for dep in "${targets[@]}"; do
      is_installed "$dep" || exit 1
      printf '%s %s\n' "$dep" "$(awk -F'\t' -v n="$dep" '$1 == n {print $2}' "$state/installed")"
    done
    exit 0
    ;;
esac
echo "fake pacman: lời gọi không hỗ trợ: pacman $op $*" >&2
exit 1
FAKE
chmod 0755 -- "$FAKE_BIN/pacman"

# --- git/curl giả: AUR gốc, mirror GitHub và snapshot ----------------------
# yay mô phỏng lỗi TLS trên aur.example.invalid rồi tải được từ mirror GitHub;
# coccoc mô phỏng lỗi ở cả hai nguồn git rồi thành công qua snapshot cgit.
cat >"$FAKE_BIN/git" <<FAKE
#!/usr/bin/env bash
set -uo pipefail
printf 'git %s\n' "\$*" >>"\$FAKE_CALLS"
[[ "\${1:-}" == clone ]] || { echo "fake git: chỉ hỗ trợ clone" >&2; exit 1; }
shift
url="" dest="" branch=""
while ((\$#)); do
  case "\$1" in
    --branch) branch="\$2"; shift 2 ;;
    --depth) shift 2 ;;
    --single-branch | --quiet) shift ;;
    --)
      shift
      url="\$1"; dest="\$2"
      break
      ;;
    -*) shift ;;
    *)
      if [[ -z "\$url" ]]; then url="\$1"; else dest="\$1"; fi
      shift
      ;;
  esac
done
if [[ "\$url" == https://github.com/archlinux/aur.git ]]; then
  pkg="\$branch"
  if [[ "\${FAKE_FAIL_CALAMARES:-0}" == 1 && "\$pkg" == calamares ]]; then
    echo "fatal: unable to access '\$url': TLS connection failed" >&2
    exit 128
  fi
  if [[ "\$pkg" == coccoc-browser-stable ]]; then
    echo "fatal: remote branch '\$pkg' unavailable in test mirror" >&2
    exit 128
  fi
else
  pkg="\${url##*/}"; pkg="\${pkg%.git}"
  if [[ "\$pkg" == coccoc-browser-stable ]]; then
    echo "fatal: unable to access '\$url': The requested URL returned error: 403" >&2
    exit 128
  fi
  if [[ "\$pkg" == yay || "\$pkg" == calamares ]]; then
    echo "fatal: unable to access '\$url': TLS connect error: unexpected eof while reading" >&2
    exit 128
  fi
fi
[[ -d "$FIXTURES/\$pkg" ]] || { echo "fatal: repository '\$url' not found" >&2; exit 128; }
mkdir -p -- "\$dest"
cp -a -- "$FIXTURES/\$pkg/." "\$dest/"
exit 0
FAKE
chmod 0755 -- "$FAKE_BIN/git"

cat >"$FAKE_BIN/curl" <<FAKE
#!/usr/bin/env bash
set -uo pipefail
printf 'curl %s\n' "\$*" >>"\$FAKE_CALLS"
out="" url=""
while ((\$#)); do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
  esac
done
pkg="\$(basename -- "\$url" .tar.gz)"
if [[ "\${FAKE_FAIL_CALAMARES:-0}" == 1 && "\$pkg" == calamares ]]; then
  echo "curl: TLS connect error while requesting calamares snapshot" >&2
  exit 22
fi
[[ -n "\$out" && -d "$FIXTURES/\$pkg" ]] || exit 22
# Snapshot thật của AUR là tarball chứa thư mục <pkg>/; dựng đúng bố cục đó.
tmp="\$(mktemp -d)"
mkdir -p -- "\$tmp/\$pkg"
cp -a -- "$FIXTURES/\$pkg/." "\$tmp/\$pkg/"
tar -czf "\$out" -C "\$tmp" "\$pkg"
rm -rf -- "\$tmp"
exit 0
FAKE
chmod 0755 -- "$FAKE_BIN/curl"

# --- makepkg giả -----------------------------------------------------------
# broken-package luôn thất bại; gói khác sinh file .pkg.tar.zst ngay trong thư mục
# hiện tại (đúng như makepkg thật khi không đặt BUILDDIR).
cat >"$FAKE_BIN/makepkg" <<'FAKE'
#!/usr/bin/env bash
set -uo pipefail
printf 'makepkg %s\n' "$*" >>"$FAKE_CALLS"
# Ghi lại makepkg đang chạy dưới tài khoản nào.
id -un >"$FAKE_MAKEPKG_USER" 2>/dev/null || echo "?" >"$FAKE_MAKEPKG_USER"
if printf '%s\n' "$*" | grep -q -- '--printsrcinfo'; then
  cat ./.SRCINFO
  exit 0
fi
pkgdir="$(basename -- "$PWD")"
if [[ "$pkgdir" == calamares ]]; then
  if grep -qE '^[[:space:]]*packagechooser[[:space:]]*$' PKGBUILD; then
    echo "==> ERROR: packagechooser remains disabled in PKGBUILD." >&2
    exit 1
  fi
  grep -qE '^[[:space:]]*packagechooserq[[:space:]]*$' PKGBUILD || {
    echo "==> ERROR: unrelated packagechooserq setting was changed." >&2
    exit 1
  }
  touch "$FAKE_CALAMARES_CHOOSER_ENABLED"
fi
if [[ "$pkgdir" == nvidia-580xx-utils ]]; then
  # Gói tách: một PackageBase sinh nhiều file .pkg.tar (nvidia-580xx-utils và -dkms).
  : >"nvidia-580xx-utils-13.0.1-1-x86_64.pkg.tar.zst"
  : >"nvidia-580xx-dkms-13.0.1-1-x86_64.pkg.tar.zst"
  echo "==> Finished making: $pkgdir 13.0.1-1 (gói tách)"
  exit 0
fi
if [[ "$pkgdir" == nvidia-580xx-settings ]]; then
  # Gói tách: settings và libxnvctrl-580xx (cùng PackageBase, như AUR thật).
  : >"nvidia-580xx-settings-13.0.1-1-x86_64.pkg.tar.zst"
  : >"libxnvctrl-580xx-13.0.1-1-x86_64.pkg.tar.zst"
  echo "==> Finished making: $pkgdir 13.0.1-1 (gói tách)"
  exit 0
fi
if [[ "$pkgdir" == broken-package ]]; then
  echo "==> ERROR: A failure occurred in build()." >&2
  exit 1
fi
# Gói có PKGBUILD lệch sha256sums (AUR chưa kịp sửa sau khi upstream đổi file):
# makepkg thật từ chối gói với "did not pass the validity check"; chỉ khi được
# truyền --skipchecksums (lối thoát ANIOS_AUR_ALLOW_STALE_SUMS=1) mới dựng tiếp.
if [[ "$pkgdir" == stale-sums ]]; then
  if printf '%s\n' "$*" | grep -q -- '--skipchecksums'; then
    : >"$pkgdir-13.0.1-1-x86_64.pkg.tar.zst"
    echo "==> Finished making: $pkgdir 13.0.1-1 (bỏ qua kiểm tra checksum)"
    exit 0
  fi
  echo "==> Validating source files with sha256sums..." >&2
  echo "    LM-Studio-0.4.26-4-x64.AppImage ... FAILED" >&2
  echo "==> ERROR: One or more files did not pass the validity check!" >&2
  exit 1
fi
# Gói hỏng đúng một lần (nguồn tải bị cắt cụt) rồi thành công ở lượt thử lại.
if [[ "$pkgdir" == flaky-package ]]; then
  if [[ -e "$FAKE_MAKEPKG_FLAKY_MARK" ]]; then
    : >"$pkgdir-13.0.1-1-x86_64.pkg.tar.zst"
    echo "==> Finished making: $pkgdir 13.0.1-1"
    exit 0
  fi
  : >"$FAKE_MAKEPKG_FLAKY_MARK"
  echo "==> ERROR: Failure while downloading source archive" >&2
  echo "curl: (56) Recv failure: Connection reset by peer" >&2
  exit 1
fi
: >"$pkgdir-13.0.1-1-x86_64.pkg.tar.zst"
echo "==> Finished making: $pkgdir 13.0.1-1"
exit 0
FAKE
chmod 0755 -- "$FAKE_BIN/makepkg"

# --- install giả (bản thật từ chối -o/-g trong user namespace) -------------
cat >"$FAKE_BIN/install" <<'FAKE'
#!/usr/bin/env bash
set -uo pipefail
printf 'install %s\n' "$*" >>"$FAKE_CALLS"
dirs=0
args=()
while (($#)); do
  case "$1" in
    -d) dirs=1; shift ;;
    -m | -o | -g) shift 2 ;;
    --) shift ;;
    -*) shift ;;
    *) args+=("$1"); shift ;;
  esac
done
if (( dirs )); then
  mkdir -p -- "${args[@]}"
  exit 0
fi
case ${#args[@]} in
  0) exit 0 ;;
  1) mkdir -p -- "${args[0]}" ;;
  2) cp -- "${args[0]}" "${args[1]}" ;;
  *)
    # Như GNU install: nhiều nguồn -> thư mục đích (đích phải là thư mục).
    dest="${args[${#args[@]} - 1]}"
    [[ -d "$dest" ]] || { echo "fake install: đích không phải thư mục: $dest" >&2; exit 1; }
    for ((i = 0; i < ${#args[@]} - 1; i++)); do
      cp -- "${args[i]}" "$dest/"
    done
    ;;
esac
FAKE
chmod 0755 -- "$FAKE_BIN/install"

# --- runuser/setpriv giả: bỏ cờ chọn tài khoản rồi chạy phần lệnh còn lại ---
for tool in runuser setpriv; do
  cat >"$FAKE_BIN/$tool" <<FAKE
#!/usr/bin/env bash
set -uo pipefail
printf '%s %s\n' "$tool" "\$*" >>"\$FAKE_CALLS"
cmd=()
while ((\$#)); do
  case "\$1" in
    --user | -u) printf 'fake-%s\n' "\$2" >"\$FAKE_DROP_USER"; shift 2 ;;
    --uid | --gid) shift 2 ;;
    --reap | --init-groups) shift ;;
    --) shift; cmd+=("\$@"); break ;;
    *) cmd+=("\$@"); break ;;
  esac
done
(( \${#cmd[@]} > 0 )) || exit 0
"\${cmd[@]}"
FAKE
  chmod 0755 -- "$FAKE_BIN/$tool"
done

# --- Quản lý tài khoản và chown giả ---------------------------------------
for tool in groupadd userdel chown groupdel; do
  cat >"$FAKE_BIN/$tool" <<FAKE
#!/usr/bin/env bash
printf '%s %s\n' "$tool" "\$*" >>"\$FAKE_CALLS"
exit 0
FAKE
  chmod 0755 -- "$FAKE_BIN/$tool"
done

cat >"$FAKE_BIN/useradd" <<FAKE
#!/usr/bin/env bash
printf 'useradd %s\n' "\$*" >>"\$FAKE_CALLS"
touch "\$FAKE_USER_CREATED"
exit 0
FAKE
chmod 0755 -- "$FAKE_BIN/useradd"

cat >"$FAKE_BIN/getent" <<FAKE
#!/usr/bin/env bash
printf 'getent %s\n' "\$*" >>"\$FAKE_CALLS"
exit 2
FAKE
chmod 0755 -- "$FAKE_BIN/getent"

cat >"$FAKE_BIN/id" <<FAKE
#!/usr/bin/env bash
printf 'id %s\n' "\$*" >>"\$FAKE_CALLS" 2>/dev/null || true
case "\${1:-}" in
  -u)
    [[ -f "\$FAKE_USER_CREATED" ]] && { echo 1412; exit 0; }
    exit 1
    ;;
  -g)
    [[ -f "\$FAKE_USER_CREATED" ]] && { echo 1413; exit 0; }
    exit 1
    ;;
  -un)
    if [[ -n "\${FAKE_DROP_USER_FILE:-}" && -f "\${FAKE_DROP_USER_FILE:-}" ]]; then
      cat "\$FAKE_DROP_USER_FILE"
    else
      # Gọi thẳng binary thật: `command id` vẫn tra PATH nên đệ quy vô hạn
      # vào chính bản giả này.
      /usr/bin/id -un 2>/dev/null || echo unknown
    fi
    exit 0
    ;;
esac
/usr/bin/id "\$@"
FAKE
chmod 0755 -- "$FAKE_BIN/id"

# findmnt giả: /tmp của airootfs không noexec.
cat >"$FAKE_BIN/findmnt" <<FAKE
#!/usr/bin/env bash
printf 'findmnt %s\n' "\$*" >>"\$FAKE_CALLS"
echo "rw,relatime"
FAKE
chmod 0755 -- "$FAKE_BIN/findmnt"

cat >"$FAKE_BIN/repo-add" <<'FAKE'
#!/usr/bin/env bash
printf 'repo-add %s\n' "$*" >>"$FAKE_CALLS"
db=""
for arg in "$@"; do
  case "$arg" in
    -*) ;;
    *.db.tar.gz) db="$arg"; break ;;
  esac
done
[[ -n "$db" ]] && : >"$db"
exit 0
FAKE
chmod 0755 -- "$FAKE_BIN/repo-add"

# --- Chạy script thật trên airootfs giả ------------------------------------
# $1: manifest, $2: user|root, $3: nhãn (quyết định tên thư mục state/airootfs)
run_builder() {
  local manifest="$1" mode="$2" label="$3"
  local stage_calamares="${4:-0}" fail_calamares="${5:-0}"
  local state="$SANDBOX/state.$label"
  local airootfs="$SANDBOX/airootfs.$label"
  local staged_calamares="$airootfs/usr/share/anios/installer/calamares"
  local -a extra_env=()
  rm -rf -- "$state" "$airootfs"
  mkdir -p -- "$state" "$airootfs/root/.anios-aur" "$airootfs/usr/share/anios" \
    "$airootfs/var/tmp" "$airootfs/var/cache/pacman/pkg" \
    "$state/pacman-db/sync" "$state/makepkg-marks"
  # sync DB giả để bước kiểm tra sơ bộ của script không báo động oan trong bài
  # kiểm tra; bài riêng bên dưới trỏ ANIOS_AUR_PACMAN_DB vào thư mục rỗng để
  # chắc rằng cảnh báo vẫn bật khi airootfs thật sự chưa có sync DB.
  : >"$state/pacman-db/sync/core.db"
  mkdir -p -- "$airootfs/etc"
  printf '[options]\n[core]\nInclude = /etc/pacman.d/mirrorlist\n' >"$airootfs/etc/pacman.conf"
  if [[ "$stage_calamares" == 1 ]]; then
    mkdir -p -- "$staged_calamares"
  fi
  if [[ "$fail_calamares" == 1 ]]; then
    extra_env+=("FAKE_FAIL_CALAMARES=1")
  fi
  # Bài kiểm tra thêm biến môi trường riêng bằng cách gán EXTRA_BUILDER_ENV
  # (mảng) trước khi gọi; biến được xoá sau mỗi lượt để không lọt sang bài sau.
  if [[ -n "${EXTRA_BUILDER_ENV[*]:-}" ]]; then
    extra_env+=("${EXTRA_BUILDER_ENV[@]}")
  fi
  EXTRA_BUILDER_ENV=()
  : >"$state/calls"
  # Ảnh live giả: những gói packages.x86_64 đã cài TRƯỚC khi hook AUR chạy.
  printf '%s\t%s\t%s\n' \
    pacman 7.0-1 explicit \
    git 2.47.0-1 explicit \
    base-devel 1-2 explicit \
    jre-openjdk 21-1 explicit \
    qt5-base 5.15-1 explicit \
    ttf-liberation 2.1.5-1 explicit \
    libx11 1.8-1 explicit \
    glibc 2.40-1 explicit \
    python 3.13-1 explicit \
    nodejs 23-1 explicit \
    wine 10.0-1 explicit >"$state/installed"

  cp -- "$BUILDER" "$airootfs/root/.anios-aur/anios-aur-build.sh"
  cp -- "$manifest" "$airootfs/root/.anios-aur/packages.aur.x86_64"

  local -a cmd=(
    env
    "PATH=$FAKE_BIN:$PATH"
    "FAKE_PACMAN_STATE=$state"
    "FAKE_CALLS=$state/calls"
    "FAKE_MAKEPKG_USER=$state/makepkg-user"
    "FAKE_MAKEPKG_FLAKY_MARK=$state/makepkg-marks/flaky"
    "FAKE_CALAMARES_CHOOSER_ENABLED=$state/calamares-chooser-enabled"
    "FAKE_DROP_USER=$state/drop-user"
    "FAKE_DROP_USER_FILE=$state/drop-user"
    "FAKE_USER_CREATED=$state/user-created"
    "ANIOS_AUR_MANIFEST=$airootfs/root/.anios-aur/packages.aur.x86_64"
    "ANIOS_AUR_SRC_DIR=$airootfs/var/tmp/anios-aur-build"
    "ANIOS_AUR_REPORT=$airootfs/usr/share/anios/aur-packages.txt"
    "ANIOS_AUR_PKG_CACHE=$airootfs/var/cache/pacman/pkg"
    "ANIOS_AUR_ROOT=https://aur.example.invalid"
    "ANIOS_AUR_GITHUB_MIRROR=https://github.com/archlinux/aur.git"
    "ANIOS_AUR_CALAMARES_STAGED_DIR=$staged_calamares"
    "ANIOS_AUR_PACMAN_DB=$state/pacman-db"
    "ANIOS_AUR_RETRIES=0"
    "ANIOS_AUR_TARGET_REPO=$airootfs/usr/share/anios/aur-repo"
    "ANIOS_AUR_PACMAN_CONF=$airootfs/etc/pacman.conf"
    "ANIOS_AUR_KEEP_TMP=${ANIOS_AUR_KEEP_TMP:-0}"
    "${extra_env[@]}"
    bash ${ANIOS_SELFTEST_TRACE:+"-x"} "$airootfs/root/.anios-aur/anios-aur-build.sh"
  )
  local trace_out="/dev/stderr"
  [[ -n "${ANIOS_SELFTEST_TRACE:-}" ]] || trace_out="$state/stderr"
  if [[ "$mode" == root ]]; then
    # Chạy trong user namespace để EUID == 0 mà không cần root thật: bài kiểm tra
    # đi đúng nhánh tạo tài khoản dựng gói và hạ quyền bằng runuser.
    unshare --map-root-user "${cmd[@]}" >"$state/stdout" 2>"$trace_out" || return $?
  else
    "${cmd[@]}" >"$state/stdout" 2>"$trace_out" || return $?
  fi
  return 0
}

# --- 1. Dựng thành công cả ba gói AUR --------------------------------------
MANIFEST_OK="$SANDBOX/packages.aur.ok"
cat >"$MANIFEST_OK" <<'EOF'
# Danh sách gói AUR của bài kiểm tra (comment và dòng trống phải bị bỏ qua).

yay   # comment cuối dòng cũng phải bị bỏ qua
coccoc-browser-stable=152.0.7977.124-1
legacy-launcher
EOF

status=0
run_builder "$MANIFEST_OK" user ok || status=$?
if (( status != 0 )); then
  cat "$SANDBOX/state.ok/stderr" >&2
  fail "script trả exit $status dù cả ba gói đều dựng được"
fi

CALLS="$SANDBOX/state.ok/calls"
INSTALLED="$SANDBOX/state.ok/installed"
AIROOTFS_OK="$SANDBOX/airootfs.ok"

# yay mô phỏng lỗi TLS ở AUR rồi phải lấy từ mirror GitHub; coccoc mô phỏng
# lỗi ở cả hai git host trước khi dùng snapshot .tar.gz.
grep -q '^git clone .*yay.git' "$CALLS" || fail "không thử clone yay từ AUR"
grep -q '^git clone .*--branch yay -- https://github.com/archlinux/aur.git' "$CALLS" ||
  fail "không thử mirror GitHub sau lỗi git AUR"
grep -q '^git clone .*--branch coccoc-browser-stable -- https://github.com/archlinux/aur.git' "$CALLS" ||
  fail "không thử mirror GitHub trước snapshot coccoc"
grep -q '^curl .*coccoc-browser-stable.tar.gz' "$CALLS" ||
  fail "không thử tải snapshot khi cả hai git host đều lỗi"

# makepkg phải được gọi đúng cờ mà AniOS chọn (không -s/-i/-r: script tự cài dep
# và tự pacman -U để tài khoản dựng gói không cần sudo).
grep -qxF 'makepkg -f --noconfirm --nocheck' "$CALLS" ||
  fail "makepkg không được gọi với cờ dựng gói AUR của AniOS"

# Cả ba gói phải có trong pacman DB của ảnh và ở trạng thái explicit.
for pkg in yay coccoc-browser-stable legacy-launcher; do
  cut -f1 "$INSTALLED" | grep -qxF "$pkg" || fail "gói AUR không được cài vào ảnh: $pkg"
  reason="$(awk -F'\t' -v n="$pkg" '$1 == n {print $3}' "$INSTALLED")"
  [[ "$reason" == explicit ]] ||
    fail "$pkg phải được cài bằng pacman -U --asexplicit (đang là '$reason')"
done

# Phụ thuộc đọc từ .SRCINFO: makedepend go>=1.24 phải cài bằng --asdeps, và biến
# thể theo kiến trúc depends_x86_64 cũng phải được đọc ra.
asdeps_targets="$(grep -E '^pacman -S .*--asdeps' "$CALLS" | sed -E 's/^.*--asdeps -- //')"
grep -qxF 'go>=1.24' <<<"$asdeps_targets" ||
  fail "makedepend 'go>=1.24' của yay không được cài bằng --asdeps (đã cài: ${asdeps_targets:-không có})"
grep -qxF lib32-fake-arch-dep <<<"$asdeps_targets" ||
  fail "không đọc phụ thuộc theo kiến trúc (depends_x86_64) từ .SRCINFO"

# Phiên bản phải được giữ nguyên khi kiểm tra và khi cài phụ thuộc.
grep -qF 'pacman -T pacman>6.1 git go>=1.24' "$CALLS" ||
  fail "đã làm mất ràng buộc phiên bản trước khi kiểm tra phụ thuộc"
if grep -E '^pacman ' "$CALLS" | grep -q 'unavailable-'; then
  fail "đã xử lý checkdepends hoặc phụ thuộc i686 dù dựng x86_64 --nocheck"
fi

# Không cài lại thứ ảnh đã có, không cài dep "ảo" đã được provider thoả mãn.
if grep -qE '^pacman -S .*--asdeps.* java-runtime' "$CALLS"; then
  fail "java-runtime đã được jre-openjdk thoả mãn mà vẫn bị đem cài"
fi
if grep -qE '^pacman -S .*--asdeps.* qt5-base' "$CALLS"; then
  fail "qt5-base đã có sẵn trong ảnh mà vẫn bị cài lại"
fi

# go chỉ cần lúc dựng yay nên phải bị gỡ; gói explicit của ảnh live phải còn.
if cut -f1 "$INSTALLED" | grep -qxF go; then
  fail "makedepend 'go' không được gỡ — ảnh live nặng thêm vài trăm MB vô ích"
fi
grep -qE '^pacman -Rns --noconfirm -- .*go' "$CALLS" || fail "không gỡ makedepend mồ côi 'go'"
for keep in git base-devel jre-openjdk python nodejs wine qt5-base libx11 glibc; do
  cut -f1 "$INSTALLED" | grep -qxF "$keep" || fail "dọn mồ côi đã gỡ nhầm gói của ảnh live: $keep"
done

# makepkg không được chạy bằng root; không lệnh nào đi qua sudo.
if [[ -s "$SANDBOX/state.ok/makepkg-user" ]]; then
  if grep -qxF root "$SANDBOX/state.ok/makepkg-user"; then
    fail "makepkg chạy bằng root (makepkg thật sẽ từ chối dựng gói)"
  fi
fi
if grep -qE '^sudo ' "$CALLS"; then fail "script gọi sudo — không được phép"; fi
if grep -qi 'NOPASSWD' "$CALLS"; then fail "script đụng tới NOPASSWD"; fi

# Thư mục dựng gói phải bị dọn; báo cáo gói AUR phải còn trong ảnh.
if [[ -e "$AIROOTFS_OK/var/tmp/anios-aur-build" ]]; then
  fail "thư mục dựng gói AUR không được dọn khỏi ảnh"
fi
report="$AIROOTFS_OK/usr/share/anios/aur-packages.txt"
[[ -s "$report" ]] || fail "thiếu báo cáo gói AUR: usr/share/anios/aur-packages.txt"
for pkg in yay coccoc-browser-stable legacy-launcher; do
  grep -qE "^$pkg=" "$report" || fail "báo cáo gói AUR thiếu $pkg"
done
pass "dựng và cài được yay, coccoc-browser-stable, legacy-launcher vào ảnh giả"

# --- 1b. Calamares: mirror GitHub và packagechooser -------------------------
MANIFEST_CALAMARES="$SANDBOX/packages.aur.calamares"
printf '%s\n' calamares >"$MANIFEST_CALAMARES"
status=0
run_builder "$MANIFEST_CALAMARES" user calamares || status=$?
if (( status != 0 )); then
  cat "$SANDBOX/state.calamares/stderr" >&2
  fail "Calamares không được dựng từ mirror GitHub (exit $status)"
fi
grep -q '^git clone .*calamares.git' "$SANDBOX/state.calamares/calls" ||
  fail "không thử tải Calamares từ AUR trước"
grep -q '^git clone .*--branch calamares -- https://github.com/archlinux/aur.git' \
  "$SANDBOX/state.calamares/calls" || fail "không lấy Calamares từ mirror GitHub"
[[ -e "$SANDBOX/state.calamares/calamares-chooser-enabled" ]] ||
  fail "PKGBUILD Calamares vẫn bỏ qua packagechooser bắt buộc"
pass "Calamares được lấy từ mirror GitHub và bật module packagechooser"

# Nếu cả AUR, mirror và snapshot đều lỗi, chỉ báo lỗi tải gói gốc — không để
# chẩn đoán phụ về Calamares/packagechooser che mất nguyên nhân.
status=0
run_builder "$MANIFEST_CALAMARES" user calamares-fetch-failed 1 1 || status=$?
(( status != 0 )) || fail "AUR hỏng mà builder vẫn báo Calamares thành công"
grep -qF 'Bỏ qua kiểm tra packagechooser: gói calamares đã thất bại trước đó' \
  "$SANDBOX/state.calamares-fetch-failed/stdout" ||
  fail "không bỏ qua kiểm tra packagechooser sau khi tải Calamares thất bại"
grep -qF 'calamares (dựng thất bại' "$SANDBOX/state.calamares-fetch-failed/stderr" ||
  fail "phần tổng kết không nêu lỗi AUR gốc của Calamares"
if grep -qF 'does not provide its packagechooser module' \
  "$SANDBOX/state.calamares-fetch-failed/stderr"; then
  fail "kiểm tra packagechooser đã che lỗi tải Calamares trước đó"
fi
pass "lỗi lấy Calamares được giữ làm nguyên nhân chính thay vì lỗi packagechooser phụ"

# --- 2. Nhánh chạy bằng root: tạo tài khoản thường rồi hạ quyền -------------
if unshare --map-root-user true >/dev/null 2>&1; then
  status=0
  run_builder "$MANIFEST_OK" root root || status=$?
  if (( status != 0 )); then
    cat "$SANDBOX/state.root/stderr" >&2
    fail "nhánh root (EUID=0 trong user namespace) trả exit $status"
  fi
  CALLS_ROOT="$SANDBOX/state.root/calls"
  grep -q '^useradd --system --uid 1412' "$CALLS_ROOT" ||
    fail "không tạo tài khoản dựng gói tạm thời (makepkg từ chối chạy bằng root)"
  grep -q '^chown -R -- 1412:1413 ' "$CALLS_ROOT" ||
    fail "quyền nguồn phải dùng GID thật (1413), không phải UID (1412)"
  grep -q '^install -d -m 0700 -o 1412 -g 1413 ' "$CALLS_ROOT" ||
    fail "home của builder phải dùng GID thật"
  grep -q '^runuser --user aniosbuild -- env' "$CALLS_ROOT" ||
    fail "makepkg không được chạy qua runuser dưới tài khoản dựng gói"
  grep -q '^userdel aniosbuild' "$CALLS_ROOT" ||
    fail "tài khoản dựng gói không bị xoá — sẽ nằm lại trong ảnh live"
  if grep -qE '^sudo ' "$CALLS_ROOT"; then fail "nhánh root gọi sudo"; fi
  if [[ -s "$SANDBOX/state.root/makepkg-user" ]] &&
    grep -qxF root "$SANDBOX/state.root/makepkg-user"; then
    fail "nhánh root vẫn chạy makepkg bằng root"
  fi
  pass "nhánh root tạo tài khoản tạm, hạ quyền bằng runuser rồi xoá tài khoản"
else
  echo "SKIP: unshare --map-root-user không chạy được nên bỏ qua nhánh root"
fi

# --- 3. Một gói dựng hỏng thì bản dựng PHẢI dừng ---------------------------
MANIFEST_BAD="$SANDBOX/packages.aur.bad"
cat >"$MANIFEST_BAD" <<'EOF'
yay
broken-package
EOF
status=0
run_builder "$MANIFEST_BAD" user bad || status=$?
if (( status == 0 )); then
  fail "gói AUR dựng hỏng mà script vẫn trả exit 0: ISO thiếu gói nhưng CI vẫn xanh"
fi
grep -qF 'broken-package' "$SANDBOX/state.bad/stderr" || fail "thông báo lỗi không nêu tên gói hỏng"
grep -qF -- '--no-aur' "$SANDBOX/state.bad/stderr" || fail "thông báo lỗi không gợi ý --no-aur"
cut -f1 "$SANDBOX/state.bad/installed" | grep -qxF yay ||
  fail "gói dựng được trước gói hỏng cũng không được cài vào ảnh"
grep -qE '^# THẤT BẠI: broken-package' "$SANDBOX/airootfs.bad/usr/share/anios/aur-packages.txt" ||
  fail "báo cáo gói AUR không ghi lại gói dựng hỏng"
pass "gói AUR dựng hỏng làm bản dựng dừng kèm gợi ý --no-aur"

# --- 4. Tên gói lạ trong manifest phải bị chặn -----------------------------
MANIFEST_WEIRD="$SANDBOX/packages.aur.weird"
cat >"$MANIFEST_WEIRD" <<'EOF'
yay; rm -rf /
EOF
status=0
run_builder "$MANIFEST_WEIRD" user weird || status=$?
(( status != 0 )) || fail "manifest chứa tên gói nguy hiểm mà script vẫn chấp nhận"
grep -qF 'không hợp lệ' "$SANDBOX/state.weird/stderr" || fail "không báo rõ tên gói không hợp lệ"
if grep -qE '^(git clone|curl|makepkg) ' "$SANDBOX/state.weird/calls"; then
  fail "script vẫn tải/dựng gói dù tên gói trong manifest không hợp lệ"
fi
pass "tên gói AUR không hợp lệ bị chặn trước khi tải/dựng"

# --- 5. KEEP_TMP=1 giữ lại hiện trường để tự chạy makepkg ------------------
status=0
ANIOS_AUR_KEEP_TMP=1 run_builder "$MANIFEST_OK" user keep || status=$?
(( status == 0 )) || fail "ANIOS_AUR_KEEP_TMP=1 làm script hỏng (exit $status)"
[[ -d "$SANDBOX/airootfs.keep/var/tmp/anios-aur-build/src/yay" ]] ||
  fail "ANIOS_AUR_KEEP_TMP=1 không giữ lại thư mục nguồn để mổ xẻ"
[[ -s "$SANDBOX/airootfs.keep/var/tmp/anios-aur-build/anios-aur-build.log" ]] ||
  fail "ANIOS_AUR_KEEP_TMP=1 không giữ lại nhật ký dựng gói"
pass "ANIOS_AUR_KEEP_TMP=1 giữ lại thư mục dựng gói và nhật ký"



# Phụ thuộc bắt buộc không có trong kho: dừng trước makepkg, không báo đủ dep.
make_fixture missing-dependency 'pkgbase = missing-dependency
    depends = unavailable-runtime>=2
    pkgname = missing-dependency'
printf '%s\n' missing-dependency >"$SANDBOX/packages.aur.missing"
status=0
run_builder "$SANDBOX/packages.aur.missing" user missing || status=$?
(( status != 0 )) || fail "phụ thuộc bắt buộc thiếu mà bản dựng vẫn thành công"
grep -qF 'không phân giải được phụ thuộc trong kho chính thức: unavailable-runtime>=2' \
  "$SANDBOX/state.missing/stdout" || fail "không nêu rõ phụ thuộc thiếu"
if grep -q '^makepkg -f' "$SANDBOX/state.missing/calls"; then
  fail "vẫn chạy makepkg khi chưa đủ phụ thuộc bắt buộc"
fi
pass "phụ thuộc bắt buộc thiếu được báo rõ trước khi dựng"

# --- 6. Gói hỏng KHÔNG được chặn các gói còn lại ---------------------------
# Trước đây một gói thiếu phụ thuộc gọi die() ngay, nên nhật ký chỉ nói về gói
# đầu tiên và mỗi lượt dựng chỉ sửa được một lỗi. Nay script đi hết danh sách,
# ghi từng gói vào phần tổng kết rồi mới dừng.
MANIFEST_PARTIAL_FAILURE="$SANDBOX/packages.aur.partial"
cat >"$MANIFEST_PARTIAL_FAILURE" <<'EOF'
missing-dependency
yay
EOF
status=0
run_builder "$MANIFEST_PARTIAL_FAILURE" user partial || status=$?
(( status != 0 )) || fail "có gói AUR hỏng mà bản dựng vẫn báo thành công"
cut -f1 "$SANDBOX/state.partial/installed" | grep -qxF yay ||
  fail "gói sau gói hỏng không được dựng/cài (script dừng quá sớm)"
summary="$(cat "$SANDBOX/state.partial/stderr")"
grep -qF 'missing-dependency (dựng thất bại' <<<"$summary" ||
  fail "phần tổng kết không nêu gói hỏng: $summary"
grep -qF 'yay ' <<<"$summary" || fail "phần tổng kết không nêu gói dựng được"
pass "một gói AUR hỏng vẫn để các gói còn lại dựng xong rồi mới kết luận"

# --- 7. AUR lệch checksum: phân loại đúng, in hash thật, phát annotation ----
make_fixture stale-sums 'pkgbase = stale-sums
	depends = git
	pkgname = stale-sums'
mkdir -p -- "$FIXTURES/stale-sums/src"
printf 'appimage bytes\n' >"$FIXTURES/stale-sums/src/LM-Studio-0.4.26-4-x64.AppImage"
printf "%s\n" "sha256sums=('0000000000000000000000000000000000000000000000000000000000000000')" \
  >>"$FIXTURES/stale-sums/PKGBUILD"
printf '%s\n' stale-sums >"$SANDBOX/packages.aur.stale"
EXTRA_BUILDER_ENV=("ANIOS_AUR_ANNOTATE=1")
status=0
run_builder "$SANDBOX/packages.aur.stale" user stale || status=$?
(( status != 0 )) || fail "AUR lệch checksum mà bản dựng vẫn báo thành công"
STALE_STDOUT="$SANDBOX/state.stale/stdout"
grep -qF '[checksum]' "$STALE_STDOUT" || fail "không phân loại lỗi thành checksum"
grep -qF 'AUR đang lệch' "$STALE_STDOUT" ||
  fail "không đối chiếu sha256 thật của nguồn với PKGBUILD"
grep -qF 'AUR lệch checksum' "$SANDBOX/state.stale/stderr" ||
  fail "phần tổng kết không nói rõ AUR lệch checksum"
grep -q '^::error ' "$STALE_STDOUT" ||
  fail "không phát annotation ::error cho GitHub Actions"
grep -q '^::error .*sha256sums' "$STALE_STDOUT" ||
  fail "annotation không nêu nguyên nhân lệch checksum"
pass "lệch checksum của AUR được phân loại, đối chiếu hash và báo bằng annotation"

# --- 8. Lối thoát ANIOS_AUR_ALLOW_STALE_SUMS=1 -----------------------------
EXTRA_BUILDER_ENV=("ANIOS_AUR_ALLOW_STALE_SUMS=1")
status=0
run_builder "$SANDBOX/packages.aur.stale" user stale-allowed || status=$?
(( status == 0 )) || {
  cat "$SANDBOX/state.stale-allowed/stderr" >&2
  fail "ANIOS_AUR_ALLOW_STALE_SUMS=1 không dựng được gói lệch checksum"
}
grep -q -- '--skipchecksums' "$SANDBOX/state.stale-allowed/calls" ||
  fail "không thử lại makepkg với --skipchecksums"
cut -f1 "$SANDBOX/state.stale-allowed/installed" | grep -qxF stale-sums ||
  fail "gói dựng bằng --skipchecksums không được cài vào ảnh"
grep -qF '# CHÚ Ý: stale-sums được dựng với ANIOS_AUR_ALLOW_STALE_SUMS=1' \
  "$SANDBOX/airootfs.stale-allowed/usr/share/anios/aur-packages.txt" ||
  fail "báo cáo của ảnh không ghi gói được dựng khi AUR lệch checksum"
pass "ANIOS_AUR_ALLOW_STALE_SUMS=1 dựng được gói lệch checksum và ghi rõ trong báo cáo"

# --- 9. Lượt thử lại cứu được lỗi tải nguồn thoáng qua ---------------------
make_fixture flaky-package 'pkgbase = flaky-package
	depends = git
	pkgname = flaky-package'
printf '%s\n' flaky-package >"$SANDBOX/packages.aur.flaky"
EXTRA_BUILDER_ENV=("ANIOS_AUR_RETRIES=1" "ANIOS_AUR_RETRY_DELAY=0")
status=0
run_builder "$SANDBOX/packages.aur.flaky" user flaky || status=$?
(( status == 0 )) || {
  cat "$SANDBOX/state.flaky/stderr" >&2
  fail "gói hỏng ở lượt đầu không được thử lại (exit $status)"
}
grep -qF 'Thử lại flaky-package (lần 2/2' "$SANDBOX/state.flaky/stdout" ||
  fail "không thử lại gói hỏng ở lượt đầu"
cut -f1 "$SANDBOX/state.flaky/installed" | grep -qxF flaky-package ||
  fail "gói thành công ở lượt thử lại không được cài vào ảnh"
pass "gói hỏng ở lượt đầu được thử lại và cài vào ảnh"

# --- 10. Kiểm tra sơ bộ: sync DB trống thì cảnh báo ngay -------------------
EXTRA_BUILDER_ENV=("ANIOS_AUR_ANNOTATE=1" "ANIOS_AUR_PACMAN_DB=$SANDBOX/pacman-db-empty")
mkdir -p -- "$SANDBOX/pacman-db-empty"
status=0
run_builder "$MANIFEST_OK" user no-sync-db || status=$?
(( status == 0 )) || fail "cảnh báo sync DB trống lại làm hỏng bản dựng (exit $status)"
grep -qF 'sync DB của pacman trống' "$SANDBOX/state.no-sync-db/stdout" ||
  fail "không cảnh báo khi airootfs chưa có sync DB"
grep -q '^::warning ' "$SANDBOX/state.no-sync-db/stdout" ||
  fail "cảnh báo sync DB trống không được phát thành annotation"
pass "thiếu sync DB trong airootfs được cảnh báo sớm thay vì hỏng lặng lẽ"

# --- 11. Driver NVIDIA 580xx: gói tách được cài đủ và đưa vào kho cục bộ ---
# SRCINFO khớp AUR thật (đã đối chiếu mirror archlinux/aur, 580.178.04):
#  - nvidia-580xx-utils là gói tách (utils + opencl + dkms); dkms phụ thuộc
#    CHÍNH utils=<ver>, utils provides nvidia-utils.
#  - nvidia-580xx-settings là gói tách cùng libxnvctrl-580xx; settings cần
#    nvidia-utils (được utils thoả qua provides) và libxnvctrl-580xx (tự sinh).
make_fixture nvidia-580xx-utils 'pkgbase = nvidia-580xx-utils
	pkgver = 13.0.1
	pkgdesc = NVIDIA drivers (580xx), split: utils + opencl + dkms
pkgname = nvidia-580xx-utils
	depends = libglvnd
	provides = nvidia-utils
pkgname = opencl-nvidia-580xx
	depends = zlib
pkgname = nvidia-580xx-dkms
	depends = dkms
	depends = nvidia-580xx-utils=13.0.1
	depends = libglvnd'
make_fixture lib32-nvidia-580xx-utils 'pkgbase = lib32-nvidia-580xx-utils
	pkgver = 13.0.1
pkgname = lib32-nvidia-580xx-utils
	depends = glibc'
make_fixture nvidia-580xx-settings 'pkgbase = nvidia-580xx-settings
	pkgver = 13.0.1
	makedepends = jansson
	makedepends = nvidia-580xx-utils
pkgname = nvidia-580xx-settings
	depends = jansson
	depends = nvidia-utils
	depends = libxnvctrl-580xx
pkgname = libxnvctrl-580xx
	depends = libxext'
printf '%s\n' nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-settings \
  yay >"$SANDBOX/packages.aur.nvidia"
status=0
run_builder "$SANDBOX/packages.aur.nvidia" user nvidia || status=$?
(( status == 0 )) || {
  cat "$SANDBOX/state.nvidia/stderr" >&2
  fail "bản dựng driver NVIDIA 580xx thất bại (exit $status)"
}
NV_STATE="$SANDBOX/state.nvidia"
NV_ROOT="$SANDBOX/airootfs.nvidia"
# Cả hai file của gói tách phải được pacman -U cùng lúc, và -dkms phải được cài.
grep -E '^pacman -U ' "$NV_STATE/calls" | grep -q 'nvidia-580xx-dkms-13.0.1-1-x86_64.pkg.tar.zst' &&
  grep -E '^pacman -U ' "$NV_STATE/calls" | grep -q 'nvidia-580xx-utils-13.0.1-1-x86_64.pkg.tar.zst' ||
  fail "gói tách nvidia-580xx-utils không được cài đủ mọi file (thiếu -dkms?)"
cut -f1 "$NV_STATE/installed" | grep -qxF nvidia-580xx-dkms ||
  fail "nvidia-580xx-dkms (module kernel) không có trong pacman DB của ảnh"
# Kho cục bộ: các file gói được sao vào, DB được tạo, pacman.conf khai báo [anios-aur].
for f in nvidia-580xx-utils nvidia-580xx-dkms lib32-nvidia-580xx-utils nvidia-580xx-settings; do
  ls "$NV_ROOT/usr/share/anios/aur-repo/" | grep -q "^$f-13.0.1-1-x86_64.pkg.tar.zst\$" ||
    fail "file gói $f không được đưa vào kho cục bộ của bộ cài đặt"
done
grep -qF 'repo-add' "$NV_STATE/calls" || fail "không tạo DB của kho [anios-aur]"
grep -qxF '[anios-aur]' "$NV_ROOT/etc/pacman.conf" || fail "pacman.conf không khai báo [anios-aur]"
grep -qxF 'SigLevel = Optional TrustAll' "$NV_ROOT/etc/pacman.conf" ||
  fail "kho [anios-aur] không khai báo SigLevel"
grep -qxF "Server = file://$NV_ROOT/usr/share/anios/aur-repo" "$NV_ROOT/etc/pacman.conf" ||
  fail "kho [anios-aur] không trỏ tới thư mục gói"
pass "driver NVIDIA 580xx: gói tách cài đủ, kho cục bộ và pacman.conf đúng"

# Bản dựng không có gói kho cục bộ không được đụng vào pacman.conf của ảnh.
grep -q '\[anios-aur\]' "$SANDBOX/airootfs.ok/etc/pacman.conf" &&
  fail "bản dựng không có driver NVIDIA vẫn khai báo kho [anios-aur]"
[[ ! -e "$SANDBOX/airootfs.ok/usr/share/anios/aur-repo" ]] ||
  fail "bản dựng không có driver NVIDIA vẫn tạo thư mục kho cục bộ"
pass "manifest không có driver NVIDIA thì không tạo kho cục bộ"

echo "AniOS AUR build self-test passed"
