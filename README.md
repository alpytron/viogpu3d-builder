# viogpu3d Builder — 4K · D3D11 · Venus · hardware cursor on a Linux/QEMU host

Build automation and a working recipe for full hardware 3D in a **Windows 10**
guest on **`qemu:///session` + virtio-gpu + virglrenderer (Venus)** on a
**Linux/AMD** host — driving a real workstation VM (KVM, SPICE, AMD Radeon 840M /
RADV `gfx1153`, Venus 26.1.0).

## What works

| Capability | Status |
|---|---|
| **4K display** (3840×2160) | ✅ real 31.6 MB framebuffer, no BSOD |
| **Hardware Vulkan (Venus)** | ✅ `Virtio-GPU Venus (AMD Radeon 840M (RADV GFX1153))` |
| **D3D11 via DXVK** | ✅ `D3D11CreateDevice` on the HW adapter, up to feature level 12_1 |
| **Hardware mouse cursor** | ✅ smooth & wedge-free (shape cache) |
| Reboot-persistent, signed | ✅ test-signing + trusted self-signed cert |

All on a single coherent driver built from the **`akre`** branch (Ake Rehnman's
virtio-gpu 3D driver, arehnman lineage) plus the fixes below. See
[`docs/INSTALL-4K-D3D11.md`](docs/INSTALL-4K-D3D11.md) for the full install recipe.

## Driver fixes (branch `akre-4k-fix` of `alpytron/kvm-guest-drivers-windows-neptune`)

- **4K framebuffer** — `req_size` 16 MB → 64 MB so a 4K primary surface fits the
  frame segment; plus a NULL-deref fix in `VioGpuObj::Init`'s error path.
- **Hardware cursor** — the 3D driver shipped `DxgkDdiSetPointerShape/Position`
  as stubs, so Windows fell back to a software cursor that stutters at the
  present rate. Implemented the virtio-gpu hardware cursor and hardened it:
  - NULL-guard on `AllocCursor` (pool exhaustion under a `MOVE_CURSOR` flood),
  - hide→show recovery (a cursor hidden via `UPDATE_CURSOR` res_id 0 is re-shown
    with `UPDATE_CURSOR`, not `MOVE_CURSOR`),
  - keep the pointer position on shape changes (no teleport-to-corner),
  - **32-entry shape cache** — each distinct cursor image uploads once via
    `TransferToHost2D`; re-selecting a cached shape is a single cursor-queue
    command with no control-queue transfer. This is the key fix: without it,
    per-shape uploads accumulate on the shared control queue and eventually
    stall virglrenderer (guest GPU hang). Validated: 14 distinct cursors +
    fast-mouse + heavy present for 130 s with zero stalls.

## Building the driver

### Option A — GitHub Actions (KMD only)

`.github/workflows/build-akre-kmd.yml` builds `viogpu3d.sys` (x64) from
`akre-4k-fix`. It uses an empty `MESA_PREFIX_x64` so the Mesa/packaging steps
self-skip and only the kernel driver is produced. Trigger from the Actions tab;
download the `viogpu3d-kmd` artifact.

### Option B — Local EWDK build (fast iteration, in-guest)

A self-contained WDK toolchain in the guest gives minute-scale build cycles and
debug/traced builds. This is how the cursor work was iterated.

1. Download the **EWDK 26100** ISO (VS2022 BuildTools 17.14) — `go.microsoft.com/fwlink/?linkid=2335681` (~18.6 GB).
2. Attach a scratch NTFS disk to the VM (holds the source + build output) and put the driver source at `D:\src`.
3. In the guest, mount the EWDK and build:
   ```cmd
   powershell Mount-DiskImage -ImagePath <path-to-EWDK.iso>   :: mounts as E:
   mkdir D:\mesa_prefix
   call E:\BuildEnv\SetupBuildEnv.cmd amd64
   set MESA_PREFIX_x64=D:\mesa_prefix
   cd /d D:\src\VirtIO        && msbuild VirtioLib.vcxproj  /p:Configuration="Win10 Release" /p:Platform=x64
   cd /d D:\src\viogpu\viogpu3d && msbuild viogpu3d.vcxproj /p:Configuration="Win10 Release" /p:Platform=x64 /p:SignMode=Off
   ```
   Output: `D:\src\viogpu\viogpu3d\objfre_win10_amd64\amd64\viogpu3d.sys`.

Notes: configuration names contain a space (`Win10 Release|x64`); VirtioLib must
build first (the KMD links `virtiolib.lib`); `MESA_PREFIX_x64` must point at an
existing directory that contains **no** Mesa DLLs (validation passes, packaging
self-skips). The EWDK ISO can even be mounted straight off a virtiofs share.

## Repo contents

| Path | What |
|---|---|
| `docs/INSTALL-4K-D3D11.md` | End-to-end install recipe (akre KMD + INF + Venus ICD, signing, DXVK) |
| `akre-package/viogpu3d.inf` | Trimmed akre INF (device settings + Venus ICD registration) |
| `scripts/` | Signing/install + DXVK D3D11 and 4K test harnesses |
| `.github/workflows/build-akre-kmd.yml` | CI KMD build |

---

<details>
<summary>Original (upstream Mesa+driver) build automation — retained</summary>

Build automation for the viogpu3d driver with Mesa virgl support (OpenGL
`viogpu_wgl.dll` + D3D10 `viogpu_d3d10.dll` UMDs). Scripts:
`scripts/setup-environment.bat`, `build.bat`, `build-mesa-only.bat`,
`build-driver-only.bat`. Mesa config: `-Dgallium-drivers=virgl`,
`-Dgallium-d3d10umd=true`, `-Dgallium-wgl-dll-name=viogpu_wgl`,
`-Dgallium-d3d10-dll-name=viogpu_d3d10`, `-Db_vscrt=mt`.

References: [Mesa virgl](https://docs.mesa3d.org/drivers/virgl.html) ·
[virtio-gpu spec](https://docs.oasis-open.org/virtio/virtio/v1.1/virtio-v1.1.html) ·
[KVM Guest Drivers for Windows](https://github.com/virtio-win/kvm-guest-drivers-windows)

</details>
