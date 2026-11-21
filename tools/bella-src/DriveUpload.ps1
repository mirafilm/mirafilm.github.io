# =====================================================================
#  MIRAFILM - TAI THU MUC KHACH LEN DRIVE + LAY LINK
#  Goi tu "Tim anh khach": DriveUpload.ps1 -Dir <thu muc da gom> -Name <ten thu muc tren Drive>
#  May KHONG giu chia khoa Drive: xin link tai len tu Apps Script (DriveUrl + DriveKey trong config.json)
# =====================================================================
param([string]$Dir, [string]$Name, [switch]$NoGui)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$LogDir = Join-Path $Root 'logs'; New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

function Write-Log([string]$msg) {
    Add-Content -Path (Join-Path $LogDir 'hoat-dong.log') -Value ('[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:COMPUTERNAME, $msg) -Encoding UTF8
}

function Get-DriveCfg {
    $c = @{ Url = ''; Key = '' }
    $cp = Join-Path $Root 'config.json'
    if (Test-Path $cp) {
        $j = Get-Content $cp -Raw -Encoding UTF8 | ConvertFrom-Json
        $c.Url = [string]$j.DriveUrl; $c.Key = [string]$j.DriveKey
    }
    return $c
}

function Invoke-Relay($cfg, [hashtable]$body) {
    $body.key = $cfg.Key
    $bytes = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress))
    $r = Invoke-RestMethod -Uri $cfg.Url -Method Post -Body $bytes -ContentType 'text/plain; charset=utf-8' -TimeoutSec 60 -UseBasicParsing
    if ($r -is [string]) { $r = $r | ConvertFrom-Json }
    if (-not $r.ok) { throw "Máy chủ Drive báo lỗi: $($r.error)" }
    return $r
}

function Get-Mime([string]$ext) {
    switch ($ext.ToLower()) {
        '.jpg' { 'image/jpeg' } '.jpeg' { 'image/jpeg' } '.png' { 'image/png' } '.gif' { 'image/gif' }
        '.mp4' { 'video/mp4' } '.mov' { 'video/quicktime' } '.zip' { 'application/zip' }
        default { 'application/octet-stream' }
    }
}

# Day 1 file len link tai len (resumable session). $tick duoc goi voi so byte vua gui.
function Send-File([string]$url, [IO.FileInfo]$fi, [scriptblock]$tick) {
    $req = [Net.HttpWebRequest]::Create($url)
    $req.Method = 'PUT'; $req.ContentLength = $fi.Length; $req.ContentType = Get-Mime $fi.Extension
    $req.AllowWriteStreamBuffering = $false; $req.SendChunked = $false
    $req.Timeout = 900000; $req.ReadWriteTimeout = 900000
    $in = [IO.File]::OpenRead($fi.FullName)
    try {
        $out = $req.GetRequestStream()
        try {
            $buf = New-Object byte[] (1MB)
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) { $out.Write($buf, 0, $n); if ($tick) { & $tick $n } }
        } finally { $out.Close() }
    } finally { $in.Close() }
    $resp = $req.GetResponse()
    try { $code = [int]$resp.StatusCode } finally { $resp.Close() }
    if ($code -ne 200 -and $code -ne 201) { throw "Google trả mã $code cho $($fi.Name)" }
}

# Tai ca thu muc. $state giu ket qua giua cac lan thu lai (thu muc Drive + file da xong).
function Invoke-Upload([string]$dir, [string]$name, $state, [scriptblock]$onStep, [scriptblock]$tick) {
    $cfg = Get-DriveCfg
    if (-not $cfg.Url -or -not $cfg.Key) { throw 'Máy chưa kết nối Drive (thiếu mã kết nối).' }
    $files = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Extension -ine '.zip' } | Sort-Object Name)
    if ($files.Count -eq 0) { throw "Thư mục trống: $dir" }
    if (-not $state.Folder) {
        if ($onStep) { & $onStep 'Đang tạo thư mục trên Drive...' }
        $r = Invoke-Relay $cfg @{ a = 'folder'; name = $name }
        $state.Folder = [string]$r.folder; $state.Url = [string]$r.url
    }
    $i = 0
    foreach ($fi in $files) {
        $i++
        if ($state.Done.ContainsKey($fi.Name)) { continue }
        if ($onStep) { & $onStep ("Đang tải file {0}/{1}: {2}" -f $i, $files.Count, $fi.Name) }
        $tries = 0
        while ($true) {
            $tries++
            try {
                $u = Invoke-Relay $cfg @{ a = 'file'; folder = $state.Folder; name = $fi.Name; size = $fi.Length; mime = (Get-Mime $fi.Extension) }
                Send-File ([string]$u.upload) $fi $tick
                break
            } catch {
                if ($tries -ge 3) { throw "Không tải được $($fi.Name): $($_.Exception.Message)" }
                Start-Sleep -Seconds (3 * $tries)
            }
        }
        $state.Done[$fi.Name] = $true
    }
    [double]$mb = ($files | Measure-Object Length -Sum).Sum / 1MB
    $csv = Join-Path $LogDir 'drive-link.csv'
    if (-not (Test-Path $csv)) { Add-Content -Path $csv -Value 'ThoiGian,May,Ten,SoFile,MB,Link' -Encoding UTF8 }
    Add-Content -Path $csv -Value ('{0},{1},"{2}",{3},{4:N0},{5}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:COMPUTERNAME, $name, $files.Count, $mb, $state.Url) -Encoding UTF8
    Write-Log ("Drive: {0} file ({1:N0} MB) -> {2}" -f $files.Count, $mb, $state.Url)
    return @{ Url = $state.Url; Count = $files.Count; MB = $mb; Total = [double]($files | Measure-Object Length -Sum).Sum }
}

if ($NoGui -or -not $Dir) { return }

# ===================================================================== GIAO DIEN
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$FontBig = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
$FontMid = New-Object System.Drawing.Font('Segoe UI', 11)
if (-not $Name) { $Name = Split-Path $Dir -Leaf }

$f = New-Object System.Windows.Forms.Form
$f.Text = 'Mirafilm - Tải lên Drive'; $f.Size = New-Object System.Drawing.Size(680, 330)
$f.StartPosition = 'CenterScreen'; $f.TopMost = $true; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $true
$f.BackColor = [System.Drawing.Color]::White
$title = New-Object System.Windows.Forms.Label; $title.Font = $FontBig; $title.SetBounds(20, 15, 630, 36); $title.Text = 'Đang tải lên Drive...'
$sub = New-Object System.Windows.Forms.Label; $sub.Font = $FontMid; $sub.SetBounds(20, 55, 630, 26); $sub.Text = $Name
$step = New-Object System.Windows.Forms.Label; $step.Font = $FontMid; $step.SetBounds(20, 85, 630, 26); $step.ForeColor = [System.Drawing.Color]::DimGray
$bar = New-Object System.Windows.Forms.ProgressBar; $bar.SetBounds(20, 118, 625, 26); $bar.Maximum = 1000
$link = New-Object System.Windows.Forms.TextBox; $link.Font = $FontMid; $link.SetBounds(20, 160, 625, 30); $link.ReadOnly = $true; $link.Visible = $false
$bCopy = New-Object System.Windows.Forms.Button; $bCopy.Text = 'Chép link'; $bCopy.Font = $FontMid; $bCopy.SetBounds(20, 205, 150, 55); $bCopy.Visible = $false
$bCopy.BackColor = [System.Drawing.Color]::FromArgb(82, 10, 10); $bCopy.ForeColor = [System.Drawing.Color]::White; $bCopy.FlatStyle = 'Flat'
$bOpen = New-Object System.Windows.Forms.Button; $bOpen.Text = 'Mở link'; $bOpen.Font = $FontMid; $bOpen.SetBounds(180, 205, 130, 55); $bOpen.Visible = $false
$bRetry = New-Object System.Windows.Forms.Button; $bRetry.Text = 'Thử lại'; $bRetry.Font = $FontMid; $bRetry.SetBounds(20, 205, 150, 55); $bRetry.Visible = $false
$bClose = New-Object System.Windows.Forms.Button; $bClose.Text = 'Đóng'; $bClose.Font = $FontMid; $bClose.SetBounds(525, 205, 120, 55)
$f.Controls.AddRange(@($title, $sub, $step, $bar, $link, $bCopy, $bOpen, $bRetry, $bClose))

$script:St = @{ Folder = ''; Url = ''; Done = @{} }
$script:Busy = $false
[double]$script:Total = (Get-ChildItem -LiteralPath $Dir -File | Where-Object { $_.Extension -ine '.zip' } | Measure-Object Length -Sum).Sum
[double]$script:Sent = 0

$copyLink = { try { [System.Windows.Forms.Clipboard]::SetText($link.Text); $step.Text = 'Đã chép link. Dán (Ctrl+V) vào Zalo cho khách.' } catch { $step.Text = 'Không chép được, bôi đen link rồi Ctrl+C.' } }
$run = {
    $script:Busy = $true; $bRetry.Visible = $false; $title.Text = 'Đang tải lên Drive...'; $title.ForeColor = [System.Drawing.Color]::Black
    $bClose.Text = 'Ẩn'
    $script:Sent = 0; foreach ($k in $script:St.Done.Keys) { $p = Join-Path $Dir $k; if (Test-Path -LiteralPath $p) { $script:Sent += (Get-Item -LiteralPath $p).Length } }
    $onStep = { param($t) $step.Text = $t; [System.Windows.Forms.Application]::DoEvents() }
    $tick = { param($n) $script:Sent += $n; if ($script:Total -gt 0) { $bar.Value = [int][Math]::Min(1000, 1000 * $script:Sent / $script:Total) }; [System.Windows.Forms.Application]::DoEvents() }
    try {
        $r = Invoke-Upload $Dir $Name $script:St $onStep $tick
        $bar.Value = 1000
        $title.Text = 'XONG - link đã được chép'; $title.ForeColor = [System.Drawing.Color]::FromArgb(20, 120, 40)
        $sub.Text = ("{0}  ·  {1} file, {2:N0} MB" -f $Name, $r.Count, $r.MB)
        $link.Text = $r.Url; $link.Visible = $true; $bCopy.Visible = $true; $bOpen.Visible = $true
        & $copyLink
        $f.WindowState = 'Normal'; $f.Activate()
    } catch {
        Write-Log "Drive LOI: $($_.Exception.Message)"
        $title.Text = 'Chưa tải xong'; $title.ForeColor = [System.Drawing.Color]::Firebrick
        $step.Text = $_.Exception.Message + '  - Kiểm tra mạng rồi bấm Thử lại.'
        $bRetry.Visible = $true; $f.WindowState = 'Normal'; $f.Activate()
    }
    $bClose.Text = 'Đóng'; $script:Busy = $false
}
$bCopy.Add_Click($copyLink)
$bOpen.Add_Click({ Start-Process $link.Text })
$bRetry.Add_Click({ & $run })
$bClose.Add_Click({ if ($script:Busy) { $f.WindowState = 'Minimized' } else { $f.Close() } })
$f.Add_FormClosing({ param($x, $e) if ($script:Busy) { $e.Cancel = $true; $f.WindowState = 'Minimized' } })
$f.Add_Shown({ & $run })
[void]$f.ShowDialog()
