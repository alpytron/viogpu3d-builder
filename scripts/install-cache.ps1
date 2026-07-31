$ErrorActionPreference='Stop'
$pkg='C:\Tools\akre-cache'
$localSys='D:\src\viogpu\viogpu3d\objfre_win10_amd64\amd64\viogpu3d.sys'
Remove-Item $pkg -Recurse -Force -EA SilentlyContinue
New-Item -ItemType Directory $pkg | Out-Null
# package skeleton (akre INF w/ HWCursor=1 + D3D10 UMD + Venus ICD) from the share
Copy-Item 'Y:\VMs\share\akre-min\*' $pkg -Recurse -Force
Remove-Item "$pkg\viogpu3d.cat" -EA SilentlyContinue
# overlay the LOCALLY-built cache driver
Copy-Item $localSys "$pkg\viogpu3d.sys" -Force
"sys: $((Get-Item "$pkg\viogpu3d.sys").Length) (local cache build=139264)"
# bump DriverVer so it supersedes the installed one
$inf = (Get-Content "$pkg\viogpu3d.inf") -replace 'DriverVer\s*=.*','DriverVer = 07/31/2026,100.2026.7.51'
Set-Content "$pkg\viogpu3d.inf" $inf
($inf | Select-String 'DriverVer|HWCursor')

$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq 'CN=Virto Akre Test' -and $_.HasPrivateKey } | Select-Object -First 1
function Sign-Retry($p){ for($i=0;$i -lt 6;$i++){ $r=Set-AuthenticodeSignature $p -Certificate $cert -HashAlgorithm SHA256; if($r.Status -eq 'Valid'){return 'Valid'}; Start-Sleep -Milliseconds 800 }; return $r.Status }
"sign sys: " + (Sign-Retry "$pkg\viogpu3d.sys")
New-FileCatalog -Path $pkg -CatalogFilePath "$pkg\viogpu3d.cat" -CatalogVersion 2 | Out-Null
"sign cat: " + (Sign-Retry "$pkg\viogpu3d.cat")

# remove previous viogpu3d packages
$pkgs = (pnputil /enum-drivers | Out-String) -split "`r?`n`r?`n" | Where-Object { $_ -match 'viogpu3d\.inf' }
foreach($p in $pkgs){ $oem=([regex]::Match($p,'Published Name:\s*(oem\d+\.inf)')).Groups[1].Value; if($oem){ pnputil /delete-driver $oem /uninstall /force 2>&1 | Out-Null } }
$r = pnputil /add-driver "$pkg\viogpu3d.inf" /install 2>&1 | Out-String
($r -split "`r?`n" | Where-Object { $_ -match 'Published|installed on device|success|fail|Added' }) -join ' | '
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\VioGpu3D' -Name Start -Value 3 -EA SilentlyContinue
$d = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match 'VirtIO' } | Select-Object -First 1
"device: $($d.FriendlyName) $($d.Status)" | Out-File C:\Tools\install-cache.done
"done"
