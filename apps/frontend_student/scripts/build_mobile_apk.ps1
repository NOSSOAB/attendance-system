param(
    [Parameter(Mandatory = $true)]
    [string]$ApiBaseUrl
)

$ErrorActionPreference = 'Stop'
$api = $ApiBaseUrl.Trim().TrimEnd('/')
$uri = $null
if (-not [Uri]::TryCreate($api, [UriKind]::Absolute, [ref]$uri) -or
    $uri.Scheme -ne 'https' -or
    [string]::IsNullOrWhiteSpace($uri.Host) -or
    $uri.AbsolutePath -ne '/' -or
    $uri.Query -or
    $uri.Fragment -or
    $uri.UserInfo) {
    throw 'ApiBaseUrl phải là địa chỉ gốc HTTPS của API, không có path hoặc thông tin đăng nhập.'
}

$health = Invoke-WebRequest -Uri "$api/health" -TimeoutSec 10
if ($health.StatusCode -ne 200) {
    throw "API không sẵn sàng: HTTP $($health.StatusCode)"
}

$flutter = (Get-Command flutter.bat -ErrorAction SilentlyContinue).Source
if (-not $flutter -and $env:FLUTTER_ROOT) {
    $flutter = Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat'
}
if (-not $flutter -or -not (Test-Path -LiteralPath $flutter)) {
    throw 'Không tìm thấy flutter.bat trong PATH hoặc FLUTTER_ROOT.'
}

$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repository = (Resolve-Path (Join-Path $project '..\..')).Path
$output = Join-Path $repository 'dist/smartattendance-mobile-first-v1.0.13-arm64-release.apk'
New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { throw 'Cần Python để kiểm tra và chuẩn bị model nhận diện khuôn mặt.' }
& $python (Join-Path $PSScriptRoot 'prepare_mobile_models.py')
if ($LASTEXITCODE -ne 0) { throw 'Chuẩn bị model nhận diện khuôn mặt thất bại.' }

Push-Location $project
try {
    & $flutter build apk --release --target-platform android-arm64 `
        "--dart-define=API_BASE_URL=$api" `
        '--dart-define=MOBILE_FACE_AUTH=true' `
        '--dart-define=BLE_ATTENDANCE_ENABLED=true'
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter build thất bại (exit code $LASTEXITCODE)."
    }
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination $output -Force
    $apk = Get-Item -LiteralPath $output
    Write-Output "$($apk.FullName) ($([math]::Round($apk.Length / 1MB, 2)) MiB)"
} finally {
    Pop-Location
}
