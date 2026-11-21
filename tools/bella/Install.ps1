# MIRAFILM - CAI DAT BO CONG CU MAY BELLA (chay 1 lan tren moi may, qua CaiDat.bat)
param([int]$KeepDays = 30)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
$Src = $PSScriptRoot
$Dest = 'C:\MirafilmBella'
New-Item -ItemType Directory -Force -Path $Dest, (Join-Path $Dest 'logs') | Out-Null

$files = 'BellaTools.ps1', 'BellaScan.ps1', 'Update.ps1', 'version.txt', 'HUONG_DAN.txt'
foreach ($fn in $files) { $p = Join-Path $Src $fn; if ((Test-Path $p) -and ($Src.TrimEnd('\') -ne $Dest)) { Copy-Item $p $Dest -Force } }

# config: giu lai so ngay cu neu da cai truoc do
$cp = Join-Path $Dest 'config.json'
$cfg = [ordered]@{ BoothRoot = 'C:\dslrBooth'; Event = ''; KeepDays = $KeepDays; SendFolder = ''; ShowCount = 12; MinFreeGB = 30; UpdateBase = 'https://mirafilm.github.io/tools/bella/' }
if (Test-Path $cp) { try { $old = Get-Content $cp -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $old.PSObject.Properties) { $cfg[$p.Name] = $p.Value } } catch { } }
$cfg | ConvertTo-Json | Set-Content $cp -Encoding UTF8

# loi tat (WScript.Shell khong luu duoc ten co dau -> luu ten tam roi doi ten)
$wsh = New-Object -ComObject WScript.Shell
$ps = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
function New-Lnk($path, $script, $args2, $hotkey, $icon) {
    $tmp = Join-Path (Split-Path $path -Parent) ('mirafilm_tmp_' + [guid]::NewGuid().ToString('N') + '.lnk')
    $s = $wsh.CreateShortcut($tmp)
    $s.TargetPath = $ps
    $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Dest\$script`" $args2"
    $s.WorkingDirectory = $Dest; $s.IconLocation = $icon
    if ($hotkey) { $s.Hotkey = $hotkey }
    $s.Save()
    Move-Item -LiteralPath $tmp -Destination $path -Force
}
$desk = [Environment]::GetFolderPath('Desktop')
New-Lnk (Join-Path $desk 'Bảng điều khiển.lnk') 'BellaTools.ps1' '-Action Panel' 'CTRL+ALT+M' "$env:WINDIR\System32\shell32.dll,21"
New-Lnk (Join-Path $desk 'Tìm ảnh khách.lnk') 'BellaTools.ps1' '-Action TimAnh' 'CTRL+ALT+F' "$env:WINDIR\System32\shell32.dll,22"
New-Lnk (Join-Path ([Environment]::GetFolderPath('Startup')) 'Mirafilm cap nhat.lnk') 'Update.ps1' '' $null "$env:WINDIR\System32\shell32.dll,46"

# cap nhat ngay lan dau (khong sao neu khong co mang)
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dest 'Update.ps1')
$ver = if (Test-Path "$Dest\version.txt") { (Get-Content "$Dest\version.txt" -Raw).Trim() } else { '?' }
$upd = if (Test-Path "$Dest\logs\cap-nhat.log") { (Get-Content "$Dest\logs\cap-nhat.log" | Select-Object -Last 1) } else { '' }
[System.Windows.Forms.MessageBox]::Show("ĐÃ CÀI XONG trên máy $env:COMPUTERNAME (bản $ver).`n`nDesktop: 'Bảng điều khiển' (Ctrl+Alt+M) và 'Tìm ảnh khách' (Ctrl+Alt+F).`nGiữ ảnh $($cfg.KeepDays) ngày. Máy tự cập nhật mỗi lần bật.`n`n$upd", 'Mirafilm') | Out-Null
