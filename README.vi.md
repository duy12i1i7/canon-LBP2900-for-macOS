# Driver Canon LBP2900 cho macOS

**Driver giúp máy in Canon LBP2900 (LASER SHOT / i-SENSYS LBP2900/2900B) chạy được trên macOS đời mới — kể cả Apple Silicon — dù Canon không hề phát hành driver cho model này.**

[🇬🇧 English](README.md) &nbsp;|&nbsp; 🇻🇳 Tiếng Việt

---

LBP2900 là máy in **host-based (GDI)**: không có bộ thông dịch PostScript/PCL, chỉ nói giao thức độc quyền **CAPT** của Canon (nén Smart Compression Architecture / Hi-SCoA). Gói driver macOS chính thức của Canon chỉ hỗ trợ từ LBP3000 trở lên, nên con 2900 bị bỏ rơi.

Dự án này cung cấp một **CUPS filter** (`rastertocapt`) hiện thực giao thức CAPT, kèm một **PPD** mô tả máy in. Nó dựa trên dự án mã nguồn mở [captdriver](https://github.com/mounaiban/captdriver) (GPLv3), **cộng thêm các bản vá cần thiết để LBP2900 thực sự in được trên macOS** (xem [Bản vá](#bản-vá)).

> Trạng thái: **đã kiểm chứng in được thật** trên macOS (Apple Silicon, arm64). Tiến trình in và báo hết giấy được tích hợp vào cửa sổ hàng đợi in native của macOS.

## Làm được gì

- ✅ In (600 DPI, mọi khổ giấy chuẩn, giấy thường/dày/phong bì, tiết kiệm mực, in 2 mặt thủ công)
- ✅ CAPT 2 chiều đầy đủ qua USB bằng backend `usb` chuẩn của CUPS — **không cần kext, không cần tắt SIP**
- ✅ **Tiến trình in** trực tiếp trong hàng đợi macOS (“Đang in trang N”)
- ✅ Báo **hết giấy** + thông báo; tự in tiếp khi nạp lại giấy
- ✅ Báo ngoại tuyến / rớt kết nối (do backend USB của CUPS lo)
- ⚠️ Chưa có: phân biệt *kẹt giấy* vs *mở nắp* (driver nền chưa giải mã các bit trạng thái đó — xem [Dự kiến](#dự-kiến))

## Yêu cầu

- macOS có CUPS (mọi bản macOS đều có). Đã thử trên macOS 26, Apple Silicon.
- **Apple Silicon (arm64):** đã kèm sẵn binary dựng trước — không cần biên dịch.
- **Intel (x86_64):** không kèm binary sẵn; script cài sẽ tự build từ mã nguồn. Cần Xcode Command Line Tools (`xcode-select --install`) và autotools (`brew install autoconf automake`).

## Cài đặt

```bash
git clone https://github.com/duy12i1i7/canon-LBP2900-for-macOS.git
cd canon-LBP2900-for-macOS
chmod +x install.sh uninstall.sh
# Cắm và bật máy in trước, rồi:
sudo ./install.sh
```

Script cài sẽ:
1. đặt filter CAPT vào `/usr/libexec/cups/filter/` (nằm trên data volume ghi được; chạy được dù SIP đang bật),
2. đặt PPD vào `/Library/Printers/PPDs/…`,
3. dò máy in USB và tạo hàng đợi tên `Canon_LBP2900`.

Nếu chưa cắm máy in, filter và PPD vẫn được cài — chỉ cần chạy lại `sudo ./install.sh` sau khi cắm.

## Cách dùng

In từ ứng dụng bất kỳ và chọn máy **Canon LBP2900**, hoặc từ terminal:

```bash
lpr -P Canon_LBP2900 file-nao-do.pdf
lpstat -p Canon_LBP2900        # trạng thái hàng đợi
```

## Theo dõi trạng thái in

**Không có cửa sổ trạng thái nổi kiểu Canon** — đó là app đóng chỉ có trên Windows. Thay vào đó, driver này đưa trạng thái vào **cửa sổ hàng đợi in native của macOS** (Cài đặt hệ thống ▸ Máy in & Máy quét ▸ Canon LBP2900 ▸ *Mở hàng đợi in*, hoặc icon máy in dưới Dock khi đang in):

- **Tiến trình** — “Đang in trang N” (thông điệp `PAGE:`)
- **Hết giấy** — badge cảnh báo + thông báo (`STATE: +media-empty`); nạp giấy lại là job chạy tiếp
- **Ngoại tuyến / chưa kết nối** — backend USB của CUPS báo khi rút cáp hoặc tắt máy in

## Gỡ lỗi

Bật log chi tiết và xem khi in:

```bash
sudo cupsctl LogLevel=debug
tail -f /var/log/cups/error_log      # các dòng gắn "CAPT:" là của driver này
sudo cupsctl LogLevel=warn           # nhớ tắt lại sau khi xong
```

- **`filter failed`** — kiểm tra filter có mặt và chạy được:
  `ls -l /usr/libexec/cups/filter/rastertocapt` (phải là `-rwxr-xr-x root wheel`). Chạy lại `sudo ./install.sh` nếu thiếu.
- **Job kẹt mãi ở “now printing” (bộ đếm trang lệch)** — thường xảy ra sau khi bạn **hủy một job giữa chừng**: job bị hủy không gửi lệnh kết thúc sạch, nên bộ đếm trang tích lũy trong máy in bị lệch và job kế tiếp chờ mãi. Cách sửa: `cancel -a Canon_LBP2900`, rồi **tắt/bật nguồn máy in** (tắt ~10 giây, bật lại, chờ đèn xanh sáng ổn định) để reset bộ đếm, rồi in lại. Đây là [hành vi đã biết của captdriver](https://github.com/agalakhov/captdriver/issues/7).
- **macOS tự thêm hàng đợi “Generic/AirPrint”** — LBP2900 không có AirPrint; hãy dùng hàng đợi `Canon_LBP2900` do script tạo (đã gán đúng PPD).
- **In ra trắng hoặc lệch** — chọn đúng khổ giấy (A4/Letter) trong hộp thoại in; máy cần lề tối thiểu ~5 mm.

## Cơ chế hoạt động

Chuỗi lọc CUPS: `app → PDF → cgpdftoraster → rastertocapt → backend usb → máy in`.

`rastertocapt` rasterize từng trang thành các dải nén CAPT/Hi-SCoA rồi stream sang máy in, dùng **kênh ngược** (`cupsBackChannelRead`) và **kênh phụ** (`cupsSideChannelDoRequest`) chuẩn của CUPS cho bắt tay trạng thái 2 chiều. Nhờ vậy không cần kext và không cần quyền đặc biệt ngoài `sudo` lúc cài.

### Bản vá

captdriver gốc đăng ký LBP2900 với chiến lược status *có điều kiện* (`capt_get_xstatus` / `capt_wait_ready`). Kiểu này chỉ đọc status **mở rộng** (lệnh CAPT `0xA0A8`) khi cờ `XSTATUS_CHNG` bật — mà con máy này không bao giờ bật. Các bộ đếm trang (`page_decoding` / `page_out` / `page_completed`) **chỉ nằm trong** bản ghi status mở rộng, nên không bao giờ được cập nhật, để lại giá trị cũ/rác và treo các vòng chờ cuối trang (chính là vòng poll `0xE0A0` lặp vô tận, [captdriver#3](https://github.com/mounaiban/captdriver/issues/3)).

Bản vá chuyển LBP2900 sang đúng chiến lược mà LBP3010 (đã “WORKS”) dùng — **luôn** đọc status mở rộng (`capt_get_xstatus_only` / `capt_wait_xready_only`). Khi các bộ đếm được đọc đúng, chúng hội tụ (`1/1/1/1`) và trang được in. Cùng bản vá này còn thêm phần báo `PAGE:`/`STATE:` nói trên. Xem [`patches/lbp2900-macos.patch`](patches/lbp2900-macos.patch).

Hành vi này khớp với đặc tả giao thức CAPT đã reverse-engineer (xem [`captdriver/SPECS`](captdriver/SPECS)): bản ghi status mở rộng (reply cho `0xA0A8`) chứa bộ đếm trang ở byte 14–21, và cờ hết giấy nằm ở STATUS0 bit 1 / STATUS1 bit 14.

## Build từ mã nguồn

Binary arm64 dựng sẵn nằm trong `prebuilt/arm64/`. Để build lại (ví dụ cho Intel hoặc binary universal), xem [`docs/BUILD.md`](docs/BUILD.md). Vắn tắt:

```bash
cd captdriver
autoreconf -fi && ./configure
make CFLAGS="-D_DARWIN_C_SOURCE -std=gnu99 -O2"     # -> src/rastertocapt
```

Thư mục `captdriver/` ở đây là captdriver gốc **đã áp sẵn bản vá macOS/LBP2900**, kèm theo vừa để build một lệnh, vừa để tuân thủ yêu cầu cung cấp mã nguồn của GPLv3.

## Dự kiến

- Giải mã bit trạng thái kẹt giấy / mở nắp (STATUS2 bit 7 = “Problem” theo đặc tả) để báo lỗi cụ thể thay vì chỉ dừng chung chung.
- Binary universal (arm64 + x86_64) dựng sẵn.

## Ghi công

- [captdriver](https://github.com/mounaiban/captdriver) của Moses Chong và các cộng sự — CUPS filter CAPT mà dự án này dựa trên.
- Công reverse-engineer CAPT gốc bởi **Alexey Galakhov**, Nicolas Boichat, Benoit Bolsee và những người khác (xem [`captdriver/AUTHORS`](captdriver/AUTHORS) và [`captdriver/SPECS`](captdriver/SPECS)).
- Port macOS, vá chiến lược status cho LBP2900, và báo trạng thái native: repo này.

Đây là phần mềm không chính thức, không do Canon Inc. bảo trợ hay liên kết.

## Giấy phép

**GNU General Public License v3** — xem [`LICENSE`](LICENSE). captdriver theo GPLv3, và tác phẩm phái sinh này (bản vá + binary) cũng phát hành theo cùng điều khoản.
