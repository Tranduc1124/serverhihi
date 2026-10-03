# Prepare the current two-file APIClient SDK package on Windows.
# Windows cannot compile arm64 iOS archives; use Theos on macOS/Linux/WSL for the build.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Out = Join-Path $Root "..\dist\APIClient"
$Header = Join-Path $Root "include\APIClient.h"
$Archive = Join-Path $Out "libAPIClient.a"
$LegacyOut = Join-Path $Root "..\dist\TserverAuth"

if (-not (Test-Path -LiteralPath $Header -PathType Leaf)) {
  throw "Missing public APIClient header: $Header"
}

New-Item -ItemType Directory -Force -Path $Out | Out-Null
if (Test-Path -LiteralPath $LegacyOut -PathType Container) {
  Write-Warning "Retired SDK directory remains at $LegacyOut. Do not package or distribute it."
}
Copy-Item -LiteralPath $Header -Destination (Join-Path $Out "APIClient.h") -Force
Copy-Item -LiteralPath (Join-Path $Root "..\docs\CUSTOMER_INTEGRATION.md") -Destination (Join-Path $Out "INTEGRATE.md") -Force

if (Test-Path -LiteralPath $Archive -PathType Leaf) {
  Write-Host "Existing SDK archive retained: $Archive"
}
else {
  Write-Warning "libAPIClient.a is not present yet. Build it with Theos before releasing this package."
}

$Readme = @"
APIClient build notes (Windows)
===============================

Windows does not compile arm64 iOS archives. On a Theos macOS/Linux/WSL host:

  export THEOS=~/theos
  cd sdk-ios
  export TSERVER_CLIENT_API_KEY="<matching 64-hex CLIENT_API_KEY>"
  make clean all
  bash pack_customer_sdk.sh

The supported release files are APIClient.h and libAPIClient.a. Link Foundation,
UIKit, Security, and SafariServices. Do not ship or link retired libTserverAuth.a
packages. Verify a finished dylib using deploy/vps/diagnose-client-api-key.ps1
and require Artifact MATCH before release.
"@
Set-Content -LiteralPath (Join-Path $Out "BUILD_ON_MAC.md") -Value $Readme -Encoding utf8

Write-Host "Prepared current APIClient SDK folder: $Out"
Get-ChildItem -LiteralPath $Out | Select-Object Name, Length, LastWriteTime
