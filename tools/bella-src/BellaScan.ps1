# MIRAFILM - KIEM TRA MAY BELLA (CHI DOC, KHONG XOA GI)
$ErrorActionPreference = 'Continue'
$Root = 'C:\dslrBooth'
$Out = Join-Path $PSScriptRoot 'bella-scan.txt'
$L = New-Object System.Collections.Generic.List[string]
function Add([string]$s) { $L.Add($s); Write-Host $s }

Add "KIEM TRA MAY BELLA $env:COMPUTERNAME - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$d = New-Object IO.DriveInfo('C:\')
Add ("O C con trong: {0:N1} GB / tong {1:N1} GB" -f ($d.AvailableFreeSpace/1GB), ($d.TotalSize/1GB))
foreach ($dr in [IO.DriveInfo]::GetDrives()) { if ($dr.IsReady -and $dr.DriveType -eq 'Fixed') { Add ("  O {0} trong {1:N1} / {2:N1} GB" -f $dr.Name, ($dr.AvailableFreeSpace/1GB), ($dr.TotalSize/1GB)) } }
$t = [IO.Path]::GetTempPath()
$tf = Get-ChildItem -LiteralPath $t -Recurse -File -Force -ErrorAction SilentlyContinue
Add ("%temp%: {0} file, {1:N2} GB" -f @($tf).Count, (($tf | Measure-Object Length -Sum).Sum/1GB))
Add ''

# Bella app / tien trinh
$procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'PhotoBooth|dslrBooth|Bella' } | ForEach-Object { "$($_.ProcessName) [$($_.Path)]" }
Add ("Tien trinh Bella/dslrBooth dang chay: " + $(if ($procs) { $procs -join ' | ' } else { '(khong)' }))
$printers = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
Add ("May in: " + ($printers -join ' | '))
Add ''

# Cac thu muc
$events = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('Frames','Settings','Shares','Templates') }
Add ("Thu muc su kien trong C:\dslrBooth: " + (($events | ForEach-Object Name) -join ', '))
$targets = @()
foreach ($ev in $events) { $targets += Get-ChildItem -LiteralPath $ev.FullName -Directory -ErrorAction SilentlyContinue }
$targets += Get-Item -LiteralPath (Join-Path $Root 'Shares') -ErrorAction SilentlyContinue
$cut7 = (Get-Date).Date.AddDays(-6); $cut14 = (Get-Date).Date.AddDays(-13); $cut30 = (Get-Date).Date.AddDays(-29)
foreach ($dir in $targets) {
    $files = @([IO.Directory]::EnumerateFiles($dir.FullName, '*', [IO.SearchOption]::AllDirectories) | ForEach-Object { [IO.FileInfo]$_ })
    if ($files.Count -eq 0) { Add ("{0}: trong" -f $dir.FullName); continue }
    $sum = ($files | Measure-Object Length -Sum).Sum
    $old = $files | Sort-Object LastWriteTime | Select-Object -First 1
    $new = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $o7 = ($files | Where-Object { $_.LastWriteTime -lt $cut7 } | Measure-Object Length -Sum)
    $o14 = ($files | Where-Object { $_.LastWriteTime -lt $cut14 } | Measure-Object Length -Sum)
    $o30 = ($files | Where-Object { $_.LastWriteTime -lt $cut30 } | Measure-Object Length -Sum)
    Add ("{0}: {1} file, {2:N2} GB, cu nhat {3:yyyy-MM-dd}, moi nhat {4:yyyy-MM-dd HH:mm}" -f $dir.FullName, $files.Count, ($sum/1GB), $old.LastWriteTime, $new.LastWriteTime)
    Add ("    cu hon 7 ngay: {0} file {1:N2} GB | 14 ngay: {2} file {3:N2} GB | 30 ngay: {4} file {5:N2} GB" -f $o7.Count, ($o7.Sum/1GB), $o14.Count, ($o14.Sum/1GB), $o30.Count, ($o30.Sum/1GB))
    $ext = $files | Group-Object { $_.Extension.ToLower() } | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { "$($_.Name)=$($_.Count)" }
    Add ("    loai file: " + ($ext -join ', '))
    $samp = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 4 | ForEach-Object { $_.FullName.Substring($dir.FullName.Length + 1) }
    Add ("    moi nhat: " + ($samp -join ' | '))
}
Add ''

# Luot chup / ngay theo Prints
foreach ($ev in $events) {
    $pd = Join-Path $ev.FullName 'Prints'
    if (-not (Test-Path $pd)) { continue }
    $ids = [IO.Directory]::EnumerateFiles($pd) | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) } |
           Where-Object { $_ -match '^(\d{8})_(\d{6})_(\d{3})' } | ForEach-Object { $Matches[1] + '_' + $Matches[2] } | Sort-Object -Unique
    $byDay = $ids | Group-Object { $_.Substring(0, 8) } | Sort-Object Name | Select-Object -Last 14
    Add ("Luot chup/ngay (theo Prints, su kien $($ev.Name)): " + (($byDay | ForEach-Object { "$($_.Name.Substring(4)):$($_.Count)" }) -join '  '))
}
Add ''

# Thu ghep 5 luot gan nhat: Prints <- Originals <- Animated
function TimeOf([string]$name) {
    if ($name -match '(\d{8})_(\d{6})') { try { return [datetime]::ParseExact($Matches[1] + $Matches[2], 'yyyyMMddHHmmss', $null) } catch { } }
    return $null
}
foreach ($ev in $events) {
    $pd = Join-Path $ev.FullName 'Prints'; $od = Join-Path $ev.FullName 'Originals'; $ad = Join-Path $ev.FullName 'Animated'
    if (-not (Test-Path $pd)) { continue }
    $since = (Get-Date).AddDays(-2)
    $prints = Get-ChildItem -LiteralPath $pd -File | Where-Object { $_.LastWriteTime -gt $since } | Sort-Object Name
    $orig = Get-ChildItem -LiteralPath $od -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $since.AddHours(-1) } | Sort-Object Name
    $anim = Get-ChildItem -LiteralPath $ad -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $since.AddHours(-1) } | Sort-Object Name
    Add "Mau ghep luot (su kien $($ev.Name), 6 ban in gan nhat):"
    $base = $prints | ForEach-Object { if ($_.BaseName -match '^(\d{8}_\d{6}_\d{3})') { $Matches[1] } } | Sort-Object -Unique
    $last = $base | Select-Object -Last 7
    for ($i = 1; $i -lt $last.Count; $i++) {
        $T = TimeOf $last[$i]; $P = TimeOf $last[$i - 1]
        $os = $orig | Where-Object { $ot = TimeOf $_.Name; $ot -and $ot -gt $P -and $ot -le $T }
        $vs = $anim | Where-Object { $vt = TimeOf $_.Name; $vt -and $vt -gt $P -and $vt -le $T.AddMinutes(3) }
        $pf = $prints | Where-Object { $_.BaseName.StartsWith($last[$i]) } | ForEach-Object Name
        Add ("  In {0:HH:mm:ss}: frame=[{1}] goc={2} ({3} -> {4}) video=[{5}]" -f $T, ($pf -join ','), @($os).Count,
             $(if ($os) { (TimeOf @($os)[0].Name).ToString('HH:mm:ss') } else { '-' }), $(if ($os) { (TimeOf @($os)[-1].Name).ToString('HH:mm:ss') } else { '-' }), (($vs | ForEach-Object Name) -join ','))
    }
}
Add ''
$sh = Get-ChildItem -LiteralPath (Join-Path $Root 'Shares') -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3
foreach ($s in $sh) { Add ("Shares moi: {0} ({1:yyyy-MM-dd HH:mm}): {2}" -f $s.Name, $s.LastWriteTime, ((Get-ChildItem -LiteralPath $s.FullName -File | ForEach-Object Name) -join ', ')) }
$L | Set-Content -Path $Out -Encoding UTF8
Add ''
Add "XONG. Bao cao: $Out"
