Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class Modes {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
    public ushort dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public uint dmFields;
    public int dmPositionX, dmPositionY; public uint dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
    public ushort dmLogPixels; public uint dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public uint dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern bool EnumDisplaySettingsA(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern int ChangeDisplaySettingsExA(string dev, ref DEVMODE dm, IntPtr h, uint f, IntPtr l);
  public static string Enumerate(){
    var sb=new StringBuilder(); DEVMODE dm=new DEVMODE(); dm.dmSize=(ushort)Marshal.SizeOf(typeof(DEVMODE));
    int i=0; long maxA=0; string maxS=""; int count=0; bool has4k=false;
    while(EnumDisplaySettingsA(null,i,ref dm)){ long a=(long)dm.dmPelsWidth*dm.dmPelsHeight; if(a>maxA){maxA=a;maxS=dm.dmPelsWidth+"x"+dm.dmPelsHeight;} if(dm.dmPelsWidth>=3840&&dm.dmPelsHeight>=2160)has4k=true; count++; i++; }
    sb.Append("modes="+count+" max="+maxS+" has3840x2160="+has4k);
    return sb.ToString();
  }
  public static string Set4K(){
    DEVMODE dm=new DEVMODE(); dm.dmSize=(ushort)Marshal.SizeOf(typeof(DEVMODE));
    EnumDisplaySettingsA(null,-1,ref dm);
    dm.dmPelsWidth=3840; dm.dmPelsHeight=2160; dm.dmBitsPerPel=32;
    dm.dmFields=0x80000u|0x100000u|0x40000u;
    int r=ChangeDisplaySettingsExA(null, ref dm, IntPtr.Zero, 0, IntPtr.Zero);
    return "CDS(3840x2160)="+r+" (0=OK,-2=BADMODE,-1=FAILED)";
  }
}
"@
$out = "ENUM: " + [Modes]::Enumerate()
$out += "`nSET:  " + [Modes]::Set4K()
Start-Sleep 4
$v = Get-CimInstance Win32_VideoController | Where-Object {$_.Name -match 'VirtIO'}
$d = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match 'VirtIO' } | Select-Object -First 1
$out += "`nAFTER: res=$($v.CurrentHorizontalResolution)x$($v.CurrentVerticalResolution) device=$($d.Status) prob=$($d.ProblemCode)"
$fb = [math]::Round($v.CurrentHorizontalResolution*$v.CurrentVerticalResolution*4/1MB,1)
$out += "  fb=${fb}MB"
Set-Content C:\Tools\dxvk\enum4k.txt $out
