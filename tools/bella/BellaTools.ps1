# =====================================================================
#  MIRAFILM - BANG DIEU KHIEN MAY BELLA (dslrBooth)
#  Action: Panel (mac dinh) | TimAnh | DonBoNho | TatMay | KiemTra
# =====================================================================
param([string]$Action = 'Panel', [switch]$NoGui, [switch]$DryRun)

$ErrorActionPreference = 'Continue'
$Root   = $PSScriptRoot
$LogDir = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Version = '?'
$vf = Join-Path $Root 'version.txt'
if (Test-Path $vf) { $Version = (Get-Content $vf -Raw).Trim() }

if (-not $NoGui) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
}

function Write-Log([string]$msg) {
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:COMPUTERNAME, $msg
    Add-Content -Path (Join-Path $LogDir 'hoat-dong.log') -Value $line -Encoding UTF8
}

# ---------------------------------------------------------------- config
$Cfg = [ordered]@{ BoothRoot = 'C:\dslrBooth'; Event = ''; KeepDays = 30; SendFolder = ''; ShowCount = 12; MinFreeGB = 30 }
$cp = Join-Path $Root 'config.json'
if (Test-Path $cp) {
    try { $j = Get-Content $cp -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $Cfg[$p.Name] = $p.Value } } catch { }
}
$script:Dry = [bool]$DryRun
$BoothRoot = [string]$Cfg.BoothRoot
$Skip = @('Frames', 'Settings', 'Shares', 'Templates')

function Get-EventDir {
    if ($Cfg.Event) { $p = Join-Path $BoothRoot $Cfg.Event; if (Test-Path (Join-Path $p 'Prints')) { return $p } }
    # tu do: thu muc su kien co Prints moi nhat
    $best = $null; $bestT = [datetime]::MinValue
    foreach ($d in Get-ChildItem -LiteralPath $BoothRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $Skip -notcontains $_.Name }) {
        $pd = Join-Path $d.FullName 'Prints'
        if (Test-Path $pd) { $t = (Get-Item $pd).LastWriteTime; if ($t -gt $bestT) { $bestT = $t; $best = $d.FullName } }
    }
    return $best
}
$EventDir = Get-EventDir
$SendDir = $(if ($Cfg.SendFolder) { [string]$Cfg.SendFolder } else { Join-Path ([Environment]::GetFolderPath('Desktop')) 'Gửi khách' })

# =====================================================================
#  GHEP LUOT CHUP
#  Frame + video: chung ma gio in  <yyyyMMdd_HHmmss_fff>
#  Anh goc: Originals\IMG_xxxx_<yyyyMMdd>_<HHmmss>.JPG chup sau lan in truoc, truoc lan in nay
# =====================================================================
$RxSession = '^(\d{8})_(\d{6})_(\d{3})'
$RxShot = '_(\d{8})_(\d{6})'

function Parse-T([string]$d, [string]$t) {
    try { return [datetime]::ParseExact($d + $t, 'yyyyMMddHHmmss', $null) } catch { return $null }
}

function Get-Sessions([int]$max) {
    if (-not $EventDir) { return @() }
    $pd = Join-Path $EventDir 'Prints'; $od = Join-Path $EventDir 'Originals'; $ad = Join-Path $EventDir 'Animated'
    $prints = @(Get-ChildItem -LiteralPath $pd -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $RxSession })
    $groups = $prints | Group-Object { if ($_.Name -match $RxSession) { $Matches[1] + '_' + $Matches[2] + '_' + $Matches[3] } } |
              Sort-Object Name -Descending | Select-Object -First ($max + 1)
    if (-not $groups) { return @() }
    $oldest = $groups[-1].Name
    $tOldest = Parse-T $oldest.Substring(0, 8) $oldest.Substring(9, 6)
    $since = $tOldest.AddHours(-1)
    $orig = @(Get-ChildItem -LiteralPath $od -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $since } | ForEach-Object {
        if ($_.Name -match $RxShot) { $t = Parse-T $Matches[1] $Matches[2]; if ($t) { [pscustomobject]@{ File = $_; T = $t } } }
    } | Sort-Object T)
    $anim = @(Get-ChildItem -LiteralPath $ad -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $since -and $_.Extension -ieq '.mp4' })
    $list = @()
    for ($i = 0; $i -lt [Math]::Min($max, $groups.Count); $i++) {
        $base = $groups[$i].Name
        $T = Parse-T $base.Substring(0, 8) $base.Substring(9, 6)
        $P = $(if ($i + 1 -lt $groups.Count) { $n = $groups[$i + 1].Name; Parse-T $n.Substring(0, 8) $n.Substring(9, 6) } else { $T.AddMinutes(-20) })
        $lo = $(if ($P -gt $T.AddMinutes(-20)) { $P } else { $T.AddMinutes(-20) })
        $shots = @($orig | Where-Object { $_.T -gt $lo -and $_.T -le $T } | ForEach-Object { $_.File })
        $vids = @($anim | Where-Object { $_.Name.StartsWith($base) })
        $frames = @($groups[$i].Group | Sort-Object Name)
        $thumbs = @(Get-ChildItem -LiteralPath (Join-Path $pd 'thumb') -File -Filter "thumb_$base*" -ErrorAction SilentlyContinue)
        $list += [pscustomobject]@{
            Id = $base; Time = $T; Frames = $frames; Shots = $shots; Videos = $vids
            Thumb = $(if ($thumbs) { $thumbs[0].FullName } else { ($frames | Sort-Object Length | Select-Object -First 1).FullName })
        }
    }
    return $list
}

function Safe-Name([string]$s) { return ($s -replace '[\\/:*?"<>|]', ' ').Trim() }

function Invoke-Gom($s, [string]$label, [switch]$Zip) {
    $name = $s.Time.ToString('yyyy-MM-dd HH.mm') + $(if ($label) { ' - ' + (Safe-Name $label) } else { '' })
    $dest = Join-Path $SendDir $name
    if ($script:Dry) { Write-Log "[THU] Se gom $($s.Frames.Count) frame, $($s.Shots.Count) anh goc, $($s.Videos.Count) video -> $dest"; return $dest }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $n = 0
    foreach ($f in @($s.Frames) + @($s.Shots) + @($s.Videos)) { Copy-Item -LiteralPath $f.FullName -Destination $dest -Force; $n++ }
    $out = $dest
    if ($Zip) {
        $zp = "$dest.zip"
        if (Test-Path -LiteralPath $zp) { Remove-Item -LiteralPath $zp -Force }
        Compress-Archive -Path (Join-Path $dest '*') -DestinationPath $zp -CompressionLevel NoCompression
        $out = $zp
    }
    $csv = Join-Path $LogDir 'gom-anh.csv'
    if (-not (Test-Path $csv)) { Add-Content -Path $csv -Value 'ThoiGian,May,Luot,SoFile,Ten,NoiLuu' -Encoding UTF8 }
    Add-Content -Path $csv -Value ('{0},{1},{2},{3},"{4}","{5}"' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:COMPUTERNAME, $s.Id, $n, $label, $out) -Encoding UTF8
    Write-Log "Gom luot $($s.Id): $n file -> $out"
    return $out
}

# =====================================================================
#  DON BO NHO
# =====================================================================
$AllowedExt = @('.jpg', '.jpeg', '.png', '.mp4', '.mov', '.gif')
function Get-CleanTargets {
    $t = @()
    foreach ($ev in Get-ChildItem -LiteralPath $BoothRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $Skip -notcontains $_.Name }) {
        foreach ($sub in 'Singles', 'Originals', 'Prints', 'Animated', 'Videos', 'GreenScreen') {
            $p = Join-Path $ev.FullName $sub
            if (Test-Path -LiteralPath $p -PathType Container) { $t += $p }
        }
    }
    $sh = Join-Path $BoothRoot 'Shares'; if (Test-Path -LiteralPath $sh) { $t += $sh }
    if (Test-Path -LiteralPath $SendDir) { $t += $SendDir }
    return $t
}
function Get-OldFiles([int]$keep) {
    if ($keep -lt 7) { $keep = 7 }   # rao chan: khong bao gio xoa anh moi hon 7 ngay
    $cutoff = (Get-Date).Date.AddDays(-($keep - 1))
    $all = foreach ($d in Get-CleanTargets) {
        [IO.Directory]::EnumerateFiles($d, '*', [IO.SearchOption]::AllDirectories) | ForEach-Object { [IO.FileInfo]$_ } |
            Where-Object { $_.LastWriteTime -lt $cutoff -and ($AllowedExt -contains $_.Extension.ToLower() -or $d -eq $SendDir) }
    }
    return @($all)
}
function Remove-Files($files) {
    [double]$bytes = ($files | Measure-Object Length -Sum).Sum
    if ($script:Dry) { Write-Log ("[THU] Se xoa {0} file, {1:N1} GB" -f @($files).Count, ($bytes / 1GB)); return @{ Count = @($files).Count; GB = [math]::Round($bytes / 1GB, 1) } }
    $n = 0; $fail = 0
    foreach ($f in $files) { try { [IO.File]::Delete($f.FullName); $n++ } catch { $fail++ } }
    foreach ($d in @((Join-Path $BoothRoot 'Shares'), $SendDir)) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        Get-ChildItem -LiteralPath $d -Recurse -Directory -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending |
            Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue) } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }
    Write-Log ("Don bo nho: xoa {0} file ({1:N1} GB), loi {2}. O trong {3} GB" -f $n, ($bytes / 1GB), $fail, (Get-FreeGB))
    return @{ Count = $n; GB = [math]::Round($bytes / 1GB, 1) }
}
function Get-FreeGB { try { [math]::Round((New-Object IO.DriveInfo([IO.Path]::GetPathRoot($BoothRoot))).AvailableFreeSpace / 1GB, 1) } catch { -1 } }

# =====================================================================
#  GIAO DIEN
# =====================================================================
if ($NoGui) { return }

$FontBig = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$FontMid = New-Object System.Drawing.Font('Segoe UI', 12)
$FontSmall = New-Object System.Drawing.Font('Segoe UI', 10)

function New-Owner { $o = New-Object System.Windows.Forms.Form; $o.TopMost = $true; $o.ShowInTaskbar = $false; $o.Opacity = 0; $o.Size = New-Object System.Drawing.Size(1, 1); $o.StartPosition = 'CenterScreen'; $o.Show(); $o.Activate(); return $o }
function Ask([string]$t) { $o = New-Owner; try { $r = [System.Windows.Forms.MessageBox]::Show($o, $t, 'Mirafilm', 'YesNo', 'Question', 'Button2') } finally { $o.Close() }; return ($r -eq 'Yes') }
function Say([string]$t) { $o = New-Owner; try { [System.Windows.Forms.MessageBox]::Show($o, $t, 'Mirafilm', 'OK', 'Information') | Out-Null } finally { $o.Close() } }

$script:Prog = $null
function Show-Progress([string]$title) {
    $f = New-Object System.Windows.Forms.Form; $f.Text = 'Mirafilm'; $f.Size = New-Object System.Drawing.Size(600, 200)
    $f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.ControlBox = $false; $f.FormBorderStyle = 'FixedDialog'
    $t = New-Object System.Windows.Forms.Label; $t.Text = $title; $t.Font = $FontBig; $t.SetBounds(20, 15, 550, 40)
    $l = New-Object System.Windows.Forms.Label; $l.Font = $FontMid; $l.SetBounds(20, 65, 550, 80); $l.Text = 'Vui lòng chờ, KHÔNG tắt cửa sổ này...'
    $f.Controls.AddRange(@($t, $l)); $f.Show(); [System.Windows.Forms.Application]::DoEvents()
    $script:Prog = @{ Form = $f; Label = $l }
}
function Step([string]$t) { if ($script:Prog) { $script:Prog.Label.Text = $t; [System.Windows.Forms.Application]::DoEvents() } }
function Close-Progress { if ($script:Prog) { $script:Prog.Form.Close(); $script:Prog = $null } }

# ---------------------------------------------------------------- Tim anh khach
function Show-TimAnh {
    $script:TA = @{ Sel = $null; Items = @{}; Thumbs = @(); Show = [int]$Cfg.ShowCount }
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Mirafilm - Tìm ảnh khách (mất QR)' + $(if ($script:Dry) { '  [CHẠY THỬ]' } else { '' })
    $f.WindowState = 'Maximized'; $f.TopMost = $true; $f.KeyPreview = $true
    $f.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

    $top = New-Object System.Windows.Forms.Panel; $top.Dock = 'Top'; $top.Height = 60
    $info = New-Object System.Windows.Forms.Label; $info.SetBounds(15, 8, 1500, 48); $info.Font = $FontMid
    $info.Text = "Lượt mới nhất ở đầu. Chạm vào ảnh của khách rồi bấm GOM FILE: máy chép ảnh frame + ảnh gốc + video vào thư mục '$SendDir'."
    $top.Controls.Add($info)

    $bot = New-Object System.Windows.Forms.Panel; $bot.Dock = 'Bottom'; $bot.Height = 100; $bot.BackColor = [System.Drawing.Color]::White
    $lblName = New-Object System.Windows.Forms.Label; $lblName.Text = 'Tên khách (không bắt buộc):'; $lblName.Font = $FontSmall; $lblName.SetBounds(15, 12, 260, 22)
    $txtName = New-Object System.Windows.Forms.TextBox; $txtName.Font = $FontMid; $txtName.SetBounds(15, 38, 300, 32)
    $chkZip = New-Object System.Windows.Forms.CheckBox; $chkZip.Text = 'Nén thành 1 file .zip'; $chkZip.Font = $FontSmall; $chkZip.Checked = $true; $chkZip.SetBounds(330, 42, 200, 26)
    $btnGom = New-Object System.Windows.Forms.Button; $btnGom.Text = 'GOM FILE'; $btnGom.Font = $FontBig; $btnGom.SetBounds(540, 14, 230, 72)
    $btnGom.BackColor = [System.Drawing.Color]::FromArgb(82, 10, 10); $btnGom.ForeColor = [System.Drawing.Color]::White; $btnGom.FlatStyle = 'Flat'
    $btnMore = New-Object System.Windows.Forms.Button; $btnMore.Text = 'Xem thêm lượt cũ hơn'; $btnMore.Font = $FontMid; $btnMore.SetBounds(790, 14, 210, 72)
    $btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = 'Đóng'; $btnClose.Font = $FontMid; $btnClose.SetBounds(1015, 14, 120, 72)
    $selLbl = New-Object System.Windows.Forms.Label; $selLbl.Font = $FontMid; $selLbl.SetBounds(1150, 14, 600, 72)
    $bot.Controls.AddRange(@($lblName, $txtName, $chkZip, $btnGom, $btnMore, $btnClose, $selLbl))

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel; $flow.Dock = 'Fill'; $flow.AutoScroll = $true; $flow.Padding = New-Object System.Windows.Forms.Padding(10)
    $f.Controls.Add($flow); $f.Controls.Add($bot); $f.Controls.Add($top)

    $selectTile = {
        param($tile)
        foreach ($c in $flow.Controls) { $c.BackColor = [System.Drawing.Color]::White }
        $tile.BackColor = [System.Drawing.Color]::FromArgb(233, 230, 215)
        $script:TA.Sel = [string]$tile.Tag
        $s = $script:TA.Items[$script:TA.Sel]
        $selLbl.Text = "Đã chọn lượt " + $s.Time.ToString('HH:mm dd/MM') + "`n" + "$($s.Frames.Count) frame, $($s.Shots.Count) ảnh gốc, $($s.Videos.Count) video"
    }
    $load = {
        foreach ($t in $script:TA.Thumbs) { $t.Dispose() }
        $script:TA.Thumbs = @(); $script:TA.Items = @{}; $script:TA.Sel = $null; $selLbl.Text = ''
        $flow.Controls.Clear(); $f.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $items = @(Get-Sessions ([int]$script:TA.Show))
        foreach ($s in $items) {
            $script:TA.Items[$s.Id] = $s
            $tile = New-Object System.Windows.Forms.Panel; $tile.Size = New-Object System.Drawing.Size(280, 380); $tile.Margin = New-Object System.Windows.Forms.Padding(8)
            $tile.BackColor = [System.Drawing.Color]::White; $tile.Tag = $s.Id; $tile.Cursor = [System.Windows.Forms.Cursors]::Hand
            $pb = New-Object System.Windows.Forms.PictureBox; $pb.SizeMode = 'Zoom'; $pb.SetBounds(6, 6, 268, 300); $pb.Tag = $s.Id
            try {
                $ms = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($s.Thumb)); $im = [System.Drawing.Image]::FromStream($ms)
                $r = [Math]::Min(560 / $im.Width, 560 / $im.Height); if ($r -gt 1) { $r = 1 }
                $th = New-Object System.Drawing.Bitmap($im, [int]($im.Width * $r), [int]($im.Height * $r)); $im.Dispose(); $ms.Dispose()
                $pb.Image = $th; $script:TA.Thumbs += $th
            } catch { }
            $lb = New-Object System.Windows.Forms.Label; $lb.SetBounds(6, 310, 268, 64); $lb.Font = $FontSmall; $lb.TextAlign = 'MiddleCenter'; $lb.Tag = $s.Id
            $mins = [int]((Get-Date) - $s.Time).TotalMinutes
            $ago = $(if ($mins -lt 60) { "$mins phút trước" } elseif ($mins -lt 1440) { "$([int]($mins/60)) giờ trước" } else { "$([int]($mins/1440)) ngày trước" })
            $lb.Text = $s.Time.ToString('HH:mm  dd/MM') + "  ($ago)`n$($s.Shots.Count) ảnh gốc · $($s.Videos.Count) video"
            if ($s.Shots.Count -eq 0) { $lb.ForeColor = [System.Drawing.Color]::Firebrick }
            $tile.Controls.AddRange(@($pb, $lb))
            $h = { param($x, $e) $t = $x; if ($t -isnot [System.Windows.Forms.Panel]) { $t = $x.Parent }; & $selectTile $t }
            $tile.Add_Click($h); $pb.Add_Click($h); $lb.Add_Click($h)
            $flow.Controls.Add($tile)
        }
        $f.Cursor = [System.Windows.Forms.Cursors]::Default
        $btnMore.Enabled = ($items.Count -ge $script:TA.Show)
        if ($script:TA.Show -gt [int]$Cfg.ShowCount -and $flow.Controls.Count -gt 0) {
            $flow.ScrollControlIntoView($flow.Controls[[Math]::Max(0, $flow.Controls.Count - [int]$Cfg.ShowCount)])
        }
        if ($items.Count -eq 0) { $info.Text = "Không tìm thấy lượt chụp nào trong $EventDir\Prints" }
    }
    $btnMore.Add_Click({ $script:TA.Show += [int]$Cfg.ShowCount; & $load })
    $btnClose.Add_Click({ $f.Close() })
    $btnGom.Add_Click({
        if (-not $script:TA.Sel) { Say 'Chưa chọn lượt. Chạm vào ảnh của khách trước.'; return }
        $s = $script:TA.Items[$script:TA.Sel]
        if (-not (Ask ("Gom file lượt " + $s.Time.ToString('HH:mm dd/MM') + "?`n`n$($s.Frames.Count) ảnh frame, $($s.Shots.Count) ảnh gốc, $($s.Videos.Count) video"))) { return }
        $btnGom.Enabled = $false; $btnGom.Text = 'Đang gom...'; [System.Windows.Forms.Application]::DoEvents()
        try { $out = Invoke-Gom $s $txtName.Text -Zip:$chkZip.Checked } catch { $out = $null; Say "Có lỗi khi gom file: $($_.Exception.Message)" }
        $btnGom.Enabled = $true; $btnGom.Text = 'GOM FILE'
        if ($out -and -not $script:Dry) { Start-Process explorer.exe "/select,`"$out`""; $txtName.Text = '' }
        elseif ($script:Dry) { Say "[CHẠY THỬ] Không chép thật. Xem nhật ký: $LogDir\hoat-dong.log" }
    })
    $f.Add_KeyDown({ param($x, $e) if ($e.KeyCode -eq 'Escape') { $f.Close() } })
    $f.Add_Shown({ & $load })
    $f.Add_FormClosed({ foreach ($t in $script:TA.Thumbs) { $t.Dispose() } })
    [void]$f.ShowDialog()
}

# ---------------------------------------------------------------- Don / Tat may / Kiem tra
function Invoke-DonBoNho {
    Show-Progress 'Đang kiểm tra bộ nhớ...'; Step 'Đang đếm file cũ (có thể mất 1-2 phút)...'
    $files = Get-OldFiles ([int]$Cfg.KeepDays); Close-Progress
    $gb = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1GB, 1)
    if ($files.Count -eq 0) { Say "Không có file nào cũ hơn $($Cfg.KeepDays) ngày.`nỔ đĩa còn trống: $(Get-FreeGB) GB."; return }
    if (-not (Ask "DỌN BỘ NHỚ`n`nSẽ xoá $($files.Count) file cũ hơn $($Cfg.KeepDays) ngày (~$gb GB).`nKhông đụng: File hình khách, frame, template.`nỔ đĩa đang trống: $(Get-FreeGB) GB.`n`nTiếp tục?")) { return }
    Show-Progress 'Đang dọn bộ nhớ...'; Step "Đang xoá $($files.Count) file..."
    $r = Remove-Files $files; Close-Progress
    Say $(if ($script:Dry) { "[CHẠY THỬ] Không xoá gì. Nếu chạy thật sẽ xoá $($r.Count) file (~$($r.GB) GB)." } else { "XONG. Đã xoá $($r.Count) file (~$($r.GB) GB).`nỔ đĩa còn trống: $(Get-FreeGB) GB." })
}
function Invoke-TatMay {
    if (-not (Ask "TẮT MÁY CUỐI NGÀY`n`nMáy sẽ tự dọn ảnh/video cũ hơn $($Cfg.KeepDays) ngày rồi TẮT MÁY.`n`nTiếp tục?")) { return }
    Write-Log '=== TAT MAY CUOI NGAY'
    Show-Progress 'Đang tắt máy cuối ngày...'; Step 'Đang dọn ảnh cũ...'
    $files = Get-OldFiles ([int]$Cfg.KeepDays); if ($files.Count -gt 0) { Remove-Files $files | Out-Null }
    Step 'Đang tắt máy...'; Start-Sleep 2
    if ($script:Dry) { Close-Progress; Say '[CHẠY THỬ] Đến đây máy sẽ TẮT. Không làm gì thật.'; return }
    shutdown.exe /s /t 5 /c "Mirafilm: tat may cuoi ngay"
}
function Invoke-KiemTra {
    $scan = Join-Path $Root 'BellaScan.ps1'
    if (-not (Test-Path $scan)) { Say 'Thiếu file BellaScan.ps1'; return }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scan`"" -Wait
    $rep = Join-Path $Root 'bella-scan.txt'; if (Test-Path $rep) { Start-Process notepad.exe $rep }
}

function Show-Panel {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Mirafilm - Bảng điều khiển ($env:COMPUTERNAME) - bản $Version" + $(if ($script:Dry) { '  [CHẠY THỬ]' } else { '' })
    $f.Size = New-Object System.Drawing.Size(560, 560); $f.StartPosition = 'CenterScreen'; $f.TopMost = $true
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.BackColor = [System.Drawing.Color]::White
    $status = New-Object System.Windows.Forms.Label; $status.Font = $FontMid; $status.SetBounds(20, 10, 510, 50)
    $refresh = {
        $free = Get-FreeGB; $status.Text = "Ổ đĩa còn trống: $free GB"
        if ($free -ge 0 -and $free -lt [double]$Cfg.MinFreeGB) { $status.Text += '  - SẮP ĐẦY, bấm Dọn bộ nhớ'; $status.ForeColor = [System.Drawing.Color]::Firebrick }
        else { $status.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60) }
    }
    $mk = {
        param($text, $y, $h, $r, $g, $b, $big)
        $x = New-Object System.Windows.Forms.Button; $x.Text = $text; $x.SetBounds(20, $y, 505, $h)
        $x.Font = $(if ($big) { $FontBig } else { $FontMid }); $x.BackColor = [System.Drawing.Color]::FromArgb($r, $g, $b)
        $x.ForeColor = [System.Drawing.Color]::White; $x.FlatStyle = 'Flat'; $x.FlatAppearance.BorderSize = 0
        $f.Controls.Add($x); return $x
    }
    $b1 = & $mk '1   TÌM ẢNH KHÁCH (mất QR)' 65 90 82 10 10 $true
    $b2 = & $mk '2   DỌN BỘ NHỚ' 165 80 25 118 210 $true
    $b3 = & $mk '3   TẮT MÁY CUỐI NGÀY' 255 80 183 28 28 $true
    $b4 = & $mk '    Kiểm tra máy (chỉ đọc)' 345 50 97 97 97 $false
    $f.Controls.Add($status)
    $b1.Add_Click({ $f.Hide(); Show-TimAnh; $f.Show() })
    $b2.Add_Click({ $f.Hide(); Invoke-DonBoNho; & $refresh; $f.Show() })
    $b3.Add_Click({ $f.Hide(); Invoke-TatMay; $f.Show() })
    $b4.Add_Click({ $f.Hide(); Invoke-KiemTra; $f.Show() })
    $f.Add_Shown({ & $refresh })
    [void]$f.ShowDialog()
}

$created = $false
$mtx = New-Object System.Threading.Mutex($true, "MirafilmBella_$Action", [ref]$created)
if (-not $created) { exit 0 }
try {
    switch ($Action) {
        'TimAnh'   { Show-TimAnh }
        'DonBoNho' { Invoke-DonBoNho }
        'TatMay'   { Invoke-TatMay }
        'KiemTra'  { Invoke-KiemTra }
        default    { Show-Panel }
    }
} catch {
    Write-Log "LOI: $($_.Exception.Message)"; Close-Progress
    Say "Có lỗi: $($_.Exception.Message)`nChụp màn hình gửi quản lý."
} finally { $mtx.ReleaseMutex() }
