$ErrorActionPreference = 'Continue'
Set-Location 'C:\Users\93343\Desktop\demo'
$c = Get-Content 'scripts\player.gd' -Encoding UTF8
$regions = @(@(798,812), @(1216,1226), @(1410,1422), @(1600,1612), @(1662,1678), @(3828,3842), @(3880,3892), @(3896,3912), @(3958,3970), @(3982,3992), @(4100,4115))
foreach ($r in $regions) {
    Write-Host ('===== ' + $r[0] + ' - ' + $r[1] + ' =====')
    for ($i = $r[0]; $i -le $r[1]; $i++) {
        Write-Host ($i.ToString() + ': ' + $c[$i-1])
    }
}
