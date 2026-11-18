# shellcheck shell=bash
# Thư viện "chế độ quán net" của AniOS — được SOURCE bởi
#   * /usr/local/bin/anios-cafe    (lệnh quản trị: status / on / off / clean)
#   * /usr/local/bin/anios-session (dọn dữ liệu khách + ghi nhận phiên chết)
#   * unit anios-cafe-watchdog.service (chạy bằng root, quyết định khởi động lại)
# nên không cần bit thực thi.
#
# Vì sao cần: máy quán net là máy DÙNG CHUNG. Hai sự cố vận hành hay gặp nhất —
# không liên quan gì tới driver đồ hoạ — là
#   1. khách sau thừa hưởng dữ liệu của khách trước: phiên đăng nhập Steam, lịch
#      sử/mật khẩu trình duyệt, file tải về, clipboard...;
#   2. phiên đồ hoạ chết lặp lại (driver, ép xung, RAM) và máy nằm im ở màn hình
#      đăng nhập cho tới khi có người gọi kỹ thuật.
# Hai hàm dưới đây xử lý đúng hai việc đó, và CHỈ hai việc đó: không xoá dotfiles,
# không đụng tới Desktop (nơi có lối tắt của ảnh), không sửa cấu hình Hyprland.
#
# Mọi biến ANIOS_CAFE_* dưới đây có thể đặt trong
#   /etc/anios/net-cafe.conf            (toàn bộ máy — quản trị viên quán)
#   ~/.config/anios/net-cafe.conf       (một tài khoản)
#   tham số nhân `anios.cafe=1`         (bật cho riêng lần khởi động này)
# và biến môi trường ANIOS_CAFE_HOME / ANIOS_CAFE_ETC_CONF / ANIOS_CAFE_STATE_DIR
# / ANIOS_CAFE_CMDLINE_FILE chỉ tồn tại để bài tự kiểm tra chạy trên cây giả.

anios_cafe_home() {
  printf '%s\n' "${ANIOS_CAFE_HOME:-${HOME:-}}"
}

# Giá trị mặc định = hành vi cũ của AniOS (không xoá gì, không tự khởi động lại).
# Chế độ quán net bật bằng `anios-cafe on` hoặc `ANIOS_CAFE_ENABLE=1`.
anios_cafe_defaults() {
  ANIOS_CAFE_ENABLE="${ANIOS_CAFE_ENABLE:-0}"
  ANIOS_CAFE_MAX_FAST_FAILURES="${ANIOS_CAFE_MAX_FAST_FAILURES:-3}"
  ANIOS_CAFE_FAILURE_WINDOW="${ANIOS_CAFE_FAILURE_WINDOW:-600}"
  # Tài khoản dùng chung của quán; unit watchdog chạy bằng root nên phải biết
  # đọc trạng thái của ai.
  ANIOS_CAFE_USER="${ANIOS_CAFE_USER:-anios}"
  # Vai trò của MÁY NÀY: "gaming" (máy cho khách) hoặc "pos" (máy quầy thu ngân).
  # Máy quầy dùng chung tài khoản nhưng KHÔNG được dọn dữ liệu: trình duyệt ở quầy
  # đang đăng nhập sẵn phần mềm bán hàng (KiotViet/MISA/Sapo/POS365...), xoá hồ sơ
  # trình duyệt là mất phiên đăng nhập giữa ca, và tự khởi động lại máy giữa lúc
  # tính tiền thì mất hoá đơn. Xem anios_cafe_load_config bên dưới.
  ANIOS_CAFE_ROLE="${ANIOS_CAFE_ROLE:-gaming}"
  # Những đường dẫn bị XOÁ HẲN khi bắt đầu phiên mới (tương đối so với $HOME).
  # Cố ý KHÔNG có: dotfiles Hyprland/quickshell, ~/Desktop, ~/.local/share/anios
  # (nhật ký phiên, cần cho anios-gpu-doctor), và mọi thứ ngoài $HOME.
  ANIOS_CAFE_WIPE_PATHS=(
    .steam
    .local/share/Steam
    .config/google-chrome
    .cache/google-chrome
    .config/chromium
    .cache/chromium
    .config/coccoc
    .cache/coccoc
    .config/firefox
    .mozilla
    .cache/mozilla
    .config/discord
    .config/TelegramDesktop
    .local/share/TelegramDesktop
    .local/share/recently-used.xbel
    .bash_history
    .zsh_history
  )
  # Những thư mục được GIỮ LẠI nhưng DỌN SẠCH nội dung (khách sau vẫn thấy thư mục).
  ANIOS_CAFE_EMPTY_DIRS=(Downloads Documents Pictures Videos)
}

# anios_cafe_load_config: nạp /etc rồi ~/.config (file sau đè file trước), cuối
# cùng xét tham số nhân. Không file nào tồn tại thì giữ mặc định.
anios_cafe_load_config() {
  local home file cmdline
  local -a files=()
  anios_cafe_defaults
  home="$(anios_cafe_home)"
  files+=("${ANIOS_CAFE_ETC_CONF:-/etc/anios/net-cafe.conf}")
  [[ -n "$home" ]] && files+=("$home/.config/anios/net-cafe.conf")
  for file in "${files[@]}"; do
    [[ -n "$file" && -r "$file" ]] || continue
    # File cấu hình là shell thuần (ANIOS_CAFE_KEY=value, mảng bằng ( ... )).
    # Một dòng gõ sai KHÔNG được làm chết phiên đăng nhập (nhất là ở máy quầy):
    # chỉ cảnh báo một dòng rồi dùng tiếp các giá trị đọc được trước đó.
    # shellcheck disable=SC1090
    if ! . "$file" 2>/dev/null; then
      printf 'anios-cafe: %s có dòng sai, đã bỏ qua phần còn lại\n' "$file" >&2
    fi
  done
  cmdline="${ANIOS_CAFE_CMDLINE_FILE:-/proc/cmdline}"
  if [[ -r "$cmdline" ]] && grep -qE '(^|[[:space:]])anios\.cafe=1([[:space:]]|$)' "$cmdline" 2>/dev/null; then
    ANIOS_CAFE_ENABLE=1
  fi
  # Hai công tắc con mặc định đi theo công tắc tổng.
  ANIOS_CAFE_WIPE_ON_START="${ANIOS_CAFE_WIPE_ON_START:-$ANIOS_CAFE_ENABLE}"
  ANIOS_CAFE_REBOOT_ON_CRASH="${ANIOS_CAFE_REBOOT_ON_CRASH:-$ANIOS_CAFE_ENABLE}"
  anios_cafe_normalize_role
  # Máy quầy thu ngân: bật chế độ quán net cho cả dàn (`on --system`) là chuyện
  # bình thường ở quầy, nhưng máy POS phải miễn nhiễm — xoá hồ sơ trình duyệt là
  # mất phiên đăng nhập phần mềm bán hàng, còn tự reboot giữa ca là mất hoá đơn.
  # Vai trò "pos" vì thế KHOÁ CỨNG hai công tắc này, dù file nào bật chúng.
  if [[ "$ANIOS_CAFE_ROLE" == pos ]]; then
    ANIOS_CAFE_WIPE_ON_START=0
    ANIOS_CAFE_REBOOT_ON_CRASH=0
  fi
}

# anios_cafe_normalize_role: chấp nhận các cách gọi quen miệng của chủ quán
# (quay/quầy/counter/thungan) để không ai phải nhớ đúng một chữ.
anios_cafe_normalize_role() {
  case "${ANIOS_CAFE_ROLE:-}" in
    pos | POS | quay | quầy | quay-thu-ngan | counter | cashier | thungan) ANIOS_CAFE_ROLE=pos ;;
    *) ANIOS_CAFE_ROLE=gaming ;;
  esac
}

# anios_cafe_is_pos: 0 khi máy này là máy quầy thu ngân.
anios_cafe_is_pos() {
  [[ "${ANIOS_CAFE_ROLE:-}" == pos ]]
}

anios_cafe_state_dir() {
  local home
  home="$(anios_cafe_home)"
  # Không có $HOME (ví dụ unit chạy bằng root trên máy mà tài khoản ANIOS_CAFE_USER
  # không tồn tại — máy quầy hay đặt tên tài khoản khác): KHÔNG suy ra thành
  # "/.local/state/anios" rồi tạo thư mục rác ở gốc ổ đĩa. Trả 1 để nơi gọi im lặng
  # bỏ qua.
  if [[ -z "${ANIOS_CAFE_STATE_DIR:-}" && -z "$home" ]]; then
    return 1
  fi
  printf '%s\n' "${ANIOS_CAFE_STATE_DIR:-$home/.local/state/anios}"
}

anios_cafe_failures_file() {
  local dir
  dir="$(anios_cafe_state_dir)" || return 1
  printf '%s\n' "$dir/session-failures"
}

# _anios_cafe_safe_path <đường dẫn tương đối>: in ra đường dẫn tuyệt đối trong
# $HOME, hoặc trả 1 nếu đường dẫn không an toàn (tuyệt đối, có '..', rỗng, hoặc
# $HOME không tồn tại). Bài tự kiểm tra dựa vào hàm này để chứng minh không có
# cách nào xoá ra ngoài home.
_anios_cafe_safe_path() {
  local rel="$1" home
  home="$(anios_cafe_home)"
  [[ -n "$home" && -d "$home" ]] || return 1
  [[ -n "$rel" && "$rel" != /* ]] || return 1
  case "/$rel/" in
    *"/../"*) return 1 ;;
  esac
  printf '%s\n' "${home%/}/$rel"
}

# anios_cafe_clean [dry-run]: 0 = xoá thật, 1 = chỉ in ra. In mỗi mục một dòng
# "<ĐÃ XOÁ|SẼ XOÁ|TRỐNG|KHÔNG CÓ> <đường dẫn>" để `anios-cafe status` và nhật ký
# phiên đọc lại được. Đặt ANIOS_CAFE_LAST_REMOVED = số mục đã xoá (hoặc sẽ xoá).
anios_cafe_clean() {
  local dry="${1:-0}" rel path removed=0 item entry
  ANIOS_CAFE_LAST_REMOVED=0
  local home
  home="$(anios_cafe_home)"
  if [[ -z "$home" || ! -d "$home" ]]; then
    # stderr: không biết thư mục nhà (unit root tra không ra tài khoản, hoặc máy
    # chưa có ai đăng nhập) thì không phải lỗi của người dùng. Vẫn im lặng trên
    # stdout để `anios_cafe_clean` không ghi dòng rác vào nhật ký phiên.
    printf 'anios-cafe: chưa xác định được thư mục nhà (%s) — bỏ qua\n' \
      "${home:-HOME chưa đặt}" >&2
    return 0
  fi

  for rel in "${ANIOS_CAFE_WIPE_PATHS[@]}"; do
    path="$(_anios_cafe_safe_path "$rel")" || continue
    if [[ -e "$path" || -L "$path" ]]; then
      if (( dry )); then
        printf 'SẼ XOÁ %s\n' "$rel"
      else
        # --one-file-system: nếu quán gắn ổ riêng (hoặc symlink) cho thư viện game
        # thì KHÔNG xoá vào ổ đó. Mất dữ liệu khách còn cứu được, xoá game của quán
        # thì phải tải lại từ đầu.
        rm -rf --one-file-system -- "$path" 2>/dev/null || true
        printf 'ĐÃ XOÁ %s\n' "$rel"
      fi
      removed=$((removed + 1))
    fi
  done

  for rel in "${ANIOS_CAFE_EMPTY_DIRS[@]}"; do
    path="$(_anios_cafe_safe_path "$rel")" || continue
    if [[ ! -d "$path" ]]; then
      continue
    fi
    # Chỉ xoá các mục CON, giữ lại chính thư mục để khách sau vẫn thấy quen mắt.
    item=0
    while IFS= read -r -d '' entry; do
      item=$((item + 1))
      if (( dry )); then
        continue
      fi
      rm -rf --one-file-system -- "$entry" 2>/dev/null || true
    done < <(find "$path" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
    if (( item > 0 )); then
      if (( dry )); then
        printf 'SẼ DỌN %s (%d mục)\n' "$rel" "$item"
      else
        printf 'ĐÃ DỌN %s (%d mục)\n' "$rel" "$item"
      fi
      removed=$((removed + 1))
    fi
  done

  ANIOS_CAFE_LAST_REMOVED="$removed"
  return 0
}

# --- Ghi nhận phiên chết nhanh ---------------------------------------------
# anios-session gọi hai hàm này; unit watchdog (root) chỉ ĐỌC tệp nên không cần
# quyền đặc biệt ở phía người dùng.

anios_cafe_record_failure() {
  local dir file
  file="$(anios_cafe_failures_file)" || return 0
  dir="$(dirname -- "$file")"
  mkdir -p -- "$dir" 2>/dev/null || return 0
  printf '%s\n' "$(date +%s)" >>"$file" 2>/dev/null || true
  anios_cafe_prune_failures
  return 0
}

anios_cafe_clear_failures() {
  local file
  file="$(anios_cafe_failures_file)" || return 0
  rm -f -- "$file" 2>/dev/null || true
  return 0
}

# anios_cafe_prune_failures: chỉ giữ những lần chết trong ANIOS_CAFE_FAILURE_WINDOW
# giây gần nhất, để "3 lần trong 10 phút" không bị tính cả tháng trước.
anios_cafe_prune_failures() {
  local file now cutoff line kept=""
  file="$(anios_cafe_failures_file)" || return 0
  [[ -r "$file" ]] || return 0
  now="$(date +%s)"
  cutoff=$((now - ANIOS_CAFE_FAILURE_WINDOW))
  while IFS= read -r line; do
    [[ "$line" =~ ^[0-9]+$ ]] || continue
    (( line >= cutoff )) || continue
    kept+="$line"$'\n'
  done <"$file"
  if [[ -n "$kept" ]]; then
    printf '%s' "$kept" >"$file" 2>/dev/null || true
  else
    rm -f -- "$file" 2>/dev/null || true
  fi
}

# anios_cafe_failure_count: in ra số lần chết nhanh còn trong cửa sổ thời gian.
anios_cafe_failure_count() {
  local file count=0 line
  file="$(anios_cafe_failures_file)" || {
    printf '0\n'
    return 0
  }
  [[ -r "$file" ]] || {
    printf '0\n'
    return 0
  }
  while IFS= read -r line; do
    [[ "$line" =~ ^[0-9]+$ ]] || continue
    count=$((count + 1))
  done <"$file"
  printf '%s\n' "$count"
}

# anios_cafe_should_reboot: 0 khi số lần chết nhanh đã chạm ngưỡng VÀ chế độ tự
# khởi động lại đang bật.
anios_cafe_should_reboot() {
  local count
  [[ "${ANIOS_CAFE_REBOOT_ON_CRASH:-0}" == 1 ]] || return 1
  count="$(anios_cafe_failure_count)"
  [[ "$count" =~ ^[0-9]+$ ]] || return 1
  (( count >= ANIOS_CAFE_MAX_FAST_FAILURES ))
}
