$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$versionLine = Select-String -Path (Join-Path $ProjectRoot 'pubspec.yaml') -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+(\d+)'
if (-not $versionLine) {
    throw 'Could not read app version from pubspec.yaml.'
}
$version = $versionLine.Matches[0].Groups[1].Value
$archive = "MoonCalendar-$version-windows-x64.zip"

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    throw 'Flutter is not on PATH. Open a new PowerShell after configuring Flutter, then retry.'
}

Write-Host 'Flutter version:'
flutter --version
if ($LASTEXITCODE -ne 0) { throw 'flutter --version failed.' }

flutter clean
if ($LASTEXITCODE -ne 0) { throw 'flutter clean failed.' }

flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build windows --release failed.' }

$bundle = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
$exe = Join-Path $bundle 'mooncalendar.exe'
if (-not (Test-Path $exe)) {
    throw "Build reported success, but the executable was not found at $exe"
}

$dist = Join-Path $ProjectRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$destination = Join-Path $dist $archive
if (Test-Path $destination) { Remove-Item $destination -Force }
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $destination -CompressionLevel Optimal

Write-Host ''
Write-Host "Release bundle created: $destination"
Write-Host 'This is a portable ZIP. It contains the release executable and runtime files; it is not an installer.'
