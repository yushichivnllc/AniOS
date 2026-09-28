#!/bin/sh
# Tài khoản live tự động vào desktop, chỉ những TTY cứu hộ mới đi qua shell.
# Hiển thị logo AniOS kèm thông tin máy cho dễ nhận biết và dễ chẩn đoán.
#
# Chỉ chạy với shell tương tác: SDDM khởi chạy phiên qua `bash --login`, nên
# nếu không kiểm tra điều này thì fastfetch sẽ chạy cả khi vào desktop.
# Đặt ANIOS_NO_MOTD=1 trong shell để tắt.
case $- in
  *i*) ;;
  *) return 0 ;;
esac
[ -t 1 ] || return 0
[ -z "${ANIOS_NO_MOTD:-}" ] || [ "${ANIOS_NO_MOTD}" = "0" ] || return 0
command -v fastfetch >/dev/null 2>&1 || return 0

# Chỉ hiện ở shell đăng nhập đầu tiên của mỗi TTY, tránh lặp khi mở tmux/shell con.
[ -z "${_ANIOS_MOTD_SHOWN:-}" ] || return 0
export _ANIOS_MOTD_SHOWN=1

fastfetch \
  --logo /usr/share/anios/logo.txt \
  --structure Title:Separator:OS:Host:Kernel:Uptime:Packages:Shell:Display:WM:CPU:GPU:Memory \
  --title-text "anios@live" \
  --color-keys blue
