#!/usr/bin/env bash
set -Eeuo pipefail

# Kiểm tra một mật khẩu có khớp với hash crypt(3) đọc ra từ /etc/shadow hay
# không — đúng phép so mà pam_unix thực hiện khi đăng nhập. Dùng để CI xác
# nhận hash mật khẩu live 1111 đã được nướng vào ảnh thật sự là hash của 1111.
#
# Vì sao cần script này: `passwd` của shadow-utils không có chế độ kiểm tra mật
# khẩu với hash có sẵn ("passwd --verify" không tồn tại, chỉ in usage rồi trả
# về khác 0 nên luôn kết luận sai). Cách kiểm tra đúng là tính lại
# crypt(MAT_KHAU, HASH) bằng libxcrypt rồi so kết quả với HASH.
#
# Cách dùng: verify-password-hash.sh <MAT_KHAU> <HASH>
#   thoát 0: HASH đúng là hash của MAT_KHAU
#   thoát 1: không khớp (kể cả khi HASH không phải hash hợp lệ)
#   thoát 2: thiếu công cụ hoặc sai cú pháp
#
# Script biên dịch một chương trình C nhỏ gắn liền ở dưới bằng `cc`/`gcc` +
# libcrypt. Trong container `archlinux:base-devel` dựng ISO thì gcc (base-devel)
# và libcrypt (libxcrypt, dependency của shadow) luôn có sẵn.

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <password> <crypt-hash>" >&2
  echo "Exits 0 when <crypt-hash> is the crypt(3) hash of <password>." >&2
  exit 2
fi
password="$1"
hash="$2"

compiler="${CC:-cc}"
if ! command -v "$compiler" >/dev/null 2>&1; then
  compiler=gcc
fi
command -v "$compiler" >/dev/null 2>&1 || {
  echo "verify-password-hash: no C compiler found (tried \$CC, cc, gcc)" >&2
  exit 2
}

workdir="$(mktemp -d)"
trap 'rm -rf -- "$workdir"' EXIT

cat >"$workdir/verify.c" <<'EOF'
/* Thoát 0 nếu argv[2] là hash crypt(3) của argv[1], ngược lại thoát 1. */
#include <crypt.h>
#include <string.h>

int main(int argc, char **argv)
{
    char stored[512];

    if (argc != 3)
        return 2;

    /* crypt() trả lời vào buffer nội bộ của chính nó. Sao chép hash sang
       vùng nhớ riêng trước khi gọi, nếu không kết quả sẽ ghi đè chính chuỗi
       cần so sánh và phép so luôn đúng. */
    if (strlen(argv[2]) >= sizeof stored)
        return 1;
    strcpy(stored, argv[2]);

    const char *computed = crypt(argv[1], stored);
    if (computed == NULL)
        return 1; /* hash hỏng hoặc libxcrypt không hiểu thuật ngữ của hash */
    return strcmp(computed, stored) == 0 ? 0 : 1;
}
EOF

if ! "$compiler" -O2 -o "$workdir/verify" "$workdir/verify.c" -lcrypt; then
  echo "verify-password-hash: cannot build the verifier against libcrypt" >&2
  echo "(install a C compiler and libcrypt development files)" >&2
  exit 2
fi

"$workdir/verify" "$password" "$hash"
