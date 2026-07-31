$ErrorActionPreference='Stop'
$pkg='C:\Tools\akre-pkg'

# consolidate to ONE cert (remove duplicates from earlier attempts)
$existing = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq 'CN=Virto Akre Test' }
if ($existing) { $existing | Select-Object -Skip 1 | ForEach-Object { Remove-Item ("Cert:\LocalMachine\My\"+$_.Thumbprint) -Force } }
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq 'CN=Virto Akre Test' } | Select-Object -First 1
if (-not $cert) {
  $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=Virto Akre Test' `
    -CertStoreLocation Cert:\LocalMachine\My -KeyUsage DigitalSignature `
    -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3') -NotAfter (Get-Date).AddYears(5)
}
"cert: $($cert.Thumbprint)  HasPrivateKey=$($cert.HasPrivateKey)"

function Sign-Retry($path) {
  for ($i=0; $i -lt 6; $i++) {
    $r = Set-AuthenticodeSignature $path -Certificate $cert -HashAlgorithm SHA256
    if ($r.Status -eq 'Valid') { return $r.Status }
    Start-Sleep -Milliseconds 800
  }
  return $r.Status
}

# fresh package: CI INF + UMDs, RAW akre KMD swapped in
Remove-Item $pkg -Recurse -Force -EA SilentlyContinue
New-Item -ItemType Directory -Path $pkg | Out-Null
Copy-Item C:\Tools\viogpu3d-new\* $pkg -Force
Remove-Item "$pkg\viogpu3d.cat","$pkg\VirtIOTestCert.cer" -EA SilentlyContinue
Copy-Item C:\Tools\viogpu3d-akre.sys "$pkg\viogpu3d.sys" -Force
$inf = (Get-Content "$pkg\viogpu3d.inf") -replace 'DriverVer\s*=.*','DriverVer = 07/31/2026,100.6.101.60000'
Set-Content "$pkg\viogpu3d.inf" $inf
"sys=$((Get-Item "$pkg\viogpu3d.sys").Length) (akre=136192)"

# CORRECT ORDER: 1) embed-sign .sys  2) catalog (hashes signed .sys)  3) sign .cat  -- nothing touches .sys after
"sign sys: " + (Sign-Retry "$pkg\viogpu3d.sys")
New-FileCatalog -Path $pkg -CatalogFilePath "$pkg\viogpu3d.cat" -CatalogVersion 2 | Out-Null
"sign cat: " + (Sign-Retry "$pkg\viogpu3d.cat")

# verify final on-disk state
foreach($f in 'viogpu3d.sys','viogpu3d.cat'){ $g=Get-AuthenticodeSignature "$pkg\$f"; "  $f : $($g.Status)" }

# trust cert
foreach($s in 'Root','TrustedPublisher'){ $st=New-Object System.Security.Cryptography.X509Certificates.X509Store($s,'LocalMachine'); $st.Open('ReadWrite'); $st.Add($cert); $st.Close() }
"cert trusted (Root + TrustedPublisher)"

# remove the earlier oem17 (mismatched) then install clean
$old = (pnputil /enum-drivers | Out-String) -split "`r?`n`r?`n" | Where-Object { $_ -match 'viogpu3d\.inf' -and $_ -match '100\.6\.101\.59000' }
$oem = ([regex]::Match(($old -join "`n"),'Published Name:\s*(oem\d+\.inf)')).Groups[1].Value
if ($oem) { pnputil /delete-driver $oem /uninstall /force 2>&1 | Out-Null; "removed old $oem" }
$r = pnputil /add-driver "$pkg\viogpu3d.inf" /install 2>&1 | Out-String
($r -split "`r?`n" | Where-Object { $_ -match 'Published|installed on device|success|fail|Added' }) -join ' | '
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\VioGpu3D' -Name Start -Value 3 -EA SilentlyContinue
"done"
