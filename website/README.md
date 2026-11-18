# Trang chính thức của AniOS

Trang tĩnh, không cần bước dựng: mở `index.html` là chạy. Toàn bộ nội dung lấy từ
`README.md` của repository; giao diện theo hướng **poster ghép** — nền lưới tím nhạt,
chữ display in hoa cỡ lớn, ảnh dán viền trắng xoay nhẹ, sticker vàng/đỏ.

```
website/
├── index.html          # toàn bộ nội dung, một trang
├── styles.css          # hệ thống màu, kiểu chữ, bố cục poster
├── script.js           # menu di động, hiện dần khi cuộn, thị sai nhẹ
└── assets/
    ├── hero-gamer.jpg      # minh hoạ nhân vật (ảnh gốc, do dự án tạo)
    ├── chibi-sticker.jpg   # sticker chibi dùng ở thẻ "đang chạy"
    └── net-cafe-desk.jpg   # minh hoạ một góc máy trong quán
```

## Xem thử tại máy

```bash
cd website
python3 -m http.server 8080
# mở http://localhost:8080
```

Không cần Node, không cần bundler. Mở thẳng `index.html` bằng trình duyệt cũng được:
mọi đường dẫn đều tương đối, và nếu JavaScript bị tắt thì nội dung vẫn hiện đầy đủ
(phần hiện-dần chỉ bật khi có JavaScript).

## Ghi chú thiết kế

- **Màu**: tím nhạt `#cfd0f0` + trắng ngà `#fffdf9`, nhấn vàng `#ffd42a` và đỏ
  `#e63329`. Chữ chính `#21213d`.
- **Chữ**: `Oswald` cho tiêu đề (condensed, có đủ dấu tiếng Việt), `Space Grotesk`
  cho nội dung, `JetBrains Mono` cho lệnh và nhãn nhỏ. Khi mở offline, Google Fonts
  không tải được thì trang rơi về Impact / Arial Narrow / system-ui — vẫn đọc tốt.
- **Lớp trang trí**: lưới giấy kẻ ô + hạt nhiễu (SVG), băng dính giấy, sticker trái
  tim vàng, dấu hoa thị đỏ, chữ nền rỗng. Tất cả bằng CSS/SVG, không ảnh nền.
- **Ảnh minh hoạ** là ảnh gốc do dự án tạo cho trang này, không dùng tài nguyên của
  dự án khác.
- Mọi hiệu ứng đều tắt theo `prefers-reduced-motion`; liên kết có `:focus-visible`.

## Cập nhật nội dung

Sửa trực tiếp trong `index.html`. Vài chỗ cần đồng bộ khi repo đổi:

| Chỗ trong trang | Nguồn trong repo |
| --- | --- |
| Ba bản ISO (tên, mô tả, `--edition`) | `README.md` → “Ba bản ISO”, `profile/editions/README.md` |
| Danh sách tính năng | `README.md` → “Sử dụng phiên Live”, “Gói AUR”, mục NVIDIA |
| Lệnh trong mục Sự cố | `usr/local/bin/anios-{gpu-doctor,dmesg-check,netcheck,audio-*}` |
| Chế độ quán net | `README.md` → “Chạy trong quán net”, `profile/airootfs/etc/anios/net-cafe.conf` |

## Đưa lên mạng

Là trang tĩnh nên chỗ nào phục vụ file tĩnh cũng được: GitHub Pages (trỏ thư mục
`website/`), Cloudflare Pages, Netlify, hoặc chép vào `/srv/http` của một máy nginx.
`script.js` và `styles.css` dùng đường dẫn tương đối nên chạy được cả ở thư mục con.
