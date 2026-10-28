param(
    # Target architecture of the Windows build: x64 (default) or arm64 (needs an Arm64 PC and the Arm64 Flutter SDK).
    [ValidateSet('x64', 'arm64')]
    [string]$Arch = 'x64'
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$versionLine = Select-String -Path (Join-Path $ProjectRoot 'pubspec.yaml') -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+(\d+)'
if (-not $versionLine) {
    throw 'Could not read app version/build number from pubspec.yaml.'
}
$version = $versionLine.Matches[0].Groups[1].Value
$buildNumber = $versionLine.Matches[0].Groups[2].Value
$archive = "MoonCalendar-$version-windows-$Arch.zip"

$appVersionFile = Get-Content (Join-Path $ProjectRoot 'lib\core\app_version.dart') -Raw
if ($appVersionFile -notmatch "appVersion\s*=\s*'$([regex]::Escape($version))'") {
    throw "Version mismatch: pubspec.yaml says $version but lib\core\app_version.dart does not."
}
$runnerCmake = Get-Content (Join-Path $ProjectRoot 'windows\runner\CMakeLists.txt') -Raw
$expectedVersionDefinition = 'FLUTTER_VERSION=\"' + $version + '\"'
if (-not $runnerCmake.Contains($expectedVersionDefinition)) {
    throw "Windows executable metadata is not set to $version in windows\runner\CMakeLists.txt."
}
$runnerRc = Get-Content (Join-Path $ProjectRoot 'windows\runner\Runner.rc') -Raw
$expectedResourceVersion = '#define VERSION_AS_STRING "' + $version + '"'
if (-not $runnerRc.Contains($expectedResourceVersion)) {
    throw "Windows Explorer file version is not set to $version in windows\runner\Runner.rc."
}

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    throw 'Flutter is not on PATH. Open a new PowerShell after configuring Flutter, then retry.'
}

Write-Host "Preparing MoonCalendar $version+$buildNumber ($Arch)"
Write-Host 'Flutter version:'
flutter --version
if ($LASTEXITCODE -ne 0) { throw 'flutter --version failed.' }

flutter clean
if ($LASTEXITCODE -ne 0) { throw 'flutter clean failed.' }

flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

flutter analyze --no-fatal-infos --no-fatal-warnings
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed; resolve errors before releasing.' }

flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build windows --release failed.' }

$bundle = Join-Path $ProjectRoot "build\windows\$Arch\runner\Release"
$exe = Join-Path $bundle 'mooncalendar.exe'
if (-not (Test-Path $exe)) {
    throw "Build reported success, but the executable was not found at $exe"
}

$dist = Join-Path $ProjectRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$destination = Join-Path $dist $archive
if (Test-Path $destination) { Remove-Item $destination -Force }
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $destination -CompressionLevel Optimal
$portableLatest = Join-Path $dist "MoonCalendar-windows-$Arch.zip"
Copy-Item $destination $portableLatest -Force

# The updater deliberately looks for this exact release asset name. Build it locally too, rather than
# leaving the user with only the portable ZIP. The in-app updater consumes the ZIP;
# Setup remains available for first installs and manual repair/reinstallation.
$programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$candidates = @(
    (Join-Path $programFilesX86 'Inno Setup 7\ISCC.exe'),
    (Join-Path $programFilesX86 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
)
$iscc = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) {
    $isccCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($isccCommand) { $iscc = $isccCommand.Source }
}
if (-not $iscc) {
    throw "Portable ZIP created at $destination, but Inno Setup 6/7 ISCC.exe was not found. Install Inno Setup to create the setup.exe required by the updater."
}

$env:MOONCALENDAR_VERSION = $version
$env:MOONCALENDAR_ARCH = $Arch
$iss = Join-Path $ProjectRoot 'windows\installer\Mooncalendar.iss'
Write-Host "Compiling installer with $iscc"
& $iscc $iss
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed to compile the installer.' }

$setupBuilt = Join-Path $ProjectRoot "windows\installer\Output\MoonCalendar-Setup-$Arch.exe"
if (-not (Test-Path $setupBuilt)) {
    throw "Inno Setup reported success, but installer was not found at $setupBuilt"
}
$setupLatest = Join-Path $dist "MoonCalendar-windows-$Arch-setup.exe"
$setupVersioned = Join-Path $dist "MoonCalendar-$version-windows-$Arch-setup.exe"
Copy-Item $setupBuilt $setupLatest -Force
Copy-Item $setupBuilt $setupVersioned -Force

Write-Host ''
Write-Host "Release outputs created in $dist :"
Write-Host "  Portable:  $destination"
Write-Host "  Portable:  $portableLatest"
Write-Host "  Installer: $setupLatest (first install / manual repair)"
Write-Host "  Installer: $setupVersioned"
Write-Host 'The Windows installer has been compiled. The in-app updater uses the portable ZIP; test power-loss recovery and rollback on Windows before publishing.'
