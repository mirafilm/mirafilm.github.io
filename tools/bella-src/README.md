# Bộ công cụ máy Bella (Mirafilm CN1, CN2)

Mã nguồn của bộ công cụ cài ở `C:\MirafilmBella` trên các máy chụp Bella/dslrBooth.

- `BellaTools.ps1`: Bảng điều khiển, Tìm ảnh khách (khi mất mã QR), Dọn bộ nhớ, Tắt máy cuối ngày.
- `BellaScan.ps1`: Kiểm tra máy (chỉ đọc).
- `Update.ps1`: tự cập nhật khi bật máy từ `https://mirafilm.github.io/tools/bella/manifest.json`. Kiểm tra SHA256 từng file, không đụng `config.json`.
- `Install.ps1` + `CaiDat.bat`: cài lần đầu.

Phát hành bản mới (lấy ngày làm số phiên bản):

```
python3 tools/bella-src/build.py 2026.11.21.1 tools/bella
```

Sau đó commit và push lên `main`. Các máy sẽ tự cập nhật ở lần bật máy tiếp theo.
