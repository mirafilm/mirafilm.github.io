/**
 * MIRAFILM - CẦU NỐI DRIVE CHO MÁY BELLA
 * Dán vào 1 dự án Apps Script MỚI, tạo khi đang đăng nhập mirafilm.ops@gmail.com.
 *
 * Máy booth KHÔNG giữ chìa khoá Drive. Máy gọi web app này để:
 *   1. tạo thư mục khách trong "File hình PTB (tự động)", chia sẻ "Bất kỳ ai có link - Xem"
 *   2. xin 1 link tải lên cho từng file, rồi máy tự đẩy file thẳng lên Google theo link đó.
 * Web app chỉ làm được 2 việc trên, trong đúng thư mục gốc đó, và phải có mã KEY.
 *
 * CÀI ĐẶT (1 lần):
 *   - Chạy hàm caiDat() -> cấp quyền -> xem Nhật ký thực thi (lấy KEY + link thư mục).
 *   - Triển khai > Tùy chọn triển khai mới > Ứng dụng web: Thực thi với tư cách "Tôi", Ai có quyền truy cập "Bất kỳ ai".
 *   - Mã kết nối dán vào máy booth = <URL ứng dụng web>#<KEY>
 */
var TEN_GOC = 'File hình PTB (tự động)';

function doPost(e) {
  var r;
  try {
    var q = JSON.parse(e.postData.contents);
    var P = PropertiesService.getScriptProperties();
    if (!q.key || q.key !== P.getProperty('KEY')) throw new Error('Sai mã kết nối');
    if (q.a === 'ping') r = { root: layGoc_().getUrl() };
    else if (q.a === 'folder') r = taoThuMuc_(q.name);
    else if (q.a === 'file') r = taoFile_(q.folder, q.name, q.size, q.mime);
    else throw new Error('Lệnh không hợp lệ');
    r.ok = true;
  } catch (err) {
    r = { ok: false, error: String(err && err.message || err) };
  }
  return ContentService.createTextOutput(JSON.stringify(r)).setMimeType(ContentService.MimeType.JSON);
}

function layGoc_() {
  var P = PropertiesService.getScriptProperties();
  var id = P.getProperty('ROOT_ID');
  if (id) {
    try { var g = DriveApp.getFolderById(id); if (!g.isTrashed()) return g; } catch (e) { }
  }
  var lock = LockService.getScriptLock(); lock.waitLock(20000);
  try {
    id = P.getProperty('ROOT_ID');
    if (id) { try { var g2 = DriveApp.getFolderById(id); if (!g2.isTrashed()) return g2; } catch (e) { } }
    var f = DriveApp.createFolder(TEN_GOC);
    P.setProperty('ROOT_ID', f.getId());
    return f;
  } finally { lock.releaseLock(); }
}

function taoThuMuc_(name) {
  name = String(name || 'Khách').replace(/[\\\/]/g, ' ').slice(0, 150);
  var f = layGoc_().createFolder(name);
  f.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  return { folder: f.getId(), url: f.getUrl() };
}

function taoFile_(folderId, name, size, mime) {
  var f = DriveApp.getFolderById(String(folderId));
  var gocId = layGoc_().getId(), ok = false, ps = f.getParents();
  while (ps.hasNext()) { if (ps.next().getId() === gocId) ok = true; }
  if (!ok) throw new Error('Thư mục không thuộc ' + TEN_GOC);
  var res = UrlFetchApp.fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable', {
    method: 'post',
    contentType: 'application/json; charset=UTF-8',
    headers: {
      Authorization: 'Bearer ' + ScriptApp.getOAuthToken(),
      'X-Upload-Content-Type': String(mime || 'application/octet-stream'),
      'X-Upload-Content-Length': String(size)
    },
    payload: JSON.stringify({ name: String(name), parents: [f.getId()] }),
    muteHttpExceptions: true
  });
  if (res.getResponseCode() !== 200) throw new Error('Drive ' + res.getResponseCode() + ': ' + res.getContentText().slice(0, 200));
  var h = res.getAllHeaders();
  return { upload: h.Location || h.location };
}

/** Chạy 1 lần: tạo KEY + thư mục gốc. Chạy lại chỉ in ra KEY cũ. */
function caiDat() {
  var P = PropertiesService.getScriptProperties();
  var k = P.getProperty('KEY');
  if (!k) { k = Utilities.getUuid().replace(/-/g, ''); P.setProperty('KEY', k); }
  var g = layGoc_();
  DriveApp.getRootFolder(); // xin quyền Drive
  Logger.log('Thư mục gốc: ' + g.getUrl());
  Logger.log('KEY: ' + k);
  Logger.log('Mã kết nối cho máy booth = <URL ứng dụng web>#' + k);
}

/** Đổi KEY (khi nghi lộ). Sau đó phải dán mã mới vào cả 5 máy. */
function doiKey() {
  PropertiesService.getScriptProperties().deleteProperty('KEY');
  caiDat();
}
