# GPU present-load: a window that continuously resizes and repaints, driving
# present/compositing traffic through the viogpu3d driver (mimics the resize
# scenario that wedged the GPU). Runs ~65s then closes.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$f = New-Object System.Windows.Forms.Form
$f.Text = 'gpu-load'
$f.StartPosition = 'Manual'
$f.Location = New-Object System.Drawing.Point(40,40)
$f.TopMost = $true
$rnd = New-Object System.Random 777
$f.Add_Paint({
  param($s,$e)
  $e.Graphics.Clear([System.Drawing.Color]::FromArgb($rnd.Next(255),$rnd.Next(255),$rnd.Next(255)))
  for($i=0;$i -lt 40;$i++){
    $b = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($rnd.Next(255),$rnd.Next(255),$rnd.Next(255)))
    $e.Graphics.FillEllipse($b, $rnd.Next(600), $rnd.Next(400), 60, 60)
    $b.Dispose()
  }
})
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$t = New-Object System.Windows.Forms.Timer
$t.Interval = 12
$t.Add_Tick({
  if ($sw.ElapsedMilliseconds -gt 65000) { $t.Stop(); $f.Close(); return }
  $w = 400 + $rnd.Next(600); $h = 300 + $rnd.Next(450)
  $f.Size = New-Object System.Drawing.Size($w,$h)
  $f.Invalidate()
})
$t.Start()
[System.Windows.Forms.Application]::Run($f)
"present-load done $(Get-Date -Format o)" | Out-File C:\Tools\present.log
