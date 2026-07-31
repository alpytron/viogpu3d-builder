$dst='C:\Tools\dxvk'
New-Item -ItemType Directory $dst -Force | Out-Null
Copy-Item Y:\VMs\share\dxvk\d3d11.dll,Y:\VMs\share\dxvk\dxgi.dll $dst -Force -EA SilentlyContinue
$env:DXVK_LOG_LEVEL='info'; $env:DXVK_LOG_PATH=$dst
Remove-Item "$dst\*.log","$dst\result.txt" -EA SilentlyContinue
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class DXR {
 [DllImport("kernel32",SetLastError=true)] public static extern IntPtr LoadLibrary(string p);
 [DllImport("kernel32")] public static extern IntPtr GetProcAddress(IntPtr h,string n);
 [UnmanagedFunctionPointer(CallingConvention.StdCall)] public delegate int Fn(IntPtr a,int dt,IntPtr sw,uint fl,IntPtr pfl,uint nfl,uint sdk,out IntPtr dev,out int lvl,out IntPtr ctx);
 public static string Run(string dir){
  LoadLibrary("vulkan-1.dll"); LoadLibrary(dir+"\\dxgi.dll");
  IntPtr h=LoadLibrary(dir+"\\d3d11.dll"); IntPtr p=GetProcAddress(h,"D3D11CreateDevice");
  var fn=(Fn)Marshal.GetDelegateForFunctionPointer(p,typeof(Fn));
  IntPtr dev,ctx; int lvl; int hr=fn(IntPtr.Zero,1,IntPtr.Zero,0,IntPtr.Zero,0,7,out dev,out lvl,out ctx);
  return string.Format("hr=0x{0:X8} featureLevel=0x{1:X4} devicePtr=0x{2:X}",hr,lvl,dev.ToInt64());
 }
}
"@
$fl = @{ '0xB000'='11_0'; '0xB100'='11_1'; '0xC000'='12_0'; '0xC100'='12_1'; '0xA100'='10_1'; '0xA000'='10_0' }
$r=[DXR]::Run($dst)
$m=[regex]::Match($r,'featureLevel=(0x[0-9A-F]{4})')
$name = if($m.Success -and $fl.ContainsKey($m.Groups[1].Value)){ $fl[$m.Groups[1].Value] } else { 'unknown' }
Set-Content C:\Tools\dxvk\result.txt ("$r  => D3D_FEATURE_LEVEL_$name")
