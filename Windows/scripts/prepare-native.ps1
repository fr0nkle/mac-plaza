$ErrorActionPreference = 'Stop'
$manifest = Get-Content native/sdk-manifest.json | ConvertFrom-Json
New-Item -ItemType Directory -Force native/build-input | Out-Null
gh release download $manifest.draftTag --repo fr0nkle/mac-plaza --pattern $manifest.asset --dir native/build-input --clobber
if ($LASTEXITCODE -ne 0) { throw 'Could not read the private SDK build draft. Do not publish it or substitute an unofficial SDK.' }
$archive = Join-Path native/build-input $manifest.asset
if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.sha256) { throw 'Official SDK build-input checksum mismatch.' }
Expand-Archive $archive native/sdk -Force
pnpm run build:native
if ($LASTEXITCODE -ne 0) { throw 'Native Windows bridge build failed.' }
New-Item -ItemType Directory -Force native/runtime | Out-Null
Copy-Item build/Release/plaza_native.node native/runtime/
Copy-Item native/sdk/bin/release/* native/runtime/ -Exclude arm64 -Force
Copy-Item native/sdk/License-Notices.txt native/runtime/DISCORD-LICENSE-NOTICES.txt
Write-Output 'Built the Windows wallpaper bridge and official Discord Social SDK integration.'
