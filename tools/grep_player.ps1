$ErrorActionPreference = 'Continue'
Set-Location 'C:\Users\93343\Desktop\demo'
Write-Host '=== residual reflection ==='
Select-String -Path 'scripts\player.gd' -Pattern '_fp_vm\.get\(|_fp_vm\._model|_fp_vm\.free\(\)' | ForEach-Object {
    '{0}: {1}' -f $_.LineNumber, $_.Line.Trim().Substring(0, [Math]::Min(90, $_.Line.Trim().Length)) }
