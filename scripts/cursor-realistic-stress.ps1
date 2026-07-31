# Realistic combined stress: continuous position flood (fast mouse) + shape changes
# at ~20/sec (busy CAD UI / resize arrows) + (present-load runs alongside). Tests
# whether a real-world cursor-shape rate is safe on the shared control queue.
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class UR {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] public static extern IntPtr LoadCursor(IntPtr h,int id);
  [DllImport("user32.dll")] public static extern bool SetSystemCursor(IntPtr h,uint id);
  [DllImport("user32.dll")] public static extern IntPtr CopyIcon(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a,uint b,IntPtr c,uint d);
}
"@
$log='C:\Tools\realstress.log'; "start $(Get-Date -Format o)" | Out-File $log
$ids = 32512,32513,32514,32515,32516,32642,32643,32644,32645,32646,32648,32649,32650,32651
$curs = @{}; foreach($i in $ids){ $curs[$i] = [UR]::LoadCursor([IntPtr]::Zero,$i) }
$rand=555; $sw=[System.Diagnostics.Stopwatch]::StartNew(); $lastShape=0; $si=0; $moves=0; $shapes=0
while ($sw.ElapsedMilliseconds -lt 60000) {
  for ($k=0; $k -lt 80; $k++) {
    $rand = ($rand*1103515245+12345) -band 0x7fffffff
    [UR]::SetCursorPos(($rand%1900), (($rand -shr 8)%1000)) | Out-Null; $moves++
  }
  if (($sw.ElapsedMilliseconds - $lastShape) -ge 50) {   # ~20 shape changes/sec
    [UR]::SetSystemCursor([UR]::CopyIcon($curs[$ids[$si % $ids.Count]]), 32512) | Out-Null
    $si++; $shapes++; $lastShape = $sw.ElapsedMilliseconds
  }
}
[UR]::SystemParametersInfo(0x0057, 0, [IntPtr]::Zero, 0) | Out-Null
"done: moves=$moves shapes=$shapes elapsed=$($sw.ElapsedMilliseconds)ms $(Get-Date -Format o)" | Out-File $log -Append
