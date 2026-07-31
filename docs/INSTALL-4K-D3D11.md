# viogpu3d: 4K + D3D11 + Venus on a Linux/QEMU host

Recipe that gets a Windows 10 guest full hardware 3D on `qemu:///session` with
virtio-gpu + virglrenderer (Venus) on a Linux/AMD host — **4K display, hardware
Vulkan (Venus), and D3D11 via DXVK** — on a single coherent, signed driver that
survives reboot. Verified 2026-07-31 on Win10 LTSC 2021, host QEMU 10.2.4,
AMD Radeon 840M (RADV GFX1153), Venus 26.1.0.

## The winning combination

**akre KMD (with the 4K fix) + akre INF + the 2026-06-04 akre Venus ICD.**

- **KMD**: `viogpu3d.sys` built from the `akre` branch (arehnman lineage) with the
  4K fix applied (`req_size` 16MB→64MB + a NULL-deref fix in `VioGpuObj::Init`).
  Build with `.github/workflows/build-akre-kmd.yml` (KMD-only; empty
  `MESA_PREFIX_x64` so the mesa/packaging steps self-skip).
- **INF**: use the **akre** INF, not a max8rr8/virtio-win INF. The akre INF sets
  device settings the others lack — `UsePhysicalMemory=0`, `FlexResolution=1`,
  `EnablePreemption=1`, `TdrDebugMode=1` — and auto-registers the Venus ICD.
  Installing the akre KMD under a max8rr8 INF gives `CM_PROB_FAILED_POST_START`
  (Code 43). A trimmed copy (KMD + D3D10 UMD + Venus ICD, no OpenGL/lavapipe) is
  in [`akre-package/viogpu3d.inf`](../akre-package/viogpu3d.inf).
- **Venus ICD**: `libvulkan_virtio.dll` (x64 36MB / x86 40MB) + `virtio_icd.*.json`
  from the 2026-06-04 akre build. The akre INF copies them to System32/SysWOW64
  and registers them under `HKLM\...\Khronos\Vulkan\Drivers`.

## Why proper signing (not the nointegritychecks hack)

Binary-swapping a `.sys` into an installed DriverStore package + `nointegritychecks`
works until the next **cold boot**, where PnP re-validates the package catalog
against the on-disk file and fails (`CM_PROB_UNSIGNED_DRIVER`). The durable fix is
a properly signed package under **test-signing**:

1. `bcdedit /set testsigning on`
2. `New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=Virto Akre Test' -CertStoreLocation Cert:\LocalMachine\My`
3. Import that cert to **both** `LocalMachine\Root` and `LocalMachine\TrustedPublisher`.
4. **Order matters** — nothing may touch the `.sys` after the catalog is built:
   1. `Set-AuthenticodeSignature` the `.sys` (embed sign)
   2. `New-FileCatalog -CatalogVersion 2` (hashes the signed `.sys`)
   3. `Set-AuthenticodeSignature` the `.cat`
5. `pnputil /add-driver <pkg>\viogpu3d.inf /install`

Gotcha: `Set-AuthenticodeSignature` throws a transient `UnknownError` immediately
after cert creation — wrap it in a retry loop (~6 × 800ms). Embed-signing the
`.sys` makes PnP trust the file itself, which is important because
`New-FileCatalog` uses flat (not PE-image) hashes. Full script:
[`scripts/sign-install-akre.ps1`](../scripts/sign-install-akre.ps1).

## Critical: everything GPU must run in an INTERACTIVE session

Venus, DXVK, and even `ChangeDisplaySettings` only work in the **logged-in user's
session**. A session-0 / `NT AUTHORITY\SYSTEM` process (e.g. plain `qemu-ga`
`guest-exec`) cannot reach the display adapter, so the Venus ICD enumerates **0
GPUs** (`Failed to detect any valid GPUs`) and the driver exposes no display modes.
Run tests via `Register-ScheduledTask -LogonType Interactive` for the logged-in
user, write results to a file, and read them back.

Also install the Vulkan runtime loader `vulkan-1.dll` into `System32` (LunarG 1.4
loader) or apps can't load Venus.

## D3D11 via DXVK

The native `viogpu_d3d10` UMD is a D3D10-class gallium driver — dxdiag reports
**Feature Level 10_0** max. For D3D11 use **DXVK** (D3D11→Vulkan→Venus): drop
`d3d11.dll` + `dxgi.dll` (from dxvk-2.4.1 x64) next to the target `.exe`.
Verified: `D3D11CreateDevice` → S_OK on the HW Venus adapter,
`Max supported feature level = D3D_FEATURE_LEVEL_12_1`. Test harness:
[`scripts/dxvk-d3d11-test.ps1`](../scripts/dxvk-d3d11-test.ps1).

## Verification results

| Check | Result |
|-------|--------|
| Display device | `Hardsoft VirtIO GPU 3D controller` — OK, survives cold boot |
| Vulkan | `Virtio-GPU Venus (AMD Radeon 840M (RADV GFX1153))`, venus 26.1.0 |
| D3D11 (DXVK) | `D3D11CreateDevice` S_OK, device on HW Venus, max FL 12_1 |
| 4K | `ChangeDisplaySettings(3840x2160)`=0, device OK, 31.6MB fb, no BSOD |

4K mode test: [`scripts/enum-4k-test.ps1`](../scripts/enum-4k-test.ps1).

## Host notes

- Guest has no internet (user-mode NAT restricted) → stage DXVK/loaders/driver via
  a virtiofs share (`~/VMs/share` → `Y:\VMs\share` RO home mount).
- Test-signing shows a "Test Mode" desktop watermark — expected for a self-signed
  driver.
- The 4K fix is also submitted upstream: max8rr8 PR #1 and an osy/neptune PR draft.
