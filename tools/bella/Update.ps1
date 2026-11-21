# MIRAFILM - TU CAP NHAT BO CONG CU (chay an khi bat may)
# Tai manifest.json tu trang Mirafilm, kiem tra SHA256 tung file roi moi thay. Khong dung vao config.json.
param([string]$Base = '', [switch]$Force)
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$LogDir = Join-Path $Root 'logs'; New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
function Log([string]$m) { Add-Content -Path (Join-Path $LogDir 'cap-nhat.log') -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }

try {
    if (-not $Base) {
        $cp = Join-Path $Root 'config.json'
        if (Test-Path $cp) { $Base = [string]((Get-Content $cp -Raw -Encoding UTF8 | ConvertFrom-Json).UpdateBase) }
    }
    if (-not $Base) { $Base = 'https://mirafilm.github.io/tools/bella/' }
    if (-not $Base.EndsWith('/')) { $Base += '/' }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

    $local = ''; $vf = Join-Path $Root 'version.txt'; if (Test-Path $vf) { $local = (Get-Content $vf -Raw).Trim() }
    $mf = (Invoke-WebRequest -Uri ($Base + 'manifest.json?t=' + [DateTime]::UtcNow.Ticks) -UseBasicParsing -TimeoutSec 20).Content | ConvertFrom-Json
    if (-not $Force -and $mf.version -eq $local) { Log "Da la ban moi nhat ($local)"; exit 0 }

    $stage = Join-Path $Root '_update'
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage | Out-Null
    foreach ($f in $mf.files) {
        $name = [string]$f.name
        if ($name -notmatch '^[A-Za-z0-9_.-]+$' -or $name -ieq 'config.json') { throw "Ten file khong hop le trong manifest: $name" }
        $dst = Join-Path $stage $name
        Invoke-WebRequest -Uri ($Base + $name + '?v=' + $mf.version) -OutFile $dst -UseBasicParsing -TimeoutSec 60
        $h = (Get-FileHash -Path $dst -Algorithm SHA256).Hash
        if ($h -ne ([string]$f.sha256).ToUpper()) { throw "Sai ma kiem tra (SHA256) cua $name - huy cap nhat" }
    }
    # tat ca file deu dung -> moi thay
    foreach ($f in $mf.files) { Copy-Item -LiteralPath (Join-Path $stage $f.name) -Destination (Join-Path $Root $f.name) -Force }
    Set-Content -Path $vf -Value $mf.version -Encoding ASCII
    Remove-Item $stage -Recurse -Force
    Log "Da cap nhat $local -> $($mf.version) ($(@($mf.files).Count) file)"
} catch {
    Log "Khong cap nhat duoc: $($_.Exception.Message)"
    exit 1
}
