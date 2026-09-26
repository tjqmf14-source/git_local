param(
    [string]$Version = '1.0.0-alpha.3'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root 'dist'
$publish = Join-Path $dist 'publish'
$packageName = "GitLocal-$Version-win-x64"
$packageDir = Join-Path $dist $packageName
$zipPath = Join-Path $dist "$packageName.zip"
$hashPath = Join-Path $dist "$packageName.sha256.txt"

if (Test-Path -LiteralPath $dist) { Remove-Item -LiteralPath $dist -Recurse -Force }
New-Item -ItemType Directory -Path $publish -Force | Out-Null
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

& dotnet publish (Join-Path $root 'launcher\GitLocal.Launcher.csproj') -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None -p:DebugSymbols=false -o $publish
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed: $LASTEXITCODE" }

$exe = Join-Path $publish 'GitLocal.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'GitLocal.exe was not generated.' }

Copy-Item -LiteralPath $exe -Destination (Join-Path $packageDir 'GitLocal.exe')
Copy-Item -LiteralPath (Join-Path $root 'Git_Local_START.cmd') -Destination $packageDir
Copy-Item -LiteralPath (Join-Path $root 'README.md') -Destination $packageDir
Copy-Item -LiteralPath (Join-Path $root 'src') -Destination $packageDir -Recurse
Copy-Item -LiteralPath (Join-Path $root 'assets') -Destination $packageDir -Recurse

$packageExe = Join-Path $packageDir 'GitLocal.exe'
$exeSelfTest = Start-Process -FilePath $packageExe -ArgumentList '--self-test' -Wait -PassThru
if ($exeSelfTest.ExitCode -ne 0) { throw "Packaged EXE self-test failed: $($exeSelfTest.ExitCode)" }

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $packageDir 'src\GitLocal.App.ps1') -SelfTest
if ($LASTEXITCODE -ne 0) { throw "Packaged UI self-test failed: $LASTEXITCODE" }

Compress-Archive -Path (Join-Path $packageDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
$hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
("{0}  {1}" -f $hash.Hash.ToLowerInvariant(),(Split-Path -Leaf $zipPath)) | Set-Content -LiteralPath $hashPath -Encoding ASCII

Write-Host "PACKAGE=$zipPath"
Write-Host "SHA256=$($hash.Hash)"
