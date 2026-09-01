$ErrorActionPreference = 'Continue'
Set-Location 'C:\Users\93343\Desktop\demo'
$git = 'C:\Program Files\Git\cmd\git.exe'

Write-Host '=== uncommitted changes ==='
$out = & $git status --porcelain=v1 2>&1
Write-Host ("count: " + ($out | Measure-Object).Count)
$out | Select-Object -First 30

Write-Host '=== grenade3p dir ==='
Get-ChildItem 'resources\animations\grenade3p' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $_.FullName.Replace('C:\Users\93343\Desktop\demo\', '') + ' (' + $_.Length + 'B)'
}

Write-Host '=== grenade mentions in calib scene/script ==='
Select-String -Path 'scenes\nepal_knife_calib.tscn' -Pattern 'grenade|gaobao|Knife|HandAnchor|character_id' | ForEach-Object {
    '{0}: {1}' -f $_.LineNumber, $_.Line.Trim().Substring(0, [Math]::Min(90, $_.Line.Trim().Length))
}
Select-String -Path 'tools\nepal_knife_calib_scene.gd' -Pattern 'grenade|gaobao|Knife|KNIFE_MODEL' | ForEach-Object {
    '{0}: {1}' -f $_.LineNumber, $_.Line.Trim().Substring(0, [Math]::Min(90, $_.Line.Trim().Length))
}
